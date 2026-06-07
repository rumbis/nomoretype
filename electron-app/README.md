# NoMoreType — Electron (Cross-Platform)

> Open-source, cross-platform transcription app powered by the **Groq Whisper API**.  
> Transcribe audio/video files, record from your microphone, download YouTube subtitles, and polish transcripts — all from a beautiful desktop app.

Built with **Electron 35**, vanilla JavaScript, and the Web Audio API. Works on **macOS, Windows, and Linux**.

## Features

| Feature | Description |
|---------|-------------|
| **📁 File Transcription** | Upload audio/video files (MP3, M4A, WAV, FLAC, OGG, MP4, WebM) and transcribe via Groq Whisper |
| **🎙️ Mic Transcription** | Record from your microphone → transcribe → copy/save the result |
| **▶️ YouTube Subtitles** | Download subtitles directly from YouTube, or download audio & transcribe via Groq |
| **✨ Polish & Translate** | Fix grammar, translate, summarize, or re-punctuate transcripts using any OpenAI-compatible LLM |
| **📜 History** | All transcriptions saved locally with search, export, and detail view |
| **⚙️ Settings** | Configure Groq API key, LLM endpoint/model, auto-save preferences |
| **🌍 Multi-language** | 15+ languages with auto-detect for transcription |

## Requirements

- **Node.js** 18+
- **Groq API key** — free at [console.groq.com](https://console.groq.com)
- **yt-dlp** (optional, for YouTube subtitles) — `brew install yt-dlp` on macOS

## Quick Start

```bash
cd electron-app
npm install   # Already done — run if you pulled fresh
npm start     # Launch the app
```

## Build for Distribution

Build installers for your platform:

```bash
# macOS (DMG + ZIP, both Apple Silicon & Intel)
npm run build:mac

# Windows (NSIS installer + portable)
npm run build:win

# Linux (AppImage + DEB)
npm run build:linux

# All platforms
npm run build:all
```

Output goes to `electron-app/dist/`.

## Project Structure

```
electron-app/
├── package.json              # Dependencies & scripts
├── build.config.js           # electron-builder config
├── main.js                   # Electron main process
├── preload.js                # Secure IPC bridge
├── build/
│   └── entitlements.mac.plist  # macOS permissions
└── src/
    ├── index.html            # Main window (all tabs)
    ├── styles.css            # Dark theme CSS
    ├── renderer.js           # UI logic
    ├── recorder.js           # Microphone MediaRecorder
    └── services/
        ├── groqService.js    # Groq Whisper API client
        ├── llmService.js     # LLM polish/translate
        ├── youtubeService.js # yt-dlp integration
        └── historyStorage.js # localStorage history
```

## Architecture

- **Main Process** (`main.js`): File dialogs, file reading, yt-dlp execution via `child_process`, file save
- **Preload** (`preload.js`): Exposes a safe `window.electronAPI` bridge to the renderer
- **Renderer** (`src/`): Full single-page app with 6 tabs, local state via `localStorage`
- **Security**: `contextIsolation: true`, `nodeIntegration: false`, CSP headers

## Settings (saved in localStorage)

| Key | Default | Purpose |
|-----|---------|---------|
| `groq_api_key` | — | Groq API key for transcription |
| `llm_endpoint` | `https://api.groq.com/openai/v1` | LLM API endpoint |
| `llm_api_key` | (same as groq) | LLM API key |
| `llm_model` | `llama-3.3-70b-versatile` | LLM model for polish/translate |
| `save_history` | `true` | Auto-save transcriptions |

## Keyboard shortcuts

| Shortcut | Action |
|----------|--------|
| `Cmd/Ctrl+1-6` | Switch tabs |
| `Esc` | Close history modal |

## Why Electron?

The native macOS SwiftUI version has deeper OS integration (global hotkeys, auto-insert at cursor).  
This Electron version is **cross-platform** — the same code runs on Windows and Linux, making it suitable for open-source distribution to a wider audience.

## License

MIT — free to use, modify, and distribute.
