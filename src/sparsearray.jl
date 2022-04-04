
abstract type AbstractSparseArray{T,N} <: AbstractArray{T,N} end

function Base.getindex(
    sa::AbstractSparseArray{T,N},
    idx::NTuple{N,Any},
) where {T,N}
    return get(_data(sa), idx, zero(T))
end

function Base.getindex(
    sa::AbstractSparseArray{T,N},
    idx::NamedTuple,
) where {T,N}
    return select(sa, idx)
end

function Base.getindex(sa::AbstractSparseArray{T,N}, idx...) where {T,N}
    length(idx) != N && throw(BoundsError(sa, idx))
    return _getindex(sa, idx)
end

function Base.setindex!(
    sa::AbstractSparseArray{T,N},
    val,
    idx::NTuple{N,Any},
) where {T,N}
    return set!(_data(sa), idx, val)
end

function Base.setindex!(sa::AbstractSparseArray{T,N}, val, idx...) where {T,N}
    length(idx) != N && throw(BoundsError(sa, idx))
    return setindex!(sa, val, idx)
end

Base.length(sa::AbstractSparseArray) = length(_data(sa))
Base.size(sa::AbstractSparseArray) = length(_data(sa))
Base.keys(sa::AbstractSparseArray) = keys(_data(sa))

function Base.summary(io::IO, sa::AbstractSparseArray)
    num_entries = length(sa)
    return print(
        io,
        typeof(sa),
        " with ",
        num_entries,
        isone(num_entries) ? " entry" : " entries",
    )
end
function Base.show(io::IO, ::MIME"text/plain", sa::AbstractSparseArray)
    summary(io, sa)
    if !iszero(length(_data(sa)))
        println(io, ":")
        if length(_data(sa)) > 20
            show(io, first(_data(sa), 10))
            print(io, "\n ⋮\n")
            show(io, last(_data(sa), 10))
        else
            show(io, sa)
        end
    end
end
Base.show(io::IO, sa::AbstractSparseArray) = show(_data(sa))

# TODO: For performance, precalculate these and store in sa:
function Base.firstindex(sa::AbstractSparseArray, d)
    return minimum(x -> x[d], _data(sa).indices)
end
function Base.lastindex(sa::AbstractSparseArray, d)
    return maximum(x -> x[d], _data(sa).indices)
end

function select(
    sa::AbstractSparseArray{T,N},
    pattern::NTuple{N,Any},
) where {T,N}
    return select(keys(sa), pattern)
end

function select(
    sa::AbstractSparseArray{T,N},
    pattern...;
    cache = true,
) where {T,N}
    length(pattern) != N && throw(BoundsError(sa, pattern))
    return select_test(sa, pattern, cache)
end

"""
    SparseArray{T,N, K <: NTuple{N,Any} }
Implementation of an AbstractSparseArray where data is stored
in a dictionary. 
"""
struct SparseArray{T,N,K<:NTuple{N,Any}} <: AbstractSparseArray{T,N}
    data::Dictionary{K,T}
end

function SparseArray(d::Dict{K,T}) where {T,N,K<:NTuple{N,Any}}
    return SparseArray(Dictionary(d))
end

function SparseArray(d::Dict{S,T}) where {S,T}
    dd = Dict((key,) => val for (key, val) in d)
    return SparseArray(Dictionary(dd))
end

function SparseArray{T,N}() where {T,N}
    return SparseArray(Dictionary{NTuple{N,Any},T}())
end

function SparseArray{T,N,K}() where {T,N,K<:NTuple{N,Any}}
    return SparseArray(Dictionary{K,T}())
end

_data(sa::SparseArray) = sa.data
