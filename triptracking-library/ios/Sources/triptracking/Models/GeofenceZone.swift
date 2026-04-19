//
//  GeofenceZone.swift
//  TripTracker
//
//  Model for a geofence zone with enter/exit notifications and auto-stop.
//

import Foundation
import CoreLocation

public struct GeofenceZone: Codable {
    public let id: String              // UUID
    public var name: String            // e.g. "Home", "Office"
    public var latitude: Double
    public var longitude: Double
    public var radius: Double          // metres (50–1000)
    public var notifyOnEnter: Bool
    public var notifyOnExit: Bool
    public var autoStopOnEnter: Bool   // auto-end trip when entering this zone

    public var coordinate: CLLocationCoordinate2D {
        CLLocationCoordinate2D(latitude: latitude, longitude: longitude)
    }

    public var region: CLCircularRegion {
        let r = CLCircularRegion(center: coordinate, radius: radius, identifier: id)
        r.notifyOnEntry = notifyOnEnter
        r.notifyOnExit  = notifyOnExit
        return r
    }

    public init(name: String, latitude: Double, longitude: Double,
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
