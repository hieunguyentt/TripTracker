package com.carmd.triptracking.geofence;

import android.Manifest;
import android.app.PendingIntent;
import android.content.Context;
import android.content.Intent;
import android.content.SharedPreferences;
import android.content.pm.PackageManager;
import android.util.Log;
import androidx.core.app.ActivityCompat;
import com.google.android.gms.location.Geofence;
import com.google.android.gms.location.GeofencingClient;
import com.google.android.gms.location.GeofencingRequest;
import com.google.android.gms.location.LocationServices;
import com.google.gson.Gson;
import com.google.gson.reflect.TypeToken;

import java.lang.reflect.Type;
import java.util.ArrayList;
import java.util.List;
import java.util.UUID;

/**
 * Manages geofence zones: storage (SharedPreferences + JSON), registration
 * with Google Play Services Geofencing API, and CRUD operations.
 *
 * Each geofence has:
 *   - id: unique string
 *   - name: user-visible label (e.g. "Home", "Office")
 *   - latitude, longitude, radiusMeters
 *   - notifyOnEnter, notifyOnExit: booleans
 *   - autoStopTrip: if true, auto-stop trip when entering this zone
 */
public class GeofenceManager {

    private static final String TAG   = "GeofenceManager";
    private static final String PREFS = "geofence_storage";
    private static final String KEY_ZONES = "geofence_zones";
    private static final String KEY_ENABLED = "geofencing_enabled";

    private static final int GEOFENCE_PI_REQUEST = 7001;

    // ── Data model ───────────────────────────────────────────────────────

    public static class GeofenceZone {
        public String  id;
        public String  name;
        public double  latitude;
        public double  longitude;
        public float   radiusMeters;
        public boolean notifyOnEnter;
        public boolean notifyOnExit;
        public boolean autoStopTrip;

        public GeofenceZone() {}

        public GeofenceZone(String name, double latitude, double longitude,
                            float radiusMeters, boolean notifyOnEnter,
                            boolean notifyOnExit, boolean autoStopTrip) {
            this.id            = UUID.randomUUID().toString().substring(0, 8);
            this.name          = name;
            this.latitude      = latitude;
            this.longitude     = longitude;
            this.radiusMeters  = radiusMeters;
            this.notifyOnEnter = notifyOnEnter;
            this.notifyOnExit  = notifyOnExit;
            this.autoStopTrip  = autoStopTrip;
        }
    }

    // ── Storage ──────────────────────────────────────────────────────────

    private static SharedPreferences prefs(Context ctx) {
        return ctx.getSharedPreferences(PREFS, Context.MODE_PRIVATE);
    }

    public static boolean isEnabled(Context ctx) {
        return prefs(ctx).getBoolean(KEY_ENABLED, false);
    }

    public static void setEnabled(Context ctx, boolean enabled) {
        prefs(ctx).edit().putBoolean(KEY_ENABLED, enabled).apply();
        if (enabled) {
            registerAll(ctx);
        } else {
            unregisterAll(ctx);
        }
    }

    public static List<GeofenceZone> getAll(Context ctx) {
        String json = prefs(ctx).getString(KEY_ZONES, "[]");
        Type type = new TypeToken<ArrayList<GeofenceZone>>(){}.getType();
        List<GeofenceZone> list = new Gson().fromJson(json, type);
        return list != null ? list : new ArrayList<>();
    }

    public static void saveAll(Context ctx, List<GeofenceZone> zones) {
        String json = new Gson().toJson(zones);
        prefs(ctx).edit().putString(KEY_ZONES, json).apply();
    }

    public static void addZone(Context ctx, GeofenceZone zone) {
        List<GeofenceZone> zones = getAll(ctx);
        zones.add(zone);
        saveAll(ctx, zones);
        if (isEnabled(ctx)) registerAll(ctx);
        Log.d(TAG, "Added geofence: " + zone.name + " (" + zone.id + ")");
    }

    public static void removeZone(Context ctx, String zoneId) {
        List<GeofenceZone> zones = getAll(ctx);
        zones.removeIf(z -> z.id.equals(zoneId));
        saveAll(ctx, zones);
        if (isEnabled(ctx)) registerAll(ctx);
        Log.d(TAG, "Removed geofence: " + zoneId);
    }

    public static void updateZone(Context ctx, GeofenceZone updated) {
        List<GeofenceZone> zones = getAll(ctx);
        for (int i = 0; i < zones.size(); i++) {
            if (zones.get(i).id.equals(updated.id)) {
                zones.set(i, updated);
                break;
            }
        }
        saveAll(ctx, zones);
        if (isEnabled(ctx)) registerAll(ctx);
    }

    public static GeofenceZone getById(Context ctx, String zoneId) {
        for (GeofenceZone z : getAll(ctx)) {
            if (z.id.equals(zoneId)) return z;
        }
        return null;
    }

    // ── Google Play Services registration ────────────────────────────────

    public static void registerAll(Context ctx) {
        if (ActivityCompat.checkSelfPermission(ctx, Manifest.permission.ACCESS_FINE_LOCATION)
                != PackageManager.PERMISSION_GRANTED) {
            Log.w(TAG, "No location permission — cannot register geofences");
            return;
        }

        List<GeofenceZone> zones = getAll(ctx);
        if (zones.isEmpty()) {
            Log.d(TAG, "No geofences to register");
            return;
        }

        GeofencingClient client = LocationServices.getGeofencingClient(ctx);

        // Remove all first, then re-add
        PendingIntent pi = getGeofencePendingIntent(ctx);
        client.removeGeofences(pi).addOnCompleteListener(task -> {
            List<Geofence> geofences = new ArrayList<>();
            for (GeofenceZone zone : zones) {
                int transitionTypes = 0;
                if (zone.notifyOnEnter) transitionTypes |= Geofence.GEOFENCE_TRANSITION_ENTER;
                if (zone.notifyOnExit)  transitionTypes |= Geofence.GEOFENCE_TRANSITION_EXIT;
                if (transitionTypes == 0) transitionTypes = Geofence.GEOFENCE_TRANSITION_ENTER | Geofence.GEOFENCE_TRANSITION_EXIT;

                geofences.add(new Geofence.Builder()
                        .setRequestId(zone.id)
                        .setCircularRegion(zone.latitude, zone.longitude, zone.radiusMeters)
                        .setExpirationDuration(Geofence.NEVER_EXPIRE)
                        .setTransitionTypes(transitionTypes)
                        .setLoiteringDelay(30000) // 30s dwell time
                        .build());
            }

            GeofencingRequest request = new GeofencingRequest.Builder()
                    .setInitialTrigger(0)  // don't trigger if already inside zone
                    .addGeofences(geofences)
                    .build();

            try {
                client.addGeofences(request, pi)
                        .addOnSuccessListener(aVoid ->
                                Log.d(TAG, "✅ Registered " + geofences.size() + " geofences"))
                        .addOnFailureListener(e ->
                                Log.e(TAG, "❌ Failed to register geofences: " + e.getMessage()));
            } catch (SecurityException e) {
                Log.e(TAG, "Permission error registering geofences", e);
            }
        });
    }

    public static void unregisterAll(Context ctx) {
        GeofencingClient client = LocationServices.getGeofencingClient(ctx);
        PendingIntent pi = getGeofencePendingIntent(ctx);
        client.removeGeofences(pi)
                .addOnSuccessListener(aVoid -> Log.d(TAG, "All geofences removed"))
                .addOnFailureListener(e -> Log.w(TAG, "Failed to remove geofences: " + e.getMessage()));
    }

    private static PendingIntent getGeofencePendingIntent(Context ctx) {
        Intent intent = new Intent(ctx, GeofenceBroadcastReceiver.class);
        return PendingIntent.getBroadcast(ctx, GEOFENCE_PI_REQUEST, intent,
                PendingIntent.FLAG_UPDATE_CURRENT | PendingIntent.FLAG_MUTABLE);
    }
}
