import Foundation

enum BackendKind: String, Codable, CaseIterable, Identifiable {
    case komari, nezha, nezhaV0, dstatus
    var id: String { rawValue }
    var title: String { switch self { case .komari: return "Komari"; case .nezha: return NSLocalizedString("哪吒 V1", comment: ""); case .nezhaV0: return NSLocalizedString("哪吒 V0", comment: ""); case .dstatus: return "DStatus" } }
}
struct BackendSnapshot: Sendable { let nodes: [JSON]; let statuses: JSON }
struct MonitorAPI: Sendable {
    let kind: BackendKind
    private let base: URL
    private let key: String
    private let session: URLSession
    init(kind: BackendKind, address: String, key: String, allowHTTP: Bool,
         configuration: URLSessionConfiguration = .ephemeral) throws {
        self.kind = kind; base = try KomariAPI.validatedURL(address, allowHTTP: allowHTTP)
        guard kind == .dstatus || !key.isEmpty else { throw KomariAPIError.invalidAPIKey }
        guard key.unicodeScalars.allSatisfy({ $0.value >= 33 && $0.value <= 126 }) else { throw KomariAPIError.invalidAPIKey }
        self.key = kind == .dstatus ? "" : key
        let c = configuration
        c.urlCache = nil; c.httpCookieStorage = nil; c.urlCredentialStorage = nil; c.httpShouldSetCookies = false
        c.timeoutIntervalForRequest = 20; c.timeoutIntervalForResource = 25
        session = URLSession(configuration: c, delegate: NoRedirectDelegate(), delegateQueue: nil)
    }
    func request(_ path: String, query: [String: String] = [:], socket: Bool = false) -> URLRequest {
        var u = URLComponents(url: base, resolvingAgainstBaseURL: false)!
        u.path = u.path.trimmingCharacters(in: CharacterSet(charactersIn: "/"))
        u.path = "/" + (u.path.isEmpty ? "" : u.path + "/") + path
        if !query.isEmpty { u.queryItems = query.sorted { $0.key < $1.key }.map { URLQueryItem(name: $0.key, value: $0.value) } }
        if socket { u.scheme = base.scheme == "https" ? "wss" : "ws" }
        var r = URLRequest(url: u.url!, timeoutInterval: 20)
        r.setValue("application/json", forHTTPHeaderField: "Accept")
        if !key.isEmpty { r.setValue(kind == .nezhaV0 ? key : "Bearer " + key, forHTTPHeaderField: "Authorization") }
        return r
    }
    func get(_ path: String, query: [String: String] = [:]) async throws -> JSON {
        let data: Data; let response: URLResponse
        do { (data, response) = try await session.data(for: request(path, query: query)) } catch { throw RequestFailure.safeTransportError(error) }
        guard let h = response as? HTTPURLResponse else { throw KomariAPIError.invalidResponse }
        guard (200..<300).contains(h.statusCode) else { throw KomariAPIError.httpStatus(h.statusCode) }
        guard data.count <= 8 * 1024 * 1024, let j = try? JSONDecoder().decode(JSON.self, from: data) else { throw KomariAPIError.invalidResponse }
        if j["success"] == .bool(false) || (kind == .nezhaV0 && j["code"] != .null && j["code"].number != 0) { throw KomariAPIError.invalidResponse }
        return j
    }
    func nezhaStream() async throws -> JSON {
        let socket = session.webSocketTask(with: request("api/v1/ws/server", socket: true))
        socket.maximumMessageSize = 8 * 1024 * 1024; socket.resume()
        defer { socket.cancel(with: .normalClosure, reason: nil) }
        do {
            return try await withTaskCancellationHandler {
                try await withThrowingTaskGroup(of: JSON.self) { group in
                    group.addTask {
                        let m = try await socket.receive(); let d: Data
                        switch m { case .data(let v): d = v; case .string(let v): d = Data(v.utf8); @unknown default: throw KomariAPIError.invalidResponse }
                        guard let j = try? JSONDecoder().decode(JSON.self, from: d), case .array = j["servers"] else { throw KomariAPIError.invalidResponse }
                        return j
                    }
                    group.addTask { try await Task.sleep(for: .seconds(20)); throw KomariAPIError.timedOut }
                    defer { group.cancelAll(); socket.cancel(with: .goingAway, reason: nil) }
                    guard let result = try await group.next() else { throw KomariAPIError.invalidResponse }; return result
                }
            } onCancel: { socket.cancel(with: .goingAway, reason: nil) }
        } catch { throw RequestFailure.safeTransportError(error) }
    }
    func snapshot() async throws -> BackendSnapshot {
        switch kind {
        case .komari: throw KomariAPIError.invalidMethod
        case .nezha: return Self.normalizeNezha(try await nezhaStream(), legacy: false)
        case .nezhaV0:
            let j = try await get("api/v1/server/details")
            guard case .array = j["result"] else { throw KomariAPIError.invalidResponse }
            return Self.normalizeNezha(j, legacy: true)
        case .dstatus:
            async let live = get("api/allnode_status")
            async let inventory = get("api/servers")
            let (a,b) = try await (live, inventory)
            guard case .object = a["data"], case .array = b["data"] else { throw KomariAPIError.invalidResponse }
            return Self.normalizeDStatus(a, inventory: b)
        }
    }
    static func normalizeNezha(_ j: JSON, legacy: Bool, now: Date = Date()) -> BackendSnapshot {
        var nodes: [JSON] = []; var states: [String: JSON] = [:]
        for r in j[legacy ? "result" : "servers"].array {
            let id = r["id"].string.isEmpty ? String(format: "%.0f", r["id"].number) : r["id"].string
            let h = r["host"], s = r[legacy ? "status" : "state"]
            func host(_ a: String, _ b: String) -> JSON { h[legacy ? b : a] }
            func state(_ a: String, _ b: String) -> JSON { s[legacy ? b : a] }
            let date = legacy ? Date(timeIntervalSince1970: r["last_active"].number) : recordDate(r["last_active"].string)
            let online: JSON = date.map { .bool(now.timeIntervalSince($0) < 15 && now.timeIntervalSince($0) >= -60) } ?? .null
            nodes.append(.object(["uuid": .string(id), "name": r["name"], "group": r["tag"], "os": host("platform", "Platform"), "arch": host("arch", "Arch"), "region": legacy ? host("country_code", "CountryCode") : r["country_code"], "mem_total": host("mem_total", "MemTotal"), "disk_total": host("disk_total", "DiskTotal"), "public_remark": r["public_note"], "cpu_name": host("cpu", "CPU").array.first ?? .null]))
            states[id] = .object(["online": online, "cpu": state("cpu", "CPU"), "ram": state("mem_used", "MemUsed"), "disk": state("disk_used", "DiskUsed"), "load1": state("load_1", "Load1"), "load5": state("load_5", "Load5"), "load15": state("load_15", "Load15"), "net_in": state("net_in_speed", "NetInSpeed"), "net_out": state("net_out_speed", "NetOutSpeed"), "net_total_down": state("net_in_transfer", "NetInTransfer"), "net_total_up": state("net_out_transfer", "NetOutTransfer"), "uptime": state("uptime", "Uptime")])
        }
        return BackendSnapshot(nodes: nodes, statuses: .object(states))
    }
    static func normalizeDStatus(_ j: JSON, inventory: JSON) -> BackendSnapshot {
        let info = Dictionary(inventory["data"].array.map { ($0["id"].string, $0) }, uniquingKeysWith: { _, b in b })
        let order = j["order"].array.map(\.string) + j["data"].object.keys.sorted().filter { !j["order"].array.map(\.string).contains($0) }
        var nodes: [JSON] = []; var states: [String: JSON] = [:]
        for id in order {
            let r = j["data"][id]; guard r != .null else { continue }
            let s = r["stat"], h = info[id] ?? .null, traffic = r["traffic_stats"]
            let cpu: JSON = s["cpu"]["multi"] == .null ? .null : .number(s["cpu"]["multi"].number * 100)
            nodes.append(.object(["uuid": .string(id), "name": r["name"], "region": h["data"]["location"]["code"] == .null ? h["data"]["metadata"]["region"] : h["data"]["location"]["code"], "group": .string(h["group_ids"].array.map(\.string).joined(separator: " · ")), "mem_total": s["mem"]["virtual"]["total"], "traffic_limit": traffic["limit"]]))
            states[id] = .object(["online": s["offline"] == .null ? .null : .bool(!s["offline"].bool), "cpu": cpu, "ram": s["mem"]["virtual"]["used"], "net_in": s["net"]["delta"]["in"], "net_out": s["net"]["delta"]["out"], "net_total_down": s["net"]["total"]["in"], "net_total_up": s["net"]["total"]["out"], "traffic_used": traffic["used"], "traffic_unlimited": traffic["unlimited"]])
        }
        return BackendSnapshot(nodes: nodes, statuses: .object(states))
    }
    func history(id: String, field: String, hours: Int) async throws -> [JSON] {
        guard !id.isEmpty, !id.contains("/"), id != ".", id != "..", let escaped = id.addingPercentEncoding(withAllowedCharacters: .alphanumerics) else { throw KomariAPIError.invalidParams }
        let start = Date().addingTimeInterval(-Double(hours) * 3600)
        if kind == .nezhaV0 {
            guard field == "latency" else { return [] }
            let j = try await get("api/v1/monitor/" + escaped)
            return j["result"].array.flatMap { monitor in
                monitor["created_at"].array.enumerated().compactMap { index, t in
                    guard index < monitor["avg_delay"].array.count else { return nil }
                    return .object(["time": .string(ISO8601DateFormatter().string(from: Date(timeIntervalSince1970: t.number))), "latency": monitor["avg_delay"].array[index], "series": monitor["monitor_name"]])
                }
            }.filter { (recordDate($0["time"].string) ?? .distantPast) >= start }
        }
        if kind == .nezha {
            let metric = ["ram": "memory", "net_in": "net_in_speed", "net_out": "net_out_speed"][field] ?? field
            let j = try await get("api/v1/server/" + escaped + "/metrics", query: ["metric": metric, "period": "1d"])
            return j["data"]["data_points"].array.compactMap { p in
                let d = Date(timeIntervalSince1970: p["ts"].number / 1000)
                guard d >= start, p["value"] != .null else { return nil }
                return .object(["time": .string(ISO8601DateFormatter().string(from: d)), field: p["value"]])
            }
        }
        if kind == .dstatus {
            guard field != "disk" else { return [] }
            let f = ["cpu": "cpu", "ram": "mem", "net_in": "ibw", "net_out": "obw"][field] ?? field
            let j = try await get("api/stats/" + escaped + "/bandwidth/history", query: ["range": hours == 1 ? "1h" : "24h", "fields": f])
            let data = j["data"]
            return data["timestamps"].array.enumerated().compactMap { index, t in
                let d = Date(timeIntervalSince1970: t.number / 1000)
                guard d >= start, index < data[f].array.count else { return nil }
                let v = data[f].array[index]
                return .object(["time": .string(ISO8601DateFormatter().string(from: d)), field: f == "cpu" && v != .null ? .number(v.number * 100) : v])
            }
        }
        return []
    }
}
