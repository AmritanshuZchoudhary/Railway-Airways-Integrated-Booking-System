import { StrictMode } from 'react';
import { createRoot } from 'react-dom/client';
import './index.css';
import App from './App.jsx';
import { applyTheme, getInitialTheme } from './services/theme.js';

// Apply the saved (or system) theme before the first paint to avoid a light flash.
applyTheme(getInitialTheme());

createRoot(document.getElementById('root')).render(
  <StrictMode>
    <App />
  </StrictMode>
);
