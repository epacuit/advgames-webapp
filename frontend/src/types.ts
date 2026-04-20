export type ModelParams = {
  num_cooperators: number;
  num_defectors: number;
  num_neutrals: number;
  init_pr_coop_cooperator: number;
  init_pr_coop_defector: number;
  learning_increment: number;
  weight_of_present_for_move: number;
  weight_of_present_for_adv: number;
  move_mutation_rate: number;
  adv_mutation_rate: number;
  tolerance: number;
  pos_pressure_limit: number;
  neg_pressure_limit: number;
  move_reassess_frequency: number;
  adv_reassess_frequency: number;
};

export type GameSpec =
  | { kind: 'base'; name: string }
  | { kind: 'custom'; R: number; S: number; T: number; P: number };

export type RunRequest = ModelParams & {
  numrounds: number;
  seed?: number | null;
  base_game?: string;
  rstp?: [number, number, number, number];
  payouts?: { cc: number; cd: number; dc: number; dd: number };
  include_agents?: boolean;
  network_preset?: string | null;
  lattice_rows?: number;
  lattice_cols?: number;
};

export type AgentSeries = {
  id: number;
  inclination: number[];
  advocacy: ('C' | 'D')[];
  // Present only in network-mode runs
  local_cn_interaction?: boolean[];
  local_un_interaction?: boolean[];
  local_cn_influence?: boolean[];
  local_un_influence?: boolean[];
};

export type TopologyLayout =
  | { kind: 'lattice'; rows: number; cols: number }
  | { kind: 'default' };

export type Topology = {
  preset: string;
  layout: TopologyLayout;
  interaction: Record<string, number[]>;  // "id" -> peer ids
  influence:   Record<string, number[]>;
  // Present only for lattice layouts: agent id -> [row, col]
  positions?: Record<string, [number, number]>;
};

export type NetworkPreset = {
  name: string;
  label: string;
  description: string;
  kind: 'standard' | 'lattice';     // lattice requires rows+cols; standard takes no extra params
};

export type BehaviorCounts = {
  advC_playC: number[];
  advC_playD: number[];
  advD_playC: number[];
  advD_playD: number[];
};

export type LocalCounts = {
  cn_int: number[];
  un_int: number[];
  cn_infl: number[];
  un_infl: number[];
};

export type Series = {
  rounds: number[];
  avg_incl: number[];
  pr_adv_coop: number[];
  prop_cc: number[];
  prop_dd: number[];
  avg_payoff: number[];
  game_type: string[];
  payouts: { cc: number[]; cd: number[]; dc: number[]; dd: number[] };
  in_cn_norm: boolean[];
  in_un_norm: boolean[];
  agents: AgentSeries[];
  behavior: BehaviorCounts | null;
  topology: Topology | null;
  local_counts: LocalCounts | null;
};

export type Summary = {
  cai: number;
  avg_pr_adv_coop: number;
  advocacy_volatility: number;
  coop_behavior_time: number;
  defect_behavior_time: number;
  order_degree: number;
  cn_state_time: number;
  un_state_time: number;
  cn_time: number;
  un_time: number;
  cn_end_state: boolean;
  un_end_state: boolean;
  norm_transitions: number;
  avg_payoff_final: number;
  avg_advC_playC: number;
  avg_advC_playD: number;
  avg_advD_playC: number;
  avg_advD_playD: number;
  avg_uncommitted: number;
};

export type RunResponse = {
  seed: number;
  numrounds: number;
  stride: number;
  n_points: number;
  elapsed_sec: number;
  network_preset: string | null;
  population: number;
  series: Series;
  summary: Summary;
  params_echo: Record<string, unknown>;
};

export type Defaults = ModelParams & {
  default_base_game: string;
  numrounds_default: number;
};

export type Caps = {
  numrounds_max: number;
  numrounds_min: number;
  population_max: number;
  pressure_limit_max: number;
};

export type BaseGamesMap = Record<string, { R: number; S: number; T: number; P: number }>;
