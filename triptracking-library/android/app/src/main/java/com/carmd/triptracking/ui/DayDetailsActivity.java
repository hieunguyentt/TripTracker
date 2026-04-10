package com.carmd.triptracking.ui;

import android.graphics.Bitmap;
import android.graphics.Canvas;
import android.graphics.Color;
import android.graphics.drawable.Drawable;
import android.os.Bundle;
import android.view.MenuItem;
import android.widget.TextView;
import android.widget.Toast;

import androidx.annotation.DrawableRes;
import androidx.annotation.NonNull;
import androidx.appcompat.app.AppCompatActivity;
import androidx.core.content.ContextCompat;
import com.carmd.triptracking.R;
import com.carmd.triptracking.database.LocationDatabase;
import com.google.android.gms.maps.CameraUpdateFactory;
import com.google.android.gms.maps.GoogleMap;
import com.google.android.gms.maps.OnMapReadyCallback;
import com.google.android.gms.maps.SupportMapFragment;
import com.google.android.gms.maps.model.*;
import java.util.ArrayList;
import java.util.Collections;
import java.util.List;

public class DayDetailsActivity extends AppCompatActivity implements OnMapReadyCallback {

    private GoogleMap map;
    private LocationDatabase database;
    private String date;

    private TextView tvDayTitle, tvTimeRange, tvDistance, tvLocationCount, tvDuration;

    @Override
    protected void onCreate(Bundle savedInstanceState) {
        super.onCreate(savedInstanceState);
        setContentView(R.layout.activity_day_details);

        if (getSupportActionBar() != null) {
            getSupportActionBar().setDisplayHomeAsUpEnabled(true);
            getSupportActionBar().setTitle("Day Details");
            // Set action bar color
            getSupportActionBar().setBackgroundDrawable(
                    new android.graphics.drawable.ColorDrawable(
                            ContextCompat.getColor(this, R.color.header_blue)
                    )
            );
        }

        database = LocationDatabase.getInstance(this);

        // Get date from intent
        date = getIntent().getStringExtra("date");

        // Initialize views
        tvDayTitle = findViewById(R.id.tvDayTitle);
        tvTimeRange = findViewById(R.id.tvTimeRange);
        tvDistance = findViewById(R.id.tvDistance);
        tvLocationCount = findViewById(R.id.tvLocationCount);
        tvDuration = findViewById(R.id.tvDuration);

        // Setup map
        SupportMapFragment mapFragment = (SupportMapFragment) getSupportFragmentManager()
                .findFragmentById(R.id.map);
        if (mapFragment != null) {
            mapFragment.getMapAsync(this);
        }

        // Load and display data
        loadDayData();
    }

    private void loadDayData() {
        LocationDatabase.DailySummary summary = database.getDailySummary(date);

        tvDayTitle.setText(summary.getFormattedDate());
        tvTimeRange.setText(summary.getFormattedTimeRange());
        tvDistance.setText(summary.getFormattedDistance());
        tvLocationCount.setText(String.valueOf(summary.locationCount));
        tvDuration.setText(summary.getFormattedDuration());
    }

    @Override
    public void onMapReady(@NonNull GoogleMap googleMap) {
        map = googleMap;
        map.getUiSettings().setZoomControlsEnabled(true);

        // Load locations and draw route
        drawDailyRoute();
    }

    private void drawDailyHistory() {
        // Load locations for this day (cache + trips)
        List<LocationDatabase.LocationPoint> allLocations = database.getAllLocationsByDay(date);

        if (allLocations.isEmpty()) {
            Toast.makeText(this, "No location data for this trip", Toast.LENGTH_SHORT).show();
            return;
        }

        android.util.Log.d("RouteView", "Total locations for trip: " + allLocations.size());
        // Filter to GPS and Sensor points only (remove WiFi/Cell jumps for cleaner route)
        List<LocationDatabase.LocationPoint> routeLocations = new ArrayList<>();

        // Use all locations then deduplicate and remove points closer than 5 m
        routeLocations = filterRoutePoints(allLocations);
        android.util.Log.d("DayDetails", "Filtered route points: " + routeLocations.size() + " from " + allLocations.size());

        // Filter GPS and Sensor points only for clean route
        List<LocationDatabase.LocationPoint> filteredLocations = new ArrayList<>();
        for (LocationDatabase.LocationPoint point : allLocations) {
            String source = (point.source != null ? point.source : "").toLowerCase();
            // Include GPS and Sensor points only
            if (source.contains("gps") || source.contains("sensor")) {
                // Filter by accuracy too
                if (point.accuracy > 0 && point.accuracy < 100) {
                    filteredLocations.add(point);
                } else if (point.accuracy == 0) {
                    filteredLocations.add(point);
                }
            }
        }

        android.util.Log.d("RouteView", "Filtered GPS/Sensor points: " + filteredLocations.size());

        // Use filtered locations for drawing route
        List<LocationDatabase.LocationPoint> locations = filteredLocations.isEmpty() ?
                allLocations : filteredLocations;

        if (locations.size() < 2) {
            Toast.makeText(this, "Not enough points to draw route", Toast.LENGTH_SHORT).show();
            return;
        }

        // Convert to LatLng points
        List<LatLng> routePoints = new ArrayList<>();
        for (LocationDatabase.LocationPoint point : locations) {
            routePoints.add(new LatLng(point.latitude, point.longitude));
        }

        // Draw route line
        PolylineOptions polylineOptions = new PolylineOptions()
                .addAll(routePoints)
                .color(Color.parseColor("#4CAF50"))
                .width(7.5f)
                .geodesic(true)
                .zIndex(1000f);

        map.addPolyline(polylineOptions);

        // Add start marker (green)
        LocationDatabase.LocationPoint start = routeLocations.get(0);
        map.addMarker(new MarkerOptions()
                .position(new LatLng(start.latitude, start.longitude))
                .title("Start")
                .snippet(new java.text.SimpleDateFormat("HH:mm:ss", java.util.Locale.US)
                        .format(new java.util.Date(start.timestamp)))
                .icon(BitmapDescriptorFactory.defaultMarker(BitmapDescriptorFactory.HUE_GREEN)));

        // Add end marker (red)
        LocationDatabase.LocationPoint end = routeLocations.get(routeLocations.size() - 1);
        map.addMarker(new MarkerOptions()
                .position(new LatLng(end.latitude, end.longitude))
                .title("End")
                .snippet(new java.text.SimpleDateFormat("HH:mm:ss", java.util.Locale.US)
                        .format(new java.util.Date(end.timestamp)))
                .icon(BitmapDescriptorFactory.defaultMarker(BitmapDescriptorFactory.HUE_RED)));

        // Calculate bounds and zoom to fit route
        LatLngBounds.Builder boundsBuilder = new LatLngBounds.Builder();
        for (LatLng point : routePoints) {
            boundsBuilder.include(point);
        }
        LatLngBounds bounds = boundsBuilder.build();

        // Zoom to fit with padding
        int padding = 100; // pixels
        map.animateCamera(CameraUpdateFactory.newLatLngBounds(bounds, padding));

        // Log for debugging
        android.util.Log.d("DayDetails",
                "Route drawn: " + routeLocations.size() + " points (filtered from " +
                        allLocations.size() + " total)");
    }

    private void drawDailyRoute() {
        // Load locations for this day (cache + trips)
        List<LocationDatabase.LocationPoint> allLocations = database.getAllLocationsByDay(date);

        if (allLocations.isEmpty()) {
            return;
        }

        // Filter to GPS and Sensor points only (remove WiFi/Cell jumps for cleaner route)
        List<LocationDatabase.LocationPoint> routeLocations = new ArrayList<>();

        // Use all locations then deduplicate and remove points closer than 5 m
        routeLocations = filterRoutePoints(allLocations);
        android.util.Log.d("DayDetails", "Filtered route points: " + routeLocations.size() + " from " + allLocations.size());

        // Need at least 2 points to draw a route
        if (routeLocations.size() < 2) {
            // Just show single point marker
            if (!routeLocations.isEmpty()) {
                LocationDatabase.LocationPoint point = routeLocations.get(0);
                LatLng position = new LatLng(point.latitude, point.longitude);
                map.addMarker(new MarkerOptions()
                        .position(position)
                        .title("Location")
                        .icon(BitmapDescriptorFactory.defaultMarker(BitmapDescriptorFactory.HUE_BLUE)));
                map.animateCamera(CameraUpdateFactory.newLatLngZoom(position, 15f));
            }
            return;
        }

        // Create route polyline from filtered points
//        List<LatLng> routePoints = new ArrayList<>();
//        LatLngBounds.Builder boundsBuilder = new LatLngBounds.Builder();
//
////        for (LocationDatabase.LocationPoint point : routeLocations) {
//        for (int i = 0; i < routeLocations.size() ; i++) {
//            LocationDatabase.LocationPoint point = routeLocations.get(i);
//            LatLng latLng = new LatLng(point.latitude, point.longitude);
//            routePoints.add(latLng);
//            boundsBuilder.include(latLng);
//        }
//
//        // Draw polyline (green for daily route to match web monitor)
//        PolylineOptions polylineOptions = new PolylineOptions()
//                .addAll(routePoints)
//                .color(Color.parseColor("#4CAF50"))  // Green
//                .width(10f)
//                .geodesic(false);
//
//        map.addPolyline(polylineOptions);

        // Draw route as separate segments — if two consecutive points are more
        // than 50 m apart the segment is skipped (e.g. gap between trips or
        // a long stationary period where location jumped).
        LatLngBounds.Builder boundsBuilder = new LatLngBounds.Builder();
        List<LatLng> segment = new ArrayList<>();
        LocationDatabase.LocationPoint prev = null;
        final float MAX_SEGMENT_GAP_M = 200f;

        for (LocationDatabase.LocationPoint point : routeLocations) {
            LatLng latLng = new LatLng(point.latitude, point.longitude);
            boundsBuilder.include(latLng);

            if (prev == null) {
                segment.add(latLng);
            } else {
                float[] dist = new float[1];
                android.location.Location.distanceBetween(
                        prev.latitude, prev.longitude,
                        point.latitude, point.longitude, dist);

                if (dist[0] > MAX_SEGMENT_GAP_M) {
                    // Gap too large — commit the current segment and start a new one
                    if (segment.size() >= 2) {
                        map.addPolyline(new PolylineOptions()
                                .addAll(segment)
                                .color(Color.parseColor("#4CAF50"))
                                .width(10f)
                                .geodesic(true));
                    }
                    segment = new ArrayList<>();
                }
                segment.add(latLng);
            }
            prev = point;
        }

        // Commit the final segment
        if (segment.size() >= 2) {
            map.addPolyline(new PolylineOptions()
                    .addAll(segment)
                    .color(Color.parseColor("#4CAF50"))
                    .width(10f)
                    .geodesic(true));
        }

        // Add start marker (green)
        LocationDatabase.LocationPoint start = routeLocations.get(0);
        map.addMarker(new MarkerOptions()
                .position(new LatLng(start.latitude, start.longitude))
                .title("Start")
                .snippet(new java.text.SimpleDateFormat("HH:mm:ss", java.util.Locale.US)
                        .format(new java.util.Date(start.timestamp)))
                .icon(BitmapDescriptorFactory.defaultMarker(BitmapDescriptorFactory.HUE_GREEN)));

        // Add end marker (red)
        LocationDatabase.LocationPoint end = routeLocations.get(routeLocations.size() - 1);
        map.addMarker(new MarkerOptions()
                .position(new LatLng(end.latitude, end.longitude))
                .title("End")
                .snippet(new java.text.SimpleDateFormat("HH:mm:ss", java.util.Locale.US)
                        .format(new java.util.Date(end.timestamp)))
                .icon(BitmapDescriptorFactory.defaultMarker(BitmapDescriptorFactory.HUE_RED)));

        // Calculate bounds to show entire route
        LatLngBounds bounds = boundsBuilder.build();

        // Move camera to show entire route with padding
        int padding = 100; // pixels
        map.animateCamera(CameraUpdateFactory.newLatLngBounds(bounds, padding));

        // Log for debugging
        android.util.Log.d("DayDetails",
                "Route drawn: " + routeLocations.size() + " points (filtered from " +
                        allLocations.size() + " total)");
    }

    /**
     * Remove duplicate coordinates and points closer than 5 m from the previous kept point.
     * Keeps the first occurrence of any duplicate and preserves chronological order.
     */
    private List<LocationDatabase.LocationPoint> filterRoutePoints(
            List<LocationDatabase.LocationPoint> input) {

        // 1. Sort ascending by timestamp — route must go start → end
        List<LocationDatabase.LocationPoint> sorted = new ArrayList<>(input);
        Collections.sort(sorted, (a, b) -> Long.compare(a.timestamp, b.timestamp));

        // 2. Deduplicate same-timestamp entries (cache table and trip table both
        //    store every fix; keep only the first occurrence per timestamp).
        List<LocationDatabase.LocationPoint> deduped = new ArrayList<>();
        long lastTimestamp = Long.MIN_VALUE;
        for (LocationDatabase.LocationPoint point : sorted) {
            if (point.timestamp == lastTimestamp) continue;
            deduped.add(point);
            lastTimestamp = point.timestamp;
        }

        // 3. Skip points within 10 m of the previous kept point (noise reduction)
        List<LocationDatabase.LocationPoint> result = new ArrayList<>();
        LocationDatabase.LocationPoint last = null;
        for (LocationDatabase.LocationPoint point : deduped) {
            if (last == null) {
                result.add(point);
                last = point;
                continue;
            }
            float[] distResult = new float[1];
            android.location.Location.distanceBetween(
                    last.latitude, last.longitude,
                    point.latitude, point.longitude,
                    distResult);
            if (distResult[0] < 10f) continue; // skip < 10 m
            result.add(point);
            last = point;
        }
        return result;
    }

    private void drawPOIDailyRoute() {
        // Load locations for this day (cache + trips)
        List<LocationDatabase.LocationPoint> allLocations = database.getAllLocationsByDay(date);

        if (allLocations.isEmpty()) {
            return;
        }

        android.util.Log.d("DayDetails", "Displaying " + allLocations.size() + " location points as markers");

        // Calculate bounds to fit all markers
        LatLngBounds.Builder boundsBuilder = new LatLngBounds.Builder();
        List<LocationDatabase.LocationPoint> routeLocations = new ArrayList<>();
        routeLocations = filterRoutePoints(allLocations);

        List<LatLng> routePoints = new ArrayList<>();

        // Add a marker for each location point
        for (int i = 0; i < routeLocations.size(); i++) {
            LocationDatabase.LocationPoint point = routeLocations.get(i);
            LatLng position = new LatLng(point.latitude, point.longitude);
            boundsBuilder.include(position);

            LatLng latLng = new LatLng(point.latitude, point.longitude);
            routePoints.add(latLng);

            // Format time
            java.text.SimpleDateFormat timeFormat = new java.text.SimpleDateFormat("HH:mm:ss", java.util.Locale.US);
            String time = timeFormat.format(new java.util.Date(point.timestamp));

            // Determine marker color based on source
            float markerColor;
            String source = (point.source != null ? point.source : "UNKNOWN").toUpperCase();

            if (source.contains("GPS")) {
                markerColor = BitmapDescriptorFactory.HUE_BLUE;     // Blue for GPS
            } else if (source.contains("WIFI") || source.contains("WI-FI")) {
                markerColor = BitmapDescriptorFactory.HUE_ORANGE;   // Orange for WiFi
            } else if (source.contains("CELL") || source.contains("NETWORK")) {
                markerColor = BitmapDescriptorFactory.HUE_RED;      // Red for Cell
            } else if (source.contains("SENSOR")) {
                markerColor = BitmapDescriptorFactory.HUE_GREEN;    // Green for Sensor
            } else {
                markerColor = BitmapDescriptorFactory.HUE_VIOLET;   // Violet for Unknown
            }

            // Format speed if available
            String speedInfo = "";
            if (point.speed > 0) {
                speedInfo = String.format(java.util.Locale.US, " | %.1f km/h", point.speed * 3.6);
            }

            // Format accuracy if available
            String accuracyInfo = "";
            if (point.accuracy > 0) {
                accuracyInfo = String.format(java.util.Locale.US, " | ±%.0fm", point.accuracy);
            }

            // Create marker
            MarkerOptions markerOptions = new MarkerOptions()
                    .position(position)
                    .title(time + " - " + source)
                    .snippet(String.format(java.util.Locale.US,
                            "%.6f, %.6f%s%s",
                            point.latitude, point.longitude, speedInfo, accuracyInfo))
                    .icon(BitmapDescriptorFactory.defaultMarker(markerColor));

            // Make first and last markers slightly different
            if (i == 0) {
                // First point - make it stand out with star icon
                markerOptions.title("🌅 Day Start - " + time)
                        .icon(BitmapDescriptorFactory.defaultMarker(BitmapDescriptorFactory.HUE_GREEN))
                        .alpha(1.0f);
            } else if (i == allLocations.size() - 1) {
                // Last point - make it stand out
                markerOptions.title("🏁 Day End -" + time)
                        .icon(BitmapDescriptorFactory.defaultMarker(BitmapDescriptorFactory.HUE_RED))
                        .alpha(1.0f);
            } else {
                // Regular points - slightly transparent
                markerOptions.alpha(0.7f);
            }

            map.addMarker(markerOptions);
        }

//        // Draw polyline (green for daily route to match web monitor)
//        PolylineOptions polylineOptions = new PolylineOptions()
//                .addAll(routePoints)
//                .color(Color.parseColor("#4CAF50"))  // Green
//                .width(10f)
//                .geodesic(true);
//
//        map.addPolyline(polylineOptions);

        // Fit map to show all markers
        LatLngBounds bounds = boundsBuilder.build();
        int padding = 100; // pixels
        map.animateCamera(CameraUpdateFactory.newLatLngBounds(bounds, padding));

        android.util.Log.d("DayDetails", "All markers displayed successfully");
    }

    @Override
    public boolean onOptionsItemSelected(@NonNull MenuItem item) {
        if (item.getItemId() == android.R.id.home) {
            finish();
            return true;
        }
        return super.onOptionsItemSelected(item);
    }

    private BitmapDescriptor bitmapDescriptorFromVector(@DrawableRes int vectorResId) {
        Drawable drawable = ContextCompat.getDrawable(this, vectorResId);
        drawable.setBounds(0, 0, drawable.getIntrinsicWidth(), drawable.getIntrinsicHeight());
        Bitmap bitmap = Bitmap.createBitmap(
                drawable.getIntrinsicWidth(), drawable.getIntrinsicHeight(), Bitmap.Config.ARGB_8888);
        Canvas canvas = new Canvas(bitmap);
        drawable.draw(canvas);
        return BitmapDescriptorFactory.fromBitmap(bitmap);
    }
}