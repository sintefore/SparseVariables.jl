function variable_name(var::SparseVarArray, index)
    return "$(var.name)[" *  join(index,",") * "]"
end

function insertvar!(var::SparseVarArray{N}, index...) where {N} 
    var[index] = @variable(var.model, lower_bound=0)
    set_name(var[index], variable_name(var,index))
end