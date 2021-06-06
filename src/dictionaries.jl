function variable_name(var::String, index)
    return var *"[" *  join(index,", ") * "]"
end

function create_variables_dictionary(model::JuMP.Model, dim::Int, varname, indices)

    # var = SparseDict{dim, VariableRef}()
    var = Dictionary{eltype(indices),VariableRef}()

    for i in indices
        v = @variable(model, lower_bound = 0)
        insert!(var, i, v)
        set_name(v, variable_name(varname,i))
    end
    model[Symbol(varname)] = var

    return var
end


function create_variables_dictionary2(model::JuMP.Model, dim::Int, varname, indices;lower_bound=0)

    var = Array{VariableRef}(undef, length(indices))

    for (idx,i) in enumerate(indices)
        v = @variable(model, lower_bound=0)
        var[idx] = v
        set_name(v, variable_name(varname,i))
    end
    
    return Dictionary(indices, var)
end



function create_variables_dictionary3(model::JuMP.Model, dim::Int, varname, indices)

    var = Dictionary(indices, (@variable(model; lower_bound=0) for _ in indices))
    for (k,v) in pairs(var)
        set_name(v, variable_name(varname, k))
    end
    
    return var
end

"""
    myfilt(c, pos)
TODO: Better name for this
Return function to use for filtering depending on the type and value of `c` 
to apply at position `pos`
"""
function myfilt(c, pos)
    if c == :* || c == "∀"
        return x->true
    else
        return x->x[pos] == c 
    end
end
myfilt(c::Base.Fix2, pos) = x->c(x[pos])
myfilt(c::Function, pos) = x->c(x[pos])


"""
	recfil(fs, data)
TODO: Better name for this
Filter `data` recursively with functions `fs`
"""
function recfil(fs, data)
	(f, rest) = Iterators.peel(fs)
	if isempty(rest)
		return filter(f, data)
	else
		return recfil(rest, filter(f, data))
	end
end


"""
    check_indices(some_tuple)
TODO: Better name for this
Return functions to be used for filtering from a tuple following the format
supported by `myfilt`
"""
function check_indices(some_tuple)
	(myfilt(v, pos) for (pos, v) in enumerate(some_tuple))
end

"""
    select(dict, indices)
Return subset of `dict` matching selection defined by indices
"""
function select(dict, indices)
    recfil(check_indices(indices), dict)	
end
select(dict::Dictionary, indices) = getindices(dict, select(keys(dict), indices))
select(dict, f::Function) = filter(f, dict)