//
//  CarPlayMapManager.swift
//  TripTracker
//
//  Manages the CarPlay map interface:
//    - CPMapTemplate with MKMapView
//    - Live trip status bar (distance, duration, speed)
//    - Trip start/stop indicators
//    - Geofence enter/exit alerts
//    - Speed display
//
//  Works alongside the existing LocationTrackingService — reads state, doesn't control it.
//

import UIKit
import MapKit
import CarPlay

class CarPlayMapManager: NSObject {

    private let interfaceController: CPInterfaceController
    private let window: CPWindow

    private var mapTemplate: CPMapTemplate?
    private var mapViewController: CarPlayMapViewController?
    private var updateTimer: Timer?

    // Track state for alerts (prevent duplicate alerts)
    private var lastTripState: Bool = false
    private var lastAnnouncedTripId: Int64 = -1

    init(interfaceController: CPInterfaceController, window: CPWindow) {
        self.interfaceController = interfaceController
        self.window = window
        super.init()
    }

    // MARK: - Lifecycle

    func start() {
        // Create map view controller
        let mapVC = CarPlayMapViewController()
        mapViewController = mapVC
        window.rootViewController = mapVC

        // Create map template with buttons
        let template = CPMapTemplate()
        template.mapDelegate = self

        // Leading buttons: zoom controls
        let zoomIn = CPMapButton { [weak self] _ in
            self?.mapViewController?.zoomIn()
        }
        zoomIn.image = UIImage(systemName: "plus.magnifyingglass")

        let zoomOut = CPMapButton { [weak self] _ in
            self?.mapViewController?.zoomOut()
        }
        zoomOut.image = UIImage(systemName: "minus.magnifyingglass")

        template.mapButtons = [zoomIn, zoomOut]

        // Leading navigation bar: recenter button
        let recenterBtn = CPBarButton(title: "📍") { [weak self] _ in
            self?.mapViewController?.recenterOnUser()
        }

        // Trailing: trip info button
        let infoBtn = CPBarButton(title: "ℹ️") { [weak self] _ in
            self?.showTripInfo()
        }

        template.leadingNavigationBarButtons = [recenterBtn]
        template.trailingNavigationBarButtons = [infoBtn]

        mapTemplate = template
        interfaceController.setRootTemplate(template, animated: true, completion: { _, _ in })

        // Start periodic UI updates
        startUpdateTimer()

        // Observe all trip events for CarPlay alerts
        let nc = NotificationCenter.default
        nc.addObserver(self, selector: #selector(handleDistanceMilestone(_:)),
                       name: .tripDistanceMilestone, object: nil)
        nc.addObserver(self, selector: #selector(handleTripStarted(_:)),
                       name: .tripAutoStarted, object: nil)
        nc.addObserver(self, selector: #selector(handleTripEnded(_:)),
                       name: .tripAutoEnded, object: nil)
        nc.addObserver(self, selector: #selector(handleVehicleStopped(_:)),
                       name: .tripVehicleStopped, object: nil)
        nc.addObserver(self, selector: #selector(handleGeofenceEntered(_:)),
                       name: .geofenceEntered, object: nil)
        nc.addObserver(self, selector: #selector(handleGeofenceExited(_:)),
                       name: .geofenceExited, object: nil)

        // Sync initial state
        lastTripState = LocationTrackingService.shared.isTracking

        print("🚗 CarPlay map template loaded")
    }

    func stop() {
        updateTimer?.invalidate()
        updateTimer = nil
        NotificationCenter.default.removeObserver(self)
        mapViewController = nil
        print("🚗 CarPlay manager stopped")
    }

    // MARK: - Periodic Updates

    private func startUpdateTimer() {
        updateTimer = Timer.scheduledTimer(withTimeInterval: 1.0, repeats: true) { [weak self] _ in
            self?.updateDashboard()
        }
        if let timer = updateTimer {
            RunLoop.main.add(timer, forMode: .common)
        }
    }

    private func updateDashboard() {
        let svc = LocationTrackingService.shared
        let isTracking = svc.isTracking
        lastTripState = isTracking

        // Update map subtitle with trip info
        if isTracking {
            let stats = svc.getCurrentStats()
            let distText = stats.distance < 1000
                ? String(format: "%.0f m", stats.distance)
                : String(format: "%.1f km", stats.distance / 1000)
            let speedKmh = stats.speed * 3.6
            let mins = stats.duration / 60
            let secs = stats.duration % 60
            let durText = String(format: "%02d:%02d", mins, secs)

            // Update the map VC overlay
            mapViewController?.updateTripInfo(
                speed: String(format: "%.0f km/h", speedKmh),
                distance: distText,
                duration: durText,
                state: "🟢 Recording"
            )
        } else {
            mapViewController?.updateTripInfo(
                speed: String(format: "%.0f km/h", svc.getCurrentStats().speed * 3.6),
                distance: "--",
                duration: "--:--",
                state: "⏳ Waiting"
            )
        }

        // Update map position
        mapViewController?.updateUserLocation()
    }

    // MARK: - Distance Milestone

    @objc private func handleDistanceMilestone(_ notification: Notification) {
        guard let km = notification.userInfo?["km"] as? Int,
              let distance = notification.userInfo?["distance"] as? Double else { return }

        let distText = distance < 1000
            ? String(format: "%.0f m", distance)
            : String(format: "%.1f km", distance / 1000)

        showAlert(
            title: "📏 \(km) km Traveled",
            message: "Total distance: \(distText)"
        )
        print("🚗 CarPlay milestone alert: \(km) km")
    }

    // MARK: - Trip Start / End / Stop Handlers

    @objc private func handleTripStarted(_ notification: Notification) {
        let tripId = notification.userInfo?["tripId"] as? Int64 ?? 0
        showAlert(title: "🚗 Trip Started", message: "Trip #\(tripId) — recording")
        print("🚗 CarPlay trip-start alert: #\(tripId)")
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
        print("🚗 CarPlay trip-end alert: #\(tripId)")
    }

    @objc private func handleVehicleStopped(_ notification: Notification) {
        let mins = notification.userInfo?["timeout"] as? Int ?? 10
        showAlert(title: "🛑 Vehicle Stopped", message: "Auto-stop in \(mins) min if no movement")
        print("🚗 CarPlay vehicle-stopped alert")
    }

    // MARK: - Geofence Handlers

    @objc private func handleGeofenceEntered(_ notification: Notification) {
        let name = notification.userInfo?["zoneName"] as? String ?? "Zone"
        showAlert(title: "📍 Entered: \(name)", message: "You arrived at \(name)")
        print("🚗 CarPlay geofence-enter alert: \(name)")
    }

    @objc private func handleGeofenceExited(_ notification: Notification) {
        let name = notification.userInfo?["zoneName"] as? String ?? "Zone"
        showAlert(title: "📍 Left: \(name)", message: "You left \(name)")
        print("🚗 CarPlay geofence-exit alert: \(name)")
    }

    // MARK: - Alerts

    private func showAlert(title: String, message: String) {
        guard let template = mapTemplate else { return }

        let action = CPAlertAction(title: "OK", style: .default) { _ in
            template.dismissNavigationAlert(animated: true, completion: { _ in })
        }

        let alert = CPNavigationAlert(
            titleVariants: [title],
            subtitleVariants: [message],
            imageSet: nil,
            primaryAction: action,
            secondaryAction: nil,
            duration: 5.0
        )

        template.present(navigationAlert: alert, animated: true)
    }

    // MARK: - Trip Info Screen

    private func showTripInfo() {
        let svc = LocationTrackingService.shared
        let stats = svc.getCurrentStats()

        let distText = stats.distance < 1000
            ? String(format: "%.0f m", stats.distance)
            : String(format: "%.2f km", stats.distance / 1000)
        let speedText = String(format: "%.1f km/h", stats.speed * 3.6)
        let durMins = stats.duration / 60
        let durSecs = stats.duration % 60

        var items: [CPInformationItem] = [
            CPInformationItem(title: "Status", detail: svc.isTracking ? "Recording" : "Waiting"),
            CPInformationItem(title: "Speed", detail: speedText),
        ]

        if svc.isTracking {
            items.append(contentsOf: [
                CPInformationItem(title: "Trip ID", detail: "#\(svc.currentTripId)"),
                CPInformationItem(title: "Distance", detail: distText),
                CPInformationItem(title: "Duration", detail: "\(durMins)m \(durSecs)s"),
                CPInformationItem(title: "Steps", detail: "\(stats.steps)"),
            ])
        }

        // Geofence zones
        let zones = GeofenceManager.shared.zones
        if !zones.isEmpty {
            items.append(CPInformationItem(title: "Geofences", detail: "\(zones.count) zone(s)"))
        }

        let infoTemplate = CPInformationTemplate(
            title: "Trip Tracker",
            layout: .leading,
            items: items,
            actions: []
        )

        interfaceController.pushTemplate(infoTemplate, animated: true, completion: { _, _ in })
    }
}

// MARK: - CPMapTemplateDelegate

extension CarPlayMapManager: CPMapTemplateDelegate {

    func mapTemplate(_ mapTemplate: CPMapTemplate, panBeganWith direction: CPMapTemplate.PanDirection) {
        // User is panning the map
    }

    func mapTemplate(_ mapTemplate: CPMapTemplate, panEndedWith direction: CPMapTemplate.PanDirection) {
        // User stopped panning
    }

    func mapTemplate(_ mapTemplate: CPMapTemplate, panWith direction: CPMapTemplate.PanDirection) {
        mapViewController?.pan(direction: direction)
    }
}
