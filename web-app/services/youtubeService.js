/* ═══════════════════════════════════════════════════════════════════════════
   YouTubeService — Download subtitles / transcribe YouTube videos
   Platform-agnostic: works with Electron (yt-dlp) or falls back gracefully
   ═══════════════════════════════════════════════════════════════════════════ */

class YouTubeService {
  constructor() {
    this.ytDlpPath = null;
  }

  async init() {
    try {
      this.ytDlpPath = await window.Platform.checkYtDlp();
    } catch {
      this.ytDlpPath = null;
    }
    return this.ytDlpPath;
  }

  isAvailable() {
    return this.ytDlpPath !== null;
  }

  async exec(cmd) {
    return window.Platform.execCommand(cmd);
  }

  // Download subtitles as SRT
  async downloadSubtitles(url, lang = 'en') {
    const langArg = lang === 'auto' ? '--all-subs' : `--sub-langs ${lang}`;
    const resultPath = `/tmp/yt-subs-${Date.now()}`;
    const cmd = `mkdir -p "${resultPath}" && "${this.ytDlpPath}" --skip-download --write-subs --sub-format srt --convert-subs srt ${langArg} --output "${resultPath}/%(title)s.%(ext)s" "${url}"`;

    await this.exec(cmd);

    // List downloaded files
    const listCmd = `ls "${resultPath}"`;
    const listOutput = await this.exec(listCmd);
    const files = listOutput.trim().split('\n').filter(f => f.endsWith('.srt') || f.endsWith('.vtt') || f.endsWith('.txt'));

    let content = '';
    let title = 'Subtitles';

    for (const file of files) {
      const readCmd = `cat "${resultPath}/${file}"`;
      const fileContent = await this.exec(readCmd);
      content += fileContent + '\n\n';
      if (!title || title === 'Subtitles') title = file.replace(/\.\w+$/, '');
    }

    // Cleanup
    await this.exec(`rm -rf "${resultPath}"`);

    if (!content) throw new Error('No subtitles found for this video.');
    return { content, title };
  }

  // Download audio and transcribe via Groq
  async downloadAudio(url, onProgress = () => {}) {
    onProgress({ percent: 10, text: 'Downloading audio...' });
    const resultPath = `/tmp/yt-audio-${Date.now()}`;
    await this.exec(`mkdir -p "${resultPath}"`);

    const cmd = `"${this.ytDlpPath}" -x --audio-format mp3 --audio-quality 0 --output "${resultPath}/%(title)s.%(ext)s" "${url}"`;
    await this.exec(cmd);

    onProgress({ percent: 60, text: 'Audio downloaded. Transcribing...' });

    const listCmd = `ls "${resultPath}"`;
    const listOutput = await this.exec(listCmd);
    const files = listOutput.trim().split('\n').filter(f => f.endsWith('.mp3') || f.endsWith('.m4a') || f.endsWith('.wav'));

    if (files.length === 0) throw new Error('Failed to download audio.');

    const audioFile = files[0];
    const audioPath = `${resultPath}/${audioFile}`;
    const title = audioFile.replace(/\.\w+$/, '');

    onProgress({ percent: 70, text: 'Reading audio file...' });

    // Read file via platform bridge
    const blob = await this._readAudioFile(audioPath);
    await this.exec(`rm -rf "${resultPath}"`);

    return { blob, title, fileName: audioFile };
  }

  async _readAudioFile(filePath) {
    const size = await window.electronAPI.getFileSize(filePath);
    const CHUNK = 4 * 1024 * 1024;
    const parts = [];
    let offset = 0;
    while (offset < size) {
      const len = Math.min(CHUNK, size - offset);
      const b64 = await window.electronAPI.readFileChunk(filePath, offset, len);
      const bin = atob(b64);
      const bytes = new Uint8Array(bin.length);
      for (let i = 0; i < bin.length; i++) bytes[i] = bin.charCodeAt(i);
      parts.push(bytes);
      offset += len;
    }
    const all = new Uint8Array(size);
    let pos = 0;
    for (const p of parts) { all.set(p, pos); pos += p.length; }
    return new Blob([all], { type: 'audio/mpeg' });
  }
}

window.youTubeService = new YouTubeService();
