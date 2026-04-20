import { useEffect, useMemo, useRef, useState } from 'react';
import { BehaviorBar } from './BehaviorBar';
import { LocalNormChart } from './LocalNormChart';
import { NormTimeline } from './NormTimeline';
import type { AgentSeries, RunResponse, Topology } from './types';

/**
 * Agent-grid playback.
 *
 * Each agent is a cell in a grid. Its fill encodes the current cooperation
 * inclination (red → gray → blue diverging ramp); its border encodes current
 * advocacy (green = C, red = D). A small letter in the top-right makes the
 * advocacy unambiguous when the fill is ambiguous (e.g., a midway inclination).
 *
 * Playback uses the already-downsampled per-agent arrays that come back when
 * "collect per-agent data" is enabled. No new backend request is needed.
 */
const C_COLOR = '#15803d';   // deep green — advocating C
const D_COLOR = '#991b1b';   // deep red   — advocating D

function inclinationFill(incl: number): string {
  // Traffic-light ramp aligned with the rest of the UI:
  //   0   = red    (#dc2626) — full-defect inclination
  //   0.5 = orange (#f59e0b) — middling
  //   1   = green  (#16a34a) — full-cooperate inclination
  const t = Math.max(0, Math.min(1, incl));
  if (t < 0.5) {
    // red #dc2626 (220,38,38) → orange #f59e0b (245,158,11)
    const k = t * 2;
    const r = Math.round(220 + (245 - 220) * k);
    const g = Math.round( 38 + (158 -  38) * k);
    const b = Math.round( 38 + ( 11 -  38) * k);
    return `rgb(${r},${g},${b})`;
  } else {
    // orange #f59e0b (245,158,11) → green #16a34a (22,163,74)
    const k = (t - 0.5) * 2;
    const r = Math.round(245 + ( 22 - 245) * k);
    const g = Math.round(158 + (163 - 158) * k);
    const b = Math.round( 11 + ( 74 -  11) * k);
    return `rgb(${r},${g},${b})`;
  }
}

export function AnimationView({ r }: { r: RunResponse }) {
  const agents = r.series.agents;
  const nFrames = agents[0]?.inclination.length ?? 0;
  const rounds = r.series.rounds;

  // All hooks must run on every render — keep them above any early return.
  const [frame, setFrame] = useState(0);
  const [playing, setPlaying] = useState(false);
  const [fps, setFps] = useState<number>(10);

  const playingRef = useRef(playing);
  playingRef.current = playing;

  // Reset the animation whenever a new run comes back from the server.
  useEffect(() => {
    setFrame(0);
    setPlaying(false);
  }, [r]);

  useEffect(() => {
    if (!playing || nFrames === 0) return;
    const id = window.setInterval(() => {
      setFrame((f) => {
        const next = f + 1;
        if (next >= nFrames) {
          setPlaying(false);
          return nFrames - 1;
        }
        return next;
      });
    }, Math.max(10, Math.round(1000 / fps)));
    return () => window.clearInterval(id);
  }, [playing, fps, nFrames]);

  if (agents.length === 0) {
    return (
      <div className="empty" style={{ flexDirection: 'column', gap: 8 }}>
        <div>No per-agent data in the current result.</div>
        <div style={{ fontSize: 12 }}>
          Enable <code>collect per-agent data</code> in the sidebar and run again.
        </div>
      </div>
    );
  }

  const onPlayPause = () => {
    if (!playing && frame >= nFrames - 1) setFrame(0); // restart if at end
    setPlaying((p) => !p);
  };

  const behavior = r.series.behavior;

  return (
    <>
      {r.series.local_counts && (
        <LocalNormChart counts={r.series.local_counts}
                        rounds={rounds}
                        totalAgents={r.population}
                        currentFrame={frame} />
      )}

      <div className="anim-row">
        <AgentGrid agents={agents} frame={frame} topology={r.series.topology} />
        {behavior && (
          <BehaviorBar counts={behavior} frame={frame} numrounds={r.numrounds} />
        )}
      </div>

      <NormTimeline
        rounds={rounds}
        inCnNorm={r.series.in_cn_norm}
        inUnNorm={r.series.in_un_norm}
        propCc={r.series.prop_cc}
        propDd={r.series.prop_dd}
        prAdvCoop={r.series.pr_adv_coop}
        currentFrame={frame}
        onScrub={(f) => { setFrame(f); setPlaying(false); }}
      />

      <div className="playback">
        <button className="pb-btn" onClick={onPlayPause}
                aria-label={playing ? 'pause' : 'play'}>
          {playing ? '⏸︎' : '▶︎'}
        </button>
        <button className="pb-btn secondary"
                onClick={() => { setFrame(0); setPlaying(false); }}
                title="reset to round 0">⟲</button>
        <div className="pb-frame-only">
          frame {frame + 1} / {nFrames}
        </div>
        <input type="range"
               min={0} max={nFrames - 1} value={frame}
               onChange={(e) => { setFrame(Number(e.target.value)); setPlaying(false); }} />
        <label className="pb-speed">
          speed
          <select value={fps} onChange={(e) => setFps(Number(e.target.value))}>
            <option value={5}>0.5×</option>
            <option value={10}>1×</option>
            <option value={20}>2×</option>
            <option value={40}>4×</option>
            <option value={80}>8×</option>
          </select>
        </label>
      </div>

      <div className="anim-legend legend-swatches">
        <span style={{ marginRight: 12 }}><em>fill — inclination:</em></span>
        <span style={{ display: 'inline-flex', alignItems: 'center', gap: 6 }}>
          <span style={{ fontSize: 11, color: '#555' }}>0 defect</span>
          <svg width="160" height="14" style={{ verticalAlign: 'middle' }}>
            <defs>
              <linearGradient id="incl-ramp" x1="0" x2="1" y1="0" y2="0">
                <stop offset="0%"   stopColor={inclinationFill(0)} />
                <stop offset="50%"  stopColor={inclinationFill(0.5)} />
                <stop offset="100%" stopColor={inclinationFill(1)} />
              </linearGradient>
            </defs>
            <rect width="160" height="14" fill="url(#incl-ramp)" stroke="#bbb" />
            {/* 0.5 tick indicator above the middle */}
            <line x1="80" y1="-2" x2="80" y2="0" stroke="#555" />
          </svg>
          <span style={{ fontSize: 11, color: '#555' }}>1 coop</span>
        </span>
        <span style={{ marginLeft: 14, borderLeft: '1px solid #ddd', paddingLeft: 14 }}>
          <em>border + badge — advocacy:</em>
        </span>
        <span>
          <svg width="22" height="18" style={{ verticalAlign: 'middle', marginRight: 4 }}>
            <rect x="2" y="2" width="18" height="14" rx="3" fill={C_COLOR} />
            <text x="11" y="13" textAnchor="middle" fontSize="11"
                  fontWeight="800" fill="#fff">C</text>
          </svg>
          advocating C
        </span>
        <span>
          <svg width="22" height="18" style={{ verticalAlign: 'middle', marginRight: 4 }}>
            <rect x="2" y="2" width="18" height="14" rx="3" fill={D_COLOR} />
            <text x="11" y="13" textAnchor="middle" fontSize="11"
                  fontWeight="800" fill="#fff">D</text>
          </svg>
          advocating D
        </span>
        {r.series.topology && (
          <>
            <span style={{ marginLeft: 14, borderLeft: '1px solid #ddd', paddingLeft: 14 }}>
              <em>rings (local norm):</em>
            </span>
            <span title="inner dashed ring = local norm from interaction peers">
              <svg width="20" height="14" style={{ verticalAlign: 'middle', marginRight: 4 }}>
                <rect x="2" y="2" width="16" height="10" rx="2" fill="none"
                      stroke="#15803d" strokeWidth="1.5" strokeDasharray="2 2" />
              </svg>
              interaction
            </span>
            <span title="outer solid ring = local norm from influence peers">
              <svg width="20" height="14" style={{ verticalAlign: 'middle', marginRight: 4 }}>
                <rect x="1" y="1" width="18" height="12" rx="2" fill="none"
                      stroke="#15803d" strokeWidth="1.5" />
              </svg>
              influence
            </span>
          </>
        )}
      </div>
    </>
  );
}

function AgentGrid({ agents, frame, topology }: {
  agents: AgentSeries[];
  frame: number;
  topology: Topology | null;
}) {
  // Layout:
  //   - If the run returned a lattice topology with positions, place each
  //     agent at its own (row, col) so that adjacency on screen matches
  //     adjacency in the simulation.
  //   - Otherwise, use a "roughly square" default grid (existing behavior).
  const lattice = topology?.layout.kind === 'lattice' && topology.positions
    ? topology : null;
  const isLattice = !!lattice;

  // Smaller cells when population is large (49 agents on a 7x7 needs to fit nicely).
  const cellSize = agents.length > 20 ? 52 : 80;
  const pad = 8;

  const { cols, rows } = useMemo(() => {
    if (isLattice) {
      const lay = lattice!.layout as { kind: 'lattice'; rows: number; cols: number };
      return { cols: lay.cols, rows: lay.rows };
    }
    const n = agents.length;
    const cols = Math.max(1, Math.ceil(Math.sqrt(n * 1.25)));
    const rows = Math.ceil(n / cols);
    return { cols, rows };
  }, [isLattice, lattice, agents.length]);

  const width  = pad + cols * (cellSize + pad);
  const height = pad + rows * (cellSize + pad);

  const positionFor = (ag: AgentSeries, i: number): { r: number; c: number } => {
    if (isLattice) {
      const pos = lattice!.positions![String(ag.id)];
      return pos ? { r: pos[0], c: pos[1] } : { r: 1, c: 1 };
    }
    return { r: Math.floor(i / cols) + 1, c: (i % cols) + 1 };
  };

  return (
    <div className="chart-card" style={{ display: 'flex', justifyContent: 'center' }}>
      <svg viewBox={`0 0 ${width} ${height}`}
           width="100%" style={{ maxWidth: width, height: 'auto' }}
           role="img" aria-label="agent grid">
        {agents.map((ag, i) => {
          const { r, c } = positionFor(ag, i);
          const x = pad + (c - 1) * (cellSize + pad);
          const y = pad + (r - 1) * (cellSize + pad);
          const incl = ag.inclination[frame];
          const adv  = ag.advocacy[frame];
          const fill = inclinationFill(incl);
          const bord = adv === 'C' ? C_COLOR : D_COLOR;
          const labelDark = '#111';

          // Border widths scale down when cells get smaller (network 7x7).
          const bw = cellSize >= 72 ? 7 : 5;
          const ix = x + bw / 2, iy = y + bw / 2, is = cellSize - bw;

          // Local norm rings — only in network mode. Inner ring = interaction,
          // outer ring = influence. Green if local CN, red if local UN, else none.
          const cnI = ag.local_cn_interaction?.[frame];
          const unI = ag.local_un_interaction?.[frame];
          const cnF = ag.local_cn_influence?.[frame];
          const unF = ag.local_un_influence?.[frame];
          const hasLocal = cnI !== undefined || unI !== undefined
                        || cnF !== undefined || unF !== undefined;
          const ringInColor  = cnI ? C_COLOR : unI ? D_COLOR : null;
          const ringOutColor = cnF ? C_COLOR : unF ? D_COLOR : null;
          const ringGap = 3;
          const ringW   = 2.5;

          const badgeW = cellSize >= 72 ? 22 : 18;
          const badgeH = cellSize >= 72 ? 20 : 16;
          const inclFS = cellSize >= 72 ? 20 : 13;
          const idFS   = cellSize >= 72 ? 11 : 9;
          const badgeFS = cellSize >= 72 ? 14 : 11;

          return (
            <g key={ag.id}>
              {/* OUTER ring — influence local norm */}
              {hasLocal && ringOutColor && (
                <rect x={x - ringGap} y={y - ringGap}
                      width={cellSize + 2 * ringGap} height={cellSize + 2 * ringGap}
                      rx={8 + ringGap}
                      fill="none" stroke={ringOutColor} strokeWidth={ringW}
                      strokeOpacity={0.85} />
              )}

              <rect x={ix} y={iy} width={is} height={is}
                    fill={fill} stroke={bord} strokeWidth={bw} rx={6} />

              {/* INNER ring — interaction local norm, drawn just INSIDE the
                 cell so it sits atop the fill */}
              {hasLocal && ringInColor && (
                <rect x={x + bw + 1} y={y + bw + 1}
                      width={cellSize - 2 * bw - 2} height={cellSize - 2 * bw - 2}
                      rx={4}
                      fill="none" stroke={ringInColor} strokeWidth={ringW}
                      strokeOpacity={0.85} strokeDasharray="2 2" />
              )}

              {/* advocacy badge */}
              <rect x={x + 4} y={y + 4} width={badgeW} height={badgeH}
                    fill={bord} rx={3} />
              <text x={x + 4 + badgeW / 2} y={y + 4 + badgeH / 2 + badgeFS/3}
                    textAnchor="middle" fontSize={badgeFS} fontWeight={800}
                    fill="#fff" style={{ letterSpacing: '0.5px' }}>
                {adv}
              </text>

              {/* agent id */}
              <text x={x + cellSize - 5} y={y + idFS + 5}
                    textAnchor="end" fontSize={idFS} fontWeight={700}
                    fill={labelDark} opacity={0.7}>
                #{ag.id}
              </text>

              {/* inclination value */}
              <text x={x + cellSize / 2} y={y + cellSize / 2 + inclFS/3 + 2}
                    textAnchor="middle" fontSize={inclFS} fontWeight={700}
                    fill={labelDark}>
                {incl.toFixed(2)}
              </text>
            </g>
          );
        })}
      </svg>
    </div>
  );
}
