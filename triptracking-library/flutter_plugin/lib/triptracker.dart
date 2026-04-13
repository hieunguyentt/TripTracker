/// TripTracker Flutter Plugin
///
/// GPS trip tracking for iOS — auto-trip, geofencing, voice feedback, CarPlay.
///
/// ```dart
/// import 'package:triptracker/triptracker.dart';
///
/// // Open native Settings page
/// await TripTracker.openSettings();
///
/// // Get tracking status
/// final status = await TripTracker.getTrackingStatus();
/// print('Speed: ${status.speedKmh} km/h');
/// ```
library triptracker;

import 'triptracker_platform_interface.dart';

export 'triptracker_platform_interface.dart';

// ── Models ──

class TrackingStatus {
  final bool isTracking;
  final double speed;       // m/s
  final double speedKmh;    // km/h
  final double distance;    // meters
  final int duration;        // seconds
  final int steps;
  final int tripId;
  final double? latitude;
  final double? longitude;

  TrackingStatus.fromMap(Map<String, dynamic> m)
      : isTracking = m['isTracking'] ?? false,
        speed = (m['speed'] ?? 0).toDouble(),
        speedKmh = (m['speedKmh'] ?? 0).toDouble(),
        distance = (m['distance'] ?? 0).toDouble(),
        duration = (m['duration'] ?? 0).toInt(),
        steps = (m['steps'] ?? 0).toInt(),
        tripId = (m['tripId'] ?? 0).toInt(),
        latitude = m['latitude']?.toDouble(),
        longitude = m['longitude']?.toDouble();
}

class TripInfo {
  final int id;
  final int startTimeMs;
  final int endTimeMs;
  final double distance;
  final int duration;
  final bool isActive;

  TripInfo.fromMap(Map<String, dynamic> m)
      : id = (m['id'] ?? 0).toInt(),
        startTimeMs = (m['startTime'] ?? 0).toInt(),
        endTimeMs = (m['endTime'] ?? 0).toInt(),
        distance = (m['distance'] ?? 0).toDouble(),
        duration = (m['duration'] ?? 0).toInt(),
        isActive = m['isActive'] ?? false;
}

class TripTrackerSettings {
  final double vehicleThreshold;
  final double vehicleThresholdKmh;
  final double saveIntervalMinutes;
  final double saveDistanceMeters;
  final double autoEndTimeoutMinutes;
  final double routeGapThresholdMeters;
  final bool webMonitorEnabled;
  final bool voiceFeedbackEnabled;
  final bool geofencingEnabled;
  final bool notifyTripStart;
  final bool notifyTripEnd;
  final bool notifyDistanceKm;
  final bool notifyGeofenceEnter;
  final bool notifyGeofenceExit;

  TripTrackerSettings.fromMap(Map<String, dynamic> m)
      : vehicleThreshold = (m['vehicleThreshold'] ?? 6).toDouble(),
        vehicleThresholdKmh = (m['vehicleThresholdKmh'] ?? 22).toDouble(),
        saveIntervalMinutes = (m['saveIntervalMinutes'] ?? 15).toDouble(),
        saveDistanceMeters = (m['saveDistanceMeters'] ?? 30).toDouble(),
        autoEndTimeoutMinutes = (m['autoEndTimeoutMinutes'] ?? 5).toDouble(),
        routeGapThresholdMeters = (m['routeGapThresholdMeters'] ?? 500).toDouble(),
        webMonitorEnabled = m['webMonitorEnabled'] ?? false,
        voiceFeedbackEnabled = m['voiceFeedbackEnabled'] ?? true,
        geofencingEnabled = m['geofencingEnabled'] ?? false,
        notifyTripStart = m['notifyTripStart'] ?? true,
        notifyTripEnd = m['notifyTripEnd'] ?? true,
        notifyDistanceKm = m['notifyDistanceKm'] ?? true,
        notifyGeofenceEnter = m['notifyGeofenceEnter'] ?? true,
        notifyGeofenceExit = m['notifyGeofenceExit'] ?? true;
}

class GeofenceZone {
  final String id;
  final String name;
  final double latitude;
  final double longitude;
  final double radius;
  final bool notifyOnEnter;
  final bool notifyOnExit;
  final bool autoStopOnEnter;

  GeofenceZone.fromMap(Map<String, dynamic> m)
      : id = m['id'] ?? '',
        name = m['name'] ?? '',
        latitude = (m['latitude'] ?? 0).toDouble(),
        longitude = (m['longitude'] ?? 0).toDouble(),
        radius = (m['radius'] ?? 200).toDouble(),
        notifyOnEnter = m['notifyOnEnter'] ?? true,
        notifyOnExit = m['notifyOnExit'] ?? true,
        autoStopOnEnter = m['autoStopOnEnter'] ?? false;
}

// ── Main API ──

class TripTracker {
  static TripTrackerPlatform get _platform => TripTrackerPlatform.instance;

  // ── Native Pages ──

  /// Open the full native Settings page (sliders, toggles, web monitor, CarPlay).
  static Future<void> openSettings() => _platform.openSettings();

  /// Open the Notification Settings page (per-type push toggles + voice).
  static Future<void> openNotificationSettings() => _platform.openNotificationSettings();

  /// Open the Geofence Manager page (map + zone list).
  static Future<void> openGeofenceManager() => _platform.openGeofenceManager();

  /// Open the main TripTracker map view.
  static Future<void> openMainView() => _platform.openMainView();

  /// Open the Trip History page.
  static Future<void> openHistory() => _platform.openHistory();

  /// Open the Daily Locations page.
  static Future<void> openDailyLocations() => _platform.openDailyLocations();

  // ── Tracking ──

  /// Get current tracking status with typed model.
  static Future<TrackingStatus> getTrackingStatus() async {
    final map = await _platform.getTrackingStatus();
    return TrackingStatus.fromMap(map);
  }

  /// Get current GPS location.
  static Future<Map<String, dynamic>> getCurrentLocation() => _platform.getCurrentLocation();

  // ── History ──

  /// Get trip history as typed list.
  static Future<List<TripInfo>> getTripHistory({int limit = 50}) async {
    final map = await _platform.getTripHistory(limit: limit);
    final trips = (map['trips'] as List?)?.map((t) => TripInfo.fromMap(Map<String, dynamic>.from(t))).toList();
    return trips ?? [];
  }

  // ── Settings ──

  /// Get all settings as typed model.
  static Future<TripTrackerSettings> getSettings() async {
    final map = await _platform.getSettings();
    return TripTrackerSettings.fromMap(map);
  }

  /// Update a single setting by key.
  ///
  /// Keys: vehicleThreshold, saveIntervalMinutes, saveDistanceMeters,
  ///       autoEndTimeoutMinutes, routeGapThresholdMeters, webMonitorEnabled,
  ///       voiceFeedbackEnabled, geofencingEnabled
  static Future<void> updateSetting(String key, dynamic value) => _platform.updateSetting(key, value);

  // ── Geofence ──

  /// Get all geofence zones as typed list.
  static Future<List<GeofenceZone>> getGeofenceZones() async {
    final map = await _platform.getGeofenceZones();
    final zones = (map['zones'] as List?)?.map((z) => GeofenceZone.fromMap(Map<String, dynamic>.from(z))).toList();
    return zones ?? [];
  }

  /// Add a geofence zone. Returns the zone ID.
  static Future<String> addGeofenceZone({
    required String name,
    required double latitude,
    required double longitude,
    double radius = 200,
    bool notifyOnEnter = true,
    bool notifyOnExit = true,
    bool autoStopOnEnter = false,
  }) => _platform.addGeofenceZone(
    name: name,
    latitude: latitude,
    longitude: longitude,
    radius: radius,
    notifyOnEnter: notifyOnEnter,
    notifyOnExit: notifyOnExit,
    autoStopOnEnter: autoStopOnEnter,
  );

  /// Remove a geofence zone by ID.
  static Future<void> removeGeofenceZone(String id) => _platform.removeGeofenceZone(id);

  // ── Web Monitor ──

  /// Start the web monitor HTTP server on port 8080.
  static Future<void> startWebMonitor() => _platform.startWebMonitor();

  /// Stop the web monitor to save battery.
  static Future<void> stopWebMonitor() => _platform.stopWebMonitor();

  // ── Logs ──

  /// Share today's log via share sheet.
  static Future<void> sendTodayLog() => _platform.sendTodayLog();

  /// Share all logs via share sheet.
  static Future<void> sendAllLogs() => _platform.sendAllLogs();
}
