using Base: product
using Dictionaries
using Test
using JuMP
using JuMPUtils

const JU = JuMPUtils

# Test data
cars = ["ford", "bmw", "opel"]
year = [2000, 2001, 2002, 2003]
indices = vec(collect(Iterators.product(cars, year)))
lotus = ("lotus", 1957)
push!(indices, lotus)
car_cost = JU.SparseArray(Dict(
    ("ford", 2000) => 100,
    ("ford", 2001) => 150,
    ("bmw", 2001) => 200,
    ("bmw", 2002) => 300
    ))

@testset "Select" begin
    @test JU.select(indices, (⋆, 1957)) == [lotus]
    @test JU.select(indices, (⋆, <(2000) )) == [lotus]

    isenglish(x) = x in["lotus","aston martin"]
    @test JU.select(indices, (isenglish, ⋆)) == [lotus]

    complex_query(c,y) = c in ["opel","bmw"] && ((y > 2002) || (y <= 2000))
    complex_query(x) = complex_query(x...) 
    @test length(JU.select(indices, complex_query)) == 4

    @test JU.select(indices, ("lotus", in([1957, 1962]) )) == [lotus]
end

@testset "Dictionaries" begin
    m = Model()
    y = JU.create_variables_dictionary3(m, 2, "y", indices)
    @test typeof(y) == Dictionary{Tuple{String, Int64}, VariableRef}

    a = @constraint(m, sum(JU.select(y, ("lotus", ⋆))) <=1)
    @test typeof(a) == ConstraintRef{Model, MOI.ConstraintIndex{MOI.ScalarAffineFunction{Float64}, MOI.LessThan{Float64}}, ScalarShape}
end

@testset "SparseArray" begin
    
    @test typeof(car_cost) == JU.SparseArray{Int64, 2, Tuple{String, Int64}}
    @test length(car_cost) == 4

    @test car_cost["bmw", 2001] == 200
    @test car_cost["bmw", 2003] == 0
   
    car_cost["lotus", 1957] = 500
    @test length(car_cost) == 5
    @test car_cost["lotus", 1957] == 500
end

@testset "SparseVarArray" begin
    m = Model()
    @sparsevariable(m, y[c,i] for (c,i) in keys(car_cost))
    @test typeof(y) == JU.SparseVarArray{2}

    @sparsevariable(m, z[c,i])
    @test length(z) == 0
    for c in ["opel", "tesla", "nikola"]
        insertvar!(z, c, 2002)
    end
    @test length(z) == 3

    @constraint(m, con1, sum(y[c,i] + z[c,i] for c in cars, i in year) <= 300)
    @test length(constraint_object(con1).func.terms) == 5

    @constraint(m, con2[i in year], sum(car_cost[c,i] * y[c,i] for (c,i) in JU.select(y, ⋆, i)) <= 300)
    @test length(constraint_object(con2[2001]).func.terms) == 2
    
    @objective(m, Max, sum(z[c,i] + 2y[c,i] for c in cars, i in year))
    @test length(objective_function(m).terms) == 5
end
