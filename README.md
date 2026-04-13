# TripTracker
TripTracker is a GPS-based trip tracking and navigation application designed for fleet management and personal vehicle monitoring.

Cross-platform library for iOS, Android, Flutter, Ionic

# TripTracking Library — Integration Guide

## 📱 Android Native App

### Prerequisites
- Android Studio installed
- GitHub Personal Access Token with `read:packages` scope

### Step 1: Add GitHub Packages repository
Open `build.gradle` (project level):
```gradle
allprojects {
    repositories {
        google()
        mavenCentral()
        maven {
            url = uri("https://maven.pkg.github.com/hieunguyentt/TripTracker")
            credentials {
                username = "hieunguyentt"
                password = "your_github_token"
            }
        }
    }
}
```

Or if using `settings.gradle`:
```gradle
dependencyResolutionManagement {
    repositories {
        google()
        mavenCentral()
        maven {
            url = uri("https://maven.pkg.github.com/hieunguyentt/TripTracker")
            credentials {
                username = "hieunguyentt"
                password = "your_github_token"
            }
        }
    }
}
```

### Step 2: Add dependency
Open `app/build.gradle`:
```gradle
dependencies {
    implementation 'com.github.hieunguyentt:triptracking-android:1.0.0'
}
```

### Step 3: Sync project
```
Android Studio → File → Sync Project with Gradle Files
```

### Step 4: Use in code
```java
import com.carmd.triptracking.TripTracking;

// Start tracking
TripTracking.getInstance().startTracking();

// Stop tracking
TripTracking.getInstance().stopTracking();
```

### Step 5: Run app
```
Android Studio → Run → Run 'app'
```

---

## 🍎 iOS Native App

### Prerequisites
- Xcode installed
- CocoaPods installed (`sudo gem install cocoapods`)

### Step 1: Navigate to iOS project
```bash
cd your-ios-app
```

### Step 2: Create or edit Podfile
```bash
# Create if not exists
pod init
```

### Step 3: Add library to Podfile
```ruby
platform :ios, '14.0'

target 'YourApp' do
  use_frameworks!

  pod 'triptracking', 
      :git => 'https://github.com/hieunguyentt/TripTracker.git', 
      :tag => '1.0.0'
end
```

### Step 4: Install pods
```bash
pod install
```

### Step 5: Open workspace (NOT .xcodeproj)
```bash
open YourApp.xcworkspace
```

### Step 6: Use in code
```swift
import triptracking

// Start tracking
TripTracking().startTracking()

// Stop tracking
TripTracking().stopTracking()
```

### Step 7: Run app
```
Xcode → Product → Run (⌘R)
```

---

## 🐦 Flutter App

### Prerequisites
- Flutter SDK installed
- Android Studio or Xcode for device/emulator

### Step 1: Navigate to Flutter project
```bash
cd your-flutter-app
```

### Step 2: Add library to pubspec.yaml
```yaml
dependencies:
  flutter:
    sdk: flutter
  
  triptracking_flutter:
    git:
      url: https://github.com/hieunguyentt/TripTracker.git
      path: flutter_plugin
      ref: 1.0.0
```

### Step 3: Add GitHub token for Android (inside Flutter project)
Create or edit `android/local.properties`:
```properties
sdk.dir=/Users/yourname/Library/Android/sdk
GITHUB_ACTOR=hieunguyentt
GITHUB_TOKEN=your_github_token
```

### Step 4: Install dependencies
```bash
flutter pub get
```

### Step 5: Add iOS pod source (inside Flutter project)
Edit `ios/Podfile`, add at the top:
```ruby
platform :ios, '14.0'
```

Then run:
```bash
cd ios && pod install && cd ..
```

### Step 6: Use in code
```dart
import 'package:triptracking_flutter/triptracking_flutter.dart';

// Start tracking
await TripTrackingFlutter.startTracking();

// Stop tracking
await TripTrackingFlutter.stopTracking();

// Get current trip
final trip = await TripTrackingFlutter.getCurrentTrip();
```

### Step 7: Run app
```bash
# List available devices
flutter devices

# Run on specific device
flutter run -d device_id

# Or run on all devices
flutter run
```

---

## ⚡ Ionic App (Capacitor)

### Prerequisites
- Node.js >= 16 installed
- Ionic CLI installed
- Android Studio and/or Xcode installed

### Step 1: Navigate to Ionic project
```bash
cd your-ionic-app
```

### Step 2: Install the plugin
```bash
npm install github:hieunguyentt/TripTracker#1.0.0
```

### Step 3: Sync native platforms
```bash
npx cap sync
```

### Step 4: Add GitHub token for Android
Edit `android/local.properties`:
```properties
sdk.dir=/Users/yourname/Library/Android/sdk
GITHUB_ACTOR=hieunguyentt
GITHUB_TOKEN=your_github_token
```

### Step 5: Use in code
```typescript
import { TripTracking } from 'triptracking-capacitor';

// Start tracking
await TripTracking.startTracking();

// Stop tracking
await TripTracking.stopTracking();

// Get current trip
const { trip } = await TripTracking.getCurrentTrip();

// Listen for location updates
await TripTracking.addListener('locationUpdate', (location) => {
  console.log(location.lat, location.lng, location.speed);
});
```

### Step 6: Build Ionic app
```bash
ionic build
```

### Step 7: Run on Android
```bash
npx cap open android
# Android Studio opens → Run app
```

### Step 8: Run on iOS
```bash
npx cap open ios
# Xcode opens → Run app (⌘R)
```

---

## 🔄 Update to new version

When a new version (e.g. `1.1.0`) is released:

### Android
```gradle
implementation 'com.github.hieunguyentt:triptracking-android:1.1.0'
```

### iOS
```ruby
pod 'triptracking', :git => '...', :tag => '1.1.0'
```
```bash
pod update triptracking
```

### Flutter
```yaml
ref: 1.1.0
```
```bash
flutter pub upgrade
```

### Ionic
```bash
npm install github:hieunguyentt/TripTracker#1.1.0
npx cap sync
```

---

## 🔑 GitHub Token

All platforms need a GitHub Personal Access Token to download the Android library from GitHub Packages.

**Create token:**
```
1. github.com → Settings
2. Developer settings → Personal access tokens → Tokens (classic)
3. Generate new token (classic)
4. Select scopes: ✅ read:packages, ✅ repo
5. Copy token
```

> ⚠️ Never commit your token to source control.

