# NoMoreType — Capacitor Mobile

> Android & iOS mobile wrapper for NoMoreType using Capacitor.

## Requirements

- **Node.js** 18+
- **Android Studio** (for Android build)
- **Xcode 16+** (for iOS build, macOS only)
- A **Groq API key** from https://console.groq.com

## Quick Start

```bash
npm install
npx cap sync          # Sync web code → native projects
npx cap serve         # Preview in browser
```

## Build & Run

### Android

```bash
npx cap open android
# Android Studio opens → Run on device/emulator
```

Or build APK directly:
```bash
cd android
./gradlew assembleDebug
# Output: android/app/build/outputs/apk/debug/app-debug.apk
```

### iOS

```bash
npx cap open ios
# Xcode opens → Select a simulator/device → Run
```

## Platform Notes

- **yt-dlp** not available on mobile (YouTube features disabled)
- File selection uses the web `<input type="file">` picker
- File saving uses Capacitor Filesystem + Share plugin
- All features use the shared `web-app/` source (one codebase for all platforms)
