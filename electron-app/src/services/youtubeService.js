/* ═══════════════════════════════════════════════════════════════════════════
   YouTubeService — Download subtitles from YouTube via yt-dlp
   ═══════════════════════════════════════════════════════════════════════════ */

class YouTubeService {
  constructor() {
    this.ytDlpPath = null;
  }

  async init() {
    this.ytDlpPath = await window.electronAPI.checkYtDlp();
    return this.ytDlpPath;
  }

  isAvailable() {
    return this.ytDlpPath !== null;
  }

  // Extract video info (title, available subtitles, duration)
  async getInfo(url) {
    const cmd = `"${this.ytDlpPath}" --skip-download --print-json "${url}"`;
    const output = await window.electronAPI.execYtDlp(cmd);
    return JSON.parse(output);
  }

  // List available subtitle languages
  async listSubtitles(url) {
    try {
      const cmd = `"${this.ytDlpPath}" --skip-download --print-json "${url}"`;
      const output = await window.electronAPI.execYtDlp(cmd);
      const info = JSON.parse(output);
      const subs = info.subtitles || {};
      const autoSubs = info.automatic_captions || {};
      const available = {};
      for (const [lang, tracks] of Object.entries(subs)) {
        available[lang] = tracks;
      }
      for (const [lang, tracks] of Object.entries(autoSubs)) {
        if (!available[lang]) available[lang] = tracks;
      }
      return { title: info.title, duration: info.duration, available, videoId: info.id };
    } catch (err) {
      throw new Error(`Failed to get video info: ${err.message}`);
    }
  }

  // Download subtitles as SRT
  async downloadSubtitles(url, lang = 'en') {
    const langArg = lang === 'auto' ? '--all-subs' : `--sub-langs ${lang}`;
    const tmpDir = `/tmp/yt-subs-${Date.now()}`;
    const cmd = `mkdir -p "${tmpDir}" && "${this.ytDlpPath}" --skip-download --write-subs --sub-format srt --convert-subs srt ${langArg} --output "${tmpDir}/%(title)s.%(ext)s" "${url}"`;

    await window.electronAPI.execYtDlp(cmd);

    // Find the generated SRT/TXT file
    const fs = requireNode('fs');
    const path = requireNode('path');
    // Try to read output
    const files = fs.readdirSync(tmpDir).filter(f => f.endsWith('.srt') || f.endsWith('.vtt') || f.endsWith('.txt'));
    let content = '';
    let title = '';

    for (const file of files) {
      content += fs.readFileSync(path.join(tmpDir, file), 'utf-8') + '\n\n';
      if (!title) title = file.replace(/\.\w+$/, '');
    }

    // Cleanup
    fs.rmSync(tmpDir, { recursive: true, force: true });

    if (!content) throw new Error('No subtitles found for this video.');
    return { content, title };
  }

  // Download audio and transcribe via Groq as fallback
  async downloadAudio(url, onProgress = () => {}) {
    onProgress({ percent: 10, text: 'Downloading audio...' });
    const tmpDir = `/tmp/yt-audio-${Date.now()}`;
    await window.electronAPI.execYtDlp(`mkdir -p "${tmpDir}"`);

    const cmd = `"${this.ytDlpPath}" -x --audio-format mp3 --audio-quality 0 --output "${tmpDir}/%(title)s.%(ext)s" "${url}"`;
    await window.electronAPI.execYtDlp(cmd);

    onProgress({ percent: 60, text: 'Audio downloaded. Transcribing...' });

    // Find the downloaded audio file
    const fs = requireNode('fs');
    const path = requireNode('path');
    const files = fs.readdirSync(tmpDir).filter(f => f.endsWith('.mp3'));
    if (files.length === 0) throw new Error('Failed to download audio.');

    const audioPath = path.join(tmpDir, files[0]);
    const title = files[0].replace(/\.mp3$/, '');

    return { audioPath, title, tmpDir };
  }
}

// Helper to access Node modules from renderer
function requireNode(module) {
  const { BrowserWindow } = require('@electron/remote');
  // We'll use IPC instead for file operations
  throw new Error('Use IPC for Node operations');
}

// We'll override the downloadSubtitles and downloadAudio to use IPC properly

// Override downloadSubtitles with IPC-safe version
YouTubeService.prototype.downloadSubtitles = async function(url, lang = 'en') {
  const langArg = lang === 'auto' ? '--all-subs' : `--sub-langs ${lang}`;
  const resultPath = `/tmp/yt-subs-${Date.now()}`;
  const cmd = `mkdir -p "${resultPath}" && "${this.ytDlpPath}" --skip-download --write-subs --sub-format srt --convert-subs srt ${langArg} --output "${resultPath}/%(title)s.%(ext)s" "${url}"`;

  await window.electronAPI.execYtDlp(cmd);

  // Read files using IPC
  const listCmd = `ls "${resultPath}"`;
  const listOutput = await window.electronAPI.execYtDlp(listCmd);
  const files = listOutput.trim().split('\n').filter(f => f.endsWith('.srt') || f.endsWith('.vtt') || f.endsWith('.txt'));

  let content = '';
  let title = 'Subtitles';

  for (const file of files) {
    const readCmd = `cat "${resultPath}/${file}"`;
    const fileContent = await window.electronAPI.execYtDlp(readCmd);
    content += fileContent + '\n\n';
    if (!title || title === 'Subtitles') title = file.replace(/\.\w+$/, '');
  }

  // Cleanup
  await window.electronAPI.execYtDlp(`rm -rf "${resultPath}"`);

  if (!content) throw new Error('No subtitles found for this video.');
  return { content, title };
};

// Override downloadAudio with IPC-safe version
YouTubeService.prototype.downloadAudio = async function(url, onProgress = () => {}) {
  onProgress({ percent: 10, text: 'Downloading audio...' });
  const resultPath = `/tmp/yt-audio-${Date.now()}`;
  await window.electronAPI.execYtDlp(`mkdir -p "${resultPath}"`);

  const cmd = `"${this.ytDlpPath}" -x --audio-format mp3 --audio-quality 0 --output "${resultPath}/%(title)s.%(ext)s" "${url}"`;
  await window.electronAPI.execYtDlp(cmd);

  onProgress({ percent: 60, text: 'Audio downloaded. Transcribing...' });

  const listCmd = `ls "${resultPath}"`;
  const listOutput = await window.electronAPI.execYtDlp(listCmd);
  const files = listOutput.trim().split('\n').filter(f => f.endsWith('.mp3') || f.endsWith('.m4a') || f.endsWith('.wav'));

  if (files.length === 0) throw new Error('Failed to download audio.');

  const audioFile = files[0];
  const audioPath = `${resultPath}/${audioFile}`;
  const title = audioFile.replace(/\.\w+$/, '');

  // Read the audio file
  onProgress({ percent: 70, text: 'Reading audio file...' });
  const size = await window.electronAPI.getFileSize(audioPath);
  const blob = await readAudioFileAsBlob(audioPath, size);

  // Cleanup temp dir
  await window.electronAPI.execYtDlp(`rm -rf "${resultPath}"`);

  return { blob, title, fileName: audioFile };
};

async function readAudioFileAsBlob(filePath, size) {
  const CHUNK = 4 * 1024 * 1024;
  const parts = [];
  let offset = 0;
  while (offset < size) {
    const len = Math.min(CHUNK, size - offset);
    const b64 = await window.electronAPI.readFileChunk(filePath, offset, len);
    const binary = atob(b64);
    const bytes = new Uint8Array(binary.length);
    for (let i = 0; i < binary.length; i++) bytes[i] = binary.charCodeAt(i);
    parts.push(bytes);
    offset += len;
  }
  const allBytes = new Uint8Array(size);
  let pos = 0;
  for (const part of parts) {
    allBytes.set(part, pos);
    pos += part.length;
  }
  return new Blob([allBytes], { type: 'audio/mpeg' });
}

window.youTubeService = new YouTubeService();
