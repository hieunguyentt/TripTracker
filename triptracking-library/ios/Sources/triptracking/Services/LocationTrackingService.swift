//
//  LocationTrackingService.swift
//  TripTracker
//
//  THREE-TIER TRACKING RULE:
//
//    State = Still / on table    speed < 0.5 m/s   →  source = Sensors
//    State = Walking / slow      0.5 ≤ speed < 6   →  source = Sensors
//    State = Vehicle             speed ≥ 6 m/s     →  source = GPS
//
//  AUTO-TRIP:
//    Auto-start:  speed ≥ 6 m/s OR CMMotionActivity = automotive
//    Auto-end:    speed stays below 6 m/s for autoEndStillnessSecs (default 5 min)
//
//  SAVE FREQUENCY:
//    still / on table  →  every 15 minutes (timer-based, 900 s)
//    walking / slow    →  every 1 minute   (timer-based, 60 s)
//    vehicle           →  every 30 metres  (distance-based, no timer)
//
//  GPS role:
//    1. Calibrate sensor dead-reckoning baseline when accuracy <= 50 m
//    2. Save location when speed >= 6 m/s and device has moved >= 30 m
//
//  Sensors role:
//    1. CMMotionActivity + accelerometer detect movement / stillness
//    2. CMPedometer estimates walking speed
//    3. Dead-reckoning projects new coordinates when walking
//    4. Periodic timer saves position when still or walking
//
//  Network (WiFi / Cell) is NOT used for positioning.
//

import Foundation
import CoreLocation
import CoreMotion
import UIKit

protocol AutoTripDelegate: AnyObject {
    /// Called when auto-trip starts a new trip.
    func autoTripDidStart(tripId: Int64)
    /// Called when auto-trip ends a trip after prolonged stillness.
    func autoTripDidEnd(tripId: Int64, reason: String)
}

protocol LocationUpdateDelegate: AnyObject {
    func didUpdateLocation(_ location: LocationPoint, source: TrackingSource, totalDistance: Double)
    func didUpdateStats(speed: Float, distance: Double, duration: Int64)
    func didChangeTrackingState(isTracking: Bool)
}

public class LocationTrackingService: NSObject {

    public static let shared = LocationTrackingService()

    // MARK: - Delegates
    weak var delegate: LocationUpdateDelegate?

    // MARK: - Core managers
    public let locationManager: CLLocationManager = CLLocationManager()
    
    /// Exposed for GeofenceManager to register region monitoring on this
    /// CLLocationManager — the one with "Always" auth + background modes.
    public var regionLocationManager: CLLocationManager { locationManager }
    private let motionManager   = CMMotionManager()
    private let pedometer       = CMPedometer()
    private let activityManager = CMMotionActivityManager()
    private let altimeter       = CMAltimeter()

    // MARK: - Tracking state
    public private(set) var isTracking       = false
    public private(set) var currentTripId: Int64 = -1
    private var tripStartTime: Date?
    private var totalDistance: Double = 0.0
    private var stepCount: Int        = 0

    // MARK: - Location state
    private var lastGPSLocation:      CLLocation?   // latest raw GPS fix
    private var lastSensorLocation:   CLLocation?   // latest dead-reckoned position
    public var lastKnownLocation:    CLLocation?   // best position available — exposed so UI can read it without creating a new CLLocationManager
    private var lastSavedGPSLocation: CLLocation?   // last GPS point actually persisted
     /// Last location that was actually sent to API — used for 80m distance gate
    private var lastPingedLocation: CLLocation?
    public private(set) var currentSource: TrackingSource = .sensors

    /// Convenience accessor for the fake-route injector in MainViewController.
    public var lastKnownCoordinate: CLLocationCoordinate2D? { lastKnownLocation?.coordinate }
    /// Expose running distance total for fake-route UI feedback.
    public var currentTotalDistance: Double { totalDistance }

    /// When true, real GPS fixes are ignored — only fake injected locations are processed.
    /// Set by MainViewController when a fake route simulation is running.
    public var isFakeRouteActive: Bool = false
    public var appTerminated: Bool = false

    /// Still timeout: after being still for this long (no trip), stop GPS completely.
    /// GPS will restart when CMMotionActivity detects movement.
    /// Default: 5 minutes (300 seconds)
    private let stillGpsTimeoutSecs: TimeInterval = 300
    private var stillGpsTimer: Timer?

    /// Internal flag: true during injectFakeGPS() so didUpdateLocations knows it's fake.
    private var isProcessingFakeGPS: Bool = false

    // MARK: - Sensor fusion state
    private var sensorHeadingDeg:      Double = 0.0
    private var currentAccelMagnitude: Double = 0.0
    /// Public read-only access for UI display
    public var currentAccelerationMagnitude: Double { currentAccelMagnitude }
    private var isMovingByActivity:    Bool   = false
    /// true when CMMotionActivity reports walking / running / cycling (not still, not automotive)
    private var isSlowMoving:          Bool   = false
    private var lastMotionState:       MotionState = .unknown
    private var lastSensorUpdateTime:  Date   = .distantPast
    private var sensorEstimatedSpeed:  Double = 0.0
    private var lastStepCount:         Int    = 0
    private var lastStepTime:          Date   = .distantPast

    // MARK: - Speed / GPS staleness
    private var lastGPSSpeed:      Float = 0.0
    private var lastGPSUpdateTime: Date  = .distantPast

    /// Consecutive GPS fixes at vehicle speed. Must reach threshold before auto-start.
    private var consecutiveVehicleSpeedCount: Int = 0
    /// Number of consecutive vehicle-speed readings required to auto-start a trip.
    private let requiredConsecutiveVehicleFixes: Int = 2

    // Speed thresholds — internal so SettingsViewController can read/write
    public var vehicleThreshold:    Float = 3.0 {  // m/s — at or above → GPS saves
        didSet { print("⚙️ TripTracker vehicleThreshold updated → \(vehicleThreshold) m/s") }
    }
    public var stationaryThreshold: Float = 0.5 {  // m/s — below → device is still / on table
        didSet { print("⚙️ TripTracker stationaryThreshold updated → \(stationaryThreshold) m/s") }
    }

    // GPS staleness window
    private let gpsStaleSecs: Double = 3.0   // speed holds steady for 3s after last GPS fix
    private let gpsDeadSecs:  Double = 10.0  // speed forced to 0 after 10s of GPS silence

    /// One-shot timer that fires exactly at gpsDeadSecs after the last GPS fix.
    /// Immediately starts the auto-end countdown without waiting for the periodic tick.
    private var gpsSilenceTimer: Timer?

    // MARK: - Save intervals — internal so SettingsViewController can read/write
    /// 5-minute interval used when device is still / on table.
    public var saveIntervalStillMs:  Int64  = 900_000 {  // 15 min default
        didSet {
            print("⚙️ TripTracker saveIntervalStillMs updated → \(saveIntervalStillMs) ms (\(saveIntervalStillMs/1000)s)")
            startPeriodicSaveTimer()
        }
    }
    /// 1-minute interval used when moving slowly (< 6 m/s).
    public var saveIntervalSlowMs:   Int64  = 60_000 {
        didSet {
            print("⚙️ TripTracker saveIntervalSlowMs updated → \(saveIntervalSlowMs) ms (\(saveIntervalSlowMs/1000)s)")
            startPeriodicSaveTimer()
        }
    }
    /// Convenience accessor kept for SettingsViewController compatibility (maps to still interval).
    public var saveIntervalMs: Int64 {
        get { saveIntervalStillMs }
        set { saveIntervalStillMs = newValue }
    }
    public var saveDistanceVehicleM: Double = 30.0    // GPS: save every 80 m at vehicle speed

    // MARK: - Auto Trip (always enabled)
    //
    //  Auto-start: speed >= vehicleThreshold (6 m/s) OR CMMotionActivity = automotive
    //  Auto-end:   effective speed == 0 for autoEndStillnessSecs (default 300s = 5 min)
    //
    //  No toggle — auto-trip is the only mode. Manual start/stop buttons removed.

    /// Duration in seconds the device must report speed == 0 before auto-ending a trip.
    /// Default: 300 s (5 minutes).
    public var autoEndStillnessSecs: Double = 300.0 {
        didSet {
            print("⚙️ TripTracker autoEndStillnessSecs updated → \(autoEndStillnessSecs)s")
            UserDefaults.standard.set(autoEndStillnessSecs, forKey: "tt_autoEndStillnessSecs")
        }
    }

    /// Timer that fires when speed has been 0 for autoEndStillnessSecs.
    private var autoEndTimer: Timer?

    /// Timer that turn on location service
    private var autoEnsureServiceTimer: Timer?

    /// Timestamp when the speed last dropped to 0 (for countdown UI).
    private(set) var stillSinceDate: Date?

    /// Delegate for auto-trip lifecycle events so the UI can react.
    weak var autoTripDelegate: AutoTripDelegate?

    private var lastLocationSaveTime: Int64 = 0
    private var lastGPSSaveTime:      Date  = .distantPast
    /// Timestamp (truncated to the second) of the last point we actually persisted.
    /// Any save call with the same second-level timestamp is dropped as a duplicate.
    private var lastPersistedTimestampSec: Int64 = 0

    // MARK: - Timers / background task
    private var periodicTimer:  Timer?
    private var backgroundTask: UIBackgroundTaskIdentifier = .invalid

    // MARK: - Motion state

    enum MotionState: String {
        case unknown    = "Unknown"
        case still      = "Still"       // device on table / stationary
        case walking    = "Walking"
        case running    = "Running"
        case cycling    = "Cycling"
        case automotive = "Automotive"  // speed >= 6 m/s → GPS
    }

    // MARK: - Init

    private override init() {
        super.init()
        loadPersistedSettings()
        setupLocationManager()
        setupMotionManager()
    }

    private func loadPersistedSettings() {
        let ud = UserDefaults.standard
        if ud.object(forKey: "tt_vehicleThreshold")     != nil { vehicleThreshold    = ud.float(forKey: "tt_vehicleThreshold") }
        if ud.object(forKey: "tt_saveIntervalSecs")     != nil { saveIntervalStillMs = Int64(ud.double(forKey: "tt_saveIntervalSecs") * 1000) }
        if ud.object(forKey: "tt_saveIntervalSlowSecs") != nil { saveIntervalSlowMs  = Int64(ud.double(forKey: "tt_saveIntervalSlowSecs") * 1000) }
        if ud.object(forKey: "tt_saveDistanceVehicleM") != nil { saveDistanceVehicleM = ud.double(forKey: "tt_saveDistanceVehicleM") }
        // Auto-end stillness timeout
        if ud.object(forKey: "tt_autoEndStillnessSecs") != nil { autoEndStillnessSecs = ud.double(forKey: "tt_autoEndStillnessSecs") }
    }
    // MARK: - Setup

    private func setupLocationManager() {
        locationManager.delegate                           = self
        // Start in still mode — adaptLocationAccuracy() upgrades to Best
        // automatically when motion is detected. This prevents the GPS from
        // firing every second while the device is sitting on a table.
        locationManager.desiredAccuracy                    = kCLLocationAccuracyBest
        locationManager.distanceFilter                     = 10.0
        locationManager.allowsBackgroundLocationUpdates    = true
        locationManager.pausesLocationUpdatesAutomatically = false
        locationManager.showsBackgroundLocationIndicator   = false
        locationManager.requestAlwaysAuthorization()
    }

    private func setupMotionManager() {
        if motionManager.isAccelerometerAvailable {
            motionManager.accelerometerUpdateInterval = 0.1
        }
        if motionManager.isDeviceMotionAvailable {
            motionManager.deviceMotionUpdateInterval = 0.1
        }
    }

    // Adjust GPS polling rate based on motion state to save battery.
    //
    //  still      → 100 m filter + reduced accuracy — GPS wakes only on large drift
    //  walking    → 10 m filter + NearestTenMeters
    //  vehicle    → no filter + Best — maximum resolution for road tracking
    //
    // Must be called on the main thread (CLLocationManager is not thread-safe).
    private func adaptLocationAccuracy(for state: MotionState) {
        guard Thread.isMainThread else {
            DispatchQueue.main.async { self.adaptLocationAccuracy(for: state) }
            return
        }

        // ⚠️ CRITICAL: NEVER call stopUpdatingLocation().
        // GPS must always be running (even at low accuracy) so iOS keeps the
        // app alive in background. Stopping GPS = iOS kills the app.

        switch state {
        case .still, .unknown:
            print("TripTracker GPS State: \(UIApplication.shared.applicationState)")
            print("TripTracker GPS State: \(appTerminated ? "App is terminated" : "App is not terminated")")

            if isTracking {
                // ACTIVE TRIP: Keep GPS at Best accuracy — need continuous speed readings
                // for trip tracking and auto-end timer. Don't downgrade even if CMMotionActivity
                // briefly reports .still (red light, slow traffic, etc.)
                locationManager.desiredAccuracy = kCLLocationAccuracyBest
                locationManager.distanceFilter  = kCLDistanceFilterNone
                locationManager.startUpdatingLocation()
                print("📡 TripTracker GPS BEST — still during active trip (keeping full accuracy)")
            } else if appTerminated {
                // TERMINATED RELAUNCH + NO TRIP: Stop GPS to save battery.
                // Significant location changes (~500m) + visits will relaunch app.
                locationManager.stopUpdatingLocation()
                locationManager.startMonitoringSignificantLocationChanges()
                locationManager.startMonitoringVisits()
                lastGPSLocation = nil
                print("📡 TripTracker GPS STOPPED — still/no trip/terminated (significant changes + visits will relaunch)")
            } else {
                // FOREGROUND/BACKGROUND + NO TRIP + STILL:
                // Keep GPS at low-power — don't stop.
                // CMMotionActivity will upgrade to Best when automotive detected.
                locationManager.startUpdatingLocation()
                locationManager.startMonitoringSignificantLocationChanges()
                locationManager.startMonitoringVisits()
                locationManager.showsBackgroundLocationIndicator   = false
                print("📡 TripTracker GPS LOW-POWER — still/no trip (ready for next trip)")

                // Start still timeout — if device stays still for 5 min, stop GPS completely
                // to save battery overnight. CMMotionActivity will restart GPS when movement detected.
                // stillGpsTimer?.invalidate()
                // stillGpsTimer = Timer.scheduledTimer(withTimeInterval: stillGpsTimeoutSecs, repeats: false) { [weak self] _ in
                //     guard let self = self, !self.isTracking else { return }
                //     self.locationManager.stopUpdatingLocation()
                //     self.lastGPSLocation = nil
                //     print("📡 TripTracker GPS STOPPED — still for \(Int(self.stillGpsTimeoutSecs / 60)) min, saving battery (CMMotionActivity still active)")
                // }
            }
        case .walking, .running, .cycling:
            // GPS active for pedestrian/cycling movement.
            stillGpsTimer?.invalidate()
            stillGpsTimer = nil
            locationManager.desiredAccuracy = kCLLocationAccuracyNearestTenMeters
            locationManager.distanceFilter  = 10.0
            locationManager.startUpdatingLocation()
            print("📡 TripTracker GPS ON → \(state.rawValue): accuracy=10m filter=10m (survives termination)")

        case .automotive:
            // Best accuracy for driving — GPS always alive
            stillGpsTimer?.invalidate()
            stillGpsTimer = nil
            locationManager.desiredAccuracy = kCLLocationAccuracyBest
            locationManager.distanceFilter  = kCLDistanceFilterNone
            locationManager.startUpdatingLocation()
            print("📡 TripTracker GPS ON → automotive: accuracy=Best filter=none")
        }
    }

    // MARK: - Public API

    public func startTerminalTracking() {
        // Start GPS — NEVER stops (keeps app alive in background)
        if isTracking {
                // ACTIVE TRIP: Keep GPS alive at minimal accuracy.
                // If we stop GPS → iOS suspends app → timers die → auto-end never fires
                // → miss all driving when user resumes.
                locationManager.desiredAccuracy = kCLLocationAccuracyBest
                locationManager.distanceFilter  = kCLDistanceFilterNone
                locationManager.startUpdatingLocation()
                print("📡 TripTracker GPS MINIMAL — still during active trip (keeping alive for auto-end timer)")
            } else {
                locationManager.stopUpdatingLocation()
                locationManager.startMonitoringSignificantLocationChanges()
                locationManager.startMonitoringVisits()
                lastGPSLocation = nil
            }
        print("✅ TripTracker Terminal tracking started (GPS always-on + significant changes + visits)")
    }

    public func startBackgroundTracking() {
        // Start GPS — NEVER stops (keeps app alive in background)
        locationManager.allowsBackgroundLocationUpdates = true
        locationManager.pausesLocationUpdatesAutomatically = false
        locationManager.startUpdatingLocation()
        locationManager.startMonitoringSignificantLocationChanges()
        locationManager.startMonitoringVisits()
        startPeriodicSaveTimer()
        startPedometer()
        startActivityMonitor()
        print("✅ TripTracker Background tracking started (GPS always-on + significant changes + visits)")

        // Send one initial ping with current GPS location when app opens
        // so server knows device position even before a trip starts
        // DispatchQueue.main.asyncAfter(deadline: .now() + 3.0) { [weak self] in
        //     guard let self = self else { return }
        //     if let loc = self.locationManager.location, loc.horizontalAccuracy <= 50 {
        //         let clLoc = loc
        //         let safeSpeed = max(0, Float(clLoc.speed))
        //         TripTrackerAPIService.shared.sendPing(
        //             location: clLoc,
        //             isMoving: safeSpeed > 0,
        //             speed: safeSpeed,
        //             activityType: "still"
        //         )
        //         print("📡 TripTracker Initial ping sent on app open — \(clLoc.coordinate.latitude),\(clLoc.coordinate.longitude)")
        //     }
        // }
    }

    public func startTrip(withInitialLocation initialLocation: CLLocation? = nil) {
        print("🎯 TripTracker Starting trip")
        isTracking           = true
        tripStartTime        = Date()
        totalDistance        = 0.0
        stepCount            = 0
        lastLocationSaveTime = 0
        lastPingedLocation   = nil  // Reset so first ping sends immediately

        currentTripId = DatabaseManager.shared.startTrip()
        print("💾 TripTracker Created trip: ID=\(currentTripId)")

        // API: mark trip start — vehicle_id will be included in pings
        TripTrackerAPIService.shared.onTripStart()

        // Force GPS to best accuracy for fresh fix
        locationManager.desiredAccuracy = kCLLocationAccuracyBest
        locationManager.distanceFilter  = kCLDistanceFilterNone
        locationManager.startUpdatingLocation()

        // Seed with initial location if provided, or wait for fresh GPS
        if let cached = locationManager.location,
                  cached.horizontalAccuracy > 0,
                  cached.horizontalAccuracy <= 50,
                  abs(cached.timestamp.timeIntervalSinceNow) < 10 {
            // Recent + accurate cached fix (less than 10 seconds old, accuracy ≤ 50m)
            lastGPSLocation    = cached
            lastSensorLocation = cached
            lastKnownLocation  = cached
            currentSource      = .gps

            let pt = LocationPoint(from: cached, source: .gps)
            persistIfNew(pt, source: .gps, tripId: currentTripId)
            delegate?.didUpdateLocation(pt, source: .gps, totalDistance: totalDistance)
            print("📍 Trip seeded with recent GPS: (\(cached.coordinate.latitude), \(cached.coordinate.longitude)) acc:\(Int(cached.horizontalAccuracy))m age:\(Int(-cached.timestamp.timeIntervalSinceNow))s")
        } else if let seed = initialLocation {
            // Caller provided a known-good location (e.g. from auto-start GPS fix)
            lastGPSLocation    = seed
            lastSensorLocation = seed
            lastKnownLocation  = seed
            currentSource      = .gps

            let pt = LocationPoint(from: seed, source: .gps)
            persistIfNew(pt, source: .gps, tripId: currentTripId)
            delegate?.didUpdateLocation(pt, source: .gps, totalDistance: totalDistance)
            print("📍 Trip seeded with provided location: (\(seed.coordinate.latitude), \(seed.coordinate.longitude)) acc:\(Int(seed.horizontalAccuracy))m")
        } 
        else {
            // No good fix available — wait for fresh GPS via didUpdateLocations
            print("📍 Trip started — waiting for fresh GPS fix (cached too old or inaccurate)")
        }

        //startSensorTracking()
        startPedometer()

        delegate?.didChangeTrackingState(isTracking: true)
        print("✅ TripTracker Trip started: ID=\(currentTripId)")
    }

    public func stopTrip() {
        guard isTracking else { return }
        print("🏁 TripTracker Stopping trip")

        // Cancel any pending auto-end timer
        resetAutoEndTimer()
        gpsSilenceTimer?.invalidate()
        gpsSilenceTimer = nil

        let duration = Int64(Date().timeIntervalSince(tripStartTime ?? Date()))
        // Only stop trip-specific sensors (pedometer, device motion).
        // Keep CMMotionActivity alive — it detects the NEXT trip start.
        stopSensorTracking()

        DatabaseManager.shared.endTrip(
            id: currentTripId,
            distance: totalDistance,
            duration: duration,
            steps: stepCount
        )

        // API: send final GPS location when trip ends (only if route_id is set)
        if let lastLoc = locationManager.location, !TripTrackerAPIService.shared.config.routeId.isEmpty {
            TripTrackerAPIService.shared.sendTripEnd(location: lastLoc)
        }

        isTracking    = false
        currentTripId = -1
        tripStartTime = nil

        delegate?.didChangeTrackingState(isTracking: false)
        print("✅ TripTracker Trip stopped — dist: \(totalDistance)m, dur: \(duration)s")

        // Stop GPS completely for 20s after trip end.
        // Prevents: residual speed → immediate auto-start, and saves battery briefly.
        // After 20s: switch to LOW-POWER GPS for fast next-trip detection.
        // locationManager.stopUpdatingLocation()
        // locationManager.startMonitoringSignificantLocationChanges()
        // locationManager.startMonitoringVisits()
        // lastGPSLocation = nil
        // print("📡 TripTracker GPS STOPPED — 20s cooldown after trip end")

        // DispatchQueue.main.asyncAfter(deadline: .now() + 20.0) { [weak self] in
        //     guard let self = self, !self.isTracking else { return }
            self.adaptLocationAccuracy(for: .still)
            // print("📡 TripTracker GPS resumed — cooldown complete, ready for next trip")
        // }
    }

    /// Called on app relaunch when an active trip is found in the DB.
    /// Restores tracking state without creating a new trip — continues saving
    /// to the same trip until the user taps Stop Tracking.
    public func resumeTrip(id: Int64, startTimeMs: Int64) {
        guard !isTracking else { return }
        print("♻️ TripTracker Resuming interrupted trip: ID=\(id)")

        isTracking    = true
        currentTripId = id
        tripStartTime = Date(timeIntervalSince1970: Double(startTimeMs) / 1000.0)

        // API: trip resumed — include vehicle_id in pings again
        TripTrackerAPIService.shared.onTripStart()

        // Seed location state from last known GPS fix
        if let loc = locationManager.location {
            lastGPSLocation    = loc
            lastSensorLocation = loc
            lastKnownLocation  = loc
        }

        // Restart all sensor / periodic save machinery
        startSensorTracking()
        startPedometer()
        startPeriodicSaveTimer()

        delegate?.didChangeTrackingState(isTracking: true)
        print("✅ TripTracker Trip resumed: ID=\(id) started=\(tripStartTime!)")

        // If device is currently still on resume, start the auto-end countdown.
        if lastMotionState == .still || lastMotionState == .unknown {
            DispatchQueue.main.asyncAfter(deadline: .now() + 2.0) { [weak self] in
                if self?.effectiveSpeed() ?? 0 <= 0 {
                    self?.startAutoEndTimer()
                }
            }
        }
    }

    public func turnOnServiceInTime(seconds: TimeInterval) {
        if autoEnsureServiceTimer != nil { return }
        autoEnsureServiceTimer?.invalidate()
        autoEnsureServiceTimer = Timer.scheduledTimer(withTimeInterval: seconds, repeats: false) { [weak self] _ in
            guard let self = self else { return }
            print("TripTracker turnOnServiceInTimer fired after \(Int(seconds))s — ensuring background tracking is active")
            self.ensureBackgroundTracking()
        }

        // Ensure timer fires even when the run loop is tracking scroll events
        if let timer = autoEnsureServiceTimer {
            RunLoop.main.add(timer, forMode: .common)
        }
    }

    public func ensureBackgroundTracking() {
        if !isTracking { startBackgroundTracking() }

        print("✅ TripTracker ensureBackgroundTracking — significant+visits registered, tracking=\(isTracking)")
    }

    public func ensureTerminalTracking() {
        if !isTracking { startTerminalTracking() }

        print("✅ TripTracker ensureTerminalTracking — significant+visits registered, tracking=\(isTracking)")
    }

    // MARK: - Terminated App Relaunch Handling
    //
    //  When iOS kills the app, all timers and motion updates stop.
    //  iOS relaunches the app on significant location changes (~500m cell tower change).
    //  On relaunch we check:
    //    1. Active trip with no location saved for > autoEndStillnessSecs → auto-end it
    //    2. No active trip but speed >= vehicleThreshold → auto-start one

    /// Called on app relaunch. Checks if an active trip should be auto-ended
    /// because no location was saved for longer than autoEndStillnessSecs.
    /// Returns true if the trip was auto-ended.
    @discardableResult
    public func checkAndAutoEndStaleTrip() -> Bool {
        guard let info = DatabaseManager.shared.getActiveTripInfo() else { return false }

        let lastTs = DatabaseManager.shared.getLastLocationTimestamp(tripId: info.id)
        let nowMs = Int64(Date().timeIntervalSince1970 * 1000)

        // Use the later of trip start time or last location timestamp
        let lastActivityMs = max(info.startTimeMs, lastTs ?? info.startTimeMs)
        let silentSecs = Double(nowMs - lastActivityMs) / 1000.0

        if silentSecs >= autoEndStillnessSecs {
            print("🤖 TripTracker Stale trip detected on relaunch — trip #\(info.id) silent for \(Int(silentSecs))s (threshold: \(Int(autoEndStillnessSecs))s)")

            // Resume the trip briefly so stopTrip() can finalize it
            if !isTracking {
                isTracking    = true
                currentTripId = info.id
                tripStartTime = Date(timeIntervalSince1970: Double(info.startTimeMs) / 1000.0)
            }

            // Calculate duration up to the last known activity, not now
            let duration = (lastActivityMs - info.startTimeMs) / 1000
            let distance = totalDistance

            stopTrip()

            // Send notification
            NotificationManager.shared.notifyTripEnded(
                tripId: info.id,
                reason: "No activity for \(Int(silentSecs / 60)) min (app was terminated)",
                distance: distance,
                duration: duration,
                vehicleId: TripTrackerAPIService.shared.config.vehicleId
            )

            DispatchQueue.main.async { [weak self] in
                self?.autoTripDelegate?.autoTripDidEnd(
                    tripId: info.id,
                    reason: "No activity for \(Int(silentSecs / 60)) min (app was terminated)"
                )
            }

            print("🤖 TripTracker Stale trip #\(info.id) auto-ended on relaunch")
            return true
        } else {
            print("♻️ TripTracker Active trip #\(info.id) still within timeout — silent \(Int(silentSecs))s < \(Int(autoEndStillnessSecs))s")
            return false
        }
    }

    /// Called when app is relaunched by a significant location change.
    /// If speed >= vehicleThreshold and no active trip, auto-start one.
    public func handleSignificantLocationRelaunch() {
        guard let location = locationManager.location else { return }
        let speed = Float(max(0, location.speed))

        print("📍 TripTracker Significant location change relaunch — speed: \(String(format:"%.1f", speed)) m/s")

        // Send a ping on every significant location change (even without trip)
        let pt = LocationPoint(from: location, source: .gps)
        sendAPIPing(location: pt, source: .gps, speed: speed)
        print("📍 TripTracker handleSignificantLocationRelaunch — speed: \(String(format:"%.1f", pt.speed)) m/s")

        // Save to cache database
        DatabaseManager.shared.saveCachedLocation(location: pt)
        lastKnownLocation = location
        persistLastGPSTimestamp()

        if speed >= vehicleThreshold && !isTracking {
            autoStartTrip(reason: "Significant location change (speed \(String(format:"%.1f", speed)) m/s)")
        }
    }

    /// Persist the last GPS fix timestamp so we can detect staleness even
    /// after the app is killed and relaunched with no active trip.
    private func persistLastGPSTimestamp() {
        UserDefaults.standard.set(Date().timeIntervalSince1970, forKey: "tt_lastGPSTimestamp")
    }

    public func getCurrentStats() -> (speed: Float, distance: Double, duration: Int64, steps: Int) {
        let dur = tripStartTime != nil ? Int64(Date().timeIntervalSince(tripStartTime!)) : 0
        return (effectiveSpeed(), totalDistance, dur, stepCount)
    }

    // MARK: - Effective speed (single source of truth)
    //
    // Decays smoothly to 0 when GPS goes silent so a stopped vehicle does not
    // keep the source stuck at GPS.

    private func effectiveSpeed() -> Float {
        guard lastGPSUpdateTime != .distantPast else { return 0 }
        let silenceSecs = Date().timeIntervalSince(lastGPSUpdateTime)

        if silenceSecs >= gpsDeadSecs {
            if lastGPSSpeed != 0 {
                print("⏱ TripTracker GPS silent \(Int(silenceSecs))s → speed reset to 0")
                lastGPSSpeed = 0
            }
            return 0
        }
        if silenceSecs <= gpsStaleSecs { return lastGPSSpeed }

        // Decay window: gpsStaleSecs … gpsDeadSecs
        let decay = Float(1.0 - (silenceSecs - gpsStaleSecs) / (gpsDeadSecs - gpsStaleSecs))
        return lastGPSSpeed * max(0, decay)
    }

    // MARK: - Source resolution — ONE rule used everywhere

    private func resolveSource(speed: Float) -> TrackingSource {
        return speed >= vehicleThreshold ? .gps : .sensors
    }

    // MARK: - Sensor tracking (dead reckoning)

    private func startSensorTracking() {
        guard motionManager.isDeviceMotionAvailable else {
            print("⚠️ TripTracker Device motion not available")
            return
        }
        motionManager.startDeviceMotionUpdates(
            using: .xMagneticNorthZVertical,
            to: OperationQueue()
        ) { [weak self] motion, _ in
            guard let self = self, let motion = motion else { return }
            self.handleDeviceMotion(motion)
        }
        if CMAltimeter.isRelativeAltitudeAvailable() {
            altimeter.startRelativeAltitudeUpdates(to: OperationQueue()) { _, _ in }
        }
    }

    /// Stop trip-specific sensors only (pedometer, device motion, altimeter).
    /// Keeps CMMotionActivity alive for detecting the next trip start.
    private func stopTripSensors() {
        motionManager.stopDeviceMotionUpdates()
        pedometer.stopUpdates()
        altimeter.stopRelativeAltitudeUpdates()
        print("🔋 TripTracker Trip sensors stopped — CMMotionActivity still active for next trip detection")
    }

    /// Stop ALL sensor tracking including CMMotionActivity.
    /// Only call when fully shutting down (e.g., user manually stops service).
    private func stopSensorTracking() {
        motionManager.stopDeviceMotionUpdates()
        pedometer.stopUpdates()
        activityManager.stopActivityUpdates()
        altimeter.stopRelativeAltitudeUpdates()
    }

    private func startPedometer() {
        guard CMPedometer.isStepCountingAvailable() else { return }
        pedometer.startUpdates(from: Date()) { [weak self] data, _ in
            guard let self = self, let data = data else { return }
            let newSteps = data.numberOfSteps.intValue
            self.updateSensorSpeed(newSteps: newSteps)
            self.stepCount = newSteps
        }
    }

    private func startActivityMonitor() {
        guard CMMotionActivityManager.isActivityAvailable() else { return }
        activityManager.startActivityUpdates(to: OperationQueue()) { [weak self] activity in
            guard let self = self, let activity = activity else { return }
            self.handleMotionActivity(activity)
        }
    }

    private func handleMotionActivity(_ activity: CMMotionActivity) {
        // Resolve new motion state
        let newState: MotionState
        if activity.automotive {
            newState = .automotive
        } else if activity.running {
            newState = .running
        } else if activity.cycling {
            newState = .cycling
        } else if activity.walking {
            newState = .walking
        } else if activity.stationary {
            newState = .still
        } else {
            // Unknown state — ignore to prevent Still→Unknown→Still spam.
            // CMMotionActivity often reports Unknown briefly between real states.
            // Treating Unknown as a transition causes redundant GPS mode switches.
            return
        }

        let wasMoving = isMovingByActivity
        isMovingByActivity = (newState == .walking || newState == .running
                              || newState == .cycling || newState == .automotive)
        // slow-moving: on foot or cycling but NOT automotive (vehicle handled by GPS)
        isSlowMoving = (newState == .walking || newState == .running || newState == .cycling)

        // Only act on a real state transition
        guard newState != lastMotionState else { return }
        let prevState = lastMotionState
        lastMotionState = newState

        print("🏃 TripTracker Motion changed: \(prevState.rawValue) → \(newState.rawValue)")

        DispatchQueue.main.async { [weak self] in
            guard let self = self else { return }
            self.adaptLocationAccuracy(for: newState)
            self.onMotionStateChanged(from: prevState, to: newState, wasMoving: wasMoving)
        }
    }

    private func onMotionStateChanged(from prev: MotionState, to next: MotionState, wasMoving: Bool) {
        // ── When transitioning TO automotive, start GPS and wait for fresh fix ──
        // GPS was likely stopped (still state). effectiveSpeed() is stale.
        // Don't save now — let didUpdateLocations handle it with real GPS speed.
        if next == .automotive && prev != .automotive {
            adaptLocationAccuracy(for: .automotive)  // GPS ON → best accuracy
            evaluateAutoTrip(from: prev, to: next)
            print("📍 Motion → Automotive: GPS started, waiting for fresh GPS speed")
            return  // Don't save with stale speed — didUpdateLocations will save with real speed
        }

        let speed = effectiveSpeed()

        // Source rule:
        //   still                          → always Sensors
        //   walking / running / cycling    → Sensors (speed < 6) or GPS (speed >= 6)
        //   automotive / unknown           → resolveSource by speed
        let source: TrackingSource
        switch next {
        case .still:
            source = .sensors                       // on table / stationary → always Sensors
        case .walking, .running, .cycling:
            source = speed >= vehicleThreshold ? .gps : .sensors
        default:
            source = resolveSource(speed: speed)    // automotive / unknown → speed decides
        }
        currentSource = source

        // ── Auto-trip evaluation ──
        evaluateAutoTrip(from: prev, to: next)

        // Only save on meaningful transitions
        let shouldSave: Bool
        switch (prev, next) {
        case (_, .still):                                        shouldSave = true  // just stopped
        case (.still, _) where next != .unknown:                 shouldSave = true  // just started
        case (.unknown, _) where next != .unknown:               shouldSave = true  // first fix
        default:                                                 shouldSave = (prev != .unknown && next != .unknown)
        }

        guard shouldSave else { return }

        let baseLoc: CLLocation?
        if source == .gps {
            baseLoc = lastGPSLocation ?? lastKnownLocation
        } else {
            // Prefer fresh GPS fix or CLLocationManager.location over stale sensor position
            if let gps = lastGPSLocation, abs(gps.timestamp.timeIntervalSinceNow) < 60 {
                baseLoc = gps
            } else if let clm = locationManager.location, abs(clm.timestamp.timeIntervalSinceNow) < 120 {
                baseLoc = clm
            } else {
                baseLoc = lastSensorLocation ?? lastKnownLocation
            }
        }
        guard let base = baseLoc else { return }

        let nowMs = Int64(Date().timeIntervalSince1970 * 1000)
        let pt = LocationPoint(
            tripId:    currentTripId != -1 ? currentTripId : nil,
            latitude:  base.coordinate.latitude,
            longitude: base.coordinate.longitude,
            altitude:  base.altitude,
            accuracy:  Float(base.horizontalAccuracy),
            speed:     speed,  // use effectiveSpeed(), not raw CLLocation.speed
            bearing:   Float(base.course >= 0 ? base.course : 0),
            timestamp: nowMs,
            source:    source.rawValue
        )

        lastPersistedTimestampSec = nowMs / 1000
        DatabaseManager.shared.saveCachedLocation(location: pt)
        if isTracking && currentTripId != -1 {
            DatabaseManager.shared.saveLocation(tripId: currentTripId, location: pt)
        }
        // API: ping on EVERY save (trip AND no trip)
        sendAPIPing(location: pt, source: source, speed: speed)
        print("📍 TripTracker onMotionStateChanged — speed: \(String(format:"%.1f", pt.speed)) m/s")
        delegate?.didUpdateLocation(pt, source: source, totalDistance: totalDistance)

        print("📍 TripTracker Motion-change save: \(prev.rawValue)→\(next.rawValue) src=\(source.rawValue) spd=\(String(format:"%.1f", speed))m/s")
    }

    private func handleDeviceMotion(_ motion: CMDeviceMotion) {
        // Update heading
        if motion.heading >= 0 { sensorHeadingDeg = motion.heading }

        // Update acceleration magnitude (used for stationary detection)
        let ua = motion.userAcceleration
        currentAccelMagnitude = sqrt(ua.x*ua.x + ua.y*ua.y + ua.z*ua.z)

        // Dead reckoning only at walking pace (< 6 m/s).
        // Vehicle speed is handled by GPS directly.
        let speed = effectiveSpeed()
        guard speed < vehicleThreshold,      // not a vehicle
              isMovingByActivity,            // CMMotionActivity confirms movement
              currentAccelMagnitude > 0.15,  // meaningful acceleration
              sensorEstimatedSpeed > 0.1,    // pedometer confirms walking
              let base = lastKnownLocation else { return }

        let now = Date()
        let dt  = now.timeIntervalSince(lastSensorUpdateTime)
        guard dt >= 1.0 else { return }   // apply at most every 1 s
        lastSensorUpdateTime = now

        let distMeters = sensorEstimatedSpeed * dt
        let projected  = projectLocation(from: base.coordinate,
                                         bearing: sensorHeadingDeg,
                                         distance: distMeters)

        let synth = CLLocation(
            coordinate:         projected,
            altitude:           base.altitude,
            horizontalAccuracy: 15.0,
            verticalAccuracy:   -1,
            course:             sensorHeadingDeg,
            speed:              sensorEstimatedSpeed,
            timestamp:          now
        )

        DispatchQueue.main.async { self.processSensorLocation(synth) }
    }

    private func updateSensorSpeed(newSteps: Int) {
        let now        = Date()
        let dt         = now.timeIntervalSince(lastStepTime)
        let deltaSteps = newSteps - lastStepCount

        if dt > 0 && deltaSteps > 0 {
            sensorEstimatedSpeed = (Double(deltaSteps) * 0.75) / dt  // stride ≈ 0.75 m
        } else if deltaSteps == 0 {
            sensorEstimatedSpeed = 0
        }
        lastStepCount = newSteps
        lastStepTime  = now
    }

    /// Haversine forward projection: origin + bearing + distance → new coordinate
    private func projectLocation(from origin: CLLocationCoordinate2D,
                                  bearing bearingDeg: Double,
                                  distance meters: Double) -> CLLocationCoordinate2D {
        let R  = 6_371_000.0
        let d  = meters / R
        let φ1 = origin.latitude  * .pi / 180
        let λ1 = origin.longitude * .pi / 180
        let θ  = bearingDeg       * .pi / 180
        let φ2 = asin(sin(φ1) * cos(d) + cos(φ1) * sin(d) * cos(θ))
        let λ2 = λ1 + atan2(sin(θ) * sin(d) * cos(φ1),
                             cos(d) - sin(φ1) * sin(φ2))
        return CLLocationCoordinate2D(latitude:  φ2 * 180 / .pi,
                                      longitude: λ2 * 180 / .pi)
    }

    private func processSensorLocation(_ location: CLLocation) {
        guard isTracking, currentTripId != -1 else { return }

        if let last = lastKnownLocation {
            let delta = location.distance(from: last)
            if delta > 0 && delta < 50 { totalDistance += delta }
        }
        lastSensorLocation = location
        lastKnownLocation  = location

        // Voice: check distance milestones
        VoiceFeedbackManager.shared.checkDistanceMilestone(totalDistance: totalDistance)

        if shouldSaveLocation(speed: Float(location.speed)) {
            let pt = LocationPoint(from: location, source: .sensors)
            if persistIfNew(pt, source: .sensors, tripId: currentTripId) {
                delegate?.didUpdateLocation(pt, source: .sensors, totalDistance: totalDistance)
            }
            print("📱 TripTracker Sensor DR saved — hdg:\(Int(sensorHeadingDeg))° spd:\(String(format:"%.2f", sensorEstimatedSpeed)) m/s")
        }

        if let start = tripStartTime {
            delegate?.didUpdateStats(speed: Float(location.speed),
                                     distance: totalDistance,
                                     duration: Int64(Date().timeIntervalSince(start)))
        }
    }

    // MARK: - Periodic Save Timer
    //
    // Fires every 60 seconds — the shortest possible save interval (slow-move).
    // Inside periodicSaveTick we apply the correct gate:
    //   still / unknown   → 5-minute interval (saveIntervalStillMs)
    //   slow move < 6 m/s → 1-minute interval (saveIntervalSlowMs)
    //   vehicle >= 6 m/s  → skipped here; GPS distance-gate handles saves.

    private func startPeriodicSaveTimer() {
        // Must run on main thread — Timer.scheduledTimer uses the current RunLoop.
        // If called from a background thread the timer silently never fires.
        if !Thread.isMainThread {
            DispatchQueue.main.async { self.startPeriodicSaveTimer() }
            return
        }
        periodicTimer?.invalidate()
        // Tick every 15 seconds for responsive auto-end detection.
        // Save intervals (1-min slow, 5-min still) are gated internally — this
        // only affects how quickly we detect speed dropping below threshold.
        let tickSecs: Double = 15.0
        let timer = Timer(timeInterval: tickSecs, repeats: true) { [weak self] _ in
            self?.periodicSaveTick()
        }
        RunLoop.main.add(timer, forMode: .common)
        periodicTimer = timer
    }

    private func periodicSaveTick() {

        let speed  = effectiveSpeed()
        let source = resolveSource(speed: speed)
        currentSource = source

        // ── Auto-end check: start timer as soon as speed < vehicleThreshold ──
        // This catches the case where GPS goes silent (no more didUpdateLocations
        // callbacks) and CMMotionActivity is slow to report .still.
        // The periodic timer fires every 60s, so the auto-end countdown starts
        // within 60s of speed dropping — not minutes later.
        if isTracking && speed < vehicleThreshold {
            startAutoEndTimer()   // no-op if already running
        } else if isTracking && speed >= vehicleThreshold {
            cancelAutoEndTimer()
        }

        // Vehicle speed: GPS distance-gate handles saves. Skip the timer.
        guard speed < vehicleThreshold else { return }

        // Choose interval: still/unknown → 15 min, slow-moving → 1 min
        let requiredIntervalMs: Int64 = isSlowMoving ? saveIntervalSlowMs : saveIntervalStillMs
        let nowMs = Int64(Date().timeIntervalSince1970 * 1000)
        guard nowMs - lastLocationSaveTime >= requiredIntervalMs else { return }
        lastLocationSaveTime = nowMs

        // Pick the FRESHEST location available — avoid sending stale cached positions.
        // Priority: latest GPS fix > CLLocationManager.location > sensor location
        let baseLoc: CLLocation?
        let freshGPS = lastGPSLocation
        let freshCLM = locationManager.location
        
        if source == .gps {
            baseLoc = freshGPS ?? freshCLM ?? lastKnownLocation
        } else {
            // For sensor source: prefer latest GPS fix if it's recent (< 60s old),
            // otherwise use CLLocationManager.location (always up-to-date).
            // NEVER use lastSensorLocation alone — it can be from a completely different area.
            if let gps = freshGPS, abs(gps.timestamp.timeIntervalSinceNow) < 60 {
                baseLoc = gps
            } else if let clm = freshCLM, abs(clm.timestamp.timeIntervalSinceNow) < 120 {
                baseLoc = clm
            } else {
                baseLoc = lastSensorLocation ?? lastKnownLocation
            }
        }
        guard let base = baseLoc else {
            print("⏰ TripTracker Periodic save skipped — no location available yet")
            return
        }

        // Stamp with the already-captured nowMs so the timestamp matches the gate check
        let pt = LocationPoint(
            tripId:    currentTripId != -1 ? currentTripId : nil,
            latitude:  base.coordinate.latitude,
            longitude: base.coordinate.longitude,
            altitude:  base.altitude,
            accuracy:  Float(base.horizontalAccuracy),
            speed:     speed,  // use effectiveSpeed(), not raw CLLocation.speed
            bearing:   Float(base.course >= 0 ? base.course : 0),
            timestamp: nowMs,
            source:    source.rawValue
        )

        // Force-save: bypass the per-second dedup because the interval gate already ran
        lastPersistedTimestampSec = nowMs / 1000
        DatabaseManager.shared.saveCachedLocation(location: pt)
        if isTracking && currentTripId != -1 {
            DatabaseManager.shared.saveLocation(tripId: currentTripId, location: pt)
        }
        // API: ping on EVERY save (trip AND no trip)
        sendAPIPing(location: pt, source: source, speed: speed)
        print("📍 TripTracker periodicSaveTick — speed: \(String(format:"%.1f", pt.speed)) m/s")
        delegate?.didUpdateLocation(pt, source: source, totalDistance: totalDistance)

        lastKnownLocation = base
        let label = isSlowMoving ? "slow(1min)" : "still(5min)"
        print("⏰ TripTracker Periodic save [\(label)]: (\(base.coordinate.latitude), \(base.coordinate.longitude)) source=\(source.rawValue) speed=\(String(format:"%.1f", speed)) m/s")
    }

    // MARK: - Auto Trip Logic
    //
    //  Auto-start:  speed >= vehicleThreshold (6 m/s) OR CMMotionActivity = automotive
    //  Auto-end:    speed stays below vehicleThreshold for autoEndStillnessSecs (10 min)
    //               GPS drift noise (0.5–2 m/s) does NOT cancel the countdown.
    //               Only real vehicle speed (>= 6 m/s) cancels it.
    //
    //  Always active — no toggle required.

    /// Called from onMotionStateChanged on every CMMotionActivity transition.
    private func evaluateAutoTrip(from prev: MotionState, to next: MotionState) {
        let speed = effectiveSpeed()

        switch next {
        case .automotive:
            // CMMotionActivity says vehicle → cancel auto-end, auto-start if needed

            // cancelAutoEndTimer()
            if !isTracking {
                //autoStartTrip(reason: "Automotive activity detected")
                autoStartTrip(reason: "Automotive activity detected")
                print("🚗 TripTracker Automotive detected — GPS enabled, waiting for speed confirmation")
            }

        case .walking, .running, .cycling:
            // Low-speed movement — NOT vehicle speed.
            // If trip is active, start auto-end countdown (same as still).
            // User walking/holding device after parking = trip should end.
            if isTracking {
                // startAutoEndTimer()
            }

        case .still:
            // Device is still → start auto-end countdown if trip is active
            if isTracking {
                startAutoEndTimer()
            }

        case .unknown:
            break
        }
    }

    /// Called from didUpdateLocations (GPS delegate) on every GPS fix.
    /// Handles speed-based auto-start and auto-end independently of CMMotionActivity.
    ///
    /// KEY RULE: Only speed >= vehicleThreshold (6 m/s) cancels the auto-end timer.
    /// GPS drift on a stationary device can produce phantom speeds of 0.5–2 m/s;
    /// these MUST NOT reset the countdown or the trip will never auto-end.
    private func evaluateAutoTripFromGPS(speed: Float) {
        if speed >= vehicleThreshold {
            //         // ── Vehicle speed detected ──
            //         // But is this GPS fix trustworthy? Reject if accuracy > 20m.
            //         let accuracy = lastGPSLocation?.horizontalAccuracy ?? 999
            //         if accuracy > 20 {
            //     print("⚠️ TripTracker Vehicle speed \(String(format:"%.1f", speed)) m/s IGNORED — poor accuracy \(Int(accuracy))m")
            //     consecutiveVehicleSpeedCount = 0
            //     return
            // }

            // consecutiveVehicleSpeedCount += 1

            // Cancel auto-end if already tracking
            cancelAutoEndTimer()

            if !isTracking {
                // if consecutiveVehicleSpeedCount >= requiredConsecutiveVehicleFixes {
                    autoStartTrip(reason: "GPS speed \(String(format:"%.1f", speed)) m/s (\(consecutiveVehicleSpeedCount) consecutive fixes)")
                    // consecutiveVehicleSpeedCount = 0
                // } else {
                    print("🚗 TripTracker Vehicle speed \(String(format:"%.1f", speed)) m/s — \(consecutiveVehicleSpeedCount)/\(requiredConsecutiveVehicleFixes) consecutive fixes, waiting...")
                // }
            }
        } else {
            // ── Below vehicle threshold ──
            // consecutiveVehicleSpeedCount = 0

            if isTracking && autoEndTimer == nil {
                // Speed dropped while trip active → start auto-end countdown.
                startAutoEndTimer()
            }
        }
        // If autoEndTimer is already running and speed < vehicleThreshold → let it run.
        // Only real vehicle speed (>= 6 m/s) cancels the timer.
    }

    /// Schedule a one-shot timer that fires exactly gpsDeadSecs (10s) after the
    /// last GPS fix. When it fires, effectiveSpeed() == 0 → start auto-end immediately.
    /// Each new GPS fix resets this timer.
    private func scheduleGPSSilenceTimer() {
        gpsSilenceTimer?.invalidate()
        gpsSilenceTimer = Timer.scheduledTimer(withTimeInterval: gpsDeadSecs, repeats: false) { [weak self] _ in
            guard let self = self, self.isTracking else { return }
            let speed = self.effectiveSpeed()
            if speed < self.vehicleThreshold {
                print("⏱️ TripTracker GPS silent \(Int(self.gpsDeadSecs))s → speed=\(String(format:"%.1f", speed)) → starting auto-end timer")
                self.startAutoEndTimer()
            }
        }
        if let timer = gpsSilenceTimer {
            RunLoop.main.add(timer, forMode: .common)
        }
    }

    /// Auto-start a new trip (vehicle speed detected).
    private func autoStartTrip(reason: String) {
        guard !isTracking else { return }

        // Only auto-start if vehicle_id or route_id is configured.
        // If neither is set, user hasn't selected a vehicle yet — don't start trip.
        let vehicleId = TripTrackerAPIService.shared.config.vehicleId
        let routeId = TripTrackerAPIService.shared.config.routeId
        guard !vehicleId.isEmpty || !routeId.isEmpty else {
            print("⏳ TripTracker Auto-start SKIPPED — no vehicle_id or route_id configured")
            return
        }

        print("🤖  TripTracker Auto-start trip — \(reason)")

        let initialLocation = lastKnownLocation ?? locationManager.location
        startTrip(withInitialLocation: initialLocation)

        // Local push notification
        NotificationManager.shared.notifyTripStarted(tripId: currentTripId, vehicleId: TripTrackerAPIService.shared.config.vehicleId)

        // Voice feedback
        VoiceFeedbackManager.shared.resetMilestones()
        VoiceFeedbackManager.shared.announceTripStarted(tripId: currentTripId)

        // CarPlay alert
        NotificationCenter.default.post(name: .tripAutoStarted, object: nil,
            userInfo: ["tripId": currentTripId])

        DispatchQueue.main.async { [weak self] in
            guard let self = self else { return }
            self.autoTripDelegate?.autoTripDidStart(tripId: self.currentTripId)
        }
    }

    /// Start a timer that will auto-end the trip after autoEndStillnessSecs of speed == 0.
    private func startAutoEndTimer() {
        guard isTracking else { return }

        // Already counting? Don't restart.
        if autoEndTimer != nil { return }

        stillSinceDate = Date()
        let timeout = autoEndStillnessSecs

        print("⏱️ TripTracker Auto-end \(currentTripId) timer started — will stop trip after \(Int(timeout))s without vehicle speed")

        // Voice feedback
        VoiceFeedbackManager.shared.announceVehicleStopped()

        // CarPlay alert
        let mins = Int(timeout / 60)
        NotificationCenter.default.post(name: .tripVehicleStopped, object: nil,
            userInfo: ["timeout": mins])

        autoEndTimer = Timer.scheduledTimer(withTimeInterval: timeout, repeats: false) { [weak self] _ in
            guard let self = self else { return }
            self.autoEndTrip(reason: "No vehicle speed for \(Int(timeout / 60)) min")
        }
        // Ensure timer fires even when the run loop is tracking scroll events
        if let timer = autoEndTimer {
            RunLoop.main.add(timer, forMode: .common)
        }
    }

    /// Cancel the auto-end countdown (speed rose above 0 again).
    private func cancelAutoEndTimer() { 
        guard autoEndTimer != nil else { return }
        autoEndTimer?.invalidate()
        autoEndTimer = nil
        if let since = stillSinceDate {
            let elapsed = Int(Date().timeIntervalSince(since))
            print("⏱️ TripTracker Auto-end timer cancelled — vehicle speed restored after \(elapsed)s")
        }
        stillSinceDate = nil
    }

    /// Reset the auto-end timer.
    private func resetAutoEndTimer() {
        autoEndTimer?.invalidate()
        autoEndTimer = nil
        stillSinceDate = nil
    }

    /// Stop the trip automatically after prolonged zero speed.
    private func autoEndTrip(reason: String) {
        guard isTracking else {
            resetAutoEndTimer()
            return
        }

        let tripId = currentTripId
        // Capture stats before stopTrip() resets them
        let stats = getCurrentStats()
        print("🤖 TripTracker Auto-end trip #\(tripId) — reason: \(reason)")

        // Send 3 final pings at speed=0 with the LAST KNOWN GOOD position.
        // Priority: lastPingedLocation (last API ping) > lastGPSLocation > locationManager.location
        // lastPingedLocation is the most accurate because it passed the 80m distance gate
        // and was a real GPS fix during the trip.
        let finalLoc: CLLocation? = {
            if let pinged = lastPingedLocation { return pinged }
            if let gps = lastGPSLocation, abs(gps.timestamp.timeIntervalSinceNow) < 600 { return gps }
            return locationManager.location
        }()

        if let finalLoc = finalLoc {
            let pt = LocationPoint(
                tripId:    currentTripId != -1 ? currentTripId : nil,
                latitude: finalLoc.coordinate.latitude,
                longitude: finalLoc.coordinate.longitude,
                altitude: finalLoc.altitude,
                accuracy:  Float(finalLoc.horizontalAccuracy),
                speed: 0,
                bearing:   Float(finalLoc.course >= 0 ? finalLoc.course : 0),
                timestamp: Int64(Date().timeIntervalSince1970 * 1000),
                source:    TrackingSource.gps.rawValue  
            )

            // Temporarily clear lastPingedLocation so distance gate doesn't block
            lastPingedLocation = nil
            sendAPIPing(location: pt, source: .gps, speed: 0)
            print("📡 TripTracker Final ping \(i)/3 before trip end — \(pt.latitude),\(pt.longitude)")
        }

        stopTrip()
        resetAutoEndTimer()

        // Local push notification with trip summary
        NotificationManager.shared.notifyTripEnded(
            tripId: tripId,
            reason: reason,
            distance: stats.distance,
            duration: stats.duration,
            vehicleId: TripTrackerAPIService.shared.config.vehicleId
        )

        // Voice feedback
        VoiceFeedbackManager.shared.announceTripEnded(
            tripId: tripId,
            distance: stats.distance,
            duration: stats.duration
        )

        // CarPlay alert
        NotificationCenter.default.post(name: .tripAutoEnded, object: nil,
            userInfo: ["tripId": tripId, "distance": stats.distance, "duration": stats.duration])

        DispatchQueue.main.async { [weak self] in
            self?.autoTripDelegate?.autoTripDidEnd(tripId: tripId, reason: reason)
        }
    }

    // MARK: - Helpers

    /// Persist a location to DB + cache, deduplicating on timestamp (per second).
    /// Returns true if actually saved.
    @discardableResult
    private func persistIfNew(_ location: LocationPoint, source: TrackingSource, tripId: Int64) -> Bool {
        let tsSec = location.timestamp / 1000   // ms → s
        guard tsSec != lastPersistedTimestampSec else {
            return false   // same second — duplicate
        }
        lastPersistedTimestampSec = tsSec
        DatabaseManager.shared.saveCachedLocation(location: location)
        if isTracking && tripId != -1 {
            DatabaseManager.shared.saveLocation(tripId: tripId, location: location)
        }
        // API: ping on EVERY save (trip AND no trip)
        sendAPIPing(location: location, source: source, speed: location.speed)
        print("📍 TripTracker persistIfNew — speed: \(String(format:"%.1f", location.speed)) m/s")
        return true
    }

    /// Time-based gate for sensor saves.
    ///  still / unknown   → 5-min interval
    ///  slow move < 6 m/s → 1-min interval
    ///  vehicle >= 6 m/s  → not used (GPS distance-gate handles this)
    private func shouldSaveLocation(speed: Float) -> Bool {
        guard speed < vehicleThreshold else { return false }  // vehicle: GPS handles it
        let now      = Int64(Date().timeIntervalSince1970 * 1000)
        let interval = isSlowMoving ? saveIntervalSlowMs : saveIntervalStillMs
        guard now - lastLocationSaveTime >= interval else { return false }
        lastLocationSaveTime = now
        return true
    }
}

// MARK: - Fake GPS injection (for simulation / testing)

extension LocationTrackingService {
    /// Injects a synthetic GPS fix at the given coordinate with the given speed.
    /// Runs through the exact same pipeline as a real CLLocation update so that
    /// distance accumulation, source switching, DB saves and UI updates all work.
    ///
    /// - Parameters:
    ///   - coordinate: The road-snapped coordinate from MKDirections polyline.
    ///   - speed: Must be > vehicleThreshold (6 m/s) to reliably trigger GPS mode.
    ///            Use 10.0 m/s (36 km/h) for city driving simulation.
    ///   - course: Optional compass bearing (0–360°). Computed from prev→current if omitted.
    public func injectFakeGPS(coordinate: CLLocationCoordinate2D, speed: Double, course: Double = -1) {
        // Compute course from previous location if not provided
        let bearing: Double
        if course >= 0 {
            bearing = course
        } else if let prev = lastKnownLocation {
            bearing = Self.bearingBetween(prev.coordinate, and: coordinate)
        } else {
            bearing = 0
        }

        let fakeLocation = CLLocation(
            coordinate:           coordinate,
            altitude:             0,
            horizontalAccuracy:   5.0,   // excellent accuracy — forces GPS mode
            verticalAccuracy:     5.0,
            course:               bearing,
            speed:                speed,  // must be >= vehicleThreshold (6 m/s)
            timestamp:            Date()
        )
        // Drive the same delegate callback used by real GPS hardware.
        isProcessingFakeGPS = true
        locationManager(locationManager, didUpdateLocations: [fakeLocation])
        isProcessingFakeGPS = false
    }

    /// Compass bearing in degrees [0, 360) from `from` to `to`.
    private static func bearingBetween(_ from: CLLocationCoordinate2D,
                                        and to: CLLocationCoordinate2D) -> Double {
        let lat1 = from.latitude  * .pi / 180
        let lat2 = to.latitude    * .pi / 180
        let dLon = (to.longitude - from.longitude) * .pi / 180
        let y = sin(dLon) * cos(lat2)
        let x = cos(lat1) * sin(lat2) - sin(lat1) * cos(lat2) * cos(dLon)
        let bearing = atan2(y, x) * 180 / .pi
        return (bearing + 360).truncatingRemainder(dividingBy: 360)
    }
}

// MARK: - CLLocationManagerDelegate

extension LocationTrackingService: CLLocationManagerDelegate {

    public func locationManager(_ manager: CLLocationManager,
                         didUpdateLocations locations: [CLLocation]) {
        guard let location = locations.last else { return }

        // When fake route is active, ignore real GPS fixes — only process injected fakes.
        // This prevents the real location from interfering with the simulated route.
        if isFakeRouteActive && !isProcessingFakeGPS {
            return
        }

        // GPS speed is unreliable at low speeds (often reports -1 or 0.0 even when moving).
        // If GPS reports speed <= 0, calculate it from position delta — BUT only if:
        //   1. Accuracy is good (≤ 15m) — poor accuracy means position jumps are noise
        //   2. Distance > combined accuracy of both fixes — otherwise it's just GPS drift
        //   3. Computed speed is physically possible (≤ 50 m/s = 180 km/h)
        //   4. Time interval is reasonable (≥ 1s) — sub-second fixes have unreliable positions
        var rawSpeed = Float(max(0, location.speed))
        let now = Date()
        if rawSpeed <= 0, let prev = lastGPSLocation {
            let dist = location.distance(from: prev)
            let dt   = now.timeIntervalSince(prev.timestamp)
            let combinedAccuracy = location.horizontalAccuracy + prev.horizontalAccuracy
            if dt >= 1.0 && dist > 0
                && location.horizontalAccuracy <= 15
                && dist > combinedAccuracy {
                let computedSpeed = Float(dist / dt)
                // Reject impossible speed (> 50 m/s = 180 km/h) — GPS cold start drift
                // e.g., cached location from 5km away + first real fix = huge distance / small dt
                if computedSpeed <= 50.0 {
                    rawSpeed = computedSpeed
                    print("📐  TripTracker Computed speed from delta: dist=\(String(format:"%.1f",dist))m dt=\(String(format:"%.1f",dt))s acc=\(Int(location.horizontalAccuracy))m → \(String(format:"%.2f",computedSpeed)) m/s")
                } else {
                    print("📐  TripTracker Computed speed REJECTED: \(String(format:"%.1f",computedSpeed)) m/s — impossible speed (GPS cold start drift, dist=\(String(format:"%.0f",dist))m dt=\(String(format:"%.1f",dt))s)")
                }
            } else if dist > 0 {
                print("📐 TripTrackerComputed speed SKIPPED: dist=\(String(format:"%.1f",dist))m acc=\(Int(location.horizontalAccuracy))m combinedAcc=\(Int(combinedAccuracy))m — GPS drift, not real movement")
            }
        }

        // Only trust GPS data when accuracy is reasonable.
        // GPS fixes with 80-400m accuracy produce wild position jumps → corrupt speed + location.
        lastGPSSpeed      = rawSpeed
        lastGPSUpdateTime = now
        lastGPSLocation   = location
        lastKnownLocation = location
        persistLastGPSTimestamp()

        let speed  = effectiveSpeed()
        let source = resolveSource(speed: speed)
        currentSource = source

        // Always calibrate sensor baseline when accuracy is good
        if lastSensorLocation == nil { lastSensorLocation = location }

        print("📍 TripTracker GPS fix — acc:\(Int(location.horizontalAccuracy))m  spd:\(String(format:"%.1f", speed)) m/s  → \(source.rawValue)")

        // ── Auto-trip: evaluate start/end based on GPS speed ──
        evaluateAutoTripFromGPS(speed: speed)

        // ── GPS silence timer: fire exactly gpsDeadSecs after this fix ──
        // If no new GPS fix arrives within 10s, speed will be 0 and we
        // immediately start the auto-end countdown — no waiting for periodic tick.
        scheduleGPSSilenceTimer()

        // ── Geofence: check enter/exit on every GPS fix ──
        GeofenceManager.shared.checkLocation(location)

        // Keep motion state in sync with GPS speed
        if source == .gps && lastMotionState != .automotive {
            lastMotionState = .automotive
        } else if source == .sensors && lastMotionState == .automotive {
            lastMotionState = .still  // slowed down — will be refined by CMMotionActivity
        }

        // ── Always update UI on every GPS fix (speed, source, accel, distance) ──
        let livePt = LocationPoint(
            tripId:    currentTripId != -1 ? currentTripId : nil,
            latitude:  location.coordinate.latitude,
            longitude: location.coordinate.longitude,
            altitude:  location.altitude,
            accuracy:  Float(location.horizontalAccuracy),
            speed:     speed,
            bearing:   Float(location.course >= 0 ? location.course : 0),
            timestamp: Int64(now.timeIntervalSince1970 * 1000),
            source:    source.rawValue
        )
        sendAPIPing(location: livePt, source: .gps, speed: speed)
        delegate?.didUpdateLocation(livePt, source: source, totalDistance: totalDistance)

        if let start = tripStartTime {
            delegate?.didUpdateStats(
                speed:    speed,
                distance: totalDistance,
                duration: Int64(now.timeIntervalSince(start))
            )
        }

        // ── Sensors mode (speed < 6 m/s): GPS calibrates only, sensors save ──
        if source == .sensors { return }

        // ── GPS mode (speed >= 6 m/s): GPS saves directly ──────────────────
        guard isTracking, currentTripId != -1 else { return }
        guard location.horizontalAccuracy > 0,
              location.horizontalAccuracy <= 50 else { return }

        // Save every 30 m (distance-only gate at vehicle speed)
        let movedEnough = lastSavedGPSLocation.map {
            location.distance(from: $0) >= saveDistanceVehicleM
        } ?? true
        guard movedEnough else { return }

        // Accumulate distance
        if let last = lastSavedGPSLocation {
            let d = location.distance(from: last)
            if d > 0 && d < 200 { totalDistance += d }
        }
        lastSavedGPSLocation = location

        // Voice: check distance milestones (every 1 km)
        VoiceFeedbackManager.shared.checkDistanceMilestone(totalDistance: totalDistance)

        // let pt = LocationPoint(from: location, source: .gps)
        let pt = LocationPoint(
            tripId:    currentTripId != -1 ? currentTripId : nil,
            latitude:  location.coordinate.latitude,
            longitude: location.coordinate.longitude,
            altitude:  location.altitude,
            accuracy:  Float(location.horizontalAccuracy),
            speed:     speed,
            bearing:   Float(location.course >= 0 ? location.course : 0),
            timestamp: Int64(now.timeIntervalSince1970 * 1000),
            source:    source.rawValue
        )
        
        if persistIfNew(pt, source: .gps, tripId: currentTripId) {
            delegate?.didUpdateLocation(pt, source: .gps, totalDistance: totalDistance)
        }
        print("🛰️ TripTracker GPS saved (vehicle): spd=\(String(format:"%.1f", speed)) m/s")

        if let start = tripStartTime {
            delegate?.didUpdateStats(speed: speed,
                                     distance: totalDistance,
                                     duration: Int64(Date().timeIntervalSince(start)))
        }
    }

    // MARK: - Region Monitoring (forwarded to GeofenceManager)

    public func locationManager(_ manager: CLLocationManager, didEnterRegion region: CLRegion) {
        print("📍 TripTracker didEnterRegion: \(region.identifier)")
        GeofenceManager.shared.handleDidEnterRegion(region)
    }

    public func locationManager(_ manager: CLLocationManager, didExitRegion region: CLRegion) {
        print("📍 TripTracker didExitRegion: \(region.identifier)")
        GeofenceManager.shared.handleDidExitRegion(region)
    }

    public func locationManager(_ manager: CLLocationManager, monitoringDidFailFor region: CLRegion?,
                         withError error: Error) {
        GeofenceManager.shared.handleMonitoringFailed(for: region, error: error)
    }

    public func locationManager(_ manager: CLLocationManager, didStartMonitoringFor region: CLRegion) {
        print("📍 TripTracker Started monitoring region: \(region.identifier)")
        // Request the current state so we know if we're already inside
        manager.requestState(for: region)
    }

    public func locationManager(_ manager: CLLocationManager, didDetermineState state: CLRegionState,
                         for region: CLRegion) {
        let stateStr = state == .inside ? "INSIDE" : state == .outside ? "OUTSIDE" : "UNKNOWN"
        print("📍 TripTracker Region state: \(region.identifier) → \(stateStr)")
    }

    public func locationManager(_ manager: CLLocationManager, didFailWithError error: Error) {
        print("❌ TripTracker Location error: \(error.localizedDescription)")
        // GPS failed — sensor dead reckoning continues automatically; no action needed
    }

    public func locationManager(_ manager: CLLocationManager, didVisit visit: CLVisit) {
        let isDeparture = visit.departureDate != .distantFuture
        let isArrival   = visit.arrivalDate   != .distantPast
        print("📍 TripTracker Visit event — arrival:\(isArrival) departure:\(isDeparture) coord:(\(visit.coordinate.latitude), \(visit.coordinate.longitude))")

        // Send a ping on every visit event (wakes from terminated)
        if let loc = locationManager.location {
            let pt = LocationPoint(from: loc, source: .gps)
            sendAPIPing(location: pt, source: .gps, speed: max(0, effectiveSpeed()))
            print("📍 TripTracker locationManager — speed: \(String(format:"%.1f", pt.speed)) m/s")
            DatabaseManager.shared.saveCachedLocation(location: pt)
            lastKnownLocation = loc
            persistLastGPSTimestamp()
        }

        if isTracking {
            let speed = effectiveSpeed()
            if speed < vehicleThreshold {
                startAutoEndTimer()
            }
        } else if isDeparture {
            // User departed — GPS was likely stopped (Option A).
            // loc.speed is stale/0. We MUST start GPS to get fresh speed.
            // Check cached speed first, then start GPS for 60s.
            if let loc = locationManager.location,
               loc.horizontalAccuracy <= 50,
               abs(loc.timestamp.timeIntervalSinceNow) < 10,
               Float(max(0, loc.speed)) >= vehicleThreshold {
                // Fresh accurate fix with vehicle speed — start trip now
                autoStartTrip(reason: "Visit departure (speed \(String(format:"%.1f", loc.speed)) m/s)")
            } else {
                // No fresh speed — start GPS at full accuracy to detect driving
                locationManager.desiredAccuracy = kCLLocationAccuracyBest
                locationManager.distanceFilter  = kCLDistanceFilterNone
                locationManager.startUpdatingLocation()
                print("📍 TripTracker Visit departure: GPS started — waiting 60s for speed detection")

                // GPS will deliver fixes → didUpdateLocations → evaluateAutoTripFromGPS
                // If speed ≥ threshold × 3 consecutive fixes → auto-start trip
                // After 60s, if no trip started, reduce GPS
                DispatchQueue.main.asyncAfter(deadline: .now() + 60.0) { [weak self] in
                    guard let self = self else { return }
                    if !self.isTracking {
                        self.adaptLocationAccuracy(for: self.lastMotionState)
                        print("📍 TripTracker Visit departure: 60s elapsed, no trip — GPS adapted")
                    }
                }
            }
        }
    }

    public func locationManagerDidChangeAuthorization(_ manager: CLLocationManager) {
        switch manager.authorizationStatus {
        case .authorizedAlways, .authorizedWhenInUse:
            print("✅ TripTracker Location permission granted")
            locationManager.startUpdatingLocation()
        case .denied, .restricted:
            print("❌ TripTracker Location permission denied")
        case .notDetermined:
            locationManager.requestAlwaysAuthorization()
        @unknown default:
            break
        }
    }

    // MARK: - API Ping Helper

    /// Send location ping to server during active trip.

    private func sendAPIPing(location: LocationPoint, source: TrackingSource, speed: Float) {
        // Only send pings during active trip — save bandwidth and battery when idle
        guard isTracking else { return }

        let clLoc = CLLocation(latitude: location.latitude, longitude: location.longitude)

        // Distance gate: only send ping if moved >= saveDistanceVehicleM (80m) since last ping.
        // This prevents excessive API calls while keeping GPS at full rate for speed detection.
        if let lastPinged = lastPingedLocation {
            let distSinceLastPing = clLoc.distance(from: lastPinged)
            if distSinceLastPing < saveDistanceVehicleM {
                print("📡 TripTracker Ping skipped — only moved \(String(format:"%.1f", distSinceLastPing))m since last ping")
                return  // Too close to last ping — skip
            }
        }
        lastPingedLocation = clLoc

        // Clamp speed — CLLocation.speed can be -1 when invalid
        let safeSpeed = max(0, speed)
        let activityType: String
        switch lastMotionState {
            case .still, .unknown:    activityType = "still"
            case .walking:            activityType = "walking"
            case .running:            activityType = "running"
            case .cycling:            activityType = "on_bicycle"
            case .automotive:         activityType = "in_vehicle"
        }
        
        print("📡 TripTracker Sending ping — dist from last: \(String(format:"%.0f", lastPingedLocation.map { clLoc.distance(from: $0) } ?? 0))m")

        TripTrackerAPIService.shared.sendPing(
            location: clLoc,
            isMoving: safeSpeed > 0 ? true : false,
            speed: safeSpeed,
            activityType: safeSpeed > 0 ? (activityType != "still" ? activityType : "in_vehicle") : "still",
        )
    }
}
