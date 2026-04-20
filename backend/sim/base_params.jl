if !isdefined(Main, :PeerSelection)
    include("./peer_selection.jl")      
end
using .PeerSelection                    

const PD_STANDARD = Dict(
    (:C, :C) => 3.0, # R
    (:C, :D) => 0.0, # S
    (:D, :C) => 4.0, # T
    (:D, :D) => 1.0, # P
)

const PD_STANDARD_epsilon = Dict(
    (:C, :C) => 3.0, # R
    (:C, :D) => 0.001, # S
    (:D, :C) => 4.0, # T
    (:D, :D) => 1.0, # P
)

const PD_STANDARD_epsilon_double = Dict(
    (:C, :C) => 2 * PD_STANDARD_epsilon[:C, :C], # R
    (:C, :D) => 2 * PD_STANDARD_epsilon[:C, :D], # S
    (:D, :C) => 2 * PD_STANDARD_epsilon[:D, :C], # T
    (:D, :D) => 2 * PD_STANDARD_epsilon[:D, :D], # P
)

const PD_STANDARD_double = Dict(
    (:C, :C) => 2 * PD_STANDARD[:C, :C], # R
    (:C, :D) => 2 * PD_STANDARD[:C, :D], # S
    (:D, :C) => 2 * PD_STANDARD[:D, :C], # T
    (:D, :D) => 2 * PD_STANDARD[:D, :D], # P
)
const SH_STANDARD = Dict(
    (:C, :C) => 4.0, # R
    (:C, :D) => 0.0, # S
    (:D, :C) => 3.0, # T
    (:D, :D) => 1.0, # P
)

const PD1 = Dict(
    (:C, :C) => 3.9, # R
    (:C, :D) => 0.0, # S
    (:D, :C) => 4.0, # T
    (:D, :D) => 3.8, # P
)

const PD2 = Dict(
    (:C, :C) => 0.2, # R
    (:C, :D) => 0.0, # S
    (:D, :C) => 4.0, # T
    (:D, :D) => 0.1, # P
)

const SH1 = Dict(
    (:C, :C) => 4.0, # R
    (:C, :D) => 0.0, # S
    (:D, :C) => 3.9, # T
    (:D, :D) => 3.8, # P
)
const SH2 = Dict(
    (:C, :C) => 4.0, # R
    (:C, :D) => 0.0, # S
    (:D, :C) => 0.2, # T
    (:D, :D) => 0.1, # P
)


game_to_rtsp(game) = Dict(
    :R => game[:C, :C],
    :T => game[:D, :C],
    :S => game[:C, :D],
    :P => game[:D, :D],
)

const BASE_GAMES = Dict(
    :PD_STANDARD => PD_STANDARD,
    :SH_STANDARD => SH_STANDARD,
    :PD1 => PD1,
    :SH1 => SH1,
    :PD2 => PD2,
    :SH2 => SH2,
    :PD_STANDARD_epsilon => PD_STANDARD_epsilon,
    :PD_STANDARD_epsilon_double => PD_STANDARD_epsilon_double,
    :PD_STANDARD_double => PD_STANDARD_double,
)
# ========== 1.  Model parameters ==========

const MODEL_PARAMS = (
    num_cooperators            = 6,
    num_defectors              = 6,
    num_neutrals               = 0,

    init_pr_coop_cooperator    = 0.75,
    init_pr_coop_defector      = 0.25,

    rstp                       = nothing,

    payouts = PD_STANDARD,

    learning_increment = 0.15, 

    weight_of_present_for_move = 0.2,  
    weight_of_present_for_adv = 0.0015,

    move_mutation_rate = 0.15,  
    adv_mutation_rate = 0.1,  
    
    tolerance = 0.05,

    pos_pressure_limit = 4, 
    neg_pressure_limit = 4,  

    move_reassess_frequency = 0.5,  
    adv_reassess_frequency = 0.006,

)



# ========== 2.  Run-level (simulation / bookkeeping) settings ==========
const RUN_PARAMETERS = (
    numrounds        = 500_000,
    num_simulations  = 200,
    seed             = missing,

    save_model_data  = false,
    save_parameters  = false,
)

### Network parameters

const NETWORK_CONFIGURATIONS = (
    ( name = "Global:Global",
      interaction = Global(),
      influence   = GlobalInfluence() ),

    ( name = "Global:Rand-8",
      interaction = Global(),
      influence   = RandomKInfluence(8) ),

    ( name = "Rand-8:Global",
      interaction = RandomK(8),
      influence   = GlobalInfluence() ),

    ( name = "Rand-8:Rand-8",
      interaction = RandomK(8),
      influence   = RandomKInfluence(8) ),

    ( name = "Subset:Rand-8",
      interaction = SubsetOfInfluenceUniform(),
      influence   = RandomKInfluence(8) ),

    ( name = "Equal:Rand-8Reflexive",
      interaction = EqualToInfluence(),
      influence   = RandomKInfluenceReflexive(8) ),

    ( name = "Equal:Rand-8Irreflexive",
      interaction = EqualToInfluence(),
      influence   = RandomKInfluenceIrreflexive(8) ),
    
    ( name = "Lattice:Equal",
      interaction = GridMoore((7, 7), false),
      influence   = EqualToInteraction() ),
)

# ========== 1.  Model parameters ==========
const MODEL_PARAMS_NETWORK = (
    num_cooperators            = 24,
    num_defectors              = 25,
    num_neutrals               = 0,

    init_pr_coop_cooperator    = 0.75,
    init_pr_coop_defector      = 0.25,

    rstp                       = nothing,

    payouts = PD_STANDARD,

    learning_increment = 0.15, 

    weight_of_present_for_move = 0.2,  
    weight_of_present_for_adv = 0.0015,
    move_mutation_rate = 0.15,
    adv_mutation_rate = 0.1,

    tolerance = 0.05,

    pos_pressure_limit = 4,
    neg_pressure_limit = 4,

    move_reassess_frequency = 0.5,
    adv_reassess_frequency = 0.006,

    interaction_strategy = NETWORK_CONFIGURATIONS[1].interaction, 
    influence_strategy = NETWORK_CONFIGURATIONS[1].influence, 

)