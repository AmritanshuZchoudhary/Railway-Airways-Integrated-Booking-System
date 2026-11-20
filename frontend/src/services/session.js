// Login state lives in sessionStorage, which is separate for every browser tab.
// This lets two different passengers be signed in at the same time on two tabs of one
// browser (used by the "waiting list to confirmed" demonstration). Closing a tab signs it out.
const TOKEN_KEY = 'railway_token';
const USER_KEY = 'railway_user';

export function getToken() {
  return window.sessionStorage.getItem(TOKEN_KEY);
}

export function getStoredUser() {
  try {
    return JSON.parse(window.sessionStorage.getItem(USER_KEY) || 'null');
  } catch {
    return null;
  }
}

export function saveSession(token, user) {
  window.sessionStorage.setItem(TOKEN_KEY, token);
  window.sessionStorage.setItem(USER_KEY, JSON.stringify(user));
}

export function saveUser(user) {
  window.sessionStorage.setItem(USER_KEY, JSON.stringify(user));
}

export function clearSession() {
  window.sessionStorage.removeItem(TOKEN_KEY);
  window.sessionStorage.removeItem(USER_KEY);
  // Older versions kept the login in localStorage; remove it so it cannot confuse the tabs.
  window.localStorage.removeItem(TOKEN_KEY);
  window.localStorage.removeItem(USER_KEY);
}
