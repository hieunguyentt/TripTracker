//
//  RouteDrawingAlgorithm.swift
//  TripTracker
//
//  GPS + Sensor fusion pipeline for drawing accurate routes.
//
//  TWO MODES:
//
//  buildSegments()             — Trip / live route (dense points, ~30m apart)
//    Pipeline: dedup → source filter → accuracy filter → outlier reject
//              → min-distance gate → Douglas-Peucker → Catmull-Rom smooth
//
//  buildSegmentsForDailyView() — Daily Locations (sparse points, ~5 min apart)
//    Pipeline: dedup → source filter → accuracy filter → outlier reject
//              → NO Douglas-Peucker (already very few points)
//              → connect all kept points in timestamp order (no MKDirections)
//              → fallback straight-line if Directions fails
//

import Foundation
import CoreLocation
import MapKit

// MARK: - Result types

struct RoutePoint {
    let coordinate: CLLocationCoordinate2D
    let source: TrackingSource
    let timestamp: Int64
    let speed: Float
    let accuracy: Float
}

struct RouteSegment {
    let polyline: MKPolyline
    let source: TrackingSource

    var color: UIColor {
        switch source {
        case .gps:     return UIColor.systemBlue
        case .sensors: return UIColor.systemGreen
        }
    }
}

// MARK: - Tagged polylines

final class GPSPolyline:    MKPolyline {}
final class SensorPolyline: MKPolyline {}

// MARK: - RouteDrawingAlgorithm

struct RouteDrawingAlgorithm {

    // ─── Parameters ───────────────────────────────────────────────────────

    static let maxAccuracyMetres:      Float  = 50.0
    static let minPointDistanceMetres: Double = 8.0
    static let dpEpsilonMetres:        Double = 3.0
    static let maxPlausibleSpeedMs:    Double = 40.0
    static let enableSmoothing:        Bool   = true
    static let smoothingSubdivisions:  Int    = 4

    // ─── Trip / live route entry point ────────────────────────────────────
    //  Dense points (~30 m apart). Full pipeline including Douglas-Peucker.

    static func buildSegments(from raw: [LocationPoint]) -> [RouteSegment] {
        let pts = process(raw)
        guard pts.count >= 2 else { return [] }
        return buildPolylineSegments(from: pts)
    }

    static func process(_ raw: [LocationPoint]) -> [RoutePoint] {
        var pts = deduplicatePoints(raw)
        pts = filterGPSOnly(pts)           // GPS coords only — sensor dead-reckoning drifts
        pts = filterAccuracy(pts)
        pts = rejectOutliers(pts)          // drop teleport jumps > 40 m/s
        pts = enforceMinDistance(pts)      // collapse points closer than 8 m
        pts = douglasPeucker(pts, epsilon: dpEpsilonMetres)
        return pts
    }

    // ─── Daily Locations entry point ──────────────────────────────────────
    //  No MKDirections — connects points directly in timestamp order.

    static func buildSegmentsForDailyView(from raw: [LocationPoint]) -> [RouteSegment] {
        var pts = deduplicatePoints(raw)
        pts = filterSources(pts)
        pts = filterAccuracy(pts)
        pts = rejectOutliers(pts)
        pts = enforceMinDistance(pts, minDist: 15.0)
        guard pts.count >= 2 else { return [] }
        return buildPolylineSegments(from: pts)
    }

    // ─── Pipeline steps ───────────────────────────────────────────────────

    static func deduplicatePoints(_ points: [LocationPoint]) -> [RoutePoint] {
        var seen = Set<Int64>()
        return points.compactMap { lp -> RoutePoint? in
            let sec = lp.timestamp / 1000
            guard seen.insert(sec).inserted else { return nil }
            let src: TrackingSource = lp.source.lowercased().contains("gps") ? .gps : .sensors
            return RoutePoint(
                coordinate: CLLocationCoordinate2D(latitude: lp.latitude, longitude: lp.longitude),
                source:     src,
                timestamp:  lp.timestamp,
                speed:      lp.speed,
                accuracy:   lp.accuracy
            )
        }
    }

    static func filterSources(_ points: [RoutePoint]) -> [RoutePoint] {
        points.filter { $0.source == .gps || $0.source == .sensors }
    }

    // GPS-only filter: used for trip history routes where sensor dead-reckoning
    // coordinates drift significantly and should not be drawn on the map.
    static func filterGPSOnly(_ points: [RoutePoint]) -> [RoutePoint] {
        points.filter { $0.source == .gps }
    }

    static func filterAccuracy(_ points: [RoutePoint]) -> [RoutePoint] {
        points.filter { $0.accuracy <= maxAccuracyMetres || $0.accuracy <= 0 }
    }

    static func rejectOutliers(_ points: [RoutePoint]) -> [RoutePoint] {
        guard points.count > 1 else { return points }
        var kept: [RoutePoint] = [points[0]]
        for pt in points.dropFirst() {
            let prev = kept.last!
            let dt = Double(pt.timestamp - prev.timestamp) / 1000.0
            guard dt > 0 else { continue }
            let dist = distance(from: prev.coordinate, to: pt.coordinate)
            let impliedSpeed = dist / dt
            if impliedSpeed <= maxPlausibleSpeedMs {
                kept.append(pt)
            } else {
                print("🚫 RouteAlgo: rejected outlier — implied \(String(format:"%.1f", impliedSpeed)) m/s")
            }
        }
        return kept
    }

    static func enforceMinDistance(_ points: [RoutePoint], minDist: Double? = nil) -> [RoutePoint] {
        let threshold = minDist ?? minPointDistanceMetres
        guard points.count > 1 else { return points }
        var kept: [RoutePoint] = [points[0]]
        for pt in points.dropFirst() {
            if distance(from: kept.last!.coordinate, to: pt.coordinate) >= threshold {
                kept.append(pt)
            }
        }
        return kept
    }

    static func douglasPeucker(_ points: [RoutePoint], epsilon: Double) -> [RoutePoint] {
        guard points.count > 2 else { return points }
        var maxDist = 0.0
        var maxIdx  = 0
        let first = points.first!.coordinate
        let last  = points.last!.coordinate
        for i in 1..<(points.count - 1) {
            let d = perpendicularDistance(from: points[i].coordinate, lineStart: first, lineEnd: last)
            if d > maxDist { maxDist = d; maxIdx = i }
        }
        if maxDist > epsilon {
            let left  = douglasPeucker(Array(points[0...maxIdx]),   epsilon: epsilon)
            let right = douglasPeucker(Array(points[maxIdx...]),    epsilon: epsilon)
            return Array(left.dropLast()) + right
        }
        return [points.first!, points.last!]
    }

    static func smoothWithCatmullRom(_ points: [RoutePoint]) -> [CLLocationCoordinate2D] {
        guard enableSmoothing, points.count >= 2 else { return points.map(\.coordinate) }
        var result: [CLLocationCoordinate2D] = []
        let n = points.count
        for i in 0..<(n - 1) {
            let p0 = points[max(0, i - 1)].coordinate
            let p1 = points[i].coordinate
            let p2 = points[i + 1].coordinate
            let p3 = points[min(n - 1, i + 2)].coordinate
            result.append(p1)
            for step in 1...smoothingSubdivisions {
                let t = Double(step) / Double(smoothingSubdivisions + 1)
                let lat = catmullRom(p0.latitude,  p1.latitude,  p2.latitude,  p3.latitude,  t: t)
                let lng = catmullRom(p0.longitude, p1.longitude, p2.longitude, p3.longitude, t: t)
                result.append(CLLocationCoordinate2D(latitude: lat, longitude: lng))
            }
        }
        if let last = points.last?.coordinate { result.append(last) }
        return result
    }

    static func buildPolylineSegments(from points: [RoutePoint]) -> [RouteSegment] {
        guard points.count >= 2 else { return [] }
        var segments: [RouteSegment] = []
        var groupStart = 0
        var currentSource = points[0].source

        func flush(to endIdx: Int) {
            let slice = Array(points[groupStart...endIdx])
            guard slice.count >= 2 else { return }
            let coords = smoothWithCatmullRom(slice)
            let poly: MKPolyline
            switch currentSource {
            case .gps:     poly = GPSPolyline(coordinates:    coords, count: coords.count)
            case .sensors: poly = SensorPolyline(coordinates: coords, count: coords.count)
            }
            segments.append(RouteSegment(polyline: poly, source: currentSource))
        }

        for i in 1..<points.count {
            if points[i].source != currentSource {
                flush(to: i - 1)
                groupStart    = i - 1
                currentSource = points[i].source
            }
        }
        flush(to: points.count - 1)
        return segments
    }

    // ─── MapKit renderer helper ───────────────────────────────────────────

    static func renderer(for overlay: MKOverlay, lineWidth: CGFloat = 4.0) -> MKOverlayRenderer? {
        if let poly = overlay as? GPSPolyline {
            let r = MKPolylineRenderer(polyline: poly)
            r.strokeColor = UIColor.systemBlue
            r.lineWidth   = lineWidth
            r.lineCap     = .round
            r.lineJoin    = .round
            return r
        }
        if let poly = overlay as? SensorPolyline {
            let r = MKPolylineRenderer(polyline: poly)
            r.strokeColor = UIColor.systemGreen
            r.lineWidth   = lineWidth
            r.lineCap     = .round
            r.lineJoin    = .round
            return r
        }
        return nil
    }

    // ─── Geometry helpers ─────────────────────────────────────────────────

    static func distance(from a: CLLocationCoordinate2D, to b: CLLocationCoordinate2D) -> Double {
        CLLocation(latitude: a.latitude, longitude: a.longitude)
            .distance(from: CLLocation(latitude: b.latitude, longitude: b.longitude))
    }

    private static func perpendicularDistance(from point: CLLocationCoordinate2D,
                                               lineStart: CLLocationCoordinate2D,
                                               lineEnd:   CLLocationCoordinate2D) -> Double {
        let dx = lineEnd.longitude - lineStart.longitude
        let dy = lineEnd.latitude  - lineStart.latitude
        let len2 = dx*dx + dy*dy
        if len2 == 0 { return distance(from: point, to: lineStart) }
        let t = ((point.longitude - lineStart.longitude) * dx +
                 (point.latitude  - lineStart.latitude)  * dy) / len2
        let projLat = lineStart.latitude  + t * dy
        let projLng = lineStart.longitude + t * dx
        return distance(from: point, to: CLLocationCoordinate2D(latitude: projLat, longitude: projLng))
    }

    private static func catmullRom(_ p0: Double, _ p1: Double,
                                    _ p2: Double, _ p3: Double, t: Double) -> Double {
        let t2 = t * t, t3 = t2 * t
        return 0.5 * ((2*p1) + (-p0 + p2)*t + (2*p0 - 5*p1 + 4*p2 - p3)*t2 + (-p0 + 3*p1 - 3*p2 + p3)*t3)
    }
}
