import SwiftUI
import Foundation

// Contracts: upstream web/rpc/jsonrpc/admin.{ping,notification,task,system}.go.
// Load notifications were removed on main (1.6); their 1.5.1 contract remains
// supported here. A missing RPC method is surfaced, never replaced with demo data.
struct ManagementView: View {
    let api: KomariAPI
    let nodes: [JSON]

    var body: some View {
        List {
            Section("监测与通知") {
                NavigationLink { ManagementRules(api: api, nodes: nodes, kind: .ping) } label: {
                    Label("Ping 任务", systemImage: "waveform.path")
                }
                NavigationLink { ManagementRules(api: api, nodes: nodes, kind: .load) } label: {
                    Label("负载通知", systemImage: "bell.badge")
                }
                NavigationLink { ManagementOffline(api: api, nodes: nodes) } label: {
                    Label("离线通知", systemImage: "network.slash")
                }
            }
            Section("运维") {
                NavigationLink { ManagementCommands(api: api, nodes: nodes) } label: {
                    Label("远程命令与结果", systemImage: "terminal")
                }
                NavigationLink { ManagementLogs(api: api) } label: {
                    Label("审计日志", systemImage: "list.bullet.rectangle")
                }
            }
        }
        .navigationTitle("管理")
    }
}

private enum ManagementRuleKind {
    case ping, load
    var title: String { self == .ping ? "Ping 任务" : "负载通知" }
    var list: String { self == .ping ? "admin:getAllPingTasks" : "admin:getAllLoadNotifications" }
    var add: String { self == .ping ? "admin:addPingTask" : "admin:addLoadNotification" }
    var edit: String { self == .ping ? "admin:editPingTask" : "admin:editLoadNotification" }
    var delete: String { self == .ping ? "admin:deletePingTask" : "admin:deleteLoadNotification" }
    var wrapper: String { self == .ping ? "tasks" : "notifications" }
}

private struct ManagementIssue: LocalizedError {
    let text: String
    var errorDescription: String? { text }
}

private func managementText(_ value: JSON) -> String {
    switch value {
    case .string(let text): return text.isEmpty ? "—" : text
    case .number(let number): return number.formatted()
    case .bool(let bool): return bool ? "是" : "否"
    default: return "—"
    }
}

private func managementNodeName(_ uuid: String, nodes: [JSON]) -> String {
    guard let node = nodes.first(where: { $0["uuid"].string == uuid }) else { return uuid.isEmpty ? "—" : uuid }
    return node["name"].string.isEmpty ? uuid : node["name"].string
}

private func managementClients(_ selected: Set<String>) -> JSON {
    .array(selected.sorted().map { .string($0) })
}

private func managementVerify(_ actual: JSON, fields: [String: JSON]) throws {
    for (key, value) in fields {
        if key == "clients" {
            guard Set(actual[key].array.map { $0.string }) == Set(value.array.map { $0.string }) else {
                throw ManagementIssue(text: "服务器已接受请求，但节点选择回读不一致。请刷新核对，勿重复提交。")
            }
        } else if actual[key] != value {
            throw ManagementIssue(text: "服务器已接受请求，但字段 \(key) 回读不一致。请刷新核对，勿重复提交。")
        }
    }
}

private struct ManagementStatus: View {
    let busy: Bool
    let error: String?
    var body: some View {
        if busy { ProgressView("正在与服务器同步…") }
        if let error {
            Label(error, systemImage: "exclamationmark.triangle")
                .foregroundStyle(.red).font(.footnote).textSelection(.enabled)
        }
    }
}

private struct ManagementNodePicker: View {
    let nodes: [JSON]
    @Binding var selected: Set<String>
    var body: some View {
        Section("选择节点（\(selected.count)）") {
            if nodes.isEmpty { Text("没有可选节点，请返回节点页刷新。").foregroundStyle(.secondary) }
            ForEach(nodes.filter { !$0["uuid"].string.isEmpty }, id: \.self) { node in
                let uuid = node["uuid"].string
                Toggle(isOn: Binding(get: { selected.contains(uuid) }, set: { enabled in
                    if enabled { selected.insert(uuid) } else { selected.remove(uuid) }
                })) {
                    VStack(alignment: .leading) {
                        Text(managementNodeName(uuid, nodes: nodes))
                        Text(uuid).font(.caption2).foregroundStyle(.secondary)
                    }
                }
            }
            ForEach(selected.subtracting(Set(nodes.map { $0["uuid"].string })).sorted(), id: \.self) { uuid in
                Toggle(uuid, isOn: Binding(get: { selected.contains(uuid) }, set: { enabled in
                    if !enabled { selected.remove(uuid) }
                }))
            }
        }
    }
}

private struct ManagementRuleEditorItem: Identifiable {
    let id = UUID()
    let original: JSON?
}

private struct ManagementRules: View {
    let api: KomariAPI
    let nodes: [JSON]
    let kind: ManagementRuleKind
    @State private var rows: [JSON] = []
    @State private var busy = false
    @State private var loaded = false
    @State private var error: String?
    @State private var editor: ManagementRuleEditorItem?
    @State private var deleting: JSON?

    var body: some View {
        List {
            Section { ManagementStatus(busy: busy, error: error) }
            if kind == .load {
                Section { Text("适用于提供负载通知接口的 Komari 1.5.x；1.6 主线已移除此接口，若不支持将显示服务器错误。").font(.footnote).foregroundStyle(.secondary) }
            }
            if loaded && rows.isEmpty { EmptyState("暂无配置", systemImage: "tray") }
            ForEach(rows, id: \.self) { row in
                VStack(alignment: .leading, spacing: 8) {
                    Text(managementText(row["name"])).font(.headline)
                    if kind == .ping {
                        Text("\(managementText(row["type"])) · \(managementText(row["target"])) · \(managementText(row["interval"])) 秒")
                    } else {
                        Text("\(managementText(row["metric"])) · 阈值 \(managementText(row["threshold"])) · 比例 \(managementText(row["ratio"])) · \(managementText(row["interval"])) 分钟")
                    }
                    Text("节点：\(row["clients"].array.map { managementNodeName($0.string, nodes: nodes) }.joined(separator: "、"))")
                        .font(.caption).foregroundStyle(.secondary)
                    HStack {
                        Button("编辑") { editor = ManagementRuleEditorItem(original: row) }.buttonStyle(CompatibleGlassButtonStyle())
                        Button("删除", role: .destructive) { deleting = row }.buttonStyle(CompatibleGlassButtonStyle())
                    }.disabled(busy)
                }.padding(.vertical, 4)
            }
        }
        .navigationTitle(kind.title)
        .toolbar {
            ToolbarItem(placement: .topBarTrailing) {
                Button { editor = ManagementRuleEditorItem(original: nil) } label: { Label("新增", systemImage: "plus") }.disabled(busy)
            }
            ToolbarItem(placement: .topBarTrailing) {
                Button { Task { await reload() } } label: { Label("刷新", systemImage: "arrow.clockwise") }.disabled(busy)
            }
        }
        .task { await reload() }
        .refreshable { await reload() }
        .sheet(item: $editor, onDismiss: { Task { await reload() } }) { item in
            NavigationStack { ManagementRuleForm(api: api, nodes: nodes, kind: kind, original: item.original) }
        }
        .confirmationDialog("删除此\(kind.title)？此操作无法撤销。", isPresented: Binding(get: { deleting != nil }, set: { if !$0 { deleting = nil } }), titleVisibility: .visible) {
            if let row = deleting {
                Button("确认删除", role: .destructive) { Task { await remove(row) } }
            }
            Button("取消", role: .cancel) { deleting = nil }
        }
    }

    @MainActor private func reload() async {
        guard !busy else { return }
        busy = true; error = nil
        defer { busy = false }
        do { rows = try await api.rpc(kind.list).array; loaded = true }
        catch { self.error = error.localizedDescription }
    }

    @MainActor private func remove(_ row: JSON) async {
        guard !busy else { return }
        busy = true; error = nil; deleting = nil
        defer { busy = false }
        do {
            _ = try await api.rpc(kind.delete, params: .object(["id": .array([row["id"]])]))
            rows = try await api.rpc(kind.list).array
            guard !rows.contains(where: { $0["id"] == row["id"] }) else { throw ManagementIssue(text: "删除回读失败，配置仍存在。") }
            loaded = true
        } catch { self.error = error.localizedDescription }
    }
}

private struct ManagementRuleForm: View {
    let api: KomariAPI
    let nodes: [JSON]
    let kind: ManagementRuleKind
    let original: JSON?
    @Environment(\.dismiss) private var dismiss
    @State private var name: String
    @State private var target: String
    @State private var type: String
    @State private var metric: String
    @State private var interval: String
    @State private var threshold: String
    @State private var ratio: String
    @State private var defaultOn: Bool
    @State private var selected: Set<String>
    @State private var busy = false
    @State private var submitted = false
    @State private var error: String?

    init(api: KomariAPI, nodes: [JSON], kind: ManagementRuleKind, original: JSON?) {
        self.api = api; self.nodes = nodes; self.kind = kind; self.original = original
        _name = State(initialValue: original?["name"].string ?? "")
        _target = State(initialValue: original?["target"].string ?? "")
        _type = State(initialValue: original?["type"].string ?? "icmp")
        _metric = State(initialValue: original?["metric"].string ?? "cpu")
        _interval = State(initialValue: original.map { String(Int($0["interval"].number)) } ?? (kind == .ping ? "60" : "15"))
        _threshold = State(initialValue: original.map { String($0["threshold"].number) } ?? "80")
        _ratio = State(initialValue: original.map { String($0["ratio"].number) } ?? "0.8")
        _defaultOn = State(initialValue: original?["default_on"].bool ?? false)
        _selected = State(initialValue: Set(original?["clients"].array.map { $0.string } ?? []))
    }

    var body: some View {
        Form {
            Section("配置") {
                TextField("名称", text: $name)
                if kind == .ping {
                    Picker("协议", selection: $type) {
                        ForEach(["icmp", "tcp", "http"], id: \.self) { Text($0.uppercased()).tag($0) }
                        if !["icmp", "tcp", "http"].contains(type) { Text(type).tag(type) }
                    }
                    TextField("目标（主机、主机:端口或 URL）", text: $target).textInputAutocapitalization(.never).autocorrectionDisabled()
                    TextField("间隔（秒）", text: $interval).keyboardType(.numberPad)
                    Toggle("新加入节点默认开启", isOn: $defaultOn)
                    Text("此开关不影响已有节点；请显式选择已有节点。").font(.caption).foregroundStyle(.secondary)
                } else {
                    TextField("指标（如 cpu、ram、load）", text: $metric).textInputAutocapitalization(.never).autocorrectionDisabled()
                    TextField("阈值（资源占用百分比）", text: $threshold).keyboardType(.decimalPad)
                    TextField("达标时间比（大于 0，最多 1）", text: $ratio).keyboardType(.decimalPad)
                    TextField("监测窗口（1–240 分钟）", text: $interval).keyboardType(.numberPad)
                }
            }
            ManagementNodePicker(nodes: nodes, selected: $selected)
            Section {
                ManagementStatus(busy: busy, error: error)
                if submitted { Text("请求已提交。若回读失败，请关闭并刷新列表核对；不要重复提交。").font(.footnote).foregroundStyle(.secondary) }
                Button("保存并核对") { Task { await save() } }.buttonStyle(CompatibleGlassButtonStyle(prominent: true)).disabled(busy || submitted)
            }
        }
        .disabled(busy)
        .navigationTitle(original == nil ? "新增\(kind.title)" : "编辑\(kind.title)")
        .toolbar { ToolbarItem(placement: .cancellationAction) { Button("关闭") { dismiss() }.disabled(busy) } }
        .interactiveDismissDisabled(busy)
    }

    @MainActor private func save() async {
        error = nil
        guard let period = Int(interval), period > 0 else { error = "间隔必须为正整数。"; return }
        var fields: [String: JSON] = ["name": .string(name), "clients": managementClients(selected), "interval": .number(Double(period))]
        if kind == .ping {
            guard !name.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty, !target.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty, !type.isEmpty, defaultOn || !selected.isEmpty else {
                error = "填写名称和目标，并选择节点或开启新节点默认监测。"; return
            }
            fields["target"] = .string(target); fields["type"] = .string(type); fields["default_on"] = .bool(defaultOn)
        } else {
            guard !selected.isEmpty, !metric.isEmpty, period <= 240,
                  let thresholdValue = Double(threshold), thresholdValue.isFinite, thresholdValue > 0,
                  let ratioValue = Double(ratio), ratioValue.isFinite, ratioValue > 0, ratioValue <= 1 else {
                error = "请选择节点、填写指标及正阈值；比例应大于 0 且不超过 1，窗口不超过 240 分钟。"; return
            }
            // Backend stores these fields as float32 with two-decimal precision.
            fields["metric"] = .string(metric); fields["threshold"] = .number(thresholdValue); fields["ratio"] = .number(ratioValue)
        }
        busy = true
        defer { busy = false }
        do {
            let id: JSON
            if let original {
                let fresh = try await api.rpc(kind.list).array
                guard let current = fresh.first(where: { $0["id"] == original["id"] }) else { throw ManagementIssue(text: "此配置已不存在，请关闭并刷新。") }
                // Preserve all unedited fields (weight, last_notified, future fields),
                // and refuse to overwrite a concurrent edit of an exposed field.
                for key in fields.keys where current[key] != original[key] {
                    throw ManagementIssue(text: "配置已被其他人修改（\(key)），请关闭并重新编辑。")
                }
                var merged = current.object
                for (key, value) in fields { merged[key] = value }
                id = current["id"]
                _ = try await api.rpc(kind.edit, params: .object([kind.wrapper: .array([.object(merged)])]))
            } else {
                let response = try await api.rpc(kind.add, params: .object(fields))
                id = response["task_id"]
            }
            submitted = true
            let readback = try await api.rpc(kind.list).array
            guard let actual = readback.first(where: { $0["id"] == id }) else { throw ManagementIssue(text: "请求已提交，但无法找到回读配置。") }
            try managementVerify(actual, fields: fields)
            dismiss()
        } catch { self.error = error.localizedDescription }
    }
}

private struct ManagementOffline: View {
    let api: KomariAPI
    let nodes: [JSON]
    @State private var rows: [JSON] = []
    @State private var busy = false
    @State private var error: String?
    @State private var editor: ManagementRuleEditorItem?
    var body: some View {
        List {
            Section { ManagementStatus(busy: busy, error: error) }
            Section("节点离线通知") {
                ForEach(nodes, id: \.self) { node in
                    let uuid = node["uuid"].string
                    let row = rows.first { $0["client"].string == uuid }
                    Button {
                        editor = ManagementRuleEditorItem(original: row ?? .object(["client": .string(uuid)]))
                    } label: {
                        VStack(alignment: .leading, spacing: 5) {
                            Text(managementNodeName(uuid, nodes: nodes)).foregroundStyle(.primary)
                            Text(row.map { "\(managementText($0["enable"])) · 宽限期 \(managementText($0["grace_period"])) 秒" } ?? "— · 尚未配置")
                                .font(.caption).foregroundStyle(.secondary)
                        }
                    }.disabled(busy || uuid.isEmpty)
                }
                if nodes.isEmpty { Text("没有可选节点，请返回节点页刷新。").foregroundStyle(.secondary) }
            }
        }
        .navigationTitle("离线通知")
        .toolbar { Button { Task { await reload() } } label: { Label("刷新", systemImage: "arrow.clockwise") }.disabled(busy) }
        .task { await reload() }
        .refreshable { await reload() }
        .sheet(item: $editor, onDismiss: { Task { await reload() } }) { item in
            if let row = item.original { NavigationStack { ManagementOfflineForm(api: api, nodes: nodes, original: row) } }
        }
    }
    @MainActor private func reload() async {
        guard !busy else { return }; busy = true; error = nil
        defer { busy = false }
        do { rows = try await api.rpc("admin:listOfflineNotifications").array }
        catch { self.error = error.localizedDescription }
    }
}

private struct ManagementOfflineForm: View {
    let api: KomariAPI
    let nodes: [JSON]
    let original: JSON
    @Environment(\.dismiss) private var dismiss
    @State private var enabled: Bool
    @State private var grace: String
    @State private var busy = false
    @State private var submitted = false
    @State private var error: String?
    init(api: KomariAPI, nodes: [JSON], original: JSON) {
        self.api = api; self.nodes = nodes; self.original = original
        _enabled = State(initialValue: original["enable"].bool)
        _grace = State(initialValue: original.object["grace_period"] == nil ? "180" : String(Int(original["grace_period"].number)))
    }
    var body: some View {
        Form {
            Section(managementNodeName(original["client"].string, nodes: nodes)) {
                Toggle("启用离线通知", isOn: $enabled)
                TextField("宽限期（秒）", text: $grace).keyboardType(.numberPad)
                LabeledContent("上次通知", value: managementText(original["last_notified"]))
            }
            Section {
                ManagementStatus(busy: busy, error: error)
                if submitted { Text("请求已提交，请关闭并刷新核对，勿重复提交。").font(.footnote) }
                Button("保存并核对") { Task { await save() } }.buttonStyle(CompatibleGlassButtonStyle(prominent: true)).disabled(busy || submitted)
            }
        }.disabled(busy)
        .navigationTitle("编辑离线通知")
        .toolbar { ToolbarItem(placement: .cancellationAction) { Button("关闭") { dismiss() }.disabled(busy) } }
        .interactiveDismissDisabled(busy)
    }
    @MainActor private func save() async {
        guard let seconds = Int(grace), seconds > 0 else { error = "宽限期必须是正整数。"; return }
        busy = true; error = nil
        defer { busy = false }
        do {
            let uuid = original["client"].string
            let list = try await api.rpc("admin:listOfflineNotifications").array
            let current = list.first { $0["client"].string == uuid }
            if let current {
                for key in ["enable", "grace_period"] where current[key] != original[key] {
                    throw ManagementIssue(text: "此节点配置已更改，请关闭并重新编辑。")
                }
            } else if original.object["enable"] != nil { throw ManagementIssue(text: "此配置已不存在，请刷新。") }
            var payload = current?.object ?? ["client": .string(uuid)]
            payload["enable"] = .bool(enabled); payload["grace_period"] = .number(Double(seconds))
            // This RPC takes a bare array, NOT an object envelope.
            _ = try await api.rpc("admin:editOfflineNotification", params: .array([.object(payload)]))
            submitted = true
            let refreshed = try await api.rpc("admin:listOfflineNotifications").array
            guard let actual = refreshed.first(where: { $0["client"].string == uuid }) else { throw ManagementIssue(text: "请求已提交，但未找到回读配置。") }
            try managementVerify(actual, fields: ["enable": .bool(enabled), "grace_period": .number(Double(seconds))])
            dismiss()
        } catch { self.error = error.localizedDescription }
    }
}

private struct ManagementCommands: View {
    let api: KomariAPI
    let nodes: [JSON]
    @State private var selected: Set<String> = []
    @State private var command = ""
    @State private var tasks: [JSON] = []
    @State private var busy = false
    @State private var error: String?
    @State private var confirmation = false
    @State private var executionID: String?
    @State private var delivery: String?
    @State private var executed = false

    var body: some View {
        List {
            Section("远程执行") {
                Text("命令将以 Agent 的权限运行。请确认目标节点与命令，不可撤销。").font(.footnote).foregroundStyle(.secondary)
                TextEditor(text: $command).font(.system(.body, design: .monospaced)).frame(minHeight: 100)
                    .textInputAutocapitalization(.never).autocorrectionDisabled().accessibilityLabel("远程命令")
                Button { confirmation = true } label: { Label("执行命令", systemImage: "play.fill") }
                    .buttonStyle(CompatibleGlassButtonStyle(prominent: true)).disabled(busy || executed || selected.isEmpty || command.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
                if executed {
                    Text("本次命令已提交，不会自动重试。结果可能仍在等待节点回报。").font(.footnote)
                    Button("准备新命令") { executed = false; command = ""; executionID = nil; delivery = nil }.buttonStyle(CompatibleGlassButtonStyle()).disabled(busy)
                }
                if let executionID { LabeledContent("任务 ID", value: executionID).textSelection(.enabled) }
                if let delivery { Text(delivery).font(.caption).foregroundStyle(.secondary) }
                ManagementStatus(busy: busy, error: error)
            }
            ManagementNodePicker(nodes: nodes, selected: $selected)
            Section("任务与结果") {
                if tasks.isEmpty && !busy { Text("暂无任务，或尚未成功加载。").foregroundStyle(.secondary) }
                ForEach(tasks, id: \.self) { task in
                    NavigationLink {
                        ManagementTaskDetail(api: api, nodes: nodes, taskID: task["task_id"].string)
                    } label: {
                        VStack(alignment: .leading, spacing: 5) {
                            Text(managementText(task["command"])).font(.system(.body, design: .monospaced)).lineLimit(2)
                            Text("\(managementText(task["task_id"])) · \(task["results"].array.count) 条结果").font(.caption).foregroundStyle(.secondary)
                        }
                    }
                }
            }
        }
        .navigationTitle("远程命令")
        .toolbar { Button { Task { await reload() } } label: { Label("刷新", systemImage: "arrow.clockwise") }.disabled(busy) }
        .task { await reload() }
        .refreshable { await reload() }
        .confirmationDialog("在所选 \(selected.count) 个节点执行命令？", isPresented: $confirmation, titleVisibility: .visible) {
            Button("确认执行", role: .destructive) { Task { await execute() } }
            Button("取消", role: .cancel) { }
        } message: {
            Text("\(command)\n\n目标：\(selected.sorted().map { managementNodeName($0, nodes: nodes) }.joined(separator: "、"))")
        }
    }

    @MainActor private func reload() async {
        guard !busy else { return }; busy = true; error = nil
        defer { busy = false }
        do { tasks = try await api.rpc("admin:getTasks").array }
        catch { self.error = error.localizedDescription }
    }
    @MainActor private func execute() async {
        guard !busy && !executed else { return }
        busy = true; error = nil
        // Lock even on transport failure: execution outcome may be ambiguous.
        executed = true
        defer { busy = false }
        do {
            let response = try await api.rpc("admin:exec", params: .object(["command": .string(command), "clients": managementClients(selected)]))
            let id = response["task_id"].string
            executionID = id
            delivery = "即时派发：\(response["clients"].array.count) · 排队：\(response["queued_clients"].array.count)"
            guard !id.isEmpty else { throw ManagementIssue(text: "服务器未返回任务 ID，请刷新任务列表核对，不要重复执行。") }
            let actual = try await api.rpc("admin:getTaskById", params: .object(["task_id": .string(id)]))
            try managementVerify(actual, fields: ["command": .string(command), "clients": managementClients(selected)])
            tasks = try await api.rpc("admin:getTasks").array
        } catch { self.error = "\(error.localizedDescription)\n执行状态可能不确定，请刷新任务列表核对；不会自动重试。" }
    }
}

private struct ManagementTaskDetail: View {
    let api: KomariAPI
    let nodes: [JSON]
    let taskID: String
    @State private var task: JSON = .null
    @State private var busy = false
    @State private var error: String?
    var body: some View {
        List {
            Section("任务") {
                LabeledContent("ID", value: taskID).textSelection(.enabled)
                Text(managementText(task["command"])).font(.system(.body, design: .monospaced)).textSelection(.enabled)
                ManagementStatus(busy: busy, error: error)
            }
            Section("节点执行结果") {
                ForEach(task["clients"].array, id: \.self) { client in
                    let uuid = client.string
                    let result = task["results"].array.first { $0["client"].string == uuid }
                    VStack(alignment: .leading, spacing: 8) {
                        Text(managementNodeName(uuid, nodes: nodes)).font(.headline)
                        if let result {
                            LabeledContent("退出码", value: managementText(result["exit_code"]))
                            LabeledContent("完成时间", value: managementText(result["finished_at"]))
                            Text(managementText(result["result"])).font(.system(.footnote, design: .monospaced)).textSelection(.enabled)
                        } else { Text("— · 等待结果").foregroundStyle(.secondary) }
                    }
                }
            }
        }
        .navigationTitle("任务结果")
        .toolbar { Button { Task { await reload() } } label: { Label("刷新", systemImage: "arrow.clockwise") }.disabled(busy) }
        .task { await reload() }
        .refreshable { await reload() }
    }
    @MainActor private func reload() async {
        guard !busy else { return }; busy = true; error = nil
        defer { busy = false }
        do { task = try await api.rpc("admin:getTaskById", params: .object(["task_id": .string(taskID)])) }
        catch { self.error = error.localizedDescription }
    }
}

private struct ManagementLogs: View {
    let api: KomariAPI
    @State private var rows: [JSON] = []
    @State private var page = 1
    @State private var total: Int?
    @State private var filter = ""
    @State private var busy = false
    @State private var error: String?
    private let limit = 50
    var body: some View {
        List {
            Section("筛选与分页") {
                TextField("消息类型（留空为全部，如 info、warn）", text: $filter).textInputAutocapitalization(.never).autocorrectionDisabled()
                Button("应用筛选") { Task { await reload(targetPage: 1) } }.buttonStyle(CompatibleGlassButtonStyle()).disabled(busy)
                HStack {
                    Button("上一页") { Task { await reload(targetPage: page - 1) } }.buttonStyle(CompatibleGlassButtonStyle()).disabled(busy || page <= 1)
                    Spacer()
                    Text("第 \(page) 页 · 共 \(total.map(String.init) ?? "—") 条").font(.caption)
                    Spacer()
                    Button("下一页") { Task { await reload(targetPage: page + 1) } }.buttonStyle(CompatibleGlassButtonStyle()).disabled(busy || total == nil || page * limit >= (total ?? 0))
                }
                ManagementStatus(busy: busy, error: error)
            }
            Section("审计记录") {
                if rows.isEmpty && total != nil { Text("暂无记录").foregroundStyle(.secondary) }
                ForEach(rows, id: \.self) { row in
                    VStack(alignment: .leading, spacing: 6) {
                        Text(managementText(row["message"])).textSelection(.enabled)
                        Text("\(managementText(row["msg_type"])) · \(managementText(row["time"]))").font(.caption).foregroundStyle(.secondary)
                        Text("IP \(managementText(row["ip"])) · 操作者 \(managementText(row["uuid"]))").font(.caption2).foregroundStyle(.secondary).textSelection(.enabled)
                    }
                }
            }
        }
        .navigationTitle("审计日志")
        .toolbar { Button { Task { await reload(targetPage: page) } } label: { Label("刷新", systemImage: "arrow.clockwise") }.disabled(busy) }
        .task { await reload(targetPage: 1) }
        .refreshable { await reload(targetPage: page) }
    }
    @MainActor private func reload(targetPage: Int) async {
        guard !busy, targetPage > 0 else { return }; busy = true; error = nil
        defer { busy = false }
        do {
            // Backend binds limit/page as strings, not JSON numbers.
            let result = try await api.rpc("admin:getLogs", params: .object(["limit": .string(String(limit)), "page": .string(String(targetPage)), "msg_type": .string(filter)]))
            guard case .number(let count) = result["total"], count.isFinite, count >= 0 else { throw ManagementIssue(text: "服务器未返回有效日志总数。") }
            rows = result["logs"].array; total = Int(count); page = targetPage
        } catch { self.error = error.localizedDescription }
    }
}
