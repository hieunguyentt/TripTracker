package com.carmd.triptracking.ui;

import android.content.Intent;
import android.os.Bundle;
import android.view.LayoutInflater;
import android.view.Menu;
import android.view.MenuItem;
import android.view.View;
import android.view.ViewGroup;
import android.widget.TextView;
import android.widget.Toast;
import androidx.annotation.NonNull;
import androidx.appcompat.app.AlertDialog;
import androidx.appcompat.app.AppCompatActivity;
import androidx.recyclerview.widget.LinearLayoutManager;
import androidx.recyclerview.widget.RecyclerView;
import com.carmd.triptracking.R;
import com.carmd.triptracking.database.LocationDatabase;
import java.text.SimpleDateFormat;
import java.util.ArrayList;
import java.util.Date;
import java.util.List;
import java.util.Locale;

public class TripHistoryActivity extends AppCompatActivity {
    
    private RecyclerView recyclerView;
    private TripAdapter adapter;
    private LocationDatabase database;
    private TextView tvStats;
    
    @Override
    protected void onCreate(Bundle savedInstanceState) {
        super.onCreate(savedInstanceState);
        setContentView(R.layout.activity_trip_history);
        
        if (getSupportActionBar() != null) {
            getSupportActionBar().setDisplayHomeAsUpEnabled(true);
            getSupportActionBar().setTitle("Trip History");
        }
        
        database = LocationDatabase.getInstance(this);
        
        recyclerView = findViewById(R.id.recyclerViewTrips);
        tvStats = findViewById(R.id.tvStats);
        
        recyclerView.setLayoutManager(new LinearLayoutManager(this));
        adapter = new TripAdapter();
        recyclerView.setAdapter(adapter);
        
        loadTrips();
        loadStats();
    }
    
    private void loadTrips() {
        List<LocationDatabase.Trip> trips = database.getAllTrips();
        // Filter to only trips with actual location points (at least 2 for a route)
        List<LocationDatabase.Trip> tripsWithData = new ArrayList<>();
        for (LocationDatabase.Trip trip : trips) {
            int pointCount = database.getLocationsForTrip(trip.id).size();
            double distance = trip.distance;
            if (pointCount >= 2 && distance > 0) {  // Only include trips with actual route data
                tripsWithData.add(trip);
            }
        }

        adapter.setTrips(tripsWithData);
        
        if (tripsWithData.isEmpty()) {
            Toast.makeText(this, "No trips recorded yet", Toast.LENGTH_SHORT).show();
        }
    }
    
    private void loadStats() {
        LocationDatabase.DatabaseStats stats = database.getStats();
        
        String statsText = String.format(Locale.US,
                "📊 Total Trips: %d  |  📏 Total Distance: %.2f km  |  🚶 Total Steps: %,d",
                stats.totalTrips,
                stats.totalDistance / 1000,
                stats.totalSteps);
        
        tvStats.setText(statsText);
    }
    
    @Override
    public boolean onSupportNavigateUp() {
        finish();
        return true;
    }
    
    @Override
    public boolean onCreateOptionsMenu(Menu menu) {
        menu.add(0, 1, 0, "Recalculate All Distances")
                .setIcon(android.R.drawable.ic_menu_rotate)
                .setShowAsAction(MenuItem.SHOW_AS_ACTION_IF_ROOM);
        return true;
    }
    
    @Override
    public boolean onOptionsItemSelected(@NonNull MenuItem item) {
        if (item.getItemId() == 1) {
            showRecalculateDialog();
            return true;
        }
        return super.onOptionsItemSelected(item);
    }
    
    private void showRecalculateDialog() {
        new AlertDialog.Builder(this)
                .setTitle("Recalculate Distances")
                .setMessage("This will recalculate the distance for all trips based on stored location points. This fixes any incorrect distances from previous tracking sessions.\n\nContinue?")
                .setPositiveButton("Recalculate", (dialog, which) -> {
                    Toast.makeText(this, "Recalculating distances...", Toast.LENGTH_SHORT).show();
                    
                    // Run in background thread
                    new Thread(() -> {
                        database.recalculateAllTripDistances();
                        
                        // Update UI on main thread
                        runOnUiThread(() -> {
                            loadTrips();
                            loadStats();
                            Toast.makeText(this, "Distances recalculated successfully!", 
                                    Toast.LENGTH_LONG).show();
                        });
                    }).start();
                })
                .setNegativeButton("Cancel", null)
                .show();
    }
    
    @Override
    protected void onResume() {
        super.onResume();
        loadTrips();
        loadStats();
    }
    
    private class TripAdapter extends RecyclerView.Adapter<TripAdapter.TripViewHolder> {
        
        private List<LocationDatabase.Trip> trips = new ArrayList<>();
        
        public void setTrips(List<LocationDatabase.Trip> trips) {
            this.trips = trips;
            notifyDataSetChanged();
        }
        
        @NonNull
        @Override
        public TripViewHolder onCreateViewHolder(@NonNull ViewGroup parent, int viewType) {
            View view = LayoutInflater.from(parent.getContext())
                    .inflate(R.layout.item_trip, parent, false);
            return new TripViewHolder(view);
        }
        
        @Override
        public void onBindViewHolder(@NonNull TripViewHolder holder, int position) {
            LocationDatabase.Trip trip = trips.get(position);
            holder.bind(trip);
        }
        
        @Override
        public int getItemCount() {
            return trips.size();
        }
        
        class TripViewHolder extends RecyclerView.ViewHolder {
            
            private TextView tvDate;
            private TextView tvTime;
            private TextView tvDistance;
            private TextView tvDuration;
            private TextView tvSteps;
            private TextView tvLocations;
            
            public TripViewHolder(@NonNull View itemView) {
                super(itemView);
                tvDate = itemView.findViewById(R.id.tvDate);
                tvTime = itemView.findViewById(R.id.tvTime);
                tvDistance = itemView.findViewById(R.id.tvDistance);
                tvDuration = itemView.findViewById(R.id.tvDuration);
                tvSteps = itemView.findViewById(R.id.tvSteps);
                tvLocations = itemView.findViewById(R.id.tvLocations);
            }
            
            public void bind(LocationDatabase.Trip trip) {
                // Date
                SimpleDateFormat dateFormat = new SimpleDateFormat("MMM dd, yyyy", Locale.US);
                tvDate.setText(dateFormat.format(new Date(trip.startTime)));
                
                // Time
                SimpleDateFormat timeFormat = new SimpleDateFormat("HH:mm", Locale.US);
                String startTime = timeFormat.format(new Date(trip.startTime));
                String endTime = trip.endTime > 0 ? timeFormat.format(new Date(trip.endTime)) : "N/A";
                tvTime.setText(startTime + " - " + endTime);
                
                // Distance
                if (trip.distance < 1000) {
                    tvDistance.setText(String.format(Locale.US, "%.0f m", trip.distance));
                } else {
                    tvDistance.setText(String.format(Locale.US, "%.2f km", trip.distance / 1000));
                }
                
                // Duration
                long minutes = trip.duration / 60;
                long seconds = trip.duration % 60;
                tvDuration.setText(String.format(Locale.US, "%d:%02d", minutes, seconds));
                
                // Steps - just number
                tvSteps.setText(String.format(Locale.US, "%,d", trip.steps));
                
                // Location count - just number
                int locationCount = database.getLocationCount(trip.id);
                tvLocations.setText(String.format(Locale.US, "%,d", locationCount));
                
                // Click to view route
                itemView.setOnClickListener(v -> {
                    Intent intent = new Intent(TripHistoryActivity.this, RouteViewActivity.class);
                    intent.putExtra("trip_id", trip.id);
                    startActivity(intent);
                });
                
                // Long click to delete
                itemView.setOnLongClickListener(v -> {
                    showDeleteDialog(trip);
                    return true;
                });
            }
            
            private void showDeleteDialog(LocationDatabase.Trip trip) {
                new AlertDialog.Builder(TripHistoryActivity.this)
                        .setTitle("Delete Trip")
                        .setMessage("Are you sure you want to delete this trip?")
                        .setPositiveButton("Delete", (dialog, which) -> {
                            database.deleteTrip(trip.id);
                            loadTrips();
                            loadStats();
                            Toast.makeText(TripHistoryActivity.this, 
                                    "Trip deleted", Toast.LENGTH_SHORT).show();
                        })
                        .setNegativeButton("Cancel", null)
                        .show();
            }
        }
    }
}
