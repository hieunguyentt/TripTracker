//
//  DatabaseManager.swift
//  TripTracker
//
//  Native SQLite3 database manager (no external dependencies)
//

import Foundation
import SQLCipher

public class DatabaseManager {
    
    public static let shared = DatabaseManager()
    
    private var db: OpaquePointer?
    
    private init() {}
    
    public func initializeDatabase() {
        let fileManager = FileManager.default
        guard let documentsPath = fileManager.urls(for: .documentDirectory, in: .userDomainMask).first else {
            print("❌ Cannot access documents directory")
            return
        }
        
        let dbPath = documentsPath.appendingPathComponent("trip_tracker.db").path
        
        print("📁 Database path: \(dbPath)")
        
        if sqlite3_open(dbPath, &db) == SQLITE_OK {
            print("✅ Database opened successfully")
            createTables()
        } else {
            print("❌ Unable to open database")
        }
    }
    
    private func createTables() {
        // Create trips table
        let createTripsTable = """
        CREATE TABLE IF NOT EXISTS trips (
            trip_id INTEGER PRIMARY KEY AUTOINCREMENT,
            start_time INTEGER NOT NULL,
            end_time INTEGER DEFAULT 0,
            distance REAL DEFAULT 0,
            duration INTEGER DEFAULT 0,
            steps INTEGER DEFAULT 0,
            status TEXT DEFAULT 'active'
        );
        """
        
        // Create locations table
        let createLocationsTable = """
        CREATE TABLE IF NOT EXISTS locations (
            location_id INTEGER PRIMARY KEY AUTOINCREMENT,
            trip_id INTEGER NOT NULL,
            latitude REAL NOT NULL,
            longitude REAL NOT NULL,
            altitude REAL DEFAULT 0,
            accuracy REAL NOT NULL,
            speed REAL DEFAULT 0,
            bearing REAL DEFAULT 0,
            timestamp INTEGER NOT NULL,
            source TEXT NOT NULL
        );
        """
        
        // Create location_cache table
        let createCacheTable = """
        CREATE TABLE IF NOT EXISTS location_cache (
            cache_id INTEGER PRIMARY KEY AUTOINCREMENT,
            latitude REAL NOT NULL,
            longitude REAL NOT NULL,
            altitude REAL DEFAULT 0,
            accuracy REAL NOT NULL,
            speed REAL DEFAULT 0,
            bearing REAL DEFAULT 0,
            cache_timestamp INTEGER NOT NULL,
            source TEXT NOT NULL
        );
        """
        
        executeSQL(createTripsTable)
        executeSQL(createLocationsTable)
        executeSQL(createCacheTable)
        
        print("✅ Tables created successfully")
    }
    
    private func executeSQL(_ sql: String) {
        var statement: OpaquePointer?
        
        if sqlite3_prepare_v2(db, sql, -1, &statement, nil) == SQLITE_OK {
            if sqlite3_step(statement) == SQLITE_DONE {
                // Success
            } else {
                let errorMessage = String(cString: sqlite3_errmsg(db))
                print("❌ SQL execution failed: \(errorMessage)")
            }
        } else {
            let errorMessage = String(cString: sqlite3_errmsg(db))
            print("❌ SQL preparation failed: \(errorMessage)")
        }
        
        sqlite3_finalize(statement)
    }
    
    // MARK: - Trip Operations
    
    public func startTrip() -> Int64 {
        let timestamp = Int64(Date().timeIntervalSince1970 * 1000)
        let sql = "INSERT INTO trips (start_time, status) VALUES (?, 'active');"
        
        var statement: OpaquePointer?
        
        if sqlite3_prepare_v2(db, sql, -1, &statement, nil) == SQLITE_OK {
            sqlite3_bind_int64(statement, 1, timestamp)
            
            if sqlite3_step(statement) == SQLITE_DONE {
                let tripId = sqlite3_last_insert_rowid(db)
                print("🎯 Started new trip: ID=\(tripId)")
                sqlite3_finalize(statement)
                return tripId
            }
        }
        
        sqlite3_finalize(statement)
        return -1
    }
    
    public func endTrip(id: Int64, distance: Double, duration: Int64, steps: Int) {
        let timestamp = Int64(Date().timeIntervalSince1970 * 1000)
        let sql = """
        UPDATE trips 
        SET end_time = ?, distance = ?, duration = ?, steps = ?, status = 'stopped' 
        WHERE trip_id = ?;
        """
        
        var statement: OpaquePointer?
        
        if sqlite3_prepare_v2(db, sql, -1, &statement, nil) == SQLITE_OK {
            sqlite3_bind_int64(statement, 1, timestamp)
            sqlite3_bind_double(statement, 2, distance)
            sqlite3_bind_int64(statement, 3, duration)
            sqlite3_bind_int64(statement, 4, Int64(steps))
            sqlite3_bind_int64(statement, 5, id)
            
            if sqlite3_step(statement) == SQLITE_DONE {
                print("🏁 Ended trip: ID=\(id), Distance=\(distance)m")
            }
        }
        
        sqlite3_finalize(statement)
    }
    
    public func getAllTrips() -> [Trip] {
        var trips: [Trip] = []
        let sql = "SELECT trip_id, start_time, end_time, distance, duration, steps, status FROM trips ORDER BY start_time DESC;"
        
        var statement: OpaquePointer?
        
        if sqlite3_prepare_v2(db, sql, -1, &statement, nil) == SQLITE_OK {
            while sqlite3_step(statement) == SQLITE_ROW {
                let id = sqlite3_column_int64(statement, 0)
                let startTime = sqlite3_column_int64(statement, 1)
                let endTime = sqlite3_column_int64(statement, 2)
                let distance = sqlite3_column_double(statement, 3)
                let duration = sqlite3_column_int64(statement, 4)
                let steps = Int(sqlite3_column_int64(statement, 5))
                let status = String(cString: sqlite3_column_text(statement, 6))
                
                let trip = Trip(
                    id: id,
                    startTime: startTime,
                    endTime: endTime,
                    distance: distance,
                    duration: duration,
                    steps: steps,
                    status: status
                )
                trips.append(trip)
            }
        }
        
        sqlite3_finalize(statement)
        return trips
    }
    
    public func getActiveTripId() -> Int64? {
        let sql = "SELECT trip_id FROM trips WHERE status = 'active' LIMIT 1;"
        var statement: OpaquePointer?
        var tripId: Int64?
        if sqlite3_prepare_v2(db, sql, -1, &statement, nil) == SQLITE_OK {
            if sqlite3_step(statement) == SQLITE_ROW {
                tripId = sqlite3_column_int64(statement, 0)
            }
        }
        sqlite3_finalize(statement)
        return tripId
    }

    /// Returns (tripId, startTimeMs) for the interrupted active trip, or nil if none.
    public func getActiveTripInfo() -> (id: Int64, startTimeMs: Int64)? {
        let sql = "SELECT trip_id, start_time FROM trips WHERE status = 'active' ORDER BY start_time DESC LIMIT 1;"
        var statement: OpaquePointer?
        var result: (Int64, Int64)?
        if sqlite3_prepare_v2(db, sql, -1, &statement, nil) == SQLITE_OK {
            if sqlite3_step(statement) == SQLITE_ROW {
                result = (sqlite3_column_int64(statement, 0),
                          sqlite3_column_int64(statement, 1))
            }
        }
        sqlite3_finalize(statement)
        return result
    }

    /// Returns the timestamp (ms) of the most recent location saved for a trip, or nil.
    public func getLastLocationTimestamp(tripId: Int64) -> Int64? {
        let sql = "SELECT MAX(timestamp) FROM locations WHERE trip_id = ?;"
        var statement: OpaquePointer?
        var result: Int64?
        if sqlite3_prepare_v2(db, sql, -1, &statement, nil) == SQLITE_OK {
            sqlite3_bind_int64(statement, 1, tripId)
            if sqlite3_step(statement) == SQLITE_ROW {
                let val = sqlite3_column_int64(statement, 0)
                if val > 0 { result = val }
            }
        }
        sqlite3_finalize(statement)
        return result
    }
    
    // MARK: - Location Operations
    
    public func saveLocation(tripId: Int64, location: LocationPoint) {
        // Dedup: skip if a point with the same tripId + timestamp already exists
        let checkSql = "SELECT COUNT(*) FROM locations WHERE trip_id = ? AND timestamp = ?;"
        var checkStmt: OpaquePointer?
        if sqlite3_prepare_v2(db, checkSql, -1, &checkStmt, nil) == SQLITE_OK {
            sqlite3_bind_int64(checkStmt, 1, tripId)
            sqlite3_bind_int64(checkStmt, 2, location.timestamp)
            if sqlite3_step(checkStmt) == SQLITE_ROW, sqlite3_column_int(checkStmt, 0) > 0 {
                sqlite3_finalize(checkStmt)
                return  // duplicate — skip
            }
        }
        sqlite3_finalize(checkStmt)

        let sql = """
        INSERT INTO locations (trip_id, latitude, longitude, altitude, accuracy, speed, bearing, timestamp, source)
        VALUES (?, ?, ?, ?, ?, ?, ?, ?, ?);
        """
        
        var statement: OpaquePointer?
        
        if sqlite3_prepare_v2(db, sql, -1, &statement, nil) == SQLITE_OK {
            sqlite3_bind_int64(statement, 1, tripId)
            sqlite3_bind_double(statement, 2, location.latitude)
            sqlite3_bind_double(statement, 3, location.longitude)
            sqlite3_bind_double(statement, 4, location.altitude)
            sqlite3_bind_double(statement, 5, Double(location.accuracy))
            sqlite3_bind_double(statement, 6, Double(location.speed))
            sqlite3_bind_double(statement, 7, Double(location.bearing))
            sqlite3_bind_int64(statement, 8, location.timestamp)
            sqlite3_bind_text(statement, 9, (location.source as NSString).utf8String, -1, nil)
            
            sqlite3_step(statement)
        }
        
        sqlite3_finalize(statement)
    }
    
    public func saveCachedLocation(location: LocationPoint) {
        // Dedup: skip if a cached point with the same timestamp already exists
        let checkSql = "SELECT COUNT(*) FROM location_cache WHERE cache_timestamp = ?;"
        var checkStmt: OpaquePointer?
        if sqlite3_prepare_v2(db, checkSql, -1, &checkStmt, nil) == SQLITE_OK {
            sqlite3_bind_int64(checkStmt, 1, location.timestamp)
            if sqlite3_step(checkStmt) == SQLITE_ROW, sqlite3_column_int(checkStmt, 0) > 0 {
                sqlite3_finalize(checkStmt)
                return  // duplicate — skip
            }
        }
        sqlite3_finalize(checkStmt)

        let sql = """
        INSERT INTO location_cache (latitude, longitude, altitude, accuracy, speed, bearing, cache_timestamp, source)
        VALUES (?, ?, ?, ?, ?, ?, ?, ?);
        """
        
        var statement: OpaquePointer?
        
        if sqlite3_prepare_v2(db, sql, -1, &statement, nil) == SQLITE_OK {
            sqlite3_bind_double(statement, 1, location.latitude)
            sqlite3_bind_double(statement, 2, location.longitude)
            sqlite3_bind_double(statement, 3, location.altitude)
            sqlite3_bind_double(statement, 4, Double(location.accuracy))
            sqlite3_bind_double(statement, 5, Double(location.speed))
            sqlite3_bind_double(statement, 6, Double(location.bearing))
            sqlite3_bind_int64(statement, 7, location.timestamp)
            sqlite3_bind_text(statement, 8, (location.source as NSString).utf8String, -1, nil)
            
            sqlite3_step(statement)
        }
        
        sqlite3_finalize(statement)
        
        // Clean old cache
        cleanOldCache()
    }
    
    public func getLocationsForTrip(tripId: Int64) -> [LocationPoint] {
        var locations: [LocationPoint] = []
        let sql = """
        SELECT location_id, trip_id, latitude, longitude, altitude, accuracy, speed, bearing, timestamp, source
        FROM locations
        WHERE trip_id = ?
        ORDER BY timestamp ASC;
        """
        
        var statement: OpaquePointer?
        
        if sqlite3_prepare_v2(db, sql, -1, &statement, nil) == SQLITE_OK {
            sqlite3_bind_int64(statement, 1, tripId)
            
            while sqlite3_step(statement) == SQLITE_ROW {
                let id = sqlite3_column_int64(statement, 0)
                let tripId = sqlite3_column_int64(statement, 1)
                let latitude = sqlite3_column_double(statement, 2)
                let longitude = sqlite3_column_double(statement, 3)
                let altitude = sqlite3_column_double(statement, 4)
                let accuracy = Float(sqlite3_column_double(statement, 5))
                let speed = Float(sqlite3_column_double(statement, 6))
                let bearing = Float(sqlite3_column_double(statement, 7))
                let timestamp = sqlite3_column_int64(statement, 8)
                let source = String(cString: sqlite3_column_text(statement, 9))
                
                let location = LocationPoint(
                    id: id,
                    tripId: tripId,
                    latitude: latitude,
                    longitude: longitude,
                    altitude: altitude,
                    accuracy: accuracy,
                    speed: speed,
                    bearing: bearing,
                    timestamp: timestamp,
                    source: source
                )
                locations.append(location)
            }
        }
        
        sqlite3_finalize(statement)
        return locations
    }
    
    public func getCachedLocations(date: String? = nil) -> [LocationPoint] {
        var locations: [LocationPoint] = []
        var sql = """
        SELECT cache_id, latitude, longitude, altitude, accuracy, speed, bearing, cache_timestamp, source
        FROM location_cache
        """
        
        if let dateStr = date {
            // Filter by date
            let formatter = DateFormatter()
            formatter.dateFormat = "yyyy-MM-dd"
            if let targetDate = formatter.date(from: dateStr) {
                let startOfDay = Int64(Calendar.current.startOfDay(for: targetDate).timeIntervalSince1970 * 1000)
                let endOfDay = startOfDay + 86400000
                sql += " WHERE cache_timestamp >= \(startOfDay) AND cache_timestamp < \(endOfDay)"
            }
        }
        
        sql += " ORDER BY cache_timestamp DESC LIMIT 10000;"
        
        var statement: OpaquePointer?
        
        if sqlite3_prepare_v2(db, sql, -1, &statement, nil) == SQLITE_OK {
            while sqlite3_step(statement) == SQLITE_ROW {
                let id = sqlite3_column_int64(statement, 0)
                let latitude = sqlite3_column_double(statement, 1)
                let longitude = sqlite3_column_double(statement, 2)
                let altitude = sqlite3_column_double(statement, 3)
                let accuracy = Float(sqlite3_column_double(statement, 4))
                let speed = Float(sqlite3_column_double(statement, 5))
                let bearing = Float(sqlite3_column_double(statement, 6))
                let timestamp = sqlite3_column_int64(statement, 7)
                let source = String(cString: sqlite3_column_text(statement, 8))
                
                let location = LocationPoint(
                    id: id,
                    latitude: latitude,
                    longitude: longitude,
                    altitude: altitude,
                    accuracy: accuracy,
                    speed: speed,
                    bearing: bearing,
                    timestamp: timestamp,
                    source: source
                )
                locations.append(location)
            }
        }
        
        sqlite3_finalize(statement)
        return locations
    }
    
    public func getDatesWithLocations() -> [(date: String, count: Int)] {
        var dates: [(String, Int)] = []
        let sql = """
        SELECT DATE(cache_timestamp / 1000, 'unixepoch') as date, COUNT(*) as count
        FROM location_cache
        GROUP BY date
        ORDER BY date DESC
        LIMIT 30;
        """
        
        var statement: OpaquePointer?
        
        if sqlite3_prepare_v2(db, sql, -1, &statement, nil) == SQLITE_OK {
            while sqlite3_step(statement) == SQLITE_ROW {
                if let dateStr = sqlite3_column_text(statement, 0) {
                    let date = String(cString: dateStr)
                    let count = Int(sqlite3_column_int64(statement, 1))
                    dates.append((date, count))
                }
            }
        }
        
        sqlite3_finalize(statement)
        return dates
    }
    
    private func cleanOldCache() {
        if(getCachedLocationCount() >= 10000){
            let sevenDayAgo = Int64(Date().timeIntervalSince1970 * 1000) - (7 * 86400000)
            let sql = "DELETE FROM location_cache WHERE cache_timestamp < ?;"
            
            var statement: OpaquePointer?
            
            if sqlite3_prepare_v2(db, sql, -1, &statement, nil) == SQLITE_OK {
                sqlite3_bind_int64(statement, 1, sevenDayAgo)
                sqlite3_step(statement)
            }
            
            sqlite3_finalize(statement)
        }
    }
    
    public func getCachedLocationCount() -> Int {
        let sql = "SELECT COUNT(*) FROM location_cache;"
        var statement: OpaquePointer?
        var count = 0
        
        if sqlite3_prepare_v2(db, sql, -1, &statement, nil) == SQLITE_OK {
            if sqlite3_step(statement) == SQLITE_ROW {
                count = Int(sqlite3_column_int64(statement, 0))
            }
        }
        
        sqlite3_finalize(statement)
        return count
    }
    
    public func saveContext() {
        // SQLite auto-commits, but we can add any cleanup here if needed
    }
    
    deinit {
        if db != nil {
            sqlite3_close(db)
        }
    }
}
