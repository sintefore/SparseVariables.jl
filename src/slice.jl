# Project tpl to the non-Colon (fixed) positions of MT.
@generated function _project_fixed(tpl::T, ::Type{MT}) where {T,MT}
    inds = [i for i in 1:fieldcount(T) if fieldtypes(MT)[i] !== Colon]
    return :($(Expr(:tuple, [:(tpl[$i]) for i in inds]...)))
end

# Project tpl to the Colon (free) positions of MT.
@generated function _project_free(tpl::T, ::Type{MT}) where {T,MT}
    inds = [i for i in 1:fieldcount(T) if fieldtypes(MT)[i] === Colon]
    FT = Tuple{[fieldtypes(T)[i] for i in inds]...}
    return :($(Expr(:tuple, [:(tpl[$i]) for i in inds]...))::$FT)
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
    SparseArraySlice{P,V,N,T,NF,MT,FT}

A lazy, mask-filtered view of any `AbstractSparseArray`. `P` is the concrete
parent type, `NF` is the number of free (Colon) dimensions, and `FT` is the
projected key tuple type covering only the free dimensions. Implements
`AbstractSparseArray{V,NF}`.

Create via `slice(sa, mask...)`.
"""
struct SparseArraySlice{
    P<:AbstractSparseArray,
    V,
    N,
    T,
    NF,
    MT<:Tuple,
    FT<:Tuple,
} <: AbstractSparseArray{V,NF}
    parent::P
    mask::MT
end

_keytype(::Type{<:SparseArraySlice{P,V,N,T,NF,MT,FT}}) where {P,V,N,T,NF,MT,FT} = FT

"""
    slice(sa::AbstractSparseArray, mask...)

Return a lazy `SparseArraySlice` over entries of `sa` matching `mask`. Use `:`
for free (wildcard) dimensions and exact values for fixed dimensions. The result
is an `AbstractSparseArray{V,NF}` where `NF` is the number of free dimensions.

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

@generated function _make_slice(sa::P, mask::MT) where {P<:AbstractSparseArray,MT<:Tuple}
    K = _keytype(P)
    N = ndims(P)
    V = eltype(P)
    fieldcount(MT) != N && return :(throw(BoundsError(sa, mask)))
    free = [fieldtypes(K)[i] for i in 1:N if fieldtypes(MT)[i] === Colon]
    NF = length(free)
    FT = Tuple{free...}
    return :(SparseArraySlice{$P,$V,$N,$K,$NF,$MT,$FT}(sa, mask))
end

# Default: linear scan. Subtypes may override for cached lookup.
function _view_matching_keys(
    v::SparseArraySlice{P,V,N,T,NF,MT,FT},
)::Vector{T} where {P,V,N,T,NF,MT,FT}
    return collect(T, _select_gen(keys(_data(v.parent)), v.mask))
end

# Iterator traits
Base.IteratorSize(::Type{<:SparseArraySlice}) = Base.HasLength()
Base.IteratorEltype(::Type{<:SparseArraySlice}) = Base.HasEltype()
Base.eltype(::Type{<:SparseArraySlice{P,V}}) where {P,V} = V

# Iteration: values only (AbstractArray semantics)
function Base.iterate(v::SparseArraySlice{P,V,N,T,NF,MT,FT}) where {P,V,N,T,NF,MT,FT}
    matching = _view_matching_keys(v)
    isempty(matching) && return nothing
    return (v.parent[matching[1]], (matching, 2))
end

function Base.iterate(
    v::SparseArraySlice{P,V,N,T,NF,MT,FT},
    state::Tuple{Vector{T},Int},
) where {P,V,N,T,NF,MT,FT}
    matching, pos = state
    pos > length(matching) && return nothing
    return (v.parent[matching[pos]], (matching, pos + 1))
end

# getindex by FT tuple: v[(f, c)]
function Base.getindex(
    v::SparseArraySlice{P,V,N,T,NF,MT,FT},
    free_key::FT,
) where {P,V,N,T,NF,MT,FT}
    return v.parent[_reconstruct_key(v.mask, free_key, T)]
end

# Disambiguate vs AbstractSparseArray's NTuple method.
function Base.getindex(
    v::SparseArraySlice{P,V,N,T,NF,MT,FT},
    idx::NTuple{NF,Any},
) where {P,V,N,T,NF,MT,FT}
    return v.parent[_reconstruct_key(v.mask, idx, T)]
end

# Splatted: v[f, c] or v[f] (NF==1)
@generated function Base.getindex(
    v::SparseArraySlice{P,V,N,T,NF,MT,FT},
    idx...,
) where {P,V,N,T,NF,MT,FT}
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

Base.setindex!(::SparseArraySlice, _, _...) = error("SparseArraySlice is read-only")

function Base.size(::SparseArraySlice)
    return error(
        "`Base.size` is not implemented for `SparseArraySlice`. " *
        "Use `length` for the number of entries.",
    )
end

function Base.haskey(
    v::SparseArraySlice{P,V,N,T,NF,MT,FT},
    free_key::FT,
) where {P,V,N,T,NF,MT,FT}
    return haskey(_data(v.parent), _reconstruct_key(v.mask, free_key, T))
end

Base.length(v::SparseArraySlice) = length(_view_matching_keys(v))

Base.keys(v::SparseArraySlice{P,V,N,T,NF,MT,FT}) where {P,V,N,T,NF,MT,FT} =
    [_project_free(k, MT) for k in _view_matching_keys(v)]

Base.values(v::SparseArraySlice) = [v.parent[k] for k in _view_matching_keys(v)]

Base.eachindex(v::SparseArraySlice) = keys(v)

Base.pairs(v::SparseArraySlice{P,V,N,T,NF,MT,FT}) where {P,V,N,T,NF,MT,FT} =
    [_project_free(k, MT) => v.parent[k] for k in _view_matching_keys(v)]

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

Base.show(io::IO, ::MIME"text/plain", v::SparseArraySlice) = summary(io, v)
Base.show(io::IO, v::SparseArraySlice) = summary(io, v)
