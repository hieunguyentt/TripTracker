package com.carmd.triptracking.ui;

import android.graphics.Color;
import android.os.Bundle;
import android.widget.TextView;
import android.widget.Toast;
import androidx.annotation.NonNull;
import androidx.appcompat.app.AppCompatActivity;
import com.carmd.triptracking.R;
import com.carmd.triptracking.database.LocationDatabase;
import com.google.android.gms.maps.CameraUpdateFactory;
import com.google.android.gms.maps.GoogleMap;
import com.google.android.gms.maps.OnMapReadyCallback;
import com.google.android.gms.maps.SupportMapFragment;
import com.google.android.gms.maps.model.*;
import java.text.SimpleDateFormat;
import java.util.ArrayList;
import java.util.Date;
import java.util.List;
import java.util.Locale;

public class RouteViewActivity extends AppCompatActivity implements OnMapReadyCallback {
    
    private GoogleMap map;
    private LocationDatabase database;
    private long tripId;
    private TextView tvTripInfo;
    
    @Override
    protected void onCreate(Bundle savedInstanceState) {
        super.onCreate(savedInstanceState);
        setContentView(R.layout.activity_route_view);
        
        if (getSupportActionBar() != null) {
            getSupportActionBar().setDisplayHomeAsUpEnabled(true);
            getSupportActionBar().setTitle("Route Details");
        }
        
        database = LocationDatabase.getInstance(this);
        tripId = getIntent().getLongExtra("trip_id", -1);
        
        if (tripId == -1) {
            Toast.makeText(this, "Error: Invalid trip ID", Toast.LENGTH_SHORT).show();
            finish();
            return;
        }
        
        tvTripInfo = findViewById(R.id.tvTripInfo);
        
        SupportMapFragment mapFragment = (SupportMapFragment) getSupportFragmentManager()
                .findFragmentById(R.id.mapRoute);
        if (mapFragment != null) {
            mapFragment.getMapAsync(this);
        }
        
        loadTripInfo();
    }
    
    private void loadTripInfo() {
        List<LocationDatabase.Trip> trips = database.getAllTrips();
        LocationDatabase.Trip trip = null;
        
        for (LocationDatabase.Trip t : trips) {
            if (t.id == tripId) {
                trip = t;
                break;
            }
        }
        
        if (trip != null) {
            SimpleDateFormat dateFormat = new SimpleDateFormat("MMM dd, yyyy HH:mm", Locale.US);
            String date = dateFormat.format(new Date(trip.startTime));
            
            // Calculate actual distance from location points
            double calculatedDistance = database.calculateTripDistance(tripId);
            
            // Use calculated distance (more accurate)
            String distance = calculatedDistance < 1000 ? 
                    String.format(Locale.US, "%.0f m", calculatedDistance) :
                    String.format(Locale.US, "%.2f km", calculatedDistance / 1000);
            
            // Show difference if stored distance differs significantly
            String distanceNote = "";
            if (Math.abs(trip.distance - calculatedDistance) > 10.0) {
                distanceNote = String.format(Locale.US, " (stored: %.0fm)", trip.distance);
            }
            
            long minutes = trip.duration / 60;
            long seconds = trip.duration % 60;
            String duration = String.format(Locale.US, "%d:%02d", minutes, seconds);
            
            int locationCount = database.getLocationCount(tripId);
            
            String info = String.format(Locale.US,
                    "📅 %s\n📏 Distance: %s%s\n⏱️ Duration: %s  |  🚶 Steps: %d  |  📍 Points: %d",
                    date, distance, distanceNote, duration, trip.steps, locationCount);
            
            tvTripInfo.setText(info);
        }
    }
    
    @Override
    public void onMapReady(@NonNull GoogleMap googleMap) {
        map = googleMap;
        map.getUiSettings().setZoomControlsEnabled(true);
        map.getUiSettings().setCompassEnabled(true);
        
        loadAndDrawRoute();
    }
    
    private void loadAndDrawRoute() {
        // Load ALL locations from database
        List<LocationDatabase.LocationPoint> allLocations = database.getLocationsForTrip(tripId);
        
        if (allLocations.isEmpty()) {
            Toast.makeText(this, "No location data for this trip", Toast.LENGTH_SHORT).show();
            return;
        }
        
        android.util.Log.d("RouteView", "Total locations for trip: " + allLocations.size());
        
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
                .color(getColorForSource(locations.get(0).source))
                .width(10f)
                .geodesic(true)
                .zIndex(1000f);
        
        map.addPolyline(polylineOptions);
        
        // Add start marker (green)
        LatLng startPoint = routePoints.get(0);
        map.addMarker(new MarkerOptions()
                .position(startPoint)
                .title("Start")
                .snippet(formatTime(locations.get(0).timestamp))
                .icon(BitmapDescriptorFactory.defaultMarker(BitmapDescriptorFactory.HUE_GREEN)));
        
        // Add end marker (red)
        LatLng endPoint = routePoints.get(routePoints.size() - 1);
        map.addMarker(new MarkerOptions()
                .position(endPoint)
                .title("End")
                .snippet(formatTime(locations.get(locations.size() - 1).timestamp))
                .icon(BitmapDescriptorFactory.defaultMarker(BitmapDescriptorFactory.HUE_RED)));
        
        // Add waypoint markers every 10 points
//        for (int i = 10; i < locations.size() - 10; i += 10) {
//            LocationDatabase.LocationPoint point = locations.get(i);
//            map.addMarker(new MarkerOptions()
//                    .position(new LatLng(point.latitude, point.longitude))
//                    .title("Waypoint " + (i / 10))
//                    .snippet(formatTime(point.timestamp) + " | " + point.source)
//                    .icon(BitmapDescriptorFactory.defaultMarker(BitmapDescriptorFactory.HUE_AZURE))
//                    .alpha(0.7f));
//        }

        // Calculate bounds and zoom to fit route
        LatLngBounds.Builder boundsBuilder = new LatLngBounds.Builder();
        for (LatLng point : routePoints) {
            boundsBuilder.include(point);
        }
        LatLngBounds bounds = boundsBuilder.build();
        
        // Zoom to fit with padding
        int padding = 100; // pixels
        map.animateCamera(CameraUpdateFactory.newLatLngBounds(bounds, padding));
        
        Toast.makeText(this, "Route loaded: " + locations.size() + " points", 
                Toast.LENGTH_SHORT).show();
    }
    
    private int getColorForSource(String source) {
        if (source == null) return Color.GREEN;
        
        switch (source.toUpperCase()) {
            case "SENSORS":
                return Color.parseColor("#4CAF50"); // Green
            case "GPS":
                return Color.parseColor("#9C27B0"); // Purple
            case "WIFI":
                return Color.parseColor("#2196F3"); // Blue
            case "CELL":
                return Color.parseColor("#FF9800"); // Orange
            default:
                return Color.GREEN;
        }
    }
    
    private String formatTime(long timestamp) {
        SimpleDateFormat sdf = new SimpleDateFormat("HH:mm:ss", Locale.US);
        return sdf.format(new Date(timestamp));
    }
    
    @Override
    public boolean onSupportNavigateUp() {
        finish();
        return true;
    }
}
