import 'package:flutter/services.dart';
import 'triptracker_platform_interface.dart';

class MethodChannelTripTracker extends TripTrackerPlatform {
  static const _channel = MethodChannel('triptracker');

  // ── Native Pages ──

  @override
  Future<void> openSettings() async {
    await _channel.invokeMethod('openSettings');
  }

  @override
  Future<void> openNotificationSettings() async {
    await _channel.invokeMethod('openNotificationSettings');
  }

  @override
  Future<void> openGeofenceManager() async {
    await _channel.invokeMethod('openGeofenceManager');
  }

  @override
  Future<void> openMainView() async {
    await _channel.invokeMethod('openMainView');
  }

  @override
  Future<void> openHistory() async {
    await _channel.invokeMethod('openHistory');
  }

  @override
  Future<void> openDailyLocations() async {
    await _channel.invokeMethod('openDailyLocations');
  }

  // ── Tracking ──

  @override
  Future<Map<String, dynamic>> getTrackingStatus() async {
    final result = await _channel.invokeMethod('getTrackingStatus');
    return Map<String, dynamic>.from(result);
  }

  @override
  Future<Map<String, dynamic>> getCurrentLocation() async {
    final result = await _channel.invokeMethod('getCurrentLocation');
    return Map<String, dynamic>.from(result);
  }

  // ── History ──

  @override
  Future<Map<String, dynamic>> getTripHistory({int limit = 50}) async {
    final result = await _channel.invokeMethod('getTripHistory', {'limit': limit});
    return Map<String, dynamic>.from(result);
  }

  // ── Settings ──

  @override
  Future<Map<String, dynamic>> getSettings() async {
    final result = await _channel.invokeMethod('getSettings');
    return Map<String, dynamic>.from(result);
  }

  @override
  Future<void> updateSetting(String key, dynamic value) async {
    await _channel.invokeMethod('updateSetting', {'key': key, 'value': value});
  }

  // ── Geofence ──

  @override
  Future<Map<String, dynamic>> getGeofenceZones() async {
    final result = await _channel.invokeMethod('getGeofenceZones');
    return Map<String, dynamic>.from(result);
  }

  @override
  Future<String> addGeofenceZone({
    required String name,
    required double latitude,
    required double longitude,
    double radius = 200,
    bool notifyOnEnter = true,
    bool notifyOnExit = true,
    bool autoStopOnEnter = false,
  }) async {
    final result = await _channel.invokeMethod('addGeofenceZone', {
      'name': name,
      'latitude': latitude,
      'longitude': longitude,
      'radius': radius,
      'notifyOnEnter': notifyOnEnter,
      'notifyOnExit': notifyOnExit,
      'autoStopOnEnter': autoStopOnEnter,
    });
    return result['id'] as String;
  }

  @override
  Future<void> removeGeofenceZone(String id) async {
    await _channel.invokeMethod('removeGeofenceZone', {'id': id});
  }

  // ── Web Monitor ──

  @override
  Future<void> startWebMonitor() async {
    await _channel.invokeMethod('startWebMonitor');
  }

  @override
  Future<void> stopWebMonitor() async {
    await _channel.invokeMethod('stopWebMonitor');
  }

  // ── Logs ──

  @override
  Future<void> sendTodayLog() async {
    await _channel.invokeMethod('sendTodayLog');
  }

  @override
  Future<void> sendAllLogs() async {
    await _channel.invokeMethod('sendAllLogs');
  }
}
