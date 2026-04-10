//
//  SettingsViewController.swift
//  TripTracker
//
//  Exposes runtime-tunable tracking constants via sliders.
//  Changes take effect immediately — no restart required.
//
//  Settings persisted in UserDefaults:
//    tt_vehicleThreshold      Float   (m/s)   default 6.0
//    tt_saveIntervalSecs      Double  (s)     default 900.0 (15 min)
//    tt_saveDistanceVehicleM  Double  (m)     default 30.0
//    tt_routeGapThresholdM    Double  (m)     default 500.0
//    tt_autoEndStillnessSecs  Double  (s)     default 300.0 (5 min)
//    tt_voiceFeedbackEnabled  Bool            default true
//    tt_webMonitorEnabled     Bool            default false
//

import UIKit

// Key used by the web-monitor HTML to pick up the route gap threshold.
// MainViewController reads this and injects it into the page via a JS override.
let kRouteGapThresholdKey = "tt_routeGapThresholdM"

class SettingsViewController: UIViewController {

    // MARK: - UserDefaults keys
    private enum Keys {
        static let vehicleThreshold     = "tt_vehicleThreshold"
        static let saveIntervalSecs     = "tt_saveIntervalSecs"
        static let saveDistanceVehicleM = "tt_saveDistanceVehicleM"
        static let routeGapThresholdM   = kRouteGapThresholdKey
    }

    // MARK: - Default values
    private enum Defaults {
        static let vehicleThreshold:     Float  = 6.0
        static let saveIntervalSecs:     Double = 900.0   // 15 min
        static let saveDistanceVehicleM: Double = 30.0
        static let routeGapThresholdM:   Double = 500.0
    }

    // MARK: - UI
    private let scrollView = UIScrollView()
    private let stackView: UIStackView = {
        let s = UIStackView()
        s.axis = .vertical
        s.spacing = 0
        s.translatesAutoresizingMaskIntoConstraints = false
        return s
    }()

    // Slider rows — stored so we can read values on save
    private var vehicleRow:     SettingRow!
    private var saveIntervalRow: SettingRow!
    private var saveDistanceRow: SettingRow!
    private var routeGapRow:    SettingRow!
    private var autoEndTimeoutRow: SettingRow!
    private var geofenceSwitch: UISwitch!
    private var webMonitorSwitch: UISwitch!
    private var carPlayModeSwitch: UISwitch!
    private var carPlayModeDescLabel: UILabel!
    private var notifDescLabel: UILabel!
    private var transportSegment: UISegmentedControl!
    
    /// Debounce timer for auto-saving slider changes after 5 seconds of inactivity.
    private var autoSaveTimer: Timer?

    // MARK: - Lifecycle

    override func viewDidLoad() {
        super.viewDidLoad()
        overrideUserInterfaceStyle = .light
        title = "Settings"
        view.backgroundColor = UIColor(red: 0.95, green: 0.95, blue: 0.97, alpha: 1.0)

        // Sky blue nav bar
        let appearance = UINavigationBarAppearance()
        appearance.configureWithOpaqueBackground()
        appearance.backgroundColor = UIColor(red: 0.45, green: 0.80, blue: 0.95, alpha: 1.0)
        appearance.titleTextAttributes = [.foregroundColor: UIColor.white, .font: UIFont.systemFont(ofSize: 18, weight: .semibold)]
        navigationController?.navigationBar.standardAppearance = appearance
        navigationController?.navigationBar.scrollEdgeAppearance = appearance
        navigationController?.navigationBar.compactAppearance = appearance
        navigationController?.navigationBar.tintColor = .white

        navigationItem.leftBarButtonItem = UIBarButtonItem(
            image: UIImage(systemName: "chevron.left"),
            style: .plain, target: self, action: #selector(closeTapped))
        navigationItem.rightBarButtonItem = UIBarButtonItem(
            title: "Reset", style: .plain, target: self, action: #selector(resetDefaults))
        navigationItem.rightBarButtonItem?.tintColor = .white

        // Only set up the scroll view shell — content built after animation
        setupScrollView()
    }

    override func viewWillAppear(_ animated: Bool) {
        super.viewWillAppear(animated)
        // Build UI rows only once, after the navigation push animation starts
        // This makes the page appear instantly instead of blocking on UI construction
        if stackView.arrangedSubviews.isEmpty {
            buildRows()
            loadCurrentValues()
        }
        // Refresh notification summary (user may have changed toggles)
        updateNotifSummary()
    }

    private func updateNotifSummary() {
        guard let label = notifDescLabel else { return }
        let enabledCount = [
            NotificationSettingsViewController.isTripStartEnabled,
            NotificationSettingsViewController.isTripEndEnabled,
            NotificationSettingsViewController.isDistanceKmEnabled,
            NotificationSettingsViewController.isGeofenceEnterEnabled,
            NotificationSettingsViewController.isGeofenceExitEnabled,
        ].filter { $0 }.count
        let voiceStatus = VoiceFeedbackManager.shared.isEnabled ? "ON" : "OFF"
        label.text = "Push: \(enabledCount)/5 enabled · Voice: \(voiceStatus)\nConfigure push notifications and voice announcements for trip events."
    }

    override func viewWillDisappear(_ animated: Bool) {
        super.viewWillDisappear(animated)
        // If user leaves Settings with pending slider changes, save immediately
        if autoSaveTimer != nil {
            applySettings()
        }
    }

    // MARK: - Layout

    private func setupScrollView() {
        scrollView.translatesAutoresizingMaskIntoConstraints = false
        view.addSubview(scrollView)
        scrollView.addSubview(stackView)
        NSLayoutConstraint.activate([
            scrollView.topAnchor.constraint(equalTo: view.safeAreaLayoutGuide.topAnchor),
            scrollView.leadingAnchor.constraint(equalTo: view.leadingAnchor),
            scrollView.trailingAnchor.constraint(equalTo: view.trailingAnchor),
            scrollView.bottomAnchor.constraint(equalTo: view.safeAreaLayoutGuide.bottomAnchor),
            stackView.topAnchor.constraint(equalTo: scrollView.topAnchor, constant: 20),
            stackView.leadingAnchor.constraint(equalTo: scrollView.leadingAnchor),
            stackView.trailingAnchor.constraint(equalTo: scrollView.trailingAnchor),
            stackView.bottomAnchor.constraint(equalTo: scrollView.bottomAnchor, constant: -20),
            stackView.widthAnchor.constraint(equalTo: scrollView.widthAnchor),
        ])
    }

    private func buildRows() {
        // ── Section: Tracking ────────────────────────────────────────────────
        stackView.addArrangedSubview(sectionHeader("📡  Tracking"))

        vehicleRow = SettingRow(
            title: "Vehicle Speed Threshold",
            subtitle: "Speed at which tracking switches from Sensors → GPS",
            unit: "m/s",
            min: 2.0, max: 20.0, step: 0.5,
            format: "%.1f"
        )
        stackView.addArrangedSubview(vehicleRow)
        stackView.addArrangedSubview(separator())

        saveDistanceRow = SettingRow(
            title: "GPS Save Distance",
            subtitle: "Save a GPS point every N metres at vehicle speed",
            unit: "m",
            min: 10.0, max: 200.0, step: 5.0,
            format: "%.0f"
        )
        stackView.addArrangedSubview(saveDistanceRow)
        stackView.addArrangedSubview(separator())

        saveIntervalRow = SettingRow(
            title: "Slow / Still Save Interval",
            subtitle: "How often to save when walking, stationary, or device on table",
            unit: "min",
            min: 0.5, max: 30.0, step: 0.5,
            format: "%.1f"
        )
        stackView.addArrangedSubview(saveIntervalRow)

        // ── Section: Web Monitor ─────────────────────────────────────────────
        stackView.addArrangedSubview(sectionHeader("🌐  Web Monitor Map"))

        routeGapRow = SettingRow(
            title: "Route Gap Threshold",
            subtitle: "Maximum distance between two points to draw a connecting line.\nSmaller = stricter (more gaps), Larger = more connected.",
            unit: "m",
            min: 50.0, max: 5000.0, step: 50.0,
            format: "%.0f"
        )
        stackView.addArrangedSubview(routeGapRow)

        // ── Route Transport Type ───────────────────────────────────────────
        let transportRow = UIView()
        transportRow.backgroundColor = .secondarySystemGroupedBackground

        let transportLabel = UILabel()
        transportLabel.text = "Route Drawing Mode"
        transportLabel.font = .systemFont(ofSize: 16, weight: .medium)
        transportLabel.translatesAutoresizingMaskIntoConstraints = false

        let transportSubtitle = UILabel()
        transportSubtitle.text = "Choose vehicle type for road-snapped route drawing on trip history and daily locations."
        transportSubtitle.font = .systemFont(ofSize: 13)
        transportSubtitle.textColor = .secondaryLabel
        transportSubtitle.numberOfLines = 0
        transportSubtitle.translatesAutoresizingMaskIntoConstraints = false

        transportSegment = UISegmentedControl(items: ["🚗 Car", "🏍️ Moto", "🚲 Bike", "🚶 Walk"])
        transportSegment.translatesAutoresizingMaskIntoConstraints = false
        let savedTransport = UserDefaults.standard.integer(forKey: "tt_transportType")
        transportSegment.selectedSegmentIndex = (0...3).contains(savedTransport) ? savedTransport : 0
        transportSegment.addTarget(self, action: #selector(transportTypeChanged), for: .valueChanged)

        transportRow.addSubview(transportLabel)
        transportRow.addSubview(transportSubtitle)
        transportRow.addSubview(transportSegment)
        NSLayoutConstraint.activate([
            transportLabel.topAnchor.constraint(equalTo: transportRow.topAnchor, constant: 14),
            transportLabel.leadingAnchor.constraint(equalTo: transportRow.leadingAnchor, constant: 20),
            transportLabel.trailingAnchor.constraint(equalTo: transportRow.trailingAnchor, constant: -20),
            transportSubtitle.topAnchor.constraint(equalTo: transportLabel.bottomAnchor, constant: 4),
            transportSubtitle.leadingAnchor.constraint(equalTo: transportRow.leadingAnchor, constant: 20),
            transportSubtitle.trailingAnchor.constraint(equalTo: transportRow.trailingAnchor, constant: -20),
            transportSegment.topAnchor.constraint(equalTo: transportSubtitle.bottomAnchor, constant: 10),
            transportSegment.leadingAnchor.constraint(equalTo: transportRow.leadingAnchor, constant: 20),
            transportSegment.trailingAnchor.constraint(equalTo: transportRow.trailingAnchor, constant: -20),
            transportSegment.bottomAnchor.constraint(equalTo: transportRow.bottomAnchor, constant: -14),
        ])
        stackView.addArrangedSubview(transportRow)

        // ── Section: Auto Trip ───────────────────────────────────────────────
        stackView.addArrangedSubview(sectionHeader("🤖  Auto Trip"))

        autoEndTimeoutRow = SettingRow(
            title: "Auto-Stop Timeout",
            subtitle: "Trip auto-stops when speed = 0 for this many minutes.\nTrip auto-starts when vehicle speed ≥ threshold.",
            unit: "min",
            min: 1.0, max: 30.0, step: 1.0,
            format: "%.0f"
        )
        stackView.addArrangedSubview(autoEndTimeoutRow)

        // ── Section: Geofencing ──────────────────────────────────────────────
        stackView.addArrangedSubview(sectionHeader("📍  Geofencing"))

        // Toggle row
        let geoToggleRow = UIView()
        geoToggleRow.backgroundColor = .secondarySystemGroupedBackground
        let geoLabel = UILabel()
        geoLabel.text = "Geofencing Enabled"
        geoLabel.font = .systemFont(ofSize: 16, weight: .medium)
        geoLabel.translatesAutoresizingMaskIntoConstraints = false
        let geoSubtitle = UILabel()
        let zoneCount = GeofenceManager.shared.zones.count
        geoSubtitle.text = "\(zoneCount) zone(s) configured\nGet notified when entering or leaving zones. Set auto-stop to end trips on arrival."
        geoSubtitle.font = .systemFont(ofSize: 13)
        geoSubtitle.textColor = .secondaryLabel
        geoSubtitle.numberOfLines = 0
        geoSubtitle.translatesAutoresizingMaskIntoConstraints = false
        geofenceSwitch = UISwitch()
        geofenceSwitch.isOn = GeofenceManager.shared.isEnabled
        geofenceSwitch.onTintColor = .systemOrange
        geofenceSwitch.translatesAutoresizingMaskIntoConstraints = false
        geofenceSwitch.addTarget(self, action: #selector(geofenceToggled), for: .valueChanged)
        geoToggleRow.addSubview(geoLabel)
        geoToggleRow.addSubview(geoSubtitle)
        geoToggleRow.addSubview(geofenceSwitch)
        NSLayoutConstraint.activate([
            geoLabel.topAnchor.constraint(equalTo: geoToggleRow.topAnchor, constant: 14),
            geoLabel.leadingAnchor.constraint(equalTo: geoToggleRow.leadingAnchor, constant: 20),
            geofenceSwitch.centerYAnchor.constraint(equalTo: geoLabel.centerYAnchor),
            geofenceSwitch.trailingAnchor.constraint(equalTo: geoToggleRow.trailingAnchor, constant: -20),
            geoLabel.trailingAnchor.constraint(lessThanOrEqualTo: geofenceSwitch.leadingAnchor, constant: -12),
            geoSubtitle.topAnchor.constraint(equalTo: geoLabel.bottomAnchor, constant: 4),
            geoSubtitle.leadingAnchor.constraint(equalTo: geoToggleRow.leadingAnchor, constant: 20),
            geoSubtitle.trailingAnchor.constraint(equalTo: geoToggleRow.trailingAnchor, constant: -20),
            geoSubtitle.bottomAnchor.constraint(equalTo: geoToggleRow.bottomAnchor, constant: -14),
        ])
        stackView.addArrangedSubview(geoToggleRow)
        stackView.addArrangedSubview(separator())

        let manageGeoBtn = makeButton(title: "📍  MANAGE GEOFENCE ZONES", color: UIColor(red: 0.2, green: 0.6, blue: 0.95, alpha: 1))
        manageGeoBtn.addTarget(self, action: #selector(manageGeofencesTapped), for: .touchUpInside)
        stackView.addArrangedSubview(paddedWrapper(manageGeoBtn))

        // ── Section: Web Monitor ─────────────────────────────────────────────
        stackView.addArrangedSubview(sectionHeader("🌐  Web Monitor"))

        let webToggleRow = UIView()
        webToggleRow.backgroundColor = .secondarySystemGroupedBackground
        let webLabel = UILabel()
        webLabel.text = "Web Monitor Server"
        webLabel.font = .systemFont(ofSize: 16, weight: .medium)
        webLabel.translatesAutoresizingMaskIntoConstraints = false
        let webSubtitle = UILabel()
        let webEnabled = UserDefaults.standard.bool(forKey: "tt_webMonitorEnabled")
        webSubtitle.text = "Runs an HTTP server on port 8080 for live location viewing.\nTurn off to save battery when not needed."
        webSubtitle.font = .systemFont(ofSize: 13)
        webSubtitle.textColor = .secondaryLabel
        webSubtitle.numberOfLines = 0
        webSubtitle.translatesAutoresizingMaskIntoConstraints = false
        webMonitorSwitch = UISwitch()
        webMonitorSwitch.isOn = webEnabled
        webMonitorSwitch.onTintColor = .systemOrange
        webMonitorSwitch.translatesAutoresizingMaskIntoConstraints = false
        webMonitorSwitch.addTarget(self, action: #selector(webMonitorToggled), for: .valueChanged)
        webToggleRow.addSubview(webLabel)
        webToggleRow.addSubview(webSubtitle)
        webToggleRow.addSubview(webMonitorSwitch)
        NSLayoutConstraint.activate([
            webLabel.topAnchor.constraint(equalTo: webToggleRow.topAnchor, constant: 14),
            webLabel.leadingAnchor.constraint(equalTo: webToggleRow.leadingAnchor, constant: 20),
            webMonitorSwitch.centerYAnchor.constraint(equalTo: webLabel.centerYAnchor),
            webMonitorSwitch.trailingAnchor.constraint(equalTo: webToggleRow.trailingAnchor, constant: -20),
            webLabel.trailingAnchor.constraint(lessThanOrEqualTo: webMonitorSwitch.leadingAnchor, constant: -12),
            webSubtitle.topAnchor.constraint(equalTo: webLabel.bottomAnchor, constant: 4),
            webSubtitle.leadingAnchor.constraint(equalTo: webToggleRow.leadingAnchor, constant: 20),
            webSubtitle.trailingAnchor.constraint(equalTo: webToggleRow.trailingAnchor, constant: -20),
            webSubtitle.bottomAnchor.constraint(equalTo: webToggleRow.bottomAnchor, constant: -14),
        ])
        stackView.addArrangedSubview(webToggleRow)
        stackView.addArrangedSubview(separator())

        let openSafariBtn = makeButton(title: "🌐 OPEN SAFARI", color: .systemOrange)
        openSafariBtn.addTarget(self, action: #selector(openWebMonitorTapped), for: .touchUpInside)

        let copyUrlBtn = makeButton(title: "📋 COPY URL", color: UIColor.systemGray)
        copyUrlBtn.addTarget(self, action: #selector(copyWebMonitorUrlTapped), for: .touchUpInside)

        let webBtnRow = UIStackView(arrangedSubviews: [openSafariBtn, copyUrlBtn])
        webBtnRow.axis = .horizontal
        webBtnRow.spacing = 10
        webBtnRow.distribution = .fillEqually
        stackView.addArrangedSubview(paddedWrapper(webBtnRow))

        // ── Section: Notifications & Voice ───────────────────────────────────
        stackView.addArrangedSubview(sectionHeader("🔔  Notifications & Voice"))

        let notifDesc = UILabel()
        let enabledCount = [
            NotificationSettingsViewController.isTripStartEnabled,
            NotificationSettingsViewController.isTripEndEnabled,
            NotificationSettingsViewController.isDistanceKmEnabled,
            NotificationSettingsViewController.isGeofenceEnterEnabled,
            NotificationSettingsViewController.isGeofenceExitEnabled,
        ].filter { $0 }.count
        let voiceStatus = VoiceFeedbackManager.shared.isEnabled ? "ON" : "OFF"
        notifDesc.text = "Push: \(enabledCount)/5 enabled · Voice: \(voiceStatus)\nConfigure push notifications and voice announcements for trip events."
        notifDescLabel = notifDesc
        notifDesc.font = .systemFont(ofSize: 13)
        notifDesc.textColor = .secondaryLabel
        notifDesc.numberOfLines = 0
        notifDesc.translatesAutoresizingMaskIntoConstraints = false
        let notifDescRow = UIView()
        notifDescRow.backgroundColor = .secondarySystemGroupedBackground
        notifDescRow.addSubview(notifDesc)
        NSLayoutConstraint.activate([
            notifDesc.topAnchor.constraint(equalTo: notifDescRow.topAnchor, constant: 12),
            notifDesc.bottomAnchor.constraint(equalTo: notifDescRow.bottomAnchor, constant: -12),
            notifDesc.leadingAnchor.constraint(equalTo: notifDescRow.leadingAnchor, constant: 20),
            notifDesc.trailingAnchor.constraint(equalTo: notifDescRow.trailingAnchor, constant: -20),
        ])
        stackView.addArrangedSubview(notifDescRow)
        stackView.addArrangedSubview(separator())

        let notifBtn = makeButton(title: "🔔  MANAGE NOTIFICATIONS", color: UIColor.systemBlue)
        notifBtn.addTarget(self, action: #selector(notificationSettingsTapped), for: .touchUpInside)
        stackView.addArrangedSubview(paddedWrapper(notifBtn))

        // ── Section: CarPlay ─────────────────────────────────────────────────
        stackView.addArrangedSubview(sectionHeader("🚗  CarPlay"))

        let carPlayRow = UIView()
        carPlayRow.backgroundColor = .secondarySystemGroupedBackground
        let carPlayLabel = UILabel()
        carPlayLabel.text = "CarPlay Mode"
        carPlayLabel.font = .systemFont(ofSize: 16, weight: .medium)
        carPlayLabel.translatesAutoresizingMaskIntoConstraints = false

        let isMapMode = UserDefaults.standard.string(forKey: "tt_carPlayMode") == "map"
        let carPlayModeLabel = UILabel()
        carPlayModeLabel.text = isMapMode ? "🗺️ Map (requires Apple approval)" : "📋 Driving Task"
        carPlayModeLabel.font = .systemFont(ofSize: 13)
        carPlayModeLabel.textColor = .secondaryLabel
        carPlayModeLabel.numberOfLines = 0
        carPlayModeLabel.translatesAutoresizingMaskIntoConstraints = false

        carPlayModeSwitch = UISwitch()
        carPlayModeSwitch.isOn = isMapMode
        carPlayModeSwitch.onTintColor = .systemTeal
        carPlayModeSwitch.translatesAutoresizingMaskIntoConstraints = false
        carPlayModeSwitch.addTarget(self, action: #selector(carPlayModeToggled), for: .valueChanged)
        self.carPlayModeDescLabel = carPlayModeLabel

        carPlayRow.addSubview(carPlayLabel)
        carPlayRow.addSubview(carPlayModeLabel)
        carPlayRow.addSubview(carPlayModeSwitch)
        NSLayoutConstraint.activate([
            carPlayLabel.topAnchor.constraint(equalTo: carPlayRow.topAnchor, constant: 14),
            carPlayLabel.leadingAnchor.constraint(equalTo: carPlayRow.leadingAnchor, constant: 20),
            carPlayModeSwitch.centerYAnchor.constraint(equalTo: carPlayLabel.centerYAnchor),
            carPlayModeSwitch.trailingAnchor.constraint(equalTo: carPlayRow.trailingAnchor, constant: -20),
            carPlayLabel.trailingAnchor.constraint(lessThanOrEqualTo: carPlayModeSwitch.leadingAnchor, constant: -12),
            carPlayModeLabel.topAnchor.constraint(equalTo: carPlayLabel.bottomAnchor, constant: 4),
            carPlayModeLabel.leadingAnchor.constraint(equalTo: carPlayRow.leadingAnchor, constant: 20),
            carPlayModeLabel.trailingAnchor.constraint(equalTo: carPlayRow.trailingAnchor, constant: -20),
            carPlayModeLabel.bottomAnchor.constraint(equalTo: carPlayRow.bottomAnchor, constant: -14),
        ])
        stackView.addArrangedSubview(carPlayRow)

        // ── Section: Logs ────────────────────────────────────────────────────
        stackView.addArrangedSubview(sectionHeader("📋  Logs"))

        let sendTodayBtn = makeButton(title: "📧  SEND TODAY'S LOG", color: UIColor.systemBlue)
        sendTodayBtn.addTarget(self, action: #selector(sendTodayLogTapped), for: .touchUpInside)
        stackView.addArrangedSubview(paddedWrapper(sendTodayBtn))

        let sendAllBtn = makeButton(title: "📦  SEND ALL LOG FILES", color: UIColor.systemIndigo)
        sendAllBtn.addTarget(self, action: #selector(sendAllLogsTapped), for: .touchUpInside)
        stackView.addArrangedSubview(paddedWrapper(sendAllBtn))

        // ── Version Info ─────────────────────────────────────────────────────
        let versionLabel = UILabel()
        let appVersion = Bundle.main.infoDictionary?["CFBundleShortVersionString"] as? String ?? "?"
        let buildNumber = Bundle.main.infoDictionary?["CFBundleVersion"] as? String ?? "?"
        versionLabel.text = "TripTracker v\(appVersion) (build \(buildNumber))"
        versionLabel.font = .systemFont(ofSize: 12)
        versionLabel.textColor = .tertiaryLabel
        versionLabel.textAlignment = .center
        versionLabel.translatesAutoresizingMaskIntoConstraints = false
        let versionWrapper = UIView()
        versionWrapper.addSubview(versionLabel)
        NSLayoutConstraint.activate([
            versionLabel.topAnchor.constraint(equalTo: versionWrapper.topAnchor, constant: 16),
            versionLabel.bottomAnchor.constraint(equalTo: versionWrapper.bottomAnchor, constant: -24),
            versionLabel.centerXAnchor.constraint(equalTo: versionWrapper.centerXAnchor),
        ])
        stackView.addArrangedSubview(versionWrapper)
    }

    // MARK: - Load / Save

    private func loadCurrentValues() {
        let svc = LocationTrackingService.shared
        let ud  = UserDefaults.standard

        // Vehicle threshold
        let vt = ud.object(forKey: Keys.vehicleThreshold) != nil
            ? ud.float(forKey: Keys.vehicleThreshold)
            : svc.vehicleThreshold
        vehicleRow.setValue(Double(vt))

        // Save interval (stored as seconds, displayed as minutes)
        let siSecs = ud.object(forKey: Keys.saveIntervalSecs) != nil
            ? ud.double(forKey: Keys.saveIntervalSecs)
            : Double(svc.saveIntervalMs) / 1000.0
        saveIntervalRow.setValue(siSecs / 60.0)

        // Save distance
        let sd = ud.object(forKey: Keys.saveDistanceVehicleM) != nil
            ? ud.double(forKey: Keys.saveDistanceVehicleM)
            : svc.saveDistanceVehicleM
        saveDistanceRow.setValue(sd)

        // Route gap
        let rg = ud.object(forKey: Keys.routeGapThresholdM) != nil
            ? ud.double(forKey: Keys.routeGapThresholdM)
            : Defaults.routeGapThresholdM
        routeGapRow.setValue(rg)

        // Auto-stop timeout
        let autoEndMins = svc.autoEndStillnessSecs / 60.0
        autoEndTimeoutRow.setValue(autoEndMins)

        // ── Hook up auto-save for all sliders ──
        let sliderAutoSave: () -> Void = { [weak self] in
            self?.scheduleAutoSave()
        }
        vehicleRow.onValueChanged       = sliderAutoSave
        saveIntervalRow.onValueChanged   = sliderAutoSave
        saveDistanceRow.onValueChanged   = sliderAutoSave
        routeGapRow.onValueChanged       = sliderAutoSave
        autoEndTimeoutRow.onValueChanged = sliderAutoSave
    }

    /// Schedule auto-save after 5 seconds of slider inactivity.
    /// Each slider drag resets the timer.
    private func scheduleAutoSave() {
        autoSaveTimer?.invalidate()
        autoSaveTimer = Timer.scheduledTimer(withTimeInterval: 5.0, repeats: false) { [weak self] _ in
            self?.applySettings()
        }
    }

    @objc private func notificationSettingsTapped() {
        let vc = NotificationSettingsViewController()
        let nav = UINavigationController(rootViewController: vc)
        nav.modalPresentationStyle = .fullScreen
        present(nav, animated: true)
    }

    @objc private func transportTypeChanged() {
        UserDefaults.standard.set(transportSegment.selectedSegmentIndex, forKey: "tt_transportType")
        let names = ["Car", "Motorbike", "Bicycle", "Walking"]
        showToast("🛣️ Route mode: \(names[transportSegment.selectedSegmentIndex])")
    }

    @objc private func carPlayModeToggled() {
        let isMap = carPlayModeSwitch.isOn
        UserDefaults.standard.set(isMap ? "map" : "drivingTask", forKey: "tt_carPlayMode")
        carPlayModeDescLabel.text = isMap
            ? "🗺️ Map (requires Apple approval)"
            : "📋 Driving Task"
        showToast(isMap ? "🗺️ Map mode — reconnect CarPlay to apply" : "📋 Driving Task mode — reconnect CarPlay to apply")
    }

    @objc private func webMonitorToggled() {
        let enabled = webMonitorSwitch.isOn
        UserDefaults.standard.set(enabled, forKey: "tt_webMonitorEnabled")

        if let appDelegate = UIApplication.shared.delegate as? AppDelegate {
            if enabled {
                if appDelegate.webServer == nil {
                    appDelegate.webServer = LocationWebServer()
                }
                appDelegate.webServer?.start()
                showToast("🌐 Web Monitor started")
            } else {
                appDelegate.webServer?.stop()
                showToast("🌐 Web Monitor stopped — battery saving")
            }
        }
    }

    @objc private func openWebMonitorTapped() {
        guard webMonitorSwitch.isOn else {
            showToast("⚠️ Turn on Web Monitor first")
            return
        }
        let url = detectWebMonitorURL()
        if let webURL = URL(string: url) {
            UIApplication.shared.open(webURL)
        }
    }

    @objc private func copyWebMonitorUrlTapped() {
        let url = detectWebMonitorURL()
        UIPasteboard.general.string = url
        showToast("✅ URL copied: \(url)")
    }

    private func detectWebMonitorURL() -> String {
        var ifaddr: UnsafeMutablePointer<ifaddrs>?
        var wifiIP: String?
        var cellularIP: String?

        if getifaddrs(&ifaddr) == 0 {
            var ptr = ifaddr
            while let p = ptr {
                defer { ptr = p.pointee.ifa_next }
                guard p.pointee.ifa_addr.pointee.sa_family == UInt8(AF_INET) else { continue }
                let name = String(cString: p.pointee.ifa_name)
                var hostname = [CChar](repeating: 0, count: Int(NI_MAXHOST))
                getnameinfo(p.pointee.ifa_addr,
                            socklen_t(p.pointee.ifa_addr.pointee.sa_len),
                            &hostname, socklen_t(hostname.count),
                            nil, 0, NI_NUMERICHOST)
                let ip = String(cString: hostname)
                guard !ip.hasPrefix("127.") else { continue }
                if name.hasPrefix("en") && wifiIP == nil       { wifiIP = ip }
                else if name.hasPrefix("pdp_ip")               { cellularIP = ip }
            }
            freeifaddrs(ifaddr)
        }

        if let ip = wifiIP { return "http://\(ip):8080" }
        if let ip = cellularIP { return "http://\(ip):8080" }
        return "http://127.0.0.1:8080"
    }

    @objc private func geofenceToggled() {
        GeofenceManager.shared.isEnabled = geofenceSwitch.isOn
        showToast(geofenceSwitch.isOn ? "📍 Geofencing enabled" : "📍 Geofencing disabled")
    }

    @objc private func manageGeofencesTapped() {
        let vc = GeofenceViewController()
        let nav = UINavigationController(rootViewController: vc)
        nav.modalPresentationStyle = .fullScreen
        present(nav, animated: true)
    }

    @objc private func closeTapped() {
        dismiss(animated: true)
    }

    private func applySettings() {
        autoSaveTimer?.invalidate()
        autoSaveTimer = nil

        let svc = LocationTrackingService.shared
        let ud  = UserDefaults.standard

        // Vehicle threshold
        let vt = Float(vehicleRow.currentValue)
        svc.vehicleThreshold = vt
        ud.set(vt, forKey: Keys.vehicleThreshold)

        // Save interval: slider is in minutes → convert to ms for service, seconds for UserDefaults
        let siMins = saveIntervalRow.currentValue          // e.g. 5.0 min
        let siSecs = siMins * 60.0                         // e.g. 300.0 s
        let siMs   = Int64(siSecs * 1000.0)                // e.g. 300_000 ms
        svc.saveIntervalMs = siMs                          // triggers didSet → restarts timer
        ud.set(siSecs, forKey: Keys.saveIntervalSecs)      // persist in seconds

        // Save distance
        let sd = saveDistanceRow.currentValue
        svc.saveDistanceVehicleM = sd
        ud.set(sd, forKey: Keys.saveDistanceVehicleM)

        // Route gap (web monitor reads this from UserDefaults via API)
        let rg = routeGapRow.currentValue
        ud.set(rg, forKey: Keys.routeGapThresholdM)

        // Auto-stop timeout
        let autoEndMins = autoEndTimeoutRow.currentValue
        svc.autoEndStillnessSecs = autoEndMins * 60.0

        ud.synchronize()

        showToast("✅ Settings saved")
        print("⚙️ Settings auto-saved — vehicleThreshold=\(vt) m/s  saveInterval=\(siMins)min (\(siMs)ms)  saveDistance=\(sd)m  routeGap=\(rg)m  autoEnd=\(autoEndMins)min")
    }

    @objc private func resetDefaults() {
        let alert = UIAlertController(title: "Reset Settings",
                                      message: "Restore all values to defaults?",
                                      preferredStyle: .alert)
        alert.addAction(UIAlertAction(title: "Reset", style: .destructive) { [weak self] _ in
            guard let self = self else { return }
            self.vehicleRow.setValue(Double(Defaults.vehicleThreshold))
            self.saveIntervalRow.setValue(Defaults.saveIntervalSecs / 60.0)
            self.saveDistanceRow.setValue(Defaults.saveDistanceVehicleM)
            self.routeGapRow.setValue(Defaults.routeGapThresholdM)
            self.autoEndTimeoutRow.setValue(10.0)  // default 10 min
            self.applySettings()
        })
        alert.addAction(UIAlertAction(title: "Cancel", style: .cancel))
        present(alert, animated: true)
    }

    // MARK: - Helpers

    private func sectionHeader(_ text: String) -> UIView {
        let label = UILabel()
        label.text = text
        label.font = .systemFont(ofSize: 13, weight: .semibold)
        label.textColor = .secondaryLabel
        label.translatesAutoresizingMaskIntoConstraints = false
        let wrapper = UIView()
        wrapper.addSubview(label)
        NSLayoutConstraint.activate([
            label.topAnchor.constraint(equalTo: wrapper.topAnchor, constant: 24),
            label.bottomAnchor.constraint(equalTo: wrapper.bottomAnchor, constant: -8),
            label.leadingAnchor.constraint(equalTo: wrapper.leadingAnchor, constant: 20),
            label.trailingAnchor.constraint(equalTo: wrapper.trailingAnchor, constant: -20),
        ])
        return wrapper
    }

    private func separator() -> UIView {
        let v = UIView()
        v.backgroundColor = UIColor.separator
        v.heightAnchor.constraint(equalToConstant: 0.5).isActive = true
        return v
    }

    private func makeButton(title: String, color: UIColor) -> UIButton {
        let btn = UIButton(type: .system)
        btn.setTitle(title, for: .normal)
        btn.titleLabel?.font = .systemFont(ofSize: 17, weight: .semibold)
        btn.titleLabel?.adjustsFontSizeToFitWidth = true
        btn.titleLabel?.minimumScaleFactor = 0.7
        btn.backgroundColor = color
        btn.setTitleColor(.white, for: .normal)
        btn.layer.cornerRadius = 12
        btn.heightAnchor.constraint(equalToConstant: 50).isActive = true
        return btn
    }

    private func paddedWrapper(_ view: UIView) -> UIView {
        let wrapper = UIView()
        view.translatesAutoresizingMaskIntoConstraints = false
        wrapper.addSubview(view)
        NSLayoutConstraint.activate([
            view.topAnchor.constraint(equalTo: wrapper.topAnchor, constant: 8),
            view.bottomAnchor.constraint(equalTo: wrapper.bottomAnchor, constant: -8),
            view.leadingAnchor.constraint(equalTo: wrapper.leadingAnchor, constant: 20),
            view.trailingAnchor.constraint(equalTo: wrapper.trailingAnchor, constant: -20),
        ])
        return wrapper
    }

    // MARK: - Send Logs

    @objc private func sendTodayLogTapped() {
        guard let todayFile = LogManager.shared.getTodayLogFile() else {
            showToast("No log file for today yet")
            return
        }
        sendLogFiles([todayFile], subject: "TripTracker Today's Log")
    }

    @objc private func sendAllLogsTapped() {
        let allFiles = LogManager.shared.getAllLogFiles()
        guard !allFiles.isEmpty else {
            showToast("No log files found")
            return
        }
        sendLogFiles(allFiles, subject: "TripTracker All Logs")
    }

    private func sendLogFiles(_ files: [URL], subject: String) {
        // Calculate size
        var totalBytes: UInt64 = 0
        for file in files {
            if let attrs = try? FileManager.default.attributesOfItem(atPath: file.path),
               let size = attrs[FileAttributeKey.size] as? UInt64 {
                totalBytes += size
            }
        }
        let sizeText: String
        if totalBytes < 1024 { sizeText = "\(totalBytes) B" }
        else if totalBytes < 1024 * 1024 { sizeText = String(format: "%.1f KB", Double(totalBytes) / 1024) }
        else { sizeText = String(format: "%.1f MB", Double(totalBytes) / (1024 * 1024)) }

        let dateStr = DateFormatter.localizedString(from: Date(), dateStyle: .medium, timeStyle: .short)

        // Build share items: description text + file URLs
        let description = "\(subject) — \(dateStr)\n\n"
            + "Files: \(files.count)\n"
            + "Total size: \(sizeText)\n"
            + "Device: \(UIDevice.current.name)\n"
            + "iOS: \(UIDevice.current.systemVersion)"

        var items: [Any] = [description]
        items.append(contentsOf: files)

        let activityVC = UIActivityViewController(activityItems: items, applicationActivities: nil)
        activityVC.excludedActivityTypes = [.assignToContact, .addToReadingList]

        // Pre-fill subject for email apps (Gmail, Outlook, Mail, etc.)
        activityVC.setValue("\(subject) — \(dateStr)", forKey: "subject")

        // iPad popover anchor
        if let popover = activityVC.popoverPresentationController {
            popover.sourceView = self.view
            popover.sourceRect = CGRect(x: view.bounds.midX, y: view.bounds.midY, width: 0, height: 0)
            popover.permittedArrowDirections = []
        }

        activityVC.completionWithItemsHandler = { [weak self] activityType, completed, _, error in
            if completed {
                let app = activityType?.rawValue.components(separatedBy: ".").last ?? "app"
                self?.showToast("✅ Logs shared via \(app)")
            } else if let error = error {
                self?.showToast("❌ Error: \(error.localizedDescription)")
            }
        }

        present(activityVC, animated: true)
    }

    private func showToast(_ msg: String) {
        let toast = UILabel()
        toast.text = msg
        toast.textColor = .white
        toast.backgroundColor = UIColor.black.withAlphaComponent(0.75)
        toast.textAlignment = .center
        toast.font = .systemFont(ofSize: 14, weight: .medium)
        toast.layer.cornerRadius = 10
        toast.clipsToBounds = true
        toast.translatesAutoresizingMaskIntoConstraints = false
        view.addSubview(toast)
        NSLayoutConstraint.activate([
            toast.centerXAnchor.constraint(equalTo: view.centerXAnchor),
            toast.bottomAnchor.constraint(equalTo: view.safeAreaLayoutGuide.bottomAnchor, constant: -20),
            toast.widthAnchor.constraint(lessThanOrEqualTo: view.widthAnchor, constant: -40),
            toast.heightAnchor.constraint(equalToConstant: 40),
        ])
        toast.alpha = 0
        UIView.animate(withDuration: 0.3, animations: { toast.alpha = 1 }) { _ in
            UIView.animate(withDuration: 0.4, delay: 1.5, animations: { toast.alpha = 0 }) { _ in
                toast.removeFromSuperview()
            }
        }
    }
}

// MARK: - SettingRow

/// A self-contained row: title, subtitle, value label, and a stepped slider.
class SettingRow: UIView {

    private let titleLabel    = UILabel()
    private let subtitleLabel = UILabel()
    private let valueLabel    = UILabel()
    private let slider        = UISlider()

    private let minVal:  Double
    private let maxVal:  Double
    private let step:    Double
    private let unit:    String
    private let fmt:     String

    /// Called when the slider value changes (for auto-save debouncing).
    var onValueChanged: (() -> Void)?

    var currentValue: Double {
        // Snap slider to nearest step
        let raw = Double(slider.value)
        let snapped = (raw / step).rounded() * step
        return min(maxVal, max(minVal, snapped))
    }

    init(title: String, subtitle: String, unit: String,
         min: Double, max: Double, step: Double, format: String) {
        self.minVal = min
        self.maxVal = max
        self.step   = step
        self.unit   = unit
        self.fmt    = format
        super.init(frame: .zero)
        backgroundColor = .secondarySystemGroupedBackground
        setupUI(title: title, subtitle: subtitle)
    }

    required init?(coder: NSCoder) { fatalError() }

    func setValue(_ value: Double) {
        let clamped = Swift.min(maxVal, Swift.max(minVal, value))
        slider.value = Float(clamped)
        updateLabel(value: clamped)
    }

    private func setupUI(title: String, subtitle: String) {
        // Title
        titleLabel.text = title
        titleLabel.font = .systemFont(ofSize: 16, weight: .medium)
        titleLabel.textColor = .label

        // Subtitle
        subtitleLabel.text = subtitle
        subtitleLabel.font = .systemFont(ofSize: 13)
        subtitleLabel.textColor = .secondaryLabel
        subtitleLabel.numberOfLines = 0

        // Value badge
        valueLabel.font = .monospacedSystemFont(ofSize: 15, weight: .semibold)
        valueLabel.textColor = .white
        valueLabel.backgroundColor = UIColor(red:0.18,green:0.47,blue:0.82,alpha:1)
        valueLabel.textAlignment = .center
        valueLabel.layer.cornerRadius = 8
        valueLabel.clipsToBounds = true
        valueLabel.setContentHuggingPriority(.required, for: .horizontal)
        valueLabel.setContentCompressionResistancePriority(.required, for: .horizontal)

        // Slider
        slider.minimumValue = Float(minVal)
        slider.maximumValue = Float(maxVal)
        slider.tintColor    = UIColor(red:0.18,green:0.47,blue:0.82,alpha:1)
        slider.addTarget(self, action: #selector(sliderChanged), for: .valueChanged)

        // Min/max labels
        let minLabel = UILabel()
        minLabel.text = formatVal(minVal)
        minLabel.font = .systemFont(ofSize: 11)
        minLabel.textColor = .tertiaryLabel

        let maxLabel = UILabel()
        maxLabel.text = formatVal(maxVal)
        maxLabel.font = .systemFont(ofSize: 11)
        maxLabel.textColor = .tertiaryLabel

        let sliderRange = UIStackView(arrangedSubviews: [minLabel, slider, maxLabel])
        sliderRange.axis = .horizontal
        sliderRange.spacing = 6
        sliderRange.alignment = .center

        // Top row: title + value badge
        let topRow = UIStackView(arrangedSubviews: [titleLabel, valueLabel])
        topRow.axis = .horizontal
        topRow.spacing = 8
        topRow.alignment = .center

        // Full stack
        let stack = UIStackView(arrangedSubviews: [topRow, subtitleLabel, sliderRange])
        stack.axis = .vertical
        stack.spacing = 6
        stack.translatesAutoresizingMaskIntoConstraints = false
        addSubview(stack)

        NSLayoutConstraint.activate([
            stack.topAnchor.constraint(equalTo: topAnchor, constant: 14),
            stack.bottomAnchor.constraint(equalTo: bottomAnchor, constant: -14),
            stack.leadingAnchor.constraint(equalTo: leadingAnchor, constant: 20),
            stack.trailingAnchor.constraint(equalTo: trailingAnchor, constant: -20),
            valueLabel.widthAnchor.constraint(greaterThanOrEqualToConstant: 72),
            valueLabel.heightAnchor.constraint(equalToConstant: 28),
        ])
    }

    @objc private func sliderChanged() {
        updateLabel(value: currentValue)
        onValueChanged?()
    }

    private func updateLabel(value: Double) {
        valueLabel.text = " \(formatVal(value)) \(unit) "
    }

    private func formatVal(_ v: Double) -> String {
        String(format: fmt, v)
    }
}
