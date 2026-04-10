package com.carmd.triptracking.ui;

import android.content.Context;
import android.content.SharedPreferences;

/**
 * Single source of truth for all user-tuneable tracking parameters.
 * Values are persisted in SharedPreferences and read by LocationTrackingService
 * at runtime so changes take effect immediately without restarting the service.
 */
public class AppSettings {

    private static final String PREFS = "triptracker_settings";

    // Keys
    public static final String KEY_VEHICLE_SPEED    = "vehicle_speed_threshold"; // m/s
    public static final String KEY_ROUTE_GAP        = "route_gap_threshold";     // metres
    public static final String KEY_STILL_INTERVAL   = "still_save_interval";     // minutes
    public static final String KEY_WALK_INTERVAL    = "walk_save_interval";      // minutes
    public static final String KEY_VEHICLE_DISTANCE = "vehicle_save_distance";   // metres
    public static final String KEY_AUTO_STOP_TIMEOUT = "auto_stop_timeout";      // minutes
    public static final String KEY_WEB_SERVER_ENABLED = "web_server_enabled";
    public static final String KEY_VOICE_ENABLED = "voice_enabled";
    public static final String KEY_NOTIF_TRIP_START    = "notif_trip_start";
    public static final String KEY_NOTIF_TRIP_END      = "notif_trip_end";
    public static final String KEY_NOTIF_DISTANCE_KM   = "notif_distance_km";
    public static final String KEY_NOTIF_GEOFENCE_ENTER = "notif_geofence_enter";
    public static final String KEY_NOTIF_GEOFENCE_EXIT  = "notif_geofence_exit";

    // Defaults
    public static final float DEF_VEHICLE_SPEED    = 6.0f;
    public static final float DEF_ROUTE_GAP        = 500f;
    public static final float DEF_STILL_INTERVAL   = 5.0f;   // 5 min
    public static final float DEF_WALK_INTERVAL    = 1.0f;   // 1 min
    public static final float DEF_VEHICLE_DISTANCE = 30f;    // 30 m
    public static final float DEF_AUTO_STOP_TIMEOUT = 2.0f;  // 2 min

    // Slider bounds
    public static final float MIN_VEHICLE_SPEED = 2f;  public static final float MAX_VEHICLE_SPEED = 20f;
    public static final float MIN_ROUTE_GAP     = 50f; public static final float MAX_ROUTE_GAP     = 5000f;
    public static final float MIN_STILL_INTERVAL   = 1.0f;  public static final float MAX_STILL_INTERVAL   = 30.0f;  // min
    public static final float MIN_WALK_INTERVAL    = 0.5f;  public static final float MAX_WALK_INTERVAL    = 10.0f;  // min
    public static final float MIN_VEHICLE_DISTANCE = 10f;   public static final float MAX_VEHICLE_DISTANCE = 200f;   // m
    public static final float MIN_AUTO_STOP_TIMEOUT = 1f;   public static final float MAX_AUTO_STOP_TIMEOUT = 10f;   // min

    private static SharedPreferences prefs(Context ctx) {
        return ctx.getSharedPreferences(PREFS, Context.MODE_PRIVATE);
    }

    public static float getVehicleSpeed(Context ctx) {
        return prefs(ctx).getFloat(KEY_VEHICLE_SPEED, DEF_VEHICLE_SPEED);
    }
    public static float getRouteGap(Context ctx) {
        return prefs(ctx).getFloat(KEY_ROUTE_GAP, DEF_ROUTE_GAP);
    }
    /** Still save interval in minutes. */
    public static float getStillInterval(Context ctx) {
        return prefs(ctx).getFloat(KEY_STILL_INTERVAL, DEF_STILL_INTERVAL);
    }
    /** Walk save interval in minutes. */
    public static float getWalkInterval(Context ctx) {
        return prefs(ctx).getFloat(KEY_WALK_INTERVAL, DEF_WALK_INTERVAL);
    }
    /** Vehicle save distance in metres. */
    public static float getVehicleDistance(Context ctx) {
        return prefs(ctx).getFloat(KEY_VEHICLE_DISTANCE, DEF_VEHICLE_DISTANCE);
    }
    /** Auto-stop timeout in minutes. */
    public static float getAutoStopTimeout(Context ctx) {
        return prefs(ctx).getFloat(KEY_AUTO_STOP_TIMEOUT, DEF_AUTO_STOP_TIMEOUT);
    }
    /** Auto-stop timeout in milliseconds (for service use). */
    public static long getAutoStopTimeoutMs(Context ctx) {
        return (long) (getAutoStopTimeout(ctx) * 60_000L);
    }
    /** Whether the web monitor server is enabled. Default true for backward compat. */
    public static boolean isWebServerEnabled(Context ctx) {
        return prefs(ctx).getBoolean(KEY_WEB_SERVER_ENABLED, true);
    }
    public static void setWebServerEnabled(Context ctx, boolean enabled) {
        prefs(ctx).edit().putBoolean(KEY_WEB_SERVER_ENABLED, enabled).apply();
    }
    /** Whether voice announcements are enabled. Default true. */
    public static boolean isVoiceEnabled(Context ctx) {
        return prefs(ctx).getBoolean(KEY_VOICE_ENABLED, true);
    }
    public static void setVoiceEnabled(Context ctx, boolean enabled) {
        prefs(ctx).edit().putBoolean(KEY_VOICE_ENABLED, enabled).apply();
    }

    // ── Notification toggles (all default true) ──────────────────────────
    public static boolean isNotifTripStart(Context ctx) { return prefs(ctx).getBoolean(KEY_NOTIF_TRIP_START, true); }
    public static void setNotifTripStart(Context ctx, boolean v) { prefs(ctx).edit().putBoolean(KEY_NOTIF_TRIP_START, v).apply(); }

    public static boolean isNotifTripEnd(Context ctx) { return prefs(ctx).getBoolean(KEY_NOTIF_TRIP_END, true); }
    public static void setNotifTripEnd(Context ctx, boolean v) { prefs(ctx).edit().putBoolean(KEY_NOTIF_TRIP_END, v).apply(); }

    public static boolean isNotifDistanceKm(Context ctx) { return prefs(ctx).getBoolean(KEY_NOTIF_DISTANCE_KM, true); }
    public static void setNotifDistanceKm(Context ctx, boolean v) { prefs(ctx).edit().putBoolean(KEY_NOTIF_DISTANCE_KM, v).apply(); }

    public static boolean isNotifGeofenceEnter(Context ctx) { return prefs(ctx).getBoolean(KEY_NOTIF_GEOFENCE_ENTER, true); }
    public static void setNotifGeofenceEnter(Context ctx, boolean v) { prefs(ctx).edit().putBoolean(KEY_NOTIF_GEOFENCE_ENTER, v).apply(); }

    public static boolean isNotifGeofenceExit(Context ctx) { return prefs(ctx).getBoolean(KEY_NOTIF_GEOFENCE_EXIT, true); }
    public static void setNotifGeofenceExit(Context ctx, boolean v) { prefs(ctx).edit().putBoolean(KEY_NOTIF_GEOFENCE_EXIT, v).apply(); }
    /** Still save interval in milliseconds (for service use). */
    public static long getStillIntervalMs(Context ctx) {
        return (long) (getStillInterval(ctx) * 60_000L);
    }
    /** Walk save interval in milliseconds (for service use). */
    public static long getWalkIntervalMs(Context ctx) {
        return (long) (getWalkInterval(ctx) * 60_000L);
    }

    public static void save(Context ctx, float vehicleSpeed, float routeGap,
                            float stillInterval, float walkInterval, float vehicleDistance,
                            float autoStopTimeout) {
        prefs(ctx).edit()
                .putFloat(KEY_VEHICLE_SPEED,    vehicleSpeed)
                .putFloat(KEY_ROUTE_GAP,        routeGap)
                .putFloat(KEY_STILL_INTERVAL,   stillInterval)
                .putFloat(KEY_WALK_INTERVAL,    walkInterval)
                .putFloat(KEY_VEHICLE_DISTANCE, vehicleDistance)
                .putFloat(KEY_AUTO_STOP_TIMEOUT, autoStopTimeout)
                .apply();
    }

    public static void reset(Context ctx) {
        save(ctx, DEF_VEHICLE_SPEED, DEF_ROUTE_GAP,
                DEF_STILL_INTERVAL, DEF_WALK_INTERVAL, DEF_VEHICLE_DISTANCE,
                DEF_AUTO_STOP_TIMEOUT);
    }
}
