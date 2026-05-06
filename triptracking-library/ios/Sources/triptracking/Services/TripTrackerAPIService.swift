import Foundation
import CoreLocation
import UIKit
import Network

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
    private init() {
        loadPendingQueue()
        startNetworkMonitor()
    }

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

    // ═══════════════════════════════════════════════════════════════
    // Retry Queue — persists failed requests to disk, resends on network
    // ═══════════════════════════════════════════════════════════════

    private var pendingQueue: [[String: Any]] = []  // [{url, body}]
    private let queueLock = NSLock()
    private let maxQueueSize = 500
    private var isFlushing = false

    private var queueFileURL: URL? {
        FileManager.default.urls(for: .cachesDirectory, in: .userDomainMask)
            .first?.appendingPathComponent("triptracker_pending_api.json")
    }

    private func loadPendingQueue() {
        guard let url = queueFileURL,
              let data = try? Data(contentsOf: url),
              let arr = try? JSONSerialization.jsonObject(with: data) as? [[String: Any]] else { return }
        pendingQueue = arr
        print("📡  TripTracker API queue loaded: \(arr.count) pending requests")
    }

    private func savePendingQueue() {
        guard let url = queueFileURL else { return }
        queueLock.lock()
        defer { queueLock.unlock() }
        if let data = try? JSONSerialization.data(withJSONObject: pendingQueue) {
            try? data.write(to: url)
        }
    }

    private func enqueue(url: String, body: [String: Any]) {
        queueLock.lock()
        pendingQueue.append(["url": url, "body": body, "ts": Date().timeIntervalSince1970])
        // Trim oldest if over limit
        if pendingQueue.count > maxQueueSize {
            pendingQueue.removeFirst(pendingQueue.count - maxQueueSize)
        }
        queueLock.unlock()
        savePendingQueue()
        print("📡  TripTracker API queued (total: \(pendingQueue.count)) — will retry when online")
    }

    /// Flush all pending requests. Called when network becomes available.
    public func flushQueue() {
        guard !isFlushing else { return }
        queueLock.lock()
        let items = pendingQueue
        queueLock.unlock()
        guard !items.isEmpty else { return }

        isFlushing = true
        print("📡  TripTracker API flushing \(items.count) pending requests…")

        DispatchQueue.global(qos: .utility).async { [weak self] in
            var successCount = 0
            for item in items {
                guard let urlStr = item["url"] as? String,
                      let body = item["body"] as? [String: Any] else { continue }

                let ok = self?.postSync(url: urlStr, body: body) ?? false
                if ok {
                    successCount += 1
                    // Remove from queue
                    self?.queueLock.lock()
                    if let idx = self?.pendingQueue.firstIndex(where: { ($0["ts"] as? Double) == (item["ts"] as? Double) }) {
                        self?.pendingQueue.remove(at: idx)
                    }
                    self?.queueLock.unlock()
                } else {
                    // Still offline — stop flushing
                    break
                }
            }
            self?.savePendingQueue()
            self?.isFlushing = false
            let remaining = self?.pendingQueue.count ?? 0
            print("📡  TripTracker API flush done: \(successCount) sent, \(remaining) remaining")
        }
    }

    /// Number of pending requests in queue
    public var pendingCount: Int { pendingQueue.count }

    // ═══════════════════════════════════════════════════════════════
    // Network Monitor — auto-flush when connectivity returns
    // ═══════════════════════════════════════════════════════════════

    private var networkMonitor: Any?  // NWPathMonitor (stored as Any to avoid import issues)

    private func startNetworkMonitor() {
        if #available(iOS 12.0, *) {
            let monitor = NWPathMonitor()
            monitor.pathUpdateHandler = { [weak self] path in
                if path.status == .satisfied && (self?.pendingQueue.isEmpty == false) {
                    print("📡  TripTracker API network restored — flushing pending queue")
                    self?.flushQueue()
                }
            }
            monitor.start(queue: DispatchQueue.global(qos: .utility))
            networkMonitor = monitor
        }
    }

    // ═══════════════════════════════════════════════════════════════
    // Public API
    // ═══════════════════════════════════════════════════════════════

    public func updateVehicleId(_ vehicleId: String) {
        config.vehicleId = vehicleId
        config.routeId = vehicleId
        print("📡  TripTracker API vehicle_id updated → \(vehicleId)")
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
            print("📡 TripTracker Ping NOT sent because API config is incomplete")
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
                "route_Id": includeVehicleId ? routeId ?? config.vehicleId : ""
                
            ]]
        ]
        print("📡  TripTracker API ping route: \(body) (vehicleId included: \(includeVehicleId))")
        
        // Only include vehicle_Id during active trip and if configured
        if includeVehicleId && !config.vehicleId.isEmpty {
            body["vehicle_Id"] = config.vehicleId
        }
        post(url: config.pingURL, body: body) { ok in
            print("📡 TripTrackerAPI ping \(ok ? "OK" : "FAIL"): \(location.coordinate.latitude),\(location.coordinate.longitude)")
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
             "speed": spd, "activityType": activity, "route_Id": includeVehicleId ? routeId ?? config.vehicleId : ""]
        }
        print("📡  TripTracker API ping route: \(includeVehicleId ? routeId ?? config.vehicleId : "") (vehicleId included: \(includeVehicleId))")
        var body: [String: Any] = ["user_Id": config.userId, "os_Info": config.osInfo, "location": arr]
        if includeVehicleId && !config.vehicleId.isEmpty {
            body["vehicle_Id"] = config.vehicleId
        }
        post(url: config.pingURL, body: body) { ok in
            print("📡  TripTracker API batch (\(locations.count)): \(ok ? "OK" : "FAIL")")
        }
    }

    // POST /end — vehicle_id NOT included after trip end
    public func sendTripEnd(location: CLLocation) {
        if(isEnabled) {
            print("📡 TripTracker Sending trip end for location: \(location.coordinate.latitude),\(location.coordinate.longitude)")
        }else{
            print("📡 TripTracker Trip end NOT sent because API config is incomplete")
        }
        let body: [String: Any] = [
            "user_Id": config.userId,
            "timestamp": ISO8601DateFormatter().string(from: Date()),
            "latitude": location.coordinate.latitude,
            "longitude": location.coordinate.longitude
        ]
        post(url: config.endURL, body: body) { [weak self] ok in
            print("📡 TripTracker API trip-end \(ok ? "OK" : "FAIL")")
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

    // ═══════════════════════════════════════════════════════════════
    // HTTP — post with automatic retry queue on failure
    // ═══════════════════════════════════════════════════════════════

    private func postWithRetry(url: String, body: [String: Any], completion: ((Bool) -> Void)?) {
        post(url: url, body: body) { [weak self] ok in
            if !ok {
                self?.enqueue(url: url, body: body)
            } else if self?.pendingQueue.isEmpty == false {
                // Success — try flushing pending queue too
                self?.flushQueue()
            }
            completion?(ok)
        }
    }

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

    /// Synchronous POST — used by flush queue on background thread
    private func postSync(url urlStr: String, body: [String: Any]) -> Bool {
        guard let url = URL(string: urlStr) else { return false }
        var req = URLRequest(url: url)
        req.httpMethod = "POST"
        req.setValue("application/json", forHTTPHeaderField: "Content-Type")
        if !config.authorizationKey.isEmpty { req.setValue(config.authorizationKey, forHTTPHeaderField: "AuthorizationKey") }
        if !config.apiAuthKey.isEmpty { req.setValue(config.apiAuthKey, forHTTPHeaderField: "api-auth-key") }
        if !config.apiAuthToken.isEmpty { req.setValue(config.apiAuthToken, forHTTPHeaderField: "api-auth-token") }
        guard let httpBody = try? JSONSerialization.data(withJSONObject: body) else { return false }
        req.httpBody = httpBody

        let sem = DispatchSemaphore(value: 0)
        var success = false
        session.dataTask(with: req) { _, response, _ in
            let code = (response as? HTTPURLResponse)?.statusCode ?? 0
            success = (200...299).contains(code)
            sem.signal()
        }.resume()
        sem.wait()
        return success
    }
}
