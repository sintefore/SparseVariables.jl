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

indices = [k for k in keys(car_cost)]

y = JuMPUtils.create_variables(m, 2, "y", keys(car_cost))

@constraint(m, sum(y[c,i] for c in cars, i in year) <= 300)

for ii in year
    @constraint(m, sum(y[c,i] for (c,i) in JuMPUtils.select(y, :*, ii)) <= 1)
end




