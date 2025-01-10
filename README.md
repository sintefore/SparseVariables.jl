# SparseVariables.jl

[![Build Status](https://github.com/hellemo/SparseVariables.jl/workflows/CI/badge.svg?branch=main)](https://github.com/hellemo/SparseVariables.jl/actions?query=workflow%3ACI)
[![codecov](https://codecov.io/gh/hellemo/SparseVariables.jl/branch/main/graph/badge.svg?token=2LXGVU04YS)](https://codecov.io/gh/hellemo/SparseVariables.jl)
[![In Development](https://img.shields.io/badge/docs-dev-blue.svg)](https://sintefore.github.io/SparseVariables.jl/dev/)

Add container type(s) for improved performance and easier handling of sparse data 
and sparse arrays of optimizaton variables in [JuMP](https://jump.dev/JuMP.jl/stable/). 

Watch the JuliaCon/JuMP-dev 2022 lightning talk and check out the [notebook with examples and benchmarks](docs/notebook_juliacon2022.jl) (Note that the syntax
has been updated since the presentation): 

[![SparseVariables - Efficient sparse modelling with JuMP](https://img.youtube.com/vi/YuDvfZo9W5A/3.jpg)](https://youtu.be/YuDvfZo9W5A)

2022-09: Updated benchmarks of time spent on model construction with different number of variables (see [benchmark notebook for details](benchmark/benchmarks.jl)) with additional types `IndexedVarArray` (model_sparse) and `SparseAxisArray` (model_sparse_aa) on current julia master:

![](benchmark/res.svg)

Benchmarks with time spent on model construction with different level of sparsity:

![](benchmark/sparsity.svg)

## Usage

```julia
using JuMP
using SparseVariables

const SV = SparseVariables

m = Model()

cars = ["ford", "bmw", "opel"]
years = [2000, 2001, 2002, 2003]

car_cost = Dict(
    ("ford", 2000) => 100,
    ("ford", 2001) => 150,
    ("bmw", 2001) => 200,
    ("bmw", 2002) => 300
)


# Empty variables with 2 indices and allowed index values specified
# by `car` and `year`, using `container=IndexedVarArray`
@variable(m, y[car=cars, year=years]; container=IndexedVarArray)
@variable(m, z[car=cars, year=years]; container=IndexedVarArray)
# Dynamic creation of variables
for (cr, yr) in keys(car_cost)
    insertvar!(y, cr, yr)
end

# Inserting values not in the defined value sets errors:
for c in ["opel", "tesla", "nikola"]
    insertvar!(z, c, 2002)
end

# Skip tests for allowed values for maximum performance.
# Note that this will allow creating values outside the defined
# sets, as long as the type is correct.
for c in ["opel", "tesla", "nikola"]
    unsafe_insertvar!(z, c, 2002)
end

# Inefficient iteration, but 0 contribution for non-existing variables
@constraint(m, sum(y[c,i] + z[c,i] for c in cars, i in years) <= 300)

# Slicing over selected indices
@constraint(m, sum(y[:, 2000]) <= 300)

# Efficient filtering using select syntax
for i in years
    @constraint(m, sum(car_cost[c,i] * y[c,i] for (c,i) in SV.select(y, :, i)) <= 300)
end

# Filter using functions on indices
@constraint(m, sum(z[endswith("a"), iseven]) >= 1)
```

## Solution information

The [Tables.jl](https://github.com/JuliaData/Tables.jl) support has now been [upstreamed to JuMP](https://github.com/jump-dev/JuMP.jl/pull/3104), and is also supported for `IndexedVarArray`s:

```julia
using HiGHS

# Solve m
set_optimizer(m, HiGHS.Optimizer)
optimize!(m)

# Fetch solution
tab = JuMP.Containers.rowtable(value, y)

# Save to CSV
using CSV
CSV.write("result.csv", tab)

# Convert to DataFrame
using DataFrames
DataFrame(tab)

# Pretty print
using PrettyTables
pretty_table(tab)
```
