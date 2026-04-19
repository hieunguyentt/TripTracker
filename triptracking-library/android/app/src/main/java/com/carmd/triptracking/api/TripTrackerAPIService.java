package com.carmd.triptracking.api;

import android.location.Location;
import android.os.Build;
import android.util.Log;

import org.json.JSONArray;
import org.json.JSONObject;

import java.io.OutputStream;
import java.net.HttpURLConnection;
import java.net.URL;
import java.text.SimpleDateFormat;
import java.util.Date;
import java.util.Locale;
import java.util.TimeZone;
import java.util.concurrent.ExecutorService;
import java.util.concurrent.Executors;

public final class TripTrackerAPIService {
    private static final String TAG = "TripTrackerAPI";
    private static TripTrackerAPIService instance;

    // Config
    private String pingURL = "";
    private String endURL = "";
    private String userId = "";
    private String vehicleId = "";           // Optional
    private String osInfo = "Android " + Build.VERSION.RELEASE;
    private String routeId = "";
    private String authorizationKey = "";
    private String apiAuthKey = "";          // Legacy
    private String apiAuthToken = "";        // New header: api-auth-token

    // Whether to include vehicle_id in outgoing payloads
    // True during active trip, false otherwise
    private boolean includeVehicleId = false;

    private final ExecutorService executor = Executors.newSingleThreadExecutor();

    private TripTrackerAPIService() {}

    public static synchronized TripTrackerAPIService getInstance() {
        if (instance == null) instance = new TripTrackerAPIService();
        return instance;
    }

    // ── Full config (legacy — kept for backwards compat) ──
    public void configure(String pingURL, String endURL, String userId, String vehicleId,
                          String osInfo, String routeId, String authorizationKey, String apiAuthKey) {
        configure(pingURL, endURL, userId, vehicleId, osInfo, routeId,
                authorizationKey, apiAuthKey, "");
    }

    // ── Full config with new apiAuthToken ──
    public void configure(String pingURL, String endURL, String userId, String vehicleId,
                          String osInfo, String routeId, String authorizationKey,
                          String apiAuthKey, String apiAuthToken) {
        this.pingURL = pingURL != null ? pingURL : "";
        this.endURL = endURL != null ? endURL : "";
        this.userId = userId != null ? userId : "";
        this.vehicleId = vehicleId != null ? vehicleId : "";
        if (osInfo != null && !osInfo.isEmpty()) this.osInfo = osInfo;
        this.routeId = routeId != null ? routeId : "";
        this.authorizationKey = authorizationKey != null ? authorizationKey : "";
        this.apiAuthKey = apiAuthKey != null ? apiAuthKey : "";
        this.apiAuthToken = apiAuthToken != null ? apiAuthToken : "";
        Log.i(TAG, "API configured: ping=" + this.pingURL + " end=" + this.endURL + " user=" + this.userId);
    }

    // ── Update vehicle_id at any time ──
    public void updateVehicleId(String vehicleId) {
        this.vehicleId = vehicleId != null ? vehicleId : "";
        this.routeId = vehicleId != null ? vehicleId : "";
        Log.i(TAG, "vehicle_id updated → " + this.vehicleId);
    }

    public void setRouteId(String id) { this.routeId = id != null ? id : ""; }
    public boolean isEnabled() { return !pingURL.isEmpty() && !endURL.isEmpty() && !userId.isEmpty(); }
    public boolean hasRouteId() { return routeId != null && !routeId.isEmpty(); }

    // ── Trip lifecycle — controls vehicle_id inclusion ──
    public void onTripStart() {
        includeVehicleId = true;
        Log.i(TAG, "Trip started — vehicle_id will be included in pings");
    }

    public void onTripEnd() {
        includeVehicleId = false;
        Log.i(TAG, "Trip ended — vehicle_id will NOT be included until next trip");
    }

    // ── POST /ping/v2 ──
    public void sendPing(Location location, boolean isMoving, float speed, String activityType) {
        sendPing(location, isMoving, speed, activityType, this.routeId);
    }

    public void sendPing(Location location, boolean isMoving, float speed, String activityType, String routeId) {
        if (!isEnabled()) return;
        executor.execute(() -> {
            try {
                JSONObject locObj = new JSONObject();
                locObj.put("is_Moving", isMoving);
                locObj.put("timestamp", isoNow());
                locObj.put("latitude", location.getLatitude());
                locObj.put("longitude", location.getLongitude());
                locObj.put("speed", speed);
                locObj.put("activityType", activityType);
                locObj.put("route_Id", routeId != null ? routeId : this.routeId);

                JSONArray locArr = new JSONArray();
                locArr.put(locObj);

                JSONObject body = new JSONObject();
                body.put("user_Id", userId);
                body.put("os_Info", osInfo);
                body.put("location", locArr);

                // Only include vehicle_Id during active trip and if configured
                if (includeVehicleId && !vehicleId.isEmpty()) {
                    body.put("vehicle_Id", vehicleId);
                }

                boolean ok = post(pingURL, body);
                Log.d(TAG, "Ping " + (ok ? "OK" : "FAIL") + ": " + location.getLatitude() + "," + location.getLongitude());
            } catch (Exception e) {
                Log.e(TAG, "Ping error: " + e.getMessage());
            }
        });
    }

    // ── POST /end — vehicle_id NOT included ──
    public void sendTripEnd(Location location) {
        if (!isEnabled()) return;
        if (routeId == null || routeId.isEmpty()) return;
        executor.execute(() -> {
            try {
                JSONObject body = new JSONObject();
                body.put("user_Id", userId);
                body.put("timestamp", isoNow());
                body.put("latitude", location.getLatitude());
                body.put("longitude", location.getLongitude());

                boolean ok = post(endURL, body);
                Log.d(TAG, "Trip-end " + (ok ? "OK" : "FAIL"));

                // Stop including vehicle_id after trip end
                includeVehicleId = false;

                if (!ok) {
                    Thread.sleep(5000);
                    post(endURL, body);
                }
            } catch (Exception e) {
                Log.e(TAG, "Trip-end error: " + e.getMessage());
            }
        });
    }

    // ── HTTP POST ──
    private boolean post(String urlStr, JSONObject body) {
        HttpURLConnection conn = null;
        try {
            URL url = new URL(urlStr);
            conn = (HttpURLConnection) url.openConnection();
            conn.setRequestMethod("POST");
            conn.setRequestProperty("Content-Type", "application/json");
            conn.setConnectTimeout(15000);
            conn.setReadTimeout(15000);
            conn.setDoOutput(true);

            if (!authorizationKey.isEmpty())
                conn.setRequestProperty("AuthorizationKey", authorizationKey);
            if (!apiAuthKey.isEmpty())
                conn.setRequestProperty("api-auth-key", apiAuthKey);
            if (!apiAuthToken.isEmpty())
                conn.setRequestProperty("api-auth-token", apiAuthToken);

            OutputStream os = conn.getOutputStream();
            os.write(body.toString().getBytes("UTF-8"));
            os.flush(); os.close();

            int code = conn.getResponseCode();
            return code >= 200 && code < 300;
        } catch (Exception e) {
            Log.e(TAG, "POST error: " + e.getMessage());
            return false;
        } finally {
            if (conn != null) conn.disconnect();
        }
    }

    private String isoNow() {
        SimpleDateFormat sdf = new SimpleDateFormat("yyyy-MM-dd'T'HH:mm:ss.SSS'Z'", Locale.US);
        sdf.setTimeZone(TimeZone.getTimeZone("UTC"));
        return sdf.format(new Date());
    }
}
