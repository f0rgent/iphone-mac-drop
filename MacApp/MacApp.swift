import SwiftUI
import AppKit
import Combine

enum PhoneSide: String, CaseIterable, Identifiable {
    case left, right
    var id: String { rawValue }
}

/// Everything the Mac side needs, shared by the menu and the overlay.
final class MacModel: ObservableObject {
    let link = PeerLink(role: .advertiser)
    let scanner = ProximityScanner()
    let overlay = OverlayController()

    @Published var phoneSide: PhoneSide {
        didSet { UserDefaults.standard.set(phoneSide.rawValue, forKey: "phoneSide") }
    }
    @Published var lastSaved: URL?
    private var bag = Set<AnyCancellable>()

    init() {
        phoneSide = PhoneSide(rawValue: UserDefaults.standard.string(forKey: "phoneSide") ?? "") ?? .right
        overlay.show(model: self)
        link.onReceive = { [weak self] msg in self?.receive(msg) }
        // Re-publish child changes so the menu refreshes.
        link.objectWillChange.sink { [weak self] in self?.objectWillChange.send() }.store(in: &bag)
        scanner.objectWillChange.sink { [weak self] in self?.objectWillChange.send() }.store(in: &bag)
    }

    func receive(_ msg: DropMessage) {
        let url = saveToDesktop(msg)
        lastSaved = url
        overlay.arrive(msg, side: phoneSide)
    }

    private func saveToDesktop(_ msg: DropMessage) -> URL? {
        let desktop = FileManager.default.homeDirectoryForCurrentUser.appendingPathComponent("Desktop")
        let base = (msg.fileName as NSString).deletingPathExtension
        let ext = (msg.fileName as NSString).pathExtension
        var url = desktop.appendingPathComponent(msg.fileName)
        var n = 2
        while FileManager.default.fileExists(atPath: url.path) {
            url = desktop.appendingPathComponent("\(base) \(n)").appendingPathExtension(ext)
            n += 1
        }
        do { try msg.data.write(to: url); return url } catch { NSLog("f0drop save failed: \(error)"); return nil }
    }

    /// Fake drop so the animation can be checked without a phone.
    func testDrop() {
        let img = NSImage(systemSymbolName: "photo.fill", accessibilityDescription: nil)!
        let rep = NSBitmapImageRep(data: img.tiffRepresentation!)!
        let png = rep.representation(using: .png, properties: [:])!
        let msg = DropMessage(fileName: "f0drop-test.png", data: png, edge: phoneSide == .left ? .right : .left,
                              position: Double.random(in: 0.3...0.7), velocityX: 1800, velocityY: -200)
        overlay.arrive(msg, side: phoneSide)
    }
}

@main
struct MacApp: App {
    @StateObject private var model = MacModel()

    var body: some Scene {
        MenuBarExtra("f0drop", systemImage: model.scanner.touching ? "iphone.radiowaves.left.and.right" : "iphone") {
            MenuContent().environmentObject(model)
        }
        .menuBarExtraStyle(.window)
    }
}

struct MenuContent: View {
    @EnvironmentObject var model: MacModel

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            Text("f0drop").font(.headline)
            Label(model.link.connectedPeers.first.map { "Linked: \($0)" } ?? "Waiting for iPhone app…",
                  systemImage: model.link.connectedPeers.isEmpty ? "wifi.slash" : "wifi")
            Label(model.scanner.rssi.map { "RSSI \($0) dBm\(model.scanner.touching ? " · touching" : "")" }
                  ?? "BLE: \(model.scanner.state)",
                  systemImage: "dot.radiowaves.left.and.right")
            Picker("iPhone is on the", selection: $model.phoneSide) {
                Text("Left").tag(PhoneSide.left)
                Text("Right").tag(PhoneSide.right)
            }
            .pickerStyle(.segmented)
            if let url = model.lastSaved {
                Button("Show last: \(url.lastPathComponent)") { NSWorkspace.shared.activateFileViewerSelecting([url]) }
            }
            Divider()
            HStack {
                Button("Test drop") { model.testDrop() }
                Spacer()
                Button("Quit") { NSApp.terminate(nil) }
            }
        }
        .padding(14)
        .frame(width: 280)
    }
}
