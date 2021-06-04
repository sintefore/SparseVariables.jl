using JuMPUtils
using JuMP


m = Model()

cars = ["ford", "bmw", "opel"]
year = [2000, 2001, 2002, 2003]

car_cost = Dict( 
    ("ford", 2000) => 100,
    ("ford", 2001) => 150,
    ("bmw", 2001) => 200,
    ("bmw", 2002) => 300
    )

# Variable defined for a given set of tuples
y = JuMPUtils.@sparsevariable(m, y[c,i] for (c,i) in keys(car_cost))

# Empty variable with 2 indices
z = JuMPUtils.@sparsevariable(m, z[c,i])


for c in ["opel", "tesla", "nikola"]
    JuMPUtils.insert!(z, c, 2002)
end

# Inefficient iteration, but 0 contribution for non-existing variables
@constraint(m, sum(y[c,i] + z[c,i] for c in cars, i in year) <= 300)

for ii in year
    @constraint(m, sum(y[c,i] for (c,i) in JuMPUtils.select(y, :*, ii)) <= 1)
end




 