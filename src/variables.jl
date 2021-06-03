struct Dim{d} end

Dim(d) = Dim{d}()

function variable_name(var::SparseDictArray, index)
    name = "$(var.name)["
    for v in index 
        name = name * "$v"
        if v != last(index)
            name = name * ","
        end
    end
    name = name * "]"
end

create_variable(model::JuMP.Model, dim::Int, varname) = create_variable(model, dim, varname, ())

create_variable(model::JuMP.Model, dim::Int, varname, indices) = create_variable(model, Dim(dim), varname, indices)

function create_variable(model::JuMP.Model, ::Dim{1}, varname, indices)

    var = SparseDictArray{1, VariableRef}(varname)
    for i in indices
        var[i] = @variable(model, lower_bound = 0)
        set_name(var[i], variable_name(varname,i))
    end
    model[varname] = var

    return var
end

function create_variable(model::JuMP.Model, ::Dim{2}, varname, indices)

    var = SparseDictArray{2, VariableRef}(varname)
    for i in indices
        var[i] = @variable(model, lower_bound = 0)
        set_name(var[i], variable_name(var,i))
    end
    model[Symbol(varname)] = var

    return var
end

function create_variable(model::JuMP.Model, ::Dim{3}, varname, indices)

    var = SparseDictArray{3, VariableRef}(varname)
    for i in indices
        var[i] = @variable(model, lower_bound = 0)
        set_name(var[i], variable_name(var,i))
    end
    model[varname] = var

    return var
end

function add_index(model::JuMP.Model, var::SparseDictArray, index...) 
    var[index] = @variable(model, lower_bound=0)
    set_name(var[index], variable_name(var,index))
end