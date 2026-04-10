//
//  TripMapViewController.swift
//  TripTracker
//
//  Displays a trip's route on a map with start/end markers
//

import UIKit
import MapKit

class TripMapViewController: UIViewController {
    
    var tripLocations: [LocationPoint] = []
    var tripInfo: Trip?
    
    private let mapView: MKMapView = {
        let map = MKMapView()
        map.translatesAutoresizingMaskIntoConstraints = false
        return map
    }()
    
    private let infoView: UIView = {
        let view = UIView()
        view.backgroundColor = .white
        view.translatesAutoresizingMaskIntoConstraints = false
        view.layer.shadowColor = UIColor.black.cgColor
        view.layer.shadowOpacity = 0.1
        view.layer.shadowOffset = CGSize(width: 0, height: -2)
        view.layer.shadowRadius = 4
        return view
    }()
    
    private let distanceLabel = UILabel()
    private let durationLabel = UILabel()
    private let pointsLabel = UILabel()
    private let dateLabel = UILabel()
    
    override func viewDidLoad() {
        super.viewDidLoad()
        overrideUserInterfaceStyle = .light
        
        title = "Trip Route"
        view.backgroundColor = .white
        
        // Configure navigation bar appearance
        configureNavigationBar()
        
        // Add current location button to navigation bar
        let locationButton = UIBarButtonItem(
            image: UIImage(systemName: "location.fill"),
            style: .plain,
            target: self,
            action: #selector(currentLocationTapped)
        )
        // tintColor inherited from nav bar
        navigationItem.rightBarButtonItem = locationButton
        
        setupUI()
        setupMapView()
        displayRoute()
    }
    
    private func configureNavigationBar() {
        let appearance = UINavigationBarAppearance()
        appearance.configureWithOpaqueBackground()
        appearance.backgroundColor = UIColor(red: 0.45, green: 0.80, blue: 0.95, alpha: 1.0)
        appearance.titleTextAttributes = [
            .foregroundColor: UIColor.white,
            .font: UIFont.systemFont(ofSize: 20, weight: .semibold)
        ]
        navigationController?.navigationBar.standardAppearance = appearance
        navigationController?.navigationBar.scrollEdgeAppearance = appearance
        navigationController?.navigationBar.compactAppearance = appearance
        navigationController?.navigationBar.tintColor = .white
    }
    
    @objc private func currentLocationTapped() {
        // Show user location on map
        mapView.showsUserLocation = true
        
        // Zoom to current location
        if let userLocation = mapView.userLocation.location {
            let region = MKCoordinateRegion(
                center: userLocation.coordinate,
                latitudinalMeters: 500,
                longitudinalMeters: 500
            )
            mapView.setRegion(region, animated: true)
        } else {
            // Request location and wait for it
            mapView.showsUserLocation = true
            
            // Show alert that we're getting location
            let alert = UIAlertController(
                title: "Getting Location",
                message: "Waiting for GPS...",
                preferredStyle: .alert
            )
            present(alert, animated: true)
            
            // Dismiss after a moment and try to zoom
            DispatchQueue.main.asyncAfter(deadline: .now() + 1.5) { [weak self] in
                alert.dismiss(animated: true)
                
                if let location = self?.mapView.userLocation.location {
                    let region = MKCoordinateRegion(
                        center: location.coordinate,
                        latitudinalMeters: 500,
                        longitudinalMeters: 500
                    )
                    self?.mapView.setRegion(region, animated: true)
                }
            }
        }
    }
    
    private func setupUI() {
        view.addSubview(mapView)
        view.addSubview(infoView)
        
        [dateLabel, distanceLabel, durationLabel, pointsLabel].forEach {
            $0.translatesAutoresizingMaskIntoConstraints = false
            $0.font = .systemFont(ofSize: 14)
            $0.textColor = .darkGray
            infoView.addSubview($0)
        }
        
        dateLabel.font = .systemFont(ofSize: 16, weight: .semibold)
        dateLabel.textColor = .black
        
        NSLayoutConstraint.activate([
            mapView.topAnchor.constraint(equalTo: view.safeAreaLayoutGuide.topAnchor),
            mapView.leadingAnchor.constraint(equalTo: view.leadingAnchor),
            mapView.trailingAnchor.constraint(equalTo: view.trailingAnchor),
            mapView.bottomAnchor.constraint(equalTo: infoView.topAnchor),
            
            infoView.leadingAnchor.constraint(equalTo: view.leadingAnchor),
            infoView.trailingAnchor.constraint(equalTo: view.trailingAnchor),
            infoView.bottomAnchor.constraint(equalTo: view.safeAreaLayoutGuide.bottomAnchor),
            infoView.heightAnchor.constraint(equalToConstant: 100),
            
            dateLabel.topAnchor.constraint(equalTo: infoView.topAnchor, constant: 12),
            dateLabel.leadingAnchor.constraint(equalTo: infoView.leadingAnchor, constant: 20),
            dateLabel.trailingAnchor.constraint(equalTo: infoView.trailingAnchor, constant: -20),
            
            distanceLabel.topAnchor.constraint(equalTo: dateLabel.bottomAnchor, constant: 8),
            distanceLabel.leadingAnchor.constraint(equalTo: infoView.leadingAnchor, constant: 20),
            
            durationLabel.topAnchor.constraint(equalTo: dateLabel.bottomAnchor, constant: 8),
            durationLabel.centerXAnchor.constraint(equalTo: infoView.centerXAnchor),
            
            pointsLabel.topAnchor.constraint(equalTo: dateLabel.bottomAnchor, constant: 8),
            pointsLabel.trailingAnchor.constraint(equalTo: infoView.trailingAnchor, constant: -20)
        ])
        
        // Populate labels
        if let trip = tripInfo {
            dateLabel.text = trip.formattedStartTime
            distanceLabel.text = "📏 \(trip.formattedDistance)"
            durationLabel.text = "⏱️ \(trip.formattedDuration)"
        }
        pointsLabel.text = "📍 \(tripLocations.count) points"
    }
    
    private func setupMapView() {
        mapView.delegate = self
        mapView.showsUserLocation = true
        MapAppearanceHelper.applyTimeBasedAppearance(to: mapView)
    }
    
    // MARK: - Route display

    /// Tag for the raw GPS polyline so we can remove it after road-snapping.
    private var rawPolyline: MKPolyline?

    private func displayRoute() {
        guard tripLocations.count >= 2 else { return }

        // Run the full algorithm pipeline: GPS-only, dedup, accuracy filter,
        // outlier rejection, min-distance gate, Douglas-Peucker simplification.
        let gpsPoints = RouteDrawingAlgorithm.process(tripLocations)

        guard gpsPoints.count >= 2 else {
            pointsLabel.text = "📍 Not enough GPS points to draw route"
            return
        }

        pointsLabel.text = "🛰 \(gpsPoints.count) GPS pts / \(tripLocations.count) raw"

        // Fit map immediately to the GPS coordinates.
        let coords = gpsPoints.map { $0.coordinate }
        fitMap(to: coords)

        // Add start / end pins.
        addPin(coordinate: gpsPoints.first!.coordinate, title: "Start",
               subtitle: tripLocations.first?.formattedTime ?? "", isStart: true)
        addPin(coordinate: gpsPoints.last!.coordinate,  title: "End",
               subtitle: tripLocations.last?.formattedTime ?? "",  isStart: false)

        // ── Step 1: Draw raw GPS polyline INSTANTLY ──
        var rawCoords = coords
        let rawPoly = GPSPolyline(coordinates: &rawCoords, count: rawCoords.count)
        rawPolyline = rawPoly
        mapView.addOverlay(rawPoly, level: .aboveRoads)

        // ── Step 2: Road-snap with sampled waypoints in background ──
        // Instead of snapping every consecutive pair (N-1 requests),
        // sample every 10th point → ~10x fewer requests, much faster.
        let sampleStep = max(1, gpsPoints.count / 15)  // aim for ~15 segments max
        var sampled: [RoutePoint] = []
        for i in stride(from: 0, to: gpsPoints.count, by: sampleStep) {
            sampled.append(gpsPoints[i])
        }
        // Always include the last point
        if sampled.last?.coordinate.latitude != gpsPoints.last?.coordinate.latitude {
            sampled.append(gpsPoints.last!)
        }

        guard sampled.count >= 2 else { return }

        var pairs: [(RoutePoint, RoutePoint)] = []
        for i in 0..<(sampled.count - 1) {
            pairs.append((sampled[i], sampled[i + 1]))
        }

        snapSequentially(pairs: pairs, index: 0)
    }

    // Fires one MKDirections request per sampled pair.
    // When the FIRST road-snapped segment arrives, removes the raw polyline.
    private func snapSequentially(pairs: [(RoutePoint, RoutePoint)], index: Int) {
        guard index < pairs.count else { return }

        let (from, to) = pairs[index]

        let req = MKDirections.Request()
        req.source      = MKMapItem(placemark: MKPlacemark(coordinate: from.coordinate))
        req.destination = MKMapItem(placemark: MKPlacemark(coordinate: to.coordinate))
        req.transportType = RouteTransportType.currentMKType
        req.requestsAlternateRoutes = false

        MKDirections(request: req).calculate { [weak self] response, error in
            guard let self = self else { return }

            let poly: MKPolyline
            if let route = response?.routes.first {
                poly = GPSPolyline(coordinates: route.polyline.points().toArray(count: route.polyline.pointCount),
                                   count: route.polyline.pointCount)
            } else {
                var fallback = [from.coordinate, to.coordinate]
                poly = GPSPolyline(coordinates: &fallback, count: 2)
            }

            DispatchQueue.main.async {
                // Remove raw polyline on first road-snapped result
                if let raw = self.rawPolyline {
                    self.mapView.removeOverlay(raw)
                    self.rawPolyline = nil
                }
                self.mapView.addOverlay(poly, level: .aboveRoads)
            }

            // 200 ms gap between requests
            DispatchQueue.global().asyncAfter(deadline: .now() + 0.2) {
                self.snapSequentially(pairs: pairs, index: index + 1)
            }
        }
    }

    private func addPin(coordinate: CLLocationCoordinate2D, title: String,
                        subtitle: String, isStart: Bool) {
        let pin = MKPointAnnotation()
        pin.coordinate = coordinate
        pin.title      = title
        pin.subtitle   = subtitle
        mapView.addAnnotation(pin)
    }

    private func fitMap(to coords: [CLLocationCoordinate2D]) {
        guard !coords.isEmpty else { return }
        var minLat = coords[0].latitude,  maxLat = coords[0].latitude
        var minLon = coords[0].longitude, maxLon = coords[0].longitude
        for c in coords {
            minLat = min(minLat, c.latitude);  maxLat = max(maxLat, c.latitude)
            minLon = min(minLon, c.longitude); maxLon = max(maxLon, c.longitude)
        }
        let center = CLLocationCoordinate2D(latitude: (minLat + maxLat) / 2,
                                            longitude: (minLon + maxLon) / 2)
        let span = MKCoordinateSpan(latitudeDelta:  (maxLat - minLat) * 1.4 + 0.002,
                                    longitudeDelta: (maxLon - minLon) * 1.4 + 0.002)
        DispatchQueue.main.async {
            self.mapView.setRegion(MKCoordinateRegion(center: center, span: span), animated: false)
        }
    }
}

// MARK: - MKMapViewDelegate

extension TripMapViewController: MKMapViewDelegate {
    
    func mapView(_ mapView: MKMapView, rendererFor overlay: MKOverlay) -> MKOverlayRenderer {
        // All trip history overlays are GPSPolyline (road-snapped, blue).
        if let poly = overlay as? GPSPolyline {
            let r = MKPolylineRenderer(polyline: poly)
            r.strokeColor = UIColor.systemBlue
            r.lineWidth   = 4
            r.lineCap     = .round
            r.lineJoin    = .round
            return r
        }
        // Fallback for any plain MKPolyline
        if let poly = overlay as? MKPolyline {
            let r = MKPolylineRenderer(polyline: poly)
            r.strokeColor = UIColor.systemBlue
            r.lineWidth   = 4
            return r
        }
        return MKOverlayRenderer(overlay: overlay)
    }
    
    func mapView(_ mapView: MKMapView, viewFor annotation: MKAnnotation) -> MKAnnotationView? {
        guard annotation is MKPointAnnotation else { return nil }
        
        let identifier = "TripMarker"
        var annotationView = mapView.dequeueReusableAnnotationView(withIdentifier: identifier) as? MKMarkerAnnotationView
        
        if annotationView == nil {
            annotationView = MKMarkerAnnotationView(annotation: annotation, reuseIdentifier: identifier)
            annotationView?.canShowCallout = true
        } else {
            annotationView?.annotation = annotation
        }
        
        // Color markers
        if annotation.title == "Start" {
            annotationView?.markerTintColor = .systemGreen
            annotationView?.glyphText = "🏁"
        } else if annotation.title == "End" {
            annotationView?.markerTintColor = .systemRed
            annotationView?.glyphText = "🏁"
        }
        
        return annotationView
    }
}

// MARK: - Helper: convert MKMapPoint pointer to coordinate array

private extension UnsafeMutablePointer where Pointee == MKMapPoint {
    func toArray(count: Int) -> [CLLocationCoordinate2D] {
        (0..<count).map { self[$0].coordinate }
    }
}
