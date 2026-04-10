//
//  CarPlayDrivingTaskManager.swift
//  TripTracker
//
//  CarPlay UI for "Driving Task" entitlement (com.apple.developer.carplay-driving-task).
//  Uses CPTabBarTemplate with CPInformationTemplate + CPListTemplate.
//  No CPMapTemplate (that requires carplay-maps entitlement).
//
//  Shows:
//    Tab 1 — Trip Dashboard: speed, distance, duration, trip state
//    Tab 2 — Geofence Zones: list of zones with enter/exit status
//
//  All local push notifications and voice feedback work identically
//  to the Map version — they don't depend on the CarPlay template.
//

import UIKit
import CarPlay

class CarPlayDrivingTaskManager: NSObject {

    private let interfaceController: CPInterfaceController

    private var tabBarTemplate: CPTabBarTemplate?
    private var dashboardTemplate: CPInformationTemplate?
    private var geofenceListTemplate: CPListTemplate?
    private var updateTimer: Timer?

    init(interfaceController: CPInterfaceController) {
        self.interfaceController = interfaceController
        super.init()
    }

    // MARK: - Lifecycle

    func start() {
        // Tab 1: Trip Dashboard
        dashboardTemplate = buildDashboardTemplate()

        // Tab 2: Geofence Zones
        geofenceListTemplate = buildGeofenceListTemplate()

        // Tab Bar
        let tabBar = CPTabBarTemplate(templates: [dashboardTemplate!, geofenceListTemplate!])
        tabBarTemplate = tabBar

        interfaceController.setRootTemplate(tabBar, animated: true, completion: { _, _ in })

        // Periodic dashboard refresh (every 1 second)
        startUpdateTimer()

        // Observe all trip events for alerts
        let nc = NotificationCenter.default
        nc.addObserver(self, selector: #selector(handleTripStarted(_:)),
                       name: .tripAutoStarted, object: nil)
        nc.addObserver(self, selector: #selector(handleTripEnded(_:)),
                       name: .tripAutoEnded, object: nil)
        nc.addObserver(self, selector: #selector(handleVehicleStopped(_:)),
                       name: .tripVehicleStopped, object: nil)
        nc.addObserver(self, selector: #selector(handleDistanceMilestone(_:)),
                       name: .tripDistanceMilestone, object: nil)
        nc.addObserver(self, selector: #selector(handleGeofenceEntered(_:)),
                       name: .geofenceEntered, object: nil)
        nc.addObserver(self, selector: #selector(handleGeofenceExited(_:)),
                       name: .geofenceExited, object: nil)

        print("🚗 CarPlay Driving Task UI loaded")
    }

    func stop() {
        updateTimer?.invalidate()
        updateTimer = nil
        NotificationCenter.default.removeObserver(self)
        print("🚗 CarPlay Driving Task manager stopped")
    }

    // MARK: - Tab 1: Trip Dashboard

    private func buildDashboardTemplate() -> CPInformationTemplate {
        let items = buildDashboardItems()

        let template = CPInformationTemplate(
            title: "Trip Tracker",
            layout: .twoColumn,
            items: items,
            actions: []
        )
        template.tabTitle = "Dashboard"
        template.tabImage = UIImage(systemName: "gauge")
        return template
    }

    private func buildDashboardItems() -> [CPInformationItem] {
        let svc = LocationTrackingService.shared
        let isTracking = svc.isTracking

        let status = isTracking ? "🟢 Recording" : "⏳ Waiting"
        let speedKmh = svc.getCurrentStats().speed * 3.6

        var items = [
            CPInformationItem(title: "Status", detail: status),
            CPInformationItem(title: "Speed", detail: String(format: "%.0f km/h", speedKmh)),
        ]

        if isTracking {
            let stats = svc.getCurrentStats()
            let distText = stats.distance < 1000
                ? String(format: "%.0f m", stats.distance)
                : String(format: "%.1f km", stats.distance / 1000)
            let mins = stats.duration / 60
            let secs = stats.duration % 60

            items.append(contentsOf: [
                CPInformationItem(title: "Trip #", detail: "\(svc.currentTripId)"),
                CPInformationItem(title: "Distance", detail: distText),
                CPInformationItem(title: "Duration", detail: String(format: "%02d:%02d", mins, secs)),
            ])
        }

        return items
    }

    // MARK: - Tab 2: Geofence Zones

    private func buildGeofenceListTemplate() -> CPListTemplate {
        let zones = GeofenceManager.shared.zones
        var listItems: [CPListItem] = []

        if zones.isEmpty {
            let empty = CPListItem(text: "No geofence zones", detailText: "Add zones in Settings → Geofencing")
            listItems.append(empty)
        } else {
            for zone in zones {
                var flags: [String] = []
                if zone.notifyOnEnter { flags.append("Enter") }
                if zone.notifyOnExit  { flags.append("Exit") }
                if zone.autoStopOnEnter { flags.append("Auto-stop") }

                let item = CPListItem(
                    text: zone.name,
                    detailText: "\(Int(zone.radius))m · \(flags.joined(separator: ", "))"
                )
                listItems.append(item)
            }
        }

        let section = CPListSection(items: listItems)
        let template = CPListTemplate(title: "Geofence Zones", sections: [section])
        template.tabTitle = "Geofences"
        template.tabImage = UIImage(systemName: "mappin.circle")
        return template
    }

    // MARK: - Periodic Update

    private func startUpdateTimer() {
        updateTimer = Timer.scheduledTimer(withTimeInterval: 1.0, repeats: true) { [weak self] _ in
            self?.refreshDashboard()
        }
        if let timer = updateTimer {
            RunLoop.main.add(timer, forMode: .common)
        }
    }

    private func refreshDashboard() {
        guard let template = dashboardTemplate else { return }

        let items = buildDashboardItems()
        template.items = items
    }

    // MARK: - Event Handlers (CarPlay Alerts)

    @objc private func handleTripStarted(_ notification: Notification) {
        let tripId = notification.userInfo?["tripId"] as? Int64 ?? 0
        showAlert(title: "🚗 Trip Started", message: "Trip #\(tripId) — recording")
        refreshGeofenceList()
    }

    @objc private func handleTripEnded(_ notification: Notification) {
        let tripId   = notification.userInfo?["tripId"] as? Int64 ?? 0
        let distance = notification.userInfo?["distance"] as? Double ?? 0
        let duration = notification.userInfo?["duration"] as? Int64 ?? 0

        let distText = distance < 1000
            ? String(format: "%.0f m", distance)
            : String(format: "%.1f km", distance / 1000)
        let mins = duration / 60
        let secs = duration % 60

        showAlert(title: "🏁 Trip #\(tripId) Ended", message: "\(distText) · \(mins)m \(secs)s")
    }

    @objc private func handleVehicleStopped(_ notification: Notification) {
        let mins = notification.userInfo?["timeout"] as? Int ?? 10
        showAlert(title: "🛑 Vehicle Stopped", message: "Auto-stop in \(mins) min if no movement")
    }

    @objc private func handleDistanceMilestone(_ notification: Notification) {
        guard let km = notification.userInfo?["km"] as? Int else { return }
        showAlert(title: "📏 \(km) km Traveled", message: "Distance milestone reached")
    }

    @objc private func handleGeofenceEntered(_ notification: Notification) {
        let name = notification.userInfo?["zoneName"] as? String ?? "Zone"
        showAlert(title: "📍 Entered: \(name)", message: "You arrived at \(name)")
        refreshGeofenceList()
    }

    @objc private func handleGeofenceExited(_ notification: Notification) {
        let name = notification.userInfo?["zoneName"] as? String ?? "Zone"
        showAlert(title: "📍 Left: \(name)", message: "You left \(name)")
        refreshGeofenceList()
    }

    // MARK: - Refresh Geofence List

    private func refreshGeofenceList() {
        guard let oldTemplate = geofenceListTemplate,
              let tabBar = tabBarTemplate else { return }

        let newTemplate = buildGeofenceListTemplate()
        geofenceListTemplate = newTemplate

        // Update the tab bar's templates
        var templates = tabBar.templates
        if let idx = templates.firstIndex(where: { $0 === oldTemplate }) {
            templates[idx] = newTemplate
            tabBar.updateTemplates(templates)
        }
    }

    // MARK: - Alerts

    private func showAlert(title: String, message: String) {
        let ok = CPAlertAction(title: "OK", style: .default, handler: { _ in })
        let alert = CPAlertTemplate(titleVariants: [title], actions: [ok])
        interfaceController.presentTemplate(alert, animated: true, completion: { _, _ in })

        // Auto-dismiss after 5 seconds
        DispatchQueue.main.asyncAfter(deadline: .now() + 5.0) { [weak self] in
            self?.interfaceController.dismissTemplate(animated: true, completion: { _, _ in })
        }
        print("🚗 CarPlay DT alert: \(title)")
    }
}
