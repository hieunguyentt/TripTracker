//
//  TripTrackerPlugin.swift
//  TripTrackerPlugin
//
//  Capacitor plugin that bridges TripTracker iOS native code to Ionic/JavaScript.
//  Exposes: tracking control, settings page, geofencing, notifications, voice, logs.
//
//  Usage in Ionic:
//    import { TripTracker } from 'capacitor-triptracker';
//    await TripTracker.openSettings();
//    await TripTracker.openNotificationSettings();
//    const status = await TripTracker.getTrackingStatus();
//

import Foundation
import Capacitor
import UIKit
import CoreLocation
import triptracking

@objc(TripTrackerPlugin)
public class TripTrackerPlugin: CAPPlugin, CAPBridgedPlugin {

    public let identifier = "TripTrackerPlugin"
    public let jsName = "TripTracker"
    public let pluginMethods: [CAPPluginMethod] = [
        CAPPluginMethod(name: "initializeWithConfig", returnType: CAPPluginReturnPromise),
        CAPPluginMethod(name: "updateVehicleId", returnType: CAPPluginReturnPromise),
        CAPPluginMethod(name: "hasLocationPermission", returnType: CAPPluginReturnPromise),
        CAPPluginMethod(name: "startTracking", returnType: CAPPluginReturnPromise),
        CAPPluginMethod(name: "stopTracking", returnType: CAPPluginReturnPromise),
        CAPPluginMethod(name: "openSettings", returnType: CAPPluginReturnPromise),
        CAPPluginMethod(name: "openNotificationSettings", returnType: CAPPluginReturnPromise),
        CAPPluginMethod(name: "openGeofenceManager", returnType: CAPPluginReturnPromise),
        CAPPluginMethod(name: "openMainView", returnType: CAPPluginReturnPromise),
        CAPPluginMethod(name: "openHistory", returnType: CAPPluginReturnPromise),
        CAPPluginMethod(name: "openDailyLocations", returnType: CAPPluginReturnPromise),
        CAPPluginMethod(name: "getTrackingStatus", returnType: CAPPluginReturnPromise),
        CAPPluginMethod(name: "getCurrentLocation", returnType: CAPPluginReturnPromise),
        CAPPluginMethod(name: "getTripHistory", returnType: CAPPluginReturnPromise),
        CAPPluginMethod(name: "getSettings", returnType: CAPPluginReturnPromise),
        CAPPluginMethod(name: "updateSetting", returnType: CAPPluginReturnPromise),
        CAPPluginMethod(name: "getGeofenceZones", returnType: CAPPluginReturnPromise),
        CAPPluginMethod(name: "addGeofenceZone", returnType: CAPPluginReturnPromise),
        CAPPluginMethod(name: "removeGeofenceZone", returnType: CAPPluginReturnPromise),
        CAPPluginMethod(name: "startWebMonitor", returnType: CAPPluginReturnPromise),
        CAPPluginMethod(name: "stopWebMonitor", returnType: CAPPluginReturnPromise),
        CAPPluginMethod(name: "sendTodayLog", returnType: CAPPluginReturnPromise),
        CAPPluginMethod(name: "sendAllLogs", returnType: CAPPluginReturnPromise),
        CAPPluginMethod(name: "sendRecentLogs", returnType: CAPPluginReturnPromise),
        CAPPluginMethod(name: "setFakeRoute", returnType: CAPPluginReturnPromise),
        CAPPluginMethod(name: "startFakeRoute", returnType: CAPPluginReturnPromise),
        CAPPluginMethod(name: "stopFakeRoute", returnType: CAPPluginReturnPromise),
    ]

    // ═══════════════════════════════════════════════════════════════
    // Lifecycle — auto-initialize on app launch (including background relaunch)
    // ═══════════════════════════════════════════════════════════════

    public override func load() {
        // Auto-initialize SDK from saved config when app relaunches
        if !TripTrackerSDK.isInitialized {
            let hasSavedConfig = UserDefaults.standard.string(forKey: "tt_api_pingURL") != nil
            if hasSavedConfig || CLLocationManager().authorizationStatus == .authorizedAlways {
                print("🔄 TripTracker plugin load() — auto-initializing SDK from saved config")
                TripTrackerSDK.initialize(config: TripTrackerConfig())
            }
        }

        // Listen for app going to background/foreground
        NotificationCenter.default.addObserver(
            self,
            selector: #selector(handleAppDidBecomeActive),
            name: UIApplication.didBecomeActiveNotification,
            object: nil
        )
        NotificationCenter.default.addObserver(
            self,
            selector: #selector(handleAppDidEnterBackground),
            name: UIApplication.didEnterBackgroundNotification,
            object: nil
        )
        NotificationCenter.default.addObserver(
            self,
            selector: #selector(handleAppWillTerminate),
            name: UIApplication.willTerminateNotification,
            object: nil
        )
    }

    @objc private func handleAppDidBecomeActive() {
        // End background task when back in foreground
        if TripTrackerSDK.isInitialized {
            LocationTrackingService.shared.startBackgroundTracking()
        }
    }

    @objc private func handleAppDidEnterBackground() {
        if TripTrackerSDK.isInitialized {
            // Begin background task to protect API calls + DB writes
            LocationTrackingService.shared.ensureBackgroundTracking()
        }
    }

    @objc private func handleAppWillTerminate() {
        if TripTrackerSDK.isInitialized {
            TripTrackerSDK.willTerminate()
        }
    }

    // MARK: - Native Settings Pages

    /// Initialize SDK with custom config from JavaScript.
    @objc func initializeWithConfig(_ call: CAPPluginCall) {
        var config = TripTrackerConfig()
        if let v = call.getDouble("saveIntervalMinutes")   { config.saveIntervalMinutes = v }
        if let v = call.getDouble("saveDistanceMeters")    { config.saveDistanceMeters = v }
        if let v = call.getDouble("vehicleThreshold")      { config.vehicleThreshold = Float(v) }
        if let v = call.getInt("transportType")             { config.transportType = v }
        if let v = call.getDouble("autoStopTimeoutMinutes") { config.autoStopTimeoutMinutes = v }
        if let v = call.getDouble("routeGapMeters")         { config.routeGapMeters = v }
        if let v = call.getBool("geofenceEnabled")          { config.geofenceEnabled = v }
        if let v = call.getBool("webMonitorEnabled")        { config.webMonitorEnabled = v }
        if let v = call.getBool("voiceFeedbackEnabled")     { config.voiceFeedbackEnabled = v }
        if let v = call.getBool("notifyTripStart")          { config.notifyTripStart = v }
        if let v = call.getBool("notifyTripEnd")            { config.notifyTripEnd = v }
        if let v = call.getBool("notifyDistanceKm")         { config.notifyDistanceKm = v }
        if let v = call.getBool("notifyGeofenceEnter")      { config.notifyGeofenceEnter = v }
        if let v = call.getBool("notifyGeofenceExit")       { config.notifyGeofenceExit = v }
        if let v = call.getString("pingURL")                { config.pingURL = v }
        if let v = call.getString("endURL")                 { config.endURL = v }
        if let v = call.getString("userId")                 { config.userId = v }
        if let v = call.getString("vehicleId")              { config.vehicleId = v }
        if let v = call.getString("osInfo")                 { config.osInfo = v }
        if let v = call.getString("routeId")                { config.routeId = v }
        if let v = call.getString("authorizationKey")       { config.authorizationKey = v }
        if let v = call.getString("apiAuthKey")             { config.apiAuthKey = v }
        if let v = call.getString("apiAuthToken")           { config.apiAuthToken = v }

        TripTrackerSDK.initialize(config: config)

        let granted = Self.hasLocationPermissionNative()
        call.resolve([
            "initialized": true,
            "permissionGranted": granted,
            "trackingStarted": true  // Service always starts
        ])
    }

    /// Update vehicle_id at any time (e.g. user switches vehicle).
    @objc func updateVehicleId(_ call: CAPPluginCall) {
        guard let vehicleId = call.getString("vehicleId") else {
            call.reject("Missing 'vehicleId'")
            return
        }
        TripTrackerSDK.updateVehicleId(vehicleId)
        call.resolve(["updated": true, "vehicleId": vehicleId])
    }

    /// Check if location permission is granted.
    @objc func hasLocationPermission(_ call: CAPPluginCall) {
        let granted = Self.hasLocationPermissionNative()
        if granted {
            TripTrackerSDK.onPermissionGranted()
        }
        call.resolve(["granted": granted])
    }

    /// Start tracking.
    @objc func startTracking(_ call: CAPPluginCall) {
        LocationTrackingService.shared.startBackgroundTracking()
        call.resolve(["started": true])
    }

    /// Stop tracking.
    @objc func stopTracking(_ call: CAPPluginCall) {
        LocationTrackingService.shared.stopTrip()
        call.resolve(["stopped": true])
    }

    /// Start GPS location updates. Call AFTER user grants "Always" permission.
    @objc func startLocationTracking(_ call: CAPPluginCall) {
        TripTrackerSDK.startLocationTracking()
        call.resolve(["started": true])
    }

    /// Stop all GPS location updates. Call when permission not granted or to pause GPS.
    @objc func stopLocationTracking(_ call: CAPPluginCall) {
        TripTrackerSDK.stopLocationTracking()
        call.resolve(["stopped": true])
    }

    private static func hasLocationPermissionNative() -> Bool {
        let status = CLLocationManager().authorizationStatus
        return status == .authorizedAlways || status == .authorizedWhenInUse
    }

    /// Open the full native Settings page (sliders, toggles, everything).
    @objc func openSettings(_ call: CAPPluginCall) {
        DispatchQueue.main.async {
            let vc = SettingsViewController()
            let nav = UINavigationController(rootViewController: vc)
            nav.modalPresentationStyle = .fullScreen
            self.bridge?.viewController?.present(nav, animated: true) {
                call.resolve(["opened": true])
            }
        }
    }

    /// Open the Notification Settings page (push toggle per type + voice).
    @objc func openNotificationSettings(_ call: CAPPluginCall) {
        DispatchQueue.main.async {
            let vc = NotificationSettingsViewController()
            let nav = UINavigationController(rootViewController: vc)
            nav.modalPresentationStyle = .fullScreen
            self.bridge?.viewController?.present(nav, animated: true) {
                call.resolve(["opened": true])
            }
        }
    }

    /// Open the Geofence Manager page (map + zone list).
    @objc func openGeofenceManager(_ call: CAPPluginCall) {
        DispatchQueue.main.async {
            let vc = GeofenceViewController()
            let nav = UINavigationController(rootViewController: vc)
            nav.modalPresentationStyle = .fullScreen
            self.bridge?.viewController?.present(nav, animated: true) {
                call.resolve(["opened": true])
            }
        }
    }

    /// Open the main TripTracker map view.
    @objc func openMainView(_ call: CAPPluginCall) {
        DispatchQueue.main.async {
            let vc = MainViewController()
            let nav = UINavigationController(rootViewController: vc)
            nav.modalPresentationStyle = .fullScreen
            self.bridge?.viewController?.present(nav, animated: true) {
                call.resolve(["opened": true])
            }
        }
    }

    /// Open the Trip History page.
    @objc func openHistory(_ call: CAPPluginCall) {
        DispatchQueue.main.async {
            let vc = HistoryViewController()
            let nav = UINavigationController(rootViewController: vc)
            nav.modalPresentationStyle = .fullScreen
            self.bridge?.viewController?.present(nav, animated: true) {
                call.resolve(["opened": true])
            }
        }
    }

    /// Open Daily Locations page.
    @objc func openDailyLocations(_ call: CAPPluginCall) {
        DispatchQueue.main.async {
            let vc = DailyLocationsViewController()
            let nav = UINavigationController(rootViewController: vc)
            nav.modalPresentationStyle = .fullScreen
            self.bridge?.viewController?.present(nav, animated: true) {
                call.resolve(["opened": true])
            }
        }
    }

    // MARK: - Tracking Status

    /// Get current tracking status, speed, trip info.
    @objc func getTrackingStatus(_ call: CAPPluginCall) {
        let svc = LocationTrackingService.shared
        let stats = svc.getCurrentStats()

        var result: [String: Any] = [
            "isTracking": svc.isTracking,
            "speed": stats.speed,
            "speedKmh": stats.speed * 3.6,
            "distance": stats.distance,
            "duration": stats.duration,
            "steps": stats.steps,
            "tripId": svc.currentTripId,
        ]

        if let coord = svc.lastKnownCoordinate {
            result["latitude"] = coord.latitude
            result["longitude"] = coord.longitude
        }

        call.resolve(result)
    }

    /// Get current GPS location.
    @objc func getCurrentLocation(_ call: CAPPluginCall) {
        let svc = LocationTrackingService.shared
        guard let loc = svc.lastKnownLocation else {
            call.reject("No location available")
            return
        }
        let stats = svc.getCurrentStats()
        call.resolve([
            "latitude": loc.coordinate.latitude,
            "longitude": loc.coordinate.longitude,
            "speed": stats.speed,
            "speedKmh": stats.speed * 3.6,
            "accuracy": loc.horizontalAccuracy,
            "bearing": loc.course >= 0 ? loc.course : 0,
            "altitude": loc.altitude,
            "timestamp": Int64(loc.timestamp.timeIntervalSince1970 * 1000),
        ])
    }

    // MARK: - Trip History

    /// Get list of all trips.
    // @objc func getTripHistory(_ call: CAPPluginCall) {
    //     let limit = call.getInt("limit") ?? 50
    //     let trips = DatabaseManager.shared.getAllTrips(limit: limit)

    //     let tripList = trips.map { trip -> [String: Any] in
    //         return [
    //             "id": trip.id,
    //             "startTime": trip.startTimeMs,
    //             "endTime": trip.endTimeMs ?? 0,
    //             "distance": trip.distanceMeters,
    //             "duration": trip.durationSeconds,
    //             "isActive": trip.isActive,
    //         ]
    //     }

    //     call.resolve(["trips": tripList, "count": tripList.count])
    // }

    // MARK: - Settings (Read / Write)

    /// Get all current settings as a dictionary.
    @objc func getSettings(_ call: CAPPluginCall) {
        let svc = LocationTrackingService.shared
        let ud = UserDefaults.standard

        call.resolve([
            "vehicleThreshold": svc.vehicleThreshold,
            "vehicleThresholdKmh": svc.vehicleThreshold * 3.6,
            "saveIntervalMinutes": Double(svc.saveIntervalMs) / 60000.0,
            "saveDistanceMeters": svc.saveDistanceVehicleM,
            "autoEndTimeoutMinutes": svc.autoEndStillnessSecs / 60.0,
            "routeGapThresholdMeters": ud.double(forKey: "tt_routeGapThresholdM"),
            "webMonitorEnabled": ud.bool(forKey: "tt_webMonitorEnabled"),
            "voiceFeedbackEnabled": VoiceFeedbackManager.shared.isEnabled,
            "geofencingEnabled": GeofenceManager.shared.isEnabled,
            "notifyTripStart": NotificationSettingsViewController.isTripStartEnabled,
            "notifyTripEnd": NotificationSettingsViewController.isTripEndEnabled,
            "notifyDistanceKm": NotificationSettingsViewController.isDistanceKmEnabled,
            "notifyGeofenceEnter": NotificationSettingsViewController.isGeofenceEnterEnabled,
            "notifyGeofenceExit": NotificationSettingsViewController.isGeofenceExitEnabled,
        ])
    }

    /// Update a single setting by key.
    /// Keys: vehicleThreshold, saveIntervalMinutes, saveDistanceMeters,
    ///       autoEndTimeoutMinutes, routeGapThresholdMeters, webMonitorEnabled,
    ///       voiceFeedbackEnabled, geofencingEnabled
    @objc func updateSetting(_ call: CAPPluginCall) {
        guard let key = call.getString("key") else {
            call.reject("Missing 'key' parameter")
            return
        }

        let svc = LocationTrackingService.shared
        let ud = UserDefaults.standard

        switch key {
        case "vehicleThreshold":
            guard let v = call.getFloat("value") else { call.reject("Missing 'value'"); return }
            svc.vehicleThreshold = v
            ud.set(v, forKey: "tt_vehicleThreshold")

        case "saveIntervalMinutes":
            guard let v = call.getDouble("value") else { call.reject("Missing 'value'"); return }
            let ms = Int64(v * 60 * 1000)
            svc.saveIntervalMs = ms
            ud.set(v * 60, forKey: "tt_saveIntervalSecs")

        case "saveDistanceMeters":
            guard let v = call.getDouble("value") else { call.reject("Missing 'value'"); return }
            svc.saveDistanceVehicleM = v
            ud.set(v, forKey: "tt_saveDistanceVehicleM")

        case "autoEndTimeoutMinutes":
            guard let v = call.getDouble("value") else { call.reject("Missing 'value'"); return }
            svc.autoEndStillnessSecs = v * 60

        case "routeGapThresholdMeters":
            guard let v = call.getDouble("value") else { call.reject("Missing 'value'"); return }
            ud.set(v, forKey: "tt_routeGapThresholdM")

        case "webMonitorEnabled":
            guard let v = call.getBool("value") else { call.reject("Missing 'value'"); return }
            ud.set(v, forKey: "tt_webMonitorEnabled")
            DispatchQueue.main.async {
                if v {
                    TripTrackerSDK.startWebMonitor()
                } else {
                    TripTrackerSDK.stopWebMonitor()
                }
            }

        case "voiceFeedbackEnabled":
            guard let v = call.getBool("value") else { call.reject("Missing 'value'"); return }
            VoiceFeedbackManager.shared.isEnabled = v

        case "geofencingEnabled":
            guard let v = call.getBool("value") else { call.reject("Missing 'value'"); return }
            GeofenceManager.shared.isEnabled = v

        default:
            call.reject("Unknown setting key: \(key)")
            return
        }

        call.resolve(["key": key, "updated": true])
    }

    // MARK: - Geofence

    /// Get all geofence zones.
    @objc func getGeofenceZones(_ call: CAPPluginCall) {
        let zones = GeofenceManager.shared.zones.map { zone -> [String: Any] in
            [
                "id": zone.id,
                "name": zone.name,
                "latitude": zone.latitude,
                "longitude": zone.longitude,
                "radius": zone.radius,
                "notifyOnEnter": zone.notifyOnEnter,
                "notifyOnExit": zone.notifyOnExit,
                "autoStopOnEnter": zone.autoStopOnEnter,
            ]
        }
        call.resolve(["zones": zones, "count": zones.count])
    }

    /// Add a new geofence zone.
    @objc func addGeofenceZone(_ call: CAPPluginCall) {
        guard let name = call.getString("name"),
              let lat = call.getDouble("latitude"),
              let lon = call.getDouble("longitude") else {
            call.reject("Missing name, latitude, or longitude")
            return
        }
        let radius = call.getDouble("radius") ?? 200
        let notifyEnter = call.getBool("notifyOnEnter") ?? true
        let notifyExit = call.getBool("notifyOnExit") ?? true
        let autoStop = call.getBool("autoStopOnEnter") ?? false

        let zone = GeofenceZone(
            name: name,
            latitude: lat,
            longitude: lon,
            radius: radius,
            notifyOnEnter: notifyEnter,
            notifyOnExit: notifyExit,
            autoStopOnEnter: autoStop
        )
        GeofenceManager.shared.addZone(zone)
        call.resolve(["id": zone.id, "added": true])
    }

    /// Remove a geofence zone by ID.
    @objc func removeGeofenceZone(_ call: CAPPluginCall) {
        guard let id = call.getString("id") else {
            call.reject("Missing 'id' parameter")
            return
        }
        GeofenceManager.shared.removeZone(id: id)
        call.resolve(["id": id, "removed": true])
    }

    // MARK: - Web Monitor

    @objc func startWebMonitor(_ call: CAPPluginCall) {
        DispatchQueue.main.async {
        TripTrackerSDK.stopWebMonitor()  // ← stop trước
        
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.5) {
            TripTrackerSDK.startWebMonitor()
            call.resolve(["started": true])
        }
    }
    }

    @objc func stopWebMonitor(_ call: CAPPluginCall) {
        DispatchQueue.main.async {
            TripTrackerSDK.stopWebMonitor()
            call.resolve(["stopped": true])
        }
    }

    // MARK: - Logs

    @objc func sendTodayLog(_ call: CAPPluginCall) {
        DispatchQueue.main.async {
            guard let zipURL = LogManager.shared.getZippedLogs(days: 1) else {
                call.reject("No log file for today")
                return
            }
            self.shareFiles([zipURL], subject: "TripTracker Today's Log")
            call.resolve(["shared": true])
        }
    }

    @objc func sendAllLogs(_ call: CAPPluginCall) {
        DispatchQueue.main.async {
            guard let zipURL = LogManager.shared.getZippedLogs() else {
                call.reject("No log files found or zip failed")
                return
            }
            self.shareFiles([zipURL], subject: "TripTracker All Logs")
            call.resolve(["shared": true, "count": LogManager.shared.getAllLogFiles().count])
        }
    }

    /// Send the last 3 days of log files via share sheet (email, AirDrop, etc.)
    @objc func sendRecentLogs(_ call: CAPPluginCall) {
        let days = call.getInt("days") ?? 3
        DispatchQueue.main.async {
            guard let zipURL = LogManager.shared.getZippedLogs(days: days) else {
                call.reject("No log files found or zip failed")
                return
            }
            self.shareFiles([zipURL], subject: "TripTracker Logs (last \(days) days)")
            call.resolve(["shared": true, "count": days, "days": days])
        }
    }

    private func shareFiles(_ files: [URL], subject: String) {
        var items: [Any] = [subject]
        items.append(contentsOf: files)
        let activityVC = UIActivityViewController(activityItems: items, applicationActivities: nil)
        activityVC.setValue(subject, forKey: "subject")
        if let popover = activityVC.popoverPresentationController {
            popover.sourceView = self.bridge?.viewController?.view
        }
        self.bridge?.viewController?.present(activityVC, animated: true)
    }
}
