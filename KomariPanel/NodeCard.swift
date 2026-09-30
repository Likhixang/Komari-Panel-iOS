import SwiftUI

struct StatusBars: View {
    let summary: PingSummary

    private var barColors: [Color] {
        if summary.validCount == 0 && summary.timeoutCount == 0 {
            return Array(repeating: Color(.systemFill), count: 8)
        }
        let lossFraction = (summary.averageLoss ?? 0) / 100.0
        let latency = summary.averageLatency ?? 0
        let latencyColor: Color = {
            if latency <= 60 { return .green }
            else if latency <= 120 { return .teal }
            else if latency <= 200 { return .orange }
            else { return .red }
        }()

        let lossBars = Int(round(lossFraction * 8))
        var colors: [Color] = []
        for i in 0..<8 {
            if i >= (8 - lossBars) {
                colors.append(.red)
            } else if summary.allTimedOut {
                colors.append(.red)
            } else if summary.averageLatency == nil {
                colors.append(Color(.systemFill))
            } else {
                colors.append(latencyColor)
            }
        }
        return colors
    }

    var body: some View {
        HStack(spacing: 2) {
            ForEach(0..<8, id: \.self) { i in
                RoundedRectangle(cornerRadius: 1.5)
                    .fill(barColors[i])
                    .frame(height: 8)
            }
        }
        .frame(maxWidth: .infinity)
    }
}

struct ResourceGauge: View {
    let title: LocalizedStringKey
    let icon: String
    let iconColor: Color
    let value: String
    let detail: String
    let fraction: Double?
    let tint: Color

    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            HStack(spacing: 3) {
                Image(systemName: icon)
                    .font(.system(size: 9, weight: .semibold))
                    .foregroundColor(iconColor)
                Text(title)
                    .font(.system(size: 11, weight: .medium))
                    .foregroundColor(.secondary)
            }
            Text(value)
                .font(.system(size: 15, weight: .bold))
                .monospacedDigit()
                .lineLimit(1)
                .minimumScaleFactor(0.6)
            
            GeometryReader { geo in
                ZStack(alignment: .leading) {
                    Capsule()
                        .fill(Color(.systemFill))
                        .frame(height: 4)
                    Capsule()
                        .fill(tint)
                        .frame(width: max(0, min(geo.size.width, geo.size.width * CGFloat(fraction ?? 0))), height: 4)
                }
            }
            .frame(height: 4)
            .padding(.vertical, 2)

            Text(detail)
                .font(.system(size: 9))
                .foregroundColor(.secondary)
                .monospacedDigit()
                .lineLimit(1)
                .minimumScaleFactor(0.55)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }
}

// MARK: - ServerBox-Style Expanded Detail Card
struct NodeSpecificationHeroCard: View {
    let node: JSON
    let status: JSON
    let fresh: Bool

    var metrics: JSON { fresh ? status : .null }

    func total(_ field: String, fallback: String) -> JSON {
        status[field] == .null ? node[fallback] : status[field]
    }

    func ratio(_ used: JSON, _ total: JSON) -> Double? {
        guard fresh, used != .null, total != .null, total.number > 0 else { return nil }
        return used.number / total.number
    }

    var trafficUsed: JSON {
        if metrics["traffic_used"] != .null { return metrics["traffic_used"] }
        let up = metrics["net_total_up"], down = metrics["net_total_down"]
        guard up != .null, down != .null else { return .null }
        switch node["traffic_limit_type"].string {
        case "up": return up
        case "down": return down
        case "min": return .number(min(up.number, down.number))
        case "max": return .number(max(up.number, down.number))
        case "sum": return .number(up.number + down.number)
        default: return .null
        }
    }

    var isOnline: Bool { fresh && status["online"].bool }
    var pingSummary: PingSummary { PingSummary(metrics["ping"]) }

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            // Header: Status breathing dot + Name + OS/Region flags
            HStack(alignment: .center, spacing: 8) {
                ZStack {
                    Circle()
                        .fill((!fresh ? Color.secondary : isOnline ? Color.green : Color.orange).opacity(0.25))
                        .frame(width: 16, height: 16)
                    Circle()
                        .fill(!fresh ? Color.secondary : isOnline ? Color.green : Color.orange)
                        .frame(width: 9, height: 9)
                }

                Text(shown(node["name"]))
                    .font(.system(size: 20, weight: .bold))
                    .foregroundColor(.primary)

                if !node["group"].string.isEmpty {
                    Text(node["group"].string)
                        .font(.system(size: 11, weight: .medium))
                        .padding(.horizontal, 7)
                        .padding(.vertical, 2.5)
                        .background(Color(.tertiarySystemGroupedBackground), in: Capsule())
                        .foregroundColor(.secondary)
                }

                Spacer()

                NodeIdentityIcons(node: node, iconSize: 22)
            }

            // Specs Mini Cards Grid (2 columns)
            VStack(spacing: 6) {
                // Row 1: CPU Model (Full width)
                if !node["cpu_name"].string.isEmpty {
                    HStack(spacing: 6) {
                        Image(systemName: "cpu")
                            .font(.system(size: 11, weight: .semibold))
                            .foregroundColor(.teal)
                        Text(shown(node["cpu_name"]))
                            .font(.system(size: 12, weight: .medium))
                            .foregroundColor(.primary)
                            .lineLimit(1)
                        Spacer()
                    }
                    .padding(.horizontal, 10)
                    .padding(.vertical, 7)
                    .background(Color(.tertiarySystemGroupedBackground), in: RoundedRectangle(cornerRadius: 8))
                }

                // Row 2: OS & Arch
                HStack(spacing: 6) {
                    HStack(spacing: 6) {
                        Image(systemName: "server.rack")
                            .font(.system(size: 10))
                            .foregroundColor(.secondary)
                        Text(shown(node["os"]))
                            .font(.system(size: 11))
                            .lineLimit(1)
                        Spacer()
                    }
                    .padding(.horizontal, 8)
                    .padding(.vertical, 6)
                    .background(Color(.tertiarySystemGroupedBackground), in: RoundedRectangle(cornerRadius: 8))

                    HStack(spacing: 6) {
                        Image(systemName: "memorychip")
                            .font(.system(size: 10))
                            .foregroundColor(.secondary)
                        Text(shown(node["arch"]))
                            .font(.system(size: 11))
                            .lineLimit(1)
                        Spacer()
                    }
                    .padding(.horizontal, 8)
                    .padding(.vertical, 6)
                    .background(Color(.tertiarySystemGroupedBackground), in: RoundedRectangle(cornerRadius: 8))
                }

                // Row 3: Load & Specs
                HStack(spacing: 6) {
                    HStack(spacing: 6) {
                        Text("负载")
                            .font(.system(size: 10))
                            .foregroundColor(.secondary)
                        let l1 = metrics["load1"] == .null ? metrics["load"] : metrics["load1"]
                        Text(l1 == .null ? "—" : "\(String(format: "%.2f", l1.number)), \(String(format: "%.2f", metrics["load5"].number))")
                            .font(.system(size: 11, weight: .medium))
                            .monospacedDigit()
                            .lineLimit(1)
                        Spacer()
                    }
                    .padding(.horizontal, 8)
                    .padding(.vertical, 6)
                    .background(Color(.tertiarySystemGroupedBackground), in: RoundedRectangle(cornerRadius: 8))

                    HStack(spacing: 6) {
                        Text("规格")
                            .font(.system(size: 10))
                            .foregroundColor(.secondary)
                        let ram = total("ram_total", fallback: "mem_total")
                        let disk = total("disk_total", fallback: "disk_total")
                        Text("\(bytes(ram)) · \(bytes(disk))")
                            .font(.system(size: 11, weight: .medium))
                            .monospacedDigit()
                            .lineLimit(1)
                        Spacer()
                    }
                    .padding(.horizontal, 8)
                    .padding(.vertical, 6)
                    .background(Color(.tertiarySystemGroupedBackground), in: RoundedRectangle(cornerRadius: 8))
                }
            }

            // Traffic Quota Overview Bar
            VStack(alignment: .leading, spacing: 4) {
                HStack {
                    HStack(spacing: 4) {
                        Image(systemName: "arrow.up.arrow.down")
                            .font(.system(size: 10, weight: .bold))
                            .foregroundColor(.blue)
                        Text("流量配额")
                            .font(.system(size: 11, weight: .semibold))
                            .foregroundColor(.secondary)
                    }
                    Spacer()
                    if metrics["traffic_unlimited"].bool {
                        Text("不限额")
                            .font(.system(size: 11, weight: .semibold))
                            .foregroundColor(.secondary)
                    } else if let r = ratio(trafficUsed, node["traffic_limit"]) {
                        Text(String(format: "%.1f%%", r * 100))
                            .font(.system(size: 11, weight: .bold))
                            .monospacedDigit()
                            .foregroundColor(.primary)
                    }
                }

                GeometryReader { geo in
                    ZStack(alignment: .leading) {
                        Capsule()
                            .fill(Color(.systemFill))
                            .frame(height: 6)
                        Capsule()
                            .fill(Color.blue)
                            .frame(width: max(0, min(geo.size.width, geo.size.width * CGFloat(ratio(trafficUsed, node["traffic_limit"]) ?? 0))), height: 6)
                    }
                }
                .frame(height: 6)

                HStack {
                    Text(bytes(trafficUsed) + " / " + (metrics["traffic_unlimited"].bool ? NSLocalizedString("不限额", comment: "") : bytes(node["traffic_limit"])))
                        .font(.system(size: 10))
                        .monospacedDigit()
                        .foregroundColor(.secondary)
                    Spacer()
                    Text("上行 \(bytes(metrics["net_total_up"])) · 下行 \(bytes(metrics["net_total_down"]))")
                        .font(.system(size: 10))
                        .monospacedDigit()
                        .foregroundColor(.secondary)
                }
            }
            .padding(.horizontal, 12)
            .padding(.vertical, 10)
            .background(Color(.tertiarySystemGroupedBackground), in: RoundedRectangle(cornerRadius: 12))

            // 2x2 Hero Core Metrics (CPU, RAM, Disk, Speed)
            LazyVGrid(columns: [GridItem(.flexible(), spacing: 10), GridItem(.flexible(), spacing: 10)], spacing: 10) {
                // CPU
                VStack(alignment: .leading, spacing: 4) {
                    HStack {
                        Image(systemName: "cpu").foregroundColor(.green).font(.system(size: 11, weight: .semibold))
                        Text("CPU").font(.system(size: 12, weight: .medium)).foregroundColor(.secondary)
                        Spacer()
                    }
                    Text(percent(metrics["cpu"]))
                        .font(.system(size: 22, weight: .bold))
                        .monospacedDigit()
                        .lineLimit(1)
                    GeometryReader { geo in
                        ZStack(alignment: .leading) {
                            Capsule().fill(Color(.systemFill)).frame(height: 4)
                            Capsule().fill(Color.green).frame(width: max(0, min(geo.size.width, geo.size.width * CGFloat((metrics["cpu"].number) / 100))), height: 4)
                        }
                    }.frame(height: 4)
                }
                .padding(10)
                .background(Color(.tertiarySystemGroupedBackground), in: RoundedRectangle(cornerRadius: 10))

                // RAM
                VStack(alignment: .leading, spacing: 4) {
                    HStack {
                        Image(systemName: "memorychip").foregroundColor(.teal).font(.system(size: 11, weight: .semibold))
                        Text("内存").font(.system(size: 12, weight: .medium)).foregroundColor(.secondary)
                        Spacer()
                    }
                    let r = ratio(metrics["ram"], total("ram_total", fallback: "mem_total"))
                    Text(r.map { String(format: "%.1f%%", $0 * 100) } ?? "—")
                        .font(.system(size: 22, weight: .bold))
                        .monospacedDigit()
                        .lineLimit(1)
                    GeometryReader { geo in
                        ZStack(alignment: .leading) {
                            Capsule().fill(Color(.systemFill)).frame(height: 4)
                            Capsule().fill(Color.teal).frame(width: max(0, min(geo.size.width, geo.size.width * CGFloat(r ?? 0))), height: 4)
                        }
                    }.frame(height: 4)
                }
                .padding(10)
                .background(Color(.tertiarySystemGroupedBackground), in: RoundedRectangle(cornerRadius: 10))

                // Disk
                VStack(alignment: .leading, spacing: 4) {
                    HStack {
                        Image(systemName: "internaldrive").foregroundColor(.orange).font(.system(size: 11, weight: .semibold))
                        Text("磁盘").font(.system(size: 12, weight: .medium)).foregroundColor(.secondary)
                        Spacer()
                    }
                    let r = ratio(metrics["disk"], total("disk_total", fallback: "disk_total"))
                    Text(r.map { String(format: "%.1f%%", $0 * 100) } ?? "—")
                        .font(.system(size: 22, weight: .bold))
                        .monospacedDigit()
                        .lineLimit(1)
                    GeometryReader { geo in
                        ZStack(alignment: .leading) {
                            Capsule().fill(Color(.systemFill)).frame(height: 4)
                            Capsule().fill(Color.orange).frame(width: max(0, min(geo.size.width, geo.size.width * CGFloat(r ?? 0))), height: 4)
                        }
                    }.frame(height: 4)
                }
                .padding(10)
                .background(Color(.tertiarySystemGroupedBackground), in: RoundedRectangle(cornerRadius: 10))

                // Network Realtime Speed
                VStack(alignment: .leading, spacing: 4) {
                    HStack {
                        Image(systemName: "network").foregroundColor(.blue).font(.system(size: 11, weight: .semibold))
                        Text("实时网络").font(.system(size: 12, weight: .medium)).foregroundColor(.secondary)
                        Spacer()
                    }
                    HStack(spacing: 6) {
                        VStack(alignment: .leading, spacing: 2) {
                            HStack(spacing: 2) {
                                Image(systemName: "arrow.up").font(.system(size: 8, weight: .bold)).foregroundColor(.green)
                                Text(metrics["net_out"] == .null ? "—" : bytes(metrics["net_out"]) + "/s")
                                    .font(.system(size: 10, weight: .semibold))
                                    .foregroundColor(.green)
                            }
                            HStack(spacing: 2) {
                                Image(systemName: "arrow.down").font(.system(size: 8, weight: .bold)).foregroundColor(.blue)
                                Text(metrics["net_in"] == .null ? "—" : bytes(metrics["net_in"]) + "/s")
                                    .font(.system(size: 10, weight: .semibold))
                                    .foregroundColor(.blue)
                            }
                        }
                        .monospacedDigit()
                    }
                    .frame(height: 26, alignment: .center)
                }
                .padding(10)
                .background(Color(.tertiarySystemGroupedBackground), in: RoundedRectangle(cornerRadius: 10))
            }

            // Ping Status Bars Row
            HStack(spacing: 12) {
                VStack(alignment: .leading, spacing: 3) {
                    HStack(spacing: 4) {
                        Text("延迟").font(.system(size: 11, weight: .medium)).foregroundColor(.secondary)
                        let summary = pingSummary
                        Text(summary.averageLatency.map { String(format: "%.0f ms", $0) } ?? (summary.allTimedOut ? NSLocalizedString("超时", comment: "") : "—"))
                            .font(.system(size: 12, weight: .bold))
                            .foregroundColor(summary.allTimedOut ? .red : summary.averageLatency.map { $0 > 150 ? Color.red : Color.primary } ?? .secondary)
                    }
                    StatusBars(summary: pingSummary)
                }
                .monospacedDigit()
                .frame(maxWidth: .infinity, alignment: .leading)

                VStack(alignment: .leading, spacing: 3) {
                    HStack(spacing: 4) {
                        Text("丢包").font(.system(size: 11, weight: .medium)).foregroundColor(.secondary)
                        Text(pingSummary.averageLoss.map { String(format: "%.0f%%", $0) } ?? "—")
                            .font(.system(size: 12, weight: .bold))
                            .foregroundColor(pingSummary.averageLoss.map { $0 > 0 ? Color.red : Color.green } ?? .secondary)
                    }
                    StatusBars(summary: pingSummary)
                }
                .monospacedDigit()
                .frame(maxWidth: .infinity, alignment: .leading)
            }
            .padding(.horizontal, 12)
            .padding(.vertical, 8)
            .background(Color(.tertiarySystemGroupedBackground), in: RoundedRectangle(cornerRadius: 10))
        }
        .padding(16)
        .background(Color(.secondarySystemGroupedBackground), in: RoundedRectangle(cornerRadius: 20))
    }
}

struct RichNodeCard: View {
    let node: JSON
    let status: JSON
    let fresh: Bool

    var metrics: JSON { fresh ? status : .null }

    func total(_ field: String, fallback: String) -> JSON {
        status[field] == .null ? node[fallback] : status[field]
    }

    func ratio(_ used: JSON, _ total: JSON) -> Double? {
        guard fresh, used != .null, total != .null, total.number > 0 else { return nil }
        return used.number / total.number
    }

    func capacity(_ used: JSON, _ total: JSON) -> String {
        bytes(fresh ? used : .null) + " / " + bytes(total)
    }

    func load(_ field: String) -> String {
        let v = metrics[field]
        return v == .null ? "—" : String(format: "%.2f", v.number)
    }

    var trafficUsed: JSON {
        if metrics["traffic_used"] != .null { return metrics["traffic_used"] }
        let up = metrics["net_total_up"], down = metrics["net_total_down"]
        guard up != .null, down != .null else { return .null }
        switch node["traffic_limit_type"].string {
        case "up": return up
        case "down": return down
        case "min": return .number(min(up.number, down.number))
        case "max": return .number(max(up.number, down.number))
        case "sum": return .number(up.number + down.number)
        default: return .null
        }
    }

    var pingSummary: PingSummary { PingSummary(metrics["ping"]) }

    var isOnline: Bool {
        fresh && status["online"].bool
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            // Header: Status breathing dot + Name + OS/Region flags
            HStack(alignment: .center, spacing: 8) {
                // Online breathing light
                ZStack {
                    Circle()
                        .fill((!fresh ? Color.secondary : isOnline ? Color.green : Color.orange).opacity(0.25))
                        .frame(width: 14, height: 14)
                    Circle()
                        .fill(!fresh ? Color.secondary : isOnline ? Color.green : Color.orange)
                        .frame(width: 8, height: 8)
                }

                Text(shown(node["name"]))
                    .font(.system(size: 16, weight: .bold))
                    .foregroundColor(.primary)

                if !node["group"].string.isEmpty {
                    Text(node["group"].string)
                        .font(.system(size: 10, weight: .medium))
                        .padding(.horizontal, 6)
                        .padding(.vertical, 2)
                        .background(Color(.tertiarySystemGroupedBackground), in: Capsule())
                        .foregroundColor(.secondary)
                }

                Spacer()

                NodeIdentityIcons(node: node)
            }

            // Core Metrics Grid (4 columns)
            LazyVGrid(columns: Array(repeating: GridItem(.flexible(), spacing: 8), count: 4), alignment: .leading, spacing: 8) {
                ResourceGauge(
                    title: "CPU",
                    icon: "cpu",
                    iconColor: .green,
                    value: percent(metrics["cpu"]),
                    detail: load(metrics["load1"] == .null ? "load" : "load1") + ", " + load("load5") + ", " + load("load15"),
                    fraction: metrics["cpu"] == .null ? nil : metrics["cpu"].number / 100,
                    tint: .green
                )
                ResourceGauge(
                    title: "内存",
                    icon: "memorychip",
                    iconColor: .teal,
                    value: ratio(metrics["ram"], total("ram_total", fallback: "mem_total")).map { String(format: "%.1f%%", $0 * 100) } ?? "—",
                    detail: capacity(metrics["ram"], total("ram_total", fallback: "mem_total")),
                    fraction: ratio(metrics["ram"], total("ram_total", fallback: "mem_total")),
                    tint: .teal
                )
                ResourceGauge(
                    title: "磁盘",
                    icon: "internaldrive",
                    iconColor: .orange,
                    value: ratio(metrics["disk"], total("disk_total", fallback: "disk_total")).map { String(format: "%.1f%%", $0 * 100) } ?? "—",
                    detail: capacity(metrics["disk"], total("disk_total", fallback: "disk_total")),
                    fraction: ratio(metrics["disk"], total("disk_total", fallback: "disk_total")),
                    tint: .orange
                )
                ResourceGauge(
                    title: "流量",
                    icon: "arrow.up.arrow.down",
                    iconColor: .blue,
                    value: bytes(trafficUsed),
                    detail: metrics["traffic_unlimited"].bool ? NSLocalizedString("不限额", comment: "") : bytes(trafficUsed) + " / " + bytes(node["traffic_limit"]),
                    fraction: ratio(trafficUsed, node["traffic_limit"]),
                    tint: .blue
                )
            }

            Divider().opacity(0.6)

            // Bottom Network & Quality Row (4 columns)
            HStack(alignment: .top, spacing: 8) {
                // Col 1: Real-time speed
                VStack(alignment: .leading, spacing: 3) {
                    HStack(spacing: 3) {
                        Image(systemName: "arrow.up")
                            .font(.system(size: 9, weight: .bold))
                            .foregroundColor(.green)
                        Text(metrics["net_out"] == .null ? "—" : bytes(metrics["net_out"]) + "/s")
                            .font(.system(size: 11, weight: .semibold))
                            .foregroundColor(.green)
                    }
                    HStack(spacing: 3) {
                        Image(systemName: "arrow.down")
                            .font(.system(size: 9, weight: .bold))
                            .foregroundColor(.blue)
                        Text(metrics["net_in"] == .null ? "—" : bytes(metrics["net_in"]) + "/s")
                            .font(.system(size: 11, weight: .semibold))
                            .foregroundColor(.blue)
                    }
                }
                .monospacedDigit()
                .frame(maxWidth: .infinity, alignment: .leading)

                // Col 2: Cumulative total
                VStack(alignment: .leading, spacing: 3) {
                    HStack(spacing: 3) {
                        Image(systemName: "arrow.up.circle")
                            .font(.system(size: 9))
                            .foregroundColor(.secondary)
                        Text(bytes(metrics["net_total_up"]))
                            .font(.system(size: 11))
                            .foregroundColor(.secondary)
                    }
                    HStack(spacing: 3) {
                        Image(systemName: "arrow.down.circle")
                            .font(.system(size: 9))
                            .foregroundColor(.secondary)
                        Text(bytes(metrics["net_total_down"]))
                            .font(.system(size: 11))
                            .foregroundColor(.secondary)
                    }
                }
                .monospacedDigit()
                .frame(maxWidth: .infinity, alignment: .leading)

                // Col 3 & 4: Network Health (延迟与丢包 status 条条)
                VStack(alignment: .leading, spacing: 3) {
                    HStack(spacing: 3) {
                        Text("延迟")
                            .font(.system(size: 10))
                            .foregroundColor(.secondary)
                        let summary = pingSummary
                        Text(summary.averageLatency.map { String(format: "%.0f ms", $0) } ?? (summary.allTimedOut ? NSLocalizedString("超时", comment: "") : "—"))
                            .font(.system(size: 11, weight: .semibold))
                            .foregroundColor(summary.allTimedOut ? .red : summary.averageLatency.map { $0 > 150 ? Color.red : Color.primary } ?? .secondary)
                    }
                    .lineLimit(1).minimumScaleFactor(0.65)
                    StatusBars(summary: pingSummary)
                }
                .monospacedDigit()
                .frame(maxWidth: .infinity, alignment: .leading)

                VStack(alignment: .leading, spacing: 3) {
                    HStack(spacing: 3) {
                        Text("丢包")
                            .font(.system(size: 10))
                            .foregroundColor(.secondary)
                        Text(pingSummary.averageLoss.map { String(format: "%.0f%%", $0) } ?? "—")
                            .font(.system(size: 11, weight: .semibold))
                            .foregroundColor(pingSummary.averageLoss.map { $0 > 0 ? Color.red : Color.green } ?? .secondary)
                    }
                    .lineLimit(1).minimumScaleFactor(0.65)
                    StatusBars(summary: pingSummary)
                }
                .monospacedDigit()
                .frame(maxWidth: .infinity, alignment: .leading)
            }
        }
        .padding(14)
        .background(Color(.secondarySystemGroupedBackground), in: RoundedRectangle(cornerRadius: 16))
    }
}
