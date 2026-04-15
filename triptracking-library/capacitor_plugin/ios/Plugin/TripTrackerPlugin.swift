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

@objc(TripTrackerPlugin)
public class TripTrackerPlugin: CAPPlugin, CAPBridgedPlugin {

    public let identifier = "TripTrackerPlugin"
    public let jsName = "TripTracker"
    public let pluginMethods: [CAPPluginMethod] = [
        CAPPluginMethod(name: "initializeWithConfig", returnType: CAPPluginReturnPromise),
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
    ]

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

        TripTrackerSDK.initialize(config: config)
        call.resolve(["initialized": true])
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
        guard let coord = svc.lastKnownCoordinate else {
            call.reject("No location available")
            return
        }
        let stats = svc.getCurrentStats()
        call.resolve([
            "latitude": coord.latitude,
            "longitude": coord.longitude,
            "speed": stats.speed,
            "speedKmh": stats.speed * 3.6,
        ])
    }

    // MARK: - Trip History

    /// Get list of all trips.
    @objc func getTripHistory(_ call: CAPPluginCall) {
        let limit = call.getInt("limit") ?? 50
        let trips = DatabaseManager.shared.getAllTrips(limit: limit)

        let tripList = trips.map { trip -> [String: Any] in
            return [
                "id": trip.id,
                "startTime": trip.startTimeMs,
                "endTime": trip.endTimeMs ?? 0,
                "distance": trip.distanceMeters,
                "duration": trip.durationSeconds,
                "isActive": trip.isActive,
            ]
        }

        call.resolve(["trips": tripList, "count": tripList.count])
    }

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
            TripTrackerSDK.startWebMonitor()
            call.resolve(["started": true])
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
            guard let todayFile = LogManager.shared.getTodayLogFile() else {
                call.reject("No log file for today")
                return
            }
            self.shareFiles([todayFile], subject: "TripTracker Today's Log")
            call.resolve(["shared": true])
        }
    }

    @objc func sendAllLogs(_ call: CAPPluginCall) {
        DispatchQueue.main.async {
            let files = LogManager.shared.getAllLogFiles()
            guard !files.isEmpty else {
                call.reject("No log files found")
                return
            }
            self.shareFiles(files, subject: "TripTracker All Logs")
            call.resolve(["shared": true, "count": files.count])
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
