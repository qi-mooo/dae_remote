import Foundation

enum RPCClientError: LocalizedError {
    case invalidBaseURL
    case invalidResponse
    case transport(String)
    case rpcError(code: Int, message: String)
    case missingSession
    case parseError(String)

    var errorDescription: String? {
        switch self {
        case .invalidBaseURL:
            return "路由器地址无效。"
        case .invalidResponse:
            return "路由器返回了无效响应。"
        case let .transport(message):
            return "网络错误: \(message)"
        case let .rpcError(code, message):
            return "RPC 错误(\(code)): \(message)"
        case .missingSession:
            return "未登录，请先连接路由器。"
        case let .parseError(message):
            return "解析失败: \(message)"
        }
    }
}

final class InsecureTrustDelegate: NSObject, URLSessionDelegate {
    private let allowInsecureTLS: Bool
    private let allowedHost: String?

    init(allowInsecureTLS: Bool, allowedHost: String?) {
        self.allowInsecureTLS = allowInsecureTLS
        self.allowedHost = allowedHost
    }

    func urlSession(
        _ session: URLSession,
        didReceive challenge: URLAuthenticationChallenge,
        completionHandler: @escaping (URLSession.AuthChallengeDisposition, URLCredential?) -> Void
    ) {
        guard allowInsecureTLS else {
            completionHandler(.performDefaultHandling, nil)
            return
        }
        guard challenge.protectionSpace.authenticationMethod == NSURLAuthenticationMethodServerTrust,
              let trust = challenge.protectionSpace.serverTrust else {
            completionHandler(.performDefaultHandling, nil)
            return
        }
        if let allowedHost, challenge.protectionSpace.host != allowedHost {
            completionHandler(.cancelAuthenticationChallenge, nil)
            return
        }
        completionHandler(.useCredential, URLCredential(trust: trust))
    }
}

actor OpenWrtRPCClient {
    private let anonymousSession = "00000000000000000000000000000000"
    private var sessionToken: String?
    private var endpoint: URL?
    private var requestID = 1
    private var session: URLSession = .shared
    private var delegateRetainer: InsecureTrustDelegate?

    func connect(baseURL: URL, username: String, password: String, allowInsecureTLS: Bool) async throws {
        let normalized = Self.makeEndpoint(from: baseURL)
        endpoint = normalized
        requestID = 1
        sessionToken = nil
        let delegate = InsecureTrustDelegate(allowInsecureTLS: allowInsecureTLS, allowedHost: baseURL.host)
        delegateRetainer = delegate
        session = URLSession(configuration: .ephemeral, delegate: delegate, delegateQueue: nil)

        let loginResult = try await rawCall(
            sessionID: anonymousSession,
            object: "session",
            method: "login",
            payload: [
                "username": username,
                "password": password
            ]
        )
        guard let dict = loginResult as? [String: Any],
              let sid = dict["ubus_rpc_session"] as? String,
              sid.isEmpty == false else {
            throw RPCClientError.parseError("登录返回未包含 session")
        }
        sessionToken = sid
    }

    func disconnect() {
        sessionToken = nil
        endpoint = nil
        requestID = 1
    }

    func fetchStatus() async throws -> DAEStatus {
        async let rcState = readRCState()
        async let memory = readMemoryFromService()
        let state = try await rcState
        return DAEStatus(
            running: state.running,
            enabled: state.enabled,
            memory: try await memory,
            updatedAt: Date()
        )
    }

    func fetchSystemOverview() async throws -> OpenWrtOverview {
        let boardRaw = try await call(object: "system", method: "board", payload: [:])
        let infoRaw = try await call(object: "system", method: "info", payload: [:])

        guard let board = boardRaw as? [String: Any] else {
            throw RPCClientError.parseError("system.board 返回格式错误")
        }
        guard let info = infoRaw as? [String: Any] else {
            throw RPCClientError.parseError("system.info 返回格式错误")
        }

        let hostname = (board["hostname"] as? String)?.trimmingCharacters(in: .whitespacesAndNewlines)
        let model = (board["model"] as? String)?.trimmingCharacters(in: .whitespacesAndNewlines)
        let cpu = (board["system"] as? String)?.trimmingCharacters(in: .whitespacesAndNewlines)
            ?? (board["cpu_model"] as? String)?.trimmingCharacters(in: .whitespacesAndNewlines)
            ?? (board["cpu"] as? String)?.trimmingCharacters(in: .whitespacesAndNewlines)
        let kernel = (board["kernel"] as? String)?.trimmingCharacters(in: .whitespacesAndNewlines)
        let release = board["release"] as? [String: Any]
        let firmware = (release?["description"] as? String)
            ?? (release?["version"] as? String)
            ?? "--"

        let uptimeSeconds = Self.anyToInt(info["uptime"]) ?? 0
        let uptimeText = Self.formatDuration(seconds: uptimeSeconds)

        let loadArray = info["load"] as? [Any] ?? []
        let loadText = Self.formatLoad(loadArray: loadArray)

        let memory = info["memory"] as? [String: Any] ?? [:]
        let total = Self.anyToInt(memory["total"]) ?? 0
        let available = Self.anyToInt(memory["available"]) ?? (Self.anyToInt(memory["free"]) ?? 0)
        let used = max(total - available, 0)
        let memoryText: String
        if total > 0 {
            memoryText = "\(Self.formatBytes(used))/\(Self.formatBytes(total))"
        } else {
            memoryText = "--"
        }

        return OpenWrtOverview(
            hostname: hostname?.isEmpty == false ? hostname! : "--",
            model: model?.isEmpty == false ? model! : "--",
            cpu: cpu?.isEmpty == false ? cpu! : "--",
            kernel: kernel?.isEmpty == false ? kernel! : "--",
            firmware: firmware,
            uptime: uptimeText,
            load: loadText,
            memory: memoryText
        )
    }

    func setEnabled(_ enabled: Bool) async throws {
        _ = try await call(
            object: "uci",
            method: "set",
            payload: [
                "config": "dae",
                "section": "config",
                "values": [
                    "enabled": enabled ? "1" : "0"
                ]
            ]
        )
        _ = try await call(
            object: "uci",
            method: "commit",
            payload: [
                "config": "dae"
            ]
        )
    }

    func startService() async throws {
        try await rcInit(action: "start")
    }

    func stopService() async throws {
        try await rcInit(action: "stop")
    }

    func reloadService() async throws {
        // hot_reload is not accepted by ubus rc.init on many OpenWrt builds.
        try await rcInit(action: "reload")
    }

    func readConfig(section: DAEConfigSection) async throws -> String {
        let result = try await call(
            object: "file",
            method: "read",
            payload: [
                "path": section.path
            ]
        )
        guard let dict = result as? [String: Any],
              let text = dict["data"] as? String else {
            throw RPCClientError.parseError("读取 \(section.path) 失败")
        }
        return text
    }

    func writeConfig(section: DAEConfigSection, content: String) async throws {
        _ = try await call(
            object: "file",
            method: "write",
            payload: [
                "path": section.path,
                "data": content
            ]
        )
    }

    private func readEnabled() async throws -> Bool {
        let result = try await call(
            object: "uci",
            method: "get",
            payload: [
                "config": "dae",
                "section": "config",
                "option": "enabled"
            ]
        )
        guard let dict = result as? [String: Any] else {
            throw RPCClientError.parseError("uci.get 返回格式错误")
        }
        if let value = dict["value"] as? String {
            return value == "1"
        }
        if let values = dict["values"] as? [String: Any],
           let value = values["enabled"] as? String {
            return value == "1"
        }
        return false
    }

    private func readRCState() async throws -> (running: Bool, enabled: Bool) {
        let result = try await call(
            object: "rc",
            method: "list",
            payload: [:]
        )
        guard let dict = result as? [String: Any] else {
            throw RPCClientError.parseError("rc.list 返回格式错误")
        }
        guard let dae = dict["dae"] as? [String: Any] else {
            // dae may be absent when init script is missing; fallback to uci option only.
            let enabled = try await readEnabled()
            return (running: false, enabled: enabled)
        }
        let running = dae["running"] as? Bool ?? false
        let enabled: Bool
        if let rcEnabled = dae["enabled"] as? Bool {
            enabled = rcEnabled
        } else {
            enabled = try await readEnabled()
        }
        return (running: running, enabled: enabled)
    }

    private func readMemoryFromService() async throws -> String? {
        let result = try await call(
            object: "service",
            method: "list",
            payload: [:]
        )
        guard let dict = result as? [String: Any],
              let dae = dict["dae"] as? [String: Any],
              let instances = dae["instances"] as? [String: Any],
              let first = instances.values.first as? [String: Any],
              let pid = first["pid"] else {
            return nil
        }
        return "PID \(pid)"
    }

    private func rcInit(action: String) async throws {
        let result = try await call(
            object: "rc",
            method: "init",
            payload: [
                "name": "dae",
                "action": action
            ]
        )
        // For rc.init, success often returns {} via [0]. If payload contains code, validate it.
        if let dict = result as? [String: Any],
           let code = Self.anyToInt(dict["code"]),
           code != 0 {
            throw RPCClientError.rpcError(code: code, message: "rc.init \(action) failed")
        }
    }

    private func call(object: String, method: String, payload: [String: Any]) async throws -> Any {
        guard let sid = sessionToken else {
            throw RPCClientError.missingSession
        }
        return try await rawCall(sessionID: sid, object: object, method: method, payload: payload)
    }

    private func rawCall(sessionID: String, object: String, method: String, payload: [String: Any]) async throws -> Any {
        guard let endpoint else {
            throw RPCClientError.invalidBaseURL
        }
        let id = nextID()
        let body: [String: Any] = [
            "jsonrpc": "2.0",
            "id": id,
            "method": "call",
            "params": [sessionID, object, method, payload]
        ]

        let bodyData: Data
        do {
            bodyData = try JSONSerialization.data(withJSONObject: body)
        } catch {
            throw RPCClientError.parseError("请求序列化失败")
        }

        var request = URLRequest(url: endpoint)
        request.httpMethod = "POST"
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.httpBody = bodyData

        let responseData: Data
        let response: URLResponse
        do {
            (responseData, response) = try await session.data(for: request)
        } catch {
            throw RPCClientError.transport(error.localizedDescription)
        }

        guard let httpResponse = response as? HTTPURLResponse,
              (200 ... 299).contains(httpResponse.statusCode) else {
            throw RPCClientError.invalidResponse
        }

        guard let json = try JSONSerialization.jsonObject(with: responseData) as? [String: Any] else {
            throw RPCClientError.parseError("响应不是 JSON 对象")
        }

        if let error = json["error"] as? [String: Any] {
            let code = Self.anyToInt(error["code"]) ?? -1
            let message = error["message"] as? String ?? "unknown"
            throw RPCClientError.rpcError(code: code, message: message)
        }

        if let resultDict = json["result"] as? [String: Any] {
            return resultDict
        }

        guard let result = json["result"] as? [Any], result.isEmpty == false else {
            let keys = json.keys.sorted().joined(separator: ",")
            throw RPCClientError.parseError("缺少 result，响应字段: [\(keys)]")
        }

        let ubusCode = Self.anyToInt(result[0]) ?? -1
        if ubusCode != 0 {
            throw RPCClientError.rpcError(code: ubusCode, message: "ubus call failed")
        }
        // Some ubus methods (e.g. uci.commit) return only [0] without payload.
        if result.count == 1 {
            return [String: Any]()
        }
        return result[1]
    }

    private static func anyToInt(_ value: Any?) -> Int? {
        if let intValue = value as? Int {
            return intValue
        }
        if let number = value as? NSNumber {
            return number.intValue
        }
        if let text = value as? String {
            return Int(text)
        }
        return nil
    }

    private func nextID() -> Int {
        defer { requestID += 1 }
        return requestID
    }

    private static func formatDuration(seconds: Int) -> String {
        guard seconds > 0 else {
            return "--"
        }
        let days = seconds / 86_400
        let hours = (seconds % 86_400) / 3_600
        let minutes = (seconds % 3_600) / 60
        if days > 0 {
            return "\(days)d \(hours)h \(minutes)m"
        }
        if hours > 0 {
            return "\(hours)h \(minutes)m"
        }
        return "\(minutes)m"
    }

    private static func formatLoad(loadArray: [Any]) -> String {
        guard loadArray.count >= 3 else {
            return "--"
        }
        let values = loadArray.prefix(3).compactMap { anyToInt($0) }
        guard values.count == 3 else {
            return "--"
        }
        let normalized = values.map { Double($0) / 65_535.0 }
        return normalized.map { String(format: "%.2f", $0) }.joined(separator: " / ")
    }

    private static func formatBytes(_ bytes: Int) -> String {
        let mb = Double(bytes) / (1024.0 * 1024.0)
        if mb >= 1024 {
            return String(format: "%.1f GB", mb / 1024.0)
        }
        return String(format: "%.0f MB", mb)
    }

    private static func makeEndpoint(from baseURL: URL) -> URL {
        if baseURL.path.hasSuffix("/ubus") {
            return baseURL
        }
        if baseURL.path.isEmpty || baseURL.path == "/" {
            return baseURL.appendingPathComponent("ubus")
        }
        if baseURL.lastPathComponent == "cgi-bin" {
            return baseURL.appendingPathComponent("luci").appendingPathComponent("ubus")
        }
        return baseURL.appendingPathComponent("ubus")
    }
}
