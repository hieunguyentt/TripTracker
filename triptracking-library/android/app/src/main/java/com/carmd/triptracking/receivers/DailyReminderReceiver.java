package com.carmd.triptracking.receivers;

import android.app.Notification;
import android.app.NotificationManager;
import android.app.PendingIntent;
import android.content.BroadcastReceiver;
import android.content.Context;
import android.content.Intent;
import android.os.Build;
import android.util.Log;
import androidx.core.app.NotificationCompat;
import com.carmd.triptracking.ui.DailyLocationsActivity;

/**
 * Fires at 6:00 AM daily via AlarmManager.
 * Shows a push notification reminding the user to review yesterday's route.
 */
public class DailyReminderReceiver extends BroadcastReceiver {

    private static final String TAG = "DailyReminderReceiver";
    private static final String CHANNEL_TRIP_EVENTS = "trip_events";
    private static final int    NOTIF_DAILY_REMINDER = 3001;

    @Override
    public void onReceive(Context context, Intent intent) {
        Log.d(TAG, "Daily reminder fired at 6:00 AM");

        // Tapping the notification opens Daily Locations screen
        Intent launch = new Intent(context, DailyLocationsActivity.class);
        launch.setFlags(Intent.FLAG_ACTIVITY_NEW_TASK | Intent.FLAG_ACTIVITY_CLEAR_TOP);
        PendingIntent pi = PendingIntent.getActivity(context, NOTIF_DAILY_REMINDER, launch,
                PendingIntent.FLAG_UPDATE_CURRENT | PendingIntent.FLAG_IMMUTABLE);

        // Build yesterday's date string for the notification body
        java.util.Calendar cal = java.util.Calendar.getInstance();
        cal.add(java.util.Calendar.DAY_OF_YEAR, -1);
        String yesterday = new java.text.SimpleDateFormat("EEE, MMM d", java.util.Locale.US)
                .format(cal.getTime());

        Notification n = new NotificationCompat.Builder(context, CHANNEL_TRIP_EVENTS)
                .setContentTitle("📅 Check Yesterday's Route")
                .setContentText("Review your trips from " + yesterday)
                .setSmallIcon(android.R.drawable.ic_menu_mylocation)
                .setContentIntent(pi)
                .setAutoCancel(true)
                .setPriority(NotificationCompat.PRIORITY_HIGH)
                .setDefaults(NotificationCompat.DEFAULT_ALL)
                .extend(new androidx.car.app.notification.CarAppExtender.Builder()
                        .setImportance(NotificationManager.IMPORTANCE_HIGH)
                        .build())
                .build();

        NotificationManager nm = (NotificationManager) context.getSystemService(Context.NOTIFICATION_SERVICE);
        nm.notify(NOTIF_DAILY_REMINDER, n);
    }
}
