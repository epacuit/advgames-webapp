module ServerValidate

export validate_params, ValidationError, CAPS

struct ValidationError <: Exception
    msg::String
end

Base.showerror(io::IO, e::ValidationError) = print(io, "ValidationError: ", e.msg)

const CAPS = (
    numrounds_max      = 500_000,
    numrounds_min      = 100,
    population_max     = 200,
    pressure_limit_max = 20.0,
    pressure_limit_min = 0.0,
    payoff_abs_max     = 100.0,  # sanity cap on R/S/T/P
    stride_min         = 1,
    stride_max         = 10_000,
    target_points      = 2_000,  # default downsample target
)

is_finite_number(x) = x isa Real && isfinite(x)

in_unit(x) = is_finite_number(x) && 0.0 <= x <= 1.0

function require_field!(p::AbstractDict, key::Symbol, pred, description::String)
    haskey(p, key) || throw(ValidationError("missing param: $key"))
    v = p[key]
    pred(v) || throw(ValidationError("invalid $key = $v ($description)"))
    return v
end

function optional_field(p::AbstractDict, key::Symbol, pred, description::String, default)
    haskey(p, key) || return default
    v = p[key]
    v === nothing && return default
    pred(v) || throw(ValidationError("invalid $key = $v ($description)"))
    return v
end

is_pos_int(x) = x isa Integer && x > 0 || (x isa Real && isfinite(x) && x > 0 && isinteger(x))
is_nonneg_int(x) = x isa Integer && x >= 0 || (x isa Real && isfinite(x) && x >= 0 && isinteger(x))

"""
    validate_params(p)

Validate the raw request body dict. Returns a normalized NamedTuple with:
  :model_params -> Dict{Symbol,Any} suitable to splat into initialize(; ...)
  :numrounds    -> Int
  :seed         -> Union{Int,Nothing}
  :stride       -> Int (>=1)

Raises ValidationError with a clear message on any violation.
"""
function validate_params(p::AbstractDict, base_games::AbstractDict)
    numrounds = Int(require_field!(p, :numrounds,
        x -> is_pos_int(x) && CAPS.numrounds_min <= x <= CAPS.numrounds_max,
        "integer in [$(CAPS.numrounds_min), $(CAPS.numrounds_max)]"))

    seed = optional_field(p, :seed,
        x -> x isa Integer || (x isa Real && isinteger(x)),
        "integer or null", nothing)
    seed = seed === nothing ? nothing : Int(seed)

    # Population
    num_cooperators = Int(optional_field(p, :num_cooperators, is_nonneg_int, "non-negative integer", 6))
    num_defectors   = Int(optional_field(p, :num_defectors,   is_nonneg_int, "non-negative integer", 6))
    num_neutrals    = Int(optional_field(p, :num_neutrals,    is_nonneg_int, "non-negative integer", 0))
    total_pop = num_cooperators + num_defectors + num_neutrals
    if total_pop < 2
        throw(ValidationError("need at least 2 agents total (got $total_pop)"))
    end
    if total_pop > CAPS.population_max
        throw(ValidationError("population $total_pop exceeds cap $(CAPS.population_max)"))
    end

    init_pr_coop_cooperator = Float64(optional_field(p, :init_pr_coop_cooperator,
        in_unit, "probability in [0,1]", 0.75))
    init_pr_coop_defector = Float64(optional_field(p, :init_pr_coop_defector,
        in_unit, "probability in [0,1]", 0.25))

    # Learning
    learning_increment = Float64(optional_field(p, :learning_increment,
        in_unit, "probability in [0,1]", 0.15))
    weight_of_present_for_move = Float64(optional_field(p, :weight_of_present_for_move,
        in_unit, "probability in [0,1]", 0.2))
    weight_of_present_for_adv = Float64(optional_field(p, :weight_of_present_for_adv,
        in_unit, "probability in [0,1]", 0.0015))
    tolerance = Float64(optional_field(p, :tolerance,
        in_unit, "probability in [0,1]", 0.05))

    # Mutation
    move_mutation_rate = Float64(optional_field(p, :move_mutation_rate,
        in_unit, "probability in [0,1]", 0.15))
    adv_mutation_rate = Float64(optional_field(p, :adv_mutation_rate,
        in_unit, "probability in [0,1]", 0.1))

    # Pressure
    pressure_pred = x -> is_finite_number(x) && CAPS.pressure_limit_min <= x <= CAPS.pressure_limit_max
    pos_pressure_limit = Float64(optional_field(p, :pos_pressure_limit,
        pressure_pred, "number in [0,$(CAPS.pressure_limit_max)]", 4.0))
    neg_pressure_limit = Float64(optional_field(p, :neg_pressure_limit,
        pressure_pred, "number in [0,$(CAPS.pressure_limit_max)]", 4.0))

    # Reassess frequency
    move_reassess_frequency = Float64(optional_field(p, :move_reassess_frequency,
        in_unit, "probability in [0,1]", 0.5))
    adv_reassess_frequency = Float64(optional_field(p, :adv_reassess_frequency,
        in_unit, "probability in [0,1]", 0.006))

    # Game: accept base_game (string), rstp (array of 4), payouts (dict), else default PD_STANDARD
    payouts = resolve_payouts(p, base_games)

    stride = Int(optional_field(p, :stride,
        x -> is_pos_int(x) && CAPS.stride_min <= x <= CAPS.stride_max,
        "integer in [$(CAPS.stride_min),$(CAPS.stride_max)]",
        max(1, numrounds ÷ CAPS.target_points)))

    include_agents = Bool(optional_field(p, :include_agents,
        x -> x isa Bool, "boolean", false))

    network_preset_raw = optional_field(p, :network_preset,
        x -> x isa AbstractString || x isa Nothing,
        "string or null", nothing)
    network_preset = network_preset_raw === nothing ? nothing : String(network_preset_raw)

    lattice_rows_raw = optional_field(p, :lattice_rows,
        x -> is_pos_int(x) && 2 <= x <= 20,
        "integer in [2, 20]", nothing)
    lattice_cols_raw = optional_field(p, :lattice_cols,
        x -> is_pos_int(x) && 2 <= x <= 20,
        "integer in [2, 20]", nothing)
    lattice_rows = lattice_rows_raw === nothing ? nothing : Int(lattice_rows_raw)
    lattice_cols = lattice_cols_raw === nothing ? nothing : Int(lattice_cols_raw)

    model_params = Dict{Symbol,Any}(
        :num_cooperators => num_cooperators,
        :num_defectors => num_defectors,
        :num_neutrals => num_neutrals,
        :init_pr_coop_cooperator => init_pr_coop_cooperator,
        :init_pr_coop_defector => init_pr_coop_defector,
        :payouts => payouts,
        :learning_increment => learning_increment,
        :weight_of_present_for_move => weight_of_present_for_move,
        :weight_of_present_for_adv => weight_of_present_for_adv,
        :move_mutation_rate => move_mutation_rate,
        :adv_mutation_rate => adv_mutation_rate,
        :tolerance => tolerance,
        :pos_pressure_limit => pos_pressure_limit,
        :neg_pressure_limit => neg_pressure_limit,
        :move_reassess_frequency => move_reassess_frequency,
        :adv_reassess_frequency => adv_reassess_frequency,
    )

    return (
        model_params = model_params,
        numrounds = numrounds,
        seed = seed,
        stride = stride,
        include_agents = include_agents,
        network_preset = network_preset,
        lattice_rows = lattice_rows,
        lattice_cols = lattice_cols,
    )
end

function resolve_payouts(p::AbstractDict, base_games::AbstractDict)
    # Precedence: explicit payouts dict > rstp array > base_game name > default
    if haskey(p, :payouts) && p[:payouts] !== nothing
        return parse_payouts_dict(p[:payouts])
    elseif haskey(p, :rstp) && p[:rstp] !== nothing
        return parse_rstp(p[:rstp])
    elseif haskey(p, :base_game) && p[:base_game] !== nothing
        return lookup_base_game(p[:base_game], base_games)
    else
        # default: PD_STANDARD
        return lookup_base_game("PD_STANDARD", base_games)
    end
end

function parse_payouts_dict(d)
    d isa AbstractDict || throw(ValidationError("payouts must be an object with keys cc,cd,dc,dd"))
    try
        cc = Float64(d[:cc]); cd = Float64(d[:cd]); dc = Float64(d[:dc]); dd = Float64(d[:dd])
        for (k, v) in ((:cc, cc), (:cd, cd), (:dc, dc), (:dd, dd))
            isfinite(v) || throw(ValidationError("payouts.$k must be finite"))
            abs(v) <= CAPS.payoff_abs_max || throw(ValidationError("payouts.$k out of range [-$(CAPS.payoff_abs_max),$(CAPS.payoff_abs_max)]"))
        end
        return Dict((:C,:C) => cc, (:C,:D) => cd, (:D,:C) => dc, (:D,:D) => dd)
    catch e
        e isa ValidationError && rethrow()
        throw(ValidationError("payouts must be an object with keys cc,cd,dc,dd (Float64)"))
    end
end

function parse_rstp(a)
    if !(a isa AbstractVector) || length(a) != 4
        throw(ValidationError("rstp must be an array of 4 numbers [R,S,T,P]"))
    end
    R, S, T, P = Float64.(a)
    for (k, v) in ((:R,R), (:S,S), (:T,T), (:P,P))
        isfinite(v) || throw(ValidationError("rstp.$k must be finite"))
        abs(v) <= CAPS.payoff_abs_max || throw(ValidationError("rstp.$k out of range [-$(CAPS.payoff_abs_max),$(CAPS.payoff_abs_max)]"))
    end
    return Dict((:C,:C) => R, (:C,:D) => S, (:D,:C) => T, (:D,:D) => P)
end

function lookup_base_game(name, base_games::AbstractDict)
    key = name isa Symbol ? name : Symbol(String(name))
    haskey(base_games, key) || throw(ValidationError("unknown base_game '$name'; see GET /base-games"))
    return deepcopy(base_games[key])
end

end # module
