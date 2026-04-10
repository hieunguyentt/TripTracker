package com.carmd.triptracking.geofence;

import android.app.Notification;
import android.app.NotificationManager;
import android.app.PendingIntent;
import android.content.BroadcastReceiver;
import android.content.Context;
import android.content.Intent;
import android.util.Log;
import androidx.core.app.NotificationCompat;
import com.carmd.triptracking.ui.MainActivity;
import com.carmd.triptracking.ui.AppSettings;
import com.google.android.gms.location.Geofence;
import com.google.android.gms.location.GeofencingEvent;

import java.text.SimpleDateFormat;
import java.util.Date;
import java.util.List;
import java.util.Locale;

/**
 * Receives geofence transition events from Google Play Services.
 * Shows notifications on enter/exit and logs events.
 */
public class GeofenceBroadcastReceiver extends BroadcastReceiver {

    private static final String TAG = "GeofenceReceiver";
    private static final String CHANNEL_TRIP_EVENTS = "trip_events";
    private static final int    NOTIF_GEOFENCE_BASE = 5000;

    @Override
    public void onReceive(Context context, Intent intent) {
        GeofencingEvent event = GeofencingEvent.fromIntent(intent);
        if (event == null) {
            Log.w(TAG, "GeofencingEvent is null");
            return;
        }
        if (event.hasError()) {
            Log.e(TAG, "Geofence error code: " + event.getErrorCode());
            return;
        }

        int transition = event.getGeofenceTransition();
        List<Geofence> triggeringGeofences = event.getTriggeringGeofences();
        if (triggeringGeofences == null || triggeringGeofences.isEmpty()) return;

        String transitionStr;
        String emoji;
        switch (transition) {
            case Geofence.GEOFENCE_TRANSITION_ENTER:
                transitionStr = "Entered";
                emoji = "📍";
                break;
            case Geofence.GEOFENCE_TRANSITION_EXIT:
                transitionStr = "Exited";
                emoji = "🚗";
                break;
            case Geofence.GEOFENCE_TRANSITION_DWELL:
                transitionStr = "Dwelling in";
                emoji = "🏠";
                break;
            default:
                transitionStr = "Unknown transition";
                emoji = "❓";
                break;
        }

        String time = new SimpleDateFormat("HH:mm:ss", Locale.US).format(new Date());

        for (Geofence geofence : triggeringGeofences) {
            String zoneId = geofence.getRequestId();
            GeofenceManager.GeofenceZone zone = GeofenceManager.getById(context, zoneId);
            String zoneName = (zone != null) ? zone.name : zoneId;

            Log.d(TAG, emoji + " " + transitionStr + " geofence: " + zoneName + " at " + time);

            // Show notification
            boolean shouldNotify = false;
            if (zone != null) {
                if (transition == Geofence.GEOFENCE_TRANSITION_ENTER && zone.notifyOnEnter) shouldNotify = true;
                if (transition == Geofence.GEOFENCE_TRANSITION_EXIT && zone.notifyOnExit) shouldNotify = true;
            } else {
                shouldNotify = true;
            }

            if (shouldNotify) {
                boolean isEnter = (transition == Geofence.GEOFENCE_TRANSITION_ENTER);
                boolean isExit  = (transition == Geofence.GEOFENCE_TRANSITION_EXIT);

                // Push notification (gated by per-type setting)
                if ((isEnter && AppSettings.isNotifGeofenceEnter(context))
                        || (isExit && AppSettings.isNotifGeofenceExit(context))) {
                    showGeofenceNotification(context, emoji, transitionStr, zoneName, time,
                            NOTIF_GEOFENCE_BASE + Math.abs(zoneId.hashCode() % 1000));
                }
                // Voice announcement
                com.carmd.triptracking.util.VoiceFeedback voice =
                        com.carmd.triptracking.util.VoiceFeedback.getInstance(context);
                if (isEnter) {
                    voice.announceGeofenceEntered(zoneName);
                } else if (isExit) {
                    voice.announceGeofenceExited(zoneName);
                }
            }
        }
    }

    private void showGeofenceNotification(Context context, String emoji,
                                           String transitionStr, String zoneName,
                                           String time, int notifId) {
        Intent launch = new Intent(context, MainActivity.class);
        launch.setFlags(Intent.FLAG_ACTIVITY_NEW_TASK | Intent.FLAG_ACTIVITY_CLEAR_TOP);
        PendingIntent pi = PendingIntent.getActivity(context, notifId, launch,
                PendingIntent.FLAG_UPDATE_CURRENT | PendingIntent.FLAG_IMMUTABLE);

        Notification n = new NotificationCompat.Builder(context, CHANNEL_TRIP_EVENTS)
                .setContentTitle(emoji + " " + transitionStr + " " + zoneName)
                .setContentText("At " + time)
                .setSmallIcon(android.R.drawable.ic_menu_mylocation)
                .setContentIntent(pi)
                .setAutoCancel(true)
                .setPriority(NotificationCompat.PRIORITY_HIGH)
                .setDefaults(NotificationCompat.DEFAULT_ALL)
                .extend(new androidx.car.app.notification.CarAppExtender.Builder()
                        .setImportance(android.app.NotificationManager.IMPORTANCE_HIGH)
                        .build())
                .build();

        NotificationManager nm = (NotificationManager) context.getSystemService(Context.NOTIFICATION_SERVICE);
        nm.notify(notifId, n);
    }
}
