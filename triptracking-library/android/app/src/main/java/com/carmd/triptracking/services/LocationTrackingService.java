package com.carmd.triptracking.services;

import android.Manifest;
import android.app.*;
import android.content.Context;
import android.content.Intent;
import android.content.pm.PackageManager;
import android.content.pm.ServiceInfo;
import android.location.Location;
import android.location.LocationListener;
import android.location.LocationManager;
import android.os.Binder;
import android.os.Build;
import android.os.Handler;
import android.os.IBinder;
import android.os.Looper;
import android.os.PowerManager;
import android.util.Log;
import com.carmd.triptracking.ui.AppSettings;
import androidx.annotation.NonNull;
import androidx.core.app.ActivityCompat;
import androidx.core.app.NotificationCompat;
import com.carmd.triptracking.tracking.SensorBasedLocationTracker;
import com.carmd.triptracking.database.LocationDatabase;
import com.carmd.triptracking.server.LocationWebServer;
import android.app.AlarmManager;
import android.content.SharedPreferences;
import java.util.ArrayList;
import java.util.List;

/**
 * Location Tracking Service
 *
 * SINGLE CLEAR RULE:
 *   speed < 6 m/s  (stationary or walking) → source = "Sensors"
 *   speed >= 6 m/s (vehicle)               → source = "GPS"
 *
 * ONE save loop fires every SAVE_INTERVAL_MS. It reads the current effective
 * speed at that moment and picks the correct source and location accordingly.
 *
 * GPS is used ONLY for:
 *   1. Calibrating the sensor tracker position when accuracy is good
 *   2. Saving location when speed >= VEHICLE_THRESHOLD
 *
 * When device is on a table (not moving):
 *   - GPS fires updates but speed = 0  → sensor path is used
 *   - GPS eventually goes silent        → speed decays to 0  → sensor path
 *   - Sensor tracker detects no motion  → effectiveSpeed = 0 → sensor path
 */
public class LocationTrackingService extends Service implements
        SensorBasedLocationTracker.LocationUpdateListener,
        LocationListener {

    private static final String TAG = "LocationTrackingService";
    private static final int    NOTIFICATION_ID = 1001;
    private static final String CHANNEL_ID      = "location_tracking";

    // ── Trip event notifications ──────────────────────────────────────────
    private static final String CHANNEL_TRIP_EVENTS = "trip_events";
    private static final int    NOTIF_TRIP_START    = 2001;
    private static final int    NOTIF_TRIP_END      = 2002;
    private static final int    NOTIF_DISTANCE      = 2003;

    // ── Daily reminder ────────────────────────────────────────────────────
    private static final int    DAILY_REMINDER_REQUEST   = 9002;
    private static final int    DAILY_LOG_SENDER_REQUEST = 9003;

    public static final String ACTION_START_TRACKING           = "START_TRACKING";
    public static final String ACTION_RESUME_TRACKING          = "RESUME_TRACKING";  // restart after kill
    public static final String ACTION_STOP_TRACKING            = "STOP_TRACKING";
    public static final String ACTION_START_CONTINUOUS_TRACKING = "START_CONTINUOUS_TRACKING";

    // ── Tracking source ───────────────────────────────────────────────────────
    public enum TrackingSource { SENSORS, GPS }

    // ── Speed thresholds ──────────────────────────────────────────────────────
    private static final float STATIONARY_THRESHOLD = 0.5f;  // m/s — below = stationary

    // ── Fixed save intervals ───────────────────────────────────────────────────
    //   Still / on table  → configurable (default 5 min)
    //   Slow move < 6 m/s → configurable (default 1 min)
    //   Vehicle >= 6 m/s  → configurable distance-based (default 30 m, no timer)
    //   All three are now read from AppSettings at runtime.

    // ── Runtime helpers ───────────────────────────────────────────────────────
    /** Vehicle speed threshold (m/s); above this → GPS save path. */
    private float vehicleThreshold()   { return AppSettings.getVehicleSpeed(this); }
    /** Vehicle save distance (m); GPS saves when moved this far. */
    private float vehicleSaveDistance() { return AppSettings.getVehicleDistance(this); }

    // ── Auto-trip logic ─────────────────────────────────────────────────────
    /** Duration device must be still before auto-stopping a trip (from settings). */
    private long autoStopStillMs() { return AppSettings.getAutoStopTimeoutMs(this); }
    /** Timestamp when device last became still (0 = not still / moving). */
    private long stillSinceMs = 0L;
    /** Dedicated timer that fires exactly at autoStopStillMs() — not dependent on save ticks. */
    private Handler  autoStopHandler  = null;
    private Runnable autoStopRunnable = null;

    // ── GPS staleness ─────────────────────────────────────────────────────────
    private static final long GPS_STALE_MS = 10_000L; // speed starts decaying after this
    private static final long GPS_DEAD_MS  = 18_000L; // speed forced to 0 after this

    // ── Callback interface ────────────────────────────────────────────────────
    public interface LocationUpdateCallback {
        void onLocationUpdate(Location location, TrackingSource source, double distance);
        void onTrackingStateChanged(boolean isTracking);
        void onStatsUpdate(float speed, double distance, long duration);
    }

    // ── Binder ────────────────────────────────────────────────────────────────
    public class LocalBinder extends Binder {
        public LocationTrackingService getService() { return LocationTrackingService.this; }
    }
    private final IBinder binder = new LocalBinder();

    // ── Core state ────────────────────────────────────────────────────────────
    private boolean isTracking    = false;
    private long    currentTripId = -1;
    private long    tripStartTime = 0;
    private double  totalDistance = 0.0;
    private int     tripStartStepCount = 0;

    // ── Dependencies ──────────────────────────────────────────────────────────
    private SensorBasedLocationTracker sensorTracker;
    private LocationManager            locationManager;
    private PowerManager.WakeLock      wakeLock;
    private LocationDatabase           database;
    private LocationWebServer          webServer;
    private final List<LocationUpdateCallback> listeners = new ArrayList<>();

    // ── Location state ────────────────────────────────────────────────────────
    private Location lastSensorLocation      = null; // dead-reckoned by sensor tracker
    private Location lastSavedSensorLocation  = null; // last sensor location actually saved (walk debounce)
    private Location lastGpsLocation          = null; // latest GPS fix (updated every fix)
    private Location lastSavedGpsLocation     = null; // last GPS fix actually saved (vehicle debounce)

    // ── Speed state ───────────────────────────────────────────────────────────
    private float lastGpsSpeed      = 0f;
    private long  lastGpsUpdateTime = 0L;

    // ── Persistence of trip state across kills ───────────────────────────────
    private static final String PREFS_NAME          = "TripTrackerState";
    private static final String PREF_IS_TRACKING    = "isTracking";
    private static final String PREF_TRIP_ID        = "currentTripId";
    private static final String PREF_TRIP_START     = "tripStartTime";
    private static final String PREF_TOTAL_DISTANCE = "totalDistance";
    private static final String PREF_TRIP_START_STEPS = "tripStartStepCount";
    private static final int    WATCHDOG_REQUEST     = 9001;
    private static final long   WATCHDOG_INTERVAL_MS = 60_000L; // 60 s

    // ── Save loop ─────────────────────────────────────────────────────────────
    private Handler  saveHandler  = null;
    private Runnable saveLoopTask = null;
    private long     lastSaveTime = 0L;

    // =========================================================================
    // Lifecycle
    // =========================================================================

    @Override
    public void onCreate() {
        super.onCreate();

        // MUST call startForeground immediately — Android 12+ crashes otherwise
        createNotificationChannel();
        startForegroundNotification("Trip Tracker", "Starting…");

        locationManager = (LocationManager) getSystemService(Context.LOCATION_SERVICE);
        sensorTracker   = new SensorBasedLocationTracker(this, this);
        database        = LocationDatabase.getInstance(this);

        PowerManager pm = (PowerManager) getSystemService(Context.POWER_SERVICE);
        wakeLock = pm.newWakeLock(PowerManager.PARTIAL_WAKE_LOCK, "TripTracker::WakeLock");

        if (!hasLocationPermissions()) {
            Log.w(TAG, "Location permissions not granted — stopping service");
            stopSelf();
            return;
        }

        if (!wakeLock.isHeld()) wakeLock.acquire();

        // Seed sensor tracker with best available cached location
        startSensorTracking();

        // GPS runs continuously: calibration + vehicle-speed detection
        startGPSTracking();

        // Single periodic save loop (always on, even outside a trip)
        startSaveLoop();

        // Delay 5s for GPS to warm up, then save initial location
        new Handler(Looper.getMainLooper()).postDelayed(() -> {
            Location initLoc = getCurrentLocation();
            if (initLoc != null) {
                database.saveCachedLocation(initLoc, "GPS");
                notifyListeners(initLoc, TrackingSource.GPS);
                Log.d(TAG, "Initial location cached (5s delay): (" +
                        String.format("%.6f, %.6f", initLoc.getLatitude(), initLoc.getLongitude()) + ")");
            }
        }, 5000);

        // Web server for real-time monitoring (if enabled in settings)
        if (AppSettings.isWebServerEnabled(this)) {
            webServer = new LocationWebServer(this);
            webServer.start();
        }

        // Schedule daily 6 AM reminder to check yesterday's route
        scheduleDailyReminder();

        // Schedule daily 12 PM auto-send of log file via email
        scheduleDailyLogSender();

        // Re-register geofences (lost after reboot)
        if (com.carmd.triptracking.geofence.GeofenceManager.isEnabled(this)) {
            com.carmd.triptracking.geofence.GeofenceManager.registerAll(this);
        }

        Log.d(TAG, "Service started — sensor-first tracking active");
    }

    @Override
    public int onStartCommand(Intent intent, int flags, int startId) {
        String action = (intent != null) ? intent.getAction() : null;

        if (ACTION_STOP_TRACKING.equals(action)) {
            // Only used internally by auto-stop; kept for checkpoint clearing
            stopTracking();
            clearCheckpoint();
            return START_STICKY;
        }

        // ACTION_RESUME_TRACKING  OR  null intent (START_STICKY OS restart)
        // OR  ACTION_START_CONTINUOUS_TRACKING  OR  ACTION_START_TRACKING
        // All mean: ensure service is running and auto-trip logic is active.
        // If there was an active trip before a kill, resume it.
        if (ACTION_RESUME_TRACKING.equals(action) || action == null) {
            tryResumeFromCheckpoint();
        }
        return START_STICKY;
    }

    @Override
    public IBinder onBind(Intent intent) { return binder; }

    @Override
    public void onTaskRemoved(Intent rootIntent) {
        super.onTaskRemoved(rootIntent);
        if (isTracking) {
            saveCheckpoint();
            scheduleWatchdog();
        }
    }

    @Override
    public void onDestroy() {
        super.onDestroy();
        if (isTracking) {
            // Save checkpoint so trip can resume — do NOT call stopTracking() here
            // because that would end the trip in the DB and clear the tripId.
            saveCheckpoint();
            scheduleWatchdog();
        }
        // Always stop sensors and save loop on destroy
        cancelAutoStopTimer();
        sensorTracker.stopTracking();
        stopSaveLoop();
        if (wakeLock != null && wakeLock.isHeld()) wakeLock.release();
        if (webServer != null) webServer.stop();
        // Shutdown TTS
        try { com.carmd.triptracking.util.VoiceFeedback.getInstance(this).shutdown(); }
        catch (Exception e) { /* ignored */ }
    }

    // =========================================================================
    // Public API
    // =========================================================================

    public boolean isCurrentlyTracking() { return isTracking; }
    public long    getCurrentTripId()    { return currentTripId; }
    public long    getTripStartTime()    { return tripStartTime; }
    public double  getTotalDistance()    { return totalDistance; }
    public long    getStillSinceMs()    { return stillSinceMs; }
    public long    getAutoStopMs()      { return autoStopStillMs(); }
    /** Steps taken during the current trip only. */
    public int     getCurrentTripSteps() {
        if (sensorTracker == null) return 0;
        SensorBasedLocationTracker.TrackingStats s = sensorTracker.getStats();
        int total = (s != null) ? s.getStepCount() : 0;
        int tripSteps = total - tripStartStepCount;
        return Math.max(0, tripSteps);
    }
    /** Last validated GPS speed in m/s — used by UI to show correct movement state. */
    public float   getCurrentGpsSpeed() { return lastGpsSpeed; }

    /** Flag: phone app requested route clear — Android Auto renderer consumes this. */
    private volatile boolean routeClearRequested = false;
    public void requestClearRoute() { routeClearRequested = true; }
    public boolean consumeRouteClearRequest() {
        if (routeClearRequested) { routeClearRequested = false; return true; }
        return false;
    }

    /** Current best location — with fallback to LocationManager cache. */
    public Location getCurrentLocation() {
        if (lastSensorLocation != null) return new Location(lastSensorLocation);
        if (lastGpsLocation    != null) return new Location(lastGpsLocation);
        // Fallback: try LocationManager cached locations
        if (locationManager != null) {
            try {
                Location gps = locationManager.getLastKnownLocation(android.location.LocationManager.GPS_PROVIDER);
                if (gps != null) return gps;
                Location passive = locationManager.getLastKnownLocation(android.location.LocationManager.PASSIVE_PROVIDER);
                if (passive != null) return passive;
                Location network = locationManager.getLastKnownLocation(android.location.LocationManager.NETWORK_PROVIDER);
                if (network != null) return network;
            } catch (SecurityException e) {
                Log.w(TAG, "No permission for last known location");
            }
        }
        return null;
    }

    /** Last known GPS heading in degrees (0=north). */
    public float getCurrentHeading() {
        if (lastGpsLocation != null && lastGpsLocation.hasBearing())
            return lastGpsLocation.getBearing();
        if (sensorTracker != null) {
            SensorBasedLocationTracker.TrackingStats stats = sensorTracker.getStats();
            if (stats != null) return stats.getCurrentHeading();
        }
        return 0f;
    }

    /** Get recent locations for the current trip (for map trail). */
    public java.util.List<Location> getRecentTrailLocations(int maxPoints) {
        java.util.List<Location> trail = new java.util.ArrayList<>();
        if (currentTripId == -1 || database == null) return trail;
        try {
            java.util.List<LocationDatabase.LocationPoint> points =
                    database.getLocationsForTrip(currentTripId);
            int start = Math.max(0, points.size() - maxPoints);
            for (int i = start; i < points.size(); i++) {
                LocationDatabase.LocationPoint p = points.get(i);
                Location loc = new Location("trail");
                loc.setLatitude(p.latitude);
                loc.setLongitude(p.longitude);
                trail.add(loc);
            }
        } catch (Exception e) {
            Log.w(TAG, "Error getting trail: " + e.getMessage());
        }
        return trail;
    }

    public void addLocationUpdateListener(LocationUpdateCallback cb)    { listeners.add(cb); }
    public void removeLocationUpdateListener(LocationUpdateCallback cb) { listeners.remove(cb); }

    /** Public API: stop the current trip (called from UI "Clear Route"). */
    public void requestStopTrip() {
        if (!isTracking) return;
        long tripId = currentTripId;
        long duration = (System.currentTimeMillis() - tripStartTime) / 1000;
        double dist = totalDistance;
        Log.d(TAG, "⏹️ Trip stopped by user request");
        stopTracking();
        clearCheckpoint();

        String distStr = dist < 1000
                ? String.format("%.0f m", dist)
                : String.format("%.2f km", dist / 1000);
        long min = duration / 60;
        long sec = duration % 60;
        if (AppSettings.isNotifTripEnd(this))
            showTripNotification(NOTIF_TRIP_END, "⏹️ Trip Ended",
                    "Trip #" + tripId + " — " + distStr + " in " +
                    String.format("%02d:%02d", min, sec));
        com.carmd.triptracking.util.VoiceFeedback.getInstance(this)
                .announceTripEnded(tripId, dist, duration);
    }

    public SensorBasedLocationTracker.TrackingStats getTrackingStats() {
        return sensorTracker != null ? sensorTracker.getStats() : null;
    }

    // =========================================================================
    // Trip start / stop
    // =========================================================================

    private void startTracking(Location initialLocation) {
        if (isTracking) return;

        isTracking    = true;
        tripStartTime = System.currentTimeMillis();
        totalDistance = 0.0;
        currentTripId = database.startTrip();
        lastSaveTime  = 0L;
        stillSinceMs  = 0L; // reset still timer — we're moving

        // Capture step count baseline for per-trip step tracking
        SensorBasedLocationTracker.TrackingStats startStats = sensorTracker.getStats();
        tripStartStepCount = (startStats != null) ? startStats.getStepCount() : 0;

        // Reset GPS speed state so getEffectiveSpeed() starts clean,
        // not decaying from a previous trip's last known speed.
        // NOTE: do NOT reset lastGpsSpeed/lastGpsUpdateTime here for auto-trips
        // because the current speed reading is what triggered the auto-start.

        // GPS was stopped by the previous stopTracking() call — restart it.
        startGPSTracking();

        Log.d(TAG, "🚗 AUTO-TRIP STARTED — ID=" + currentTripId);

        // Seed with the best position available right now
        Location seed = (initialLocation != null) ? initialLocation : getBestAvailableLocation();
        if (seed != null) {
            if (!sensorTracker.isTracking()) sensorTracker.startTracking(seed);
            lastSensorLocation      = new Location(seed);
            lastSavedSensorLocation = null; // reset so first walk save is never skipped
            lastGpsLocation         = new Location(seed);
            lastSavedGpsLocation    = null; // reset so vehicle anchor is re-seeded from first fix
            persistLocation(seed, TrackingSource.SENSORS, 0f);
        } else {
            requestSingleLocationFix(); // will seed sensors when fix arrives
        }

        saveCheckpoint();
        cancelWatchdog();
        startForegroundNotification("Tracking…", "Auto-trip #" + currentTripId + " in progress");
        notifyTrackingStateChanged(true);
    }

    /** Auto-start a trip when vehicle speed is detected. */
    private void autoStartTrip(Location triggerLocation) {
        if (isTracking) return;
        Log.d(TAG, "🚗 Vehicle speed detected — auto-starting trip");
        startTracking(triggerLocation);
        if (AppSettings.isNotifTripStart(this))
            showTripNotification(NOTIF_TRIP_START, "🚗 Trip Started",
                "Auto-trip #" + currentTripId + " — vehicle speed detected");
        // Voice announcement
        com.carmd.triptracking.util.VoiceFeedback.getInstance(this)
                .announceTripStarted(currentTripId);
    }

    /** Auto-stop a trip after being still for autoStopStillMs(). */
    private void autoStopTrip() {
        if (!isTracking) return;
        long tripId = currentTripId;
        long duration = (System.currentTimeMillis() - tripStartTime) / 1000;
        double dist = totalDistance;
        Log.d(TAG, "⏹️ Still for " + (autoStopStillMs() / 60_000) + " min — auto-stopping trip");
        stopTracking();
        clearCheckpoint();

        String distStr = dist < 1000
                ? String.format("%.0f m", dist)
                : String.format("%.2f km", dist / 1000);
        long min = duration / 60;
        long sec = duration % 60;
        if (AppSettings.isNotifTripEnd(this))
            showTripNotification(NOTIF_TRIP_END, "⏹️ Trip Ended",
                    "Trip #" + tripId + " — " + distStr + " in " +
                    String.format("%02d:%02d", min, sec));
        // Voice announcement
        com.carmd.triptracking.util.VoiceFeedback.getInstance(this)
                .announceTripEnded(tripId, dist, duration);
    }

    /** Check if still timer has exceeded threshold and auto-stop if needed. */
    private void checkAutoStop() {
        if (!isTracking || stillSinceMs == 0L) return;
        long stillDuration = System.currentTimeMillis() - stillSinceMs;
        if (stillDuration >= autoStopStillMs()) {
            autoStopTrip();
        } else {
            long remainSec = (autoStopStillMs() - stillDuration) / 1000;
            Log.d(TAG, "Still for " + (stillDuration / 1000) + "s, auto-stop in " + remainSec + "s");
        }
    }

    /**
     * Start a dedicated auto-stop timer that fires exactly at autoStopStillMs().
     * Independent of save tick interval — guarantees precise 10-minute auto-stop.
     * Safe to call multiple times; resets the timer each call.
     */
    private void startAutoStopTimer() {
        cancelAutoStopTimer();
        if (!isTracking) return;

        if (autoStopHandler == null) {
            autoStopHandler = new Handler(Looper.getMainLooper());
        }
        autoStopRunnable = () -> {
            Log.d(TAG, "⏱️ Auto-stop timer fired after " + (autoStopStillMs() / 60_000) + " min");
            autoStopTrip();
        };
        autoStopHandler.postDelayed(autoStopRunnable, autoStopStillMs());
        Log.d(TAG, "⏱️ Auto-stop timer started — will fire in " + (autoStopStillMs() / 1000) + "s");
    }

    /**
     * Cancel the dedicated auto-stop timer (device started moving).
     */
    private void cancelAutoStopTimer() {
        if (autoStopHandler != null && autoStopRunnable != null) {
            autoStopHandler.removeCallbacks(autoStopRunnable);
            autoStopRunnable = null;
            Log.d(TAG, "⏱️ Auto-stop timer cancelled — device moving");
        }
    }

    private void stopTracking() {
        if (!isTracking) return;
        isTracking = false;
        stillSinceMs = 0L;
        cancelAutoStopTimer();

        // Final save
        Location last = getBestAvailableLocation();
        if (last != null) {
            last.setTime(System.currentTimeMillis());
//            persistLocation(last, TrackingSource.SENSORS, 0f);
        }

        if (currentTripId != -1) {
            SensorBasedLocationTracker.TrackingStats stats = sensorTracker.getStats();
            long duration = (System.currentTimeMillis() - tripStartTime) / 1000;
            int tripSteps = stats.getStepCount() - tripStartStepCount;
            if (tripSteps < 0) tripSteps = 0;
            database.endTrip(currentTripId, totalDistance, duration, tripSteps);
            Log.d(TAG, "⏹️ Trip #" + currentTripId + " ended, " +
                    database.getLocationCount(currentTripId) + " points saved" +
                    ", dist=" + String.format("%.0f", totalDistance) + "m" +
                    ", dur=" + duration + "s");
            currentTripId = -1;
        }

        // Do NOT stop sensor tracker — keep it alive for auto-trip detection.
        // Do NOT removeUpdates on GPS — keep it alive so auto-start works.
        cancelWatchdog();
        startForegroundNotification("Trip Tracker", "Waiting for vehicle speed…");
        notifyTrackingStateChanged(false);
    }

    // =========================================================================
    // Effective speed — single source of truth for all save decisions
    //
    //  GPS fresh  (< GPS_STALE_MS)              → use lastGpsSpeed as-is
    //  GPS stale  (GPS_STALE_MS .. GPS_DEAD_MS) → linearly decay toward 0
    //  GPS dead   (> GPS_DEAD_MS)               → return 0
    // =========================================================================

    private float getEffectiveSpeed() {
        if (lastGpsUpdateTime == 0L) return 0f; // GPS never fired

        long silenceMs = System.currentTimeMillis() - lastGpsUpdateTime;

        if (silenceMs >= GPS_DEAD_MS) {
            if (lastGpsSpeed != 0f) {
                lastGpsSpeed = 0f;
                Log.d(TAG, "GPS silent " + (silenceMs / 1000) + "s → speed reset to 0");
            }
            return 0f;
        }

        if (silenceMs <= GPS_STALE_MS) {
            return lastGpsSpeed; // GPS fresh
        }

        // Decay window
        float decay = 1f - (float)(silenceMs - GPS_STALE_MS) / (float)(GPS_DEAD_MS - GPS_STALE_MS);
        return lastGpsSpeed * Math.max(0f, decay);
    }

    // =========================================================================
    // Single periodic save loop
    //
    // This is the ONLY timer that writes locations periodically.
    // Vehicle-speed GPS saves also happen in onLocationChanged but are
    // debounced by lastSaveTime to avoid duplicates.
    // =========================================================================

    private void startSaveLoop() {
        saveHandler  = new Handler(Looper.getMainLooper());
        saveLoopTask = new Runnable() {
            @Override
            public void run() {
                runSaveTick();
                saveHandler.postDelayed(this, nextSaveIntervalMs());
            }
        };
        // Delay first tick 5s for service to fully initialize (GPS warm up)
        saveHandler.postDelayed(saveLoopTask, 5000);
    }

    /**
     * Pick the correct save interval based on BOTH GPS speed AND sensor movement:
     *
     *   still  : GPS speed < 0.5 m/s  AND  sensors report not moving → 5 min
     *   walk   : moving but < vehicleThreshold                        → 1 min
     *   vehicle: >= vehicleThreshold                                  → 1 min (loop alive;
     *                                     actual saves are distance-gated in onLocationChanged)
     *
     * Using both sources prevents GPS noise from holding the interval at 1 min
     * when the device is genuinely stationary (e.g. indoors where GPS is weak).
     */
    private long nextSaveIntervalMs() {
        float spd         = getEffectiveSpeed();
        boolean sensorStill = sensorTracker == null || !sensorTracker.getStats().isMoving();

        // Truly still: GPS speed below stationary threshold AND sensors confirm no movement
        if (spd < STATIONARY_THRESHOLD && sensorStill) return AppSettings.getStillIntervalMs(this);

        // Moving but below vehicle threshold (walking / cycling)
        if (spd < vehicleThreshold()) return AppSettings.getWalkIntervalMs(this);

        // Vehicle speed — keep loop alive as fallback
        return AppSettings.getWalkIntervalMs(this); // vehicle fallback
    }

    private void stopSaveLoop() {
        if (saveHandler != null && saveLoopTask != null) {
            saveHandler.removeCallbacks(saveLoopTask);
            saveLoopTask = null;
        }
    }

    /**
     * Cancel the current pending tick and reschedule immediately with the
     * correct interval for the current movement state.
     * Called when movement state changes so the timer snaps to the right
     * interval without waiting for the old tick to fire.
     */
    private void rescheduleSaveLoop() {
        if (saveHandler == null || saveLoopTask == null) return;
        saveHandler.removeCallbacks(saveLoopTask);
        saveHandler.postDelayed(saveLoopTask, nextSaveIntervalMs());
        Log.d(TAG, "Save loop rescheduled → " + (nextSaveIntervalMs() / 1000) + "s");
    }

    /**
     * Periodic save tick — handles STILL and WALK paths only.
     *
     *   still  (< STATIONARY_THRESHOLD) : fires every 5 min → Sensors source
     *   walk   (< vehicleThreshold)     : fires every 1 min → Sensors source
     *   vehicle (>= vehicleThreshold)   : skip — saves are handled by onLocationChanged
     *                                     distance-based via the distance gate.
     */
    private void runSaveTick() {
        float   speed       = getEffectiveSpeed();
        boolean sensorStill = sensorTracker == null || !sensorTracker.getStats().isMoving();

        // ── Auto-trip: still timer management ─────────────────────────────
        boolean isStill = speed < STATIONARY_THRESHOLD && sensorStill;
        if (isStill) {
            if (stillSinceMs == 0L) {
                stillSinceMs = System.currentTimeMillis();
                startAutoStopTimer();
            }
            // Fallback check in case the dedicated timer didn't fire (e.g. deep sleep)
            checkAutoStop();
        } else {
            if (stillSinceMs != 0L) {
                stillSinceMs = 0L;
                cancelAutoStopTimer();
            }
        }

        // Vehicle speed: do nothing here — onLocationChanged owns distance-based saves.
        if (speed >= vehicleThreshold()) return;

        // Choose location source — always Sensors for still/walk path
        Location locationToSave = (lastSensorLocation != null) ? new Location(lastSensorLocation)
                                : (lastGpsLocation    != null) ? new Location(lastGpsLocation) : null;

        if (locationToSave == null && sensorTracker != null) {
            SensorBasedLocationTracker.TrackingStats stats = sensorTracker.getStats();
            if (stats != null && stats.getLocation() != null) {
                locationToSave = new Location(stats.getLocation());
                Log.d(TAG, "Save tick: using current sensor location as fallback");
            }
        }

        // Fallback: request last known GPS location from LocationManager
        if (locationToSave == null && hasLocationPermissions()) {
            try {
                Location gps = locationManager.getLastKnownLocation(LocationManager.GPS_PROVIDER);
                if (gps != null) {
                    locationToSave = new Location(gps);
                    Log.d(TAG, "Save tick: using GPS lastKnownLocation as fallback");
                }
            } catch (SecurityException e) {
                Log.w(TAG, "Save tick: GPS fallback permission denied");
            }
        }

        // Fallback: try Passive provider (returns last fix from ANY provider)
        if (locationToSave == null && hasLocationPermissions()) {
            try {
                Location passive = locationManager.getLastKnownLocation(LocationManager.PASSIVE_PROVIDER);
                if (passive != null) {
                    locationToSave = new Location(passive);
                    Log.d(TAG, "Save tick: using Passive lastKnownLocation as fallback");
                }
            } catch (SecurityException e) {
                Log.w(TAG, "Save tick: Passive fallback permission denied");
            }
        }

        // Last resort: request a fresh GPS fix and save when it arrives
        if (locationToSave == null) {
            Log.w(TAG, "Save tick: all caches empty — requesting fresh GPS fix");
            requestFreshLocationForSave(speed, sensorStill);
            return;
        }

        // WALK state: only save if the device has actually moved since the last save.
        // Prevents writing duplicate coordinates every minute while sitting still
        // with a stale GPS speed reading between 0.5 and 6 m/s.
        boolean isWalking = !sensorStill || speed >= STATIONARY_THRESHOLD;
        if (isWalking && lastSavedSensorLocation != null) {
            float moved = lastSavedSensorLocation.distanceTo(locationToSave);
            if (moved < 2.0f) {
                Log.d(TAG, "WALK tick skipped — moved only " + String.format("%.1f", moved) + "m since last save");
                return;
            }
        }

        locationToSave.setTime(System.currentTimeMillis());
        locationToSave.setSpeed(speed);

        String state = sensorStill ? "STILL" : "WALK";
        Log.d(TAG, "SAVE TICK [" + state + "]: speed=" + String.format("%.1f", speed) + " m/s" +
                " pos=(" + String.format("%.6f", locationToSave.getLatitude()) +
                ", " + String.format("%.6f", locationToSave.getLongitude()) + ")");

        lastSavedSensorLocation = new Location(locationToSave);
        persistLocation(locationToSave, TrackingSource.SENSORS, speed);
        notifyListeners(locationToSave, TrackingSource.SENSORS);
        notifyStatsUpdate();
    }

    // =========================================================================
    // SensorBasedLocationTracker callbacks
    // =========================================================================

    @Override
    public void onLocationUpdate(Location location, boolean isEstimated) {
        if (!isEstimated || location == null) return;

        // Accumulate distance only when sensor tracker has confirmed movement.
        // When isMoving=false, updatePosition() no longer fires this callback,
        // but double-guard here so table vibration can never drift totalDistance.
        if (lastSensorLocation != null) {
            float dist = lastSensorLocation.distanceTo(location);
            boolean sensorMoving = sensorTracker != null && sensorTracker.getStats().isMoving();
            if (isTracking && sensorMoving && dist > 1.0f && dist < 100.0f)
                totalDistance += dist;
            // Distance milestones (every 1 km): voice + push notification
            if (isTracking) {
                double km = com.carmd.triptracking.util.VoiceFeedback.getInstance(this)
                        .checkDistanceMilestone(totalDistance);
                if (km > 0 && AppSettings.isNotifDistanceKm(this))
                    showTripNotification(NOTIF_DISTANCE, "📏 Distance Milestone",
                            String.format(java.util.Locale.US, "%.0f km traveled", km));
            }
        }
        lastSensorLocation = new Location(location);
    }

    @Override
    public void onMovementDetected(boolean isMoving, float speed) {
        if (!isMoving) {
            long silenceMs = System.currentTimeMillis() - lastGpsUpdateTime;
            if (silenceMs > GPS_STALE_MS) {
                lastGpsSpeed = 0f;
                Log.d(TAG, "Sensors: device still + GPS stale → speed reset to 0");
            }
            // Start still timer if not already running
            if (stillSinceMs == 0L) {
                stillSinceMs = System.currentTimeMillis();
                Log.d(TAG, "Still timer started");
                startAutoStopTimer();
            }
        } else {
            // Device is moving — reset still timer and cancel auto-stop
            if (stillSinceMs != 0L) {
                stillSinceMs = 0L;
                cancelAutoStopTimer();
                Log.d(TAG, "Still timer reset — device moving");
            }
        }
        rescheduleSaveLoop();
        Log.d(TAG, "Movement state → " + (isMoving ? "MOVING" : "STILL") +
                " — save loop rescheduled to " + (nextSaveIntervalMs() / 1000) + "s");
    }

    @Override public void onStepDetected(int stepCount, double distance) { notifyStatsUpdate(); }
    @Override public void onHeadingUpdate(float heading, float confidence) {}
    @Override public void onAltitudeUpdate(float altitude, Integer floor) {}

    // =========================================================================
    // GPS (LocationListener) callback
    //
    // Responsibilities:
    //   1. Update lastGpsSpeed and lastGpsUpdateTime  (drives getEffectiveSpeed)
    //   2. Calibrate sensor tracker when accuracy is good
    //   3. Save directly when speed >= VEHICLE_THRESHOLD (debounced)
    // =========================================================================

    @Override
    public void onLocationChanged(@NonNull Location location) {
        float accuracy = location.getAccuracy();

        // ── Compute speed from position delta ─────────────────────────────────
        // Deriving speed from consecutive positions is more reliable than
        // location.getSpeed() which can carry stale values from cached fixes.
        // Formula: speed = distance / elapsed_time (m/s)
        float speed = 0f;
        if (lastGpsLocation != null && lastGpsUpdateTime > 0) {
            float  distM      = lastGpsLocation.distanceTo(location);
            long   elapsedMs  = System.currentTimeMillis() - lastGpsUpdateTime;
            float  elapsedSec = elapsedMs / 1000f;
            if (elapsedSec > 0 && distM >= 0) {
                speed = distM / elapsedSec;
            }
        } else if (location.hasSpeed()) {
            // First fix — no previous position to diff against; fall back to GPS value
            speed = location.getSpeed();
        }

        float prevGpsSpeed = lastGpsSpeed; // capture BEFORE updating, for threshold crossing check
        lastGpsSpeed      = speed;
        lastGpsUpdateTime = System.currentTimeMillis();

        Log.d(TAG, "GPS: speed=" + String.format("%.2f", speed) +
                " m/s accuracy=" + String.format("%.1f", accuracy) + "m");

        // Calibrate sensor tracker (always, when accuracy is good)
        if (accuracy <= 50f) {
            sensorTracker.updateFromGPS(location);
        }

        // Always advance lastGpsLocation to the latest fix so runSaveTick()
        // and distanceTo() calculations always use the real current position —
        // not a frozen snapshot from the last saved point.
        if (accuracy <= 50f) {
            lastGpsLocation = new Location(location);
            lastSensorLocation = null;
        }

        // Reschedule save loop when crossing the vehicle threshold in either direction
        // (walk→vehicle or vehicle→walk) so the interval snaps immediately.
        boolean nowVehicle = speed >= vehicleThreshold();
        boolean wasVehicle = prevGpsSpeed >= vehicleThreshold();
        if (nowVehicle != wasVehicle) rescheduleSaveLoop();

        // ── Auto-trip: moving at vehicle speed resets still timer ──────────
        if (speed >= STATIONARY_THRESHOLD) {
            if (stillSinceMs != 0L) {
                stillSinceMs = 0L;
                cancelAutoStopTimer();
            }
        }

        if (speed < vehicleThreshold()) return;

        // ── Vehicle speed path ────────────────────────────────────────────────
        // Auto-start trip if not already tracking
        if (!isTracking && accuracy <= 50f) {
            autoStartTrip(location);
        }
        if (accuracy > 50f) return; // don't save inaccurate fast fixes

        // Seed lastSavedGpsLocation on the first vehicle-speed fix so the
        // distance gate is measured from a real position, not null (which would
        // trigger an immediate save at 0 m moved).
        if (lastSavedGpsLocation == null) {
            lastSavedGpsLocation = new Location(location);
            Log.d(TAG, "GPS vehicle: anchor seeded, waiting for " + (int) vehicleSaveDistance() + " m");
            return;
        }

        float distFromAnchor = lastSavedGpsLocation.distanceTo(location);

        // Distance gate — sole trigger for vehicle saves.
        if (distFromAnchor < vehicleSaveDistance()) return; // haven't moved enough yet

        // Accumulate totalDistance ONLY at save time, using the exact gap between
        // the previous saved point and the current position.
        // (Previously this was done on every GPS fix, which double-counted.)
        totalDistance += distFromAnchor;
        // Distance milestones (every 1 km): voice + push notification
        {
            double km = com.carmd.triptracking.util.VoiceFeedback.getInstance(this)
                    .checkDistanceMilestone(totalDistance);
            if (km > 0 && AppSettings.isNotifDistanceKm(this))
                showTripNotification(NOTIF_DISTANCE, "📏 Distance Milestone",
                        String.format(java.util.Locale.US, "%.0f km traveled", km));
        }

        lastSavedGpsLocation = new Location(location);
        Log.d(TAG, "GPS SAVE (vehicle): speed=" + String.format("%.1f", speed) +
                " m/s dist=" + String.format("%.1f", distFromAnchor) + "m");
        persistLocation(location, TrackingSource.GPS, speed);
        notifyListeners(location, TrackingSource.GPS);
        notifyStatsUpdate();
    }

    @Override public void onStatusChanged(String p, int s, android.os.Bundle e) {}
    @Override public void onProviderEnabled(@NonNull String p)  {}
    @Override public void onProviderDisabled(@NonNull String p) {}

    // =========================================================================
    // Persistence — single entry point
    // =========================================================================

    private void persistLocation(Location location, TrackingSource source, float speed) {
        String sourceStr = source == TrackingSource.GPS ? "GPS" : "Sensors";

        // Always write to cache (drives web monitor)
        database.saveCachedLocation(location, sourceStr);

        // Write to trip table only when a trip is active
        if (isTracking && currentTripId != -1) {
            database.saveLocation(currentTripId, location, sourceStr);
            lastSaveTime = System.currentTimeMillis();
            Log.d(TAG, "Saved: source=" + sourceStr +
                    " speed=" + String.format("%.1f", speed) + " m/s trip=" + currentTripId);
        }
    }

    // =========================================================================
    // Sensor tracking startup
    // =========================================================================

    private void startSensorTracking() {
        try {
            Location seed = getInitialLocation();
            if (seed != null) {
                sensorTracker.startTracking(seed);
                lastSensorLocation = new Location(seed);
                Log.d(TAG, "Sensors seeded at (" +
                        String.format("%.6f, %.6f", seed.getLatitude(), seed.getLongitude()) + ")");
            } else {
                Log.w(TAG, "No cached location — requesting live fix to seed sensors");
                requestSingleLocationFix();
            }
        } catch (Exception e) {
            Log.e(TAG, "Failed to start sensor tracking", e);
        }
    }

    private void requestSingleLocationFix() {
        if (!hasLocationPermissions()) return;
        LocationListener oneShot = new LocationListener() {
            @Override
            public void onLocationChanged(Location loc) {
                locationManager.removeUpdates(this);
                if (loc != null && !sensorTracker.isTracking()) {
                    sensorTracker.startTracking(loc);
                    lastSensorLocation   = new Location(loc);
                    lastGpsLocation      = new Location(loc);
                    lastSavedGpsLocation = new Location(loc);
                    Log.d(TAG, "One-shot fix — sensors seeded at (" +
                            String.format("%.6f, %.6f", loc.getLatitude(), loc.getLongitude()) + ")");
                }
            }
            @Override public void onProviderEnabled(String p) {}
            @Override public void onProviderDisabled(String p) {}
            @Override public void onStatusChanged(String p, int s, android.os.Bundle e) {}
        };
        // GPS only — never fall back to network provider
        if (!locationManager.isProviderEnabled(LocationManager.GPS_PROVIDER)) {
            Log.w(TAG, "GPS not enabled — cannot get one-shot fix");
            return;
        }
        try {
            locationManager.requestLocationUpdates(LocationManager.GPS_PROVIDER, 0L, 0f, oneShot);
        } catch (SecurityException e) {
            Log.e(TAG, "Permission error requesting one-shot fix", e);
        }
    }

    /**
     * Last-resort fallback when all cached locations are null.
     * Requests a fresh GPS fix and performs the save when it arrives.
     */
    private void requestFreshLocationForSave(float speed, boolean sensorStill) {
        if (!hasLocationPermissions()) {
            Log.w(TAG, "Fresh GPS for save: no permission");
            return;
        }
        if (!locationManager.isProviderEnabled(LocationManager.GPS_PROVIDER)) {
            Log.w(TAG, "Fresh GPS for save: GPS not enabled");
            return;
        }

        try {
            locationManager.requestSingleUpdate(LocationManager.GPS_PROVIDER,
                    new LocationListener() {
                        @Override
                        public void onLocationChanged(@NonNull Location loc) {
                            locationManager.removeUpdates(this);

                            // Update in-memory caches so next tick won't need this again
                            lastGpsLocation    = new Location(loc);
                            lastSensorLocation = new Location(loc);
                            if (!sensorTracker.isTracking()) {
                                sensorTracker.startTracking(loc);
                            }

                            loc.setTime(System.currentTimeMillis());
                            loc.setSpeed(speed);

                            Log.d(TAG, "Fresh GPS fix for save: (" +
                                    String.format("%.6f, %.6f", loc.getLatitude(), loc.getLongitude()) +
                                    ") accuracy=" + String.format("%.1f", loc.getAccuracy()) + "m");

                            lastSavedSensorLocation = new Location(loc);
                            persistLocation(loc, TrackingSource.GPS, speed);
                            notifyListeners(loc, TrackingSource.GPS);
                            notifyStatsUpdate();
                        }

                        @Override public void onProviderEnabled(@NonNull String p) {}
                        @Override public void onProviderDisabled(@NonNull String p) {}
                        @Override public void onStatusChanged(String p, int s, android.os.Bundle e) {}
                    }, Looper.getMainLooper());

            Log.d(TAG, "Requested fresh GPS fix for save tick");
        } catch (SecurityException e) {
            Log.e(TAG, "Fresh GPS for save: permission error", e);
        }
    }

    private void startGPSTracking() {
        if (!hasPermission(Manifest.permission.ACCESS_FINE_LOCATION)) return;
        try {
            locationManager.removeUpdates(this);
            locationManager.requestLocationUpdates(LocationManager.GPS_PROVIDER, 1000L, 3f, this);
            Log.d(TAG, "GPS updates started (1s / 3m)");
        } catch (SecurityException e) {
            Log.e(TAG, "Permission error starting GPS", e);
        }
    }

    // =========================================================================
    // Location helpers
    // =========================================================================

    /**
     * Best cached location: GPS cache → Network cache → Passive cache → in-memory
     */
    private Location getInitialLocation() {
        if (!hasPermission(Manifest.permission.ACCESS_FINE_LOCATION) &&
            !hasPermission(Manifest.permission.ACCESS_COARSE_LOCATION)) return null;

        // GPS only — network and passive providers are excluded per tracking rules
        for (String provider : new String[]{
                LocationManager.GPS_PROVIDER}) {
            try {
                Location loc = locationManager.getLastKnownLocation(provider);
                if (isLocationUsable(loc)) {
                    Log.d(TAG, "Cached location from " + provider);
                    return loc;
                }
            } catch (SecurityException ignored) {}
        }

        if (lastGpsLocation    != null) return new Location(lastGpsLocation);
        if (lastSensorLocation != null) return new Location(lastSensorLocation);
        return null;
    }

    /** Non-null and not older than 24 hours */
    private boolean isLocationUsable(Location loc) {
        return loc != null &&
               (System.currentTimeMillis() - loc.getTime()) < 24 * 60 * 60 * 1000L;
    }

    /** Best in-memory location without hitting providers */
    private Location getBestAvailableLocation() {
        if (lastSensorLocation != null) return new Location(lastSensorLocation);
        if (lastGpsLocation    != null) return new Location(lastGpsLocation);
        return getInitialLocation();
    }

    // =========================================================================
    // Notification helpers
    // =========================================================================

    private void notifyListeners(Location location, TrackingSource source) {
        for (LocationUpdateCallback cb : listeners)
            cb.onLocationUpdate(location, source, totalDistance);
    }

    private void notifyTrackingStateChanged(boolean tracking) {
        for (LocationUpdateCallback cb : listeners) cb.onTrackingStateChanged(tracking);
    }

    private void notifyStatsUpdate() {
        if (sensorTracker == null) return;
        // Use GPS-based effective speed (with staleness decay), not the sensor
        // tracker's accelerometer estimate which reads ~1.6 km/h on a still table.
        float speed = getEffectiveSpeed();
        long duration = tripStartTime != 0 ? (System.currentTimeMillis() - tripStartTime) / 1000 : 0;
        for (LocationUpdateCallback cb : listeners)
            cb.onStatsUpdate(speed, duration != 0 ? totalDistance : 0, duration);
    }


    // =========================================================================
    // Kill-survival: SharedPreferences checkpoint + AlarmManager watchdog
    //
    // Flow on kill:
    //   onDestroy / onTaskRemoved → saveCheckpoint() + scheduleWatchdog()
    //   AlarmManager fires 60 s later → BootReceiver-style intent → service
    //   onStartCommand(null or RESUME) → tryResumeFromCheckpoint()
    //   Resume: restore tripId / startTime / distance, rejoin the in-progress trip
    // =========================================================================

    /** Persist trip state so it survives a process kill. */
    private void saveCheckpoint() {
        getSharedPreferences(PREFS_NAME, MODE_PRIVATE).edit()
                .putBoolean(PREF_IS_TRACKING,    true)
                .putLong   (PREF_TRIP_ID,         currentTripId)
                .putLong   (PREF_TRIP_START,      tripStartTime)
                .putFloat  (PREF_TOTAL_DISTANCE,  (float) totalDistance)
                .putInt    (PREF_TRIP_START_STEPS, tripStartStepCount)
                .apply();
        Log.d(TAG, "Checkpoint saved: tripId=" + currentTripId);
    }

    /** Clear the checkpoint after a normal user-initiated stop. */
    private void clearCheckpoint() {
        getSharedPreferences(PREFS_NAME, MODE_PRIVATE).edit().clear().apply();
        Log.d(TAG, "Checkpoint cleared");
    }

    /**
     * Called on START_STICKY restart (null intent) or RESUME_TRACKING intent.
     * Restores the in-progress trip without creating a new DB row.
     */
    private void tryResumeFromCheckpoint() {
        SharedPreferences prefs = getSharedPreferences(PREFS_NAME, MODE_PRIVATE);
        boolean wasTracking = prefs.getBoolean(PREF_IS_TRACKING, false);
        long    savedTripId = prefs.getLong   (PREF_TRIP_ID,    -1);
        long    savedStart  = prefs.getLong   (PREF_TRIP_START,  0);
        float   savedDist   = prefs.getFloat  (PREF_TOTAL_DISTANCE, 0f);
        int     savedSteps  = prefs.getInt    (PREF_TRIP_START_STEPS, 0);

        if (!wasTracking || savedTripId == -1) {
            Log.d(TAG, "No checkpoint to resume");
            return;
        }

        Log.d(TAG, "Resuming trip #" + savedTripId + " after kill");

        isTracking    = true;
        currentTripId = savedTripId;
        tripStartTime = savedStart;
        totalDistance = savedDist;
        tripStartStepCount = savedSteps;
        lastGpsSpeed      = 0f;
        lastGpsUpdateTime = 0L;

        startGPSTracking();

        Location seed = getBestAvailableLocation();
        if (seed != null) {
            if (!sensorTracker.isTracking()) sensorTracker.startTracking(seed);
            lastSensorLocation   = new Location(seed);
            lastGpsLocation      = new Location(seed);
            lastSavedGpsLocation = new Location(seed);
        } else {
            requestSingleLocationFix();
        }

        cancelWatchdog();
        startForegroundNotification("Tracking resumed", "Trip #" + savedTripId + " continuing");
        notifyTrackingStateChanged(true);
    }

    /** Schedule a one-shot AlarmManager alarm to restart the service if it stays dead. */
    private void scheduleWatchdog() {
        AlarmManager am = (AlarmManager) getSystemService(Context.ALARM_SERVICE);
        Intent i = new Intent(this, LocationTrackingService.class);
        i.setAction(ACTION_RESUME_TRACKING);
        PendingIntent pi = PendingIntent.getService(this, WATCHDOG_REQUEST, i,
                PendingIntent.FLAG_UPDATE_CURRENT | PendingIntent.FLAG_IMMUTABLE);
        long triggerAt = System.currentTimeMillis() + WATCHDOG_INTERVAL_MS;
        if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.M) {
            am.setExactAndAllowWhileIdle(AlarmManager.RTC_WAKEUP, triggerAt, pi);
        } else {
            am.setExact(AlarmManager.RTC_WAKEUP, triggerAt, pi);
        }
        Log.d(TAG, "Watchdog scheduled in " + (WATCHDOG_INTERVAL_MS / 1000) + "s");
    }

    /** Cancel the watchdog alarm (called when service is running normally). */
    private void cancelWatchdog() {
        AlarmManager am = (AlarmManager) getSystemService(Context.ALARM_SERVICE);
        Intent i = new Intent(this, LocationTrackingService.class);
        i.setAction(ACTION_RESUME_TRACKING);
        PendingIntent pi = PendingIntent.getService(this, WATCHDOG_REQUEST, i,
                PendingIntent.FLAG_NO_CREATE | PendingIntent.FLAG_IMMUTABLE);
        if (pi != null) {
            am.cancel(pi);
            Log.d(TAG, "Watchdog cancelled");
        }
    }

    // =========================================================================
    // Permission / notification helpers
    // =========================================================================

    private boolean hasLocationPermissions() {
        return hasPermission(Manifest.permission.ACCESS_FINE_LOCATION) ||
               hasPermission(Manifest.permission.ACCESS_COARSE_LOCATION);
    }

    private boolean hasPermission(String perm) {
        return ActivityCompat.checkSelfPermission(this, perm) == PackageManager.PERMISSION_GRANTED;
    }

    private void startForegroundNotification(String title, String text) {
        Intent launch = getPackageManager().getLaunchIntentForPackage(getPackageName());
        PendingIntent pi = PendingIntent.getActivity(this, 0, launch,
                PendingIntent.FLAG_UPDATE_CURRENT | PendingIntent.FLAG_IMMUTABLE);
        Notification n = new NotificationCompat.Builder(this, CHANNEL_ID)
                .setContentTitle(title).setContentText(text)
                .setSmallIcon(android.R.drawable.ic_menu_mylocation)
                .setContentIntent(pi).setOngoing(true)
                .setPriority(NotificationCompat.PRIORITY_LOW).build();
        if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.Q)
            startForeground(NOTIFICATION_ID, n, ServiceInfo.FOREGROUND_SERVICE_TYPE_LOCATION);
        else
            startForeground(NOTIFICATION_ID, n);
    }

    private void createNotificationChannel() {
        if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.O) {
            NotificationManager nm = getSystemService(NotificationManager.class);

            // Low-priority channel for ongoing foreground notification
            NotificationChannel ch = new NotificationChannel(
                    CHANNEL_ID, "Location Tracking", NotificationManager.IMPORTANCE_LOW);
            ch.setDescription("Tracks your location in background");
            nm.createNotificationChannel(ch);

            // High-priority channel for trip start/end and daily reminder
            NotificationChannel tripCh = new NotificationChannel(
                    CHANNEL_TRIP_EVENTS, "Trip Events", NotificationManager.IMPORTANCE_HIGH);
            tripCh.setDescription("Notifications for trip start, trip end, and daily reminders");
            tripCh.enableVibration(true);
            nm.createNotificationChannel(tripCh);
        }
    }

    /** Show a one-shot push notification for trip events (also shows on Android Auto). */
    private void showTripNotification(int notifId, String title, String text) {
        Intent launch = getPackageManager().getLaunchIntentForPackage(getPackageName());
        PendingIntent pi = PendingIntent.getActivity(this, notifId, launch,
                PendingIntent.FLAG_UPDATE_CURRENT | PendingIntent.FLAG_IMMUTABLE);
        Notification n = new NotificationCompat.Builder(this, CHANNEL_TRIP_EVENTS)
                .setContentTitle(title)
                .setContentText(text)
                .setSmallIcon(android.R.drawable.ic_menu_mylocation)
                .setContentIntent(pi)
                .setAutoCancel(true)
                .setPriority(NotificationCompat.PRIORITY_HIGH)
                .setDefaults(NotificationCompat.DEFAULT_ALL)
                .extend(new androidx.car.app.notification.CarAppExtender.Builder()
                        .setImportance(NotificationManager.IMPORTANCE_HIGH)
                        .build())
                .build();
        NotificationManager nm = (NotificationManager) getSystemService(Context.NOTIFICATION_SERVICE);
        nm.notify(notifId, n);
    }

    // =========================================================================
    // Daily reminder — fires at 6:00 AM to check yesterday's route
    // =========================================================================

    /** Schedule a repeating alarm at 6:00 AM daily. */
    private void scheduleDailyReminder() {
        AlarmManager am = (AlarmManager) getSystemService(Context.ALARM_SERVICE);
        Intent i = new Intent(this, com.carmd.triptracking.receivers.DailyReminderReceiver.class);
        PendingIntent pi = PendingIntent.getBroadcast(this, DAILY_REMINDER_REQUEST, i,
                PendingIntent.FLAG_UPDATE_CURRENT | PendingIntent.FLAG_IMMUTABLE);

        // Next 6:00 AM
        java.util.Calendar cal = java.util.Calendar.getInstance();
        cal.set(java.util.Calendar.HOUR_OF_DAY, 6);
        cal.set(java.util.Calendar.MINUTE, 0);
        cal.set(java.util.Calendar.SECOND, 0);
        cal.set(java.util.Calendar.MILLISECOND, 0);
        // If 6 AM already passed today, schedule for tomorrow
        if (cal.getTimeInMillis() <= System.currentTimeMillis()) {
            cal.add(java.util.Calendar.DAY_OF_YEAR, 1);
        }

        // Repeat every 24 hours
        am.setRepeating(AlarmManager.RTC_WAKEUP, cal.getTimeInMillis(),
                AlarmManager.INTERVAL_DAY, pi);
        Log.d(TAG, "Daily reminder scheduled at 6:00 AM");
    }

    /** Schedule a repeating alarm at 12:00 PM daily to auto-send log file. */
    private void scheduleDailyLogSender() {
        AlarmManager am = (AlarmManager) getSystemService(Context.ALARM_SERVICE);
        Intent i = new Intent(this, com.carmd.triptracking.receivers.DailyLogSenderReceiver.class);
        PendingIntent pi = PendingIntent.getBroadcast(this, DAILY_LOG_SENDER_REQUEST, i,
                PendingIntent.FLAG_UPDATE_CURRENT | PendingIntent.FLAG_IMMUTABLE);

        // Next 12:00 PM
        java.util.Calendar cal = java.util.Calendar.getInstance();
        cal.set(java.util.Calendar.HOUR_OF_DAY, 12);
        cal.set(java.util.Calendar.MINUTE, 0);
        cal.set(java.util.Calendar.SECOND, 0);
        cal.set(java.util.Calendar.MILLISECOND, 0);
        // If 12 PM already passed today, schedule for tomorrow
        if (cal.getTimeInMillis() <= System.currentTimeMillis()) {
            cal.add(java.util.Calendar.DAY_OF_YEAR, 1);
        }

        am.setRepeating(AlarmManager.RTC_WAKEUP, cal.getTimeInMillis(),
                AlarmManager.INTERVAL_DAY, pi);
        Log.d(TAG, "Daily log sender scheduled at 12:00 PM");
    }
}
