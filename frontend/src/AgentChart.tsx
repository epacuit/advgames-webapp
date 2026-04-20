import { useMemo, useState } from 'react';
import {
  CartesianGrid, Line, LineChart, ResponsiveContainer, Tooltip, XAxis, YAxis,
} from 'recharts';
import { normBands } from './bands';
import { NORM_STRIP, renderNormStrip } from './normStrip';
import type { AgentSeries } from './types';

const C_COLOR = '#16a34a';  // green — advocating C
const D_COLOR = '#dc2626';  // red   — advocating D

/**
 * Split each agent's trajectory into two null-padded series — one rendered as
 * green (advocating C), one as red (advocating D). At each advocacy flip we
 * duplicate the previous point into the new series so the colored segments
 * join visually rather than leaving a gap at the transition.
 */
function buildRows(rounds: number[], agents: AgentSeries[]) {
  const rows: Record<string, number | null>[] = rounds.map((t) => ({ t }));
  for (const ag of agents) {
    const cKey = `a${ag.id}_C`;
    const dKey = `a${ag.id}_D`;
    const n = rounds.length;
    for (let j = 0; j < n; j++) {
      const adv = ag.advocacy[j];
      rows[j][cKey] = adv === 'C' ? ag.inclination[j] : null;
      rows[j][dKey] = adv === 'D' ? ag.inclination[j] : null;
    }
    for (let j = 1; j < n; j++) {
      const prev = ag.advocacy[j - 1];
      const curr = ag.advocacy[j];
      if (prev === 'C' && curr === 'D') rows[j - 1][dKey] = ag.inclination[j - 1];
      else if (prev === 'D' && curr === 'C') rows[j - 1][cKey] = ag.inclination[j - 1];
    }
  }
  return rows;
}

export function AgentChart({ rounds, agents, inCnNorm, inUnNorm }: {
  rounds: number[];
  agents: AgentSeries[];
  inCnNorm: boolean[];
  inUnNorm: boolean[];
}) {
  const data = useMemo(() => buildRows(rounds, agents), [rounds, agents]);
  const norms = useMemo(() => normBands(rounds, inCnNorm, inUnNorm),
                        [rounds, inCnNorm, inUnNorm]);

  // activeId is set by hover on the pills OR click-lock. If clickLock is set,
  // hover is ignored; clicking the same pill again (or clicking blank space)
  // releases the lock.
  const [hoverId, setHoverId] = useState<number | null>(null);
  const [lockId, setLockId] = useState<number | null>(null);
  const activeId = lockId ?? hoverId;

  // Count final advocacies for the footer
  const finalCs = agents.filter((a) => a.advocacy[a.advocacy.length - 1] === 'C').length;
  const finalDs = agents.length - finalCs;

  // Render non-active lines first so the active agent draws on top.
  const renderOrder = useMemo(() => {
    if (activeId === null) return agents;
    return [...agents.filter((a) => a.id !== activeId), ...agents.filter((a) => a.id === activeId)];
  }, [agents, activeId]);

  const baseOpacity   = 0.55;
  const dimmedOpacity = 0.06;
  const baseWidth     = 1.25;
  const activeWidth   = 2.25;

  const opacityFor = (id: number) =>
    activeId === null ? baseOpacity : (id === activeId ? 1.0 : dimmedOpacity);
  const widthFor = (id: number) =>
    activeId === null ? baseWidth : (id === activeId ? activeWidth : baseWidth * 0.8);

  const togglePillLock = (id: number) => {
    setLockId((prev) => (prev === id ? null : id));
  };

  return (
    <div className="chart-card">
      <h3>
        Individual agents: inclination over time (colored by advocacy)
        {activeId !== null && (
          <span style={{ marginLeft: 10, fontSize: 11, color: '#666', fontWeight: 400 }}>
            showing agent {activeId}
            {lockId !== null && ' (click pill again to unlock)'}
          </span>
        )}
      </h3>
      <ResponsiveContainer width="100%" height={340}>
        <LineChart data={data} margin={{ top: 10, right: 20, left: 0, bottom: 0 }}>
          <CartesianGrid strokeDasharray="3 3" stroke="#eee" />
          <XAxis dataKey="t" type="number" domain={['dataMin', 'dataMax']}
                 tickFormatter={(v: number) => v >= 10000 ? `${Math.round(v/1000)}k` : String(v)} />
          <YAxis domain={[NORM_STRIP.yMin, 1]} ticks={[0, 0.25, 0.5, 0.75, 1]} />
          <Tooltip
            labelFormatter={(v: number) => `round ${v.toLocaleString()}`}
            formatter={(val: any, key: string) => {
              if (val === null || val === undefined) return ['', ''];
              const m = /^a(\d+)_([CD])$/.exec(key);
              if (!m) return [String(val), key];
              return [Number(val).toFixed(3), `agent ${m[1]} (${m[2]})`];
            }}
            filter={(item: any) => {
              // When an agent is active, hide tooltip rows for other agents.
              if (activeId === null) return true;
              const m = /^a(\d+)_/.exec(item.dataKey);
              return m ? Number(m[1]) === activeId : false;
            }}
            itemSorter={(it: any) => Number(it.value ?? 0)}
          />

          {renderNormStrip(norms.cn, norms.un, norms.mid)}

          {renderOrder.flatMap((ag) => {
            const op = opacityFor(ag.id);
            const w = widthFor(ag.id);
            return [
              <Line key={`a${ag.id}_C`} type="monotone" dataKey={`a${ag.id}_C`}
                    stroke={C_COLOR} strokeOpacity={op} strokeWidth={w}
                    dot={false} isAnimationActive={false} connectNulls={false}
                    legendType="none" />,
              <Line key={`a${ag.id}_D`} type="monotone" dataKey={`a${ag.id}_D`}
                    stroke={D_COLOR} strokeOpacity={op} strokeWidth={w}
                    dot={false} isAnimationActive={false} connectNulls={false}
                    legendType="none" />,
            ];
          })}
        </LineChart>
      </ResponsiveContainer>

      <div className="agent-pills" onMouseLeave={() => setHoverId(null)}>
        {agents.map((ag) => {
          const finalAdv = ag.advocacy[ag.advocacy.length - 1];
          const color = finalAdv === 'C' ? C_COLOR : D_COLOR;
          const isActive = ag.id === activeId;
          const isLocked = ag.id === lockId;
          return (
            <button
              key={ag.id}
              className={'agent-pill' + (isActive ? ' active' : '') + (isLocked ? ' locked' : '')}
              style={{ borderColor: color, color: isActive ? '#fff' : color,
                       background: isActive ? color : 'transparent' }}
              onMouseEnter={() => setHoverId(ag.id)}
              onClick={() => togglePillLock(ag.id)}
              title={`agent ${ag.id} · ends advocating ${finalAdv}`}
            >
              {ag.id}
            </button>
          );
        })}
      </div>

      <div className="legend-swatches">
        <span><span className="sw" style={{ background: C_COLOR, opacity: 0.55 }}></span>advocating C</span>
        <span><span className="sw" style={{ background: D_COLOR, opacity: 0.55 }}></span>advocating D</span>
        <span style={{ marginLeft: 18, borderLeft: '1px solid #ddd', paddingLeft: 14 }}>
          <em>strip below:</em>
        </span>
        <span><span className="sw" style={{ background: NORM_STRIP.cnColor, opacity: NORM_STRIP.cnOpacity }}></span>CN norm</span>
        <span><span className="sw" style={{ background: NORM_STRIP.unColor, opacity: NORM_STRIP.unOpacity }}></span>UN norm</span>
        <span><span className="sw" style={{ background: NORM_STRIP.midColor, opacity: NORM_STRIP.midOpacity }}></span>middling</span>
        <span style={{ marginLeft: 'auto', color: '#666' }}>
          {agents.length} agents — finished: {finalCs}×C, {finalDs}×D
        </span>
      </div>
    </div>
  );
}
