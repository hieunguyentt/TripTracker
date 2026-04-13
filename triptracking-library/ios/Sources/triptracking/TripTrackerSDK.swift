//
//  TripTrackerSDK.swift
//  TripTracker Library
//
//  Single entry point for the TripTracker library.
//  Host app calls these methods from their own AppDelegate / SceneDelegate.
//
//  ──────────────────────────────────────────────────────────────────────
//  QUICK START — Add these to YOUR AppDelegate:
//  ──────────────────────────────────────────────────────────────────────
//
//  import TripTracker   // or just include the source files
//
//  func application(_ app: UIApplication,
//      didFinishLaunchingWithOptions opts: [UIApplication.LaunchOptionsKey: Any]?) -> Bool {
//      TripTrackerSDK.initialize(launchOptions: opts)
//      return true
//  }
//
//  func applicationDidEnterBackground(_ app: UIApplication) {
//      TripTrackerSDK.didEnterBackground()
//  }
//
//  func applicationWillTerminate(_ app: UIApplication) {
//      TripTrackerSDK.willTerminate()
//  }
//
//  // CarPlay support (optional):
//  func application(_ app: UIApplication,
//      configurationForConnecting session: UISceneSession,
//      options: UIScene.ConnectionOptions) -> UISceneConfiguration {
//      return TripTrackerSDK.sceneConfiguration(for: session)
//  }
//  ──────────────────────────────────────────────────────────────────────

import UIKit
import CoreLocation

public final class TripTrackerSDK {

    /// Web server instance — kept alive by the SDK.
    public static var webServer: LocationWebServer?

    // MARK: - Initialization

    /// Call from `application(_:didFinishLaunchingWithOptions:)`.
    /// Sets up defaults, logging, database, GPS, geofencing, notifications, web server.
    public static func initialize(launchOptions: [UIApplication.LaunchOptionsKey: Any]? = nil) {

        // ── First-install defaults ──
        UserDefaults.standard.register(defaults: [
            "tt_voiceFeedbackEnabled": true,
            "tt_webMonitorEnabled":    false,
            "tt_saveIntervalSecs":     900.0,
            "tt_saveDistanceVehicleM": 30.0,
            "tt_autoEndStillnessSecs": 300.0,
            "tt_transportType":        0,
        ])

        // Start log capture FIRST
        LogManager.shared.start()

        // Detect location relaunch
        let isLocationRelaunch = launchOptions?[.location] != nil
        if isLocationRelaunch {
            print("🔄 App relaunched by iOS due to location event")
        }

        // Initialize database
        DatabaseManager.shared.initializeDatabase()

        // Start background location
        LocationTrackingService.shared.startBackgroundTracking()

        // Handle active trip from before app was killed
        if let info = DatabaseManager.shared.getActiveTripInfo() {
            let wasAutoEnded = LocationTrackingService.shared.checkAndAutoEndStaleTrip()
            if !wasAutoEnded {
                print("♻️ App relaunched — resuming trip ID=\(info.id)")
                LocationTrackingService.shared.resumeTrip(id: info.id, startTimeMs: info.startTimeMs)
            }
        } else if isLocationRelaunch {
            LocationTrackingService.shared.handleSignificantLocationRelaunch()
        }

        // Web server
        if UserDefaults.standard.bool(forKey: "tt_webMonitorEnabled") {
            webServer = LocationWebServer()
            webServer?.start()
        }

        // Notifications
        NotificationManager.shared.requestPermission()

        // Geofencing
        if GeofenceManager.shared.isEnabled {
            GeofenceManager.shared.startMonitoringAll()
        }

        print("✅ TripTrackerSDK initialized")
    }

    // MARK: - Lifecycle Hooks

    /// Call from `applicationDidEnterBackground`.
    public static func didEnterBackground() {
        LocationTrackingService.shared.ensureBackgroundTracking()
    }

    /// Call from `applicationWillTerminate`.
    public static func willTerminate() {
        DatabaseManager.shared.saveContext()
    }

    // MARK: - Scene Configuration (CarPlay)

    /// Call from `application(_:configurationForConnecting:options:)`.
    /// Returns the correct UISceneConfiguration for phone or CarPlay.
    public static func sceneConfiguration(for session: UISceneSession) -> UISceneConfiguration {
        if session.role == UISceneSession.Role(rawValue: "CPTemplateApplicationSceneSessionRoleApplication") {
            let config = UISceneConfiguration(name: "CarPlay Configuration", sessionRole: session.role)
            config.delegateClass = CarPlaySceneDelegate.self
            return config
        }
        let config = UISceneConfiguration(name: "Default Configuration", sessionRole: session.role)
        config.delegateClass = SceneDelegate.self
        return config
    }

    // MARK: - Present Native Pages

    /// Present the main TripTracker map view.
    public static func presentMainView(from vc: UIViewController) {
        let mainVC = MainViewController()
        let nav = UINavigationController(rootViewController: mainVC)
        nav.modalPresentationStyle = .fullScreen
        vc.present(nav, animated: true)
    }

    /// Present the Settings page.
    public static func presentSettings(from vc: UIViewController) {
        let settingsVC = SettingsViewController()
        let nav = UINavigationController(rootViewController: settingsVC)
        nav.modalPresentationStyle = .fullScreen
        vc.present(nav, animated: true)
    }

    /// Present the Notification Settings page (per-type push + voice).
    public static func presentNotificationSettings(from vc: UIViewController) {
        let notifVC = NotificationSettingsViewController()
        let nav = UINavigationController(rootViewController: notifVC)
        nav.modalPresentationStyle = .fullScreen
        vc.present(nav, animated: true)
    }

    /// Present the Geofence Manager page (map + zones).
    public static func presentGeofenceManager(from vc: UIViewController) {
        let geoVC = GeofenceViewController()
        let nav = UINavigationController(rootViewController: geoVC)
        nav.modalPresentationStyle = .fullScreen
        vc.present(nav, animated: true)
    }

    /// Present the Trip History page.
    public static func presentHistory(from vc: UIViewController) {
        let histVC = HistoryViewController()
        let nav = UINavigationController(rootViewController: histVC)
        nav.modalPresentationStyle = .fullScreen
        vc.present(nav, animated: true)
    }

    /// Present Daily Locations page.
    public static func presentDailyLocations(from vc: UIViewController) {
        let dailyVC = DailyLocationsViewController()
        let nav = UINavigationController(rootViewController: dailyVC)
        nav.modalPresentationStyle = .fullScreen
        vc.present(nav, animated: true)
    }

    // MARK: - Data Access (No UI)

    public static var isTracking: Bool { LocationTrackingService.shared.isTracking }
    public static var currentTripId: Int64 { LocationTrackingService.shared.currentTripId }

    public static func getCurrentStats() -> (speed: Float, distance: Double, duration: Int64, steps: Int) {
        LocationTrackingService.shared.getCurrentStats()
    }

    public static var lastKnownCoordinate: CLLocationCoordinate2D? {
        LocationTrackingService.shared.lastKnownCoordinate
    }

    // MARK: - Web Monitor Control

    public static func startWebMonitor() {
        UserDefaults.standard.set(true, forKey: "tt_webMonitorEnabled")
        if webServer == nil { webServer = LocationWebServer() }
        webServer?.start()
    }

    public static func stopWebMonitor() {
        UserDefaults.standard.set(false, forKey: "tt_webMonitorEnabled")
        webServer?.stop()
    }
}
