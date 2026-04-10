package com.carmd.triptracking.ui;

import android.content.Intent;
import android.os.Bundle;
import android.view.LayoutInflater;
import android.view.MenuItem;
import android.view.View;
import android.view.ViewGroup;
import android.widget.TextView;
import androidx.annotation.NonNull;
import androidx.appcompat.app.AppCompatActivity;
import androidx.cardview.widget.CardView;
import androidx.core.content.ContextCompat;
import androidx.recyclerview.widget.LinearLayoutManager;
import androidx.recyclerview.widget.RecyclerView;
import com.carmd.triptracking.R;
import com.carmd.triptracking.database.LocationDatabase;
import java.util.ArrayList;
import java.util.List;

public class DailyLocationsActivity extends AppCompatActivity {

    private RecyclerView recyclerView;
    private DailySummaryAdapter adapter;
    private LocationDatabase database;

    @Override
    protected void onCreate(Bundle savedInstanceState) {
        super.onCreate(savedInstanceState);
        setContentView(R.layout.activity_daily_locations);

        if (getSupportActionBar() != null) {
            getSupportActionBar().setDisplayHomeAsUpEnabled(true);
            getSupportActionBar().setTitle("Daily Locations");
            // Set action bar color
            getSupportActionBar().setBackgroundDrawable(
                new android.graphics.drawable.ColorDrawable(
                    ContextCompat.getColor(this, R.color.header_blue)
                )
            );
        }

        database = LocationDatabase.getInstance(this);

        recyclerView = findViewById(R.id.recyclerViewDays);
        recyclerView.setLayoutManager(new LinearLayoutManager(this));

        loadDailySummaries();
    }

    private void loadDailySummaries() {
        List<LocationDatabase.DailySummary> summaries = database.getAllDailySummaries();
        
        android.util.Log.d("DailyLocations", "📊 Loading daily summaries");
        android.util.Log.d("DailyLocations", "Found " + summaries.size() + " days with data");
        
        if (summaries.isEmpty()) {
            android.widget.Toast.makeText(this, 
                "No location data found. Start tracking to see daily locations.", 
                android.widget.Toast.LENGTH_LONG).show();
        }

        adapter = new DailySummaryAdapter(summaries);
        recyclerView.setAdapter(adapter);
    }

    @Override
    public boolean onOptionsItemSelected(@NonNull MenuItem item) {
        if (item.getItemId() == android.R.id.home) {
            finish();
            return true;
        }
        return super.onOptionsItemSelected(item);
    }

    // Adapter for daily summaries
    private class DailySummaryAdapter extends RecyclerView.Adapter<DailySummaryAdapter.ViewHolder> {

        private final List<LocationDatabase.DailySummary> summaries;

        DailySummaryAdapter(List<LocationDatabase.DailySummary> summaries) {
            this.summaries = summaries != null ? summaries : new ArrayList<>();
        }

        @NonNull
        @Override
        public ViewHolder onCreateViewHolder(@NonNull ViewGroup parent, int viewType) {
            View view = LayoutInflater.from(parent.getContext())
                    .inflate(R.layout.item_daily_summary, parent, false);
            return new ViewHolder(view);
        }

        @Override
        public void onBindViewHolder(@NonNull ViewHolder holder, int position) {
            LocationDatabase.DailySummary summary = summaries.get(position);

            holder.tvDate.setText(summary.getFormattedDate());
            holder.tvTimeRange.setText(summary.getFormattedTimeRange());
            holder.tvLocationCount.setText(summary.locationCount + " pts");
            holder.tvDistance.setText(summary.getFormattedDistance());
            holder.tvDuration.setText(summary.getFormattedDuration());

            // Format sources
            if (summary.sources != null && !summary.sources.isEmpty()) {
                StringBuilder sourcesText = new StringBuilder();
                for (int i = 0; i < Math.min(summary.sources.size(), 2); i++) {
                    if (i > 0) sourcesText.append("+");
                    String source = summary.sources.get(i);
                    // Shorten source names
                    if ("SENSORS".equals(source)) source = "SEN";
                    sourcesText.append(source);
                }
                holder.tvSources.setText(sourcesText.toString());
            } else {
                holder.tvSources.setText("-");
            }

            // Click to view day details
            holder.itemView.setOnClickListener(v -> {
                Intent intent = new Intent(DailyLocationsActivity.this, DayDetailsActivity.class);
                intent.putExtra("date", summary.date);
                startActivity(intent);
            });
        }

        @Override
        public int getItemCount() {
            return summaries.size();
        }

        class ViewHolder extends RecyclerView.ViewHolder {
            TextView tvDate, tvTimeRange, tvLocationCount, tvDistance, tvDuration, tvSources;

            ViewHolder(View itemView) {
                super(itemView);
                tvDate = itemView.findViewById(R.id.tvDate);
                tvTimeRange = itemView.findViewById(R.id.tvTimeRange);
                tvLocationCount = itemView.findViewById(R.id.tvLocationCount);
                tvDistance = itemView.findViewById(R.id.tvDistance);
                tvDuration = itemView.findViewById(R.id.tvDuration);
                tvSources = itemView.findViewById(R.id.tvSources);
            }
        }
    }
}
