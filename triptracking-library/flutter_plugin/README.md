# TripTracker Flutter Plugin (iOS + Android)

Flutter plugin for TripTracker — GPS trip tracking, geofencing, voice feedback.
Opens native pages directly from Flutter on both platforms.

## Architecture

```
Flutter (Dart)
  │
  ├── MethodChannel('triptracker')
  │
  ├──► iOS:     TripTrackerPlugin.swift    → Native Swift UIKit pages
  │                                         → TripTrackerSDK / Services
  │
  └──► Android: TripTrackerFlutterPlugin.java → Native Java Activities
                                               → LocationTrackingService
```

## Installation

### 1. Add plugin

```yaml
# pubspec.yaml
dependencies:
  triptracker:
    path: ./plugins/triptracker
```

### 2. Add native sources

**iOS:** Add the `triptracking` CocoaPod or copy Swift sources into Xcode project.

**Android:** The host app must include the TripTracker native Java sources in its module:
```
app/src/main/java/com/carmd/triptracking/
├── services/LocationTrackingService.java
├── tracking/SensorBasedLocationTracker.java
├── database/LocationDatabase.java
├── geofence/GeofenceManager.java, GeofenceBroadcastReceiver.java
├── server/LocationWebServer.java
├── ui/MainActivity.java, SettingsActivity.java, NotificationSettingsActivity.java,
│    GeofenceSettingsActivity.java, TripHistoryActivity.java, DailyLocationsActivity.java,
│    DayDetailsActivity.java, RouteViewActivity.java, AppSettings.java
├── util/LogcatWriter.java, VoiceFeedback.java
├── receivers/BootReceiver.java, DailyLogSenderReceiver.java, DailyReminderReceiver.java
├── auto/TripTrackerCarAppService.java, TripTrackerSession.java, TripTrackerScreen.java, TripMapRenderer.java
└── TripTrackerApp.java
```

### 3. Initialize

**iOS** — `AppDelegate.swift`:
```swift
TripTrackerSDK.initialize(launchOptions: launchOptions)
```

**Android** — `TripTrackerApp.java` already handles initialization.
Add activities to your `AndroidManifest.xml` (see the Android source).

## Usage (same Dart API for both platforms)

```dart
import 'package:triptracker/triptracker.dart';

// ── Open native pages ──
await TripTracker.openSettings();
await TripTracker.openNotificationSettings();
await TripTracker.openGeofenceManager();
await TripTracker.openMainView();
await TripTracker.openHistory();
await TripTracker.openDailyLocations();

// ── Tracking status ──
final status = await TripTracker.getTrackingStatus();
print('${status.speedKmh} km/h, ${status.distance} m');
print('Tracking: ${status.isTracking}, Trip #${status.tripId}');

// ── Settings ──
final settings = await TripTracker.getSettings();
await TripTracker.updateSetting('voiceFeedbackEnabled', false);
await TripTracker.updateSetting('autoEndTimeoutMinutes', 10);

// ── Geofence ──
final zones = await TripTracker.getGeofenceZones();
await TripTracker.addGeofenceZone(
  name: 'Office',
  latitude: 10.8017,
  longitude: 106.6408,
  radius: 200,
);

// ── Trip history ──
final trips = await TripTracker.getTripHistory(limit: 20);
for (final trip in trips) {
  print('Trip #${trip.id}: ${trip.distance}m in ${trip.duration}s');
}

// ── Web monitor / Logs ──
await TripTracker.startWebMonitor();
await TripTracker.sendTodayLog();
```

## API Reference

| Method | Description | iOS | Android |
|--------|-------------|-----|---------|
| `openSettings()` | Full native Settings page | ✅ | ✅ |
| `openNotificationSettings()` | Push + voice toggles | ✅ | ✅ |
| `openGeofenceManager()` | Map + zone management | ✅ | ✅ |
| `openMainView()` | Full map + tracking | ✅ | ✅ |
| `openHistory()` | Trip list | ✅ | ✅ |
| `openDailyLocations()` | Day-by-day locations | ✅ | ✅ |
| `getTrackingStatus()` | Speed, distance, trip info | ✅ | ✅ |
| `getCurrentLocation()` | Lat/lon/speed | ✅ | ✅ |
| `getTripHistory()` | Trip list with stats | ✅ | ✅ |
| `getSettings()` | All settings as typed model | ✅ | ✅ |
| `updateSetting(key, value)` | Update one setting | ✅ | ✅ |
| `getGeofenceZones()` | All zones | ✅ | ✅ |
| `addGeofenceZone(...)` | Add zone | ✅ | ✅ |
| `removeGeofenceZone(id)` | Remove zone | ✅ | ✅ |
| `startWebMonitor()` | HTTP server | ✅ | ✅ |
| `stopWebMonitor()` | Save battery | ✅ | ✅ |
| `sendTodayLog()` | Share sheet | ✅ | ✅ |
| `sendAllLogs()` | Share sheet | ✅ | ✅ |

## Plugin Structure

```
triptracker/
├── pubspec.yaml                              ← Both platforms
├── lib/
│   ├── triptracker.dart                      ← Public API + typed models
│   ├── triptracker_platform_interface.dart    ← Platform interface
│   └── triptracker_method_channel.dart        ← MethodChannel
├── ios/
│   ├── Classes/
│   │   └── TripTrackerPlugin.swift           ← iOS bridge
│   └── triptracker.podspec
├── android/
│   ├── build.gradle
│   └── src/main/
│       ├── AndroidManifest.xml
│       └── java/.../TripTrackerFlutterPlugin.java  ← Android bridge
├── example/lib/
│   └── main.dart                             ← Demo app
└── README.md
```
