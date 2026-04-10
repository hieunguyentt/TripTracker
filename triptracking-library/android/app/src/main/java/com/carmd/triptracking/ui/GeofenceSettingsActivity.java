package com.carmd.triptracking.ui;

import android.Manifest;
import android.app.AlertDialog;
import android.content.pm.PackageManager;
import android.graphics.Color;
import android.location.Location;
import android.location.LocationManager;
import android.os.Bundle;
import android.view.LayoutInflater;
import android.view.View;
import android.widget.CheckBox;
import android.widget.EditText;
import android.widget.LinearLayout;
import android.widget.SeekBar;
import android.widget.TextView;
import android.widget.Toast;
import androidx.annotation.NonNull;
import androidx.appcompat.app.AppCompatActivity;
import androidx.core.app.ActivityCompat;
import androidx.core.content.ContextCompat;
import com.carmd.triptracking.R;
import com.carmd.triptracking.geofence.GeofenceManager;
import com.carmd.triptracking.geofence.GeofenceManager.GeofenceZone;
import com.google.android.gms.maps.CameraUpdateFactory;
import com.google.android.gms.maps.GoogleMap;
import com.google.android.gms.maps.OnMapReadyCallback;
import com.google.android.gms.maps.SupportMapFragment;
import com.google.android.gms.maps.model.*;

import java.util.HashMap;
import java.util.List;
import java.util.Locale;
import java.util.Map;

/**
 * Full-screen map activity for managing geofence zones.
 *
 * - Long-press on map to add a new geofence at that location
 * - Tap an existing marker to view/delete the geofence
 * - Circles show the radius of each zone
 * - List of zones shown at bottom
 */
public class GeofenceSettingsActivity extends AppCompatActivity implements OnMapReadyCallback {

    private GoogleMap map;
    private LinearLayout llZoneList;
    private final Map<String, Marker> markers = new HashMap<>();
    private final Map<String, Circle> circles = new HashMap<>();

    @Override
    protected void onCreate(Bundle savedInstanceState) {
        super.onCreate(savedInstanceState);
        setContentView(R.layout.activity_geofence_settings);

        if (getSupportActionBar() != null) {
            getSupportActionBar().setTitle("Geofence Zones");
            getSupportActionBar().setDisplayHomeAsUpEnabled(true);
            getSupportActionBar().setBackgroundDrawable(
                    new android.graphics.drawable.ColorDrawable(
                            ContextCompat.getColor(this, R.color.header_blue)));
        }

        llZoneList = findViewById(R.id.llZoneList);
        findViewById(R.id.btnAddCurrentLocation).setOnClickListener(v -> addAtCurrentLocation());

        SupportMapFragment mapFragment = (SupportMapFragment) getSupportFragmentManager()
                .findFragmentById(R.id.mapGeofence);
        if (mapFragment != null) {
            mapFragment.getMapAsync(this);
        }
    }

    @Override
    public void onMapReady(@NonNull GoogleMap googleMap) {
        map = googleMap;
        map.getUiSettings().setZoomControlsEnabled(true);

        if (ActivityCompat.checkSelfPermission(this, Manifest.permission.ACCESS_FINE_LOCATION)
                == PackageManager.PERMISSION_GRANTED) {
            map.setMyLocationEnabled(true);
        }

        // Long-press to add new geofence
        map.setOnMapLongClickListener(latLng -> showAddDialog(latLng.latitude, latLng.longitude));

        // Tap marker to show info / delete
        map.setOnMarkerClickListener(marker -> {
            String zoneId = (String) marker.getTag();
            if (zoneId != null) {
                showZoneInfoDialog(zoneId);
            }
            return true;
        });

        // Focus on current location
        focusCurrentLocation();

        // Draw existing geofences
        refreshMapAndList();
    }

    @Override
    protected void onResume() {
        super.onResume();
        if (map != null) refreshMapAndList();
    }

    // ── Map display ──────────────────────────────────────────────────────

    private void refreshMapAndList() {
        // Clear old markers and circles
        for (Marker m : markers.values()) m.remove();
        for (Circle c : circles.values()) c.remove();
        markers.clear();
        circles.clear();

        List<GeofenceZone> zones = GeofenceManager.getAll(this);

        // Draw on map
        for (GeofenceZone zone : zones) {
            LatLng pos = new LatLng(zone.latitude, zone.longitude);

            Marker m = map.addMarker(new MarkerOptions()
                    .position(pos)
                    .title(zone.name)
                    .snippet(String.format(Locale.US, "Radius: %.0f m", zone.radiusMeters))
                    .icon(BitmapDescriptorFactory.defaultMarker(
                            zone.autoStopTrip ? BitmapDescriptorFactory.HUE_RED
                                              : BitmapDescriptorFactory.HUE_AZURE)));
            if (m != null) {
                m.setTag(zone.id);
                markers.put(zone.id, m);
            }

            Circle c = map.addCircle(new CircleOptions()
                    .center(pos)
                    .radius(zone.radiusMeters)
                    .strokeColor(zone.autoStopTrip ? Color.argb(180, 244, 67, 54)
                                                   : Color.argb(180, 33, 150, 243))
                    .fillColor(zone.autoStopTrip ? Color.argb(40, 244, 67, 54)
                                                 : Color.argb(40, 33, 150, 243))
                    .strokeWidth(3f));
            circles.put(zone.id, c);
        }

        // Refresh list
        refreshZoneList(zones);
    }

    private void refreshZoneList(List<GeofenceZone> zones) {
        llZoneList.removeAllViews();

        if (zones.isEmpty()) {
            TextView empty = new TextView(this);
            empty.setText("No geofence zones.\nLong-press on the map to add one.");
            empty.setTextColor(Color.parseColor("#8E8E93"));
            empty.setTextSize(14);
            empty.setPadding(32, 24, 32, 24);
            llZoneList.addView(empty);
            return;
        }

        for (GeofenceZone zone : zones) {
            View row = LayoutInflater.from(this).inflate(R.layout.item_geofence_zone, llZoneList, false);

            TextView tvName   = row.findViewById(R.id.tvZoneName);
            TextView tvDetail = row.findViewById(R.id.tvZoneDetail);
            View btnDelete    = row.findViewById(R.id.btnDeleteZone);

            tvName.setText(zone.name);
            String flags = "";
            if (zone.notifyOnEnter) flags += "Enter ";
            if (zone.notifyOnExit)  flags += "Exit ";
            if (zone.autoStopTrip) flags += "AutoStop ";
            tvDetail.setText(String.format(Locale.US, "%.0f m • %s• (%.4f, %.4f)",
                    zone.radiusMeters, flags, zone.latitude, zone.longitude));

            row.setOnClickListener(v -> {
                LatLng pos = new LatLng(zone.latitude, zone.longitude);
                map.animateCamera(CameraUpdateFactory.newLatLngZoom(pos, 16f));
            });

            btnDelete.setOnClickListener(v -> {
                new AlertDialog.Builder(this)
                        .setTitle("Delete " + zone.name + "?")
                        .setMessage("This geofence zone will be removed.")
                        .setPositiveButton("Delete", (d, w) -> {
                            GeofenceManager.removeZone(this, zone.id);
                            refreshMapAndList();
                            Toast.makeText(this, "Deleted: " + zone.name, Toast.LENGTH_SHORT).show();
                        })
                        .setNegativeButton("Cancel", null)
                        .show();
            });

            llZoneList.addView(row);
        }
    }

    // ── Add dialog ───────────────────────────────────────────────────────

    private void showAddDialog(double lat, double lng) {
        View dialogView = LayoutInflater.from(this).inflate(R.layout.dialog_add_geofence, null);

        EditText etName       = dialogView.findViewById(R.id.etGeofenceName);
        TextView tvRadius     = dialogView.findViewById(R.id.tvRadiusValue);
        SeekBar  sbRadius     = dialogView.findViewById(R.id.sbRadius);
        CheckBox cbEnter      = dialogView.findViewById(R.id.cbNotifyEnter);
        CheckBox cbExit       = dialogView.findViewById(R.id.cbNotifyExit);
        CheckBox cbAutoStop   = dialogView.findViewById(R.id.cbAutoStopTrip);
        TextView tvCoords     = dialogView.findViewById(R.id.tvCoordinates);

        tvCoords.setText(String.format(Locale.US, "%.6f, %.6f", lat, lng));

        // Radius: 50 – 2000 m, step 50, default 200
        sbRadius.setMax(39); // (2000-50)/50 = 39
        sbRadius.setProgress(3); // (200-50)/50 = 3
        tvRadius.setText("200 m");
        sbRadius.setOnSeekBarChangeListener(new SeekBar.OnSeekBarChangeListener() {
            @Override public void onProgressChanged(SeekBar sb, int p, boolean u) {
                int radius = 50 + p * 50;
                tvRadius.setText(radius + " m");
            }
            @Override public void onStartTrackingTouch(SeekBar sb) {}
            @Override public void onStopTrackingTouch(SeekBar sb) {}
        });

        new AlertDialog.Builder(this)
                .setTitle("📍 Add Geofence Zone")
                .setView(dialogView)
                .setPositiveButton("Add", (d, w) -> {
                    String name = etName.getText().toString().trim();
                    if (name.isEmpty()) name = "Zone";
                    int radius = 50 + sbRadius.getProgress() * 50;

                    GeofenceZone zone = new GeofenceZone(
                            name, lat, lng, radius,
                            cbEnter.isChecked(), cbExit.isChecked(),
                            cbAutoStop.isChecked());
                    GeofenceManager.addZone(this, zone);
                    refreshMapAndList();

                    map.animateCamera(CameraUpdateFactory.newLatLngZoom(
                            new LatLng(lat, lng), 16f));
                    Toast.makeText(this, "Added: " + name, Toast.LENGTH_SHORT).show();
                })
                .setNegativeButton("Cancel", null)
                .show();
    }

    private void showZoneInfoDialog(String zoneId) {
        GeofenceZone zone = GeofenceManager.getById(this, zoneId);
        if (zone == null) return;

        String info = "Name: " + zone.name
                + "\nRadius: " + (int) zone.radiusMeters + " m"
                + "\nPosition: " + String.format(Locale.US, "%.6f, %.6f", zone.latitude, zone.longitude)
                + "\nNotify Enter: " + (zone.notifyOnEnter ? "Yes" : "No")
                + "\nNotify Exit: " + (zone.notifyOnExit ? "Yes" : "No")
                + "\nAuto-stop Trip: " + (zone.autoStopTrip ? "Yes" : "No");

        new AlertDialog.Builder(this)
                .setTitle("📍 " + zone.name)
                .setMessage(info)
                .setNeutralButton("Delete", (d, w) -> {
                    GeofenceManager.removeZone(this, zone.id);
                    refreshMapAndList();
                    Toast.makeText(this, "Deleted: " + zone.name, Toast.LENGTH_SHORT).show();
                })
                .setPositiveButton("Close", null)
                .show();
    }

    // ── Add at current GPS location ──────────────────────────────────────

    private void addAtCurrentLocation() {
        if (ActivityCompat.checkSelfPermission(this, Manifest.permission.ACCESS_FINE_LOCATION)
                != PackageManager.PERMISSION_GRANTED) {
            Toast.makeText(this, "Location permission required", Toast.LENGTH_SHORT).show();
            return;
        }

        LocationManager lm = (LocationManager) getSystemService(LOCATION_SERVICE);
        Location loc = lm.getLastKnownLocation(LocationManager.GPS_PROVIDER);
        if (loc == null) loc = lm.getLastKnownLocation(LocationManager.PASSIVE_PROVIDER);

        if (loc != null) {
            showAddDialog(loc.getLatitude(), loc.getLongitude());
        } else {
            Toast.makeText(this, "No current location available", Toast.LENGTH_SHORT).show();
        }
    }

    private void focusCurrentLocation() {
        if (ActivityCompat.checkSelfPermission(this, Manifest.permission.ACCESS_FINE_LOCATION)
                != PackageManager.PERMISSION_GRANTED) return;

        LocationManager lm = (LocationManager) getSystemService(LOCATION_SERVICE);
        Location loc = lm.getLastKnownLocation(LocationManager.GPS_PROVIDER);
        if (loc == null) loc = lm.getLastKnownLocation(LocationManager.PASSIVE_PROVIDER);

        if (loc != null) {
            map.moveCamera(CameraUpdateFactory.newLatLngZoom(
                    new LatLng(loc.getLatitude(), loc.getLongitude()), 15f));
        }
    }

    @Override
    public boolean onSupportNavigateUp() { finish(); return true; }
}
