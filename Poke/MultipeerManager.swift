import AppKit
import Combine
import Foundation
import MultipeerConnectivity
import UserNotifications

struct PeerHistory: Codable {
    let peerID: String
    let displayName: String
    let lastSeen: Date
}

@MainActor
final class MultipeerManager: NSObject, ObservableObject {
    private let serviceType = "poke-service"
    let myPeerID: MCPeerID

    private var session: MCSession!
    private var advertiser: MCNearbyServiceAdvertiser!
    private var browser: MCNearbyServiceBrowser!
    private var httpServer: RaycastHTTPServer?

    @Published private(set) var nearbyPeers: [MCPeerID] = []
    @Published private(set) var peerHistory: [PeerHistory] = []
    @Published private(set) var isVisible: Bool = true

    enum PokeDeliveryState {
        case sending
        case delivered
        case failed
    }

    struct TimedPokeStatus {
        let state: PokeDeliveryState
        let timestamp: Date
    }

    // Last poke delivery status per peer (keyed by displayName)
    @Published private(set) var lastPokeStatus: [String: TimedPokeStatus] = [:]

    // MARK: - Delivery/Acknowledgement

    // Store continuations waiting for ACKs keyed by message ID
    private var pendingAcks: [String: CheckedContinuation<Void, Error>] = [:]
    // Track seen poke IDs to avoid duplicate notifications on retries
    private var seenPokeIDs: Set<String> = []
    private let ackTimeout: TimeInterval = 3.0
    private let maxAckRetries: Int = 2
    
    // Poke status cleanup timeout (5 seconds in nanoseconds)
    private let pokeStatusCleanupDelay: UInt64 = 5_000_000_000

    private let historyTimeLimit: TimeInterval = 24 * 60 * 60 // 24 hours
    private let userDefaults = UserDefaults.standard
    private let peerHistoryKey = "Poke_PeerHistory"
    private let visiblePrefKey = "Poke_VisiblePreference"

    private func log(_ items: @autoclosure () -> Any,
                     function: StaticString = #function,
                     line: Int = #line)
    {
        let ts = ISO8601DateFormatter().string(from: Date())
        print("[MultipeerManager \(ts)] \(function):\(line) - \(items())")
    }

    override init() {
        let displayName = UserDefaults.standard.string(forKey: "displayName")
            ?? (Host.current().localizedName ?? "Mac")
        myPeerID = MCPeerID(displayName: displayName)
        super.init()

        createTransport()
        // Start local HTTP server for Raycast integration
        let server = RaycastHTTPServer(manager: self)
        httpServer = server
        server.start()

        loadPeerHistory()

        // Load visibility preference (default to true on first launch)
        if userDefaults.object(forKey: visiblePrefKey) == nil {
            userDefaults.set(true, forKey: visiblePrefKey)
        }
        isVisible = userDefaults.bool(forKey: visiblePrefKey)
        if isVisible {
            start()
        }

        // Defensively enforce visibility on app activation
        NotificationCenter.default.addObserver(
            forName: NSApplication.didBecomeActiveNotification,
            object: nil,
            queue: .main
        ) { [weak self] _ in
            Task { @MainActor [weak self] in
                guard let self = self else { return }
                if self.isVisible {
                    // Ensure we're advertising/browsing when visible
                    self.start()
                } else {
                    // Ensure everything remains torn down when hidden
                    self.stop()
                }
            }
        }
    }

    deinit {
        NotificationCenter.default.removeObserver(self)
        let server = httpServer
        Task { @MainActor in
            server?.stop()
        }
    }

    private func createTransport() {
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

    private func teardownTransport() {
        session?.disconnect()
        advertiser?.stopAdvertisingPeer()
        browser?.stopBrowsingForPeers()
        advertiser = nil
        browser = nil
        session = nil
    }

    func start() {
        if session == nil || advertiser == nil || browser == nil {
            createTransport()
        }
        advertiser.startAdvertisingPeer()
        browser.startBrowsingForPeers()
        broadcastPresence(isVisible: true)
        // Persist
        isVisible = true
        userDefaults.set(true, forKey: visiblePrefKey)
    }

    func stop() {
        // Best-effort notify connected peers that we're going invisible
        broadcastPresence(isVisible: false)
        // Fully tear down to avoid inadvertent advertising on activation
        teardownTransport()
        nearbyPeers.removeAll()
        // Persist
        isVisible = false
        userDefaults.set(false, forKey: visiblePrefKey)
    }

    func setVisible(_ visible: Bool) {
        if visible { start() } else { stop() }
    }

    func invite(_ peer: MCPeerID) {
        // MainActor context, safe to touch browser/session directly
        guard isVisible, let browser = browser, let session = session else { return }
        browser.invitePeer(peer, to: session, withContext: nil, timeout: 10)
    }

    func trySendPoke(to peer: MCPeerID, note: String?) async -> Bool {
        // Ensure message is processed by recipient using app-level ACKs with retry
        lastPokeStatus[peer.displayName] = TimedPokeStatus(state: .sending, timestamp: Date())
        let delivered = await sendPokeEnsuringReceipt(to: peer, note: note)
        lastPokeStatus[peer.displayName] = TimedPokeStatus(
            state: delivered ? .delivered : .failed, 
            timestamp: Date()
        )
        
        // Schedule cleanup after 5 seconds
        Task { [weak self] in
            try? await Task.sleep(nanoseconds: self?.pokeStatusCleanupDelay ?? 5_000_000_000)
            await MainActor.run {
                self?.cleanupOldPokeStatus(for: peer.displayName)
            }
        }
        
        return delivered
    }

    private func cleanupOldPokeStatus(for peerDisplayName: String) {
        // Only remove if the status is older than 5 seconds
        if let status = lastPokeStatus[peerDisplayName] {
            let elapsed = Date().timeIntervalSince(status.timestamp)
            if elapsed >= 5.0 {
                lastPokeStatus.removeValue(forKey: peerDisplayName)
                log("Cleaned up old poke status for \(peerDisplayName)")
            }
        }
    }

    private func sendPoke(to peer: MCPeerID, note: String?, id: String) throws {
        // On MainActor, safe to touch session
        guard let session = session, session.connectedPeers.contains(peer) else {
            throw NSError(domain: "Poke", code: 1,
                          userInfo: [NSLocalizedDescriptionKey: "Peer not connected"])
        }
        let payload: [String: Any] = [
            "type": "poke",
            "from": myPeerID.displayName,
            "timestamp": Date().timeIntervalSince1970,
            "note": note ?? "",
            "id": id,
        ]
        let data = try JSONSerialization.data(withJSONObject: payload, options: [])
        try session.send(data, toPeers: [peer], with: .reliable)
    }

    private func sendPokeEnsuringReceipt(to peer: MCPeerID, note: String?) async -> Bool {
        // If we're hidden or transport is down, fail fast
        guard isVisible, let _ = session else { return false }
        let messageID = UUID().uuidString
        var attempt = 0
        while attempt <= maxAckRetries {
            do {
                if let session = session, !session.connectedPeers.contains(peer) {
                    // Attempt to connect and give it a moment
                    invite(peer)
                    try? await Task.sleep(nanoseconds: 700_000_000)
                }
                try sendPoke(to: peer, note: note, id: messageID)
                log("Sent poke id=\(messageID) to \(peer.displayName) (attempt \(attempt + 1))")
                // Wait for ACK with timeout
                try await awaitAck(for: messageID, timeout: ackTimeout)
                log("ACK received for id=\(messageID) from \(peer.displayName)")
                return true
            } catch {
                attempt += 1
                log("ACK wait failed for id=\(messageID): \(error.localizedDescription). Attempt \(attempt) of \(maxAckRetries + 1)")
                if attempt > maxAckRetries { break }
                // Exponential backoff before retry
                let backoff = UInt64(pow(2.0, Double(attempt - 1)) * 500_000_000) // 0.5s, 1s, 2s...
                try? await Task.sleep(nanoseconds: backoff)
            }
        }
        log("Failed to confirm delivery for id=\(messageID) to \(peer.displayName)")
        return false
    }

    private func awaitAck(for id: String, timeout: TimeInterval) async throws {
        try await withCheckedThrowingContinuation { (continuation: CheckedContinuation<Void, Error>) in
            // Register continuation
            self.pendingAcks[id] = continuation
            // Timeout task
            Task { [weak self] in
                // Sleep on a background task, then resume on main
                let ns = UInt64(max(timeout, 0) * 1_000_000_000)
                try? await Task.sleep(nanoseconds: ns)
                await MainActor.run {
                    guard let self = self else { return }
                    if let cont = self.pendingAcks.removeValue(forKey: id) {
                        cont.resume(throwing: NSError(domain: "PokeACK", code: 2, userInfo: [NSLocalizedDescriptionKey: "ACK timeout"]))
                    }
                }
            }
        }
    }

    // MARK: - Presence

    private func broadcastPresence(isVisible: Bool) {
        guard let session = session, !session.connectedPeers.isEmpty else { return }
        let payload: [String: Any] = [
            "type": "presence",
            "visible": isVisible,
        ]
        guard let data = try? JSONSerialization.data(withJSONObject: payload, options: []) else { return }
        do {
            try session.send(data, toPeers: session.connectedPeers, with: .reliable)
            log("Broadcasted presence visible=\(isVisible) to peers: \(session.connectedPeers.map { $0.displayName })")
        } catch {
            log("Failed broadcasting presence: \(error.localizedDescription)")
        }
    }

    private func notifyPoke(from name: String, note: String) {
        let content = UNMutableNotificationContent()
        content.title = "Poke from \(name)"
        if !note.isEmpty { content.body = note }
        content.sound = .default
        let request = UNNotificationRequest(
            identifier: UUID().uuidString,
            content: content,
            trigger: nil
        )
        UNUserNotificationCenter.current().add(request)
    }

    // MARK: - Peer History Management

    private func loadPeerHistory() {
        guard let data = userDefaults.data(forKey: peerHistoryKey),
              let history = try? JSONDecoder().decode([PeerHistory].self, from: data)
        else {
            peerHistory = []
            return
        }

        // Filter out entries older than the time limit
        let cutoff = Date().addingTimeInterval(-historyTimeLimit)
        peerHistory = history.filter { $0.lastSeen >= cutoff }

        // Save the filtered history back
        savePeerHistory()
    }

    private func savePeerHistory() {
        guard let data = try? JSONEncoder().encode(peerHistory) else { return }
        userDefaults.set(data, forKey: peerHistoryKey)
    }

    private func updatePeerHistory(for peerID: MCPeerID) {
        let now = Date()

        // Remove existing entry for this peer
        peerHistory.removeAll { $0.peerID == peerID.displayName }

        // Add new entry
        let newEntry = PeerHistory(
            peerID: peerID.displayName,
            displayName: peerID.displayName,
            lastSeen: now
        )
        peerHistory.append(newEntry)

        // Clean up old entries
        let cutoff = now.addingTimeInterval(-historyTimeLimit)
        peerHistory = peerHistory.filter { $0.lastSeen >= cutoff }

        savePeerHistory()
    }

    func getRecentlySeenPeers() -> [PeerHistory] {
        let cutoff = Date().addingTimeInterval(-historyTimeLimit)
        return peerHistory.filter { history in
            history.lastSeen >= cutoff && !nearbyPeers.contains { peer in
                peer.displayName == history.peerID
            }
        }
    }
}

extension MultipeerManager: MCSessionDelegate {
    nonisolated func session(_ session: MCSession,
                             peer peerID: MCPeerID,
                             didChange state: MCSessionState)
    {
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

    nonisolated func session(_: MCSession,
                             didReceive data: Data,
                             fromPeer peerID: MCPeerID)
    {
        Task { @MainActor in
            self.log("didReceive \(data.count) bytes from \(peerID.displayName)")
            do {
                let obj = try JSONSerialization.jsonObject(with: data, options: [])
                self.log("Parsed JSON: \(obj)")
                guard let json = obj as? [String: Any], let type = json["type"] as? String else {
                    self.log("Received data is not a recognized JSON message")
                    return
                }

                switch type {
                case "poke":
                    let note = (json["note"] as? String) ?? ""
                    let messageID = (json["id"] as? String) ?? ""

                    // De-duplicate pokes by message ID to avoid duplicate notifications
                    var shouldNotify = true
                    if !messageID.isEmpty {
                        if self.seenPokeIDs.contains(messageID) {
                            shouldNotify = false
                        } else {
                            self.seenPokeIDs.insert(messageID)
                            // Best-effort trimming to keep memory bounded
                            if self.seenPokeIDs.count > 500 {
                                self.seenPokeIDs.remove(self.seenPokeIDs.first!)
                            }
                        }
                    }

                    if shouldNotify {
                        NSApp.requestUserAttention(.informationalRequest)
                        self.notifyPoke(from: peerID.displayName, note: note)
                    }

                    // Always send ACK back (even if duplicate) when ID is present
                    if !messageID.isEmpty {
                        let ackPayload: [String: Any] = [
                            "type": "ack",
                            "id": messageID,
                        ]
                        if let ackData = try? JSONSerialization.data(withJSONObject: ackPayload, options: []) {
                            do {
                                try self.session.send(ackData, toPeers: [peerID], with: .reliable)
                                self.log("Sent ACK for id=\(messageID) to \(peerID.displayName)")
                            } catch {
                                self.log("Failed to send ACK: \(error.localizedDescription)")
                            }
                        }
                    }

                case "ack":
                    guard let ackID = json["id"] as? String else {
                        self.log("ACK missing id; ignoring")
                        return
                    }
                    if let cont = self.pendingAcks.removeValue(forKey: ackID) {
                        cont.resume()
                        self.log("ACK matched and resumed for id=\(ackID)")
                    } else {
                        self.log("ACK for unknown id=\(ackID); possibly timed out")
                    }

                case "presence":
                    let visible = (json["visible"] as? Bool) ?? true
                    if !visible {
                        // Remove from nearby list and update history immediately
                        self.nearbyPeers.removeAll { $0 == peerID }
                        self.updatePeerHistory(for: peerID)
                        self.log("Peer \(peerID.displayName) set visibility=false; marked offline")
                    }

                default:
                    self.log("Received unknown message type: \(type)")
                }
            } catch {
                self.log("JSON parse error: \(error.localizedDescription)")
            }
        }
    }

    nonisolated func session(_: MCSession,
                             didReceive _: [Any]?,
                             fromPeer peerID: MCPeerID,
                             certificateHandler: @escaping (Bool) -> Void)
    {
        Task { @MainActor in
            self.log("Received certificate from \(peerID.displayName). Auto-accepting.")
            certificateHandler(true)
        }
    }

    nonisolated func session(_: MCSession,
                             didReceive _: InputStream,
                             withName _: String,
                             fromPeer _: MCPeerID) {}

    nonisolated func session(_: MCSession,
                             didStartReceivingResourceWithName _: String,
                             fromPeer _: MCPeerID,
                             with _: Progress) {}

    nonisolated func session(_: MCSession,
                             didFinishReceivingResourceWithName _: String,
                             fromPeer _: MCPeerID,
                             at _: URL?,
                             withError _: Error?) {}
}

extension MultipeerManager: MCNearbyServiceAdvertiserDelegate, MCNearbyServiceBrowserDelegate {
    nonisolated func advertiser(_: MCNearbyServiceAdvertiser,
                                didReceiveInvitationFromPeer _: MCPeerID,
                                withContext _: Data?,
                                invitationHandler: @escaping (Bool, MCSession?) -> Void)
    {
        // Hop to MainActor to supply our main-actor session
        Task { @MainActor in
            if self.isVisible, let session = self.session {
                invitationHandler(true, session)
            } else {
                invitationHandler(false, nil)
            }
        }
    }

    nonisolated func browser(_: MCNearbyServiceBrowser,
                             foundPeer peerID: MCPeerID,
                             withDiscoveryInfo _: [String: String]?)
    {
        Task { @MainActor in
            if !self.nearbyPeers.contains(peerID) {
                self.nearbyPeers.append(peerID)
                self.updatePeerHistory(for: peerID)
            }
        }
    }

    nonisolated func browser(_: MCNearbyServiceBrowser,
                             lostPeer peerID: MCPeerID)
    {
        Task { @MainActor in
            self.updatePeerHistory(for: peerID)
            self.nearbyPeers.removeAll { $0 == peerID }
        }
    }
}
