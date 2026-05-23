using Base: product
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
    @test car_cost[endswith("s"), <(2000)] isa SparseArraySlice
    @test length(car_cost[endswith("s"), <(2000)]) == 1
    @test car_cost[endswith("s"), <(2000)]["lotus", 1957] == 500
    @test car_cost[endswith("s"), <(2000)]["bmw", 2001] == 0

    @test length(car_cost) == 5
    @test car_cost["lotus", 1957] == 500

    # show
    @test length(sprint(show, "text/plain", car_cost)) > 100
    @test occursin("SparseArray", sprint(show, "text/plain", car_cost))

    @test !occursin("SparseArray", sprint(show, car_cost))
    @test occursin("(\"bmw\", 2001) = 200", sprint(show, car_cost))

    # select
    @test length(SparseVariables.select(car_cost, ("ford", :))) == 2

    # summary
    @test startswith(sprint(summary, car_cost), "SparseArray{")

    # constructors
    @test typeof(SparseArray(Dict(1 => 2, 2 => 2))) ==
          SparseArray{Int,1,Tuple{Int}}
    @test typeof(SparseArray{Int,3}()) == SparseArray{Int,3,Tuple{Any,Any,Any}}
    @test length(SparseArray{Int,3}()) == 0
    @test typeof(SparseArray{Int,3,NTuple{3,String}}()) ==
          SparseArray{Int,3,Tuple{String,String,String}}
    @test length(SparseArray{Int,3,Tuple{String,String,String}}()) == 0

    # indexing
    indices = eachindex(car_cost)
    @test length(indices) == 5
    @test car_cost[first(indices)] == 200
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
    @test z[endswith("w"), isodd] isa SparseArraySlice
    @test length(z[endswith("w"), isodd]) == 1
    @test haskey(z[endswith("w"), isodd], ("bmw", 2001))
    @test !haskey(z[endswith("w"), isodd], ("bmw", 2002))

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

@testset "Tables IndexedVarArray" begin
    (; cars, year, car_cost) = testdata1(false)

    m = Model()
    @variable(m, y[car = cars, year = year] >= 0; container = IndexedVarArray)
    for c in cars
        insertvar!(y, c, 2002)
    end
    @constraint(m, sum(y[:, :]) <= 300)
    @constraint(
        m,
        [i in year],
        sum(car_cost[c, i] * y[c, i] for (c, i) in SV.select(y, :, i)) <= 200
    )

    @objective(m, Max, sum(y[c, i] for c in cars, i in year))

    set_optimizer(m, HiGHS.Optimizer)
    set_optimizer_attribute(m, MOI.Silent(), true)
    optimize!(m)

    tab = JuMP.Containers.rowtable(value, y)

    T = NamedTuple{(:car, :year, :value),Tuple{String,Int,Float64}}
    @test tab isa Vector{T}

    @test length(tab) == 3
    r = tab[1]
    @test r.car == "ford"
    @test r.year == 2002
    @test r.value == 300.0

    tab_cust =
        JuMP.Containers.rowtable(value, y; header = [:Car, :Year, :Value])
    r = first(tab_cust)
    @test r.Car == "ford"
    @test r.Year == 2002
    @test r.Value == 300.0
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

    insertvar!(x, UnsafeInsert(), 2, 103)
    @test length(x) == 3

    # When no names are provided
    @variable(m, y[1:3, 100:102] >= 0, container = IndexedVarArray)
    @test length(y) == 0
    insertvar!(y, 1, 100)
    @test length(y) == 1
    unsafe_insertvar!(y, 2, 102)
    @test length(y) == 2
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

const _test_sa = testdata_sa()

@testset "SparseArraySlice on SparseArray" begin
    sa = _test_sa

    # _keytype
    @test SV._keytype(sa) == Tuple{String,Int}

    # Types
    v = slice(sa, "ford", :)
    @test v isa SparseArraySlice
    @test v isa SV.AbstractSparseArray
    @test SV._keytype(v) == Tuple{Int}       # projected key type
    @test eltype(v) == Int

    # length
    @test length(slice(sa, "ford", :)) == 2
    @test length(slice(sa, :, 2001))   == 2
    @test length(slice(sa, :, :))      == 5
    @test length(slice(sa, "xxx", :))  == 0

    # keys / values / eachindex / pairs
    ks = sort(keys(v))
    @test ks == [(2000,), (2001,)]
    @test eachindex(v) == keys(v)
    @test sort(values(v)) == [100, 150]
    ps = Dict(pairs(v))
    @test ps[(2000,)] == 100
    @test ps[(2001,)] == 150

    # getindex
    @test v[(2000,)]              == 100    # FT-tuple
    @test v[NTuple{1,Any}((2001,))] == 150  # NTuple{NF,Any}
    @test v[2000]                 == 100    # splatted (NF==1)
    @test v[2001]                 == 150

    v2 = slice(sa, :, :)                   # NF==2
    @test v2["ford", 2000]        == 100
    @test v2["bmw", 2002]         == 300

    # haskey
    @test  haskey(v, (2000,))
    @test !haskey(v, (1999,))

    # sum
    @test sum(v) == 250
    @test sum(slice(sa, :, 2001)) == 350
    @test sum(slice(sa, "xxx", :)) == 0

    # firstindex / lastindex (d = parent-dimension index)
    @test SV.firstindex(v, 2) == 2000
    @test SV.lastindex(v, 2)  == 2001

    # iteration (values only)
    @test sum(val for val in v) == 250
    @test Base.IteratorSize(typeof(v)) == Base.HasLength()
    @test Base.IteratorEltype(typeof(v)) == Base.HasEltype()

    # show / summary
    @test occursin("SparseArraySlice", sprint(summary, v))
    @test occursin("matching (\"ford\", Colon())", sprint(summary, v))
    @test occursin("(2000,) => 100", sprint(show, MIME("text/plain"), v))
    @test occursin("(2001,) => 150", sprint(show, MIME("text/plain"), v))

    # read-only
    @test_throws MethodError (v[(2000,)] = 999)
    @test_throws ErrorException size(v)

    # wrong mask length
    @test_throws BoundsError slice(sa, "ford", :, :)

    # empty slice
    ve = slice(sa, "xxx", :)
    @test length(ve) == 0
    @test isempty(keys(ve))
    @test isempty(values(ve))
    @test sum(ve) == 0
end

@testset "SparseArraySlice on IndexedVarArray" begin
    (; cars, year, car_cost) = testdata1(false)
    m = Model()
    @variable(m, x[c = cars, y = year]; container = IndexedVarArray)
    for k in keys(car_cost)
        insertvar!(x, k...)
    end

    v = slice(x, "ford", :)

    # type and _keytype
    @test v isa SparseArraySlice
    @test SV._keytype(x) == Tuple{String,Int}
    @test SV._keytype(v) == Tuple{Int}

    # length / keys
    @test length(v) == 2
    @test sort(keys(v)) == [(2000,), (2001,)]

    # JuMP sum returns AffExpr
    @test sum(v) isa AffExpr
    @test length(sum(v).terms) == 2

    @test sum(slice(x, :, 2001)) isa AffExpr
    @test length(sum(slice(x, :, 2001)).terms) == 2

    # empty JuMP slice sum returns zero(AffExpr)
    @test sum(slice(x, "xxx", :)) == zero(AffExpr)
end

@testset "Broadcasting SparseArray" begin
    sa = _test_sa

    # scalar broadcast
    r = sa .* 2
    @test r isa SparseArray
    @test length(r) == 5
    @test r["ford", 2000] == 200
    @test r["lotus", 1957] == 1000

    r2 = 2 .* sa
    @test r2["bmw", 2001] == 400

    r3 = sa .+ 10
    @test r3["ford", 2001] == 160

    # element-wise binary
    r4 = sa .+ sa
    @test r4["ford", 2000] == 200
    @test r4["bmw", 2002]  == 600

    # function broadcast
    r5 = sqrt.(sa .* 1.0)
    @test r5 isa SparseArray
    @test r5["ford", 2000] ≈ sqrt(100.0)

    # result type
    @test Base.BroadcastStyle(typeof(sa)) isa SV.SparseBroadcastStyle

    # key mismatch error
    sa2 = SparseArray(Dict(("a", 1) => 1))
    @test_throws ArgumentError sa .+ sa2

    # empty array broadcast
    empty_sa = SparseArray(Dictionary{Tuple{String,Int},Int}())
    r_empty = empty_sa .* 2
    @test r_empty isa SparseArray
    @test length(r_empty) == 0
end

@testset "Broadcasting SparseArraySlice" begin
    sa = _test_sa

    v = slice(sa, "ford", :)
    r = v .* 2
    @test r isa SparseArray
    @test length(r) == 2
    @test r[(2000,)] == 200
    @test r[(2001,)] == 300

    # slice .+ slice (same keys)
    r2 = v .+ v
    @test r2[(2000,)] == 200

    # NF=2 slice broadcast
    v2 = slice(sa, :, :)
    r3 = v2 .* 3
    @test r3["ford", 2000] == 300
    @test r3["lotus", 1957] == 1500

    # key mismatch between two slices
    vbmw = slice(sa, "bmw", :)
    @test_throws ArgumentError v .+ vbmw
end

@testset "Broadcasting IndexedVarArray" begin
    (; cars, year, car_cost) = testdata1(false)
    m = Model()
    @variable(m, x[c = cars, y = year] >= 0; container = IndexedVarArray)
    for k in keys(car_cost)
        insertvar!(x, k...)
    end
    @objective(m, Min, sum(x[c, y] for (c, y) in keys(car_cost)))
    @constraint(m, sum(x[:, :]) == 1)
    set_optimizer(m, HiGHS.Optimizer)
    set_optimizer_attribute(m, MOI.Silent(), true)
    optimize!(m)

    # value.(iva) → SparseArray
    vals = value.(x)
    @test vals isa SparseArray
    @test length(vals) == length(x)
    @test isapprox(sum(values(vals)), 1.0; atol = 1e-6)

    # value.(slice) → SparseArray with projected keys
    vslice = value.(slice(x, "ford", :))
    @test vslice isa SparseArray
    @test length(vslice) == 2
    @test eltype(vslice) == Float64

    # iva .+ iva → SparseArray{AffExpr}
    aff = x .+ x
    @test aff isa SparseArray
    @test length(aff) == length(x)
    @test first(values(aff)) isa AffExpr

    # key mismatch error
    m2 = Model()
    @variable(m2, y[c = ["lotus"], yr = [1957]]; container = IndexedVarArray)
    insertvar!(y, "lotus", 1957)
    @test_throws ArgumentError x .+ y
end
