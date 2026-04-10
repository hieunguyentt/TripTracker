//
//  CarPlaySceneDelegate.swift
//  TripTracker
//
//  Handles CarPlay connection lifecycle.
//  Supports TWO modes (switch in Settings → CarPlay Mode):
//
//    1. "Driving Task" (default) — CPTabBarTemplate + CPInformationTemplate.
//       Entitlement: com.apple.developer.carplay-driving-task
//       Delegate method: didConnect interfaceController (NO window)
//
//    2. "Map" — CPMapTemplate with MKMapView.
//       Entitlement: com.apple.developer.carplay-maps
//       Delegate method: didConnect interfaceController TO window
//
//  Both modes receive the same local push notifications and voice feedback.
//

import UIKit
import CarPlay

class CarPlaySceneDelegate: UIResponder, CPTemplateApplicationSceneDelegate {

    var interfaceController: CPInterfaceController?
    var carWindow: CPWindow?

    private var mapManager: CarPlayMapManager?
    private var drivingTaskManager: CarPlayDrivingTaskManager?

    static let carPlayModeKey = "tt_carPlayMode"

    static var isMapMode: Bool {
        return UserDefaults.standard.string(forKey: carPlayModeKey) == "map"
    }

    // MARK: - Driving Task mode (NO window — for carplay-driving-task entitlement)
    //
    // This is the method iOS calls when the entitlement is carplay-driving-task.
    // It does NOT provide a CPWindow — only templates are allowed.

    func templateApplicationScene(_ templateApplicationScene: CPTemplateApplicationScene,
                                   didConnect interfaceController: CPInterfaceController) {
        print("🚗 CarPlay connected (Driving Task — no window)")
        self.interfaceController = interfaceController

        if CarPlaySceneDelegate.isMapMode {
            // Map mode requested but we're in driving-task entitlement — fall back to driving task
            print("🚗 ⚠️ Map mode requested but no CPWindow — using Driving Task mode")
        }

        drivingTaskManager = CarPlayDrivingTaskManager(interfaceController: interfaceController)
        drivingTaskManager?.start()
    }

    func templateApplicationScene(_ templateApplicationScene: CPTemplateApplicationScene,
                                   didDisconnect interfaceController: CPInterfaceController) {
        print("🚗 CarPlay disconnected (Driving Task)")
        cleanup()
    }

    // MARK: - Map mode (WITH window — for carplay-maps entitlement)
    //
    // This is the method iOS calls when the entitlement is carplay-maps.
    // It provides a CPWindow for rendering MKMapView.

    func templateApplicationScene(_ templateApplicationScene: CPTemplateApplicationScene,
                                   didConnect interfaceController: CPInterfaceController,
                                   to window: CPWindow) {
        print("🚗 CarPlay connected (Map — with window)")
        self.interfaceController = interfaceController
        self.carWindow = window

        if CarPlaySceneDelegate.isMapMode {
            print("🚗 Using Map mode (CPMapTemplate)")
            mapManager = CarPlayMapManager(interfaceController: interfaceController, window: window)
            mapManager?.start()
        } else {
            print("🚗 Driving Task mode selected — ignoring window")
            drivingTaskManager = CarPlayDrivingTaskManager(interfaceController: interfaceController)
            drivingTaskManager?.start()
        }
    }

    func templateApplicationScene(_ templateApplicationScene: CPTemplateApplicationScene,
                                   didDisconnect interfaceController: CPInterfaceController,
                                   from window: CPWindow) {
        print("🚗 CarPlay disconnected (Map)")
        cleanup()
    }

    // MARK: - Cleanup

    private func cleanup() {
        mapManager?.stop()
        mapManager = nil
        drivingTaskManager?.stop()
        drivingTaskManager = nil
        self.interfaceController = nil
        self.carWindow = nil
    }
}
