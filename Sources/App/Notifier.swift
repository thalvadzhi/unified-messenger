import AppKit
import UserNotifications

/// Posts macOS banners and routes banner clicks back to the app.
/// Suppression (is the user looking?) is decided by the caller before `post`.
@MainActor
final class Notifier: NSObject, UNUserNotificationCenterDelegate {
    /// Called on the main actor with the clicked banner's service and page notification id (if any).
    var onClick: ((ServiceID, String?) -> Void)?

    override init() {
        super.init()
        UNUserNotificationCenter.current().delegate = self
    }

    func requestAuthorization() {
        UNUserNotificationCenter.current().requestAuthorization(options: [.alert, .sound]) { granted, error in
            if let error {
                NSLog("[um] notification authorization error: %@", error.localizedDescription)
            } else if !granted {
                NSLog("[um] notification authorization denied")
            }
        }
    }

    func post(identifier: String, title: String, body: String, service: ServiceID, pageNotificationID: String?) {
        let content = UNMutableNotificationContent()
        content.title = title
        content.body = body
        content.sound = .default
        content.threadIdentifier = service.rawValue
        var info: [String: String] = ["service": service.rawValue]
        if let pageNotificationID { info["pageID"] = pageNotificationID }
        content.userInfo = info

        let request = UNNotificationRequest(identifier: identifier, content: content, trigger: nil)
        UNUserNotificationCenter.current().add(request) { error in
            if let error {
                NSLog("[um] failed to post notification: %@", error.localizedDescription)
            }
        }
    }

    // MARK: - UNUserNotificationCenterDelegate

    nonisolated func userNotificationCenter(
        _ center: UNUserNotificationCenter,
        willPresent notification: UNNotification
    ) async -> UNNotificationPresentationOptions {
        [.banner, .sound]
    }

    nonisolated func userNotificationCenter(
        _ center: UNUserNotificationCenter,
        didReceive response: UNNotificationResponse
    ) async {
        let info = response.notification.request.content.userInfo
        guard let raw = info["service"] as? String, let service = ServiceID(rawValue: raw) else { return }
        let pageID = info["pageID"] as? String
        await MainActor.run {
            self.onClick?(service, pageID)
        }
    }
}
