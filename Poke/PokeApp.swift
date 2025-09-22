import AppKit
import SwiftUI
import UserNotifications

@main
struct PokeApp: App {
    @StateObject private var mp = MultipeerManager()
    @NSApplicationDelegateAdaptor(AppDelegate.self) var appDelegate

    var body: some Scene {
        MenuBarExtra("Poke", systemImage: "dot.radiowaves.left.and.right") {
            PeersMenu()
                .environmentObject(mp)
        }
        .menuBarExtraStyle(.window)
    }
}

final class AppDelegate: NSObject, NSApplicationDelegate, UNUserNotificationCenterDelegate {
    func applicationDidFinishLaunching(_: Notification) {
        // Hide Dock icon: make this a menu bar only app
        NSApp.setActivationPolicy(.accessory)

        let center = UNUserNotificationCenter.current()
        center.delegate = self
        center.requestAuthorization(options: [.alert, .sound, .badge]) { granted, error in
            print("Granted:", granted, "error:", String(describing: error))
            center.getNotificationSettings { s in
                print("Settings -> status=\(s.authorizationStatus.rawValue) alert=\(s.alertSetting.rawValue) sound=\(s.soundSetting.rawValue)")
            }
        }
    }

    func userNotificationCenter(
        _: UNUserNotificationCenter,
        willPresent _: UNNotification,
        withCompletionHandler completionHandler: @escaping (UNNotificationPresentationOptions) -> Void
    ) {
        completionHandler([.banner, .list, .sound])
    }
}
