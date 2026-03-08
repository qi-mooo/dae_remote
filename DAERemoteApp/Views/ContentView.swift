import SwiftUI
import UniformTypeIdentifiers

struct ContentView: View {
    @EnvironmentObject private var model: AppModel

    var body: some View {
        ZStack {
            LiquidBackground()
                .ignoresSafeArea()

            if model.isConnected {
                MainShellView()
            } else {
                LoginView()
            }
        }
        .overlay(alignment: .top) {
            if let notice = model.noticeMessage {
                Text(notice)
                    .font(.footnote.weight(.semibold))
                    .padding(.horizontal, 14)
                    .padding(.vertical, 8)
                    .background(.thinMaterial, in: Capsule())
                    .padding(.top, 8)
                    .task {
                        try? await Task.sleep(for: .seconds(1.8))
                        model.noticeMessage = nil
                    }
            }
        }
        .alert("连接提示", isPresented: $model.showConnectionAlert) {
            Button("确定", role: .cancel) {}
        } message: {
            Text(model.connectionAlertMessage)
        }
        .task {
            while Task.isCancelled == false {
                if model.isConnected {
                    model.refreshStatusSilently()
                }
                try? await Task.sleep(for: .seconds(12))
            }
        }
    }
}

private struct LoginView: View {
    @EnvironmentObject private var model: AppModel

    var body: some View {
        VStack(spacing: 16) {
            VStack(alignment: .leading, spacing: 8) {
                Text("DAE Remote")
                    .font(.system(size: 34, weight: .heavy, design: .rounded))
                Text("登录 OpenWrt 后开始管理 luci-app-dae")
                    .font(.footnote)
                    .foregroundStyle(.secondary)
            }
            .frame(maxWidth: .infinity, alignment: .leading)

            GlassCard {
                VStack(alignment: .leading, spacing: 12) {
                    Text("登录")
                        .font(.headline)

                    TextField("路由器地址，例如 http://10.0.0.1", text: $model.routerAddress)
                        .textInputAutocapitalization(.never)
                        .keyboardType(.URL)
                        .autocorrectionDisabled()
                        .textFieldStyle(.roundedBorder)

                    TextField("用户名", text: $model.username)
                        .textInputAutocapitalization(.never)
                        .autocorrectionDisabled()
                        .textFieldStyle(.roundedBorder)

                    SecureField("密码", text: $model.password)
                        .textFieldStyle(.roundedBorder)

                    Toggle("允许自签名 TLS（内网常用）", isOn: $model.allowInsecureTLS)
                        .font(.footnote)

                    HStack(spacing: 12) {
                        Button("登录") {
                            model.connect()
                        }
                        .buttonStyle(.borderedProminent)
                        .disabled(model.isLoading)

                        if model.isLoading {
                            ProgressView()
                        }
                    }

                    if let error = model.errorMessage {
                        Text(error)
                            .font(.footnote)
                            .foregroundStyle(.red)
                    }
                }
            }
        }
        .padding(.horizontal, 16)
        .padding(.top, 24)
        .padding(.bottom, 40)
    }
}

private struct MainShellView: View {
    var body: some View {
        TabView {
            DashboardView()
                .tabItem {
                    Label("控制台", systemImage: "gauge.with.dots.needle.67percent")
                }

            OptionsEditorView()
                .tabItem {
                    Label("选项编辑", systemImage: "slider.horizontal.3")
                }

            SettingsView()
                .tabItem {
                    Label("设置", systemImage: "gearshape")
                }
        }
    }
}

private struct DashboardView: View {
    @EnvironmentObject private var model: AppModel
    @State private var pendingAction: DashboardControlAction?

    var body: some View {
        ScrollView {
            VStack(spacing: 16) {
                header
                overviewCard
                statusCard
                controlCard
            }
            .padding(.horizontal, 16)
            .padding(.top, 24)
            .padding(.bottom, 40)
        }
        .task {
            model.refreshStatus()
        }
        .alert("确认操作", isPresented: Binding(get: {
            pendingAction != nil
        }, set: { newValue in
            if newValue == false {
                pendingAction = nil
            }
        }), presenting: pendingAction) { action in
            Button("取消", role: .cancel) {
                pendingAction = nil
            }
            Button("确认") {
                perform(action)
                pendingAction = nil
            }
        } message: { action in
            Text(action.confirmText(model: model))
        }
    }

    private var header: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("DAE Remote")
                .font(.system(size: 32, weight: .heavy, design: .rounded))
            Text("OpenWrt + luci-app-dae JSON-RPC 控制台")
                .font(.footnote)
                .foregroundStyle(.secondary)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    private var overviewCard: some View {
        GlassCard {
            VStack(alignment: .leading, spacing: 10) {
                Text("OpenWrt 系统概览")
                    .font(.headline)

                InfoKVRow(key: "主机名", value: model.overview.hostname)
                InfoKVRow(key: "设备", value: model.overview.model)
                InfoKVRow(key: "CPU", value: model.overview.cpu)
                InfoKVRow(key: "固件", value: model.overview.firmware)
                InfoKVRow(key: "内核", value: model.overview.kernel)
                InfoKVRow(key: "运行时长", value: model.overview.uptime)
                InfoKVRow(key: "Load", value: model.overview.load)
                InfoKVRow(key: "内存", value: model.overview.memory)
            }
        }
    }

    private var statusCard: some View {
        GlassCard {
            VStack(alignment: .leading, spacing: 12) {
                Text("状态")
                    .font(.headline)

                HStack(spacing: 12) {
                    StatusPill(
                        title: "运行",
                        value: model.status.running ? "RUNNING" : "STOPPED",
                        good: model.status.running
                    )
                    StatusPill(
                        title: "启用",
                        value: model.status.enabled ? "YES" : "NO",
                        good: model.status.enabled
                    )
                    StatusPill(
                        title: "进程",
                        value: model.status.memory ?? "--",
                        good: true
                    )
                }

                Text("更新时间: \(model.status.updatedAt.formatted(date: .omitted, time: .standard))")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
        }
    }

    private var controlCard: some View {
        GlassCard {
            VStack(alignment: .leading, spacing: 10) {
                Text("控制")
                    .font(.headline)

                HStack(spacing: 8) {
                    dashboardButton(title: model.status.enabled ? "禁用" : "启用") {
                        pendingAction = .toggleEnable
                    }
                    dashboardButton(title: model.status.running ? "停止" : "启动") {
                        pendingAction = .toggleRunning
                    }
                    dashboardButton(title: "重载") {
                        pendingAction = .reload
                    }
                }
            }
        }
    }

    private func dashboardButton(title: String, action: @escaping () -> Void) -> some View {
        Button(title, action: action)
            .buttonStyle(.borderedProminent)
            .font(.headline.weight(.bold))
            .lineLimit(1)
            .frame(maxWidth: .infinity, minHeight: 56)
            .disabled(model.isLoading)
    }

    private func perform(_ action: DashboardControlAction) {
        switch action {
        case .toggleEnable:
            model.toggleEnabled()
        case .toggleRunning:
            model.switchService(!model.status.running)
        case .reload:
            model.hotReload()
        }
    }
}

private enum DashboardControlAction {
    case toggleEnable
    case toggleRunning
    case reload

    @MainActor
    func confirmText(model: AppModel) -> String {
        switch self {
        case .toggleEnable:
            return model.status.enabled ? "确认禁用 dae？" : "确认启用 dae？"
        case .toggleRunning:
            return model.status.running ? "确认停止 dae 服务？" : "确认启动 dae 服务？"
        case .reload:
            return "确认重载 dae 服务？"
        }
    }
}

private struct OptionsEditorView: View {
    @EnvironmentObject private var model: AppModel
    @State private var showSaveConfirm = false
    @State private var showReloadConfirm = false

    var body: some View {
        NavigationStack {
            ZStack(alignment: .bottomTrailing) {
                VStack(spacing: 12) {
                    headerCard
                    contentBody
                }

                VStack(spacing: 10) {
                    floatingButton(systemName: "arrow.clockwise", color: .red) {
                        showReloadConfirm = true
                    }
                    .disabled(model.isLoading)

                    floatingButton(systemName: "checkmark", color: .green) {
                        showSaveConfirm = true
                    }
                    .disabled(model.isLoading || model.nodeGroupNames.isEmpty)
                }
                .padding(.trailing, 20)
                .padding(.bottom, 24)
            }
            .background(Color.clear)
            .navigationBarTitleDisplayMode(.inline)
            .sheet(isPresented: $model.showingRawEditor) {
                RawConfigEditorSheet()
                    .environmentObject(model)
            }
            .alert("确认重载 dae 服务？", isPresented: $showReloadConfirm) {
                Button("取消", role: .cancel) {}
                Button("确认") {
                    model.hotReload()
                }
            }
            .alert("确认保存并重载？", isPresented: $showSaveConfirm) {
                Button("取消", role: .cancel) {}
                Button("确认") {
                    model.saveOptionEditor()
                }
            }
            .task {
                model.ensureOptionEditorLoaded()
            }
        }
    }

    private var headerCard: some View {
        GlassCard {
            VStack(alignment: .leading, spacing: 12) {
                HStack(alignment: .top) {
                    VStack(alignment: .leading, spacing: 6) {
                        Text("选项编辑")
                            .font(.system(size: 30, weight: .heavy, design: .rounded))
                        Text("Node/Route 为预览条目，点击后进入快速编辑")
                            .font(.footnote)
                            .foregroundStyle(.secondary)
                    }
                    Spacer()
                    Button {
                        model.openRawEditor()
                    } label: {
                        Image(systemName: "doc.text")
                            .font(.headline)
                    }
                    .buttonStyle(.bordered)
                }

                Picker("编辑页", selection: $model.editorTab) {
                    ForEach(DAEEditorTab.allCases) { tab in
                        Text(tab.title).tag(tab)
                    }
                }
                .pickerStyle(.segmented)

                if let error = model.errorMessage {
                    Text(error)
                        .font(.footnote)
                        .foregroundStyle(.red)
                }
            }
        }
        .padding(.horizontal, 16)
        .padding(.top, 16)
    }

    @ViewBuilder
    private var contentBody: some View {
        switch model.editorTab {
        case .global:
            ScrollView {
                GlassCard {
                    GlobalOptionsForm()
                }
                .padding(.horizontal, 16)
                .padding(.bottom, 120)
            }
        case .node:
            NodeOptionsForm()
        case .route:
            RouteOptionsForm()
        }
    }

    private func floatingButton(systemName: String, color: Color, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Image(systemName: systemName)
                .font(.headline)
                .foregroundStyle(.white)
                .frame(width: 52, height: 52)
                .background(color, in: Circle())
                .shadow(color: .black.opacity(0.25), radius: 10, x: 0, y: 6)
        }
    }
}

private struct GlobalOptionsForm: View {
    @EnvironmentObject private var model: AppModel

    private func help(_ key: String) -> String {
        GlobalOptionHelp.text(for: key)
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("Global")
                .font(.headline)

            OptionTextField(
                title: "tproxy_port",
                placeholder: "12345",
                text: $model.globalOptions.tproxyPort,
                helpText: help("tproxy_port")
            )
            OptionToggleField(
                title: "tproxy_port_protect",
                isOn: $model.globalOptions.tproxyPortProtect,
                helpText: help("tproxy_port_protect")
            )
            OptionTextField(
                title: "pprof_port",
                placeholder: "0",
                text: $model.globalOptions.pprofPort,
                helpText: help("pprof_port")
            )
            OptionTextField(
                title: "so_mark_from_dae",
                placeholder: "0",
                text: $model.globalOptions.soMarkFromDae,
                helpText: help("so_mark_from_dae")
            )

            OptionMenuField(title: "log_level", selection: $model.globalOptions.logLevel, helpText: help("log_level")) {
                ForEach(DAELogLevel.allCases) { level in
                    Text(level.rawValue).tag(level)
                }
            }
            OptionToggleField(
                title: "disable_waiting_network",
                isOn: $model.globalOptions.disableWaitingNetwork,
                helpText: help("disable_waiting_network")
            )
            OptionTextField(
                title: "wan_interface",
                placeholder: "auto",
                text: $model.globalOptions.wanInterface,
                helpText: help("wan_interface")
            )
            OptionToggleField(
                title: "auto_config_kernel_parameter",
                isOn: $model.globalOptions.autoConfigKernelParameter,
                helpText: help("auto_config_kernel_parameter")
            )

            OptionTextField(
                title: "tcp_check_url",
                placeholder: "http://cp.cloudflare.com,...",
                text: $model.globalOptions.tcpCheckURL,
                helpText: help("tcp_check_url")
            )
            OptionTextField(
                title: "tcp_check_http_method",
                placeholder: "HEAD",
                text: $model.globalOptions.tcpCheckHTTPMethod,
                helpText: help("tcp_check_http_method")
            )
            OptionTextField(
                title: "udp_check_dns",
                placeholder: "dns.google:53,...",
                text: $model.globalOptions.udpCheckDNS,
                helpText: help("udp_check_dns")
            )
            OptionTextField(
                title: "check_interval",
                placeholder: "30s",
                text: $model.globalOptions.checkInterval,
                helpText: help("check_interval")
            )
            OptionTextField(
                title: "check_tolerance",
                placeholder: "50ms",
                text: $model.globalOptions.checkTolerance,
                helpText: help("check_tolerance")
            )

            OptionMenuField(title: "dial_mode", selection: $model.globalOptions.dialMode, helpText: help("dial_mode")) {
                ForEach(DAEDialMode.allCases) { mode in
                    Text(mode.rawValue).tag(mode)
                }
            }
            OptionToggleField(
                title: "allow_insecure",
                isOn: $model.globalOptions.allowInsecure,
                helpText: help("allow_insecure")
            )
            OptionTextField(
                title: "sniffing_timeout",
                placeholder: "100ms",
                text: $model.globalOptions.sniffingTimeout,
                helpText: help("sniffing_timeout")
            )

            OptionMenuField(
                title: "tls_implementation",
                selection: $model.globalOptions.tlsImplementation,
                helpText: help("tls_implementation")
            ) {
                ForEach(DAETlsImplementation.allCases) { impl in
                    Text(impl.rawValue).tag(impl)
                }
            }
            OptionTextField(
                title: "utls_imitate",
                placeholder: "chrome_auto",
                text: $model.globalOptions.utlsImitate,
                helpText: help("utls_imitate")
            )
            OptionToggleField(
                title: "tls_fragment",
                isOn: $model.globalOptions.tlsFragment,
                helpText: help("tls_fragment")
            )
            OptionTextField(
                title: "tls_fragment_length",
                placeholder: "50-100",
                text: $model.globalOptions.tlsFragmentLength,
                helpText: help("tls_fragment_length")
            )
            OptionTextField(
                title: "tls_fragment_interval",
                placeholder: "10-20",
                text: $model.globalOptions.tlsFragmentInterval,
                helpText: help("tls_fragment_interval")
            )

            OptionToggleField(
                title: "mptcp",
                isOn: $model.globalOptions.mptcp,
                helpText: help("mptcp")
            )
            OptionTextField(
                title: "bandwidth_max_tx",
                placeholder: "200 mbps",
                text: $model.globalOptions.bandwidthMaxTx,
                helpText: help("bandwidth_max_tx")
            )
            OptionTextField(
                title: "bandwidth_max_rx",
                placeholder: "1 gbps",
                text: $model.globalOptions.bandwidthMaxRx,
                helpText: help("bandwidth_max_rx")
            )
            OptionTextField(
                title: "fallback_resolver",
                placeholder: "8.8.8.8:53",
                text: $model.globalOptions.fallbackResolver,
                helpText: help("fallback_resolver")
            )
        }
    }
}

private struct NodeOptionsForm: View {
    @EnvironmentObject private var model: AppModel

    @State private var sectionTab: NodeSectionAnchor = .subscription
    @State private var editTarget: NodeEditTarget?
    @State private var showingAddGroupSheet = false
    @State private var showingAddSubscriptionSheet = false
    @State private var showingAddNodeSheet = false

    private let subscriptionQuickTokens = [
        "https://www.example.com/subscription/link",
        "https-file://www.example.com/persist_sub/link",
        "file://relative/path/to/mysub.sub"
    ]
    private let nodeQuickTokens = [
        "socks5://localhost:1080",
        "ss://LINK",
        "vmess://LINK",
        "vless://LINK",
        "hysteria2://password@server-ip:port/?sni=domain"
    ]
    private let groupFilterQuickTokens = [
        "name()",
        "name(keyword: '')",
        "subtag()",
        "subtag(regex: '^my_', another_sub)",
        "[add_latency: -500ms]",
        "&& !name(keyword: '')"
    ]

    var body: some View {
        ScrollViewReader { proxy in
            ScrollView {
                VStack(spacing: 12) {
                    GlassCard {
                        VStack(alignment: .leading, spacing: 10) {
                            HStack {
                                Text("Subscription")
                                    .font(.headline)
                                Spacer()
                                Button {
                                    showingAddSubscriptionSheet = true
                                } label: {
                                    Label("新增", systemImage: "plus")
                                }
                                .buttonStyle(.bordered)
                                .disabled(model.isLoading)
                            }

                            ForEach(model.subscriptionEntries) { entry in
                                PreviewEntryStrip(
                                    title: entry.name.isEmpty ? "(无 tag)" : entry.name,
                                    subtitle: entry.value,
                                    enabled: subscriptionEnabledBinding(id: entry.id),
                                    onDelete: {
                                        model.removeSubscriptionEntry(entry.id)
                                    },
                                    onTap: {
                                        editTarget = .subscription(entry.id)
                                    }
                                )
                            }
                        }
                    }
                    .id(NodeSectionAnchor.subscription.rawValue)

                    GlassCard {
                        VStack(alignment: .leading, spacing: 10) {
                            HStack {
                                Text("Node")
                                    .font(.headline)
                                Spacer()
                                Button {
                                    showingAddNodeSheet = true
                                } label: {
                                    Label("新增", systemImage: "plus")
                                }
                                .buttonStyle(.bordered)
                                .disabled(model.isLoading)
                            }

                            ForEach(model.nodeEntries) { entry in
                                PreviewEntryStrip(
                                    title: nodeDisplayTitle(for: entry),
                                    subtitle: entry.value,
                                    enabled: nodeEnabledBinding(id: entry.id),
                                    onDelete: {
                                        model.removeNodeEntry(entry.id)
                                    },
                                    onTap: {
                                        editTarget = .node(entry.id)
                                    }
                                )
                            }
                        }
                    }
                    .id(NodeSectionAnchor.node.rawValue)

                    GlassCard {
                        VStack(alignment: .leading, spacing: 10) {
                            HStack {
                                Text("Group")
                                    .font(.headline)
                                Spacer()
                                Button {
                                    showingAddGroupSheet = true
                                } label: {
                                    Label("新增", systemImage: "plus")
                                }
                                .buttonStyle(.bordered)
                                .disabled(model.isLoading)
                            }

                            ForEach(Array(model.nodeGroups.enumerated()), id: \.element.id) { _, group in
                                PreviewRow(
                                    title: group.name,
                                    subtitle: "policy: \(group.policy.rawValue)",
                                    onDelete: {
                                        model.removeNodeGroup(group.id)
                                    },
                                    onTap: {
                                        editTarget = .group(group.id)
                                    }
                                )
                            }
                        }
                    }
                    .id(NodeSectionAnchor.group.rawValue)
                }
                .padding(.horizontal, 16)
                .padding(.top, 12)
                .padding(.bottom, 120)
            }
            .safeAreaInset(edge: .top) {
                HStack(spacing: 8) {
                    ForEach(NodeSectionAnchor.allCases) { anchor in
                        Button(anchor.title) {
                            sectionTab = anchor
                        }
                        .buttonStyle(.bordered)
                        .tint(sectionTab == anchor ? .accentColor : .gray)
                    }
                }
                .padding(.horizontal, 16)
                .padding(.vertical, 8)
            }
            .onChange(of: sectionTab) { _, newValue in
                withAnimation {
                    proxy.scrollTo(newValue.rawValue, anchor: .top)
                }
            }
        }
        .sheet(isPresented: $showingAddSubscriptionSheet) {
            AddSubscriptionSheet(quickTokens: subscriptionQuickTokens) { name, value, enabled in
                model.addSubscriptionEntry(name: name, value: value, enabled: enabled)
            }
            .presentationDetents([.medium])
        }
        .sheet(isPresented: $showingAddNodeSheet) {
            AddNodeSheet(quickTokens: nodeQuickTokens) { name, value, enabled in
                model.addNodeEntry(name: name, value: value, enabled: enabled)
            }
            .presentationDetents([.large])
        }
        .sheet(isPresented: $showingAddGroupSheet) {
            AddGroupSheet(filterQuickTokens: groupFilterQuickTokens) { name, policy, filter in
                model.addNodeGroup(name: name, policy: policy, filter: filter)
            }
        }
        .sheet(item: $editTarget) { target in
            switch target {
            case let .subscription(id):
                if let binding = subscriptionBinding(id: id) {
                    EndpointQuickEditorSheet(
                        title: "编辑 Subscription",
                        entry: binding,
                        quickTokens: subscriptionQuickTokens,
                        showNameField: true,
                        nameTitle: "tag（可选）",
                        namePlaceholder: "my_tag",
                        valueTitle: "value",
                        valuePlaceholder: "https://www.example.com/subscription/link"
                    )
                }
            case let .node(id):
                if let binding = nodeBinding(id: id) {
                    EndpointQuickEditorSheet(
                        title: "编辑 Node",
                        entry: binding,
                        quickTokens: nodeQuickTokens,
                        showNameField: true,
                        nameTitle: "name（可选）",
                        namePlaceholder: "node1",
                        valueTitle: "node",
                        valuePlaceholder: "socks5://localhost:1080"
                    )
                }
            case let .group(id):
                if let binding = groupBinding(id: id) {
                    GroupQuickEditorSheet(
                        group: binding,
                        filterQuickTokens: groupFilterQuickTokens
                    )
                }
            }
        }
    }

    private func subscriptionBinding(id: UUID) -> Binding<DAEEndpointEntry>? {
        guard let idx = model.subscriptionEntries.firstIndex(where: { $0.id == id }) else {
            return nil
        }
        return $model.subscriptionEntries[idx]
    }

    private func subscriptionEnabledBinding(id: UUID) -> Binding<Bool> {
        Binding(
            get: {
                model.subscriptionEntries.first(where: { $0.id == id })?.enabled ?? false
            },
            set: { enabled in
                guard let idx = model.subscriptionEntries.firstIndex(where: { $0.id == id }) else {
                    return
                }
                model.subscriptionEntries[idx].enabled = enabled
            }
        )
    }

    private func nodeBinding(id: UUID) -> Binding<DAEEndpointEntry>? {
        guard let idx = model.nodeEntries.firstIndex(where: { $0.id == id }) else {
            return nil
        }
        return $model.nodeEntries[idx]
    }

    private func nodeEnabledBinding(id: UUID) -> Binding<Bool> {
        Binding(
            get: {
                model.nodeEntries.first(where: { $0.id == id })?.enabled ?? false
            },
            set: { enabled in
                guard let idx = model.nodeEntries.firstIndex(where: { $0.id == id }) else {
                    return
                }
                model.nodeEntries[idx].enabled = enabled
            }
        )
    }

    private func groupBinding(id: UUID) -> Binding<DAENodeGroup>? {
        guard let idx = model.nodeGroups.firstIndex(where: { $0.id == id }) else {
            return nil
        }
        return $model.nodeGroups[idx]
    }

    private func nodeDisplayTitle(for entry: DAEEndpointEntry) -> String {
        let explicitName = entry.name.trimmingCharacters(in: .whitespacesAndNewlines)
        if explicitName.isEmpty == false {
            return explicitName
        }
        let raw = entry.value.trimmingCharacters(in: .whitespacesAndNewlines)
        guard raw.isEmpty == false else {
            return "(未命名节点)"
        }
        if let schemeRange = raw.range(of: "://"),
           let splitIndex = raw[..<schemeRange.lowerBound].lastIndex(of: ":") {
            let prefixedName = String(raw[..<splitIndex]).trimmingCharacters(in: .whitespacesAndNewlines)
            if prefixedName.isEmpty == false {
                return prefixedName
            }
        }
        if let components = URLComponents(string: raw) {
            if let fragment = components.fragment?.trimmingCharacters(in: .whitespacesAndNewlines),
               fragment.isEmpty == false {
                return fragment.removingPercentEncoding ?? fragment
            }
            if let name = components.queryItems?.first(where: { $0.name.lowercased() == "name" })?.value?
                .trimmingCharacters(in: .whitespacesAndNewlines),
                name.isEmpty == false {
                return name
            }
            if let host = components.host?.trimmingCharacters(in: .whitespacesAndNewlines),
               host.isEmpty == false {
                return host
            }
        }
        if let schemeRange = raw.range(of: "://") {
            let suffix = String(raw[schemeRange.upperBound...])
            if let token = suffix.split(separator: "/", maxSplits: 1).first,
               token.isEmpty == false {
                return String(token)
            }
        }
        return raw
    }
}

private enum NodeSectionAnchor: String, CaseIterable, Identifiable {
    case subscription
    case node
    case group

    var id: String { rawValue }

    var title: String {
        switch self {
        case .subscription: return "Sub"
        case .node: return "Node"
        case .group: return "Group"
        }
    }
}

private enum NodeEditTarget: Identifiable {
    case subscription(UUID)
    case node(UUID)
    case group(UUID)

    var id: String {
        switch self {
        case let .subscription(id): return "s-\(id.uuidString)"
        case let .node(id): return "n-\(id.uuidString)"
        case let .group(id): return "g-\(id.uuidString)"
        }
    }
}

private struct RouteOptionsForm: View {
    @EnvironmentObject private var model: AppModel

    @State private var showingMatcherSelector = false
    @State private var showingMatcherComposer = false
    @State private var composerKind: DAERouteMatcherKind = .pname
    @State private var composerInput = ""
    @State private var composerOutbound = ""
    @State private var draggingRuleID: UUID?
    @State private var editingRouteID: UUID?

    var body: some View {
        ScrollView {
            VStack(spacing: 12) {
                GlassCard {
                    VStack(alignment: .leading, spacing: 10) {
                        HStack {
                            Text("Route")
                                .font(.headline)
                            Spacer()
                            Button {
                                showingMatcherSelector = true
                            } label: {
                                Label("新增规则", systemImage: "plus")
                            }
                            .buttonStyle(.bordered)
                            .disabled(model.isLoading)
                        }

                        VStack(alignment: .leading, spacing: 6) {
                            Text("Fallback 出站目标")
                                .font(.caption)
                                .foregroundStyle(.secondary)
                            Menu {
                                ForEach(model.routeOutboundChoices, id: \.self) { name in
                                    Button(name) {
                                        model.routeFallbackGroup = name
                                    }
                                }
                            } label: {
                                HStack {
                                    Text(model.routeFallbackGroup.isEmpty ? "请选择目标" : model.routeFallbackGroup)
                                        .lineLimit(1)
                                    Spacer()
                                    Image(systemName: "chevron.up.chevron.down")
                                }
                            }
                            .buttonStyle(.borderedProminent)
                            .tint(.indigo)
                        }

                        if model.nodeGroupNames.isEmpty {
                            Text("可直接使用固定目标：direct / block / must_rules；也可在 Node 页新增 Group。")
                                .font(.footnote)
                                .foregroundStyle(.secondary)
                        }

                        ForEach(model.routeRules) { rule in
                            RoutePreviewStrip(
                                matcher: rule.matcher,
                                outbound: rule.outbound,
                                enabled: routeEnabledBinding(id: rule.id),
                                onDelete: {
                                    model.removeRouteRule(rule.id)
                                },
                                onTap: {
                                    editingRouteID = rule.id
                                }
                            )
                            .onDrag {
                                draggingRuleID = rule.id
                                return NSItemProvider(object: rule.id.uuidString as NSString)
                            }
                            .onDrop(
                                of: [UTType.text],
                                delegate: RouteRuleDropDelegate(
                                    targetID: rule.id,
                                    rules: $model.routeRules,
                                    draggingID: $draggingRuleID
                                )
                            )
                        }
                    }
                }
            }
            .padding(.horizontal, 16)
            .padding(.top, 12)
            .padding(.bottom, 120)
        }
        .confirmationDialog("选择 Matcher", isPresented: $showingMatcherSelector, titleVisibility: .visible) {
            ForEach(DAERouteMatcherKind.allCases) { kind in
                Button(kind.title) {
                    composerKind = kind
                    composerInput = ""
                    composerOutbound = model.routeFallbackGroup.isEmpty
                        ? (model.routeOutboundChoices.first ?? "")
                        : model.routeFallbackGroup
                    showingMatcherComposer = true
                }
            }
        }
        .sheet(isPresented: $showingMatcherComposer) {
            RouteMatcherComposerSheet(
                matcherKind: composerKind,
                outboundChoices: model.routeOutboundChoices,
                matcherInput: $composerInput,
                selectedOutbound: $composerOutbound
            ) { matcher, outbound in
                model.addRouteRule(matcher: matcher, outbound: outbound, enabled: true)
            }
        }
        .sheet(isPresented: Binding(get: {
            editingRouteID != nil
        }, set: { newValue in
            if newValue == false {
                editingRouteID = nil
            }
        })) {
            if let id = editingRouteID, let binding = routeBinding(id: id) {
                RouteRuleQuickEditorSheet(
                    rule: binding,
                    outboundChoices: model.routeOutboundChoices
                )
            }
        }
    }

    private func routeBinding(id: UUID) -> Binding<DAERouteRule>? {
        guard let idx = model.routeRules.firstIndex(where: { $0.id == id }) else {
            return nil
        }
        return $model.routeRules[idx]
    }

    private func routeEnabledBinding(id: UUID) -> Binding<Bool> {
        Binding(
            get: {
                model.routeRules.first(where: { $0.id == id })?.enabled ?? false
            },
            set: { enabled in
                guard let idx = model.routeRules.firstIndex(where: { $0.id == id }) else {
                    return
                }
                model.routeRules[idx].enabled = enabled
            }
        )
    }
}

private struct PreviewEntryStrip: View {
    let title: String
    let subtitle: String
    @Binding var enabled: Bool
    let onDelete: () -> Void
    let onTap: () -> Void

    var body: some View {
        HStack(spacing: 12) {
            Toggle("", isOn: $enabled)
                .labelsHidden()
                .frame(width: 48)

            Button(action: onTap) {
                HStack(spacing: 8) {
                    VStack(alignment: .leading, spacing: 2) {
                        Text(title)
                            .font(.subheadline.weight(.semibold))
                            .lineLimit(1)
                        Text(subtitle)
                            .font(.caption)
                            .foregroundStyle(.secondary)
                            .lineLimit(1)
                    }
                    Spacer(minLength: 8)
                    Image(systemName: "chevron.right")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
                .contentShape(Rectangle())
            }
            .buttonStyle(.plain)

            Button(role: .destructive) {
                onDelete()
            } label: {
                Image(systemName: "trash")
            }
            .buttonStyle(.bordered)
        }
        .padding(10)
        .background(
            RoundedRectangle(cornerRadius: 12)
                .fill(.thinMaterial)
        )
        .saturation(enabled ? 1 : 0)
        .opacity(enabled ? 1 : 0.5)
    }
}

private struct PreviewRow: View {
    let title: String
    let subtitle: String
    let onDelete: () -> Void
    let onTap: () -> Void

    var body: some View {
        HStack(spacing: 12) {
            Button(action: onTap) {
                HStack(spacing: 8) {
                    VStack(alignment: .leading, spacing: 2) {
                        Text(title)
                            .font(.subheadline.weight(.semibold))
                            .lineLimit(1)
                        Text(subtitle)
                            .font(.caption)
                            .foregroundStyle(.secondary)
                            .lineLimit(1)
                    }
                    Spacer(minLength: 8)
                    Image(systemName: "chevron.right")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
                .contentShape(Rectangle())
            }
            .buttonStyle(.plain)

            Button(role: .destructive) {
                onDelete()
            } label: {
                Image(systemName: "trash")
            }
            .buttonStyle(.bordered)
        }
        .padding(10)
        .background(
            RoundedRectangle(cornerRadius: 12)
                .fill(.thinMaterial)
        )
    }
}

private struct RoutePreviewStrip: View {
    let matcher: String
    let outbound: String
    @Binding var enabled: Bool
    let onDelete: () -> Void
    let onTap: () -> Void

    private var parsedMatcher: (type: String, content: String) {
        let text = matcher.trimmingCharacters(in: .whitespacesAndNewlines)
        guard text.isEmpty == false else {
            return ("matcher", "(empty matcher)")
        }
        guard let open = text.firstIndex(of: "("),
              let close = text.lastIndex(of: ")"),
              open < close else {
            return ("matcher", text)
        }
        let type = String(text[..<open]).trimmingCharacters(in: .whitespacesAndNewlines)
        var content = String(text[text.index(after: open) ..< close]).trimmingCharacters(in: .whitespacesAndNewlines)
        if let colon = content.firstIndex(of: ":") {
            let head = String(content[..<colon]).trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
            let tail = String(content[content.index(after: colon)...]).trimmingCharacters(in: .whitespacesAndNewlines)
            if ["geosite", "geoip", "keyword", "suffix", "ip"].contains(head) {
                content = tail
            }
        }
        let cleaned = content
            .replacingOccurrences(of: "'", with: "")
            .replacingOccurrences(of: "\"", with: "")
        return (
            type.isEmpty ? "matcher" : String(type),
            cleaned.isEmpty ? text : cleaned
        )
    }

    var body: some View {
        HStack(alignment: .top, spacing: 12) {
            Image(systemName: "line.3.horizontal")
                .foregroundStyle(.secondary)
                .padding(.leading, 2)
                .padding(.top, 6)

            Toggle("", isOn: $enabled)
                .labelsHidden()
                .frame(width: 48)
                .padding(.top, 2)

            Button(action: onTap) {
                HStack(spacing: 8) {
                    VStack(alignment: .leading, spacing: 2) {
                        Text(parsedMatcher.content)
                            .font(.subheadline.weight(.semibold))
                            .lineLimit(2)
                        Text("\(parsedMatcher.type) -> \(outbound)")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                            .lineLimit(1)
                    }
                    Spacer(minLength: 8)
                    Image(systemName: "chevron.right")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
                .contentShape(Rectangle())
            }
            .buttonStyle(.plain)

            Button(role: .destructive) {
                onDelete()
            } label: {
                Image(systemName: "trash")
            }
            .buttonStyle(.bordered)
            .padding(.top, 1)
        }
        .padding(10)
        .background(
            RoundedRectangle(cornerRadius: 12)
                .fill(.thinMaterial)
        )
        .saturation(enabled ? 1 : 0)
        .opacity(enabled ? 1 : 0.5)
    }
}

private struct EndpointQuickEditorSheet: View {
    let title: String
    @Binding var entry: DAEEndpointEntry
    let quickTokens: [String]
    let showNameField: Bool
    let nameTitle: String
    let namePlaceholder: String
    let valueTitle: String
    let valuePlaceholder: String
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        NavigationStack {
            VStack(alignment: .leading, spacing: 12) {
                Toggle("启用（关闭时保存为注释行）", isOn: $entry.enabled)

                if showNameField {
                    OptionTextField(title: nameTitle, placeholder: namePlaceholder, text: $entry.name)
                }
                OptionTextField(title: valueTitle, placeholder: valuePlaceholder, text: $entry.value)

                QuickTokenRow(title: "快速输入", tokens: quickTokens) { token in
                    entry.value = token
                }

                Spacer()
            }
            .padding(16)
            .navigationTitle(title)
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .confirmationAction) {
                    Button("完成") {
                        dismiss()
                    }
                }
            }
        }
    }
}

private struct GroupQuickEditorSheet: View {
    @Binding var group: DAENodeGroup
    let filterQuickTokens: [String]
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        NavigationStack {
            VStack(alignment: .leading, spacing: 12) {
                OptionTextField(title: "group", placeholder: "my_group", text: $group.name)

                Picker("policy", selection: $group.policy) {
                    ForEach(DAEGroupPolicy.allCases) { policy in
                        Text(policy.rawValue).tag(policy)
                    }
                }
                .pickerStyle(.menu)

                QuickTokenRow(title: "过滤快速输入", tokens: filterQuickTokens) { token in
                    if group.filter.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                        group.filter = token
                    } else {
                        group.filter += "\n\(token)"
                    }
                }

                TextEditor(text: $group.filter)
                    .frame(minHeight: 160)
                    .font(.system(.footnote, design: .monospaced))
                    .scrollContentBackground(.hidden)
                    .padding(8)
                    .background(
                        RoundedRectangle(cornerRadius: 10)
                            .fill(Color.black.opacity(0.12))
                    )

                Spacer()
            }
            .padding(16)
            .navigationTitle("编辑 Group")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .confirmationAction) {
                    Button("完成") {
                        dismiss()
                    }
                }
            }
        }
    }
}

private struct AddGroupSheet: View {
    let filterQuickTokens: [String]
    let onConfirm: (String, DAEGroupPolicy, String) -> Void

    @State private var name = ""
    @State private var policy: DAEGroupPolicy = .minMovingAvg
    @State private var filter = ""
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        NavigationStack {
            VStack(alignment: .leading, spacing: 12) {
                OptionTextField(title: "group", placeholder: "my_group", text: $name)

                Picker("policy", selection: $policy) {
                    ForEach(DAEGroupPolicy.allCases) { item in
                        Text(item.rawValue).tag(item)
                    }
                }
                .pickerStyle(.menu)

                QuickTokenRow(title: "过滤快速输入", tokens: filterQuickTokens) { token in
                    if filter.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                        filter = token
                    } else {
                        filter += "\n\(token)"
                    }
                }

                TextEditor(text: $filter)
                    .frame(minHeight: 140)
                    .font(.system(.footnote, design: .monospaced))
                    .scrollContentBackground(.hidden)
                    .padding(8)
                    .background(
                        RoundedRectangle(cornerRadius: 10)
                            .fill(Color.black.opacity(0.12))
                    )

                Spacer()
            }
            .padding(16)
            .navigationTitle("新增 Group")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("取消") {
                        dismiss()
                    }
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button("添加") {
                        onConfirm(name, policy, filter)
                        dismiss()
                    }
                }
            }
        }
    }
}

private struct AddSubscriptionSheet: View {
    let quickTokens: [String]
    let onConfirm: (String, String, Bool) -> Void

    @State private var name = ""
    @State private var value = "https://"
    @State private var enabled = true
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        NavigationStack {
            VStack(alignment: .leading, spacing: 12) {
                Toggle("启用（关闭时保存为注释行）", isOn: $enabled)
                OptionTextField(title: "tag（可选）", placeholder: "my_sub", text: $name)
                OptionTextField(title: "value", placeholder: "https://www.example.com/subscription/link", text: $value)
                QuickTokenRow(title: "快速输入", tokens: quickTokens) { token in
                    value = token
                }
                Spacer()
            }
            .padding(16)
            .navigationTitle("新增 Subscription")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("取消") {
                        dismiss()
                    }
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button("添加") {
                        onConfirm(name, value, enabled)
                        dismiss()
                    }
                    .disabled(value.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
                }
            }
        }
    }
}

private struct AddNodeSheet: View {
    let quickTokens: [String]
    let onConfirm: (String, String, Bool) -> Void

    @State private var name = ""
    @State private var value = "socks5://"
    @State private var enabled = true
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        NavigationStack {
            VStack(alignment: .leading, spacing: 12) {
                Toggle("启用（关闭时保存为注释行）", isOn: $enabled)
                OptionTextField(title: "name（可选）", placeholder: "node1", text: $name)

                VStack(alignment: .leading, spacing: 6) {
                    Text("node")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                    TextField("socks5://localhost:1080", text: $value, axis: .vertical)
                        .lineLimit(2 ... 6)
                        .textInputAutocapitalization(.never)
                        .autocorrectionDisabled()
                        .textFieldStyle(.roundedBorder)
                }

                QuickTokenRow(title: "快速输入", tokens: quickTokens) { token in
                    value = token
                }
                Spacer()
            }
            .padding(16)
            .navigationTitle("新增 Node")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("取消") {
                        dismiss()
                    }
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button("添加") {
                        onConfirm(name, value, enabled)
                        dismiss()
                    }
                    .disabled(value.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
                }
            }
        }
    }
}

private struct RouteRuleQuickEditorSheet: View {
    @Binding var rule: DAERouteRule
    let outboundChoices: [String]
    @Environment(\.dismiss) private var dismiss

    private let quickTokens = ["pname()", "dip()", "domain()", "l4proto()", "dport()", "geoip:", "geosite:"]
    private let builtInOutboundTokens = ["direct", "block", "must_rules"]

    var body: some View {
        NavigationStack {
            VStack(alignment: .leading, spacing: 12) {
                Toggle("启用（关闭时保存为注释行）", isOn: $rule.enabled)

                VStack(alignment: .leading, spacing: 6) {
                    Text("matcher")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                    TextField("domain(geosite:cn)", text: $rule.matcher, axis: .vertical)
                        .lineLimit(2 ... 6)
                        .textInputAutocapitalization(.never)
                        .autocorrectionDisabled()
                        .textFieldStyle(.roundedBorder)
                }

                QuickTokenRow(title: "快速输入", tokens: quickTokens) { token in
                    if rule.matcher.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                        rule.matcher = token
                    } else {
                        rule.matcher += token
                    }
                }

                VStack(alignment: .leading, spacing: 6) {
                    Text("出站目标")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                    Menu {
                        ForEach(outboundChoices, id: \.self) { outbound in
                            Button(outbound) {
                                rule.outbound = outbound
                            }
                        }
                    } label: {
                        HStack {
                            Text(rule.outbound.isEmpty ? "请选择目标" : rule.outbound)
                                .lineLimit(1)
                            Spacer()
                            Image(systemName: "chevron.up.chevron.down")
                        }
                    }
                    .buttonStyle(.borderedProminent)
                    .tint(.indigo)

                    if outboundQuickTokens.isEmpty == false {
                        QuickTokenRow(title: "固定目标快捷", tokens: outboundQuickTokens) { token in
                            rule.outbound = token
                        }
                    }
                }

                Spacer()
            }
            .padding(16)
            .navigationTitle("编辑 Route")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .confirmationAction) {
                    Button("完成") {
                        dismiss()
                    }
                }
            }
        }
    }

    private var outboundQuickTokens: [String] {
        let builtIns = Set(builtInOutboundTokens)
        return outboundChoices.filter { builtIns.contains($0) }
    }
}

private struct RouteMatcherComposerSheet: View {
    let matcherKind: DAERouteMatcherKind
    let outboundChoices: [String]
    @Binding var matcherInput: String
    @Binding var selectedOutbound: String
    let onConfirm: (String, String) -> Void
    @Environment(\.dismiss) private var dismiss
    private let builtInOutboundTokens = ["direct", "block", "must_rules"]

    private var quickTokens: [String] {
        switch matcherKind {
        case .pname:
            return ["NetworkManager", "openvpn", "dae"]
        case .dip:
            return ["geoip:private", "geoip:cn", "224.0.0.0/3"]
        case .domain:
            return ["geosite:cn", "keyword:example", "suffix:.cn"]
        case .l4proto:
            return ["tcp", "udp"]
        case .dport:
            return ["443", "53", "80"]
        case .sport:
            return ["1024-65535"]
        case .process:
            return ["dae", "openvpn", "clash"]
        case .custom:
            return []
        }
    }

    private var matcherPreview: String {
        let value = matcherInput.trimmingCharacters(in: .whitespacesAndNewlines)
        guard value.isEmpty == false else {
            return ""
        }
        if matcherKind == .custom {
            return value
        }
        let functionName = matcherKind == .process ? "process_name" : matcherKind.rawValue
        return "\(functionName)(\(value))"
    }

    var body: some View {
        NavigationStack {
            VStack(alignment: .leading, spacing: 12) {
                Text("Matcher: \(matcherKind.title)")
                    .font(.headline)

                if matcherKind == .custom {
                    TextEditor(text: $matcherInput)
                        .frame(minHeight: 110)
                        .font(.system(.footnote, design: .monospaced))
                        .scrollContentBackground(.hidden)
                        .padding(8)
                        .background(
                            RoundedRectangle(cornerRadius: 10)
                                .fill(Color.black.opacity(0.12))
                        )
                } else {
                    TextField(matcherKind.placeholder, text: $matcherInput, axis: .vertical)
                        .lineLimit(2 ... 6)
                        .textInputAutocapitalization(.never)
                        .autocorrectionDisabled()
                        .textFieldStyle(.roundedBorder)
                }

                if quickTokens.isEmpty == false {
                    QuickTokenRow(title: "快速输入", tokens: quickTokens) { token in
                        matcherInput = token
                    }
                }

                VStack(alignment: .leading, spacing: 6) {
                    Text("出站目标")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                    Menu {
                        ForEach(outboundChoices, id: \.self) { outbound in
                            Button(outbound) {
                                selectedOutbound = outbound
                            }
                        }
                    } label: {
                        HStack {
                            Text(selectedOutbound.isEmpty ? "请选择目标" : selectedOutbound)
                                .lineLimit(1)
                            Spacer()
                            Image(systemName: "chevron.up.chevron.down")
                        }
                    }
                    .buttonStyle(.borderedProminent)
                    .tint(.indigo)

                    if outboundQuickTokens.isEmpty == false {
                        QuickTokenRow(title: "固定目标快捷", tokens: outboundQuickTokens) { token in
                            selectedOutbound = token
                        }
                    }
                }

                if matcherPreview.isEmpty == false {
                    Text("预览: \(matcherPreview) -> \(selectedOutbound)")
                        .font(.footnote)
                        .foregroundStyle(.secondary)
                }

                Spacer()
            }
            .padding(16)
            .navigationTitle("新增 Route")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("取消") {
                        dismiss()
                    }
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button("添加") {
                        onConfirm(matcherPreview, selectedOutbound)
                        dismiss()
                    }
                    .disabled(matcherPreview.isEmpty || selectedOutbound.isEmpty)
                }
            }
        }
    }

    private var outboundQuickTokens: [String] {
        let builtIns = Set(builtInOutboundTokens)
        return outboundChoices.filter { builtIns.contains($0) }
    }
}

private struct QuickTokenRow: View {
    let title: String
    let tokens: [String]
    let onTap: (String) -> Void

    private var columns: [GridItem] {
        [GridItem(.adaptive(minimum: 120), spacing: 8, alignment: .leading)]
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            Text(title)
                .font(.caption2)
                .foregroundStyle(.secondary)
            LazyVGrid(columns: columns, alignment: .leading, spacing: 8) {
                ForEach(tokens, id: \.self) { token in
                    Button {
                        onTap(token)
                    } label: {
                        Text(token)
                            .font(.caption)
                            .multilineTextAlignment(.leading)
                            .lineLimit(3)
                            .frame(maxWidth: .infinity, alignment: .leading)
                    }
                    .buttonStyle(.bordered)
                }
            }
            .padding(.vertical, 2)
        }
    }
}

private struct RouteRuleDropDelegate: DropDelegate {
    let targetID: UUID
    @Binding var rules: [DAERouteRule]
    @Binding var draggingID: UUID?

    func dropEntered(info: DropInfo) {
        guard let draggingID, draggingID != targetID else {
            return
        }
        guard let from = rules.firstIndex(where: { $0.id == draggingID }),
              let to = rules.firstIndex(where: { $0.id == targetID }) else {
            return
        }
        if from != to {
            withAnimation {
                rules.move(fromOffsets: IndexSet(integer: from), toOffset: to > from ? to + 1 : to)
            }
        }
    }

    func dropUpdated(info: DropInfo) -> DropProposal? {
        DropProposal(operation: .move)
    }

    func performDrop(info: DropInfo) -> Bool {
        draggingID = nil
        return true
    }
}

private struct RawConfigEditorSheet: View {
    @EnvironmentObject private var model: AppModel

    var body: some View {
        NavigationStack {
            VStack(spacing: 12) {
                Picker("Section", selection: $model.selectedSection) {
                    ForEach(DAEConfigSection.allCases) { section in
                        Text(section.title).tag(section)
                    }
                }
                .pickerStyle(.segmented)
                .onChange(of: model.selectedSection) { _, _ in
                    model.loadConfig()
                }

                Text(model.selectedSection.path)
                    .font(.caption2)
                    .foregroundStyle(.secondary)
                    .frame(maxWidth: .infinity, alignment: .leading)

                TextEditor(text: $model.configText)
                    .font(.system(.footnote, design: .monospaced))
                    .scrollContentBackground(.hidden)
                    .padding(8)
                    .background(
                        RoundedRectangle(cornerRadius: 12)
                            .fill(Color.black.opacity(0.12))
                    )
                    .onChange(of: model.configText) { _, _ in
                        model.markConfigDirty()
                    }

                HStack(spacing: 10) {
                    Button("重载服务") {
                        model.hotReload()
                    }
                    .buttonStyle(.borderedProminent)
                    .tint(.red)
                    .disabled(model.isLoading)

                    Button("保存并重载") {
                        model.saveConfig()
                    }
                    .buttonStyle(.borderedProminent)
                    .disabled(model.isLoading || !model.configDirty)
                }

                if let error = model.errorMessage {
                    Text(error)
                        .font(.footnote)
                        .foregroundStyle(.red)
                        .frame(maxWidth: .infinity, alignment: .leading)
                }
            }
            .padding(16)
            .navigationTitle("直接编辑配置")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("关闭") {
                        model.showingRawEditor = false
                    }
                }
            }
            .task {
                model.loadConfig()
            }
        }
    }
}

private struct SettingsView: View {
    @EnvironmentObject private var model: AppModel

    var body: some View {
        ScrollView {
            VStack(spacing: 16) {
                VStack(alignment: .leading, spacing: 8) {
                    Text("设置")
                        .font(.system(size: 32, weight: .heavy, design: .rounded))
                    Text("已登录后，登录信息在这里管理")
                        .font(.footnote)
                        .foregroundStyle(.secondary)
                }
                .frame(maxWidth: .infinity, alignment: .leading)

                GlassCard {
                    VStack(alignment: .leading, spacing: 12) {
                        Text("登录信息")
                            .font(.headline)

                        TextField("路由器地址，例如 http://10.0.0.1", text: $model.routerAddress)
                            .textInputAutocapitalization(.never)
                            .keyboardType(.URL)
                            .autocorrectionDisabled()
                            .textFieldStyle(.roundedBorder)

                        TextField("用户名", text: $model.username)
                            .textInputAutocapitalization(.never)
                            .autocorrectionDisabled()
                            .textFieldStyle(.roundedBorder)

                        SecureField("密码", text: $model.password)
                            .textFieldStyle(.roundedBorder)

                        Toggle("允许自签名 TLS（内网常用）", isOn: $model.allowInsecureTLS)
                            .font(.footnote)

                        HStack(spacing: 10) {
                            Button("保存并重连") {
                                model.connect()
                            }
                            .buttonStyle(.borderedProminent)
                            .disabled(model.isLoading)

                            Button("断开登录") {
                                model.disconnect()
                            }
                            .buttonStyle(.bordered)
                            .disabled(model.isLoading)

                            if model.isLoading {
                                ProgressView()
                            }
                        }

                        if let error = model.errorMessage {
                            Text(error)
                                .font(.footnote)
                                .foregroundStyle(.red)
                        }
                    }
                }
            }
            .padding(.horizontal, 16)
            .padding(.top, 24)
            .padding(.bottom, 40)
        }
    }
}

private struct OptionTextField: View {
    let title: String
    let placeholder: String
    @Binding var text: String
    let helpText: String?

    init(
        title: String,
        placeholder: String,
        text: Binding<String>,
        helpText: String? = nil
    ) {
        self.title = title
        self.placeholder = placeholder
        _text = text
        self.helpText = helpText
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            OptionFieldTitle(title: title, helpText: helpText)
            TextField(placeholder, text: $text)
                .textInputAutocapitalization(.never)
                .autocorrectionDisabled()
                .textFieldStyle(.roundedBorder)
        }
    }
}

private struct OptionToggleField: View {
    let title: String
    @Binding var isOn: Bool
    let helpText: String?

    var body: some View {
        HStack(alignment: .center, spacing: 10) {
            OptionFieldTitle(title: title, helpText: helpText)
            Spacer()
            Toggle("", isOn: $isOn)
                .labelsHidden()
        }
    }
}

private struct OptionMenuField<SelectionValue: Hashable, Content: View>: View {
    let title: String
    @Binding var selection: SelectionValue
    let helpText: String?
    let content: () -> Content

    init(
        title: String,
        selection: Binding<SelectionValue>,
        helpText: String? = nil,
        @ViewBuilder content: @escaping () -> Content
    ) {
        self.title = title
        _selection = selection
        self.helpText = helpText
        self.content = content
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            OptionFieldTitle(title: title, helpText: helpText)
            Picker("", selection: $selection) {
                content()
            }
            .labelsHidden()
            .pickerStyle(.menu)
            .frame(maxWidth: .infinity, alignment: .leading)
        }
    }
}

private struct OptionFieldTitle: View {
    let title: String
    let helpText: String?
    @State private var showingHelp = false

    var body: some View {
        HStack(spacing: 4) {
            Text(title)
                .font(.subheadline.weight(.semibold))
                .foregroundStyle(.secondary)
            if let helpText, helpText.isEmpty == false {
                Button {
                    showingHelp = true
                } label: {
                    Image(systemName: "questionmark.circle")
                        .font(.body)
                        .foregroundStyle(.secondary)
                }
                .buttonStyle(.plain)
                .popover(isPresented: $showingHelp, attachmentAnchor: .point(.bottom), arrowEdge: .top) {
                    ScrollView {
                        VStack(alignment: .leading, spacing: 10) {
                            Text(title)
                                .font(.headline)
                            Text(helpText)
                                .font(.body)
                                .multilineTextAlignment(.leading)
                                .lineLimit(nil)
                                .fixedSize(horizontal: false, vertical: true)
                            Link("来源: example.dae", destination: GlobalOptionHelp.sourceURL)
                                .font(.subheadline)
                        }
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .padding(12)
                    }
                    .frame(minWidth: 260, idealWidth: 300, maxWidth: 320, minHeight: 100, maxHeight: 320)
                    .presentationCompactAdaptation(.popover)
                }
            }
        }
    }
}

private enum GlobalOptionHelp {
    static let sourceURL = URL(string: "https://github.com/daeuniverse/dae/blob/main/example.dae")!

    static let translations: [String: String] = [
        "tproxy_port": "tproxy 监听端口（不是 HTTP/SOCKS 端口），主要给 eBPF 程序使用，通常不需要改。",
        "tproxy_port_protect": "是否保护 tproxy 端口免受非预期流量访问。关闭后可配合自定义 iptables tproxy 规则。",
        "pprof_port": "非 0 时启用 pprof 调试端口。",
        "so_mark_from_dae": "非 0 时给 dae 发出的流量打 SO_MARK，用于避免与 iptables tproxy 规则形成流量回环。",
        "log_level": "日志级别：error / warn / info / debug / trace。",
        "disable_waiting_network": "拉取订阅前不等待网络就绪。",
        "wan_interface": "绑定的 WAN 接口。可用逗号分隔多个接口；auto 表示自动检测。",
        "auto_config_kernel_parameter": "自动配置 Linux 内核参数（如 ip_forward、send_redirects）。",
        "tcp_check_url": "节点 TCP 连通性检测目标。第一个为 URL，后续可附 IP。",
        "tcp_check_http_method": "访问 tcp_check_url 时使用的 HTTP 方法，默认 HEAD。",
        "udp_check_dns": "用于检测节点 UDP 连通性的 DNS 地址（也可用于部分 TCP DNS 检测）。",
        "check_interval": "节点连通性检测间隔。",
        "check_tolerance": "仅当新延迟 <= 旧延迟 - 容差 时才切换节点。",
        "dial_mode": "代理拨号模式：ip / domain / domain+ / domain++。",
        "allow_insecure": "允许不安全 TLS 证书，不建议开启，除非确有需要。",
        "sniffing_timeout": "嗅探首包等待超时；dial_mode=ip 时固定为 0。",
        "tls_implementation": "TLS 实现：tls（Go 标准库）或 utls（可模拟浏览器握手）。",
        "utls_imitate": "uTLS 的 ClientHello 模拟标识，仅在 tls_implementation=utls 时生效。",
        "tls_fragment": "开启后会分片发送 ClientHello，用于对抗部分 SNI 封锁。",
        "tls_fragment_length": "TLS 分片长度范围（字节），每片随机取值。",
        "tls_fragment_interval": "TLS 分片间隔范围（毫秒），每片随机取值。",
        "mptcp": "启用 MPTCP，多路径场景下可用于负载均衡和故障切换（需节点支持）。",
        "bandwidth_max_tx": "上行最大带宽提示值，部分协议（如 Hysteria2）可利用该信息优化表现。",
        "bandwidth_max_rx": "下行最大带宽提示值，部分协议（如 Hysteria2）可利用该信息优化表现。",
        "fallback_resolver": "当系统 DNS 解析失败时使用的兜底 DNS 服务器。"
    ]

    static func text(for key: String) -> String {
        if let text = translations[key] {
            return text
        }
        return "该参数说明来源于 dae 官方 example.dae。"
    }
}

private struct InfoKVRow: View {
    let key: String
    let value: String

    var body: some View {
        HStack(alignment: .firstTextBaseline) {
            Text(key)
                .font(.caption)
                .foregroundStyle(.secondary)
                .frame(width: 74, alignment: .leading)
            Text(value)
                .font(.subheadline)
                .frame(maxWidth: .infinity, alignment: .leading)
        }
    }
}

private struct StatusPill: View {
    let title: String
    let value: String
    let good: Bool

    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            Text(title)
                .font(.caption)
                .foregroundStyle(.secondary)
            Text(value)
                .font(.subheadline.weight(.bold))
                .foregroundStyle(good ? .green : .red)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(12)
        .background(
            RoundedRectangle(cornerRadius: 12, style: .continuous)
                .fill(.thinMaterial)
        )
    }
}

private struct LiquidBackground: View {
    var body: some View {
        ZStack {
            LinearGradient(
                colors: [
                    Color(red: 0.08, green: 0.13, blue: 0.24),
                    Color(red: 0.02, green: 0.31, blue: 0.36),
                    Color(red: 0.03, green: 0.08, blue: 0.16)
                ],
                startPoint: .topLeading,
                endPoint: .bottomTrailing
            )
            Circle()
                .fill(Color.cyan.opacity(0.45))
                .frame(width: 300, height: 300)
                .blur(radius: 40)
                .offset(x: 150, y: -280)
            Circle()
                .fill(Color.blue.opacity(0.32))
                .frame(width: 360, height: 360)
                .blur(radius: 44)
                .offset(x: -180, y: 240)
            Circle()
                .fill(Color.white.opacity(0.20))
                .frame(width: 250, height: 250)
                .blur(radius: 58)
                .offset(x: -120, y: -300)
        }
    }
}
