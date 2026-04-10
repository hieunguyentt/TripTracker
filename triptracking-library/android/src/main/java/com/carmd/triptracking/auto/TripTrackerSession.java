package com.carmd.triptracking.auto;

import android.content.Intent;
import android.util.Log;
import androidx.annotation.NonNull;
import androidx.car.app.Screen;
import androidx.car.app.Session;

/**
 * Android Auto session. Created when the user opens TripTracker on the car head unit.
 * Returns the navigation-style TripTrackerScreen.
 */
public class TripTrackerSession extends Session {

    private static final String TAG = "TripTrackerSession";

    @Override
    @NonNull
    public Screen onCreateScreen(@NonNull Intent intent) {
        Log.d(TAG, "Creating navigation screen for Android Auto");
        return new TripTrackerScreen(getCarContext());
    }
}
