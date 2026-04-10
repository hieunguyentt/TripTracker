package com.carmd.triptracking.database;

import android.content.ContentValues;
import android.content.Context;
import android.database.Cursor;
import android.database.sqlite.SQLiteDatabase;
import android.database.sqlite.SQLiteOpenHelper;
import android.location.Location;
import android.util.Log;

import java.text.SimpleDateFormat;
import java.util.ArrayList;
import java.util.Date;
import java.util.List;
import java.util.Locale;

public class LocationDatabase extends SQLiteOpenHelper {
    private static final String TAG = "LocationDatabase";
    
    private static final String DATABASE_NAME = "trip_tracker.db";
    private static final int DATABASE_VERSION = 3; // v3: location_cache is now permanent (no auto-delete)
    
    // Tables
    private static final String TABLE_TRIPS = "trips";
    private static final String TABLE_LOCATIONS = "locations";
    private static final String TABLE_LOCATION_CACHE = "location_cache"; // permanent all-time store
    
    // Trips table columns
    private static final String TRIP_ID = "trip_id";
    private static final String TRIP_START_TIME = "start_time";
    private static final String TRIP_END_TIME = "end_time";
    private static final String TRIP_DISTANCE = "distance";
    private static final String TRIP_DURATION = "duration";
    private static final String TRIP_STEPS = "steps";
    private static final String TRIP_STATUS = "status"; // active, completed
    
    // Locations table columns
    private static final String LOC_ID = "location_id";
    private static final String LOC_TRIP_ID = "trip_id";
    private static final String LOC_LATITUDE = "latitude";
    private static final String LOC_LONGITUDE = "longitude";
    private static final String LOC_ALTITUDE = "altitude";
    private static final String LOC_ACCURACY = "accuracy";
    private static final String LOC_SPEED = "speed";
    private static final String LOC_BEARING = "bearing";
    private static final String LOC_TIMESTAMP = "timestamp";
    private static final String LOC_SOURCE = "source"; // sensors, gps, wifi, cell
    private static final String LOC_PROVIDER = "provider";
    
    // Location cache table columns (same as locations but no trip_id)
    private static final String CACHE_ID = "cache_id";
    private static final String CACHE_LATITUDE = "latitude";
    private static final String CACHE_LONGITUDE = "longitude";
    private static final String CACHE_ALTITUDE = "altitude";
    private static final String CACHE_ACCURACY = "accuracy";
    private static final String CACHE_SPEED = "speed";
    private static final String CACHE_BEARING = "bearing";
    private static final String CACHE_TIMESTAMP = "timestamp";
    private static final String CACHE_SOURCE = "source";
    private static final String CACHE_PROVIDER = "provider";
    
    private static LocationDatabase instance;
    
    public static synchronized LocationDatabase getInstance(Context context) {
        if (instance == null) {
            instance = new LocationDatabase(context.getApplicationContext());
        }
        return instance;
    }
    
    private LocationDatabase(Context context) {
        super(context, DATABASE_NAME, null, DATABASE_VERSION);
    }
    
    @Override
    public void onCreate(SQLiteDatabase db) {
        // Create trips table
        String createTripsTable = "CREATE TABLE " + TABLE_TRIPS + " (" +
                TRIP_ID + " INTEGER PRIMARY KEY AUTOINCREMENT, " +
                TRIP_START_TIME + " INTEGER NOT NULL, " +
                TRIP_END_TIME + " INTEGER, " +
                TRIP_DISTANCE + " REAL DEFAULT 0, " +
                TRIP_DURATION + " INTEGER DEFAULT 0, " +
                TRIP_STEPS + " INTEGER DEFAULT 0, " +
                TRIP_STATUS + " TEXT DEFAULT 'active'" +
                ")";
        
        // Create locations table (for tracked trips)
        String createLocationsTable = "CREATE TABLE " + TABLE_LOCATIONS + " (" +
                LOC_ID + " INTEGER PRIMARY KEY AUTOINCREMENT, " +
                LOC_TRIP_ID + " INTEGER NOT NULL, " +
                LOC_LATITUDE + " REAL NOT NULL, " +
                LOC_LONGITUDE + " REAL NOT NULL, " +
                LOC_ALTITUDE + " REAL, " +
                LOC_ACCURACY + " REAL, " +
                LOC_SPEED + " REAL, " +
                LOC_BEARING + " REAL, " +
                LOC_TIMESTAMP + " INTEGER NOT NULL, " +
                LOC_SOURCE + " TEXT, " +
                LOC_PROVIDER + " TEXT, " +
                "FOREIGN KEY(" + LOC_TRIP_ID + ") REFERENCES " + TABLE_TRIPS + "(" + TRIP_ID + ")" +
                ")";
        
        // Create location cache table (for continuous tracking without trip)
        String createCacheTable = "CREATE TABLE " + TABLE_LOCATION_CACHE + " (" +
                CACHE_ID + " INTEGER PRIMARY KEY AUTOINCREMENT, " +
                CACHE_LATITUDE + " REAL NOT NULL, " +
                CACHE_LONGITUDE + " REAL NOT NULL, " +
                CACHE_ALTITUDE + " REAL, " +
                CACHE_ACCURACY + " REAL, " +
                CACHE_SPEED + " REAL, " +
                CACHE_BEARING + " REAL, " +
                CACHE_TIMESTAMP + " INTEGER NOT NULL, " +
                CACHE_SOURCE + " TEXT, " +
                CACHE_PROVIDER + " TEXT" +
                ")";
        
        db.execSQL(createTripsTable);
        db.execSQL(createLocationsTable);
        db.execSQL(createCacheTable);
        
        Log.d(TAG, "✅ Database created successfully with cache table");
    }
    
    @Override
    public void onUpgrade(SQLiteDatabase db, int oldVersion, int newVersion) {
        if (oldVersion < 2) {
            // v1 → v2: add location_cache table
            String createCacheTable = "CREATE TABLE IF NOT EXISTS " + TABLE_LOCATION_CACHE + " (" +
                    CACHE_ID + " INTEGER PRIMARY KEY AUTOINCREMENT, " +
                    CACHE_LATITUDE + " REAL NOT NULL, " +
                    CACHE_LONGITUDE + " REAL NOT NULL, " +
                    CACHE_ALTITUDE + " REAL, " +
                    CACHE_ACCURACY + " REAL, " +
                    CACHE_SPEED + " REAL, " +
                    CACHE_BEARING + " REAL, " +
                    CACHE_TIMESTAMP + " INTEGER NOT NULL, " +
                    CACHE_SOURCE + " TEXT, " +
                    CACHE_PROVIDER + " TEXT" +
                    ")";
            db.execSQL(createCacheTable);
            Log.d(TAG, "✅ Database upgraded to version 2: location_cache table added");
        }
        if (oldVersion < 3) {
            // v2 → v3: schema unchanged, version bump only
            Log.d(TAG, "✅ Database upgraded to version 3: no schema changes");
        }
    }

    @Override
    public void onDowngrade(SQLiteDatabase db, int oldVersion, int newVersion) {
        // Allow downgrade gracefully — keep existing data, do nothing
        Log.w(TAG, "⚠️ Database downgrade from " + oldVersion + " to " + newVersion + " — keeping existing data");
    }
    
    /**
     * Start a new trip
     * @return trip ID
     */
    public long startTrip() {
        SQLiteDatabase db = this.getWritableDatabase();
        ContentValues values = new ContentValues();
        values.put(TRIP_START_TIME, System.currentTimeMillis());
        values.put(TRIP_STATUS, "active");
        
        long tripId = db.insert(TABLE_TRIPS, null, values);
        Log.d(TAG, "🎯 Started new trip: ID=" + tripId);
        return tripId;
    }
    
    /**
     * End the current trip
     */
    public void endTrip(long tripId, double distance, long duration, int steps) {
        SQLiteDatabase db = this.getWritableDatabase();
        ContentValues values = new ContentValues();
        values.put(TRIP_END_TIME, System.currentTimeMillis());
        values.put(TRIP_DISTANCE, distance);
        values.put(TRIP_DURATION, duration);
        values.put(TRIP_STEPS, steps);
        values.put(TRIP_STATUS, "completed");
        
        int rows = db.update(TABLE_TRIPS, values, TRIP_ID + "=?", 
                new String[]{String.valueOf(tripId)});
        
        Log.d(TAG, "🏁 Ended trip: ID=" + tripId + 
                ", Distance=" + String.format("%.1f", distance) + "m, " +
                "Duration=" + duration + "s, Steps=" + steps);
    }

    /**
     * Get the ID of the most recently completed trip.
     * Returns -1 if no completed trips exist.
     */
    public long getLastTripId() {
        SQLiteDatabase db = this.getReadableDatabase();
        Cursor cursor = db.rawQuery(
                "SELECT " + TRIP_ID + " FROM " + TABLE_TRIPS +
                " WHERE " + TRIP_STATUS + "='completed'" +
                " ORDER BY " + TRIP_END_TIME + " DESC LIMIT 1", null);
        long tripId = -1;
        if (cursor.moveToFirst()) {
            tripId = cursor.getLong(0);
        }
        cursor.close();
        return tripId;
    }
    
    /**
     * Save a location point
     */
    public long saveLocation(long tripId, Location location, String source) {
        SQLiteDatabase db = this.getWritableDatabase();
        ContentValues values = new ContentValues();
        
        values.put(LOC_TRIP_ID, tripId);
        values.put(LOC_LATITUDE, location.getLatitude());
        values.put(LOC_LONGITUDE, location.getLongitude());
        values.put(LOC_ALTITUDE, location.hasAltitude() ? location.getAltitude() : null);
        values.put(LOC_ACCURACY, location.hasAccuracy() ? location.getAccuracy() : null);
        values.put(LOC_SPEED, location.hasSpeed() ? location.getSpeed() : null);
        values.put(LOC_BEARING, location.hasBearing() ? location.getBearing() : null);
        values.put(LOC_TIMESTAMP, location.getTime());
        values.put(LOC_SOURCE, source);
        values.put(LOC_PROVIDER, location.getProvider());
        
        long locationId = db.insert(TABLE_LOCATIONS, null, values);
        
        if (locationId % 10 == 0) { // Log every 10th location
            Log.d(TAG, "💾 Saved location #" + locationId + " for trip #" + tripId + 
                    " - Source: " + source);
        }
        
        return locationId;
    }
    
    /**
     * Get all locations for a trip
     */
    public List<LocationPoint> getLocationsForTrip(long tripId) {
        List<LocationPoint> locations = new ArrayList<>();
        SQLiteDatabase db = this.getReadableDatabase();
        
        Cursor cursor = db.query(TABLE_LOCATIONS, null, 
                LOC_TRIP_ID + "=?", new String[]{String.valueOf(tripId)},
                null, null, LOC_TIMESTAMP + " ASC");
        
        if (cursor.moveToFirst()) {
            do {
                LocationPoint point = new LocationPoint();
                point.id = cursor.getLong(cursor.getColumnIndexOrThrow(LOC_ID));
                point.tripId = cursor.getLong(cursor.getColumnIndexOrThrow(LOC_TRIP_ID));
                point.latitude = cursor.getDouble(cursor.getColumnIndexOrThrow(LOC_LATITUDE));
                point.longitude = cursor.getDouble(cursor.getColumnIndexOrThrow(LOC_LONGITUDE));
                point.altitude = cursor.getDouble(cursor.getColumnIndexOrThrow(LOC_ALTITUDE));
                point.accuracy = cursor.getFloat(cursor.getColumnIndexOrThrow(LOC_ACCURACY));
                point.speed = cursor.getFloat(cursor.getColumnIndexOrThrow(LOC_SPEED));
                point.bearing = cursor.getFloat(cursor.getColumnIndexOrThrow(LOC_BEARING));
                point.timestamp = cursor.getLong(cursor.getColumnIndexOrThrow(LOC_TIMESTAMP));
                point.source = cursor.getString(cursor.getColumnIndexOrThrow(LOC_SOURCE));
                point.provider = cursor.getString(cursor.getColumnIndexOrThrow(LOC_PROVIDER));
                
                locations.add(point);
            } while (cursor.moveToNext());
        }
        cursor.close();
        
        Log.d(TAG, "📖 Retrieved " + locations.size() + " locations for trip #" + tripId);
        return locations;
    }
    
    /**
     * Get all trips
     */
    public List<Trip> getAllTrips() {
        List<Trip> trips = new ArrayList<>();
        SQLiteDatabase db = this.getReadableDatabase();
        
        Cursor cursor = db.query(TABLE_TRIPS, null, null, null, 
                null, null, TRIP_START_TIME + " DESC");
        
        if (cursor.moveToFirst()) {
            do {
                Trip trip = new Trip();
                trip.id = cursor.getLong(cursor.getColumnIndexOrThrow(TRIP_ID));
                trip.startTime = cursor.getLong(cursor.getColumnIndexOrThrow(TRIP_START_TIME));
                trip.endTime = cursor.getLong(cursor.getColumnIndexOrThrow(TRIP_END_TIME));
                trip.distance = cursor.getDouble(cursor.getColumnIndexOrThrow(TRIP_DISTANCE));
                trip.duration = cursor.getLong(cursor.getColumnIndexOrThrow(TRIP_DURATION));
                trip.steps = cursor.getInt(cursor.getColumnIndexOrThrow(TRIP_STEPS));
                trip.status = cursor.getString(cursor.getColumnIndexOrThrow(TRIP_STATUS));
                
                trips.add(trip);
            } while (cursor.moveToNext());
        }
        cursor.close();
        
        Log.d(TAG, "📖 Retrieved " + trips.size() + " trips");
        return trips;
    }
    
    /**
     * Get active trip ID (if any)
     */
    public long getActiveTripId() {
        SQLiteDatabase db = this.getReadableDatabase();
        Cursor cursor = db.query(TABLE_TRIPS, new String[]{TRIP_ID},
                TRIP_STATUS + "=?", new String[]{"active"},
                null, null, TRIP_START_TIME + " DESC", "1");
        
        long tripId = -1;
        if (cursor.moveToFirst()) {
            tripId = cursor.getLong(0);
        }
        cursor.close();
        return tripId;
    }
    
    /**
     * Get location count for a trip
     */
    public int getLocationCount(long tripId) {
        SQLiteDatabase db = this.getReadableDatabase();
        Cursor cursor = db.rawQuery("SELECT COUNT(*) FROM " + TABLE_LOCATIONS + 
                " WHERE " + LOC_TRIP_ID + "=?", new String[]{String.valueOf(tripId)});
        
        int count = 0;
        if (cursor.moveToFirst()) {
            count = cursor.getInt(0);
        }
        cursor.close();
        return count;
    }
    
    /**
     * Calculate actual distance from stored location points
     * This recalculates distance from the location history, not from stored trip.distance
     */
    public double calculateTripDistance(long tripId) {
        List<LocationPoint> locations = getLocationsForTrip(tripId);
        
        if (locations.size() < 2) {
            return 0.0;
        }
        
        double totalDistance = 0.0;
        LocationPoint previousPoint = null;
        
        for (LocationPoint point : locations) {
            if (previousPoint != null) {
                // Create Location objects for distance calculation
                Location prevLoc = new Location("previous");
                prevLoc.setLatitude(previousPoint.latitude);
                prevLoc.setLongitude(previousPoint.longitude);
                
                Location currLoc = new Location("current");
                currLoc.setLatitude(point.latitude);
                currLoc.setLongitude(point.longitude);
                
                // Calculate distance between consecutive points
                float distance = prevLoc.distanceTo(currLoc);
                
                // Filter outliers: only add if distance is reasonable
                // Skip if distance > 100m between consecutive points (likely GPS jump)
                if (distance > 0 && distance < 100.0f) {
                    totalDistance += distance;
                }
            }
            previousPoint = point;
        }
        
        Log.d(TAG, "📏 Calculated distance for trip #" + tripId + ": " + 
                String.format("%.1f", totalDistance) + "m from " + locations.size() + " points");
        
        return totalDistance;
    }
    
    /**
     * Update trip distance with recalculated value from location points
     */
    public void recalculateTripDistance(long tripId) {
        double calculatedDistance = calculateTripDistance(tripId);
        
        SQLiteDatabase db = this.getWritableDatabase();
        ContentValues values = new ContentValues();
        values.put(TRIP_DISTANCE, calculatedDistance);
        
        int rows = db.update(TABLE_TRIPS, values, TRIP_ID + "=?", 
                new String[]{String.valueOf(tripId)});
        
        Log.d(TAG, "✅ Updated trip #" + tripId + " distance to " + 
                String.format("%.1f", calculatedDistance) + "m");
    }
    
    /**
     * Recalculate distance for all trips
     */
    public void recalculateAllTripDistances() {
        List<Trip> trips = getAllTrips();
        int updatedCount = 0;
        
        for (Trip trip : trips) {
            double oldDistance = trip.distance;
            double newDistance = calculateTripDistance(trip.id);
            
            if (Math.abs(oldDistance - newDistance) > 1.0) { // Only update if difference > 1m
                recalculateTripDistance(trip.id);
                updatedCount++;
                
                Log.d(TAG, "🔄 Trip #" + trip.id + 
                        " | Old: " + String.format("%.1f", oldDistance) + "m" +
                        " → New: " + String.format("%.1f", newDistance) + "m" +
                        " | Diff: " + String.format("%.1f", Math.abs(oldDistance - newDistance)) + "m");
            }
        }
        
        Log.d(TAG, "✅ Recalculated " + updatedCount + " of " + trips.size() + " trips");
    }
    
    /**
     * Delete a trip and all its locations
     */
    public void deleteTrip(long tripId) {
        SQLiteDatabase db = this.getWritableDatabase();
        
        // Delete locations first
        int locationCount = db.delete(TABLE_LOCATIONS, LOC_TRIP_ID + "=?", 
                new String[]{String.valueOf(tripId)});
        
        // Delete trip
        int tripCount = db.delete(TABLE_TRIPS, TRIP_ID + "=?", 
                new String[]{String.valueOf(tripId)});
        
        Log.d(TAG, "🗑️ Deleted trip #" + tripId + " (" + locationCount + " locations)");
    }
    
    /**
     * Get database statistics
     */
    public DatabaseStats getStats() {
        SQLiteDatabase db = this.getReadableDatabase();
        DatabaseStats stats = new DatabaseStats();
        
        // Total trips
        Cursor tripCursor = db.rawQuery("SELECT COUNT(*) FROM " + TABLE_TRIPS, null);
        if (tripCursor.moveToFirst()) {
            stats.totalTrips = tripCursor.getInt(0);
        }
        tripCursor.close();
        
        // Total locations
        Cursor locCursor = db.rawQuery("SELECT COUNT(*) FROM " + TABLE_LOCATIONS, null);
        if (locCursor.moveToFirst()) {
            stats.totalLocations = locCursor.getInt(0);
        }
        locCursor.close();
        
        // Total distance
        Cursor distCursor = db.rawQuery("SELECT SUM(" + TRIP_DISTANCE + ") FROM " + TABLE_TRIPS, null);
        if (distCursor.moveToFirst()) {
            stats.totalDistance = distCursor.getDouble(0);
        }
        distCursor.close();
        
        // Total steps
        Cursor stepsCursor = db.rawQuery("SELECT SUM(" + TRIP_STEPS + ") FROM " + TABLE_TRIPS, null);
        if (stepsCursor.moveToFirst()) {
            stats.totalSteps = stepsCursor.getInt(0);
        }
        stepsCursor.close();
        
        return stats;
    }
    
    // Data classes
    public static class LocationPoint {
        public long id;
        public long tripId;
        public double latitude;
        public double longitude;
        public double altitude;
        public float accuracy;
        public float speed;
        public float bearing;
        public long timestamp;
        public String source;
        public String provider;
        
        public String getFormattedTime() {
            SimpleDateFormat sdf = new SimpleDateFormat("HH:mm:ss", Locale.US);
            return sdf.format(new Date(timestamp));
        }
    }
    
    public static class Trip {
        public long id;
        public long startTime;
        public long endTime;
        public double distance;
        public long duration;
        public int steps;
        public String status;
        
        public String getFormattedStartTime() {
            SimpleDateFormat sdf = new SimpleDateFormat("yyyy-MM-dd HH:mm:ss", Locale.US);
            return sdf.format(new Date(startTime));
        }
        
        public String getFormattedDuration() {
            long minutes = duration / 60;
            long seconds = duration % 60;
            return String.format(Locale.US, "%02d:%02d", minutes, seconds);
        }
    }
    
    public static class DatabaseStats {
        public int totalTrips;
        public int totalLocations;
        public double totalDistance;
        public int totalSteps;
    }
    
    // ========== LOCATION CACHE METHODS (Continuous tracking) ==========
    
    /**
     * Save location to cache (always running, no trip required)
     */
    public void saveCachedLocation(Location location, String source) {
        SQLiteDatabase db = this.getWritableDatabase();
        
        ContentValues values = new ContentValues();
        values.put(CACHE_LATITUDE, location.getLatitude());
        values.put(CACHE_LONGITUDE, location.getLongitude());
        values.put(CACHE_ALTITUDE, location.hasAltitude() ? location.getAltitude() : 0.0);
        values.put(CACHE_ACCURACY, location.hasAccuracy() ? location.getAccuracy() : 0.0f);
        values.put(CACHE_SPEED, location.hasSpeed() ? location.getSpeed() : 0.0f);
        values.put(CACHE_BEARING, location.hasBearing() ? location.getBearing() : 0.0f);
        values.put(CACHE_TIMESTAMP, location.getTime());
        values.put(CACHE_SOURCE, source);
        values.put(CACHE_PROVIDER, location.getProvider());
        
        db.insert(TABLE_LOCATION_CACHE, null, values);
        // location_cache is permanent — never auto-deleted. All locations
        // across foreground, background, and kill+resume are kept forever.
    }
    
    /**
     * Get cached location count
     */
    public int getCachedLocationCount() {
        SQLiteDatabase db = this.getReadableDatabase();
        Cursor cursor = db.rawQuery("SELECT COUNT(*) FROM " + TABLE_LOCATION_CACHE, null);
        int count = 0;
        if (cursor.moveToFirst()) {
            count = cursor.getInt(0);
        }
        cursor.close();
        return count;
    }
    
    /**
     * Get all cached locations from last N hours
     */
    public List<LocationPoint> getCachedLocations(int hours) {
        List<LocationPoint> locations = new ArrayList<>();
        SQLiteDatabase db = this.getReadableDatabase();
        
        long timeLimit = System.currentTimeMillis() - (hours * 60 * 60 * 1000);
        
        Cursor cursor = db.query(TABLE_LOCATION_CACHE,
                null,
                CACHE_TIMESTAMP + " > ?",
                new String[]{String.valueOf(timeLimit)},
                null, null,
                CACHE_TIMESTAMP + " ASC");
        
        while (cursor.moveToNext()) {
            LocationPoint point = new LocationPoint();
            point.id = cursor.getLong(cursor.getColumnIndexOrThrow(CACHE_ID));
            point.tripId = -1; // No trip for cached locations
            point.latitude = cursor.getDouble(cursor.getColumnIndexOrThrow(CACHE_LATITUDE));
            point.longitude = cursor.getDouble(cursor.getColumnIndexOrThrow(CACHE_LONGITUDE));
            point.altitude = cursor.getDouble(cursor.getColumnIndexOrThrow(CACHE_ALTITUDE));
            point.accuracy = cursor.getFloat(cursor.getColumnIndexOrThrow(CACHE_ACCURACY));
            point.speed = cursor.getFloat(cursor.getColumnIndexOrThrow(CACHE_SPEED));
            point.bearing = cursor.getFloat(cursor.getColumnIndexOrThrow(CACHE_BEARING));
            point.timestamp = cursor.getLong(cursor.getColumnIndexOrThrow(CACHE_TIMESTAMP));
            point.source = cursor.getString(cursor.getColumnIndexOrThrow(CACHE_SOURCE));
            point.provider = cursor.getString(cursor.getColumnIndexOrThrow(CACHE_PROVIDER));
            locations.add(point);
        }
        
        cursor.close();
        return locations;
    }
    
    /**
     * Clear all cached locations
     */
    public void clearCachedLocations() {
        SQLiteDatabase db = this.getWritableDatabase();
        int deleted = db.delete(TABLE_LOCATION_CACHE, null, null);
        Log.d(TAG, "🗑️ Cleared " + deleted + " cached locations");
    }
    
    // ========== DAILY LOCATION METHODS ==========
    
    /**
     * Get list of days that have locations (cache OR trips)
     * Returns dates in "YYYY-MM-DD" format
     */
    public List<String> getDaysWithLocations() {
        List<String> days = new ArrayList<>();
        SQLiteDatabase db = this.getReadableDatabase();
        
        // Get distinct dates from both cache and trips tables using UNION
        String query = 
                "SELECT DISTINCT date(" + CACHE_TIMESTAMP + "/1000, 'unixepoch', 'localtime') as day " +
                "FROM " + TABLE_LOCATION_CACHE + " " +
                "UNION " +
                "SELECT DISTINCT date(" + LOC_TIMESTAMP + "/1000, 'unixepoch', 'localtime') as day " +
                "FROM " + TABLE_LOCATIONS + " " +
                "ORDER BY day DESC";
        
        Log.d(TAG, "📅 Querying days with locations...");
        Cursor cursor = db.rawQuery(query, null);
        
        while (cursor.moveToNext()) {
            String day = cursor.getString(0);
            days.add(day);
            Log.d(TAG, "   Found date: " + day);
        }
        
        cursor.close();
        Log.d(TAG, "📊 Total days with locations: " + days.size());
        return days;
    }
    
    /**
     * Get all cached locations for a specific day
     * @param date Date in "YYYY-MM-DD" format
     */
    public List<LocationPoint> getLocationsByDay(String date) {
        List<LocationPoint> locations = new ArrayList<>();
        SQLiteDatabase db = this.getReadableDatabase();
        
        // Get start and end of day in milliseconds
        String startQuery = "SELECT strftime('%s', ?) * 1000";
        String endQuery = "SELECT strftime('%s', ? || ' 23:59:59') * 1000";
        
        Cursor startCursor = db.rawQuery(startQuery, new String[]{date});
        Cursor endCursor = db.rawQuery(endQuery, new String[]{date});
        
        long startTime = 0;
        long endTime = 0;
        
        if (startCursor.moveToFirst()) {
            startTime = startCursor.getLong(0);
        }
        if (endCursor.moveToFirst()) {
            endTime = endCursor.getLong(0);
        }
        
        startCursor.close();
        endCursor.close();
        
        // Get locations for this day
        Cursor cursor = db.query(TABLE_LOCATION_CACHE,
                null,
                CACHE_TIMESTAMP + " BETWEEN ? AND ?",
                new String[]{String.valueOf(startTime), String.valueOf(endTime)},
                null, null,
                CACHE_TIMESTAMP + " ASC");
        
        while (cursor.moveToNext()) {
            LocationPoint point = new LocationPoint();
            point.id = cursor.getLong(cursor.getColumnIndexOrThrow(CACHE_ID));
            point.tripId = -1; // Cached locations don't have trip_id
            point.latitude = cursor.getDouble(cursor.getColumnIndexOrThrow(CACHE_LATITUDE));
            point.longitude = cursor.getDouble(cursor.getColumnIndexOrThrow(CACHE_LONGITUDE));
            point.altitude = cursor.getDouble(cursor.getColumnIndexOrThrow(CACHE_ALTITUDE));
            point.accuracy = cursor.getFloat(cursor.getColumnIndexOrThrow(CACHE_ACCURACY));
            point.speed = cursor.getFloat(cursor.getColumnIndexOrThrow(CACHE_SPEED));
            point.bearing = cursor.getFloat(cursor.getColumnIndexOrThrow(CACHE_BEARING));
            point.timestamp = cursor.getLong(cursor.getColumnIndexOrThrow(CACHE_TIMESTAMP));
            point.source = cursor.getString(cursor.getColumnIndexOrThrow(CACHE_SOURCE));
            point.provider = cursor.getString(cursor.getColumnIndexOrThrow(CACHE_PROVIDER));
            locations.add(point);
        }
        
        cursor.close();
        return locations;
    }
    
    /**
     * Get ALL locations for a specific day (both cached AND trip locations)
     * @param date Date in "YYYY-MM-DD" format
     */
    public List<LocationPoint> getAllLocationsByDay(String date) {
        List<LocationPoint> allLocations = new ArrayList<>();
        SQLiteDatabase db = this.getReadableDatabase();
        
        // Get start and end of day in milliseconds
        String startQuery = "SELECT strftime('%s', ?) * 1000";
        String endQuery = "SELECT strftime('%s', ? || ' 23:59:59') * 1000";
        
        Cursor startCursor = db.rawQuery(startQuery, new String[]{date});
        Cursor endCursor = db.rawQuery(endQuery, new String[]{date});
        
        long startTime = 0;
        long endTime = 0;
        
        if (startCursor.moveToFirst()) {
            startTime = startCursor.getLong(0);
        }
        if (endCursor.moveToFirst()) {
            endTime = endCursor.getLong(0);
        }
        
        startCursor.close();
        endCursor.close();
        
        // 1. Get cached locations for this day
        Cursor cacheCursor = db.query(TABLE_LOCATION_CACHE,
                null,
                CACHE_TIMESTAMP + " BETWEEN ? AND ?",
                new String[]{String.valueOf(startTime), String.valueOf(endTime)},
                null, null,
                CACHE_TIMESTAMP + " ASC");

        while (cacheCursor.moveToNext()) {
            LocationPoint point = new LocationPoint();
            point.id = cacheCursor.getLong(cacheCursor.getColumnIndexOrThrow(CACHE_ID));
            point.tripId = -1;
            point.latitude = cacheCursor.getDouble(cacheCursor.getColumnIndexOrThrow(CACHE_LATITUDE));
            point.longitude = cacheCursor.getDouble(cacheCursor.getColumnIndexOrThrow(CACHE_LONGITUDE));
            point.altitude = cacheCursor.getDouble(cacheCursor.getColumnIndexOrThrow(CACHE_ALTITUDE));
            point.accuracy = cacheCursor.getFloat(cacheCursor.getColumnIndexOrThrow(CACHE_ACCURACY));
            point.speed = cacheCursor.getFloat(cacheCursor.getColumnIndexOrThrow(CACHE_SPEED));
            point.bearing = cacheCursor.getFloat(cacheCursor.getColumnIndexOrThrow(CACHE_BEARING));
            point.timestamp = cacheCursor.getLong(cacheCursor.getColumnIndexOrThrow(CACHE_TIMESTAMP));
            point.source = cacheCursor.getString(cacheCursor.getColumnIndexOrThrow(CACHE_SOURCE));
            point.provider = cacheCursor.getString(cacheCursor.getColumnIndexOrThrow(CACHE_PROVIDER));
            allLocations.add(point);
        }
        cacheCursor.close();
        
        // 2. Get trip locations for this day
        Cursor tripCursor = db.query(TABLE_LOCATIONS,
                null,
                LOC_TIMESTAMP + " BETWEEN ? AND ?",
                new String[]{String.valueOf(startTime), String.valueOf(endTime)},
                null, null,
                LOC_TIMESTAMP + " ASC");

        while (tripCursor.moveToNext()) {
            LocationPoint point = new LocationPoint();
            point.id = tripCursor.getLong(tripCursor.getColumnIndexOrThrow(LOC_ID));
            point.tripId = tripCursor.getLong(tripCursor.getColumnIndexOrThrow(LOC_TRIP_ID));
            point.latitude = tripCursor.getDouble(tripCursor.getColumnIndexOrThrow(LOC_LATITUDE));
            point.longitude = tripCursor.getDouble(tripCursor.getColumnIndexOrThrow(LOC_LONGITUDE));
            point.altitude = tripCursor.getDouble(tripCursor.getColumnIndexOrThrow(LOC_ALTITUDE));
            point.accuracy = tripCursor.getFloat(tripCursor.getColumnIndexOrThrow(LOC_ACCURACY));
            point.speed = tripCursor.getFloat(tripCursor.getColumnIndexOrThrow(LOC_SPEED));
            point.bearing = tripCursor.getFloat(tripCursor.getColumnIndexOrThrow(LOC_BEARING));
            point.timestamp = tripCursor.getLong(tripCursor.getColumnIndexOrThrow(LOC_TIMESTAMP));
            point.source = tripCursor.getString(tripCursor.getColumnIndexOrThrow(LOC_SOURCE));
            point.provider = tripCursor.getString(tripCursor.getColumnIndexOrThrow(LOC_PROVIDER));
            allLocations.add(point);
        }
        tripCursor.close();
        
        // Sort by timestamp to merge cached and trip locations chronologically
        allLocations.sort((a, b) -> Long.compare(a.timestamp, b.timestamp));
        
        return allLocations;
    }
    
    /**
     * Calculate distance for a specific day
     * @param date Date in "YYYY-MM-DD" format
     * @return Distance in meters
     */
    public double calculateDailyDistance(String date) {
        // Use getAllLocationsByDay to include BOTH cache and trip locations
        List<LocationPoint> locations = getAllLocationsByDay(date);
        
        if (locations.size() < 2) {
            return 0.0;
        }
        
        double totalDistance = 0.0;
        
        for (int i = 1; i < locations.size(); i++) {
            LocationPoint prev = locations.get(i - 1);
            LocationPoint curr = locations.get(i);
            
            // Create Location objects for distance calculation
            Location prevLoc = new Location("");
            prevLoc.setLatitude(prev.latitude);
            prevLoc.setLongitude(prev.longitude);
            
            Location currLoc = new Location("");
            currLoc.setLatitude(curr.latitude);
            currLoc.setLongitude(curr.longitude);
            
            // Calculate distance between consecutive points
            float segmentDistance = prevLoc.distanceTo(currLoc);
            
            // Only add if distance is reasonable (< 500m between points)
            // This filters out GPS jumps
            if (segmentDistance < 500.0f) {
                totalDistance += segmentDistance;
            }
        }
        
        return totalDistance;
    }
    
    /**
     * Get daily statistics
     */
    public DailySummary getDailySummary(String date) {
        DailySummary summary = new DailySummary();
        summary.date = date;
        
        // Use getAllLocationsByDay to include BOTH cache and trip locations
        List<LocationPoint> locations = getAllLocationsByDay(date);
        summary.locationCount = locations.size();
        
        if (locations.isEmpty()) {
            return summary;
        }
        
        // Calculate distance
        summary.distance = calculateDailyDistance(date);
        
        // Get first and last location times
        summary.firstLocationTime = locations.get(0).timestamp;
        summary.lastLocationTime = locations.get(locations.size() - 1).timestamp;
        
        // Calculate duration (in seconds)
        summary.duration = (summary.lastLocationTime - summary.firstLocationTime) / 1000;
        
        // Count unique sources
        List<String> sources = new ArrayList<>();
        for (LocationPoint point : locations) {
            if (point.source != null && !sources.contains(point.source)) {
                sources.add(point.source);
            }
        }
        summary.sources = sources;
        
        return summary;
    }
    
    /**
     * Get summaries for all days
     */
    public List<DailySummary> getAllDailySummaries() {
        List<DailySummary> summaries = new ArrayList<>();
        List<String> days = getDaysWithLocations();
        
        Log.d(TAG, "📋 Creating summaries for " + days.size() + " days");
        
        for (String day : days) {
            DailySummary summary = getDailySummary(day);
            summaries.add(summary);
            Log.d(TAG, "   " + day + ": " + summary.locationCount + " locations, " + 
                  String.format(Locale.US, "%.0f m", summary.distance));
        }
        
        return summaries;
    }
    
    // ========== DATA CLASSES ==========
    
    /**
     * Daily summary data class
     */
    public static class DailySummary {
        public String date;              // YYYY-MM-DD
        public int locationCount;
        public double distance;          // meters
        public long duration;            // seconds
        public long firstLocationTime;   // milliseconds
        public long lastLocationTime;    // milliseconds
        public List<String> sources;     // GPS, WIFI, CELL, etc.
        
        public String getFormattedDate() {
            try {
                SimpleDateFormat inputFormat = new SimpleDateFormat("yyyy-MM-dd", Locale.US);
                SimpleDateFormat outputFormat = new SimpleDateFormat("MMM dd, yyyy", Locale.US);
                Date d = inputFormat.parse(date);
                return d != null ? outputFormat.format(d) : date;
            } catch (Exception e) {
                return date;
            }
        }
        
        public String getFormattedDistance() {
            if (distance < 1000) {
                return String.format(Locale.US, "%.0f m", distance);
            } else {
                return String.format(Locale.US, "%.2f km", distance / 1000.0);
            }
        }
        
        public String getFormattedDuration() {
            long hours = duration / 3600;
            long minutes = (duration % 3600) / 60;
            
            if (hours > 0) {
                return String.format(Locale.US, "%dh %dm", hours, minutes);
            } else {
                return String.format(Locale.US, "%dm", minutes);
            }
        }
        
        public String getFormattedTimeRange() {
            SimpleDateFormat timeFormat = new SimpleDateFormat("HH:mm", Locale.US);
            String start = timeFormat.format(new Date(firstLocationTime));
            String end = timeFormat.format(new Date(lastLocationTime));
            return start + " - " + end;
        }
    }
}

