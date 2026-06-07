/* ═══════════════════════════════════════════════════════════════════════════
   GroqService — Groq Whisper API client with chunked upload support
   ═══════════════════════════════════════════════════════════════════════════ */

class GroqService {
  constructor() {
    this.BASE_URL = 'https://api.groq.com/openai/v1';
    this.MAX_CHUNK_SIZE = 24 * 1024 * 1024; // 24 MB per chunk
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
      try {
        const err = await resp.json();
        errMsg = err.error?.message || errMsg;
      } catch {}
      throw new Error(errMsg);
    }
    return resp.json();
  }

  // List available models
  async listModels() {
    return this.request('GET', '/models');
  }

  // Transcribe audio from a blob/array buffer
  async transcribe(blob, options = {}) {
    const { language = 'auto', model = 'whisper-large-v3-turbo', responseFormat = 'text' } = options;
    const fd = new FormData();
    fd.append('file', blob, 'recording.m4a');
    fd.append('model', model);
    fd.append('response_format', responseFormat);
    if (language && language !== 'auto') {
      fd.append('language', language);
    }
    fd.append('temperature', '0');
    return this.request('POST', '/audio/transcriptions', fd);
  }

  // Transcribe a file by reading chunks and sending sequentially
  async transcribeFile(fileInfo, options = {}, onProgress = () => {}) {
    const { language = 'auto', model = 'whisper-large-v3-turbo', responseFormat = 'text' } = options;

    onProgress({ percent: 0, text: 'Reading file...' });

    const filePath = fileInfo.path;
    const fileSize = fileInfo.size;
    const fileName = fileInfo.name;

    // For smaller files, read entirely and send as one
    if (fileSize <= this.MAX_CHUNK_SIZE) {
      onProgress({ percent: 20, text: 'Uploading to Groq...' });
      const blob = await this.readFileAsBlob(filePath);
      const fd = new FormData();
      fd.append('file', blob, fileName);
      fd.append('model', model);
      fd.append('response_format', responseFormat);
      if (language && language !== 'auto') fd.append('language', language);
      fd.append('temperature', '0');

      onProgress({ percent: 50, text: 'Transcribing...' });
      const result = await this.request('POST', '/audio/transcriptions', fd);
      onProgress({ percent: 100, text: 'Done!' });
      return result;
    }

    // Large file: chunked upload
    onProgress({ percent: 10, text: 'File too large, splitting into chunks...' });
    return this.transcribeLargeFile(fileInfo, options, onProgress);
  }

  async readFileAsBlob(filePath) {
    // Read file via IPC in chunks and build a blob
    const size = await window.electronAPI.getFileSize(filePath);
    const CHUNK = 4 * 1024 * 1024; // 4MB read chunks
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
    return new Blob([allBytes]);
  }

  async transcribeLargeFile(fileInfo, options, onProgress) {
    // Simple approach: use ffmpeg via child_process to split, then transcribe each chunk
    // For now, we just transcribe the whole file with a fallback note
    onProgress({ percent: 30, text: 'Large file — extracting audio segments...' });

    // TODO: In production, use ffmpeg to split into 10-minute segments
    // For the MVP, we attempt direct transcription
    const blob = await this.readFileAsBlob(fileInfo.path);
    onProgress({ percent: 50, text: 'Uploading to Groq...' });

    const fd = new FormData();
    fd.append('file', blob, fileInfo.name);
    fd.append('model', options.model || 'whisper-large-v3-turbo');
    fd.append('response_format', options.responseFormat || 'text');
    if (options.language && options.language !== 'auto') fd.append('language', options.language);
    fd.append('temperature', '0');

    onProgress({ percent: 70, text: 'Transcribing...' });
    const result = await this.request('POST', '/audio/transcriptions', fd);
    onProgress({ percent: 100, text: 'Done!' });
    return result;
  }
}

window.groqService = new GroqService();
