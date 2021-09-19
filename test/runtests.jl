using Base: product
using Dictionaries
using Test
using JuMP
using JuMPUtils
using Cbc

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
    @test JU.select(indices, (:, 1957)) == [lotus]
    @test JU.select(indices, (:, <(2000) )) == [lotus]
    @test JU.select(indices, (:, <(2000)), (2,1)) == [lotus]
    ntnames = (car=1, year=2)
    @test JU.select(indices, (;car="lotus"), ntnames) == [lotus]
    @test JU.select(indices, (;year=1957), ntnames) == [lotus]
    @test JU.select(indices, (year=1957, car="lotus"), ntnames) == [lotus]

    isenglish(x) = x in["lotus","aston martin"]
    @test JU.select(indices, (isenglish, :)) == [lotus]

    complex_query(c,y) = c in ["opel","bmw"] && ((y > 2002) || (y <= 2000))
    complex_query(x) = complex_query(x...) 
    @test length(JU.select(indices, complex_query)) == 4

    @test JU.select(indices, ("lotus", in([1957, 1962]) )) == [lotus]
end

@testset "Permutations" begin
    for N = 1:10
        for K = 1:10
            @test JU._encode_permutation(JU._decode_permutation(N, K)) == K
        end
    end
    for N = 1:100
        t = tuple(collect(N:-1:1)...)
        @test JU._decode_permutation(N, JU._encode_permutation(t)) == t
    end
end

@testset "Named select" begin
    m = Model()
    N = 998
    more_indices = unique(zip(
        rand(["bmw","ford","opel","mazda","volvo"], N),
        rand(1980:2021, N),
        rand(["red","green","black","blue","gray"], N),
        rand(1000:250_000, N)));
    push!(more_indices, ("lotus", 1957, "white", 21332))
    push!(more_indices, ("rolls royce", 1950, "black", 37219))

    car_vars = JU.SparseVarArray(m,"cars", [:maker,:year,:color,:kms])
    @test typeof(car_vars) == JuMPUtils.SparseVarArray{4, Tuple{Any, Any, Any, Any}}
    JU.set_index_names!(car_vars, (:maker,:year,:color,:kms))
    @test JU.get_index_names(car_vars) == (maker = 1, year = 2, color = 3, kms = 4)

    for c in more_indices
        JU.insertvar!(car_vars,c...)
    end

    @test length( JU.kselect(car_vars,(year= <=(1960), maker= x->occursin(" ", x)))) == 1 #rolls royce
    @test length( JU.kselect(car_vars,(;maker="lotus"))) == 1 # lotus
    for (c,y,clr,km) in JU.kselect(car_vars, (;year= <(1960)))
        @test y < 1960
    end
    c = @constraint(m, sum(car_vars[(;year= <(1960))]) <= 1)
    @test typeof(c) <: ConstraintRef
 
end

car_cost["lotus", 1957] = 500
@testset "SparseArray" begin
    
    @test typeof(car_cost) == JU.SparseArray{Int64, 2, Tuple{String, Int64}}
    @test length(car_cost) == 5

    @test car_cost["bmw", 2001] == 200
    @test car_cost["bmw", 2003] == 0
   
    @test length(car_cost) == 5
    @test car_cost["lotus", 1957] == 500
end

@testset "SparseVarArray" begin
    m = Model()
    @sparsevariable(m, y[c,i] for (c,i) in collect(keys(car_cost)))
    @test typeof(y) == JU.SparseVarArray{2 ,Tuple{String, Int}}

    @sparsevariable(m, z[c,i])
    @test length(z) == 0
    for c in ["opel", "tesla", "nikola"]
        insertvar!(z, c, 2002)
    end
    @test length(z) == 3

    @constraint(m, con1, sum(y[c,i] + z[c,i] for c in cars, i in year) <= 300)
    @test length(constraint_object(con1).func.terms) == 5

    @constraint(m, con2[i in year], sum(car_cost[c,i] * y[c,i] for (c,i) in JU.select(y, :, i)) <= 300)
    @test length(constraint_object(con2[2001]).func.terms) == 2
    
    @objective(m, Max, sum(z[c,i] + 2y[c,i] for c in cars, i in year))
    @test length(objective_function(m).terms) == 5

    c =  @constraint(m, [i in year], sum(y[:, i]) <= 1)
    @test isa(c, JuMP.Containers.DenseAxisArray)
    @test isa(first(c), ConstraintRef)
    @test length(c) == length(year)

    insertvar!(z, "mazda", 1990)
    @test length(z[:, begin:2000]) == 1
    @test length(z[:, 2000:end]) == 3
    @test length(z["mazda", 1990:2002]) == 1
end

@testset "Tables" begin
    m = Model()
    @sparsevariable(m, y[car,year] for (car,year) in collect(keys(car_cost)))
    @sparsevariable(m, z[car,year])
    for c in ["opel", "tesla", "nikola"]
        insertvar!(z, c, 2002)
    end
    @constraint(m, con1, sum(y[c,i] + z[c,i] for c in cars, i in year) <= 300)
    @constraint(m, con2[i in year], sum(car_cost[c,i] * y[c,i] for (c,i) in JU.select(y, :, i)) <= 300)

    @objective(m, Max, sum(z[c,i] + 2y[c,i] for c in cars, i in year))

    set_optimizer(m, Cbc.Optimizer)
    set_optimizer_attribute(m, MOI.Silent(), true)
    set_optimizer_attributes(m, "loglevel" => 0)
    optimize!(m)

    t = JU.SolutionTable(y)
    @test typeof(t) == JU.SolutionTable

    @test length(t) == 5

    r = first(t)
    @test typeof(r) == JU.SolutionRow
    @test r.car == "bmw"
end
 