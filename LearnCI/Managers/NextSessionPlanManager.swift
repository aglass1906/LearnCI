import Foundation
import SwiftData
import UserNotifications

@Observable
@MainActor
final class NextSessionPlanManager {
    var lastAuthorizationStatus: UNAuthorizationStatus = .notDetermined

    init() {}

    /// Fetch the single plan scheduled for today (day-window) for the given user,
    /// most-recently created wins. Returns nil if none.
    func todaysPlan(for userID: String?, in context: ModelContext) -> NextSessionPlan? {
        let calendar = Calendar.current
        let start = calendar.startOfDay(for: Date())
        let end = calendar.date(byAdding: .day, value: 1, to: start) ?? Date()
        var descriptor = FetchDescriptor<NextSessionPlan>(
            predicate: #Predicate {
                $0.userID == userID &&
                $0.scheduledFor >= start &&
                $0.scheduledFor < end &&
                $0.statusRaw != "completed" &&
                $0.statusRaw != "skipped"
            },
            sortBy: [SortDescriptor(\.createdAt, order: .reverse)]
        )
        descriptor.fetchLimit = 1
        return (try? context.fetch(descriptor))?.first
    }

    /// Save a plan and, if requested, schedule a local notification. Cancels any
    /// prior notification associated with a plan for the same day.
    @discardableResult
    func upsertPlan(
        userID: String?,
        scheduledFor: Date,
        sourceType: NextSessionSourceType,
        sourceID: String,
        sourceTitle: String,
        chapterNumber: Int?,
        sceneIndex: Int?,
        targetMinutes: Int,
        wordReviewCount: Int,
        focusNote: String?,
        notificationTime: Date?,
        in context: ModelContext
    ) async -> NextSessionPlan {
        // Cancel any existing same-day plan's notification and delete the row so
        // there's a single canonical "next" plan per day.
        if let existing = todaysPlan(for: userID, in: context) {
            if let notifID = existing.notificationID {
                UNUserNotificationCenter.current().removePendingNotificationRequests(withIdentifiers: [notifID])
            }
            context.delete(existing)
        }

        let plan = NextSessionPlan(
            userID: userID,
            scheduledFor: scheduledFor,
            sourceType: sourceType,
            sourceID: sourceID,
            sourceTitle: sourceTitle,
            chapterNumber: chapterNumber,
            sceneIndex: sceneIndex,
            targetMinutes: targetMinutes,
            wordReviewCount: wordReviewCount,
            focusNote: focusNote,
            notificationTime: notificationTime
        )
        context.insert(plan)

        if let time = notificationTime {
            if let notifID = await scheduleNotification(for: plan, at: time) {
                plan.notificationID = notifID
            }
        }

        try? context.save()
        return plan
    }

    func markStarted(_ plan: NextSessionPlan, in context: ModelContext) {
        plan.status = .started
        plan.isSynced = false
        try? context.save()
    }

    func markCompleted(_ plan: NextSessionPlan, in context: ModelContext) {
        plan.status = .completed
        plan.isSynced = false
        if let notifID = plan.notificationID {
            UNUserNotificationCenter.current().removePendingNotificationRequests(withIdentifiers: [notifID])
        }
        try? context.save()
    }

    /// Request notification authorization on first use. Returns whether we're
    /// currently authorized to post notifications.
    @discardableResult
    func requestNotificationAuthorization() async -> Bool {
        let center = UNUserNotificationCenter.current()
        let settings = await center.notificationSettings()
        lastAuthorizationStatus = settings.authorizationStatus

        switch settings.authorizationStatus {
        case .authorized, .provisional, .ephemeral:
            return true
        case .denied:
            return false
        case .notDetermined:
            let granted = (try? await center.requestAuthorization(options: [.alert, .sound])) ?? false
            let refreshed = await center.notificationSettings()
            lastAuthorizationStatus = refreshed.authorizationStatus
            return granted
        @unknown default:
            return false
        }
    }

    private func scheduleNotification(for plan: NextSessionPlan, at time: Date) async -> String? {
        let granted = await requestNotificationAuthorization()
        guard granted else { return nil }

        let content = UNMutableNotificationContent()
        content.title = "Today's Learning Plan"
        var body = "Continue \"\(plan.sourceTitle)\""
        if let chapter = plan.chapterNumber { body += " · Chapter \(chapter)" }
        body += " · \(plan.targetMinutes) min"
        content.body = body
        content.sound = .default
        content.userInfo = [
            "planID": plan.id.uuidString,
            "sourceID": plan.sourceID,
            "sourceType": plan.sourceTypeRaw
        ]

        let components = Calendar.current.dateComponents([.year, .month, .day, .hour, .minute], from: time)
        let trigger = UNCalendarNotificationTrigger(dateMatching: components, repeats: false)
        let id = "next-session-\(plan.id.uuidString)"
        let request = UNNotificationRequest(identifier: id, content: content, trigger: trigger)

        do {
            try await UNUserNotificationCenter.current().add(request)
            return id
        } catch {
            Logger.error("Failed to schedule next-session notification: \(error.localizedDescription)", category: .general)
            return nil
        }
    }
}
