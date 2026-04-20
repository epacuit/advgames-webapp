import { useMemo } from 'react';

/**
 * Phase portrait of a single run, rendered as a density heatmap.
 *
 *   x = pr_adv_coop   (fraction of population advocating C)
 *   y = avg_incl      (mean cooperation inclination)
 *
 * We grid the [0,1] × [0,1] plot area into GRID × GRID cells, count how
 * many rounds fall into each cell, and shade each cell by the log of its
 * count. Darker = more time spent there. A thin faint line shows the
 * full trajectory for context; S / E mark start and end.
 *
 * This answers "where does the system live?" at a glance:
 *   - a dark blob in the top-right  → locked into the CN norm
 *   - a dark blob in the bottom-left → locked into the UN norm
 *   - a diffuse cloud                → no norm formed
 *   - two blobs with a bridge        → bistable / transitions between norms
 */
const GRID = 30;                 // heatmap resolution
const CELL_COLOR = '#1e3a8a';    // navy — neutral, distinct from R/G
const START_STROKE = '#1e3a8a';
const END_FILL = '#1e3a8a';

export function PhasePortrait({ prAdvCoop, avgIncl }: {
  // `rounds` used to be a prop but is no longer needed since the round label
  // was removed. Kept the variable name in callers for clarity.
  rounds?: number[];
  prAdvCoop: number[];
  avgIncl: number[];
}) {
  const size = 380;
  const pad = 40;
  const plot = size - 2 * pad;
  const xScale = (x: number) => pad + x * plot;
  const yScale = (y: number) => pad + (1 - y) * plot; // SVG y is inverted

  // Count rounds per cell, log-normalize for visibility.
  const { hist, logMax } = useMemo(() => {
    const h = new Array(GRID * GRID).fill(0);
    const n = Math.min(prAdvCoop.length, avgIncl.length);
    for (let i = 0; i < n; i++) {
      const x = prAdvCoop[i], y = avgIncl[i];
      const cx = Math.min(GRID - 1, Math.max(0, Math.floor(x * GRID)));
      const cy = Math.min(GRID - 1, Math.max(0, Math.floor(y * GRID)));
      h[cy * GRID + cx] += 1;
    }
    const max = h.reduce((a, b) => (b > a ? b : a), 0);
    return { hist: h, logMax: Math.log(1 + max) };
  }, [prAdvCoop, avgIncl]);

  const n = Math.min(prAdvCoop.length, avgIncl.length);
  const startX = pts(0, xScale, prAdvCoop);
  const startY = pts(0, yScale, avgIncl);
  const endX   = pts(n - 1, xScale, prAdvCoop);
  const endY   = pts(n - 1, yScale, avgIncl);

  return (
    <div className="chart-card">
      <h3>Phase portrait — density of time spent in each region</h3>
      <div style={{ display: 'flex', justifyContent: 'center' }}>
        <svg viewBox={`0 0 ${size} ${size}`}
             style={{ width: '100%', maxWidth: size, height: 'auto' }}
             role="img" aria-label="phase-portrait density heatmap">
          {/* CN target corner (top-right) */}
          <rect x={xScale(0.5)} y={yScale(1)}
                width={xScale(1) - xScale(0.5)}
                height={yScale(0.8) - yScale(1)}
                fill="#16a34a" fillOpacity={0.10} />
          {/* UN target corner (bottom-left) */}
          <rect x={xScale(0)} y={yScale(0.2)}
                width={xScale(0.5) - xScale(0)}
                height={yScale(0) - yScale(0.2)}
                fill="#dc2626" fillOpacity={0.10} />

          {/* density cells */}
          {hist.map((count, idx) => {
            if (count === 0) return null;
            const cx = idx % GRID;
            const cy = Math.floor(idx / GRID);
            const x0 = xScale(cx / GRID);
            const x1 = xScale((cx + 1) / GRID);
            const y1 = yScale(cy / GRID);        // bottom edge in SVG
            const y0 = yScale((cy + 1) / GRID);  // top edge in SVG
            const intensity = Math.log(1 + count) / logMax; // 0..1
            return (
              <rect key={idx}
                    x={x0} y={y0}
                    width={x1 - x0} height={y1 - y0}
                    fill={CELL_COLOR}
                    fillOpacity={intensity * 0.85}
                    shapeRendering="crispEdges" />
            );
          })}

          {/* axis box + midlines */}
          <rect x={pad} y={pad} width={plot} height={plot} fill="none" stroke="#ddd" />
          <line x1={xScale(0.5)} y1={pad} x2={xScale(0.5)} y2={pad + plot}
                stroke="#cbd5e1" strokeDasharray="3 3" />
          <line x1={pad} y1={yScale(0.5)} x2={pad + plot} y2={yScale(0.5)}
                stroke="#cbd5e1" strokeDasharray="3 3" />

          {/* start marker */}
          <circle cx={startX} cy={startY} r={8}
                  fill="#ffffff" stroke={START_STROKE} strokeWidth={2} />
          <text x={startX} y={startY + 3.5}
                textAnchor="middle" fontSize={10} fontWeight={700}
                fill={START_STROKE}>S</text>

          {/* end marker */}
          <circle cx={endX} cy={endY} r={8}
                  fill={END_FILL} stroke="#fff" strokeWidth={2} />
          <text x={endX} y={endY + 3.5}
                textAnchor="middle" fontSize={10} fontWeight={700}
                fill="#fff">E</text>

          {/* corner labels */}
          <text x={xScale(0.99)} y={yScale(0.99) + 14} textAnchor="end"
                fontSize={10} fill="#166534" fontWeight={600} opacity={0.7}>
            CN target
          </text>
          <text x={xScale(0.01)} y={yScale(0.01) - 6}
                fontSize={10} fill="#991b1b" fontWeight={600} opacity={0.7}>
            UN target
          </text>

          {/* axis titles */}
          <text x={pad + plot / 2} y={size - 8} textAnchor="middle"
                fontSize={11} fill="#555">pr advocating C →</text>
          <text x={12} y={pad + plot / 2} textAnchor="middle"
                fontSize={11} fill="#555"
                transform={`rotate(-90 12 ${pad + plot / 2})`}>
            avg cooperation →
          </text>

          {/* tick labels */}
          {[0, 0.5, 1].map((t) => (
            <g key={t}>
              <text x={xScale(t)} y={pad + plot + 14} textAnchor="middle"
                    fontSize={10} fill="#888">{t}</text>
              <text x={pad - 6} y={yScale(t) + 4} textAnchor="end"
                    fontSize={10} fill="#888">{t}</text>
            </g>
          ))}
        </svg>
      </div>
      <div className="legend-swatches">
        <span style={{ display: 'inline-flex', alignItems: 'center', gap: 4 }}>
          <svg width="70" height="10">
            <defs>
              <linearGradient id="pp-ramp" x1="0" x2="1" y1="0" y2="0">
                <stop offset="0%"   stopColor={CELL_COLOR} stopOpacity="0" />
                <stop offset="100%" stopColor={CELL_COLOR} stopOpacity="0.85" />
              </linearGradient>
            </defs>
            <rect width="70" height="10" fill="url(#pp-ramp)" />
          </svg>
          few → many rounds in cell (log-scaled)
        </span>
        <span>
          <svg width="14" height="14" style={{ verticalAlign: 'middle', marginRight: 4 }}>
            <circle cx="7" cy="7" r="5" fill="#fff" stroke={START_STROKE} strokeWidth={1.5} />
          </svg>
          start (S)
        </span>
        <span>
          <svg width="14" height="14" style={{ verticalAlign: 'middle', marginRight: 4 }}>
            <circle cx="7" cy="7" r="5" fill={END_FILL} />
          </svg>
          end (E)
        </span>
        <span style={{ marginLeft: 18, borderLeft: '1px solid #ddd', paddingLeft: 14 }}>
          <em>targets:</em>
        </span>
        <span><span className="sw" style={{ background: 'rgba(22,163,74,0.22)' }}></span>CN (advC ≥ 0.5, coop ≥ 0.8)</span>
        <span><span className="sw" style={{ background: 'rgba(220,38,38,0.22)' }}></span>UN (advC ≤ 0.5, coop ≤ 0.2)</span>
      </div>
    </div>
  );
}

function pts(i: number, scale: (v: number) => number, arr: number[]): number {
  return scale(arr[Math.max(0, Math.min(i, arr.length - 1))] ?? 0);
}
