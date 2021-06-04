module JuMPUtils

using JuMP

include("sparsedict.jl")
include("variables.jl")
include("macros.jl")

export @sparsevariable
export insertvar!



end # module
