module SparseVariables

using Dictionaries
using JuMP
using LinearAlgebra
using PrecompileTools

include("sparsearray.jl")
include("dictionaries.jl")
include("indexedarray.jl")
include("translate.jl")
include("tables.jl")

export SparseArray
export IndexedVarArray
export TranslateVarArray
export insertvar!
export unsafe_insertvar!
export SafeInsert, UnsafeInsert

@setup_workload begin
    # Putting some things in `setup` can reduce the size of the
    # precompile file and potentially make loading faster.
    rs = 1:10
    is = [1, 2, 3]
    sts = ["a", "b"]
    sys = [:a, :b]
    m = Model()

    @compile_workload begin
        # all calls in this block will be precompiled, regardless of whether
        # they belong to your package or not (on Julia 1.8 and higher)

        @variable(
            m,
            x[r = rs, i = is, st = sts, sy = sys];
            container = IndexedVarArray
        )
        for r in rs, i in is, st in sts, sy in sys
            insertvar!(x, r, i, st, sy)
            unsafe_insertvar!(x, r, i, st, sy)
        end
        x[:, 1, :, :]
        x[10, :, :, :]
        x[1, :, :, :a]
        @variable(m, y[i = rs, j = rs, k = rs]; container = IndexedVarArray)
        for i in rs, j in rs, k in rs
            insertvar!(y, i, j, k)
        end
    end
end

end # module
