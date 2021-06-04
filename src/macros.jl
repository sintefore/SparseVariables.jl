# Create a sparse array to hold JuMP variables
# Supports two variations:
#    y = @sparsevariable(m, y[c,i] for (c,i) in idx)

# Consider having sparse variables with restrictions on the index set?
#   y = @sparsevariable(m, y[c,i] for c in cars, i in year)
#   y = @sparsevariable(m, y[c,i] for c in String, i in Int64)
# 
# TODO: - variable bounds
macro sparsevariable(m,ex)
   
    if isa(ex.args[1], Symbol)
        v = ex.args[1]  # variable    
        vname = string(v)
        idx = ex.args[2:end]
        dim = length(idx)
      
        return quote
            var = $(esc(m))[Symbol($vname)] = SparseVarArray{$dim}($(esc(m)), $vname)
        end    
    end

    v = ex.args[1].args[1]  # variable
    vname = string(v)
    idx = ex.args[1].args[2:end]
    dim = length(idx)
    
    # For iteration
    itr = ex.args[2]
    i = itr.args[1]
    I = itr.args[2]
    return quote
        var = $(esc(m))[Symbol($vname)] = SparseVarArray{$dim}($(esc(m)), $vname)
        for $i in $(esc(I))
            insert!(var,$i...)
        end
        var
    end
end
