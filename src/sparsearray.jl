
abstract type AbstractSparseArray{T,N} <: AbstractArray{T,N} end

function Base.getindex(sa::AbstractSparseArray{T,N}, idx::NTuple{N,Any}) where {T,N} 
    return get(_data(sa), idx, zero(T))
end

function Base.getindex(sa::AbstractSparseArray{T,N}, idx::NamedTuple) where {T,N}
    return select(sa, idx)
end

function Base.getindex(sa::AbstractSparseArray{T,N}, idx...) where {T,N} 
    length(idx) != N && throw(BoundsError(sa, idx))
    return _getindex(sa, idx)
end

function Base.setindex!(sa::AbstractSparseArray{T,N}, val, idx::NTuple{N,Any}) where {T,N}
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
Base.firstindex(sa::AbstractSparseArray, d) =  minimum(x->x[d], _data(sa).indices)
Base.lastindex(sa::AbstractSparseArray, d) =  maximum(x->x[d], _data(sa).indices)




function select(sa::AbstractSparseArray{T,N}, pattern::NTuple{N,Any}) where {T,N}
    select(keys(sa), pattern)
end

function select(sa::AbstractSparseArray{T,N}, pattern...; cache = true) where {T,N} 
    length(pattern) != N && throw(BoundsError(sa, pattern))
    select_test(sa, pattern, cache)
end

struct SparseArray{T,N, K <: NTuple{N,Any} } <: AbstractSparseArray{T,N}
    data::Dictionary{K,T}
end

function SparseArray(d::Dict{K,T}) where {T,N,K <: NTuple{N,Any}}
    return SparseArray(Dictionary(d))
end

function SparseArray(d::Dict{S,T}) where {S,T}
    dd = Dict( (key,) => val for (key,val) in d)
    return SparseArray(Dictionary(dd))
end

function SparseArray{T,N}() where {T,N}
    return SparseArray(Dictionary{NTuple{N,Any},T}())
end

function SparseArray{T,N,K}() where {T,N,K <: NTuple{N,Any}}
    return SparseArray(Dictionary{K,T}())
end

_data(sa::SparseArray) = sa.data

"""
    SparseVarArray{N,T}

    Structure for holding an optimization variable with a sparse structure. 
"""
struct SparseVarArray{N,T} <: AbstractSparseArray{VariableRef,N}
    model::Model
    name::String 
    data::Dictionary{T,VariableRef}
    index_names::Vector{Symbol}

    index_cache::Dict
end

function SparseVarArray{N,T}(model::Model,name::String) where {N,T} 
    dict = Dictionary{T,VariableRef}()
    index_names = _default_index_names(N)
    SparseVarArray{N}(model, name, dict, index_names)
end

function SparseVarArray{N,T}(model::Model, name::String, ind_names) where {N,T} 
    dict = Dictionary{NTuple{N,Any},VariableRef}()
    index_names = ind_names
    SparseVarArray{N,T}(model, name, dict, index_names, Dict())
end

function SparseVarArray{N,T}(model::Model, name::String, ind_names, indices::Vector{<:Tuple}; lower_bound = 0, kw_args... ) where {N,T}
    dict = Dictionary(indices, (createvar(model, name, k; lower_bound, kw_args...) for k in indices)) 
    model[Symbol(name)] = SparseVarArray{N,T}(model, name, dict, ind_names, Dict())
end

function SparseVarArray{N,T}(model::Model, name::String, ind_names, indices::Dictionaries.Indices{<:Tuple}; lower_bound = 0, kw_args... ) where {N,T}
    SparseVarArray{N,T}(model, name, ind_names, collect(indices); lower_bound, kw_args...)
end

function SparseVarArray(m,n,ind_names)
    N = length(ind_names)
    SparseVarArray{N,NTuple{N, Any}}(m,n,ind_names)
end

function SparseVarArray(m,n,ind_names,indi; lower_bound = 0, kw_args...)
    SparseVarArray{length(ind_names),eltype(indi)}(m,n,ind_names,indi; lower_bound, kw_args...)
end


_data(sa::SparseVarArray) = sa.data
_default_index_names(N) = collect(Symbol("i$i") for i=1:N)
get_index_names(sa::SparseVarArray) = NamedTuple{tuple(sa.index_names...)}(collect(1:length(sa.index_names)))
set_index_names!(sa::SparseVarArray{N}, new_index_names) where {N} = sa.index_names .= new_index_names

"""
    insertvar!(var::SparseVarArray{N}, index...; lower_bound = 0, kw_args...)

Insert a new variable with the given index. 
"""
function insertvar!(var::SparseVarArray{N}, index...; lower_bound = 0, kw_args...) where {N} 
    var[index] = createvar(var.model, var.name, index; lower_bound, kw_args...)
end

function createvar(model, name, index...; lower_bound = 0, kw_args...)
    if !isnothing(lower_bound)
        var = @variable(model, lower_bound = lower_bound)
    else
        var = @variable(model)
    end
    for kw in kw_args
        if kw.first == :binary && kw.second
            set_binary(var)
        end
        if kw.first == :integer && kw.second
            set_integer(var)
        end
        if kw.first == :upper_bound 
            set_upper_bound(var, kw.second)
        end
    end
    
    set_name(var, variable_name(name, index))
    return var
end