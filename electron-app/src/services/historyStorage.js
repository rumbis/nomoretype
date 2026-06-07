/* ═══════════════════════════════════════════════════════════════════════════
   HistoryStorage — Manages transcription history via localStorage
   ═══════════════════════════════════════════════════════════════════════════ */

class HistoryStorage {
  constructor() {
    this.STORAGE_KEY = 'nomoretype_history';
  }

  getAll() {
    try {
      return JSON.parse(localStorage.getItem(this.STORAGE_KEY) || '[]');
    } catch {
      return [];
    }
  }

  add(entry) {
    const history = this.getAll();
    history.unshift({
      id: Date.now().toString(36) + Math.random().toString(36).slice(2, 6),
      timestamp: new Date().toISOString(),
      ...entry,
    });
    // Keep last 500
    if (history.length > 500) history.length = 500;
    localStorage.setItem(this.STORAGE_KEY, JSON.stringify(history));
    return history;
  }

  delete(id) {
    const history = this.getAll().filter(e => e.id !== id);
    localStorage.setItem(this.STORAGE_KEY, JSON.stringify(history));
    return history;
  }

  clear() {
    localStorage.removeItem(this.STORAGE_KEY);
    return [];
  }

  export() {
    const data = JSON.stringify(this.getAll(), null, 2);
    return data;
  }
}

window.historyStorage = new HistoryStorage();
