
dataframe(var::SparseVarArray) = DataFrames.DataFrame(table(var))
dataframe(var::SparseVarArray, name) = DataFrames.DataFrame(table(var, name))

function dataframe(
    var::Containers.DenseAxisArray{VariableRef,N,Ax,L},
    name,
    colnames...,
) where {N,Ax,L}
    return DataFrames.DataFrame(table(var, name, colnames...))
end

export dataframe
