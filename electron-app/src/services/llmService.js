/* ═══════════════════════════════════════════════════════════════════════════
   LLMService — Polish, translate, or summarize transcripts via OpenAI-compatible API
   ═══════════════════════════════════════════════════════════════════════════ */

class LLMService {
  getSettings() {
    return {
      endpoint: localStorage.getItem('llm_endpoint') || 'https://api.groq.com/openai/v1',
      apiKey: localStorage.getItem('llm_api_key') || localStorage.getItem('groq_api_key') || '',
      model: localStorage.getItem('llm_model') || 'llama-3.3-70b-versatile',
    };
  }

  async process(text, mode, targetLang) {
    const { endpoint, apiKey, model } = this.getSettings();
    if (!apiKey) throw new Error('LLM API key not set. Go to Settings → configure LLM.');

    const systemPrompts = {
      'polish': 'You are a transcription editor. Fix grammar, punctuation, and awkward phrasing. Preserve the original meaning, speaker intent, and tone. Remove filler words (um, uh, like) where appropriate. Output only the polished text, no commentary.',
      'translate': `You are a translator. Translate the following text to ${targetLang}. Preserve the meaning, tone, and style. For ${targetLang === 'Greek' ? 'Greek, use the Greek alphabet (ελληνικά).' : ''} Output only the translation, no commentary.`,
      'summarize': 'Provide a concise summary of the following transcript. Capture the key points, decisions, and action items. Output in clear bullet points.',
      'fix-punctuation': 'Add proper punctuation (periods, commas, question marks, capitalization) to this transcript. Do NOT change any words or their order. Output only the punctuated text.',
    };

    const prompt = systemPrompts[mode];
    if (!prompt) throw new Error(`Unknown mode: ${mode}`);

    const url = `${endpoint.replace(/\/$/, '')}/chat/completions`;
    const resp = await fetch(url, {
      method: 'POST',
      headers: {
        'Authorization': `Bearer ${apiKey}`,
        'Content-Type': 'application/json',
      },
      body: JSON.stringify({
        model,
        messages: [
          { role: 'system', content: prompt },
          { role: 'user', content: text },
        ],
        temperature: 0.3,
        max_tokens: 4096,
      }),
    });

    if (!resp.ok) {
      let errMsg = `HTTP ${resp.status}`;
      try {
        const err = await resp.json();
        errMsg = err.error?.message || errMsg;
      } catch {}
      throw new Error(errMsg);
    }

    const data = await resp.json();
    return data.choices?.[0]?.message?.content?.trim() || '';
  }
}

window.llmService = new LLMService();
