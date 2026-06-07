# NoMoreType — Multi-Platform

> Open-source transcription app powered by **Groq Whisper API**.  
> Transcribe audio/video files, record microphone, download YouTube subtitles, polish & translate transcripts.

## 📱 Platform Support

| Platform | Technology | Status | How to Run |
|----------|-----------|--------|------------|
| **🖥️ macOS** | Electron + SwiftUI | ✅ Done | `cd electron-app && npm start` |
| **🪟 Windows** | Electron | ✅ Done | `cd electron-app && npm start` |
| **🐧 Linux** | Electron | ✅ Done | `cd electron-app && npm start` |
| **🤖 Android** | Capacitor | ✅ Created | See `capacitor-app/README.md` |
| **🍎 iOS** | Capacitor | ✅ Created | See `capacitor-app/README.md` |
| **🌐 Web/PWA** | HTML/JS/CSS | ✅ Done | Open `web-app/` in any browser |

## 🗂️ Project Structure

```
transcription-mac-app/
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
│   ├── build.config.js         # electron-builder config
│   └── package.json
│
├── capacitor-app/              # 📱 MOBILE — Capacitor wrapper
│   ├── capacitor.config.json   # Points to ../web-app
│   ├── ios/                    # iOS Xcode project
│   ├── android/                # Android Studio project
│   └── package.json
│
└── README.md                   # ← You are here
```

## 🚀 Quick Start

### Desktop (macOS / Windows / Linux)

```bash
cd electron-app
npm install
npm start
```

Or build installers:
```bash
npm run build:mac      # DMG + ZIP
npm run build:win      # NSIS + portable
npm run build:linux    # AppImage + DEB
```

### Mobile (Android / iOS)

```bash
cd capacitor-app
npm install
npx cap sync           # Sync web code to native projects
npx cap open android   # Open in Android Studio
npx cap open ios       # Open in Xcode (macOS only)
```

### Web / PWA

Simply serve the `web-app/` folder with any HTTP server:

```bash
cd web-app
python3 -m http.server 8080
# Open http://localhost:8080 in any browser
```

Or open `index.html` directly (some features like mic need HTTPS).

## ✨ Features

| Feature | Desktop | Mobile | Web |
|---------|---------|--------|-----|
| File transcription (Groq) | ✅ | ✅ | ✅ |
| Mic recording & transcribe | ✅ | ✅ | ✅ |
| YouTube subtitles (yt-dlp) | ✅ | ❌ | ❌ |
| YouTube audio → transcribe | ✅ | ❌ | ❌ |
| LLM Polish & Translate | ✅ | ✅ | ✅ |
| History (localStorage) | ✅ | ✅ | ✅ |
| PWA installable | — | — | ✅ |
| Global hotkey | ✅* | ❌ | ❌ |

*\*macOS native SwiftUI version only*

## 🔑 Setup

1. Get a **Groq API key**: https://console.groq.com → API Keys
2. Open **Settings** tab → paste your key → click **Validate**
3. (Optional) LLM endpoint for Polish/Translate — defaults to Groq

## 🏗️ Architecture

The core logic lives in `web-app/` as vanilla HTML/JS/CSS.  
Each platform wraps this core with native capabilities:

- **Electron**: adds native file dialogs, `yt-dlp` execution, system file save
- **Capacitor**: adds native file system, share sheet, status bar control
- **PWA**: adds offline support, install prompt, fullscreen display

The `platform.js` file detects the runtime and provides a unified API for:
- File picking: native dialog (Electron) → `<input type="file">` (Web/Mobile)
- File saving: native save dialog (Electron) → download Blob (Web) → Capacitor FS (Mobile)
- Shell commands: `child_process` (Electron) → unavailable (Web/Mobile)

## 📄 License

MIT — free to use, modify, and distribute. Built by [Influro Academy](https://influro.com).
