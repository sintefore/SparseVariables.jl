module SparseVariables

using Dictionaries
using JuMP
using LinearAlgebra

include("sparsearray.jl")
include("sparsevararray.jl")
include("macros.jl")
include("dictionaries.jl")
include("indexedarray.jl")
include("tables.jl")

export SparseArray
export SparseVarArray
export IndexedVarArray
export @sparsevariable
export insertvar!
export unsafe_insertvar!

end # module
