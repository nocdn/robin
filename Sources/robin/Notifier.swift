import Foundation
import UserNotifications

@MainActor
final class Notifier {
    func requestAuthorization() async {
        do {
            Logger.shared.info("Requesting notification authorization")
            try await UNUserNotificationCenter.current().requestAuthorization(options: [.alert, .sound])
            Logger.shared.info("Notification authorization request completed")
        } catch {
            Logger.shared.error("Notification authorization failed: \(error.localizedDescription)")
        }
    }

    func error(_ error: Error) {
        let content = UNMutableNotificationContent()
        content.title = "Robin error"
        content.body = error.localizedDescription
        content.sound = .default

        let request = UNNotificationRequest(
            identifier: "robin-error-\(UUID().uuidString)",
            content: content,
            trigger: nil
        )

        UNUserNotificationCenter.current().add(request) { addError in
            if let addError {
                Logger.shared.error("Failed to post notification: \(addError.localizedDescription)")
                print("Failed to post notification: \(addError.localizedDescription)")
            }
        }

        Logger.shared.error("Notification error shown: \(error.localizedDescription)")
        print("Robin error: \(error.localizedDescription)")
    }
}
