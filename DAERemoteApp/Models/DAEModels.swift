import Foundation

struct DAEStatus: Equatable {
    var running: Bool
    var enabled: Bool
    var memory: String?
    var updatedAt: Date

    static let offline = DAEStatus(running: false, enabled: false, memory: nil, updatedAt: .distantPast)
}

struct OpenWrtOverview: Equatable {
    var hostname: String
    var model: String
    var cpu: String
    var kernel: String
    var firmware: String
    var uptime: String
    var load: String
    var memory: String

    static let empty = OpenWrtOverview(
        hostname: "--",
        model: "--",
        cpu: "--",
        kernel: "--",
        firmware: "--",
        uptime: "--",
        load: "--",
        memory: "--"
    )
}

enum DAEConfigSection: String, CaseIterable, Identifiable {
    case global
    case dns
    case node
    case route

    var id: String { rawValue }

    var title: String {
        switch self {
        case .global: return "Global"
        case .dns: return "DNS"
        case .node: return "Node"
        case .route: return "Route"
        }
    }

    var path: String {
        switch self {
        case .global: return "/etc/dae/config.dae"
        case .dns: return "/etc/dae/config.d/dns.dae"
        case .node: return "/etc/dae/config.d/node.dae"
        case .route: return "/etc/dae/config.d/route.dae"
        }
    }
}

enum DAEEditorTab: String, CaseIterable, Identifiable {
    case global
    case node
    case route

    var id: String { rawValue }

    var title: String {
        switch self {
        case .global: return "Global"
        case .node: return "Node"
        case .route: return "Route"
        }
    }

    var rawSection: DAEConfigSection {
        switch self {
        case .global: return .global
        case .node: return .node
        case .route: return .route
        }
    }
}

enum DAELogLevel: String, CaseIterable, Identifiable {
    case error, warn, info, debug, trace
    var id: String { rawValue }
}

enum DAEDialMode: String, CaseIterable, Identifiable {
    case ip
    case domain
    case domainPlus = "domain+"
    case domainDoublePlus = "domain++"

    var id: String { rawValue }
}

enum DAETlsImplementation: String, CaseIterable, Identifiable {
    case tls
    case utls
    var id: String { rawValue }
}

enum DAEGroupPolicy: String, CaseIterable, Identifiable {
    case random
    case fixed0 = "fixed(0)"
    case min
    case minMovingAvg = "min_moving_avg"
    case minAvg10 = "min_avg10"

    var id: String { rawValue }
}

enum DAERouteMatcherKind: String, CaseIterable, Identifiable {
    case pname
    case dip
    case domain
    case l4proto
    case dport
    case sport
    case process
    case custom

    var id: String { rawValue }

    var title: String {
        switch self {
        case .pname: return "pname"
        case .dip: return "dip"
        case .domain: return "domain"
        case .l4proto: return "l4proto"
        case .dport: return "dport"
        case .sport: return "sport"
        case .process: return "process_name"
        case .custom: return "custom"
        }
    }

    var placeholder: String {
        switch self {
        case .pname:
            return "NetworkManager"
        case .dip:
            return "geoip:cn"
        case .domain:
            return "geosite:cn"
        case .l4proto:
            return "tcp"
        case .dport:
            return "443"
        case .sport:
            return "1024-65535"
        case .process:
            return "openvpn"
        case .custom:
            return "直接输入完整 matcher"
        }
    }
}

struct DAEGlobalOptions {
    var tproxyPort = "12345"
    var tproxyPortProtect = true
    var pprofPort = "0"
    var soMarkFromDae = "0"
    var logLevel: DAELogLevel = .info
    var disableWaitingNetwork = false
    var wanInterface = "auto"
    var autoConfigKernelParameter = true
    var tcpCheckURL = "http://cp.cloudflare.com,1.1.1.1,2606:4700:4700::1111"
    var tcpCheckHTTPMethod = "HEAD"
    var udpCheckDNS = "dns.google:53,8.8.8.8,2001:4860:4860::8888"
    var checkInterval = "30s"
    var checkTolerance = "50ms"
    var dialMode: DAEDialMode = .domain
    var allowInsecure = false
    var sniffingTimeout = "100ms"
    var tlsImplementation: DAETlsImplementation = .tls
    var utlsImitate = "chrome_auto"
    var tlsFragment = false
    var tlsFragmentLength = "50-100"
    var tlsFragmentInterval = "10-20"
    var mptcp = false
    var bandwidthMaxTx = "200 mbps"
    var bandwidthMaxRx = "1 gbps"
    var fallbackResolver = "8.8.8.8:53"
}

struct DAENodeGroup: Identifiable, Equatable {
    let id: UUID
    var name: String
    var policy: DAEGroupPolicy
    var filter: String

    init(id: UUID = UUID(), name: String, policy: DAEGroupPolicy, filter: String) {
        self.id = id
        self.name = name
        self.policy = policy
        self.filter = filter
    }
}

struct DAEEndpointEntry: Identifiable, Equatable {
    let id: UUID
    var name: String
    var value: String
    var enabled: Bool

    init(id: UUID = UUID(), name: String, value: String, enabled: Bool) {
        self.id = id
        self.name = name
        self.value = value
        self.enabled = enabled
    }
}

struct DAERouteRule: Identifiable, Equatable {
    let id: UUID
    var matcher: String
    var outbound: String
    var enabled: Bool

    init(id: UUID = UUID(), matcher: String, outbound: String, enabled: Bool = true) {
        self.id = id
        self.matcher = matcher
        self.outbound = outbound
        self.enabled = enabled
    }
}
