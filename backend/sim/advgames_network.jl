using Agents
using Parameters
using Statistics: mean
using Random, StatsBase
using Graphs

if !isdefined(Main, :PeerSelection)
    include("./peer_selection.jl")      
end
using .PeerSelection                    

@with_kw mutable struct MoveSettings
    inclinations::Dict{Symbol, Float64} = Dict(:C => 0.5, :D => 0.5)
    act_est::Dict{Symbol, Float64} = Dict(:C => 0.0, :D => 0.0)
    weight_of_present::Float64 = 0.2
    learning_increment::Float64 = 0.15
    move_mutation_rate::Float64 = 0.15
end

@with_kw mutable struct AdvocacySettings
    adv_type::Symbol = :C
    adv_est::Dict{Symbol, Float64} = Dict(:C => 0.0, :D => 0.0)
    weight_of_present::Float64 = 0.3
    adv_mutation_rate::Float64 = 0.2
end

"""
A Player in the advocacy game.

Fields:
  - id: Unique identifier.
  - acts: List of possible actions.
  - move_settings: Settings that define how the player chooses its moves.
  - advocacy_settings: Settings that define how the player updates its advocacy.
  - tolerance: Threshold for updating estimates.
  - total_payout, num_moves, num_adv_mutations: Tracking fields.
"""
@with_kw mutable struct Player <: AbstractAgent
    
    id::Int
    acts::Vector{Symbol} = [:C, :D]
    
    move_settings::MoveSettings = MoveSettings()
    advocacy_settings::AdvocacySettings = AdvocacySettings()
    
    # each player maintains their own payouts of the game
    payouts::Dict{Tuple{Symbol, Symbol}, Float64}
    
    influence_by_peer_ids::Set{Int} = Set{Int}()   # peers that influence ME
    influencing_peer_ids::Set{Int}  = Set{Int}()   # peers that I influence
    interaction_peer_ids::Set{Int}  = Set{Int}()   # peers I interact with
    
    tolerance::Float64 = 0.05
    
    total_payout::Float64 = 0.0
    num_moves::Int = 0
    num_adv_mutations::Int = 0
end

# A biased coin flip.
flip(bias) = rand() < bias

# Return the other action.
other_act(act) = act != :C ? :C : :D

# Helper functions to extract information about a player.
advocate(player) = player.advocacy_settings.adv_type

inc_coop(player) = player.move_settings.inclinations[:C]
pr_coop(player) = inc_coop(player)

inc_defect(player) = player.move_settings.inclinations[:D]
pr_defect(player) = inc_defect(player)

est_move_coop(player) = player.move_settings.act_est[:C]
est_move_defect(player) = player.move_settings.act_est[:D]
est_adv_coop(player) = player.advocacy_settings.adv_est[:C]
est_adv_defect(player) = player.advocacy_settings.adv_est[:D]

utility_adv_coop(player) = est_adv_coop(player) - est_adv_defect(player)
utility_inc_coop(player) = est_move_coop(player) - est_move_defect(player)

influencers(player::Player)  = player.influence_by_peer_ids   # incoming
influencees(player::Player)  = player.influencing_peer_ids    # outgoing
interaction_peers(player)    = player.interaction_peer_ids
payout(player, act, other_act) = player.payouts[act, other_act]


# ============================================================================
# Local CN / UN state helpers
# ----------------------------------------------------------------------------
# A "local CN-state" for agent `a` at a given round uses exactly the same
# rule as the population-level CN-state, but restricted to a's own
# neighborhood (a ∪ peers). Two flavors of neighborhood are supported via
# the `get_hood` argument:
#
#   get_hood = influencers       → "who exerts pressure on me"
#   get_hood = interaction_peers → "who do I play against"
#
# Both must be used with the is_committed_cooperator / is_committed_defector
# / advocate predicates defined in advgames_analysis.jl; those are
# late-bound and so not needed at module parse time.
#
# If |hood|+1 < 2 (an isolated agent) the state is defined as false -- a
# one-agent norm is meaningless.
# ============================================================================

function local_cn_state(model, a, get_hood; threshold::Float64=0.80)
    hood_ids = get_hood(a)
    self_in_hood = a.id in hood_ids
    k = length(hood_ids) + (self_in_hood ? 0 : 1)
    if k < 2
        return false
    end
    # Self is counted exactly once. If the peer list already includes self,
    # start the counts at 0; otherwise seed with self's contribution.
    n_coop = self_in_hood ? 0 : (is_committed_cooperator(a) ? 1 : 0)
    n_adv_c = self_in_hood ? 0 : ((advocate(a) == :C) ? 1 : 0)
    for id in hood_ids
        p = model[id]
        n_coop += is_committed_cooperator(p) ? 1 : 0
        n_adv_c += (advocate(p) == :C) ? 1 : 0
    end
    return (n_coop / k >= threshold) && (n_adv_c / k > 0.50)
end

function local_un_state(model, a, get_hood; threshold::Float64=0.80)
    hood_ids = get_hood(a)
    self_in_hood = a.id in hood_ids
    k = length(hood_ids) + (self_in_hood ? 0 : 1)
    if k < 2
        return false
    end
    n_def = self_in_hood ? 0 : (is_committed_defector(a) ? 1 : 0)
    n_adv_d = self_in_hood ? 0 : ((advocate(a) == :D) ? 1 : 0)
    for id in hood_ids
        p = model[id]
        n_def += is_committed_defector(p) ? 1 : 0
        n_adv_d += (advocate(p) == :D) ? 1 : 0
    end
    return (n_def / k >= threshold) && (n_adv_d / k > 0.50)
end

"""
    local_cn_mask!(out, model, get_hood; threshold=0.80)

Fill `out` (a `BitVector` of length `nagents(model)`) with
`local_cn_state(model, a, get_hood; threshold)` for every agent, in the
order yielded by `allagents(model)`.

Short-circuit: if the first agent's neighborhood (hood ∪ {self}) covers
the entire population, every agent's neighborhood must also (there are
only N agents). In that case the local CN-state collapses to the
population-level CN-state, so we compute it once and fill `out`.
"""
function local_cn_mask!(out::BitVector, model, get_hood; threshold::Float64=0.80)
    n = length(out)
    first_a = first(allagents(model))
    first_hood = get_hood(first_a)
    first_k = length(first_hood) + (first_a.id in first_hood ? 0 : 1)
    if first_k >= n
        # Whole-population neighborhood -> global CN-state for every agent.
        n_coop = 0
        n_adv_c = 0
        for p in allagents(model)
            is_committed_cooperator(p) && (n_coop += 1)
            advocate(p) == :C && (n_adv_c += 1)
        end
        val = (n_coop / n >= threshold) && (n_adv_c / n > 0.50)
        fill!(out, val)
        return out
    end
    for (i, a) in enumerate(allagents(model))
        out[i] = local_cn_state(model, a, get_hood; threshold=threshold)
    end
    return out
end

function local_un_mask!(out::BitVector, model, get_hood; threshold::Float64=0.80)
    n = length(out)
    first_a = first(allagents(model))
    first_hood = get_hood(first_a)
    first_k = length(first_hood) + (first_a.id in first_hood ? 0 : 1)
    if first_k >= n
        n_def = 0
        n_adv_d = 0
        for p in allagents(model)
            is_committed_defector(p) && (n_def += 1)
            advocate(p) == :D && (n_adv_d += 1)
        end
        val = (n_def / n >= threshold) && (n_adv_d / n > 0.50)
        fill!(out, val)
        return out
    end
    for (i, a) in enumerate(allagents(model))
        out[i] = local_un_state(model, a, get_hood; threshold=threshold)
    end
    return out
end


# Helper function to convert input to a Set
to_set(peer_ids::Set{Int}) = peer_ids
to_set(peer_ids::Vector{Int}) = Set(peer_ids)
to_set(peer_id::Int) = Set([peer_id])

"""
    add_influencees!(player, peer_ids)

Add agents that *player* influences (outgoing edges).
"""
function add_influencees!(player::Player, peer_ids)
    union!(player.influencing_peer_ids, to_set(peer_ids))
end

remove_influencees!(player::Player, peer_ids) =
    setdiff!(player.influencing_peer_ids, to_set(peer_ids))


"""
    add_influencers!(player, peer_ids)

Add agents that influence *player* (incoming edges).
"""
function add_influencers!(player::Player, peer_ids)
    union!(player.influence_by_peer_ids, to_set(peer_ids))
end

remove_influencers!(player::Player, peer_ids) =
    setdiff!(player.influence_by_peer_ids, to_set(peer_ids))

"""
    add_interaction_peers!(player, peer_ids)

Add agents that interact with the player.
"""
add_interaction_peers!(player::Player, peer_ids) =
    union!(player.interaction_peer_ids, to_set(peer_ids))

remove_interaction_peers!(player::Player, peer_ids) =
    setdiff!(player.interaction_peer_ids, to_set(peer_ids))




# Using the move_settings, randomly select an act, then possibly mutate.
function move(player)
    weights = [player.move_settings.inclinations[a] for a in player.acts]
    tentative_move = sample(player.acts, Weights(weights), 1)[1]
    return flip(player.move_settings.move_mutation_rate) ? other_act(tentative_move) : tentative_move
end

# Update total payouts and move counts.
update_total_payout!(player, payout) = player.total_payout += payout
update_num_moves!(player) = player.num_moves += 1

# Update act estimates using values from move_settings.
update_act_estimate!(player, payout, act) =
    player.move_settings.act_est[act] = 
        player.move_settings.weight_of_present * payout +
        (1 - player.move_settings.weight_of_present) * player.move_settings.act_est[act]

# Update advocacy estimates using values from advocacy_settings.
update_adv_estimate!(player, payout, adv) =
    player.advocacy_settings.adv_est[adv] =
        player.advocacy_settings.weight_of_present * payout +
        (1 - player.advocacy_settings.weight_of_present) * player.advocacy_settings.adv_est[adv]

function update_estimates!(player, payout, act, adv)
    update_act_estimate!(player, payout, act)
    update_adv_estimate!(player, payout, adv)
    return player
end

# Update the player's advocacy type.
function update_advocate_type!(player)
    est_diff = player.advocacy_settings.adv_est[:C] - player.advocacy_settings.adv_est[:D]
    # Change advocacy based on estimated returns.
    if abs(est_diff) >= player.tolerance && est_diff > 0
        player.advocacy_settings.adv_type = :C
    elseif abs(est_diff) >= player.tolerance && est_diff < 0
        player.advocacy_settings.adv_type = :D
    end
    # With small probability, mutate the advocacy type.
    if flip(player.advocacy_settings.adv_mutation_rate)
        player.num_adv_mutations += 1
        player.advocacy_settings.adv_type = other_act(player.advocacy_settings.adv_type)
    end
    return
end

# Update the player's inclinations (in move_settings).
function update_inclinations!(player)
    est_diff = player.move_settings.act_est[:C] - player.move_settings.act_est[:D]
    if abs(est_diff) > player.tolerance
        new_incl = player.move_settings.inclinations[:C] + est_diff * player.move_settings.learning_increment
        if new_incl > 1
            player.move_settings.inclinations[:C] = 1
            player.move_settings.inclinations[:D] = 0
        elseif new_incl < 0
            player.move_settings.inclinations[:C] = 0
            player.move_settings.inclinations[:D] = 1
        else
            player.move_settings.inclinations[:C] = new_incl
            player.move_settings.inclinations[:D] = 1 - new_incl
        end
    end
    return
end

## Update Game

# Count the number of players advocating a given action.
num_advocating(players, act) = length([a for a in players if advocate(a)== act])

# For local influence
function update_game!(model, player)
    peers = [model[id] for id in influencers(player)]
    properties = abmproperties(model)
    update_payouts!(
        player.payouts, 
        peers, 
        properties.pos_pressure_limit,
        properties.neg_pressure_limit,
        properties.base_payouts)
end

# For global influence
function update_game!(model)
    all_players = collect(values(allagents(model)))
    properties = abmproperties(model)
    update_payouts!(
        abmproperties(model).payouts, 
        all_players, 
        properties.pos_pressure_limit, 
        properties.neg_pressure_limit, 
        properties.base_payouts)
end

# Update the current game (i.e., adjust the payoff matrix) based on advocacy proportions.
function update_payouts!(
    target_payouts, 
    peers, 
    pos_pressure_limit, 
    neg_pressure_limit, 
    base_payouts)
    
    num_peers = length(peers)

    proportion_adv_C = num_advocating(peers, :C) / num_peers
    proportion_adv_D = num_advocating(peers, :D) / num_peers

    pos_pressure = proportion_adv_C > 0.5 ? pos_pressure_limit * (2 * proportion_adv_C - 1) :
    pos_pressure_limit * (2 * proportion_adv_D - 1)
    neg_pressure = proportion_adv_C > 0.5 ? neg_pressure_limit * (2 * proportion_adv_C - 1) :
    neg_pressure_limit * (2 * proportion_adv_D - 1)

    new_payouts = if proportion_adv_C > 0.5
        Dict(
            (:C, :C) => base_payouts[:C, :C] + pos_pressure,
            (:C, :D) => base_payouts[:C, :D] + pos_pressure,
            (:D, :C) => base_payouts[:D, :C] - neg_pressure,
            (:D, :D) => base_payouts[:D, :D] - neg_pressure,
        )
    else
        Dict(
            (:C, :C) => base_payouts[:C, :C] - neg_pressure,
            (:C, :D) => base_payouts[:C, :D] - neg_pressure,
            (:D, :C) => base_payouts[:D, :C] + pos_pressure,
            (:D, :D) => base_payouts[:D, :D] + pos_pressure,
        )
    end

    for k in keys(new_payouts)
        target_payouts[k] = new_payouts[k]
    end
end

## Model Step

# Helper function to decide if an update should occur.
should_update(frequency) = flip(frequency)

function maybe_update_inclinations!(player, frequency)
    if should_update(frequency)
        update_inclinations!(player)
        return true  # reassessed regardless of numeric change
    end
    return false
end

function maybe_update_advocacy!(player, frequency)
    old_advocacy = advocate(player)
    if should_update(frequency)
        update_advocate_type!(player)
        return advocate(player) != old_advocacy  # true only if changed
    end
    return false
end

function model_step!(model)
    # Randomly select a player and an opponent.
    # The player is selected from the model, and the opponent is selected from the player's interaction peers.
    player = random_agent(model)
    opponent_id  = rand(interaction_peers(player))
    opponent = model[opponent_id]

    move_player = move(player)
    move_opponent = move(opponent)

    payoff_player = payout(player, move_player, move_opponent) 
    payoff_opponent = payout(opponent, move_opponent, move_player) 

    advocacy_player = advocate(player)
    advocacy_opponent = advocate(opponent)
    
    update_total_payout!(player, payoff_player)
    update_total_payout!(opponent, payoff_opponent)

    update_num_moves!(player)
    update_num_moves!(opponent)

    update_estimates!(player, payoff_player, move_player, advocacy_player)
    update_estimates!(opponent, payoff_opponent, move_opponent, advocacy_opponent)

    # Retrieve the adv/move reassess frequencies.
    current_props = abmproperties(model)

    # update advocacy
    player_advocacy_updated = maybe_update_advocacy!(player, current_props.adv_reassess_frequency)
    
    opponent_advocacy_updated = maybe_update_advocacy!(opponent, current_props.adv_reassess_frequency)
    
    advocacy_updated = player_advocacy_updated || opponent_advocacy_updated

    # update inclinations
    player_inclination_updated = maybe_update_inclinations!(player, current_props.move_reassess_frequency)
    
    opponent_inclination_updated = maybe_update_inclinations!(opponent, current_props.move_reassess_frequency)

    if advocacy_updated

        # Track which players have their games updated
        games_updated_ids = Int[]
        
        # 1. update the two focal agents directly
        update_game!(model, player)
        update_game!(model, opponent)
        push!(games_updated_ids, player.id)
        push!(games_updated_ids, opponent.id)

        # 2. build the union of all agents they influence
        targets = union(influencees(player), influencees(opponent))

        # 3. update every target except the two we just handled
        for pid in targets
            if pid != player.id && pid != opponent.id
                update_game!(model, model[pid])
                push!(games_updated_ids, pid)
            end
        end
        
        # Record gameplay if tracking is enabled
        if haskey(current_props, :track_gameplay) && current_props.track_gameplay
            push!(current_props.gameplay_history, (
                time = abmtime(model),
                player_id = player.id,
                opponent_id = opponent.id,
                move_player = move_player,
                move_opponent = move_opponent,
                advocacy_player = advocacy_player,
                advocacy_opponent = advocacy_opponent,
                payoff_player = payoff_player,
                payoff_opponent = payoff_opponent,
                player_advocacy_updated = player_advocacy_updated,
                opponent_advocacy_updated = opponent_advocacy_updated,
                player_inclination_updated = player_inclination_updated,
                opponent_inclination_updated = opponent_inclination_updated,
                games_updated_ids = games_updated_ids  # NEW: IDs of players whose games were updated
            ))
        end
    elseif haskey(current_props, :track_gameplay) && current_props.track_gameplay
        # Still record gameplay even if no advocacy update
        push!(current_props.gameplay_history, (
            time = abmtime(model),
            player_id = player.id,
            opponent_id = opponent.id,
            move_player = move_player,
            move_opponent = move_opponent,
            advocacy_player = advocacy_player,
            advocacy_opponent = advocacy_opponent,
            payoff_player = payoff_player,
            payoff_opponent = payoff_opponent,
            player_advocacy_updated = player_advocacy_updated,
            opponent_advocacy_updated = opponent_advocacy_updated,
            player_inclination_updated = player_inclination_updated,
            opponent_inclination_updated = opponent_inclination_updated,
            games_updated_ids = Int[]  # Empty list when no games updated
        ))
    end
end


generate_payouts(R, S, T, P) = Dict((:C, :C) => R, (:C, :D) => S, (:D, :C) => T, (:D, :D) => P)

function initialize(; 
    num_cooperators = 6,
    init_pr_coop_cooperator = 0.75,
    num_defectors = 6,
    init_pr_coop_defector = 0.25,
    num_neutrals = 0,
    rstp = nothing,
    payouts = Dict(
        (:C, :C) => 3.0,
        (:C, :D) => 0.0,
        (:D, :C) => 4.0,
        (:D, :D) => 1.0
    ),
    learning_increment = 0.15,
    weight_of_present_for_move = 0.3,
    weight_of_present_for_adv = 0.2,
    move_mutation_rate = 0.03,
    adv_mutation_rate = 0.15,
    tolerance = 0.05,
    pos_pressure_limit = 4,
    neg_pressure_limit = 4,
    move_reassess_frequency = 0.5,
    adv_reassess_frequency = 0.01,
    track_gameplay = false,
    # Peer selection
    interaction_strategy::PeerSelection.InteractionStrategy =
        PeerSelection.Global(),            # everyone can meet everyone
    influence_strategy::PeerSelection.InfluenceStrategy   =
        PeerSelection.GlobalInfluence(),   # everyone influences everyone
)
    # Determine base payouts: if rstp is provided, generate payouts; otherwise, use the given payouts.
    base_payouts = rstp === nothing ? payouts : generate_payouts(rstp[1], rstp[2], rstp[3], rstp[4])
    
    # Total number of agents.
    total_agents = num_cooperators + num_defectors + num_neutrals
    
    # Define model properties as a NamedTuple.
    properties = (
        payouts = deepcopy(base_payouts),
        base_payouts = deepcopy(base_payouts),
        adv_reassess_frequency = adv_reassess_frequency,
        move_reassess_frequency = move_reassess_frequency,
        pos_pressure_limit = pos_pressure_limit,
        neg_pressure_limit = neg_pressure_limit,
        interaction_strategy = interaction_strategy,
        influence_strategy = influence_strategy,
        track_gameplay = track_gameplay,
        gameplay_history = track_gameplay ? Vector{NamedTuple}() : nothing,
    )
    
    # Record simulation parameters for later analysis.
    parameters = Dict{Symbol, Any}(
        :base_payouts => [base_payouts[(:D, :C)], base_payouts[(:C, :C)], base_payouts[(:D, :D)], base_payouts[(:C, :D)]],
        :num_cooperators => num_cooperators,
        :num_defectors => num_defectors,
        :num_neutrals => num_neutrals,
        :population => total_agents,
        :adv_and_move_reassess_frequencies => [adv_reassess_frequency, move_reassess_frequency],
        :pos_and_neg_pressure_limits => [pos_pressure_limit, neg_pressure_limit],
        :adv_and_move_mutation_rates => [adv_mutation_rate, move_mutation_rate],
        :tolerance => tolerance,
        :adv_and_move_weights_of_present => [weight_of_present_for_adv, weight_of_present_for_move],
        :learning_increment => learning_increment,
        :interaction_strategy => string(typeof(interaction_strategy)),
        :influence_strategy   => string(typeof(influence_strategy)),
    )
    
    # Create a non-spatial model using StandardABM.
    # In Agents.jl v6, pass nothing as the space if not using spatial dynamics.
    model = StandardABM(Player, nothing; 
        properties = properties, 
        model_step! = model_step!
    )
    
    # Compute a default return estimate from the base payouts.
    default_estimate = mean([
        base_payouts[(:C, :C)], 
        base_payouts[(:C, :D)], 
        base_payouts[(:D, :C)], 
        base_payouts[(:D, :D)]
    ])
    
    # Helper function to create a player, add it to the model.
    function create_and_add_player!(player_id, init_coop, advocacy_type)
        player = Player(
            id = player_id,
            acts = [:C, :D],
            move_settings = MoveSettings(
                inclinations = Dict(:C => init_coop, :D => 1 - init_coop),
                act_est = Dict(:C => default_estimate, :D => default_estimate),
                weight_of_present = weight_of_present_for_move,
                learning_increment = learning_increment,
                move_mutation_rate = move_mutation_rate
            ),
            advocacy_settings = AdvocacySettings(
                adv_type = advocacy_type,
                adv_est = Dict(:C => default_estimate, :D => default_estimate),
                weight_of_present = weight_of_present_for_adv,
                adv_mutation_rate = adv_mutation_rate
            ),
            payouts = deepcopy(base_payouts),
            tolerance = tolerance,
            total_payout = 0.0,
            num_moves = 0,
            num_adv_mutations = 0
        )
        add_agent!(player, model)
    end
    
    # Create cooperators.
    for pid in 1:num_cooperators
        create_and_add_player!(pid, init_pr_coop_cooperator, :C)
    end

    # Create defectors.
    for pid in 1:num_defectors
        create_and_add_player!(num_cooperators + pid, init_pr_coop_defector, :D)
    end
    
    # Create neutral players.
    for pid in 1:num_neutrals
        random_advocacy = rand() < 0.5 ? :C : :D
        create_and_add_player!(num_cooperators + num_defectors + pid, 0.5, random_advocacy)
    end

    agent_ids = collect(allids(model))

    inter_dict, infl_dict =
    PeerSelection.build_neighbourhoods(agent_ids;
        interaction = interaction_strategy,
        influence   = influence_strategy)

    # 1. incoming “who influences me”
    for a in allagents(model)
        add_influencers!(a, infl_dict[a.id])
    end

    
    # 2. outgoing "whom I influence"  (inverse map)
    for (id, incoming) in infl_dict, src in incoming
        add_influencees!(model[src], id)
    end

    # 3. interaction peers
    for a in allagents(model)
        add_interaction_peers!(a, inter_dict[a.id])
    end

    return model, parameters
end
