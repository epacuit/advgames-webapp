using Statistics: mean, std

# Use the new grouping for advocacy settings.
adv_coop(player)   = player.advocacy_settings.adv_type == :C
adv_defect(player) = player.advocacy_settings.adv_type == :D

should_c(player)       = est_move_coop(player) > est_move_defect(player)
should_d(player)       = est_move_coop(player) < est_move_defect(player)
should_adv_c(player)   = est_adv_coop(player) > est_adv_defect(player)
should_adv_d(player)   = est_adv_coop(player) < est_adv_defect(player)

adv_est_diff(player) = est_adv_coop(player) - est_adv_defect(player)
act_est_diff(player) = est_move_coop(player) - est_move_defect(player)

# Cumulative average using built-in functions.
function cum_avg(a::Vector{Float64})
    return cumsum(a) ./ collect(1:length(a))
end

# Accessor functions (using the new grouped settings)
pr_coop(player)   = player.move_settings.inclinations[:C]
pr_defect(player) = player.move_settings.inclinations[:D]

est_move_coop(player) = player.move_settings.act_est[:C]
est_move_defect(player) = player.move_settings.act_est[:D]
est_adv_coop(player) = player.advocacy_settings.adv_est[:C]
est_adv_defect(player) = player.advocacy_settings.adv_est[:D]

# Model measures
avg_incl(model) = sum(pr_coop(p) for p in allagents(model)) / nagents(model)

avg_payoff(model) = mean(p.num_moves > 0 ? p.total_payout / p.num_moves : 0.0 for p in allagents(model))
std_payoff(model) = std(p.num_moves > 0 ? p.total_payout / p.num_moves : 0.0 for p in allagents(model))
min_payoff(model) = minimum(p.num_moves > 0 ? p.total_payout / p.num_moves : 0.0 for p in allagents(model))

pr_max_coop(model) = sum(pr_coop(p) == 1.0 for p in allagents(model)) / nagents(model)
pr_max_defect(model) = sum(pr_coop(p) == 0.0 for p in allagents(model)) / nagents(model)

cooperate_state(model) = pr_max_coop(model) > 0.80
defect_state(model)    = pr_max_defect(model) > 0.80

pr_adv_coop(model)   = sum(advocate(p) == :C for p in allagents(model)) / nagents(model)
pr_adv_defect(model) = sum(advocate(p) == :D for p in allagents(model)) / nagents(model)

# Advocacy-behavior alignment metrics (2x2 matrix)
pr_adv_c_play_c(model) = sum((advocate(p) == :C && pr_coop(p) >= 0.85) for p in allagents(model)) / nagents(model)
pr_hyp_adv_c_play_d(model) = sum((advocate(p) == :C && pr_coop(p) <= 0.15) for p in allagents(model)) / nagents(model)
pr_hyp_adv_d_play_c(model) = sum((advocate(p) == :D && pr_coop(p) >= 0.85) for p in allagents(model)) / nagents(model)
pr_adv_d_play_d(model) = sum((advocate(p) == :D && pr_coop(p) <= 0.15) for p in allagents(model)) / nagents(model)

# These functions return booleans indicating whether the average inclination is extreme.
avg_pr_max_coop(model) = mean(pr_coop(p) for p in allagents(model)) >= 0.85
avg_pr_max_defect(model) = mean(pr_coop(p) for p in allagents(model)) <= 0.15

pr_mistaken_adv(model) = sum(
    (advocate(p) == :C && est_move_coop(p) < est_move_defect(p)) ||
    (advocate(p) == :D && est_move_coop(p) > est_move_defect(p))
    for p in allagents(model)
) / nagents(model)

proportion_should_c(model)     = sum(should_c(p) for p in allagents(model)) / nagents(model)
proportion_should_d(model)     = sum(should_d(p) for p in allagents(model)) / nagents(model)
proportion_should_adv_c(model) = sum(should_adv_c(p) for p in allagents(model)) / nagents(model)
proportion_should_adv_d(model) = sum(should_adv_d(p) for p in allagents(model)) / nagents(model)

# Convert payout values to Float64 using abmproperties (which is a NamedTuple)
cc(model) = Float64(abmproperties(model).payouts[:C, :C])
cd(model) = Float64(abmproperties(model).payouts[:C, :D])
dc(model) = Float64(abmproperties(model).payouts[:D, :C])
dd(model) = Float64(abmproperties(model).payouts[:D, :D])

S(model) = cd(model)
T(model) = dc(model)
R(model) = cc(model)
P(model) = dd(model)

# Prisoner's Dilemma
is_pd(model) = T(model) > R(model) > P(model) > S(model)

# Weak Prisoner's Dilemma
is_wpd1(model) = T(model) > R(model) > P(model) && isapprox(P(model), S(model))
is_wpd2(model) = isapprox(T(model), R(model)) && R(model) > P(model) > S(model)
is_wpd(model) = is_wpd1(model) || is_wpd2(model)

# Prisoner's Delight
is_pde1(model) = isapprox(R(model), T(model)) && R(model) > S(model) > P(model)
is_pde2(model) = R(model) > T(model) > S(model) && isapprox(S(model), P(model))
is_pde3(model) = R(model) > T(model) > S(model) > P(model)
is_pde4(model) = R(model) > T(model) && isapprox(T(model), S(model)) && S(model) > P(model)
is_pde5(model) = R(model) > S(model) > T(model) > P(model)
is_pde6(model) = (R(model) > S(model)) && isapprox(S(model), T(model)) && isapprox(T(model), P(model))
is_pde7(model) = (R(model) > S(model)) && (S(model)> T(model)) && isapprox(T(model), P(model))

is_pde(model) = is_pde1(model) || is_pde2(model) || is_pde3(model) || is_pde4(model) || is_pde5(model) || is_pde6(model) || is_pde7(model)

# Stag Hunt
is_sh1(model) = R(model) > T(model) > P(model) > S(model)
is_sh2(model) = R(model) > T(model) && isapprox(T(model), P(model)) && P(model) > S(model)
is_sh(model) = is_sh1(model) || is_sh2(model)

# Weak Stag Hunt
is_wsh(model) = isapprox(R(model), T(model)) && (T(model) > P(model)) && isapprox(P(model), S(model))

# Chicken
is_ch(model) = T(model) > R(model) > S(model) > P(model)

# Prisoner's Dismay
is_pdm1(model) = T(model) > P(model) > R(model) > S(model)
is_pdm2(model) = T(model) > P(model) && isapprox(P(model), R(model)) && R(model) > S(model)
is_pdm3(model) = isapprox(T(model), P(model)) && P(model) > R(model) > S(model)
is_pdm4(model) = isapprox(T(model), P(model)) && isapprox(P(model), R(model)) && R(model) > S(model)

is_pdm(model) = is_pdm1(model) || is_pdm2(model) || is_pdm3(model) || is_pdm4(model)


function game_type(model)
    if is_pd(model)
        return "PD"
    elseif is_wpd(model)
        return "WPD"
    elseif is_ch(model)
        return "CH"
    elseif is_sh(model)
        return "SH"
    elseif is_wsh(model)
        return "WSH"
    elseif is_pde(model)
        return "PDe"
    elseif is_pdm(model)
        return "PDm"
    else 
        return "Other"
    end
end

gauthier1(model) = R(model) > 0.5 * (S(model) + T(model))
gauthier2(model) = P(model) < 0.5 * (S(model) + T(model))

chicken_intermediate(model) = (P(model) - S(model)) < (T(model) - R(model))

stag_hunt_intermediate(model) = (T(model) - R(model)) < (P(model) - S(model))

### Agent State Classification

# Predicates for agent state classification
is_committed_cooperator(player) = pr_coop(player) >= (1 - player.move_settings.learning_increment)
is_committed_defector(player) = pr_coop(player) <= player.move_settings.learning_increment
is_uncommitted(player) = !is_committed_cooperator(player) && !is_committed_defector(player)

# Model-level statistics (proportions)
prop_committed_cooperators(model) = count(is_committed_cooperator, allagents(model)) / nagents(model)
prop_committed_defectors(model) = count(is_committed_defector, allagents(model)) / nagents(model)
prop_uncommitted(model) = count(is_uncommitted, allagents(model)) / nagents(model)

####

### Additional Measures

variance_inclinations(model) = var(pr_coop(p) for p in allagents(model))

avg_num_adv_mutations(model) = mean(p.num_adv_mutations for p in allagents(model))
avg_num_moves(model) = mean(p.num_moves for p in allagents(model))


function get_gameplay_dataframe(model)
    props = abmproperties(model)
    if !haskey(props, :gameplay_history) || props.gameplay_history === nothing
        error("Gameplay tracking was not enabled. Initialize with track_gameplay=true")
    end
    
    return DataFrame(props.gameplay_history)
end