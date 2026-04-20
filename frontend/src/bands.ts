export type Band = { x1: number; x2: number };

/** Given rounds[] and a same-length boolean flags[], return contiguous intervals
 *  of rounds where flags is true. Each interval is closed on the left, open on
 *  the right (x2 = first round where flag became false, or last round if still true). */
export function bandsFromBools(rounds: number[], flags: boolean[]): Band[] {
  const bands: Band[] = [];
  let start: number | null = null;
  for (let i = 0; i < flags.length; i++) {
    if (flags[i] && start === null) {
      start = rounds[i];
    } else if (!flags[i] && start !== null) {
      bands.push({ x1: start, x2: rounds[i] });
      start = null;
    }
  }
  if (start !== null) bands.push({ x1: start, x2: rounds[rounds.length - 1] });
  return bands;
}

/** Given rounds, in_cn_norm, in_un_norm (all same length), classify every round
 *  and return three band arrays: CN stretches, UN stretches, and the "middling"
 *  rounds (not in a CN or UN norm). Used to render the normative-classification
 *  strip below each chart. */
export function normBands(rounds: number[], inCn: boolean[], inUn: boolean[]): {
  cn: Band[]; un: Band[]; mid: Band[];
} {
  const cn = bandsFromBools(rounds, inCn);
  const un = bandsFromBools(rounds, inUn);
  const midMask = rounds.map((_, i) => !inCn[i] && !inUn[i]);
  const mid = bandsFromBools(rounds, midMask);
  return { cn, un, mid };
}
