import Foundation
import MultipeerConnectivity
import Swifter

final class RaycastHTTPServer {
    static let port: UInt16 = 42123

    private let server = HttpServer()
    private weak var manager: MultipeerManager?

    init(manager: MultipeerManager) {
        self.manager = manager
        setupRoutes()
    }

    func start() {
        guard !server.operating else { return }
        do {
            try server.start(UInt16(RaycastHTTPServer.port), forceIPv4: true, priority: .userInitiated)
            print("[RaycastHTTPServer] Started on 127.0.0.1:\(RaycastHTTPServer.port)")
        } catch {
            print("[RaycastHTTPServer] Failed to start: \(error)")
        }
    }

    func stop() {
        guard server.operating else { return }
        server.stop()
    }

    private func setupRoutes() {
        // Health
        server["/v1/health"] = { _ in
            Self.json(["ok": true])
        }

        // Status
        server["/v1/status"] = { [weak self] _ in
            guard let self, let manager = self.manager else { return Self.json(["ok": false], status: 500) }
            let sema = DispatchSemaphore(value: 0)
            var payload: [String: Any] = [:]
            Task { @MainActor in
                payload = [
                    "ok": true,
                    "name": manager.myPeerID.displayName,
                    "visible": manager.isVisible,
                    "nearbyCount": manager.nearbyPeers.count,
                    "nearby": manager.nearbyPeers.map { ["id": $0.displayName, "displayName": $0.displayName] },
                ]
                sema.signal()
            }
            sema.wait()
            return Self.json(payload)
        }

        // Peers
        server["/v1/peers"] = { [weak self] _ in
            guard let self, let manager = self.manager else { return Self.json(["ok": false], status: 500) }
            let sema = DispatchSemaphore(value: 0)
            var payload: [String: Any] = [:]
            Task { @MainActor in
                let recently = manager.getRecentlySeenPeers().map { h in
                    [
                        "id": h.peerID,
                        "displayName": h.displayName,
                        "lastSeenISO": ISO8601DateFormatter().string(from: h.lastSeen),
                    ]
                }
                payload = [
                    "ok": true,
                    "nearby": manager.nearbyPeers.map { ["id": $0.displayName, "displayName": $0.displayName] },
                    "recentlySeen": recently,
                ]
                sema.signal()
            }
            sema.wait()
            return Self.json(payload)
        }

        // Poke
        server.POST["/v1/poke"] = { [weak self] req in
            guard let self, let manager = self.manager else { return Self.json(["ok": false], status: 500) }
            guard let data = req.bodyData(),
                  let obj = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
                  let toName = obj["to"] as? String
            else {
                return Self.json(["ok": false, "error": "missing 'to'"], status: 400)
            }
            let note = (obj["note"] as? String) ?? ""
            let sema = DispatchSemaphore(value: 0)
            var delivered = false
            var errorStr: String?
            Task { @MainActor in
                if let peer = manager.nearbyPeers.first(where: { $0.displayName == toName }) {
                    delivered = await manager.trySendPoke(to: peer, note: note)
                } else {
                    errorStr = "peer not found or offline"
                }
                sema.signal()
            }
            sema.wait()
            if let e = errorStr { return Self.json(["ok": false, "error": e], status: 404) }
            return Self.json(["ok": true, "delivered": delivered])
        }

        // Visible
        server.POST["/v1/visible"] = { [weak self] req in
            guard let self, let manager = self.manager else { return Self.json(["ok": false], status: 500) }
            guard let data = req.bodyData(),
                  let obj = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
                  let visible = obj["visible"] as? Bool
            else {
                return Self.json(["ok": false, "error": "missing 'visible' bool"], status: 400)
            }
            let sema = DispatchSemaphore(value: 0)
            Task { @MainActor in
                manager.setVisible(visible)
                sema.signal()
            }
            sema.wait()
            return Self.json(["ok": true, "visible": visible])
        }
    }

    private static func json(_ obj: [String: Any], status: Int = 200) -> HttpResponse {
        let data = (try? JSONSerialization.data(withJSONObject: obj)) ?? ("{}".data(using: String.Encoding.utf8) ?? Data())
        return .raw(status, status == 200 ? "OK" : "",
                    ["Content-Type": "application/json; charset=utf-8",
                     "Cache-Control": "no-store"]) { writer in try writer.write(data) }
    }
}

private extension HttpRequest {
    func bodyData() -> Data? {
        guard !body.isEmpty else { return nil }
        return Data(body)
    }
}
