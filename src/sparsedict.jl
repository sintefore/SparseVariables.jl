struct SparseDict{N,T}
    
    tupledict::Dict{NTuple{N,Any},T}

    function SparseDict{N,T}() where {N,T} 
        dict = Dict{NTuple{N,Any},T}()
        return new{N,T}(dict)
    end
end

function Base.getindex(tl::SparseDict, inds...) 
    if length(inds) == 1 && isa(inds[1], Tuple)
        return get(tl.tupledict, inds[1], 0) 
    end
    return get(tl.tupledict, inds, 0)
end

function Base.setindex!(tl::SparseDict, val, inds...) 
    
    if length(inds) == 1 && isa(inds[1], Tuple)
        tl.tupledict[inds[1]] = val
        return
    end
    tl.tupledict[inds] = val
    return
end

function select(td::SparseDict, pattern...)
    # Return all tuple indices that satfies pattern
    matches = []
    
    for t in keys(td.tupledict)
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