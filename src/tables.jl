abstract type SolutionTable end


Tables.istable(::Type{<:SolutionTable}) = true
rowacccess(::Type{<:SolutionTable}) = true

rows(t::SolutionTable) = t
names(t::SolutionTable) = getfield(t, :names)
lookup(t::SolutionTable) = getfield(t, :lookup)

Base.eltype(::SolutionTable) = SolutionRow
Base.length(t::SolutionTable) = length(t.var)

struct SolutionRow <: Tables.AbstractRow
    index_vals
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
    lookup::Dict{Symbol, Int}
    var::SparseVarArray
end

function SolutionTableSparse(v::SparseVarArray)
    if length(v) > 0 && !has_values(first(v.data).model)
        error("No solution values available for variable")
    end
    names = vcat(v.index_names, Symbol(v.name))
    lookup = Dict(nm=>i for (i, nm) in enumerate(names))
    return SolutionTableSparse(names, lookup, v)
end

function Base.iterate(t::SolutionTableSparse, state = nothing)
    next = isnothing(state) ? iterate(keys(t.var.data)) : iterate(keys(t.var.data), state)
    next === nothing && return nothing
    return SolutionRow(next[1], JuMP.value(t.var[next[1]]), t), next[2]
end

table(var::SparseVarArray) = SolutionTableSparse(var)

struct SolutionTableDense <: SolutionTable
    names::Vector{Symbol}
    lookup::Dict{Symbol, Int}
    var::Containers.DenseAxisArray
end

macro name(arg)
    string(arg)
end

function SolutionTableDense(v::Containers.DenseAxisArray{VariableRef,N,Ax,L}, colnames...) where {N,Ax,L}
    if length(colnames) < length(axes(v))
        error("Not enough column names provided")
    end
    if length(v) > 0 && !has_values(first(v).model)
        error("No solution values available for variable")
    end
    names = vcat(colnames..., Symbol(@name(v)))
    lookup = Dict(nm=>i for (i, nm) in enumerate(names))
    return SolutionTableDense(names, lookup, v)
end

function Base.iterate(t::SolutionTableDense, state = nothing)
    next = isnothing(state) ? iterate(eachindex(t.var)) : iterate(eachindex(t.var), state)
    next === nothing && return nothing
    return SolutionRow(next[1], JuMP.value(t.var[next[1]]), t), next[2]
end

table(var::Containers.DenseAxisArray{VariableRef,N,Ax,L}, names...) where {N,Ax,L} = SolutionTableDense(var,names...) 