//
//  GeofenceZone.swift
//  TripTracker
//
//  Model for a geofence zone with enter/exit notifications and auto-stop.
//

import Foundation
import CoreLocation

struct GeofenceZone: Codable {
    let id: String              // UUID
    var name: String            // e.g. "Home", "Office"
    var latitude: Double
    var longitude: Double
    var radius: Double          // metres (50–1000)
    var notifyOnEnter: Bool
    var notifyOnExit: Bool
    var autoStopOnEnter: Bool   // auto-end trip when entering this zone

    var coordinate: CLLocationCoordinate2D {
        CLLocationCoordinate2D(latitude: latitude, longitude: longitude)
    }

    var region: CLCircularRegion {
        let r = CLCircularRegion(center: coordinate, radius: radius, identifier: id)
        r.notifyOnEntry = notifyOnEnter
        r.notifyOnExit  = notifyOnExit
        return r
    }

    init(name: String, latitude: Double, longitude: Double,
         radius: Double = 200, notifyOnEnter: Bool = true,
         notifyOnExit: Bool = true, autoStopOnEnter: Bool = false) {
        self.id              = UUID().uuidString
        self.name            = name
        self.latitude        = latitude
        self.longitude       = longitude
        self.radius          = radius
        self.notifyOnEnter   = notifyOnEnter
        self.notifyOnExit    = notifyOnExit
        self.autoStopOnEnter = autoStopOnEnter
    }
}
