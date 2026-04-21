package com.carmd.triptracking.api;

import android.content.Context;
import android.location.Location;
import android.net.ConnectivityManager;
import android.net.Network;
import android.net.NetworkCapabilities;
import android.net.NetworkRequest;
import android.os.Build;
import android.util.Log;

import org.json.JSONArray;
import org.json.JSONObject;

import java.io.*;
import java.net.HttpURLConnection;
import java.net.URL;
import java.text.SimpleDateFormat;
import java.util.*;
import java.util.concurrent.CopyOnWriteArrayList;
import java.util.concurrent.ExecutorService;
import java.util.concurrent.Executors;

public final class TripTrackerAPIService {
    private static final String TAG = "TripTrackerAPI";
    private static final int MAX_QUEUE_SIZE = 500;
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

    // ═══════════════════════════════════════════════════════════════
    // Retry Queue — persists failed requests to disk
    // ═══════════════════════════════════════════════════════════════

    private final CopyOnWriteArrayList<String> pendingQueue = new CopyOnWriteArrayList<>();
    private volatile boolean isFlushing = false;
    private Context appContext;
    private ConnectivityManager.NetworkCallback networkCallback;

    private TripTrackerAPIService() {}

    public static synchronized TripTrackerAPIService getInstance() {
        if (instance == null) instance = new TripTrackerAPIService();
        return instance;
    }

    /** Call once with app context to enable queue persistence + network monitoring */
    public void setContext(Context ctx) {
        this.appContext = ctx.getApplicationContext();
        loadPendingQueue();
        startNetworkMonitor();
    }

    // ═══════════════════════════════════════════════════════════════
    // Queue Persistence
    // ═══════════════════════════════════════════════════════════════

    private File getQueueFile() {
        if (appContext == null) return null;
        return new File(appContext.getCacheDir(), "triptracker_pending_api.json");
    }

    private void loadPendingQueue() {
        File file = getQueueFile();
        if (file == null || !file.exists()) return;
        try {
            BufferedReader reader = new BufferedReader(new FileReader(file));
            StringBuilder sb = new StringBuilder();
            String line;
            while ((line = reader.readLine()) != null) sb.append(line);
            reader.close();

            JSONArray arr = new JSONArray(sb.toString());
            pendingQueue.clear();
            for (int i = 0; i < arr.length(); i++) {
                pendingQueue.add(arr.getString(i));
            }
            Log.i(TAG, "Queue loaded: " + pendingQueue.size() + " pending requests");
        } catch (Exception e) {
            Log.e(TAG, "Load queue error: " + e.getMessage());
        }
    }

    private void savePendingQueue() {
        File file = getQueueFile();
        if (file == null) return;
        try {
            JSONArray arr = new JSONArray();
            for (String item : pendingQueue) arr.put(item);
            FileWriter writer = new FileWriter(file);
            writer.write(arr.toString());
            writer.close();
        } catch (Exception e) {
            Log.e(TAG, "Save queue error: " + e.getMessage());
        }
    }

    private void enqueue(String url, JSONObject body) {
        try {
            JSONObject item = new JSONObject();
            item.put("url", url);
            item.put("body", body.toString());
            item.put("ts", System.currentTimeMillis());
            pendingQueue.add(item.toString());

            // Trim oldest if over limit
            while (pendingQueue.size() > MAX_QUEUE_SIZE) {
                pendingQueue.remove(0);
            }
            savePendingQueue();
            Log.i(TAG, "Queued (total: " + pendingQueue.size() + ") — will retry when online");
        } catch (Exception e) {
            Log.e(TAG, "Enqueue error: " + e.getMessage());
        }
    }

    /** Flush all pending requests. Called when network becomes available. */
    public void flushQueue() {
        if (isFlushing || pendingQueue.isEmpty()) return;
        isFlushing = true;

        executor.execute(() -> {
            int sent = 0;
            Log.i(TAG, "Flushing " + pendingQueue.size() + " pending requests…");

            Iterator<String> it = pendingQueue.iterator();
            while (it.hasNext()) {
                try {
                    JSONObject item = new JSONObject(it.next());
                    String url = item.getString("url");
                    JSONObject body = new JSONObject(item.getString("body"));

                    boolean ok = post(url, body);
                    if (ok) {
                        it.remove();
                        sent++;
                    } else {
                        break;  // Still offline — stop flushing
                    }
                } catch (Exception e) {
                    it.remove();  // Corrupt entry — remove
                }
            }
            savePendingQueue();
            isFlushing = false;
            Log.i(TAG, "Flush done: " + sent + " sent, " + pendingQueue.size() + " remaining");
        });
    }

    public int getPendingCount() { return pendingQueue.size(); }

    // ═══════════════════════════════════════════════════════════════
    // Network Monitor — auto-flush when connectivity returns
    // ═══════════════════════════════════════════════════════════════

    private void startNetworkMonitor() {
        if (appContext == null) return;
        try {
            ConnectivityManager cm = (ConnectivityManager) appContext.getSystemService(Context.CONNECTIVITY_SERVICE);
            if (cm == null) return;

            networkCallback = new ConnectivityManager.NetworkCallback() {
                @Override
                public void onAvailable(Network network) {
                    if (!pendingQueue.isEmpty()) {
                        Log.i(TAG, "Network restored — flushing pending queue");
                        flushQueue();
                    }
                }
            };

            NetworkRequest request = new NetworkRequest.Builder()
                    .addCapability(NetworkCapabilities.NET_CAPABILITY_INTERNET)
                    .build();
            cm.registerNetworkCallback(request, networkCallback);
            Log.i(TAG, "Network monitor started");
        } catch (Exception e) {
            Log.e(TAG, "Network monitor error: " + e.getMessage());
        }
    }

    // ═══════════════════════════════════════════════════════════════
    // Configure
    // ═══════════════════════════════════════════════════════════════

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
        Log.i(TAG, "API configured: ping=" + this.pingURL + " user=" + this.userId);

        // Try flushing any pending requests now that config may have URLs
        if (isEnabled() && !pendingQueue.isEmpty()) {
            flushQueue();
        }
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

    // ═══════════════════════════════════════════════════════════════
    // POST /ping/v2
    // ═══════════════════════════════════════════════════════════════

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
                

                JSONArray locArr = new JSONArray();
                locArr.put(locObj);

                JSONObject body = new JSONObject();
                body.put("user_Id", userId);
                body.put("os_Info", osInfo);
                body.put("location", locArr);

                // Only include vehicle_Id during active trip and if configured
                if (includeVehicleId && !vehicleId.isEmpty()) {
                    body.put("vehicle_Id", vehicleId);
                    body.put("route_Id", routeId != null ? routeId : this.routeId);
                }

                boolean ok = post(pingURL, body);
                if (ok) {
                    Log.d(TAG, "Ping OK: " + location.getLatitude() + "," + location.getLongitude());
                    // Success — try flushing pending queue too
                    if (!pendingQueue.isEmpty()) flushQueue();
                } else {
                    Log.d(TAG, "Ping FAIL — queued for retry");
                    enqueue(pingURL, body);
                }
            } catch (Exception e) {
                Log.e(TAG, "Ping error: " + e.getMessage());
            }
        });
    }

    // ═══════════════════════════════════════════════════════════════
    // POST /end
    // ═══════════════════════════════════════════════════════════════

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
                includeVehicleId = false;

                if (ok) {
                    Log.d(TAG, "Trip-end OK");
                    if (!pendingQueue.isEmpty()) flushQueue();
                } else {
                    Log.d(TAG, "Trip-end FAIL — queued for retry");
                    enqueue(endURL, body);
                }
            } catch (Exception e) {
                Log.e(TAG, "Trip-end error: " + e.getMessage());
            }
        });
    }

    // ═══════════════════════════════════════════════════════════════
    // HTTP POST
    // ═══════════════════════════════════════════════════════════════

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
