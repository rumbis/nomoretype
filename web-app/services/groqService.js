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
    const contentType = resp.headers.get('content-type') || '';
    if (contentType.includes('json')) {
      return resp.json();
    }
    const text = await resp.text();
    return { text };
  }

  async listModels() {
    return this.request('GET', '/models');
  }

  // Convert verbose_json segments to SRT format
  _segmentsToSrt(segments) {
    if (!segments || !Array.isArray(segments)) return '';
    return segments.map((seg, i) => {
      const start = this._formatSrtTime(seg.start);
      const end = this._formatSrtTime(seg.end);
      return `${i + 1}\n${start} --> ${end}\n${seg.text.trim()}\n`;
    }).join('\n');
  }

  _formatSrtTime(seconds) {
    const h = Math.floor(seconds / 3600);
    const m = Math.floor((seconds % 3600) / 60);
    const s = Math.floor(seconds % 60);
    const ms = Math.floor((seconds - Math.floor(seconds)) * 1000);
    return `${String(h).padStart(2, '0')}:${String(m).padStart(2, '0')}:${String(s).padStart(2, '0')},${String(ms).padStart(3, '0')}`;
  }

  // Normalize response_format for Groq API (only supports: json, text, verbose_json)
  _normalizeFormat(format) {
    switch (format) {
      case 'segments': return 'verbose_json';
      case 'srt': return 'verbose_json'; // Groq doesn't support srt — we'll convert from segments
      case 'text': return 'text';
      case 'json': return 'json';
      default: return format;
    }
  }

  // Post-process the API result based on requested format
  _postProcess(result, requestedFormat) {
    if (requestedFormat === 'srt' && result.segments) {
      return { text: this._segmentsToSrt(result.segments), language: result.language, duration: result.duration, segments: result.segments };
    }
    if (requestedFormat === 'segments') {
      return result; // verbose_json already has segments, text, etc.
    }
    return result;
  }

  // Transcribe from a Blob
  async transcribe(blob, options = {}) {
    const { language = 'auto', model = 'whisper-large-v3-turbo', responseFormat = 'text' } = options;
    const apiFormat = this._normalizeFormat(responseFormat);
    const fd = new FormData();
    fd.append('file', blob, 'recording.m4a');
    fd.append('model', model);
    fd.append('response_format', apiFormat);
    if (language && language !== 'auto') fd.append('language', language);
    fd.append('temperature', '0');
    const result = await this.request('POST', '/audio/transcriptions', fd);
    return this._postProcess(result, responseFormat);
  }

  // Transcribe a file
  async transcribeFile(fileInfo, options = {}, onProgress = () => {}) {
    const { language = 'auto', model = 'whisper-large-v3-turbo', responseFormat = 'text' } = options;

    onProgress({ percent: 0, text: 'Reading file...' });

    let blob;
    try {
      blob = await window.Platform.readFileAsBlob(fileInfo);
    } catch (err) {
      if (fileInfo.blob) { blob = fileInfo.blob; }
      else { throw new Error(`Cannot read file: ${err.message}`); }
    }

    onProgress({ percent: 20, text: 'Uploading to Groq...' });

    const apiFormat = this._normalizeFormat(responseFormat);
    const fd = new FormData();
    fd.append('file', blob, fileInfo.name);
    fd.append('model', model);
    fd.append('response_format', apiFormat);
    if (language && language !== 'auto') fd.append('language', language);
    fd.append('temperature', '0');

    onProgress({ percent: 60, text: 'Transcribing...' });
    const result = await this.request('POST', '/audio/transcriptions', fd);
    onProgress({ percent: 100, text: 'Done!' });
    return this._postProcess(result, responseFormat);
  }
}

window.groqService = new GroqService();
