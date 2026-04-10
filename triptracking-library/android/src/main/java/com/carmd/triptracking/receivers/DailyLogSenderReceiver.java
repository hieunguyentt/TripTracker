package com.carmd.triptracking.receivers;

import android.app.Notification;
import android.app.NotificationManager;
import android.app.PendingIntent;
import android.content.BroadcastReceiver;
import android.content.Context;
import android.content.Intent;
import android.net.Uri;
import android.os.Build;
import android.util.Log;
import androidx.core.app.NotificationCompat;
import androidx.core.content.FileProvider;
import com.carmd.triptracking.util.LogcatWriter;

import java.io.File;
import java.text.SimpleDateFormat;
import java.util.Calendar;
import java.util.Locale;

/**
 * Fires at 12:00 PM daily via AlarmManager.
 * Automatically opens email composer with today's log file attached,
 * pre-addressed to hieu.nguyen@sw.innova.com.
 *
 * Also triggers cleanup of log files older than 7 days.
 */
public class DailyLogSenderReceiver extends BroadcastReceiver {

    private static final String TAG = "DailyLogSender";
    private static final String CHANNEL_TRIP_EVENTS = "trip_events";
    private static final int    NOTIF_LOG_SEND = 4001;
    private static final String RECIPIENT = "hieu.nguyen@sw.innova.com";

    @Override
    public void onReceive(Context context, Intent intent) {
        Log.d(TAG, "Daily log sender fired at 12:00 PM");

        // Clean up old logs (older than 7 days)
        LogcatWriter.cleanupOldLogs(context, 7);

        // Get today's log file
        File logFile = LogcatWriter.getTodayLogFile(context);
        if (!logFile.exists() || logFile.length() == 0) {
            Log.w(TAG, "No log file to send for today");
            return;
        }

        Uri fileUri = FileProvider.getUriForFile(context,
                context.getPackageName() + ".fileprovider", logFile);

        String today = new SimpleDateFormat("yyyy-MM-dd", Locale.US)
                .format(Calendar.getInstance().getTime());
        String deviceInfo = Build.MANUFACTURER + " " + Build.MODEL
                + " (SDK " + Build.VERSION.SDK_INT + ")";

        String subject = "TripTracker Daily Log — " + today + " — " + deviceInfo;

        String body = "Daily log report"
                + "\n\nDate: " + today
                + "\nDevice: " + deviceInfo
                + "\nAndroid: " + Build.VERSION.RELEASE
                + "\nApp: " + context.getPackageName()
                + "\nLog size: " + LogcatWriter.getLogFileSize(context)
                + "\nTotal logs: " + LogcatWriter.getLogFileCount(context) + " files"
                + " (" + LogcatWriter.getTotalLogSize(context) + ")"
                + "\n\n(Log file attached)";

        // Build the email intent
        Intent emailIntent = new Intent(Intent.ACTION_SEND);
        emailIntent.setType("message/rfc822");
        emailIntent.putExtra(Intent.EXTRA_EMAIL, new String[]{RECIPIENT});
        emailIntent.putExtra(Intent.EXTRA_SUBJECT, subject);
        emailIntent.putExtra(Intent.EXTRA_TEXT, body);
        emailIntent.putExtra(Intent.EXTRA_STREAM, fileUri);
        emailIntent.addFlags(Intent.FLAG_GRANT_READ_URI_PERMISSION);
        emailIntent.addFlags(Intent.FLAG_ACTIVITY_NEW_TASK);

        // Try to send directly (opens email app)
        try {
            Intent chooser = Intent.createChooser(emailIntent, "Send daily log…");
            chooser.addFlags(Intent.FLAG_ACTIVITY_NEW_TASK);
            context.startActivity(chooser);
            Log.d(TAG, "Email composer opened for daily log");
        } catch (Exception e) {
            Log.e(TAG, "Failed to open email composer", e);
            // Fallback: show notification so user can tap to send
            showSendNotification(context, emailIntent, today, deviceInfo);
        }
    }

    /**
     * Fallback: show a notification that opens the email composer when tapped.
     */
    private void showSendNotification(Context context, Intent emailIntent,
                                       String today, String deviceInfo) {
        PendingIntent pi = PendingIntent.getActivity(context, NOTIF_LOG_SEND,
                Intent.createChooser(emailIntent, "Send daily log…"),
                PendingIntent.FLAG_UPDATE_CURRENT | PendingIntent.FLAG_IMMUTABLE);

        Notification n = new NotificationCompat.Builder(context, CHANNEL_TRIP_EVENTS)
                .setContentTitle("📧 Daily Log Ready")
                .setContentText("Tap to send " + today + " log from " + deviceInfo)
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
        nm.notify(NOTIF_LOG_SEND, n);
    }
}
