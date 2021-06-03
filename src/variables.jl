struct Dim{d} end

Dim(d) = Dim{d}()

function variable_name(varname::String, index)
    name = "$varname["
    for v in index 
        name = name * "$v"
        if v != last(index)
            name = name * ","
        end
    end
    name = name * "]"
end

create_variables(model::JuMP.Model, dim::Int, varname, indices) = create_variables(model, Dim(dim), varname, indices)

function create_variables(model::JuMP.Model, ::Dim{1}, varname, indices)

    var = SparseDict{1, VariableRef}()
    for i in indices
        var[i] = @variable(model, lower_bound = 0)
        set_name(var[i], variable_name(varname,i))
    end
    model[varname] = var

    return var
end

function create_variables(model::JuMP.Model, ::Dim{2}, varname, indices)

    var = SparseDict{2, VariableRef}()
    for i in indices
        var[i] = @variable(model, lower_bound = 0)
        set_name(var[i], variable_name(varname,i))
    end
    model[Symbol(varname)] = var

    return var
end

function create_variables(model::JuMP.Model, ::Dim{3}, varname, indices)

    var = SparseDict{3, VariableRef}()
    for i in indices
        var[i] = @variable(model, lower_bound = 0)
        set_name(var[i], variable_name(varname,i))
    end
    model[varname] = var

    return var
end
