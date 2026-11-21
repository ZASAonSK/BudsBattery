import Foundation

/// One point in time where at least one battery value changed.
struct Sample: Codable, Identifiable {
    let date: Date
    let l: Int?
    let r: Int?
    let c: Int?
    var id: Date { date }
}

enum Trend { case up, down }

extension Array where Element == Sample {
    private func points(_ kp: KeyPath<Sample, Int?>) -> [(date: Date, value: Int)] {
        compactMap { s in s[keyPath: kp].map { (s.date, $0) } }
    }

    /// Direction of the last change of a channel; nil if unchanged for over an hour.
    func trend(_ kp: KeyPath<Sample, Int?>, now: Date = Date()) -> Trend? {
        let pts = points(kp)
        guard let last = pts.last, now.timeIntervalSince(last.date) < 3600,
              let previous = pts.last(where: { $0.value != last.value }) else { return nil }
        return last.value > previous.value ? .up : .down
    }

    /// Estimated seconds until empty, from the current discharge run
    /// (at least 10 minutes long and at least 2 % drop). nil if not discharging.
    func remaining(_ kp: KeyPath<Sample, Int?>) -> TimeInterval? {
        let pts = points(kp)
        guard var first = pts.last else { return nil }
        let last = first
        for p in pts.reversed() {
            if p.value < first.value { break }   // an earlier, lower value means it was charging
            first = p
        }
        let hours = last.date.timeIntervalSince(first.date) / 3600
        let drop = first.value - last.value
        guard hours >= 10.0 / 60, drop >= 2, last.value > 0 else { return nil }
        return Double(last.value) / (Double(drop) / hours) * 3600
    }
}
