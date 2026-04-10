//
//  TrackingSource.swift
//  TripTracker
//

import Foundation

// Two sources only:
//   .sensors → speed < 6 m/s (stationary, walking, device on table)
//   .gps     → speed >= 6 m/s (vehicle)
enum TrackingSource: String {
    case sensors = "Sensors"
    case gps     = "GPS"

    var displayName: String {
        switch self {
        case .sensors: return "📱 Sensors"
        case .gps:     return "🛰️ GPS"
        }
    }
}

enum MovementState {
    case stationary
    case slow
    case fast

    var displayName: String {
        switch self {
        case .stationary: return "⏸️ Standing Still"
        case .slow:       return "🚶 Walking"
        case .fast:       return "🚗 Vehicle"
        }
    }
}

// MARK: - Route Transport Type Setting
//
// Stored in UserDefaults as "tt_transportType" (Int):
//   0 = Car          → .automobile
//   1 = Motorbike    → .automobile (Apple has no motorcycle type)
//   2 = Bicycle      → .walking   (closest — avoids highways)
//   3 = Walking      → .walking

import MapKit

enum RouteTransportType {
    /// Read the user's chosen transport type from Settings.
    static var currentMKType: MKDirectionsTransportType {
        let index = UserDefaults.standard.integer(forKey: "tt_transportType")
        switch index {
        case 0:  return .automobile   // Car
        case 1:  return .automobile   // Motorbike (same roads as car)
        case 2:  return .walking      // Bicycle (closest to bike routes)
        case 3:  return .walking      // Walking
        default: return .automobile
        }
    }

    static var displayName: String {
        let index = UserDefaults.standard.integer(forKey: "tt_transportType")
        switch index {
        case 0:  return "🚗 Car"
        case 1:  return "🏍️ Motorbike"
        case 2:  return "🚲 Bicycle"
        case 3:  return "🚶 Walking"
        default: return "🚗 Car"
        }
    }
}

// MARK: - Time-Based Map Appearance
//
// Map shows dark tiles at night (7 PM – 6 AM), light tiles during the day.
// Independent of system dark/light mode — based on actual time of day.

import UIKit

enum MapAppearanceHelper {
    /// Apply day/night appearance to an MKMapView based on current hour.
    /// Night = 19:00–05:59 → dark map.  Day = 06:00–18:59 → light map.
    static func applyTimeBasedAppearance(to mapView: UIView) {
        let hour = Calendar.current.component(.hour, from: Date())
        let isNight = hour >= 19 || hour < 6
        mapView.overrideUserInterfaceStyle = isNight ? .dark : .light
    }

    /// Whether it's currently nighttime (for logging).
    static var isNight: Bool {
        let hour = Calendar.current.component(.hour, from: Date())
        return hour >= 19 || hour < 6
    }
}
