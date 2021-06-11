using Dictionaries
using Test
using JuMP
using JuMPUtils

const JU = JuMPUtils

# Test data
cars = repeat(["ford", "bmw", "opel"], 4)
year = repeat([2000, 2001, 2002, 2003], 3)
indices = collect(zip(cars, year))
lotus = ("lotus", 1957)
push!(indices, lotus)

@testset "Select" begin
    @test JU.select(indices, (⋆, 1957)) == [lotus]
    @test JU.select(indices, (⋆, <(2000) )) == [lotus]
    @test JU.select(indices, (⋆, <(2000)), (2,1)) == [lotus]

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