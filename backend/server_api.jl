module ServerApi

using Agents
using Random
using Statistics: mean, std

# Thrown when the request is valid JSON but semantically rejected (e.g. a
# network preset that doesn't match the requested population). The HTTP
# layer converts these to 400 responses.
struct RequestError <: Exception
    msg::String
end
Base.showerror(io::IO, e::RequestError) = print(io, "RequestError: ", e.msg)

# The simulation sources are snapshotted into webapp/backend/sim/ by
# ../sync-sim.sh so the webapp directory can be deployed on its own without
# dragging the whole repo along.
const SIM_DIR = joinpath(@__DIR__, "sim")
include(joinpath(SIM_DIR, "advgames.jl"))
include(joinpath(SIM_DIR, "advgames_analysis.jl"))
include(joinpath(SIM_DIR, "base_params.jl"))

# ---------------------------------------------------------------------------
# Network simulation lives in its own submodule so its `Player`, `initialize`,
# `model_step!` etc. don't collide with the core model's. The analysis
# functions (pr_coop, advocate, avg_incl, ...) are duck-typed on the Player
# fields, so re-including advgames_analysis.jl inside NetSim just binds them
# to NetSim's Player type.
# ---------------------------------------------------------------------------
module NetSim
    using Agents
    using Parameters
    using Statistics: mean
    using Random, StatsBase
    using Graphs

    const SIM_DIR = joinpath(@__DIR__, "sim")
    include(joinpath(SIM_DIR, "peer_selection.jl"))
    using .PeerSelection
    include(joinpath(SIM_DIR, "advgames_network.jl"))
    include(joinpath(SIM_DIR, "advgames_analysis.jl"))
end

# ---------------------------------------------------------------------------
# mdata collected per round. Keep in sync with the frontend chart's assumptions.
# ---------------------------------------------------------------------------
const MDATA = Any[
    avg_incl,
    pr_adv_coop,
    prop_committed_cooperators,
    prop_committed_defectors,
    cc, cd, dc, dd,
    game_type,
    avg_payoff,
    # 2x2 advocacy × committed-behavior proportions (sum to ≤ 1; remainder = uncommitted)
    pr_adv_c_play_c,
    pr_hyp_adv_c_play_d,
    pr_hyp_adv_d_play_c,
    pr_adv_d_play_d,
]

# Per-agent data collected each round.
const ADATA = Any[
    pr_coop,        # Float64: inclination to cooperate
    advocate,       # Symbol:  :C or :D
]

# Count-based model measures that call the paper's local_cn_state /
# local_un_state once per agent each round and sum the hits. Each produces one
# Int per round, so they ship with every network run (no per-agent adf required).
count_local_cn_int(model)   = count(a -> NetSim.local_cn_state(model, a, NetSim.interaction_peers), Agents.allagents(model))
count_local_un_int(model)   = count(a -> NetSim.local_un_state(model, a, NetSim.interaction_peers), Agents.allagents(model))
count_local_cn_infl(model)  = count(a -> NetSim.local_cn_state(model, a, NetSim.influencers),       Agents.allagents(model))
count_local_un_infl(model)  = count(a -> NetSim.local_un_state(model, a, NetSim.influencers),       Agents.allagents(model))

# Same measure *functions* but resolved against NetSim's Player (the re-included
# advgames_analysis.jl inside NetSim binds these names there too).
const NETSIM_MDATA = Any[
    NetSim.avg_incl,
    NetSim.pr_adv_coop,
    NetSim.prop_committed_cooperators,
    NetSim.prop_committed_defectors,
    NetSim.cc, NetSim.cd, NetSim.dc, NetSim.dd,
    NetSim.game_type,
    NetSim.avg_payoff,
    NetSim.pr_adv_c_play_c,
    NetSim.pr_hyp_adv_c_play_d,
    NetSim.pr_hyp_adv_d_play_c,
    NetSim.pr_adv_d_play_d,
    # Local-norm counts — per round, summed via paper's local_cn_state/local_un_state.
    count_local_cn_int,
    count_local_un_int,
    count_local_cn_infl,
    count_local_un_infl,
]
const NETSIM_ADATA = Any[
    NetSim.pr_coop,
    NetSim.advocate,
]

# ---------------------------------------------------------------------------
# Network presets (matches NETWORK_CONFIGURATIONS in base_params.jl).
#
# Each preset has a label (what the UI dropdown shows), an internal name
# (what the API accepts), a layout descriptor that tells the frontend how
# to arrange agents, and a builder that returns the (interaction, influence)
# strategy pair using types from NetSim.PeerSelection.
#
# The Lattice preset requires a specific population (rows * cols).
# ---------------------------------------------------------------------------
struct NetworkPreset
    name::String
    label::String
    description::String
    # The build function receives the full validated request params dict so
    # parameterized topologies (e.g. lattice with custom rows/cols) can read
    # the user's chosen dimensions. It returns (interaction, influence, layout).
    build::Function
    kind::Symbol                       # :standard or :lattice
end

function _build_lattice_equal(p)
    rows = Int(get(p, :lattice_rows, 7))
    cols = Int(get(p, :lattice_cols, 7))
    return (
        NetSim.PeerSelection.GridMoore((rows, cols), false),
        NetSim.PeerSelection.EqualToInteraction(),
        Dict{String,Any}("kind" => "lattice", "rows" => rows, "cols" => cols),
    )
end

const NETWORK_PRESETS = NetworkPreset[
    NetworkPreset(
        "Global:Global",
        "Global / Global",
        "Everyone interacts with everyone; everyone influences everyone.",
        (p) -> (NetSim.PeerSelection.Global(), NetSim.PeerSelection.GlobalInfluence(),
                Dict{String,Any}("kind" => "default")),
        :standard,
    ),
    NetworkPreset(
        "Global:Rand-8",
        "Global / Random-8",
        "Global interaction, each agent influenced by 8 random peers.",
        (p) -> (NetSim.PeerSelection.Global(), NetSim.PeerSelection.RandomKInfluence(8),
                Dict{String,Any}("kind" => "default")),
        :standard,
    ),
    NetworkPreset(
        "Rand-8:Global",
        "Random-8 / Global",
        "Each agent plays 8 random peers; influenced by everyone.",
        (p) -> (NetSim.PeerSelection.RandomK(8), NetSim.PeerSelection.GlobalInfluence(),
                Dict{String,Any}("kind" => "default")),
        :standard,
    ),
    NetworkPreset(
        "Rand-8:Rand-8",
        "Random-8 / Random-8",
        "Each agent plays 8 random peers and is influenced by 8 random peers.",
        (p) -> (NetSim.PeerSelection.RandomK(8), NetSim.PeerSelection.RandomKInfluence(8),
                Dict{String,Any}("kind" => "default")),
        :standard,
    ),
    NetworkPreset(
        "Subset:Rand-8",
        "Subset-of-Influence / Random-8",
        "Each agent's interaction set is a random subset of its influencers.",
        (p) -> (NetSim.PeerSelection.SubsetOfInfluenceUniform(), NetSim.PeerSelection.RandomKInfluence(8),
                Dict{String,Any}("kind" => "default")),
        :standard,
    ),
    NetworkPreset(
        "Equal:Rand-8Reflexive",
        "Equal-to-Influence / Random-8 (reflexive)",
        "Interaction = influence; influence includes self.",
        (p) -> (NetSim.PeerSelection.EqualToInfluence(), NetSim.PeerSelection.RandomKInfluenceReflexive(8),
                Dict{String,Any}("kind" => "default")),
        :standard,
    ),
    NetworkPreset(
        "Equal:Rand-8Irreflexive",
        "Equal-to-Influence / Random-8 (irreflexive)",
        "Interaction = influence; influence excludes self.",
        (p) -> (NetSim.PeerSelection.EqualToInfluence(), NetSim.PeerSelection.RandomKInfluenceIrreflexive(8),
                Dict{String,Any}("kind" => "default")),
        :standard,
    ),
    NetworkPreset(
        "Lattice:Equal",
        "Lattice / Equal-to-Interaction",
        "Moore grid interaction; influence equals interaction. Population = rows × cols.",
        _build_lattice_equal,
        :lattice,
    ),
]

function find_preset(name::AbstractString)
    for p in NETWORK_PRESETS
        p.name == name && return p
    end
    return nothing
end

"""
Return the list of presets as JSON-friendly Dicts, for GET /network-configs.
"""
function network_presets_dict()
    [Dict(
        "name"        => p.name,
        "label"       => p.label,
        "description" => p.description,
        "kind"        => String(p.kind),  # :standard or :lattice (lattice needs rows+cols)
    ) for p in NETWORK_PRESETS]
end

# ---------------------------------------------------------------------------
# Norm detection, lifted from run_advgames_simulation.jl so we don't pull in
# CSV/DataFrames into the server.
# ---------------------------------------------------------------------------
function in_norm(state::AbstractVector{Bool}; min_stretch::Int=1000)
    n = length(state)
    result = falses(n)
    i = 1
    while i <= n
        if state[i]
            j = i
            while j <= n && state[j]
                j += 1
            end
            run_len = j - i
            if run_len >= min_stretch
                result[i:(j - 1)] .= true
            end
            i = j
        else
            i += 1
        end
    end
    return result
end

function count_norm_transitions(in_cn::AbstractVector{Bool}, in_un::AbstractVector{Bool})
    transitions = 0
    last = :none
    for i in eachindex(in_cn)
        current = in_cn[i] ? :cn : (in_un[i] ? :un : :none)
        if current != :none
            if last != :none && current != last
                transitions += 1
            end
            last = current
        end
    end
    return transitions
end

# ---------------------------------------------------------------------------
# Downsampling
# ---------------------------------------------------------------------------
"Pick row indices at uniform stride, always including first and last row."
function stride_indices(nrows::Int, stride::Int)
    stride = max(1, stride)
    idx = collect(1:stride:nrows)
    if !isempty(idx) && idx[end] != nrows
        push!(idx, nrows)
    end
    return idx
end

# ---------------------------------------------------------------------------
# Agent trajectory reshape
# ---------------------------------------------------------------------------
"""
Pivot the long-form agent dataframe from Agents.jl into one ordered entry per
agent with inclination and advocacy arrays sampled at `idx` (indices into the
per-agent time axis, 1-based, matching the model-level stride).

`adf` has one row per (time, id) with columns `pr_coop` and `advocate`. It is
sorted by (time, id), so row k for agent i (1..n) lives at index
    (t_idx - 1) * n + local_index_of(i)

We rebuild per-agent time vectors by bucketing rows on id.
"""
# Pivot the long-form adf into dicts keyed by agent id, returning the FULL
# per-round arrays (length = nrows), plus the insertion order of agent ids.
function pivot_adf(adf)
    incl = Dict{Int, Vector{Float64}}()
    adv  = Dict{Int, Vector{String}}()
    order = Int[]
    for row in eachrow(adf)
        id = Int(row.id)
        if !haskey(incl, id)
            incl[id] = Float64[]
            adv[id]  = String[]
            push!(order, id)
        end
        push!(incl[id], Float64(row.pr_coop))
        push!(adv[id],  String(row.advocate))
    end
    return (incl, adv, order)
end

function per_agent_series(adf, idx::AbstractVector{Int})
    (incl, adv, order) = pivot_adf(adf)
    out = Vector{Dict{String,Any}}(undef, length(order))
    for (k, id) in enumerate(order)
        out[k] = Dict(
            "id"          => id,
            "inclination" => incl[id][idx],
            "advocacy"    => adv[id][idx],
        )
    end
    return out
end

# (No custom local-norm formula here — we call NetSim.local_cn_state /
# NetSim.local_un_state directly from advgames_network.jl. See run_one.)

"""
Walk `gameplay_history` once and build four cumulative count arrays of length
`nrows` (one entry per mdf row, i.e. per time index 0..numrounds). Each entry
records how many plays of each (advocacy, move) kind have happened by that
round. Exactly 2 plays happen per round (the interacting pair), so the totals
grow by 2 each step.

Returns the arrays downsampled at `idx`, as plain Julia Ints so JSON3 ships
them compactly.
"""
function behavior_counts(model, nrows::Int, idx::AbstractVector{Int})
    # cumulative[i] = counts after i-1 rounds of play (i starts at 1 for round 0)
    cc_ = zeros(Int, nrows)  # advC playC
    cd_ = zeros(Int, nrows)  # advC playD
    dc_ = zeros(Int, nrows)  # advD playC
    dd_ = zeros(Int, nrows)  # advD playD

    props = abmproperties(model)
    hist = hasproperty(props, :gameplay_history) ? props.gameplay_history : nothing

    if hist !== nothing
        # Each history entry corresponds to one round; round t lives at mdf index t+1.
        # The core and network simulations use different NamedTuple field names
        # for the two interacting agents. Detect and normalize.
        for (k, step) in enumerate(hist)
            cc_[k + 1] = cc_[k]
            cd_[k + 1] = cd_[k]
            dc_[k + 1] = dc_[k]
            dd_[k + 1] = dd_[k]

            local adv1, move1, adv2, move2
            if hasproperty(step, :advocacy1)
                adv1, move1 = step.advocacy1, step.move1
                adv2, move2 = step.advocacy2, step.move2
            else
                adv1, move1 = step.advocacy_player,   step.move_player
                adv2, move2 = step.advocacy_opponent, step.move_opponent
            end
            advance_bucket!(cc_, cd_, dc_, dd_, adv1, move1, k + 1)
            advance_bucket!(cc_, cd_, dc_, dd_, adv2, move2, k + 1)
        end
    end

    return Dict(
        "advC_playC" => cc_[idx],
        "advC_playD" => cd_[idx],
        "advD_playC" => dc_[idx],
        "advD_playD" => dd_[idx],
    )
end

@inline function advance_bucket!(cc, cd, dc, dd,
                                 advocacy::Symbol, move::Symbol, i::Int)
    if advocacy == :C
        if move == :C
            cc[i] += 1
        else
            cd[i] += 1
        end
    else
        if move == :C
            dc[i] += 1
        else
            dd[i] += 1
        end
    end
    return nothing
end

# ---------------------------------------------------------------------------
# Public metadata for the frontend
# ---------------------------------------------------------------------------

# Games exposed via the webapp. The double / epsilon variants defined in
# base_params.jl are for internal experiments and are hidden here — both from
# the dropdown and from /run's validator.
const HIDDEN_BASE_GAMES = Set{Symbol}([
    :PD_STANDARD_double,
    :PD_STANDARD_epsilon,
    :PD_STANDARD_epsilon_double,
])

const EXPOSED_BASE_GAMES = Dict(
    k => v for (k, v) in BASE_GAMES if !(k in HIDDEN_BASE_GAMES)
)

"""
Return a Dict of base_game_name => {R, S, T, P} (Float64) for the UI's dropdown.
"""
function base_games_dict()
    out = Dict{String, Any}()
    for (name, payout_dict) in EXPOSED_BASE_GAMES
        out[String(name)] = Dict(
            "R" => Float64(payout_dict[(:C, :C)]),
            "S" => Float64(payout_dict[(:C, :D)]),
            "T" => Float64(payout_dict[(:D, :C)]),
            "P" => Float64(payout_dict[(:D, :D)]),
        )
    end
    return out
end

"""
Return the paper default model parameters as plain JSON-friendly types.
payouts are exposed as `default_base_game` (name) rather than the raw Dict.
"""
function defaults_dict()
    mp = MODEL_PARAMS
    Dict(
        "num_cooperators"            => mp.num_cooperators,
        "num_defectors"              => mp.num_defectors,
        "num_neutrals"               => mp.num_neutrals,
        "init_pr_coop_cooperator"    => mp.init_pr_coop_cooperator,
        "init_pr_coop_defector"      => mp.init_pr_coop_defector,
        "default_base_game"          => "PD_STANDARD",
        "learning_increment"         => mp.learning_increment,
        "weight_of_present_for_move" => mp.weight_of_present_for_move,
        "weight_of_present_for_adv"  => mp.weight_of_present_for_adv,
        "move_mutation_rate"         => mp.move_mutation_rate,
        "adv_mutation_rate"          => mp.adv_mutation_rate,
        "tolerance"                  => mp.tolerance,
        "pos_pressure_limit"         => mp.pos_pressure_limit,
        "neg_pressure_limit"         => mp.neg_pressure_limit,
        "move_reassess_frequency"    => mp.move_reassess_frequency,
        "adv_reassess_frequency"     => mp.adv_reassess_frequency,
        "numrounds_default"          => 100_000,
    )
end

# ---------------------------------------------------------------------------
# Core: run one simulation and return a JSON-serializable Dict
# ---------------------------------------------------------------------------
"""
    run_one(model_params::Dict; numrounds, seed, stride) -> Dict

Initialize and run one simulation. Compute norm bands on the full trajectory,
then downsample time series to roughly numrounds/stride points.

The returned Dict has only JSON-friendly types (numbers, strings, bools, arrays, nested Dicts).
"""
function run_one(model_params::AbstractDict; numrounds::Int, seed::Union{Int,Nothing}=nothing,
                 stride::Int=max(1, numrounds ÷ 2000),
                 include_agents::Bool=false,
                 network_preset::Union{String,Nothing}=nothing,
                 lattice_rows::Union{Int,Nothing}=nothing,
                 lattice_cols::Union{Int,Nothing}=nothing)

    used_seed = seed === nothing ? rand(UInt32) % typemax(Int32) : seed
    Random.seed!(Int(used_seed))

    preset = network_preset === nothing ? nothing : find_preset(network_preset)
    if network_preset !== nothing && preset === nothing
        throw(RequestError("unknown network_preset '$network_preset'"))
    end

    # Lattice topologies require population == rows × cols, with both dims ≥ 2.
    preset_params = Dict{Symbol,Any}()
    if preset !== nothing && preset.kind == :lattice
        r = lattice_rows === nothing ? 7 : Int(lattice_rows)
        c = lattice_cols === nothing ? 7 : Int(lattice_cols)
        if r < 2 || c < 2
            throw(RequestError("lattice dimensions must each be ≥ 2 (got $r × $c)"))
        end
        if r * c > 200
            throw(RequestError("lattice rows × cols exceeds 200 (got $(r*c))"))
        end
        pop = Int(get(model_params, :num_cooperators, 0)) +
              Int(get(model_params, :num_defectors, 0)) +
              Int(get(model_params, :num_neutrals, 0))
        if pop != r * c
            throw(RequestError("lattice $(r)×$(c) requires exactly $(r*c) agents (got $pop)"))
        end
        preset_params[:lattice_rows] = r
        preset_params[:lattice_cols] = c
    end

    t0 = time()
    # When agents are requested, also turn on gameplay tracking so we can
    # return cumulative per-round behavior counts for the animation view.
    local init_params = model_params
    if include_agents
        init_params = Dict{Symbol,Any}(model_params)
        init_params[:track_gameplay] = true
    end

    local model, adf, mdf
    if preset === nothing
        # --- core (non-network) simulation ---
        model, _parameters = initialize(; init_params...)
        if include_agents
            adf, mdf = run!(model, numrounds; adata=ADATA, mdata=MDATA)
        else
            _, mdf = run!(model, numrounds; mdata=MDATA)
            adf = nothing
        end
    else
        # --- network simulation ---
        interaction, influence, preset_layout = preset.build(preset_params)
        net_params = Dict{Symbol,Any}(init_params)
        net_params[:interaction_strategy] = interaction
        net_params[:influence_strategy]   = influence
        model, _parameters = NetSim.initialize(; net_params...)
        if include_agents
            adf, mdf = Agents.run!(model, numrounds;
                                    adata = NETSIM_ADATA, mdata = NETSIM_MDATA)
        else
            _, mdf = Agents.run!(model, numrounds; mdata = NETSIM_MDATA)
            adf = nothing
        end
    end

    elapsed_sim = time() - t0

    nrows = size(mdf, 1)

    # --- norm detection on the FULL trajectory (1000-round stretch rule) ---
    coop_behavior   = mdf.prop_committed_cooperators .>= 0.80
    defect_behavior = mdf.prop_committed_defectors   .>= 0.80
    cn_state = coop_behavior .& (mdf.pr_adv_coop .>  0.50)
    un_state = defect_behavior .& (mdf.pr_adv_coop .< 0.50)
    in_cn = in_norm(cn_state)
    in_un = in_norm(un_state)
    transitions = count_norm_transitions(in_cn, in_un)

    # --- summary statistics (full resolution) ---
    avg_advC_playC = mean(mdf.pr_adv_c_play_c)
    avg_advC_playD = mean(mdf.pr_hyp_adv_c_play_d)
    avg_advD_playC = mean(mdf.pr_hyp_adv_d_play_c)
    avg_advD_playD = mean(mdf.pr_adv_d_play_d)
    avg_uncommitted = 1.0 - (avg_advC_playC + avg_advC_playD + avg_advD_playC + avg_advD_playD)

    summary = Dict(
        "cai"                  => mean(mdf.avg_incl),
        "avg_pr_adv_coop"      => mean(mdf.pr_adv_coop),
        "advocacy_volatility"  => std(mdf.pr_adv_coop),
        "coop_behavior_time"   => mean(coop_behavior),
        "defect_behavior_time" => mean(defect_behavior),
        "order_degree"         => mean(coop_behavior .| defect_behavior),
        "cn_state_time"        => mean(cn_state),
        "un_state_time"        => mean(un_state),
        "cn_time"              => mean(in_cn),
        "un_time"              => mean(in_un),
        "cn_end_state"         => Bool(in_cn[end]),
        "un_end_state"         => Bool(in_un[end]),
        "norm_transitions"     => transitions,
        "avg_payoff_final"     => mdf.avg_payoff[end],
        # 2x2 advocacy × committed-behavior averages
        "avg_advC_playC"       => avg_advC_playC,
        "avg_advC_playD"       => avg_advC_playD,
        "avg_advD_playC"       => avg_advD_playC,
        "avg_advD_playD"       => avg_advD_playD,
        "avg_uncommitted"      => max(0.0, avg_uncommitted),
    )

    # --- downsample for transport ---
    idx = stride_indices(nrows, stride)
    rounds = (collect(0:(nrows-1)))[idx]  # mdf rows correspond to t = 0, 1, 2, ... numrounds

    # Agents series + (for network) augment with local norms + topology.
    local agents_series::Vector{Dict{String,Any}} = Dict{String,Any}[]
    local topology = nothing

    if adf !== nothing
        (incl_full, adv_full, order) = pivot_adf(adf)
        agents_series = Vector{Dict{String,Any}}(undef, length(order))
        for (k, id) in enumerate(order)
            agents_series[k] = Dict(
                "id"          => id,
                "inclination" => incl_full[id][idx],
                "advocacy"    => adv_full[id][idx],
            )
        end

        if preset !== nothing
            # Snapshot static peer sets for the topology payload.
            int_hoods  = Dict{Int, Vector{Int}}()
            infl_hoods = Dict{Int, Vector{Int}}()
            for a in Agents.allagents(model)
                int_hoods[a.id]  = sort!(collect(a.interaction_peer_ids))
                infl_hoods[a.id] = sort!(collect(a.influence_by_peer_ids))
            end

            # Pre-allocate output arrays on each agent row.
            out_map = Dict{Int, Dict{String,Any}}()
            n_sampled = length(idx)
            for ag in agents_series
                ag["local_cn_interaction"] = zeros(Bool, n_sampled)
                ag["local_un_interaction"] = zeros(Bool, n_sampled)
                ag["local_cn_influence"]   = zeros(Bool, n_sampled)
                ag["local_un_influence"]   = zeros(Bool, n_sampled)
                out_map[ag["id"]] = ag
            end

            # For each sampled round, restore every agent's pr_coop and advocacy
            # from the adf snapshot, then call the paper's NetSim.local_cn_state /
            # NetSim.local_un_state exactly — no re-implementation here.
            agent_list = collect(Agents.allagents(model))
            for (si, ti) in enumerate(idx)
                for a in agent_list
                    x = incl_full[a.id][ti]
                    a.move_settings.inclinations[:C] = x
                    a.move_settings.inclinations[:D] = 1.0 - x
                    a.advocacy_settings.adv_type = Symbol(adv_full[a.id][ti])
                end
                for a in agent_list
                    out = out_map[a.id]
                    out["local_cn_interaction"][si] = NetSim.local_cn_state(model, a, NetSim.interaction_peers)
                    out["local_un_interaction"][si] = NetSim.local_un_state(model, a, NetSim.interaction_peers)
                    out["local_cn_influence"][si]   = NetSim.local_cn_state(model, a, NetSim.influencers)
                    out["local_un_influence"][si]   = NetSim.local_un_state(model, a, NetSim.influencers)
                end
            end

            topology = Dict(
                "preset"      => preset.name,
                "layout"      => preset_layout,
                "interaction" => Dict(string(id) => peers for (id, peers) in int_hoods),
                "influence"   => Dict(string(id) => peers for (id, peers) in infl_hoods),
            )

            # For lattice layouts, compute each agent's (row, col) using the
            # same reshape convention as PeerSelection.grid_peers (column-major
            # over `collect(allids(model))`) so the frontend can place agents
            # at the same grid positions the sim uses internally.
            if preset_layout["kind"] == "lattice"
                rows = Int(preset_layout["rows"])
                all_ids = collect(Agents.allids(model))
                positions = Dict{String, Vector{Int}}()
                for (k, id) in enumerate(all_ids)
                    r = mod1(k, rows)
                    c = div(k - 1, rows) + 1
                    positions[string(id)] = [r, c]
                end
                topology["positions"] = positions
            end
        end
    end

    ts = Dict(
        "rounds"        => rounds,
        "avg_incl"      => Float64.(mdf.avg_incl[idx]),
        "pr_adv_coop"   => Float64.(mdf.pr_adv_coop[idx]),
        "prop_cc"       => Float64.(mdf.prop_committed_cooperators[idx]),
        "prop_dd"       => Float64.(mdf.prop_committed_defectors[idx]),
        "avg_payoff"    => Float64.(mdf.avg_payoff[idx]),
        "game_type"     => String.(mdf.game_type[idx]),
        "payouts"       => Dict(
            "cc" => Float64.(mdf.cc[idx]),
            "cd" => Float64.(mdf.cd[idx]),
            "dc" => Float64.(mdf.dc[idx]),
            "dd" => Float64.(mdf.dd[idx]),
        ),
        "in_cn_norm"    => Bool.(in_cn[idx]),
        "in_un_norm"    => Bool.(in_un[idx]),
        "agents"        => agents_series,
        "topology"      => topology,
        "behavior"      => include_agents ? behavior_counts(model, nrows, idx) : nothing,
        # Local-norm counts — present only in network runs; nothing in core runs.
        "local_counts"  => (preset === nothing ? nothing : Dict(
            "cn_int"  => Int.(mdf.count_local_cn_int[idx]),
            "un_int"  => Int.(mdf.count_local_un_int[idx]),
            "cn_infl" => Int.(mdf.count_local_cn_infl[idx]),
            "un_infl" => Int.(mdf.count_local_un_infl[idx]),
        )),
    )

    pop_total = Int(get(model_params, :num_cooperators, 0)) +
                Int(get(model_params, :num_defectors, 0)) +
                Int(get(model_params, :num_neutrals, 0))

    response = Dict(
        "seed"            => Int(used_seed),
        "numrounds"       => numrounds,
        "stride"          => stride,
        "n_points"        => length(idx),
        "elapsed_sec"     => round(elapsed_sim; digits=3),
        "network_preset"  => preset === nothing ? nothing : preset.name,
        "population"      => pop_total,
        "series"          => ts,
        "summary"         => summary,
    )

    # A 500K run transiently allocates several GB; Julia's lazy GC can hold
    # those pages for a long time. Force a collection so RSS returns to
    # baseline between requests.
    model = nothing
    adf = nothing
    mdf = nothing
    GC.gc()

    return response
end

end # module
