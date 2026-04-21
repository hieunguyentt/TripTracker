package com.carmd.triptracking;

import android.app.Activity;
import android.content.Context;
import android.content.Intent;
import android.content.SharedPreferences;
import android.content.pm.PackageManager;
import android.util.Log;
import androidx.core.content.ContextCompat;
import com.carmd.triptracking.api.TripTrackerAPIService;
import com.carmd.triptracking.database.LocationDatabase;
import com.carmd.triptracking.geofence.GeofenceManager;
import com.carmd.triptracking.services.LocationTrackingService;
import com.carmd.triptracking.ui.*;
import com.carmd.triptracking.util.LogcatWriter;
import com.carmd.triptracking.util.VoiceFeedback;

public final class TripTrackerSDK {
    private static final String TAG = "TripTrackerSDK";
    private static Context appContext;
    private static boolean initialized = false;
    private TripTrackerSDK() {}

    public static class Config {
        // Save & Tracking
        public double saveIntervalMinutes = 15.0;
        public double saveDistanceMeters = 30.0;
        public float  vehicleThreshold = 6.0f;
        public int    transportType = 0;
        public double autoStopTimeoutMinutes = 5.0;
        public double routeGapMeters = 500.0;

        // Features
        public boolean geofenceEnabled = false;
        public boolean webMonitorEnabled = false;
        public boolean voiceFeedbackEnabled = false;

        // Notifications
        public boolean notifyTripStart = false;
        public boolean notifyTripEnd = false;
        public boolean notifyDistanceKm = false;
        public boolean notifyGeofenceEnter = false;
        public boolean notifyGeofenceExit = false;

        // API
        public String pingURL = "";
        public String endURL = "";
        public String userId = "";
        public String vehicleId = "";
        public String osInfo = "";
        public String routeId = "";
        public String authorizationKey = "";
        public String apiAuthKey = "";
        public String apiAuthToken = "";   // NEW header: api-auth-token

        public Config() {}

        // Builder setters
        public Config saveInterval(double v)     { saveIntervalMinutes = v; return this; }
        public Config saveDistance(double v)       { saveDistanceMeters = v; return this; }
        public Config vehicleSpeed(float v)        { vehicleThreshold = v; return this; }
        public Config transport(int v)              { transportType = v; return this; }
        public Config autoStopTimeout(double v)    { autoStopTimeoutMinutes = v; return this; }
        public Config routeGap(double v)            { routeGapMeters = v; return this; }
        public Config geofence(boolean v)           { geofenceEnabled = v; return this; }
        public Config webMonitor(boolean v)         { webMonitorEnabled = v; return this; }
        public Config voice(boolean v)              { voiceFeedbackEnabled = v; return this; }
        public Config notifTripStart(boolean v)     { notifyTripStart = v; return this; }
        public Config notifTripEnd(boolean v)       { notifyTripEnd = v; return this; }
        public Config notifDistanceKm(boolean v)    { notifyDistanceKm = v; return this; }
        public Config notifGeofenceEnter(boolean v) { notifyGeofenceEnter = v; return this; }
        public Config notifGeofenceExit(boolean v)  { notifyGeofenceExit = v; return this; }
        public Config pingUrl(String v)             { pingURL = v; return this; }
        public Config endUrl(String v)              { endURL = v; return this; }
        public Config user(String v)                { userId = v; return this; }
        public Config vehicle(String v)             { vehicleId = v; return this; }
        public Config os(String v)                  { osInfo = v; return this; }
        public Config route(String v)               { routeId = v; return this; }
        public Config authorization(String v)       { authorizationKey = v; return this; }
        public Config apiAuth(String v)             { apiAuthKey = v; return this; }
        public Config apiAuthToken(String v)        { apiAuthToken = v; return this; }
    }

    // ═══════════════════════════════════════════════════════════════
    // Initialize — ALWAYS starts the service
    // ═══════════════════════════════════════════════════════════════

    public static void initialize(Context context) {
        initialize(context, new Config());
    }

    public static void initialize(Context context, Config config) {
        if (initialized) { applyConfig(context, config); return; }
        appContext = context.getApplicationContext();
        applyConfig(appContext, config);
        LogcatWriter.start(appContext);
        LocationDatabase.getInstance(appContext);

        // ALWAYS start the service — it handles permission internally.
        // Service starts with minimal notification if no permission,
        // then upgrades to full location tracking when permission granted.
        try {
            Intent si = new Intent(appContext, LocationTrackingService.class);
            appContext.startForegroundService(si);
            Log.i(TAG, "✅ Service started");
        } catch (Exception e) {
            Log.e(TAG, "Service start failed: " + e.getMessage());
        }

        VoiceFeedback.getInstance(appContext);
        if (config.geofenceEnabled && hasLocationPermission(appContext)) {
            GeofenceManager.registerAll(appContext);
        }
        initialized = true;
        Log.i(TAG, "✅ TripTrackerSDK initialized");
    }

    // ═══════════════════════════════════════════════════════════════
    // Apply config — settings + API (API only works if URLs set)
    // ═══════════════════════════════════════════════════════════════

    public static void applyConfig(Context ctx, Config config) {
        SharedPreferences.Editor ed = ctx.getSharedPreferences("triptracker_settings", Context.MODE_PRIVATE).edit();
        ed.putFloat(AppSettings.KEY_STILL_INTERVAL, (float) config.saveIntervalMinutes);
        ed.putFloat(AppSettings.KEY_VEHICLE_DISTANCE, (float) config.saveDistanceMeters);
        ed.putFloat(AppSettings.KEY_VEHICLE_SPEED, config.vehicleThreshold);
        ed.putFloat(AppSettings.KEY_AUTO_STOP_TIMEOUT, (float) config.autoStopTimeoutMinutes);
        ed.putFloat(AppSettings.KEY_ROUTE_GAP, (float) config.routeGapMeters);
        ed.putBoolean(AppSettings.KEY_WEB_SERVER_ENABLED, config.webMonitorEnabled);
        ed.putBoolean(AppSettings.KEY_VOICE_ENABLED, config.voiceFeedbackEnabled);
        ed.putBoolean(AppSettings.KEY_NOTIF_TRIP_START, config.notifyTripStart);
        ed.putBoolean(AppSettings.KEY_NOTIF_TRIP_END, config.notifyTripEnd);
        ed.putBoolean(AppSettings.KEY_NOTIF_DISTANCE_KM, config.notifyDistanceKm);
        ed.putBoolean(AppSettings.KEY_NOTIF_GEOFENCE_ENTER, config.notifyGeofenceEnter);
        ed.putBoolean(AppSettings.KEY_NOTIF_GEOFENCE_EXIT, config.notifyGeofenceExit);
        ed.putInt("transport_type", config.transportType);

        // Persist API config — survives app kill + service restart
        ed.putString("api_pingURL", config.pingURL != null ? config.pingURL : "");
        ed.putString("api_endURL", config.endURL != null ? config.endURL : "");
        ed.putString("api_userId", config.userId != null ? config.userId : "");
        ed.putString("api_vehicleId", config.vehicleId != null ? config.vehicleId : "");
        ed.putString("api_osInfo", config.osInfo != null ? config.osInfo : "");
        ed.putString("api_routeId", config.routeId != null ? config.routeId : "");
        ed.putString("api_authorizationKey", config.authorizationKey != null ? config.authorizationKey : "");
        ed.putString("api_apiAuthKey", config.apiAuthKey != null ? config.apiAuthKey : "");
        ed.putString("api_apiAuthToken", config.apiAuthToken != null ? config.apiAuthToken : "");
        ed.apply();

        GeofenceManager.setEnabled(ctx, config.geofenceEnabled);
        if (config.geofenceEnabled && hasLocationPermission(ctx)) {
            GeofenceManager.registerAll(ctx);
        }

        // API — set context for queue persistence + network monitoring
        TripTrackerAPIService.getInstance().setContext(ctx);
        TripTrackerAPIService.getInstance().configure(
                config.pingURL, config.endURL, config.userId, config.vehicleId,
                config.osInfo, config.routeId, config.authorizationKey,
                config.apiAuthKey, config.apiAuthToken);
    }

    public static boolean isInitialized() { return initialized; }

    /**
     * Restore API config from SharedPreferences.
     * Called by LocationTrackingService.onCreate when service restarts after app kill.
     */
    public static void restoreAPIConfigFromPrefs(Context ctx) {
        SharedPreferences prefs = ctx.getSharedPreferences("triptracker_settings", Context.MODE_PRIVATE);
        String pingURL = prefs.getString("api_pingURL", "");
        String endURL = prefs.getString("api_endURL", "");
        String userId = prefs.getString("api_userId", "");
        String vehicleId = prefs.getString("api_vehicleId", "");
        String osInfo = prefs.getString("api_osInfo", "");
        String routeId = prefs.getString("api_routeId", "");
        String authKey = prefs.getString("api_authorizationKey", "");
        String apiAuthKey = prefs.getString("api_apiAuthKey", "");
        String apiAuthToken = prefs.getString("api_apiAuthToken", "");

        // Use vehicleId as routeId if routeId is empty
        String effectiveRouteId = (routeId != null && !routeId.isEmpty()) ? routeId : vehicleId;

        TripTrackerAPIService.getInstance().setContext(ctx);
        TripTrackerAPIService.getInstance().configure(
                pingURL, endURL, userId, vehicleId,
                osInfo, effectiveRouteId, authKey, apiAuthKey, apiAuthToken);

        boolean enabled = TripTrackerAPIService.getInstance().isEnabled();
        Log.i(TAG, "API config restored from prefs — enabled=" + enabled
                + " ping=" + pingURL + " user=" + userId);
    }

    // ═══════════════════════════════════════════════════════════════
    // Permission
    // ═══════════════════════════════════════════════════════════════

    public static boolean hasLocationPermission(Context ctx) {
        int fine = ContextCompat.checkSelfPermission(ctx, android.Manifest.permission.ACCESS_FINE_LOCATION);
        int coarse = ContextCompat.checkSelfPermission(ctx, android.Manifest.permission.ACCESS_COARSE_LOCATION);
        return fine == PackageManager.PERMISSION_GRANTED || coarse == PackageManager.PERMISSION_GRANTED;
    }

    /**
     * Notify the service that permission has been granted.
     * Call from Activity.onRequestPermissionsResult or plugin handleOnResume.
     */
    public static void onPermissionGranted(Context context) {
        LocationTrackingService svc = LocationTrackingService.getInstance();
        if (svc != null) {
            svc.onLocationPermissionGranted();
            Log.i(TAG, "✅ Permission granted — location tracking activated");
        } else {
            // Service not running yet, start it
            startTracking(context);
        }
    }

    public static void startTracking(Context context) {
        try {
            Intent si = new Intent(context.getApplicationContext(), LocationTrackingService.class);
            context.getApplicationContext().startForegroundService(si);
        } catch (Exception e) {
            Log.e(TAG, "Start tracking failed: " + e.getMessage());
        }
    }

    public static void stopTracking(Context context) {
        try {
            Intent si = new Intent(context.getApplicationContext(), LocationTrackingService.class);
            context.getApplicationContext().stopService(si);
        } catch (Exception e) {
            Log.e(TAG, "Stop tracking failed: " + e.getMessage());
        }
    }

    // ═══════════════════════════════════════════════════════════════
    // Native pages
    // ═══════════════════════════════════════════════════════════════

    public static void openMainView(Activity a)       { a.startActivity(new Intent(a, MainActivity.class)); }
    public static void openSettings(Activity a)        { a.startActivity(new Intent(a, SettingsActivity.class)); }
    public static void openNotifications(Activity a)   { a.startActivity(new Intent(a, NotificationSettingsActivity.class)); }
    public static void openGeofence(Activity a)        { a.startActivity(new Intent(a, GeofenceSettingsActivity.class)); }
    public static void openHistory(Activity a)         { a.startActivity(new Intent(a, TripHistoryActivity.class)); }
    public static void openDailyLocations(Activity a)  { a.startActivity(new Intent(a, DailyLocationsActivity.class)); }
    public static void openMainView(Context c)      { launch(c, MainActivity.class); }
    public static void openSettings(Context c)       { launch(c, SettingsActivity.class); }
    public static void openNotifications(Context c)  { launch(c, NotificationSettingsActivity.class); }
    public static void openGeofence(Context c)       { launch(c, GeofenceSettingsActivity.class); }
    public static void openHistory(Context c)        { launch(c, TripHistoryActivity.class); }
    public static void openDailyLocations(Context c) { launch(c, DailyLocationsActivity.class); }
    private static void launch(Context c, Class<?> cls) { Intent i = new Intent(c, cls); i.addFlags(Intent.FLAG_ACTIVITY_NEW_TASK); c.startActivity(i); }

    // Data access
    public static boolean isTracking()    { LocationTrackingService s = LocationTrackingService.getInstance(); return s != null && s.isCurrentlyTracking(); }
    public static long getCurrentTripId() { LocationTrackingService s = LocationTrackingService.getInstance(); return s != null ? s.getCurrentTripId() : 0; }
    public static double getDistance()    { LocationTrackingService s = LocationTrackingService.getInstance(); return s != null ? s.getTotalDistance() : 0; }
    public static float getSpeed()        { LocationTrackingService s = LocationTrackingService.getInstance(); return s != null ? s.getEffectiveSpeed() : 0; }
    public static float getSpeedKmh()     { return getSpeed() * 3.6f; }
    public static long getDuration()      { LocationTrackingService s = LocationTrackingService.getInstance(); return s != null ? s.getCurrentTripDuration() : 0; }
    public static int getSteps()          { LocationTrackingService s = LocationTrackingService.getInstance(); return s != null ? s.getCurrentTripSteps() : 0; }
    public static android.location.Location getLastLocation() { LocationTrackingService s = LocationTrackingService.getInstance(); return s != null ? s.getLastKnownLocation() : null; }

    // Settings getters
    public static float getVehicleThreshold()   { return appContext != null ? AppSettings.getVehicleSpeed(appContext) : 6f; }
    public static boolean isVoiceEnabled()      { return appContext != null && AppSettings.isVoiceEnabled(appContext); }
    public static boolean isWebMonitorEnabled() { return appContext != null && AppSettings.isWebServerEnabled(appContext); }
    public static boolean isGeofencingEnabled() { return appContext != null && GeofenceManager.isEnabled(appContext); }

    // ── Update vehicle_id at runtime ──
    public static void updateVehicleId(String vehicleId) {
        TripTrackerAPIService.getInstance().updateVehicleId(vehicleId);
    }
}
