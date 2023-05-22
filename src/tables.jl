function _rows(x::Union{SparseArray,IndexedVarArray})
    return zip(eachindex(x.data), keys(x.data))
end

function JuMP.Containers.rowtable(
    f::Function,
    x::AbstractSparseArray;
    header::Vector{Symbol} = Symbol[],
)
    if isempty(header)
        header = Symbol[Symbol("x$i") for i in 1:ndims(x)]
        push!(header, :y)
    end
    got, want = length(header), ndims(x) + 1
    if got != want
        error(
            "Invalid number of column names provided: Got $got, expected $want.",
        )
    end
    names = tuple(header...)
    return [NamedTuple{names}((args..., f(x[i]))) for (i, args) in _rows(x)]
end

function JuMP.Containers.rowtable(
    f::Function,
    x::IndexedVarArray,
    col_header::Symbol,
)
    header = Symbol[k for k in keys(x.index_names)]
    push!(header, col_header)
    return JuMP.Containers.rowtable(f, x; header = header)
end

function JuMP.Containers.rowtable(f::Function, x::IndexedVarArray)
    header = Symbol[k for k in keys(x.index_names)]
    push!(header, Symbol(f))
    return JuMP.Containers.rowtable(f, x; header = header)
end
