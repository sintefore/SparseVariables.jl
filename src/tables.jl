abstract type SolutionTable end

Tables.istable(::Type{<:SolutionTable}) = true
Tables.rowaccess(::Type{<:SolutionTable}) = true

rows(t::SolutionTable) = t
names(t::SolutionTable) = getfield(t, :names)
lookup(t::SolutionTable) = getfield(t, :lookup)

Base.eltype(::SolutionTable) = SolutionRow
Base.length(t::SolutionTable) = length(t.var)

struct SolutionRow <: Tables.AbstractRow
    index_vals::Any
    sol_val::Float64
    source::SolutionTable
end

function Tables.getcolumn(s::SolutionRow, i::Int)
    if i > length(getfield(s, :index_vals))
        return getfield(s, :sol_val)
    end
    return getfield(s, :index_vals)[i]
end

function Tables.getcolumn(s::SolutionRow, nm::Symbol)
    i = lookup(getfield(s, :source))[nm]
    if i > length(getfield(s, :index_vals))
        return getfield(s, :sol_val)
    end
    return getfield(s, :index_vals)[i]
end

Tables.columnnames(s::SolutionRow) = names(getfield(s, :source))

struct SolutionTableSparse <: SolutionTable
    names::Vector{Symbol}
    lookup::Dict{Symbol,Int}
    var::SparseVarArray
end

SolutionTableSparse(v::SparseVarArray) = SolutionTableSparse(v, Symbol(v.name))

function SolutionTableSparse(v::SparseVarArray, name)
    if length(v) > 0 && !has_values(first(v.data).model)
        error("No solution values available for variable")
    end
    names = vcat(v.index_names, name)
    lookup = Dict(nm => i for (i, nm) in enumerate(names))
    return SolutionTableSparse(names, lookup, v)
end

function Base.iterate(t::SolutionTableSparse, state = nothing)
    next =
        isnothing(state) ? iterate(keys(t.var.data)) :
        iterate(keys(t.var.data), state)
    next === nothing && return nothing
    return SolutionRow(next[1], JuMP.value(t.var[next[1]]), t), next[2]
end

table(var::SparseVarArray) = SolutionTableSparse(var)
table(var::SparseVarArray, name) = SolutionTableSparse(var, name)

struct SolutionTableDense <: SolutionTable
    names::Vector{Symbol}
    lookup::Dict{Symbol,Int}
    index_lookup::Dict
    var::Containers.DenseAxisArray
end

function SolutionTableDense(
    v::Containers.DenseAxisArray{VariableRef,N,Ax,L},
    name,
    colnames...,
) where {N,Ax,L}
    if length(colnames) < length(axes(v))
        error("Not enough column names provided")
    end
    if length(v) > 0 && !has_values(first(v).model)
        error("No solution values available for variable")
    end
    names = vcat(colnames..., name)
    lookup = Dict(nm => i for (i, nm) in enumerate(names))
    index_lookup = Dict()
    for (i, ax) in enumerate(v.axes)
        index_lookup[i] = collect(ax)
    end
    return SolutionTableDense(names, lookup, index_lookup, v)
end

function Base.iterate(t::SolutionTableDense, state = nothing)
    next =
        isnothing(state) ? iterate(eachindex(t.var)) :
        iterate(eachindex(t.var), state)
    next === nothing && return nothing
    index = next[1]
    index_vals = [t.index_lookup[i][index[i]] for i in 1:length(index)]
    return SolutionRow(index_vals, JuMP.value(t.var[next[1]]), t), next[2]
end

function table(
    var::Containers.DenseAxisArray{VariableRef,N,Ax,L},
    name,
    colnames...,
) where {N,Ax,L}
    return SolutionTableDense(var, name, colnames...)
end
