struct SparseDictArray{T,N} # <: AbstractArray{T,N}

    data::Dict{NTuple{N,Any},T}

    function SparseDictArray{T,N}() where {T,N} 
        dict = Dict{NTuple{N,Any},T}()
        return new{T,N}(dict)
    end
end

function Base.getindex(sd::SparseDictArray{T,N}, idx::NTuple{N,Any}) where {T,N} 
    return getindex(sd,idx...)
end

function Base.getindex(sd::SparseDictArray{T,N}, idx...) where {T,N} 
    length(idx) < N && throw(BoundsError(sd, idx))
    return get(sd.data, idx, 0)
end

function Base.setindex!(sd::SparseDictArray{T,N}, val, idx::NTuple{N,Any}) where {T,N}
    return setindex!(sd.data, val, idx...)
end

function Base.setindex!(sd::SparseDictArray{T,N}, val, idx...) where {T,N}
    length(idx) < N && throw(BoundsError(sd, idx))
    return setindex!(sd.data, val, idx)
end

struct SparseVarArray{N} #<: AbstractArray{VariableRef,N}
   
    model::Model

    name::String 
    
    data::Dict{NTuple{N,Any},VariableRef}

    function SparseVarArray{N}(model::Model,name::String) where {N} 
        dict = Dict{NTuple{N,Any},VariableRef}()
        return new{N}(model, name, dict)
    end
end

function Base.getindex(sd::SparseVarArray{N}, idx::NTuple{N,Any}) where {N} 
    return getindex(sd,idx...)
end

function Base.getindex(sd::SparseVarArray{N}, idx...) where {N} 
    length(idx) < N && throw(BoundsError(sd, idx))
    return get(sd.data, idx, 0)
end

function Base.setindex!(sd::SparseVarArray{N}, val, idx::NTuple{N,Any}) where {N}
    return setindex!(sd.data, val, idx...)
end

function Base.setindex!(sd::SparseVarArray{N}, val, idx...) where {N}
    length(idx) < N && throw(BoundsError(sd, idx))
    return setindex!(sd.data, val, idx)
end

function select(sd::SparseVarArray, pattern...)
    # Return all tuple indices that satfies pattern
    matches = []
    
    for t in keys(sd.data)
        match = true
        for (index,val) in enumerate(pattern)
            if val != :* && val != t[index]
                match = false
                break
            end
        end
        if match 
            push!(matches, t)
        end
    end

    return matches
end

function Base.summary(io::IO, sa::SparseVarArray)
    num_entries = length(sa.data)
    return print(
        io,
        typeof(sa),
        " with ",
        num_entries,
        isone(num_entries) ? " entry" : " entries",
    )
end
function Base.show(io::IO, ::MIME"text/plain", sa::SparseVarArray)
    summary(io, sa)
end