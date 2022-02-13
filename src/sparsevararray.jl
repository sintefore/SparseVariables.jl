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