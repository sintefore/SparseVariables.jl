module JuMPUtils

using Dictionaries
using JuMP
using Tables
using Requires

include("sparsearray.jl")
include("macros.jl")
include("dictionaries.jl")
include("tables.jl")

export SparseArray
export SparseVarArray
export @sparsevariable
export insertvar!
export table

function __init__()
    @require DataFrames="a93c6f00-e57d-5684-b7b6-d8193f3e46c0" include("dataframes.jl")
end



end # module
