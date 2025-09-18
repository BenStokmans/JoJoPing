import SwiftUI
import MultipeerConnectivity
import AppKit

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
            Text(peer.displayName).lineLimit(1)
            Spacer()
            Button("Ping") {
              Task { await mp.trySendPing(to: peer, note: note) }
            }
          }
        }
      }

      Divider()

      TextField("Optional note…", text: $note)
        .textFieldStyle(.roundedBorder)

      Toggle("Visible to others", isOn: $visible)
        .onChange(of: visible) { _, newValue in
          if newValue { mp.start() } else { mp.stop() }
        }

      HStack {
        Spacer()
        Button("Quit") { NSApp.terminate(nil) }
          .keyboardShortcut("q")
      }
    }
    .padding(12)
    .frame(width: 300)
    .onAppear { mp.start() }
  }
}
