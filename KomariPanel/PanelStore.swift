import Foundation
import Combine

struct Panel: Codable, Identifiable, Hashable {
    var id = UUID().uuidString
    var name: String
    var address: String
    var allowHTTP: Bool = false
    var backend: BackendKind? = nil
    var kind: BackendKind { backend ?? .komari }
}

/// A connection owns the exact clients used for its initial and subsequent snapshots.
/// Closure injection lets tests suspend real store operations without networking or Keychain.
@MainActor struct PanelConnection {
    var api: KomariAPI? = nil
    var monitor: MonitorAPI? = nil
    let load: () async throws -> BackendSnapshot
    let refresh: () async throws -> BackendSnapshot

    static func live(_ panel: Panel) throws -> PanelConnection {
        let key = panel.kind == .dstatus ? "" : try Keychain.load(account: panel.id)
        if panel.kind != .komari {
            let client = try MonitorAPI(kind: panel.kind, address: panel.address, key: key, allowHTTP: panel.allowHTTP)
            return PanelConnection(monitor: client, load: { try await client.snapshot() }, refresh: { try await client.snapshot() })
        }
        let client = try KomariAPI(baseURL: panel.address, apiKey: key, allowHTTP: panel.allowHTTP)
        return PanelConnection(api: client, load: {
            let list = try await client.rpc("admin:listClients")
            try Task.checkCancellation()
            let statuses = try await client.rpc("common:getNodesLatestStatus")
            let nodes = list.array.sorted {
                $0["weight"].number == $1["weight"].number
                    ? $0["name"].string < $1["name"].string
                    : $0["weight"].number > $1["weight"].number
            }
            return BackendSnapshot(nodes: nodes, statuses: statuses)
        }, refresh: {
            BackendSnapshot(nodes: [], statuses: try await client.rpc("common:getNodesLatestStatus"))
        })
    }
}

@MainActor final class PanelStore: ObservableObject {
    @Published var panels: [Panel] = [] {
        didSet {
            if oldValue.first(where: { $0.id == selected }) != selectedPanel { invalidateConnection() }
        }
    }
    @Published var selected: String = "" {
        didSet { if oldValue != selected { invalidateConnection() } }
    }
    @Published var nodes: [JSON] = []
    @Published var statuses: JSON = .object([:])
    @Published var error: String?
    @Published var loading = false
    @Published var updated: Date?
    @Published var api: KomariAPI?
    @Published var monitor: MonitorAPI?

    private let defaults: UserDefaults
    private let makeConnection: @MainActor (Panel) throws -> PanelConnection
    private var connection: PanelConnection?
    private var generation = UUID()
    private var refreshID = UUID()
    private var selectedPanel: Panel? { panels.first { $0.id == selected } }

    init(defaults: UserDefaults = .standard,
         makeConnection: @escaping @MainActor (Panel) throws -> PanelConnection = { try PanelConnection.live($0) }) {
        self.defaults = defaults
        self.makeConnection = makeConnection
        if let data = defaults.data(forKey: "panels"), let saved = try? JSONDecoder().decode([Panel].self, from: data) { panels = saved }
        selected = defaults.string(forKey: "selectedPanel") ?? panels.first?.id ?? ""
    }

    func persist() throws {
        defaults.set(try JSONEncoder().encode(panels), forKey: "panels")
        defaults.set(selected, forKey: "selectedPanel")
    }

    /// Invalidate synchronously on selection/configuration changes, not just when
    /// SwiftUI eventually starts its next .task. This also closes the A → B → A race.
    private func invalidateConnection() {
        generation = UUID()
        refreshID = UUID()
        connection = nil
        api = nil; monitor = nil; nodes = []; statuses = .object([:])
        updated = nil; error = nil; loading = false
    }

    private func isCurrent(_ token: UUID, panel: Panel) -> Bool {
        generation == token && selectedPanel == panel
    }

    func connect() async {
        // A cancelled SwiftUI task must not reset a newer connection's state.
        guard !Task.isCancelled else { return }
        // Same-panel reloads retain the last good snapshot/clients if the caller
        // is cancelled (for example when SwiftUI ends a pull-to-refresh task).
        generation = UUID()
        refreshID = UUID()
        guard let panel = selectedPanel else { invalidateConnection(); return }
        let token = generation
        loading = true
        defer {
            // Old completions must not dismiss the newer request's spinner.
            if isCurrent(token, panel: panel) { loading = false }
        }
        do {
            let candidate = try makeConnection(panel)
            let snapshot = try await candidate.load()
            try Task.checkCancellation()
            guard isCurrent(token, panel: panel) else { return }
            try persist()
            connection = candidate
            api = candidate.api; monitor = candidate.monitor
            nodes = snapshot.nodes; statuses = snapshot.statuses
            updated = Date(); error = nil
        } catch {
            guard isCurrent(token, panel: panel), !Task.isCancelled,
                  !RequestFailure.isCancellation(error) else { return }
            self.error = error.localizedDescription
            updated = nil
        }
    }

    func refresh() async {
        guard !Task.isCancelled, !loading else { return }
        // An initial scene task can be cancelled before it installs a connection.
        // The active-scene poll then reconnects once, rather than staying empty.
        guard let connection else { await connect(); return }
        guard let panel = selectedPanel else { return }
        let token = generation
        let requestID = UUID()
        refreshID = requestID
        do {
            let snapshot = try await connection.refresh()
            try Task.checkCancellation()
            guard isCurrent(token, panel: panel), refreshID == requestID else { return }
            // Komari refresh returns statuses only; inventory comes from connect.
            if connection.api == nil { nodes = snapshot.nodes }
            statuses = snapshot.statuses; updated = Date(); error = nil
        } catch {
            guard isCurrent(token, panel: panel), refreshID == requestID,
                  !Task.isCancelled, !RequestFailure.isCancellation(error) else { return }
            self.error = error.localizedDescription
            updated = nil
        }
    }
}
