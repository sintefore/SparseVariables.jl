module SparseVariables

using Dictionaries
using JuMP
using LinearAlgebra
using Tables

include("sparsearray.jl")
include("dictionaries.jl")
include("indexedarray.jl")

export SparseArray
export IndexedVarArray
export insertvar!
export unsafe_insertvar!

end # module
