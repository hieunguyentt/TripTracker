package com.carmd.triptracking.auto;

import android.content.pm.ApplicationInfo;
import android.util.Log;
import androidx.annotation.NonNull;
import androidx.car.app.CarAppService;
import androidx.car.app.Session;
import androidx.car.app.SessionInfo;
import androidx.car.app.validation.HostValidator;

/**
 * Android Auto entry point — registered as a CarAppService in the manifest.
 * Creates a navigation-style session with live trip dashboard.
 */
public class TripTrackerCarAppService extends CarAppService {

    private static final String TAG = "TripTrackerCarApp";

    @Override
    @NonNull
    public HostValidator createHostValidator() {
        // Allow all hosts (safe for both debug and production for now)
        return HostValidator.ALLOW_ALL_HOSTS_VALIDATOR;
    }

    @Override
    @NonNull
    public Session onCreateSession() {
        Log.d(TAG, "Android Auto session created");
        return new TripTrackerSession();
    }
}
