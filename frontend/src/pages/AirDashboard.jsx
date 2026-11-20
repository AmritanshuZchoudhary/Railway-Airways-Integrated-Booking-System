import { useCallback, useEffect, useMemo, useState, useRef } from 'react';
import { useNavigate } from 'react-router-dom';
import Brand from '../components/Brand.jsx';
import api, { getApiError } from '../services/api.js';
import { clearSession, getStoredUser, saveUser } from '../services/session.js';
import useBookingWatcher from '../hooks/useBookingWatcher.js';

const iconPaths = {
  overview: <><rect x="3" y="3" width="7" height="7" rx="1.5"/><rect x="14" y="3" width="7" height="7" rx="1.5"/><rect x="3" y="14" width="7" height="7" rx="1.5"/><rect x="14" y="14" width="7" height="7" rx="1.5"/></>,
  search: <><circle cx="10.5" cy="10.5" r="6.5"/><path d="m16 16 4.2 4.2"/></>,
  bookings: <><path d="M5 4.5h14a2 2 0 0 1 2 2v11a2 2 0 0 1-2 2H5a2 2 0 0 1-2-2v-11a2 2 0 0 1 2-2Z"/><path d="M8 9h8M8 13h5"/></>,
  star: <path d="m12 3 2.7 5.6 6.1.9-4.4 4.3 1 6.1L12 17l-5.4 2.9 1-6.1L3.2 9.5l6.1-.9L12 3Z"/>,
  admin: <><rect x="4" y="4" width="16" height="16" rx="3"/><path d="M9 9h6M9 13h6M9 17h3"/></>,
  arrow: <path d="M5 12h14M13 6l6 6-6 6"/>,
  plane: <path d="M21 3 3 10.5l6.5 3L12.5 21 21 3ZM9.5 13.5 15 8"/>,
  train: <><rect x="5" y="3" width="14" height="16" rx="3"/><path d="M8 7h8M8 11h.01M16 11h.01M8 19l-2 3m10-3 2 3M7 16h10"/></>,
  clock: <><circle cx="12" cy="12" r="9"/><path d="M12 7v5l3 2"/></>,
  pin: <><path d="M19 10c0 5-7 11-7 11S5 15 5 10a7 7 0 1 1 14 0Z"/><circle cx="12" cy="10" r="2"/></>,
  logout: <><path d="M10 17l5-5-5-5M15 12H3"/><path d="M12 3h6a2 2 0 0 1 2 2v14a2 2 0 0 1-2 2h-6"/></>,
  check: <path d="m5 12 4 4L19 6"/>,
  close: <path d="m6 6 12 12M18 6 6 18"/>,
  bag: <><rect x="5" y="8" width="14" height="12" rx="2"/><path d="M9 8V6a3 3 0 0 1 6 0v2"/></>
};

function Icon({ name, size = 19 }) {
  return <svg aria-hidden="true" width={size} height={size} viewBox="0 0 24 24" fill="none" stroke="currentColor" strokeWidth="1.7" strokeLinecap="round" strokeLinejoin="round">{iconPaths[name] || iconPaths.overview}</svg>;
}

function localDatePlus(days) {
  const date = new Date();
  date.setHours(12, 0, 0, 0);
  date.setDate(date.getDate() + days);
  return `${date.getFullYear()}-${String(date.getMonth() + 1).padStart(2, '0')}-${String(date.getDate()).padStart(2, '0')}`;
}

function formatDate(value, options = { weekday: 'short', day: 'numeric', month: 'short' }) {
  if (!value) return '—';
  const date = value instanceof Date ? value : new Date(`${String(value).slice(0, 10)}T12:00:00`);
  if (Number.isNaN(date.getTime())) return '—';
  return new Intl.DateTimeFormat('en-IN', options).format(date);
}

function formatMoney(value) {
  return new Intl.NumberFormat('en-IN', { style: 'currency', currency: 'INR', maximumFractionDigits: 0 }).format(Number(value || 0));
}

function getStatusClass(status) {
  if (status === 'CONFIRMED') return 'status-confirmed';
  if (status === 'STANDBY') return 'status-waitlisted';
  return 'status-cancelled';
}

function getInitials(name = 'Guest') {
  return name.split(/\s+/).filter(Boolean).slice(0, 2).map((part) => part[0]?.toUpperCase()).join('') || 'G';
}

const cabinLabel = (cabin) => (cabin === 'BUSINESS' ? 'Business' : 'Economy');

function EmptyState({ title, description, action, onAction }) {
  return <div className="empty-state"><div className="empty-state-icon"><Icon name="plane" size={24}/></div><h3>{title}</h3><p>{description}</p>{action && <button className="button button-outline button-small" onClick={onAction}>{action}</button>}</div>;
}

function StatCard({ label, value, caption, icon, tone }) {
  return <article className="stat-card"><div className={`stat-icon ${tone}`}><Icon name={icon} size={20}/></div><div className="stat-copy"><span>{label}</span><strong>{value ?? '—'}</strong><small>{caption}</small></div><div className="stat-corner"/></article>;
}

function AirProbabilityCard({ item }) {
  if (!item) return null;
  const canEstimate = item.canEstimate && Number.isFinite(Number(item.probabilityPercent));
  const percent = canEstimate ? Number(item.probabilityPercent) : 0;
  return (
    <div className="probability-card air-probability-card">
      <div className="probability-heading">
        <div><span className="mini-label">STANDBY ESTIMATE</span><h4>{canEstimate ? `Probability based on past data: ${percent}%` : 'Confirmation probability'}</h4></div>
        <span className={`data-chip ${canEstimate ? (item.dataSupport === 'STRONG' ? 'data-strong' : 'data-adequate') : 'data-low'}`}>{canEstimate ? item.dataSupport : 'LOW DATA'}</span>
      </div>
      {canEstimate ? <>
        <div className="probability-main">
          <div className="probability-ring" style={{ '--probability': `${percent * 3.6}deg` }}><div><strong>{percent}%</strong><small>estimate</small></div></div>
          <div className="probability-summary"><strong>{item.successes} of {item.totalSample}</strong><span>comparable past cases confirmed</span><small>{item.unsuccessful} were not confirmed</small></div>
        </div>
        <div className="probability-bar"><span style={{ width: `${percent}%` }} /></div>
        <p className="probability-group">{item.comparisonGroup}</p>
      </> : <div className="probability-empty"><span className="probability-empty-icon">i</span><p>{item.message || 'Not enough comparable past outcomes yet.'}</p><small>{item.totalSample ?? 0} comparable outcomes · {item.minimumSampleRequired ?? 20} required</small></div>}
      <div className="probability-source-tags"><span>Recorded outcomes <b>{item.recordedObservations ?? 0}</b></span><span>Simulated demo <b>{item.simulatedObservations ?? 0}</b></span></div>
    </div>
  );
}

function AirBookingCard({ booking, bagWeight, onBagWeight, onAddBag, onCancel, bagBusy, highlighted, onCheckProbability, probability, probabilityLoading }) {
  const canCancel = booking.status !== 'CANCELLED' && new Date(`${String(booking.flight_date).slice(0, 10)}T12:00:00`) >= new Date(new Date().toDateString());
  const label = booking.status === 'STANDBY' && booking.standby_position ? `WL-${booking.standby_position}` : booking.status;
  return (
    <article className={highlighted ? 'booking-card booking-card-upgraded' : 'booking-card'}>
      {highlighted && <div className="upgrade-banner">✓ Upgraded from standby to CONFIRMED just now</div>}
      <div className="booking-card-main">
        <div className="train-avatar"><Icon name="plane" size={22}/></div>
        <div className="booking-route-content">
          <div className="booking-top-line"><strong>{booking.airline_name}</strong><span className="train-number">{booking.flight_number}</span><span className={`status-pill ${getStatusClass(booking.status)}`}>{label}</span></div>
          <div className="booking-stations"><strong>{booking.origin_airport}</strong><span className="route-dash">────────</span><strong>{booking.destination_airport}</strong></div>
          <div className="booking-metadata"><span><Icon name="clock" size={14}/>{formatDate(booking.flight_date)} · {booking.departure_time}</span><span>{cabinLabel(booking.cabin_class)}</span>{booking.seat_no && <span>Seat {booking.seat_no}</span>}</div>
        </div>
        <div className="booking-price"><small>FINAL FARE</small><strong>{formatMoney(booking.fare)}</strong><small>Ref. #{booking.air_booking_id}</small></div>
      </div>
      <div className="booking-loyalty-breakdown">
        <span>Base fare <b>{formatMoney(booking.base_fare ?? booking.fare)}</b></span>
        {Number(booking.loyalty_discount_amount) > 0
          ? <span className="loyalty-saving">{booking.loyalty_tier_at_booking || 'LOYALTY'} discount ({Number(booking.loyalty_discount_percent)}%) <b>−{formatMoney(booking.loyalty_discount_amount)}</b></span>
          : <span className="loyalty-no-saving">{booking.loyalty_tier_at_booking || 'BASIC'} tier · 0% flight discount</span>}
        <span className="loyalty-paid">Final fare <b>{formatMoney(booking.fare)}</b></span>
      </div>
      {booking.status === 'STANDBY' && <div className="booking-inline-insight"><span className="insight-bullet"/><strong className="waitlist-position">WL-{booking.standby_position || '—'}</strong><span>Current standby position</span><button className="text-button" onClick={() => onCheckProbability(booking.air_booking_id)} disabled={probabilityLoading}>{probabilityLoading ? 'Calculating…' : probability ? 'Refresh probability' : 'Check probability'} <span>↗</span></button></div>}
      {booking.status === 'STANDBY' && probability && <AirProbabilityCard item={probability}/>}
      {booking.status === 'CANCELLED' && booking.refund_amount !== null && <div className="booking-inline-insight"><span className="insight-bullet"/><span>Refund calculated by time before departure: <b>{formatMoney(booking.refund_amount)}</b></span></div>}
      {booking.status === 'CONFIRMED' && (
        <div className="bag-panel">
          <div className="bag-heading"><Icon name="bag" size={16}/><strong>Baggage</strong><small>{booking.cabin_class === 'BUSINESS' ? '30 kg' : '15 kg'} free · ₹400 per extra kg</small></div>
          {booking.bags.length > 0 && <ul className="bag-list">{booking.bags.map((bag) => <li key={bag.bag_no}><span>Bag {bag.bag_no}</span><span>{Number(bag.weight_kg).toFixed(1)} kg</span><b>{Number(bag.excess_fee) > 0 ? formatMoney(bag.excess_fee) : 'Free'}</b></li>)}</ul>}
          {booking.bags.length > 0 && <p className="bag-total">{booking.baggage_total_kg.toFixed(1)} kg in total · excess fees {formatMoney(booking.baggage_fees)}</p>}
          {canCancel && <form className="bag-form" onSubmit={(event) => { event.preventDefault(); onAddBag(booking.air_booking_id); }}><input type="number" min="0.5" max="50" step="0.5" placeholder="Weight (kg)" value={bagWeight || ''} onChange={(event) => onBagWeight(booking.air_booking_id, event.target.value)} aria-label="Bag weight in kilograms"/><button className="button button-outline button-small" type="submit" disabled={bagBusy || !bagWeight}>Add bag</button></form>}
        </div>
      )}
      {canCancel && <div className="booking-actions"><span className="booking-reference">Booked {formatDate(booking.booking_time, { day: 'numeric', month: 'short', year: 'numeric' })}</span><button className="button button-quiet-danger button-small" onClick={() => onCancel(booking.air_booking_id)}>Cancel booking</button></div>}
    </article>
  );
}

export default function AirDashboard() {
  const navigate = useNavigate();
  const [user, setUser] = useState(() => {
    return getStoredUser();
  });
  const [activeView, setActiveView] = useState('overview');
  const [airports, setAirports] = useState([]);
  const [bookings, setBookings] = useState([]);
  const [probabilities, setProbabilities] = useState({});
  const [probabilityLoading, setProbabilityLoading] = useState({});
  const [loyalty, setLoyalty] = useState(null);
  const [ledger, setLedger] = useState([]);
  const [trips, setTrips] = useState([]);
  const [adminSummary, setAdminSummary] = useState(null);
  const [scheduleOptions, setScheduleOptions] = useState({ flights: [], aircraft: [], schedules: [] });
  const [scheduleForm, setScheduleForm] = useState({ flight_id: '', aircraft_id: '', flight_date: localDatePlus(3), overbook_limit: 2 });
  const [originId, setOriginId] = useState('1');
  const [destinationId, setDestinationId] = useState('2');
  const [flightDate, setFlightDate] = useState(localDatePlus(3));
  const [cabin, setCabin] = useState('ECONOMY');
  const [flights, setFlights] = useState([]);
  const [searched, setSearched] = useState(false);
  const [searching, setSearching] = useState(false);
  const [bookingInProgress, setBookingInProgress] = useState(null);
  const [busyBookingId, setBusyBookingId] = useState(null);
  const [bagWeights, setBagWeights] = useState({});
  const [bagBusy, setBagBusy] = useState(false);
  const [scheduleBusy, setScheduleBusy] = useState(false);
  const [toast, setToast] = useState(null);
  const [loading, setLoading] = useState(true);
  const [error, setError] = useState('');

  const showToast = useCallback((message, tone = 'success') => {
    setToast({ message, tone });
    window.setTimeout(() => setToast(null), 5200);
  }, []);

  const logout = useCallback(() => {
    clearSession();
    navigate('/login', { replace: true });
  }, [navigate]);

  const refreshAccountData = useCallback(async (isAdmin) => {
    const [bookingRes, loyaltyRes, tripRes] = await Promise.all([api.get('/air/bookings/my'), api.get('/loyalty/me'), api.get('/loyalty/trips')]);
    setBookings(bookingRes.data.bookings || []);
    setLoyalty(loyaltyRes.data.loyalty || null);
    setLedger(loyaltyRes.data.ledger || []);
    setTrips(tripRes.data.trips || []);
    if (isAdmin) {
      const adminRes = await api.get('/air/admin/summary');
      setAdminSummary(adminRes.data.summary || null);
    }
  }, []);

  useEffect(() => {
    let active = true;
    async function load() {
      setLoading(true); setError('');
      try {
        const [meRes, airportRes] = await Promise.all([api.get('/auth/me'), api.get('/air/airports')]);
        if (!active) return;
        setUser(meRes.data.user);
        saveUser(meRes.data.user);
        const list = airportRes.data.airports || [];
        setAirports(list);
        if (list.length > 1) { setOriginId(String(list.find((a) => a.iata_code === 'NDA')?.airport_id || list[0].airport_id)); setDestinationId(String(list.find((a) => a.iata_code === 'MBA')?.airport_id || list[1].airport_id)); }
        await refreshAccountData(meRes.data.user.role === 'ADMIN');
        if (meRes.data.user.role === 'ADMIN') {
          const optionRes = await api.get('/air/admin/schedule-options');
          if (active) setScheduleOptions(optionRes.data);
        }
      } catch (requestError) {
        if (!active) return;
        if (requestError.response?.status === 401) return logout();
        setError(getApiError(requestError, 'Could not load the airline dashboard.'));
      } finally { if (active) setLoading(false); }
    }
    load();
    return () => { active = false; };
  }, [logout, refreshAccountData]);

  const isAdminUser = user?.role === 'ADMIN';
  const refreshForWatcher = useCallback(() => refreshAccountData(isAdminUser), [refreshAccountData, isAdminUser]);
  // Polls for changes so a standby passenger sees the upgrade as soon as another passenger cancels.
  const upgradedIds = useBookingWatcher({
    bookings,
    refresh: refreshForWatcher,
    enabled: !loading,
    idKey: 'air_booking_id',
    waitingStatus: 'STANDBY',
    onUpgrade: (booking) => {
      setActiveView('bookings');
      showToast(`Good news! Standby booking #${booking.air_booking_id} (${booking.flight_number}) is now CONFIRMED${booking.seat_no ? ` with seat ${booking.seat_no}` : ''}.`);
    }
  });

  const summary = useMemo(() => ({
    total: bookings.length,
    confirmed: bookings.filter((b) => b.status === 'CONFIRMED').length,
    standby: bookings.filter((b) => b.status === 'STANDBY').length
  }), [bookings]);
  const titleMap = { overview: 'Overview', search: 'Find a flight', bookings: 'My flights', loyalty: 'Loyalty and trips', admin: 'Airline console' };
  const isAdmin = user?.role === 'ADMIN';

  // Parameters of the search currently on screen; background refreshes reuse them.
  const lastFlightSearch = useRef(null);
  const refreshFlights = useCallback(async () => {
    if (!lastFlightSearch.current) return;
    try {
      const { data } = await api.get('/air/flights/search', { params: lastFlightSearch.current });
      setFlights(data.flights || []);
    } catch { /* a failed background refresh is ignored; the next one retries */ }
  }, []);

  // Keep seat counts live while the flight search page is open and the tab is visible.
  useEffect(() => {
    if (activeView !== 'search' || !searched) return undefined;
    const tick = () => { if (document.visibilityState === 'visible') refreshFlights(); };
    const timer = window.setInterval(tick, 8000);
    document.addEventListener('visibilitychange', tick);
    return () => { window.clearInterval(timer); document.removeEventListener('visibilitychange', tick); };
  }, [activeView, searched, refreshFlights]);

  const handleSearch = async (event) => {
    event?.preventDefault();
    if (!originId || !destinationId || originId === destinationId) { setToast({ message: 'Choose two different airports to search.', tone: 'error' }); return; }
    setSearching(true); setSearched(true); setFlights([]); setError('');
    const searchParams = { origin_airport_id: originId, destination_airport_id: destinationId, flight_date: flightDate, cabin_class: cabin };
    lastFlightSearch.current = searchParams;
    try {
      const { data } = await api.get('/air/flights/search', { params: searchParams });
      setFlights(data.flights || []);
      if (!data.flights?.length) showToast('No flights matched. Try another date or route.', 'info');
    } catch (requestError) {
      if (requestError.response?.status === 401) return logout();
      setError(getApiError(requestError, 'Flight search failed.'));
    } finally { setSearching(false); }
  };

  const handleBook = async (flight) => {
    setBookingInProgress(flight.flight_schedule_id); setError('');
    try {
      const { data } = await api.post('/air/bookings/create', { flight_schedule_id: flight.flight_schedule_id, cabin_class: flight.cabin_class });
      const saving = Number(data.loyalty_discount_amount || 0);
      const discountMessage = saving > 0
        ? ` ${data.loyalty_tier_at_booking} loyalty benefit: ${Number(data.loyalty_discount_percent)}% off, saving ${formatMoney(saving)}.`
        : ' No flight loyalty discount applied at the current tier.';
      showToast(`${data.message}${discountMessage} Booking reference #${data.air_booking_id}.`);
      await refreshAccountData(isAdmin);
      await refreshFlights(); // seat count drops immediately, without blanking the list
      if (data.status === 'STANDBY') { setActiveView('bookings'); window.setTimeout(() => checkProbability(data.air_booking_id), 120); }
    } catch (requestError) {
      if (requestError.response?.status === 401) return logout();
      setError(getApiError(requestError, 'Booking failed.'));
    } finally { setBookingInProgress(null); }
  };

  const handleCancel = async (bookingId) => {
    if (!window.confirm(`Cancel booking #${bookingId}? The refund depends on how close the flight is. If a seat is released, the top standby passenger is promoted automatically.`)) return;
    setBusyBookingId(bookingId); setError('');
    try {
      const { data } = await api.post('/air/bookings/cancel', { air_booking_id: bookingId });
      showToast(`${data.message} Refund: ${formatMoney(data.refund_amount)}.`);
      setProbabilities((current) => { const next = { ...current }; delete next[bookingId]; return next; });
      await refreshAccountData(isAdmin);
      await refreshFlights(); // a cancelled seat becomes available again
    } catch (requestError) {
      if (requestError.response?.status === 401) return logout();
      setError(getApiError(requestError, 'Cancellation failed.'));
    } finally { setBusyBookingId(null); }
  };

  const checkProbability = async (bookingId) => {
    setProbabilityLoading((current) => ({ ...current, [bookingId]: true }));
    try {
      const { data } = await api.get('/air/bookings/probability', { params: { air_booking_id: bookingId } });
      setProbabilities((current) => ({ ...current, [bookingId]: data }));
    } catch (requestError) {
      if (requestError.response?.status === 401) return logout();
      showToast(getApiError(requestError, 'Could not calculate the flight standby probability.'), 'error');
    } finally {
      setProbabilityLoading((current) => ({ ...current, [bookingId]: false }));
    }
  };

  const handleAddBag = async (bookingId) => {
    setBagBusy(true); setError('');
    try {
      const { data } = await api.post('/air/bookings/baggage', { air_booking_id: bookingId, weight_kg: Number(bagWeights[bookingId]) });
      showToast(data.message, data.excess_fee > 0 ? 'info' : 'success');
      setBagWeights((current) => ({ ...current, [bookingId]: '' }));
      await refreshAccountData(isAdmin);
    } catch (requestError) {
      if (requestError.response?.status === 401) return logout();
      setError(getApiError(requestError, 'Could not add the bag.'));
    } finally { setBagBusy(false); }
  };

  const handleFinalizeAirHistory = async () => {
    try {
      const { data } = await api.post('/air/admin/finalize-history');
      showToast(data.message, data.inserted_count ? 'success' : 'info');
      await refreshAccountData(isAdmin);
    } catch (requestError) {
      if (requestError.response?.status === 401) return logout();
      showToast(getApiError(requestError, 'Could not finalize completed flight standby outcomes.'), 'error');
    }
  };

  const handleCreateSchedule = async (event) => {
    event.preventDefault();
    setScheduleBusy(true); setError('');
    try {
      const { data } = await api.post('/air/admin/schedules', { ...scheduleForm, flight_id: Number(scheduleForm.flight_id), aircraft_id: Number(scheduleForm.aircraft_id), overbook_limit: Number(scheduleForm.overbook_limit) });
      showToast(data.message);
      const [optionRes, adminRes] = await Promise.all([api.get('/air/admin/schedule-options'), api.get('/air/admin/summary')]);
      setScheduleOptions(optionRes.data); setAdminSummary(adminRes.data.summary || null);
    } catch (requestError) {
      if (requestError.response?.status === 401) return logout();
      showToast(getApiError(requestError, 'The schedule could not be created.'), 'error');
    } finally { setScheduleBusy(false); }
  };

  const searchPanel = (
    <section className="search-panel">
      <div className="section-heading search-heading"><div><p className="eyebrow">PLAN THE NEXT FLIGHT</p><h2>Find your flight</h2><p className="muted">Direct flights, dynamic fares, priority standby.</p></div><div className="search-heading-mark"><Icon name="plane" size={27}/></div></div>
      <form className="journey-form" onSubmit={handleSearch}>
        <div className="field-group station-field"><label htmlFor="air-origin">FROM</label><div className="select-with-icon"><Icon name="pin" size={17}/><select id="air-origin" value={originId} onChange={(e) => setOriginId(e.target.value)} required>{airports.map((a) => <option key={a.airport_id} value={a.airport_id}>{a.city} ({a.iata_code})</option>)}</select></div></div>
        <button type="button" className="swap-stations" title="Swap origin and destination" onClick={() => { setOriginId(destinationId); setDestinationId(originId); }} aria-label="Swap origin and destination">⇄</button>
        <div className="field-group station-field"><label htmlFor="air-destination">TO</label><div className="select-with-icon"><Icon name="pin" size={17}/><select id="air-destination" value={destinationId} onChange={(e) => setDestinationId(e.target.value)} required>{airports.map((a) => <option key={a.airport_id} value={a.airport_id}>{a.city} ({a.iata_code})</option>)}</select></div></div>
        <div className="field-group date-field"><label htmlFor="air-date">FLIGHT DATE</label><div className="select-with-icon"><Icon name="clock" size={17}/><input id="air-date" type="date" min={localDatePlus(0)} max={localDatePlus(29)} value={flightDate} onChange={(e) => setFlightDate(e.target.value)} required/></div></div>
        <div className="field-group class-field"><label htmlFor="air-cabin">CABIN</label><div className="select-with-icon"><Icon name="star" size={17}/><select id="air-cabin" value={cabin} onChange={(e) => setCabin(e.target.value)}><option value="ECONOMY">Economy</option><option value="BUSINESS">Business</option></select></div></div>
        <button className="button button-primary search-submit" type="submit" disabled={searching}>{searching ? <span className="spinner"/> : <Icon name="search" size={17}/>}<span>{searching ? 'Searching' : 'Search flights'}</span></button>
      </form>
      <div className="search-footnote"><span className="green-dot"/> Two direct demo flights run daily for every airport pair <span className="footnote-divider">·</span> Select any date in the next 30 days</div>
      {loyalty && <div className="flight-loyalty-hint"><Icon name="star" size={15}/><span>Your {loyalty.tier} tier ({loyalty.points.toLocaleString('en-IN')} points) gives you <b>{loyalty.flight_discount_percent}% off flight fares</b>. Earn points on confirmed rail and air bookings to unlock higher discounts.</span></div>}
    </section>
  );

  const resultsPanel = searched && (
    <section className="results-section">
      <div className="section-heading"><div><p className="eyebrow">YOUR MATCHES</p><h2>Available flights <span className="count-pill">{flights.length}</span></h2></div><button className="text-button" onClick={() => { setSearched(false); setFlights([]); }}>Clear results <Icon name="close" size={14}/></button></div>
      {flights.length ? <div className="schedule-list">{flights.map((flight) => {
        const hasSeat = Number(flight.available_seats) > 0;
        const canJoin = !hasSeat && flight.standby_open;
        return (
          <article className="schedule-card" key={flight.flight_schedule_id}>
            <div className="schedule-title-row"><div><div className="schedule-name"><strong>{flight.airline_name}</strong><span className="train-number">{flight.flight_number}</span></div><small className="muted">{formatDate(flight.flight_date, { weekday: 'long', day: 'numeric', month: 'long' })}</small></div><span className={`status-pill ${hasSeat ? 'status-confirmed' : canJoin ? 'status-waitlisted' : 'status-cancelled'}`}>{hasSeat ? `Available · ${flight.available_seats} seats` : canJoin ? `STANDBY OPEN (${flight.standby_slots_left} LEFT)` : 'FULL'}</span></div>
            <div className="schedule-route"><div className="schedule-time"><strong>{flight.departure_time}</strong><small>{flight.origin_city}</small><span>{flight.origin_code}</span></div><div className="schedule-track"><span>{flight.origin_airport}</span><div className="track-line"><i/><b><Icon name="plane" size={15}/></b><i/></div><span>{flight.destination_airport}</span></div><div className="schedule-time schedule-time-end"><strong>{flight.arrival_time}</strong><small>{flight.destination_city}</small><span>{flight.destination_code}</span></div></div>
            <div className="schedule-bottom schedule-bottom-loyalty">
              <span className="class-chip">{cabinLabel(flight.cabin_class)}</span>
              <div className="flight-fare-breakdown">
                <div><small>BASE FARE</small><strong>{formatMoney(flight.base_fare ?? flight.fare)}</strong></div>
                {Number(flight.loyalty_discount_amount) > 0
                  ? <div className="flight-fare-saving"><small>{flight.loyalty_tier} · {Number(flight.loyalty_discount_percent)}% OFF</small><strong>−{formatMoney(flight.loyalty_discount_amount)}</strong></div>
                  : <div><small>{flight.loyalty_tier || 'BASIC'} DISCOUNT</small><strong>0%</strong></div>}
                <div className="flight-fare-payable"><small>FINAL FARE</small><strong>{formatMoney(flight.fare)}</strong></div>
              </div>
              <button className="button button-primary button-small" onClick={() => handleBook(flight)} disabled={bookingInProgress === flight.flight_schedule_id || (!hasSeat && !canJoin)}>{bookingInProgress === flight.flight_schedule_id ? 'Booking…' : hasSeat ? 'Book seat' : canJoin ? 'Join standby' : 'Full'}</button>
            </div>
          </article>
        );
      })}</div> : <EmptyState title="No flights found for this date" description="Choose another date within the next 30 days. Two direct demo flights are scheduled daily between every listed airport pair." action="Edit search" onAction={() => setSearched(false)}/>}
    </section>
  );

  const bookingsPanel = (list = bookings, title = 'Your flights') => (
    <section className="bookings-section">
      <div className="section-heading"><div><p className="eyebrow">THE DETAILS, ALL IN ONE PLACE</p><h2>{title} <span className="count-pill">{list.length}</span></h2></div>{activeView === 'overview' && <button className="text-button" onClick={() => setActiveView('bookings')}>View all <Icon name="arrow" size={15}/></button>}</div>
      {list.length ? <div className="booking-list">{list.map((booking) => <AirBookingCard key={booking.air_booking_id} highlighted={upgradedIds.includes(booking.air_booking_id)} booking={booking} bagWeight={bagWeights[booking.air_booking_id]} onBagWeight={(id, value) => setBagWeights((current) => ({ ...current, [id]: value }))} onAddBag={handleAddBag} onCancel={handleCancel} bagBusy={bagBusy} onCheckProbability={checkProbability} probability={probabilities[booking.air_booking_id]} probabilityLoading={Boolean(probabilityLoading[booking.air_booking_id])}/>)}</div> : <EmptyState title="No flights booked yet" description="Search a route to book a seat or join the priority standby list." action="Find a flight" onAction={() => setActiveView('search')}/>}
    </section>
  );

  const loyaltyPanel = loyalty && (
    <>
      <section className="loyalty-card">
        <div className="loyalty-head"><div><span className="mini-label">SHARED ACROSS RAIL AND AIR</span><h2>{loyalty.points.toLocaleString('en-IN')} points</h2></div><span className={`tier-chip tier-${loyalty.tier.toLowerCase()}`}>{loyalty.tier}</span></div>
        {loyalty.next_tier ? <><div className="progress-track"><span style={{ width: `${Math.min(100, (loyalty.points / (loyalty.next_tier === 'GOLD' ? loyalty.gold_at : loyalty.silver_at)) * 100)}%` }}/></div><p className="muted">{loyalty.points_to_next_tier.toLocaleString('en-IN')} points to {loyalty.next_tier}</p></> : <p className="muted">You have reached the top tier.</p>}
        <p className="loyalty-note">Earn 1 point for every ₹100 of a confirmed fare across Railways and Airways. Points from a cancelled confirmed booking are reversed. Your points unlock discounts on flight tickets; the discount is fixed when you book.</p>
        <div className="flight-discount-tiers">
          <div className={loyalty.tier === 'BASIC' ? 'flight-discount-tier active' : 'flight-discount-tier'}><span><b>BASIC</b><small>0–999 points</small></span><strong>0% off</strong></div>
          <div className={loyalty.tier === 'SILVER' ? 'flight-discount-tier active' : 'flight-discount-tier'}><span><b>SILVER</b><small>1,000–4,999 points</small></span><strong>5% off</strong></div>
          <div className={loyalty.tier === 'GOLD' ? 'flight-discount-tier active' : 'flight-discount-tier'}><span><b>GOLD</b><small>5,000+ points</small></span><strong>10% off</strong></div>
        </div>
        <p className="loyalty-current-benefit">Your current flight benefit: <b>{loyalty.flight_discount_percent}% discount</b> on the displayed dynamic flight fare.</p>
      </section>
      <section className="ledger-section">
        <div className="section-heading"><div><p className="eyebrow">POINTS LEDGER</p><h2>Recent activity <span className="count-pill">{ledger.length}</span></h2></div></div>
        {ledger.length ? <ul className="ledger-list">{ledger.map((row) => <li key={row.loyalty_txn_id}><span className={`mode-chip mode-${row.travel_mode.toLowerCase()}`}>{row.travel_mode}</span><span>Booking #{row.booking_ref}</span><span className="muted">{formatDate(row.created_at, { day: 'numeric', month: 'short' })}</span><b className={row.points > 0 ? 'points-up' : 'points-down'}>{row.points > 0 ? '+' : ''}{row.points}</b></li>)}</ul> : <p className="muted">Points appear here after your first confirmed booking.</p>}
      </section>
      <section className="ledger-section">
        <div className="section-heading"><div><p className="eyebrow">UNIFIED TRIP HISTORY</p><h2>Rail and air together <span className="count-pill">{trips.length}</span></h2></div></div>
        {trips.length ? <ul className="ledger-list trip-list">{trips.map((trip) => <li key={`${trip.travel_mode}-${trip.booking_ref}`}><span className={`mode-chip mode-${trip.travel_mode.toLowerCase()}`}>{trip.travel_mode}</span><span><b>{trip.carrier}</b> {trip.service_number}</span><span>{trip.origin} → {trip.destination}</span><span className="muted">{formatDate(trip.travel_date)}</span>{trip.travel_mode === 'AIR' && Number(trip.loyalty_discount_amount) > 0 && <span className="trip-discount-saved">Saved {formatMoney(trip.loyalty_discount_amount)} ({Number(trip.loyalty_discount_percent)}%)</span>}<span className={`status-pill ${getStatusClass(trip.status === 'WAITLISTED' ? 'STANDBY' : trip.status)}`}>{trip.status}</span></li>)}</ul> : <p className="muted">No trips yet.</p>}
      </section>
    </>
  );

  const adminPanel = () => (
    <section className="admin-overview">
      <div className="feature-banner"><div className="feature-banner-icon"><Icon name="admin" size={26}/></div><div className="feature-banner-copy"><p className="eyebrow eyebrow-light">AIRLINE CONSOLE</p><h2>Airline module at a glance</h2><p>Live totals from the airline database. Create a flight schedule to see the aircraft conflict trigger work.</p></div><button className="button button-banner-action" type="button" onClick={handleFinalizeAirHistory}>Finalize past outcomes</button></div>
      {adminSummary ? <div className="admin-stat-grid">
        <StatCard label="Open flights" value={adminSummary.open_flights} caption="Future bookable schedules" icon="plane" tone="tone-blue"/>
        <StatCard label="Aircraft" value={adminSummary.aircraft} caption={`${adminSummary.airlines} airlines`} icon="overview" tone="tone-teal"/>
        <StatCard label="All bookings" value={adminSummary.total_bookings} caption="Across all passengers" icon="bookings" tone="tone-orange"/>
        <StatCard label="On standby" value={adminSummary.current_standby} caption="Waiting for a seat" icon="clock" tone="tone-purple"/>
        <StatCard label="Standby promotions" value={adminSummary.promotions} caption="Promoted by database trigger" icon="check" tone="tone-green"/>
        <StatCard label="Cancellations" value={adminSummary.cancellations} caption="Cancellation records" icon="close" tone="tone-red"/>
        <StatCard label="Baggage fees" value={formatMoney(adminSummary.baggage_fees)} caption="Excess baggage collected" icon="bag" tone="tone-indigo"/>
        <StatCard label="Loyalty points issued" value={Number(adminSummary.loyalty_points_issued).toLocaleString('en-IN')} caption="Rail and air combined" icon="star" tone="tone-teal"/>
        <StatCard label="Flight discounts applied" value={formatMoney(adminSummary.flight_discounts_given)} caption="Total loyalty savings on air bookings" icon="star" tone="tone-purple"/>
      </div> : <div className="inline-loading"><span className="spinner"/> Loading system metrics…</div>}
      <section className="admin-form-panel">
        <div className="section-heading"><div><p className="eyebrow">NOVELTY A4</p><h2>Schedule a flight</h2><p className="muted">An aircraft cannot fly two overlapping schedules (45-minute turnaround) and must belong to the flight's airline. Try DS150 with VT-DS01 on the same date as DS101.</p></div></div>
        <form className="admin-form-grid" onSubmit={handleCreateSchedule}>
          <div className="field-group"><label htmlFor="sch-flight">FLIGHT</label><select id="sch-flight" value={scheduleForm.flight_id} onChange={(e) => setScheduleForm({ ...scheduleForm, flight_id: e.target.value })} required><option value="">Choose flight</option>{scheduleOptions.flights.map((f) => <option key={f.flight_id} value={f.flight_id}>{f.flight_number} · {f.origin_code}→{f.destination_code} · {f.departure_time}–{f.arrival_time}</option>)}</select></div>
          <div className="field-group"><label htmlFor="sch-aircraft">AIRCRAFT</label><select id="sch-aircraft" value={scheduleForm.aircraft_id} onChange={(e) => setScheduleForm({ ...scheduleForm, aircraft_id: e.target.value })} required><option value="">Choose aircraft</option>{scheduleOptions.aircraft.map((a) => <option key={a.aircraft_id} value={a.aircraft_id}>{a.registration_no} · {a.airline_name} · {a.economy_seats}E/{a.business_seats}B</option>)}</select></div>
          <div className="field-group"><label htmlFor="sch-date">DATE</label><input id="sch-date" type="date" min={localDatePlus(0)} value={scheduleForm.flight_date} onChange={(e) => setScheduleForm({ ...scheduleForm, flight_date: e.target.value })} required/></div>
          <div className="field-group"><label htmlFor="sch-limit">STANDBY LIMIT</label><input id="sch-limit" type="number" min="0" max="20" value={scheduleForm.overbook_limit} onChange={(e) => setScheduleForm({ ...scheduleForm, overbook_limit: e.target.value })} required/></div>
          <button className="button button-primary" type="submit" disabled={scheduleBusy}>{scheduleBusy ? 'Creating…' : 'Create schedule'}</button>
        </form>
        <ul className="ledger-list">{scheduleOptions.schedules.map((s) => <li key={s.flight_schedule_id}><span className="mode-chip mode-air">#{s.flight_schedule_id}</span><span><b>{s.flight_number}</b></span><span>{formatDate(s.flight_date)}</span><span className="muted">{s.registration_no}</span><span className="muted">standby limit {s.overbook_limit}</span></li>)}</ul>
      </section>
    </section>
  );

  const navButton = (view, icon, label, count) => <button className={activeView === view ? 'nav-item active' : 'nav-item'} onClick={() => { setActiveView(view); setError(''); }}><Icon name={icon}/><span>{label}</span>{count > 0 && <i className="nav-count">{count}</i>}</button>;

  return (
    <div className="app-shell">
      <aside className="sidebar">
        <div className="sidebar-brand"><Brand light product="AIR"/></div>
        <div className="sidebar-section-label">WORKSPACE</div>
        <nav className="sidebar-nav" aria-label="Main navigation">
          {navButton('overview', 'overview', 'Overview')}
          {navButton('search', 'search', 'Find a flight')}
          {navButton('bookings', 'bookings', 'My flights', summary.standby)}
          {navButton('loyalty', 'star', 'Loyalty and trips')}
          <div className="sidebar-section-label sidebar-section-spaced">OTHER SERVICES</div>
          <button className="nav-item" onClick={() => navigate('/dashboard')}><Icon name="train"/><span>Railway booking</span></button>
          {isAdmin && <><div className="sidebar-section-label sidebar-section-spaced">MANAGEMENT</div>{navButton('admin', 'admin', 'Airline console')}</>}
        </nav>
        <div className="sidebar-lower">
          <div className="sidebar-user"><div className="avatar avatar-small">{getInitials(user?.full_name)}</div><div className="sidebar-user-details"><strong>{user?.full_name || 'Passenger'}</strong><small>{isAdmin ? 'Administrator' : 'Passenger account'}</small></div><button className="logout-icon" onClick={logout} aria-label="Log out" title="Log out"><Icon name="logout" size={17}/></button></div>
        </div>
      </aside>
      <main className="main-area">
        <header className="topbar"><div className="breadcrumb"><span>Airways</span><b>/</b><strong>{titleMap[activeView]}</strong></div><div className="topbar-right"><span className="service-status"><i/> System ready</span></div></header>
        <div className="content-area">
          {error && <div className="alert alert-error dashboard-alert" role="alert"><span>!</span>{error}<button onClick={() => setError('')} aria-label="Dismiss error"><Icon name="close" size={16}/></button></div>}
          {loading ? <div className="dashboard-loading"><span className="spinner spinner-dark"/><p>Preparing your flight dashboard…</p></div> : <>
            {activeView === 'overview' && <>
              <div className="page-intro"><div><p className="eyebrow">{formatDate(new Date(), { weekday: 'long', day: 'numeric', month: 'long', year: 'numeric' }).toUpperCase()}</p><h1>Your flights, <em>in the air.</em></h1><p className="muted">Book a seat, join the priority standby list, add baggage and earn points shared with your rail journeys.</p></div></div>
              <div className="stats-grid">
                <StatCard label="Total flights" value={summary.total} caption="Bookings you've made" icon="bookings" tone="tone-indigo"/>
                <StatCard label="Confirmed" value={summary.confirmed} caption="Seats currently assigned" icon="check" tone="tone-teal"/>
                <StatCard label="On standby" value={summary.standby} caption="Waiting for a seat" icon="clock" tone="tone-orange"/>
                <StatCard label="Loyalty points" value={loyalty ? loyalty.points.toLocaleString('en-IN') : 0} caption={loyalty ? `${loyalty.tier} tier` : 'BASIC tier'} icon="star" tone="tone-purple"/>
              </div>
              {searchPanel}{resultsPanel}{bookingsPanel(bookings.slice(0, 3), 'Your latest flights')}
            </>}
            {activeView === 'search' && <><div className="page-intro compact-intro"><div><p className="eyebrow">DISCOVER YOUR ROUTE</p><h1>Find your next <em>flight.</em></h1><p className="muted">Search the demo network by origin, destination, date, and cabin.</p></div></div>{searchPanel}{resultsPanel}</>}
            {activeView === 'bookings' && <><div className="page-intro compact-intro"><div><p className="eyebrow">YOUR TRAVEL TIMELINE</p><h1>Every flight, <em>in one place.</em></h1><p className="muted">Seats, standby position, baggage and refunds.</p></div></div>{bookingsPanel()}</>}
            {activeView === 'loyalty' && <><div className="page-intro compact-intro"><div><p className="eyebrow">ONE ACCOUNT, TWO MODES</p><h1>Loyalty and <em>trips.</em></h1><p className="muted">Points and tier are shared by the railway and airline modules.</p></div></div>{loyaltyPanel}</>}
            {activeView === 'admin' && isAdmin && adminPanel()}
          </>}
          <footer className="dashboard-footer"><span>AIRWAYS+ <b>·</b> DATABASE SYSTEMS PROJECT</span><span>Fictional airlines and airports for demonstration.</span></footer>
        </div>
      </main>
      {toast && <div className={`toast toast-${toast.tone}`} role="status"><span className="toast-mark">{toast.tone === 'error' ? '!' : toast.tone === 'info' ? 'i' : '✓'}</span><span>{toast.message}</span><button onClick={() => setToast(null)} aria-label="Dismiss notification"><Icon name="close" size={15}/></button></div>}
      {busyBookingId && <div className="action-busy-overlay"><div><span className="spinner spinner-dark"/><p>Updating booking #{busyBookingId}…</p></div></div>}
    </div>
  );
}
