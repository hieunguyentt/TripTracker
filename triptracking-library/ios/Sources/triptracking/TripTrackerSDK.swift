import UIKit
import CoreLocation

// MARK: - Configuration

public struct TripTrackerConfig {

    // Save & Tracking
    public var saveIntervalMinutes: Double = 15.0
    public var saveDistanceMeters: Double = 30.0
    public var vehicleThreshold: Float = 6.0
    public var transportType: Int = 0   // 0=Car, 1=Moto, 2=Bike, 3=Walk
    public var autoStopTimeoutMinutes: Double = 5.0
    public var routeGapMeters: Double = 500.0

    // Features
    public var geofenceEnabled: Bool = false
    public var webMonitorEnabled: Bool = false
    public var voiceFeedbackEnabled: Bool = false

    // API
    public var pingURL: String = ""
    public var endURL: String = ""
    public var userId: String = ""
    public var vehicleId: String = ""
    public var osInfo: String = ""
    public var routeId: String = ""
    public var authorizationKey: String = ""
    public var apiAuthKey: String = ""
    public var apiAuthToken: String = ""    // NEW header: api-auth-token

    // Notifications
    public var notifyTripStart: Bool = false
    public var notifyTripEnd: Bool = false
    public var notifyDistanceKm: Bool = false
    public var notifyGeofenceEnter: Bool = false
    public var notifyGeofenceExit: Bool = false

    public init() {}

    public init(from dict: [String: Any]) {
        if let v = dict["saveIntervalMinutes"] as? Double   { saveIntervalMinutes = v }
        if let v = dict["saveDistanceMeters"] as? Double    { saveDistanceMeters = v }
        if let v = dict["vehicleThreshold"] as? Double      { vehicleThreshold = Float(v) }
        if let v = dict["transportType"] as? Int             { transportType = v }
        if let v = dict["autoStopTimeoutMinutes"] as? Double { autoStopTimeoutMinutes = v }
        if let v = dict["routeGapMeters"] as? Double         { routeGapMeters = v }
        if let v = dict["geofenceEnabled"] as? Bool          { geofenceEnabled = v }
        if let v = dict["webMonitorEnabled"] as? Bool        { webMonitorEnabled = v }
        if let v = dict["voiceFeedbackEnabled"] as? Bool     { voiceFeedbackEnabled = v }
        if let v = dict["pingURL"] as? String                { pingURL = v }
        if let v = dict["endURL"] as? String                  { endURL = v }
        if let v = dict["userId"] as? String                  { userId = v }
        if let v = dict["vehicleId"] as? String               { vehicleId = v }
        if let v = dict["osInfo"] as? String                  { osInfo = v }
        if let v = dict["routeId"] as? String                 { routeId = v }
        if let v = dict["authorizationKey"] as? String        { authorizationKey = v }
        if let v = dict["apiAuthKey"] as? String              { apiAuthKey = v }
        if let v = dict["apiAuthToken"] as? String            { apiAuthToken = v }
        if let v = dict["notifyTripStart"] as? Bool          { notifyTripStart = v }
        if let v = dict["notifyTripEnd"] as? Bool            { notifyTripEnd = v }
        if let v = dict["notifyDistanceKm"] as? Bool         { notifyDistanceKm = v }
        if let v = dict["notifyGeofenceEnter"] as? Bool      { notifyGeofenceEnter = v }
        if let v = dict["notifyGeofenceExit"] as? Bool       { notifyGeofenceExit = v }
    }
}

// MARK: - SDK

public final class TripTrackerSDK {

    public static var webServer: LocationWebServer?
    private static var _initialized = false
    public static var isInitialized: Bool { _initialized }

    // ── Initialize with defaults ──
    public static func initialize(launchOptions: [UIApplication.LaunchOptionsKey: Any]? = nil) {
        initialize(config: TripTrackerConfig(), launchOptions: launchOptions)
    }

    // ── Initialize with config ──
    public static func initialize(config: TripTrackerConfig,
                                  launchOptions: [UIApplication.LaunchOptionsKey: Any]? = nil) {
        guard !_initialized else {
            applyConfig(config)
            return
        }

        applyConfig(config)
        LogManager.shared.start()

        // Restore API config from UserDefaults (in case app was killed + relaunched)
        restoreAPIConfigFromDefaults()

        let isLocationRelaunch = launchOptions?[.location] != nil
        DatabaseManager.shared.initializeDatabase()

        // ALWAYS start the service — it requests permission internally
        LocationTrackingService.shared.startBackgroundTracking()

        if let info = DatabaseManager.shared.getActiveTripInfo() {
            let wasAutoEnded = LocationTrackingService.shared.checkAndAutoEndStaleTrip()
            if !wasAutoEnded { LocationTrackingService.shared.resumeTrip(id: info.id, startTimeMs: info.startTimeMs) }
        } else if isLocationRelaunch {
            LocationTrackingService.shared.handleSignificantLocationRelaunch()
        }

        if UserDefaults.standard.bool(forKey: "tt_webMonitorEnabled") {
            webServer = LocationWebServer(); webServer?.start()
        }

        NotificationManager.shared.requestPermission()
        if GeofenceManager.shared.isEnabled { GeofenceManager.shared.startMonitoringAll() }

        // If permission not yet granted, request it and observe for changes
        if !hasLocationPermission {
            print("⚠️ TripTracker Location permission not granted — requesting…")
            permissionDelegate = LocationPermissionDelegate()
        } else {
            print("✅ TripTracker Location permission already granted — tracking active")
        }

        _initialized = true
        print("✅ TripTracker TripTrackerSDK initialized")
    }

    // ── Permission ──
    public static var hasLocationPermission: Bool {
        let status = CLLocationManager().authorizationStatus
        return status == .authorizedAlways || status == .authorizedWhenInUse
    }

    /// Called when permission is granted (from delegate or plugin)
    public static func onPermissionGranted() {
        LocationTrackingService.shared.startBackgroundTracking()
        permissionDelegate = nil  // no longer needed
        print("✅ TripTracker Permission granted — tracking activated")
    }

    private static var permissionDelegate: LocationPermissionDelegate?

    // ── Apply config to UserDefaults + live services ──
    public static func applyConfig(_ config: TripTrackerConfig) {
        let ud = UserDefaults.standard
        ud.set(config.saveIntervalMinutes * 60.0, forKey: "tt_saveIntervalSecs")
        ud.set(config.saveDistanceMeters, forKey: "tt_saveDistanceVehicleM")
        ud.set(config.vehicleThreshold, forKey: "tt_vehicleThreshold")
        ud.set(config.transportType, forKey: "tt_transportType")
        ud.set(config.autoStopTimeoutMinutes * 60.0, forKey: "tt_autoEndStillnessSecs")
        ud.set(config.routeGapMeters, forKey: "tt_routeGapThresholdM")
        ud.set(config.webMonitorEnabled, forKey: "tt_webMonitorEnabled")
        ud.set(config.voiceFeedbackEnabled, forKey: "tt_voiceFeedbackEnabled")
        ud.set(config.notifyTripStart, forKey: "tt_notify_tripStart")
        ud.set(config.notifyTripEnd, forKey: "tt_notify_tripEnd")
        ud.set(config.notifyDistanceKm, forKey: "tt_notify_distanceKm")
        ud.set(config.notifyGeofenceEnter, forKey: "tt_notify_geofenceEnter")
        ud.set(config.notifyGeofenceExit, forKey: "tt_notify_geofenceExit")

        GeofenceManager.shared.isEnabled = config.geofenceEnabled

        let svc = LocationTrackingService.shared
        svc.vehicleThreshold = config.vehicleThreshold
        svc.saveDistanceVehicleM = config.saveDistanceMeters
        svc.saveIntervalMs = Int64(config.saveIntervalMinutes * 60 * 1000)
        svc.autoEndStillnessSecs = config.autoStopTimeoutMinutes * 60.0
        VoiceFeedbackManager.shared.isEnabled = config.voiceFeedbackEnabled

        if config.webMonitorEnabled { startWebMonitor() } else { stopWebMonitor() }

        // API Service
        var apiConfig = TripTrackerAPIConfig()
        apiConfig.pingURL = config.pingURL
        apiConfig.endURL = config.endURL
        apiConfig.userId = config.userId
        apiConfig.vehicleId = config.vehicleId
        if !config.osInfo.isEmpty { apiConfig.osInfo = config.osInfo }
        apiConfig.routeId = config.routeId
        apiConfig.authorizationKey = config.authorizationKey
        apiConfig.apiAuthKey = config.apiAuthKey
        apiConfig.apiAuthToken = config.apiAuthToken
        TripTrackerAPIService.shared.config = apiConfig

        // Persist API config — survives app kill + service restart
        ud.set(config.pingURL, forKey: "tt_api_pingURL")
        ud.set(config.endURL, forKey: "tt_api_endURL")
        ud.set(config.userId, forKey: "tt_api_userId")
        ud.set(config.vehicleId, forKey: "tt_api_vehicleId")
        ud.set(config.osInfo, forKey: "tt_api_osInfo")
        ud.set(apiConfig.routeId, forKey: "tt_api_routeId")
        ud.set(config.authorizationKey, forKey: "tt_api_authorizationKey")
        ud.set(config.apiAuthKey, forKey: "tt_api_apiAuthKey")
        ud.set(config.apiAuthToken, forKey: "tt_api_apiAuthToken")

        if config.geofenceEnabled { GeofenceManager.shared.startMonitoringAll() }
    }

    /// Restore API config from UserDefaults (after app kill + relaunch).
    public static func restoreAPIConfigFromDefaults() {
        let ud = UserDefaults.standard
        var apiConfig = TripTrackerAPIConfig()
        apiConfig.pingURL = ud.string(forKey: "tt_api_pingURL") ?? ""
        apiConfig.endURL = ud.string(forKey: "tt_api_endURL") ?? ""
        apiConfig.userId = ud.string(forKey: "tt_api_userId") ?? ""
        apiConfig.vehicleId = ud.string(forKey: "tt_api_vehicleId") ?? ""
        let osInfo = ud.string(forKey: "tt_api_osInfo") ?? ""
        if !osInfo.isEmpty { apiConfig.osInfo = osInfo }
        apiConfig.routeId = ud.string(forKey: "tt_api_routeId") ?? ""
        apiConfig.authorizationKey = ud.string(forKey: "tt_api_authorizationKey") ?? ""
        apiConfig.apiAuthKey = ud.string(forKey: "tt_api_apiAuthKey") ?? ""
        apiConfig.apiAuthToken = ud.string(forKey: "tt_api_apiAuthToken") ?? ""
        TripTrackerAPIService.shared.config = apiConfig
        print("📡 TripTracker API config restored from UserDefaults — enabled=\(apiConfig.isConfigured) ping=\(apiConfig.pingURL)")
    }

    // ── Lifecycle ──
    public static func didEnterBackground() { LocationTrackingService.shared.ensureBackgroundTracking() }
    public static func willTerminate() { DatabaseManager.shared.saveContext() }

    // ── Scene Configuration ──
    public static func sceneConfiguration(for session: UISceneSession) -> UISceneConfiguration {
        if session.role == UISceneSession.Role(rawValue: "CPTemplateApplicationSceneSessionRoleApplication") {
            let c = UISceneConfiguration(name: "CarPlay Configuration", sessionRole: session.role)
            c.delegateClass = CarPlaySceneDelegate.self; return c
        }
        let c = UISceneConfiguration(name: "Default Configuration", sessionRole: session.role)
        c.delegateClass = SceneDelegate.self; return c
    }

    // ── Present Native Pages ──
    public static func presentMainView(from vc: UIViewController) { present(MainViewController(), from: vc) }
    public static func presentSettings(from vc: UIViewController) { present(SettingsViewController(), from: vc) }
    public static func presentNotificationSettings(from vc: UIViewController) { present(NotificationSettingsViewController(), from: vc) }
    public static func presentGeofenceManager(from vc: UIViewController) { present(GeofenceViewController(), from: vc) }
    public static func presentHistory(from vc: UIViewController) { present(HistoryViewController(), from: vc) }
    public static func presentDailyLocations(from vc: UIViewController) { present(DailyLocationsViewController(), from: vc) }
    private static func present(_ child: UIViewController, from vc: UIViewController) {
        let nav = UINavigationController(rootViewController: child); nav.modalPresentationStyle = .fullScreen
        vc.present(nav, animated: true)
    }

    // ── Data Access ──
    public static var isTracking: Bool { LocationTrackingService.shared.isTracking }
    public static var currentTripId: Int64 { LocationTrackingService.shared.currentTripId }
    public static func getCurrentStats() -> (speed: Float, distance: Double, duration: Int64, steps: Int) { LocationTrackingService.shared.getCurrentStats() }
    public static var lastKnownCoordinate: CLLocationCoordinate2D? { LocationTrackingService.shared.lastKnownCoordinate }

    // ── Web Monitor ──
    public static func startWebMonitor() { UserDefaults.standard.set(true, forKey: "tt_webMonitorEnabled"); if webServer == nil { webServer = LocationWebServer() }; webServer?.start() }
    public static func stopWebMonitor() { UserDefaults.standard.set(false, forKey: "tt_webMonitorEnabled"); webServer?.stop() }

    // ── Update vehicle_id at runtime ──
    public static func updateVehicleId(_ vehicleId: String) {
        TripTrackerAPIService.shared.updateVehicleId(vehicleId)
    }
}

// ═══════════════════════════════════════════════════════════════
// Permission Observer — auto-starts tracking when user grants permission
// ═══════════════════════════════════════════════════════════════

private class LocationPermissionDelegate: NSObject, CLLocationManagerDelegate {
    private let manager = CLLocationManager()

    override init() {
        super.init()
        manager.delegate = self
        // Request permission — iOS shows the system dialog
        manager.requestWhenInUseAuthorization()
    }

    public func locationManagerDidChangeAuthorization(_ manager: CLLocationManager) {
        let status = manager.authorizationStatus
        if status == .authorizedAlways || status == .authorizedWhenInUse {
            print("✅ TripTrackerLocation permission granted via delegate — auto-starting tracking")
            TripTrackerSDK.onPermissionGranted()
        }
    }
}
