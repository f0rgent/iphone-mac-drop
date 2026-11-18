import Foundation
import MultipeerConnectivity

#if os(iOS)
import UIKit
private let localName = UIDevice.current.name
#else
private let localName = Host.current().localizedName ?? "Mac"
#endif

/// Thin MultipeerConnectivity wrapper.
/// The Mac advertises; the phone browses and invites. Everyone auto-accepts (MVP).
final class PeerLink: NSObject, ObservableObject {
    enum Role { case advertiser, browser }

    @Published private(set) var connectedPeers: [String] = []
    var onReceive: ((DropMessage) -> Void)?

    private let myPeer = MCPeerID(displayName: localName)
    private var session: MCSession
    private var advertiser: MCNearbyServiceAdvertiser?
    private var browser: MCNearbyServiceBrowser?
    private var watchdog: Timer?
    private var lastInvite = Date.distantPast

    init(role: Role) {
        session = MCSession(peer: myPeer, securityIdentity: nil, encryptionPreference: .none)
        super.init()
        session.delegate = self
        switch role {
        case .advertiser:
            let a = MCNearbyServiceAdvertiser(peer: myPeer, discoveryInfo: nil, serviceType: F0Drop.serviceType)
            a.delegate = self
            a.startAdvertisingPeer()
            dlog("advertising as \(myPeer.displayName)")
            advertiser = a
        case .browser:
            let b = MCNearbyServiceBrowser(peer: myPeer, serviceType: F0Drop.serviceType)
            b.delegate = self
            b.startBrowsingForPeers()
            browser = b
            // Multipeer links sometimes drop right after connecting. If we're not connected,
            // restart browsing so foundPeer fires again and we re-invite.
            watchdog = Timer.scheduledTimer(withTimeInterval: 3, repeats: true) { [weak self] _ in
                guard let self, self.session.connectedPeers.isEmpty, let b = self.browser else { return }
                b.stopBrowsingForPeers()
                b.startBrowsingForPeers()
            }
        }
    }

    /// Fresh session, so a half-dead connection can't block the next one.
    private func resetSession() {
        session.disconnect()
        session = MCSession(peer: myPeer, securityIdentity: nil, encryptionPreference: .none)
        session.delegate = self
    }

    var isConnected: Bool { !session.connectedPeers.isEmpty }

    func send(_ message: DropMessage) throws {
        guard !session.connectedPeers.isEmpty else { throw NSError(domain: "f0drop", code: 1, userInfo: [NSLocalizedDescriptionKey: "No Mac connected"]) }
        let data = try PropertyListEncoder().encode(message)
        try session.send(data, toPeers: session.connectedPeers, with: .reliable)
    }

    private func refreshPeers() {
        let names = session.connectedPeers.map(\.displayName)
        DispatchQueue.main.async { self.connectedPeers = names }
    }
}

extension PeerLink: MCSessionDelegate {
    func session(_ session: MCSession, peer peerID: MCPeerID, didChange state: MCSessionState) {
        dlog("peer \(peerID.displayName) state \(state.rawValue)")
        refreshPeers()
        // If the link drops, the browser will see the peer again and re-invite.
    }

    func session(_ session: MCSession, didReceive data: Data, fromPeer peerID: MCPeerID) {
        guard let msg = try? PropertyListDecoder().decode(DropMessage.self, from: data) else { dlog("bad message"); return }
        dlog("received \(msg.fileName) \(msg.data.count) bytes edge \(msg.edge.rawValue) pos \(msg.position) speed \(Int(msg.speed))")
        DispatchQueue.main.async { self.onReceive?(msg) }
    }

    func session(_ session: MCSession, didReceive stream: InputStream, withName streamName: String, fromPeer peerID: MCPeerID) {}
    func session(_ session: MCSession, didStartReceivingResourceWithName resourceName: String, fromPeer peerID: MCPeerID, with progress: Progress) {}
    func session(_ session: MCSession, didFinishReceivingResourceWithName resourceName: String, fromPeer peerID: MCPeerID, at localURL: URL?, withError error: Error?) {}
}

extension PeerLink: MCNearbyServiceAdvertiserDelegate {
    func advertiser(_ advertiser: MCNearbyServiceAdvertiser, didReceiveInvitationFromPeer peerID: MCPeerID, withContext context: Data?, invitationHandler: @escaping (Bool, MCSession?) -> Void) {
        dlog("invitation from \(peerID.displayName)")
        if session.connectedPeers.isEmpty { resetSession() }
        invitationHandler(true, session)
    }

    func advertiser(_ advertiser: MCNearbyServiceAdvertiser, didNotStartAdvertisingPeer error: Error) {
        dlog("advertise failed: \(error)")
    }
}

extension PeerLink: MCNearbyServiceBrowserDelegate {
    func browser(_ browser: MCNearbyServiceBrowser, foundPeer peerID: MCPeerID, withDiscoveryInfo info: [String: String]?) {
        dlog("found \(peerID.displayName)")
        guard session.connectedPeers.isEmpty, Date().timeIntervalSince(lastInvite) > 8 else { return }
        lastInvite = Date()
        resetSession()
        browser.invitePeer(peerID, to: session, withContext: nil, timeout: 15)
    }

    func browser(_ browser: MCNearbyServiceBrowser, didNotStartBrowsingForPeers error: Error) {
        dlog("browse failed: \(error)")
    }

    func browser(_ browser: MCNearbyServiceBrowser, lostPeer peerID: MCPeerID) {}
}
