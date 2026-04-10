//
//  NotificationSettingsViewController.swift
//  TripTracker
//
//  Settings page for push notifications and voice feedback.
//  Each notification type can be independently toggled on/off.
//  Voice feedback toggle is also here (moved from main Settings).
//

import UIKit

class NotificationSettingsViewController: UIViewController {

    // MARK: - Keys (UserDefaults)

    private struct Keys {
        static let tripStart     = "tt_notify_tripStart"
        static let tripEnd       = "tt_notify_tripEnd"
        static let distanceKm    = "tt_notify_distanceKm"
        static let geofenceEnter = "tt_notify_geofenceEnter"
        static let geofenceExit  = "tt_notify_geofenceExit"
    }

    // MARK: - Static helpers for checking from anywhere

    static var isTripStartEnabled: Bool {
        UserDefaults.standard.object(forKey: Keys.tripStart) == nil ? true : UserDefaults.standard.bool(forKey: Keys.tripStart)
    }
    static var isTripEndEnabled: Bool {
        UserDefaults.standard.object(forKey: Keys.tripEnd) == nil ? true : UserDefaults.standard.bool(forKey: Keys.tripEnd)
    }
    static var isDistanceKmEnabled: Bool {
        UserDefaults.standard.object(forKey: Keys.distanceKm) == nil ? true : UserDefaults.standard.bool(forKey: Keys.distanceKm)
    }
    static var isGeofenceEnterEnabled: Bool {
        UserDefaults.standard.object(forKey: Keys.geofenceEnter) == nil ? true : UserDefaults.standard.bool(forKey: Keys.geofenceEnter)
    }
    static var isGeofenceExitEnabled: Bool {
        UserDefaults.standard.object(forKey: Keys.geofenceExit) == nil ? true : UserDefaults.standard.bool(forKey: Keys.geofenceExit)
    }

    // MARK: - UI

    private let scrollView = UIScrollView()
    private let stackView: UIStackView = {
        let sv = UIStackView()
        sv.axis = .vertical
        sv.spacing = 0
        sv.translatesAutoresizingMaskIntoConstraints = false
        return sv
    }()

    private var tripStartSwitch     = UISwitch()
    private var tripEndSwitch       = UISwitch()
    private var distanceKmSwitch    = UISwitch()
    private var geofenceEnterSwitch = UISwitch()
    private var geofenceExitSwitch  = UISwitch()
    private var voiceFeedbackSwitch = UISwitch()

    // MARK: - Lifecycle

    override func viewDidLoad() {
        super.viewDidLoad()
        overrideUserInterfaceStyle = .light
        title = "Notifications"
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

        setupScrollView()
        buildRows()
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
            scrollView.bottomAnchor.constraint(equalTo: view.bottomAnchor),
            stackView.topAnchor.constraint(equalTo: scrollView.topAnchor),
            stackView.leadingAnchor.constraint(equalTo: scrollView.leadingAnchor),
            stackView.trailingAnchor.constraint(equalTo: scrollView.trailingAnchor),
            stackView.bottomAnchor.constraint(equalTo: scrollView.bottomAnchor),
            stackView.widthAnchor.constraint(equalTo: scrollView.widthAnchor),
        ])
    }

    private func buildRows() {
        // ── Section: Push Notifications ──────────────────────────────
        stackView.addArrangedSubview(sectionHeader("🔔  Push Notifications"))

        tripStartSwitch.isOn = Self.isTripStartEnabled
        tripStartSwitch.onTintColor = .systemGreen
        tripStartSwitch.addTarget(self, action: #selector(switchChanged), for: .valueChanged)
        stackView.addArrangedSubview(
            toggleRow(title: "Trip Started",
                      subtitle: "Notify when a trip auto-starts (vehicle speed detected).",
                      icon: "🚗",
                      toggle: tripStartSwitch))
        stackView.addArrangedSubview(separator())

        tripEndSwitch.isOn = Self.isTripEndEnabled
        tripEndSwitch.onTintColor = .systemGreen
        tripEndSwitch.addTarget(self, action: #selector(switchChanged), for: .valueChanged)
        stackView.addArrangedSubview(
            toggleRow(title: "Trip Ended",
                      subtitle: "Notify when a trip auto-ends with distance and duration.",
                      icon: "🏁",
                      toggle: tripEndSwitch))
        stackView.addArrangedSubview(separator())

        distanceKmSwitch.isOn = Self.isDistanceKmEnabled
        distanceKmSwitch.onTintColor = .systemGreen
        distanceKmSwitch.addTarget(self, action: #selector(switchChanged), for: .valueChanged)
        stackView.addArrangedSubview(
            toggleRow(title: "Distance Milestone",
                      subtitle: "Notify every 1 km traveled during a trip.",
                      icon: "📏",
                      toggle: distanceKmSwitch))
        stackView.addArrangedSubview(separator())

        geofenceEnterSwitch.isOn = Self.isGeofenceEnterEnabled
        geofenceEnterSwitch.onTintColor = .systemGreen
        geofenceEnterSwitch.addTarget(self, action: #selector(switchChanged), for: .valueChanged)
        stackView.addArrangedSubview(
            toggleRow(title: "Geofence Enter",
                      subtitle: "Notify when entering a geofence zone.",
                      icon: "📍",
                      toggle: geofenceEnterSwitch))
        stackView.addArrangedSubview(separator())

        geofenceExitSwitch.isOn = Self.isGeofenceExitEnabled
        geofenceExitSwitch.onTintColor = .systemGreen
        geofenceExitSwitch.addTarget(self, action: #selector(switchChanged), for: .valueChanged)
        stackView.addArrangedSubview(
            toggleRow(title: "Geofence Exit",
                      subtitle: "Notify when leaving a geofence zone.",
                      icon: "📍",
                      toggle: geofenceExitSwitch))

        // ── Section: Voice Feedback ──────────────────────────────────
        stackView.addArrangedSubview(sectionHeader("🔊  Voice Feedback"))

        voiceFeedbackSwitch.isOn = VoiceFeedbackManager.shared.isEnabled
        voiceFeedbackSwitch.onTintColor = .systemPurple
        voiceFeedbackSwitch.addTarget(self, action: #selector(voiceToggled), for: .valueChanged)
        stackView.addArrangedSubview(
            toggleRow(title: "Voice Announcements",
                      subtitle: "Speak trip start/end, distance milestones, geofence enter/exit, and vehicle stop through the speaker or car audio.",
                      icon: "🔊",
                      toggle: voiceFeedbackSwitch))
    }

    // MARK: - Actions

    @objc private func switchChanged() {
        UserDefaults.standard.set(tripStartSwitch.isOn,     forKey: Keys.tripStart)
        UserDefaults.standard.set(tripEndSwitch.isOn,       forKey: Keys.tripEnd)
        UserDefaults.standard.set(distanceKmSwitch.isOn,    forKey: Keys.distanceKm)
        UserDefaults.standard.set(geofenceEnterSwitch.isOn, forKey: Keys.geofenceEnter)
        UserDefaults.standard.set(geofenceExitSwitch.isOn,  forKey: Keys.geofenceExit)
    }

    @objc private func voiceToggled() {
        VoiceFeedbackManager.shared.isEnabled = voiceFeedbackSwitch.isOn
        if voiceFeedbackSwitch.isOn {
            VoiceFeedbackManager.shared.speak("Voice feedback enabled.")
        }
    }

    @objc private func closeTapped() {
        dismiss(animated: true)
    }

    // MARK: - Helpers

    private func toggleRow(title: String, subtitle: String, icon: String, toggle: UISwitch) -> UIView {
        let row = UIView()
        row.backgroundColor = .secondarySystemGroupedBackground

        let iconLabel = UILabel()
        iconLabel.text = icon
        iconLabel.font = .systemFont(ofSize: 22)
        iconLabel.translatesAutoresizingMaskIntoConstraints = false

        let titleLabel = UILabel()
        titleLabel.text = title
        titleLabel.font = .systemFont(ofSize: 16, weight: .medium)
        titleLabel.translatesAutoresizingMaskIntoConstraints = false

        let subtitleLabel = UILabel()
        subtitleLabel.text = subtitle
        subtitleLabel.font = .systemFont(ofSize: 13)
        subtitleLabel.textColor = .secondaryLabel
        subtitleLabel.numberOfLines = 0
        subtitleLabel.translatesAutoresizingMaskIntoConstraints = false

        toggle.translatesAutoresizingMaskIntoConstraints = false

        row.addSubview(iconLabel)
        row.addSubview(titleLabel)
        row.addSubview(subtitleLabel)
        row.addSubview(toggle)

        NSLayoutConstraint.activate([
            iconLabel.leadingAnchor.constraint(equalTo: row.leadingAnchor, constant: 20),
            iconLabel.topAnchor.constraint(equalTo: row.topAnchor, constant: 14),

            titleLabel.leadingAnchor.constraint(equalTo: iconLabel.trailingAnchor, constant: 12),
            titleLabel.topAnchor.constraint(equalTo: row.topAnchor, constant: 14),
            titleLabel.trailingAnchor.constraint(lessThanOrEqualTo: toggle.leadingAnchor, constant: -12),

            toggle.trailingAnchor.constraint(equalTo: row.trailingAnchor, constant: -20),
            toggle.centerYAnchor.constraint(equalTo: titleLabel.centerYAnchor),

            subtitleLabel.topAnchor.constraint(equalTo: titleLabel.bottomAnchor, constant: 4),
            subtitleLabel.leadingAnchor.constraint(equalTo: titleLabel.leadingAnchor),
            subtitleLabel.trailingAnchor.constraint(equalTo: row.trailingAnchor, constant: -20),
            subtitleLabel.bottomAnchor.constraint(equalTo: row.bottomAnchor, constant: -14),
        ])

        return row
    }

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
        ])
        return wrapper
    }

    private func separator() -> UIView {
        let v = UIView()
        v.backgroundColor = .separator
        v.heightAnchor.constraint(equalToConstant: 0.5).isActive = true
        return v
    }
}
