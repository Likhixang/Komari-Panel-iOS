import Foundation

/// Per-panel, device-local presentation settings. Never writes server `hidden`.
struct DashboardPreferences: Codable {
    var orderedNodeIDs: [String] = []
    var hiddenNodeIDs: Set<String> = []

    init() {}

    private enum CodingKeys: String, CodingKey { case orderedNodeIDs, hiddenNodeIDs }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        // Older saved preferences contain sortOrder instead. Ignore that field,
        // preserve hidden nodes, and start with the panel's own order.
        orderedNodeIDs = try container.decodeIfPresent([String].self, forKey: .orderedNodeIDs) ?? []
        hiddenNodeIDs = try container.decodeIfPresent(Set<String>.self, forKey: .hiddenNodeIDs) ?? []
    }

    func orderedNodes(_ nodes: [JSON]) -> [JSON] {
        var ranks: [String: Int] = [:]
        for id in orderedNodeIDs where ranks[id] == nil { ranks[id] = ranks.count }
        // New nodes append in backend order; stale saved IDs never create rows.
        return nodes.enumerated().sorted { lhs, rhs in
            let left = ranks[lhs.element["uuid"].string] ?? Int.max
            let right = ranks[rhs.element["uuid"].string] ?? Int.max
            return left == right ? lhs.offset < rhs.offset : left < right
        }.map(\.element)
    }

    func visibleNodes(_ nodes: [JSON]) -> [JSON] {
        orderedNodes(nodes).filter { !hiddenNodeIDs.contains($0["uuid"].string) }
    }
}
