module SparseVariables

using Dictionaries
using JuMP
using LinearAlgebra
using Tables

include("sparsearray.jl")
include("macros.jl")
include("dictionaries.jl")
#include("tables.jl")
include("indexedarray.jl")

export SparseArray
export IndexedVarArray
export @sparsevariable
export insertvar!
export unsafe_insertvar!


end # module
