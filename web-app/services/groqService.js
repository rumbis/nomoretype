/* ═══════════════════════════════════════════════════════════════════════════
   GroqService — Groq Whisper API client (platform-agnostic)
   ═══════════════════════════════════════════════════════════════════════════ */

class GroqService {
  constructor() {
    this.BASE_URL = 'https://api.groq.com/openai/v1';
    this.MAX_CHUNK_SIZE = 24 * 1024 * 1024;
  }

  getApiKey() {
    return localStorage.getItem('groq_api_key') || '';
  }

  async request(method, path, body) {
    const key = this.getApiKey();
    if (!key) throw new Error('Groq API key not set. Go to Settings → paste your key.');
    const url = `${this.BASE_URL}${path}`;
    const options = {
      method,
      headers: { 'Authorization': `Bearer ${key}` },
    };
    if (body instanceof FormData) {
      options.body = body;
    } else {
      options.headers['Content-Type'] = 'application/json';
      options.body = JSON.stringify(body);
    }
    const resp = await fetch(url, options);
    if (!resp.ok) {
      let errMsg = `HTTP ${resp.status}`;
      try { const err = await resp.json(); errMsg = err.error?.message || errMsg; } catch {}
      throw new Error(errMsg);
    }
    return resp.json();
  }

  async listModels() {
    return this.request('GET', '/models');
  }

  // Transcribe from a Blob (mic recording, downloaded YouTube audio, etc.)
  async transcribe(blob, options = {}) {
    const { language = 'auto', model = 'whisper-large-v3-turbo', responseFormat = 'text' } = options;
    const fd = new FormData();
    fd.append('file', blob, 'recording.m4a');
    fd.append('model', model);
    fd.append('response_format', responseFormat);
    if (language && language !== 'auto') fd.append('language', language);
    fd.append('temperature', '0');
    return this.request('POST', '/audio/transcriptions', fd);
  }

  // Transcribe a file selected via file picker
  async transcribeFile(fileInfo, options = {}, onProgress = () => {}) {
    const { language = 'auto', model = 'whisper-large-v3-turbo', responseFormat = 'text' } = options;

    onProgress({ percent: 0, text: 'Reading file...' });

    // Get the file as a Blob (works across all platforms)
    let blob;
    try {
      blob = await window.Platform.readFileAsBlob(fileInfo);
    } catch (err) {
      // Fallback: if fileInfo already has a blob
      if (fileInfo.blob) {
        blob = fileInfo.blob;
      } else {
        throw new Error(`Cannot read file: ${err.message}`);
      }
    }

    onProgress({ percent: 20, text: 'Uploading to Groq...' });

    const fd = new FormData();
    fd.append('file', blob, fileInfo.name);
    fd.append('model', model);
    fd.append('response_format', responseFormat);
    if (language && language !== 'auto') fd.append('language', language);
    fd.append('temperature', '0');

    onProgress({ percent: 60, text: 'Transcribing...' });
    const result = await this.request('POST', '/audio/transcriptions', fd);
    onProgress({ percent: 100, text: 'Done!' });
    return result;
  }
}

window.groqService = new GroqService();
