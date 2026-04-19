//
//  HistoryViewController.swift
//  TripTracker
//

import UIKit
import MapKit

public class HistoryViewController: UIViewController {
    
    private let tableView: UITableView = {
        let table = UITableView()
        table.translatesAutoresizingMaskIntoConstraints = false
        table.register(TripCell.self, forCellReuseIdentifier: "TripCell")
        return table
    }()
    
    private var trips: [Trip] = []
    
    public override func viewDidLoad() {
        super.viewDidLoad()
        overrideUserInterfaceStyle = .light
        
        title = "Trip History"
        view.backgroundColor = .white
        
        // Configure navigation bar appearance
        configureNavigationBar()
        
        setupUI()
        loadTrips()
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
    
    public override func viewWillAppear(_ animated: Bool) {
        super.viewWillAppear(animated)
        loadTrips() // Reload when coming back
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
    
    private func loadTrips() {
        trips = DatabaseManager.shared.getAllTrips()
        tableView.reloadData()
    }
    
    private func showTripOnMap(trip: Trip) {
        let locations = DatabaseManager.shared.getLocationsForTrip(tripId: trip.id)
        
        guard !locations.isEmpty else {
            showAlert(title: "No Data", message: "This trip has no location data.")
            return
        }
        
        // Filter to GPS/Sensor points only for clean route
        let filteredLocations = locations.filter { location in
            let source = location.source.lowercased()
            return (source.contains("gps") || source.contains("sensor")) && location.accuracy <= 50
        }
        
        guard filteredLocations.count >= 2 else {
            showAlert(title: "Insufficient Data", message: "Need at least 2 GPS/Sensor points to draw route.")
            return
        }
        
        // Create and show map view controller
        let mapVC = TripMapViewController()
        mapVC.tripLocations = filteredLocations
        mapVC.tripInfo = trip
        navigationController?.pushViewController(mapVC, animated: true)
    }
    
    private func showAlert(title: String, message: String) {
        let alert = UIAlertController(title: title, message: message, preferredStyle: .alert)
        alert.addAction(UIAlertAction(title: "OK", style: .default))
        present(alert, animated: true)
    }
}

extension HistoryViewController: UITableViewDelegate, UITableViewDataSource {
    
    public func tableView(_ tableView: UITableView, numberOfRowsInSection section: Int) -> Int {
        return trips.count
    }
    
    public func tableView(_ tableView: UITableView, cellForRowAt indexPath: IndexPath) -> UITableViewCell {
        let cell = tableView.dequeueReusableCell(withIdentifier: "TripCell", for: indexPath) as! TripCell
        cell.configure(with: trips[indexPath.row])
        return cell
    }
    
    public func tableView(_ tableView: UITableView, heightForRowAt indexPath: IndexPath) -> CGFloat {
        return 80
    }
    
    public func tableView(_ tableView: UITableView, didSelectRowAt indexPath: IndexPath) {
        tableView.deselectRow(at: indexPath, animated: true)
        let trip = trips[indexPath.row]
        showTripOnMap(trip: trip)
    }
}

public class TripCell: UITableViewCell {
    
    private let dateLabel = UILabel()
    private let distanceLabel = UILabel()
    private let durationLabel = UILabel()
    private let statusBadge = UILabel()
    
    override init(style: UITableViewCell.CellStyle, reuseIdentifier: String?) {
        super.init(style: style, reuseIdentifier: reuseIdentifier)
        
        [dateLabel, distanceLabel, durationLabel, statusBadge].forEach {
            $0.translatesAutoresizingMaskIntoConstraints = false
            contentView.addSubview($0)
        }
        
        dateLabel.font = .systemFont(ofSize: 16, weight: .semibold)
        distanceLabel.font = .systemFont(ofSize: 14)
        durationLabel.font = .systemFont(ofSize: 14)
        distanceLabel.textColor = .gray
        durationLabel.textColor = .gray
        
        statusBadge.font = .systemFont(ofSize: 12, weight: .bold)
        statusBadge.textAlignment = .center
        statusBadge.layer.cornerRadius = 4
        statusBadge.layer.masksToBounds = true
        
        NSLayoutConstraint.activate([
            statusBadge.topAnchor.constraint(equalTo: contentView.topAnchor, constant: 10),
            statusBadge.trailingAnchor.constraint(equalTo: contentView.trailingAnchor, constant: -15),
            statusBadge.widthAnchor.constraint(equalToConstant: 80),
            statusBadge.heightAnchor.constraint(equalToConstant: 24),
            
            dateLabel.topAnchor.constraint(equalTo: contentView.topAnchor, constant: 10),
            dateLabel.leadingAnchor.constraint(equalTo: contentView.leadingAnchor, constant: 15),
            dateLabel.trailingAnchor.constraint(equalTo: statusBadge.leadingAnchor, constant: -10),
            
            distanceLabel.topAnchor.constraint(equalTo: dateLabel.bottomAnchor, constant: 5),
            distanceLabel.leadingAnchor.constraint(equalTo: contentView.leadingAnchor, constant: 15),
            
            durationLabel.topAnchor.constraint(equalTo: dateLabel.bottomAnchor, constant: 5),
            durationLabel.leadingAnchor.constraint(equalTo: distanceLabel.trailingAnchor, constant: 15)
        ])
        
        accessoryType = .disclosureIndicator
    }
    
    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }
    
    public func configure(with trip: Trip) {
        dateLabel.text = trip.formattedStartTime
        distanceLabel.text = "📏 \(trip.formattedDistance)"
        durationLabel.text = "⏱️ \(trip.formattedDuration)"
        
        if trip.status == "active" {
            statusBadge.text = "Active"
            statusBadge.backgroundColor = UIColor.systemGreen
            statusBadge.textColor = .white
        } else {
            statusBadge.text = "Completed"
            statusBadge.backgroundColor = UIColor.systemGray
            statusBadge.textColor = .white
        }
    }
}
