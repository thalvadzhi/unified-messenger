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
        // Async API, not a completion closure: UserNotifications calls completion handlers on its own
        // queue, and a closure written in this @MainActor class can be compiled as main-actor isolated,
        // which traps at runtime when called off the main thread (crash seen on launch).
        Task {
            do {
                if try await UNUserNotificationCenter.current().requestAuthorization(options: [.alert, .sound]) == false {
                    NSLog("[um] notification authorization denied")
                }
            } catch {
                NSLog("[um] notification authorization error: %@", error.localizedDescription)
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
        Task {
            do {
                try await UNUserNotificationCenter.current().add(request)
            } catch {
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
