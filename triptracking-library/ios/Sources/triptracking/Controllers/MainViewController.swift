//
//  MainViewController.swift
//  TripTracker
//
//  Main screen with map and controls
//

import UIKit
import MapKit
import CoreLocation

/// Tagged polyline so the renderer always draws it green regardless of tracking state

public class MainViewController: UIViewController {
    
    // MARK: - UI Components
    
    private let mapView: MKMapView = {
        let map = MKMapView()
        map.translatesAutoresizingMaskIntoConstraints = false
        // Hide all points of interest — keeps the map clean during tracking
        map.pointOfInterestFilter = .excludingAll
        // Defer showsUserLocation to viewDidAppear for faster initial render
        map.showsUserLocation = false
        return map
    }()
    
    private let sourceLabel: UILabel = {
        let label = UILabel()
        label.text = "Source: --"
        label.font = UIFont.systemFont(ofSize: 14, weight: .medium)
        label.textAlignment = .center
        label.translatesAutoresizingMaskIntoConstraints = false
        return label
    }()
    
    private let statsStackView: UIStackView = {
        let stack = UIStackView()
        stack.axis = .horizontal
        stack.distribution = .fillEqually
        stack.spacing = 10
        stack.translatesAutoresizingMaskIntoConstraints = false
        return stack
    }()
    
    private let distanceLabel = StatLabel(title: "Distance", value: "0 m")
    private let speedLabel = StatLabel(title: "Speed", value: "0.0 km/h")
    private let durationLabel = StatLabel(title: "Duration", value: "00:00")
    
    private let stepsLabel: UILabel = {
        let label = UILabel()
        label.text = "Steps: 0"
        label.font = UIFont.systemFont(ofSize: 14, weight: .medium)
        label.textAlignment = .center
        label.numberOfLines = 0 // Allow multiple lines if needed
        label.translatesAutoresizingMaskIntoConstraints = false
        return label
    }()
    
    private let movementLabel: UILabel = {
        let label = UILabel()
        label.text = "⏸️ Still · Sensor"
        label.font = UIFont.systemFont(ofSize: 14, weight: .medium)
        label.textAlignment = .center
        label.numberOfLines = 0 // Allow multiple lines if needed
        label.translatesAutoresizingMaskIntoConstraints = false
        return label
    }()
    
    private let accelerationLabel: UILabel = {
        let label = UILabel()
        label.text = "Acceleration: 0.00 m/s²"
        label.font = UIFont.systemFont(ofSize: 12)
        label.textAlignment = .center
        label.textColor = .gray
        label.numberOfLines = 0 // Allow multiple lines if needed
        label.translatesAutoresizingMaskIntoConstraints = false
        return label
    }()
    
    private let buttonStackView: UIStackView = {
        let stack = UIStackView()
        stack.axis = .vertical
        stack.spacing = 8
        stack.distribution = .fill
        stack.alignment = .fill
        stack.translatesAutoresizingMaskIntoConstraints = false
        return stack
    }()

    private let tripStatusLabel: UILabel = {
        let label = UILabel()
        label.text = "⏳ Waiting for vehicle speed (≥ 6 m/s) to auto-start trip"
        label.font = UIFont.systemFont(ofSize: 13, weight: .semibold)
        label.textAlignment = .center
        label.textColor = .systemPurple
        label.numberOfLines = 0
        label.translatesAutoresizingMaskIntoConstraints = false
        return label
    }()
    
    private let clearButton: UIButton = {
        let button = UIButton(type: .system)
        button.setTitle("CLEAR ROUTE", for: .normal)
        button.backgroundColor = UIColor.systemOrange
        button.setTitleColor(.white, for: .normal)
        button.titleLabel?.font = UIFont.systemFont(ofSize: 14, weight: .bold)
        button.layer.cornerRadius = 8
        button.translatesAutoresizingMaskIntoConstraints = false
        return button
    }()
    
    private let historyButton: UIButton = {
        let button = UIButton(type: .system)
        button.setTitle("📜 HISTORY", for: .normal)
        button.backgroundColor = UIColor.systemBlue
        button.setTitleColor(.white, for: .normal)
        button.titleLabel?.font = UIFont.systemFont(ofSize: 14, weight: .bold)
        button.layer.cornerRadius = 8
        button.translatesAutoresizingMaskIntoConstraints = false
        return button
    }()
    
    private let dailyLocationsButton: UIButton = {
        let button = UIButton(type: .system)
        button.setTitle("📅 DAILY LOCATIONS", for: .normal)
        button.backgroundColor = UIColor.systemTeal
        button.setTitleColor(.white, for: .normal)
        button.titleLabel?.font = UIFont.systemFont(ofSize: 14, weight: .bold)
        button.layer.cornerRadius = 8
        button.translatesAutoresizingMaskIntoConstraints = false
        return button
    }()
    
    // MARK: - Properties
    
    private var routePolyline: MKPolyline?
    private var routePoints: [CLLocationCoordinate2D] = []
    private var isRouteVisible: Bool = false   // false after clearRoute — suppresses redraw until next trip start
    private var startAnnotation: MKPointAnnotation?
    private var currentAnnotation: MKPointAnnotation?
    
    private var lastRouteLocation: CLLocation?
    private let maxAcceptableAccuracy: Float = 50.0
    private let minRouteDistance: Float = 10.0
    
    private var updateTimer: Timer?

    // MARK: - Fake route (debug / demo)
    private var fakePin: MKPointAnnotation?          // orange destination pin
    private var fakeRouteTimer: Timer?               // drives the animated walk
    private var fakeRouteSteps: [CLLocationCoordinate2D] = []
    private var fakeRouteStepIndex: Int = 0
    private var isTappingForFakePin: Bool = false    // true while waiting for map tap
    private var fakePinTimeoutTimer: Timer?          // auto-cancel after 10s if no tap
    
    // MARK: - Lifecycle
    
    public override func viewDidLoad() {
        super.viewDidLoad()
        overrideUserInterfaceStyle = .light
        
        title = "Trip Tracker"
        view.backgroundColor = .white
        
        // Configure navigation bar appearance
        configureNavigationBar()
        
        // Triple-tap cheat code to force end trip
        let tripleTap = UITapGestureRecognizer(target: self, action: #selector(titleTripleTapped))
        tripleTap.numberOfTapsRequired = 3
        
        if #available(iOS 26.0, *) {
            // iOS 26: use native title — Liquid Glass renders it correctly
            navigationItem.title = "Trip Tracker"
            navigationController?.navigationBar.addGestureRecognizer(tripleTap)
        } else {
            // iOS 14–25: custom label with adaptive color
            let titleLabel = UILabel()
            titleLabel.text = "Trip Tracker"
            titleLabel.font = UIFont.systemFont(ofSize: 18, weight: .semibold)
            titleLabel.textColor = .white
            titleLabel.isUserInteractionEnabled = true
            titleLabel.addGestureRecognizer(tripleTap)
            navigationItem.titleView = titleLabel
        }
        
        // Add current location button to navigation bar with SF Symbol
        let locationButton = UIBarButtonItem(
            image: UIImage(systemName: "location.fill"),
            style: .plain,
            target: self,
            action: #selector(currentLocationTapped)
        )

        // Debug: fake-route button (left side of nav bar)
        let fakeButton = UIBarButtonItem(
            image: UIImage(systemName: "map.fill"),
            style: .plain,
            target: self,
            action: #selector(fakeRouteTapped)
        )

        // Settings button
        let settingsButton = UIBarButtonItem(
            image: UIImage(systemName: "gearshape.fill"),
            style: .plain,
            target: self,
            action: #selector(settingsTapped)
        )
        navigationItem.rightBarButtonItems = [settingsButton, locationButton]

        navigationItem.leftBarButtonItems = [fakeButton]
        
        setupUI()
        setupActions()
        setupLocationService()
        setupUpdateTimer()

        // Request location permission
        requestLocationPermission()
        mapView.delegate = self
        mapView.showsBuildings = false
        mapView.showsTraffic = false
        MapAppearanceHelper.applyTimeBasedAppearance(to: mapView)

        // Set initial map region immediately so tiles start loading the right area
        // instead of loading the entire world first then zooming
        if let coord = LocationTrackingService.shared.lastKnownCoordinate {
            mapView.setRegion(MKCoordinateRegion(center: coord,
                latitudinalMeters: 1000, longitudinalMeters: 1000), animated: false)
        }

        // Sync trip status — trip may have been resumed after app kill
        let isTracking = LocationTrackingService.shared.isTracking
        updateButtonStates(isTracking: isTracking)
        updateTripStatusLabel()
        if isTracking {
            showToast(message: "♻️ Resumed tracking trip #\(LocationTrackingService.shared.currentTripId)")
        }
    }
    
    private func configureNavigationBar() {
        let appearance = UINavigationBarAppearance()
        appearance.configureWithOpaqueBackground()
        appearance.backgroundColor = UIColor(red: 0.45, green: 0.80, blue: 0.95, alpha: 1.0)
        appearance.titleTextAttributes = [
            .foregroundColor: UIColor.white,
            .font: UIFont.systemFont(ofSize: 18, weight: .semibold)
        ]
        navigationController?.navigationBar.standardAppearance = appearance
        navigationController?.navigationBar.scrollEdgeAppearance = appearance
        navigationController?.navigationBar.compactAppearance = appearance
        navigationController?.navigationBar.tintColor = .white

        navigationController?.navigationBar.prefersLargeTitles = false
        navigationItem.largeTitleDisplayMode = .never
    }
    
    @objc private func currentLocationTapped() {
        // Cancel any running fake route simulation and clear all markers/overlays
        if fakeRouteTimer != nil {
            cancelFakeRoute()
        }
        clearRoute()

        // Zoom to real GPS location from LocationTrackingService
        let svc = LocationTrackingService.shared

        if let coord = svc.lastKnownCoordinate ?? mapView.userLocation.location?.coordinate {
            let region = MKCoordinateRegion(
                center: coord,
                latitudinalMeters: 500,
                longitudinalMeters: 500
            )
            mapView.setRegion(region, animated: true)
            mapView.showsUserLocation = true
            showToast(message: "📍 Current location")
        } else {
            showToast(message: "📍 Getting your location...")
            DispatchQueue.main.asyncAfter(deadline: .now() + 1.0) { [weak self] in
                if let coord = svc.lastKnownCoordinate ?? self?.mapView.userLocation.location?.coordinate {
                    let region = MKCoordinateRegion(
                        center: coord,
                        latitudinalMeters: 500,
                        longitudinalMeters: 500
                    )
                    self?.mapView.setRegion(region, animated: true)
                    self?.mapView.showsUserLocation = true
                }
            }
        }
    }
    
    public override func viewDidAppear(_ animated: Bool) {
        super.viewDidAppear(animated)
        
        // Refresh map day/night based on current time
        MapAppearanceHelper.applyTimeBasedAppearance(to: mapView)
        
        // Zoom to current location when app opens
        zoomToCurrentLocation()
    }
    
    private func zoomToCurrentLocation() {
        // Enable user location (deferred from viewDidLoad for faster map init)
        mapView.showsUserLocation = true
        
        // Best source: MKMapView's own user location
        // Fallback: LocationTrackingService's last known coordinate
        let coord = mapView.userLocation.location?.coordinate
            ?? LocationTrackingService.shared.lastKnownCoordinate

        if let center = coord {
            let region = MKCoordinateRegion(
                center: center,
                latitudinalMeters: 1000,
                longitudinalMeters: 1000
            )
            mapView.setRegion(region, animated: true)
        } else {
            // If location not ready yet, retry after 1 second
            DispatchQueue.main.asyncAfter(deadline: .now() + 1.0) { [weak self] in
                let retryCoord = self?.mapView.userLocation.location?.coordinate
                    ?? LocationTrackingService.shared.lastKnownCoordinate
                if let center = retryCoord {
                    let region = MKCoordinateRegion(
                        center: center,
                        latitudinalMeters: 1000,
                        longitudinalMeters: 1000
                    )
                    self?.mapView.setRegion(region, animated: true)
                }
            }
        }
    }
    
    // MARK: - Setup
    
    private func setupUI() {
        view.backgroundColor = .white

        // ── Build sub-stacks ─────────────────────────────────────────────────

        // Stats: Distance | Speed | Duration
        statsStackView.addArrangedSubview(distanceLabel)
        statsStackView.addArrangedSubview(speedLabel)
        statsStackView.addArrangedSubview(durationLabel)

        // Info row: Steps | Movement  (side by side)
        let infoRow = UIStackView(arrangedSubviews: [stepsLabel, movementLabel])
        infoRow.axis = .horizontal
        infoRow.distribution = .fillEqually
        infoRow.spacing = 8
        infoRow.translatesAutoresizingMaskIntoConstraints = false

        // Button row: Clear | History
        let row1 = UIStackView(arrangedSubviews: [clearButton, historyButton])
        row1.axis = .horizontal
        row1.spacing = 8
        row1.distribution = .fillEqually

        // Main button stack
        buttonStackView.spacing = 8
        buttonStackView.addArrangedSubview(tripStatusLabel)
        buttonStackView.addArrangedSubview(row1)
        buttonStackView.addArrangedSubview(dailyLocationsButton)

        // ── Full-screen vertical stack ───────────────────────────────────────
        // One outer UIStackView fills safeArea top→bottom.
        // Map has no fixed height — it stretches to fill whatever space remains.

        let outerStack = UIStackView()
        outerStack.axis = .vertical
        outerStack.spacing = 0
        outerStack.translatesAutoresizingMaskIntoConstraints = false

        // Info panel: everything below the map
        let infoPanel = UIStackView()
        infoPanel.axis = .vertical
        infoPanel.spacing = 6
        infoPanel.isLayoutMarginsRelativeArrangement = true
        infoPanel.layoutMargins = UIEdgeInsets(top: 8, left: 16, bottom: 8, right: 16)
        infoPanel.addArrangedSubview(sourceLabel)
        infoPanel.addArrangedSubview(statsStackView)
        infoPanel.addArrangedSubview(infoRow)
        infoPanel.addArrangedSubview(accelerationLabel)
        infoPanel.addArrangedSubview(buttonStackView)

        // Map expands; infoPanel hugs its content
        outerStack.addArrangedSubview(mapView)
        outerStack.addArrangedSubview(infoPanel)

        // Map should stretch, infoPanel should not
        mapView.setContentHuggingPriority(.defaultLow, for: .vertical)
        mapView.setContentCompressionResistancePriority(.defaultLow, for: .vertical)
        infoPanel.setContentHuggingPriority(.required, for: .vertical)
        infoPanel.setContentCompressionResistancePriority(.required, for: .vertical)

        view.addSubview(outerStack)

        // ── Constraints ──────────────────────────────────────────────────────
        NSLayoutConstraint.activate([
            outerStack.topAnchor.constraint(equalTo: view.safeAreaLayoutGuide.topAnchor),
            outerStack.leadingAnchor.constraint(equalTo: view.leadingAnchor),
            outerStack.trailingAnchor.constraint(equalTo: view.trailingAnchor),
            outerStack.bottomAnchor.constraint(equalTo: view.safeAreaLayoutGuide.bottomAnchor),

            // Stats height
            statsStackView.heightAnchor.constraint(equalToConstant: 40),

            // Info row height
            infoRow.heightAnchor.constraint(equalToConstant: 20),

            // All buttons same height
            clearButton.heightAnchor.constraint(equalTo: view.heightAnchor, multiplier: 0.055),
            historyButton.heightAnchor.constraint(equalTo: view.heightAnchor, multiplier: 0.055),
            dailyLocationsButton.heightAnchor.constraint(equalTo: view.heightAnchor, multiplier: 0.055),
        ])
    }
    
    private func setupActions() {
        clearButton.addTarget(self, action: #selector(clearRouteTapped), for: .touchUpInside)
        historyButton.addTarget(self, action: #selector(historyTapped), for: .touchUpInside)
        dailyLocationsButton.addTarget(self, action: #selector(dailyLocationsTapped), for: .touchUpInside)
    }
    
    private func setupLocationService() {
        LocationTrackingService.shared.delegate = self
        LocationTrackingService.shared.autoTripDelegate = self
    }
    
    private func setupUpdateTimer() {
        updateTimer = Timer.scheduledTimer(withTimeInterval: 1.0, repeats: true) { [weak self] _ in
            self?.updateDurationLabel()
        }
    }
    
    private func requestLocationPermission() {
        let locationManager = CLLocationManager()
        
        switch locationManager.authorizationStatus {
        case .notDetermined:
            let alert = UIAlertController(
                title: "Location Permission",
                message: "TripTracker needs location permission to track your trips. Please allow 'Always' access for background tracking.",
                preferredStyle: .alert
            )
            alert.addAction(UIAlertAction(title: "OK", style: .default) { _ in
                locationManager.requestAlwaysAuthorization()
            })
            safePresent(alert)
        case .denied, .restricted:
            let alert = UIAlertController(
                title: "Permission Required",
                message: "Please enable location permission in Settings → TripTracker → Location → Always",
                preferredStyle: .alert
            )
            alert.addAction(UIAlertAction(title: "Open Settings", style: .default) { _ in
                if let url = URL(string: UIApplication.openSettingsURLString) {
                    UIApplication.shared.open(url)
                }
            })
            alert.addAction(UIAlertAction(title: "Cancel", style: .cancel))
            safePresent(alert)
        case .authorizedWhenInUse:
            locationManager.requestAlwaysAuthorization()
        case .authorizedAlways:
            break
        @unknown default:
            break
        }
    }
    
    // MARK: - Actions

    /// Cheat code: triple-tap the title "Trip Tracker" to force end the current trip.
    @objc private func titleTripleTapped() {
        let svc = LocationTrackingService.shared
        guard svc.isTracking else {
            showToast(message: "No active trip")
            return
        }

        let tripId = svc.currentTripId
        let stats = svc.getCurrentStats()

        // Confirm before ending
        let alert = UIAlertController(
            title: "⚡ Force End Trip",
            message: "End trip #\(tripId) now?\nDistance: \(stats.distance < 1000 ? String(format: "%.0f m", stats.distance) : String(format: "%.2f km", stats.distance / 1000))\nDuration: \(stats.duration / 60)m \(stats.duration % 60)s",
            preferredStyle: .alert
        )
        alert.addAction(UIAlertAction(title: "End Trip", style: .destructive) { [weak self] _ in
            guard let self = self else { return }
            self.cancelFakeRoute()
            svc.stopTrip()
            self.updateButtonStates(isTracking: false)
            self.updateTripStatusLabel()
            self.showToast(message: "⚡ Trip #\(tripId) force-ended")
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.5) {
                self.displayCompletedRoute(tripId: tripId)
                self.clearButton.isEnabled = true
                self.clearButton.alpha = 1.0
            }
        })
        alert.addAction(UIAlertAction(title: "Cancel", style: .cancel))
        safePresent(alert)
    }
    
    @objc private func clearRouteTapped() {
        cancelFakeRoute()
        clearRoute()
    }
    
    @objc private func historyTapped() {
        let historyVC = HistoryViewController()
        navigationController?.pushViewController(historyVC, animated: true)
    }
    
    @objc private func dailyLocationsTapped() {
        let dailyVC = DailyLocationsViewController()
        navigationController?.pushViewController(dailyVC, animated: true)
    }

    // MARK: - Trip Status Display

    /// Update the trip status label — called every second from the update timer.
    private func updateTripStatusLabel() {
        let svc = LocationTrackingService.shared

        if svc.isTracking, let stillSince = svc.stillSinceDate {
            // Trip active, device is still — show countdown
            let elapsed = Int(Date().timeIntervalSince(stillSince))
            let remaining = max(0, Int(svc.autoEndStillnessSecs) - elapsed)
            let remMins = remaining / 60
            let remSecs = remaining % 60
            tripStatusLabel.text = "🔴 Trip #\(svc.currentTripId) · Vehicle stopped · auto-stop in \(remMins)m \(remSecs)s"
            tripStatusLabel.textColor = .systemRed
        } else if svc.isTracking {
            // Trip active, device is moving
            let stats = svc.getCurrentStats()
            let distText = stats.distance < 1000
                ? String(format: "%.0f m", stats.distance)
                : String(format: "%.2f km", stats.distance / 1000)
            tripStatusLabel.text = "🟢 Trip #\(svc.currentTripId) active · \(distText)"
            tripStatusLabel.textColor = .systemGreen
        } else {
            // No trip — waiting for vehicle speed
            tripStatusLabel.text = "⏳ Waiting for vehicle speed (≥ \(String(format: "%.0f", svc.vehicleThreshold * 3.6)) km/h) to auto-start"
            tripStatusLabel.textColor = .systemPurple
        }
    }
    
    // MARK: - Fake Route (Debug / Demo)
    //
    // Tap 🗺️ in the nav bar to enter fake-route mode:
    //   1. An orange pin drops ~100 m ahead of current position.
    //   2. Drag the pin anywhere on the map to choose a destination.
    //   3. Tap 🗺️ again (or tap "Go" in the alert) to start the walk.
    //   The app injects one fake GPS point every 2 s, interpolating from
    //   current position to the pin in 15 steps.  Each point is fed through
    //   the normal didUpdateLocation path so the route draws and DB saves
    //   exactly as with real GPS — perfect for demo / QA without leaving your desk.

    // MARK: - Fake Route (Debug / Demo)
    //
    // Tap 🗺️ in the nav bar to enter fake-route mode:
    //   1. The map enters "tap to place" mode — a banner tells the user to tap anywhere.
    //   2. User taps the map → orange pin drops at the tapped coordinate.
    //   3. An alert confirms distance and asks "Go / Move pin / Cancel".
    //   4. On Go: 15 fake GPS points inject every 2 s from current position to the pin.
    //   Each point feeds through the normal didUpdateLocation path — route draws and
    //   DB saves exactly as real GPS. Perfect for demo / QA without leaving your desk.

    @objc private func settingsTapped() {
        let vc = SettingsViewController()
        let nav = UINavigationController(rootViewController: vc)
        nav.modalPresentationStyle = .formSheet
        safePresent(nav)
    }

    @objc private func fakeRouteTapped() {
        // Cancel any running simulation
        if fakeRouteTimer != nil {
            cancelFakeRoute()
            clearRoute()
            showToast(message: "🛑 Fake route cancelled")
            return
        }

        // Verify we have an origin
        guard let origin = LocationTrackingService.shared.lastKnownCoordinate
                        ?? mapView.userLocation.location?.coordinate else {
            showAlert(title: "No Location", message: "Cannot determine current position. Start tracking first.")
            return
        }

        // If pin already placed → go straight to confirm
        if let pin = fakePin {
            confirmAndStartFakeRoute(from: origin, to: pin.coordinate)
            return
        }

        // Enter tap-to-place mode
        isTappingForFakePin = true

        // Add a UITapGestureRecognizer to the map for a single tap
        let tap = UITapGestureRecognizer(target: self, action: #selector(mapTappedForFakePin(_:)))
        tap.numberOfTapsRequired = 1
        // Let existing map gestures (pan/zoom) coexist — only intercept single taps
        mapView.gestureRecognizers?.forEach { tap.require(toFail: $0) }
        tap.name = "FakePinTap"
        mapView.addGestureRecognizer(tap)

        // Zoom out to city scale so user can pick any spot
        let region = MKCoordinateRegion(
            center: mapView.userLocation.coordinate.latitude != 0
                ? mapView.userLocation.coordinate : origin,
            latitudinalMeters: 22_000, longitudinalMeters: 22_000
        )
        mapView.setRegion(region, animated: true)

        showToast(message: "👆 Tap anywhere on the map within 10s")

        // Auto-cancel if user doesn't tap within 10 seconds
        fakePinTimeoutTimer?.invalidate()
        fakePinTimeoutTimer = Timer.scheduledTimer(withTimeInterval: 10.0, repeats: false) { [weak self] _ in
            guard let self = self, self.isTappingForFakePin else { return }
            self.cancelFakeRoute()
            self.showToast(message: "⏱️ Fake route cancelled — no tap within 10s")
            print("🧪 Fake pin timeout — cancelled")
        }
    }

    @objc private func mapTappedForFakePin(_ gesture: UITapGestureRecognizer) {
        guard isTappingForFakePin else { return }

        // User tapped in time — cancel the timeout
        fakePinTimeoutTimer?.invalidate()
        fakePinTimeoutTimer = nil

        // Remove this one-shot gesture recognizer
        mapView.removeGestureRecognizer(gesture)
        isTappingForFakePin = false

        // Convert tap point → map coordinate
        let point  = gesture.location(in: mapView)
        let coord  = mapView.convert(point, toCoordinateFrom: mapView)

        // Remove old pin if any
        if let old = fakePin { mapView.removeAnnotation(old) }

        // Place orange pin at tapped location
        let pin = MKPointAnnotation()
        pin.coordinate = coord
        pin.title      = "🧪 Fake Destination"
        pin.subtitle   = "Tap 🗺️ to start"
        mapView.addAnnotation(pin)
        fakePin = pin

        // Ask the user to confirm or re-tap
        guard let origin = LocationTrackingService.shared.lastKnownCoordinate
                        ?? mapView.userLocation.location?.coordinate else { return }
        confirmAndStartFakeRoute(from: origin, to: coord)
    }

    private func confirmAndStartFakeRoute(from origin: CLLocationCoordinate2D,
                                          to dest: CLLocationCoordinate2D) {
        let distM = Int(CLLocation(latitude: origin.latitude,  longitude: origin.longitude)
                            .distance(from: CLLocation(latitude: dest.latitude, longitude: dest.longitude)))
        let distText = distM >= 1000
            ? String(format: "%.1f km", Double(distM) / 1000)
            : "\(distM) m"

        let alert = UIAlertController(
            title: "🧪 Fake Route",
            message: "Simulate driving \(distText) to the pinned location at 10 m/s (36 km/h) following real roads.",
            preferredStyle: .alert
        )
        alert.addAction(UIAlertAction(title: "Go 🚶", style: .default) { [weak self] _ in
            self?.startFakeRoute(from: origin, to: dest)
        })
        alert.addAction(UIAlertAction(title: "Move Pin 📍", style: .default) { [weak self] _ in
            guard let self = self else { return }
            // Remove current pin and re-enter tap mode
            if let pin = self.fakePin { self.mapView.removeAnnotation(pin) }
            self.fakePin = nil
            self.fakeRouteTapped()
        })
        alert.addAction(UIAlertAction(title: "Cancel", style: .cancel) { [weak self] _ in
            self?.cancelFakeRoute()
        })
        safePresent(alert)
    }

    // Vehicle speed for fake route simulation.
    // Must be clearly above vehicleThreshold (6 m/s) so GPS mode always triggers.
    // 10 m/s = 36 km/h — typical city driving speed, no risk of falling back to Sensors.
    private let fakeRouteSpeedMs: Double = 10.0     // 10 m/s = 36 km/h
    private let fakeRouteInterval: TimeInterval = 1.0  // inject one point every 1 s (smoother animation)

    private func startFakeRoute(from origin: CLLocationCoordinate2D,
                                to dest: CLLocationCoordinate2D) {
        showToast(message: "🗺️ Fetching road route...")
        clearButton.isEnabled = false
        LocationTrackingService.shared.isFakeRouteActive = true

        // Ask Apple Maps for a real driving route so the simulation follows roads.
        let req = MKDirections.Request()
        req.source             = MKMapItem(placemark: MKPlacemark(coordinate: origin))
        req.destination        = MKMapItem(placemark: MKPlacemark(coordinate: dest))
        req.transportType      = RouteTransportType.currentMKType
        req.requestsAlternateRoutes = false

        MKDirections(request: req).calculate { [weak self] response, error in
            guard let self = self else { return }

            DispatchQueue.main.async {
                let roadCoords: [CLLocationCoordinate2D]

                if let route = response?.routes.first {
                    // Extract every polyline vertex — these are road-snapped coordinates
                    // from Apple Maps and will never cut through buildings or houses.
                    let pts = route.polyline.points()
                    roadCoords = (0..<route.polyline.pointCount).map { pts[$0].coordinate }
                    print("🗺️ Road route: \(roadCoords.count) waypoints, \(Int(route.distance))m, \(Int(route.expectedTravelTime))s")
                } else {
                    // MKDirections failed (no network, pedestrian-only area, etc.)
                    // Fall back to straight line — user is warned via toast.
                    print("⚠️ MKDirections failed: \(error?.localizedDescription ?? "unknown") — using straight line")
                    self.showToast(message: "⚠️ No road route found — using straight line")
                    roadCoords = [origin, dest]
                }

                // Densify the road geometry so each timer tick (1 s) advances
                // the vehicle by exactly fakeRouteSpeedMs metres (10 m) along
                // the real road — never teleporting across intersections.
                let stepDistM = self.fakeRouteSpeedMs * self.fakeRouteInterval  // 10 m per tick
                self.fakeRouteSteps = self.densifyPolyline(roadCoords, stepMetres: stepDistM)
                self.fakeRouteStepIndex = 0

                let totalDist = self.totalPolylineLength(roadCoords)
                let estSecs   = Int(totalDist / self.fakeRouteSpeedMs)
                let estMins   = estSecs / 60
                let estSecsR  = estSecs % 60

                self.isRouteVisible = true
                let etaStr = estMins > 0
                    ? "\(estMins)m \(estSecsR)s"
                    : "\(estSecsR)s"
                self.showToast(message: "🧪 Fake drive started — \(self.fakeRouteSteps.count) pts · \(Int(self.fakeRouteSpeedMs * 3.6)) km/h · ETA \(etaStr)")

                self.fakeRouteTimer = Timer.scheduledTimer(
                    withTimeInterval: self.fakeRouteInterval, repeats: true) { [weak self] _ in
                    self?.injectNextFakePoint()
                }
                self.injectNextFakePoint()
            }
        }
    }

    /// Total length of a polyline in metres (used for ETA estimate).
    private func totalPolylineLength(_ coords: [CLLocationCoordinate2D]) -> Double {
        guard coords.count >= 2 else { return 0 }
        var total = 0.0
        for i in 1..<coords.count {
            total += CLLocation(latitude: coords[i-1].latitude, longitude: coords[i-1].longitude)
                        .distance(from: CLLocation(latitude: coords[i].latitude, longitude: coords[i].longitude))
        }
        return total
    }

    private func injectNextFakePoint() {
        guard fakeRouteStepIndex < fakeRouteSteps.count else {
            finishFakeRoute()
            return
        }

        let coord = fakeRouteSteps[fakeRouteStepIndex]
        fakeRouteStepIndex += 1

        // Compute heading from previous step so the CLLocation course is correct.
        let bearing: Double
        if fakeRouteStepIndex >= 2 {
            let prev = fakeRouteSteps[fakeRouteStepIndex - 2]
            let dLon = (coord.longitude - prev.longitude) * .pi / 180
            let lat1 = prev.latitude  * .pi / 180
            let lat2 = coord.latitude * .pi / 180
            let y = sin(dLon) * cos(lat2)
            let x = cos(lat1) * sin(lat2) - sin(lat1) * cos(lat2) * cos(dLon)
            bearing = (atan2(y, x) * 180 / .pi + 360).truncatingRemainder(dividingBy: 360)
        } else {
            bearing = 0
        }

        // Inject through the full LocationTrackingService GPS pipeline.
        // speed = 10 m/s → clearly above vehicleThreshold (6 m/s) → GPS mode guaranteed.
        LocationTrackingService.shared.injectFakeGPS(
            coordinate: coord,
            speed: fakeRouteSpeedMs,
            course: bearing
        )

        let remaining = fakeRouteSteps.count - fakeRouteStepIndex
        if remaining % 10 == 0 || remaining < 5 {
            print("🧪 Fake GPS \(fakeRouteStepIndex)/\(fakeRouteSteps.count) — (\(String(format:"%.6f", coord.latitude)), \(String(format:"%.6f", coord.longitude))) — \(remaining) remaining")
        }
    }

    private func finishFakeRoute() {
        clearButton.isEnabled = true
        fakeRouteTimer?.invalidate()
        fakeRouteTimer = nil
        LocationTrackingService.shared.isFakeRouteActive = false

        // Remove orange destination pin
        if let pin = fakePin {
            mapView.removeAnnotation(pin)
            fakePin = nil
        }

        showToast(message: "✅ Fake route complete!")
        print("🧪 Fake route finished")

        // Zoom back to real current location
        zoomToRealLocation()
    }

    private func cancelFakeRoute() {
        fakeRouteTimer?.invalidate()
        fakeRouteTimer = nil
        fakePinTimeoutTimer?.invalidate()
        fakePinTimeoutTimer = nil
        LocationTrackingService.shared.isFakeRouteActive = false
        fakeRouteSteps.removeAll()
        fakeRouteStepIndex = 0
        isTappingForFakePin = false
        // Remove the one-shot tap gesture if still attached
        mapView.gestureRecognizers?
            .filter { $0.name == "FakePinTap" }
            .forEach { mapView.removeGestureRecognizer($0) }
        if let pin = fakePin {
            mapView.removeAnnotation(pin)
            fakePin = nil
        }

        // Zoom back to real current location
        zoomToRealLocation()
    }

    /// Zoom map to the real GPS location after fake route ends/cancels.
    private func zoomToRealLocation() {
        let coord = LocationTrackingService.shared.lastKnownCoordinate
            ?? mapView.userLocation.location?.coordinate
        guard let center = coord else { return }
        let region = MKCoordinateRegion(
            center: center,
            latitudinalMeters: 500,
            longitudinalMeters: 500
        )
        mapView.setRegion(region, animated: true)
        mapView.showsUserLocation = true
    }

    // MARK: - Fake Route Geometry Helpers

    /// Resample a polyline (array of road coords) into evenly-spaced points
    /// separated by `stepMetres` metres. This ensures each timer tick advances
    /// the simulated vehicle by exactly speed × interval along the real road.
    private func densifyPolyline(_ coords: [CLLocationCoordinate2D],
                                 stepMetres: Double) -> [CLLocationCoordinate2D] {
        guard coords.count >= 2, stepMetres > 0 else { return coords }

        var result: [CLLocationCoordinate2D] = []
        var remaining = 0.0          // leftover metres from previous segment
        var prev = coords[0]

        for i in 1..<coords.count {
            let next = coords[i]
            let segLen = CLLocation(latitude: prev.latitude, longitude: prev.longitude)
                .distance(from: CLLocation(latitude: next.latitude, longitude: next.longitude))
            guard segLen > 0 else { continue }

            var walked = remaining   // start where we left off in this segment
            while walked < segLen {
                let t = walked / segLen
                let pt = CLLocationCoordinate2D(
                    latitude:  prev.latitude  + (next.latitude  - prev.latitude)  * t,
                    longitude: prev.longitude + (next.longitude - prev.longitude) * t
                )
                result.append(pt)
                walked += stepMetres
            }
            remaining = walked - segLen   // carry leftover into next segment
            prev = next
        }

        // Always include the final destination
        if let last = coords.last {
            result.append(last)
        }
        return result
    }



    // MARK: - Helper Methods
    
    private func updateButtonStates(isTracking: Bool) {
        // Disable Clear Route during active trip, enable when stopped and has content
        let hasMapContent = !mapView.overlays.isEmpty
            || mapView.annotations.contains(where: { !($0 is MKUserLocation) })
        clearButton.isEnabled = !isTracking && (hasMapContent || !routePoints.isEmpty)
        clearButton.alpha = clearButton.isEnabled ? 1.0 : 0.5
    }
    
    private func clearRoute() {
        // Stop accepting new route points / annotations until next trip starts
        isRouteVisible = false

        // Remove all overlays (route polylines, fake route lines, etc.)
        mapView.removeOverlays(mapView.overlays)
        routePolyline = nil

        // Remove all annotations except the user's blue current-location dot
        let stale = mapView.annotations.filter { !($0 is MKUserLocation) }
        mapView.removeAnnotations(stale)
        startAnnotation   = nil
        currentAnnotation = nil

        // Clear buffered route points
        routePoints.removeAll()
        lastRouteLocation = nil

        // Reset stats
        distanceLabel.setValue("0 m")
        speedLabel.setValue("0.0 km/h")
        durationLabel.setValue("00:00")
        stepsLabel.text = "Steps: 0"
        movementLabel.text = "⏸️ Still · Sensor"
        movementLabel.textColor = .systemOrange
        accelerationLabel.text = "Acceleration: 0.00 m/s²"
    }
    
    private func displayCompletedRoute(tripId: Int64) {
        let locations = DatabaseManager.shared.getLocationsForTrip(tripId: tripId)

        guard !locations.isEmpty else {
            showToast(message: "⚠️ No route data to display")
            return
        }

        // ── GPS + Sensor fusion pipeline ──────────────────────────────────
        let segments = RouteDrawingAlgorithm.buildSegments(from: locations)

        guard !segments.isEmpty else {
            showToast(message: "⚠️ Not enough accurate points to draw route")
            return
        }

        // Clear live-tracking overlays and annotations
        mapView.removeOverlays(mapView.overlays)
        mapView.removeAnnotations(mapView.annotations.filter { !($0 is MKUserLocation) })
        routePolyline     = nil
        currentAnnotation = nil
        startAnnotation   = nil
        routePoints.removeAll()

        // Add colour-coded segments  (🔵 blue = GPS/vehicle · 🟢 green = Sensor/slow)
        for seg in segments { mapView.addOverlay(seg.polyline, level: .aboveRoads) }
        routePolyline = segments.first?.polyline   // reference so Clear Route works

        // Start marker
        if let firstCoord = segments.first?.polyline.points().pointee.coordinate {
            let startPin        = MKPointAnnotation()
            startPin.coordinate = firstCoord
            startPin.title      = "Start"
            startPin.subtitle   = locations.first.map { $0.formattedTime } ?? ""
            mapView.addAnnotation(startPin)
            startAnnotation = startPin
        }

        // End marker
        if let lastSeg = segments.last {
            let raw      = lastSeg.polyline.points().advanced(by: lastSeg.polyline.pointCount - 1)
            let endPin   = MKPointAnnotation()
            endPin.coordinate = raw.pointee.coordinate
            endPin.title      = "End"
            endPin.subtitle   = locations.last.map { $0.formattedTime } ?? ""
            mapView.addAnnotation(endPin)
        }

        // Fit map to all segments with 15% padding
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.1) { [weak self] in
            guard let self = self else { return }
            let rects  = segments.map { $0.polyline.boundingMapRect }
            let union  = rects.dropFirst().reduce(rects[0]) { $0.union($1) }
            let padded = union.insetBy(dx: -union.size.width * 0.15,
                                       dy: -union.size.height * 0.15)
            self.mapView.setVisibleMapRect(padded, animated: true)
        }

        let processed = RouteDrawingAlgorithm.process(locations).count
        showToast(message: "✅ Route drawn: \(processed) / \(locations.count) points")
    }
    
    private func updateDurationLabel() {
        let svc = LocationTrackingService.shared
        let stats = svc.getCurrentStats()
        
        let minutes = stats.duration / 60
        let seconds = stats.duration % 60
        durationLabel.setValue(String(format: "%02d:%02d", minutes, seconds))

        // ── Sync speed + movement labels every second ──
        // When GPS goes silent, effectiveSpeed() decays to 0 but the delegate
        // doesn't fire — so the UI would show stale speed. Fix: refresh here.
        // When auto-end timer is counting (device still), force speed = 0.
        let displaySpeed: Float
        if svc.stillSinceDate != nil {
            // Auto-end countdown active → device is still → speed = 0
            displaySpeed = 0
        } else {
            displaySpeed = stats.speed
        }

        let kmh = displaySpeed * 3.6
        speedLabel.setValue(String(format: "%.1f km/h", kmh))

        // Movement label (3-tier)
        let vt = svc.vehicleThreshold
        if displaySpeed < 0.5 {
            movementLabel.text = "⏸️ Still · Sensor"
            movementLabel.textColor = .systemOrange
        } else if displaySpeed < vt {
            movementLabel.text = "🚶 Walking · Sensor"
            movementLabel.textColor = .systemGreen
        } else {
            movementLabel.text = "🚗 Vehicle · GPS"
            movementLabel.textColor = .systemBlue
        }

        // Update auto-trip status / countdown
        updateTripStatusLabel()
    }
    
    private func showToast(message: String) {
        // Use a UILabel overlay — never conflicts with presented alert controllers
        let toast = UILabel()
        toast.text = message
        toast.textColor = .white
        toast.backgroundColor = UIColor.black.withAlphaComponent(0.8)
        toast.textAlignment = .center
        toast.font = .systemFont(ofSize: 14, weight: .medium)
        toast.numberOfLines = 0
        toast.layer.cornerRadius = 10
        toast.clipsToBounds = true
        toast.translatesAutoresizingMaskIntoConstraints = false
        view.addSubview(toast)
        NSLayoutConstraint.activate([
            toast.centerXAnchor.constraint(equalTo: view.centerXAnchor),
            toast.bottomAnchor.constraint(equalTo: view.safeAreaLayoutGuide.bottomAnchor, constant: -20),
            toast.leadingAnchor.constraint(greaterThanOrEqualTo: view.leadingAnchor, constant: 30),
            toast.trailingAnchor.constraint(lessThanOrEqualTo: view.trailingAnchor, constant: -30),
            toast.heightAnchor.constraint(greaterThanOrEqualToConstant: 40),
        ])
        toast.alpha = 0
        UIView.animate(withDuration: 0.25, animations: { toast.alpha = 1 }) { _ in
            UIView.animate(withDuration: 0.3, delay: 1.5, animations: { toast.alpha = 0 }) { _ in
                toast.removeFromSuperview()
            }
        }
    }
    
    private func showAlert(title: String, message: String) {
        let alert = UIAlertController(title: title, message: message, preferredStyle: .alert)
        alert.addAction(UIAlertAction(title: "OK", style: .default))
        safePresent(alert)
    }

    /// Present a view controller safely — dismisses any existing presented VC first.
    private func safePresent(_ vc: UIViewController, animated: Bool = true) {
        if presentedViewController != nil {
            dismiss(animated: false) { [weak self] in
                self?.present(vc, animated: animated)
            }
        } else {
            present(vc, animated: animated)
        }
    }
}

// MARK: - LocationUpdateDelegate

extension MainViewController: LocationUpdateDelegate {
    
    public func didUpdateLocation(_ location: LocationPoint, source: TrackingSource, totalDistance: Double) {
        DispatchQueue.main.async { [weak self] in
            guard let self = self else { return }

            // ── Source ──
            self.sourceLabel.text = "Source: \(source.displayName)"

            // ── Speed ──
            let kmh = location.speed * 3.6
            self.speedLabel.setValue(String(format: "%.1f km/h", kmh))

            // ── Distance ──
            if totalDistance < 1000 {
                self.distanceLabel.setValue(String(format: "%.0f m", totalDistance))
            } else {
                self.distanceLabel.setValue(String(format: "%.2f km", totalDistance / 1000))
            }

            // ── Acceleration (from motion manager) ──
            let accel = LocationTrackingService.shared.currentAccelerationMagnitude
            self.accelerationLabel.text = String(format: "Acceleration: %.2f m/s²", accel)

            // ── Movement label (3-tier state) ──
            let vt = LocationTrackingService.shared.vehicleThreshold
            if location.speed < 0.5 {
                self.movementLabel.text = "⏸️ Still · Sensor"
                self.movementLabel.textColor = .systemOrange
            } else if location.speed < vt {
                self.movementLabel.text = "🚶 Walking · Sensor"
                self.movementLabel.textColor = .systemGreen
            } else {
                self.movementLabel.text = "🚗 Vehicle · GPS"
                self.movementLabel.textColor = .systemBlue
            }

            // ── Steps ──
            let stats = LocationTrackingService.shared.getCurrentStats()
            self.stepsLabel.text = "Steps: \(stats.steps)"
            
            // Update map
            let coordinate = CLLocationCoordinate2D(latitude: location.latitude, longitude: location.longitude)
            let clLocation = location.toCLLocation()
            
            // Check if should add to route
            let isAccurateSource = source == .gps || source == .sensors
            let isAccurateReading = location.accuracy <= self.maxAcceptableAccuracy
            
            var hasMoved = true
            if let lastLoc = self.lastRouteLocation {
                let distance = Float(clLocation.distance(from: lastLoc))
                hasMoved = distance >= self.minRouteDistance
            }
            
            if isRouteVisible && isAccurateSource && isAccurateReading && hasMoved {
                self.routePoints.append(coordinate)
                self.lastRouteLocation = clLocation

                // ── Live route: redraw using fusion algorithm every update ──
                // Remove previous live overlays (keep annotations)
                self.mapView.removeOverlays(self.mapView.overlays)

                // Build a synthetic LocationPoint array from the live buffer
                // so RouteDrawingAlgorithm can apply outlier/DP/smooth passes.
                // routePoints are already accuracy+source filtered above,
                // so we wrap them as plain GPS/Sensor points for the algo.
                let livePoints: [LocationPoint] = self.routePoints.enumerated().map { idx, coord in
                    LocationPoint(
                        tripId:    nil,
                        latitude:  coord.latitude,
                        longitude: coord.longitude,
                        accuracy:  Float(location.accuracy),
                        speed:     location.speed,
                        timestamp: Int64(Date().timeIntervalSince1970 * 1000) - Int64((self.routePoints.count - idx) * 1000),
                        source:    source.rawValue
                    )
                }

                let segments = RouteDrawingAlgorithm.buildSegments(from: livePoints)
                if segments.isEmpty {
                    // Fallback: plain polyline while points are still few
                    let poly = MKPolyline(coordinates: self.routePoints, count: self.routePoints.count)
                    self.mapView.addOverlay(poly)
                    self.routePolyline = poly
                } else {
                    for seg in segments { self.mapView.addOverlay(seg.polyline, level: .aboveRoads) }
                    self.routePolyline = segments.first?.polyline
                }

                // Add start marker on first point
                if self.startAnnotation == nil {
                    let start = MKPointAnnotation()
                    start.coordinate = coordinate
                    start.title = "Start"
                    self.mapView.addAnnotation(start)
                    self.startAnnotation = start
                    let region = MKCoordinateRegion(center: coordinate,
                                                    latitudinalMeters: 500,
                                                    longitudinalMeters: 500)
                    self.mapView.setRegion(region, animated: true)
                }
            }
            
            // Update current position marker only while route is visible
            if self.isRouteVisible {
                if let current = self.currentAnnotation {
                    self.mapView.removeAnnotation(current)
                }
                let current = MKPointAnnotation()
                current.coordinate = coordinate
                current.title = "Current Position"
                self.mapView.addAnnotation(current)
                self.currentAnnotation = current
            }
        }
    }
    
    public func didUpdateStats(speed: Float, distance: Double, duration: Int64) {
        DispatchQueue.main.async { [weak self] in
            guard let self = self else { return }
            
            let kmh = speed * 3.6
            self.speedLabel.setValue(String(format: "%.1f km/h", kmh))
            
            let stats = LocationTrackingService.shared.getCurrentStats()
            self.stepsLabel.text = "Steps: \(stats.steps)"
            
            // Update movement state (3-tier)
            let vt = LocationTrackingService.shared.vehicleThreshold
            if speed < 0.5 {
                self.movementLabel.text = "⏸️ Still · Sensor"
                self.movementLabel.textColor = .systemOrange
            } else if speed < vt {
                self.movementLabel.text = "🚶 Walking · Sensor"
                self.movementLabel.textColor = .systemGreen
            } else {
                self.movementLabel.text = "🚗 Vehicle · GPS"
                self.movementLabel.textColor = .systemBlue
            }
        }
    }
    
    public func didChangeTrackingState(isTracking: Bool) {
        DispatchQueue.main.async { [weak self] in
            self?.updateButtonStates(isTracking: isTracking)
        }
    }
}

// MARK: - MKMapViewDelegate

extension MainViewController: MKMapViewDelegate {

    // MARK: Orange pin styling for fake destination
    public func mapView(_ mapView: MKMapView, viewFor annotation: MKAnnotation) -> MKAnnotationView? {
        guard let point = annotation as? MKPointAnnotation,
              point === fakePin else { return nil }

        let id = "FakeDestPin"
        let view = mapView.dequeueReusableAnnotationView(withIdentifier: id) as? MKMarkerAnnotationView
                ?? MKMarkerAnnotationView(annotation: annotation, reuseIdentifier: id)
        view.annotation      = annotation
        view.markerTintColor = .systemOrange
        view.glyphImage      = UIImage(systemName: "mappin.and.ellipse")
        view.isDraggable     = false
        view.canShowCallout  = true
        return view
    }
    
    public func mapView(_ mapView: MKMapView, rendererFor overlay: MKOverlay) -> MKOverlayRenderer {
        // RouteDrawingAlgorithm renders:
        //   GPSPolyline    → blue  (vehicle speed ≥ 6 m/s)
        //   SensorPolyline → green (slow / walking speed)
        if let r = RouteDrawingAlgorithm.renderer(for: overlay, lineWidth: 4.5) { return r }

        // Fallback: plain MKPolyline while live buffer is still small
        if let polyline = overlay as? MKPolyline {
            let renderer = MKPolylineRenderer(polyline: polyline)
            renderer.strokeColor = UIColor.systemBlue.withAlphaComponent(0.7)
            renderer.lineWidth   = 4
            renderer.lineCap     = .round
            renderer.lineJoin    = .round
            return renderer
        }
        return MKOverlayRenderer(overlay: overlay)
    }
}

// MARK: - AutoTripDelegate

extension MainViewController: AutoTripDelegate {

    public func autoTripDidStart(tripId: Int64) {
        DispatchQueue.main.async { [weak self] in
            guard let self = self else { return }

            // Clear previous route and enable drawing
            self.clearRoute()
            self.isRouteVisible = true

            // Update UI
            self.updateButtonStates(isTracking: true)
            self.updateTripStatusLabel()

            self.showToast(message: "🤖 Auto-started trip #\(tripId)")
            print("🤖 UI: Auto-trip #\(tripId) started")
        }
    }

    public func autoTripDidEnd(tripId: Int64, reason: String) {
        DispatchQueue.main.async { [weak self] in
            guard let self = self else { return }

            // Update UI
            self.updateButtonStates(isTracking: false)
            self.updateTripStatusLabel()

            self.showToast(message: "🤖 Auto-stopped trip #\(tripId)\n\(reason)")
            print("🤖 UI: Auto-trip #\(tripId) ended — \(reason)")

            // Display the completed route after a short delay,
            // then force-enable Clear Route button
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.5) {
                self.displayCompletedRoute(tripId: tripId)
                // Force enable — route is now drawn on the map
                self.clearButton.isEnabled = true
                self.clearButton.alpha = 1.0
            }
        }
    }
}

// MARK: - StatLabel

public class StatLabel: UIView {
    
    private let titleLabel: UILabel = {
        let label = UILabel()
        label.font = UIFont.systemFont(ofSize: 11)
        label.textColor = .gray
        label.textAlignment = .center
        label.translatesAutoresizingMaskIntoConstraints = false
        return label
    }()
    
    private let valueLabel: UILabel = {
        let label = UILabel()
        label.font = UIFont.systemFont(ofSize: 14, weight: .bold)
        label.textAlignment = .center
        label.translatesAutoresizingMaskIntoConstraints = false
        return label
    }()
    
    public init(title: String, value: String) {
        super.init(frame: .zero)
        
        titleLabel.text = title
        valueLabel.text = value
        
        addSubview(titleLabel)
        addSubview(valueLabel)
        
        NSLayoutConstraint.activate([
            titleLabel.topAnchor.constraint(equalTo: topAnchor),
            titleLabel.leadingAnchor.constraint(equalTo: leadingAnchor),
            titleLabel.trailingAnchor.constraint(equalTo: trailingAnchor),
            
            valueLabel.topAnchor.constraint(equalTo: titleLabel.bottomAnchor, constant: 4),
            valueLabel.leadingAnchor.constraint(equalTo: leadingAnchor),
            valueLabel.trailingAnchor.constraint(equalTo: trailingAnchor),
            valueLabel.bottomAnchor.constraint(equalTo: bottomAnchor)
        ])
    }
    
    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }
    
    public func setValue(_ value: String) {
        valueLabel.text = value
    }
}
