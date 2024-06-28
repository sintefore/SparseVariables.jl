# Benchmarks

Benchmarks of time spent on model construction with different number of variables (see [benchmark notebook for details](https://github.com/sintefore/SparseVariables.jl/blob/main/benchmark/benchmark.jl)) with  [`IndexedVarArray`](@ref) (`model_indexed`) and `SparseAxisArray` (`model_sparse_aa`) illustrate the potential improvement in model generation time:

![](res.svg)

Time spent on model construction can vary a lot depending on the level of sparsity (here constructed by varying sparsity level through parameter `DP`):

![](sparsity.svg)