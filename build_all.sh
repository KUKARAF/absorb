#!/bin/bash
echo "Building GitHub APK..."
flutter build apk --release --flavor github --dart-define=GITHUB_BUILD=true "$@" || exit 1
echo ""
echo "Building Play Store AAB..."
flutter build appbundle --release --flavor playstore --dart-define=PLAYSTORE_BUILD=true "$@" || exit 1
echo ""
echo "Both builds complete!"
explorer "build\\app\\outputs\\apk\\github\\release"
explorer "build\\app\\outputs\\bundle\\playstoreRelease"
