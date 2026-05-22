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

# Minimum number of entries before the index cache is used; below this a
# linear scan is cheaper. Tune with set_cache_cutoff! or calibrate with
# benchmark/cutoff_benchmark.jl.
const _CACHE_CUTOFF = Ref{Int}(100)

"""
    set_cache_cutoff!(n::Int)

Set the minimum number of entries in an `IndexedVarArray` at which
selection switches from a linear scan to the pre-built
index cache.  Smaller values favour caching; larger values favour the linear
scan for small arrays.  Default: `100`.
"""
set_cache_cutoff!(n::Int) = (_CACHE_CUTOFF[] = n; nothing)

function _select_cached(sa::IndexedVarArray{V,N,T}, pat)::Vector{T} where {V,N,T}
    length(_data(sa)) < _CACHE_CUTOFF[] && return collect(T, _select_gen(keys(_data(sa)), pat))
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

# Project a full key T down to the free dimensions FT.
@generated function _project_key(key::T, ::Type{MT}) where {T,MT}
    free_idx = [i for i in 1:fieldcount(T) if fieldtypes(MT)[i] === Colon]
    FT = Tuple{[fieldtypes(T)[i] for i in free_idx]...}
    return :($(Expr(:tuple, [:(key[$i]) for i in free_idx]...))::$FT)
end

# Reconstruct a full key T from the fixed values in mask and the free key FT.
@generated function _reconstruct_key(mask::MT, free_key::FT, ::Type{T}) where {MT,FT,T}
    parts = Vector{Expr}(undef, fieldcount(T))
    fi = 1
    for i in 1:fieldcount(T)
        if fieldtypes(MT)[i] === Colon
            parts[i] = :(free_key[$fi])
            fi += 1
        else
            parts[i] = :(mask[$i])
        end
    end
    return :($(Expr(:tuple, parts...))::$T)
end

"""
    IndexedVarArraySlice{V,N,T,NF,MT,FT}

A lazy, filtered view into an `IndexedVarArray` implementing the
`AbstractSparseArray{V,NF}` interface, where `NF` is the number of free
(Colon) dimensions. Keys are projected tuples covering only the free dimensions.
Iterates values only; use `pairs(v)` or `eachindex(v)` for projected keys alongside values.

Create via `slice(iva, mask...)`.
"""
struct IndexedVarArraySlice{V<:AbstractVariableRef,N,T,NF,MT<:Tuple,FT<:Tuple} <:
       AbstractSparseArray{V,NF}
    parent::IndexedVarArray{V,N,T}
    mask::MT
end

"""
    slice(iva::IndexedVarArray, mask...)

Return a lazy `IndexedVarArraySlice` over entries of `iva` matching `mask`.
Use `:` for free (wildcard) dimensions and exact values for fixed dimensions.

The result is an `AbstractSparseArray{V,NF}` where `NF` is the number of free
dimensions. Iterates values only; use `pairs(v)` for projected-key/value pairs,
or `eachindex(v)` for projected keys.

# Example
```julia
v = slice(flow, :, c, p, t)              # NF=1, one free dimension
sum(v)                                    # sum of matching VariableRefs
for (k, var) in pairs(v); ...; end        # k is a 1-tuple projected key
var = v[f, c]                             # splatted index lookup
```
"""
function slice(iva::IndexedVarArray{V,N,T}, mask...) where {V,N,T}
    return _make_slice(iva, tuple(mask...))
end

@generated function _make_slice(
    iva::IndexedVarArray{V,N,T},
    mask::MT,
) where {V,N,T,MT<:Tuple}
    fieldcount(MT) != N && return :(throw(BoundsError(iva, mask)))
    free = [fieldtypes(T)[i] for i in 1:N if fieldtypes(MT)[i] === Colon]
    NF = length(free)
    FT = Tuple{free...}
    return :(IndexedVarArraySlice{$V,$N,$T,$NF,$MT,$FT}(iva, mask))
end

function _view_matching_keys(v::IndexedVarArraySlice{V,N,T})::Vector{T} where {V,N,T}
    return _select_cached(v.parent, v.mask)
end

# Iterator traits: length is known but size() is not meaningful
Base.IteratorSize(::Type{<:IndexedVarArraySlice}) = Base.HasLength()
Base.IteratorEltype(::Type{<:IndexedVarArraySlice}) = Base.HasEltype()
Base.eltype(::Type{<:IndexedVarArraySlice{V}}) where {V} = V

# Iteration: values only (AbstractArray semantics)
function Base.iterate(v::IndexedVarArraySlice{V,N,T,NF,MT,FT}) where {V,N,T,NF,MT,FT}
    matching = _view_matching_keys(v)
    isempty(matching) && return nothing
    return (v.parent[matching[1]], (matching, 2))
end

function Base.iterate(
    v::IndexedVarArraySlice{V,N,T,NF,MT,FT},
    state::Tuple{Vector{T},Int},
) where {V,N,T,NF,MT,FT}
    matching, pos = state
    pos > length(matching) && return nothing
    return (v.parent[matching[pos]], (matching, pos + 1))
end

# getindex by FT tuple: v[(f, c)]
function Base.getindex(
    v::IndexedVarArraySlice{V,N,T,NF,MT,FT},
    free_key::FT,
) where {V,N,T,NF,MT,FT}
    return v.parent[_reconstruct_key(v.mask, free_key, T)]
end

# Disambiguate: AbstractSparseArray defines getindex(sa, ::NTuple{N,Any}) where N=NF,
# which overlaps with the FT method above when FT <: NTuple{NF,Any}.
# This more-specific overload resolves the ambiguity for broadcasting and other
# callers that hold the key as an unparameterised NTuple.
function Base.getindex(
    v::IndexedVarArraySlice{V,N,T,NF,MT,FT},
    idx::NTuple{NF,Any},
) where {V,N,T,NF,MT,FT}
    return v.parent[_reconstruct_key(v.mask, idx, T)]
end

# getindex by splatted args: v[f, c] or v[f] (NF==1)
# Generated at compile time — reconstructs the full key by interleaving
# the fixed mask values and the free positional arguments.
@generated function Base.getindex(
    v::IndexedVarArraySlice{V,N,T,NF,MT,FT},
    idx...,
) where {V,N,T,NF,MT,FT}
    if length(idx) != NF
        return :(throw(BoundsError(v, idx)))
    end
    parts = Expr[]
    fi = 1
    for i in 1:fieldcount(T)
        if fieldtypes(MT)[i] === Colon
            push!(parts, :(idx[$fi]))
            fi += 1
        else
            push!(parts, :(v.mask[$i]))
        end
    end
    return :(v.parent[$(Expr(:tuple, parts...))])
end

# Block mutation — views are read-only
Base.setindex!(::IndexedVarArraySlice, _, _...) =
    error("IndexedVarArraySlice is read-only")

# size is not meaningful for sparse tuple-keyed arrays
function Base.size(::IndexedVarArraySlice)
    return error(
        "`Base.size` is not implemented for `IndexedVarArraySlice` because it " *
        "is conceptually a sparse dictionary with NF-dimensional keys. " *
        "Use `length` for the number of entries.",
    )
end

function Base.haskey(
    v::IndexedVarArraySlice{V,N,T,NF,MT,FT},
    free_key::FT,
) where {V,N,T,NF,MT,FT}
    return haskey(_data(v.parent), _reconstruct_key(v.mask, free_key, T))
end

Base.length(v::IndexedVarArraySlice) = length(_view_matching_keys(v))

Base.keys(v::IndexedVarArraySlice{V,N,T,NF,MT,FT}) where {V,N,T,NF,MT,FT} =
    [_project_key(k, MT) for k in _view_matching_keys(v)]

Base.values(v::IndexedVarArraySlice) = [v.parent[k] for k in _view_matching_keys(v)]

# eachindex returns projected FT tuples (same as keys)
Base.eachindex(v::IndexedVarArraySlice) = keys(v)

Base.pairs(v::IndexedVarArraySlice{V,N,T,NF,MT,FT}) where {V,N,T,NF,MT,FT} =
    [_project_key(k, MT) => v.parent[k] for k in _view_matching_keys(v)]

function Base.firstindex(v::IndexedVarArraySlice, d)
    return minimum(k[d] for k in _view_matching_keys(v))
end
function Base.lastindex(v::IndexedVarArraySlice, d)
    return maximum(k[d] for k in _view_matching_keys(v))
end

# sum: build AffExpr directly — avoids _data() from AbstractSparseArray default
function Base.sum(v::IndexedVarArraySlice{V}) where {V}
    result = zero(AffExpr)
    for k in _view_matching_keys(v)
        JuMP.add_to_expression!(result, v.parent[k])
    end
    return result
end

# show: override AbstractSparseArray defaults which call _data()
Base.show(io::IO, ::MIME"text/plain", v::IndexedVarArraySlice) = summary(io, v)
Base.show(io::IO, v::IndexedVarArraySlice) = summary(io, v)

# ------------------------------------------------------------------------------
# Broadcasting
# Follows the pattern of JuMP.Containers.SparseAxisArray.
# The result of any broadcast over these types is always a plain SparseArray.
# ------------------------------------------------------------------------------

"""
    IVABroadcastStyle{N,K} <: Broadcast.BroadcastStyle

Shared broadcasting style for `IndexedVarArray` and `IndexedVarArraySlice`.
`N` is the effective key dimensionality and `K` is the concrete key tuple type.
All broadcast results are materialised as `SparseArray`.
"""
struct IVABroadcastStyle{N,K} <: Broadcast.BroadcastStyle end

Base.BroadcastStyle(::Type{<:IndexedVarArray{V,N,T}}) where {V,N,T} =
    IVABroadcastStyle{N,T}()

Base.BroadcastStyle(
    ::Type{<:IndexedVarArraySlice{V,N,T,NF,MT,FT}},
) where {V,N,T,NF,MT,FT} = IVABroadcastStyle{NF,FT}()

# Disallow mixing with other array types.
function Base.BroadcastStyle(::IVABroadcastStyle, ::Base.BroadcastStyle)
    return throw(
        ArgumentError(
            "Cannot broadcast IndexedVarArray or a view with another array of a different type",
        ),
    )
end

# Scalar (0-d) broadcasting is allowed.
function Base.BroadcastStyle(
    style::IVABroadcastStyle,
    ::Base.Broadcast.DefaultArrayStyle{0},
)
    return style
end

# Fix ambiguity with Unknown.
function Base.BroadcastStyle(::IVABroadcastStyle, ::Base.Broadcast.Unknown)
    return throw(
        ArgumentError(
            "Cannot broadcast IndexedVarArray or a view with an unknown broadcast style",
        ),
    )
end

# Bypass the default instantiate which calls axes().
function Base.Broadcast.instantiate(
    bc::Base.Broadcast.Broadcasted{<:IVABroadcastStyle},
)
    return bc
end

# ── Internal helpers ──────────────────────────────────────────────────────────

# Apply a broadcast tree to a single key.
_iva_getindex(x::IndexedVarArray, key) = x[key]
_iva_getindex(x::IndexedVarArraySlice, key) = x[key]
_iva_getindex(x::Any, ::Any) = x
_iva_getindex(x::Ref, ::Any) = x[]

function _iva_getindex(
    bc::Base.Broadcast.Broadcasted{<:IVABroadcastStyle},
    key,
)
    return bc.f(_iva_get_args(bc.args, key)...)
end

function _iva_get_args(args::Tuple, key)
    return (_iva_getindex(first(args), key), _iva_get_args(Base.tail(args), key)...)
end
_iva_get_args(::Tuple{}, ::Any) = ()

# Verify x has the same key set as ref_keys.
function _iva_check_same_keys(ref_keys, x::IndexedVarArray, args...)
    if length(ref_keys) != length(_data(x)) ||
       any(k -> !haskey(_data(x), k), ref_keys)
        throw(ArgumentError("Cannot broadcast IndexedVarArrays with different indices"))
    end
    return _iva_check_same_keys(ref_keys, args...)
end

function _iva_check_same_keys(
    ref_keys,
    x::IndexedVarArraySlice,
    args...,
)
    if length(ref_keys) != length(x) || any(k -> !haskey(x, k), ref_keys)
        throw(
            ArgumentError("Cannot broadcast IndexedVarArray views with different indices"),
        )
    end
    return _iva_check_same_keys(ref_keys, args...)
end

_iva_check_same_keys(ref_keys, ::Any, args...) = _iva_check_same_keys(ref_keys, args...)
_iva_check_same_keys(::Any) = nothing

# Recursively extract the key set from the first IVA-family object found.
function _iva_indices(bc::Base.Broadcast.Broadcasted{<:IVABroadcastStyle}, rest...)
    return _iva_indices(bc.args..., rest...)
end

function _iva_indices(x::IndexedVarArray, rest...)
    ks = collect(keys(_data(x)))
    _iva_check_same_keys(ks, rest...)
    return ks
end

function _iva_indices(x::IndexedVarArraySlice, rest...)
    ks = keys(x)   # Vector{FT}
    _iva_check_same_keys(ks, rest...)
    return ks
end

_iva_indices(::Any, rest...) = _iva_indices(rest...)   # skip scalars

# ── Materialise ───────────────────────────────────────────────────────────────

function Base.copy(
    bc::Base.Broadcast.Broadcasted{IVABroadcastStyle{N,K}},
) where {N,K}
    indices = _iva_indices(bc)
    isempty(indices) && return SparseArray(Dictionary{K,Any}())
    vals = [_iva_getindex(bc, k) for k in indices]
    return SparseArray(Dictionary(indices, vals))
end

# Prevent scalar broadcast from reducing to a 0-d result.
for _IVAType in (
    :IndexedVarArray,
    :IndexedVarArraySlice,
)
    @eval begin
        function Base.Broadcast.broadcast_preserving_zero_d(
            f,
            A::$_IVAType,
            As...,
        )
            return broadcast(f, A, As...)
        end
        function Base.Broadcast.broadcast_preserving_zero_d(
            f,
            x,
            A::$_IVAType,
            As...,
        )
            return broadcast(f, x, A, As...)
        end
    end
end
