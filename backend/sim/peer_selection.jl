module PeerSelection
# ============================================================================
using Random
using StatsBase: sample, shuffle
using Graphs          # erdos_renyi, random_regular_graph
# ----------------------------------------------------------------------------
export build_neighbourhoods,
       # interaction
       Global, RandomK, ErdosRenyi, RandomRegular, Circle, GridMoore, GridVonNeumann, Star,
        SubsetOfInfluenceBySize, SubsetOfInfluenceUniform, EqualToInfluence,
       CustomInteraction,
       # influence
       GlobalInfluence, 
       RandomKInfluence, RandomKInfluenceIrreflexive, RandomKInfluenceReflexive,
       SubsetOfInteraction, SupersetOfInteraction,
       EqualToInteraction, EqualToInteractionWithSelf, 
       OligarchyInfluence, CustomInfluence
# ============================================================================
# 1. STRATEGY TYPES
# ----------------------------------------------------------------------------
abstract type InteractionStrategy end
abstract type InfluenceStrategy   end

struct Global                   <: InteractionStrategy end
struct RandomK          <: InteractionStrategy; k::Int          end
struct ErdosRenyi       <: InteractionStrategy; p::Float64      end
struct RandomRegular    <: InteractionStrategy; k::Int          end
struct Circle           <: InteractionStrategy end
struct GridMoore        <: InteractionStrategy
    dims::Tuple{Int,Int}; include_self::Bool
end
struct GridVonNeumann   <: InteractionStrategy
    dims::Tuple{Int,Int}; include_self::Bool
end
struct Star             <: InteractionStrategy
    center::Union{Nothing,Int}
end

struct SubsetOfInfluenceBySize <: InteractionStrategy end
struct SubsetOfInfluenceUniform <: InteractionStrategy end
struct EqualToInfluence <: InteractionStrategy end

"Hook for ad-hoc interaction generators."
struct CustomInteraction{F,P} <: InteractionStrategy
    fn::F; params::P
end
CustomInteraction(fn; kwargs...)=CustomInteraction(fn, kwargs)

# influence strategies -------------------------------------------------------
struct GlobalInfluence             <: InfluenceStrategy end
struct RandomKInfluence            <: InfluenceStrategy; k::Int end
struct RandomKInfluenceIrreflexive <: InfluenceStrategy; k::Int end
struct RandomKInfluenceReflexive   <: InfluenceStrategy; k::Int end


struct EqualToInteraction       <: InfluenceStrategy end
struct EqualToInteractionWithSelf       <: InfluenceStrategy end

struct SubsetOfInteraction      <: InfluenceStrategy
    min::Int; max::Int
    SubsetOfInteraction(;min=3,max=8)=new(min,max)
end
struct SupersetOfInteraction    <: InfluenceStrategy
    k::Int
    SupersetOfInteraction(k=8)=new(k)
end
struct OligarchyInfluence <: InfluenceStrategy
    size::Int
    oligarch_ids::Union{Nothing,Vector{Int}}
end
OligarchyInfluence(size::Int) = OligarchyInfluence(size, nothing)

OligarchyInfluence(; size::Int = 3, oligarch_ids = nothing) =
    OligarchyInfluence(size, oligarch_ids)

struct CustomInfluence{F,P}     <: InfluenceStrategy
    fn::F; params::P
end
CustomInfluence(fn;kwargs...)=CustomInfluence(fn,kwargs)

# ============================================================================
# 2. UTILITY
# ----------------------------------------------------------------------------
"""
    _krandom(ids, self, k; exclude_self)

Return `k` distinct IDs sampled from `ids`.
If `exclude_self` is true, remove `self` from pool first.
"""
function _krandom(ids::Vector{Int}, self::Int, k::Int; exclude_self::Bool)
    pool = exclude_self ? setdiff(ids, [self]) : ids
    k    = clamp(k, 1, length(pool))
    Set(sample(pool, k; replace=false))
end

# ============================================================================
# 3. GENERIC PEER HELPERS (unchanged)
# ----------------------------------------------------------------------------
function erdos_renyi_peers(agent_ids; p=0.5)
    n = length(agent_ids)
    g = erdos_renyi(n, p; is_directed=false)
    Dict(agent_ids[i] => Set(agent_ids[j] for j in neighbors(g,i)) for i in 1:n)
end

function regular_peers(agent_ids; degree=4)
    n = length(agent_ids)
    n*degree % 2 == 0 || error("n*degree must be even.")
    g = random_regular_graph(n, degree)
    Dict(agent_ids[i] => Set(agent_ids[j] for j in neighbors(g,i)) for i in 1:n)
end

star_peers(agent_ids;center_id=nothing) = Dict(
    id => (id==(center_id==nothing ? rand(agent_ids) : center_id) ?
           setdiff(Set(agent_ids),[center_id]) : Set([center_id])) for id in agent_ids)

circle_peers(agent_ids)=Dict(id=>Set([agent_ids[mod1(i-1,end)],
                                      agent_ids[mod1(i+1,end)]])
                              for (i,id) in enumerate(agent_ids))

function grid_vonneumann_peers(agent_ids; dims=(3,4), include_self=false)
    rows,cols=dims; length(agent_ids)==rows*cols||
        error("agent_ids count ≠ grid dims product")
    pos=reshape(agent_ids,rows,cols); dict=Dict{Int,Set{Int}}()
    for r in 1:rows, c in 1:cols
        nbrs=Set{Int}()
        for (dr,dc) in [(0,1),(0,-1),(1,0),(-1,0)]
            push!(nbrs,pos[mod1(r+dr,rows),mod1(c+dc,cols)])
        end
        include_self && push!(nbrs,pos[r,c])
        dict[pos[r,c]]=nbrs
    end
    dict
end

function grid_peers(agent_ids; dims=(3,4), include_self=false)
    rows,cols=dims; length(agent_ids)==rows*cols||
        error("agent_ids count ≠ grid dims product")
    pos=reshape(agent_ids,rows,cols); dict=Dict{Int,Set{Int}}()
    for r in 1:rows, c in 1:cols
        nbrs=Set{Int}()
        for dr in -1:1, dc in -1:1
            (!include_self && dr==0 && dc==0) && continue
            push!(nbrs,pos[mod1(r+dr,rows),mod1(c+dc,cols)])
        end
        dict[pos[r,c]]=nbrs
    end
    dict
end

function oligarchy_influence(agent_ids,_unused;
                             oligarchy_size=3, oligarch_ids=nothing)
    n=length(agent_ids)
    oligarchy_size<=n || error("oligarchy_size > population")
    oligarch_ids = isnothing(oligarch_ids) ?
                   Set(sample(agent_ids,oligarchy_size;replace=false)) :
                   Set(oligarch_ids)
    Dict(id => setdiff(Set(oligarch_ids),Set([id]))
         for id in agent_ids)
end

# ============================================================================
# 4. INTERACTION BUILDERS
# ----------------------------------------------------------------------------
_interaction(::Global, ids) =
    Dict(id => Set(setdiff(ids,[id])) for id in ids)

_interaction(s::RandomK, ids) =
    Dict(id => _krandom(ids,id,s.k; exclude_self=true) for id in ids)

_interaction(s::ErdosRenyi, ids)=erdos_renyi_peers(ids; p=s.p)
_interaction(s::RandomRegular,ids)=regular_peers(ids; degree=s.k)
_interaction(::Circle, ids)=circle_peers(ids)
_interaction(s::GridMoore,ids)=grid_peers(ids; dims=s.dims, include_self=s.include_self)
_interaction(s::GridVonNeumann,ids)=grid_vonneumann_peers(ids; dims=s.dims, include_self=s.include_self)
_interaction(s::Star, ids)=star_peers(ids; center_id=s.center)

"""
    random_subset_by_size(pool)

Randomly select a subset by first choosing a random size k ∈ {1,...,|pool|}, 
then sampling k elements without replacement. This gives larger subsets 
higher probability than smaller ones.
"""
function random_subset_by_size(pool)
    k = rand(1:length(pool))
    return Set(sample(collect(pool), k; replace=false))
end

"""
    random_subset_uniform(pool)

Randomly select a non-empty subset where each possible subset has equal 
probability 1/(2^n - 1) of being selected.
"""
function random_subset_uniform(pool)
    pool_array = collect(pool)
    n = length(pool_array)
    
    # Generate a random integer from 1 to 2^n - 1
    subset_id = rand(1:(2^n - 1))
    
    # Convert to subset using binary representation
    subset = []
    for i in 1:n
        if (subset_id >> (i-1)) & 1 == 1
            push!(subset, pool_array[i])
        end
    end
    
    return Set(subset)
end

_interaction(::SubsetOfInfluenceBySize, ids, infl_dict) =
    Dict(id => begin
            pool=setdiff(infl_dict[id],[id])
            random_subset_by_size(pool)
        end for id in ids)

_interaction(::SubsetOfInfluenceUniform, ids, infl_dict) =
    Dict(id => begin
            pool=setdiff(infl_dict[id],[id])
            random_subset_by_size(pool)
        end for id in ids)

_interaction(::EqualToInfluence, ids, infl_dict) =
    Dict(id => setdiff(infl_dict[id], [id])  for id in ids)

_interaction(s::CustomInteraction, ids)=s.fn(ids; s.params...)

# ============================================================================
# 5. INFLUENCE BUILDERS
# ----------------------------------------------------------------------------
_influence(::GlobalInfluence, ids, _)=Dict(id=>Set(ids) for id in ids)

_influence(s::RandomKInfluence, ids, _)=
    Dict(id => _krandom(ids, id, s.k; exclude_self=false) for id in ids)

_influence(s::RandomKInfluenceIrreflexive, ids, _)=
    Dict(id => _krandom(ids, id, s.k; exclude_self=true) for id in ids)

_influence(s::RandomKInfluenceReflexive, ids, _)=
    Dict(id => s.k == 1 ? Set([id]) : _krandom(ids, id, s.k-1; exclude_self=true) ∪ Set([id]) for id in ids)

_influence(::EqualToInteraction, _, inter)=deepcopy(inter)


_influence(::EqualToInteractionWithSelf, ids, inter)=Dict(id => deepcopy(inter[id] ∪ Set([id])) for id in ids)


_influence(s::SubsetOfInteraction, ids, inter)=
    Dict(id => begin
            base=collect(inter[id])
            l=clamp(s.min,1,length(base)); u=clamp(s.max,l,length(base))
            k=rand(l:u); Set(sample(base,k;replace=false))
        end for id in ids)

_influence(s::SupersetOfInteraction, ids, inter)=
    Dict(id => begin
            base=collect(inter[id])
            if length(base)>=s.k
                Set(sample(base,s.k;replace=false))
            else
                need=s.k-length(base)
                extra=_krandom(ids,id,need;exclude_self=false)
                union(Set(base),extra)
            end
        end for id in ids)

_influence(s::OligarchyInfluence, ids, inter)=
    oligarchy_influence(ids,inter; oligarchy_size=s.size, oligarch_ids=s.oligarch_ids)

_influence(s::CustomInfluence, ids, inter)=s.fn(ids,inter; s.params...)

# ============================================================================
# 6. PUBLIC 
# ----------------------------------------------------------------------------
"""
    build_neighbourhoods(ids; interaction, influence)

Return `(interaction_dict, influence_dict)` according to the strategies.
"""
function build_neighbourhoods(ids_iter;
                              interaction::InteractionStrategy=Global(),
                              influence::InfluenceStrategy=GlobalInfluence())
    ids=collect(ids_iter)

    if interaction isa Union{SubsetOfInfluenceBySize, SubsetOfInfluenceUniform, EqualToInfluence}
        infl  = _influence(influence, ids, nothing)   # influence first
        inter = _interaction(interaction, ids, infl)
    else
        inter = _interaction(interaction, ids)        # interaction first
        infl  = _influence(influence, ids, inter)
    end
    return inter, infl
end

end # module
# ============================================================================
