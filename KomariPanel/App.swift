import SwiftUI
import Charts
import Combine

@main
struct KomariPanelApp: App {
    @StateObject private var store = PanelStore()
    @AppStorage("accentHex") private var hex = "#007AFF"
    var body: some Scene { WindowGroup { AppAppearanceRoot().environmentObject(store) } }
}

struct RootView: View {
    @EnvironmentObject private var store: PanelStore
    @Environment(\.scenePhase) private var phase
    var body: some View {
        TabView {
            DashboardView().tabItem { Label("总览", systemImage: "square.grid.2x2") }
            Group {
                if let api = store.api { NavigationStack { ManagementView(api: api, nodes: store.nodes) }.id(store.selected) }
                else { EmptyState("尚未连接", systemImage: "network.slash", description: Text("Komari 支持管理；哪吒与 DStatus 当前提供只读监控。")) }
            }
            .tabItem { Label("管理", systemImage: "slider.horizontal.3") }
            PanelsView().tabItem { Label("面板", systemImage: "server.rack") }
        }
        .task(id: store.selected) { await store.connect() }
        .task(id: phase) {
            guard phase == .active else { return }
            while !Task.isCancelled {
                do { try await Task.sleep(for: .seconds(5)) } catch { return }
                await store.refresh()
            }
        }
    }
}

@MainActor
struct DashboardView: View {
    @EnvironmentObject private var store: PanelStore
    @State private var search = ""
    @State private var onlineOnly = false
    @Environment(\.accessibilityReduceMotion) private var systemReduceMotion
    @Environment(\.scenePhase) private var scenePhase
    @FocusState private var searchFocused: Bool
    @AppStorage("dashboardPreferences") private var preferencesData = Data()
    @State private var managingHiddenNodes = false
    @State private var arrangingNodes = false
    @Namespace private var nodeTransition
    @State private var nodePath: [Expansion] = []

    private var preferences: DashboardPreferences {
        (try? JSONDecoder().decode([String: DashboardPreferences].self, from: preferencesData))?[store.selected] ?? DashboardPreferences()
    }

    private func updatePreferences(_ change: (inout DashboardPreferences) -> Void) {
        var all = (try? JSONDecoder().decode([String: DashboardPreferences].self, from: preferencesData)) ?? [:]
        var current = all[store.selected] ?? DashboardPreferences()
        change(&current)
        all[store.selected] = current
        if let data = try? JSONEncoder().encode(all) { preferencesData = data }
    }

    private var allNodeIDs: [String] {
        var seen = Set<String>()
        return dashboardNodes.map { $0["uuid"].string }.filter { !$0.isEmpty && seen.insert($0).inserted }
    }

    private var orderedIDs: [String] {
        let validIDs = Set(allNodeIDs)
        var seen = Set<String>()
        return preferences.orderedNodes(dashboardNodes).map { $0["uuid"].string }
            .filter { validIDs.contains($0) && seen.insert($0).inserted }
    }

    private var nodeOrderSheet: some View {
        NavigationStack {
            List {
                Section {
                    ForEach(orderedIDs, id: \.self) { id in
                        Text(shown(nodesByID[id]?["name"] ?? .null))
                            .accessibilityIdentifier("sortNode-\(id)")
                    }
                    .onMove { source, destination in
                        var ids = orderedIDs
                        ids.move(fromOffsets: source, toOffset: destination)
                        updatePreferences { $0.orderedNodeIDs = ids }
                    }
                } footer: {
                    Text("拖动右侧手柄调整顺序，仅保存在本机当前面板。隐藏的节点也保留排序位置。")
                }
            }
            .environment(\.editMode, .constant(.active))
            .navigationTitle("自定义排序")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .confirmationAction) {
                    Button("完成") { arrangingNodes = false }
                        .accessibilityIdentifier("doneOrderingNodes")
                }
            }
        }
    }

    private var hiddenNodesSheet: some View {
        NavigationStack {
            List {
                Section {
                    Button("恢复全部节点") { updatePreferences { $0.hiddenNodeIDs.removeAll() } }
                        .accessibilityIdentifier("restoreAllNodes")
                    ForEach(allNodeIDs, id: \.self) { id in
                        Toggle(isOn: Binding(get: { preferences.hiddenNodeIDs.contains(id) }, set: { hidden in
                            updatePreferences {
                                if hidden { $0.hiddenNodeIDs.insert(id) } else { $0.hiddenNodeIDs.remove(id) }
                            }
                        })) { Text(shown(nodesByID[id]?["name"] ?? .null)) }
                            .accessibilityIdentifier("hideNode-\(id)")
                    }
                } footer: {
                    Text("开启表示在总览隐藏；仅保存在本机当前面板，不修改服务器。统计仍包含全部节点。")
                }
            }
            .navigationTitle("隐藏节点")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar { ToolbarItem(placement: .confirmationAction) { Button("完成") { managingHiddenNodes = false }.accessibilityIdentifier("doneHidingNodes") } }
        }
    }

    private var reduceMotion: Bool {
        #if DEBUG
        if ProcessInfo.processInfo.arguments.contains("--ui-test-reduce-motion") { return true }
        #endif
        return systemReduceMotion
    }

    private var dashboardNodes: [JSON] {
        #if DEBUG
        // UI automation only: no metrics, network, persistence, or production data mutation.
        if ProcessInfo.processInfo.arguments.contains("--ui-test-node-expansion") {
            return [2, 1, 3, 4, 5, 6, 7, 8, 9, 10, 11, 12].map { index in
                .object(["uuid": .string("ui-test-\(index)"),
                         "name": .string(String(format: NSLocalizedString("UI 测试节点 %ld", comment: "UI test fixture name"), index)),
                         "group": .string(NSLocalizedString("仅用于 UI 自动化", comment: "UI test fixture group"))])
            }
        }
        #endif
        return store.nodes
    }

    private struct DashboardNode: Identifiable {
        let id: String
        let value: JSON
    }

    private struct Expansion: Hashable {
        let id: String
        let panelID: String
    }

    private var nodesByID: [String: JSON] {
        Dictionary(dashboardNodes.compactMap { node in
            let id = node["uuid"].string
            return id.isEmpty ? nil : (id, node)
        }, uniquingKeysWith: { first, _ in first })
    }

    private var visibleNodes: [DashboardNode] {
        let nodes = nodesByID
        var seen = Set<String>()
        return filtered.compactMap { node in
            let id = node["uuid"].string
            guard seen.insert(id).inserted, let n = nodes[id] else { return nil }
            return DashboardNode(id: id, value: n)
        }
    }

    private func expand(_ item: DashboardNode) {
        guard nodePath.isEmpty else { return }
        searchFocused = false
        nodePath.append(Expansion(id: item.id, panelID: store.selected))
    }

    var currentPanelName: String {
        store.panels.first(where: { $0.id == store.selected })?.name ?? "Monitor Panel"
    }

    var totalCount: Int { dashboardNodes.count }
    var onlineCount: Int {
        dashboardNodes.filter { store.statuses[$0["uuid"].string]["online"].bool }.count
    }
    var offlineCount: Int {
        totalCount - onlineCount
    }

    var totalNetUpSpeed: Double {
        dashboardNodes.reduce(0) { acc, node in
            let v = store.statuses[node["uuid"].string]["net_out"].number
            return acc + (v > 0 ? v : 0)
        }
    }

    var totalNetDownSpeed: Double {
        dashboardNodes.reduce(0) { acc, node in
            let v = store.statuses[node["uuid"].string]["net_in"].number
            return acc + (v > 0 ? v : 0)
        }
    }

    var filtered: [JSON] {
        preferences.visibleNodes(dashboardNodes).filter { node in
            (!onlineOnly || store.statuses[node["uuid"].string]["online"].bool) && (search.isEmpty || ["name", "group", "tags", "ipv4"].contains { node[$0].string.localizedCaseInsensitiveContains(search) })
        }
    }

    var body: some View {
        NavigationStack(path: $nodePath) {
            overview
                .background(Color(.systemGroupedBackground))
                .navigationTitle("总览")
                .navigationBarTitleDisplayMode(.inline)
                .navigationDestination(for: Expansion.self) { selection in
                    if selection.panelID == store.selected, let node = nodesByID[selection.id] {
                        NodeDetail(api: store.api, monitor: store.monitor, node: node)
                            .nodeZoomDestination(id: selection, in: nodeTransition, reduceMotion: reduceMotion)
                    } else {
                        EmptyState("暂无匹配节点", systemImage: "server.rack")
                    }
                }
                .toolbar {
                    ToolbarItemGroup(placement: .navigationBarTrailing) {
                        Button { searchFocused = false; arrangingNodes = true } label: {
                            Label("自定义排序", systemImage: "arrow.up.arrow.down")
                        }
                        .accessibilityIdentifier("dashboardSort")
                        Button { searchFocused = false; managingHiddenNodes = true } label: {
                            Label("隐藏节点", systemImage: "eye.slash")
                        }
                        .accessibilityIdentifier("dashboardHiddenNodes")
                    }
                }
                .sheet(isPresented: $managingHiddenNodes) { hiddenNodesSheet }
                .sheet(isPresented: $arrangingNodes) { nodeOrderSheet }
                .onChange(of: store.selected) { _ in
                    managingHiddenNodes = false
                    arrangingNodes = false
                    nodePath.removeAll()
                }
        }
    }

    private func heroCard(_ node: JSON) -> some View {
        RichNodeCard(node: node, status: store.statuses[node["uuid"].string], fresh: store.updated != nil)
    }

    private var overview: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 16) {
                HStack(spacing: 8) {
                    Image(systemName: "magnifyingglass").foregroundStyle(.secondary)
                    TextField("搜索节点名、分组或 IP", text: $search)
                        .focused($searchFocused)
                        .submitLabel(.search)
                        .onSubmit { searchFocused = false }
                        .textInputAutocapitalization(.never)
                        .autocorrectionDisabled()
                        .accessibilityIdentifier("dashboardSearch")
                    if !search.isEmpty {
                        Button { search = "" } label: { Image(systemName: "xmark.circle.fill") }
                            .frame(minWidth: 44, minHeight: 44)
                            .accessibilityLabel("清除搜索")
                            .accessibilityIdentifier("clearDashboardSearch")
                    }
                }
                .padding(.horizontal, 12)
                .frame(minHeight: 44)
                .background(Color(.secondarySystemGroupedBackground), in: RoundedRectangle(cornerRadius: 12))
                VStack(alignment: .leading, spacing: 16) {
                    VStack(alignment: .leading, spacing: 14) {
                        HStack(alignment: .firstTextBaseline) {
                            VStack(alignment: .leading, spacing: 4) {
                                Text(currentPanelName).font(.title2.bold())
                                HStack(spacing: 6) {
                                    Circle()
                                        .fill(store.updated == nil ? Color.orange : Color.green)
                                        .frame(width: 8, height: 8)
                                    Text(LocalizedStringKey(store.updated == nil ? "等待连接或未就绪" : "每 5 秒刷新 · 运行正常"))
                                        .font(.subheadline)
                                        .foregroundStyle(.secondary)
                                }
                            }
                            Spacer()
                            Button { Task { await store.connect() } } label: {
                                Image(systemName: "arrow.clockwise")
                                    .font(.body.weight(.semibold))
                            }
                            .buttonStyle(CompatibleGlassButtonStyle())
                            .disabled(store.loading)
                        }

                        if !dashboardNodes.isEmpty {
                            HStack(spacing: 10) {
                                StatBadge(title: "全部", count: "\(totalCount)", color: .primary)
                                StatBadge(title: "在线", count: "\(onlineCount)", color: .green)
                                StatBadge(title: "离线", count: "\(offlineCount)", color: offlineCount > 0 ? .orange : .secondary)
                                Divider().frame(height: 24)
                                VStack(alignment: .leading, spacing: 2) {
                                    HStack(spacing: 4) {
                                        Image(systemName: "arrow.up").font(.caption2).foregroundStyle(.green)
                                        Text(ByteCountFormatter.string(fromByteCount: Int64(totalNetUpSpeed), countStyle: .binary) + "/s")
                                            .font(.caption.monospacedDigit().weight(.medium))
                                    }
                                    HStack(spacing: 4) {
                                        Image(systemName: "arrow.down").font(.caption2).foregroundStyle(.blue)
                                        Text(ByteCountFormatter.string(fromByteCount: Int64(totalNetDownSpeed), countStyle: .binary) + "/s")
                                            .font(.caption.monospacedDigit().weight(.medium))
                                    }
                                }
                                .frame(maxWidth: .infinity, alignment: .trailing)
                            }
                            .padding(.horizontal, 14)
                            .padding(.vertical, 10)
                            .background(Color(.secondarySystemGroupedBackground), in: RoundedRectangle(cornerRadius: 14))
                        }
                    }

                    HStack {
                        Button {
                            onlineOnly.toggle()
                        } label: {
                            HStack(spacing: 6) {
                                Image(systemName: onlineOnly ? "line.3.horizontal.decrease.circle.fill" : "line.3.horizontal.decrease.circle")
                                if onlineOnly { Text("仅看在线 (\(onlineCount))") }
                                else { Text("全部节点 (\(totalCount))") }
                            }
                            .font(.subheadline.weight(.medium))
                            .foregroundStyle(onlineOnly ? Color.accentColor : .secondary)
                        }
                        .frame(minHeight: 44)
                        .accessibilityIdentifier("dashboardOnlineFilter")
                        Spacer()
                    }

                    if let error = store.error {
                        Label(error, systemImage: "exclamationmark.triangle")
                            .foregroundStyle(.orange)
                            .textSelection(.enabled)
                    }

                    if store.loading {
                        ProgressView("正在同步面板状态…").frame(maxWidth: .infinity).padding(.vertical, 20)
                    }

                    if filtered.isEmpty && !store.loading {
                        EmptyState(dashboardNodes.isEmpty && store.panels.isEmpty ? "添加你的第一个面板" : "暂无匹配节点", systemImage: "server.rack", description: Text(LocalizedStringKey(dashboardNodes.isEmpty ? "在「面板」页选择后端并输入面板地址与凭据。" : "试试清除搜索、切换在线筛选，或通过右上角「隐藏节点」恢复显示。")))
                    }
                }

                LazyVStack(spacing: 12) {
                    ForEach(visibleNodes) { item in
                        Button { expand(item) } label: {
                            heroCard(item.value)
                        }
                        .buttonStyle(.plain)
                        .nodeZoomSource(id: Expansion(id: item.id, panelID: store.selected),
                                        in: nodeTransition, reduceMotion: reduceMotion)
                        .accessibilityIdentifier("nodeCard-\(item.id)")
                        .accessibilityHint("展开节点详情")
                    }
                }
            }
            .padding(.horizontal, 16)
            .padding(.vertical, 12)
        }
        .scrollDismissesKeyboard(.interactively)
        .refreshable { await store.connect() }
    }
}

struct StatBadge: View {
    let title: LocalizedStringKey
    let count: String
    let color: Color
    var body: some View {
        HStack(spacing: 4) {
            Text(title).font(.caption2).foregroundStyle(.secondary)
            Text(count).font(.subheadline.monospacedDigit().weight(.semibold)).foregroundStyle(color)
        }
    }
}
func shown(_ value: JSON) -> String { value == .null || value.string.isEmpty ? "—" : value.string }
func percent(_ value: JSON) -> String { value == .null ? "—" : String(format: "%.1f%%", value.number) }
func bytes(_ value: JSON) -> String { value == .null ? "—" : ByteCountFormatter.string(fromByteCount: Int64(value.number), countStyle: .binary) }
struct NodeCard: View {
    let node: JSON
    let status: JSON
    let fresh: Bool
    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            HStack {
                Image(systemName: "server.rack").font(.title2).foregroundStyle(Color.accentColor)
                VStack(alignment: .leading) { Text(shown(node["name"])).font(.headline); Text([node["region"].string,node["group"].string].filter { !$0.isEmpty }.joined(separator: " · ")).font(.caption).foregroundStyle(.secondary) }
                Spacer()
                Label(LocalizedStringKey(!fresh ? "未知" : status["online"] == .null ? "未上报" : status["online"].bool ? "在线" : "离线"), systemImage: "circle.fill").font(.caption).foregroundStyle(!fresh ? Color.secondary : status["online"].bool ? Color.green : Color.orange)
            }
            HStack {
                metric("CPU", value: fresh ? percent(status["cpu"]) : "—")
                Spacer()
                metric("内存", value: fresh ? bytes(status["ram"]) : "—")
                Spacer()
                metric("磁盘", value: fresh ? bytes(status["disk"]) : "—")
            }
            HStack { Label(fresh ? bytes(status["net_in"]) + "/s" : "—", systemImage: "arrow.down"); Spacer(); Label(fresh ? bytes(status["net_out"]) + "/s" : "—", systemImage: "arrow.up") }.font(.caption).foregroundStyle(.secondary).monospacedDigit()
        }.padding(18).background(Color(.secondarySystemGroupedBackground), in: RoundedRectangle(cornerRadius: 24))
    }
    func metric(_ name: LocalizedStringKey, value: String) -> some View { VStack(alignment: .leading, spacing: 5) { Text(name).font(.caption).foregroundStyle(.secondary); Text(value).font(.subheadline.weight(.semibold)).monospacedDigit() } }
}

struct PanelsView: View {
    @EnvironmentObject private var store: PanelStore
    @State private var editor = false
    @State private var editing: Panel?
    @State private var removing: Panel?
    @State private var error: String?
    var body: some View {
        NavigationStack {
            List {
                Section("连接") {
                    ForEach(store.panels) { p in
                        Button { store.selected = p.id } label: {
                            HStack { VStack(alignment: .leading) { Text(p.name).foregroundStyle(.primary); Text(p.address).font(.caption).foregroundStyle(.secondary) }; Spacer(); if store.selected == p.id { Image(systemName: "checkmark.circle.fill").foregroundStyle(Color.accentColor) } }
                        }
                        .swipeActions { Button("移除", role: .destructive) { removing = p }; Button("编辑") { editing = p; editor = true }.tint(.blue) }
                        .contextMenu { Button("编辑") { editing = p; editor = true }; Button("移除", role: .destructive) { removing = p } }
                    }
                    Button { editing = nil; editor = true } label: { Label("添加面板", systemImage: "plus") }.accessibilityIdentifier("addPanel")
                }
                Section("应用") { NavigationLink("外观") { AppearanceView() }; NavigationLink("关于") { AboutView() } }
                if let error { Section { Text(error).foregroundStyle(.red) } }
            }.navigationTitle("面板")
            .sheet(isPresented: $editor) { PanelEditor(existing: editing) }
            .confirmationDialog("移除 \(removing?.name ?? "")？仅删除本机连接及 Keychain 凭据，不删除服务器。", isPresented: Binding(get: { removing != nil }, set: { if !$0 { removing = nil } }), titleVisibility: .visible) {
                Button("确认移除", role: .destructive) {
                    guard let p = removing else { return }
                    do { try Keychain.delete(account: p.id); store.panels.removeAll { $0.id == p.id }; if store.selected == p.id { store.selected = store.panels.first?.id ?? "" }; try store.persist() } catch { self.error = error.localizedDescription }
                    removing = nil
                }
            }
        }
    }
}
struct PanelEditor: View {
    @EnvironmentObject private var store: PanelStore
    @Environment(\.dismiss) private var dismiss
    let existing: Panel?
    @State private var name = ""
    @State private var address = ""
    @State private var key = ""
    @State private var backend = BackendKind.komari
    @State private var allowHTTP = false
    @State private var busy = false
    @State private var error: String?
    var body: some View {
        NavigationStack {
            Form {
                Section("后端") { Picker("类型", selection: $backend) { ForEach(BackendKind.allCases) { Text($0.title).tag($0) } }; Text(LocalizedStringKey(backend == .dstatus ? "DStatus 使用匿名公开只读 API，无需 API key。" : backend == .nezha ? "使用 PAT 或 JWT。只读 PAT 需要 inventory:read 与 server:read 权限。" : backend == .nezhaV0 ? "使用旧版 API Token，认证头不含 Bearer 前缀。" : "使用 Komari 管理员 API key。")).font(.footnote).foregroundStyle(.secondary) }
                Section("连接信息") { TextField("面板名称", text: $name); TextField("https://你的面板地址", text: $address).keyboardType(.URL).textInputAutocapitalization(.never).autocorrectionDisabled(); if backend != .dstatus { SecureField(LocalizedStringKey(existing == nil ? "API key" : "新 API key（留空保持原 key）"), text: $key).textInputAutocapitalization(.never).autocorrectionDisabled() } }
                Section { Toggle("允许不安全 HTTP", isOn: $allowHTTP); if allowHTTP { Text("HTTP 会明文传输管理员 API key，仅在受信任网络使用。").foregroundStyle(.orange) } }
                if let error { Text(error).foregroundStyle(.red) }
                Section { Button { Task { await save() } } label: { HStack { Text("验证并保存"); if busy { Spacer(); ProgressView() } } }.disabled(busy || name.trimmingCharacters(in: .whitespaces).isEmpty || address.isEmpty || (backend != .dstatus && existing == nil && key.isEmpty)) }
            }.navigationTitle(LocalizedStringKey(existing == nil ? "添加面板" : "编辑面板")).navigationBarTitleDisplayMode(.inline)
            .toolbar { ToolbarItem(placement: .cancellationAction) { Button("取消") { dismiss() }.disabled(busy) } }
            .onAppear { if let p = existing { name = p.name; address = p.address; allowHTTP = p.allowHTTP; backend = p.kind } }
        }.interactiveDismissDisabled(busy)
    }
    func save() async {
        busy = true; defer { busy = false }
        do {
            let id = existing?.id ?? UUID().uuidString
            let effective = backend == .dstatus ? "" : key.isEmpty ? try Keychain.load(account: id) : key
            if backend == .komari {
                guard !effective.isEmpty else { throw KomariAPIError.invalidAPIKey }
                let api = try KomariAPI(baseURL: address, apiKey: effective, allowHTTP: allowHTTP)
                _ = try await api.rpc("admin:listClients")
            } else {
                let api = try MonitorAPI(kind: backend, address: address, key: effective, allowHTTP: allowHTTP)
                _ = try await api.snapshot()
            }
            if backend != .dstatus { try Keychain.save(effective, account: id) }
            let p = Panel(id: id, name: name.trimmingCharacters(in: .whitespaces), address: address.trimmingCharacters(in: .whitespacesAndNewlines), allowHTTP: allowHTTP, backend: backend)
            if let index = store.panels.firstIndex(where: { $0.id == id }) { store.panels[index] = p } else { store.panels.append(p) }
            store.selected = id; try store.persist(); await store.connect(); dismiss()
        } catch { self.error = error.localizedDescription }
    }
}

struct NodeDetail: View {
    let api: KomariAPI?
    let monitor: MonitorAPI?
    let node: JSON
    @EnvironmentObject private var store: PanelStore
    @State private var records: [JSON] = []
    @State private var hours = 6
    @State private var field = "cpu"
    @State private var loading = false
    @State private var error: String?
    @State private var historyRequestID = UUID()
    @State private var edit = false
    var status: JSON { store.statuses[node["uuid"].string] }
    // Display labels are separate from the unchanged API metric/schema keys.
    private var fieldTitle: String {
        switch field {
        case "cpu": return "CPU"
        case "ram": return NSLocalizedString("内存", comment: "")
        case "disk": return NSLocalizedString("磁盘", comment: "")
        case "net_in": return NSLocalizedString("下载", comment: "")
        case "net_out": return NSLocalizedString("上传", comment: "")
        case "latency": return NSLocalizedString("延迟", comment: "")
        default: return field
        }
    }
    private var specificationFields: [(key: String, title: String)] {
        [("ipv4", "IPv4"), ("ipv6", "IPv6"),
         ("os", NSLocalizedString("操作系统", comment: "")),
         ("cpu_name", NSLocalizedString("CPU 型号", comment: "")),
         ("arch", NSLocalizedString("架构", comment: "")),
         ("kernel_version", NSLocalizedString("内核版本", comment: "")),
         ("tags", NSLocalizedString("标签", comment: "")),
         ("public_remark", NSLocalizedString("公开备注", comment: ""))]
    }
    var body: some View {
        ScrollView {
            LazyVStack(alignment: .leading, spacing: 16) {
                NodeSpecificationHeroCard(node: node, status: status, fresh: store.updated != nil)
                    .accessibilityElement(children: .contain)
                    .accessibilityIdentifier("expandedNodeCard")
                VStack(alignment: .leading, spacing: 12) {
                    Text("历史指标").font(.title3.bold()).accessibilityIdentifier("nodeHistory")
                    Picker("时间范围", selection: $hours) { Text("1 小时").tag(1); Text("6 小时").tag(6); Text("24 小时").tag(24) }.pickerStyle(.segmented)
                    Picker("指标", selection: $field) { Text("CPU %").tag("cpu"); Text(LocalizedStringKey(monitor?.kind == .nezha || monitor?.kind == .dstatus ? "内存 %" : "内存 GiB")).tag("ram"); Text(LocalizedStringKey(monitor?.kind == .nezha ? "磁盘 %" : "磁盘 GiB")).tag("disk"); Text("下载 MiB/s").tag("net_in"); Text("上传 MiB/s").tag("net_out"); if monitor?.kind == .nezhaV0 { Text("延迟 ms").tag("latency") } }
                    if loading { ProgressView() }
                    else if records.isEmpty { EmptyState("暂无历史记录", systemImage: "chart.xyaxis.line") }
                    else {
                        Chart {
                            ForEach(Array(records.enumerated()), id: \.offset) { _, r in
                                if let date = recordDate(r["time"].string), r[field] != .null {
                                    LineMark(x: .value(NSLocalizedString("时间", comment: ""), date), y: .value(NSLocalizedString("值", comment: ""), chartValue(r))).foregroundStyle(by: .value(NSLocalizedString("目标", comment: ""), r["series"].string.isEmpty ? fieldTitle : r["series"].string))
                                }
                            }
                        }.frame(height: 220).accessibilityLabel("\(fieldTitle) 历史趋势")
                    }
                }.padding(18).background(Color(.secondarySystemGroupedBackground), in: RoundedRectangle(cornerRadius: 24))
                if let error { Text(error).foregroundStyle(.orange).textSelection(.enabled) }
                VStack(spacing: 12) {
                    ForEach(specificationFields, id: \.key) { item in HStack(alignment: .top) { Text(item.title).foregroundStyle(.secondary); Spacer(); Text(shown(node[item.key])).multilineTextAlignment(.trailing).textSelection(.enabled) } }
                }.font(.subheadline).padding(18).background(Color(.secondarySystemGroupedBackground), in: RoundedRectangle(cornerRadius: 24))
                if !status["ping"].object.isEmpty {
                    VStack(alignment: .leading, spacing: 10) {
                        Text("Ping · 最近 1 小时").font(.headline)
                        ForEach(status["ping"].object.keys.sorted(), id: \.self) { id in
                            let p = status["ping"][id]
                            HStack { Text(shown(p["name"])); Spacer(); Text(p["latest"].number < 0 ? NSLocalizedString("丢包", comment: "") : String(localized: "\(Int(p["latest"].number)) ms")); Text(String(format: NSLocalizedString("%.1f%% 丢包", comment: "Packet loss percentage"), p["loss"].number)).foregroundStyle(.secondary) }
                        }
                    }.padding(18).background(Color(.secondarySystemGroupedBackground), in: RoundedRectangle(cornerRadius: 24))
                }
            }.padding(.horizontal, 16).padding(.vertical, 12)
        }
        .accessibilityIdentifier("nodeDetailScroll")
        .background(Color(.systemGroupedBackground)).navigationTitle(shown(node["name"])).navigationBarTitleDisplayMode(.inline)
        .toolbar { if api != nil { Button { edit = true } label: { Label("编辑", systemImage: "pencil") } } }
        .sheet(isPresented: $edit) { if let api { NodeEditor(api: api, node: node) } }
        .task(id: "\(hours)-\(field)") { await load() }
        .refreshable { await load(); await store.refresh() }
    }
    func chartValue(_ r: JSON) -> Double { let value = r[field].number; if (monitor?.kind == .nezha && (field == "ram" || field == "disk")) || (monitor?.kind == .dstatus && field == "ram") { return value }; return field == "ram" || field == "disk" ? value / 1_073_741_824 : field == "net_in" || field == "net_out" ? value / 1_048_576 : value }
    @MainActor func load() async {
        guard !Task.isCancelled else { return }
        let requestID = UUID()
        historyRequestID = requestID
        let requestedHours = hours
        let requestedField = field
        loading = true; error = nil
        defer { if historyRequestID == requestID { loading = false } }
        do {
            let result: [JSON]
            if let monitor {
                result = try await monitor.history(id: node["uuid"].string, field: requestedField, hours: requestedHours)
            } else if let api {
                let response = try await api.rpc("public:getRecordsByUUID", params: .object([
                    "uuid": node["uuid"], "hours": .string(String(requestedHours)), "load_type": .string("all")]))
                result = response["records"].array.sorted { $0["time"].string < $1["time"].string }
            } else { result = [] }
            try Task.checkCancellation()
            guard historyRequestID == requestID, hours == requestedHours, field == requestedField else { return }
            records = result; error = nil
        } catch {
            guard historyRequestID == requestID, hours == requestedHours, field == requestedField,
                  !Task.isCancelled, !RequestFailure.isCancellation(error) else { return }
            records = []; self.error = error.localizedDescription
        }
    }
}
func recordDate(_ string: String) -> Date? { let f = ISO8601DateFormatter(); f.formatOptions = [.withInternetDateTime, .withFractionalSeconds]; return f.date(from: string) ?? ISO8601DateFormatter().date(from: string) }
struct NodeEditor: View {
    let api: KomariAPI
    let node: JSON
    @EnvironmentObject private var store: PanelStore
    @Environment(\.dismiss) private var dismiss
    @State private var name = ""
    @State private var group = ""
    @State private var tags = ""
    @State private var remark = ""
    @State private var hidden = false
    @State private var busy = false
    @State private var error: String?
    var body: some View {
        NavigationStack {
            Form {
                TextField("名称", text: $name); TextField("分组", text: $group); TextField("标签（分号分隔）", text: $tags); TextField("公开备注", text: $remark, axis: .vertical); Toggle("隐藏节点", isOn: $hidden)
                if let error { Text(error).foregroundStyle(.red) }
            }.navigationTitle("编辑节点").toolbar {
                ToolbarItem(placement: .cancellationAction) { Button("取消") { dismiss() }.disabled(busy) }
                ToolbarItem(placement: .confirmationAction) { Button("保存") { Task { await save() } }.disabled(busy || name.isEmpty) }
            }.onAppear { name = node["name"].string; group = node["group"].string; tags = node["tags"].string; remark = node["public_remark"].string; hidden = node["hidden"].bool }
        }.interactiveDismissDisabled(busy)
    }
    func save() async {
        busy = true; defer { busy = false }
        do {
            _ = try await api.rpc("admin:editClient", params: .object(["uuid": node["uuid"], "name": .string(name), "group": .string(group), "tags": .string(tags), "public_remark": .string(remark), "hidden": .bool(hidden)]))
            let saved = try await api.rpc("admin:getClient", params: .object(["uuid": node["uuid"]]))
            guard saved["name"].string == name, saved["group"].string == group, saved["tags"].string == tags, saved["public_remark"].string == remark, saved["hidden"].bool == hidden else { throw NSError(domain: "Komari", code: 1, userInfo: [NSLocalizedDescriptionKey: NSLocalizedString("服务器回读内容不一致，请刷新后检查。", comment: "")] ) }
            await store.connect(); dismiss()
        } catch { self.error = error.localizedDescription }
    }
}
