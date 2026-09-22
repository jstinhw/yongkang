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
    /// The question the screen asked and the keys the user pressed while it was up, once it's gone.
    var onAnswer: (_ question: String, _ keys: [[UInt8]]) -> Void = { _, _ in }
    private(set) var hasDraft = false
    /// What the user has typed since the question on screen went up, one entry per key press.
    private(set) var answer: [[UInt8]] = []

    /// Every key the user presses reaches the process through here, and nothing the app types
    /// does: `TerminalRegistry` writes to the process directly.
    override func send(source: TerminalView, data: ArraySlice<UInt8>) {
        if lastReason != nil { answer.append(Array(data)) }
        super.send(source: source, data: data)
    }

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
                if let asked = self.lastReason, !self.answer.isEmpty { self.onAnswer(asked, self.answer) }
                self.answer = []
                self.lastReason = reason
                self.onAttention(reason)
            }
            self.onCheck()
        }
        check = work
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.2, execute: work)
    }
}

/// Main-actor state: it reads `NSApp`, and what it remembers is the questions the window is
/// showing, which only the main actor changes.
@MainActor final class AgentNotifications: NSObject, UNUserNotificationCenterDelegate {
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
        // The permission callback arrives on whatever thread UserNotifications picks, so it
        // captures only the values it needs and comes back to the main actor to post.
        center.requestAuthorization(options: [.alert, .sound]) { allowed, _ in
            guard allowed else { return }
            Task { @MainActor in Self.shared.post(sessionID: sessionID, title: title, reason: reason) }
        }
    }

    /// Posts the banner, unless the question was answered while permission was being asked for.
    private func post(sessionID: UUID, title: String, reason: String) {
        guard active[sessionID] == reason else { return }
        let content = UNMutableNotificationContent()
        content.title = "\(title) — action required"
        content.body = reason + " Open this notification to answer in the session."
        content.sound = .default
        content.userInfo = ["sessionID": sessionID.uuidString]
        UNUserNotificationCenter.current()
            .add(UNNotificationRequest(identifier: sessionID.uuidString, content: content, trigger: nil))
    }

    func clear(_ sessionID: UUID) {
        active[sessionID] = nil
        guard Bundle.main.bundleIdentifier != nil else { return }
        let center = UNUserNotificationCenter.current()
        center.removePendingNotificationRequests(withIdentifiers: [sessionID.uuidString])
        center.removeDeliveredNotifications(withIdentifiers: [sessionID.uuidString])
    }

    // UserNotifications makes no promise about the thread it calls its delegate on, so both
    // stay off the actor and hop for the part that touches the window.

    nonisolated func userNotificationCenter(
        _ center: UNUserNotificationCenter,
        willPresent notification: UNNotification,
        withCompletionHandler completionHandler: @escaping (UNNotificationPresentationOptions) -> Void
    ) {
        completionHandler([.banner, .sound])
    }

    nonisolated func userNotificationCenter(
        _ center: UNUserNotificationCenter,
        didReceive response: UNNotificationResponse,
        withCompletionHandler completionHandler: @escaping () -> Void
    ) {
        if response.actionIdentifier == UNNotificationDefaultActionIdentifier,
            let id = response.notification.request.content.userInfo["sessionID"] as? String
        {
            Task { @MainActor in
                NotificationCenter.default.post(name: Self.openSession, object: id)
            }
        }
        completionHandler()
    }
}
