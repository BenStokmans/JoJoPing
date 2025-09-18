import SwiftUI
import UserNotifications
import AppKit

@main
struct JoJoPingApp: App {
  @StateObject private var mp = MultipeerManager()
  @NSApplicationDelegateAdaptor(AppDelegate.self) var appDelegate

  var body: some Scene {
    MenuBarExtra("JoJoPing", systemImage: "dot.radiowaves.left.and.right") {
      PeersMenu()
        .environmentObject(mp)
    }
    .menuBarExtraStyle(.window)
  }
}

final class AppDelegate: NSObject, NSApplicationDelegate, UNUserNotificationCenterDelegate {
  func applicationDidFinishLaunching(_ notification: Notification) {
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
    _ center: UNUserNotificationCenter,
    willPresent notification: UNNotification,
    withCompletionHandler completionHandler: @escaping (UNNotificationPresentationOptions) -> Void
  ) {
    completionHandler([.banner, .list, .sound])
  }
}
