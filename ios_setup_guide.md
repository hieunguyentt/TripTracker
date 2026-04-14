# TripTracking SDK — iOS Integration Guide

## Requirements

| Tool | Minimum Version |
|---|---|
| iOS | 14.0+ |
| Xcode | 14.0+ |
| Swift | 5.0+ |
| CocoaPods | 1.11.0+ |

---

## Step 1: Install CocoaPods

```bash
sudo gem install cocoapods
pod --version
```

---

## Step 2: Initialize CocoaPods in your project

> ⚠️ Close Xcode before running these commands.

```bash
cd path/to/YourApp
pod init
```

---

## Step 3: Edit Podfile

```ruby
platform :ios, '14.0'

install! 'cocoapods', :disable_input_output_paths => true

target 'YourApp' do
  use_frameworks! :linkage => :static

  pod 'triptracking',
      :git => 'https://github.com/hieunguyentt/TripTracker.git',
      :tag => '1.0.0'
end
```

> Replace `YourApp` with your actual Xcode target name.

---

## Step 4: Install pods

```bash
pod install
```

Expected output:
```
Installing triptracking 1.0.0
Pod installation complete!
```

---

## Step 5: Open .xcworkspace

> ⚠️ Always open `.xcworkspace` — NOT `.xcodeproj`

```bash
open YourApp.xcworkspace
```

---

## Step 6: Add permissions to Info.plist

In Xcode, open `Info.plist` and add the following keys:

```xml
<!-- Location -->
<key>NSLocationWhenInUseUsageDescription</key>
<string>App needs location access to track trips</string>

<key>NSLocationAlwaysAndWhenInUseUsageDescription</key>
<string>App needs background location to track trips continuously</string>

<key>NSLocationAlwaysUsageDescription</key>
<string>App needs background location to track trips continuously</string>

<!-- Motion -->
<key>NSMotionUsageDescription</key>
<string>App needs motion sensor to detect trips</string>

<!-- Background Modes -->
<key>UIBackgroundModes</key>
<array>
    <string>location</string>
    <string>fetch</string>
</array>
```

Or via Xcode UI:
```
Target → Signing & Capabilities → + Capability → Background Modes
✅ Location updates
✅ Background fetch
```

---

## Step 7: Initialize SDK in AppDelegate.swift

```swift
import UIKit
import triptracking

@main
class AppDelegate: UIResponder, UIApplicationDelegate {

    func application(
        _ application: UIApplication,
        didFinishLaunchingWithOptions launchOptions: [UIApplication.LaunchOptionsKey: Any]?
    ) -> Bool {
        // Initialize TripTrackerSDK
        TripTrackerSDK.initialize(launchOptions: launchOptions)
        return true
    }

    func applicationDidEnterBackground(_ application: UIApplication) {
        TripTrackerSDK.didEnterBackground()
    }

    func applicationWillTerminate(_ application: UIApplication) {
        TripTrackerSDK.willTerminate()
    }

    func application(
        _ application: UIApplication,
        configurationForConnecting connectingSceneSession: UISceneSession,
        options: UIScene.ConnectionOptions
    ) -> UISceneConfiguration {
        return TripTrackerSDK.sceneConfiguration(for: connectingSceneSession)
    }
}
```

---

## Step 8: Use SDK in ViewController.swift

```swift
import UIKit
import triptracking

class ViewController: UIViewController {

    override func viewDidLoad() {
        super.viewDidLoad()

        // Check tracking status
        let isTracking = TripTrackerSDK.isTracking
        print("Is tracking: \(isTracking)")

        // Get last known location
        if let coord = TripTrackerSDK.lastKnownCoordinate {
            print("Location: \(coord.latitude), \(coord.longitude)")
        }
    }

    // ── Present Native Screens ──────────────────────────────

    func openMap() {
        TripTrackerSDK.presentMainView(from: self)
    }

    func openSettings() {
        TripTrackerSDK.presentSettings(from: self)
    }

    func openNotificationSettings() {
        TripTrackerSDK.presentNotificationSettings(from: self)
    }

    func openGeofenceManager() {
        TripTrackerSDK.presentGeofenceManager(from: self)
    }

    func openHistory() {
        TripTrackerSDK.presentHistory(from: self)
    }

    func openDailyLocations() {
        TripTrackerSDK.presentDailyLocations(from: self)
    }

    // ── Web Monitor ─────────────────────────────────────────

    func startMonitor() {
        TripTrackerSDK.startWebMonitor()
    }

    func stopMonitor() {
        TripTrackerSDK.stopWebMonitor()
    }

    // ── Data Access ─────────────────────────────────────────

    func getCurrentStats() {
        let stats = TripTrackerSDK.getCurrentStats()
        print("Speed: \(stats.speed)")
        print("Distance: \(stats.distance)")
        print("Duration: \(stats.duration)")
        print("Steps: \(stats.steps)")
    }
}
```

---

## SDK API Reference

### Lifecycle

| Method | Description |
|---|---|
| `TripTrackerSDK.initialize(launchOptions:)` | Initialize SDK — call in `didFinishLaunching` |
| `TripTrackerSDK.didEnterBackground()` | Call in `applicationDidEnterBackground` |
| `TripTrackerSDK.willTerminate()` | Call in `applicationWillTerminate` |
| `TripTrackerSDK.sceneConfiguration(for:)` | Handle CarPlay + phone scene config |

### Present Native Screens

| Method | Description |
|---|---|
| `TripTrackerSDK.presentMainView(from:)` | Show map with trip tracking |
| `TripTrackerSDK.presentSettings(from:)` | Show settings screen |
| `TripTrackerSDK.presentNotificationSettings(from:)` | Show notification settings |
| `TripTrackerSDK.presentGeofenceManager(from:)` | Show geofence manager |
| `TripTrackerSDK.presentHistory(from:)` | Show trip history |
| `TripTrackerSDK.presentDailyLocations(from:)` | Show daily locations |

### Data Access

| Property / Method | Description |
|---|---|
| `TripTrackerSDK.isTracking` | `Bool` — current tracking state |
| `TripTrackerSDK.currentTripId` | `Int64` — active trip ID |
| `TripTrackerSDK.lastKnownCoordinate` | `CLLocationCoordinate2D?` — last GPS point |
| `TripTrackerSDK.getCurrentStats()` | Returns speed, distance, duration, steps |

### Web Monitor

| Method | Description |
|---|---|
| `TripTrackerSDK.startWebMonitor()` | Start web monitor server |
| `TripTrackerSDK.stopWebMonitor()` | Stop web monitor server |

---

## Troubleshooting

### Module 'triptracking' not found
```bash
pod deintegrate
pod install
# Open .xcworkspace NOT .xcodeproj
```

### Sandbox / rsync permission error
```bash
# Disable Xcode sandbox
defaults write com.apple.dt.Xcode DVTDisableSandbox -bool YES
killall Xcode
```

Then clean and rebuild:
```
Product → Clean Build Folder (⌘ + Shift + K)
Product → Run (⌘R)
```

### Deployment target error
```
Xcode → Target → General
→ Minimum Deployments → iOS 14.0
```

### Pod not found
```bash
pod cache clean --all
pod install
```

---

## Version History

| Version | Notes |
|---|---|
| 1.0.0 | Initial release |
