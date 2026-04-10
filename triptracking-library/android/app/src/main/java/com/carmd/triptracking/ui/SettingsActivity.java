package com.carmd.triptracking.ui;

import android.content.Intent;
import android.net.Uri;
import android.os.Build;
import android.os.Bundle;
import android.view.MenuItem;
import android.widget.SeekBar;
import android.widget.TextView;
import android.widget.Toast;
import androidx.annotation.NonNull;
import androidx.appcompat.app.AppCompatActivity;
import androidx.appcompat.widget.SwitchCompat;
import androidx.core.content.ContextCompat;
import androidx.core.content.FileProvider;
import com.carmd.triptracking.R;
import com.carmd.triptracking.geofence.GeofenceManager;
import com.carmd.triptracking.util.LogcatWriter;

import java.io.File;
import java.util.ArrayList;
import java.util.Locale;

public class SettingsActivity extends AppCompatActivity {

    // Save Rules sliders
    private SeekBar  sbStillInterval, sbWalkInterval, sbVehicleDistance;
    private TextView tvStillIntervalValue, tvWalkIntervalValue, tvVehicleDistanceValue;

    // Tracking sliders
    private SeekBar  sbVehicleSpeed, sbRouteGap;
    private TextView tvVehicleSpeedValue, tvRouteGapValue;

    // Auto Trip
    private SeekBar  sbAutoStopTimeout;
    private TextView tvAutoStopTimeoutValue;

    // Geofencing
    private SwitchCompat switchGeofenceEnabled;
    private TextView tvGeofenceCount;

    // Debug
    private TextView tvLogFileSize, tvLogInfo;

    // Web Monitor
    private SwitchCompat switchWebServer;

    // Current values
    private float vehicleSpeed, routeGap;
    private float stillInterval, walkInterval, vehicleDistance;
    private float autoStopTimeout;

    @Override
    protected void onCreate(Bundle savedInstanceState) {
        super.onCreate(savedInstanceState);
        setContentView(R.layout.activity_settings);

        if (getSupportActionBar() != null) {
            getSupportActionBar().setTitle("Settings");
            getSupportActionBar().setDisplayHomeAsUpEnabled(true);
            getSupportActionBar().setBackgroundDrawable(
                    new android.graphics.drawable.ColorDrawable(
                            ContextCompat.getColor(this, R.color.header_blue)));
        }

        vehicleSpeed    = AppSettings.getVehicleSpeed(this);
        routeGap        = AppSettings.getRouteGap(this);
        stillInterval   = AppSettings.getStillInterval(this);
        walkInterval    = AppSettings.getWalkInterval(this);
        vehicleDistance = AppSettings.getVehicleDistance(this);
        autoStopTimeout = AppSettings.getAutoStopTimeout(this);

        bindViews();
        populateSliders();
        bindListeners();
        updateLogFileSize();
        updateGeofenceInfo();
        updateVersionInfo();
    }

    @Override
    protected void onResume() {
        super.onResume();
        updateLogFileSize();
        updateGeofenceInfo();
    }

    // ── Auto-save: debounce slider changes by 5 seconds ───────────────
    private final android.os.Handler saveHandler = new android.os.Handler(android.os.Looper.getMainLooper());
    private final Runnable saveRunnable = () -> {
        AppSettings.save(this, vehicleSpeed, routeGap,
                stillInterval, walkInterval, vehicleDistance, autoStopTimeout);
        Toast.makeText(this, "✅ Settings saved", Toast.LENGTH_SHORT).show();
    };

    private void scheduleSave() {
        saveHandler.removeCallbacks(saveRunnable);
        saveHandler.postDelayed(saveRunnable, 5000);
    }

    @Override
    public boolean onOptionsItemSelected(@NonNull MenuItem item) {
        return super.onOptionsItemSelected(item);
    }

    // ── View binding ─────────────────────────────────────────────────────

    private void bindViews() {
        // Save Rules
        sbStillInterval      = findViewById(R.id.sbStillInterval);
        sbWalkInterval       = findViewById(R.id.sbWalkInterval);
        sbVehicleDistance     = findViewById(R.id.sbVehicleDistance);
        tvStillIntervalValue = findViewById(R.id.tvStillIntervalValue);
        tvWalkIntervalValue  = findViewById(R.id.tvWalkIntervalValue);
        tvVehicleDistanceValue = findViewById(R.id.tvVehicleDistanceValue);

        // Tracking
        sbVehicleSpeed      = findViewById(R.id.sbVehicleSpeed);
        sbRouteGap          = findViewById(R.id.sbRouteGap);
        tvVehicleSpeedValue = findViewById(R.id.tvVehicleSpeedValue);
        tvRouteGapValue     = findViewById(R.id.tvRouteGapValue);

        // Auto Trip
        sbAutoStopTimeout      = findViewById(R.id.sbAutoStopTimeout);
        tvAutoStopTimeoutValue = findViewById(R.id.tvAutoStopTimeoutValue);

        // Debug
        tvLogFileSize = findViewById(R.id.tvLogFileSize);
        tvLogInfo     = findViewById(R.id.tvLogInfo);

        // Geofencing
        switchGeofenceEnabled = findViewById(R.id.switchGeofenceEnabled);
        tvGeofenceCount       = findViewById(R.id.tvGeofenceCount);

        // Web Monitor
        switchWebServer = findViewById(R.id.switchWebServer);
        switchWebServer.setChecked(AppSettings.isWebServerEnabled(this));
        switchWebServer.setOnCheckedChangeListener((btn, checked) -> {
            AppSettings.setWebServerEnabled(this, checked);
            Toast.makeText(this, checked ? "Web server enabled" : "Web server disabled",
                    Toast.LENGTH_SHORT).show();
        });
        findViewById(R.id.btnOpenBrowser).setOnClickListener(v -> openWebMonitor());
        findViewById(R.id.btnCopyUrl).setOnClickListener(v -> copyWebMonitorUrl());

        // Notifications
        findViewById(R.id.btnManageNotifications).setOnClickListener(v ->
                startActivity(new Intent(this, NotificationSettingsActivity.class)));

        // Buttons
        findViewById(R.id.tvReset).setOnClickListener(v -> resetToDefaults());
        findViewById(R.id.btnSendLogs).setOnClickListener(v -> sendTodayLogViaEmail());
        findViewById(R.id.btnSendAllLogs).setOnClickListener(v -> sendAllLogsViaEmail());
        findViewById(R.id.btnManageGeofences).setOnClickListener(v ->
                startActivity(new Intent(this, GeofenceSettingsActivity.class)));

        switchGeofenceEnabled.setOnCheckedChangeListener((btn, checked) -> {
            GeofenceManager.setEnabled(this, checked);
            Toast.makeText(this, checked ? "Geofencing enabled" : "Geofencing disabled",
                    Toast.LENGTH_SHORT).show();
        });
    }

    private void populateSliders() {
        // Save Rules: Still interval 1.0 – 30.0 min, step 0.5
        sbStillInterval.setMax(scaleMax(AppSettings.MIN_STILL_INTERVAL, AppSettings.MAX_STILL_INTERVAL, 0.5f));
        sbStillInterval.setProgress(toProgress(stillInterval, AppSettings.MIN_STILL_INTERVAL, 0.5f));
        tvStillIntervalValue.setText(fmt1f(stillInterval) + " min");

        // Save Rules: Walk interval 0.5 – 10.0 min, step 0.5
        sbWalkInterval.setMax(scaleMax(AppSettings.MIN_WALK_INTERVAL, AppSettings.MAX_WALK_INTERVAL, 0.5f));
        sbWalkInterval.setProgress(toProgress(walkInterval, AppSettings.MIN_WALK_INTERVAL, 0.5f));
        tvWalkIntervalValue.setText(fmt1f(walkInterval) + " min");

        // Save Rules: Vehicle distance 10 – 200 m, step 10
        sbVehicleDistance.setMax(scaleMax(AppSettings.MIN_VEHICLE_DISTANCE, AppSettings.MAX_VEHICLE_DISTANCE, 10f));
        sbVehicleDistance.setProgress(toProgress(vehicleDistance, AppSettings.MIN_VEHICLE_DISTANCE, 10f));
        tvVehicleDistanceValue.setText(fmtInt(vehicleDistance) + " m");

        // Tracking: Vehicle speed 2.0 – 20.0 m/s, step 0.5
        sbVehicleSpeed.setMax(scaleMax(AppSettings.MIN_VEHICLE_SPEED, AppSettings.MAX_VEHICLE_SPEED, 0.5f));
        sbVehicleSpeed.setProgress(toProgress(vehicleSpeed, AppSettings.MIN_VEHICLE_SPEED, 0.5f));
        tvVehicleSpeedValue.setText(fmt1f(vehicleSpeed) + " m/s");

        // Tracking: Route gap 50 – 5000 m, step 50
        sbRouteGap.setMax(scaleMax(AppSettings.MIN_ROUTE_GAP, AppSettings.MAX_ROUTE_GAP, 50f));
        sbRouteGap.setProgress(toProgress(routeGap, AppSettings.MIN_ROUTE_GAP, 50f));
        tvRouteGapValue.setText(fmtInt(routeGap) + " m");

        // Auto Trip: Auto-stop timeout 1 – 10 min, step 1
        sbAutoStopTimeout.setMax(scaleMax(AppSettings.MIN_AUTO_STOP_TIMEOUT, AppSettings.MAX_AUTO_STOP_TIMEOUT, 1f));
        sbAutoStopTimeout.setProgress(toProgress(autoStopTimeout, AppSettings.MIN_AUTO_STOP_TIMEOUT, 1f));
        tvAutoStopTimeoutValue.setText(fmtInt(autoStopTimeout) + " min");
    }

    private void bindListeners() {
        sbStillInterval.setOnSeekBarChangeListener(new Sl() {
            @Override public void onProgressChanged(SeekBar sb, int p, boolean u) {
                stillInterval = fromProgress(p, AppSettings.MIN_STILL_INTERVAL, 0.5f);
                tvStillIntervalValue.setText(fmt1f(stillInterval) + " min");
                if (u) scheduleSave();
            }
        });
        sbWalkInterval.setOnSeekBarChangeListener(new Sl() {
            @Override public void onProgressChanged(SeekBar sb, int p, boolean u) {
                walkInterval = fromProgress(p, AppSettings.MIN_WALK_INTERVAL, 0.5f);
                tvWalkIntervalValue.setText(fmt1f(walkInterval) + " min");
                if (u) scheduleSave();
            }
        });
        sbVehicleDistance.setOnSeekBarChangeListener(new Sl() {
            @Override public void onProgressChanged(SeekBar sb, int p, boolean u) {
                vehicleDistance = fromProgress(p, AppSettings.MIN_VEHICLE_DISTANCE, 10f);
                tvVehicleDistanceValue.setText(fmtInt(vehicleDistance) + " m");
                if (u) scheduleSave();
            }
        });
        sbVehicleSpeed.setOnSeekBarChangeListener(new Sl() {
            @Override public void onProgressChanged(SeekBar sb, int p, boolean u) {
                vehicleSpeed = fromProgress(p, AppSettings.MIN_VEHICLE_SPEED, 0.5f);
                tvVehicleSpeedValue.setText(fmt1f(vehicleSpeed) + " m/s");
                if (u) scheduleSave();
            }
        });
        sbRouteGap.setOnSeekBarChangeListener(new Sl() {
            @Override public void onProgressChanged(SeekBar sb, int p, boolean u) {
                routeGap = fromProgress(p, AppSettings.MIN_ROUTE_GAP, 50f);
                tvRouteGapValue.setText(fmtInt(routeGap) + " m");
                if (u) scheduleSave();
            }
        });
        sbAutoStopTimeout.setOnSeekBarChangeListener(new Sl() {
            @Override public void onProgressChanged(SeekBar sb, int p, boolean u) {
                autoStopTimeout = fromProgress(p, AppSettings.MIN_AUTO_STOP_TIMEOUT, 1f);
                tvAutoStopTimeoutValue.setText(fmtInt(autoStopTimeout) + " min");
                if (u) scheduleSave();
            }
        });
    }

    // ── Save / Reset ─────────────────────────────────────────────────────

    private void applySettings() {
        AppSettings.save(this, vehicleSpeed, routeGap,
                stillInterval, walkInterval, vehicleDistance, autoStopTimeout);
    }

    private void resetToDefaults() {
        vehicleSpeed    = AppSettings.DEF_VEHICLE_SPEED;
        routeGap        = AppSettings.DEF_ROUTE_GAP;
        stillInterval   = AppSettings.DEF_STILL_INTERVAL;
        walkInterval    = AppSettings.DEF_WALK_INTERVAL;
        vehicleDistance = AppSettings.DEF_VEHICLE_DISTANCE;
        autoStopTimeout = AppSettings.DEF_AUTO_STOP_TIMEOUT;
        populateSliders();
        applySettings();
        Toast.makeText(this, "Reset to defaults", Toast.LENGTH_SHORT).show();
    }

    @Override
    protected void onDestroy() {
        // Flush any pending auto-save immediately
        saveHandler.removeCallbacks(saveRunnable);
        applySettings();
        super.onDestroy();
    }

    // ── Geofence helpers ────────────────────────────────────────────────

    private void updateGeofenceInfo() {
        if (switchGeofenceEnabled != null) {
            switchGeofenceEnabled.setChecked(GeofenceManager.isEnabled(this));
        }
        if (tvGeofenceCount != null) {
            int count = GeofenceManager.getAll(this).size();
            tvGeofenceCount.setText(count + " zone(s) configured");
        }
    }

    // ── Log file helpers ─────────────────────────────────────────────────

    private void updateLogFileSize() {
        if (tvLogFileSize != null) {
            tvLogFileSize.setText(LogcatWriter.getTotalLogSize(this));
        }
        if (tvLogInfo != null) {
            int count = LogcatWriter.getLogFileCount(this);
            String today = LogcatWriter.getLogFileSize(this);
            tvLogInfo.setText(count + " file(s) • Today: " + today
                    + " • Auto-sent at 12 PM • Deleted after 7 days");
        }
    }

    /** Send today's log file via email. */
    private void sendTodayLogViaEmail() {
        File logFile = LogcatWriter.getTodayLogFile(this);
        if (!logFile.exists() || logFile.length() == 0) {
            Toast.makeText(this, "No log file for today", Toast.LENGTH_SHORT).show();
            return;
        }

        Uri fileUri = FileProvider.getUriForFile(this,
                getPackageName() + ".fileprovider", logFile);

        String subject = "TripTracker Log — " + Build.MODEL
                + " (SDK " + Build.VERSION.SDK_INT + ") — Today";

        String body = "Device: " + Build.MANUFACTURER + " " + Build.MODEL
                + "\nAndroid: " + Build.VERSION.RELEASE + " (SDK " + Build.VERSION.SDK_INT + ")"
                + "\nApp: " + getPackageName()
                + "\nLog size: " + LogcatWriter.getLogFileSize(this)
                + "\n\n(Today's log file attached)";

        Intent intent = new Intent(Intent.ACTION_SEND);
        intent.setType("message/rfc822");
        intent.putExtra(Intent.EXTRA_EMAIL, new String[]{"hieu.nguyen@sw.innova.com"});
        intent.putExtra(Intent.EXTRA_SUBJECT, subject);
        intent.putExtra(Intent.EXTRA_TEXT, body);
        intent.putExtra(Intent.EXTRA_STREAM, fileUri);
        intent.addFlags(Intent.FLAG_GRANT_READ_URI_PERMISSION);

        startActivity(Intent.createChooser(intent, "Send today's log…"));
    }

    /** Send ALL log files via email as multiple attachments. */
    private void sendAllLogsViaEmail() {
        File[] logFiles = LogcatWriter.getAllLogFiles(this);
        if (logFiles.length == 0) {
            Toast.makeText(this, "No log files to send", Toast.LENGTH_SHORT).show();
            return;
        }

        ArrayList<Uri> uris = new ArrayList<>();
        for (File f : logFiles) {
            if (f.exists() && f.length() > 0) {
                uris.add(FileProvider.getUriForFile(this,
                        getPackageName() + ".fileprovider", f));
            }
        }

        if (uris.isEmpty()) {
            Toast.makeText(this, "No log files to send", Toast.LENGTH_SHORT).show();
            return;
        }

        String subject = "TripTracker All Logs — " + Build.MODEL
                + " (SDK " + Build.VERSION.SDK_INT + ") — "
                + logFiles.length + " files";

        String body = "Device: " + Build.MANUFACTURER + " " + Build.MODEL
                + "\nAndroid: " + Build.VERSION.RELEASE + " (SDK " + Build.VERSION.SDK_INT + ")"
                + "\nApp: " + getPackageName()
                + "\nFiles: " + logFiles.length
                + "\nTotal size: " + LogcatWriter.getTotalLogSize(this)
                + "\n\n(" + logFiles.length + " log file(s) attached)";

        Intent intent = new Intent(Intent.ACTION_SEND_MULTIPLE);
        intent.setType("message/rfc822");
        intent.putExtra(Intent.EXTRA_EMAIL, new String[]{"hieu.nguyen@sw.innova.com"});
        intent.putExtra(Intent.EXTRA_SUBJECT, subject);
        intent.putExtra(Intent.EXTRA_TEXT, body);
        intent.putParcelableArrayListExtra(Intent.EXTRA_STREAM, uris);
        intent.addFlags(Intent.FLAG_GRANT_READ_URI_PERMISSION);

        startActivity(Intent.createChooser(intent, "Send all logs…"));
    }

    // ── Math / formatting helpers ────────────────────────────────────────

    private static int   scaleMax(float min, float max, float step) { return Math.round((max - min) / step); }
    private static int   toProgress(float val, float min, float step) { return Math.round((val - min) / step); }
    private static float fromProgress(int p, float min, float step)   { return min + p * step; }
    private static String fmt1f(float v)  { return String.format(Locale.US, "%.1f", v); }
    private static String fmtInt(float v) { return String.valueOf((int) v); }

    private abstract static class Sl implements SeekBar.OnSeekBarChangeListener {
        @Override public void onStartTrackingTouch(SeekBar sb) {}
        @Override public void onStopTrackingTouch(SeekBar sb)  {}
    }

    // ── Web Monitor helpers ─────────────────────────────────────────────

    private void openWebMonitor() {
        String url = "http://" + getWifiIpAddress() + ":8080";
        try {
            startActivity(new Intent(Intent.ACTION_VIEW, android.net.Uri.parse(url)));
        } catch (Exception e) {
            Toast.makeText(this, "Unable to open browser", Toast.LENGTH_SHORT).show();
        }
    }

    private void copyWebMonitorUrl() {
        String url = "http://" + getWifiIpAddress() + ":8080";
        android.content.ClipboardManager clipboard =
                (android.content.ClipboardManager) getSystemService(CLIPBOARD_SERVICE);
        clipboard.setPrimaryClip(android.content.ClipData.newPlainText("Web Monitor URL", url));
        Toast.makeText(this, "URL copied!", Toast.LENGTH_SHORT).show();
    }

    private String getWifiIpAddress() {
        try {
            java.util.Enumeration<java.net.NetworkInterface> interfaces =
                    java.net.NetworkInterface.getNetworkInterfaces();
            if (interfaces != null) {
                while (interfaces.hasMoreElements()) {
                    java.net.NetworkInterface ni = interfaces.nextElement();
                    String name = ni.getName().toLowerCase(Locale.US);
                    if (ni.isLoopback() || !ni.isUp()) continue;
                    java.util.Enumeration<java.net.InetAddress> addrs = ni.getInetAddresses();
                    while (addrs.hasMoreElements()) {
                        java.net.InetAddress addr = addrs.nextElement();
                        if (!addr.isLoopbackAddress() && addr instanceof java.net.Inet4Address) {
                            if (name.startsWith("wlan") || name.startsWith("eth"))
                                return addr.getHostAddress();
                        }
                    }
                }
            }
        } catch (Exception ignored) {}
        try {
            android.net.wifi.WifiManager wm =
                    (android.net.wifi.WifiManager) getApplicationContext().getSystemService(WIFI_SERVICE);
            int ip = wm.getConnectionInfo().getIpAddress();
            if (ip != 0) return String.format(Locale.US, "%d.%d.%d.%d",
                    ip & 0xff, (ip >> 8) & 0xff, (ip >> 16) & 0xff, (ip >> 24) & 0xff);
        } catch (Exception ignored) {}
        return "localhost";
    }

    // ── Version info ──────────────────────────────────────────────────────

    private void updateVersionInfo() {
        TextView tvVersion = findViewById(R.id.tvVersionInfo);
        if (tvVersion != null) {
            try {
                android.content.pm.PackageInfo pi = getPackageManager()
                        .getPackageInfo(getPackageName(), 0);
                tvVersion.setText("TripTracker v" + pi.versionName
                        + " (build " + pi.versionCode + ")");
            } catch (Exception ignored) {}
        }
    }

    @Override public boolean onSupportNavigateUp() { finish(); return true; }
}
