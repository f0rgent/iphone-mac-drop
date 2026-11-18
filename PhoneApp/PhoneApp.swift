import SwiftUI

@main
struct PhoneApp: App {
    @StateObject private var link = PeerLink(role: .browser)
    @StateObject private var beacon = BLEBeacon()

    var body: some Scene {
        WindowGroup {
            ContentView()
                .environmentObject(link)
                .environmentObject(beacon)
        }
    }
}
