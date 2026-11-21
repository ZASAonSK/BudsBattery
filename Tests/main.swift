import Foundation

func data(_ s: String) -> Data { Data(s.split(separator: " ").map { UInt8($0, radix: 16)! }) }

// 39-byte frame shaped like a Buds3 Pro broadcast (set token replaced by a dummy): case 44, left 88, right 88.
let frame = data("75 00 42 09 81 02 14 15 03 21 01 08 A2 0C 01 54 06 3C 00 00 00 00 00 00 00 00 00 11 22 33 44 55 66 2C 58 58 00 03 14")
precondition(frame.count == 39)
let full = BudsDecoder.decode(frame)!
precondition(full.caseLevel == 44 && full.left == 88 && full.right == 88)
precondition(full.token == data("11 22 33 44 55 66"))

// Each channel is independent; >100 (e.g. 255) means unavailable.
for (index, name) in [(33, "case"), (34, "left"), (35, "right")] {
    var b = [UInt8](frame); b[index] = 255
    let p = BudsDecoder.decode(Data(b))!
    let values = [p.caseLevel, p.left, p.right]
    precondition(values[index - 33] == nil, name)
    precondition(values.compactMap { $0 }.count == 2, name)
}
var zero = [UInt8](frame); zero[34] = 0
precondition(BudsDecoder.decode(Data(zero))?.left == 0)

// Shortened scan response: fewer battery bytes still decode what is present.
let two = Data(frame.prefix(26)) + data("00 11 22 33 44 55 66 2C 58 00 03 14")
let partial = BudsDecoder.decode(two)!
precondition(partial.caseLevel == 44 && partial.left == 88 && partial.right == nil)

// Rejected: advertising-only, truncated, wrong company, wrong header.
precondition(BudsDecoder.decode(Data(frame.prefix(26))) == nil)
for n in 0..<37 { precondition(BudsDecoder.decode(Data(frame.prefix(n))) == nil) }
precondition(BudsDecoder.decode(data("4C 00") + frame.dropFirst(2)) == nil)
var wrong = [UInt8](frame); wrong[10] = 2
precondition(BudsDecoder.decode(Data(wrong)) == nil)

print("BudsDecoder checks passed")

// History analytics.
let t0 = Date(timeIntervalSince1970: 1_000_000)
func at(_ minutes: Double, _ l: Int?) -> Sample { Sample(date: t0.addingTimeInterval(minutes * 60), l: l, r: nil, c: nil) }
let drain = [at(0, 90), at(30, 85), at(60, 80)]
precondition(drain.trend(\.l, now: t0.addingTimeInterval(61 * 60)) == .down)
let eta = drain.remaining(\.l)!   // 10 % per hour, 80 % left -> 8 h
precondition(abs(eta - 8 * 3600) < 1)
let charge = [at(0, 50), at(20, 60)]
precondition(charge.trend(\.l, now: t0.addingTimeInterval(21 * 60)) == .up)
precondition(charge.remaining(\.l) == nil)
precondition(drain.trend(\.l, now: t0.addingTimeInterval(5 * 3600)) == nil)   // stale
precondition([at(0, 90), at(5, 88)].remaining(\.l) == nil)                    // too short
precondition(([at(0, 50), at(30, 70), at(60, 68), at(90, 64)].remaining(\.l)!) > 0) // only the last discharge run
print("History checks passed")
