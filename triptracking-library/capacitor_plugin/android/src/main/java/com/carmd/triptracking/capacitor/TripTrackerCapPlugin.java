package com.carmd.triptracking.capacitor;

import android.content.ComponentName;
import android.content.Context;
import android.content.Intent;
import android.content.ServiceConnection;
import android.content.SharedPreferences;
import android.net.Uri;
import android.os.IBinder;

import androidx.core.content.FileProvider;
import com.carmd.triptracking.TripTrackerSDK;
import com.carmd.triptracking.database.LocationDatabase;
import com.carmd.triptracking.geofence.GeofenceManager;
import com.carmd.triptracking.services.LocationTrackingService;
import com.carmd.triptracking.ui.AppSettings;
import com.carmd.triptracking.database.LocationDatabase;
import com.carmd.triptracking.geofence.GeofenceManager;
import com.carmd.triptracking.services.LocationTrackingService;
import com.carmd.triptracking.ui.AppSettings;
import com.carmd.triptracking.ui.DailyLocationsActivity;
import com.carmd.triptracking.ui.GeofenceSettingsActivity;
import com.carmd.triptracking.ui.MainActivity;
import com.carmd.triptracking.ui.NotificationSettingsActivity;
import com.carmd.triptracking.ui.SettingsActivity;
import com.carmd.triptracking.ui.TripHistoryActivity;
import com.carmd.triptracking.util.VoiceFeedback;

import com.getcapacitor.JSArray;
import com.getcapacitor.JSObject;
import com.getcapacitor.Plugin;
import com.getcapacitor.PluginCall;
import com.getcapacitor.PluginMethod;
import com.getcapacitor.annotation.CapacitorPlugin;

import org.json.JSONException;
import org.json.JSONObject;

import java.io.File;
import java.util.ArrayList;
import java.util.List;
import com.carmd.triptracking.util.LogcatWriter;
import com.carmd.triptracking.api.TripTrackerAPIService;


@CapacitorPlugin(name = "TripTracker")
public class TripTrackerCapPlugin extends Plugin {

    private LocationTrackingService trackingService;
    private boolean serviceBound = false;

    // Static self-reference so LocationTrackingService can call emitMotionChange via reflection
    private static TripTrackerCapPlugin instance;

    // ── Event name constants ──────────────────────────────────────────────────
    private static final String EVENT_ACTIVITY_CHANGE     = "activityChange";
    private static final String EVENT_LOCATION_UPDATE     = "locationUpdate";
    private static final String EVENT_TRACKING_STATE      = "trackingStateChange";
    private static final String EVENT_STATS_UPDATE        = "statsUpdate";

    /**
     * Called via reflection from LocationTrackingService.emitMotionChange().
     * Must be public static — no hard compile-time dependency on this class from the service.
     *
     * @param activity   "IN_VEHICLE" | "STILL" | "MOVING" | "WALKING" | "ON_BICYCLE"
     * @param transition "ENTER" | "EXIT"  (Activity Recognition)
     *                   "SENSOR"          (SensorBasedLocationTracker accelerometer)
     */
    public static void emitMotionChange(String activity, String transition) {
        if (instance == null) return;
        JSObject data = new JSObject();
        data.put("activity", activity);
        data.put("transition", transition);
        instance.notifyListeners(EVENT_ACTIVITY_CHANGE, data);
    }

    private final ServiceConnection serviceConnection = new ServiceConnection() {
        @Override
        public void onServiceConnected(ComponentName name, IBinder binder) {
            LocationTrackingService.LocalBinder localBinder =
                    (LocationTrackingService.LocalBinder) binder;
            trackingService = localBinder.getService();
            serviceBound = true;
        }
        @Override
        public void onServiceDisconnected(ComponentName name) {
            trackingService = null;
            serviceBound = false;
        }
    };

    @Override
    public void load() {
        instance = this;  // register static reference for emitMotionChange()
        // Service is always started by SDK. Bind to it.
        bindToServiceIfRunning();
    }

    @Override
    protected void handleOnResume() {
        super.handleOnResume();
        // User may have just granted permission in Settings
        if (TripTrackerSDK.isInitialized() && TripTrackerSDK.hasLocationPermission(getContext())) {
            TripTrackerSDK.onPermissionGranted(getContext());
            if (!serviceBound) bindToServiceIfRunning();
        }
        // Ping server with current location when app returns to foreground.
        if (TripTrackerSDK.isInitialized() && TripTrackerSDK.hasLocationPermission(getContext())
                && trackingService != null) {
            trackingService.requestCurrentLocation(15_000, new LocationTrackingService.LocationCallback() {
                @Override public void onLocation(android.location.Location loc) {
                    android.util.Log.d("TripTrackerCap", "handleOnResume — location pinged ("
                            + loc.getLatitude() + ", " + loc.getLongitude() + ")");
                }
                @Override public void onError(String error) {
                    android.util.Log.d("TripTrackerCap", "handleOnResume — location unavailable: " + error);
                }
            });
        }
    }

    /** Bind to service if it's running. */
    private void bindToServiceIfRunning() {
        if (serviceBound) return;
        try {
            Intent intent = new Intent(getContext(), LocationTrackingService.class);
            getContext().bindService(intent, serviceConnection, Context.BIND_AUTO_CREATE);
        } catch (Exception e) {
            android.util.Log.e("TripTrackerCap", "bindService failed: " + e.getMessage());
        }
    }

    // ═══════════════════════════════════════════════════════════════════
    // Permission & Tracking Control
    // ═══════════════════════════════════════════════════════════════════

    @PluginMethod
    public void hasLocationPermission(PluginCall call) {
        boolean granted = TripTrackerSDK.hasLocationPermission(getContext());
        if (granted) {
            TripTrackerSDK.onPermissionGranted(getContext());
        }
        JSObject ret = new JSObject();
        ret.put("granted", granted);
        call.resolve(ret);
    }

    @PluginMethod
    public void updateVehicleId(PluginCall call) {
        String vehicleId = call.getString("vehicleId");
        if (vehicleId == null) {
            call.reject("Missing 'vehicleId'");
            return;
        }
        TripTrackerSDK.updateVehicleId(vehicleId);
        JSObject ret = new JSObject();
        ret.put("updated", true);
        ret.put("vehicleId", vehicleId);
        call.resolve(ret);
    }

    @PluginMethod
    public void updateToolId(PluginCall call) {
        String toolId = call.getString("toolId");
        if (toolId == null) {
            call.reject("Missing 'toolId'");
            return;
        }
        TripTrackerAPIService.getInstance().updateToolId(toolId);
        JSObject ret = new JSObject();
        ret.put("updated", true);
        ret.put("toolId", toolId);
        call.resolve(ret);
    }

    @PluginMethod
    public void startTracking(PluginCall call) {
        if (!TripTrackerSDK.hasLocationPermission(getContext())) {
            call.reject("Location permission not granted. Grant permission first.");
            return;
        }
        TripTrackerSDK.startTracking(getContext());
        bindToServiceIfRunning();
        JSObject ret = new JSObject();
        ret.put("started", true);
        call.resolve(ret);
    }

    @PluginMethod
    public void stopTracking(PluginCall call) {
        TripTrackerSDK.stopTracking(getContext());
        JSObject ret = new JSObject();
        ret.put("stopped", true);
        call.resolve(ret);
    }

    // logd truncates any single entry at ~4076 bytes (UTF-8, whole entry
    // including tag); split longer messages into multiple lines so nothing
    // gets cut off, regardless of how much of the payload is multi-byte.
    private static final int LOG_CHUNK_BYTES = 3500;

    @PluginMethod
    public void writeLog(PluginCall call) {
        String message = call.getString("message", "");
        logChunked("⚡️ [Ionic] ", message);
        call.resolve();
    }

    private static void logChunked(String tag, String message) {
        if (message == null) message = "";
        byte[] bytes = message.getBytes(java.nio.charset.StandardCharsets.UTF_8);
        if (bytes.length <= LOG_CHUNK_BYTES) {
            android.util.Log.i(tag, message);
            return;
        }

        List<String> chunks = new ArrayList<>();
        int offset = 0;
        while (offset < bytes.length) {
            int end = Math.min(offset + LOG_CHUNK_BYTES, bytes.length);
            // Don't split in the middle of a multi-byte UTF-8 sequence —
            // back off until we land on a lead byte (not a 10xxxxxx continuation byte).
            while (end > offset && end < bytes.length && (bytes[end] & 0xC0) == 0x80) {
                end--;
            }
            chunks.add(new String(bytes, offset, end - offset, java.nio.charset.StandardCharsets.UTF_8));
            offset = end;
        }

        for (int i = 0; i < chunks.size(); i++) {
            android.util.Log.i(tag, "[" + (i + 1) + "/" + chunks.size() + "] " + chunks.get(i));
        }
    }

    @PluginMethod
    public void endTrip(PluginCall call) {
        if (trackingService == null || !serviceBound) {
            call.resolve(new JSObject().put("ended", false).put("reason", "Service not bound"));
            return;
        }
        if (!trackingService.isCurrentlyTracking()) {
            call.resolve(new JSObject().put("ended", false).put("reason", "No active trip"));
            return;
        }
        long tripId = trackingService.getCurrentTripId();
        trackingService.forceEndTrip();
        TripTrackerAPIService.getInstance().flushQueue();
        call.resolve(new JSObject().put("ended", true).put("tripId", tripId));
    }

    // ═══════════════════════════════════════════════════════════════════
    // Native Pages
    // ═══════════════════════════════════════════════════════════════════

    @PluginMethod
    public void initializeWithConfig(PluginCall call) {
        TripTrackerSDK.Config config = new TripTrackerSDK.Config();

        Double saveInterval = call.getDouble("saveIntervalMinutes");
        if (saveInterval != null) config.saveIntervalMinutes = saveInterval;

        Double saveDist = call.getDouble("saveDistanceMeters");
        if (saveDist != null) config.saveDistanceMeters = saveDist;

        Double vehicleThresh = call.getDouble("vehicleThreshold");
        if (vehicleThresh != null) config.vehicleThreshold = vehicleThresh.floatValue();

        Integer transport = call.getInt("transportType");
        if (transport != null) config.transportType = transport;

        Double autoStop = call.getDouble("autoStopTimeoutMinutes");
        if (autoStop != null) config.autoStopTimeoutMinutes = autoStop;

        Double routeGap = call.getDouble("routeGapMeters");
        if (routeGap != null) config.routeGapMeters = routeGap;

        Boolean geofence = call.getBoolean("geofenceEnabled");
        if (geofence != null) config.geofenceEnabled = geofence;

        Boolean webMon = call.getBoolean("webMonitorEnabled");
        if (webMon != null) config.webMonitorEnabled = webMon;

        Boolean voice = call.getBoolean("voiceFeedbackEnabled");
        if (voice != null) config.voiceFeedbackEnabled = voice;

        Boolean nStart = call.getBoolean("notifyTripStart");
        if (nStart != null) config.notifyTripStart = nStart;

        Boolean nEnd = call.getBoolean("notifyTripEnd");
        if (nEnd != null) config.notifyTripEnd = nEnd;
        // notifyTrip sets both start and end together
        Boolean nTrip = call.getBoolean("notifyTrip");
        if (nTrip != null) { config.notifyTripStart = nTrip; config.notifyTripEnd = nTrip; }

        Boolean nDist = call.getBoolean("notifyDistanceKm");
        if (nDist != null) config.notifyDistanceKm = nDist;

        Boolean nEnter = call.getBoolean("notifyGeofenceEnter");
        if (nEnter != null) config.notifyGeofenceEnter = nEnter;

        Boolean nExit = call.getBoolean("notifyGeofenceExit");
        if (nExit != null) config.notifyGeofenceExit = nExit;

        String pingURL = call.getString("pingURL");
        if (pingURL != null) config.pingURL = pingURL;
        String endURL = call.getString("endURL");
        if (endURL != null) config.endURL = endURL;
        String userId = call.getString("userId");
        if (userId != null) config.userId = userId;
        String vehicleId = call.getString("vehicleId");
        if (vehicleId != null) config.vehicleId = vehicleId;
        String osInfo = call.getString("osInfo");
        if (osInfo != null) config.osInfo = osInfo;
        String routeId = call.getString("routeId");
        if (routeId != null) config.routeId = routeId;
        String authKey = call.getString("authorizationKey");
        if (authKey != null) config.authorizationKey = authKey;
        String apiAuth = call.getString("apiAuthKey");
        if (apiAuth != null) config.apiAuthKey = apiAuth;
        String apiAuthTok = call.getString("apiAuthToken");
        if (apiAuthTok != null) config.apiAuthToken = apiAuthTok;

        TripTrackerSDK.initialize(getContext(), config);

        // Service always starts — bind to it
        boolean permGranted = TripTrackerSDK.hasLocationPermission(getContext());
        bindToServiceIfRunning();

        // Request current location shortly after init so first ping fires immediately
        if (permGranted) {
            new android.os.Handler(android.os.Looper.getMainLooper()).postDelayed(() -> {
                LocationTrackingService svc = LocationTrackingService.getInstance();
                if (svc == null) return;
                svc.requestCurrentLocation(15_000, new LocationTrackingService.LocationCallback() {
                    @Override public void onLocation(android.location.Location loc) {
                        android.util.Log.d("TripTrackerCap", "init ping OK ("
                                + loc.getLatitude() + ", " + loc.getLongitude() + ")");
                    }
                    @Override public void onError(String error) {
                        android.util.Log.d("TripTrackerCap", "init ping failed: " + error);
                    }
                });
            }, 1_000);
        }

        JSObject ret = new JSObject();
        ret.put("initialized", true);
        ret.put("permissionGranted", permGranted);
        ret.put("trackingStarted", true);  // Service always starts
        call.resolve(ret);
    }

    @PluginMethod
    public void openSettings(PluginCall call) {
        launchActivity(SettingsActivity.class);
        JSObject ret = new JSObject();
        ret.put("opened", true);
        call.resolve(ret);
    }

    @PluginMethod
    public void openNotificationSettings(PluginCall call) {
        launchActivity(NotificationSettingsActivity.class);
        JSObject ret = new JSObject();
        ret.put("opened", true);
        call.resolve(ret);
    }

    @PluginMethod
    public void openGeofenceManager(PluginCall call) {
        launchActivity(GeofenceSettingsActivity.class);
        JSObject ret = new JSObject();
        ret.put("opened", true);
        call.resolve(ret);
    }

    @PluginMethod
    public void openMainView(PluginCall call) {
        launchActivity(MainActivity.class);
        JSObject ret = new JSObject();
        ret.put("opened", true);
        call.resolve(ret);
    }

    @PluginMethod
    public void openHistory(PluginCall call) {
        launchActivity(TripHistoryActivity.class);
        JSObject ret = new JSObject();
        ret.put("opened", true);
        call.resolve(ret);
    }

    @PluginMethod
    public void openDailyLocations(PluginCall call) {
        launchActivity(DailyLocationsActivity.class);
        JSObject ret = new JSObject();
        ret.put("opened", true);
        call.resolve(ret);
    }

    // ═══════════════════════════════════════════════════════════════════
    // Tracking Status
    // ═══════════════════════════════════════════════════════════════════

    @PluginMethod
    public void getTrackingStatus(PluginCall call) {
        JSObject ret = new JSObject();
        if (trackingService != null && serviceBound) {
            float speed = trackingService.getEffectiveSpeed();
            ret.put("isTracking", trackingService.isCurrentlyTracking());
            ret.put("speed", (double) speed);
            ret.put("speedKmh", (double) speed * 3.6);
            ret.put("distance", trackingService.getTotalDistance());
            ret.put("duration", trackingService.getCurrentTripDuration());
            ret.put("steps", trackingService.getCurrentTripSteps());
            ret.put("tripId", trackingService.getCurrentTripId());

            android.location.Location loc = trackingService.getLastKnownLocation();
            if (loc != null) {
                ret.put("latitude", loc.getLatitude());
                ret.put("longitude", loc.getLongitude());
            }
        } else {
            ret.put("isTracking", false);
            ret.put("speed", 0.0);
            ret.put("speedKmh", 0.0);
            ret.put("distance", 0.0);
            ret.put("duration", 0L);
            ret.put("steps", 0);
            ret.put("tripId", 0L);
        }
        call.resolve(ret);
    }

    @PluginMethod
    public void getCurrentLocation(PluginCall call) {
        call.setKeepAlive(true);
        int timeoutMs = (int)(15f * 1000);
        LocationTrackingService svc = (trackingService != null)
                ? trackingService : LocationTrackingService.getInstance();
        if (svc == null) {
            call.reject("LocationTrackingService not available");
            return;
        }

        svc.requestCurrentLocation(timeoutMs, new LocationTrackingService.LocationCallback() {
            @Override
            public void onLocation(android.location.Location loc) {
                JSObject ret = new JSObject();
                ret.put("latitude",  loc.getLatitude());
                ret.put("longitude", loc.getLongitude());
                ret.put("speed",     (double) loc.getSpeed());
                ret.put("speedKmh",  (double) loc.getSpeed() * 3.6);
                ret.put("accuracy",  (double) loc.getAccuracy());
                ret.put("bearing",   (double) loc.getBearing());
                ret.put("altitude",  loc.getAltitude());
                ret.put("timestamp", loc.getTime());
                call.resolve(ret);
            }
            @Override
            public void onError(String error) {
                call.reject(error);
            }
        });
    }


    // ═══════════════════════════════════════════════════════════════════
    // Trip History
    // ═══════════════════════════════════════════════════════════════════

    @PluginMethod
    public void getTripHistory(PluginCall call) {
        int limit = call.getInt("limit", 50);
        LocationDatabase db = LocationDatabase.getInstance(getContext());
        List<LocationDatabase.Trip> trips = db.getAllTrips();

        JSArray tripArr = new JSArray();
        int count = Math.min(trips.size(), limit);
        for (int i = 0; i < count; i++) {
            LocationDatabase.Trip t = trips.get(i);
            JSObject obj = new JSObject();
            obj.put("id", t.id);
            obj.put("startTime", t.startTime);
            obj.put("endTime", t.endTime);
            obj.put("distance", t.distance);
            obj.put("duration", t.duration);
            obj.put("steps", t.steps);
            obj.put("isActive", "active".equals(t.status));
            tripArr.put(obj);
        }

        JSObject ret = new JSObject();
        ret.put("trips", tripArr);
        ret.put("count", count);
        call.resolve(ret);
    }

    // ═══════════════════════════════════════════════════════════════════
    // Settings
    // ═══════════════════════════════════════════════════════════════════

    @PluginMethod
    public void getSettings(PluginCall call) {
        Context ctx = getContext();
        JSObject ret = new JSObject();
        ret.put("vehicleThreshold", (double) AppSettings.getVehicleSpeed(ctx));
        ret.put("vehicleThresholdKmh", (double) AppSettings.getVehicleSpeed(ctx) * 3.6);
        ret.put("saveIntervalMinutes", (double) AppSettings.getStillInterval(ctx));
        ret.put("saveDistanceMeters", (double) AppSettings.getVehicleDistance(ctx));
        ret.put("autoEndTimeoutMinutes", (double) AppSettings.getAutoStopTimeout(ctx));
        ret.put("routeGapThresholdMeters", (double) AppSettings.getRouteGap(ctx));
        ret.put("webMonitorEnabled", AppSettings.isWebServerEnabled(ctx));
        ret.put("voiceFeedbackEnabled", AppSettings.isVoiceEnabled(ctx));
        ret.put("geofencingEnabled", GeofenceManager.isEnabled(ctx));
        ret.put("notifyTripStart", AppSettings.isNotifTripStart(ctx));
        ret.put("notifyTripEnd", AppSettings.isNotifTripEnd(ctx));
        ret.put("notifyDistanceKm", AppSettings.isNotifDistanceKm(ctx));
        ret.put("notifyGeofenceEnter", AppSettings.isNotifGeofenceEnter(ctx));
        ret.put("notifyGeofenceExit", AppSettings.isNotifGeofenceExit(ctx));
        call.resolve(ret);
    }

    @PluginMethod
    public void updateSetting(PluginCall call) {
        String key = call.getString("key");
        if (key == null) { call.reject("Missing 'key'"); return; }

        Context ctx = getContext();
        SharedPreferences prefs = ctx.getSharedPreferences("triptracker_settings", Context.MODE_PRIVATE);
        SharedPreferences.Editor editor = prefs.edit();

        switch (key) {
            case "vehicleThreshold":
                editor.putFloat(AppSettings.KEY_VEHICLE_SPEED, call.getFloat("value", 6f)); break;
            case "saveIntervalMinutes":
                editor.putFloat(AppSettings.KEY_STILL_INTERVAL, call.getFloat("value", 5f)); break;
            case "saveDistanceMeters":
                editor.putFloat(AppSettings.KEY_VEHICLE_DISTANCE, call.getFloat("value", 30f)); break;
            case "autoEndTimeoutMinutes":
                editor.putFloat(AppSettings.KEY_AUTO_STOP_TIMEOUT, call.getFloat("value", 2f)); break;
            case "routeGapThresholdMeters":
                editor.putFloat(AppSettings.KEY_ROUTE_GAP, call.getFloat("value", 500f)); break;
            case "webMonitorEnabled":
                AppSettings.setWebServerEnabled(ctx, call.getBoolean("value", false)); break;
            case "voiceFeedbackEnabled":
                AppSettings.setVoiceEnabled(ctx, call.getBoolean("value", true)); break;
            case "geofencingEnabled":
                boolean enabled = call.getBoolean("value", false);
                GeofenceManager.setEnabled(ctx, enabled);
                if (enabled) GeofenceManager.registerAll(ctx);
                else GeofenceManager.unregisterAll(ctx);
                break;
            case "notifyTrip":
                boolean notifyTrip = call.getBoolean("value", true);
                AppSettings.setNotifTripStart(ctx, notifyTrip);
                AppSettings.setNotifTripEnd(ctx, notifyTrip);
                break;
            case "notifyTripStart":
                AppSettings.setNotifTripStart(ctx, call.getBoolean("value", true)); break;
            case "notifyTripEnd":
                AppSettings.setNotifTripEnd(ctx, call.getBoolean("value", true)); break;
            default:
                call.reject("Unknown setting: " + key); return;
        }
        editor.apply();
        call.resolve(new JSObject().put("key", key).put("updated", true));
    }

    // ─────────────────────────────────────────────────────────────────────────
    // Trip notification toggles (dedicated method from Ionic)
    // ─────────────────────────────────────────────────────────────────────────

    /**
     * Enable or disable trip start / end push notifications.
     * options:
     *   { notify: bool }           — sets both start AND end together
     *   { start: bool, end: bool } — set each individually
     */
    @PluginMethod
    public void setTripNotifications(PluginCall call) {
        Context ctx = getContext();
        Boolean notify = call.getBoolean("notify");
        if (notify != null) {
            AppSettings.setNotifTripStart(ctx, notify);
            AppSettings.setNotifTripEnd(ctx, notify);
        } else {
            Boolean start = call.getBoolean("start");
            Boolean end   = call.getBoolean("end");
            if (start != null) AppSettings.setNotifTripStart(ctx, start);
            if (end   != null) AppSettings.setNotifTripEnd(ctx, end);
        }
        JSObject ret = new JSObject();
        ret.put("notifyTripStart", AppSettings.isNotifTripStart(ctx));
        ret.put("notifyTripEnd",   AppSettings.isNotifTripEnd(ctx));
        call.resolve(ret);
    }

    // ═══════════════════════════════════════════════════════════════════
    // Geofence
    // ═══════════════════════════════════════════════════════════════════

    @PluginMethod
    public void getGeofenceZones(PluginCall call) {
        List<GeofenceManager.GeofenceZone> zones = GeofenceManager.getAll(getContext());
        JSArray arr = new JSArray();
        for (GeofenceManager.GeofenceZone z : zones) {
            JSObject obj = new JSObject();
            obj.put("id", z.id);
            obj.put("name", z.name);
            obj.put("latitude", z.latitude);
            obj.put("longitude", z.longitude);
            obj.put("radius", z.radiusMeters);
            obj.put("notifyOnEnter", z.notifyOnEnter);
            obj.put("notifyOnExit", z.notifyOnExit);
            obj.put("autoStopOnEnter", z.autoStopTrip);
            arr.put(obj);
        }
        JSObject ret = new JSObject();
        ret.put("zones", arr);
        ret.put("count", zones.size());
        call.resolve(ret);
    }

    @PluginMethod
    public void addGeofenceZone(PluginCall call) {
        String name = call.getString("name");
        Double lat = call.getDouble("latitude");
        Double lon = call.getDouble("longitude");
        if (name == null || lat == null || lon == null) {
            call.reject("Missing name/latitude/longitude"); return;
        }

      Double radiusDouble = call.getDouble("radius");
      float radiusMeters = radiusDouble != null ? radiusDouble.floatValue() : 200.0f;

      GeofenceManager.GeofenceZone zone = new GeofenceManager.GeofenceZone(
        name, lat, lon,
        radiusMeters,
        call.getBoolean("notifyOnEnter", true),
        call.getBoolean("notifyOnExit", true),
        call.getBoolean("autoStopOnEnter", false)
      );
        GeofenceManager.addZone(getContext(), zone);
        GeofenceManager.registerAll(getContext());

        JSObject ret = new JSObject();
        ret.put("id", zone.id);
        ret.put("added", true);
        call.resolve(ret);
    }

    @PluginMethod
    public void removeGeofenceZone(PluginCall call) {
        String id = call.getString("id");
        if (id == null) { call.reject("Missing 'id'"); return; }
        GeofenceManager.removeZone(getContext(), id);

        JSObject ret = new JSObject();
        ret.put("id", id);
        ret.put("removed", true);
        call.resolve(ret);
    }

    // ═══════════════════════════════════════════════════════════════════
    // Web Monitor
    // ═══════════════════════════════════════════════════════════════════

    @PluginMethod
    public void startWebMonitor(PluginCall call) {
        AppSettings.setWebServerEnabled(getContext(), true);
        JSObject ret = new JSObject();
        ret.put("started", true);
        call.resolve(ret);
    }

    @PluginMethod
    public void stopWebMonitor(PluginCall call) {
        AppSettings.setWebServerEnabled(getContext(), false);
        JSObject ret = new JSObject();
        ret.put("stopped", true);
        call.resolve(ret);
    }

    // ═══════════════════════════════════════════════════════════════════
    // Logs
    // ═══════════════════════════════════════════════════════════════════

    @PluginMethod
    public void sendTodayLog(PluginCall call) {
        shareLogFiles(0);  // 0 = today only
        JSObject ret = new JSObject();
        ret.put("shared", true);
        call.resolve(ret);
    }

    @PluginMethod
    public void sendAllLogs(PluginCall call) {
        shareLogFiles(3);  // 3 = last 3 days
        JSObject ret = new JSObject();
        ret.put("shared", true);
        call.resolve(ret);
    }

    @PluginMethod
    public void sendRecentLogs(PluginCall call) {
        int days = call.getInt("days", 3);
        Integer zipDays = (days == -1) ? null : (days == 0 ? 1 : days);
        File zip = com.carmd.triptracking.util.LogcatWriter.getZippedLogs(getContext(), zipDays);
        if (zip == null) {
            call.reject("No log files found or zip failed");
            return;
        }
        // Copy to external cache so path is accessible
        File outDir = getContext().getExternalCacheDir();
        if (outDir == null) outDir = getContext().getCacheDir();
        File shareFile = new File(outDir, zip.getName());
        try {
            java.nio.file.Files.copy(zip.toPath(), shareFile.toPath(),
                    java.nio.file.StandardCopyOption.REPLACE_EXISTING);
        } catch (Exception e) {
            call.reject("Failed to prepare zip: " + e.getMessage());
            return;
        }

        shareLogFiles(days);
        JSObject ret = new JSObject();
        ret.put("path", shareFile.getAbsolutePath());
        call.resolve(ret);
    }

    @PluginMethod
    public void resetConfig(PluginCall call) {
        TripTrackerSDK.resetConfig(getContext());
        JSObject ret = new JSObject();
        ret.put("reset", true);
        call.resolve(ret);
    }

    // ═══════════════════════════════════════════════════════════════════
    // Helpers
    // ═══════════════════════════════════════════════════════════════════

    private void launchActivity(Class<?> cls) {
        Intent intent = new Intent(getContext(), cls);
        intent.addFlags(Intent.FLAG_ACTIVITY_NEW_TASK);
        getContext().startActivity(intent);
    }

    /**
     * Share log files via share sheet (email, etc.)
     * @param days  0 = today only, -1 = all, N = last N days
     */
    private void shareLogFiles(int days) {
    if (getActivity() == null) return;

    Integer zipDays = (days == -1) ? null : (days == 0 ? 1 : days);
    File zip = com.carmd.triptracking.util.LogcatWriter.getZippedLogs(getContext(), zipDays);
    if (zip == null) return;

    String subject;
    if (days == 0) subject = "TripTracker Today's Log";
    else if (days == -1) subject = "TripTracker All Logs";
    else subject = "TripTracker Logs — Last " + days + " days";

    try {
        // Copy zip to external cache — bypasses FileProvider permission issues
        File externalDir = getContext().getExternalCacheDir();
        if (externalDir == null) externalDir = getContext().getCacheDir();
        File shareFile = new File(externalDir, zip.getName());
        java.nio.file.Files.copy(zip.toPath(), shareFile.toPath(),
                java.nio.file.StandardCopyOption.REPLACE_EXISTING);

        Uri uri = androidx.core.content.FileProvider.getUriForFile(
                getContext(),
                getContext().getPackageName() + ".fileprovider",
                shareFile);

        Intent intent = new Intent(Intent.ACTION_SEND);
        intent.setType("application/zip");
        intent.putExtra(Intent.EXTRA_STREAM, uri);
        intent.putExtra(Intent.EXTRA_SUBJECT, subject);
        intent.addFlags(Intent.FLAG_GRANT_READ_URI_PERMISSION);

        // Grant permission explicitly to all possible receivers
        getContext().grantUriPermission(
                "android", uri, Intent.FLAG_GRANT_READ_URI_PERMISSION);

        getActivity().startActivity(Intent.createChooser(intent, subject));
    } catch (Exception e) {
        android.util.Log.e("TripTrackerPlugin", "Share failed: " + e.getMessage());
    }
}
    // private void shareLogFiles(int days) {
    //     if (getActivity() == null) return;

    //     // Collect dates to include
    //     java.util.Set<String> datesToInclude = new java.util.HashSet<>();
    //     java.text.SimpleDateFormat sdf = new java.text.SimpleDateFormat("yyyy-MM-dd", java.util.Locale.US);
    //     if (days >= 0) {
    //         int count = (days == 0) ? 1 : days;
    //         java.util.Calendar cal = java.util.Calendar.getInstance();
    //         for (int i = 0; i < count; i++) {
    //             datesToInclude.add(sdf.format(cal.getTime()));
    //             cal.add(java.util.Calendar.DAY_OF_YEAR, -1);
    //         }
    //     }

    //     // Get files from LogcatWriter (uses getCacheDir, prefix "triptracker_logcat_")
    //     File[] logFiles = com.carmd.triptracking.util.LogcatWriter.getAllLogFiles(getContext());
    //     if (logFiles == null || logFiles.length == 0) return;

    //     ArrayList<Uri> uris = new ArrayList<>();
    //     for (File f : logFiles) {
    //         if (days == -1) {
    //             // All files
    //             uris.add(getUriForFile(f));
    //         } else {
    //             // Filter by date
    //             for (String date : datesToInclude) {
    //                 if (f.getName().contains(date)) {
    //                     uris.add(getUriForFile(f));
    //                     break;
    //                 }
    //             }
    //         }
    //     }
    //     if (uris.isEmpty()) return;

    //     String subject;
    //     if (days == 0) {
    //         subject = "TripTracker Today's Log";
    //     } else if (days == -1) {
    //         subject = "TripTracker All Logs (" + logFiles.length + " files)";
    //     } else {
    //         subject = "TripTracker Logs — Last " + days + " days";
    //     }

    //     Intent shareIntent = new Intent(Intent.ACTION_SEND_MULTIPLE);
    //     shareIntent.setType("text/plain");
    //     shareIntent.putParcelableArrayListExtra(Intent.EXTRA_STREAM, uris);
    //     shareIntent.putExtra(Intent.EXTRA_SUBJECT, subject);
    //     shareIntent.addFlags(Intent.FLAG_GRANT_READ_URI_PERMISSION);
    //     getActivity().startActivity(Intent.createChooser(shareIntent, subject));
    // }

    private Uri getUriForFile(File f) {
        return FileProvider.getUriForFile(getContext(),
                getContext().getPackageName() + ".fileprovider", f);
    }
}
