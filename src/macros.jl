
function _extract_kw(args)
    kw_args =
        filter(x -> Meta.isexpr(x, :(=)), collect(args))
    flat_args = filter(x -> !Meta.isexpr(x, :(=)), collect(args))
    return flat_args, kw_args
end

# Create a sparse array to hold JuMP variables
# Supports two variations:
#    y = @sparsevariable(m, y[c,i] for (c,i) in idx)

# Consider having sparse variables with restrictions on the index set?
#   y = @sparsevariable(m, y[cars,year])
# 
# TODO: - variable bounds
macro sparsevariable(args...)

    args = JuMP._reorder_parameters(args)
    m = args[1]

    ex, kw_args = _extract_kw(args[2:end])
    ex = ex[1]

    if isa(ex.args[1], Symbol)
        v = ex.args[1]  # variable    
        vname = string(v)
        idx = ex.args[2:end]
        dim = length(idx)  
        return quote
            $(esc(v)) = $(esc(m))[Symbol($vname)] = SparseVarArray($(esc(m)), $vname, $idx)
        end    
    end

    v = ex.args[1].args[1]  # variable
    vname = string(v)
    idx = ex.args[1].args[2:end]
    dim = length(idx)
    
    # For iteration
    itr = ex.args[2]
    I = itr.args[2]
    
    sva = :(SparseVarArray($(esc(m)), $vname, $idx, $(esc(I))))
    for kw in kw_args
        push!(sva.args, esc(Expr(:kw, kw.args...)))
    end
    return quote
        $(esc(v)) = $(esc(m))[Symbol($vname)] = $sva
    end
end
