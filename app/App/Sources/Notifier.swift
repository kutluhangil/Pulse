import AppKit
import Foundation
import PulseClient
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

    func postUpdate(_ release: ReleaseInfo) {
        let content = UNMutableNotificationContent()
        content.title = String(localized: "Pulse \(release.version.description) is available")
        content.body = String(localized: "Click to download it from GitHub.")
        content.userInfo = ["url": (release.downloadURL ?? release.pageURL).absoluteString]
        center.add(UNNotificationRequest(identifier: "update-\(release.tag)", content: content, trigger: nil))
    }

    func userNotificationCenter(_: UNUserNotificationCenter, didReceive response: UNNotificationResponse) async {
        guard let raw = response.notification.request.content.userInfo["url"] as? String, let url = URL(string: raw) else { return }
        await MainActor.run { _ = NSWorkspace.shared.open(url) }
    }

    func userNotificationCenter(_: UNUserNotificationCenter, willPresent _: UNNotification) async -> UNNotificationPresentationOptions {
        [.banner, .list, .sound]
    }
}
