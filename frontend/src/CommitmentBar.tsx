import { useState } from 'react';
import type { Summary } from './types';

/**
 * Stacked horizontal bar of the 2×2 advocacy × committed-behavior averages
 * over the whole run, plus the "uncommitted" remainder.
 *
 *   advC / playC : aligned cooperator (green)
 *   advD / playD : aligned defector   (red)
 *   advC / playD : advocates C but defects — "hypocrite-C" (amber)
 *   advD / playC : advocates D but cooperates — "hypocrite-D" (blue)
 *   uncommitted  : pr_coop in (0.15, 0.85)  (gray)
 *
 * Values are time-averaged fractions that sum to 1.
 */
const SEGMENTS: Array<{ key: keyof Summary; label: string; color: string; desc: string }> = [
  { key: 'avg_advC_playC',  label: 'advC · playC', color: '#16a34a',
    desc: "advocate C and committed cooperator (pr_coop ≥ 0.85)" },
  { key: 'avg_advC_playD',  label: 'advC · playD', color: '#f59e0b',
    desc: "advocate C but committed defector (pr_coop ≤ 0.15) — hypocrite-C" },
  { key: 'avg_advD_playC',  label: 'advD · playC', color: '#2563eb',
    desc: "advocate D but committed cooperator (pr_coop ≥ 0.85) — hypocrite-D" },
  { key: 'avg_advD_playD',  label: 'advD · playD', color: '#dc2626',
    desc: "advocate D and committed defector (pr_coop ≤ 0.15)" },
  { key: 'avg_uncommitted', label: 'uncommitted',  color: '#9ca3af',
    desc: "pr_coop between 0.15 and 0.85 (neither committed)" },
];

export function CommitmentBar({ summary }: { summary: Summary }) {
  const [hovered, setHovered] = useState<string | null>(null);

  return (
    <div className="chart-card" style={{ padding: 10 }}>
      <h3 style={{ marginBottom: 6 }}>Advocacy × committed-behavior (run average)</h3>
      <div className="gt-bar" onMouseLeave={() => setHovered(null)}>
        {SEGMENTS.map((s) => {
          const frac = Math.max(0, Number(summary[s.key] ?? 0));
          if (frac === 0) return null;
          return (
            <div key={s.key}
                 className="gt-seg"
                 style={{
                   width: `${frac * 100}%`,
                   background: s.color,
                   opacity: hovered && hovered !== s.key ? 0.35 : 1,
                 }}
                 onMouseEnter={() => setHovered(s.key)}
                 title={`${s.label}: ${(frac * 100).toFixed(1)}% — ${s.desc}`} />
          );
        })}
      </div>
      <div className="gt-legend">
        {SEGMENTS.map((s) => {
          const frac = Math.max(0, Number(summary[s.key] ?? 0));
          return (
            <span key={s.key}
                  className={'gt-pill' + (hovered === s.key ? ' active' : '')}
                  style={{ borderColor: s.color }}
                  onMouseEnter={() => setHovered(s.key)}
                  title={s.desc}>
              <span className="sw" style={{ background: s.color }} />
              {s.label} {(frac * 100).toFixed(1)}%
            </span>
          );
        })}
      </div>
    </div>
  );
}
