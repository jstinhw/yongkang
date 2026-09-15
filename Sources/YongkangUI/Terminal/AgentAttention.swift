import AppKit
import SwiftTerm
import UserNotifications
import YongkangCore

final class AttentionTerminalView: LocalProcessTerminalView {
    var onAttention: (String?) -> Void = { _ in }
    /// Runs on every attention check, whether or not the reason changed: the moment a CLI has
    /// redrawn after the user answered it, submitted a draft or left a picker, so whatever
    /// was waiting for that can go.
    var onCheck: () -> Void = {}
    var onUserInput: () -> Void = {}
    private(set) var hasDraft = false

    func recordInput(_ event: NSEvent) {
        onUserInput()
        if event.keyCode == 36 || (event.modifierFlags.contains(.control) && event.charactersIgnoringModifiers == "u") {
            hasDraft = false
        } else if event.modifierFlags.contains(.command) {
            if event.charactersIgnoringModifiers == "v" { hasDraft = true }
        } else if event.characters?.unicodeScalars.contains(where: { $0.value >= 32 && $0.value < 0xF700 }) == true {
            hasDraft = true
        }
    }

    private var check: DispatchWorkItem?
    private var lastReason: String?

    var screen: String {
        let terminal = getTerminal()
        // ponytail: bounded by the terminal's scrollback; use a screen-only buffer API
        // if large scrollback makes this measurable. History never triggers a notice.
        let lines = String(decoding: terminal.getBufferAsData(), as: UTF8.self)
            .split(separator: "\n", omittingEmptySubsequences: false).dropLast()
        return lines.suffix(terminal.rows).joined(separator: "\n")
    }

    var attentionReason: String? { AgentPrompt.reason(in: screen) }

    override func dataReceived(slice: ArraySlice<UInt8>) {
        super.dataReceived(slice: slice)
        // Check on a fixed deadline. Codex redraws even while waiting for input;
        // restarting the delay on every frame can suppress the notice forever.
        guard check == nil else { return }
        let work = DispatchWorkItem { [weak self] in
            guard let self else { return }
            self.check = nil
            let reason = self.attentionReason
            if reason != self.lastReason {
                self.lastReason = reason
                self.onAttention(reason)
            }
            self.onCheck()
        }
        check = work
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.2, execute: work)
    }
}

final class AgentNotifications: NSObject, UNUserNotificationCenterDelegate {
    static let shared = AgentNotifications()
    static let openSession = Notification.Name("Yongkang.openAttentionSession")
    private var active: [UUID: String] = [:]

    func send(sessionID: UUID, title: String, reason: String) {
        active[sessionID] = reason
        NSApp.requestUserAttention(.informationalRequest)
        // Command-line self-tests have no app bundle; the persistent in-app notice works
        // there too, and when macOS notification permission is denied.
        guard Bundle.main.bundleIdentifier != nil else { return }
        let center = UNUserNotificationCenter.current()
        center.delegate = self
        center.requestAuthorization(options: [.alert, .sound]) { allowed, _ in
            guard allowed else { return }
            DispatchQueue.main.async {
                guard self.active[sessionID] == reason else { return }
                let content = UNMutableNotificationContent()
                content.title = "\(title) — action required"
                content.body = reason + " Open this notification to answer in the session."
                content.sound = .default
                content.userInfo = ["sessionID": sessionID.uuidString]
                center.add(UNNotificationRequest(identifier: sessionID.uuidString, content: content, trigger: nil))
            }
        }
    }

    func clear(_ sessionID: UUID) {
        active[sessionID] = nil
        guard Bundle.main.bundleIdentifier != nil else { return }
        let center = UNUserNotificationCenter.current()
        center.removePendingNotificationRequests(withIdentifiers: [sessionID.uuidString])
        center.removeDeliveredNotifications(withIdentifiers: [sessionID.uuidString])
    }

    func userNotificationCenter(
        _ center: UNUserNotificationCenter,
        willPresent notification: UNNotification,
        withCompletionHandler completionHandler: @escaping (UNNotificationPresentationOptions) -> Void
    ) {
        completionHandler([.banner, .sound])
    }

    func userNotificationCenter(
        _ center: UNUserNotificationCenter,
        didReceive response: UNNotificationResponse,
        withCompletionHandler completionHandler: @escaping () -> Void
    ) {
        if response.actionIdentifier == UNNotificationDefaultActionIdentifier,
            let id = response.notification.request.content.userInfo["sessionID"] as? String
        {
            DispatchQueue.main.async {
                NotificationCenter.default.post(name: Self.openSession, object: id)
            }
        }
        completionHandler()
    }
}
