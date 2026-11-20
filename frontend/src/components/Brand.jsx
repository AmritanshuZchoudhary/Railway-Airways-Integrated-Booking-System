export default function Brand({ light = false, compact = false, product = 'RAILWAY' }) {
  const isAir = product === 'AIR';
  const isBoth = product === 'BOTH';
  return (
    <div className={`brand ${light ? 'brand-light' : ''} ${compact ? 'brand-compact' : ''} ${isBoth ? 'brand-both' : ''}`}>
      <div className="brand-mark" aria-hidden="true">
        {isBoth ? (
          <svg viewBox="0 0 64 40" fill="none">
            <rect x="1" y="1" width="62" height="38" rx="13" fill="currentColor" opacity=".14" />
            {/* dotted link between the two modes */}
            <path d="M30 20h5" stroke="currentColor" strokeWidth="1.6" strokeLinecap="round" strokeDasharray="1.5 3" opacity=".6" />
            {/* Train (left) */}
            <g transform="translate(1.8 2.8) scale(.8)" stroke="currentColor" strokeWidth="2.4" strokeLinecap="round" strokeLinejoin="round">
              <path d="M12 9h16a3 3 0 0 1 3 3v13a5 5 0 0 1-5 5H14a5 5 0 0 1-5-5V12a3 3 0 0 1 3-3Z" />
              <path d="M12 17h16M14 30l-3 4m15-4 3 4M15 23h.01M25 23h.01" />
            </g>
            {/* Plane (right) */}
            <g transform="translate(36 8.5) scale(1.05)" stroke="currentColor" strokeWidth="2" strokeLinecap="round" strokeLinejoin="round">
              <path d="M21 3 3 10.5l6.5 3L12.5 21 21 3ZM9.5 13.5 15 8" />
            </g>
          </svg>
        ) : (
          <svg viewBox="0 0 40 40" fill="none">
            <rect x="1" y="1" width="38" height="38" rx="12" fill="currentColor" opacity=".14" />
            {isAir ? (
              <path d="M31 9 9 18l8 4 4 8 10-21ZM17 22l7-5" stroke="currentColor" strokeWidth="2.2" strokeLinecap="round" strokeLinejoin="round" />
            ) : (
              <>
                <path d="M12 9h16a3 3 0 0 1 3 3v13a5 5 0 0 1-5 5H14a5 5 0 0 1-5-5V12a3 3 0 0 1 3-3Z" stroke="currentColor" strokeWidth="2" />
                <path d="M12 16h16M14 30l-3 4m15-4 3 4M15 22h.01M25 22h.01" stroke="currentColor" strokeWidth="2.4" strokeLinecap="round" />
              </>
            )}
          </svg>
        )}
      </div>
      <div className="brand-copy">
        <strong>{isBoth ? 'RAILWAYS + AIRWAYS' : isAir ? 'AIRWAYS' : 'RAILWAY'}{!isBoth && <span>+</span>}</strong>
        {!compact && <small>{isBoth ? 'ONE TRAVEL PORTAL' : 'JOURNEY INTELLIGENCE'}</small>}
      </div>
    </div>
  );
}