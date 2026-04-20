import { useEffect, useMemo, useState } from 'react';
import {
  CartesianGrid, Legend, Line, LineChart, ReferenceArea,
  ResponsiveContainer, Tooltip, XAxis, YAxis,
} from 'recharts';
import { fetchBaseGames, fetchDefaults, fetchNetworkConfigs, postRun } from './api';
import { bandsFromBools, normBands } from './bands';
import { AgentChart } from './AgentChart';
import { AnimationView } from './AnimationView';
import { GameTypeBar } from './GameTypeBar';
import { CommitmentBar } from './CommitmentBar';
import { LocalNormChart } from './LocalNormChart';
import { PhasePortrait } from './PhasePortrait';
import { NORM_STRIP, renderNormStrip } from './normStrip';
import type { BaseGamesMap, Caps, Defaults, ModelParams, NetworkPreset, RunRequest, RunResponse } from './types';
import './App.css';

const MODEL_KEYS: (keyof ModelParams)[] = [
  'num_cooperators', 'num_defectors', 'num_neutrals',
  'init_pr_coop_cooperator', 'init_pr_coop_defector',
  'learning_increment', 'weight_of_present_for_move', 'weight_of_present_for_adv',
  'tolerance', 'move_mutation_rate', 'adv_mutation_rate',
  'pos_pressure_limit', 'neg_pressure_limit',
  'move_reassess_frequency', 'adv_reassess_frequency',
];

function pickModel(p: Defaults): ModelParams {
  const o = {} as ModelParams;
  for (const k of MODEL_KEYS) (o as any)[k] = p[k];
  return o;
}

const groups: { title: string; keys: (keyof ModelParams)[] }[] = [
  { title: 'Population', keys: ['num_cooperators', 'num_defectors', 'num_neutrals', 'init_pr_coop_cooperator', 'init_pr_coop_defector'] },
  { title: 'Learning', keys: ['learning_increment', 'weight_of_present_for_move', 'weight_of_present_for_adv', 'tolerance'] },
  { title: 'Mutation', keys: ['move_mutation_rate', 'adv_mutation_rate'] },
  { title: 'Pressure', keys: ['pos_pressure_limit', 'neg_pressure_limit'] },
  { title: 'Reassess', keys: ['move_reassess_frequency', 'adv_reassess_frequency'] },
];

export default function App() {
  const [defaults, setDefaults] = useState<Defaults | null>(null);
  const [caps, setCaps] = useState<Caps | null>(null);
  const [baseGames, setBaseGames] = useState<BaseGamesMap | null>(null);
  const [networkPresets, setNetworkPresets] = useState<NetworkPreset[] | null>(null);
  const [networkPreset, setNetworkPreset] = useState<string>(''); // '' = no network
  const [latticeRows, setLatticeRows] = useState<number>(7);
  const [latticeCols, setLatticeCols] = useState<number>(7);
  const [bootError, setBootError] = useState<string | null>(null);

  const [model, setModel] = useState<ModelParams | null>(null);
  const [baseGame, setBaseGame] = useState<string>('PD_STANDARD');
  const [rstp, setRstp] = useState<{ R: number; S: number; T: number; P: number } | null>(null);
  const [rstpCustom, setRstpCustom] = useState<boolean>(false);
  const [numrounds, setNumrounds] = useState<number>(100_000);
  const [seed, setSeed] = useState<string>(''); // blank = random
  const [includeAgents, setIncludeAgents] = useState<boolean>(false);

  const [running, setRunning] = useState(false);
  const [result, setResult] = useState<RunResponse | null>(null);
  const [runError, setRunError] = useState<string | null>(null);

  type TabId = 'charts' | 'animation';
  const [activeTab, setActiveTab] = useState<TabId>('charts');

  useEffect(() => {
    Promise.all([fetchDefaults(), fetchBaseGames(), fetchNetworkConfigs()])
      .then(([d, bg, nc]) => {
        setDefaults(d.defaults);
        setCaps(d.caps);
        setBaseGames(bg.base_games);
        setNetworkPresets(nc.presets);
        setModel(pickModel(d.defaults));
        setBaseGame(d.defaults.default_base_game);
        setRstp(bg.base_games[d.defaults.default_base_game]);
        setRstpCustom(false);
        setNumrounds(d.defaults.numrounds_default);
      })
      .catch((e) => setBootError(String(e)));
  }, []);

  const activePreset = networkPresets?.find((p) => p.name === networkPreset) ?? null;
  const isLattice = activePreset?.kind === 'lattice';
  const requiredPop = isLattice ? latticeRows * latticeCols : null;
  const currentPop = model
    ? model.num_cooperators + model.num_defectors + model.num_neutrals
    : 0;
  const popMismatch = requiredPop !== null && currentPop !== requiredPop;

  const snapPopulationTo = (target: number) => {
    if (!model) return;
    const coop = Math.floor(target / 2);
    const def = target - coop;
    setModel({ ...model, num_cooperators: coop, num_defectors: def, num_neutrals: 0 });
  };

  const onNetworkPresetChange = (name: string) => {
    setNetworkPreset(name);
    const p = networkPresets?.find((x) => x.name === name);
    if (p?.kind === 'lattice') {
      snapPopulationTo(latticeRows * latticeCols);
    }
  };

  const onLatticeDimsChange = (rows: number, cols: number) => {
    setLatticeRows(rows);
    setLatticeCols(cols);
    if (isLattice) snapPopulationTo(rows * cols);
  };

  // When the user picks a preset from the dropdown, load its payoffs into the
  // R/S/T/P editors and drop out of "custom" mode.
  const onBaseGameChange = (name: string) => {
    setBaseGame(name);
    if (baseGames?.[name]) {
      setRstp(baseGames[name]);
      setRstpCustom(false);
    }
  };

  const onRstpEdit = (k: 'R' | 'S' | 'T' | 'P', v: number) => {
    if (!rstp) return;
    const next = { ...rstp, [k]: v };
    setRstp(next);
    setRstpCustom(true);
  };

  const resetToPaperDefaults = () => {
    if (!defaults || !baseGames) return;
    setModel(pickModel(defaults));
    setBaseGame(defaults.default_base_game);
    setRstp(baseGames[defaults.default_base_game]);
    setRstpCustom(false);
    setNumrounds(defaults.numrounds_default);
    setSeed('');
  };

  const runSim = async () => {
    if (!model) return;
    setRunning(true);
    setRunError(null);
    try {
      const req: RunRequest = {
        ...model,
        numrounds,
        seed: seed.trim() === '' ? null : Number(seed),
        include_agents: includeAgents,
        network_preset: networkPreset === '' ? null : networkPreset,
      };
      if (isLattice) {
        req.lattice_rows = latticeRows;
        req.lattice_cols = latticeCols;
      }
      if (rstpCustom && rstp) {
        req.rstp = [rstp.R, rstp.S, rstp.T, rstp.P];
      } else {
        req.base_game = baseGame;
      }
      const r = await postRun(req);
      setResult(r);
    } catch (e: any) {
      setRunError(e?.message ?? String(e));
    } finally {
      setRunning(false);
    }
  };

  return (
    <div className="app">
      <aside className="sidebar">
        <h1>Advocacy Games</h1>

        {bootError && <div className="status-line error">backend error: {bootError}</div>}

        <div className="group">
          <h2>Game {rstpCustom && <span className="rstp-custom-tag">(custom)</span>}</h2>
          <div className="row row--select">
            <label>preset</label>
            <select value={rstpCustom ? '' : baseGame} onChange={(e) => onBaseGameChange(e.target.value)}>
              {rstpCustom && <option value="">— custom —</option>}
              {baseGames && Object.keys(baseGames).sort().map((k) => (
                <option key={k} value={k}>{k}</option>
              ))}
            </select>
          </div>
          {rstp && (
            <div className="rstp-grid">
              {(['R', 'S', 'T', 'P'] as const).map((k) => (
                <div key={k} className="cell">
                  <label>{k}</label>
                  <input type="number" step={0.1} value={rstp[k]}
                         onChange={(e) => onRstpEdit(k, Number(e.target.value))} />
                </div>
              ))}
            </div>
          )}
        </div>

        <div className="group">
          <h2>Network</h2>
          <div className="row row--select">
            <label>topology</label>
            <select value={networkPreset}
                    onChange={(e) => onNetworkPresetChange(e.target.value)}>
              <option value="">None — standard model (no network)</option>
              {networkPresets?.map((p) => (
                <option key={p.name} value={p.name}
                        title={p.description}>{p.label}</option>
              ))}
            </select>
          </div>
          <div style={{ fontSize: 10, color: '#777', marginTop: 4 }}>
            {activePreset?.description ??
              'Uses advgames.jl: random pair of agents interact each round, single global advocacy-driven payoff matrix.'}
          </div>
          {isLattice && (
            <div className="rstp-grid" style={{ gridTemplateColumns: '1fr 1fr', marginTop: 8 }}>
              <div className="cell">
                <label>rows</label>
                <input type="number" min={2} max={20} step={1} value={latticeRows}
                       onChange={(e) => onLatticeDimsChange(Number(e.target.value), latticeCols)} />
              </div>
              <div className="cell">
                <label>cols</label>
                <input type="number" min={2} max={20} step={1} value={latticeCols}
                       onChange={(e) => onLatticeDimsChange(latticeRows, Number(e.target.value))} />
              </div>
            </div>
          )}
          {isLattice && (
            <div style={{ fontSize: 10, color: '#777', marginTop: 4 }}>
              population = {latticeRows} × {latticeCols} = {latticeRows * latticeCols}
            </div>
          )}
          {popMismatch && (
            <div className="rstp-custom-tag" style={{ color: '#b91c1c' }}>
              needs exactly {requiredPop} agents (have {currentPop})
            </div>
          )}
        </div>

        {model && groups.map((g) => (
          <div key={g.title} className="group">
            <h2>{g.title}</h2>
            {g.keys.map((k) => (
              <div key={k} className="row">
                <label>{k}</label>
                <input
                  type="number"
                  value={model[k] as number}
                  step={isIntKey(k) ? 1 : 0.001}
                  onChange={(e) => setModel({ ...model, [k]: Number(e.target.value) })}
                />
              </div>
            ))}
          </div>
        ))}

        <div className="group">
          <h2>Run</h2>
          <div className="row">
            <label>numrounds</label>
            <input
              type="number"
              value={numrounds}
              min={caps?.numrounds_min ?? 100}
              max={caps?.numrounds_max ?? 500000}
              step={1000}
              onChange={(e) => setNumrounds(Number(e.target.value))}
            />
          </div>
          <div className="row">
            <label>seed (blank = random)</label>
            <input
              type="text"
              value={seed}
              placeholder="random"
              onChange={(e) => setSeed(e.target.value)}
            />
          </div>
          <label className="toggle">
            <input
              type="checkbox"
              checked={includeAgents}
              onChange={(e) => setIncludeAgents(e.target.checked)}
            />
            <span>collect per-agent data <small>(slower)</small></span>
          </label>
        </div>

        <button className="run-button" onClick={runSim} disabled={running || !model}>
          {running ? 'Running…' : 'Run simulation'}
        </button>
        <button className="preset-button" onClick={resetToPaperDefaults}>Paper defaults</button>
      </aside>

      <main className="main">
        <div className="tabbar" role="tablist">
          <button role="tab" aria-selected={activeTab === 'charts'}
                  className={'tab' + (activeTab === 'charts' ? ' active' : '')}
                  onClick={() => setActiveTab('charts')}>Charts</button>
          <button role="tab" aria-selected={activeTab === 'animation'}
                  className={'tab' + (activeTab === 'animation' ? ' active' : '')}
                  onClick={() => setActiveTab('animation')}>Animation</button>
        </div>

        {runError && <div className="status-line error">error: {runError}</div>}
        {!result && !runError && (
          <div className="empty">configure parameters and click "Run simulation"</div>
        )}

        {result && activeTab === 'charts'    && <ResultView r={result} />}
        {result && activeTab === 'animation' && <AnimationView r={result} />}
      </main>
    </div>
  );
}

function isIntKey(k: keyof ModelParams): boolean {
  return k === 'num_cooperators' || k === 'num_defectors' || k === 'num_neutrals';
}

function ResultView({ r }: { r: RunResponse }) {
  const { series, summary } = r;

  // Build one combined row per rendered point for Recharts
  const data = useMemo(() => series.rounds.map((t, i) => ({
    t,
    avg_incl:    series.avg_incl[i],
    pr_adv_coop: series.pr_adv_coop[i],
  })), [series]);

  // Bands are just "≥80% committed in one direction", computed per point.
  const coopMask   = useMemo(() => series.prop_cc.map((v) => v >= 0.80), [series]);
  const defectMask = useMemo(() => series.prop_dd.map((v) => v >= 0.80), [series]);
  const coopBands   = useMemo(() => bandsFromBools(series.rounds, coopMask),   [series.rounds, coopMask]);
  const defectBands = useMemo(() => bandsFromBools(series.rounds, defectMask), [series.rounds, defectMask]);

  // CN/UN norm classification (1000-round stretch definition) for the strip
  // below the plot area.
  const norms = useMemo(
    () => normBands(series.rounds, series.in_cn_norm, series.in_un_norm),
    [series.rounds, series.in_cn_norm, series.in_un_norm]);

  return (
    <>
      {(() => {
        const middling = Math.max(0, 1 - summary.cn_time - summary.un_time);
        return (
          <>
            <div className="summary summary-main">
              <Cell label="CNF"         value={pct(summary.cn_time)}
                    tone={summary.cn_time > 0 ? 'cn' : undefined}
                    tip="Cooperative-Norm Fraction: fraction of rounds inside a sustained ≥1000-round CN stretch (prop committed cooperators ≥ 0.80 AND pr advocating C > 0.50)." />
              <Cell label="UNF"         value={pct(summary.un_time)}
                    tone={summary.un_time > 0 ? 'un' : undefined}
                    tip="Uncooperative-Norm Fraction: fraction of rounds inside a sustained ≥1000-round UN stretch (prop committed defectors ≥ 0.80 AND pr advocating C < 0.50)." />
              <Cell label="middling"    value={pct(middling)}
                    tip="Fraction of rounds not in any sustained norm (1 − CNF − UNF)." />
              <Cell label="order deg"   value={pct(summary.order_degree)}
                    tip="Order degree: fraction of rounds with ≥80% committed cooperators OR ≥80% committed defectors (instantaneous — no stretch requirement)." />
              <Cell label="transitions" value={String(summary.norm_transitions)}
                    tip="Number of times the active sustained norm flipped between CN and UN across the run." />
              <Cell label="ending"
                    value={summary.cn_end_state ? 'CN norm' : summary.un_end_state ? 'UN norm' : '—'}
                    tone={summary.cn_end_state ? 'cn' : summary.un_end_state ? 'un' : undefined}
                    tip="Whether the final round is inside a sustained CN stretch, sustained UN stretch, or neither." />
            </div>
            <div className="summary summary-side">
              <Cell label="cai"              value={summary.cai.toFixed(3)}
                    tip="Cumulative Average Inclination: time-averaged mean cooperation inclination across all rounds (mean of avg_incl over the run)." />
              <Cell label="avg adv C"        value={summary.avg_pr_adv_coop.toFixed(3)}
                    tip="Run-averaged fraction of the population advocating cooperation (mean of pr_adv_coop)." />
              <Cell label="adv volatility"   value={summary.advocacy_volatility.toFixed(3)}
                    tip="Advocacy volatility: standard deviation of pr_adv_coop across rounds. High = the fraction advocating C shifted a lot; low = advocacy composition was stable." />
              <Cell label="cn state time"    value={pct(summary.cn_state_time)}
                    tip="Fraction of rounds where the CN condition holds instantaneously (no 1000-round stretch requirement). Always ≥ CNF." />
              <Cell label="un state time"    value={pct(summary.un_state_time)}
                    tip="Fraction of rounds where the UN condition holds instantaneously. Always ≥ UNF." />
              <Cell label="coop beh time"    value={pct(summary.coop_behavior_time)}
                    tip="Fraction of rounds with ≥80% committed cooperators (regardless of advocacy)." />
              <Cell label="defect beh time"  value={pct(summary.defect_behavior_time)}
                    tip="Fraction of rounds with ≥80% committed defectors (regardless of advocacy)." />
              <Cell label="avg payoff"       value={summary.avg_payoff_final.toFixed(2)}
                    tip="Final-round mean per-move payoff across all agents." />
              <Cell label="sim time"         value={`${r.elapsed_sec}s`}
                    tip="Server wall-clock time for the Julia simulation (not including network transit)." />
            </div>
          </>
        );
      })()}

      <div className="chart-card">
        <h3>Cooperation and advocacy over time</h3>
        <ResponsiveContainer width="100%" height={360}>
          <LineChart data={data} margin={{ top: 10, right: 20, left: 0, bottom: 0 }}>
            <CartesianGrid strokeDasharray="3 3" stroke="#eee" />
            <XAxis dataKey="t" type="number" domain={['dataMin', 'dataMax']}
                   tickFormatter={(v: number) => v >= 10000 ? `${Math.round(v/1000)}k` : String(v)} />
            <YAxis domain={[NORM_STRIP.yMin, 1]} ticks={[0, 0.25, 0.5, 0.75, 1]} />
            <Tooltip labelFormatter={(v: number) => `round ${v.toLocaleString()}`}
                     formatter={(v: number) => v.toFixed(3)} />
            <Legend verticalAlign="top" height={24} iconType="plainline" />

            {coopBands.map((b, i) => (
              <ReferenceArea key={`coop-${i}`} x1={b.x1} x2={b.x2} y1={0} y2={1}
                             fill="#16a34a" fillOpacity={0.10} stroke="none" />
            ))}
            {defectBands.map((b, i) => (
              <ReferenceArea key={`def-${i}`} x1={b.x1} x2={b.x2} y1={0} y2={1}
                             fill="#dc2626" fillOpacity={0.10} stroke="none" />
            ))}

            {renderNormStrip(norms.cn, norms.un, norms.mid)}

            <Line type="monotone" dataKey="avg_incl"    name="avg cooperation"     stroke="#2d72d9" strokeWidth={2} dot={false} />
            <Line type="monotone" dataKey="pr_adv_coop" name="pr advocating C"     stroke="#ea580c" strokeWidth={2} dot={false} />
          </LineChart>
        </ResponsiveContainer>
        <div className="legend-swatches">
          <span><span className="sw" style={{ background: 'rgba(22,163,74,0.22)' }}></span>≥80% committed cooperators</span>
          <span><span className="sw" style={{ background: 'rgba(220,38,38,0.22)' }}></span>≥80% committed defectors</span>
          <span style={{ marginLeft: 18, borderLeft: '1px solid #ddd', paddingLeft: 14 }}>
            <em>strip below:</em>
          </span>
          <span><span className="sw" style={{ background: NORM_STRIP.cnColor, opacity: NORM_STRIP.cnOpacity }}></span>CN norm</span>
          <span><span className="sw" style={{ background: NORM_STRIP.unColor, opacity: NORM_STRIP.unOpacity }}></span>UN norm</span>
          <span><span className="sw" style={{ background: NORM_STRIP.midColor, opacity: NORM_STRIP.midOpacity }}></span>middling</span>
        </div>
      </div>

      <PhasePortrait rounds={series.rounds}
                     prAdvCoop={series.pr_adv_coop}
                     avgIncl={series.avg_incl} />

      {series.agents.length > 0 && (
        <AgentChart rounds={series.rounds} agents={series.agents}
                    inCnNorm={series.in_cn_norm} inUnNorm={series.in_un_norm} />
      )}

      {series.local_counts && (
        <LocalNormChart counts={series.local_counts}
                        rounds={series.rounds}
                        totalAgents={r.population} />
      )}

      <GameTypeBar gameTypes={series.game_type} />
      <CommitmentBar summary={summary} />
    </>
  );
}

function Cell({ label, value, tone, tip }: {
  label: string; value: string; tone?: 'cn' | 'un'; tip?: string;
}) {
  return (
    <div className="cell" title={tip}>
      <div className={'label' + (tip ? ' hastip' : '')}>{label}</div>
      <div className={'value' + (tone ? ` ${tone}` : '')}>{value}</div>
    </div>
  );
}

function pct(x: number): string {
  return `${(x * 100).toFixed(1)}%`;
}
