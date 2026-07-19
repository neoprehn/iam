/* Leichtgewichtige i18n-Runtime ohne Framework/Build-Step.
 *
 * Texte liegen in /i18n/<lang>.json (flache, verschachtelte Keys -> Text). Platzhalter im
 * Format {name} werden ueber t(key, {name: ...}) ersetzt.
 *
 * Statisches HTML:
 *   <span data-i18n="header.title"></span>            -> textContent
 *   <span data-i18n-html="header.note"></span>        -> innerHTML (nur fuer eigene Markups)
 *   <input data-i18n-attr="placeholder:search.hint">  -> Attribut(e), mehrere per ';' getrennt
 *
 * Dynamische JS-Strings: I18N.t('key', params).
 *
 * Sprachaufloesung: localStorage('iam.lang') -> Masterdata-Default (/admin/masterdata/ui) -> 'de'.
 */
(function () {
  const LS_KEY = 'iam.lang';
  const FALLBACK = 'de';
  const state = { lang: FALLBACK, dict: {}, fallbackDict: {}, available: ['de', 'en'] };
  const listeners = [];

  async function loadDict(lang) {
    const res = await fetch('/i18n/' + lang + '.json', { cache: 'no-cache' });
    if (!res.ok) throw new Error('i18n: konnte /i18n/' + lang + '.json nicht laden');
    return res.json();
  }

  function lookup(key, dict) {
    return String(key).split('.').reduce((o, k) => (o && o[k] != null ? o[k] : undefined), dict);
  }

  function t(key, params) {
    let s = lookup(key, state.dict);
    if (s === undefined) s = lookup(key, state.fallbackDict);
    if (s === undefined) return key; // fehlender Key wird sichtbar gemacht
    if (params) s = s.replace(/\{(\w+)\}/g, (m, p) => (params[p] != null ? params[p] : m));
    return s;
  }

  function applyTo(root) {
    root = root || document;
    root.querySelectorAll('[data-i18n]').forEach((el) => {
      el.textContent = t(el.getAttribute('data-i18n'));
    });
    root.querySelectorAll('[data-i18n-html]').forEach((el) => {
      el.innerHTML = t(el.getAttribute('data-i18n-html'));
    });
    root.querySelectorAll('[data-i18n-attr]').forEach((el) => {
      el.getAttribute('data-i18n-attr').split(';').forEach((pair) => {
        const idx = pair.indexOf(':');
        if (idx < 0) return;
        const attr = pair.slice(0, idx).trim();
        const key = pair.slice(idx + 1).trim();
        if (attr && key) el.setAttribute(attr, t(key));
      });
    });
  }

  async function setLang(lang) {
    if (!state.available.includes(lang)) lang = FALLBACK;
    const dict = await loadDict(lang);
    state.dict = dict;
    if (lang === FALLBACK) {
      state.fallbackDict = dict;
    } else if (!Object.keys(state.fallbackDict).length) {
      try { state.fallbackDict = await loadDict(FALLBACK); } catch (e) { /* Fallback optional */ }
    }
    state.lang = lang;
    localStorage.setItem(LS_KEY, lang);
    document.documentElement.setAttribute('lang', lang);
    applyTo(document);
    listeners.forEach((fn) => { try { fn(lang); } catch (e) { console.error(e); } });
  }

  async function resolveDefault() {
    try {
      const r = await fetch('/admin/masterdata/ui', { cache: 'no-cache' });
      if (r.ok) {
        const d = await r.json();
        if (d) {
          if (Array.isArray(d.languages) && d.languages.length) state.available = d.languages.slice();
          if (d.defaultLanguage) return d.defaultLanguage;
        }
      }
    } catch (e) { /* Default optional -> Fallback */ }
    return FALLBACK;
  }

  async function init() {
    let lang = localStorage.getItem(LS_KEY);
    const preferred = await resolveDefault(); // fuellt zugleich state.available
    if (!lang) lang = preferred;
    await setLang(lang);
    return state.lang;
  }

  window.I18N = {
    t: t,
    setLang: setLang,
    applyTo: applyTo,
    onChange: (fn) => { listeners.push(fn); },
    get lang() { return state.lang; },
    get available() { return state.available.slice(); },
    ready: init(),
  };
})();
