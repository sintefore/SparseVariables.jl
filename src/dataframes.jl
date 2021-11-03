using DataFrames

dataframe(var::SparseVarArray) = DataFrame(table(var))
dataframe(var::Containers.DenseAxisArray{VariableRef,N,Ax,L}, colnames...) where {N,Ax,L} = DataFrame(table(var,colnames...))

export dataframe