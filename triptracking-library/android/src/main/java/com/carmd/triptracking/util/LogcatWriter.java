package com.carmd.triptracking.util;

import android.content.Context;
import android.os.Build;
import android.util.Log;

import java.io.BufferedReader;
import java.io.File;
import java.io.FileOutputStream;
import java.io.FilenameFilter;
import java.io.InputStreamReader;
import java.io.OutputStreamWriter;
import java.io.PrintWriter;
import java.text.SimpleDateFormat;
import java.util.Arrays;
import java.util.Calendar;
import java.util.Date;
import java.util.Locale;

/**
 * Captures all Logcat output for this process into daily log files
 * in the app's cache directory.
 *
 * File naming: triptracker_logcat_YYYY-MM-DD.txt
 *
 * Features:
 *   - Daily file rotation (new file each day)
 *   - Automatic cleanup of files older than 7 days
 *   - Session markers with timestamp, PID, device info
 *
 * Usage:
 *   LogcatWriter.start(context)              — call once from Application.onCreate()
 *   LogcatWriter.getTodayLogFile(ctx)        — get today's log file
 *   LogcatWriter.getLogFile(ctx)             — alias for getTodayLogFile (backward compat)
 *   LogcatWriter.getLogFilesDir(ctx)         — cache dir containing all log files
 *   LogcatWriter.cleanupOldLogs(ctx, days)   — delete files older than N days
 */
public final class LogcatWriter {

    private static final String TAG        = "LogcatWriter";
    private static final String PREFIX     = "triptracker_logcat_";
    private static final String SUFFIX     = ".txt";
    private static final int    RETAIN_DAYS = 7;

    private static volatile boolean sStarted = false;
    private static volatile String  sCurrentDate = "";

    private LogcatWriter() { /* utility */ }

    /**
     * Start capturing logcat in a daemon thread.  Safe to call multiple
     * times — only the first call does anything.  Automatically rotates
     * to a new file when the date changes.
     */
    public static synchronized void start(Context context) {
        if (sStarted) return;
        sStarted = true;

        final File cacheDir = context.getCacheDir();

        Thread t = new Thread(() -> {
            Process process = null;
            PrintWriter writer = null;
            try {
                // Clean up old log files on start
                cleanupOldLogs(cacheDir, RETAIN_DAYS);

                sCurrentDate = todayStr();
                File logFile = new File(cacheDir, PREFIX + sCurrentDate + SUFFIX);

                writer = openWriter(logFile);
                writeSessionHeader(writer);

                // Clear logcat buffer first so we don't re-capture old entries
                Runtime.getRuntime().exec("logcat -c").waitFor();

                // Start logcat filtered to our PID
                int pid = android.os.Process.myPid();
                process = Runtime.getRuntime().exec(
                        "logcat -v threadtime --pid=" + pid);

                BufferedReader reader = new BufferedReader(
                        new InputStreamReader(process.getInputStream()));

                String line;
                while ((line = reader.readLine()) != null) {
                    // Check for date rollover
                    String now = todayStr();
                    if (!now.equals(sCurrentDate)) {
                        // Day changed — rotate to new file
                        writer.println();
                        writer.println("═══ DAY ROLLOVER → " + now + " ═══");
                        writer.close();

                        sCurrentDate = now;
                        logFile = new File(cacheDir, PREFIX + sCurrentDate + SUFFIX);
                        writer = openWriter(logFile);
                        writeSessionHeader(writer);

                        // Clean up old files after rotation
                        cleanupOldLogs(cacheDir, RETAIN_DAYS);
                    }

                    writer.println(line);
                    writer.flush();
                }

            } catch (Exception e) {
                Log.e(TAG, "Logcat capture failed", e);
            } finally {
                if (writer != null)  writer.close();
                if (process != null) process.destroy();
                sStarted = false;
            }
        }, "LogcatWriter");
        t.setDaemon(true);
        t.start();

        Log.i(TAG, "Logcat capture started (daily rotation, " + RETAIN_DAYS + " day retention)");
    }

    // ── File access ──────────────────────────────────────────────────────

    /** Return today's log file. */
    public static File getTodayLogFile(Context context) {
        return new File(context.getCacheDir(), PREFIX + todayStr() + SUFFIX);
    }

    /** Backward-compatible alias for getTodayLogFile. */
    public static File getLogFile(Context context) {
        return getTodayLogFile(context);
    }

    /** Return the log file for a specific date string (YYYY-MM-DD). */
    public static File getLogFileForDate(Context context, String dateStr) {
        return new File(context.getCacheDir(), PREFIX + dateStr + SUFFIX);
    }

    /** Return all log files sorted by name (oldest first). */
    public static File[] getAllLogFiles(Context context) {
        File[] files = context.getCacheDir().listFiles(
                (dir, name) -> name.startsWith(PREFIX) && name.endsWith(SUFFIX));
        if (files == null) return new File[0];
        Arrays.sort(files);
        return files;
    }

    // ── Size helpers ─────────────────────────────────────────────────────

    /** Human-readable size of today's log file. */
    public static String getLogFileSize(Context context) {
        return formatSize(getTodayLogFile(context));
    }

    /** Human-readable total size of all log files. */
    public static String getTotalLogSize(Context context) {
        long total = 0;
        for (File f : getAllLogFiles(context)) {
            total += f.length();
        }
        return formatBytes(total);
    }

    /** Number of log files currently stored. */
    public static int getLogFileCount(Context context) {
        return getAllLogFiles(context).length;
    }

    // ── Cleanup ──────────────────────────────────────────────────────────

    /** Delete log files older than retainDays. */
    public static void cleanupOldLogs(Context context, int retainDays) {
        cleanupOldLogs(context.getCacheDir(), retainDays);
    }

    private static void cleanupOldLogs(File cacheDir, int retainDays) {
        Calendar cutoff = Calendar.getInstance();
        cutoff.add(Calendar.DAY_OF_YEAR, -retainDays);
        String cutoffStr = new SimpleDateFormat("yyyy-MM-dd", Locale.US).format(cutoff.getTime());

        File[] files = cacheDir.listFiles(
                (dir, name) -> name.startsWith(PREFIX) && name.endsWith(SUFFIX));
        if (files == null) return;

        for (File f : files) {
            // Extract date from filename: triptracker_logcat_2026-03-20.txt
            String name = f.getName();
            String dateStr = name.substring(PREFIX.length(), name.length() - SUFFIX.length());
            if (dateStr.compareTo(cutoffStr) < 0) {
                if (f.delete()) {
                    Log.d(TAG, "Deleted old log: " + name);
                } else {
                    Log.w(TAG, "Failed to delete old log: " + name);
                }
            }
        }
    }

    // ── Internal helpers ─────────────────────────────────────────────────

    private static String todayStr() {
        return new SimpleDateFormat("yyyy-MM-dd", Locale.US).format(new Date());
    }

    private static PrintWriter openWriter(File file) throws Exception {
        File parent = file.getParentFile();
        if (parent != null && !parent.exists()) parent.mkdirs();
        return new PrintWriter(
                new OutputStreamWriter(
                        new FileOutputStream(file, true /* append */), "UTF-8"), true);
    }

    private static void writeSessionHeader(PrintWriter writer) {
        String ts = new SimpleDateFormat("yyyy-MM-dd HH:mm:ss.SSS", Locale.US)
                .format(new Date());
        writer.println();
        writer.println("═══════════════════════════════════════════════════════════");
        writer.println("  SESSION START  " + ts);
        writer.println("  PID " + android.os.Process.myPid()
                + "  SDK " + Build.VERSION.SDK_INT
                + "  Device " + Build.MANUFACTURER + " " + Build.MODEL);
        writer.println("═══════════════════════════════════════════════════════════");
        writer.println();
    }

    private static String formatSize(File f) {
        if (!f.exists()) return "0 B";
        return formatBytes(f.length());
    }

    private static String formatBytes(long bytes) {
        if (bytes < 1024)         return bytes + " B";
        if (bytes < 1024 * 1024)  return String.format(Locale.US, "%.1f KB", bytes / 1024.0);
        return String.format(Locale.US, "%.1f MB", bytes / (1024.0 * 1024.0));
    }
}
