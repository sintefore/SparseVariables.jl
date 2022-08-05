using Base.Meta: isexpr

function _extract_kw(args)
    kw_args = filter(x -> Meta.isexpr(x, :(=)), collect(args))
    flat_args = filter(x -> !Meta.isexpr(x, :(=)), collect(args))
    return flat_args, kw_args
end

function _reorder_parameters(args)
    if !isexpr(args[1], :parameters)
        return args
    end
    args = collect(args)
    p = popfirst!(args)
    for arg in p.args
        @assert arg.head == :kw
        push!(args, Expr(:(=), arg.args[1], arg.args[2]))
    end
    return args
end

# Create a sparse array to hold JuMP variables
# Supports two variations:
#    y = @sparsevariable(m, y[c,i] for (c,i) in idx)

"""
    sparsevariable(args...)

Create a sparse array to hold JuMP variables. The array can be created 
empty or have variables for a provided index set. The array name will
be registered with the model.

## Example
 ```julia
@sparsevariable(m, x[cars,year])  
idx = [("volvo",1989), ("nissan",1988), ("nissan", 1991)]
@sparsevariable(m, x[cars,year] for (cars,year) in idx)
 ```    
"""
macro sparsevariable(args...)
    args = _reorder_parameters(args)
    m = args[1]

    ex, kw_args = _extract_kw(args[2:end])
    ex = ex[1]

    if isa(ex.args[1], Symbol)
        v = ex.args[1]  # variable    
        vname = string(v)
        idx = ex.args[2:end]
        dim = length(idx)
        return quote
            $(esc(v)) =
                $(esc(m))[Symbol($vname)] =
                    IndexedVarArray($(esc(m)), $vname, $idx)
        end
    end

    v = ex.args[1].args[1]  # variable
    vname = string(v)
    idx = ex.args[1].args[2:end]
    dim = length(idx)

    # For iteration
    itr = ex.args[2]
    I = itr.args[2]

    sva = :(IndexedVarArray($(esc(m)), $vname, $idx, $(esc(I))))
    for kw in kw_args
        push!(sva.args, esc(Expr(:kw, kw.args...)))
    end
    return quote
        $(esc(v)) = $(esc(m))[Symbol($vname)] = $sva
    end
end
