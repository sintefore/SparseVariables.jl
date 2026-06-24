# Generated functions in this file cannot rely on helpers defined later in the
# include order, so selector classification stays local.
_is_exact_selector_type(::Type) = true
_is_exact_selector_type(::Type{<:Function}) = false
_is_exact_selector_type(::Type{<:AbstractRange}) = false
_is_exact_selector_type(::Type{<:Colon}) = false

# Project tpl to the exact-match positions of MT.
@generated function _project_fixed(tpl::T, ::Type{MT}) where {T,MT}
    inds = [
        i for i in 1:fieldcount(T) if _is_exact_selector_type(fieldtypes(MT)[i])
    ]
    return :($(Expr(:tuple, [:(tpl[$i]) for i in inds]...)))
end

# Project tpl to the non-exact (free) positions of MT.
@generated function _project_free(tpl::T, ::Type{MT}) where {T,MT}
    inds = [
        i for
        i in 1:fieldcount(T) if !_is_exact_selector_type(fieldtypes(MT)[i])
    ]
    FT = Tuple{[fieldtypes(T)[i] for i in inds]...}
    return :($(Expr(:tuple, [:(tpl[$i]) for i in inds]...))::$FT)
end

# Reconstruct a full key T from the exact values in mask and the free key FT.
@generated function _reconstruct_key(
    mask::MT,
    free_key::FT,
    ::Type{T},
) where {MT,FT,T}
    parts = Vector{Expr}(undef, fieldcount(T))
    fi = 1
    for i in 1:fieldcount(T)
        if !_is_exact_selector_type(fieldtypes(MT)[i])
            parts[i] = :(free_key[$fi])
            fi += 1
        else
            parts[i] = :(mask[$i])
        end
    end
    return :($(Expr(:tuple, parts...))::$T)
end

"""
    SparseArraySlice{P,V,NF,MT}

A lazy, mask-filtered view of any `AbstractSparseArray`. `P` is the concrete
parent type, `NF` is the number of non-exact dimensions, and `MT` is the
mask type. Implements
`AbstractSparseArray{V,NF}`.

Create via `slice(sa, mask...)`.
"""
struct SparseArraySlice{P<:AbstractSparseArray,V,NF,MT<:Tuple} <:
       AbstractSparseArray{V,NF}
    parent::P
    mask::MT
end

function _keytype(
    ::Type{<:SparseArraySlice{P,V,NF,MT}},
) where {P,V,NF,MT}
    return _free_keytype(MT, _keytype(P))
end

@generated function _free_keytype(::Type{MT}, ::Type{T}) where {MT,T}
    inds = [
        i for
        i in 1:fieldcount(T) if !_is_exact_selector_type(fieldtypes(MT)[i])
    ]
    FT = Tuple{[fieldtypes(T)[i] for i in inds]...}
    return :($FT)
end

function _matches_free_key(
    v::SparseArraySlice{P,V,NF,MT},
    free_key,
) where {P,V,NF,MT}
    return _select_generated(_project_free(v.mask, MT), free_key)
end

"""
    slice(sa::AbstractSparseArray, mask...)

Return a lazy `SparseArraySlice` over entries of `sa` matching `mask`. Use `:`
for wildcard dimensions, exact values for fixed dimensions, and predicates or
ranges for filtered dimensions. The result is an `AbstractSparseArray{V,NF}`
where `NF` is the number of non-exact dimensions.

# Example
```julia
v = slice(sa, :, "foo", :)               # NF=2, two free dimensions
sum(v)
for (k, val) in pairs(v); ...; end
```
"""
function slice(sa::AbstractSparseArray, mask...)
    return _make_slice(sa, tuple(mask...))
end

@generated function _make_slice(
    sa::P,
    mask::MT,
) where {P<:AbstractSparseArray,MT<:Tuple}
    N = ndims(P)
    V = eltype(P)
    fieldcount(MT) != N && return :(throw(BoundsError(sa, mask)))
    NF = count(i -> !_is_exact_selector_type(fieldtypes(MT)[i]), 1:N)
    return :(SparseArraySlice{$P,$V,$NF,$MT}(sa, mask))
end

# Default: linear scan. Subtypes may override for cached lookup.
function _view_matching_keys(
    v::SparseArraySlice{P,V,NF,MT},
) where {P,V,NF,MT}
    T = _keytype(P)
    return collect(T, _select_gen(keys(_data(v.parent)), v.mask))
end

# Iterator traits
Base.IteratorSize(::Type{<:SparseArraySlice}) = Base.HasLength()
Base.IteratorEltype(::Type{<:SparseArraySlice}) = Base.HasEltype()
Base.eltype(::Type{<:SparseArraySlice{P,V}}) where {P,V} = V

# Iteration: values only (AbstractArray semantics)
function Base.iterate(
    v::SparseArraySlice,
)
    matching = _view_matching_keys(v)
    isempty(matching) && return nothing
    return (v.parent[matching[1]], (matching, 2))
end

function Base.iterate(
    v::SparseArraySlice,
    state::Tuple{Vector,Int},
)
    matching, pos = state
    pos > length(matching) && return nothing
    return (v.parent[matching[pos]], (matching, pos + 1))
end

# getindex by FT tuple: v[(f, c)]
function Base.getindex(
    v::SparseArraySlice{P,V,NF,MT},
    free_key::Tuple,
) where {P,V,NF,MT}
    length(free_key) == NF || throw(BoundsError(v, free_key))
    T = _keytype(P)
    _matches_free_key(v, free_key) || return zero(V)
    return v.parent[_reconstruct_key(v.mask, free_key, T)]
end

# Splatted: v[f, c] or v[f] (NF==1)
function Base.getindex(
    v::SparseArraySlice{P,V,NF,MT},
    idx...,
) where {P,V,NF,MT}
    length(idx) == NF || throw(BoundsError(v, idx))
    return v[idx]
end

function Base.setindex!(::SparseArraySlice, _, _...)
    return error("SparseArraySlice is read-only")
end

function Base.size(::SparseArraySlice)
    return error(
        "`Base.size` is not implemented for `SparseArraySlice`. " *
        "Use `length` for the number of entries.",
    )
end

function Base.haskey(
    v::SparseArraySlice{P,V,NF,MT},
    free_key::Tuple,
) where {P,V,NF,MT}
    T = _keytype(P)
    _matches_free_key(v, free_key) || return false
    return haskey(_data(v.parent), _reconstruct_key(v.mask, free_key, T))
end

Base.length(v::SparseArraySlice) = length(_view_matching_keys(v))

function Base.keys(
    v::SparseArraySlice{P,V,NF,MT},
) where {P,V,NF,MT}
    return [_project_free(k, MT) for k in _view_matching_keys(v)]
end

Base.values(v::SparseArraySlice) = [v.parent[k] for k in _view_matching_keys(v)]

Base.eachindex(v::SparseArraySlice) = keys(v)

function Base.pairs(
    v::SparseArraySlice{P,V,NF,MT},
) where {P,V,NF,MT}
    return [_project_free(k, MT) => v.parent[k] for k in _view_matching_keys(v)]
end

function Base.firstindex(v::SparseArraySlice, d)
    return minimum(k[d] for k in _view_matching_keys(v))
end
function Base.lastindex(v::SparseArraySlice, d)
    return maximum(k[d] for k in _view_matching_keys(v))
end

function Base.sum(v::SparseArraySlice{P,V}) where {P,V}
    ks = _view_matching_keys(v)
    isempty(ks) && return zero(V)
    return sum(v.parent[k] for k in ks)
end

function Base.summary(io::IO, v::SparseArraySlice)
    num_entries = length(v)
    return print(
        io,
        "SparseArraySlice with ",
        num_entries,
        isone(num_entries) ? " entry" : " entries",
        " matching ",
        v.mask,
    )
end

function Base.show(io::IO, ::MIME"text/plain", v::SparseArraySlice)
    summary(io, v)
    if !iszero(length(v))
        println(io, ":")
        entries = pairs(v)
        if length(entries) > 20
            show(io, first(entries, 10))
            print(io, "\n ⋮\n")
            show(io, last(entries, 10))
        else
            show(io, entries)
        end
    end
end

Base.show(io::IO, v::SparseArraySlice) = summary(io, v)
