import AppKit
import SwiftUI
import UserNotifications

@main
struct RobinApp: App {
    @NSApplicationDelegateAdaptor(AppDelegate.self) private var appDelegate

    var body: some Scene {
        MenuBarExtra("Robin", systemImage: "waveform.mid") {
            Button("Settings") {
                appDelegate.coordinator.openSettings()
            }

            Button("Show History") {
                appDelegate.coordinator.showHistory()
            }

            Button("Show Logs") {
                appDelegate.coordinator.showLogs()
            }

            Button("Reset Setting") {
                appDelegate.coordinator.resetSettings()
            }

            Divider()

            Button("Quit") {
                NSApplication.shared.terminate(nil)
            }
        }
        .menuBarExtraStyle(.menu)
    }
}

@MainActor
final class AppDelegate: NSObject, NSApplicationDelegate {
    let coordinator = AppCoordinator()
    private let notificationDelegate = NotificationDelegate()

    func applicationDidFinishLaunching(_ notification: Notification) {
        NSApplication.shared.setActivationPolicy(.accessory)
        UNUserNotificationCenter.current().delegate = notificationDelegate

        Task { @MainActor in
            await coordinator.start()
        }
    }
}

final class NotificationDelegate: NSObject, UNUserNotificationCenterDelegate {
    func userNotificationCenter(
        _ center: UNUserNotificationCenter,
        willPresent notification: UNNotification
    ) async -> UNNotificationPresentationOptions {
        [.banner, .sound]
    }
}
