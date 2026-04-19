//
//  CarPlayMapViewController.swift
//  TripTracker
//
//  UIViewController that hosts the MKMapView rendered on the CarPlay display.
//  Shows current location, trip info overlay (speed, distance, duration),
//  and geofence circles on the map.
//

import UIKit
import MapKit
import CarPlay

public class CarPlayMapViewController: UIViewController {

    // MARK: - UI

    private let mapView: MKMapView = {
        let m = MKMapView()
        m.showsUserLocation = true
        m.showsCompass = true
        m.showsScale = true
        m.userTrackingMode = .followWithHeading
        m.translatesAutoresizingMaskIntoConstraints = false
        return m
    }()

    /// Semi-transparent overlay at the bottom showing trip stats
    private let infoBar: UIView = {
        let v = UIView()
        v.backgroundColor = UIColor.black.withAlphaComponent(0.7)
        v.translatesAutoresizingMaskIntoConstraints = false
        return v
    }()

    private let stateLabel: UILabel = {
        let l = UILabel()
        l.text = "⏳ Waiting"
        l.font = .systemFont(ofSize: 18, weight: .bold)
        l.textColor = .white
        l.textAlignment = .left
        l.translatesAutoresizingMaskIntoConstraints = false
        return l
    }()

    private let speedValueLabel: UILabel = {
        let l = UILabel()
        l.text = "0 km/h"
        l.font = .monospacedDigitSystemFont(ofSize: 36, weight: .bold)
        l.textColor = .white
        l.textAlignment = .center
        l.translatesAutoresizingMaskIntoConstraints = false
        return l
    }()

    private let distanceValueLabel: UILabel = {
        let l = UILabel()
        l.text = "--"
        l.font = .systemFont(ofSize: 16, weight: .semibold)
        l.textColor = .systemGreen
        l.textAlignment = .center
        l.translatesAutoresizingMaskIntoConstraints = false
        return l
    }()

    private let distanceTitleLabel: UILabel = {
        let l = UILabel()
        l.text = "DIST"
        l.font = .systemFont(ofSize: 11, weight: .medium)
        l.textColor = UIColor.white.withAlphaComponent(0.6)
        l.textAlignment = .center
        l.translatesAutoresizingMaskIntoConstraints = false
        return l
    }()

    private let durationValueLabel: UILabel = {
        let l = UILabel()
        l.text = "--:--"
        l.font = .systemFont(ofSize: 16, weight: .semibold)
        l.textColor = .cyan
        l.textAlignment = .center
        l.translatesAutoresizingMaskIntoConstraints = false
        return l
    }()

    private let durationTitleLabel: UILabel = {
        let l = UILabel()
        l.text = "TIME"
        l.font = .systemFont(ofSize: 11, weight: .medium)
        l.textColor = UIColor.white.withAlphaComponent(0.6)
        l.textAlignment = .center
        l.translatesAutoresizingMaskIntoConstraints = false
        return l
    }()

    private var isFollowingUser = true

    // MARK: - Lifecycle

    public override func viewDidLoad() {
        super.viewDidLoad()
        setupMap()
        setupInfoBar()
        drawGeofenceZones()
    }

    private func setupMap() {
        view.addSubview(mapView)
        mapView.delegate = self
        NSLayoutConstraint.activate([
            mapView.topAnchor.constraint(equalTo: view.topAnchor),
            mapView.leadingAnchor.constraint(equalTo: view.leadingAnchor),
            mapView.trailingAnchor.constraint(equalTo: view.trailingAnchor),
            mapView.bottomAnchor.constraint(equalTo: view.bottomAnchor),
        ])
    }

    private func setupInfoBar() {
        view.addSubview(infoBar)
        NSLayoutConstraint.activate([
            infoBar.leadingAnchor.constraint(equalTo: view.leadingAnchor),
            infoBar.trailingAnchor.constraint(equalTo: view.trailingAnchor),
            infoBar.bottomAnchor.constraint(equalTo: view.bottomAnchor),
            infoBar.heightAnchor.constraint(equalToConstant: 80),
        ])

        // Speed (big, center-left)
        infoBar.addSubview(speedValueLabel)

        // State label (top-left)
        infoBar.addSubview(stateLabel)

        // Distance stack (right side)
        let distStack = UIStackView(arrangedSubviews: [distanceTitleLabel, distanceValueLabel])
        distStack.axis = .vertical
        distStack.alignment = .center
        distStack.spacing = 2
        distStack.translatesAutoresizingMaskIntoConstraints = false
        infoBar.addSubview(distStack)

        // Duration stack (far right)
        let durStack = UIStackView(arrangedSubviews: [durationTitleLabel, durationValueLabel])
        durStack.axis = .vertical
        durStack.alignment = .center
        durStack.spacing = 2
        durStack.translatesAutoresizingMaskIntoConstraints = false
        infoBar.addSubview(durStack)

        NSLayoutConstraint.activate([
            stateLabel.topAnchor.constraint(equalTo: infoBar.topAnchor, constant: 8),
            stateLabel.leadingAnchor.constraint(equalTo: infoBar.leadingAnchor, constant: 16),

            speedValueLabel.leadingAnchor.constraint(equalTo: infoBar.leadingAnchor, constant: 16),
            speedValueLabel.bottomAnchor.constraint(equalTo: infoBar.bottomAnchor, constant: -8),

            durStack.trailingAnchor.constraint(equalTo: infoBar.trailingAnchor, constant: -20),
            durStack.centerYAnchor.constraint(equalTo: infoBar.centerYAnchor),

            distStack.trailingAnchor.constraint(equalTo: durStack.leadingAnchor, constant: -24),
            distStack.centerYAnchor.constraint(equalTo: infoBar.centerYAnchor),
        ])
    }

    // MARK: - Public API (called by CarPlayMapManager)

    public func updateTripInfo(speed: String, distance: String, duration: String, state: String) {
        DispatchQueue.main.async { [weak self] in
            self?.speedValueLabel.text = speed
            self?.distanceValueLabel.text = distance
            self?.durationValueLabel.text = duration
            self?.stateLabel.text = state
        }
    }

    public func updateUserLocation() {
        guard isFollowingUser else { return }
        if let coord = LocationTrackingService.shared.lastKnownCoordinate {
            let region = MKCoordinateRegion(
                center: coord,
                latitudinalMeters: 500,
                longitudinalMeters: 500
            )
            mapView.setRegion(region, animated: false)
        }
    }

    public func recenterOnUser() {
        isFollowingUser = true
        mapView.userTrackingMode = .followWithHeading
        if let coord = LocationTrackingService.shared.lastKnownCoordinate {
            let region = MKCoordinateRegion(
                center: coord,
                latitudinalMeters: 500,
                longitudinalMeters: 500
            )
            mapView.setRegion(region, animated: true)
        }
    }

    public func zoomIn() {
        var region = mapView.region
        region.span.latitudeDelta /= 2
        region.span.longitudeDelta /= 2
        mapView.setRegion(region, animated: true)
    }

    public func zoomOut() {
        var region = mapView.region
        region.span.latitudeDelta = min(region.span.latitudeDelta * 2, 10)
        region.span.longitudeDelta = min(region.span.longitudeDelta * 2, 10)
        mapView.setRegion(region, animated: true)
    }

    public func pan(direction: CPMapTemplate.PanDirection) {
        isFollowingUser = false
        mapView.userTrackingMode = .none

        var center = mapView.centerCoordinate
        let span = mapView.region.span
        let offset = 0.3

        switch direction {
        case .up:    center.latitude  += span.latitudeDelta * offset
        case .down:  center.latitude  -= span.latitudeDelta * offset
        case .left:  center.longitude -= span.longitudeDelta * offset
        case .right: center.longitude += span.longitudeDelta * offset
        default: break
        }

        mapView.setCenter(center, animated: true)
    }

    // MARK: - Geofence Circles

    private func drawGeofenceZones() {
        let zones = GeofenceManager.shared.zones
        for zone in zones {
            let circle = MKCircle(center: zone.coordinate, radius: zone.radius)
            mapView.addOverlay(circle)

            let pin = MKPointAnnotation()
            pin.coordinate = zone.coordinate
            pin.title = zone.name
            mapView.addAnnotation(pin)
        }
    }
}

// MARK: - MKMapViewDelegate

extension CarPlayMapViewController: MKMapViewDelegate {

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
