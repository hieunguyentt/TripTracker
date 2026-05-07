//
//  Location.swift
//  TripTracker
//

import Foundation
import CoreLocation

public struct LocationPoint {
    public let id: Int64
    public let tripId: Int64?
    public let latitude: Double
    public let longitude: Double
    public let altitude: Double
    public let accuracy: Float
    public let speed: Float
    public let bearing: Float
    public let timestamp: Int64
    public let source: String
    
    public init(id: Int64 = 0,
         tripId: Int64? = nil,
         latitude: Double,
         longitude: Double,
         altitude: Double = 0,
         accuracy: Float,
         speed: Float,
         bearing: Float = 0,
         timestamp: Int64,
         source: String) {
        self.id = id
        self.tripId = tripId
        self.latitude = latitude
        self.longitude = longitude
        self.altitude = altitude
        self.accuracy = accuracy
        self.speed = speed
        self.bearing = bearing
        self.timestamp = timestamp
        self.source = source
    }
    
    public init(from clLocation: CLLocation, source: TrackingSource) {
        self.id = 0
        self.tripId = nil
        self.latitude = clLocation.coordinate.latitude
        self.longitude = clLocation.coordinate.longitude
        self.altitude = clLocation.altitude
        self.accuracy = Float(clLocation.horizontalAccuracy)
        self.speed = Float(max(0, clLocation.speed))  // CLLocation.speed = -1 when invalid
        self.bearing = Float(clLocation.course)
        self.timestamp = Int64(clLocation.timestamp.timeIntervalSince1970 * 1000)
        self.source = source.rawValue
    }
    
    public func toCLLocation() -> CLLocation {
        let coordinate = CLLocationCoordinate2D(latitude: latitude, longitude: longitude)
        return CLLocation(coordinate: coordinate,
                         altitude: altitude,
                         horizontalAccuracy: CLLocationAccuracy(accuracy),
                         verticalAccuracy: -1,
                         course: CLLocationDirection(bearing),
                         speed: CLLocationSpeed(speed),
                         timestamp: Date(timeIntervalSince1970: Double(timestamp) / 1000.0))
    }
    
    public var formattedTime: String {
        let date = Date(timeIntervalSince1970: Double(timestamp) / 1000.0)
        let formatter = DateFormatter()
        formatter.dateFormat = "HH:mm:ss"
        return formatter.string(from: date)
    }
}
