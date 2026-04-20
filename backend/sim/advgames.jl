using Agents
using Parameters
using Statistics: mean
using Random, StatsBase


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
num_advocating(model, act) = length([a for a in allagents(model) if advocate(a) == act])

# Update the current game (i.e., adjust the payoff matrix) based on advocacy proportions.
function update_game!(model)
    total = nagents(model)
    proportion_adv_C = num_advocating(model, :C) / total
    proportion_adv_D = num_advocating(model, :D) / total

    # Access pressure limits and base payouts via abmproperties.
    props = abmproperties(model)
    pos_pressure_limit = props.pos_pressure_limit
    neg_pressure_limit = props.neg_pressure_limit
    base_payouts = props.base_payouts

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

    # model.payouts = new_payouts
    # Update the mutable payout Dict stored in the properties.
    for k in keys(new_payouts)
        props.payouts[k] = new_payouts[k]
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
    player1 = random_agent(model)
    player2 = rand([p for p in allagents(model) if p.id != player1.id])

    move1 = move(player1)
    move2 = move(player2)

    # Retrieve the current payoff matrix from properties.
    current_props = abmproperties(model)
    payoff1 = current_props.payouts[move1, move2]
    payoff2 = current_props.payouts[move2, move1]

    current_advocacy1 = advocate(player1)
    current_advocacy2 = advocate(player2)

    update_total_payout!(player1, payoff1)
    update_total_payout!(player2, payoff2)
    update_num_moves!(player1)
    update_num_moves!(player2)

    update_estimates!(player1, payoff1, move1, current_advocacy1)
    update_estimates!(player2, payoff2, move2, current_advocacy2)


    player1_advocacy_updated = maybe_update_advocacy!(player1, current_props.adv_reassess_frequency)

    player2_advocacy_updated = maybe_update_advocacy!(player2, current_props.adv_reassess_frequency)

    advocacy_updated = player1_advocacy_updated || player2_advocacy_updated

    player1_inclination_updated = maybe_update_inclinations!(player1, current_props.move_reassess_frequency)
    
    player2_inclination_updated = maybe_update_inclinations!(player2, current_props.move_reassess_frequency)

    inclination_updated = player1_inclination_updated || player2_inclination_updated

    if  advocacy_updated
        update_game!(model)
    end

    if haskey(current_props, :track_gameplay) && current_props.track_gameplay
        push!(current_props.gameplay_history, (
            time = abmtime(model),
            player1_id = player1.id,
            player2_id = player2.id,
            move1 = move1,
            move2 = move2,
            advocacy1 = current_advocacy1,
            advocacy2 = current_advocacy2,
            payoff1 = payoff1,
            payoff2 = payoff2,
            player1_advocacy_updated = player1_advocacy_updated,
            player2_advocacy_updated = player2_advocacy_updated,
            player1_inclination_updated = player1_inclination_updated,
            player2_inclination_updated = player2_inclination_updated
        ))
    end
end

## Initialize

generate_payouts(R, S, T, P) = Dict((:C, :C) => R, (:C, :D) => S, (:D, :C) => T, (:D, :D) => P)


# Modified initialize function - Fixed version
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
    move_reassess_frequency = 0.03,
    adv_reassess_frequency = 0.1,
    track_gameplay = false,   
)
    base_payouts = rstp === nothing ? payouts : generate_payouts(rstp[1], rstp[2], rstp[3], rstp[4])
    # Ensure population counts are integers (YAML may pass Float64)
    num_cooperators = Int(num_cooperators)
    num_defectors = Int(num_defectors)
    num_neutrals = Int(num_neutrals)
    total_agents = num_cooperators + num_defectors + num_neutrals
    
    # Keep as NamedTuple (for compatibility), but gameplay_history Vector is mutable
    properties = (
        payouts = deepcopy(base_payouts),
        base_payouts = base_payouts,
        adv_reassess_frequency = adv_reassess_frequency,
        move_reassess_frequency = move_reassess_frequency,
        pos_pressure_limit = pos_pressure_limit,
        neg_pressure_limit = neg_pressure_limit,
        prs_coop = zeros(total_agents),
        track_gameplay = track_gameplay,
        gameplay_history = track_gameplay ? Vector{NamedTuple}() : nothing
    )
    
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
        :learning_increment => learning_increment
    )
    
    model = StandardABM(Player, nothing; 
        properties = properties, 
        model_step! = model_step!
    )
    
    default_estimate = mean([
        base_payouts[(:C, :C)], 
        base_payouts[(:C, :D)], 
        base_payouts[(:D, :C)], 
        base_payouts[(:D, :D)]
    ])
    
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
            tolerance = tolerance,
            total_payout = 0.0,
            num_moves = 0,
            num_adv_mutations = 0
        )
        add_agent!(player, model)
    end
    
    for pid in 1:num_cooperators
        create_and_add_player!(pid, init_pr_coop_cooperator, :C)
    end

    for pid in 1:num_defectors
        create_and_add_player!(num_cooperators + pid, init_pr_coop_defector, :D)
    end
    
    for pid in 1:num_neutrals
        random_advocacy = rand() < 0.5 ? :C : :D
        create_and_add_player!(num_cooperators + num_defectors + pid, 0.5, random_advocacy)
    end
    
    return model, parameters
end