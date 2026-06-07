/* ═══════════════════════════════════════════════════════════════════════════
   Recorder — Microphone audio recording via MediaRecorder API
   ═══════════════════════════════════════════════════════════════════════════ */

class MicRecorder {
  constructor() {
    this.mediaRecorder = null;
    this.audioChunks = [];
    this.stream = null;
    this.isRecording = false;
    this.startTime = null;
    this.timerInterval = null;
    this.analyserNode = null;
    this.dataArray = null;
    this.onLevelUpdate = null; // callback(level 0-1)
    this.onTimerUpdate = null;  // callback(formattedTime)
  }

  async requestPermission() {
    try {
      const stream = await navigator.mediaDevices.getUserMedia({ audio: true });
      // Stop immediately — we just wanted permission
      stream.getTracks().forEach(t => t.stop());
      return true;
    } catch (err) {
      if (err.name === 'NotAllowedError' || err.name === 'PermissionDeniedError') {
        throw new Error('Microphone permission denied. Please allow microphone access in your system settings.');
      }
      throw new Error(`Microphone error: ${err.message}`);
    }
  }

  async start() {
    if (this.isRecording) return;

    this.audioChunks = [];

    try {
      this.stream = await navigator.mediaDevices.getUserMedia({
        audio: {
          sampleRate: 44100,
          channelCount: 1,
          echoCancellation: true,
          noiseSuppression: true,
        }
      });
    } catch (err) {
      throw new Error(`Cannot access microphone: ${err.message}`);
    }

    // Set up audio level analysis
    try {
      const audioCtx = new AudioContext();
      const source = audioCtx.createMediaStreamSource(this.stream);
      this.analyserNode = audioCtx.createAnalyser();
      this.analyserNode.fftSize = 256;
      source.connect(this.analyserNode);
      this.dataArray = new Uint8Array(this.analyserNode.frequencyBinCount);
    } catch (e) {
      // AudioContext may not be available, level meter won't work
      this.analyserNode = null;
    }

    // Detect supported mime type
    const mimeType = this._getSupportedMimeType();
    this.mediaRecorder = new MediaRecorder(this.stream, mimeType ? { mimeType } : {});

    this.mediaRecorder.ondataavailable = (event) => {
      if (event.data.size > 0) {
        this.audioChunks.push(event.data);
      }
    };

    this.mediaRecorder.start(250); // collect data every 250ms
    this.isRecording = true;
    this.startTime = Date.now();

    // Start level monitoring
    this._startLevelMonitor();

    // Start timer
    this._startTimer();
  }

  stop() {
    return new Promise((resolve) => {
      if (!this.isRecording || !this.mediaRecorder) {
        resolve(null);
        return;
      }

      this.mediaRecorder.onstop = async () => {
        this.isRecording = false;
        this._stopTimer();
        this._stopLevelMonitor();

        const blob = new Blob(this.audioChunks, { type: this.mediaRecorder.mimeType || 'audio/mp4' });
        this.audioChunks = [];

        if (this.stream) {
          this.stream.getTracks().forEach(t => t.stop());
          this.stream = null;
        }

        resolve(blob);
      };

      this.mediaRecorder.stop();
    });
  }

  cancel() {
    if (this.mediaRecorder && this.mediaRecorder.state !== 'inactive') {
      this.mediaRecorder.onstop = null;
      this.mediaRecorder.stop();
    }
    this.isRecording = false;
    this._stopTimer();
    this._stopLevelMonitor();
    this.audioChunks = [];
    if (this.stream) {
      this.stream.getTracks().forEach(t => t.stop());
      this.stream = null;
    }
  }

  _getSupportedMimeType() {
    const types = [
      'audio/webm;codecs=opus',
      'audio/webm',
      'audio/ogg;codecs=opus',
      'audio/mp4',
    ];
    for (const type of types) {
      if (MediaRecorder.isTypeSupported(type)) return type;
    }
    return null;
  }

  _startLevelMonitor() {
    if (!this.analyserNode || !this.dataArray) return;

    const update = () => {
      if (!this.isRecording) return;
      this.analyserNode.getByteFrequencyData(this.dataArray);
      const avg = Array.from(this.dataArray).reduce((a, b) => a + b, 0) / this.dataArray.length;
      const level = Math.min(1, avg / 128);
      if (this.onLevelUpdate) this.onLevelUpdate(level);
      this._levelRAF = requestAnimationFrame(update);
    };
    this._levelRAF = requestAnimationFrame(update);
  }

  _stopLevelMonitor() {
    if (this._levelRAF) {
      cancelAnimationFrame(this._levelRAF);
      this._levelRAF = null;
    }
  }

  _startTimer() {
    this.timerInterval = setInterval(() => {
      if (!this.startTime) return;
      const elapsed = Math.floor((Date.now() - this.startTime) / 1000);
      const mins = String(Math.floor(elapsed / 60)).padStart(2, '0');
      const secs = String(elapsed % 60).padStart(2, '0');
      if (this.onTimerUpdate) this.onTimerUpdate(`${mins}:${secs}`);
    }, 200);
  }

  _stopTimer() {
    if (this.timerInterval) {
      clearInterval(this.timerInterval);
      this.timerInterval = null;
    }
  }
}

window.MicRecorder = MicRecorder;
