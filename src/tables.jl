
struct SolutionTable
    names::Vector{Symbol}
    lookup::Dict{Symbol, Int}
    var::SparseVarArray
end

function SolutionTable(v::SparseVarArray)
    names = vcat(v.index_names, Symbol(v.name))
    lookup = Dict(nm=>i for (i, nm) in enumerate(names))
    return SolutionTable(names, lookup, v)
end

Tables.istable(::Type{<:SolutionTable}) = true
rowacccess(::Type{<:SolutionTable}) = true

rows(t::SolutionTable) = t
names(t::SolutionTable) = getfield(t, :names)
lookup(t::SolutionTable) = getfield(t, :lookup)

Base.eltype(::SolutionTable) = SolutionRow
Base.length(t::SolutionTable) = length(t.var)

function Base.iterate(t::SolutionTable)
    next = iterate(keys(t.var.data))
    next === nothing && return nothing
    return SolutionRow(next[1], JuMP.value(t.var[next[1]]), t), next[2]
end

function Base.iterate(t::SolutionTable, state)
    next = iterate(keys(t.var.data), state)
    next === nothing && return nothing
    return SolutionRow(next[1], JuMP.value(t.var[next[1]]), t), next[2]
end

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