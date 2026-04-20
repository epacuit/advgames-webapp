import { ReferenceArea, ReferenceLine } from 'recharts';
import type { Band } from './bands';

/**
 * Shared constants + renderer for the CN/UN/middling classification strip
 * below the plot area. We extend the chart's Y domain slightly below 0 so
 * we can paint a thin colored strip there without covering any data.
 *
 * Usage:
 *   <YAxis domain={[NORM_STRIP.yMin, 1]} ticks={[0, 0.25, 0.5, 0.75, 1]} />
 *   {renderNormStrip(cnBands, unBands, midBands)}
 */
export const NORM_STRIP = {
  yMin:    -0.07,  // extend Y domain down to here
  stripLo: -0.06,  // strip bottom
  stripHi: -0.01,  // strip top
  baseline: 0,     // thin line between plot and strip

  cnColor:  '#16a34a',   // green — CN norm
  unColor:  '#dc2626',   // red   — UN norm
  midColor: '#f59e0b',   // amber — middling (neither norm)

  cnOpacity:  0.85,
  unOpacity:  0.85,
  midOpacity: 0.35,
};

export function renderNormStrip(cn: Band[], un: Band[], mid: Band[]) {
  const { stripLo, stripHi, baseline,
          cnColor, unColor, midColor,
          cnOpacity, unOpacity, midOpacity } = NORM_STRIP;
  return [
    // Middling first so CN/UN paint over it (defensive — they shouldn't overlap).
    ...mid.map((b, i) => (
      <ReferenceArea key={`mid-${i}`} x1={b.x1} x2={b.x2} y1={stripLo} y2={stripHi}
                     fill={midColor} fillOpacity={midOpacity} stroke="none" />
    )),
    ...cn.map((b, i) => (
      <ReferenceArea key={`cn-${i}`}  x1={b.x1} x2={b.x2} y1={stripLo} y2={stripHi}
                     fill={cnColor}  fillOpacity={cnOpacity}  stroke="none" />
    )),
    ...un.map((b, i) => (
      <ReferenceArea key={`un-${i}`}  x1={b.x1} x2={b.x2} y1={stripLo} y2={stripHi}
                     fill={unColor}  fillOpacity={unOpacity}  stroke="none" />
    )),
    <ReferenceLine key="strip-base" y={baseline} stroke="#cbd5e1" strokeWidth={0.5} />,
  ];
}
