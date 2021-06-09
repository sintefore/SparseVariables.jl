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
    make_filter_fun(c, pos)

Return function to use for filtering depending on the type and value of `c` 
to apply at position `pos`
"""
make_filter_fun(c, pos) = x->x[pos] == c 
make_filter_fun(c::Base.Fix2, pos) = x->c(x[pos])
make_filter_fun(c::Function, pos) = x->c(x[pos])

"""
    ⭐(x)
Returns true. To be used as shorthand for wildcard function in patterns for select/filtering.

TODO: Better character to use for wildcard? (*,∀,? and ¿ are reserved)

# Example
```
data = [("bmw",1929,"black")]
select(data, (⭐,⭐,⭐)) == data # true
```
"""
⭐(x) = true

# Using function is faster, suggest to disable:
# function make_filter_fun(c)
#     if c == :*
#         return x->true
#     else
#         return x->x == c 
#     end
# end

make_filter_fun(c) = x->x==c
make_filter_fun(c::Base.Fix2) = x->c(x)
make_filter_fun(c::Function) = x->c(x)

"""
	recursive_filter(fs, data)
Filter `data` recursively with functions `fs`
"""
function recursive_filter(fs, data)
	(f, rest) = Iterators.peel(fs)
	if isempty(rest)
		return filter(f, data)
	else
		return recursive_filter(rest, filter(f, data))
	end
end


"""
    indices_fun(some_tuple)

Return functions to be used for filtering from a tuple following the format
supported by `make_filter_fun`
"""
function indices_fun(some_tuple)
	(make_filter_fun(v, pos) for (pos, v) in enumerate(some_tuple))
end

"""
    _select_rowwise(a, pattern) 

Filter iterable data a by tuple `pattern` by row (slow)
"""
function _select_rowwise(a, pattern)
    filter(x->reduce(&, f(x) for f in indices_fun(pattern)), a)
end


"""
    _select_colwise(a, pattern) 

Filter iterable data a by tuple `pattern` by column (recursively)
"""
function _select_colwise(a, pattern)
	recursive_filter(indices_fun(pattern), a)	
end

"""
    _select_gen(a, pattern)

Filter iterable data by tuple `pattern` by row, using generated function for speed.
See more straight-forward implementations `_select_rowwise` and `_select_colwise` for reference.   
"""
function _select_gen(a, pattern)
    filter(x->_select_generated(pattern,x), a)
end


"""
    _select_generated(pat,x,::Val{N}) where N

Compose function from pattern `pat` to filter entire tuple at once, see `_select_rowwise` for reference.
"""
_select_generated(pat, x) = _select_generated(pat, x, Val(length(pat)))

@generated function _select_generated(pat,x,::Val{N}) where N
    ex = :(true)
    for i = 1:N
        ex = :($ex && make_filter_fun(pat[$i])(x[$i]))
    end
    return :($ex)
end

"""
    select(dict, indices)
Return subset of `dict` matching selection defined by indices
"""
select(dict, indices) = _select_gen(dict, indices)
select(dict::Dictionary, indices) = getindices(dict, select(keys(dict), indices))
select(dict, f::Function) = filter(f, dict)