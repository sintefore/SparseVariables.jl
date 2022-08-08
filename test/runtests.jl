using Base: product
using DataFrames
using Dictionaries
using HiGHS
using JuMP
using SparseVariables
using Test

const SV = SparseVariables

# Test data
cars = ["ford", "bmw", "opel"]
year = [2000, 2001, 2002, 2003]
indices = vec(collect(Iterators.product(cars, year)))
lotus = ("lotus", 1957)
push!(indices, lotus)
car_cost = SV.SparseArray(
    Dict(
        ("ford", 2000) => 100,
        ("ford", 2001) => 150,
        ("bmw", 2001) => 200,
        ("bmw", 2002) => 300,
    ),
)
car_cost["lotus", 1957] = 500

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
    m = Model()
    N = 998
    more_indices = unique(
        zip(
            rand(["bmw", "ford", "opel", "mazda", "volvo"], N),
            rand(1980:2021, N),
            rand(["red", "green", "black", "blue", "gray"], N),
            rand(1000:250_000, N),
        ),
    )
    push!(more_indices, ("lotus", 1957, "white", 21332))
    push!(more_indices, ("rolls royce", 1950, "black", 37219))

    car_vars = SV.SparseVarArray(m, "cars", [:maker, :year, :color, :kms])
    @test typeof(car_vars) == SV.SparseVarArray{4,Tuple{Any,Any,Any,Any}}
    SV.set_index_names!(car_vars, (:maker, :year, :color, :kms))
    @test SV.get_index_names(car_vars) ==
          (maker = 1, year = 2, color = 3, kms = 4)

    for c in more_indices
        SV.insertvar!(car_vars, c...)
    end

    @test length(
        SV.kselect(car_vars, (year = <=(1960), maker = x -> occursin(" ", x))),
    ) == 1 #rolls royce
    @test length(SV.kselect(car_vars, (; maker = "lotus"))) == 1 # lotus
    for (c, y, clr, km) in SV.kselect(car_vars, (; year = <(1960)))
        @test y < 1960
    end
    c = @constraint(m, sum(car_vars[(; year = <(1960))]) <= 1)
    @test typeof(c) <: ConstraintRef
end

@testset "SparseArray" begin
    @test typeof(car_cost) == SV.SparseArray{Int,2,Tuple{String,Int}}
    @test length(car_cost) == 5

    @test car_cost["bmw", 2001] == 200
    @test car_cost["bmw", 2003] == 0

    @test length(car_cost) == 5
    @test car_cost["lotus", 1957] == 500
end

@testset "SparseVarArray" begin
    m = Model()
    @sparsevariable(m, y[c, i] for (c, i) in collect(keys(car_cost)))
    @test typeof(y) == SV.SparseVarArray{2,Tuple{String,Int}}

    @sparsevariable(m, w[c, i] for (c, i) in keys(car_cost); binary = true)
    @test typeof(w) == SV.SparseVarArray{2,Tuple{String,Int}}
    @test count(JuMP.is_binary(w[c, i]) for (c, i) in SV.select(w, "bmw", :)) ==
          2

    @sparsevariable(m, z[c, i])
    @test length(z) == 0
    for c in ["opel", "tesla", "nikola"]
        insertvar!(z, c, 2002)
    end
    @test length(z) == 3

    @constraint(m, con1, sum(y[c, i] + z[c, i] for c in cars, i in year) <= 300)
    @test length(constraint_object(con1).func.terms) == 5

    @constraint(
        m,
        con2[i in year],
        sum(car_cost[c, i] * y[c, i] for (c, i) in SV.select(y, :, i)) <= 300
    )
    @test length(constraint_object(con2[2001]).func.terms) == 2

    @objective(m, Max, sum(z[c, i] + 2y[c, i] for c in cars, i in year))
    @test length(objective_function(m).terms) == 5

    c = @constraint(m, [i in year], sum(y[:, i]) <= 1)
    @test isa(c, JuMP.Containers.DenseAxisArray)
    @test isa(first(c), ConstraintRef)
    @test length(c) == length(year)

    insertvar!(z, "mazda", 1990)
    @test length(z[:, begin:2000]) == 1
    @test length(z[:, 2000:end]) == 3
    @test length(z["mazda", 1990:2002]) == 1
end

@testset "Caching" begin
    m = Model()
    @sparsevariable(m, y[c, i] for (c, i) in collect(keys(car_cost)))
    @sparsevariable(m, w[c, i] for (c, i) in keys(car_cost); binary = true)

    @constraint(m, con1, sum(y[:, 2001]) <= 300)
    @test length(y.index_cache) == 1
    @test length(y.index_cache[(2,)]) == 4
    @test length(y.index_cache[(2,)][(2002,)]) == 1

    @constraint(m, con2, sum(y[:, 2000]) <= 500)
    @test length(constraint_object(con2).func.terms) == 1

    @constraint(m, con3, sum(y[:, :]) <= 1200)
    @test length(y.index_cache[()][()]) == 5

    # Add extra variable to test cache update
    insertvar!(y, "nissan", 2000)

    @test length(y.index_cache[(2,)][(2000,)]) == 2
    @test length(y.index_cache[()][()]) == 6
end

@testset "Tables" begin
    m = Model()
    @sparsevariable(m, y[car, year] for (car, year) in collect(keys(car_cost)))
    @sparsevariable(m, z[car, year])
    @variable(m, u[cars, year])
    for c in ["opel", "tesla", "nikola"]
        insertvar!(z, c, 2002)
    end
    @constraint(m, con1, sum(y[c, i] + z[c, i] for c in cars, i in year) <= 300)
    @constraint(
        m,
        con2[i in year],
        sum(car_cost[c, i] * y[c, i] for (c, i) in SV.select(y, :, i)) <= 300
    )

    for c in cars, y in year
        @constraint(m, u[c, y] <= 1)
    end

    @objective(
        m,
        Max,
        sum(z[c, i] + 2y[c, i] for c in cars, i in year) +
        sum(u[c, 2002] for c in cars)
    )

    set_optimizer(m, HiGHS.Optimizer)
    set_optimizer_attribute(m, MOI.Silent(), true)
    optimize!(m)

    tab = table(y)
    @test typeof(tab) == SV.SolutionTableSparse

    @test length(tab) == 5

    r = first(tab)
    @test typeof(r) == SV.SolutionRow
    @test r.car == "bmw"

    t2 = table(u, :u, :car, :year)
    @test typeof(t2) == SV.SolutionTableDense
    @test length(t2) == 12
    rows = collect(t2)
    @test rows[11].year == 2003

    df = dataframe(u, :u, :car, :year)
    @test first(df.car) == "ford"
end

@testset "IndexedVarArray" begin
    m = Model()
    car_cost = SV.SparseArray(
        Dict(
            ("ford", 2000) => 100,
            ("ford", 2001) => 150,
            ("bmw", 2001) => 200,
            ("bmw", 2002) => 300,
        ),
    )

    y = IndexedVarArray(
        m,
        "y",
        (cars = cars, year = year),
        collect(keys(car_cost)),
    )
    @test length(y) == length(car_cost)
    z = IndexedVarArray(m, "z", (cars = cars, year = year))
    for (cr, yr) in keys(car_cost)
        safe_insertvar!(z, cr, yr)
    end
    @test length(z) == length(car_cost)
    # Add invalid set of values
    for (cr, yr) in keys(car_cost)
        # All should fail, either already added, or invalid keys
        @test_throws ErrorException safe_insertvar!(z, cr, yr)
    end
    @test_throws BoundsError safe_insertvar!(z, "lotus", 2001)
    @test_throws BoundsError safe_insertvar!(z, "bmw", 1957)
    @test length(z) == length(y)

    # Slicing and lookup
    @test length(y[:, 2001]) == 2
    @test length(z["bmw", :]) == 2
    @test typeof(z["bmw", 2001]) == VariableRef
    @test z["bmw", 20] == 0

    # Unsafe add still works
    insertvar!(z, "lotus", 1957)
    @test length(z) == 5

    # Alternative constructor
    z2 = IndexedVarArray(m, "z2", (cars = cars, year = year), keys(car_cost))
    @test length(z2) == length(car_cost)

    # Larger number of variables (to test caching)
    N = 2000
    valid_cars = ["bmw", "ford", "opel", "mazda", "volvo"]
    valid_years = 1980:2021
    valid_colors = ["red", "green", "black", "blue", "gray"]
    valid_kms = 1000:250_000

    more_indices = unique(
        zip(
            rand(valid_cars, N),
            rand(valid_years, N),
            rand(valid_colors, N),
            rand(valid_kms, N),
        ),
    )

    z3 = IndexedVarArray(
        m,
        "z3",
        (
            cars = valid_cars,
            year = valid_years,
            color = valid_colors,
            km = valid_kms,
        ),
        more_indices,
    )
    @test length(z3[:, 1994, :, :]) ==
          length(filter(x -> x[2] == 1994, more_indices))

    @test length(z3.index_cache[4]) ==
          length(unique(i[2] for i in more_indices))
    SparseVariables.clear_cache!(z3)
    @test length(z3.index_cache[4]) == 0
end
