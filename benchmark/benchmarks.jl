import Pkg;
Pkg.activate(@__DIR__)

using IndexedTables
using JuMP
using SparseVariables

function generate_common(N)
    m = Model()
    ts = collect(zip(1:N, 1:N, 1:N))
    return m, ts
end

# Use condition on construction (inefficient)
function test_naive(N = 10)
    m, ts = generate_common(N)
    valid = Dict()
    for t in ts
        valid[t] = true
    end
    @variable(m, x[i = 1:N, j = 1:N, k = 1:N; haskey(valid, (i, j, k))] ≥ 0)
    return m
end

# Fix unused variables (inefficient, but allows slicing)
function test_dense(N = 10)
    m, ts = generate_common(N)
    @variable(m, x[i = 1:N, j = 1:N, k = 1:N] == 0)
    for t in ts
        unfix(x[t...])
    end
    return m
end

# Only generate used variables, more efficient, but clunky and
# does not support slicing
# NB! Requires SparseHelper to be loaded
# git@github.com:hellemo/SparseHelper.jl.git
function test_sparse(N = 10)
    m, ts = generate_common(N)
    I, J, K = Main.SparseHelper.sparsehelper(ts, 3)
    @variable(m, x[i = I, j = J[i], k = K[i, j]])
    return m
end

# Suggested workaround, does not support slicing
function test_dict(N = 10)
    m, ts = generate_common(N)
    x = m[:x] = Dict()
    for i in ts
        createvar(m, "x", i)
    end
    return m
end

# SparseVariables: simple, efficient, and supports slicing
function test_sparse_var(N = 10)
    m, ts = generate_common(N)
    #SparseVarArray(m, "x", [:a,:b,:c], ts) # TODO: replace with macro when done
    @sparsevariable(m, x[a, b, c] for (a, b, c) in ts)
    return m
end

function benchmark_variables()
    methods = (test_naive, test_dense, test_sparse_var)
    N = [10, 20, 50]
    for n in N, method in methods
        time = @elapsed method(n)
        println(time)
    end
end

function benchmark_constraints() end

function benchmark_solving() end

benchmark_variables()

# TODO:
# * test constraint construction time with slicing and manual workarounds
# * test solution time with extra fixed variables vs sparse formulation
# * tables/plots
# * showcase other nice things
