import { useMemo } from 'react';
import { normBands } from './bands';
import { NORM_STRIP } from './normStrip';

/**
 * A horizontal timeline colored by CN / UN / middling classification across
 * the entire run. Shows a cursor line at the current playback frame. Click
 * anywhere on the strip to jump the playhead.
 */
export function NormTimeline({
  rounds, inCnNorm, inUnNorm, propCc, propDd, prAdvCoop,
  currentFrame, onScrub,
}: {
  rounds: number[];
  inCnNorm: boolean[];
  inUnNorm: boolean[];
  propCc: number[];
  propDd: number[];
  prAdvCoop: number[];
  currentFrame: number;
  onScrub?: (frame: number) => void;
}) {
  const { cn, un, mid } = useMemo(
    () => normBands(rounds, inCnNorm, inUnNorm),
    [rounds, inCnNorm, inUnNorm]);

  const n = rounds.length;
  if (n === 0) return null;
  const rMin = rounds[0];
  const rMax = rounds[n - 1];
  const span = Math.max(1, rMax - rMin);

  const height = 22;
  const frac = (r: number) => (r - rMin) / span;
  const cursorPct = frac(rounds[Math.max(0, Math.min(n - 1, currentFrame))]) * 100;

  const handleClick = (ev: React.MouseEvent<HTMLDivElement>) => {
    if (!onScrub) return;
    const rect = ev.currentTarget.getBoundingClientRect();
    const x = Math.max(0, Math.min(rect.width, ev.clientX - rect.left));
    const t = x / rect.width;
    const target = rMin + t * span;
    // find the frame whose round is nearest to `target`
    let lo = 0, hi = n - 1;
    while (lo < hi) {
      const m = (lo + hi) >> 1;
      if (rounds[m] < target) lo = m + 1; else hi = m;
    }
    onScrub(lo);
  };

  const fi = Math.max(0, Math.min(n - 1, currentFrame));
  const currentRound = rounds[fi];
  const inCn = inCnNorm[fi];
  const inUn = inUnNorm[fi];
  const stateLabel = inCn ? 'CN norm' : inUn ? 'UN norm' : 'no norm';
  const stateColor = inCn ? NORM_STRIP.cnColor
                    : inUn ? NORM_STRIP.unColor
                    : NORM_STRIP.midColor;

  const pctCc = propCc[fi] ?? 0;
  const pctDd = propDd[fi] ?? 0;
  const pctAdvC = prAdvCoop[fi] ?? 0;
  const pctAdvD = 1 - pctAdvC;

  const fmt = (x: number) => `${(x * 100).toFixed(0)}%`;

  return (
    <div className="norm-timeline-wrap">
      <div className="norm-timeline-header">
        <span className="norm-timeline-label">round {currentRound.toLocaleString()} — </span>
        <span className="norm-state-badge"
              style={{ background: stateColor,
                       opacity: inCn || inUn ? 0.9 : 0.7 }}>
          {stateLabel}
        </span>
      </div>
      <div className="norm-pct-row">
        <span className="norm-pct-group">
          <span className="norm-pct-group-label">committed</span>
          <span className="norm-pct pct-coop"
                title="fraction of agents with pr_coop ≥ 0.85">
            <b>{fmt(pctCc)}</b> C
          </span>
          <span className="norm-pct pct-def"
                title="fraction of agents with pr_coop ≤ 0.15">
            <b>{fmt(pctDd)}</b> D
          </span>
        </span>
        <span className="norm-pct-group">
          <span className="norm-pct-group-label">advocating</span>
          <span className="norm-pct pct-coop"
                title="fraction of agents advocating cooperation">
            <b>{fmt(pctAdvC)}</b> C
          </span>
          <span className="norm-pct pct-def"
                title="fraction of agents advocating defection">
            <b>{fmt(pctAdvD)}</b> D
          </span>
        </span>
      </div>
      <div className="norm-timeline-bar"
           onClick={handleClick}
           style={{ cursor: onScrub ? 'pointer' : 'default', height }}
           title="click to jump to that round">
        {/* middling base layer so empty regions aren't bare white */}
        {mid.map((b, i) => (
          <div key={`m-${i}`} className="nt-seg"
               style={{
                 left: `${frac(b.x1) * 100}%`,
                 width: `${(frac(b.x2) - frac(b.x1)) * 100}%`,
                 background: NORM_STRIP.midColor,
                 opacity: NORM_STRIP.midOpacity,
               }} />
        ))}
        {cn.map((b, i) => (
          <div key={`c-${i}`} className="nt-seg"
               style={{
                 left: `${frac(b.x1) * 100}%`,
                 width: `${(frac(b.x2) - frac(b.x1)) * 100}%`,
                 background: NORM_STRIP.cnColor,
                 opacity: NORM_STRIP.cnOpacity,
               }} />
        ))}
        {un.map((b, i) => (
          <div key={`u-${i}`} className="nt-seg"
               style={{
                 left: `${frac(b.x1) * 100}%`,
                 width: `${(frac(b.x2) - frac(b.x1)) * 100}%`,
                 background: NORM_STRIP.unColor,
                 opacity: NORM_STRIP.unOpacity,
               }} />
        ))}
        {/* playhead cursor */}
        <div className="nt-cursor" style={{ left: `${cursorPct}%` }} />
      </div>
    </div>
  );
}
