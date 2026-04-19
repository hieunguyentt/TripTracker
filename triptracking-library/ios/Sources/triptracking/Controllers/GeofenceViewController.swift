//
//  GeofenceViewController.swift
//  TripTracker
//
//  Full-screen map with geofence zones:
//    - Blue circles on map for each zone
//    - "Add at Current Location" button
//    - Long-press on map to add at any location
//    - Zone list at bottom with swipe-to-delete
//    - Add dialog: name, radius slider, enter/exit/auto-stop toggles
//

import UIKit
import MapKit
import CoreLocation

public class GeofenceViewController: UIViewController {

    // MARK: - UI

    private let mapView: MKMapView = {
        let m = MKMapView()
        m.showsUserLocation = true
        m.translatesAutoresizingMaskIntoConstraints = false
        return m
    }()

    private let addButton: UIButton = {
        let b = UIButton(type: .system)
        b.setTitle("📍 ADD AT CURRENT LOCATION", for: .normal)
        b.titleLabel?.font = .systemFont(ofSize: 15, weight: .bold)
        b.backgroundColor = UIColor(red: 0.2, green: 0.6, blue: 0.95, alpha: 1)
        b.setTitleColor(.white, for: .normal)
        b.layer.cornerRadius = 10
        b.translatesAutoresizingMaskIntoConstraints = false
        return b
    }()

    private let hintLabel: UILabel = {
        let l = UILabel()
        l.text = "Long-press on map to add at any location"
        l.font = .systemFont(ofSize: 12)
        l.textColor = .secondaryLabel
        l.textAlignment = .center
        l.translatesAutoresizingMaskIntoConstraints = false
        return l
    }()

    private let tableView: UITableView = {
        let t = UITableView(frame: .zero, style: .plain)
        t.translatesAutoresizingMaskIntoConstraints = false
        t.rowHeight = 60
        t.register(UITableViewCell.self, forCellReuseIdentifier: "ZoneCell")
        return t
    }()

    // MARK: - Lifecycle

    public override func viewDidLoad() {
        super.viewDidLoad()
        overrideUserInterfaceStyle = .light
        title = "Geofence Zones"
        view.backgroundColor = .white

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

        setupLayout()
        setupActions()
        mapView.delegate = self
        MapAppearanceHelper.applyTimeBasedAppearance(to: mapView)
        tableView.dataSource = self
        tableView.delegate = self

        drawAllZones()
        zoomToCurrentLocation()
    }

    public override func viewWillAppear(_ animated: Bool) {
        super.viewWillAppear(animated)
        tableView.reloadData()
        drawAllZones()
    }

    // MARK: - Layout

    private func setupLayout() {
        view.addSubview(mapView)
        view.addSubview(addButton)
        view.addSubview(hintLabel)
        view.addSubview(tableView)

        NSLayoutConstraint.activate([
            mapView.topAnchor.constraint(equalTo: view.safeAreaLayoutGuide.topAnchor),
            mapView.leadingAnchor.constraint(equalTo: view.leadingAnchor),
            mapView.trailingAnchor.constraint(equalTo: view.trailingAnchor),
            mapView.heightAnchor.constraint(equalTo: view.heightAnchor, multiplier: 0.45),

            addButton.topAnchor.constraint(equalTo: mapView.bottomAnchor, constant: 12),
            addButton.leadingAnchor.constraint(equalTo: view.leadingAnchor, constant: 20),
            addButton.trailingAnchor.constraint(equalTo: view.trailingAnchor, constant: -20),
            addButton.heightAnchor.constraint(equalToConstant: 46),

            hintLabel.topAnchor.constraint(equalTo: addButton.bottomAnchor, constant: 6),
            hintLabel.leadingAnchor.constraint(equalTo: view.leadingAnchor, constant: 20),
            hintLabel.trailingAnchor.constraint(equalTo: view.trailingAnchor, constant: -20),

            tableView.topAnchor.constraint(equalTo: hintLabel.bottomAnchor, constant: 8),
            tableView.leadingAnchor.constraint(equalTo: view.leadingAnchor),
            tableView.trailingAnchor.constraint(equalTo: view.trailingAnchor),
            tableView.bottomAnchor.constraint(equalTo: view.safeAreaLayoutGuide.bottomAnchor),
        ])
    }

    private func setupActions() {
        addButton.addTarget(self, action: #selector(addAtCurrentLocation), for: .touchUpInside)

        let longPress = UILongPressGestureRecognizer(target: self, action: #selector(mapLongPress(_:)))
        longPress.minimumPressDuration = 0.5
        mapView.addGestureRecognizer(longPress)
    }

    // MARK: - Map

    private func zoomToCurrentLocation() {
        if let loc = mapView.userLocation.location {
            let region = MKCoordinateRegion(center: loc.coordinate,
                                            latitudinalMeters: 2000, longitudinalMeters: 2000)
            mapView.setRegion(region, animated: false)
        } else {
            DispatchQueue.main.asyncAfter(deadline: .now() + 1) { [weak self] in
                if let loc = self?.mapView.userLocation.location {
                    let region = MKCoordinateRegion(center: loc.coordinate,
                                                    latitudinalMeters: 2000, longitudinalMeters: 2000)
                    self?.mapView.setRegion(region, animated: true)
                }
            }
        }
    }

    private func drawAllZones() {
        // Remove existing overlays and annotations (except user location)
        mapView.removeOverlays(mapView.overlays)
        let stale = mapView.annotations.filter { !($0 is MKUserLocation) }
        mapView.removeAnnotations(stale)

        for zone in GeofenceManager.shared.zones {
            let circle = MKCircle(center: zone.coordinate, radius: zone.radius)
            mapView.addOverlay(circle)

            let pin = MKPointAnnotation()
            pin.coordinate = zone.coordinate
            pin.title = zone.name
            pin.subtitle = "\(Int(zone.radius))m"
            mapView.addAnnotation(pin)
        }
    }

    // MARK: - Actions

    @objc private func closeTapped() {
        dismiss(animated: true)
    }

    @objc private func addAtCurrentLocation() {
        guard let coord = mapView.userLocation.location?.coordinate else {
            showAlert("No Location", "Cannot determine current position.")
            return
        }
        showAddDialog(coordinate: coord)
    }

    @objc private func mapLongPress(_ gesture: UILongPressGestureRecognizer) {
        guard gesture.state == .began else { return }
        let point = gesture.location(in: mapView)
        let coord = mapView.convert(point, toCoordinateFrom: mapView)
        showAddDialog(coordinate: coord)
    }

    // MARK: - Add Zone Dialog

    private func showAddDialog(coordinate: CLLocationCoordinate2D) {
        let sheet = AddGeofenceSheetController(coordinate: coordinate) { [weak self] zone in
            GeofenceManager.shared.addZone(zone)
            self?.drawAllZones()
            self?.tableView.reloadData()
        }
        sheet.modalPresentationStyle = .pageSheet
        if #available(iOS 15.0, *) {
            if let pc = sheet.sheetPresentationController {
                pc.detents = [.medium()]
                pc.prefersGrabberVisible = true
            }
        }
        present(sheet, animated: true)
    }

    private func showAlert(_ title: String, _ message: String) {
        let a = UIAlertController(title: title, message: message, preferredStyle: .alert)
        a.addAction(UIAlertAction(title: "OK", style: .default))
        present(a, animated: true)
    }
}

// MARK: - UITableViewDataSource & Delegate

extension GeofenceViewController: UITableViewDataSource, UITableViewDelegate {

    public func tableView(_ tableView: UITableView, numberOfRowsInSection section: Int) -> Int {
        GeofenceManager.shared.zones.count
    }

    public func tableView(_ tableView: UITableView, cellForRowAt indexPath: IndexPath) -> UITableViewCell {
        let cell = tableView.dequeueReusableCell(withIdentifier: "ZoneCell", for: indexPath)
        let zone = GeofenceManager.shared.zones[indexPath.row]

        var flags: [String] = []
        if zone.notifyOnEnter { flags.append("Enter") }
        if zone.notifyOnExit  { flags.append("Exit") }
        if zone.autoStopOnEnter { flags.append("Auto-stop") }

        cell.textLabel?.text = zone.name
        cell.textLabel?.font = .systemFont(ofSize: 16, weight: .semibold)
        cell.detailTextLabel?.text = "\(Int(zone.radius))m · \(flags.joined(separator: " · ")) · (\(String(format: "%.4f", zone.latitude)), \(String(format: "%.4f", zone.longitude)))"

        // Use subtitle style
        var content = cell.defaultContentConfiguration()
        content.text = zone.name
        content.textProperties.font = .systemFont(ofSize: 16, weight: .semibold)
        content.secondaryText = "\(Int(zone.radius))m · \(flags.joined(separator: ", ")) · (\(String(format: "%.4f", zone.latitude)), \(String(format: "%.4f", zone.longitude)))"
        content.secondaryTextProperties.font = .systemFont(ofSize: 12)
        content.secondaryTextProperties.color = .secondaryLabel
        cell.contentConfiguration = content
        return cell
    }

    public func tableView(_ tableView: UITableView, commit editingStyle: UITableViewCell.EditingStyle,
                    forRowAt indexPath: IndexPath) {
        if editingStyle == .delete {
            GeofenceManager.shared.removeZone(at: indexPath.row)
            tableView.deleteRows(at: [indexPath], with: .fade)
            drawAllZones()
        }
    }

    public func tableView(_ tableView: UITableView, didSelectRowAt indexPath: IndexPath) {
        tableView.deselectRow(at: indexPath, animated: true)
        let zone = GeofenceManager.shared.zones[indexPath.row]
        let region = MKCoordinateRegion(center: zone.coordinate,
                                        latitudinalMeters: zone.radius * 3,
                                        longitudinalMeters: zone.radius * 3)
        mapView.setRegion(region, animated: true)
    }
}

// MARK: - MKMapViewDelegate

extension GeofenceViewController: MKMapViewDelegate {

    public func mapView(_ mapView: MKMapView, rendererFor overlay: MKOverlay) -> MKOverlayRenderer {
        if let circle = overlay as? MKCircle {
            let renderer = MKCircleRenderer(circle: circle)
            renderer.fillColor = UIColor.systemBlue.withAlphaComponent(0.15)
            renderer.strokeColor = UIColor.systemBlue.withAlphaComponent(0.6)
            renderer.lineWidth = 2
            return renderer
        }
        return MKOverlayRenderer(overlay: overlay)
    }
}

// MARK: - Add Geofence Sheet Controller

/// Clean bottom sheet for adding a geofence zone.
public class AddGeofenceSheetController: UIViewController {

    private let coordinate: CLLocationCoordinate2D
    private let onAdd: (GeofenceZone) -> Void

    private let nameField = UITextField()
    private let radiusSlider = UISlider()
    private let radiusValueLabel = UILabel()
    private let enterSwitch = UISwitch()
    private let exitSwitch = UISwitch()
    private let autoStopSwitch = UISwitch()

    public init(coordinate: CLLocationCoordinate2D, onAdd: @escaping (GeofenceZone) -> Void) {
        self.coordinate = coordinate
        self.onAdd = onAdd
        super.init(nibName: nil, bundle: nil)
    }

    required init?(coder: NSCoder) { fatalError() }

    public override func viewDidLoad() {
        super.viewDidLoad()
        overrideUserInterfaceStyle = .light
        view.backgroundColor = .white
        buildUI()
    }

    private func buildUI() {
        let scrollView = UIScrollView()
        scrollView.translatesAutoresizingMaskIntoConstraints = false
        view.addSubview(scrollView)

        let stack = UIStackView()
        stack.axis = .vertical
        stack.spacing = 16
        stack.translatesAutoresizingMaskIntoConstraints = false
        scrollView.addSubview(stack)

        NSLayoutConstraint.activate([
            scrollView.topAnchor.constraint(equalTo: view.safeAreaLayoutGuide.topAnchor),
            scrollView.leadingAnchor.constraint(equalTo: view.leadingAnchor),
            scrollView.trailingAnchor.constraint(equalTo: view.trailingAnchor),
            scrollView.bottomAnchor.constraint(equalTo: view.bottomAnchor),
            stack.topAnchor.constraint(equalTo: scrollView.topAnchor, constant: 20),
            stack.leadingAnchor.constraint(equalTo: scrollView.leadingAnchor, constant: 24),
            stack.trailingAnchor.constraint(equalTo: scrollView.trailingAnchor, constant: -24),
            stack.bottomAnchor.constraint(equalTo: scrollView.bottomAnchor, constant: -20),
            stack.widthAnchor.constraint(equalTo: scrollView.widthAnchor, constant: -48),
        ])

        // ── Title ──
        let titleLabel = UILabel()
        titleLabel.text = "📍 Add Geofence Zone"
        titleLabel.font = .systemFont(ofSize: 20, weight: .bold)
        titleLabel.textAlignment = .center
        stack.addArrangedSubview(titleLabel)

        // ── Coordinate ──
        let coordLabel = UILabel()
        coordLabel.text = String(format: "%.6f, %.6f", coordinate.latitude, coordinate.longitude)
        coordLabel.font = .monospacedSystemFont(ofSize: 14, weight: .regular)
        coordLabel.textColor = .secondaryLabel
        coordLabel.textAlignment = .center
        stack.addArrangedSubview(coordLabel)

        // ── Name field ──
        nameField.placeholder = "Zone name (e.g. Home, Office)"
        nameField.font = .systemFont(ofSize: 16)
        nameField.borderStyle = .roundedRect
        nameField.autocapitalizationType = .words
        nameField.returnKeyType = .done
        nameField.delegate = self
        stack.addArrangedSubview(nameField)

        // ── Radius ──
        let radiusHeader = makeRow("Radius", rightView: radiusValueLabel)
        radiusValueLabel.text = "200 m"
        radiusValueLabel.font = .monospacedSystemFont(ofSize: 15, weight: .bold)
        radiusValueLabel.textColor = .systemBlue
        stack.addArrangedSubview(radiusHeader)

        radiusSlider.minimumValue = 50
        radiusSlider.maximumValue = 1000
        radiusSlider.value = 200
        radiusSlider.tintColor = .systemBlue
        radiusSlider.addTarget(self, action: #selector(radiusChanged), for: .valueChanged)
        stack.addArrangedSubview(radiusSlider)

        // ── Divider ──
        stack.addArrangedSubview(divider())

        // ── Toggles ──
        enterSwitch.isOn = true
        enterSwitch.onTintColor = .systemGreen
        stack.addArrangedSubview(makeRow("Notify on Enter", rightView: enterSwitch))

        exitSwitch.isOn = true
        exitSwitch.onTintColor = .systemGreen
        stack.addArrangedSubview(makeRow("Notify on Exit", rightView: exitSwitch))

        stack.addArrangedSubview(divider())

        autoStopSwitch.isOn = false
        autoStopSwitch.onTintColor = .systemOrange
        stack.addArrangedSubview(makeRow("Auto-stop trip on enter", rightView: autoStopSwitch))

        let autoHint = UILabel()
        autoHint.text = "Automatically end the current trip when entering this zone (e.g. arriving home)"
        autoHint.font = .systemFont(ofSize: 12)
        autoHint.textColor = .tertiaryLabel
        autoHint.numberOfLines = 0
        stack.addArrangedSubview(autoHint)

        stack.addArrangedSubview(divider())

        // ── Buttons ──
        let buttonRow = UIStackView()
        buttonRow.axis = .horizontal
        buttonRow.spacing = 12
        buttonRow.distribution = .fillEqually

        let cancelBtn = UIButton(type: .system)
        cancelBtn.setTitle("Cancel", for: .normal)
        cancelBtn.titleLabel?.font = .systemFont(ofSize: 17, weight: .medium)
        cancelBtn.backgroundColor = UIColor.systemGray5
        cancelBtn.setTitleColor(.label, for: .normal)
        cancelBtn.layer.cornerRadius = 10
        cancelBtn.heightAnchor.constraint(equalToConstant: 48).isActive = true
        cancelBtn.addTarget(self, action: #selector(cancelTapped), for: .touchUpInside)

        let addBtn = UIButton(type: .system)
        addBtn.setTitle("Add", for: .normal)
        addBtn.titleLabel?.font = .systemFont(ofSize: 17, weight: .bold)
        addBtn.backgroundColor = UIColor(red: 0.2, green: 0.6, blue: 0.95, alpha: 1)
        addBtn.setTitleColor(.white, for: .normal)
        addBtn.layer.cornerRadius = 10
        addBtn.heightAnchor.constraint(equalToConstant: 48).isActive = true
        addBtn.addTarget(self, action: #selector(addTapped), for: .touchUpInside)

        buttonRow.addArrangedSubview(cancelBtn)
        buttonRow.addArrangedSubview(addBtn)
        stack.addArrangedSubview(buttonRow)
    }

    // MARK: - Helpers

    private func makeRow(_ title: String, rightView: UIView) -> UIStackView {
        let label = UILabel()
        label.text = title
        label.font = .systemFont(ofSize: 16)
        let row = UIStackView(arrangedSubviews: [label, rightView])
        row.axis = .horizontal
        row.alignment = .center
        row.distribution = .equalSpacing
        return row
    }

    private func divider() -> UIView {
        let v = UIView()
        v.backgroundColor = .separator
        v.heightAnchor.constraint(equalToConstant: 0.5).isActive = true
        return v
    }

    // MARK: - Actions

    @objc private func radiusChanged() {
        let v = Int(radiusSlider.value / 50) * 50
        radiusSlider.value = Float(v)
        radiusValueLabel.text = "\(v) m"
    }

    @objc private func cancelTapped() {
        dismiss(animated: true)
    }

    @objc private func addTapped() {
        let name = nameField.text?.trimmingCharacters(in: .whitespaces) ?? ""
        guard !name.isEmpty else {
            nameField.layer.borderColor = UIColor.systemRed.cgColor
            nameField.layer.borderWidth = 1
            nameField.placeholder = "⚠️ Please enter a zone name"
            return
        }

        let zone = GeofenceZone(
            name: name,
            latitude: coordinate.latitude,
            longitude: coordinate.longitude,
            radius: Double(Int(radiusSlider.value / 50) * 50),
            notifyOnEnter: enterSwitch.isOn,
            notifyOnExit: exitSwitch.isOn,
            autoStopOnEnter: autoStopSwitch.isOn
        )
        dismiss(animated: true) { [weak self] in
            self?.onAdd(zone)
        }
    }
}

// MARK: - UITextFieldDelegate

extension AddGeofenceSheetController: UITextFieldDelegate {
    public func textFieldShouldReturn(_ textField: UITextField) -> Bool {
        textField.resignFirstResponder()
        return true
    }
}
