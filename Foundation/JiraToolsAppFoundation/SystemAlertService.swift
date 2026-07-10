import AppKit
import Foundation
import UserNotifications

@MainActor
public final class SystemAlertService {
    private let requestNotificationAuthorization: @MainActor () async throws -> Bool
    private let sendNotification: @MainActor (JiraToolsAlert) async throws -> Void
    private let playSound: @MainActor () -> Void

    public convenience init() {
        self.init(
            requestNotificationAuthorization: requestSystemNotificationAuthorization,
            sendNotification: sendSystemNotification,
            playSound: playSystemSound,
        )
    }

    public init(
        requestNotificationAuthorization: @escaping @MainActor () async throws -> Bool,
        sendNotification: @escaping @MainActor (JiraToolsAlert) async throws -> Void,
        playSound: @escaping @MainActor () -> Void,
    ) {
        self.requestNotificationAuthorization = requestNotificationAuthorization
        self.sendNotification = sendNotification
        self.playSound = playSound
    }

    public func deliver(
        _ alert: JiraToolsAlert,
        mode: JiraToolsAlertMode,
    ) async throws {
        if mode == .notification || mode == .both {
            try await sendNotification(alert)
        }
        if mode == .sound || mode == .both {
            playSound()
        }
    }

    public func requestAuthorization() async throws -> Bool {
        try await requestNotificationAuthorization()
    }
}

@MainActor
private func playSystemSound() {
    NSSound.beep()
}

@MainActor
private func requestSystemNotificationAuthorization() async throws -> Bool {
    try await UNUserNotificationCenter.current().requestAuthorization(options: [.alert, .sound])
}

@MainActor
private func sendSystemNotification(_ alert: JiraToolsAlert) async throws {
    let content = UNMutableNotificationContent()
    content.body = alert.body
    content.sound = .default
    content.title = alert.title
    let request = UNNotificationRequest(
        identifier: UUID().uuidString,
        content: content,
        trigger: nil,
    )
    try await UNUserNotificationCenter.current().add(request)
}
