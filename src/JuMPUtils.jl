module JuMPUtils

using Dictionaries
using JuMP
using Tables

include("sparsedict.jl")
include("macros.jl")
include("dictionaries.jl")
include("tables.jl")

export @sparsevariable
export insertvar!
export ⋆


end # module
