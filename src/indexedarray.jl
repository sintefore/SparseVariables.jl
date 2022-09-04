"""
    IndexedVarArray{N,T}

    Structure for holding an optimization variable with a sparse structure with extra indexing
"""
struct IndexedVarArray{N,T} <: AbstractSparseArray{VariableRef,N}
    model::Model
    name::Any
    data::Dictionary{T,VariableRef}
    index_names::NamedTuple
    index_cache::Vector{Dictionary}
end

function IndexedVarArray(
    model::Model,
    name::AbstractString,
    index_names::NamedTuple{Ns,Ts};
    lower_bound = 0,
    kw_args...,
) where {Ns,Ts}
    T = Tuple{eltype.(fieldtypes(Ts))...}
    N = length(fieldtypes(Ts))
    dict = Dictionary{T,VariableRef}()
    return model[Symbol(name)] = IndexedVarArray{N,T}(
        model,
        name,
        dict,
        index_names,
        Vector{Dictionary}(undef, 2^N),
    )
end

function IndexedVarArray(
    model::Model,
    name::AbstractString,
    index_names::NamedTuple{Ns,Ts},
    indices::Vector{T};
    lower_bound = 0,
    kw_args...,
) where {Ns,Ts,T}
    @assert T == Tuple{eltype.(fieldtypes(Ts))...}
    N = length(fieldtypes(Ts))
    # TODO: Check if each index is valid
    dict = Dictionary(
        indices,
        (createvar(model, name, k; lower_bound, kw_args...) for k in indices),
    )
    return model[Symbol(name)] = IndexedVarArray{N,T}(
        model,
        name,
        dict,
        index_names,
        Vector{Dictionary}(undef, 2^N),
    )
end

function IndexedVarArray(
    model::Model,
    name::AbstractString,
    index_names::NamedTuple{Ns,Ts},
    indices::Dictionaries.Indices{T};
    lower_bound = 0,
    kw_args...,
) where {Ns,Ts,T}
    @assert T == Tuple{eltype.(fieldtypes(Ts))...}
    N = length(fieldtypes(Ts))
    return IndexedVarArray(
        model,
        name,
        index_names,
        collect(indices);
        lower_bound,
        kw_args...,
    )
end

_data(sa::IndexedVarArray) = sa.data

already_defined(var, index) = haskey(_data(var), index)

function valid_index(var, index)
    for i in 1:length(var.index_names)
        if !(index[i] ∈ var.index_names[i])
            return false
        end
    end
    return true
end

function clear_cache!(var)
    for i in 1:length(var.index_cache)
        if isassigned(var.index_cache, i)
            empty!(var.index_cache[i])
        end
    end
end

"""
    insertvar!(var::IndexedVarArray{N,T}, index...; lower_bound = 0, kw_args...)

Insert a new variable with the given index only after checking if keys are valid and not already defined.
"""
function insertvar!(
    var::IndexedVarArray{N,T},
    index...;
    lower_bound = 0,
    kw_args...,
) where {N,T}
    !valid_index(var, index) && throw(BoundsError(var, index))# "Not a valid index for $(var.name): $index"g
    already_defined(var, index) && error("$(var.name): $index already defined")

    var[index] = createvar(var.model, var.name, index; lower_bound, kw_args...)

    clear_cache!(var)
    return var[index]
end

"""
    unsafe_insertvar!(var::indexedVarArray{N,T}, index...; lower_bound = 0, kw_args...)

Insert a new variable with the given index withouth checking if the index is valid or 
 already assigned.
"""
function unsafe_insertvar!(
    var::IndexedVarArray{N,T},
    index...;
    lower_bound = 0,
    kw_args...,
) where {N,T}
    return var[index] =
        createvar(var.model, var.name, index; lower_bound, kw_args...)

    #TODO: Reactivate this later
    # If active caches, update with new variable
    # cache = _getcache(var.sa, index)
    # for ind in keys(cache)
    #     vred = Tuple(val for (i, val) in enumerate(index) if i in ind)
    #     if !(vred in keys(var.index_cache[ind]))
    #         var.index_cache[ind][vred] = []
    #     end
    #     push!(var.index_cache[ind][vred], index)
    # end
end

function _active_old(idx, active)
    return Tuple((idx[i] for i ∈ 1:length(idx) if active[i]))
end

joinex(ex1, ex2) = :($ex1..., $ex2...)
@generated function _active(idx::I, pat::P) where {I,P}
    ids = fieldtypes(I)
    ps = fieldtypes(P)
    exs = []
    for i in 1:length(ids)
        if ps[i] != Colon
            if i > 2
                push!(exs, :(a1 = idx[$i],))
            else
                push!(exs, :(idx[$i],))
            end
        end
    end
    for i in 1:length(exs)-1
        exs[i+1] = joinex(exs[i], exs[i+1])
    end
    return :(tuple($(exs[end])...))
end

function build_cache!(cache, pat, sa::IndexedVarArray{N,T}) where {N,T}
    if isempty(cache)
        for v in keys(sa)
            vred = _active(v, pat)
            nv = get!(cache, vred, T[])
            push!(nv, v)
        end
    end
    return cache
end

function _select_cached(sa::IndexedVarArray{N,T}, pat) where {N,T}
    # TODO: Benchmark to find good cutoff-value for caching
    # TODO: Return same type for type stability
    length(_data(sa)) < 100 && return _select_gen(keys(_data(sa)), pat)
    cache = _getcache(sa, pat)::Dictionary{_decode_nonslices(sa, pat),Vector{T}}
    build_cache!(cache, pat, sa)
    vals = _dropslices_gen(pat)
    return get!(cache, vals, T[])
end

struct Dim{N} end
bin2int(v) = bin2int(v, Dim{length(v)}())
@generated function bin2int(v, ::Dim{N}) where {N}
    w = reverse([2^(i - 1) for i in 1:N])
    return :(dot($w, v))
end

function _dropslices(t::P) where {P}
    return Tuple(ti for ti in t if ti != Colon())
end

@generated function _dropslices_gen(pat::P) where {P}
    ps = fieldtypes(P)
    exs = []
    for i in 1:length(ps)
        if ps[i] != Colon
            if i > 2 # Workaround for slurping of iterables (like strings) when passing to joinex
                push!(exs, :(a2 = pat[$i],))
            else
                push!(exs, :(pat[$i],))
            end
        end
    end
    for i in 1:length(exs)-1
        exs[i+1] = joinex(exs[i], exs[i+1])
    end
    return exs[end]
end

@generated function _encode_nonslices(t::P) where {P}
    tf = Tuple(ti != Colon for ti in fieldtypes(P))
    i = bin2int(tf)
    return :($i)
end

function _decode_nonslices(::IndexedVarArray{N,T}, v::Integer) where {N,T}
    fts = fieldtypes(T)
    return Tuple{
        (fts[i] for (i, c) in enumerate(last(bitstring(v), N)) if c == '1')...,
    }
end

@generated function _decode_nonslices(::IndexedVarArray{N,T}, ::P) where {N,T,P}
    fts = fieldtypes(T)
    fts2 = fieldtypes(P)
    t = Tuple{(fts[i] for (i, v) in enumerate(fts2) if v != Colon)...}
    return :($t)
end

function _getcache(sa::IndexedVarArray{N,T}, pat::P) where {N,T,P}
    t = _encode_nonslices(pat)
    if isassigned(sa.index_cache, t)
        return sa.index_cache[t]
    else
        sa.index_cache[t] = Dictionary{_decode_nonslices(sa, t),Vector{T}}()
    end
    return sa.index_cache[t]
end
