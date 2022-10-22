function testdata(N = 998)
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
    push!(valid_cars, "lotus")
    push!(valid_cars, "rolls royce")
    push!(valid_colors, "white")
    valid_years = 1950:2021
    push!(more_indices, ("lotus", 1957, "white", 21332))
    push!(more_indices, ("rolls royce", 1950, "black", 37219))
    return (
        cars = valid_cars,
        years = valid_years,
        colors = valid_colors,
        kms = valid_kms,
        indices = more_indices,
    )
end

function testdata1(addlotus = true)
    cars = ["ford", "bmw", "opel"]
    year = [2000, 2001, 2002, 2003]
    indices = vec(collect(Iterators.product(cars, year)))
    lotus = ("lotus", 1957)
    if addlotus
        push!(indices, lotus)
    end
    car_cost = SparseVariables.SparseArray(
        Dict(
            ("ford", 2000) => 100,
            ("ford", 2001) => 150,
            ("bmw", 2001) => 200,
            ("bmw", 2002) => 300,
        ),
    )
    if addlotus
        car_cost["lotus", 1957] = 500
    end
    return (
        cars = cars,
        year = year,
        indices = indices,
        car_cost = car_cost,
        lotus = lotus,
    )
end
