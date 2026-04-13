import Flutter
import UIKit
import CoreLocation

public class TripTrackerPlugin: NSObject, FlutterPlugin {

    public static func register(with registrar: FlutterPluginRegistrar) {
        let channel = FlutterMethodChannel(name: "triptracker", binaryMessenger: registrar.messenger())
        let instance = TripTrackerPlugin()
        registrar.addMethodCallDelegate(instance, channel: channel)
    }

    public func handle(_ call: FlutterMethodCall, result: @escaping FlutterResult) {
        let args = call.arguments as? [String: Any]

        switch call.method {

        // ── Native Pages ──

        case "openSettings":
            presentVC(SettingsViewController(), result: result)

        case "openNotificationSettings":
            presentVC(NotificationSettingsViewController(), result: result)

        case "openGeofenceManager":
            presentVC(GeofenceViewController(), result: result)

        case "openMainView":
            presentVC(MainViewController(), result: result)

        case "openHistory":
            presentVC(HistoryViewController(), result: result)

        case "openDailyLocations":
            presentVC(DailyLocationsViewController(), result: result)

        // ── Tracking ──

        case "getTrackingStatus":
            let svc = LocationTrackingService.shared
            let stats = svc.getCurrentStats()
            var res: [String: Any] = [
                "isTracking": svc.isTracking,
                "speed": stats.speed,
                "speedKmh": Double(stats.speed) * 3.6,
                "distance": stats.distance,
                "duration": stats.duration,
                "steps": stats.steps,
                "tripId": svc.currentTripId,
            ]
            if let coord = svc.lastKnownCoordinate {
                res["latitude"] = coord.latitude
                res["longitude"] = coord.longitude
            }
            result(res)

        case "getCurrentLocation":
            let svc = LocationTrackingService.shared
            guard let coord = svc.lastKnownCoordinate else {
                result(FlutterError(code: "NO_LOCATION", message: "No location available", details: nil))
                return
            }
            let stats = svc.getCurrentStats()
            result([
                "latitude": coord.latitude,
                "longitude": coord.longitude,
                "speed": stats.speed,
                "speedKmh": Double(stats.speed) * 3.6,
            ])

        // ── History ──

        case "getTripHistory":
            let limit = args?["limit"] as? Int ?? 50
            let trips = DatabaseManager.shared.getAllTrips(limit: limit)
            let tripList = trips.map { trip -> [String: Any] in
                [
                    "id": trip.id,
                    "startTime": trip.startTimeMs,
                    "endTime": trip.endTimeMs ?? 0,
                    "distance": trip.distanceMeters,
                    "duration": trip.durationSeconds,
                    "isActive": trip.isActive,
                ]
            }
            result(["trips": tripList, "count": tripList.count])

        // ── Settings ──

        case "getSettings":
            let svc = LocationTrackingService.shared
            let ud = UserDefaults.standard
            result([
                "vehicleThreshold": svc.vehicleThreshold,
                "vehicleThresholdKmh": Double(svc.vehicleThreshold) * 3.6,
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

        case "updateSetting":
            guard let key = args?["key"] as? String else {
                result(FlutterError(code: "MISSING_KEY", message: "Missing 'key'", details: nil))
                return
            }
            let svc = LocationTrackingService.shared
            let ud = UserDefaults.standard

            switch key {
            case "vehicleThreshold":
                if let v = args?["value"] as? Double { svc.vehicleThreshold = Float(v); ud.set(Float(v), forKey: "tt_vehicleThreshold") }
            case "saveIntervalMinutes":
                if let v = args?["value"] as? Double { svc.saveIntervalMs = Int64(v * 60 * 1000); ud.set(v * 60, forKey: "tt_saveIntervalSecs") }
            case "saveDistanceMeters":
                if let v = args?["value"] as? Double { svc.saveDistanceVehicleM = v; ud.set(v, forKey: "tt_saveDistanceVehicleM") }
            case "autoEndTimeoutMinutes":
                if let v = args?["value"] as? Double { svc.autoEndStillnessSecs = v * 60 }
            case "routeGapThresholdMeters":
                if let v = args?["value"] as? Double { ud.set(v, forKey: "tt_routeGapThresholdM") }
            case "webMonitorEnabled":
                if let v = args?["value"] as? Bool { if v { TripTrackerSDK.startWebMonitor() } else { TripTrackerSDK.stopWebMonitor() } }
            case "voiceFeedbackEnabled":
                if let v = args?["value"] as? Bool { VoiceFeedbackManager.shared.isEnabled = v }
            case "geofencingEnabled":
                if let v = args?["value"] as? Bool { GeofenceManager.shared.isEnabled = v }
            default:
                result(FlutterError(code: "UNKNOWN_KEY", message: "Unknown setting: \(key)", details: nil))
                return
            }
            result(["key": key, "updated": true])

        // ── Geofence ──

        case "getGeofenceZones":
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
            result(["zones": zones, "count": zones.count])

        case "addGeofenceZone":
            guard let name = args?["name"] as? String,
                  let lat = args?["latitude"] as? Double,
                  let lon = args?["longitude"] as? Double else {
                result(FlutterError(code: "MISSING_ARGS", message: "Missing name/latitude/longitude", details: nil))
                return
            }
            let zone = GeofenceZone(
                name: name,
                latitude: lat,
                longitude: lon,
                radius: args?["radius"] as? Double ?? 200,
                notifyOnEnter: args?["notifyOnEnter"] as? Bool ?? true,
                notifyOnExit: args?["notifyOnExit"] as? Bool ?? true,
                autoStopOnEnter: args?["autoStopOnEnter"] as? Bool ?? false
            )
            GeofenceManager.shared.addZone(zone)
            result(["id": zone.id, "added": true])

        case "removeGeofenceZone":
            guard let id = args?["id"] as? String else {
                result(FlutterError(code: "MISSING_ID", message: "Missing 'id'", details: nil))
                return
            }
            GeofenceManager.shared.removeZone(id: id)
            result(["id": id, "removed": true])

        // ── Web Monitor ──

        case "startWebMonitor":
            TripTrackerSDK.startWebMonitor()
            result(["started": true])

        case "stopWebMonitor":
            TripTrackerSDK.stopWebMonitor()
            result(["stopped": true])

        // ── Logs ──

        case "sendTodayLog":
            DispatchQueue.main.async {
                guard let file = LogManager.shared.getTodayLogFile() else {
                    result(FlutterError(code: "NO_LOG", message: "No log for today", details: nil))
                    return
                }
                self.shareFiles([file], subject: "TripTracker Today's Log")
                result(["shared": true])
            }

        case "sendAllLogs":
            DispatchQueue.main.async {
                let files = LogManager.shared.getAllLogFiles()
                guard !files.isEmpty else {
                    result(FlutterError(code: "NO_LOGS", message: "No log files", details: nil))
                    return
                }
                self.shareFiles(files, subject: "TripTracker All Logs")
                result(["shared": true, "count": files.count])
            }

        default:
            result(FlutterMethodNotImplemented)
        }
    }

    // MARK: - Helpers

    private func presentVC(_ vc: UIViewController, result: @escaping FlutterResult) {
        DispatchQueue.main.async {
            let nav = UINavigationController(rootViewController: vc)
            nav.modalPresentationStyle = .fullScreen
            if let topVC = UIApplication.shared.connectedScenes
                .compactMap({ $0 as? UIWindowScene })
                .first(where: { $0.activationState == .foregroundActive })?
                .windows.first(where: { $0.isKeyWindow })?
                .rootViewController {
                var presenter = topVC
                while let presented = presenter.presentedViewController {
                    presenter = presented
                }
                presenter.present(nav, animated: true) {
                    result(["opened": true])
                }
            } else {
                result(FlutterError(code: "NO_VC", message: "No view controller", details: nil))
            }
        }
    }

    private func shareFiles(_ files: [URL], subject: String) {
        var items: [Any] = [subject]
        items.append(contentsOf: files)
        let activityVC = UIActivityViewController(activityItems: items, applicationActivities: nil)
        activityVC.setValue(subject, forKey: "subject")
        if let topVC = UIApplication.shared.connectedScenes
            .compactMap({ $0 as? UIWindowScene })
            .first(where: { $0.activationState == .foregroundActive })?
            .windows.first(where: { $0.isKeyWindow })?
            .rootViewController {
            if let popover = activityVC.popoverPresentationController {
                popover.sourceView = topVC.view
            }
            topVC.present(activityVC, animated: true)
        }
    }
}
