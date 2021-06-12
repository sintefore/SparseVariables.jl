
abstract type AbstractSparseArray{T,N} <: AbstractArray{T,N} end

function Base.getindex(sa::AbstractSparseArray{T,N}, idx::NTuple{N,Any}) where {T,N} 
    return getindex(sa,idx...)
end

function Base.getindex(sa::AbstractSparseArray{T,N}, idx::NamedTuple) where {T,N}
    return select(sa, idx)
end

function Base.getindex(sa::AbstractSparseArray{T,N}, idx...) where {T,N} 
    length(idx) < N && throw(BoundsError(sa, idx))
    return get(_data(sa), idx, zero(T))
end

function Base.setindex!(sa::AbstractSparseArray{T,N}, val, idx::NTuple{N,Any}) where {T,N}
    return set!(_data(sa), idx, val)
end

function Base.setindex!(sa::AbstractSparseArray{T,N}, val, idx...) where {T,N}
    length(idx) < N && throw(BoundsError(sa, idx))
    return set!(_data(sa), idx, val)
end

Base.length(sa::AbstractSparseArray) = length(_data(sa)) 

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
        show(io, sa)
    end
end
Base.show(io::IO, sa::AbstractSparseArray) = show(_data(sa))


function select(sa::AbstractSparseArray{T,N}, pattern::NTuple{N,Any}) where {T,N}
    select(keys(_data(sa)), pattern)
end

function select(sa::AbstractSparseArray{T,N}, pattern...) where {T,N} 
    length(pattern) < N && throw(BoundsError(sa, pattern))
    select(keys(_data(sa)), pattern)
end

struct SparseArray{T,N, K <: NTuple{N,Any} } <: AbstractSparseArray{T,N}
    data::Dictionary{K,T}
end

function SparseArray(d::Dict{K,T}) where {T,N,K <: NTuple{N,Any}}
    return SparseArray{T,N,K}(Dictionary(d))
end

function SparseArray{T,N}() where {T,N}
    return SparseArray{T,N,NTuple{N,Any}}(Dictionary{NTuple{N,Any},T}())
end

function SparseArray{T,N,K}() where {T,N,K <: NTuple{N,Any}}
    return SparseArray{T,N,K}(Dictionary{K,T}())
end

_data(sa::SparseArray) = sa.data

struct SparseVarArray{N} <: AbstractSparseArray{VariableRef,N} 
    model::Model
    name::String 
    data::Dictionary{NTuple{N,Any},VariableRef}
    index_names::Vector{Symbol}
end

function SparseVarArray{N}(model::Model,name::String) where {N} 
    dict = Dictionary{NTuple{N,Any},VariableRef}()
    index_names = _default_index_names(N)
    SparseVarArray{N}(model, name, dict, index_names)
end

_data(sa::SparseVarArray) = sa.data
_default_index_names(N) = collect(Symbol("i$i") for i=1:N)
get_index_names(sa::SparseVarArray) = NamedTuple{tuple(sa.index_names...)}(collect(1:length(sa.index_names)))
set_index_names!(sa::SparseVarArray{N}, new_index_names) where {N} = sa.index_names .= new_index_names

function insertvar!(var::SparseVarArray{N}, index...;lower_bound=0) where {N} 
    var[index] = @variable(var.model, lower_bound=lower_bound)
    set_name(var[index], variable_name(var.name,index))
end