/* ═══════════════════════════════════════════════════════════════════════════
   App — Main UI logic for NoMoreType (platform-agnostic)
   Works in: Electron, Capacitor (iOS/Android), Web/PWA
   ═══════════════════════════════════════════════════════════════════════════ */

'use strict';

const $ = id => document.getElementById(id);

// ─── Init ───────────────────────────────────────────────────────────

document.addEventListener('DOMContentLoaded', async () => {
  initNavigation();
  initFileTab();
  initMicTab();
  initYouTubeTab();
  initPolishTab();
  initHistoryTab();
  initSettingsTab();
  initPWA();

  startYouTubeService();
  if (window._loadSettings) window._loadSettings();
});

// ─── Navigation ────────────────────────────────────────────────────

function initNavigation() {
  const tabs = document.querySelectorAll('.nav-tab');
  tabs.forEach(tab => {
    tab.addEventListener('click', () => {
      const tabName = tab.dataset.tab;
      tabs.forEach(t => t.classList.remove('active'));
      tab.classList.add('active');
      document.querySelectorAll('.tab-content').forEach(c => c.classList.remove('active'));
      const target = document.getElementById(`tab-${tabName}`);
      if (target) target.classList.add('active');
      if (tabName === 'history' && window._refreshHistory) window._refreshHistory();
    });
  });
}

// ─── PWA / Install Prompt ──────────────────────────────────────────

function initPWA() {
  // Register service worker for PWA
  if ('serviceWorker' in navigator && !window.Platform.isElectron) {
    navigator.serviceWorker.register('sw.js').catch(() => {});
  }

  // Install prompt
  let deferredPrompt = null;
  window.addEventListener('beforeinstallprompt', (e) => {
    e.preventDefault();
    deferredPrompt = e;
    const btn = document.getElementById('installBtn');
    if (btn) btn.style.display = 'flex';
  });

  const installBtn = document.getElementById('installBtn');
  if (installBtn) {
    installBtn.addEventListener('click', async () => {
      if (deferredPrompt) {
        deferredPrompt.prompt();
        const result = await deferredPrompt.userChoice;
        if (result.outcome === 'accepted') installBtn.style.display = 'none';
        deferredPrompt = null;
      }
    });
  }
}

// ─── Toast ──────────────────────────────────────────────────────────

function showToast(message, type = 'success', duration = 3000) {
  const toast = $('toast');
  if (!toast) return;
  toast.textContent = message;
  toast.className = `toast ${type}`;
  toast.style.display = 'block';
  clearTimeout(toast._hideTimeout);
  toast._hideTimeout = setTimeout(() => { toast.style.display = 'none'; }, duration);
}

// ─── Utility ───────────────────────────────────────────────────────

function formatFileSize(bytes) {
  if (!bytes) return '—';
  if (bytes < 1024) return `${bytes} B`;
  if (bytes < 1024 * 1024) return `${(bytes / 1024).toFixed(1)} KB`;
  return `${(bytes / (1024 * 1024)).toFixed(1)} MB`;
}

function formatDate(iso) {
  const d = new Date(iso);
  return d.toLocaleDateString() + ' ' + d.toLocaleTimeString([], { hour: '2-digit', minute: '2-digit' });
}

function getSavingHistory() {
  return localStorage.getItem('save_history') !== 'false';
}

// ─── ═══════════════════════════════════════════════════════════════
//   FILE TRANSCRIBE TAB
// ─── ═══════════════════════════════════════════════════════════════

function initFileTab() {
  const dropZone = $('fileDropArea');
  const fileSelected = $('fileSelected');
  const fileName = $('fileName');
  const fileSize = $('fileSize');
  const changeBtn = $('fileChangeBtn');
  const transcribeBtn = $('fileTranscribeBtn');
  const progressSection = $('fileProgress');
  const progressFill = $('fileProgressFill');
  const progressText = $('fileProgressText');
  const resultSection = $('fileResult');
  const resultText = $('fileResultText');
  const resultInfo = $('fileResultInfo');
  const copyBtn = $('fileCopyBtn');
  const saveBtn = $('fileSaveBtn');
  const language = $('fileLanguage');
  const model = $('fileModel');
  const output = $('fileOutput');

  let selectedFile = null;

  dropZone.addEventListener('click', selectFile);
  changeBtn.addEventListener('click', selectFile);

  async function selectFile() {
    const fileInfo = await window.Platform.pickFile();
    if (!fileInfo) return;
    selectedFile = fileInfo;
    dropZone.style.display = 'none';
    fileSelected.style.display = 'flex';
    fileName.textContent = fileInfo.name;
    fileSize.textContent = formatFileSize(fileInfo.size);
    transcribeBtn.disabled = false;
  }

  // Drag & drop
  dropZone.addEventListener('dragover', (e) => { e.preventDefault(); dropZone.classList.add('drag-over'); });
  dropZone.addEventListener('dragleave', () => { dropZone.classList.remove('drag-over'); });
  dropZone.addEventListener('drop', async (e) => {
    e.preventDefault();
    dropZone.classList.remove('drag-over');
    const files = e.dataTransfer?.files;
    if (files?.length > 0) {
      const f = files[0];
      selectedFile = { name: f.name, size: f.size, blob: f, _file: f };
      dropZone.style.display = 'none';
      fileSelected.style.display = 'flex';
      fileName.textContent = f.name;
      fileSize.textContent = formatFileSize(f.size);
      transcribeBtn.disabled = false;
    }
  });

  transcribeBtn.addEventListener('click', async () => {
    if (!selectedFile) return;
    progressSection.style.display = 'block';
    resultSection.style.display = 'none';
    transcribeBtn.disabled = true;

    try {
      const result = await window.groqService.transcribeFile(selectedFile, {
        language: language.value,
        model: model.value,
        responseFormat: output.value,
      }, (progress) => {
        progressFill.style.width = `${progress.percent}%`;
        progressText.textContent = progress.text;
      });

      let text = '';
      let extraInfo = '';
      if (output.value === 'text') {
        text = result.text || '';
        extraInfo = `Duration: ${result.duration || '—'}s | Language: ${result.language || 'auto'}`;
      } else if (output.value === 'srt') {
        text = result.text || '';
        extraInfo = 'SRT subtitle format';
      } else if (output.value === 'segments') {
        text = JSON.stringify(result.segments || result, null, 2);
        extraInfo = 'JSON segments output';
      }

      resultText.textContent = text || '(empty transcription)';
      resultInfo.textContent = extraInfo;
      resultInfo.style.display = extraInfo ? 'block' : 'none';
      resultSection.style.display = 'block';

      if (getSavingHistory()) {
        window.historyStorage.add({
          type: 'file',
          title: selectedFile.name,
          text,
          model: model.value,
          language: language.value,
          duration: result.duration || null,
        });
      }
      showToast('Transcription complete!');
    } catch (err) {
      showToast(err.message, 'error', 5000);
    } finally {
      transcribeBtn.disabled = false;
      progressSection.style.display = 'none';
    }
  });

  copyBtn.addEventListener('click', () => {
    window.Platform.copyToClipboard(resultText.textContent).then(() => showToast('Copied!'));
  });

  saveBtn.addEventListener('click', async () => {
    const ext = output.value === 'srt' ? 'srt' : 'txt';
    const defaultName = (selectedFile ? selectedFile.name.replace(/\.[^.]+$/, '') : 'transcript') + `_transcript.${ext}`;
    const saved = await window.Platform.saveFile(resultText.textContent, defaultName);
    if (saved) showToast('Saved!');
  });
}

// ─── ═══════════════════════════════════════════════════════════════
//   MIC TAB
// ─── ═══════════════════════════════════════════════════════════════

function initMicTab() {
  const recordBtn = $('micRecordBtn');
  const btnIcon = $('micBtnIcon');
  const btnText = $('micBtnText');
  const micIcon = $('micIcon');
  const micStatus = $('micStatus');
  const micTimer = $('micTimer');
  const micLevel = $('micLevel');
  const levelFill = $('levelFill');
  const progressSection = $('micProgress');
  const progressFill = $('micProgressFill');
  const progressText = $('micProgressText');
  const resultSection = $('micResult');
  const resultText = $('micResultText');
  const copyBtn = $('micCopyBtn');
  const saveBtn = $('micSaveBtn');
  const language = $('micLanguage');
  const model = $('micModel');

  const recorder = new MicRecorder();
  let isRecording = false;

  recorder.onLevelUpdate = (level) => {
    levelFill.style.width = `${Math.min(100, level * 100)}%`;
  };
  recorder.onTimerUpdate = (time) => {
    micTimer.textContent = time;
  };

  recordBtn.addEventListener('click', async () => {
    if (!isRecording) {
      try {
        await recorder.start();
        isRecording = true;
        btnIcon.textContent = '⏹';
        btnText.textContent = 'Stop Recording';
        micIcon.className = 'mic-icon recording';
        micStatus.textContent = 'Recording…';
        micTimer.style.display = 'block';
        micTimer.textContent = '00:00';
        micLevel.style.display = 'block';
        recordBtn.style.background = '#ef4444';
        recordBtn.style.color = '#fff';
        resultSection.style.display = 'none';
      } catch (err) {
        showToast(err.message, 'error', 5000);
      }
    } else {
      recordBtn.disabled = true;
      btnText.textContent = 'Transcribing…';
      try {
        const blob = await recorder.stop();
        isRecording = false;
        micIcon.className = 'mic-icon';
        micStatus.textContent = 'Processing…';
        recordBtn.style.background = '';
        recordBtn.style.color = '';

        if (!blob) { showToast('No audio recorded', 'warning'); resetMicUI(); return; }

        progressSection.style.display = 'block';
        progressFill.style.width = '50%';
        progressText.textContent = 'Transcribing…';

        const result = await window.groqService.transcribe(blob, {
          language: language.value, model: model.value, responseFormat: 'text',
        });

        progressFill.style.width = '100%';
        progressText.textContent = 'Done!';

        resultText.textContent = result.text || '(empty transcription)';
        resultSection.style.display = 'block';

        if (getSavingHistory()) {
          window.historyStorage.add({
            type: 'mic', title: 'Microphone Recording',
            text: result.text, model: model.value, language: language.value,
            duration: Math.floor((Date.now() - recorder.startTime) / 1000),
          });
        }
        showToast('Transcription complete!');
      } catch (err) {
        showToast(err.message, 'error', 5000);
        recorder.cancel();
      } finally {
        resetMicUI();
        progressSection.style.display = 'none';
      }
    }
  });

  function resetMicUI() {
    isRecording = false;
    btnIcon.textContent = '⏺';
    btnText.textContent = 'Start Recording';
    micIcon.className = 'mic-icon';
    micStatus.textContent = 'Ready to record';
    micTimer.style.display = 'none';
    micLevel.style.display = 'none';
    recordBtn.disabled = false;
    recordBtn.style.background = '';
    recordBtn.style.color = '';
  }

  copyBtn.addEventListener('click', () => {
    window.Platform.copyToClipboard(resultText.textContent).then(() => showToast('Copied!'));
  });
  saveBtn.addEventListener('click', async () => {
    const saved = await window.Platform.saveFile(resultText.textContent, 'mic_transcript.txt');
    if (saved) showToast('Saved!');
  });
}

// ─── ═══════════════════════════════════════════════════════════════
//   YOUTUBE TAB
// ─── ═══════════════════════════════════════════════════════════════

function initYouTubeTab() {
  const urlInput = $('ytUrl');
  const lang = $('ytLanguage');
  const model = $('ytModel');
  const getSubsBtn = $('ytGetSubsBtn');
  const transcribeBtn = $('ytTranscribeBtn');
  const progressSection = $('ytProgress');
  const progressFill = $('ytProgressFill');
  const progressText = $('ytProgressText');
  const resultSection = $('ytResult');
  const resultText = $('ytResultText');
  const copyBtn = $('ytCopyBtn');
  const saveBtn = $('ytSaveBtn');

  // Platform notice
  const platformNotice = document.createElement('div');
  platformNotice.className = 'platform-notice';

  getSubsBtn.addEventListener('click', async () => {
    const url = urlInput.value.trim();
    if (!url) { showToast('Please enter a YouTube URL', 'warning'); return; }

    if (!window.youTubeService.isAvailable()) {
      showToast('yt-dlp not detected. YouTube features require yt-dlp (desktop only).', 'warning', 5000);
      return;
    }

    progressSection.style.display = 'block';
    resultSection.style.display = 'none';
    getSubsBtn.disabled = true;
    transcribeBtn.disabled = true;

    try {
      progressText.textContent = 'Fetching subtitles…';
      progressFill.style.width = '30%';
      const result = await window.youTubeService.downloadSubtitles(url, lang.value);
      progressFill.style.width = '80%';
      progressText.textContent = 'Processing…';
      resultText.textContent = result.content;
      resultSection.style.display = 'block';
      progressFill.style.width = '100%';
      progressText.textContent = 'Done!';
      if (getSavingHistory()) {
        window.historyStorage.add({ type: 'youtube', title: result.title || url, text: result.content, model: 'yt-dlp' });
      }
      showToast('Subtitles downloaded!');
    } catch (err) {
      showToast(err.message, 'error', 5000);
    } finally {
      getSubsBtn.disabled = false;
      transcribeBtn.disabled = false;
      progressSection.style.display = 'none';
    }
  });

  transcribeBtn.addEventListener('click', async () => {
    const url = urlInput.value.trim();
    if (!url) { showToast('Please enter a YouTube URL', 'warning'); return; }
    if (!window.youTubeService.isAvailable()) {
      showToast('yt-dlp not detected. YouTube features require yt-dlp (desktop only).', 'warning', 5000);
      return;
    }

    progressSection.style.display = 'block';
    resultSection.style.display = 'none';
    getSubsBtn.disabled = true;
    transcribeBtn.disabled = true;

    try {
      progressText.textContent = 'Downloading audio…';
      progressFill.style.width = '10%';
      const { blob, title } = await window.youTubeService.downloadAudio(url, (p) => {
        progressFill.style.width = `${p.percent}%`; progressText.textContent = p.text;
      });
      progressText.textContent = 'Transcribing…';
      progressFill.style.width = '80%';
      const result = await window.groqService.transcribe(blob, {
        language: lang.value === 'auto' ? 'auto' : lang.value,
        model: model.value, responseFormat: 'text',
      });
      progressFill.style.width = '100%';
      progressText.textContent = 'Done!';
      resultText.textContent = result.text || '(empty transcription)';
      resultSection.style.display = 'block';
      if (getSavingHistory()) {
        window.historyStorage.add({ type: 'youtube', title: title || url, text: result.text, model: model.value });
      }
      showToast('Transcription complete!');
    } catch (err) {
      showToast(err.message, 'error', 5000);
    } finally {
      getSubsBtn.disabled = false;
      transcribeBtn.disabled = false;
      progressSection.style.display = 'none';
    }
  });

  copyBtn.addEventListener('click', () => {
    window.Platform.copyToClipboard(resultText.textContent).then(() => showToast('Copied!'));
  });
  saveBtn.addEventListener('click', async () => {
    const saved = await window.Platform.saveFile(resultText.textContent, 'youtube_transcript.txt');
    if (saved) showToast('Saved!');
  });
}

async function startYouTubeService() {
  await window.youTubeService.init();
}

// ─── ═══════════════════════════════════════════════════════════════
//   POLISH & TRANSLATE TAB
// ─── ═══════════════════════════════════════════════════════════════

function initPolishTab() {
  const input = $('polishInput');
  const mode = $('polishMode');
  const targetLangGroup = $('translateLangGroup');
  const targetLang = $('polishTargetLang');
  const processBtn = $('polishBtn');
  const resultSection = $('polishResult');
  const resultText = $('polishResultText');
  const copyBtn = $('polishCopyBtn');
  const replaceBtn = $('polishReplaceBtn');

  mode.addEventListener('change', () => {
    targetLangGroup.style.display = mode.value === 'translate' ? 'block' : 'none';
  });

  processBtn.addEventListener('click', async () => {
    const text = input.value.trim();
    if (!text) { showToast('Please enter text to process', 'warning'); return; }
    processBtn.disabled = true;
    resultSection.style.display = 'none';

    try {
      const result = await window.llmService.process(text, mode.value, targetLang.value);
      resultText.textContent = result;
      resultSection.style.display = 'block';
      showToast(`${mode.options[mode.selectedIndex].text} complete!`);
    } catch (err) {
      showToast(err.message, 'error', 5000);
    } finally {
      processBtn.disabled = false;
    }
  });

  copyBtn.addEventListener('click', () => {
    window.Platform.copyToClipboard(resultText.textContent).then(() => showToast('Copied!'));
  });
  replaceBtn.addEventListener('click', () => {
    input.value = resultText.textContent;
    resultSection.style.display = 'none';
    showToast('Input replaced');
  });
}

// ─── ═══════════════════════════════════════════════════════════════
//   HISTORY TAB
// ─── ═══════════════════════════════════════════════════════════════

function initHistoryTab() {
  const list = $('historyList');
  const clearBtn = $('historyClearBtn');
  const exportBtn = $('historyExportBtn');
  const modal = $('historyModal');
  const modalText = $('historyModalText');
  const modalTitle = $('historyModalTitle');
  const modalClose = $('historyModalClose');
  const modalCopy = $('historyModalCopy');
  const typeIcons = { file: '📁', mic: '🎙️', youtube: '▶️', polish: '✨' };

  function render() {
    const items = window.historyStorage.getAll();
    if (items.length === 0) {
      list.innerHTML = '<div class="empty-state">No transcriptions yet</div>';
      return;
    }
    list.innerHTML = items.map(item => {
      const preview = (item.text || '').slice(0, 100);
      const icon = typeIcons[item.type] || '📄';
      return `<div class="history-item" data-id="${item.id}">
        <div style="display:flex;align-items:center;gap:12px;min-width:0;flex:1">
          <span class="history-item-type">${icon}</span>
          <div class="history-item-info">
            <div class="history-item-title">${item.title || 'Untitled'}</div>
            <div class="history-item-meta">${formatDate(item.timestamp)} · ${preview}${preview.length >= 100 ? '…' : ''}</div>
          </div>
        </div>
      </div>`;
    }).join('');

    list.querySelectorAll('.history-item').forEach(el => {
      el.addEventListener('click', () => {
        const item = window.historyStorage.getAll().find(i => i.id === el.dataset.id);
        if (item) {
          modalTitle.textContent = `${typeIcons[item.type] || '📄'} ${item.title || 'Transcription'}`;
          modalText.textContent = item.text || '(empty)';
          modal.style.display = 'block';
        }
      });
    });
  }

  render();

  modalClose.addEventListener('click', () => { modal.style.display = 'none'; });
  modal.addEventListener('click', (e) => {
    if (e.target.classList.contains('modal-backdrop')) modal.style.display = 'none';
  });
  modalCopy.addEventListener('click', () => {
    window.Platform.copyToClipboard(modalText.textContent).then(() => showToast('Copied!'));
  });

  clearBtn.addEventListener('click', () => {
    if (confirm('Clear all history?')) {
      window.historyStorage.clear();
      render();
      showToast('History cleared');
    }
  });

  exportBtn.addEventListener('click', async () => {
    const data = window.historyStorage.export();
    const saved = await window.Platform.saveFile(data, 'transcription_history.json', 'application/json');
    if (saved) showToast('Exported!');
  });

  window._refreshHistory = render;
}

// ─── ═══════════════════════════════════════════════════════════════
//   SETTINGS TAB
// ─── ═══════════════════════════════════════════════════════════════

function initSettingsTab() {
  const groqKey = $('settingsGroqKey');
  const toggleKey = $('settingsToggleKey');
  const validateBtn = $('settingsValidateKey');
  const keyStatus = $('settingsKeyStatus');
  const llmEndpoint = $('settingsLlmEndpoint');
  const llmKey = $('settingsLlmKey');
  const llmModel = $('settingsLlmModel');
  const saveHistory = $('settingsSaveHistory');
  const saveBtn = $('settingsSaveBtn');

  toggleKey.addEventListener('click', () => {
    groqKey.type = groqKey.type === 'password' ? 'text' : 'password';
    toggleKey.textContent = groqKey.type === 'password' ? '👁' : '🙈';
  });

  validateBtn.addEventListener('click', async () => {
    const key = groqKey.value.trim();
    if (!key) { keyStatus.textContent = '❌ No key'; keyStatus.className = 'status-indicator err'; return; }
    localStorage.setItem('groq_api_key', key);
    validateBtn.disabled = true;
    keyStatus.textContent = '⏳ Validating…';
    keyStatus.className = 'status-indicator';
    try {
      const models = await window.groqService.listModels();
      const count = models.data?.length || 0;
      keyStatus.textContent = `✅ Valid! ${count} models`;
      keyStatus.className = 'status-indicator ok';
      showToast(`Groq key valid — ${count} models`);
    } catch (err) {
      localStorage.removeItem('groq_api_key');
      keyStatus.textContent = `❌ ${err.message}`;
      keyStatus.className = 'status-indicator err';
    } finally { validateBtn.disabled = false; }
  });

  function load() {
    groqKey.value = localStorage.getItem('groq_api_key') || '';
    llmEndpoint.value = localStorage.getItem('llm_endpoint') || 'https://api.groq.com/openai/v1';
    llmKey.value = localStorage.getItem('llm_api_key') || '';
    const savedModel = localStorage.getItem('llm_model');
    if (savedModel) llmModel.value = savedModel;
    saveHistory.checked = localStorage.getItem('save_history') !== 'false';
  }

  saveBtn.addEventListener('click', () => {
    localStorage.setItem('groq_api_key', groqKey.value.trim());
    localStorage.setItem('llm_endpoint', llmEndpoint.value.trim());
    localStorage.setItem('llm_api_key', llmKey.value.trim());
    localStorage.setItem('llm_model', llmModel.value);
    localStorage.setItem('save_history', saveHistory.checked ? 'true' : 'false');
    showToast('Settings saved!');
  });

  window._loadSettings = load;
}
