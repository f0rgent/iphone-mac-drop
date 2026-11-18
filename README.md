# f0drop: flick a photo from iPhone onto your Mac

Hold the iPhone against the side of the MacBook. The Mac screen edge glows. Flick a photo off the phone toward the Mac and it slides onto the Mac screen and lands on the Desktop.

Two small apps, Apple frameworks only (SwiftUI, MultipeerConnectivity, CoreBluetooth, PhotosUI):

- `PhoneApp/`: iOS 17+. Photo grid, drag and flick a photo past the edge facing the Mac. Advertises a BLE beacon so the Mac can measure distance.
- `MacApp/`: macOS 14+ menu-bar app. Scans BLE (RSSI ≥ -40 dBm = touching) and shows a glow on the phone's side. Receives the photo over Multipeer, animates it in from that edge with a spring matched to the flick speed, saves it to `~/Desktop`.
- `Shared/`: message format and the Multipeer link (service type `f0drop`).

## Build and run

You need a Mac with full Xcode (16 or newer) and an iPhone with a cable. A free Apple ID is enough.

1. Open `F0Drop.xcodeproj` in Xcode.
2. Select target **F0Drop** → Signing & Capabilities → Team → your (Personal Team). Change the bundle identifier from `com.example.f0drop.phone` to something unique, e.g. `com.yourname.f0drop.phone`.
3. iPhone: Settings → Privacy & Security → Developer Mode → On (the phone restarts).
4. Pick the **F0Drop** scheme and your iPhone, press Run. The first time, on the iPhone: Settings → General → VPN & Device Management → your Apple ID → Trust. Then run again.
5. Pick the **F0DropMac** scheme and "My Mac", press Run. An iPhone icon appears in the menu bar.
6. Allow Local Network and Bluetooth on both devices when asked.

## Use

1. In the Mac menu-bar icon, choose which side the iPhone is on (Left / Right).
2. In the phone app, pick the edge that faces the Mac (`← left`, `right →` or `↑ top`), then tap **Photos** and pick a few.
3. Put the phone against the MacBook, drag a photo and flick it off that edge.

"Test drop" in the menu-bar app plays the landing animation without a phone.

## Notes

- Both devices need Wi-Fi and Bluetooth on. They don't have to be on the same network.
- With a free Apple ID the iPhone app expires after 7 days; just run it again from Xcode.
- The -40 dBm "touching" threshold is in `Shared/DropMessage.swift` (`touchRSSI`). Tune it for your devices.
- The Mac app writes a debug log to `~/Library/Logs/f0drop.log`.
- MVP: the Mac app is not sandboxed, and the link is unencrypted.
