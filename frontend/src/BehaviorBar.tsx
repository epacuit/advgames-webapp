import type { BehaviorCounts } from './types';

/**
 * Cumulative-plays bar chart. Each bar is a count of one kind of (advocacy,
 * play) combination that has actually been realized in the simulation so far.
 * Bars grow by 2 per round (the 2 agents that interact). The y-axis is
 * normalized to the final total (= 2 × numrounds) so you can watch the
 * buckets fill up to their share of the whole.
 *
 * This is distinct from the inclination-based CommitmentBar in ResultView,
 * because mutations mean actual plays don't always match inclinations.
 */
const SEGMENTS: Array<{ key: keyof BehaviorCounts; label: string; sub: string; color: string }> = [
  { key: 'advC_playC', label: 'advC · playC', sub: 'coop advocate, cooperates', color: '#16a34a' },
  { key: 'advC_playD', label: 'advC · playD', sub: 'coop advocate, defects',     color: '#f59e0b' },
  { key: 'advD_playC', label: 'advD · playC', sub: 'defect advocate, cooperates', color: '#2563eb' },
  { key: 'advD_playD', label: 'advD · playD', sub: 'defect advocate, defects',   color: '#dc2626' },
];

export function BehaviorBar({ counts, frame, numrounds }: {
  counts: BehaviorCounts;
  frame: number;
  numrounds: number;
}) {
  // Clamp frame access.
  const idx = Math.max(0, Math.min(frame, counts.advC_playC.length - 1));
  const vals = SEGMENTS.map((s) => ({ ...s, value: counts[s.key][idx] ?? 0 }));
  const totalNow = vals.reduce((a, b) => a + b.value, 0);
  // Scale so the tallest possible bar (everything in one bucket at run-end)
  // is the full plot height. That way bars grow smoothly over a run.
  const maxScale = Math.max(1, 2 * numrounds);

  const size = { w: 480, h: 270, pad: { l: 44, r: 16, t: 20, b: 38 } };
  const plotW = size.w - size.pad.l - size.pad.r;
  const plotH = size.h - size.pad.t - size.pad.b;
  const gap   = 28;
  const barW  = (plotW - (vals.length - 1) * gap) / vals.length;

  const yFor = (v: number) => size.pad.t + plotH * (1 - v / maxScale);

  // Pick nice y ticks
  const tickValues = [0, 0.25, 0.5, 0.75, 1].map((f) => Math.round(maxScale * f));

  return (
    <div className="chart-card" style={{ padding: 10 }}>
      <h3 style={{ marginBottom: 4 }}>Behavior so far</h3>
      <div style={{ fontSize: 11, color: '#666', marginBottom: 6 }}>
        {totalNow.toLocaleString()} plays / {maxScale.toLocaleString()} total
      </div>
      <svg viewBox={`0 0 ${size.w} ${size.h}`} width="100%"
           style={{ maxWidth: size.w, height: 'auto' }}>
        {/* y gridlines + labels */}
        {tickValues.map((v) => (
          <g key={v}>
            <line x1={size.pad.l} y1={yFor(v)} x2={size.w - size.pad.r} y2={yFor(v)}
                  stroke="#eee" />
            <text x={size.pad.l - 4} y={yFor(v) + 3} textAnchor="end"
                  fontSize={9} fill="#888">{abbrev(v)}</text>
          </g>
        ))}

        {/* bars */}
        {vals.map((v, i) => {
          const x = size.pad.l + i * (barW + gap);
          const h = (v.value / maxScale) * plotH;
          const y = size.pad.t + plotH - h;
          return (
            <g key={v.key}>
              <title>{v.label} — {v.sub}: {v.value.toLocaleString()} plays</title>
              <rect x={x} y={y} width={barW} height={h}
                    fill={v.color} rx={4} />
              {/* count label just above the top of the bar (or at the baseline if bar is empty) */}
              <text x={x + barW / 2}
                    y={Math.max(size.pad.t + 11, y - 5)}
                    textAnchor="middle" fontSize={11} fontWeight={700}
                    fill={v.color}>
                {abbrev(v.value)}
              </text>
              <text x={x + barW / 2} y={size.pad.t + plotH + 16}
                    textAnchor="middle" fontSize={11} fontWeight={600}
                    fill={v.color}>
                {v.label}
              </text>
            </g>
          );
        })}

        {/* baseline */}
        <line x1={size.pad.l} y1={size.pad.t + plotH}
              x2={size.w - size.pad.r} y2={size.pad.t + plotH}
              stroke="#cbd5e1" />
      </svg>
    </div>
  );
}

function abbrev(n: number): string {
  if (n >= 1_000_000) return (n / 1_000_000).toFixed(1).replace(/\.0$/, '') + 'M';
  if (n >= 1_000)     return (n / 1_000).toFixed(1).replace(/\.0$/, '') + 'k';
  return String(n);
}
