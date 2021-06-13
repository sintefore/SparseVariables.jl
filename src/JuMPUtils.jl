module JuMPUtils

using Dictionaries
using JuMP

include("sparsedict.jl")
include("macros.jl")
include("dictionaries.jl")

export @sparsevariable
export insertvar!
export ⋆


end # module
