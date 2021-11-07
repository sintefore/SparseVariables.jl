using DataFrames

dataframe(var::SparseVarArray) = DataFrame(table(var))
dataframe(var::SparseVarArray, name) = DataFrame(table(var,name))

dataframe(var::Containers.DenseAxisArray{VariableRef,N,Ax,L}, name, colnames...) where {N,Ax,L} = DataFrame(table(var, name, colnames...))

export dataframe