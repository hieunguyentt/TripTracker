#!/bin/bash

# ─────────────────────────────────────────────
# CONFIG — change these before running
# ─────────────────────────────────────────────
GITHUB_USERNAME="hieunguyentt"
LIBRARY_NAME="triptracking"
PACKAGE_NAME="com.carmd.triptracking"       # Android package
MIN_SDK=21
IOS_DEPLOYMENT_TARGET="13.0"
VERSION="1.0.0"
# ─────────────────────────────────────────────

ROOT="$(echo "$LIBRARY_NAME" | tr '[:upper:]' '[:lower:]')-library"

echo "🚀 Creating project: $ROOT"
mkdir -p "$ROOT" && cd "$ROOT" || exit 1

# ════════════════════════════════════════════
# FOLDERS
# ════════════════════════════════════════════
mkdir -p android/src/main/java/${PACKAGE_NAME//./\/}/models
mkdir -p android/src/main/java/${PACKAGE_NAME//./\/}/utils
mkdir -p android/src/main/res
mkdir -p ios/Sources/$LIBRARY_NAME/models
mkdir -p ios/Sources/$LIBRARY_NAME/utils
mkdir -p flutter_plugin/lib/src
mkdir -p flutter_plugin/android/src/main/kotlin/${PACKAGE_NAME//./\/}/flutter
mkdir -p flutter_plugin/ios/Classes
mkdir -p capacitor_plugin/src
mkdir -p capacitor_plugin/android/src/main/java/${PACKAGE_NAME//./\/}/capacitor
mkdir -p capacitor_plugin/ios/Plugin
mkdir -p example/android_app
mkdir -p example/ios_app
mkdir -p example/flutter_app
mkdir -p example/ionic_app
mkdir -p .github/workflows

echo "✅ Folders created"

# ════════════════════════════════════════════
# ROOT FILES
# ════════════════════════════════════════════

# .gitignore
cat > .gitignore << 'EOF'
# Android
.gradle/
build/
local.properties
*.aar
*.iml
.idea/
captures/
.cxx/

# iOS
Pods/
*.xcworkspace
DerivedData/
xcuserdata/
*.pbxuser
*.mode1v3
*.xcuserstate

# Flutter
.dart_tool/
.flutter-plugins
.flutter-plugins-dependencies
.packages
pubspec.lock

# Capacitor
node_modules/
dist/
www/

# System
.DS_Store
Thumbs.db
.env
*.env.local
gpr.properties
EOF

# README.md
cat > README.md << EOF
# $LIBRARY_NAME

Cross-platform native library for iOS, Android, Flutter, and Ionic (Capacitor).

## Platforms
| Platform | Distribution |
|---|---|
| Android Native | GitHub Packages (.aar) |
| iOS Native | CocoaPods |
| Flutter | pub.dev / git dependency |
| Ionic | npm / git dependency |

## Installation

### Android (build.gradle)
\`\`\`gradle
implementation 'com.github.$GITHUB_USERNAME:${ROOT}:$VERSION'
\`\`\`

### iOS (Podfile)
\`\`\`ruby
pod '$LIBRARY_NAME', :git => 'https://github.com/$GITHUB_USERNAME/${ROOT}.git', :tag => '$VERSION'
\`\`\`

### Flutter (pubspec.yaml)
\`\`\`yaml
dependencies:
  ${LIBRARY_NAME,,}_flutter:
    git:
      url: https://github.com/$GITHUB_USERNAME/${ROOT}.git
      path: flutter_plugin
      ref: $VERSION
\`\`\`

### Ionic / Capacitor
\`\`\`bash
npm install github:$GITHUB_USERNAME/${ROOT}#$VERSION
npx cap sync
\`\`\`

## Version
Current version: \`$VERSION\`
EOF

# settings.gradle.kts
cat > settings.gradle.kts << EOF
rootProject.name = "${ROOT}"
include(":android")
EOF

# build.gradle.kts
cat > build.gradle.kts << EOF
plugins {
    id("com.android.library") version "8.1.0" apply false
    id("org.jetbrains.kotlin.android") version "1.9.0" apply false
}
EOF

# gradle.properties
cat > gradle.properties << EOF
android.useAndroidX=true
android.enableJetifier=true
kotlin.code.style=official
EOF

echo "✅ Root files created"

# ════════════════════════════════════════════
# ANDROID
# ════════════════════════════════════════════

cat > android/AndroidManifest.xml << EOF
<manifest xmlns:android="http://schemas.android.com/apk/res/android"
    package="$PACKAGE_NAME" />
EOF

cat > android/build.gradle << EOF
plugins {
    id 'com.android.library'
    id 'kotlin-android'
    id 'maven-publish'
}

android {
    namespace '$PACKAGE_NAME'
    compileSdk 34

    defaultConfig {
        minSdk $MIN_SDK
        targetSdk 34
        versionName "$VERSION"
        consumerProguardFiles "consumer-rules.pro"
    }

    buildTypes {
        release {
            minifyEnabled false
            proguardFiles getDefaultProguardFile('proguard-android-optimize.txt'), 'proguard-rules.pro'
        }
    }

    compileOptions {
        sourceCompatibility JavaVersion.VERSION_17
        targetCompatibility JavaVersion.VERSION_17
    }

    kotlinOptions { jvmTarget = '17' }

    publishing {
        singleVariant("release") {
            withSourcesJar()
            withJavadocJar()
        }
    }
}

dependencies {
    implementation 'androidx.core:core-ktx:1.12.0'
    // ↓ Add your existing Android dependencies here
}

afterEvaluate {
    publishing {
        publications {
            release(MavenPublication) {
                from components.release
                groupId   = 'com.github.$GITHUB_USERNAME'
                artifactId = '${ROOT}-android'
                version   = '$VERSION'
            }
        }
        repositories {
            maven {
                name = "GitHubPackages"
                url  = uri("https://maven.pkg.github.com/$GITHUB_USERNAME/${ROOT}")
                credentials {
                    username = System.getenv("GITHUB_ACTOR")
                    password = System.getenv("GITHUB_TOKEN")
                }
            }
        }
    }
}
EOF

touch android/proguard-rules.pro
touch android/consumer-rules.pro

# Placeholder — user will replace with their own code
cat > android/src/main/java/${PACKAGE_NAME//./\/}/${LIBRARY_NAME}.kt << EOF
package $PACKAGE_NAME

/**
 * ${LIBRARY_NAME} — Main entry point.
 * TODO: Replace this file with your existing Android source code.
 */
class $LIBRARY_NAME {
    fun doSomething(input: String): String {
        return "Processed: \$input"
    }
}
EOF

echo "✅ Android files created"

# ════════════════════════════════════════════
# iOS
# ════════════════════════════════════════════

cat > ios/${LIBRARY_NAME}.podspec << EOF
Pod::Spec.new do |s|
  s.name             = '$LIBRARY_NAME'
  s.version          = '$VERSION'
  s.summary          = '$LIBRARY_NAME cross-platform native library'
  s.description      = <<-DESC
    Native iOS library that can be consumed by iOS native, Flutter, and Ionic apps.
  DESC
  s.homepage         = 'https://github.com/$GITHUB_USERNAME/${ROOT}'
  s.license          = { :type => 'MIT', :file => 'LICENSE' }
  s.author           = { 'Your Name' => 'you@email.com' }
  s.source           = {
    :git => 'https://github.com/$GITHUB_USERNAME/${ROOT}.git',
    :tag => s.version.to_s
  }
  s.ios.deployment_target = '$IOS_DEPLOYMENT_TARGET'
  s.swift_version         = '5.0'
  s.source_files          = 'ios/Sources/$LIBRARY_NAME/**/*.{swift,h,m}'
  s.public_header_files   = 'ios/Sources/$LIBRARY_NAME/*.h'
  # s.dependency 'Alamofire', '~> 5.0'   ← add your iOS dependencies here
end
EOF

# Umbrella header
cat > ios/Sources/${LIBRARY_NAME}/${LIBRARY_NAME}.h << EOF
#import <Foundation/Foundation.h>
FOUNDATION_EXPORT double ${LIBRARY_NAME}VersionNumber;
FOUNDATION_EXPORT const unsigned char ${LIBRARY_NAME}VersionString[];
EOF

# Placeholder — user will replace with their own code
cat > ios/Sources/${LIBRARY_NAME}/${LIBRARY_NAME}.swift << EOF
import Foundation

/**
 * ${LIBRARY_NAME} — Main entry point.
 * TODO: Replace this file with your existing iOS source code.
 */
public class ${LIBRARY_NAME} {
    public init() {}

    public func doSomething(input: String) -> String {
        return "Processed: \(input)"
    }
}
EOF

echo "✅ iOS files created"

# ════════════════════════════════════════════
# FLUTTER PLUGIN
# ════════════════════════════════════════════

FLUTTER_PKG="${LIBRARY_NAME,,}_flutter"

cat > flutter_plugin/pubspec.yaml << EOF
name: ${FLUTTER_PKG}
description: Flutter plugin for $LIBRARY_NAME — wraps native Android and iOS library.
version: $VERSION
homepage: https://github.com/$GITHUB_USERNAME/${ROOT}

environment:
  sdk: ">=3.0.0 <4.0.0"
  flutter: ">=3.3.0"

dependencies:
  flutter:
    sdk: flutter

dev_dependencies:
  flutter_test:
    sdk: flutter
  flutter_lints: ^3.0.0

flutter:
  plugin:
    platforms:
      android:
        package: ${PACKAGE_NAME}.flutter
        pluginClass: ${LIBRARY_NAME}Plugin
      ios:
        pluginClass: ${LIBRARY_NAME}Plugin
EOF

cat > flutter_plugin/lib/${FLUTTER_PKG}.dart << EOF
import 'package:flutter/services.dart';

/// ${LIBRARY_NAME} Flutter Plugin
class ${LIBRARY_NAME}Flutter {
  static const _channel = MethodChannel('${PACKAGE_NAME}/flutter');

  /// Example method — replace with your actual feature methods
  static Future<String?> doSomething(String input) async {
    return await _channel.invokeMethod<String>('doSomething', {'input': input});
  }
}
EOF

cat > flutter_plugin/android/build.gradle << EOF
group '${PACKAGE_NAME}.flutter'
version '$VERSION'

buildscript {
    repositories { google(); mavenCentral() }
    dependencies {
        classpath 'com.android.tools.build:gradle:8.1.0'
        classpath 'org.jetbrains.kotlin:kotlin-gradle-plugin:1.9.0'
    }
}

apply plugin: 'com.android.library'
apply plugin: 'kotlin-android'

android {
    namespace '${PACKAGE_NAME}.flutter'
    compileSdkVersion 34
    defaultConfig { minSdkVersion $MIN_SDK }
    compileOptions {
        sourceCompatibility JavaVersion.VERSION_17
        targetCompatibility JavaVersion.VERSION_17
    }
    kotlinOptions { jvmTarget = '17' }
}

repositories {
    google()
    mavenCentral()
    maven {
        url = uri("https://maven.pkg.github.com/$GITHUB_USERNAME/${ROOT}")
        credentials {
            username = System.getenv("GITHUB_ACTOR") ?: project.findProperty("gpr.user")
            password = System.getenv("GITHUB_TOKEN") ?: project.findProperty("gpr.key")
        }
    }
}

dependencies {
    compileOnly 'io.flutter:flutter_embedding_debug:+'
    // ↓ Pull your Android library from GitHub Packages
    implementation 'com.github.$GITHUB_USERNAME:${ROOT}-android:$VERSION'
}
EOF

cat > flutter_plugin/android/src/main/kotlin/${PACKAGE_NAME//./\/}/flutter/${LIBRARY_NAME}Plugin.kt << EOF
package ${PACKAGE_NAME}.flutter

import ${PACKAGE_NAME}.${LIBRARY_NAME}
import io.flutter.embedding.engine.plugins.FlutterPlugin
import io.flutter.plugin.common.MethodCall
import io.flutter.plugin.common.MethodChannel
import io.flutter.plugin.common.MethodChannel.MethodCallHandler
import io.flutter.plugin.common.MethodChannel.Result

class ${LIBRARY_NAME}Plugin : FlutterPlugin, MethodCallHandler {
    private lateinit var channel: MethodChannel

    override fun onAttachedToEngine(binding: FlutterPlugin.FlutterPluginBinding) {
        channel = MethodChannel(binding.binaryMessenger, "${PACKAGE_NAME}/flutter")
        channel.setMethodCallHandler(this)
    }

    override fun onMethodCall(call: MethodCall, result: Result) {
        when (call.method) {
            "doSomething" -> {
                val input = call.argument<String>("input") ?: ""
                result.success(${LIBRARY_NAME}().doSomething(input))
            }
            else -> result.notImplemented()
        }
    }

    override fun onDetachedFromEngine(binding: FlutterPlugin.FlutterPluginBinding) {
        channel.setMethodCallHandler(null)
    }
}
EOF

cat > flutter_plugin/ios/${FLUTTER_PKG}.podspec << EOF
Pod::Spec.new do |s|
  s.name             = '${FLUTTER_PKG}'
  s.version          = '$VERSION'
  s.summary          = 'Flutter plugin iOS bridge for $LIBRARY_NAME'
  s.homepage         = 'https://github.com/$GITHUB_USERNAME/${ROOT}'
  s.license          = { :type => 'MIT' }
  s.author           = { 'Your Name' => 'you@email.com' }
  s.source           = { :path => '.' }
  s.source_files     = 'Classes/**/*'
  s.dependency 'Flutter'
  s.dependency '$LIBRARY_NAME', '$VERSION'
  s.swift_version             = '5.0'
  s.ios.deployment_target     = '$IOS_DEPLOYMENT_TARGET'
  s.pod_target_xcconfig       = { 'DEFINES_MODULE' => 'YES' }
end
EOF

cat > flutter_plugin/ios/Classes/${LIBRARY_NAME}Plugin.swift << EOF
import Flutter
import $LIBRARY_NAME

public class ${LIBRARY_NAME}Plugin: NSObject, FlutterPlugin {
    public static func register(with registrar: FlutterPluginRegistrar) {
        let channel = FlutterMethodChannel(
            name: "${PACKAGE_NAME}/flutter",
            binaryMessenger: registrar.messenger()
        )
        let instance = ${LIBRARY_NAME}Plugin()
        registrar.addMethodCallDelegate(instance, channel: channel)
    }

    public func handle(_ call: FlutterMethodCall, result: @escaping FlutterResult) {
        switch call.method {
        case "doSomething":
            let args = call.arguments as! [String: Any]
            let input = args["input"] as? String ?? ""
            result(${LIBRARY_NAME}().doSomething(input: input))
        default:
            result(FlutterMethodNotImplemented)
        }
    }
}
EOF

echo "✅ Flutter plugin files created"

# ════════════════════════════════════════════
# CAPACITOR PLUGIN (Ionic)
# ════════════════════════════════════════════

CAP_PKG="${LIBRARY_NAME,,}-capacitor"

cat > capacitor_plugin/package.json << EOF
{
  "name": "$CAP_PKG",
  "version": "$VERSION",
  "description": "Capacitor plugin for $LIBRARY_NAME",
  "main": "dist/plugin.js",
  "module": "dist/esm/index.js",
  "types": "dist/esm/index.d.ts",
  "unpkg": "dist/plugin.js",
  "repository": {
    "type": "git",
    "url": "https://github.com/$GITHUB_USERNAME/${ROOT}.git",
    "directory": "capacitor_plugin"
  },
  "capacitor": {
    "ios": { "src": "ios" },
    "android": { "src": "android" }
  },
  "scripts": {
    "build": "npm run clean && tsc && rollup -c rollup.config.js",
    "clean": "rimraf ./dist",
    "watch": "tsc --watch"
  },
  "devDependencies": {
    "@capacitor/android": "^5.0.0",
    "@capacitor/core": "^5.0.0",
    "@capacitor/ios": "^5.0.0",
    "rimraf": "^5.0.0",
    "rollup": "^3.0.0",
    "typescript": "^5.0.0"
  },
  "peerDependencies": {
    "@capacitor/core": "^5.0.0"
  }
}
EOF

cat > capacitor_plugin/src/definitions.ts << EOF
export interface ${LIBRARY_NAME}Plugin {
  /**
   * Example method — replace with your actual feature methods.
   */
  doSomething(options: { input: string }): Promise<{ value: string }>;
}
EOF

cat > capacitor_plugin/src/index.ts << EOF
import { registerPlugin } from '@capacitor/core';
import type { ${LIBRARY_NAME}Plugin } from './definitions';

const ${LIBRARY_NAME} = registerPlugin<${LIBRARY_NAME}Plugin>('${LIBRARY_NAME}', {
  web: () => import('./web').then(m => new m.${LIBRARY_NAME}Web()),
});

export * from './definitions';
export { ${LIBRARY_NAME} };
EOF

cat > capacitor_plugin/src/web.ts << EOF
import { WebPlugin } from '@capacitor/core';
import type { ${LIBRARY_NAME}Plugin } from './definitions';

export class ${LIBRARY_NAME}Web extends WebPlugin implements ${LIBRARY_NAME}Plugin {
  async doSomething(options: { input: string }): Promise<{ value: string }> {
    return { value: 'Web fallback: ' + options.input };
  }
}
EOF

cat > capacitor_plugin/android/build.gradle << EOF
apply plugin: 'com.android.library'
apply plugin: 'kotlin-android'

android {
    namespace '${PACKAGE_NAME}.capacitor'
    compileSdkVersion 34
    defaultConfig { minSdkVersion $MIN_SDK }
    compileOptions {
        sourceCompatibility JavaVersion.VERSION_17
        targetCompatibility JavaVersion.VERSION_17
    }
    kotlinOptions { jvmTarget = '17' }
}

repositories {
    google(); mavenCentral()
    maven {
        url = uri("https://maven.pkg.github.com/$GITHUB_USERNAME/${ROOT}")
        credentials {
            username = System.getenv("GITHUB_ACTOR") ?: project.findProperty("gpr.user")
            password = System.getenv("GITHUB_TOKEN") ?: project.findProperty("gpr.key")
        }
    }
}

dependencies {
    implementation project(':capacitor-android')
    implementation 'com.github.$GITHUB_USERNAME:${ROOT}-android:$VERSION'
}
EOF

cat > capacitor_plugin/android/src/main/java/${PACKAGE_NAME//./\/}/capacitor/${LIBRARY_NAME}CapacitorPlugin.kt << EOF
package ${PACKAGE_NAME}.capacitor

import ${PACKAGE_NAME}.${LIBRARY_NAME}
import com.getcapacitor.Plugin
import com.getcapacitor.PluginCall
import com.getcapacitor.PluginMethod
import com.getcapacitor.annotation.CapacitorPlugin
import com.getcapacitor.JSObject

@CapacitorPlugin(name = "${LIBRARY_NAME}")
class ${LIBRARY_NAME}CapacitorPlugin : Plugin() {

    @PluginMethod
    fun doSomething(call: PluginCall) {
        val input = call.getString("input") ?: ""
        val result = ${LIBRARY_NAME}().doSomething(input)
        val ret = JSObject()
        ret.put("value", result)
        call.resolve(ret)
    }
}
EOF

cat > capacitor_plugin/ios/Plugin/${LIBRARY_NAME}CapacitorPlugin.swift << EOF
import Capacitor
import $LIBRARY_NAME

@objc(${LIBRARY_NAME}CapacitorPlugin)
public class ${LIBRARY_NAME}CapacitorPlugin: CAPPlugin {

    @objc func doSomething(_ call: CAPPluginCall) {
        let input = call.getString("input") ?? ""
        let result = ${LIBRARY_NAME}().doSomething(input: input)
        call.resolve(["value": result])
    }
}
EOF

cat > capacitor_plugin/ios/Plugin/${LIBRARY_NAME}CapacitorPlugin.m << EOF
#import <Capacitor/Capacitor.h>
CAP_PLUGIN(${LIBRARY_NAME}CapacitorPlugin, "${LIBRARY_NAME}",
    CAP_PLUGIN_METHOD(doSomething, CAPPluginReturnPromise);
)
EOF

cat > capacitor_plugin/ios/${CAP_PKG}.podspec << EOF
Pod::Spec.new do |s|
  s.name             = '$CAP_PKG'
  s.version          = '$VERSION'
  s.summary          = 'Capacitor plugin for $LIBRARY_NAME'
  s.homepage         = 'https://github.com/$GITHUB_USERNAME/${ROOT}'
  s.license          = { :type => 'MIT' }
  s.author           = { 'Your Name' => 'you@email.com' }
  s.source           = { :path => '.' }
  s.source_files     = 'Plugin/**/*.{swift,h,m}'
  s.dependency 'Capacitor'
  s.dependency '$LIBRARY_NAME', '$VERSION'
  s.swift_version             = '5.0'
  s.ios.deployment_target     = '$IOS_DEPLOYMENT_TARGET'
end
EOF

echo "✅ Capacitor plugin files created"

# ════════════════════════════════════════════
# GITHUB ACTIONS
# ════════════════════════════════════════════

cat > .github/workflows/publish-android.yml << EOF
name: Publish Android Library

on:
  push:
    tags:
      - '*.*.*'

jobs:
  publish:
    runs-on: ubuntu-latest
    permissions:
      contents: read
      packages: write
    steps:
      - uses: actions/checkout@v4

      - uses: actions/setup-java@v4
        with:
          java-version: '17'
          distribution: 'temurin'

      - uses: gradle/gradle-build-action@v2

      - name: Publish to GitHub Packages
        run: ./gradlew :android:publishReleasePublicationToGitHubPackagesRepository
        env:
          GITHUB_TOKEN: \${{ secrets.GITHUB_TOKEN }}
          GITHUB_ACTOR: \${{ github.actor }}
EOF

cat > .github/workflows/validate-ios.yml << EOF
name: Validate iOS Podspec

on:
  push:
    tags:
      - '*.*.*'

jobs:
  validate:
    runs-on: macos-latest
    steps:
      - uses: actions/checkout@v4

      - name: Validate podspec
        run: pod spec lint ios/${LIBRARY_NAME}.podspec --allow-warnings
EOF

cat > .github/workflows/validate-flutter.yml << EOF
name: Validate Flutter Plugin

on:
  push:
    branches: [ main ]
    tags:
      - '*.*.*'

jobs:
  validate:
    runs-on: ubuntu-latest
    steps:
      - uses: actions/checkout@v4

      - uses: subosito/flutter-action@v2
        with:
          flutter-version: '3.19.0'

      - name: Flutter analyze
        working-directory: flutter_plugin
        run: |
          flutter pub get
          flutter analyze
EOF

echo "✅ GitHub Actions workflows created"

# ════════════════════════════════════════════
# LICENSE
# ════════════════════════════════════════════

YEAR=$(date +%Y)
cat > LICENSE << EOF
MIT License

Copyright (c) $YEAR $GITHUB_USERNAME

Permission is hereby granted, free of charge, to any person obtaining a copy
of this software and associated documentation files (the "Software"), to deal
in the Software without restriction, including without limitation the rights
to use, copy, modify, merge, publish, distribute, sublicense, and/or sell
copies of the Software, and to permit persons to whom the Software is
furnished to do so, subject to the following conditions:

The above copyright notice and this permission notice shall be included in all
copies or substantial portions of the Software.

THE SOFTWARE IS PROVIDED "AS IS", WITHOUT WARRANTY OF ANY KIND, EXPRESS OR
IMPLIED, INCLUDING BUT NOT LIMITED TO THE WARRANTIES OF MERCHANTABILITY,
FITNESS FOR A PARTICULAR PURPOSE AND NONINFRINGEMENT.
EOF

echo "✅ LICENSE created"

# ════════════════════════════════════════════
# DONE
# ════════════════════════════════════════════

echo ""
echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
echo "✅  Project created at: ./$ROOT"
echo ""
echo "📂 Next steps:"
echo "   1. Copy your Android source code into:"
echo "      $ROOT/android/src/main/java/${PACKAGE_NAME//./\/}/"
echo ""
echo "   2. Copy your iOS source code into:"
echo "      $ROOT/ios/Sources/$LIBRARY_NAME/"
echo ""
echo "   3. Update GITHUB_USERNAME in all build files if needed"
echo ""
echo "   4. Push to GitHub and create first tag:"
echo "      cd $ROOT"
echo "      git init"
echo "      git remote add origin https://github.com/$GITHUB_USERNAME/${ROOT}.git"
echo "      git add ."
echo "      git commit -m 'chore: initial library structure'"
echo "      git push origin main"
echo "      git tag $VERSION && git push origin $VERSION"
echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
