# Build Instructions

## Icon Tree-Shaking Issue

The Flutter build process may encounter an `IconTreeShakerException` when building the Android release APK. This occurs when the tree-shaking process tries to optimize the CupertinoIcons font but encounters a codepoint that doesn't exist in the font.

### Error Message
```
Font asset "CupertinoIcons.ttf" was tree-shaken, reducing it from 257628 to 16816 bytes (93.5% reduction). Tree-shaking can be disabled by providing the --no-tree-shake-icons flag when building your app.
Codepoint 57490 not found in font, aborting.
Target aot_android_asset_bundle failed: IconTreeShakerException: Font subsetting failed with exit code 255.
```

### Solution

Use the provided build script that automatically disables icon tree-shaking:

```bash
./build_release.sh
```

Or manually run the build command with the flag:

```bash
flutter build apk --release --no-tree-shake-icons
```

### Build Script

A convenience script `build_release.sh` is included in the project root:

- **Location**: `/build_release.sh`
- **Purpose**: Builds the release APK with disabled icon tree-shaking
- **Usage**: `./build_release.sh`

### Output

The built APK will be located at:
```
build/app/outputs/flutter-apk/app-release.apk
```

### Alternative Build Commands

For different build targets, use the same flag:

```bash
# Android APK
flutter build apk --release --no-tree-shake-icons

# Android App Bundle
flutter build appbundle --release --no-tree-shake-icons

# iOS (if needed)
flutter build ios --release --no-tree-shake-icons
```

### Note

Disabling icon tree-shaking will increase the APK size slightly (by including the full icon fonts), but it prevents the build failure and ensures all icons are available in the app.
