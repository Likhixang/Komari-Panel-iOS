import Foundation

/// Equal-weight mean across monitored targets, never an arbitrary first target.
/// Komari's `latest` is the latest successful sample within its one-hour window;
/// a negative value means that target has no successful sample in that window.
struct PingSummary {
    let averageLatency: Double?
    let averageLoss: Double?
    let validCount: Int
    let timeoutCount: Int
    var allTimedOut: Bool { validCount == 0 && timeoutCount > 0 }

    init(_ targets: JSON) {
        let samples = targets.object.values.compactMap { target -> Double? in
            guard case .number(let value) = target["latest"], value.isFinite else { return nil }
            return value
        }
        let valid = samples.filter { $0 >= 0 }
        let losses = targets.object.values.compactMap { target -> Double? in
            guard case .number(let value) = target["loss"], value.isFinite,
                  (0...100).contains(value) else { return nil }
            return value
        }
        validCount = valid.count
        timeoutCount = samples.filter { $0 < 0 }.count
        // Dividing before summation also avoids overflowing on extreme input.
        averageLatency = valid.isEmpty ? nil : valid.reduce(0) { $0 + $1 / Double(valid.count) }
        averageLoss = losses.isEmpty ? nil : losses.reduce(0) { $0 + $1 / Double(losses.count) }
    }
}
