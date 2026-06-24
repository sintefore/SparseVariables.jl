"""
    IndexedVarArray{V,N,T}

    Structure for holding an optimization variable with a sparse structure with extra indexing
"""
struct IndexedVarArray{V<:AbstractVariableRef,N,T} <: AbstractSparseArray{V,N}
    f::Function
    data::Dictionary{T,V}
    index_names::NamedTuple
    index_cache::Vector{Dictionary}
end

struct SafeInsert end
struct UnsafeInsert end

_data(sa::IndexedVarArray) = sa.data
_keytype(::Type{<:IndexedVarArray{V,N,T}}) where {V,N,T} = T

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
    clear_cache!(var)
    return var[index] = var.f(index...)
end

"""
    unsafe_insertvar!(var::indexedVarArray{V,N,T}, index...)

Insert a new variable with the given index without checking if the index is valid or
 already assigned.
"""
function unsafe_insertvar!(var::IndexedVarArray{V,N,T}, index...) where {V,N,T}
    return insertvar!(var, UnsafeInsert(), index...)
end

function build_cache!(cache, pat, sa::IndexedVarArray{V,N,T}) where {V,N,T}
    if isempty(cache)
        for v in keys(sa)
            vred = _project_fixed(v, typeof(pat))
            nv = get!(cache, vred, T[])
            push!(nv, v)
        end
    end
    return cache
end

# Minimum number of entries before the index cache is used; below this a
# linear scan is assumed cheaper. Tune with set_cache_cutoff! or calibrate with
# benchmark/cutoff_benchmark.jl.
_CACHE_CUTOFF::Int = 100

"""
    set_cache_cutoff!(n::Int)

Set the minimum number of entries in an `IndexedVarArray` at which
selection switches from a linear scan to the pre-built
index cache.  Smaller values favour caching; larger values favour the linear
scan for small arrays.  Default: `100`.
"""
set_cache_cutoff!(n::Int) = (global _CACHE_CUTOFF = n; nothing)

@generated function _is_cacheable_pattern(::Type{P}) where {P<:Tuple}
    return :($(all(t == Colon || isfixed(t) for t in fieldtypes(P))))
end

function _select_cached(
    sa::IndexedVarArray{V,N,T},
    pat,
)::Vector{T} where {V,N,T}
    length(_data(sa)) < _CACHE_CUTOFF &&
        return collect(T, _select_gen(keys(_data(sa)), pat))
    _is_cacheable_pattern(typeof(pat)) ||
        return collect(T, _select_gen(keys(_data(sa)), pat))
    cache = _getcache(sa, pat)::Dictionary{_decode_nonslices(sa, pat),Vector{T}}
    build_cache!(cache, pat, sa)
    vals = _project_fixed(pat, typeof(pat))
    return get!(cache, vals, T[])
end

struct Dim{N} end
bin2int(v) = bin2int(v, Dim{length(v)}())
@generated function bin2int(v, ::Dim{N}) where {N}
    w = reverse([2^(i - 1) for i in 1:N])
    return :(dot($w, v))
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

# Override _view_matching_keys for IndexedVarArray parent: use index cache.
function _view_matching_keys(
    v::SparseArraySlice{P,V,NF,MT},
) where {P<:IndexedVarArray,V,NF,MT}
    return _select_cached(v.parent, v.mask)
end

# JuMP-efficient sum: build AffExpr directly via add_to_expression! for the
# standard VariableRef type. Custom AbstractVariableRef subtypes fall back to
# the generic slice sum implementation.
function Base.sum(v::SparseArraySlice{<:IndexedVarArray,VariableRef})
    result = zero(AffExpr)
    for k in _view_matching_keys(v)
        JuMP.add_to_expression!(result, v.parent[k])
    end
    return result
end
