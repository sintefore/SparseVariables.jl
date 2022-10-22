using Base: product
using DataFrames
using Dictionaries
using HiGHS
using JuMP
using SparseVariables
using Test

const SV = SparseVariables

include("testdata.jl")

(; indices, lotus) = testdata1()

@testset "Select" begin
    @test SV.select(indices, (:, 1957)) == [lotus]
    @test SV.select(indices, (:, <(2000))) == [lotus]
    @test SV.select(indices, (:, <(2000)), (2, 1)) == [lotus]
    ntnames = (car = 1, year = 2)
    @test SV.select(indices, (; car = "lotus"), ntnames) == [lotus]
    @test SV.select(indices, (; year = 1957), ntnames) == [lotus]
    @test SV.select(indices, (year = 1957, car = "lotus"), ntnames) == [lotus]

    isenglish(x) = x in ["lotus", "aston martin"]
    @test SV.select(indices, (isenglish, :)) == [lotus]

    complex_query(c, y) = c in ["opel", "bmw"] && ((y > 2002) || (y <= 2000))
    complex_query(x) = complex_query(x...)
    @test length(SV.select(indices, complex_query)) == 4

    @test SV.select(indices, ("lotus", in([1957, 1962]))) == [lotus]
end

@testset "Permutations" begin
    for N in 1:10
        for K in 1:10
            @test SV._encode_permutation(SV._decode_permutation(N, K)) == K
        end
    end
    for N in 1:100
        t = tuple(collect(N:-1:1)...)
        @test SV._decode_permutation(N, SV._encode_permutation(t)) == t
    end
end

@testset "Named select" begin
    (; cars, years, colors, kms, indices) = testdata()

    m = Model()

    @variable(
        m,
        car_vars[maker = cars, year = years, color = colors, kms = kms];
        container = IndexedVarArray
    )
    @test typeof(car_vars) ==
          IndexedVarArray{VariableRef,4,Tuple{String,Int,String,Int}}

    for c in indices
        insertvar!(car_vars, c...)
    end

    # @test length(
    #     length(car_vars[year <=(1960), maker = x -> occursin(" ", x)]
    # ) == 1 #rolls royce
    # @test length(car_vars[maker = "lotus"]) == 1 # lotus
    # for (c, y, clr, km) in SV.kselect(car_vars, (; year = <(1960)))
    #     @test y < 1960
    # end
    # c = @constraint(m, sum(car_vars[(; year = <(1960))]) <= 1)
    # @test typeof(c) <: ConstraintRef
end

@testset "SparseArray" begin
    (; car_cost) = testdata1()
    @test typeof(car_cost) == SV.SparseArray{Int,2,Tuple{String,Int}}
    @test length(car_cost) == 5

    @test car_cost["bmw", 2001] == 200
    @test car_cost["bmw", 2003] == 0

    @test length(car_cost) == 5
    @test car_cost["lotus", 1957] == 500
end

@testset "Repurposed from SparseVarArray" begin
    (; cars, years, colors, kms) = testdata()
    (; car_cost) = testdata1()

    m = Model()
    @variable(m, y[c = cars, i = years]; container = IndexedVarArray)
    for (c, i) in collect(keys(car_cost))
        insertvar!(y, c, i)
    end

    @test typeof(y) == IndexedVarArray{VariableRef,2,Tuple{String,Int}}

    @variable(m, w[c = cars, i = years], Bin; container = IndexedVarArray)
    for (c, i) in collect(keys(car_cost))
        insertvar!(w, c, i)
    end
    @test typeof(w) == IndexedVarArray{VariableRef,2,Tuple{String,Int}}
    @test count(JuMP.is_binary(w[c, i]) for (c, i) in SV.select(w, "bmw", :)) ==
          2

    # @sparsevariable(m, z[c, i])
    # @test length(z) == 0
    # for c in ["opel", "tesla", "nikola"]
    #     insertvar!(z, c, 2002)
    # end
    # @test length(z) == 3

    # @constraint(m, con1, sum(y[c, i] + z[c, i] for c in cars, i in year) <= 300)
    # @test length(constraint_object(con1).func.terms) == 5

    # @constraint(
    #     m,
    #     con2[i in year],
    #     sum(car_cost[c, i] * y[c, i] for (c, i) in SV.select(y, :, i)) <= 300
    # )
    # @test length(constraint_object(con2[2001]).func.terms) == 2

    # @objective(m, Max, sum(z[c, i] + 2y[c, i] for c in cars, i in year))
    # @test length(objective_function(m).terms) == 5

    # c = @constraint(m, [i in year], sum(y[:, i]) <= 1)
    # @test isa(c, JuMP.Containers.DenseAxisArray)
    # @test isa(first(c), ConstraintRef)
    # @test length(c) == length(year)

    # insertvar!(z, "mazda", 1990)
    # @test length(z[:, begin:2000]) == 1
    # @test length(z[:, 2000:end]) == 3
    # @test length(z["mazda", 1990:2002]) == 1
end

@testset "Caching" begin
    (; cars, years, colors, kms, indices) = testdata()
    (; car_cost) = testdata1()

    m = Model()

    @variable(m, y[c = cars, i = years]; container = IndexedVarArray)
    @variable(m, w[c = cars, i = years], Bin; container = IndexedVarArray)
    for (c, i) in keys(car_cost)
        insertvar!(y, c, i)
        insertvar!(w, c, i)
    end

    @constraint(m, con1, sum(y[:, 2001]) <= 300)
    @test length(y.index_cache) == 4
end

@testset "IndexedVarArray" begin
    m = Model()
    (; cars, year, car_cost) = testdata1(false)

    @variable(m, z[cars = cars, year = year]; container = IndexedVarArray)

    for (cr, yr) in keys(car_cost)
        insertvar!(z, cr, yr)
    end
    @test length(z) == length(car_cost)
    # Add invalid set of values
    for (cr, yr) in keys(car_cost)
        # All should fail, either already added, or invalid keys
        @test_throws ErrorException insertvar!(z, cr, yr)
    end
    @test_throws BoundsError insertvar!(z, "lotus", 2001)
    @test_throws BoundsError insertvar!(z, "bmw", 1957)

    # Slicing and lookup
    @test length(z["bmw", :]) == 2
    @test length(z[:, 2001]) == 2

    @test typeof(z["bmw", 2001]) == VariableRef
    @test z["bmw", 20] == 0

    # Unsafe also works
    unsafe_insertvar!(z, "lotus", 1957)
    @test length(z) == 5

    # Alternative constructor
    @variable(m, z2[cars = cars, year = year], container = IndexedVarArray)
    for k in keys(car_cost)
        insertvar!(z2, k...)
    end
    @test length(z2) == length(car_cost)

    # Larger number of variables (to test caching)
    (; cars, years, colors, kms, indices) = testdata(2000)

    @variable(
        m,
        z3[cars = cars, year = years, color = colors, km = kms];
        container = IndexedVarArray
    )
    for k in indices
        insertvar!(z3, k...)
    end
    # Test with integer index
    @test length(z3[:, 1994, :, :]) ==
          length(filter(x -> x[2] == 1994, indices))
    # Test with string index
    @test length(z3["bmw", :, :, :]) ==
          length(filter(x -> x[1] == "bmw", indices))

    @test length(z3.index_cache[4]) == length(unique(i[2] for i in indices))
    SparseVariables.clear_cache!(z3)
    @test length(z3.index_cache[4]) == 0

    # Begin/End
    @test length(z3[:, begin:2000, :, :]) ==
          length(filter(x -> x[2] <= 2000, indices))
    @test length(z3[:, 1990:end, :, :]) ==
          length(filter(x -> x[2] >= 1990, indices))
    @test length(z3[:, 1990:2000, :, :]) ==
          length(filter(x -> x[2] >= 1990 && x[2] <= 2000, indices))
end

@testset "JuMP extension" begin

    # Test JuMP Extension
    m = Model()
    @variable(m, x[i = 1:3, j = 100:102] >= 0, container = IndexedVarArray)
    @test length(x) == 0
    insertvar!(x, 1, 100)
    @test length(x) == 1
    unsafe_insertvar!(x, 2, 102)
    @test length(x) == 2
end

# Mockup of custom variable type
struct MockVariable <: JuMP.AbstractVariable
    var::JuMP.ScalarVariable
end

struct MockVariableRef <: JuMP.AbstractVariableRef
    v::VariableRef
end

JuMP.name(mv::MockVariableRef) = JuMP.name(mv.v)

struct Mocking end

function JuMP.build_variable(::Function, info::JuMP.VariableInfo, _::Mocking)
    return MockVariable(JuMP.ScalarVariable(info))
end

function JuMP.add_variable(model::Model, x::MockVariable, name::String)
    variable = JuMP.add_variable(model, x.var, name)
    return MockVariableRef(variable)
end

@testset "Custom VariableRef" begin
    m = Model()
    @variable(
        m,
        x[i = 1:3, j = 100:102] >= 0,
        Mocking(),
        container = IndexedVarArray
    )
    @test length(x) == 0
    insertvar!(x, 1, 101)
    @test length(x) == 1
    @test typeof(first(x[:, :])) <: MockVariableRef
    insertvar!(x, 1, 100)
    @test length(x) == 2
    @test sum(x) == sum(x[:, :])
    @test typeof(sum(x)) <: GenericAffExpr{Float64,MockVariableRef}
end
