//
//  AppDelegate.swift
//  TripTracker
//
//  iOS Location Tracking Application
//  Created: 2026
//

import UIKit
import CoreLocation
import CarPlay

@main
class AppDelegate: UIResponder, UIApplicationDelegate {

    var window: UIWindow?
    var webServer: LocationWebServer?

    // MARK: - Scene Configuration (iOS 13+ / CarPlay)

    func application(_ application: UIApplication,
                     configurationForConnecting connectingSceneSession: UISceneSession,
                     options: UIScene.ConnectionOptions) -> UISceneConfiguration {

        if connectingSceneSession.role == UISceneSession.Role(rawValue: "CPTemplateApplicationSceneSessionRoleApplication") {
            // CarPlay scene
            let config = UISceneConfiguration(name: "CarPlay Configuration", sessionRole: connectingSceneSession.role)
            config.delegateClass = CarPlaySceneDelegate.self
            return config
        }

        // Default phone scene
        let config = UISceneConfiguration(name: "Default Configuration", sessionRole: connectingSceneSession.role)
        config.delegateClass = SceneDelegate.self
        return config
    }
    
    func application(_ application: UIApplication, didFinishLaunchingWithOptions launchOptions: [UIApplication.LaunchOptionsKey: Any]?) -> Bool {

        // ── First-install defaults ──────────────────────────────────────────
        // register(defaults:) only applies when no value has been explicitly saved.
        // Once the user changes a setting, the saved value takes precedence.
        UserDefaults.standard.register(defaults: [
            "tt_voiceFeedbackEnabled": true,       // Voice ON
            "tt_webMonitorEnabled":    false,       // Web Monitor OFF (save battery)
            "tt_saveIntervalSecs":     900.0,       // Still/slow save every 15 min
            "tt_saveDistanceVehicleM": 30.0,        // GPS save distance 30 m
            "tt_autoEndStillnessSecs": 300.0,       // Auto-stop timeout 5 min
            "tt_transportType":        0,           // 0=Car, 1=Moto, 2=Bike, 3=Walk
        ])

        // Start log capture FIRST — all subsequent print() goes to file
        LogManager.shared.start()
        
        // Detect if this is a relaunch from a location event (significant change / visit)
        let isLocationRelaunch = launchOptions?[.location] != nil
        if isLocationRelaunch {
            print("🔄 App relaunched by iOS due to location event")
        }

        // Initialize database
        DatabaseManager.shared.initializeDatabase()

        // Start background location updates (GPS + significant change + visits)
        LocationTrackingService.shared.startBackgroundTracking()

        // ── Handle active trip from before app was killed ──
        if let info = DatabaseManager.shared.getActiveTripInfo() {
            // First check: is the trip stale (no location for > autoEndStillnessSecs)?
            // If so, auto-end it immediately instead of resuming.
            let wasAutoEnded = LocationTrackingService.shared.checkAndAutoEndStaleTrip()

            if !wasAutoEnded {
                // Trip is still within timeout — resume it normally
                print("♻️ App relaunched — resuming trip ID=\(info.id)")
                LocationTrackingService.shared.resumeTrip(id: info.id, startTimeMs: info.startTimeMs)
            }
        } else if isLocationRelaunch {
            // No active trip, but relaunched by location event → check if we should auto-start
            LocationTrackingService.shared.handleSignificantLocationRelaunch()
        }
        
        // Start web server (if enabled — default ON, toggle in Settings to save battery)
        let webMonitorEnabled = UserDefaults.standard.bool(forKey: "tt_webMonitorEnabled")
        if webMonitorEnabled {
            webServer = LocationWebServer()
            webServer?.start()
        } else {
            print("🌐 Web Monitor disabled — skipping server start (battery saving)")
        }

        // Request notification permission + schedule daily 6 AM reminder
        NotificationManager.shared.requestPermission()

        // Start geofence monitoring if enabled
        if GeofenceManager.shared.isEnabled {
            GeofenceManager.shared.startMonitoringAll()
        }
        
        return true
    }
    
    func applicationDidEnterBackground(_ application: UIApplication) {
        // Ensure tracking continues in background
        LocationTrackingService.shared.ensureBackgroundTracking()
    }

    // iOS can relaunch a terminated app due to significant location change.
    // launchOptions will contain UIApplication.LaunchOptionsKey.location in that case.
    // startBackgroundTracking() + resumeTrip() above already handle this correctly.
    
    func applicationWillTerminate(_ application: UIApplication) {
        // Save any pending data
        DatabaseManager.shared.saveContext()
    }
}
