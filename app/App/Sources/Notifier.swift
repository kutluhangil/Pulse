import Foundation
import PulseCore
import PulseUI
import UserNotifications

/// Posts alert events as user notifications. Shown even while Pulse is
/// frontmost, since it has no main window to show them in.
final class Notifier: NSObject, UNUserNotificationCenterDelegate, @unchecked Sendable {
    private let center = UNUserNotificationCenter.current()

    override init() {
        super.init()
        center.delegate = self
    }

    func requestAuthorization() {
        center.requestAuthorization(options: [.alert, .sound]) { _, error in
            if let error { NSLog("Pulse: notification permission error: \(error.localizedDescription)") }
        }
    }

    func post(_ event: AlertEvent, host: String) {
        let text = AlertText.content(for: event, host: host)
        let content = UNMutableNotificationContent()
        content.title = text.title
        content.body = text.body
        content.threadIdentifier = event.key
        if event.phase == .fired, event.kind != .reboot { content.sound = .default }
        let request = UNNotificationRequest(identifier: "\(event.key)-\(Date().timeIntervalSince1970)", content: content, trigger: nil)
        center.add(request)
    }

    func userNotificationCenter(_: UNUserNotificationCenter, willPresent _: UNNotification) async -> UNNotificationPresentationOptions {
        [.banner, .list, .sound]
    }
}
