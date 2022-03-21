# SparseVariables.jl

This package contains routines for improved and easier handling of sparse data 
and sparse arrays of optimizaton variables in JuMP.

## Usage

```julia
using SparseVariables
using JuMP

const SV = SparseVariables

m = Model()

cars = ["ford", "bmw", "opel"]
year = [2000, 2001, 2002, 2003]

car_cost = SV.SparseArray(Dict(
    ("ford", 2000) => 100,
    ("ford", 2001) => 150,
    ("bmw", 2001) => 200,
    ("bmw", 2002) => 300
    ))

# Variable defined for a given set of tuples
@sparsevariable(m, y[car, year] for (car,year) in keys(car_cost))

# Empty variable with 2 indices
@sparsevariable(m, z[car, year])

# Dynamic creation of variables
for c in ["opel", "tesla", "nikola"]
    insertvar!(z, c, 2002)
end

# Inefficient iteration, but 0 contribution for non-existing variables
@constraint(m, sum(y[c,i] + z[c,i] for c in cars, i in year) <= 300)

# Slicing over selected indices
@constraint(m, sum(y[:,2000])  <= 300)


# Efficient filtering using select syntax
for i in year
    @constraint(m, sum(car_cost[c,i] * y[c,i] for (c,i) in SV.select(y, :, i)) <= 300)
end

```

## Solution information

The package defines a structure SolutionTable that supports the Tables.jl interface, allowing 
easy output of solution values to e.g. a dataframe or a csv-file
```julia
using DataFrames
using CSV

tab = table(y)
CSV.write("result.csv", tab)

df = dataframe(y)
```
The Tables interface is also implemented for DenseAxisArrray, allowing the functionality to be used also for normal
dense JuMP-variables. Since the container does not provide index names, these has to be given as explicit arguments.

Note that output to a DataFrame through the dataframe function is only possible if the DataFrames package is loaded
before JuMPUtils.


## TODO

* Support for broadcasting?
* Restriction on allowable indices (e.g. only a fixed set allowed)

