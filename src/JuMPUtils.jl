module JuMPUtils

using JuMP

include("sparsedict.jl")
include("variables.jl")
include("macros.jl")

export SparseDictArray
export create_variable
export add_index


end # module
