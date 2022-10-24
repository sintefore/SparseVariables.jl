module SparseVariables

using Dictionaries
using JuMP
using LinearAlgebra

include("sparsearray.jl")
include("dictionaries.jl")
include("indexedarray.jl")
include("tables.jl")

export SparseArray
export IndexedVarArray
export insertvar!
export unsafe_insertvar!

end # module
