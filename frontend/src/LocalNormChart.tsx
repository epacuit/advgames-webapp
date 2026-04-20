import { useMemo } from 'react';
import {
  Area, AreaChart, ReferenceLine, ResponsiveContainer, Tooltip, XAxis, YAxis,
} from 'recharts';
import type { LocalCounts } from './types';

const C_COLOR = '#16a34a';   // local CN
const D_COLOR = '#dc2626';   // local UN
const NEUTRAL = '#cbd5e1';   // neither (light gray)

/**
 * Two stacked-area charts of **local** norm counts over time — one for
 * interaction neighborhoods, one for influence neighborhoods. At each
 * (downsampled) round the chart shows how many agents satisfy their own
 * local CN-state (green) or local UN-state (red); the rest are "neither"
 * (gray). Population count is the y-axis max.
 *
 * A vertical cursor marks the current playback frame.
 *
 * Only rendered when network mode is active (local_*_interaction /
 * local_*_influence arrays are present on the agent rows).
 */
export function LocalNormChart({
  counts, rounds, totalAgents, currentFrame,
}: {
  counts: LocalCounts;
  rounds: number[];
  totalAgents: number;
  currentFrame?: number;        // when omitted, no cursor; readout shows last frame
}) {
  const n = totalAgents;

  const { intData, inflData } = useMemo(() => {
    const nFrames = rounds.length;
    const intData  = new Array(nFrames);
    const inflData = new Array(nFrames);
    for (let f = 0; f < nFrames; f++) {
      const cnI = counts.cn_int[f]   ?? 0;
      const unI = counts.un_int[f]   ?? 0;
      const cnF = counts.cn_infl[f]  ?? 0;
      const unF = counts.un_infl[f]  ?? 0;
      intData[f]  = { t: rounds[f], cn: cnI, un: unI, other: n - cnI - unI };
      inflData[f] = { t: rounds[f], cn: cnF, un: unF, other: n - cnF - unF };
    }
    return { intData, inflData };
  }, [counts, rounds, n]);

  const readoutIdx = currentFrame ?? rounds.length - 1;
  const curRound = rounds[Math.max(0, Math.min(rounds.length - 1, readoutIdx))];
  const curInt  = intData[readoutIdx] ?? intData[intData.length - 1];
  const curInfl = inflData[readoutIdx] ?? inflData[inflData.length - 1];
  const cursorX = currentFrame !== undefined ? curRound : null;
  const hasInteraction = true;
  const hasInfluence = true;

  return (
    <div className="chart-card" style={{ padding: 10 }}>
      <h3 style={{ marginBottom: 6 }}>Local norms over time — how many agents are in a local CN / UN</h3>
      <div className="local-norm-grid">
        {hasInteraction && (
          <Panel title="by interaction peers"
                 current={curInt} total={n}
                 data={intData}
                 cursorX={cursorX} />
        )}
        {hasInfluence && (
          <Panel title="by influence peers"
                 current={curInfl} total={n}
                 data={inflData}
                 cursorX={cursorX} />
        )}
      </div>
      <div className="legend-swatches" style={{ marginTop: 6 }}>
        <span><span className="sw" style={{ background: C_COLOR }} />in local CN</span>
        <span><span className="sw" style={{ background: D_COLOR }} />in local UN</span>
        <span><span className="sw" style={{ background: NEUTRAL }} />neither</span>
      </div>
    </div>
  );
}

function Panel({ title, current, total, data, cursorX }: {
  title: string;
  current: { cn: number; un: number; other: number };
  total: number;
  data: Array<{ t: number; cn: number; un: number; other: number }>;
  cursorX: number | null;
}) {
  return (
    <div className="local-norm-panel">
      <div className="local-norm-head">
        <span className="local-norm-title">{title}</span>
        <span className="local-norm-now">
          <span style={{ color: C_COLOR, fontWeight: 700 }}>{current.cn}</span> CN ·{' '}
          <span style={{ color: D_COLOR, fontWeight: 700 }}>{current.un}</span> UN ·{' '}
          <span style={{ color: '#64748b' }}>{current.other}</span> neither
          <span style={{ color: '#888', marginLeft: 4 }}>/ {total}</span>
        </span>
      </div>
      <ResponsiveContainer width="100%" height={140}>
        <AreaChart data={data} margin={{ top: 4, right: 8, left: 0, bottom: 2 }}>
          <XAxis dataKey="t" type="number" domain={['dataMin', 'dataMax']}
                 tickFormatter={(v: number) => v >= 10000 ? `${Math.round(v/1000)}k` : String(v)}
                 height={18} tick={{ fontSize: 10 }} />
          <YAxis domain={[0, total]} allowDecimals={false}
                 width={28} tick={{ fontSize: 10 }} />
          <Tooltip
            labelFormatter={(v: any) => `round ${Number(v).toLocaleString()}`}
            formatter={(val: any, key: any) => [val, String(key)]}
            contentStyle={{ fontSize: 11 }} />
          <Area type="stepAfter" dataKey="cn"    stackId="1"
                stroke="none" fill={C_COLOR} fillOpacity={0.85}
                isAnimationActive={false} />
          <Area type="stepAfter" dataKey="un"    stackId="1"
                stroke="none" fill={D_COLOR} fillOpacity={0.85}
                isAnimationActive={false} />
          <Area type="stepAfter" dataKey="other" stackId="1"
                stroke="none" fill={NEUTRAL} fillOpacity={0.6}
                isAnimationActive={false} />
          {cursorX !== null && (
            <ReferenceLine x={cursorX} stroke="#111" strokeWidth={1} strokeDasharray="3 2" />
          )}
        </AreaChart>
      </ResponsiveContainer>
    </div>
  );
}
