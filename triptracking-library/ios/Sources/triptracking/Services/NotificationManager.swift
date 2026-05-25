//
//  NotificationManager.swift
//  TripTracker
//
//  Local push notifications:
//    1. Trip auto-started
//    2. Trip auto-ended
//    3. Daily 6:00 AM reminder to check yesterday's route
//

import Foundation
import UserNotifications
import UIKit

public class NotificationManager: NSObject {

    public static let shared = NotificationManager()

    // MARK: - Notification identifiers
    private let dailyReminderID = "tt_daily_route_reminder"

    private override init() {
        super.init()
    }

    // MARK: - Permission

    /// Request notification permission. Call once at app launch.
    public func requestPermission() {
        let center = UNUserNotificationCenter.current()
        center.delegate = self
        center.requestAuthorization(options: [.alert, .sound, .badge]) { granted, error in
            if granted {
                print("🔔 Notification permission granted")
            } else {
                print("🔔 Notification permission denied: \(error?.localizedDescription ?? "–")")
            }
            // Schedule daily reminder regardless — it'll fire once permission is granted
            // self.scheduleDailyReminder()
        }
    }

    // MARK: - Trip Notifications

    /// Notify when a trip auto-starts.
    public func notifyTripStarted(tripId: Int64, vehicleId: String = "") {
        guard NotificationSettingsViewController.isTripStartEnabled else { return }
        let content = UNMutableNotificationContent()
        content.title = "🚗 Trip Started"
        let vehicleInfo = vehicleId.isEmpty ? "" : " · Vehicle: \(vehicleId)"
        content.body = "Trip #\(tripId) auto-started — vehicle speed detected.\(vehicleInfo)"
        content.sound = .default
        content.categoryIdentifier = "TRIP_EVENT"
        content.userInfo = ["tripId": tripId, "vehicleId": vehicleId]

        let request = UNNotificationRequest(
            identifier: "tt_trip_start_\(tripId)",
            content: content,
            trigger: nil  // fire immediately
        )

        UNUserNotificationCenter.current().add(request) { error in
            if let error = error {
                print("🔔 Failed to send trip-start notification: \(error)")
            } else {
                print("🔔 TripTrackerTrip-start notification sent for trip #\(tripId)")
            }
        }
    }

    /// Notify when a trip auto-ends.
    public func notifyTripEnded(tripId: Int64, reason: String, distance: Double, duration: Int64, vehicleId: String = "") {
        guard NotificationSettingsViewController.isTripEndEnabled else { return }
        let content = UNMutableNotificationContent()
        content.title = "🏁 Trip Ended"

        let distText = distance < 1000
            ? String(format: "%.0f m", distance)
            : String(format: "%.2f km", distance / 1000)
        let durMins = duration / 60
        let durSecs = duration % 60
        let durText = durMins > 0 ? "\(durMins)m \(durSecs)s" : "\(durSecs)s"
        let vehicleInfo = vehicleId.isEmpty ? "" : " · Vehicle: \(vehicleId)"

        content.body = "Trip #\(tripId) ended · \(distText) · \(durText)\(vehicleInfo)\n\(reason)"
        content.sound = .default
        content.categoryIdentifier = "TRIP_EVENT"
        content.userInfo = ["tripId": tripId, "vehicleId": vehicleId, "distance": distance, "duration": duration]

        let request = UNNotificationRequest(
            identifier: "tt_trip_end_\(tripId)",
            content: content,
            trigger: nil  // fire immediately
        )

        UNUserNotificationCenter.current().add(request) { error in
            if let error = error {
                print("🔔 Failed to send trip-end notification: \(error)")
            } else {
                print("🔔 TripTracker Trip-end notification sent for trip #\(tripId)")
            }
        }
    }

    /// Notify when a distance milestone is reached (every 1 km).
    public func notifyDistanceMilestone(km: Int, totalDistance: Double) {
        guard NotificationSettingsViewController.isDistanceKmEnabled else { return }
        let content = UNMutableNotificationContent()
        content.title = "📏 \(km) km Traveled"

        let distText = totalDistance < 1000
            ? String(format: "%.0f m", totalDistance)
            : String(format: "%.1f km", totalDistance / 1000)
        content.body = "You've traveled \(distText) on this trip."
        content.sound = .default
        content.categoryIdentifier = "TRIP_MILESTONE"

        let request = UNNotificationRequest(
            identifier: "tt_milestone_\(km)km",
            content: content,
            trigger: nil  // fire immediately
        )

        UNUserNotificationCenter.current().add(request) { error in
            if let error = error {
                print("🔔 Failed to send milestone notification: \(error)")
            } else {
                print("🔔 Milestone notification sent: \(km) km")
            }
        }
    }

    // MARK: - Daily 6:00 AM Reminder

    /// Schedule a repeating daily notification at 6:00 AM to check yesterday's route.
    /// Safe to call multiple times — removes the old one before rescheduling.
    public func scheduleDailyReminder() {
        let center = UNUserNotificationCenter.current()

        // Remove any existing daily reminder to avoid duplicates
        center.removePendingNotificationRequests(withIdentifiers: [dailyReminderID])

        let content = UNMutableNotificationContent()
        content.title = "📍 Check Yesterday's Route"
        content.body = "Good morning! Open TripTracker to review yesterday's trips and locations."
        content.sound = .default
        content.categoryIdentifier = "DAILY_REMINDER"

        // Trigger at 6:00 AM every day
        var dateComponents = DateComponents()
        dateComponents.hour = 6
        dateComponents.minute = 0

        let trigger = UNCalendarNotificationTrigger(dateMatching: dateComponents, repeats: true)

        let request = UNNotificationRequest(
            identifier: dailyReminderID,
            content: content,
            trigger: trigger
        )

        center.add(request) { error in
            if let error = error {
                print("🔔 Failed to schedule daily reminder: \(error)")
            } else {
                print("🔔 Daily 6:00 AM reminder scheduled")
            }
        }
    }
}

// MARK: - UNUserNotificationCenterDelegate

extension NotificationManager: UNUserNotificationCenterDelegate {

    /// Show notification even when app is in foreground.
    public func userNotificationCenter(_ center: UNUserNotificationCenter,
                                willPresent notification: UNNotification,
                                withCompletionHandler completionHandler: @escaping (UNNotificationPresentationOptions) -> Void) {
        completionHandler([.banner, .sound])
    }

    /// Handle tap on notification.
    public func userNotificationCenter(_ center: UNUserNotificationCenter,
                                didReceive response: UNNotificationResponse,
                                withCompletionHandler completionHandler: @escaping () -> Void) {
        let id = response.notification.request.identifier
        print("🔔 Notification tapped: \(id)")
        completionHandler()
    }
}
