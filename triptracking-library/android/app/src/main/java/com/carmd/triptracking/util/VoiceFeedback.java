package com.carmd.triptracking.util;

import android.content.Context;
import android.speech.tts.TextToSpeech;
import android.util.Log;
import com.carmd.triptracking.ui.AppSettings;
import java.util.Locale;

/**
 * Text-to-Speech voice feedback for trip milestones.
 * Announces: trip start, trip end, distance milestones, geofence entry/exit.
 * Works in Android Auto via car speakers.
 */
public class VoiceFeedback implements TextToSpeech.OnInitListener {

    private static final String TAG = "VoiceFeedback";
    private static VoiceFeedback instance;

    private TextToSpeech tts;
    private boolean ready = false;
    private Context appContext;

    // Distance milestone tracking
    private double lastMilestoneKm = 0;
    private static final double MILESTONE_INTERVAL_KM = 1.0; // announce every 1 km

    private VoiceFeedback(Context context) {
        appContext = context.getApplicationContext();
        tts = new TextToSpeech(appContext, this);
    }

    public static synchronized VoiceFeedback getInstance(Context context) {
        if (instance == null) {
            instance = new VoiceFeedback(context);
        }
        return instance;
    }

    @Override
    public void onInit(int status) {
        if (status == TextToSpeech.SUCCESS) {
            int result = tts.setLanguage(Locale.US);
            if (result == TextToSpeech.LANG_MISSING_DATA || result == TextToSpeech.LANG_NOT_SUPPORTED) {
                Log.w(TAG, "TTS language not supported, trying default");
                tts.setLanguage(Locale.getDefault());
            }
            tts.setSpeechRate(1.0f);
            tts.setPitch(1.0f);
            ready = true;
            Log.d(TAG, "TTS initialized");
        } else {
            Log.e(TAG, "TTS init failed: " + status);
            ready = false;
        }
    }

    public void setEnabled(boolean e) { AppSettings.setVoiceEnabled(appContext, e); }
    public boolean isEnabled() { return AppSettings.isVoiceEnabled(appContext); }

    private void speak(String text) {
        if (!ready || !AppSettings.isVoiceEnabled(appContext) || tts == null) return;
        tts.speak(text, TextToSpeech.QUEUE_ADD, null, "trip_" + System.currentTimeMillis());
        Log.d(TAG, "Speaking: " + text);
    }

    // ── Trip events ──────────────────────────────────────────────────────

    public void announceTripStarted(long tripId) {
        speak("Trip " + tripId + " started. Drive safely.");
    }

    public void announceTripEnded(long tripId, double distanceMeters, long durationSeconds) {
        String dist;
        if (distanceMeters < 1000) {
            dist = String.format(Locale.US, "%.0f meters", distanceMeters);
        } else {
            dist = String.format(Locale.US, "%.1f kilometers", distanceMeters / 1000);
        }
        long min = durationSeconds / 60;
        String dur = min < 1 ? "less than a minute"
                : min == 1 ? "1 minute"
                : min + " minutes";
        speak("Trip " + tripId + " ended. You traveled " + dist + " in " + dur + ".");
        lastMilestoneKm = 0; // reset for next trip
    }

    // ── Distance milestones ──────────────────────────────────────────────

    /**
     * Check if a distance milestone was reached. Returns the milestone km value
     * if one was just crossed (e.g. 3.0 for 3 km), or 0 if none.
     */
    public double checkDistanceMilestone(double totalDistanceMeters) {
        double km = totalDistanceMeters / 1000.0;
        double nextMilestone = lastMilestoneKm + MILESTONE_INTERVAL_KM;
        if (km >= nextMilestone) {
            lastMilestoneKm = Math.floor(km / MILESTONE_INTERVAL_KM) * MILESTONE_INTERVAL_KM;
            speak(String.format(Locale.US, "%.0f kilometers traveled.", lastMilestoneKm));
            return lastMilestoneKm;
        }
        return 0;
    }

    public void resetMilestones() {
        lastMilestoneKm = 0;
    }

    // ── Geofence events ──────────────────────────────────────────────────

    public void announceGeofenceEntered(String zoneName) {
        speak("Entering " + zoneName + ".");
    }

    public void announceGeofenceExited(String zoneName) {
        speak("Leaving " + zoneName + ".");
    }

    // ── Cleanup ──────────────────────────────────────────────────────────

    public void shutdown() {
        if (tts != null) {
            tts.stop();
            tts.shutdown();
            ready = false;
        }
        instance = null;
    }
}
