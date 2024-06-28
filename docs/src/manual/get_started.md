# Get Started

## Usage

```jldoctest readme_example
using JuMP
using SparseVariables
using HiGHS

const SV = SparseVariables

m = Model()

cars = ["ford", "bmw", "opel"]
years = [2000, 2001, 2002, 2003]

car_cost = SparseArray(Dict(
    ("ford", 2000) => 100,
    ("ford", 2001) => 150,
    ("bmw", 2001) => 200,
    ("bmw", 2002) => 300
    ))


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
# output
ERROR: BoundsError: attempt to access IndexedVarArray{VariableRef, 2, Tuple{String, Int64}} with 1 entry at index ["tesla", 2002]

```

```jldoctest readme_example
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

# Solve m
set_optimizer(m, optimizer_with_attributes(HiGHS.Optimizer, MOI.Silent()=>true))
optimize!(m)

termination_status(m)

# output

OPTIMAL::TerminationStatusCode = 1

```

## Solution information

The [Tables.jl](https://github.com/JuliaData/Tables.jl) support has now been [upstreamed to JuMP](https://github.com/jump-dev/JuMP.jl/pull/3104), and is also supported for `IndexedVarArray`s, which makes it easy to get solutions for all indices at once and e.g. save to a CSV file or import into a `DataFrame`:

```jldoctest readme_example
# Fetch solution
tab = JuMP.Containers.rowtable(value, y)

# Save to CSV
using CSV
CSV.write("result.csv", tab)

# Convert to DataFrame
using DataFrames
DataFrame(tab)

# output

4×3 DataFrame
 Row │ car     year   value
     │ String  Int64  Float64
─────┼────────────────────────
   1 │ bmw      2001      1.5
   2 │ ford     2001      0.0
   3 │ ford     2000      3.0
   4 │ bmw      2002      1.0
```

The results may also be pretty-printed in the terminal using `PrettyTables`:

```jldoctest readme_example
using PrettyTables
pretty_table(tab)

# output

┌────────┬───────┬─────────┐
│    car │  year │   value │
│ String │ Int64 │ Float64 │
├────────┼───────┼─────────┤
│    bmw │  2001 │     1.5 │
│   ford │  2001 │     0.0 │
│   ford │  2000 │     3.0 │
│    bmw │  2002 │     1.0 │
└────────┴───────┴─────────┘
```
