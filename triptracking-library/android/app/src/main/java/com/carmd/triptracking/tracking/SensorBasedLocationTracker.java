package com.carmd.triptracking.tracking;

import android.content.Context;
import android.hardware.Sensor;
import android.hardware.SensorEvent;
import android.hardware.SensorEventListener;
import android.hardware.SensorManager;
import android.location.Location;
import android.os.SystemClock;
import android.util.Log;

/**
 * Sensor-Based Location Tracker (Pedestrian Dead Reckoning)
 * PRIORITY 1: Sensors - accelerometer, gyroscope, magnetometer, barometer
 *
 * BATTERY OPTIMIZATION:
 *   STILL mode  → accelerometer at SENSOR_DELAY_NORMAL (~5 Hz)
 *                  magnetometer OFF, barometer at NORMAL
 *   MOVING mode → accelerometer at SENSOR_DELAY_FASTEST (~100-200 Hz)
 *                  magnetometer at GAME rate, barometer at NORMAL
 *
 * Transitions:
 *   still → moving : after MOVEMENT_CONFIRM_MS of sustained acceleration
 *   moving → still : after STILL_CONFIRM_MS of no significant acceleration
 */
public class SensorBasedLocationTracker implements SensorEventListener {

    private static final String TAG = "SensorLocationTracker";
    private static final long POSITION_UPDATE_INTERVAL_MS = 1000L;
    private static final float STEP_THRESHOLD = 3.5f;
    private static final float ALPHA_LOW_PASS = 0.8f;
    private static final double EARTH_RADIUS_METERS = 6371000.0;

    // Raised from 0.8f → real vibration/noise on a table is typically 0.2-0.5 m/s²
    // 2.0f requires a deliberate shake/step to trigger — eliminates false "moving" on still surface
    private static final float MOVEMENT_THRESHOLD = 2.0f;

    // Device must stay above threshold for this long before we declare "moving"
    private static final long MOVEMENT_CONFIRM_MS = 800L;

    // Device must stay below threshold for this long before switching to low-power still mode
    private static final long STILL_CONFIRM_MS = 2000L;

    // ── Sensor rate modes ─────────────────────────────────────────────────
    private enum SensorMode { STILL, MOVING }
    private SensorMode currentSensorMode = SensorMode.STILL;

    public interface LocationUpdateListener {
        void onLocationUpdate(Location location, boolean isEstimated);
        void onStepDetected(int stepCount, double distance);
        void onHeadingUpdate(float heading, float confidence);
        void onAltitudeUpdate(float altitude, Integer floor);
        void onMovementDetected(boolean isMoving, float speed);
    }

    public static class TrackingStats {
        private final int stepCount;
        private final double totalDistance;
        private final float currentSpeed;
        private final float currentHeading;
        private final float currentAltitude;
        private final Integer currentFloor;
        private final boolean isMoving;
        private final Location location;
        private final float currentAcceleration;

        public TrackingStats(int stepCount, double totalDistance, float currentSpeed,
                           float currentHeading, float currentAltitude, Integer currentFloor,
                           boolean isMoving, Location location, float currentAcceleration) {
            this.stepCount = stepCount;
            this.totalDistance = totalDistance;
            this.currentSpeed = currentSpeed;
            this.currentHeading = currentHeading;
            this.currentAltitude = currentAltitude;
            this.currentFloor = currentFloor;
            this.isMoving = isMoving;
            this.location = location;
            this.currentAcceleration = currentAcceleration;
        }

        public int getStepCount() { return stepCount; }
        public double getTotalDistance() { return totalDistance; }
        public float getCurrentSpeed() { return currentSpeed; }
        public float getCurrentHeading() { return currentHeading; }
        public float getCurrentAltitude() { return currentAltitude; }
        public Integer getCurrentFloor() { return currentFloor; }
        public boolean isMoving() { return isMoving; }
        public Location getLocation() { return location; }
        public float getCurrentAcceleration() { return currentAcceleration; }
    }

    private final Context context;
    private final LocationUpdateListener listener;
    private final SensorManager sensorManager;

    private Sensor accelerometer;
    private Sensor magnetometer;
    private Sensor barometer;

    private Location currentLocation;
    private float currentHeading = 0f;
    private float currentSpeed = 0f;
    private float currentAltitude = 0f;
    private float currentAcceleration = 0f;
    private boolean isTracking = false;

    private int stepCount = 0;
    private long lastStepTime = 0;
    private long lastDebugLog = 0;

    private final float[] gravity = new float[3];
    private final float[] geomagnetic = new float[3];
    private final float[] rotationMatrix = new float[9];
    private final float[] orientation = new float[3];

    private boolean isMoving = false;
    private long lastMovementTime = 0;
    private long movementStartTime = 0;
    private long lastPositionUpdate = 0;

    public SensorBasedLocationTracker(Context context, LocationUpdateListener listener) {
        this.context = context;
        this.listener = listener;
        this.sensorManager = (SensorManager) context.getSystemService(Context.SENSOR_SERVICE);

        accelerometer = sensorManager.getDefaultSensor(Sensor.TYPE_ACCELEROMETER);
        magnetometer = sensorManager.getDefaultSensor(Sensor.TYPE_MAGNETIC_FIELD);
        barometer = sensorManager.getDefaultSensor(Sensor.TYPE_PRESSURE);
    }

    public boolean isTracking() { return isTracking; }

    public void startTracking(Location initialLocation) {
        if (isTracking) return;

        currentLocation = new Location(initialLocation);
        currentAltitude = (float) initialLocation.getAltitude();
        isTracking = true;
        stepCount = 0;
        lastPositionUpdate = SystemClock.elapsedRealtime();
        isMoving          = false;
        currentSpeed      = 0f;
        movementStartTime = 0;
        lastMovementTime  = 0;
        lastStepTime      = 0;

        // Start in low-power STILL mode
        switchToStillMode();
        Log.d(TAG, "✅ Sensor tracking started (STILL mode — low power)");
    }

    public void stopTracking() {
        if (!isTracking) return;

        isTracking        = false;
        isMoving          = false;
        currentSpeed      = 0f;
        movementStartTime = 0;
        lastMovementTime  = 0;
        currentSensorMode = SensorMode.STILL;
        sensorManager.unregisterListener(this);
        Log.d(TAG, "✅ Sensor tracking stopped - Steps: " + stepCount);
    }

    // =========================================================================
    // Sensor rate management — battery optimization
    // =========================================================================

    /**
     * STILL mode: accelerometer at NORMAL rate (~5 Hz), magnetometer OFF.
     * Only needs to detect when movement begins — no heading or step tracking.
     * Battery: ~1-2% / hour
     */
    private void switchToStillMode() {
        if (currentSensorMode == SensorMode.STILL) return;
        currentSensorMode = SensorMode.STILL;

        sensorManager.unregisterListener(this);

        if (accelerometer != null) {
            sensorManager.registerListener(this, accelerometer,
                    SensorManager.SENSOR_DELAY_NORMAL);
        }
        // Magnetometer OFF in still mode — no heading needed
        // Barometer stays at NORMAL (already low power)
        if (barometer != null) {
            sensorManager.registerListener(this, barometer,
                    SensorManager.SENSOR_DELAY_NORMAL);
        }
        Log.d(TAG, "🔋 Switched to STILL mode (accel=NORMAL, mag=OFF) — saving battery");
    }

    /**
     * MOVING mode: accelerometer at FASTEST rate (~100-200 Hz), magnetometer at GAME.
     * Needs precise step detection, heading for dead-reckoning.
     * Battery: ~8-10% / hour
     */
    private void switchToMovingMode() {
        if (currentSensorMode == SensorMode.MOVING) return;
        currentSensorMode = SensorMode.MOVING;

        sensorManager.unregisterListener(this);

        if (accelerometer != null) {
            sensorManager.registerListener(this, accelerometer,
                    SensorManager.SENSOR_DELAY_FASTEST);
        }
        if (magnetometer != null) {
            sensorManager.registerListener(this, magnetometer,
                    SensorManager.SENSOR_DELAY_GAME);
        }
        if (barometer != null) {
            sensorManager.registerListener(this, barometer,
                    SensorManager.SENSOR_DELAY_NORMAL);
        }
        Log.d(TAG, "🏃 Switched to MOVING mode (accel=FASTEST, mag=GAME) — full tracking");
    }

    /**
     * Initial registration: starts in STILL mode (low power).
     * Called from startTracking() only.
     */
    private void registerSensors() {
        switchToStillMode();
    }

    // =========================================================================
    // Sensor callbacks
    // =========================================================================

    @Override
    public void onSensorChanged(SensorEvent event) {
        if (event.sensor.getType() == Sensor.TYPE_ACCELEROMETER) {
            processAccelerometer(event);
        }

        if (!isTracking) return;

        switch (event.sensor.getType()) {
            case Sensor.TYPE_MAGNETIC_FIELD:
                processMagnetometer(event);
                break;
            case Sensor.TYPE_PRESSURE:
                processBarometer(event);
                break;
        }

        long now = SystemClock.elapsedRealtime();
        if (now - lastPositionUpdate >= POSITION_UPDATE_INTERVAL_MS) {
            updatePosition();
            lastPositionUpdate = now;
        }
    }

    @Override
    public void onAccuracyChanged(Sensor sensor, int accuracy) {}

    private void processAccelerometer(SensorEvent event) {
        // Low-pass filter to remove gravity
        gravity[0] = ALPHA_LOW_PASS * gravity[0] + (1 - ALPHA_LOW_PASS) * event.values[0];
        gravity[1] = ALPHA_LOW_PASS * gravity[1] + (1 - ALPHA_LOW_PASS) * event.values[1];
        gravity[2] = ALPHA_LOW_PASS * gravity[2] + (1 - ALPHA_LOW_PASS) * event.values[2];

        // Linear acceleration without gravity
        float linearX = event.values[0] - gravity[0];
        float linearY = event.values[1] - gravity[1];
        float linearZ = event.values[2] - gravity[2];

        // Calculate magnitude
        float accelerationMagnitude = (float) Math.sqrt(
                linearX * linearX + linearY * linearY + linearZ * linearZ);

        currentAcceleration = accelerationMagnitude;

        long now = SystemClock.elapsedRealtime();

        // DEBUG: Log acceleration values every 5 seconds in STILL mode, 2s in MOVING
        long debugInterval = (currentSensorMode == SensorMode.STILL) ? 5000 : 2000;
        if (now - lastDebugLog > debugInterval) {
            Log.d(TAG, "📊 Accel: " + String.format("%.2f", accelerationMagnitude) +
                    " m/s² | Mode: " + currentSensorMode +
                    " | Moving: " + isMoving);
            lastDebugLog = now;
        }

        // Step detection (only meaningful in MOVING mode with high sample rate)
        if (accelerationMagnitude > STEP_THRESHOLD) {
            if (now - lastStepTime > 200) {
                stepCount++;
                lastStepTime = now;
                listener.onStepDetected(stepCount, 0);
            }
        }

        // ── Movement detection with sensor rate switching ─────────────────
        boolean wasMoving = isMoving;

        if (accelerationMagnitude > MOVEMENT_THRESHOLD) {
            if (movementStartTime == 0) {
                movementStartTime = now;
            }
            // Confirm movement after sustained acceleration
            if (!isMoving && (now - movementStartTime) >= MOVEMENT_CONFIRM_MS) {
                isMoving = true;
                Log.d(TAG, "🚶 Movement confirmed - Accel: " +
                        String.format("%.2f", accelerationMagnitude) + " m/s²");
                listener.onMovementDetected(true, currentSpeed);

                // ── Switch to high-rate MOVING mode ───────────────────────
                switchToMovingMode();
            }
            lastMovementTime = now;
            currentSpeed = Math.min(accelerationMagnitude * 0.15f, 1.5f);
        } else {
            movementStartTime = 0;
            // Only stop "moving" after STILL_CONFIRM_MS of no activity
            if (isMoving && (now - lastMovementTime) > STILL_CONFIRM_MS) {
                isMoving = false;
                currentSpeed = 0f;
                Log.d(TAG, "⏸️ Movement stopped — switching to low-power mode");
                listener.onMovementDetected(false, 0f);

                // ── Switch to low-rate STILL mode ─────────────────────────
                switchToStillMode();
            }
        }
    }

    private void processMagnetometer(SensorEvent event) {
        System.arraycopy(event.values, 0, geomagnetic, 0, 3);

        if (SensorManager.getRotationMatrix(rotationMatrix, null, gravity, geomagnetic)) {
            SensorManager.getOrientation(rotationMatrix, orientation);
            
            float heading = (float) Math.toDegrees(orientation[0]);
            if (heading < 0) heading += 360f;
            
            currentHeading = heading;
            listener.onHeadingUpdate(currentHeading, 1.0f);
        }
    }

    private void processBarometer(SensorEvent event) {
        float pressure = event.values[0];
        float altitude = (float) (44330 * (1 - Math.pow(pressure / 1013.25, 0.1903)));
        currentAltitude = altitude;
        
        Integer floor = Math.round(altitude / 3.5f);
        listener.onAltitudeUpdate(currentAltitude, floor);
    }

    private void updatePosition() {
        if (currentLocation == null) return;

        // Device is still — do NOT fire onLocationUpdate
        if (!isMoving || currentSpeed < 0.3f) {
            return;
        }

        double timeDelta = POSITION_UPDATE_INTERVAL_MS / 1000.0;
        double distanceMoved = currentSpeed * timeDelta;

        if (distanceMoved < 0.5) return;

        Location newLocation = calculateNewLocation(
                currentLocation.getLatitude(),
                currentLocation.getLongitude(),
                currentHeading,
                distanceMoved
        );

        newLocation.setSpeed(currentSpeed);
        newLocation.setBearing(currentHeading);
        newLocation.setAltitude(currentAltitude);
        newLocation.setTime(System.currentTimeMillis());
        newLocation.setAccuracy(25f);

        currentLocation = newLocation;
        listener.onLocationUpdate(newLocation, true);
    }

    private Location calculateNewLocation(double lat, double lon, 
                                         double bearing, double distance) {
        double lat1 = Math.toRadians(lat);
        double lon1 = Math.toRadians(lon);
        double bearingRad = Math.toRadians(bearing);

        double angularDistance = distance / EARTH_RADIUS_METERS;

        double lat2 = Math.asin(
                Math.sin(lat1) * Math.cos(angularDistance) +
                Math.cos(lat1) * Math.sin(angularDistance) * Math.cos(bearingRad)
        );

        double lon2 = lon1 + Math.atan2(
                Math.sin(bearingRad) * Math.sin(angularDistance) * Math.cos(lat1),
                Math.cos(angularDistance) - Math.sin(lat1) * Math.sin(lat2)
        );

        Location newLocation = new Location("sensor");
        newLocation.setLatitude(Math.toDegrees(lat2));
        newLocation.setLongitude(Math.toDegrees(lon2));
        return newLocation;
    }

    public void updateFromGPS(Location gpsLocation) {
        if (!isTracking || gpsLocation.getAccuracy() >= 50f) return;
        
        Log.d(TAG, "📡 GPS calibration: Accuracy " + 
                String.format("%.1f", gpsLocation.getAccuracy()) + "m");
        
        currentLocation = new Location(gpsLocation);
        if (gpsLocation.hasAltitude()) {
            currentAltitude = (float) gpsLocation.getAltitude();
        }
    }

    public TrackingStats getStats() {
        return new TrackingStats(stepCount, 0.0, currentSpeed,
                currentHeading, currentAltitude, null, isMoving, currentLocation, currentAcceleration);
    }
}
