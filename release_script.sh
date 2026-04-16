#!/bin/bash

# ═══════════════════════════════════════════════════════════
# TripTracker Library — Auto Release Script
# Usage: ./release.sh 1.0.6
# ═══════════════════════════════════════════════════════════

# ── Config ──────────────────────────────────────────────────
GITHUB_USERNAME="hieunguyentt"
GITHUB_TOKEN="your_github_token"   # ← paste your token here

LIBRARY_ROOT="/Users/devmac2025/Documents/HieuNguyen/Projects/R&D/Sensor/Versions/Github/TripTracker/triptracking-library"
REPO_ROOT="/Users/devmac2025/Documents/HieuNguyen/Projects/R&D/Sensor/Versions/Github/TripTracker"
# ────────────────────────────────────────────────────────────

# Colors
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m'

log()     { echo -e "${BLUE}[INFO]${NC} $1"; }
success() { echo -e "${GREEN}[✅]${NC} $1"; }
warning() { echo -e "${YELLOW}[⚠️]${NC} $1"; }
error()   { echo -e "${RED}[❌]${NC} $1"; exit 1; }

# ── Check version argument ───────────────────────────────────
if [ -z "$1" ]; then
    echo "Usage: ./release.sh <version>"
    echo "Example: ./release.sh 1.0.6"
    exit 1
fi

NEW_VERSION=$1

# Get current version from podspec
OLD_VERSION=$(grep "s.version" "$REPO_ROOT/triptracking.podspec" | sed "s/.*= '//;s/'.*//")

echo ""
echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
echo "  TripTracker Release: $OLD_VERSION → $NEW_VERSION"
echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
echo ""

# ── Step 1: Bump versions ────────────────────────────────────
log "Step 1: Bumping version $OLD_VERSION → $NEW_VERSION"

# Android build.gradle
sed -i '' "s/version   = '$OLD_VERSION'/version   = '$NEW_VERSION'/" \
    "$LIBRARY_ROOT/android/build.gradle"
sed -i '' "s/versionName \"$OLD_VERSION\"/versionName \"$NEW_VERSION\"/" \
    "$LIBRARY_ROOT/android/build.gradle"
success "android/build.gradle updated"

# iOS podspec
sed -i '' "s/s.version          = '$OLD_VERSION'/s.version          = '$NEW_VERSION'/" \
    "$REPO_ROOT/triptracking.podspec"
success "triptracking.podspec updated"

# Flutter pubspec
sed -i '' "s/^version: $OLD_VERSION/version: $NEW_VERSION/" \
    "$LIBRARY_ROOT/flutter_plugin/pubspec.yaml"
success "flutter_plugin/pubspec.yaml updated"

# Root package.json (Capacitor)
sed -i '' "s/\"version\": \"$OLD_VERSION\"/\"version\": \"$NEW_VERSION\"/" \
    "$REPO_ROOT/package.json"
success "package.json updated"

# ── Step 2: Build Capacitor plugin ───────────────────────────
log "Step 2: Building Capacitor plugin..."

cd "$LIBRARY_ROOT/capacitor_plugin" || error "capacitor_plugin folder not found"

npm install --silent
npm run build

if [ $? -ne 0 ]; then
    error "Capacitor plugin build failed!"
fi
success "Capacitor plugin built"

# ── Step 3: Publish Android to GitHub Packages ───────────────
log "Step 3: Publishing Android library to GitHub Packages..."

cd "$LIBRARY_ROOT" || error "Library root not found"

./gradlew :android:publishReleasePublicationToGitHubPackagesRepository \
    -PGITHUB_ACTOR=$GITHUB_USERNAME \
    -PGITHUB_TOKEN=$GITHUB_TOKEN

if [ $? -ne 0 ]; then
    error "Android publish failed!"
fi
success "Android library published to GitHub Packages"

# ── Step 4: Commit and push ───────────────────────────────────
log "Step 4: Committing changes..."

cd "$REPO_ROOT" || error "Repo root not found"

git add .
git commit -m "release: v$NEW_VERSION"
git push origin main

if [ $? -ne 0 ]; then
    error "Git push failed!"
fi
success "Changes pushed to GitHub"

# ── Step 5: Create and push tag ───────────────────────────────
log "Step 5: Creating tag v$NEW_VERSION..."

# Delete old tag if exists
git tag -d $NEW_VERSION 2>/dev/null
git push origin :refs/tags/$NEW_VERSION 2>/dev/null

# Create new tag
git tag $NEW_VERSION
git push origin $NEW_VERSION

if [ $? -ne 0 ]; then
    error "Tag push failed!"
fi
success "Tag $NEW_VERSION pushed"

# ── Done ──────────────────────────────────────────────────────
echo ""
echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
echo -e "${GREEN}🎉 Release v$NEW_VERSION completed!${NC}"
echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
echo ""
echo "📦 Update consumers:"
echo ""
echo "  Android app (build.gradle):"
echo "  implementation 'com.github.$GITHUB_USERNAME:triptracking-android:$NEW_VERSION'"
echo ""
echo "  iOS app (Podfile):"
echo "  pod 'triptracking', :git => 'https://github.com/$GITHUB_USERNAME/TripTracker.git', :tag => '$NEW_VERSION'"
echo "  → run: pod update triptracking"
echo ""
echo "  Flutter app (pubspec.yaml):"
echo "  ref: $NEW_VERSION"
echo "  → run: flutter pub upgrade"
echo ""
echo "  Ionic app:"
echo "  npm uninstall capacitor-triptracker"
echo "  npm install 'github:$GITHUB_USERNAME/TripTracker#$NEW_VERSION' --legacy-peer-deps"
echo "  npx cap sync"
echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
