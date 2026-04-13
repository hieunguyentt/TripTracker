package com.carmd.triptracking.flutter;

import android.app.Activity;
import android.content.ComponentName;
import android.content.Context;
import android.content.Intent;
import android.content.ServiceConnection;
import android.content.SharedPreferences;
import android.net.Uri;
import android.os.IBinder;

import androidx.annotation.NonNull;
import androidx.core.content.FileProvider;

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
import com.carmd.triptracking.util.LogcatWriter;
import com.carmd.triptracking.util.VoiceFeedback;

import java.io.File;
import java.util.ArrayList;
import java.util.HashMap;
import java.util.List;
import java.util.Map;

import io.flutter.embedding.engine.plugins.FlutterPlugin;
import io.flutter.embedding.engine.plugins.activity.ActivityAware;
import io.flutter.embedding.engine.plugins.activity.ActivityPluginBinding;
import io.flutter.plugin.common.MethodCall;
import io.flutter.plugin.common.MethodChannel;
import io.flutter.plugin.common.MethodChannel.MethodCallHandler;

public class TripTrackerFlutterPlugin implements FlutterPlugin, MethodCallHandler, ActivityAware {

    private MethodChannel channel;
    private Context context;
    private Activity activity;
    private LocationTrackingService trackingService;
    private boolean serviceBound = false;

    // ── FlutterPlugin ──

    @Override
    public void onAttachedToEngine(@NonNull FlutterPluginBinding binding) {
        context = binding.getApplicationContext();
        channel = new MethodChannel(binding.getBinaryMessenger(), "triptracker");
        channel.setMethodCallHandler(this);
        bindTrackingService();
    }

    @Override
    public void onDetachedFromEngine(@NonNull FlutterPluginBinding binding) {
        channel.setMethodCallHandler(null);
        unbindTrackingService();
    }

    // ── ActivityAware ──

    @Override
    public void onAttachedToActivity(@NonNull ActivityPluginBinding binding) {
        activity = binding.getActivity();
    }

    @Override
    public void onDetachedFromActivityForConfigChanges() { activity = null; }

    @Override
    public void onReattachedToActivityForConfigChanges(@NonNull ActivityPluginBinding binding) {
        activity = binding.getActivity();
    }

    @Override
    public void onDetachedFromActivity() { activity = null; }

    // ── Service Binding ──

    private final ServiceConnection serviceConnection = new ServiceConnection() {
        @Override
        public void onServiceConnected(ComponentName name, IBinder binder) {
            LocationTrackingService.LocalBinder localBinder = (LocationTrackingService.LocalBinder) binder;
            trackingService = localBinder.getService();
            serviceBound = true;
        }

        @Override
        public void onServiceDisconnected(ComponentName name) {
            trackingService = null;
            serviceBound = false;
        }
    };

    private void bindTrackingService() {
        Intent intent = new Intent(context, LocationTrackingService.class);
        context.bindService(intent, serviceConnection, Context.BIND_AUTO_CREATE);
    }

    private void unbindTrackingService() {
        if (serviceBound) {
            context.unbindService(serviceConnection);
            serviceBound = false;
        }
    }

    // ── Method Handler ──

    @Override
    public void onMethodCall(@NonNull MethodCall call, @NonNull MethodChannel.Result result) {
        switch (call.method) {

            // ── Native Pages ──

            case "openMainView":
                launchActivity(MainActivity.class);
                result.success(asMap("opened", true));
                break;

            case "openSettings":
                launchActivity(SettingsActivity.class);
                result.success(asMap("opened", true));
                break;

            case "openNotificationSettings":
                launchActivity(NotificationSettingsActivity.class);
                result.success(asMap("opened", true));
                break;

            case "openGeofenceManager":
                launchActivity(GeofenceSettingsActivity.class);
                result.success(asMap("opened", true));
                break;

            case "openHistory":
                launchActivity(TripHistoryActivity.class);
                result.success(asMap("opened", true));
                break;

            case "openDailyLocations":
                launchActivity(DailyLocationsActivity.class);
                result.success(asMap("opened", true));
                break;

            // ── Tracking Status ──

            case "getTrackingStatus":
                result.success(getTrackingStatus());
                break;

            case "getCurrentLocation":
                result.success(getCurrentLocation());
                break;

            // ── Trip History ──

            case "getTripHistory": {
                Integer limit = call.argument("limit");
                result.success(getTripHistory(limit != null ? limit : 50));
                break;
            }

            // ── Settings ──

            case "getSettings":
                result.success(getSettingsMap());
                break;

            case "updateSetting": {
                String key = call.argument("key");
                Object value = call.argument("value");
                if (key == null) {
                    result.error("MISSING_KEY", "Missing 'key'", null);
                } else {
                    updateSetting(key, value);
                    result.success(asMap("key", key, "updated", true));
                }
                break;
            }

            // ── Geofence ──

            case "getGeofenceZones":
                result.success(getGeofenceZones());
                break;

            case "addGeofenceZone": {
                String name = call.argument("name");
                Double lat = call.argument("latitude");
                Double lon = call.argument("longitude");
                if (name == null || lat == null || lon == null) {
                    result.error("MISSING_ARGS", "Missing name/latitude/longitude", null);
                } else {
                    Double radius = call.argument("radius");
                    Boolean notifyEnter = call.argument("notifyOnEnter");
                    Boolean notifyExit = call.argument("notifyOnExit");
                    Boolean autoStop = call.argument("autoStopOnEnter");

                    GeofenceManager.GeofenceZone zone = new GeofenceManager.GeofenceZone(
                            name, lat, lon,
                            radius != null ? radius : 200,
                            notifyEnter != null ? notifyEnter : true,
                            notifyExit != null ? notifyExit : true,
                            autoStop != null ? autoStop : false
                    );
                    GeofenceManager.addZone(context, zone);
                    GeofenceManager.registerAll(context);
                    result.success(asMap("id", zone.id, "added", true));
                }
                break;
            }

            case "removeGeofenceZone": {
                String id = call.argument("id");
                if (id == null) {
                    result.error("MISSING_ID", "Missing 'id'", null);
                } else {
                    GeofenceManager.removeZone(context, id);
                    result.success(asMap("id", id, "removed", true));
                }
                break;
            }

            // ── Web Monitor ──

            case "startWebMonitor":
                AppSettings.setWebServerEnabled(context, true);
                // Web server starts via service
                result.success(asMap("started", true));
                break;

            case "stopWebMonitor":
                AppSettings.setWebServerEnabled(context, false);
                result.success(asMap("stopped", true));
                break;

            // ── Logs ──

            case "sendTodayLog":
                shareLogs(false);
                result.success(asMap("shared", true));
                break;

            case "sendAllLogs":
                shareLogs(true);
                result.success(asMap("shared", true));
                break;

            default:
                result.notImplemented();
        }
    }

    // ═══════════════════════════════════════════════════════════════════════
    // Helper methods
    // ═══════════════════════════════════════════════════════════════════════

    private void launchActivity(Class<?> cls) {
        if (activity != null) {
            activity.startActivity(new Intent(activity, cls));
        } else if (context != null) {
            Intent intent = new Intent(context, cls);
            intent.addFlags(Intent.FLAG_ACTIVITY_NEW_TASK);
            context.startActivity(intent);
        }
    }

    private Map<String, Object> getTrackingStatus() {
        Map<String, Object> map = new HashMap<>();
        if (trackingService != null && serviceBound) {
            float speed = trackingService.getEffectiveSpeed();
            map.put("isTracking", trackingService.isCurrentlyTracking());
            map.put("speed", (double) speed);
            map.put("speedKmh", (double) speed * 3.6);
            map.put("distance", trackingService.getTotalDistance());
            map.put("duration", trackingService.getCurrentTripDuration());
            map.put("steps", trackingService.getCurrentTripSteps());
            map.put("tripId", trackingService.getCurrentTripId());

            android.location.Location loc = trackingService.getLastKnownLocation();
            if (loc != null) {
                map.put("latitude", loc.getLatitude());
                map.put("longitude", loc.getLongitude());
            }
        } else {
            map.put("isTracking", false);
            map.put("speed", 0.0);
            map.put("speedKmh", 0.0);
            map.put("distance", 0.0);
            map.put("duration", 0L);
            map.put("steps", 0);
            map.put("tripId", 0L);
        }
        return map;
    }

    private Map<String, Object> getCurrentLocation() {
        Map<String, Object> map = new HashMap<>();
        if (trackingService != null) {
            android.location.Location loc = trackingService.getLastKnownLocation();
            if (loc != null) {
                map.put("latitude", loc.getLatitude());
                map.put("longitude", loc.getLongitude());
                map.put("speed", (double) loc.getSpeed());
                map.put("speedKmh", (double) loc.getSpeed() * 3.6);
            }
        }
        return map;
    }

    private Map<String, Object> getTripHistory(int limit) {
        LocationDatabase db = LocationDatabase.getInstance(context);
        List<LocationDatabase.Trip> trips = db.getAllTrips();
        List<Map<String, Object>> tripList = new ArrayList<>();

        int count = Math.min(trips.size(), limit);
        for (int i = 0; i < count; i++) {
            LocationDatabase.Trip t = trips.get(i);
            Map<String, Object> tm = new HashMap<>();
            tm.put("id", t.id);
            tm.put("startTime", t.startTime);
            tm.put("endTime", t.endTime);
            tm.put("distance", t.distance);
            tm.put("duration", t.duration);
            tm.put("steps", t.steps);
            tm.put("isActive", "active".equals(t.status));
            tripList.add(tm);
        }

        Map<String, Object> result = new HashMap<>();
        result.put("trips", tripList);
        result.put("count", tripList.size());
        return result;
    }

    private Map<String, Object> getSettingsMap() {
        Map<String, Object> map = new HashMap<>();
        map.put("vehicleThreshold", (double) AppSettings.getVehicleSpeed(context));
        map.put("vehicleThresholdKmh", (double) AppSettings.getVehicleSpeed(context) * 3.6);
        map.put("saveIntervalMinutes", (double) AppSettings.getStillInterval(context));
        map.put("saveDistanceMeters", (double) AppSettings.getVehicleDistance(context));
        map.put("autoEndTimeoutMinutes", (double) AppSettings.getAutoStopTimeout(context));
        map.put("routeGapThresholdMeters", (double) AppSettings.getRouteGap(context));
        map.put("webMonitorEnabled", AppSettings.isWebServerEnabled(context));
        map.put("voiceFeedbackEnabled", AppSettings.isVoiceEnabled(context));
        map.put("geofencingEnabled", GeofenceManager.isEnabled(context));
        map.put("notifyTripStart", AppSettings.isNotifEnabled(context, AppSettings.KEY_NOTIF_TRIP_START));
        map.put("notifyTripEnd", AppSettings.isNotifEnabled(context, AppSettings.KEY_NOTIF_TRIP_END));
        map.put("notifyDistanceKm", AppSettings.isNotifEnabled(context, AppSettings.KEY_NOTIF_DISTANCE_KM));
        map.put("notifyGeofenceEnter", AppSettings.isNotifEnabled(context, AppSettings.KEY_NOTIF_GEOFENCE_ENTER));
        map.put("notifyGeofenceExit", AppSettings.isNotifEnabled(context, AppSettings.KEY_NOTIF_GEOFENCE_EXIT));
        return map;
    }

    private void updateSetting(String key, Object value) {
        SharedPreferences prefs = context.getSharedPreferences("triptracker_settings", Context.MODE_PRIVATE);
        SharedPreferences.Editor editor = prefs.edit();

        switch (key) {
            case "vehicleThreshold":
                editor.putFloat(AppSettings.KEY_VEHICLE_SPEED, ((Number) value).floatValue());
                break;
            case "saveIntervalMinutes":
                editor.putFloat(AppSettings.KEY_STILL_INTERVAL, ((Number) value).floatValue());
                break;
            case "saveDistanceMeters":
                editor.putFloat(AppSettings.KEY_VEHICLE_DISTANCE, ((Number) value).floatValue());
                break;
            case "autoEndTimeoutMinutes":
                editor.putFloat(AppSettings.KEY_AUTO_STOP_TIMEOUT, ((Number) value).floatValue());
                break;
            case "routeGapThresholdMeters":
                editor.putFloat(AppSettings.KEY_ROUTE_GAP, ((Number) value).floatValue());
                break;
            case "webMonitorEnabled":
                AppSettings.setWebServerEnabled(context, (Boolean) value);
                break;
            case "voiceFeedbackEnabled":
                AppSettings.setVoiceEnabled(context, (Boolean) value);
                break;
            case "geofencingEnabled":
                GeofenceManager.setEnabled(context, (Boolean) value);
                if ((Boolean) value) GeofenceManager.registerAll(context);
                else GeofenceManager.unregisterAll(context);
                break;
        }
        editor.apply();
    }

    private Map<String, Object> getGeofenceZones() {
        List<GeofenceManager.GeofenceZone> zones = GeofenceManager.getAll(context);
        List<Map<String, Object>> zoneList = new ArrayList<>();

        for (GeofenceManager.GeofenceZone z : zones) {
            Map<String, Object> zm = new HashMap<>();
            zm.put("id", z.id);
            zm.put("name", z.name);
            zm.put("latitude", z.latitude);
            zm.put("longitude", z.longitude);
            zm.put("radius", z.radius);
            zm.put("notifyOnEnter", z.notifyOnEnter);
            zm.put("notifyOnExit", z.notifyOnExit);
            zm.put("autoStopOnEnter", z.autoStopTrip);
            zoneList.add(zm);
        }

        Map<String, Object> result = new HashMap<>();
        result.put("zones", zoneList);
        result.put("count", zoneList.size());
        return result;
    }

    private void shareLogs(boolean allLogs) {
        if (activity == null) return;

        File logDir = new File(context.getFilesDir(), "logs");
        if (!logDir.exists()) return;

        ArrayList<Uri> uris = new ArrayList<>();
        File[] files = logDir.listFiles();
        if (files == null) return;

        if (allLogs) {
            for (File f : files) {
                if (f.getName().endsWith(".log")) {
                    uris.add(FileProvider.getUriForFile(context,
                            context.getPackageName() + ".fileprovider", f));
                }
            }
        } else {
            // Today's log
            String today = new java.text.SimpleDateFormat("yyyy-MM-dd", java.util.Locale.US)
                    .format(new java.util.Date());
            for (File f : files) {
                if (f.getName().contains(today)) {
                    uris.add(FileProvider.getUriForFile(context,
                            context.getPackageName() + ".fileprovider", f));
                }
            }
        }

        if (uris.isEmpty()) return;

        Intent shareIntent = new Intent(Intent.ACTION_SEND_MULTIPLE);
        shareIntent.setType("text/plain");
        shareIntent.putParcelableArrayListExtra(Intent.EXTRA_STREAM, uris);
        shareIntent.putExtra(Intent.EXTRA_SUBJECT, allLogs ? "TripTracker All Logs" : "TripTracker Today's Log");
        shareIntent.addFlags(Intent.FLAG_GRANT_READ_URI_PERMISSION);
        activity.startActivity(Intent.createChooser(shareIntent, "Share Logs"));
    }

    // ── Map helpers ──

    private Map<String, Object> asMap(String k1, Object v1) {
        Map<String, Object> m = new HashMap<>();
        m.put(k1, v1);
        return m;
    }

    private Map<String, Object> asMap(String k1, Object v1, String k2, Object v2) {
        Map<String, Object> m = new HashMap<>();
        m.put(k1, v1);
        m.put(k2, v2);
        return m;
    }
}
