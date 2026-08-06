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

                // Grow the logcat ring buffer so high-volume bursts don't get
                // dropped before we can read them. Best-effort — ignore failures.
                try {
                    Runtime.getRuntime().exec("logcat -G 16M").waitFor();
                } catch (Exception ignored) { }

                // Clear logcat buffer first so we don't re-capture old entries
                Runtime.getRuntime().exec("logcat -c").waitFor();

                // Start logcat filtered to our PID — no -v flag truncation, no line filtering
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

    // ── Zip helpers ──────────────────────────────────────────────────────

    /** Get recent log files (last N days). */
    public static File[] getRecentLogFiles(Context context, int days) {
        File[] all = getAllLogFiles(context);  // sorted oldest first
        if (all.length <= days) return all;
        // Return last N files (newest)
        File[] recent = new File[days];
        System.arraycopy(all, all.length - days, recent, 0, days);
        return recent;
    }

    /**
     * Zip all log files (or last N days) into a single .zip file.
     * Returns the zip File, or null on failure.
     * Caller can share this via Intent or email.
     *
     * @param context  App context
     * @param days     Number of recent days to include (null = all files)
     */
    public static File getZippedLogs(Context context, Integer days) {
        File[] files = (days != null) ? getRecentLogFiles(context, days) : getAllLogFiles(context);
        if (files.length == 0) return null;

        String deviceName = Build.MANUFACTURER + "_" + Build.MODEL;
        deviceName = deviceName.replaceAll("[^a-zA-Z0-9_-]", "_");
        String dateStr = new SimpleDateFormat("yyyy-MM-dd", Locale.US).format(new Date());
        String zipName = dateStr + "_" + deviceName + "_logs.zip";
        File zipFile = new File(context.getCacheDir(), zipName);

        // Remove old zip if exists
        if (zipFile.exists()) zipFile.delete();

        try (java.util.zip.ZipOutputStream zos = new java.util.zip.ZipOutputStream(
                new FileOutputStream(zipFile))) {
            byte[] buffer = new byte[4096];
            for (File logFile : files) {
                if (!logFile.exists() || logFile.length() == 0) continue;
                java.util.zip.ZipEntry entry = new java.util.zip.ZipEntry(logFile.getName());
                zos.putNextEntry(entry);
                try (java.io.FileInputStream fis = new java.io.FileInputStream(logFile)) {
                    int len;
                    while ((len = fis.read(buffer)) > 0) {
                        zos.write(buffer, 0, len);
                    }
                }
                zos.closeEntry();
            }
            Log.i(TAG, "📦 Zipped " + files.length + " log files → " + zipFile.getName()
                    + " (" + formatBytes(zipFile.length()) + ")");
            return zipFile;
        } catch (Exception e) {
            Log.e(TAG, "Failed to zip log files: " + e.getMessage());
            if (zipFile.exists()) zipFile.delete();
            return null;
        }
    }

    /** Zip all log files. */
    public static File getZippedLogs(Context context) {
        return getZippedLogs(context, 3);
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
