import { useEffect, useRef, useState } from 'react';

/**
 * Keeps a passenger's bookings fresh and reports when a waiting ticket becomes CONFIRMED.
 *
 * Why: when another passenger cancels, the database trigger promotes the next waiting
 * passenger on the server. This hook lets that passenger's open tab notice the change by
 * itself, without a manual refresh (used by the two-tab "waiting list to confirmed" demo).
 *
 * - polls `refresh()` every few seconds while the tab is visible, and again when the tab is focused
 * - compares the previous and new status of every booking
 * - returns the ids that were upgraded in the last 15 seconds (to highlight their cards)
 */
export default function useBookingWatcher({ bookings, refresh, enabled, idKey, waitingStatus, onUpgrade, intervalMs = 4000 }) {
  const previousStatuses = useRef(null);
  const onUpgradeRef = useRef(onUpgrade);
  const [upgradedIds, setUpgradedIds] = useState([]);

  useEffect(() => { onUpgradeRef.current = onUpgrade; }, [onUpgrade]);

  useEffect(() => {
    const current = new Map(bookings.map((booking) => [booking[idKey], booking.status]));
    if (previousStatuses.current) {
      const upgraded = bookings.filter((booking) => previousStatuses.current.get(booking[idKey]) === waitingStatus && booking.status === 'CONFIRMED');
      if (upgraded.length) {
        const ids = upgraded.map((booking) => booking[idKey]);
        setUpgradedIds((existing) => [...existing, ...ids]);
        upgraded.forEach((booking) => onUpgradeRef.current?.(booking));
        window.setTimeout(() => setUpgradedIds((existing) => existing.filter((id) => !ids.includes(id))), 15000);
      }
    }
    previousStatuses.current = current;
  }, [bookings, idKey, waitingStatus]);

  useEffect(() => {
    if (!enabled) return undefined;
    let running = false;
    const tick = async () => {
      if (running || document.visibilityState !== 'visible') return;
      running = true;
      try { await refresh(); } catch { /* a failed background refresh is ignored; the next one retries */ } finally { running = false; }
    };
    const timer = window.setInterval(tick, intervalMs);
    document.addEventListener('visibilitychange', tick);
    window.addEventListener('focus', tick);
    return () => {
      window.clearInterval(timer);
      document.removeEventListener('visibilitychange', tick);
      window.removeEventListener('focus', tick);
    };
  }, [enabled, refresh, intervalMs]);

  return upgradedIds;
}
