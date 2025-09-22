# JoJoPing

A tiny macOS menu bar app for quickly pinging nearby Macs on the same network using MultipeerConnectivity. It lives in the menu bar (no Dock icon), shows nearby peers, lets you send an optional note with your ping, and pops a native notification when someone pings you.

- Menu bar only — no Dock icon
- Auto-discovers nearby peers via MultipeerConnectivity
- Send a “Ping” with an optional note
- Toggle advertising (Visible to others)
- Native notifications with banner/list/sound on incoming pings
- Quick “Quit” action in the menu

## Requirements

- macOS (recent versions). Verified locally on a modern macOS (Sequoia). If needed, adjust the Deployment Target in Xcode.
- Xcode installed (for building from source)

## Build and run

### Xcode (recommended)
1. Open `JoJoPing.xcodeproj` in Xcode.
2. Select the `JoJoPing` scheme.
3. Build and Run.

The app appears as a status item in the menu bar with a radio-waves icon.

### Terminal
If you prefer the command line, you can build the app with Xcode’s CLI tools:

```zsh
xcodebuild -scheme JoJoPing -project JoJoPing.xcodeproj -configuration Release build
```

The built app will be inside `Build/Products/<Config>/JoJoPing.app` under the Xcode DerivedData path.

## Usage

- Click the menu bar icon to open the window.
- “Nearby peers” lists discoverable devices. Press “Ping” next to a peer to send a ping.
- Add an optional note in the text field.
- Use the “Visible to others” toggle to advertise yourself. Turning it off stops advertising and browsing.
- Use “Quit” to exit the app. It also has a ⌘Q shortcut.

When a ping is received, the app requests attention and shows a user notification (banner/list/sound). Make sure notifications are allowed for JoJoPing in System Settings > Notifications.

## Permissions and privacy

- Notifications: requested on first launch to show incoming ping alerts.
- Networking: uses MultipeerConnectivity for local peer discovery and communication.
- App Sandbox entitlements are enabled for local networking.

## How it works (code map)

- `JoJoPing/JoJoPingApp.swift`: App entry point. Creates the menu bar extra and configures notifications. Hides the Dock icon via `NSApp.setActivationPolicy(.accessory)`.
- `JoJoPing/PeersMenu.swift`: SwiftUI view shown from the menu bar. Lists peers, note field, advertising toggle, and the Quit button.
- `JoJoPing/MultipeerManager.swift`: MultipeerConnectivity wrapper. Handles advertising, browsing, session lifecycle, sending/receiving ping JSON payloads, and posting notifications.
- `JoJoPing/Assets.xcassets`: App icon and colors.

## Tips

- Display name: The app uses `UserDefaults` key `displayName` if set, otherwise your Mac’s name. If you want to override it without editing code you can set it in Terminal:

  ```zsh
  defaults write com.bstokmans.JoJoPing displayName "Your Name"
  ```

  Then restart the app.

- Peer discovery works best when devices are on the same Wi‑Fi/LAN. If peers don’t appear:
  - Ensure both machines are on the same network and not on a guest/VPN segment that blocks peer discovery
  - Check the macOS firewall (System Settings > Network > Firewall) and allow the app to receive incoming connections
  - Keep “Visible to others” enabled on both ends

## Troubleshooting

- No notifications: Ensure JoJoPing notifications are allowed in System Settings > Notifications.
- No peers found: See tips above; some corporate networks restrict local peer traffic.
- Build issues: Make sure you’re on a recent Xcode and macOS. If needed, lower/raise the Deployment Target in the project settings.

## Contributing

Small fixes and improvements welcome. Open an issue or PR with a concise description of the change.