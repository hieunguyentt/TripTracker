import 'package:plugin_platform_interface/plugin_platform_interface.dart';
import 'triptracker_method_channel.dart';

abstract class TripTrackerPlatform extends PlatformInterface {
  TripTrackerPlatform() : super(token: _token);
  static final Object _token = Object();
  static TripTrackerPlatform _instance = MethodChannelTripTracker();
  static TripTrackerPlatform get instance => _instance;
  static set instance(TripTrackerPlatform instance) {
    PlatformInterface.verifyToken(instance, _token);
    _instance = instance;
  }

  // Native pages
  Future<void> openSettings();
  Future<void> openNotificationSettings();
  Future<void> openGeofenceManager();
  Future<void> openMainView();
  Future<void> openHistory();
  Future<void> openDailyLocations();

  // Tracking
  Future<Map<String, dynamic>> getTrackingStatus();
  Future<Map<String, dynamic>> getCurrentLocation();

  // History
  Future<Map<String, dynamic>> getTripHistory({int limit = 50});

  // Settings
  Future<Map<String, dynamic>> getSettings();
  Future<void> updateSetting(String key, dynamic value);

  // Geofence
  Future<Map<String, dynamic>> getGeofenceZones();
  Future<String> addGeofenceZone({
    required String name,
    required double latitude,
    required double longitude,
    double radius = 200,
    bool notifyOnEnter = true,
    bool notifyOnExit = true,
    bool autoStopOnEnter = false,
  });
  Future<void> removeGeofenceZone(String id);

  // Web monitor
  Future<void> startWebMonitor();
  Future<void> stopWebMonitor();

  // Logs
  Future<void> sendTodayLog();
  Future<void> sendAllLogs();
}
