package com.carmd.triptracking;

import android.app.Activity;
import android.content.Context;
import android.content.Intent;
import android.content.SharedPreferences;
import android.util.Log;
import com.carmd.triptracking.api.TripTrackerAPIService;
import com.carmd.triptracking.database.LocationDatabase;
import com.carmd.triptracking.geofence.GeofenceManager;
import com.carmd.triptracking.services.LocationTrackingService;
import com.carmd.triptracking.ui.*;
import com.carmd.triptracking.util.LogcatWriter;
import com.carmd.triptracking.util.VoiceFeedback;
import android.util.Log;


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
        public boolean voiceFeedbackEnabled = true;

        // Notifications
        public boolean notifyTripStart = true;
        public boolean notifyTripEnd = true;
        public boolean notifyDistanceKm = true;
        public boolean notifyGeofenceEnter = true;
        public boolean notifyGeofenceExit = true;

        // API
        public String pingURL = "";
        public String endURL = "";
        public String userId = "";
        public String vehicleId = "";
        public String osInfo = "";
        public String routeId = "";
        public String authorizationKey = "";
        public String apiAuthKey = "";

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
    }

    public static void initialize(Context context) {
        initialize(context, new Config());
    }

    public static void initialize(Context context, Config config) {
        if (initialized) { applyConfig(context, config); return; }
        appContext = context.getApplicationContext();
        applyConfig(appContext, config);
        LogcatWriter.start(appContext);
        LocationDatabase.getInstance(appContext);
        Intent si = new Intent(appContext, LocationTrackingService.class);
        appContext.startForegroundService(si);
        VoiceFeedback.getInstance(appContext);
        if (config.geofenceEnabled) GeofenceManager.registerAll(appContext);
        initialized = true;
        Log.i(TAG, "✅ TripTrackerSDK initialized — interval=" + config.saveIntervalMinutes
                + "min dist=" + config.saveDistanceMeters + "m autoStop=" + config.autoStopTimeoutMinutes + "min");
    }

    /** Call this after user grants permission to start the service manually. */
    public static void startTracking(Context context) {
        if (!hasLocationPermission(context)) {
            Log.e(TAG, "Cannot start — location permission still not granted");
            return;
        }
        try {
            Intent si = new Intent(context, LocationTrackingService.class);
            context.startForegroundService(si);
            Log.i(TAG, "✅ Tracking service started");
        } catch (SecurityException e) {
            Log.e(TAG, "Start failed: " + e.getMessage());
        }
    }

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
        ed.apply();

        GeofenceManager.setEnabled(ctx, config.geofenceEnabled);
        if (config.geofenceEnabled) GeofenceManager.registerAll(ctx);

        // API
        TripTrackerAPIService.getInstance().configure(
                config.pingURL, config.endURL, config.userId, config.vehicleId,
                config.osInfo, config.routeId, config.authorizationKey, config.apiAuthKey);
    }

    public static boolean isInitialized() { return initialized; }

    // Native pages
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
}
