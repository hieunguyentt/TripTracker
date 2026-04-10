package com.carmd.triptracking.ui;

import android.Manifest;
import android.content.ComponentName;
import android.content.Context;
import android.content.Intent;
import android.content.ServiceConnection;
import android.content.pm.PackageManager;
import android.graphics.Color;
import android.location.Location;
import android.location.LocationListener;
import android.location.LocationManager;
import android.os.Build;
import android.os.Bundle;
import android.os.Handler;
import android.os.IBinder;
import android.os.Looper;
import android.util.Log;
import android.view.Menu;
import android.view.MenuItem;
import android.widget.Button;
import android.widget.TextView;
import android.widget.Toast;
import androidx.annotation.NonNull;
import androidx.appcompat.app.AppCompatActivity;
import androidx.core.app.ActivityCompat;
import androidx.core.content.ContextCompat;
import com.carmd.triptracking.R;
import com.carmd.triptracking.database.LocationDatabase;
import com.carmd.triptracking.services.LocationTrackingService;
import com.carmd.triptracking.tracking.SensorBasedLocationTracker;
import com.google.android.gms.maps.CameraUpdateFactory;
import com.google.android.gms.maps.GoogleMap;
import com.google.android.gms.maps.OnMapReadyCallback;
import com.google.android.gms.maps.SupportMapFragment;
import com.google.android.gms.maps.model.*;
import java.util.ArrayList;
import java.util.List;
import java.util.Locale;

public class MainActivity extends AppCompatActivity implements 
        OnMapReadyCallback, 
        LocationTrackingService.LocationUpdateCallback {

    private static final int PERMISSION_REQUEST_CODE = 1001;
    private static final float DEFAULT_ZOOM = 17f;

    private GoogleMap map;
    private Button btnClearRoute, btnHistory;
    private TextView tvDistance, tvSpeed, tvDuration, tvSource, tvSteps;
    private TextView tvMovementStatus, tvAcceleration, tvTripStatus;

    private LocationTrackingService trackingService;
    private boolean serviceBound = false;
    private int tripStatusTapCount = 0;
    private final Handler tripStatusTapHandler = new Handler(Looper.getMainLooper());
    private final Runnable tripStatusTapReset = () -> tripStatusTapCount = 0;

    private int titleTapCount = 0;
    private final Handler titleTapHandler = new Handler(Looper.getMainLooper());
    private final Runnable titleTapReset = () -> titleTapCount = 0;

    private final List<LatLng> routePoints = new ArrayList<>();
    private Polyline routePolyline;
    private Marker startMarker, currentMarker;

    private boolean isTracking = false;
    private long tripStartTime = 0;
    
    // UI update timer
    private final Handler uiUpdateHandler = new Handler();
    private final Runnable uiUpdateRunnable = new Runnable() {
        @Override
        public void run() {
            if (trackingService != null) {
                SensorBasedLocationTracker.TrackingStats stats = trackingService.getTrackingStats();
                if (stats != null) {
                    float gpsSpeed = trackingService.getCurrentGpsSpeed();
                    boolean isMoving = stats.isMoving() || gpsSpeed >= 0.5f;
                    updateMovementStatus(isMoving, gpsSpeed, stats.getCurrentAcceleration());

                    if (isTracking) {
                        updateSteps(stats.getStepCount());
                        long duration = (System.currentTimeMillis() - tripStartTime) / 1000;
                        updateDuration(duration);
                    }
                }

                // Update trip status indicator
                updateTripStatusUI();
            }

            uiUpdateHandler.postDelayed(this, 1000);
        }
    };

    private final ServiceConnection serviceConnection = new ServiceConnection() {
        @Override
        public void onServiceConnected(ComponentName name, IBinder service) {
            LocationTrackingService.LocalBinder binder = 
                (LocationTrackingService.LocalBinder) service;
            trackingService = binder.getService();
            trackingService.addLocationUpdateListener(MainActivity.this);
            serviceBound = true;

            uiUpdateHandler.removeCallbacks(uiUpdateRunnable);
            uiUpdateHandler.post(uiUpdateRunnable);

            restoreTrackingState();
        }

        @Override
        public void onServiceDisconnected(ComponentName name) {
            if (trackingService != null) {
                trackingService.removeLocationUpdateListener(MainActivity.this);
            }
            trackingService = null;
            serviceBound = false;
        }
    };

    @Override
    protected void onCreate(Bundle savedInstanceState) {
        setTheme(R.style.Theme_TripTracker);
        super.onCreate(savedInstanceState);
        
        if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.LOLLIPOP) {
            getWindow().setStatusBarColor(ContextCompat.getColor(this, R.color.header_blue));
            getWindow().setNavigationBarColor(android.graphics.Color.TRANSPARENT);
        }
        
        setContentView(R.layout.activity_main);
        
        if (getSupportActionBar() != null) {
            getSupportActionBar().setBackgroundDrawable(
                new android.graphics.drawable.ColorDrawable(
                    ContextCompat.getColor(this, R.color.header_blue)
                )
            );
            getSupportActionBar().setDisplayShowTitleEnabled(false);
            getSupportActionBar().setDisplayShowCustomEnabled(true);

            // Custom title with double-tap to stop trip
            TextView titleView = new TextView(this);
            titleView.setText("Trip Tracker");
            titleView.setTextColor(Color.WHITE);
            titleView.setTextSize(20);
            titleView.setTypeface(null, android.graphics.Typeface.BOLD);
            titleView.setPadding(8, 0, 0, 0);
            titleView.setOnClickListener(v -> {
                if (!serviceBound || trackingService == null) return;
                if (!trackingService.isCurrentlyTracking()) return;

                titleTapCount++;
                titleTapHandler.removeCallbacks(titleTapReset);
                titleTapHandler.postDelayed(titleTapReset, 1000); // reset after 1s

                if (titleTapCount >= 2) {
                    titleTapCount = 0;
                    titleTapHandler.removeCallbacks(titleTapReset);
                    trackingService.requestStopTrip();
                    trackingService.requestClearRoute();
                    clearRouteVisuals();
                    com.carmd.triptracking.auto.TripTrackerScreen.clearAutoRoute();
                    Toast.makeText(this, "⏹️ Trip stopped", Toast.LENGTH_SHORT).show();
                } else {
                    Toast.makeText(this, "Tap once more to stop trip",
                            Toast.LENGTH_SHORT).show();
                }
            });
            getSupportActionBar().setCustomView(titleView);
        }

        initializeViews();
        setupMapFragment();
        checkPermissions();
        startContinuousTracking();
        bindTrackingService();
    }
    
    private void startContinuousTracking() {
        Intent intent = new Intent(this, LocationTrackingService.class);
        intent.setAction(LocationTrackingService.ACTION_START_CONTINUOUS_TRACKING);
        
        if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.O) {
            startForegroundService(intent);
        } else {
            startService(intent);
        }
        
        Log.d("MainActivity", "Continuous tracking service started");
    }

    private void initializeViews() {
        btnClearRoute = findViewById(R.id.btnClearRoute);
        btnHistory = findViewById(R.id.btnHistory);
        Button btnDailyLocations = findViewById(R.id.btnDailyLocations);
        tvDistance = findViewById(R.id.tvDistance);
        tvSpeed = findViewById(R.id.tvSpeed);
        tvDuration = findViewById(R.id.tvDuration);
        tvSource = findViewById(R.id.tvSource);
        tvSteps = findViewById(R.id.tvSteps);
        tvMovementStatus = findViewById(R.id.tvMovementStatus);
        tvAcceleration = findViewById(R.id.tvAcceleration);
        tvTripStatus = findViewById(R.id.tvTripStatus);

        btnClearRoute.setOnClickListener(v -> clearRoute());
        btnHistory.setOnClickListener(v -> openHistory());
        btnDailyLocations.setOnClickListener(v -> openDailyLocations());

        // Triple-tap on trip status to force-stop trip
        tvTripStatus.setOnClickListener(v -> {
            if (!serviceBound || trackingService == null) return;
            if (!trackingService.isCurrentlyTracking()) return;

            tripStatusTapCount++;
            tripStatusTapHandler.removeCallbacks(tripStatusTapReset);
            tripStatusTapHandler.postDelayed(tripStatusTapReset, 1500); // reset after 1.5s

            if (tripStatusTapCount >= 3) {
                tripStatusTapCount = 0;
                tripStatusTapHandler.removeCallbacks(tripStatusTapReset);
                trackingService.requestStopTrip();
                trackingService.requestClearRoute();
                clearRouteVisuals();
                com.carmd.triptracking.auto.TripTrackerScreen.clearAutoRoute();
                Toast.makeText(this, "⏹️ Trip stopped manually", Toast.LENGTH_SHORT).show();
            } else {
                Toast.makeText(this, "Tap " + (3 - tripStatusTapCount) + " more to stop trip",
                        Toast.LENGTH_SHORT).show();
            }
        });
    }

    // ── Trip status UI ───────────────────────────────────────────────────

    private void updateTripStatusUI() {
        if (tvTripStatus == null || trackingService == null) return;

        if (trackingService.isCurrentlyTracking()) {
            long tripId = trackingService.getCurrentTripId();
            double dist = trackingService.getTotalDistance();
            String distStr = dist < 1000
                    ? String.format(Locale.US, "%.0f m", dist)
                    : String.format(Locale.US, "%.1f km", dist / 1000);

            long stillSince = trackingService.getStillSinceMs();
            if (stillSince > 0) {
                // Vehicle stopped — show countdown
                long stillDuration = System.currentTimeMillis() - stillSince;
                long autoStopMs = trackingService.getAutoStopMs();
                long remainMs = autoStopMs - stillDuration;
                if (remainMs < 0) remainMs = 0;
                long remainMin = (remainMs / 1000) / 60;
                long remainSec = (remainMs / 1000) % 60;
                tvTripStatus.setText(String.format(Locale.US,
                        "🔴 Trip #%d · Vehicle stopped · auto-stop in %dm %02ds",
                        tripId, remainMin, remainSec));
                tvTripStatus.setTextColor(Color.parseColor("#F44336"));
                tvTripStatus.setBackgroundColor(Color.parseColor("#FFEBEE"));
            } else {
                // Active and moving
                tvTripStatus.setText(String.format(Locale.US,
                        "🟢 Trip #%d active · %s", tripId, distStr));
                tvTripStatus.setTextColor(Color.parseColor("#4CAF50"));
                tvTripStatus.setBackgroundColor(Color.parseColor("#E8F5E9"));
            }
        } else {
            // Waiting for auto-start
            float thresholdMs = AppSettings.getVehicleSpeed(this);
            int thresholdKmh = Math.round(thresholdMs * 3.6f);
            tvTripStatus.setText(String.format(Locale.US,
                    "🟣 Waiting for vehicle speed (≥ %d km/h) to auto-start", thresholdKmh));
            tvTripStatus.setTextColor(Color.parseColor("#9C27B0"));
            tvTripStatus.setBackgroundColor(Color.parseColor("#F3E5F5"));
        }
    }

    // ── Navigation ───────────────────────────────────────────────────────

    private void openHistory() {
        Intent intent = new Intent(this, TripHistoryActivity.class);
        startActivity(intent);
    }
    
    private void openDailyLocations() {
        Intent intent = new Intent(this, DailyLocationsActivity.class);
        startActivity(intent);
    }

    private void openSettings() {
        startActivity(new Intent(this, SettingsActivity.class));
    }
    
    // ── Map ──────────────────────────────────────────────────────────────

    private void setupMapFragment() {
        SupportMapFragment mapFragment = (SupportMapFragment) getSupportFragmentManager()
                .findFragmentById(R.id.map);
        if (mapFragment != null) {
            mapFragment.getMapAsync(this);
        }
    }

    @Override
    public void onMapReady(@NonNull GoogleMap googleMap) {
        map = googleMap;
        map.getUiSettings().setZoomControlsEnabled(true);
        map.getUiSettings().setMyLocationButtonEnabled(true);
        map.getUiSettings().setCompassEnabled(true);

        if (hasLocationPermissions()) {
            try {
                map.setMyLocationEnabled(true);
                focusOnCurrentLocation();
            } catch (SecurityException e) {
                e.printStackTrace();
            }
        }
    }

    private void focusOnCurrentLocation() {
        if (!hasLocationPermissions()) return;

        try {
            LocationManager locationManager = (LocationManager) getSystemService(Context.LOCATION_SERVICE);
            Location location = locationManager.getLastKnownLocation(LocationManager.GPS_PROVIDER);
            if (location == null) {
                location = locationManager.getLastKnownLocation(LocationManager.PASSIVE_PROVIDER);
            }
            if (location == null) {
                location = getLastLocationFromDatabase();
            }

            if (location != null) {
                LatLng currentPosition = new LatLng(location.getLatitude(), location.getLongitude());
                map.animateCamera(CameraUpdateFactory.newLatLngZoom(currentPosition, DEFAULT_ZOOM));
            } else {
                requestFreshLocationForMap();
            }
        } catch (SecurityException e) {
            e.printStackTrace();
        }
    }
    
    private Location getLastLocationFromDatabase() {
        try {
            LocationDatabase database = LocationDatabase.getInstance(this);
            List<LocationDatabase.LocationPoint> recentLocations = database.getCachedLocations(1);
            
            if (!recentLocations.isEmpty()) {
                LocationDatabase.LocationPoint point = recentLocations.get(0);
                Location location = new Location("database");
                location.setLatitude(point.latitude);
                location.setLongitude(point.longitude);
                location.setTime(point.timestamp);
                
                long fiveMinutesAgo = System.currentTimeMillis() - (5 * 60 * 1000);
                if (point.timestamp > fiveMinutesAgo) {
                    return location;
                }
            }
        } catch (Exception e) {
            Log.e("MainActivity", "Error getting location from database: " + e.getMessage());
        }
        return null;
    }

    private void requestFreshLocationForMap() {
        if (!hasLocationPermissions()) return;

        try {
            LocationManager locationManager = (LocationManager) getSystemService(Context.LOCATION_SERVICE);
            locationManager.requestSingleUpdate(
                    LocationManager.GPS_PROVIDER,
                    new LocationListener() {
                        @Override
                        public void onLocationChanged(@NonNull Location location) {
                            LatLng currentPosition = new LatLng(location.getLatitude(), location.getLongitude());
                            if (map != null) {
                                map.animateCamera(CameraUpdateFactory.newLatLngZoom(currentPosition, DEFAULT_ZOOM));
                            }
                        }
                        @Override public void onStatusChanged(String provider, int status, android.os.Bundle extras) {}
                        @Override public void onProviderEnabled(@NonNull String provider) {}
                        @Override public void onProviderDisabled(@NonNull String provider) {}
                    },
                    null
            );
        } catch (SecurityException e) {
            e.printStackTrace();
        }
    }

    private void bindTrackingService() {
        Intent intent = new Intent(this, LocationTrackingService.class);
        bindService(intent, serviceConnection, Context.BIND_AUTO_CREATE);
    }

    // ── Route display ────────────────────────────────────────────────────

    private void clearRoute() {
        clearRouteVisuals();
        // Clear route on Android Auto via both paths
        com.carmd.triptracking.auto.TripTrackerScreen.clearAutoRoute();
        if (serviceBound && trackingService != null) {
            trackingService.requestClearRoute();
        }
    }

    /** Clear route display only (no trip stop). Called on auto-trip start. */
    private void clearRouteVisuals() {
        int pointCount = routePoints.size();
        
        routePoints.clear();
        if (routePolyline != null) routePolyline.remove();
        if (startMarker != null) startMarker.remove();
        if (currentMarker != null) currentMarker.remove();
        routePolyline = null;
        startMarker = null;
        currentMarker = null;
        lastRouteLocation = null;

        tvDistance.setText("0 m");
        tvSpeed.setText("0 km/h");
        tvDuration.setText("00:00");
        tvSteps.setText("Steps: 0");
        
        if (pointCount > 0) {
            Toast.makeText(this, "Route cleared (" + pointCount + " points)", 
                    Toast.LENGTH_SHORT).show();
        }
    }

    // ── Service callbacks ────────────────────────────────────────────────

    @Override
    public void onLocationUpdate(Location location,
                                 LocationTrackingService.TrackingSource source,
                                 double distance) {
        runOnUiThread(() -> {
            updateLocation(location, source);
            if (isTracking) updateDistance(distance);
        });
    }

    @Override
    public void onTrackingStateChanged(boolean tracking) {
        runOnUiThread(() -> {
            boolean wasTracking = isTracking;
            isTracking = tracking;

            if (tracking && !wasTracking) {
                // Auto-trip just started — clear old route on phone + Android Auto
                clearRouteVisuals();
                com.carmd.triptracking.auto.TripTrackerScreen.clearAutoRoute();
                if (trackingService != null) {
                    trackingService.requestClearRoute();
                    tripStartTime = trackingService.getTripStartTime();
                }
                Toast.makeText(this, "🚗 Auto-trip started", Toast.LENGTH_SHORT).show();
            } else if (!tracking && wasTracking) {
                // Auto-trip just ended — reset stats display
                tvDistance.setText("0 m");
                tvSpeed.setText("0 km/h");
                tvDuration.setText("00:00");
                tvSteps.setText("Steps: 0");
                tripStartTime = 0;

                Toast.makeText(this, "⏹️ Trip auto-stopped (still timeout)", Toast.LENGTH_SHORT).show();
                // Load the completed route from DB after a brief delay
                if (trackingService != null) {
                    loadLastCompletedTrip();
                }
            }

            updateTripStatusUI();
        });
    }

    /** Load the most recent completed trip and display it on map. */
    private void loadLastCompletedTrip() {
        new Thread(() -> {
            try {
                LocationDatabase database = LocationDatabase.getInstance(MainActivity.this);
                long lastTripId = database.getLastTripId();
                if (lastTripId != -1) {
                    List<LocationDatabase.LocationPoint> locations = database.getLocationsForTrip(lastTripId);
                    Log.d("MainActivity", "Loaded " + locations.size() + " points for trip " + lastTripId);
                    runOnUiThread(() -> displayCompletedRoute(locations));
                }
            } catch (Exception e) {
                Log.e("MainActivity", "Error loading last trip: " + e.getMessage());
            }
        }).start();
    }

    private void displayCompletedRoute(List<LocationDatabase.LocationPoint> locations) {
        if (locations == null || locations.isEmpty() || map == null) return;

        routePoints.clear();
        if (routePolyline != null) { routePolyline.remove(); routePolyline = null; }
        if (startMarker != null)   { startMarker.remove();   startMarker = null; }
        if (currentMarker != null) { currentMarker.remove(); currentMarker = null; }

        List<LatLng> routeLatLngs = new ArrayList<>();
        LocationDatabase.LocationPoint lastAdded = null;

        for (LocationDatabase.LocationPoint point : locations) {
            if (point.accuracy > MAX_ACCEPTABLE_ACCURACY_M && point.accuracy > 0) continue;
            if (lastAdded != null) {
                float[] result = new float[1];
                android.location.Location.distanceBetween(
                        lastAdded.latitude, lastAdded.longitude,
                        point.latitude, point.longitude, result);
                if (result[0] < MIN_ROUTE_DISTANCE_M) continue;
            }
            routeLatLngs.add(new LatLng(point.latitude, point.longitude));
            lastAdded = point;
        }

        if (routeLatLngs.isEmpty()) {
            for (LocationDatabase.LocationPoint point : locations) {
                routeLatLngs.add(new LatLng(point.latitude, point.longitude));
            }
        }

        if (routeLatLngs.size() < 2) {
            if (!routeLatLngs.isEmpty()) {
                startMarker = map.addMarker(new MarkerOptions()
                        .position(routeLatLngs.get(0)).title("Location")
                        .icon(BitmapDescriptorFactory.defaultMarker(BitmapDescriptorFactory.HUE_GREEN)));
                map.animateCamera(CameraUpdateFactory.newLatLngZoom(routeLatLngs.get(0), DEFAULT_ZOOM));
            }
            return;
        }

        routePolyline = map.addPolyline(new PolylineOptions()
                .addAll(routeLatLngs).color(Color.BLUE).width(10f).geodesic(true));

        startMarker = map.addMarker(new MarkerOptions()
                .position(routeLatLngs.get(0)).title("Start")
                .icon(BitmapDescriptorFactory.defaultMarker(BitmapDescriptorFactory.HUE_GREEN)));

        currentMarker = map.addMarker(new MarkerOptions()
                .position(routeLatLngs.get(routeLatLngs.size() - 1)).title("End")
                .icon(BitmapDescriptorFactory.defaultMarker(BitmapDescriptorFactory.HUE_RED)));

        LatLngBounds.Builder boundsBuilder = new LatLngBounds.Builder();
        for (LatLng point : routeLatLngs) boundsBuilder.include(point);
        map.animateCamera(CameraUpdateFactory.newLatLngBounds(boundsBuilder.build(), 120));

        Toast.makeText(this, "✅ Route: " + routeLatLngs.size() + " points", Toast.LENGTH_SHORT).show();
    }

    @Override
    public void onStatsUpdate(float speed, double distance, long duration) {
        runOnUiThread(() -> {
            if (!isTracking) return; // don't overwrite reset values after trip ends
            updateSpeed(speed);
            updateDistance(distance);
            updateDuration(duration);
            
            if (trackingService != null) {
                SensorBasedLocationTracker.TrackingStats stats = trackingService.getTrackingStats();
                if (stats != null) {
                    updateSteps(stats.getStepCount());
                }
            }
        });
    }

    // ── UI updates ───────────────────────────────────────────────────────

    private static final float MAX_ACCEPTABLE_ACCURACY_M = 50f;
    private static final float MIN_ROUTE_DISTANCE_M = 10f;
    private Location lastRouteLocation = null;

    private void updateLocation(Location location, LocationTrackingService.TrackingSource source) {
        if (map == null) return;

        LatLng latLng = new LatLng(location.getLatitude(), location.getLongitude());

        boolean isAccurateSource = (source == LocationTrackingService.TrackingSource.GPS
                || source == LocationTrackingService.TrackingSource.SENSORS);
        float accuracy = location.hasAccuracy() ? location.getAccuracy() : Float.MAX_VALUE;
        boolean isAccurateReading = accuracy <= MAX_ACCEPTABLE_ACCURACY_M;

        boolean hasMoved = true;
        if (lastRouteLocation != null) {
            float distFromLast = lastRouteLocation.distanceTo(location);
            hasMoved = distFromLast >= MIN_ROUTE_DISTANCE_M;
        }

        if (isAccurateSource && isAccurateReading && hasMoved) {
            routePoints.add(latLng);
            lastRouteLocation = new Location(location);
        }

        if (currentMarker != null) currentMarker.remove();
        currentMarker = map.addMarker(new MarkerOptions()
                .position(latLng)
                .title("Current Position")
                .icon(BitmapDescriptorFactory.defaultMarker(BitmapDescriptorFactory.HUE_BLUE)));

        tvSource.setText("Source: " + getSourceName(source));
        tvSource.setTextColor(getSourceColor(source));
    }

    private void updateDistance(double distance) {
        if (distance < 1000) {
            tvDistance.setText(String.format(Locale.US, "%.0f m", distance));
        } else {
            tvDistance.setText(String.format(Locale.US, "%.2f km", distance / 1000));
        }
    }

    private void updateSpeed(float speed) {
        float kmh = speed * 3.6f;
        tvSpeed.setText(String.format(Locale.US, "%.1f km/h", kmh));
    }

    private void updateDuration(long seconds) {
        long minutes = seconds / 60;
        long secs = seconds % 60;
        tvDuration.setText(String.format(Locale.US, "%02d:%02d", minutes, secs));
    }

    private void updateSteps(int steps) {
        tvSteps.setText(String.format(Locale.US, "Steps: %d", steps));
    }

    private void updateMovementStatus(boolean isMoving, float gpsSpeed, float acceleration) {
        if (isMoving) {
            if (gpsSpeed >= 6.0f) {
                tvMovementStatus.setText(String.format(Locale.US,
                        "🚗 Moving %.1f km/h", gpsSpeed * 3.6f));
            } else if (gpsSpeed >= 0.5f) {
                tvMovementStatus.setText(String.format(Locale.US,
                        "🚶 Walking %.1f km/h", gpsSpeed * 3.6f));
            } else {
                tvMovementStatus.setText("🚶 Moving");
            }
            tvMovementStatus.setTextColor(Color.parseColor("#4CAF50"));
        } else {
            tvMovementStatus.setText("⏸️ Standing Still");
            tvMovementStatus.setTextColor(Color.parseColor("#FF9800"));
        }
        tvAcceleration.setText(String.format(Locale.US, "Acceleration: %.2f m/s²", acceleration));
    }

    private String getSourceName(LocationTrackingService.TrackingSource source) {
        switch (source) {
            case SENSORS: return "📱 Sensors (Primary)";
            case GPS: return "🛰️ GPS (Backup)";
            default: return "Unknown";
        }
    }

    private int getSourceColor(LocationTrackingService.TrackingSource source) {
        switch (source) {
            case SENSORS: return Color.parseColor("#4CAF50");
            case GPS: return Color.parseColor("#9C27B0");
            default: return Color.BLACK;
        }
    }

    // ── Restore state ────────────────────────────────────────────────────

    private void restoreTrackingState() {
        if (trackingService == null) return;
        
        boolean serviceIsTracking = trackingService.isCurrentlyTracking();
        
        if (serviceIsTracking) {
            isTracking = true;
            tripStartTime = trackingService.getTripStartTime();
            
            long elapsed = (System.currentTimeMillis() - tripStartTime) / 1000;
            long hours = elapsed / 3600;
            long minutes = (elapsed % 3600) / 60;
            
            String elapsedStr = hours > 0 
                ? String.format(Locale.US, "%dh %dm", hours, minutes)
                : String.format(Locale.US, "%dm", minutes);
            
            Toast.makeText(this, 
                "🚗 Continuing auto-trip (" + elapsedStr + ")", 
                Toast.LENGTH_LONG).show();
        }

        updateTripStatusUI();
    }

    // ── Permissions ──────────────────────────────────────────────────────

    private boolean hasLocationPermissions() {
        boolean hasLocation = ContextCompat.checkSelfPermission(this, 
                Manifest.permission.ACCESS_FINE_LOCATION) == PackageManager.PERMISSION_GRANTED;
        
        boolean hasActivity = true;
        if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.Q) {
            hasActivity = ContextCompat.checkSelfPermission(this, 
                    Manifest.permission.ACTIVITY_RECOGNITION) == PackageManager.PERMISSION_GRANTED;
        }
        
        return hasLocation && hasActivity;
    }

    private void checkPermissions() {
        if (!hasLocationPermissions()) {
            showPermissionExplanationDialog();
        }
    }

    private void showPermissionExplanationDialog() {
        new androidx.appcompat.app.AlertDialog.Builder(this)
                .setTitle("Permissions Required")
                .setMessage("Trip Tracker needs these permissions:\n\n" +
                        "📍 Location (Allow all the time)\n" +
                        "• Track your route\n" +
                        "• Show current position\n" +
                        "• Work in background\n\n" +
                        "🚶 Physical Activity\n" +
                        "• Count steps accurately\n" +
                        "• Detect movement\n" +
                        "• Calculate distance")
                .setPositiveButton("Grant Permission", (dialog, which) -> {
                    dialog.dismiss();
                    openPermissionSettings();
                })
                .setNegativeButton("Cancel", (dialog, which) -> dialog.dismiss())
                .setCancelable(true)
                .show();
    }
    
    private void openPermissionSettings() {
        Intent intent = new Intent(android.provider.Settings.ACTION_APPLICATION_DETAILS_SETTINGS);
        intent.setData(android.net.Uri.parse("package:" + getPackageName()));
        startActivityForResult(intent, PERMISSION_REQUEST_CODE);
        
        Toast.makeText(this, 
                "📍 Enable Location (Allow all the time)\n🚶 Enable Physical Activity", 
                Toast.LENGTH_LONG).show();
    }

    @Override
    public void onRequestPermissionsResult(int requestCode, @NonNull String[] permissions, 
                                          @NonNull int[] grantResults) {
        super.onRequestPermissionsResult(requestCode, permissions, grantResults);

        if (requestCode == PERMISSION_REQUEST_CODE) {
            boolean granted = true;
            for (int result : grantResults) {
                if (result != PackageManager.PERMISSION_GRANTED) {
                    granted = false;
                    break;
                }
            }

            if (granted) {
                Toast.makeText(this, "✅ Permissions granted", Toast.LENGTH_SHORT).show();
                startContinuousTracking();
                if (map != null) {
                    try {
                        map.setMyLocationEnabled(true);
                        focusOnCurrentLocation();
                    } catch (SecurityException e) {
                        e.printStackTrace();
                    }
                }
            } else {
                Toast.makeText(this, "⚠️ Location permissions required", 
                        Toast.LENGTH_LONG).show();
            }
        }
    }
    
    @Override
    protected void onActivityResult(int requestCode, int resultCode, Intent data) {
        super.onActivityResult(requestCode, resultCode, data);
        
        if (requestCode == PERMISSION_REQUEST_CODE) {
            if (hasLocationPermissions()) {
                Toast.makeText(this, "✅ All permissions granted!", Toast.LENGTH_SHORT).show();
                if (map != null) {
                    try {
                        map.setMyLocationEnabled(true);
                        focusOnCurrentLocation();
                    } catch (SecurityException e) {
                        e.printStackTrace();
                    }
                }
            } else {
                Toast.makeText(this, "⚠️ Permissions still needed", Toast.LENGTH_LONG).show();
            }
        }
    }
    
    @Override
    public boolean onCreateOptionsMenu(android.view.Menu menu) {
        getMenuInflater().inflate(R.menu.menu_main, menu);
        return true;
    }
    
    @Override
    public boolean onOptionsItemSelected(@NonNull android.view.MenuItem item) {
        if (item.getItemId() == R.id.action_my_location) {
            focusOnCurrentLocationNow();
            return true;
        }
        if (item.getItemId() == R.id.action_settings) {
            openSettings();
            return true;
        }
        return super.onOptionsItemSelected(item);
    }
    
    private void focusOnCurrentLocationNow() {
        if (!hasLocationPermissions()) {
            Toast.makeText(this, "Location permission required", Toast.LENGTH_SHORT).show();
            return;
        }
        if (map == null) {
            Toast.makeText(this, "Map not ready", Toast.LENGTH_SHORT).show();
            return;
        }
        Toast.makeText(this, "📍 Getting current location...", Toast.LENGTH_SHORT).show();
        focusOnCurrentLocation();
        requestFreshLocationForMap();
    }

    @Override
    protected void onDestroy() {
        super.onDestroy();
        uiUpdateHandler.removeCallbacks(uiUpdateRunnable);
        
        if (serviceBound) {
            if (trackingService != null) {
                trackingService.removeLocationUpdateListener(this);
            }
            unbindService(serviceConnection);
            serviceBound = false;
        }
    }
}
