import { useMemo, useState } from 'react';

// Distinct, paper-adjacent palette. Greens for cooperation-favorable games,
// reds for defection-favorable, neutral for the mixed/other categories.
export const GAME_TYPE_COLORS: Record<string, string> = {
  PD:    '#dc2626',  // Prisoner's Dilemma
  WPD:   '#f87171',  // Weak PD
  PDm:   '#7f1d1d',  // Prisoner's Dismay (worst)
  CH:    '#fb923c',  // Chicken (mixed motive)
  SH:    '#16a34a',  // Stag Hunt
  WSH:   '#86efac',  // Weak Stag Hunt
  PDe:   '#2563eb',  // Prisoner's Delight
  Other: '#9ca3af',  // Other
};

export function GameTypeBar({ gameTypes }: { gameTypes: string[] }) {
  const { items, total } = useMemo(() => {
    const counts: Record<string, number> = {};
    for (const t of gameTypes) counts[t] = (counts[t] ?? 0) + 1;
    const total = gameTypes.length;
    const items = Object.entries(counts)
      .map(([name, count]) => ({ name, count, frac: count / total }))
      .sort((a, b) => b.count - a.count);
    return { items, total };
  }, [gameTypes]);

  const [hovered, setHovered] = useState<string | null>(null);

  return (
    <div className="chart-card" style={{ padding: 10 }}>
      <h3 style={{ marginBottom: 6 }}>Game type over the run</h3>
      <div className="gt-bar" onMouseLeave={() => setHovered(null)}>
        {items.map((it) => (
          <div
            key={it.name}
            className="gt-seg"
            style={{
              width: `${it.frac * 100}%`,
              background: GAME_TYPE_COLORS[it.name] ?? '#9ca3af',
              opacity: hovered && hovered !== it.name ? 0.35 : 1,
            }}
            onMouseEnter={() => setHovered(it.name)}
            title={`${it.name}: ${(it.frac * 100).toFixed(1)}% (${it.count.toLocaleString()} / ${total.toLocaleString()})`}
          />
        ))}
      </div>
      <div className="gt-legend">
        {items.map((it) => (
          <span key={it.name}
                className={'gt-pill' + (hovered === it.name ? ' active' : '')}
                style={{ borderColor: GAME_TYPE_COLORS[it.name] ?? '#9ca3af' }}
                onMouseEnter={() => setHovered(it.name)}>
            <span className="sw" style={{ background: GAME_TYPE_COLORS[it.name] ?? '#9ca3af' }} />
            {it.name} {(it.frac * 100).toFixed(1)}%
          </span>
        ))}
      </div>
    </div>
  );
}
