//
//  DailyLocationsViewController.swift
//  TripTracker
//

import UIKit
import MapKit
import CoreLocation

class DailyLocationsViewController: UIViewController {
    
    private let tableView: UITableView = {
        let table = UITableView()
        table.translatesAutoresizingMaskIntoConstraints = false
        table.register(DateCell.self, forCellReuseIdentifier: "DateCell")
        return table
    }()
    
    private var dates: [(date: String, count: Int)] = []
    
    override func viewDidLoad() {
        super.viewDidLoad()
        overrideUserInterfaceStyle = .light
        
        title = "Daily Locations"
        view.backgroundColor = .white
        
        // Configure navigation bar appearance
        configureNavigationBar()
        
        setupUI()
        loadDates()
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
    
    override func viewWillAppear(_ animated: Bool) {
        super.viewWillAppear(animated)
        loadDates() // Reload when coming back
    }
    
    private func setupUI() {
        view.addSubview(tableView)
        tableView.delegate = self
        tableView.dataSource = self
        
        NSLayoutConstraint.activate([
            tableView.topAnchor.constraint(equalTo: view.safeAreaLayoutGuide.topAnchor),
            tableView.leadingAnchor.constraint(equalTo: view.leadingAnchor),
            tableView.trailingAnchor.constraint(equalTo: view.trailingAnchor),
            tableView.bottomAnchor.constraint(equalTo: view.bottomAnchor)
        ])
    }
    
    private func loadDates() {
        dates = DatabaseManager.shared.getDatesWithLocations()
        tableView.reloadData()
    }
    
    private func showDayRouteOnMap(date: String, count: Int) {
        let locations = DatabaseManager.shared.getCachedLocations(date: date)

        guard !locations.isEmpty else {
            showAlert(title: "No Data", message: "This day has no location data.")
            return
        }

        // Pass ALL raw points — RouteDrawingAlgorithm handles
        // dedup / outlier rejection / accuracy filtering / DP inside DailyRouteMapViewController
        let mapVC = DailyRouteMapViewController()
        mapVC.dayLocations  = locations   // raw, unfiltered
        mapVC.dateString    = date
        mapVC.totalPoints   = count
        navigationController?.pushViewController(mapVC, animated: true)
    }
    
    private func showAlert(title: String, message: String) {
        let alert = UIAlertController(title: title, message: message, preferredStyle: .alert)
        alert.addAction(UIAlertAction(title: "OK", style: .default))
        present(alert, animated: true)
    }
}

extension DailyLocationsViewController: UITableViewDelegate, UITableViewDataSource {
    
    func tableView(_ tableView: UITableView, numberOfRowsInSection section: Int) -> Int {
        return dates.count
    }
    
    func tableView(_ tableView: UITableView, cellForRowAt indexPath: IndexPath) -> UITableViewCell {
        let cell = tableView.dequeueReusableCell(withIdentifier: "DateCell", for: indexPath) as! DateCell
        let date = dates[indexPath.row]
        cell.configure(date: date.date, count: date.count)
        return cell
    }
    
    func tableView(_ tableView: UITableView, didSelectRowAt indexPath: IndexPath) {
        tableView.deselectRow(at: indexPath, animated: true)
        let dateInfo = dates[indexPath.row]
        showDayRouteOnMap(date: dateInfo.date, count: dateInfo.count)
    }
}

class DateCell: UITableViewCell {
    
    private let dateLabel = UILabel()
    private let countLabel = UILabel()
    private let iconLabel = UILabel()
    
    override init(style: UITableViewCell.CellStyle, reuseIdentifier: String?) {
        super.init(style: style, reuseIdentifier: reuseIdentifier)
        
        dateLabel.translatesAutoresizingMaskIntoConstraints = false
        countLabel.translatesAutoresizingMaskIntoConstraints = false
        iconLabel.translatesAutoresizingMaskIntoConstraints = false
        
        contentView.addSubview(iconLabel)
        contentView.addSubview(dateLabel)
        contentView.addSubview(countLabel)
        
        iconLabel.font = .systemFont(ofSize: 24)
        iconLabel.text = "📅"
        
        dateLabel.font = .systemFont(ofSize: 16, weight: .medium)
        countLabel.font = .systemFont(ofSize: 14)
        countLabel.textColor = .gray
        
        NSLayoutConstraint.activate([
            iconLabel.leadingAnchor.constraint(equalTo: contentView.leadingAnchor, constant: 15),
            iconLabel.centerYAnchor.constraint(equalTo: contentView.centerYAnchor),
            
            dateLabel.leadingAnchor.constraint(equalTo: iconLabel.trailingAnchor, constant: 12),
            dateLabel.centerYAnchor.constraint(equalTo: contentView.centerYAnchor),
            
            countLabel.trailingAnchor.constraint(equalTo: contentView.trailingAnchor, constant: -15),
            countLabel.centerYAnchor.constraint(equalTo: contentView.centerYAnchor)
        ])
        
        accessoryType = .disclosureIndicator
    }
    
    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }
    
    func configure(date: String, count: Int) {
        // Format date nicely
        let formatter = DateFormatter()
        formatter.dateFormat = "yyyy-MM-dd"
        if let dateObj = formatter.date(from: date) {
            formatter.dateFormat = "EEEE, MMM d, yyyy"
            dateLabel.text = formatter.string(from: dateObj)
        } else {
            dateLabel.text = date
        }
        
        countLabel.text = "\(count) locations"
    }
}

// MARK: - Daily POI Map View Controller

// Custom annotation carrying a full LocationPoint
class LocationAnnotation: NSObject, MKAnnotation {
    let locationPoint: LocationPoint
    var coordinate: CLLocationCoordinate2D
    var title: String?
    var subtitle: String?

    init(point: LocationPoint, index: Int, total: Int) {
        self.locationPoint = point
        self.coordinate = CLLocationCoordinate2D(latitude: point.latitude, longitude: point.longitude)
        self.title = point.formattedTime

        let speedKmh = Int(point.speed * 3.6)
        let src = point.source.lowercased().contains("gps") ? "GPS" : "Sensor"
        self.subtitle = "\(src) · \(speedKmh) km/h · #\(index + 1)/\(total)"
    }
}

class DailyRouteMapViewController: UIViewController {

    var dayLocations: [LocationPoint] = []
    var dateString: String = ""
    var totalPoints: Int = 0

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

    private let dateLabel    = UILabel()
    private let pointsLabel  = UILabel()
    private let timeRangeLabel = UILabel()

    override func viewDidLoad() {
        super.viewDidLoad()
        overrideUserInterfaceStyle = .light
        title = "Daily Locations"
        view.backgroundColor = .white
        configureNavigationBar()

        let locationButton = UIBarButtonItem(
            image: UIImage(systemName: "location.fill"),
            style: .plain, target: self,
            action: #selector(currentLocationTapped)
        )
        // tintColor inherited from nav bar
        navigationItem.rightBarButtonItem = locationButton

        mapView.delegate = self          // must be set BEFORE any addOverlay call
        mapView.showsUserLocation = true
        MapAppearanceHelper.applyTimeBasedAppearance(to: mapView)
        setupUI()
    }

    override func viewDidAppear(_ animated: Bool) {
        super.viewDidAppear(animated)
        displayRoute()
    }

    override func viewDidDisappear(_ animated: Bool) {
        super.viewDidDisappear(animated)
        mapView.removeOverlays(mapView.overlays)
        let nonUserAnnotations = mapView.annotations.filter { !($0 is MKUserLocation) }
        mapView.removeAnnotations(nonUserAnnotations)
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
        mapView.showsUserLocation = true
        if let loc = mapView.userLocation.location {
            mapView.setRegion(MKCoordinateRegion(center: loc.coordinate,
                latitudinalMeters: 500, longitudinalMeters: 500), animated: true)
        }
    }

    private func setupUI() {
        view.addSubview(mapView)
        view.addSubview(infoView)

        [dateLabel, pointsLabel, timeRangeLabel].forEach {
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
            infoView.heightAnchor.constraint(equalToConstant: 90),

            dateLabel.topAnchor.constraint(equalTo: infoView.topAnchor, constant: 12),
            dateLabel.leadingAnchor.constraint(equalTo: infoView.leadingAnchor, constant: 16),
            dateLabel.trailingAnchor.constraint(equalTo: infoView.trailingAnchor, constant: -16),

            pointsLabel.topAnchor.constraint(equalTo: dateLabel.bottomAnchor, constant: 6),
            pointsLabel.leadingAnchor.constraint(equalTo: infoView.leadingAnchor, constant: 16),

            timeRangeLabel.topAnchor.constraint(equalTo: dateLabel.bottomAnchor, constant: 6),
            timeRangeLabel.trailingAnchor.constraint(equalTo: infoView.trailingAnchor, constant: -16),
        ])

        // Date
        let fmt = DateFormatter()
        fmt.dateFormat = "yyyy-MM-dd"
        if let d = fmt.date(from: dateString) {
            fmt.dateFormat = "EEEE, MMMM d, yyyy"
            dateLabel.text = fmt.string(from: d)
        } else { dateLabel.text = dateString }

        // pointsLabel filled after route is built in displayRoute()
        if let first = dayLocations.first, let last = dayLocations.last {
            timeRangeLabel.text = "⏰ \(first.formattedTime) – \(last.formattedTime)"
        }
    }

    // MARK: - Route display

    /// Raw GPS polyline — shown instantly, removed when road-snap completes.
    private var rawPolyline: MKPolyline?

    private func displayRoute() {
        guard !dayLocations.isEmpty else { return }

        // ── Filter: GPS only, accuracy ≤ 50 m, dedup by second, sort ────────
        var seenSec = Set<Int64>()
        let prefiltered: [LocationPoint] = dayLocations
            .filter { lp in
                guard lp.source.lowercased().contains("gps") else { return false }
                guard lp.accuracy <= 50 || lp.accuracy <= 0  else { return false }
                return seenSec.insert(lp.timestamp / 1000).inserted
            }
            .sorted { $0.timestamp < $1.timestamp }

        // ── Reject outliers: implied speed > 40 m/s ──────────────────────
        var gpsPoints: [LocationPoint] = []
        for lp in prefiltered {
            if let prev = gpsPoints.last {
                let dt = Double(lp.timestamp - prev.timestamp) / 1000.0
                if dt > 0 {
                    let dist = CLLocation(latitude: prev.latitude, longitude: prev.longitude)
                        .distance(from: CLLocation(latitude: lp.latitude, longitude: lp.longitude))
                    if dist / dt > 40.0 { continue }
                }
            }
            gpsPoints.append(lp)
        }

        guard gpsPoints.count >= 2 else {
            pointsLabel.text = "⚠️ Not enough GPS points to draw route"
            return
        }

        // ── Info bar ──────────────────────────────────────────────────────
        let sensorCount = dayLocations.filter { $0.source.lowercased().contains("sensor") }.count
        pointsLabel.text = "🛰 \(gpsPoints.count) GPS · 📱 \(sensorCount) Sensor  (\(dayLocations.count) raw)"

        // ── Start / End pins ──────────────────────────────────────────────
        let startPin        = MKPointAnnotation()
        startPin.coordinate = CLLocationCoordinate2D(latitude: gpsPoints.first!.latitude,
                                                     longitude: gpsPoints.first!.longitude)
        startPin.title      = "🌅 Day Start"
        startPin.subtitle   = gpsPoints.first!.formattedTime
        mapView.addAnnotation(startPin)

        let endPin          = MKPointAnnotation()
        endPin.coordinate   = CLLocationCoordinate2D(latitude: gpsPoints.last!.latitude,
                                                     longitude: gpsPoints.last!.longitude)
        endPin.title        = "🏁 Day End"
        endPin.subtitle     = gpsPoints.last!.formattedTime
        mapView.addAnnotation(endPin)

        // ── Fit map to GPS points immediately ─────────────────────────────
        let coords = gpsPoints.map { CLLocationCoordinate2D(latitude: $0.latitude, longitude: $0.longitude) }
        fitMap(to: coords)

        // ── Step 1: Draw raw GPS polyline INSTANTLY ──
        var rawCoords = coords
        let rawPoly = MKPolyline(coordinates: &rawCoords, count: rawCoords.count)
        rawPolyline = rawPoly
        mapView.addOverlay(rawPoly, level: .aboveRoads)

        // ── Step 2: Road-snap with sampled waypoints in background ──
        // Sample every Nth point → ~15 segments max instead of N-1 requests
        let sampleStep = max(1, gpsPoints.count / 15)
        var sampled: [LocationPoint] = []
        for i in stride(from: 0, to: gpsPoints.count, by: sampleStep) {
            sampled.append(gpsPoints[i])
        }
        if sampled.last?.timestamp != gpsPoints.last?.timestamp {
            sampled.append(gpsPoints.last!)
        }

        guard sampled.count >= 2 else { return }

        let pairs = zip(sampled, sampled.dropFirst()).map { ($0, $1) }
        snapSequentially(pairs: Array(pairs), index: 0)
    }

    // Fires one MKDirections request per sampled pair.
    // Removes raw polyline on first result.
    private func snapSequentially(
        pairs: [(LocationPoint, LocationPoint)],
        index: Int
    ) {
        guard index < pairs.count else { return }

        let (from, to) = pairs[index]
        let req = MKDirections.Request()
        req.source                  = MKMapItem(placemark: MKPlacemark(coordinate:
                                        CLLocationCoordinate2D(latitude: from.latitude, longitude: from.longitude)))
        req.destination             = MKMapItem(placemark: MKPlacemark(coordinate:
                                        CLLocationCoordinate2D(latitude: to.latitude,   longitude: to.longitude)))
        req.transportType           = RouteTransportType.currentMKType
        req.requestsAlternateRoutes = false

        MKDirections(request: req).calculate { [weak self] response, error in
            guard let self = self else { return }

            var poly: MKPolyline
            if let route = response?.routes.first {
                poly = MKPolyline(points: route.polyline.points(), count: route.polyline.pointCount)
            } else {
                var coords = [
                    CLLocationCoordinate2D(latitude: from.latitude, longitude: from.longitude),
                    CLLocationCoordinate2D(latitude: to.latitude,   longitude: to.longitude)
                ]
                poly = MKPolyline(coordinates: &coords, count: 2)
            }

            DispatchQueue.main.async {
                // Remove raw polyline on first road-snapped result
                if let raw = self.rawPolyline {
                    self.mapView.removeOverlay(raw)
                    self.rawPolyline = nil
                }
                self.mapView.addOverlay(poly, level: .aboveRoads)
            }

            DispatchQueue.global().asyncAfter(deadline: .now() + 0.2) {
                self.snapSequentially(pairs: pairs, index: index + 1)
            }
        }
    }

    private func fitMap(to coords: [CLLocationCoordinate2D]) {
        guard !coords.isEmpty else { return }
        if coords.count == 1 {
            mapView.setRegion(MKCoordinateRegion(center: coords[0],
                latitudinalMeters: 500, longitudinalMeters: 500), animated: true)
            return
        }
        let lats = coords.map { $0.latitude };  let lngs = coords.map { $0.longitude }
        let center = CLLocationCoordinate2D(
            latitude:  (lats.min()! + lats.max()!) / 2,
            longitude: (lngs.min()! + lngs.max()!) / 2)
        let span = MKCoordinateSpan(
            latitudeDelta:  (lats.max()! - lats.min()!) * 1.4 + 0.002,
            longitudeDelta: (lngs.max()! - lngs.min()!) * 1.4 + 0.002)
        mapView.setRegion(MKCoordinateRegion(center: center, span: span), animated: true)
    }
}

// MARK: - MKMapViewDelegate

extension DailyRouteMapViewController: MKMapViewDelegate {

    func mapView(_ mapView: MKMapView, rendererFor overlay: MKOverlay) -> MKOverlayRenderer {
        if let poly = overlay as? MKPolyline {
            let r = MKPolylineRenderer(polyline: poly)
            r.strokeColor = UIColor.systemBlue
            r.lineWidth   = 4
            r.lineCap     = .round
            r.lineJoin    = .round
            return r
        }
        return MKOverlayRenderer(overlay: overlay)
    }

    func mapView(_ mapView: MKMapView, viewFor annotation: MKAnnotation) -> MKAnnotationView? {
        guard let locAnnotation = annotation as? LocationAnnotation else { return nil }

        let id = "POIPin"
        let view = (mapView.dequeueReusableAnnotationView(withIdentifier: id) as? MKMarkerAnnotationView)
            ?? MKMarkerAnnotationView(annotation: annotation, reuseIdentifier: id)

        view.annotation       = annotation
        view.canShowCallout   = true
        view.displayPriority  = .required  // show all pins, no clustering

        let pt = locAnnotation.locationPoint
        let src = pt.source.uppercased()
        let idx = dayLocations.firstIndex(where: { $0.timestamp == pt.timestamp }) ?? -1

        // First / last markers take priority
        if idx == 0 {
            view.markerTintColor = .systemYellow
            view.glyphImage = UIImage(systemName: "flag.fill")
        } else if idx == dayLocations.count - 1 {
            view.markerTintColor = .systemOrange
            view.glyphImage = UIImage(systemName: "flag.checkered")
        } else if src.contains("GPS") {
            // Blue for GPS
            view.markerTintColor = .systemBlue
            view.glyphImage = UIImage(systemName: "location.fill")
        } else if src.contains("WIFI") || src.contains("WI-FI") {
            // Orange for WiFi
            view.markerTintColor = UIColor(red: 1.0, green: 0.6, blue: 0.0, alpha: 1.0)
            view.glyphImage = UIImage(systemName: "wifi")
        } else if src.contains("CELL") || src.contains("NETWORK") {
            // Red for Cell
            view.markerTintColor = .systemRed
            view.glyphImage = UIImage(systemName: "antenna.radiowaves.left.and.right")
        } else if src.contains("SENSOR") {
            // Green for Sensor
            view.markerTintColor = .systemGreen
            view.glyphImage = UIImage(systemName: "sensor.tag.radiowaves.forward.fill")
        } else {
            // Violet for Unknown
            view.markerTintColor = .systemPurple
            view.glyphImage = UIImage(systemName: "mappin")
        }

        // Detail callout: coords + accuracy
        let detail = UILabel()
        detail.font = .systemFont(ofSize: 12)
        detail.numberOfLines = 2
        detail.text = String(format: "%.6f, %.6f\nAccuracy: ±%.0fm",
                             pt.latitude, pt.longitude, pt.accuracy)
        view.detailCalloutAccessoryView = detail

        return view
    }
}
