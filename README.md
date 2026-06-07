# NoMoreType

> **Stop typing. Start transcribing.**  
> A free, open-source, cross-platform transcription app powered by **Groq Whisper API**.  
> Transcribe audio/video files, record microphone, download YouTube subtitles, polish & translate transcripts.

## ⌨️ Keyboard Shortcuts

| Shortcut | Action | Scope |
|----------|--------|-------|
| **Double-tap** `Left Ctrl` | Open app + start recording | 🌍 Global* |
| **Single-tap** `Left Ctrl` | Stop → Transcribe → Auto-insert at cursor | 🌍 Global* |
| `⌘`+`⇧`+`R` / `F6` | Toggle recording (fallback) | 🌍 Global |
| `⌘`/`Ctrl`+`1`–`6` | Switch tabs | In-app |

*\*Requires Accessibility permission.*

## 📱 Platform Support

| Platform | Technology | Installer | Status |
|----------|-----------|-----------|--------|
| 🖥️ **macOS** Apple Silicon | Electron | DMG (ARM64) | ✅ |
| 🖥️ **macOS** Intel | Electron | DMG (x64) | ✅ |
| 🪟 **Windows** | Electron | NSIS / Portable | ✅ |
| 🐧 **Linux** | Electron | AppImage / DEB | ✅ |
| 🤖 **Android** | Capacitor | APK | ✅ Build from source |
| 🍎 **iOS** | Capacitor | IPA | ✅ Build from source |
| 🌐 **Web / PWA** | Vanilla JS | Installable | ✅ |

## 🗂️ Project Structure

```
nomoretype/
├── Sources/                    # Native macOS SwiftUI app (original)
│   └── NoMoreType/
├── Resources/                  # Swift app resources
├── Makefile                    # Swift build
├── Package.swift               # SwiftPM config
│
├── web-app/                    # 🌐 SHARED — Cross-platform web source
│   ├── index.html              # Main UI (6 tabs)
│   ├── styles.css              # Dark theme (all platforms)
│   ├── app.js                  # Platform-agnostic UI logic
│   ├── recorder.js             # Microphone recording (Web Audio)
│   ├── manifest.json           # PWA install manifest
│   ├── sw.js                   # Service worker (offline)
│   └── services/
│       ├── platform.js         # 🔌 Platform abstraction layer
│       ├── capacitor-bridge.js # Capacitor native plugin bridge
│       ├── groqService.js      # Groq Whisper API
│       ├── llmService.js       # LLM polish/translate
│       ├── youtubeService.js   # YouTube subtitles
│       └── historyStorage.js   # Local history
│
├── electron-app/               # 🖥️ DESKTOP — Electron wrapper
│   ├── main.js                 # Electron main process
│   ├── preload.js              # IPC bridge (file dialogs, shell)
│   ├── hotkey-helper/          # Swift CGEventTap daemon (macOS)
│   ├── build.config.js         # electron-builder config
│   └── package.json
│
├── capacitor-app/              # 📱 MOBILE — Capacitor wrapper
│   ├── capacitor.config.json   # Points to ../web-app
│   ├── ios/                    # iOS Xcode project
│   ├── android/                # Android Studio project
│   └── package.json
│
├── website/                    # 🌍 Landing page + docs + download
│
└── README.md                   # ← You are here
```

## 🚀 Quick Start

```bash
# Desktop (macOS / Windows / Linux)
cd electron-app && npm install && npm start

# Build installers
npm run build:mac      # DMG + ZIP
npm run build:win      # NSIS + portable
npm run build:linux    # AppImage + DEB

# Mobile (Android / iOS)
cd capacitor-app && npm install && npx cap sync
npx cap open android   # Android Studio
npx cap open ios       # Xcode (macOS only)

# Web / PWA
cd web-app && python3 -m http.server 8080
```

## ✨ Features

| Feature | Desktop | Mobile | Web |
|---------|---------|--------|-----|
| 📁 File Transcription (Text / SRT / Segments) | ✅ | ✅ | ✅ |
| 🎙️ Mic recording & transcribe | ✅ | ✅ | ✅ |
| 🎙️ Mic → auto-insert at cursor | ✅ | ❌ | ❌ |
| ▶️ YouTube subtitles (yt-dlp) | ✅ | ❌ | ❌ |
| ▶️ YouTube audio → transcribe (Groq) | ✅ | ❌ | ❌ |
| ✨ LLM Polish & Translate | ✅ | ✅ | ✅ |
| 📜 History (localStorage) | ✅ | ✅ | ✅ |
| ⌨️ Global hotkey (Left Ctrl) | ✅ | ❌ | ❌ |
| 🌐 PWA installable | — | — | ✅ |

## 🔑 Setup

1. Get a **Groq API key**: https://console.groq.com → API Keys (free, starts with `gsk_`)
2. Open **Settings** tab → paste your key → click **Validate**
3. (Optional) LLM endpoint for Polish/Translate — defaults to Groq

## 🏗️ Architecture

The core logic lives in `web-app/` as vanilla HTML/JS/CSS. Each platform wraps this core with native capabilities:

- **Electron**: native file dialogs, `yt-dlp` execution, global hotkey (Swift CGEventTap), auto-insert at cursor
- **Capacitor**: native file system, share sheet, status bar control
- **PWA**: service worker offline cache, install prompt

The `platform.js` file detects the runtime and provides a unified API for:
- File picking: native dialog (Electron) → `<input type="file">` (Web/Mobile)
- File saving: native save dialog (Electron) → Blob download (Web) → Capacitor FS (Mobile)
- Shell commands: `child_process` (Electron) → unavailable (Web/Mobile)

## 📄 License

**MIT** — free to use, modify, and distribute. Built by [CodeitLab](https://codeitlab.com).
