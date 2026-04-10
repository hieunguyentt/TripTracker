//
//  Trip.swift
//  TripTracker
//

import Foundation

struct Trip {
    let id: Int64
    let startTime: Int64
    var endTime: Int64
    var distance: Double
    var duration: Int64
    var steps: Int
    var status: String
    
    init(id: Int64,
         startTime: Int64,
         endTime: Int64 = 0,
         distance: Double = 0,
         duration: Int64 = 0,
         steps: Int = 0,
         status: String = "active") {
        self.id = id
        self.startTime = startTime
        self.endTime = endTime
        self.distance = distance
        self.duration = duration
        self.steps = steps
        self.status = status
    }
    
    var formattedStartTime: String {
        let date = Date(timeIntervalSince1970: Double(startTime) / 1000.0)
        let formatter = DateFormatter()
        formatter.dateFormat = "yyyy-MM-dd HH:mm:ss"
        return formatter.string(from: date)
    }
    
    var formattedDistance: String {
        if distance < 1000 {
            return String(format: "%.0f m", distance)
        } else {
            return String(format: "%.2f km", distance / 1000)
        }
    }
    
    var formattedDuration: String {
        let minutes = duration / 60
        let seconds = duration % 60
        return String(format: "%02d:%02d", minutes, seconds)
    }
}
