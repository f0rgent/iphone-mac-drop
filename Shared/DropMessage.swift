import Foundation

/// Which edge of the phone screen the photo left through.
enum DropEdge: String, Codable, CaseIterable, Identifiable {
    case left, right, top
    var id: String { rawValue }
}

/// One file flicked from the phone to the Mac.
struct DropMessage: Codable {
    var fileName: String
    var data: Data
    var edge: DropEdge
    /// Where along the exit edge the photo left, 0...1 (top→bottom for side edges, left→right for top).
    var position: Double
    /// Flick velocity in points per second at release (x, y in phone coordinates).
    var velocityX: Double
    var velocityY: Double

    var speed: Double { (velocityX * velocityX + velocityY * velocityY).squareRoot() }
}

enum F0Drop {
    /// Bonjour service type for MultipeerConnectivity (max 15 chars, a-z0-9-).
    static let serviceType = "f0drop"
    /// BLE service the phone advertises so the Mac can measure RSSI.
    static let bleServiceUUID = "7B6E2A10-4F0D-4C2B-9C1E-F0D20B0A0001"
    /// RSSI at or above this counts as "touching".
    static let touchRSSI = -40
}

/// Debug log: NSLog everywhere, plus ~/Library/Logs/f0drop.log on the Mac.
func dlog(_ text: String) {
    NSLog("f0drop: %@", text)
    #if os(macOS)
    let url = FileManager.default.homeDirectoryForCurrentUser.appendingPathComponent("Library/Logs/f0drop.log")
    let line = "\(Date()) \(text)\n"
    if let h = try? FileHandle(forWritingTo: url) { h.seekToEndOfFile(); h.write(line.data(using: .utf8)!); try? h.close() }
    else { try? line.data(using: .utf8)!.write(to: url) }
    #endif
}
