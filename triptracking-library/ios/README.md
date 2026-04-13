# TripTracker iOS Library

GPS trip tracking library for iOS — drop into any app.

**NOT included** (your app provides these):
- `AppDelegate.swift`
- `SceneDelegate.swift` (optional — library provides one for CarPlay)
- `Info.plist`
- `*.entitlements`
- `LaunchScreen.storyboard`

**Included** (25 Swift files):
- `TripTrackerSDK.swift` — single entry point
- `Controllers/` — 7 view controllers (Main, Settings, Notifications, History, TripMap, DailyLocations, Geofence)
- `Services/` — 6 services (LocationTracking, Geofence, Voice, Notification, Log, RouteDrawing)
- `Models/` — 4 models (Location, Trip, GeofenceZone, TrackingSource)
- `Database/` — DatabaseManager (SQLite)
- `WebServer/` — LocationWebServer (HTTP on :8080)
- `CarPlay/` — 4 CarPlay files
- `SceneDelegate.swift` — default scene delegate

---

## Installation

### Option A: CocoaPods

```ruby
# Podfile
pod 'TripTracker', :path => './TripTracker'
```

```bash
pod install
```

### Option B: Swift Package Manager

```
File → Add Package Dependencies → Add Local → select TripTracker folder
```

### Option C: Copy Source Files Directly

Copy the entire `Sources/TripTracker/` folder into your Xcode project.

---

## Integration (3 steps)

### Step 1: AppDelegate.swift

```swift
import UIKit
// import TripTracker  // if using SPM/CocoaPods

@main
class AppDelegate: UIResponder, UIApplicationDelegate {
    var window: UIWindow?

    func application(_ application: UIApplication,
                     didFinishLaunchingWithOptions launchOptions: [UIApplication.LaunchOptionsKey: Any]?) -> Bool {
        // ✅ One line initializes everything
        TripTrackerSDK.initialize(launchOptions: launchOptions)
        return true
    }

    func applicationDidEnterBackground(_ application: UIApplication) {
        TripTrackerSDK.didEnterBackground()
    }

    func applicationWillTerminate(_ application: UIApplication) {
        TripTrackerSDK.willTerminate()
    }

    // CarPlay support (optional — remove if not needed)
    func application(_ application: UIApplication,
                     configurationForConnecting connectingSceneSession: UISceneSession,
                     options: UIScene.ConnectionOptions) -> UISceneConfiguration {
        return TripTrackerSDK.sceneConfiguration(for: connectingSceneSession)
    }
}
```

### Step 2: Info.plist

Add these keys:

```xml
<key>NSLocationAlwaysAndWhenInUseUsageDescription</key>
<string>TripTracker needs always-on location for background tracking.</string>

<key>NSLocationAlwaysUsageDescription</key>
<string>TripTracker uses location in background to track your routes.</string>

<key>NSLocationWhenInUseUsageDescription</key>
<string>TripTracker needs location access to track your trips.</string>

<key>NSMotionUsageDescription</key>
<string>TripTracker uses motion sensors for accurate positioning.</string>

<key>UIBackgroundModes</key>
<array>
    <string>location</string>
    <string>fetch</string>
    <string>processing</string>
    <string>audio</string>
</array>
```

### Step 3: Entitlements (if using CarPlay)

Add to your `.entitlements` file:
```xml
<key>com.apple.developer.carplay-driving-task</key>
<true/>
```

---

## Usage

### Open native pages from your app

```swift
// Present the full TripTracker main view (map + tracking)
TripTrackerSDK.presentMainView(from: self)

// Present Settings page
TripTrackerSDK.presentSettings(from: self)

// Present Notification Settings (per-type toggles + voice)
TripTrackerSDK.presentNotificationSettings(from: self)

// Present Geofence Manager (map + zone list)
TripTrackerSDK.presentGeofenceManager(from: self)

// Present Trip History
TripTrackerSDK.presentHistory(from: self)

// Present Daily Locations
TripTrackerSDK.presentDailyLocations(from: self)
```

### Access data without UI

```swift
// Check if tracking
if TripTrackerSDK.isTracking {
    let tripId = TripTrackerSDK.currentTripId
    let stats = TripTrackerSDK.getCurrentStats()
    print("Speed: \(stats.speed) m/s")
    print("Distance: \(stats.distance) m")
}

// Get last known coordinate
if let coord = TripTrackerSDK.lastKnownCoordinate {
    print("Lat: \(coord.latitude), Lon: \(coord.longitude)")
}
```

### Control web monitor

```swift
TripTrackerSDK.startWebMonitor()   // HTTP server on :8080
TripTrackerSDK.stopWebMonitor()    // Save battery
```

---

## What `TripTrackerSDK.initialize()` does

One call replaces the entire AppDelegate setup:

| Step | What it does |
|------|-------------|
| 1 | Registers first-install UserDefaults |
| 2 | Starts LogManager (captures stdout to daily log files) |
| 3 | Initializes SQLite database |
| 4 | Starts GPS + significant location changes + visits |
| 5 | Resumes active trip if app was killed mid-trip |
| 6 | Starts web monitor server (if enabled) |
| 7 | Requests notification permission |
| 8 | Starts geofence monitoring (if enabled) |

---

## Library vs Standalone App

| File | Standalone App | Library |
|------|---------------|---------|
| `AppDelegate.swift` | ✅ Included | ❌ Host provides |
| `SceneDelegate.swift` | ✅ Included | ✅ Provided (for CarPlay) |
| `Info.plist` | ✅ Included | ❌ Host provides |
| `*.entitlements` | ✅ Included | ❌ Host provides |
| `LaunchScreen` | ✅ Included | ❌ Host provides |
| `TripTrackerSDK.swift` | ❌ Not needed | ✅ Entry point |
| `Controllers/` (7 files) | ✅ | ✅ |
| `Services/` (6 files) | ✅ | ✅ |
| `Models/` (4 files) | ✅ | ✅ |
| `Database/` (1 file) | ✅ | ✅ |
| `WebServer/` (1 file) | ✅ | ✅ |
| `CarPlay/` (4 files) | ✅ | ✅ |

---

## File List (25 Swift files)

```
Sources/TripTracker/
├── TripTrackerSDK.swift                    ← Entry point
├── SceneDelegate.swift                     ← Default scene (CarPlay)
├── Controllers/
│   ├── MainViewController.swift            ← Map + tracking UI
│   ├── SettingsViewController.swift        ← Sliders, toggles, web monitor
│   ├── NotificationSettingsViewController.swift ← Per-type push + voice
│   ├── HistoryViewController.swift         ← Trip list
│   ├── TripMapViewController.swift         ← Single trip route on map
│   ├── DailyLocationsViewController.swift  ← Daily locations + route
│   └── GeofenceViewController.swift        ← Map + zone management
├── Services/
│   ├── LocationTrackingService.swift       ← GPS, sensors, auto-trip
│   ├── GeofenceManager.swift               ← Zone monitoring + alerts
│   ├── VoiceFeedbackManager.swift          ← AVSpeechSynthesizer
│   ├── NotificationManager.swift           ← Push notifications
│   ├── LogManager.swift                    ← Stdout → daily log files
│   └── RouteDrawingAlgorithm.swift         ← GPS filtering + simplification
├── Models/
│   ├── Location.swift
│   ├── Trip.swift
│   ├── TrackingSource.swift                ← + RouteTransportType + MapAppearanceHelper
│   └── GeofenceZone.swift
├── Database/
│   └── DatabaseManager.swift               ← SQLite
├── WebServer/
│   └── LocationWebServer.swift             ← HTTP :8080
└── CarPlay/
    ├── CarPlaySceneDelegate.swift
    ├── CarPlayMapManager.swift
    ├── CarPlayMapViewController.swift
    └── CarPlayDrivingTaskManager.swift
```
