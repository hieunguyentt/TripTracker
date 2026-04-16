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

@CapacitorPlugin(name = "TripTracker")
public class TripTrackerCapPlugin extends Plugin {

    private LocationTrackingService trackingService;
    private boolean serviceBound = false;

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
        Intent intent = new Intent(getContext(), LocationTrackingService.class);
        getContext().bindService(intent, serviceConnection, Context.BIND_AUTO_CREATE);
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

        TripTrackerSDK.initialize(getContext(), config);

        JSObject ret = new JSObject();
        ret.put("initialized", true);
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
        JSObject ret = new JSObject();
        if (trackingService != null) {
            android.location.Location loc = trackingService.getLastKnownLocation();
            if (loc != null) {
                ret.put("latitude", loc.getLatitude());
                ret.put("longitude", loc.getLongitude());
                ret.put("speed", (double) loc.getSpeed());
                ret.put("speedKmh", (double) loc.getSpeed() * 3.6);
                call.resolve(ret);
                return;
            }
        }
        call.reject("No location available");
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
            default:
                call.reject("Unknown setting: " + key); return;
        }
        editor.apply();

        JSObject ret = new JSObject();
        ret.put("key", key);
        ret.put("updated", true);
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
            obj.put("radius", z.radius);
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

        GeofenceManager.GeofenceZone zone = new GeofenceManager.GeofenceZone(
                name, lat, lon,
                call.getDouble("radius", 200.0),
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
        shareLogs(false);
        JSObject ret = new JSObject();
        ret.put("shared", true);
        call.resolve(ret);
    }

    @PluginMethod
    public void sendAllLogs(PluginCall call) {
        shareLogs(true);
        JSObject ret = new JSObject();
        ret.put("shared", true);
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

    private void shareLogs(boolean allLogs) {
        if (getActivity() == null) return;
        File logDir = new File(getContext().getFilesDir(), "logs");
        if (!logDir.exists()) return;

        ArrayList<Uri> uris = new ArrayList<>();
        File[] files = logDir.listFiles();
        if (files == null) return;

        String today = new java.text.SimpleDateFormat("yyyy-MM-dd", java.util.Locale.US)
                .format(new java.util.Date());

        for (File f : files) {
            if (!f.getName().endsWith(".log")) continue;
            if (!allLogs && !f.getName().contains(today)) continue;
            uris.add(FileProvider.getUriForFile(getContext(),
                    getContext().getPackageName() + ".fileprovider", f));
        }
        if (uris.isEmpty()) return;

        Intent shareIntent = new Intent(Intent.ACTION_SEND_MULTIPLE);
        shareIntent.setType("text/plain");
        shareIntent.putParcelableArrayListExtra(Intent.EXTRA_STREAM, uris);
        shareIntent.putExtra(Intent.EXTRA_SUBJECT,
                allLogs ? "TripTracker All Logs" : "TripTracker Today's Log");
        shareIntent.addFlags(Intent.FLAG_GRANT_READ_URI_PERMISSION);
        getActivity().startActivity(Intent.createChooser(shareIntent, "Share Logs"));
    }
}
