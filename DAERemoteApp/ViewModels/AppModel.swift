import Foundation

@MainActor
final class AppModel: ObservableObject {
    @Published var routerAddress = ""
    @Published var username = "root"
    @Published var password = ""
    @Published var allowInsecureTLS = true

    @Published var isConnected = false
    @Published var isLoading = false
    @Published var errorMessage: String?
    @Published var noticeMessage: String?
    @Published var status: DAEStatus = .offline
    @Published var overview: OpenWrtOverview = .empty
    @Published var showConnectionAlert = false
    @Published var connectionAlertMessage = ""

    @Published var selectedSection: DAEConfigSection = .global
    @Published var configText = ""
    @Published var configDirty = false
    @Published var showingRawEditor = false

    @Published var editorTab: DAEEditorTab = .global
    @Published var globalOptions = DAEGlobalOptions()
    @Published var subscriptionEntries: [DAEEndpointEntry] = []
    @Published var nodeEntries: [DAEEndpointEntry] = []
    @Published var nodeGroups: [DAENodeGroup] = []
    @Published var routeRules: [DAERouteRule] = []
    @Published var routeFallbackGroup = ""

    private let rpcClient = OpenWrtRPCClient()
    private let defaults = UserDefaults.standard
    private var rawConfigCache: [DAEConfigSection: String] = [:]
    private var optionEditorLoaded = false
    private var reconnectInProgress = false
    private var manualDisconnected = false
    private let routeBuiltInOutbounds = ["direct", "block", "must_rules"]

    private enum DefaultsKey {
        static let routerAddress = "dae.remote.router_address"
        static let username = "dae.remote.username"
        static let password = "dae.remote.password"
        static let allowInsecureTLS = "dae.remote.allow_insecure_tls"
    }

    init() {
        routerAddress = defaults.string(forKey: DefaultsKey.routerAddress) ?? "http://10.0.0.1"
        username = defaults.string(forKey: DefaultsKey.username) ?? "root"
        password = defaults.string(forKey: DefaultsKey.password) ?? ""
        if defaults.object(forKey: DefaultsKey.allowInsecureTLS) != nil {
            allowInsecureTLS = defaults.bool(forKey: DefaultsKey.allowInsecureTLS)
        }
    }

    var nodeGroupNames: [String] {
        var set = Set<String>()
        var names: [String] = []
        for group in nodeGroups {
            let trimmed = group.name.trimmingCharacters(in: .whitespacesAndNewlines)
            guard trimmed.isEmpty == false, set.contains(trimmed) == false else {
                continue
            }
            set.insert(trimmed)
            names.append(trimmed)
        }
        return names
    }

    var routeOutboundChoices: [String] {
        var seen = Set<String>()
        var result: [String] = []

        for outbound in routeBuiltInOutbounds {
            let trimmed = outbound.trimmingCharacters(in: .whitespacesAndNewlines)
            guard trimmed.isEmpty == false, seen.contains(trimmed) == false else {
                continue
            }
            seen.insert(trimmed)
            result.append(trimmed)
        }

        for group in nodeGroupNames {
            let trimmed = group.trimmingCharacters(in: .whitespacesAndNewlines)
            guard trimmed.isEmpty == false, seen.contains(trimmed) == false else {
                continue
            }
            seen.insert(trimmed)
            result.append(trimmed)
        }
        return result
    }

    func connect() {
        Task { @MainActor in
            await connectAsync()
        }
    }

    func disconnect() {
        Task { @MainActor in
            manualDisconnected = true
            await rpcClient.disconnect()
            isConnected = false
            isLoading = false
            status = .offline
            overview = .empty
            errorMessage = nil
            optionEditorLoaded = false
            rawConfigCache.removeAll()
            configText = ""
            configDirty = false
            noticeMessage = "已断开连接"
        }
    }

    func refreshStatus() {
        Task { @MainActor in
            await refreshStatusAsync(showLoading: true)
        }
    }

    func refreshStatusSilently() {
        Task { @MainActor in
            await refreshStatusAsync(showLoading: false)
        }
    }

    func toggleEnabled() {
        Task { @MainActor in
            await setEnabledAsync(status.enabled == false)
        }
    }

    func switchService(_ shouldStart: Bool) {
        Task { @MainActor in
            await switchServiceAsync(shouldStart: shouldStart)
        }
    }

    func hotReload() {
        Task { @MainActor in
            await hotReloadAsync()
        }
    }

    func ensureOptionEditorLoaded() {
        guard optionEditorLoaded == false else {
            return
        }
        loadOptionEditor()
    }

    func loadOptionEditor() {
        Task { @MainActor in
            await loadOptionEditorAsync()
        }
    }

    func saveOptionEditor() {
        Task { @MainActor in
            await saveOptionEditorAsync()
        }
    }

    func addNodeGroup() {
        let index = nodeGroups.count + 1
        let suggested = "group\(index)"
        addNodeGroup(name: suggested, policy: .minMovingAvg, filter: "")
    }

    func addNodeGroup(name: String, policy: DAEGroupPolicy, filter: String) {
        let trimmedName = name.trimmingCharacters(in: .whitespacesAndNewlines)
        let finalName: String
        if trimmedName.isEmpty {
            finalName = "group\(nodeGroups.count + 1)"
        } else {
            finalName = trimmedName
        }
        nodeGroups.append(
            DAENodeGroup(
                name: finalName,
                policy: policy,
                filter: filter
            )
        )
        if routeFallbackGroup.isEmpty {
            routeFallbackGroup = finalName
        }
        validateRouteReferences()
    }

    func addSubscriptionEntry() {
        addSubscriptionEntry(name: "", value: "https://", enabled: true)
    }

    func addSubscriptionEntry(name: String, value: String, enabled: Bool = true) {
        let trimmedValue = value.trimmingCharacters(in: .whitespacesAndNewlines)
        guard trimmedValue.isEmpty == false else {
            return
        }
        subscriptionEntries.append(
            DAEEndpointEntry(
                name: name.trimmingCharacters(in: .whitespacesAndNewlines),
                value: trimmedValue,
                enabled: enabled
            )
        )
    }

    func removeSubscriptionEntry(_ id: UUID) {
        subscriptionEntries.removeAll { $0.id == id }
    }

    func addNodeEntry() {
        addNodeEntry(name: "", value: "socks5://", enabled: true)
    }

    func addNodeEntry(name: String, value: String, enabled: Bool = true) {
        let trimmedValue = value.trimmingCharacters(in: .whitespacesAndNewlines)
        guard trimmedValue.isEmpty == false else {
            return
        }
        nodeEntries.append(
            DAEEndpointEntry(
                name: name.trimmingCharacters(in: .whitespacesAndNewlines),
                value: trimmedValue,
                enabled: enabled
            )
        )
    }

    func removeNodeEntry(_ id: UUID) {
        nodeEntries.removeAll { $0.id == id }
    }

    func removeNodeGroup(_ id: UUID) {
        nodeGroups.removeAll { $0.id == id }
        if nodeGroups.isEmpty {
            routeFallbackGroup = ""
        }
        validateRouteReferences()
    }

    func addRouteRule() {
        let defaultOutbound: String
        let fallback = routeFallbackGroup.trimmingCharacters(in: .whitespacesAndNewlines)
        if fallback.isEmpty == false {
            defaultOutbound = fallback
        } else {
            defaultOutbound = routeOutboundChoices.first ?? ""
        }
        routeRules.append(DAERouteRule(matcher: "", outbound: defaultOutbound))
        validateRouteReferences()
    }

    func addRouteRule(matcher: String, outbound: String, enabled: Bool = true) {
        let trimmedMatcher = matcher.trimmingCharacters(in: .whitespacesAndNewlines)
        let trimmedOutbound = outbound.trimmingCharacters(in: .whitespacesAndNewlines)
        guard trimmedMatcher.isEmpty == false, trimmedOutbound.isEmpty == false else {
            return
        }
        routeRules.append(DAERouteRule(matcher: trimmedMatcher, outbound: trimmedOutbound, enabled: enabled))
        validateRouteReferences()
    }

    func removeRouteRule(_ id: UUID) {
        routeRules.removeAll { $0.id == id }
    }

    func loadConfig() {
        let section = selectedSection
        Task { @MainActor in
            await loadConfigAsync(section: section)
        }
    }

    func markConfigDirty() {
        if let cached = rawConfigCache[selectedSection] {
            configDirty = (cached != configText)
        } else {
            configDirty = true
        }
    }

    func saveConfig() {
        let section = selectedSection
        let content = configText
        Task { @MainActor in
            await saveConfigAsync(section: section, content: content)
        }
    }

    func openRawEditor() {
        showingRawEditor = true
        if configText.isEmpty {
            loadConfig()
        }
    }

    private func connectAsync() async {
        guard isLoading == false else {
            return
        }
        manualDisconnected = false
        let addressText = routerAddress.trimmingCharacters(in: .whitespacesAndNewlines)
        let userText = username.trimmingCharacters(in: .whitespacesAndNewlines)
        guard addressText.isEmpty == false, userText.isEmpty == false, password.isEmpty == false else {
            errorMessage = "请输入路由器地址、用户名和密码。"
            return
        }
        guard let baseURL = normalizedBaseURL(from: addressText) else {
            errorMessage = RPCClientError.invalidBaseURL.localizedDescription
            return
        }

        isLoading = true
        errorMessage = nil
        do {
            try await rpcClient.connect(
                baseURL: baseURL,
                username: userText,
                password: password,
                allowInsecureTLS: allowInsecureTLS
            )
            isConnected = true
            saveLoginInfo()
            noticeMessage = "登录成功"
            optionEditorLoaded = false
            rawConfigCache.removeAll()

            await refreshStatusAsync(showLoading: false, allowReconnect: false)
            await loadOptionEditorAsync(showLoading: false, allowReconnect: false)
            if configText.isEmpty {
                await loadConfigAsync(section: selectedSection, showLoading: false)
            }
        } catch {
            isConnected = false
            await handleInitialConnectFailure(error)
        }
        isLoading = false
    }

    private func refreshStatusAsync(showLoading: Bool, allowReconnect: Bool = true) async {
        guard isConnected else {
            return
        }
        if showLoading {
            isLoading = true
        }
        errorMessage = nil
        do {
            async let statusTask = rpcClient.fetchStatus()
            async let overviewTask = rpcClient.fetchSystemOverview()
            status = try await statusTask
            overview = try await overviewTask
        } catch {
            await handleOperationError(error, allowReconnect: allowReconnect)
        }
        if showLoading {
            isLoading = false
        }
    }

    private func setEnabledAsync(_ enabled: Bool) async {
        guard isConnected, isLoading == false else {
            return
        }
        isLoading = true
        errorMessage = nil
        do {
            try await rpcClient.setEnabled(enabled)
            if enabled {
                try await rpcClient.startService()
            } else {
                try await rpcClient.stopService()
            }
            await refreshStatusAsync(showLoading: false, allowReconnect: false)
            noticeMessage = enabled ? "已启用并启动 dae" : "已禁用并停止 dae"
        } catch {
            await handleOperationError(error)
        }
        isLoading = false
    }

    private func switchServiceAsync(shouldStart: Bool) async {
        guard isConnected, isLoading == false else {
            return
        }
        isLoading = true
        errorMessage = nil
        do {
            if shouldStart {
                try await rpcClient.startService()
            } else {
                try await rpcClient.stopService()
            }
            await refreshStatusAsync(showLoading: false, allowReconnect: false)
        } catch {
            await handleOperationError(error)
        }
        isLoading = false
    }

    private func hotReloadAsync() async {
        guard isConnected, isLoading == false else {
            return
        }
        isLoading = true
        errorMessage = nil
        do {
            try await rpcClient.reloadService()
            await refreshStatusAsync(showLoading: false, allowReconnect: false)
            noticeMessage = "配置已重载"
        } catch {
            await handleOperationError(error)
        }
        isLoading = false
    }

    private func loadConfigAsync(section: DAEConfigSection, showLoading: Bool = true) async {
        guard isConnected else {
            return
        }
        if showLoading {
            isLoading = true
        }
        errorMessage = nil
        do {
            let text = try await rpcClient.readConfig(section: section)
            rawConfigCache[section] = text
            if selectedSection == section {
                configText = text
                configDirty = false
            }
        } catch {
            await handleOperationError(error)
        }
        if showLoading {
            isLoading = false
        }
    }

    private func saveConfigAsync(section: DAEConfigSection, content: String) async {
        guard isConnected, isLoading == false else {
            return
        }
        isLoading = true
        errorMessage = nil
        do {
            try await rpcClient.writeConfig(section: section, content: content)
            rawConfigCache[section] = content
            if selectedSection == section {
                configText = content
                configDirty = false
            }
            try? await rpcClient.reloadService()
            await refreshStatusAsync(showLoading: false, allowReconnect: false)

            if section == .global || section == .node || section == .route {
                await loadOptionEditorAsync(showLoading: false, allowReconnect: false)
            }
            noticeMessage = "已保存 \(section.title)"
        } catch {
            await handleOperationError(error)
        }
        isLoading = false
    }

    private func loadOptionEditorAsync(showLoading: Bool = true, allowReconnect: Bool = true) async {
        guard isConnected else {
            return
        }
        if showLoading {
            isLoading = true
        }
        errorMessage = nil
        do {
            async let globalTextTask = rpcClient.readConfig(section: .global)
            async let nodeTextTask = rpcClient.readConfig(section: .node)
            async let routeTextTask = rpcClient.readConfig(section: .route)

            let globalText = try await globalTextTask
            let nodeText = try await nodeTextTask
            let routeText = try await routeTextTask

            rawConfigCache[.global] = globalText
            rawConfigCache[.node] = nodeText
            rawConfigCache[.route] = routeText

            globalOptions = parseGlobalOptions(from: globalText)
            subscriptionEntries = parseEndpointEntries(blockName: "subscription", from: nodeText)
            nodeEntries = parseEndpointEntries(blockName: "node", from: nodeText)
            nodeGroups = parseNodeGroups(from: nodeText)
            if nodeGroups.isEmpty {
                nodeGroups = [DAENodeGroup(name: "my_group", policy: .minMovingAvg, filter: "")]
            }

            let routing = parseRouting(from: routeText)
            routeRules = routing.rules
            routeFallbackGroup = routing.fallback
            validateRouteReferences()
            optionEditorLoaded = true
        } catch {
            await handleOperationError(error, allowReconnect: allowReconnect)
        }
        if showLoading {
            isLoading = false
        }
    }

    private func saveOptionEditorAsync() async {
        guard isConnected, isLoading == false else {
            return
        }
        isLoading = true
        errorMessage = nil

        do {
            normalizeNodeGroupsBeforeSave()
            validateRouteReferences()

            async let globalCurrentTask = rpcClient.readConfig(section: .global)
            async let nodeCurrentTask = rpcClient.readConfig(section: .node)
            async let routeCurrentTask = rpcClient.readConfig(section: .route)

            let globalCurrent = try await globalCurrentTask
            let nodeCurrent = try await nodeCurrentTask
            let routeCurrent = try await routeCurrentTask

            let newGlobalBlock = renderGlobalBlock(globalOptions)
            let newSubscriptionBlock = renderEndpointBlock(name: "subscription", entries: subscriptionEntries)
            let newNodePoolBlock = renderEndpointBlock(name: "node", entries: nodeEntries)
            let newNodeBlock = renderGroupBlock(nodeGroups)
            let newRouteBlock = renderRoutingBlock(rules: routeRules, fallback: routeFallbackGroup)

            let globalUpdated = replacingTopLevelBlock(
                named: "global",
                with: newGlobalBlock,
                in: globalCurrent
            )
            var nodeUpdated = replacingTopLevelBlock(
                named: "subscription",
                with: newSubscriptionBlock,
                in: nodeCurrent
            )
            nodeUpdated = replacingTopLevelBlock(
                named: "node",
                with: newNodePoolBlock,
                in: nodeUpdated
            )
            nodeUpdated = replacingTopLevelBlock(
                named: "group",
                with: newNodeBlock,
                in: nodeUpdated
            )
            let routeUpdated = replacingTopLevelBlock(
                named: "routing",
                with: newRouteBlock,
                in: routeCurrent
            )

            try await rpcClient.writeConfig(section: .global, content: globalUpdated)
            try await rpcClient.writeConfig(section: .node, content: nodeUpdated)
            try await rpcClient.writeConfig(section: .route, content: routeUpdated)
            try? await rpcClient.reloadService()

            rawConfigCache[.global] = globalUpdated
            rawConfigCache[.node] = nodeUpdated
            rawConfigCache[.route] = routeUpdated
            if let selected = rawConfigCache[selectedSection] {
                configText = selected
                configDirty = false
            }

            await refreshStatusAsync(showLoading: false, allowReconnect: false)
            optionEditorLoaded = true
            noticeMessage = "选项已保存并重载"
        } catch {
            await handleOperationError(error)
        }
        isLoading = false
    }

    private func normalizeNodeGroupsBeforeSave() {
        var seen = Set<String>()
        var normalized: [DAENodeGroup] = []

        for (index, item) in nodeGroups.enumerated() {
            var name = sanitizeGroupName(item.name)
            if name.isEmpty {
                name = "group\(index + 1)"
            }
            if seen.contains(name) {
                var suffix = 2
                var candidate = "\(name)_\(suffix)"
                while seen.contains(candidate) {
                    suffix += 1
                    candidate = "\(name)_\(suffix)"
                }
                name = candidate
            }
            seen.insert(name)

            normalized.append(
                DAENodeGroup(
                    id: item.id,
                    name: name,
                    policy: item.policy,
                    filter: item.filter
                )
            )
        }

        nodeGroups = normalized
    }

    private func validateRouteReferences() {
        let choices = routeOutboundChoices
        let choiceSet = Set(choices)
        let currentFallback = routeFallbackGroup.trimmingCharacters(in: .whitespacesAndNewlines)
        if currentFallback.isEmpty {
            routeFallbackGroup = choices.first ?? ""
        } else if choiceSet.contains(currentFallback) == false {
            routeFallbackGroup = choices.first ?? ""
        } else {
            routeFallbackGroup = currentFallback
        }

        let fallback = routeFallbackGroup.trimmingCharacters(in: .whitespacesAndNewlines)
        routeRules = routeRules.map { rule in
            var updated = rule
            let outbound = updated.outbound.trimmingCharacters(in: .whitespacesAndNewlines)
            if choiceSet.contains(outbound) {
                updated.outbound = outbound
            } else {
                updated.outbound = fallback
            }
            return updated
        }
    }

    private func handleInitialConnectFailure(_ error: Error) async {
        errorMessage = toErrorText(error)
        connectionAlertMessage = errorMessage ?? "连接失败"
        showConnectionAlert = true
    }

    private func handleOperationError(_ error: Error, allowReconnect: Bool = true) async {
        errorMessage = toErrorText(error)
        guard allowReconnect, shouldReconnect(for: error), manualDisconnected == false else {
            return
        }
        let success = await attemptAutoReconnect()
        if success == false {
            connectionAlertMessage = "连接中断且自动重连失败，请检查 OpenWrt。"
            showConnectionAlert = true
        }
    }

    private func shouldReconnect(for error: Error) -> Bool {
        guard let rpcError = error as? RPCClientError else {
            return false
        }
        switch rpcError {
        case .transport, .invalidResponse, .missingSession:
            return true
        case let .rpcError(code, _):
            return code == -32002 || code == -32001
        case .invalidBaseURL, .parseError:
            return false
        }
    }

    private func attemptAutoReconnect() async -> Bool {
        guard reconnectInProgress == false else {
            return false
        }
        guard let baseURL = normalizedBaseURL(from: routerAddress),
              username.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty == false,
              password.isEmpty == false else {
            return false
        }

        reconnectInProgress = true
        defer { reconnectInProgress = false }
        await rpcClient.disconnect()

        for attempt in 1 ... 3 {
            do {
                try await rpcClient.connect(
                    baseURL: baseURL,
                    username: username.trimmingCharacters(in: .whitespacesAndNewlines),
                    password: password,
                    allowInsecureTLS: allowInsecureTLS
                )
                isConnected = true
                errorMessage = nil
                noticeMessage = "已自动重连"
                await refreshStatusAsync(showLoading: false, allowReconnect: false)
                await loadOptionEditorAsync(showLoading: false, allowReconnect: false)
                return true
            } catch {
                if attempt < 3 {
                    try? await Task.sleep(for: .seconds(2))
                }
            }
        }

        await rpcClient.disconnect()
        isConnected = false
        overview = .empty
        return false
    }

    private func saveLoginInfo() {
        defaults.set(routerAddress, forKey: DefaultsKey.routerAddress)
        defaults.set(username, forKey: DefaultsKey.username)
        defaults.set(password, forKey: DefaultsKey.password)
        defaults.set(allowInsecureTLS, forKey: DefaultsKey.allowInsecureTLS)
    }

    private func normalizedBaseURL(from text: String) -> URL? {
        let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard trimmed.isEmpty == false else {
            return nil
        }
        if trimmed.contains("://") {
            return URL(string: trimmed)
        }
        return URL(string: "http://\(trimmed)")
    }

    private func toErrorText(_ error: Error) -> String {
        if let localized = error as? LocalizedError,
           let text = localized.errorDescription,
           text.isEmpty == false {
            return text
        }
        return error.localizedDescription
    }
}

private extension AppModel {
    struct TopLevelBlock {
        let name: String
        let range: Range<String.Index>
        let bodyRange: Range<String.Index>
    }

    func parseTopLevelBlocks(in text: String) -> [TopLevelBlock] {
        var blocks: [TopLevelBlock] = []
        var index = text.startIndex

        while index < text.endIndex {
            skipWhitespaceAndComments(in: text, index: &index)
            guard index < text.endIndex else {
                break
            }

            let nameStart = index
            while index < text.endIndex, isIdentifierChar(text[index]) {
                index = text.index(after: index)
            }

            guard nameStart < index else {
                index = text.index(after: index)
                continue
            }

            let name = String(text[nameStart ..< index])
            skipWhitespace(in: text, index: &index)
            guard index < text.endIndex else {
                break
            }

            guard text[index] == "{" else {
                moveToNextLine(in: text, index: &index)
                continue
            }

            let openBrace = index
            guard let closeBrace = findMatchingBrace(in: text, from: openBrace) else {
                break
            }
            let afterClose = text.index(after: closeBrace)
            let bodyStart = text.index(after: openBrace)

            blocks.append(
                TopLevelBlock(
                    name: name,
                    range: nameStart ..< afterClose,
                    bodyRange: bodyStart ..< closeBrace
                )
            )
            index = afterClose
        }

        return blocks
    }

    func extractTopLevelBlock(named name: String, in text: String) -> String? {
        parseTopLevelBlocks(in: text)
            .first { $0.name == name }
            .map { String(text[$0.bodyRange]) }
    }

    func replacingTopLevelBlock(named name: String, with blockText: String, in text: String) -> String {
        let trimmedBlock = blockText.trimmingCharacters(in: .whitespacesAndNewlines)
        if let block = parseTopLevelBlocks(in: text).first(where: { $0.name == name }) {
            var updated = text
            updated.replaceSubrange(block.range, with: trimmedBlock)
            return updated
        }

        var updated = text
        if updated.hasSuffix("\n") == false {
            updated.append("\n")
        }
        if updated.isEmpty == false {
            updated.append("\n")
        }
        updated.append(trimmedBlock)
        updated.append("\n")
        return updated
    }

    func findMatchingBrace(in text: String, from openBrace: String.Index) -> String.Index? {
        var depth = 0
        var inSingleQuote = false
        var inDoubleQuote = false
        var index = openBrace

        while index < text.endIndex {
            let ch = text[index]
            if ch == "'" && inDoubleQuote == false {
                inSingleQuote.toggle()
                index = text.index(after: index)
                continue
            }
            if ch == "\"" && inSingleQuote == false {
                inDoubleQuote.toggle()
                index = text.index(after: index)
                continue
            }
            if inSingleQuote == false, inDoubleQuote == false, ch == "#" {
                moveToNextLine(in: text, index: &index)
                continue
            }
            if inSingleQuote == false, inDoubleQuote == false {
                if ch == "{" {
                    depth += 1
                } else if ch == "}" {
                    depth -= 1
                    if depth == 0 {
                        return index
                    }
                }
            }
            index = text.index(after: index)
        }
        return nil
    }

    func skipWhitespaceAndComments(in text: String, index: inout String.Index) {
        while index < text.endIndex {
            let ch = text[index]
            if ch.isWhitespace {
                index = text.index(after: index)
                continue
            }
            if ch == "#" {
                moveToNextLine(in: text, index: &index)
                continue
            }
            break
        }
    }

    func skipWhitespace(in text: String, index: inout String.Index) {
        while index < text.endIndex, text[index].isWhitespace {
            index = text.index(after: index)
        }
    }

    func moveToNextLine(in text: String, index: inout String.Index) {
        while index < text.endIndex, text[index] != "\n" {
            index = text.index(after: index)
        }
        if index < text.endIndex {
            index = text.index(after: index)
        }
    }

    func isIdentifierChar(_ ch: Character) -> Bool {
        if ch.isWhitespace {
            return false
        }
        switch ch {
        case "{", "}", ":", "#", "\"", "'":
            return false
        default:
            return true
        }
    }

    func parseGlobalOptions(from text: String) -> DAEGlobalOptions {
        let body = extractTopLevelBlock(named: "global", in: text) ?? text
        var options = DAEGlobalOptions()

        for rawLine in body.split(separator: "\n", omittingEmptySubsequences: false) {
            let cleaned = trimLineComment(String(rawLine)).trimmingCharacters(in: .whitespacesAndNewlines)
            guard cleaned.isEmpty == false, let (key, value) = parseKeyValueLine(cleaned) else {
                continue
            }

            switch key {
            case "tproxy_port":
                options.tproxyPort = unquote(value)
            case "tproxy_port_protect":
                options.tproxyPortProtect = parseBool(value, fallback: options.tproxyPortProtect)
            case "pprof_port":
                options.pprofPort = unquote(value)
            case "so_mark_from_dae":
                options.soMarkFromDae = unquote(value)
            case "log_level":
                if let v = DAELogLevel(rawValue: unquote(value)) {
                    options.logLevel = v
                }
            case "disable_waiting_network":
                options.disableWaitingNetwork = parseBool(value, fallback: options.disableWaitingNetwork)
            case "wan_interface":
                options.wanInterface = unquote(value)
            case "auto_config_kernel_parameter":
                options.autoConfigKernelParameter = parseBool(value, fallback: options.autoConfigKernelParameter)
            case "tcp_check_url":
                options.tcpCheckURL = unquote(value)
            case "tcp_check_http_method":
                options.tcpCheckHTTPMethod = unquote(value)
            case "udp_check_dns":
                options.udpCheckDNS = unquote(value)
            case "check_interval":
                options.checkInterval = unquote(value)
            case "check_tolerance":
                options.checkTolerance = unquote(value)
            case "dial_mode":
                if let v = DAEDialMode(rawValue: unquote(value)) {
                    options.dialMode = v
                }
            case "allow_insecure":
                options.allowInsecure = parseBool(value, fallback: options.allowInsecure)
            case "sniffing_timeout":
                options.sniffingTimeout = unquote(value)
            case "tls_implementation":
                if let v = DAETlsImplementation(rawValue: unquote(value)) {
                    options.tlsImplementation = v
                }
            case "utls_imitate":
                options.utlsImitate = unquote(value)
            case "tls_fragment":
                options.tlsFragment = parseBool(value, fallback: options.tlsFragment)
            case "tls_fragment_length":
                options.tlsFragmentLength = unquote(value)
            case "tls_fragment_interval":
                options.tlsFragmentInterval = unquote(value)
            case "mptcp":
                options.mptcp = parseBool(value, fallback: options.mptcp)
            case "bandwidth_max_tx":
                options.bandwidthMaxTx = unquote(value)
            case "bandwidth_max_rx":
                options.bandwidthMaxRx = unquote(value)
            case "fallback_resolver":
                options.fallbackResolver = unquote(value)
            default:
                continue
            }
        }

        return options
    }

    func parseEndpointEntries(blockName: String, from text: String) -> [DAEEndpointEntry] {
        guard let body = extractTopLevelBlock(named: blockName, in: text) else {
            return []
        }

        var entries: [DAEEndpointEntry] = []
        for rawLine in body.split(separator: "\n", omittingEmptySubsequences: false) {
            var line = String(rawLine)
            if line.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                continue
            }

            var enabled = true
            if let uncommented = stripLeadingCommentMarker(line) {
                enabled = false
                line = uncommented
            }

            line = trimLineComment(line).trimmingCharacters(in: .whitespacesAndNewlines)
            if line.isEmpty {
                continue
            }

            if let (key, value) = parseKeyValueLine(line) {
                let trimmedValue = value.trimmingCharacters(in: .whitespacesAndNewlines)
                if trimmedValue.hasPrefix("'") || trimmedValue.hasPrefix("\"") {
                    let name = key.trimmingCharacters(in: .whitespacesAndNewlines)
                    let link = unquote(value)
                    entries.append(
                        DAEEndpointEntry(
                            name: name,
                            value: link,
                            enabled: enabled
                        )
                    )
                } else {
                    entries.append(
                        DAEEndpointEntry(
                            name: "",
                            value: unquote(line),
                            enabled: enabled
                        )
                    )
                }
            } else {
                entries.append(
                    DAEEndpointEntry(
                        name: "",
                        value: unquote(line),
                        enabled: enabled
                    )
                )
            }
        }
        return entries
    }

    func parseNodeGroups(from text: String) -> [DAENodeGroup] {
        let body = extractTopLevelBlock(named: "group", in: text) ?? text
        let groupBlocks = parseTopLevelBlocks(in: body)
        guard groupBlocks.isEmpty == false else {
            return []
        }

        var groups: [DAENodeGroup] = []
        for block in groupBlocks {
            let content = String(body[block.bodyRange])
            var policy: DAEGroupPolicy = .minMovingAvg
            var filters: [String] = []

            for rawLine in content.split(separator: "\n", omittingEmptySubsequences: false) {
                let cleaned = trimLineComment(String(rawLine)).trimmingCharacters(in: .whitespacesAndNewlines)
                guard cleaned.isEmpty == false, let (key, value) = parseKeyValueLine(cleaned) else {
                    continue
                }
                if key == "policy", let parsed = DAEGroupPolicy(rawValue: unquote(value)) {
                    policy = parsed
                } else if key == "filter" {
                    filters.append(unquote(value))
                }
            }

            groups.append(
                DAENodeGroup(
                    name: block.name,
                    policy: policy,
                    filter: filters.joined(separator: "\n")
                )
            )
        }

        return groups
    }

    func parseRouting(from text: String) -> (rules: [DAERouteRule], fallback: String) {
        let body = extractTopLevelBlock(named: "routing", in: text) ?? text
        let lines = body.split(separator: "\n", omittingEmptySubsequences: false)
        var rules: [DAERouteRule] = []
        var fallback = ""
        var depth = 0

        for rawLine in lines {
            var line = String(rawLine)
            var enabled = true
            if let uncommented = stripLeadingCommentMarker(line) {
                enabled = false
                line = uncommented
            }

            line = trimLineComment(line).trimmingCharacters(in: .whitespacesAndNewlines)
            guard line.isEmpty == false else {
                continue
            }

            let openCount = line.filter { $0 == "{" }.count
            let closeCount = line.filter { $0 == "}" }.count

            if openCount > 0 {
                depth += openCount
            }
            if depth > 0 {
                if closeCount > 0 {
                    depth -= closeCount
                    if depth < 0 {
                        depth = 0
                    }
                }
                continue
            }

            if line.hasPrefix("fallback:"), let colon = line.firstIndex(of: ":") {
                guard enabled else {
                    continue
                }
                let value = line[line.index(after: colon)...]
                fallback = unquote(String(value).trimmingCharacters(in: .whitespacesAndNewlines))
                continue
            }

            guard let arrowRange = line.range(of: "->") else {
                continue
            }
            let matcher = String(line[..<arrowRange.lowerBound]).trimmingCharacters(in: .whitespacesAndNewlines)
            let outbound = String(line[arrowRange.upperBound...]).trimmingCharacters(in: .whitespacesAndNewlines)

            if matcher.isEmpty == false, outbound.isEmpty == false {
                rules.append(
                    DAERouteRule(
                        matcher: matcher,
                        outbound: unquote(outbound),
                        enabled: enabled
                    )
                )
            }
        }

        return (rules, fallback)
    }

    func renderGlobalBlock(_ options: DAEGlobalOptions) -> String {
        """
        global {
            tproxy_port: \(valueOrFallback(options.tproxyPort, "12345"))
            tproxy_port_protect: \(renderBool(options.tproxyPortProtect))
            pprof_port: \(valueOrFallback(options.pprofPort, "0"))
            so_mark_from_dae: \(valueOrFallback(options.soMarkFromDae, "0"))
            log_level: \(options.logLevel.rawValue)
            disable_waiting_network: \(renderBool(options.disableWaitingNetwork))
            wan_interface: \(valueOrFallback(options.wanInterface, "auto"))
            auto_config_kernel_parameter: \(renderBool(options.autoConfigKernelParameter))

            tcp_check_url: \(singleQuoted(valueOrFallback(options.tcpCheckURL, "http://cp.cloudflare.com,1.1.1.1,2606:4700:4700::1111")))
            tcp_check_http_method: \(valueOrFallback(options.tcpCheckHTTPMethod, "HEAD"))
            udp_check_dns: \(singleQuoted(valueOrFallback(options.udpCheckDNS, "dns.google:53,8.8.8.8,2001:4860:4860::8888")))
            check_interval: \(valueOrFallback(options.checkInterval, "30s"))
            check_tolerance: \(valueOrFallback(options.checkTolerance, "50ms"))

            dial_mode: \(options.dialMode.rawValue)
            allow_insecure: \(renderBool(options.allowInsecure))
            sniffing_timeout: \(valueOrFallback(options.sniffingTimeout, "100ms"))
            tls_implementation: \(options.tlsImplementation.rawValue)
            utls_imitate: \(valueOrFallback(options.utlsImitate, "chrome_auto"))
            tls_fragment: \(renderBool(options.tlsFragment))
            tls_fragment_length: \(singleQuoted(valueOrFallback(options.tlsFragmentLength, "50-100")))
            tls_fragment_interval: \(singleQuoted(valueOrFallback(options.tlsFragmentInterval, "10-20")))
            mptcp: \(renderBool(options.mptcp))
            bandwidth_max_tx: \(singleQuoted(valueOrFallback(options.bandwidthMaxTx, "200 mbps")))
            bandwidth_max_rx: \(singleQuoted(valueOrFallback(options.bandwidthMaxRx, "1 gbps")))
            fallback_resolver: \(singleQuoted(valueOrFallback(options.fallbackResolver, "8.8.8.8:53")))
        }
        """
    }

    func renderEndpointBlock(name: String, entries: [DAEEndpointEntry]) -> String {
        var lines: [String] = ["\(name) {"]
        for entry in entries {
            let renderedValue = singleQuoted(valueOrFallback(entry.value, ""))
            let trimmedName = sanitizeEntryTag(entry.name)
            let rule: String
            if trimmedName.isEmpty {
                rule = renderedValue
            } else {
                rule = "\(trimmedName): \(renderedValue)"
            }
            if entry.enabled {
                lines.append("    \(rule)")
            } else {
                lines.append("    # \(rule)")
            }
        }
        lines.append("}")
        return lines.joined(separator: "\n")
    }

    func renderGroupBlock(_ groups: [DAENodeGroup]) -> String {
        var lines: [String] = ["group {"]
        for group in groups {
            let name = sanitizeGroupName(group.name)
            guard name.isEmpty == false else {
                continue
            }
            lines.append("    \(name) {")
            let filterLines = group.filter
                .split(separator: "\n", omittingEmptySubsequences: false)
                .map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
                .filter { $0.isEmpty == false }
            for filterLine in filterLines {
                lines.append("        filter: \(filterLine)")
            }
            lines.append("        policy: \(group.policy.rawValue)")
            lines.append("    }")
            lines.append("")
        }
        if lines.last == "" {
            lines.removeLast()
        }
        lines.append("}")
        return lines.joined(separator: "\n")
    }

    func renderRoutingBlock(rules: [DAERouteRule], fallback: String) -> String {
        var lines = ["routing {"]
        for rule in rules {
            let matcher = rule.matcher.trimmingCharacters(in: .whitespacesAndNewlines)
            let outbound = rule.outbound.trimmingCharacters(in: .whitespacesAndNewlines)
            guard matcher.isEmpty == false, outbound.isEmpty == false else {
                continue
            }
            let rendered = "\(matcher) -> \(outbound)"
            if rule.enabled {
                lines.append("    \(rendered)")
            } else {
                lines.append("    # \(rendered)")
            }
        }
        lines.append("")
        lines.append("    fallback: \(fallback)")
        lines.append("}")
        return lines.joined(separator: "\n")
    }

    func trimLineComment(_ line: String) -> String {
        var result = ""
        var inSingleQuote = false
        var inDoubleQuote = false

        for ch in line {
            if ch == "'" && inDoubleQuote == false {
                inSingleQuote.toggle()
                result.append(ch)
                continue
            }
            if ch == "\"" && inSingleQuote == false {
                inDoubleQuote.toggle()
                result.append(ch)
                continue
            }
            if ch == "#", inSingleQuote == false, inDoubleQuote == false {
                break
            }
            result.append(ch)
        }
        return result
    }

    func parseKeyValueLine(_ line: String) -> (String, String)? {
        guard let colon = line.firstIndex(of: ":") else {
            return nil
        }
        let key = line[..<colon].trimmingCharacters(in: .whitespacesAndNewlines)
        let value = line[line.index(after: colon)...].trimmingCharacters(in: .whitespacesAndNewlines)
        guard key.isEmpty == false else {
            return nil
        }
        return (key, value)
    }

    func unquote(_ value: String) -> String {
        let trimmed = value.trimmingCharacters(in: .whitespacesAndNewlines)
        if trimmed.count >= 2, trimmed.hasPrefix("'"), trimmed.hasSuffix("'") {
            return String(trimmed.dropFirst().dropLast())
        }
        if trimmed.count >= 2, trimmed.hasPrefix("\""), trimmed.hasSuffix("\"") {
            return String(trimmed.dropFirst().dropLast())
        }
        return trimmed
    }

    func parseBool(_ value: String, fallback: Bool) -> Bool {
        switch unquote(value).lowercased() {
        case "1", "true", "yes", "on":
            return true
        case "0", "false", "no", "off":
            return false
        default:
            return fallback
        }
    }

    func renderBool(_ value: Bool) -> String {
        value ? "true" : "false"
    }

    func valueOrFallback(_ value: String, _ fallback: String) -> String {
        let trimmed = value.trimmingCharacters(in: .whitespacesAndNewlines)
        return trimmed.isEmpty ? fallback : trimmed
    }

    func singleQuoted(_ value: String) -> String {
        let escaped = value.replacingOccurrences(of: "'", with: "\\'")
        return "'\(escaped)'"
    }

    func stripLeadingCommentMarker(_ raw: String) -> String? {
        var index = raw.startIndex
        while index < raw.endIndex, raw[index].isWhitespace {
            index = raw.index(after: index)
        }
        guard index < raw.endIndex, raw[index] == "#" else {
            return nil
        }
        let afterHash = raw.index(after: index)
        return String(raw[afterHash...])
    }

    func sanitizeEntryTag(_ raw: String) -> String {
        let trimmed = raw.trimmingCharacters(in: .whitespacesAndNewlines)
        guard trimmed.isEmpty == false else {
            return ""
        }
        return trimmed
            .split(whereSeparator: { $0.isWhitespace })
            .joined(separator: "_")
    }

    func sanitizeGroupName(_ raw: String) -> String {
        let trimmed = raw.trimmingCharacters(in: .whitespacesAndNewlines)
        guard trimmed.isEmpty == false else {
            return ""
        }
        return trimmed
            .split(whereSeparator: { $0.isWhitespace })
            .joined(separator: "_")
    }
}
