import Foundation
import MultipeerConnectivity
import UserNotifications
import AppKit
import Combine


@MainActor
final class MultipeerManager: NSObject, ObservableObject {
  private let serviceType = "cowork-ping"
  let myPeerID: MCPeerID

  private var session: MCSession!
  private var advertiser: MCNearbyServiceAdvertiser!
  private var browser: MCNearbyServiceBrowser!

  @Published private(set) var nearbyPeers: [MCPeerID] = []

    private func log(_ items: @autoclosure () -> Any,
                     function: StaticString = #function,
                     line: Int = #line) {
      let ts = ISO8601DateFormatter().string(from: Date())
      print("[MultipeerManager \(ts)] \(function):\(line) - \(items())")
    }
    
  override init() {
    let displayName = UserDefaults.standard.string(forKey: "displayName")
      ?? (Host.current().localizedName ?? "Mac")
    self.myPeerID = MCPeerID(displayName: displayName)
    super.init()

    session = MCSession(peer: myPeerID,
                        securityIdentity: nil,
                        encryptionPreference: .required)
    session.delegate = self

    advertiser = MCNearbyServiceAdvertiser(
      peer: myPeerID,
      discoveryInfo: ["role": "coworker"],
      serviceType: serviceType
    )
    advertiser.delegate = self

    browser = MCNearbyServiceBrowser(peer: myPeerID, serviceType: serviceType)
    browser.delegate = self
  }

  func start() {
    advertiser.startAdvertisingPeer()
    browser.startBrowsingForPeers()
  }

  func stop() {
    advertiser.stopAdvertisingPeer()
    browser.stopBrowsingForPeers()
    nearbyPeers.removeAll()
  }

  func invite(_ peer: MCPeerID) {
    // MainActor context, safe to touch browser/session directly
    browser.invitePeer(peer, to: session, withContext: nil, timeout: 10)
  }

  func trySendPing(to peer: MCPeerID, note: String?) async {
    do {
      try sendPing(to: peer, note: note)
    } catch {
      invite(peer)
      try? await Task.sleep(nanoseconds: 700_000_000)
      try? sendPing(to: peer, note: note)
    }
  }

  private func sendPing(to peer: MCPeerID, note: String?) throws {
    // On MainActor, safe to touch session
    guard session.connectedPeers.contains(peer) else {
      throw NSError(domain: "Ping", code: 1,
                    userInfo: [NSLocalizedDescriptionKey: "Peer not connected"])
    }
    let payload: [String: Any] = [
      "type": "ping",
      "from": myPeerID.displayName,
      "timestamp": Date().timeIntervalSince1970,
      "note": note ?? ""
    ]
    let data = try JSONSerialization.data(withJSONObject: payload, options: [])
    try session.send(data, toPeers: [peer], with: .reliable)
  }

  private func notifyPing(from name: String, note: String) {
    let content = UNMutableNotificationContent()
    content.title = "Ping from \(name)"
    if !note.isEmpty { content.body = note }
    content.sound = .default
    let request = UNNotificationRequest(
      identifier: UUID().uuidString,
      content: content,
      trigger: nil
    )
    UNUserNotificationCenter.current().add(request)
  }
}

extension MultipeerManager: MCSessionDelegate {
    nonisolated func session(_ session: MCSession,
                             peer peerID: MCPeerID,
                             didChange state: MCSessionState) {
      let stateDesc: String = {
        switch state {
        case .notConnected: return "notConnected"
        case .connecting: return "connecting"
        case .connected: return "connected"
        @unknown default: return "unknown"
        }
      }()
      Task { @MainActor in
        self.log("Session state change: \(peerID.displayName) -> \(stateDesc). Now connected: \(session.connectedPeers.map { $0.displayName })")
      }
    }

    nonisolated func session(_ session: MCSession,
                             didReceive data: Data,
                             fromPeer peerID: MCPeerID) {
      Task { @MainActor in
        self.log("didReceive \(data.count) bytes from \(peerID.displayName)")
        do {
          let obj = try JSONSerialization.jsonObject(with: data, options: [])
          self.log("Parsed JSON: \(obj)")
          guard let json = obj as? [String: Any],
                json["type"] as? String == "ping" else {
            self.log("Received data is not a 'ping' message")
            return
          }
          let note = (json["note"] as? String) ?? ""
          NSApp.requestUserAttention(.informationalRequest)
          self.notifyPing(from: peerID.displayName, note: note)
        } catch {
          self.log("JSON parse error: \(error.localizedDescription)")
        }
      }
    }

    nonisolated func session(_ session: MCSession,
                             didReceive certificate: [Any]?,
                             fromPeer peerID: MCPeerID,
                             certificateHandler: @escaping (Bool) -> Void) {
      Task { @MainActor in
        self.log("Received certificate from \(peerID.displayName). Auto-accepting.")
        certificateHandler(true)
      }
    }

  nonisolated func session(_ session: MCSession,
                           didReceive stream: InputStream,
                           withName streamName: String,
                           fromPeer peerID: MCPeerID) {}

  nonisolated func session(_ session: MCSession,
                           didStartReceivingResourceWithName resourceName: String,
                           fromPeer peerID: MCPeerID,
                           with progress: Progress) {}

  nonisolated func session(_ session: MCSession,
                           didFinishReceivingResourceWithName resourceName: String,
                           fromPeer peerID: MCPeerID,
                           at localURL: URL?,
                           withError error: Error?) {}

}

extension MultipeerManager: MCNearbyServiceAdvertiserDelegate, MCNearbyServiceBrowserDelegate {
  nonisolated func advertiser(_ advertiser: MCNearbyServiceAdvertiser,
                              didReceiveInvitationFromPeer peerID: MCPeerID,
                              withContext context: Data?,
                              invitationHandler: @escaping (Bool, MCSession?) -> Void) {
    // Hop to MainActor to supply our main-actor session
    Task { @MainActor in
      invitationHandler(true, self.session)
    }
  }

  nonisolated func browser(_ browser: MCNearbyServiceBrowser,
                           foundPeer peerID: MCPeerID,
                           withDiscoveryInfo info: [String : String]?) {
    Task { @MainActor in
      if !self.nearbyPeers.contains(peerID) { self.nearbyPeers.append(peerID) }
    }
  }

  nonisolated func browser(_ browser: MCNearbyServiceBrowser,
                           lostPeer peerID: MCPeerID) {
    Task { @MainActor in
      self.nearbyPeers.removeAll { $0 == peerID }
    }
  }
}
