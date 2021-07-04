using JuMPUtils
using JuMP

const JU = JuMPUtils


m = Model()

cars = ["ford", "bmw", "opel"]
year = [2000, 2001, 2002, 2003]

car_cost = JU.SparseArray(Dict(
    ("ford", 2000) => 100,
    ("ford", 2001) => 150,
    ("bmw", 2001) => 200,
    ("bmw", 2002) => 300
    ))

# Variable defined for a given set of tuples
@sparsevariable(m, y[c,i] for (c,i) in keys(car_cost))

# Empty variable with 2 indices
@sparsevariable(m, z[c,i])


for c in ["opel", "tesla", "nikola"]
    insertvar!(z, c, 2002)
end

# Inefficient iteration, but 0 contribution for non-existing variables
@constraint(m, sum(y[c,i] + z[c,i] for c in cars, i in year) <= 300)

for ii in year
    @constraint(m, sum(car_cost[c,i] * y[c,i] for (c,i) in JU.select(y, :*, ii)) <= 300)
end

c =  @constraint(m, [ii in year], sum(y[:,ii]) <= 1)
@test isa(c, JuMP.Containers.DenseAxisArray)
@test isa(first(c), ConstraintRef)
@test length(c) == length(year)