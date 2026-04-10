//
//  GeofenceManager.swift
//  TripTracker
//
//  Manages geofence zones: persistence, region monitoring, enter/exit handling.
//  Zones are stored in UserDefaults as JSON.
//
//  TWO-LAYER GEOFENCING:
//    1. Manual GPS check — runs on every GPS fix from LocationTrackingService.
//       Reliable, real-time, works for any radius (even 50m).
//    2. iOS native CLCircularRegion — backup for when app is terminated.
//       iOS wakes the app on boundary crossing (uses cell/WiFi, ~200m accuracy).
//
//  LocationTrackingService calls checkLocation(_:) on every GPS fix
//  and forwards didEnterRegion/didExitRegion for the native backup.
//

import Foundation
import CoreLocation
import UserNotifications

class GeofenceManager {

    static let shared = GeofenceManager()

    private let storageKey = "tt_geofence_zones"
    private let enabledKey = "tt_geofence_enabled"
    private let stateKey   = "tt_geofence_inside_ids"

    /// All saved zones.
    private(set) var zones: [GeofenceZone] = []

    /// Set of zone IDs the user is currently inside (persisted for app relaunch).
    private var insideZoneIDs: Set<String> = []

    /// Last known good GPS location (for sanity-checking jumps).
    private var lastGoodLocation: CLLocation?

    /// Counts consecutive "outside" readings per zone. Must reach threshold before exit fires.
    private var exitCounters: [String: Int] = [:]

    /// Minimum consecutive "outside" readings required before triggering exit (prevents GPS glitches).
    private let exitThreshold = 5

    /// Timestamp of last enter/exit event per zone (cooldown to prevent rapid toggling).
    private var lastEventTime: [String: Date] = [:]

    /// Minimum seconds between enter/exit events for the same zone.
    private let eventCooldownSecs: TimeInterval = 60.0

    /// Maximum acceptable GPS accuracy (metres). Fixes worse than this are ignored.
    private let maxAccuracyM: Double = 50.0

    /// Maximum plausible jump distance (metres) from last good fix. Beyond this → bogus GPS.
    private let maxJumpM: Double = 5000.0

    /// Master toggle — when off, all monitoring is paused.
    var isEnabled: Bool {
        get { UserDefaults.standard.bool(forKey: enabledKey) }
        set {
            UserDefaults.standard.set(newValue, forKey: enabledKey)
            if newValue { startMonitoringAll() } else { stopMonitoringAll() }
            print("🔶 Geofencing \(newValue ? "enabled" : "disabled")")
        }
    }

    private init() {
        loadZones()
        loadInsideState()
    }

    // MARK: - Persistence

    private func loadZones() {
        guard let data = UserDefaults.standard.data(forKey: storageKey),
              let decoded = try? JSONDecoder().decode([GeofenceZone].self, from: data) else {
            zones = []
            return
        }
        zones = decoded
        print("🔶 Loaded \(zones.count) geofence zone(s)")
    }

    private func saveZones() {
        if let data = try? JSONEncoder().encode(zones) {
            UserDefaults.standard.set(data, forKey: storageKey)
        }
    }

    private func loadInsideState() {
        if let ids = UserDefaults.standard.array(forKey: stateKey) as? [String] {
            insideZoneIDs = Set(ids)
            print("🔶 Restored inside-state: \(insideZoneIDs.count) zone(s)")
        }
    }

    private func saveInsideState() {
        UserDefaults.standard.set(Array(insideZoneIDs), forKey: stateKey)
    }

    // MARK: - Zone CRUD

    func addZone(_ zone: GeofenceZone) {
        guard zones.count < 20 else {
            print("🔶 Cannot add zone — max 20 reached")
            return
        }
        zones.append(zone)
        saveZones()
        if isEnabled { startMonitoring(zone) }
        print("🔶 Added zone: \(zone.name) (\(zone.latitude), \(zone.longitude)) r=\(Int(zone.radius))m")
    }

    func removeZone(at index: Int) {
        guard index < zones.count else { return }
        let zone = zones[index]
        stopMonitoring(zone)
        insideZoneIDs.remove(zone.id)
        saveInsideState()
        zones.remove(at: index)
        saveZones()
        print("🔶 Removed zone: \(zone.name)")
    }

    func removeZone(id: String) {
        if let idx = zones.firstIndex(where: { $0.id == id }) {
            removeZone(at: idx)
        }
    }

    // MARK: - Native iOS Region Monitoring (backup for terminated state)

    func startMonitoringAll() {
        guard isEnabled else { return }
        for zone in zones { startMonitoring(zone) }
        print("🔶 Monitoring \(zones.count) geofence zone(s)")
    }

    func stopMonitoringAll() {
        let lm = LocationTrackingService.shared.regionLocationManager
        for region in lm.monitoredRegions {
            if zones.contains(where: { $0.id == region.identifier }) {
                lm.stopMonitoring(for: region)
            }
        }
        print("🔶 Stopped all geofence monitoring")
    }

    private func startMonitoring(_ zone: GeofenceZone) {
        guard CLLocationManager.isMonitoringAvailable(for: CLCircularRegion.self) else {
            print("🔶 Region monitoring not available on this device")
            return
        }
        let lm = LocationTrackingService.shared.regionLocationManager
        lm.startMonitoring(for: zone.region)
        print("🔶 Native monitoring started: \(zone.name) r=\(Int(zone.radius))m")
    }

    private func stopMonitoring(_ zone: GeofenceZone) {
        let lm = LocationTrackingService.shared.regionLocationManager
        lm.stopMonitoring(for: zone.region)
    }

    // MARK: - Manual GPS-Based Geofence Check (primary, real-time)
    //
    // Called ONLY from didUpdateLocations (real GPS fixes).
    // NOT called from sensor updates or periodic saves — those use stale
    // dead-reckoned positions that cause false enter/exit toggling.
    //
    // THREE PROTECTIONS against false enter/exit:
    //   1. GPS quality filter — reject fixes with accuracy > 50m or impossible jumps (> 5km)
    //   2. Exit debounce — require 3 consecutive "outside" readings before firing exit
    //   3. Cooldown — minimum 30 seconds between enter/exit events for the same zone

    func checkLocation(_ location: CLLocation) {
        guard isEnabled, !zones.isEmpty else { return }

        // ── Protection 1: GPS quality filter ──
        // Reject fixes with poor accuracy
        guard location.horizontalAccuracy > 0,
              location.horizontalAccuracy <= maxAccuracyM else {
            return
        }

        // Reject impossible jumps (bogus GPS — your logs showed 18,866 km jumps)
        if let lastGood = lastGoodLocation {
            let jump = location.distance(from: lastGood)
            let dt = location.timestamp.timeIntervalSince(lastGood.timestamp)
            // If jumped > 5km in < 30 seconds → bogus fix, skip it
            if jump > maxJumpM && dt < 30 {
                print("🔶 GPS check SKIPPED — bogus jump \(Int(jump))m in \(String(format:"%.1f", dt))s")
                return
            }
        }
        lastGoodLocation = location

        // ── Check each zone ──
        for zone in zones {
            let zoneCenter = CLLocation(latitude: zone.latitude, longitude: zone.longitude)
            let distance = location.distance(from: zoneCenter)
            let wasInside = insideZoneIDs.contains(zone.id)
            let isInside = distance <= zone.radius

            if isInside && !wasInside {
                // ── ENTERING zone ──
                // Reset exit counter
                exitCounters[zone.id] = 0

                // Protection 3: cooldown check
                if let lastTime = lastEventTime[zone.id],
                   Date().timeIntervalSince(lastTime) < eventCooldownSecs {
                    // Too soon after last event — skip
                    continue
                }

                insideZoneIDs.insert(zone.id)
                saveInsideState()
                lastEventTime[zone.id] = Date()
                print("🔶 GPS check → ENTERED: \(zone.name) (dist=\(Int(distance))m ≤ r=\(Int(zone.radius))m)")
                handleEnter(zone: zone)

            } else if !isInside && wasInside {
                // ── Potentially EXITING zone ──
                // Protection 2: require multiple consecutive "outside" readings
                let count = (exitCounters[zone.id] ?? 0) + 1
                exitCounters[zone.id] = count

                if count < exitThreshold {
                    // Not enough consecutive "outside" readings yet — don't fire exit
                    print("🔶 GPS check → outside \(zone.name) (\(count)/\(exitThreshold)) dist=\(Int(distance))m — waiting for confirmation")
                    continue
                }

                // Protection 3: cooldown check
                if let lastTime = lastEventTime[zone.id],
                   Date().timeIntervalSince(lastTime) < eventCooldownSecs {
                    continue
                }

                // Confirmed exit: enough consecutive readings outside
                exitCounters[zone.id] = 0
                insideZoneIDs.remove(zone.id)
                saveInsideState()
                lastEventTime[zone.id] = Date()
                print("🔶 GPS check → EXITED: \(zone.name) (dist=\(Int(distance))m > r=\(Int(zone.radius))m) confirmed after \(exitThreshold) readings")
                handleExit(zone: zone)

            } else if isInside && wasInside {
                // Still inside — reset exit counter
                exitCounters[zone.id] = 0
            }
        }
    }

    // MARK: - Native Region Event Handlers (backup — forwarded by LocationTrackingService)

    func handleDidEnterRegion(_ region: CLRegion) {
        guard let zone = zones.first(where: { $0.id == region.identifier }) else { return }
        // Only fire if manual check hasn't already handled it
        guard !insideZoneIDs.contains(zone.id) else {
            print("🔶 Native didEnterRegion: \(zone.name) — already handled by GPS check")
            return
        }
        insideZoneIDs.insert(zone.id)
        saveInsideState()
        print("🔶 Native didEnterRegion → ENTERED: \(zone.name)")
        handleEnter(zone: zone)
    }

    func handleDidExitRegion(_ region: CLRegion) {
        guard let zone = zones.first(where: { $0.id == region.identifier }) else { return }
        // Only fire if manual check hasn't already handled it
        guard insideZoneIDs.contains(zone.id) else {
            print("🔶 Native didExitRegion: \(zone.name) — already handled by GPS check")
            return
        }
        insideZoneIDs.remove(zone.id)
        saveInsideState()
        print("🔶 Native didExitRegion → EXITED: \(zone.name)")
        handleExit(zone: zone)
    }

    func handleMonitoringFailed(for region: CLRegion?, error: Error) {
        print("🔶 Monitoring failed for \(region?.identifier ?? "?") — \(error.localizedDescription)")
    }

    // MARK: - Enter / Exit Actions

    private func handleEnter(zone: GeofenceZone) {
        if zone.notifyOnEnter && NotificationSettingsViewController.isGeofenceEnterEnabled {
            sendNotification(title: "📍 Entered: \(zone.name)",
                             body: "You arrived at \(zone.name).")
        }

        // Voice feedback
        VoiceFeedbackManager.shared.announceGeofenceEntered(zoneName: zone.name)

        // CarPlay alert
        NotificationCenter.default.post(name: .geofenceEntered, object: nil,
            userInfo: ["zoneName": zone.name])

        // Auto-stop trip on enter (e.g., arriving home)
        if zone.autoStopOnEnter {
            let svc = LocationTrackingService.shared
            if svc.isTracking {
                let tripId = svc.currentTripId
                let stats = svc.getCurrentStats()
                print("🔶 Auto-stopping trip #\(tripId) — entered geofence \(zone.name)")
                svc.stopTrip()

                NotificationManager.shared.notifyTripEnded(
                    tripId: tripId,
                    reason: "Entered geofence: \(zone.name)",
                    distance: stats.distance,
                    duration: stats.duration
                )

                DispatchQueue.main.async {
                    svc.autoTripDelegate?.autoTripDidEnd(
                        tripId: tripId,
                        reason: "Entered geofence: \(zone.name)"
                    )
                }
            }
        }
    }

    private func handleExit(zone: GeofenceZone) {
        if zone.notifyOnExit && NotificationSettingsViewController.isGeofenceExitEnabled {
            sendNotification(title: "📍 Left: \(zone.name)",
                             body: "You left \(zone.name).")
        }

        // Voice feedback
        VoiceFeedbackManager.shared.announceGeofenceExited(zoneName: zone.name)

        // CarPlay alert
        NotificationCenter.default.post(name: .geofenceExited, object: nil,
            userInfo: ["zoneName": zone.name])
    }

    // MARK: - Notification

    private func sendNotification(title: String, body: String) {
        let content = UNMutableNotificationContent()
        content.title = title
        content.body  = body
        content.sound = .default
        content.categoryIdentifier = "GEOFENCE_EVENT"

        let request = UNNotificationRequest(
            identifier: "geofence_\(UUID().uuidString)",
            content: content,
            trigger: nil  // fire immediately
        )
        UNUserNotificationCenter.current().add(request) { error in
            if let error = error {
                print("🔶 Notification error: \(error)")
            } else {
                print("🔶 Geofence notification sent: \(title)")
            }
        }
    }
}
