"""
    IndexedVarArray{V,N,T}

    Structure for holding an optimization variable with a sparse structure with extra indexing
"""
mutable struct IndexedVarArray{V<:AbstractVariableRef,N,T} <:
               AbstractSparseArray{V,N}
    const f::Function
    data::Dictionary{T,V}
    const index_names::NamedTuple
    const index_cache::Vector{Dictionary}
end

struct SafeInsert end
struct UnsafeInsert end

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
    insertvar!(var::IndexedVarArray{V,N,T}, index...)

Insert a new variable with the given index only after checking if keys are valid and not already defined.
"""
function insertvar!(var::IndexedVarArray{V,N,T}, index...) where {V,N,T}
    return insertvar!(var, SafeInsert(), index...)
end
function insertvar!(
    var::IndexedVarArray{V,N,T},
    ::SafeInsert = SafeInsert(),
    index...,
) where {V,N,T}
    !valid_index(var, index) && throw(BoundsError(var, index))# "Not a valid index for $(var.name): $index"g
    already_defined(var, index) && error("$index already defined for array")
    var[index] = var.f(index...)
    clear_cache!(var)
    return var[index]
end

function insertvar!(
    var::IndexedVarArray{V,N,T},
    ::UnsafeInsert,
    index...,
) where {V,N,T}
    return var[index] = var.f(index...)
end

"""
    unsafe_insertvar!(var::indexedVarArray{V,N,T}, index...)

Insert a new variable with the given index withouth checking if the index is valid or 
 already assigned.
"""
function unsafe_insertvar!(var::IndexedVarArray{V,N,T}, index...) where {V,N,T}
    return insertvar!(var, UnsafeInsert(), index...)
end

"""
    unsafe_initializevars!(var::IndexedVarArray{V,N,T}, indices)

Initialize a variable `var` with all `indices` at once without checking for valid indices or 
    if it already has data for maximum performance.
"""
function unsafe_initializevars!(
    var::IndexedVarArray{V,N,T},
    indices,
) where {V,N,T}
    var.data = Dictionary(indices, (var.f(i...) for i in indices))
    return var
end

function unsafe_initializevars_alt!(
    var::IndexedVarArray{V,N,T},
    indices,
) where {V,N,T}
    merge!(var.data, Dictionary(indices, (var.f(i...) for i in indices)))
    return var
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

function build_cache!(cache, pat, sa::IndexedVarArray{V,N,T}) where {V,N,T}
    if isempty(cache)
        for v in keys(sa)
            vred = _active(v, pat)
            nv = get!(cache, vred, T[])
            push!(nv, v)
        end
    end
    return cache
end

function _select_cached(sa::IndexedVarArray{V,N,T}, pat) where {V,N,T}
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
"""
    _get_cache_index(::P)

Return the position in the cache array computed from the pattern (Tuple), using the types only.
Non-colons count as 1, colons as 0, which are binary encoded to an integer.
"""
@generated function _get_cache_index(::P) where {P}
    tf = Tuple(ti != Colon for ti in fieldtypes(P))
    i = bin2int(tf)
    return :($i)
end

function _decode_nonslices(::IndexedVarArray{V,N,T}, v::Integer) where {V,N,T}
    fts = fieldtypes(T)
    return Tuple{
        (fts[i] for (i, c) in enumerate(last(bitstring(v), N)) if c == '1')...,
    }
end

"""
    _decode_nonslices(::IndexedVarArray{V,N,T}, ::P)

Reconstruct types of a pattern from the array types and the pattern type
"""
@generated function _decode_nonslices(
    ::IndexedVarArray{V,N,T},
    ::P,
) where {V,N,T,P}
    fts = fieldtypes(T)
    fts2 = fieldtypes(P)
    t = Tuple{(fts[i] for (i, v) in enumerate(fts2) if v != Colon)...}
    return :($t)
end

function _getcache(sa::IndexedVarArray{V,N,T}, pat::P) where {V,N,T,P}
    t = _get_cache_index(pat)
    if isassigned(sa.index_cache, t)
        return sa.index_cache[t]
    else
        sa.index_cache[t] = Dictionary{_decode_nonslices(sa, t),Vector{T}}()
    end
    return sa.index_cache[t]
end

# Extension for standard JuMP macros
function Containers.container(
    f::Function,
    indices,
    D::Type{IndexedVarArray},
    names,
)
    iva_names = NamedTuple{tuple(names...)}(indices.prod.iterators)
    T = Tuple{eltype.(indices.prod.iterators)...}
    N = length(names)
    V = first(Base.return_types(f))
    return IndexedVarArray{V,N,T}(
        f,
        Dictionary{T,V}(),
        iva_names,
        Vector{Dictionary}(undef, 2^N),
    )
end

function Base.firstindex(sa::IndexedVarArray, d)
    return first(sort(sa.index_names[d]))
end
function Base.lastindex(sa::IndexedVarArray, d)
    return last(sort(sa.index_names[d]))
end
