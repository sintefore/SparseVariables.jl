struct SparseDictArray{N,T}

    name::String
    
    data::Dict{NTuple{N,Any},T}

    function SparseDictArray{N,T}(name::String) where {N,T} 
        dict = Dict{NTuple{N,Any},T}()
        return new{N,T}(name, dict)
    end
end

function Base.getindex(sd::SparseDictArray{N,T}, idx::NTuple{N,Any}) where {N,T} 
    return getindex(sd,idx...)
end

function Base.getindex(sd::SparseDictArray{N,T}, idx...) where {N,T} 
    length(idx) < N && throw(BoundsError(sd, idx))
    return get(sd.data, idx, 0)
end

function Base.setindex!(sd::SparseDictArray{N,T}, val, idx::NTuple{N,Any}) where {N,T}
    return setindex!(sd.data, val, idx...)
end

function Base.setindex!(sd::SparseDictArray{N,T}, val, idx...) where {N,T}
    length(idx) < N && throw(BoundsError(sd, idx))
    return setindex!(sd.data, val, idx)
end

function select(sd::SparseDictArray, pattern...)
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