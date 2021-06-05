module JuMPUtils

using Dictionaries
using JuMP

include("sparsedict.jl")
include("variables.jl")
include("macros.jl")
include("dictionaries.jl")

export @sparsevariable
export insertvar!



end # module
