
abstract type AbstractSparseArray{T,N} <: AbstractArray{T,N} end

function Base.getindex(sa::AbstractSparseArray{T,N}, idx::NTuple{N,Any}) where {T,N} 
    return getindex(sa,idx...)
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
    length(pattern) < N && throw(BoundsError(sa, idx))
    select(keys(_data(sa)), pattern)
end

struct SparseArray{T,N, K <: NTuple{N,Any} } <: AbstractSparseArray{T,N}

    data::Dictionary{K,T}
end

function SparseArray(d::Dict{K,T})  where {T,N,K <: NTuple{N,Any}}
    return SparseArray{T,N,K}(Dictionary(d))
end

_data(sa::SparseArray) = sa.data

struct SparseVarArray{N} <: AbstractSparseArray{VariableRef,N} 
   
    model::Model
    name::String 
    data::Dictionary{NTuple{N,Any},VariableRef}

    function SparseVarArray{N}(model::Model,name::String) where {N} 
        dict = Dictionary{NTuple{N,Any},VariableRef}()
        return new{N}(model, name, dict)
    end
end

_data(sa::SparseVarArray) = sa.data

function insertvar!(var::SparseVarArray{N}, index...) where {N} 
    var[index] = @variable(var.model, lower_bound=0)
    set_name(var[index], variable_name(var.name,index))
end