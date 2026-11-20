# UI refresh (2026-11-02)

Front-end only. No backend, database, API or booking logic was changed.

## What changed
- **New design system** in `frontend/src/index.css`: colour/shape/shadow tokens, readable type scale (previously many labels were 7–10 px; now 11–15 px), softer cards, consistent spacing.
- **Dark mode** with a toggle (top bar and sign-in/register pages). Follows the system setting on first visit, then remembers the choice (`frontend/src/services/theme.js`, `frontend/src/components/ThemeToggle.jsx`).
- **Overview hero banner**, animated route illustration on sign-in, gradient loyalty card, clearer ticket-style schedule cards, bigger probability ring.
- **Working status filters** on "My reservations" (railway) and "My flights" (air). They were static labels before.
- **Password strength meter** on the register page.
- **Mobile layout**: floating bottom tab bar, and the sign-out button is now reachable on phones (it was hidden before).
- Fonts load from `index.html` instead of a CSS `@import` (faster first paint); viewport handles notched phones.

## Files touched
`index.html`, `src/index.css`, `src/main.jsx`, `src/components/ThemeToggle.jsx` (new), `src/services/theme.js` (new),
`src/pages/Login.jsx`, `Register.jsx`, `PassengerDashboard.jsx`, `AirDashboard.jsx`.
