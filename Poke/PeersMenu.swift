import AppKit
import MultipeerConnectivity
import SwiftUI

struct PeersMenu: View {
    @EnvironmentObject var mp: MultipeerManager
    @State private var note: String = ""
    @State private var visible: Bool = true

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            Text("Nearby peers").font(.headline)

            if mp.nearbyPeers.isEmpty {
                Text("No peers found").foregroundColor(.secondary)
            } else {
                ForEach(mp.nearbyPeers, id: \.self) { peer in
                    HStack {
                        VStack(alignment: .leading) {
                            Text(peer.displayName).lineLimit(1)
                            let status = mp.lastPokeStatus[peer.displayName]
                            HStack(spacing: 6) {
                                // Online indicator
                                Circle()
                                    .fill(Color.green)
                                    .frame(width: 6, height: 6)
                                Text("Online")
                                    .font(.caption)
                                    .foregroundStyle(.secondary)
                                if let status = status {
                                    switch status {
                                    case .sending:
                                        Circle().fill(Color.secondary).frame(width: 6, height: 6)
                                        Text("sending…").font(.caption).foregroundStyle(.secondary)
                                    case .delivered:
                                        Circle().fill(Color.accentColor).frame(width: 6, height: 6)
                                        Text("delivered").font(.caption).foregroundStyle(.primary)
                                    case .failed:
                                        Circle().fill(Color.red).frame(width: 6, height: 6)
                                        Text("failed").font(.caption).foregroundStyle(.primary)
                                    }
                                }
                            }
                        }
                        Spacer()
                        Button("Poke") {
                            Task {
                                let delivered = await mp.trySendPoke(to: peer, note: note)
                                if delivered {
                                    note = "" // Clear the text field after confirmed delivery
                                } else {
                                    NSSound.beep() // subtle feedback on failure
                                }
                            }
                        }
                    }
                }
            }

            let recentlySeenPeers = mp.getRecentlySeenPeers()
            if !recentlySeenPeers.isEmpty {
                Text("Recently seen").font(.headline).padding(.top, 8)

                ForEach(recentlySeenPeers, id: \.peerID) { peerHistory in
                    HStack {
                        VStack(alignment: .leading) {
                            Text(peerHistory.displayName).lineLimit(1)
                            Text("Last seen \(timeAgoString(from: peerHistory.lastSeen))")
                                .font(.caption)
                                .foregroundColor(.secondary)
                        }
                        Spacer()
                        Text("Offline").font(.caption).foregroundColor(.gray)
                    }
                }
            }

            Divider()

            TextField("Optional note…", text: $note)
                .textFieldStyle(.roundedBorder)

            Toggle("Visible to others", isOn: $visible)
                .onChange(of: visible) { _, newValue in
                    mp.setVisible(newValue)
                }

            HStack {
                Spacer()
                Button("Quit") { NSApp.terminate(nil) }
                    .keyboardShortcut("q")
            }
        }
        .padding(12)
        .frame(width: 300)
        .onAppear {
            // Sync toggle with persisted manager state without forcing start
            visible = mp.isVisible
        }
    }

    private func timeAgoString(from date: Date) -> String {
        let now = Date()
        let timeInterval = now.timeIntervalSince(date)

        if timeInterval < 60 {
            return "just now"
        } else if timeInterval < 3600 {
            let minutes = Int(timeInterval / 60)
            return "\(minutes) minute\(minutes == 1 ? "" : "s") ago"
        } else if timeInterval < 86400 {
            let hours = Int(timeInterval / 3600)
            return "\(hours) hour\(hours == 1 ? "" : "s") ago"
        } else {
            let days = Int(timeInterval / 86400)
            return "\(days) day\(days == 1 ? "" : "s") ago"
        }
    }
}
