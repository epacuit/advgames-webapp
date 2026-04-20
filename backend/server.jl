#!/usr/bin/env julia
#
# Advocacy Games webapp backend.
# Run with:   julia --project=. -t auto server.jl
#

using Oxygen
using HTTP
using JSON3

include("server_validate.jl")
include("server_api.jl")
using .ServerValidate
using .ServerApi

const HOST = get(ENV, "SIM_HOST", "127.0.0.1")
const PORT = parse(Int, get(ENV, "SIM_PORT", "8080"))

# ---------------------------------------------------------------------------
# CORS — explicit origin allowlist.
#
# Default list covers:
#   - production frontend on Netlify
#   - the two common Vite / CRA dev ports
# Override by setting SIM_CORS_ORIGINS to a comma-separated list of origins.
# The response *reflects* the request's Origin header when it matches the
# allowlist (required for credentialed requests and safer than `*`).
# ---------------------------------------------------------------------------
const DEFAULT_CORS_ORIGINS = [
    "https://advgames.pacuit.org",
    "http://localhost:5173",
    "http://localhost:3000",
]

function _parse_cors_origins()
    raw = strip(get(ENV, "SIM_CORS_ORIGINS", ""))
    isempty(raw) && return Set(DEFAULT_CORS_ORIGINS)
    return Set(String.(strip.(split(raw, ","))))
end
const ALLOWED_ORIGINS = _parse_cors_origins()

function cors_middleware(handler)
    return function(req::HTTP.Request)
        origin  = HTTP.header(req, "Origin", "")
        allowed = !isempty(origin) && origin in ALLOWED_ORIGINS

        if req.method == "OPTIONS"
            headers = Pair{String,String}[
                "Access-Control-Allow-Methods" => "GET, POST, OPTIONS",
                "Access-Control-Allow-Headers" => "Content-Type",
                "Access-Control-Max-Age"       => "86400",
                "Vary"                         => "Origin",
            ]
            if allowed
                push!(headers, "Access-Control-Allow-Origin" => origin)
            end
            return HTTP.Response(204, headers)
        end

        resp = handler(req)
        if allowed
            HTTP.setheader(resp, "Access-Control-Allow-Origin" => origin)
            HTTP.setheader(resp, "Vary" => "Origin")
        end
        return resp
    end
end

# ---------------------------------------------------------------------------
# JSON helpers
# ---------------------------------------------------------------------------
json_response(status::Int, body) = HTTP.Response(status,
    ["Content-Type" => "application/json"],
    JSON3.write(body))

error_response(status::Int, msg::AbstractString) = json_response(status,
    Dict("error" => msg))

"""
Read request body as a Dict{Symbol,Any}. Returns nothing on parse failure.
"""
function read_body_dict(req::HTTP.Request)
    body = String(req.body)
    isempty(body) && return Dict{Symbol,Any}()
    try
        parsed = JSON3.read(body)
        # Convert JSON3.Object → Dict{Symbol,Any} with symbol keys
        return Dict{Symbol,Any}(k => _normalize_json(v) for (k, v) in pairs(parsed))
    catch e
        return nothing
    end
end

# Recursively convert JSON3 types to plain Julia containers so validation code
# can use haskey/getindex with symbol keys uniformly.
function _normalize_json(v)
    if v isa JSON3.Object
        return Dict{Symbol,Any}(k => _normalize_json(vv) for (k, vv) in pairs(v))
    elseif v isa JSON3.Array
        return [_normalize_json(x) for x in v]
    else
        return v
    end
end

# ---------------------------------------------------------------------------
# Routes
# ---------------------------------------------------------------------------
@get "/health" function(req::HTTP.Request)
    return json_response(200, Dict("status" => "ok"))
end

@get "/defaults" function(req::HTTP.Request)
    return json_response(200, Dict(
        "defaults" => ServerApi.defaults_dict(),
        "caps"     => Dict(
            "numrounds_max"      => ServerValidate.CAPS.numrounds_max,
            "numrounds_min"      => ServerValidate.CAPS.numrounds_min,
            "population_max"     => ServerValidate.CAPS.population_max,
            "pressure_limit_max" => ServerValidate.CAPS.pressure_limit_max,
        ),
    ))
end

@get "/base-games" function(req::HTTP.Request)
    return json_response(200, Dict("base_games" => ServerApi.base_games_dict()))
end

@get "/network-configs" function(req::HTTP.Request)
    return json_response(200, Dict("presets" => ServerApi.network_presets_dict()))
end

@post "/run" function(req::HTTP.Request)
    body = read_body_dict(req)
    body === nothing && return error_response(400, "body is not valid JSON")

    local validated
    try
        validated = ServerValidate.validate_params(body, ServerApi.EXPOSED_BASE_GAMES)
    catch e
        if e isa ServerValidate.ValidationError
            return error_response(400, e.msg)
        else
            rethrow()
        end
    end

    result = try
        ServerApi.run_one(validated.model_params;
            numrounds      = validated.numrounds,
            seed           = validated.seed,
            stride         = validated.stride,
            include_agents = validated.include_agents,
            network_preset = validated.network_preset,
            lattice_rows   = validated.lattice_rows,
            lattice_cols   = validated.lattice_cols)
    catch e
        if e isa ServerApi.RequestError
            return error_response(400, e.msg)
        end
        @error "simulation failure" exception=(e, catch_backtrace())
        return error_response(500, "simulation failed: $(sprint(showerror, e))")
    end

    # Echo back the (normalized) params used, minus the raw Dict payouts which
    # JSON3 can't serialize due to tuple keys.
    params_echo = Dict{String,Any}()
    for (k, v) in validated.model_params
        k === :payouts && continue
        params_echo[String(k)] = v
    end
    params_echo["payouts"] = Dict(
        "cc" => validated.model_params[:payouts][(:C,:C)],
        "cd" => validated.model_params[:payouts][(:C,:D)],
        "dc" => validated.model_params[:payouts][(:D,:C)],
        "dd" => validated.model_params[:payouts][(:D,:D)],
    )
    result["params_echo"] = params_echo

    return json_response(200, result)
end

# ---------------------------------------------------------------------------
# Warmup: trigger JIT compilation of initialize + run! before accepting traffic.
# ---------------------------------------------------------------------------
function warmup()
    @info "Warmup: running a small simulation to JIT-compile the hot path"
    t0 = time()
    warm_params = Dict{Symbol,Any}(
        :num_cooperators => 6,
        :num_defectors => 6,
        :num_neutrals => 0,
        :init_pr_coop_cooperator => 0.75,
        :init_pr_coop_defector => 0.25,
        :payouts => deepcopy(ServerApi.BASE_GAMES[:PD_STANDARD]),
        :learning_increment => 0.15,
        :weight_of_present_for_move => 0.2,
        :weight_of_present_for_adv => 0.0015,
        :move_mutation_rate => 0.15,
        :adv_mutation_rate => 0.1,
        :tolerance => 0.05,
        :pos_pressure_limit => 4.0,
        :neg_pressure_limit => 4.0,
        :move_reassess_frequency => 0.5,
        :adv_reassess_frequency => 0.006,
    )
    _ = ServerApi.run_one(warm_params; numrounds=2_000, seed=1, stride=10)
    @info "Warmup complete in $(round(time() - t0; digits=2))s"
end

# ---------------------------------------------------------------------------
# Main
# ---------------------------------------------------------------------------
function main()
    warmup()
    origins_list = join(sort(collect(ALLOWED_ORIGINS)), ", ")
    @info "Serving on http://$(HOST):$(PORT)"
    @info "Allowed CORS origins: $origins_list"
    # Bind to 127.0.0.1 only — Caddy fronts us on the public interface.
    serve(; host=HOST, port=PORT, middleware=[cors_middleware])
end

# Only run the server when this file is executed as a script, not when loaded
# interactively (e.g. via `julia --project=. -e 'include("server.jl")'` for testing).
if abspath(PROGRAM_FILE) == @__FILE__
    main()
end
