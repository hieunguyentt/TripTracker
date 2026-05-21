#!/bin/bash
# ═══════════════════════════════════════════════════════════════
# TripTracker Release Script
# Updates version in all config files, commits, tags, and pushes.
# 
# Usage:
#   ./release.sh 1.0.50
#   ./release.sh 1.0.50 "Fix GPS cold start speed"
# ═══════════════════════════════════════════════════════════════

set -e

VERSION=$1
MESSAGE=${2:-"Release v$VERSION"}

if [ -z "$VERSION" ]; then
    echo "❌ Usage: ./release.sh <version> [message]"
    echo "   Example: ./release.sh 1.0.50 \"Fix GPS cold start speed\""
    exit 1
fi

echo "🚀 Releasing TripTracker v$VERSION"
echo "   Message: $MESSAGE"
echo ""

# ── 1. Root package.json ──
ROOT_PKG="package.json"
if [ -f "$ROOT_PKG" ]; then
    sed -i '' "s/\"version\": \"[^\"]*\"/\"version\": \"$VERSION\"/" "$ROOT_PKG"
    echo "✅ $ROOT_PKG → $VERSION"
fi

# ── 2. Root package-lock.json ──
ROOT_LOCK="package-lock.json"
if [ -f "$ROOT_LOCK" ]; then
    # Update only the top-level "version" (first occurrence) — perl for macOS compat
    perl -i -pe "BEGIN{\$done=0} if(!\$done && s/\"version\": \"[^\"]*\"/\"version\": \"$VERSION\"/){\$done=1}" "$ROOT_LOCK"
    echo "✅ $ROOT_LOCK → $VERSION"
fi

# ── 3 & 4. Capacitor plugin package.json + package-lock.json ──
# Handled by "npm version" in step 9 below

# ── 5. CapacitorTripTracker.podspec (root) ──
ROOT_PODSPEC="CapacitorTripTracker.podspec"
if [ -f "$ROOT_PODSPEC" ]; then
    sed -i '' "s/s\.version[[:space:]]*=[[:space:]]*'[^']*'/s.version          = '$VERSION'/" "$ROOT_PODSPEC"
    echo "✅ $ROOT_PODSPEC → $VERSION"
fi

# ── 6. CapacitorTripTracker.podspec (capacitor_plugin) ──
CAP_PODSPEC="triptracking-library/capacitor_plugin/CapacitorTripTracker.podspec"
if [ -f "$CAP_PODSPEC" ]; then
    sed -i '' "s/s\.version[[:space:]]*=[[:space:]]*'[^']*'/s.version          = '$VERSION'/" "$CAP_PODSPEC"
    echo "✅ $CAP_PODSPEC → $VERSION"
fi

# ── 7. triptracking.podspec (root) ──
ROOT_TT_PODSPEC="triptracking.podspec"
if [ -f "$ROOT_TT_PODSPEC" ]; then
    sed -i '' "s/s\.version[[:space:]]*=[[:space:]]*'[^']*'/s.version          = '$VERSION'/" "$ROOT_TT_PODSPEC"
    echo "✅ $ROOT_TT_PODSPEC → $VERSION"
fi

# ── 8. triptracking.podspec (ios) ──
IOS_PODSPEC="triptracking-library/ios/triptracking.podspec"
if [ -f "$IOS_PODSPEC" ]; then
    sed -i '' "s/s\.version[[:space:]]*=[[:space:]]*'[^']*'/s.version          = '$VERSION'/" "$IOS_PODSPEC"
    echo "✅ $IOS_PODSPEC → $VERSION"
fi

# ── 9. Capacitor plugin npm version ──
echo ""
echo "📦 Updating npm version in capacitor_plugin..."
cd triptracking-library/capacitor_plugin
npm version $VERSION --no-git-tag-version --allow-same-version
echo "✅ npm version → $VERSION"
cd ../..

# ── 10. Ensure .gitignore excludes zip files ──
GITIGNORE=".gitignore"
PATTERNS=(
    "*.zip"
)
for pattern in "${PATTERNS[@]}"; do
    if ! grep -qxF "$pattern" "$GITIGNORE" 2>/dev/null; then
        echo "$pattern" >> "$GITIGNORE"
        echo "✅ Added '$pattern' to .gitignore"
    fi
done

# Remove any tracked zip files from git cache
git rm --cached triptracking-library/android/app/src/main/java/com/carmd/triptracking*.zip 2>/dev/null || true
git rm --cached triptracking-library/ios/Sources*.zip 2>/dev/null || true
git rm --cached triptracking-library/ios/Sources/triptracking.zip 2>/dev/null || true


echo ""
echo "📝 All files updated. Committing..."

# ── 10. Git: commit + tag + push ──
git add -A
git commit -m "v$VERSION — $MESSAGE"
git tag "$VERSION"
git push origin main
git push origin "$VERSION"

echo ""
echo "═══════════════════════════════════════════════════"
echo "✅ TripTracker v$VERSION released!"
echo ""
echo "GitHub Actions will build Android AAR automatically."
echo "Check: https://github.com/hieunguyentt/TripTracker/actions"
echo ""
echo "To update Ionic project:"
echo "  npm install \"github:hieunguyentt/TripTracker#$VERSION\""
echo "  npx cap sync"
echo "═══════════════════════════════════════════════════"
