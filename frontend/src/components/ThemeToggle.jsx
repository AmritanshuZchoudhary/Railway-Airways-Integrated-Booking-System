import { useState } from 'react';
import { applyTheme, getInitialTheme, saveTheme } from '../services/theme.js';

export default function ThemeToggle({ className = '' }) {
  const [theme, setTheme] = useState(() => document.documentElement.getAttribute('data-theme') || getInitialTheme());

  const toggle = () => {
    const next = theme === 'dark' ? 'light' : 'dark';
    applyTheme(next);
    saveTheme(next);
    setTheme(next);
  };

  const isDark = theme === 'dark';
  return (
    <button type="button" className={`theme-toggle ${className}`} onClick={toggle} aria-label={isDark ? 'Switch to light mode' : 'Switch to dark mode'} title={isDark ? 'Light mode' : 'Dark mode'}>
      <svg width="19" height="19" viewBox="0 0 24 24" fill="none" stroke="currentColor" strokeWidth="1.8" strokeLinecap="round" strokeLinejoin="round" aria-hidden="true">
        {isDark
          ? <><circle cx="12" cy="12" r="4" /><path d="M12 2v2M12 20v2M4.9 4.9l1.4 1.4M17.7 17.7l1.4 1.4M2 12h2M20 12h2M4.9 19.1l1.4-1.4M17.7 6.3l1.4-1.4" /></>
          : <path d="M21 12.8A9 9 0 1 1 11.2 3a7 7 0 0 0 9.8 9.8Z" />}
      </svg>
    </button>
  );
}
