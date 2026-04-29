#!/bin/bash

# Build script for Flutter app with disabled icon tree-shaking
# This prevents the IconTreeShakerException during build

echo "Building Flutter app with disabled icon tree-shaking..."
flutter build apk --release --no-tree-shake-icons

if [ $? -eq 0 ]; then
    echo "✅ Build completed successfully!"
    echo "📱 APK location: build/app/outputs/flutter-apk/app-release.apk"
else
    echo "❌ Build failed!"
    exit 1
fi
