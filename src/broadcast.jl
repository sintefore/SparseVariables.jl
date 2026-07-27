# ------------------------------------------------------------------------------
# Broadcasting over AbstractSparseArray
# Follows the pattern of JuMP.Containers.SparseAxisArray.
# The result of any broadcast is always a plain SparseArray.
# ------------------------------------------------------------------------------

"""
    SparseBroadcastStyle{K} <: Broadcast.BroadcastStyle

Broadcasting style for all `AbstractSparseArray` subtypes. `K` is the key tuple type.
All broadcast results are materialised as `SparseArray`.
"""
struct SparseBroadcastStyle{K} <: Broadcast.BroadcastStyle end

function Base.BroadcastStyle(::Type{SA}) where {SA<:AbstractSparseArray}
    return SparseBroadcastStyle{_keytype(SA)}()
end

# Disallow mixing with other array types.
function Base.BroadcastStyle(::SparseBroadcastStyle, ::Base.BroadcastStyle)
    return throw(
        ArgumentError(
            "Cannot broadcast a SparseArray with incompatible key types",
        ),
    )
end

# Scalar (0-d) broadcasting is allowed.
function Base.BroadcastStyle(
    style::SparseBroadcastStyle,
    ::Base.Broadcast.DefaultArrayStyle{0},
)
    return style
end

# Fix ambiguity with Unknown.
function Base.BroadcastStyle(::SparseBroadcastStyle, ::Base.Broadcast.Unknown)
    return throw(
        ArgumentError(
            "Cannot broadcast a SparseArray with an unknown broadcast style",
        ),
    )
end

# Bypass the default instantiate which calls axes().
function Base.Broadcast.instantiate(
    bc::Base.Broadcast.Broadcasted{<:SparseBroadcastStyle},
)
    return bc
end

# Internal helpers
_sparse_getindex(x::AbstractSparseArray, key) = x[key]
_sparse_getindex(x::Any, ::Any) = x
_sparse_getindex(x::Ref, ::Any) = x[]

function _sparse_getindex(
    bc::Base.Broadcast.Broadcasted{<:SparseBroadcastStyle},
    key,
)
    return bc.f(_sparse_get_args(bc.args, key)...)
end

function _sparse_get_args(args::Tuple, key)
    return (
        _sparse_getindex(first(args), key),
        _sparse_get_args(Base.tail(args), key)...,
    )
end
_sparse_get_args(::Tuple{}, ::Any) = ()

function _sparse_check_same_keys(ref_keys, x::AbstractSparseArray, args...)
    if length(ref_keys) != length(x) || any(k -> !haskey(x, k), ref_keys)
        throw(
            ArgumentError(
                "Cannot broadcast SparseArrays with different indices",
            ),
        )
    end
    return _sparse_check_same_keys(ref_keys, args...)
end

function _sparse_check_same_keys(ref_keys, ::Any, args...)
    return _sparse_check_same_keys(ref_keys, args...)
end
_sparse_check_same_keys(::Any) = nothing

function _sparse_indices(
    bc::Base.Broadcast.Broadcasted{<:SparseBroadcastStyle},
    rest...,
)
    return _sparse_indices(bc.args..., rest...)
end

function _sparse_indices(x::AbstractSparseArray, rest...)
    ks = collect(keys(x))
    _sparse_check_same_keys(ks, rest...)
    return ks
end

_sparse_indices(::Any, rest...) = _sparse_indices(rest...)

# Materialise

function Base.copy(
    bc::Base.Broadcast.Broadcasted{SparseBroadcastStyle{K}},
) where {K}
    indices = _sparse_indices(bc)
    T = Base.Broadcast.combine_eltypes(bc.f, bc.args)
    isempty(indices) && return SparseArray(Dictionary{K,T}())
    vals = [_sparse_getindex(bc, k) for k in indices]
    return SparseArray(Dictionary(indices, vals))
end

function Base.Broadcast.broadcast_preserving_zero_d(
    f,
    A::AbstractSparseArray,
    As...,
)
    return broadcast(f, A, As...)
end
function Base.Broadcast.broadcast_preserving_zero_d(
    f,
    x,
    A::AbstractSparseArray,
    As...,
)
    return broadcast(f, x, A, As...)
end
