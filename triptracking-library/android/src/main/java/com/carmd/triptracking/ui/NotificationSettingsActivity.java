package com.carmd.triptracking.ui;

import android.os.Bundle;
import androidx.appcompat.app.AppCompatActivity;
import androidx.appcompat.widget.SwitchCompat;
import androidx.core.content.ContextCompat;
import com.carmd.triptracking.R;

public class NotificationSettingsActivity extends AppCompatActivity {

    @Override
    protected void onCreate(Bundle savedInstanceState) {
        super.onCreate(savedInstanceState);
        setContentView(R.layout.activity_notification_settings);

        if (getSupportActionBar() != null) {
            getSupportActionBar().setTitle("Notifications");
            getSupportActionBar().setDisplayHomeAsUpEnabled(true);
            getSupportActionBar().setBackgroundDrawable(
                    new android.graphics.drawable.ColorDrawable(
                            ContextCompat.getColor(this, R.color.header_blue)));
        }

        // Push Notifications
        bindSwitch(R.id.switchTripStart, AppSettings.isNotifTripStart(this),
                checked -> AppSettings.setNotifTripStart(this, checked));

        bindSwitch(R.id.switchTripEnd, AppSettings.isNotifTripEnd(this),
                checked -> AppSettings.setNotifTripEnd(this, checked));

        bindSwitch(R.id.switchDistanceKm, AppSettings.isNotifDistanceKm(this),
                checked -> AppSettings.setNotifDistanceKm(this, checked));

        bindSwitch(R.id.switchGeofenceEnter, AppSettings.isNotifGeofenceEnter(this),
                checked -> AppSettings.setNotifGeofenceEnter(this, checked));

        bindSwitch(R.id.switchGeofenceExit, AppSettings.isNotifGeofenceExit(this),
                checked -> AppSettings.setNotifGeofenceExit(this, checked));

        // Voice Feedback
        bindSwitch(R.id.switchVoiceEnabled, AppSettings.isVoiceEnabled(this),
                checked -> AppSettings.setVoiceEnabled(this, checked));
    }

    private void bindSwitch(int id, boolean currentValue, OnToggle listener) {
        SwitchCompat sw = findViewById(id);
        sw.setChecked(currentValue);
        sw.setOnCheckedChangeListener((btn, checked) -> listener.onToggle(checked));
    }

    private interface OnToggle {
        void onToggle(boolean checked);
    }

    @Override
    public boolean onSupportNavigateUp() {
        finish();
        return true;
    }
}
