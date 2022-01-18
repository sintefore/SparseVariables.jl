
dataframe(var::SparseVarArray) = DataFrames.DataFrame(table(var))
dataframe(var::SparseVarArray, name) = DataFrames.DataFrame(table(var,name))

dataframe(var::Containers.DenseAxisArray{VariableRef,N,Ax,L}, name, colnames...) where {N,Ax,L} = 
    DataFrames.DataFrame(table(var, name, colnames...))

export dataframe