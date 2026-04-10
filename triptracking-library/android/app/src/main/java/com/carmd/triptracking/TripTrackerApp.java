package com.carmd.triptracking;

import android.app.Application;
import com.carmd.triptracking.util.LogcatWriter;

public class TripTrackerApp extends Application {

    @Override
    public void onCreate() {
        super.onCreate();
        // Start capturing logcat as early as possible
        LogcatWriter.start(this);
    }
}
