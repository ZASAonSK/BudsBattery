import Foundation

/// Battery levels (0...100) broadcast by Galaxy Buds. `nil` = not reported.
struct BudsBattery: Equatable {
    var left: Int?
    var right: Int?
    var caseLevel: Int?
    /// 6-byte set identity; stable across rotating BLE addresses.
    let token: Data
}

/// Samsung manufacturer data (company 0x0075) with the Buds "Easy Setup" header.
/// iOS merges advertisement + scan response into one blob:
///
///   [0..<11]  75 00 | 42 09 81 02 14 15 03 21 01
///   [26]      status byte (meaning unknown)
///   [27..<33] set token
///   [33...]   case, left, right (1...3 bytes; 0xFF/>100 = unavailable)
///   [last 3]  suffix
///
/// Layout is inferred from captured Buds3 Pro frames, not a published protocol.
enum BudsDecoder {
    static let header: [UInt8] = [0x75, 0x00, 0x42, 0x09, 0x81, 0x02, 0x14, 0x15, 0x03, 0x21, 0x01]
    private static let tokenRange = 27..<33
    private static let valuesStart = 33
    private static let suffixLength = 3

    static func decode(_ data: Data) -> BudsBattery? {
        let b = [UInt8](data)
        guard b.count >= valuesStart + 1 + suffixLength, b.starts(with: header) else { return nil }
        let values = b[valuesStart..<(b.count - suffixLength)]
        guard values.count <= 6 else { return nil }
        func percent(_ i: Int) -> Int? {
            let index = valuesStart + i
            return index < b.count - suffixLength && b[index] <= 100 ? Int(b[index]) : nil
        }
        return BudsBattery(left: percent(1), right: percent(2), caseLevel: percent(0),
                           token: Data(b[tokenRange]))
    }
}
