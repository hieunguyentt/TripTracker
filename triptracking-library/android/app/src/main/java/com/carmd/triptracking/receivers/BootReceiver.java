package com.carmd.triptracking.receivers;

import android.content.BroadcastReceiver;
import android.content.Context;
import android.content.Intent;
import android.os.Build;
import android.util.Log;
import com.carmd.triptracking.services.LocationTrackingService;

/**
 * Receives BOOT_COMPLETED broadcast to start location tracking automatically
 */
public class BootReceiver extends BroadcastReceiver {
    private static final String TAG = "BootReceiver";

    @Override
    public void onReceive(Context context, Intent intent) {
        String action = intent.getAction();
        if (Intent.ACTION_BOOT_COMPLETED.equals(action)
                || "android.intent.action.QUICKBOOT_POWERON".equals(action)
                || "android.intent.action.LOCKED_BOOT_COMPLETED".equals(action)) {
            Log.d(TAG, "📱 Device booted - Starting location tracking service");
            
            Intent serviceIntent = new Intent(context, LocationTrackingService.class);
            // On boot, try to resume any trip that was active before the reboot.
            // tryResumeFromCheckpoint() will do nothing if no checkpoint exists.
            serviceIntent.setAction(LocationTrackingService.ACTION_RESUME_TRACKING);
            
            if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.O) {
                context.startForegroundService(serviceIntent);
            } else {
                context.startService(serviceIntent);
            }
            
            Log.d(TAG, "✅ Location tracking service started automatically");
        }
    }
}
