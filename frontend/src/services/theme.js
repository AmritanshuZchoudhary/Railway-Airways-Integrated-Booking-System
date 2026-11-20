const STORAGE_KEY = 'rw_theme';

export function getInitialTheme() {
  try {
    const saved = window.localStorage.getItem(STORAGE_KEY);
    if (saved === 'light' || saved === 'dark') return saved;
  } catch { /* storage unavailable: fall back to the system preference */ }
  return window.matchMedia?.('(prefers-color-scheme: dark)').matches ? 'dark' : 'light';
}

export function applyTheme(theme) {
  document.documentElement.setAttribute('data-theme', theme);
  const meta = document.querySelector('meta[name="theme-color"]');
  if (meta) meta.setAttribute('content', theme === 'dark' ? '#0a1420' : '#0f2a3f');
}

export function saveTheme(theme) {
  try { window.localStorage.setItem(STORAGE_KEY, theme); } catch { /* ignore */ }
}
