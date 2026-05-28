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
        String apiAuthTok = call.getString("apiAuthToken");
        if (apiAuthTok != null) config.apiAuthToken = apiAuthTok;

        TripTrackerSDK.initialize(getContext(), config);

        // Service always starts — bind to it
        boolean permGranted = TripTrackerSDK.hasLocationPermission(getContext());
        bindToServiceIfRunning();

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
        JSObject ret = new JSObject();
        // Try bound service first, then static instance
        android.location.Location loc = null;
        if (trackingService != null) {
            loc = trackingService.getLastKnownLocation();
        }
        if (loc == null) {
            LocationTrackingService svc = LocationTrackingService.getInstance();
            if (svc != null) loc = svc.getLastKnownLocation();
        }
        if (loc == null) {
            LocationTrackingService svc = LocationTrackingService.getInstance();
            if (svc != null) loc = svc.getCurrentLocation();
        }
        if (loc != null) {
            ret.put("latitude", loc.getLatitude());
            ret.put("longitude", loc.getLongitude());
            ret.put("speed", (double) loc.getSpeed());
            ret.put("speedKmh", (double) loc.getSpeed() * 3.6);
            ret.put("accuracy", (double) loc.getAccuracy());
            ret.put("bearing", (double) loc.getBearing());
            ret.put("altitude", loc.getAltitude());
            ret.put("timestamp", loc.getTime());
            call.resolve(ret);
        } else {
            call.reject("No location available");
        }
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
        // shareLogFiles(-1);  // -1 = all files
        // JSObject ret = new JSObject();
        // ret.put("shared", true);
        // call.resolve(ret);
        File zip = LogcatWriter.getZippedLogs(getContext());
if (zip != null) {
    // Copy to external cache (no FileProvider needed)
    File externalZip = new File(getContext().getExternalCacheDir(), zip.getName());
    try {
        java.nio.file.Files.copy(zip.toPath(), externalZip.toPath(), 
            java.nio.file.StandardCopyOption.REPLACE_EXISTING);
    } catch (Exception e) { return; }
    
    Uri uri = Uri.fromFile(externalZip);
    Intent intent = new Intent(Intent.ACTION_SEND);
    intent.setType("application/zip");
    intent.putExtra(Intent.EXTRA_STREAM, uri);
    intent.addFlags(Intent.FLAG_GRANT_READ_URI_PERMISSION);
    getActivity().startActivity(Intent.createChooser(intent, "Share Logs"));
}
    }

    @PluginMethod
    public void sendRecentLogs(PluginCall call) {
        int days = call.getInt("days", 3);
        shareLogFiles(days);
        JSObject ret = new JSObject();
        ret.put("shared", true);
        ret.put("days", days);
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

        // Collect dates to include
        java.util.Set<String> datesToInclude = new java.util.HashSet<>();
        java.text.SimpleDateFormat sdf = new java.text.SimpleDateFormat("yyyy-MM-dd", java.util.Locale.US);
        if (days >= 0) {
            int count = (days == 0) ? 1 : days;
            java.util.Calendar cal = java.util.Calendar.getInstance();
            for (int i = 0; i < count; i++) {
                datesToInclude.add(sdf.format(cal.getTime()));
                cal.add(java.util.Calendar.DAY_OF_YEAR, -1);
            }
        }

        // Get files from LogcatWriter (uses getCacheDir, prefix "triptracker_logcat_")
        File[] logFiles = com.carmd.triptracking.util.LogcatWriter.getAllLogFiles(getContext());
        if (logFiles == null || logFiles.length == 0) return;

        ArrayList<Uri> uris = new ArrayList<>();
        for (File f : logFiles) {
            if (days == -1) {
                // All files
                uris.add(getUriForFile(f));
            } else {
                // Filter by date
                for (String date : datesToInclude) {
                    if (f.getName().contains(date)) {
                        uris.add(getUriForFile(f));
                        break;
                    }
                }
            }
        }
        if (uris.isEmpty()) return;

        String subject;
        if (days == 0) {
            subject = "TripTracker Today's Log";
        } else if (days == -1) {
            subject = "TripTracker All Logs (" + logFiles.length + " files)";
        } else {
            subject = "TripTracker Logs — Last " + days + " days";
        }

        Intent shareIntent = new Intent(Intent.ACTION_SEND_MULTIPLE);
        shareIntent.setType("text/plain");
        shareIntent.putParcelableArrayListExtra(Intent.EXTRA_STREAM, uris);
        shareIntent.putExtra(Intent.EXTRA_SUBJECT, subject);
        shareIntent.addFlags(Intent.FLAG_GRANT_READ_URI_PERMISSION);
        getActivity().startActivity(Intent.createChooser(shareIntent, subject));
    }

    private Uri getUriForFile(File f) {
        return FileProvider.getUriForFile(getContext(),
                getContext().getPackageName() + ".fileprovider", f);
    }
}
