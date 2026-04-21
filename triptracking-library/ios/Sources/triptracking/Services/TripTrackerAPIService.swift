import Foundation
import CoreLocation
import UIKit

// MARK: - API Configuration

public struct TripTrackerAPIConfig {
    public var pingURL: String = ""
    public var endURL: String = ""
    public var userId: String = ""
    public var vehicleId: String = ""       // Optional — can be empty
    public var osInfo: String = ""
    public var routeId: String = ""
    public var authorizationKey: String = ""
    public var apiAuthKey: String = ""        // Legacy — kept for backwards compat
    public var apiAuthToken: String = ""      // New header: api-auth-token

    public var isConfigured: Bool { !pingURL.isEmpty && !endURL.isEmpty && !userId.isEmpty }

    public init() { self.osInfo = "iOS \(UIDevice.current.systemVersion)" }

    public init(from dict: [String: Any]) {
        self.init()
        if let v = dict["pingURL"] as? String         { pingURL = v }
        if let v = dict["endURL"] as? String           { endURL = v }
        if let v = dict["userId"] as? String           { userId = v }
        if let v = dict["vehicleId"] as? String        { vehicleId = v }
        if let v = dict["osInfo"] as? String           { osInfo = v }
        if let v = dict["routeId"] as? String          { routeId = v }
        if let v = dict["authorizationKey"] as? String { authorizationKey = v }
        if let v = dict["apiAuthKey"] as? String       { apiAuthKey = v }
        if let v = dict["apiAuthToken"] as? String     { apiAuthToken = v }
    }
}

// MARK: - API Service

public final class TripTrackerAPIService {
    public static let shared = TripTrackerAPIService()
    private init() {}

    public var config = TripTrackerAPIConfig()
    public var isEnabled: Bool { config.isConfigured }

    /// Whether to include vehicle_Id in outgoing payloads.
    /// Automatically set to true on trip start, false on trip end.
    public var includeVehicleId: Bool = false

    private let session: URLSession = {
        let cfg = URLSessionConfiguration.default
        cfg.timeoutIntervalForRequest = 15
        return URLSession(configuration: cfg)
    }()

    // ── Update vehicle_id at any time (e.g. user switches vehicle) ──
    public func updateVehicleId(_ vehicleId: String) {
        config.vehicleId = vehicleId
        config.routeId = vehicleId
        print("📡 API vehicle_id updated → \(vehicleId)")
    }

    // ── Called on trip start to start including vehicle_id ──
    public func onTripStart() {
        includeVehicleId = true
    }

    // ── Called on trip end to stop including vehicle_id ──
    public func onTripEnd() {
        includeVehicleId = false
    }

    // POST /ping/v2
    public func sendPing(location: CLLocation, isMoving: Bool, speed: Float, activityType: String, routeId: String? = nil) {
        if(isEnabled) {
            print("📡 TripTracker Sending ping for location: \(location.coordinate.latitude),\(location.coordinate.longitude)")
        }else{
            print("📡 Ping NOT sent because API config is incomplete")
        }
        var body: [String: Any] = [
            "user_Id": config.userId,
            "os_Info": config.osInfo,
            "location": [[
                "is_Moving": isMoving,
                "timestamp": ISO8601DateFormatter().string(from: Date()),
                "latitude": location.coordinate.latitude,
                "longitude": location.coordinate.longitude,
                "speed": speed,
                "activityType": activityType,
            ]]
        ]
        // Only include vehicle_Id during active trip and if configured
        if includeVehicleId && !config.vehicleId.isEmpty {
            body["vehicle_Id"] = config.vehicleId
            body["route_Id"] = routeId ?? config.routeId
        }
        post(url: config.pingURL, body: body) { ok in
            print("📡 API ping \(ok ? "OK" : "FAIL"): \(location.coordinate.latitude),\(location.coordinate.longitude)")
        }
    }

    // POST /ping/v2 batch
    public func sendPingBatch(locations: [(CLLocation, Bool, Float, String, Date)], routeId: String? = nil) {
        if(isEnabled) {
            print("📡 TripTracker Sending batch ping for \(locations.count) locations")
        } else {
            print("📡 TripTracker Batch ping NOT sent because API config is incomplete")
        }
        guard isEnabled, !locations.isEmpty else { return }
        let fmt = ISO8601DateFormatter()
        let arr: [[String: Any]] = locations.map { loc, moving, spd, activity, ts in
            ["is_Moving": moving, "timestamp": fmt.string(from: ts),
             "latitude": loc.coordinate.latitude, "longitude": loc.coordinate.longitude,
             "speed": spd, "activityType": activity, "route_Id": routeId ?? config.routeId]
        }
        var body: [String: Any] = ["user_Id": config.userId, "os_Info": config.osInfo, "location": arr]
        if includeVehicleId && !config.vehicleId.isEmpty {
            body["vehicle_Id"] = config.vehicleId
        }
        post(url: config.pingURL, body: body) { ok in
            print("📡 API batch (\(locations.count)): \(ok ? "OK" : "FAIL")")
        }
    }

    // POST /end — vehicle_id NOT included after trip end
    public func sendTripEnd(location: CLLocation) {
        if(isEnabled) {
            print("📡 TripTracker Sending trip end for location: \(location.coordinate.latitude),\(location.coordinate.longitude)")
        }else{
            print("📡 Trip end NOT sent because API config is incomplete")
        }
        let body: [String: Any] = [
            "user_Id": config.userId,
            "timestamp": ISO8601DateFormatter().string(from: Date()),
            "latitude": location.coordinate.latitude,
            "longitude": location.coordinate.longitude
        ]
        post(url: config.endURL, body: body) { [weak self] ok in
            print("📡 API trip-end \(ok ? "OK" : "FAIL")")
            // Stop including vehicle_id after trip end
            self?.includeVehicleId = false
            if !ok {
                DispatchQueue.global().asyncAfter(deadline: .now() + 5) {
                    self?.post(url: self?.config.endURL ?? "", body: body, completion: nil)
                }
            }
        }
    }

    public func setRouteId(_ id: String) { config.routeId = id }

    private func post(url: String, body: [String: Any], completion: ((Bool) -> Void)?) {
        guard let url = URL(string: url) else { completion?(false); return }
        var req = URLRequest(url: url)
        req.httpMethod = "POST"
        req.setValue("application/json", forHTTPHeaderField: "Content-Type")
        if !config.authorizationKey.isEmpty { req.setValue(config.authorizationKey, forHTTPHeaderField: "AuthorizationKey") }
        if !config.apiAuthKey.isEmpty { req.setValue(config.apiAuthKey, forHTTPHeaderField: "api-auth-key") }
        if !config.apiAuthToken.isEmpty { req.setValue(config.apiAuthToken, forHTTPHeaderField: "api-auth-token") }
        do { req.httpBody = try JSONSerialization.data(withJSONObject: body) } catch { completion?(false); return }
        session.dataTask(with: req) { data, response, error in
            let code = (response as? HTTPURLResponse)?.statusCode ?? 0
            completion?((200...299).contains(code))
        }.resume()
    }
}
