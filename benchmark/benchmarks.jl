### A Pluto.jl notebook ###
# v0.19.11

using Markdown
using InteractiveUtils

# ╔═╡ 198a71fb-bcbb-46ad-ad79-b24a720e62c7
import Pkg;
Pkg.activate(".");

# ╔═╡ eb67a960-b8a9-4dee-b51d-8202934cab2c
begin
    using AlgebraOfGraphics
    using BenchmarkTools
    using CairoMakie
    using DataFrames
    using JuMP
    using ProgressLogging
    using Random
    using SparseVariables
end

# ╔═╡ 907fdf86-ec90-11ec-1e2e-97884202e0e6
html"""<button onclick=present()>Present</button"""

# ╔═╡ 3a58880b-d505-4149-bb09-e2658147adc8
md"# SparseVariables.jl
###  Efficient sparse modelling with JuMP
Lars Hellemo & Truls Flatberg, SINTEF
"

# ╔═╡ b9886259-16e7-4704-9560-05011abe3227
md"# About Us
* [SINTEF](https://www.sintef.no/en/) is one of Europe’s largest independent research organisations (~2200 employees).
* Department of [Sustainable Energy](https://www.sintef.no/en/industry/topics/sustainable-energy/) Technology, optimization group
* MILP optimization (mostly modelling) for different sectors:
  - Supply chain optimization
  - Energy systems
  - Health care
  - Sustainability
* Historically used proprietary modelling languages (Mosel, AMPL, OPL, GAMS)
* Moving to more open source alternatives, more and more JuMP/Julia
* Several other exciting project using Julia ongoing
"

# ╔═╡ 1ee0b191-292c-4c6d-9e4f-7304fd7d57a6
md"# Motivation
* We love Julia and JuMP for all the usual reasons
  - fast
  - expressive
  - elegant
  - **fun**
  - **hackable**
* Commercial modeling languages are very efficient for:
  - **sparse structures**
  - **large models**
* JuMP performance and usability snags 
* Workarounds are verbose and lacking functionality
* Can we improve the situation?
"

# ╔═╡ f2fd20fc-4775-4520-bbb4-96e0e8b1c888
md"# Tmp using dev environment"

# ╔═╡ a78edb02-00c0-4f78-bea1-c13c54c2bfb3
Pkg.status()

# ╔═╡ 5ed6f654-e73f-4bb7-a2fe-ce22cf2fc1d4
md" 
# An Illustrating Example
We will illustrate some modelling approches using a simple supply chain problem. Consider a company that produces a large selection of different products and sells these to geographically dispersed customers. The company has several factories that can produce each product and they need a decision support system that helps them in deciding which factory should service each customer order. 

Let $P$ denote the set of products, $F$ the factories, $C$ the customers and $T$ the set of time periods. We are given the customer demand, $D_{c,p,t}$, for some combinations of customers, products and periods and want to find how this demand should be assigned to one or more factories in a cost optimal way. Introducing non-negative decision variables $x_{f,p,c,t}$, this corresponds to 

$\sum_{f} x_{f,p,c,t} = D_{c,p,t}.$

In addition to fulfilling demand there are constraints on the feasible solutions. Each factory has an upper limit on total production per period

$\sum_{c,p} x_{f,p,c,t} \le U_{f,t}.$

For some of combinations of factory and customer there can be an upper limit $V_{f,c}$ on the transport capacity per time period

$\sum_{p} x_{f,p,c,t} \le V_{f,c}.$

Finally, not all factories can produce every product. Let $W_{f,p}$ be a parameter with value 1 if the factory $f$ can produce product $p$ and 0 otherwise. Then we have that

$W_{f,p} = 0 \implies x_{f,p,c,t} = 0.$
"

# ╔═╡ d415dbdc-c7c4-400d-8546-23bfa0222bad
md"## Standard (Naïve) Approach
* Don't worry about the extra variables and constraints, presolve will take care of it
"

# ╔═╡ fa24bb0d-7050-4a1c-bbd0-f44ce4f3527b
function model_standard(F, C, P, T, D, U, V, W)
    m = Model()
    @variable(m, x[F, C, P, T] ≥ 0)

    for f in F, c in C, p in P, t in T
        @constraint(m, sum(x[f, c, p, t] for f in F) == get(D, (c, p, t), 0.0))
    end

    for f in F, t in T
        @constraint(m, sum(x[f, c, p, t] for c in C, p in P) ≤ U[f, t])
    end

    for (f, c) in keys(V), t in T
        @constraint(m, sum(x[f, c, p, t] for p in P) ≤ V[f, c])
    end

    for f in F, c in C, p in P, t in T
        if W[f, p] == 0
            @constraint(m, x[f, c, p, t] == 0)
        end
    end

    return m
end

# ╔═╡ f3612117-732c-41c6-a85a-7b38dae49ab8
md"## Using Base Dict
* Widely used workaround
* Create anonymous variables and put in Dict
* Verbose
* Subsetting is awkward
"

# ╔═╡ 935153cb-f77b-443f-941d-52674502e7b7
function model_dict(F, C, P, T, D, U, V, W)
    m = Model()

    # Variable creation
    x = Dict()
    for (c, p, t) in keys(D), f in F
        if W[f, p] == 1
            x[f, c, p, t] = @variable(m, lower_bound = 0)
        end
    end

    # Constraint setup
    indices = [(f, c, p, t) for (c, p, t) in keys(D), f in F if W[f, p] == 1]

    # Customer demand
    for (c̄, p̄, t̄) in keys(D)
        @constraint(
            m,
            sum(
                x[f, c, p, t] for (f, c, p, t) in
                filter(i -> i[2] == c̄ && i[3] == p̄ && i[4] == t̄, indices)
            ) == D[c̄, p̄, t̄]
        )
    end

    # Production capacity
    for (f̄, t̄) in keys(U)
        @constraint(
            m,
            sum(
                x[f, c, p, t] for
                (f, c, p, t) in filter(i -> i[1] == f̄ && i[4] == t̄, indices)
            ) ≤ U[f̄, t̄]
        )
    end

    # Transport capacity
    for (f̄, c̄) in keys(V), t̄ in T
        @constraint(
            m,
            sum(
                x[f, c, p, t] for (f, c, p, t) in
                filter(i -> i[1] == f̄ && i[2] == c̄ && i[4] == t̄, indices)
            ) ≤ V[f̄, c̄]
        )
    end

    return m
end

# ╔═╡ f7da2625-887d-46fe-b159-4fa6d89d61e5
md"## Index using Tuples
* Alternative workaround
* Bundle indices into tuples
* Also reasonably efficient
* Subsetting is awkward
"

# ╔═╡ 0fa9dc20-0cef-41b0-ac03-98031e18db7d
function model_index(F, C, P, T, D, U, V, W)
    m = Model()

    # Variable creation
    indices = [(f, c, p, t) for (c, p, t) in keys(D), f in F if W[f, p] == 1]
    @variable(m, x[indices] ≥ 0)

    # Constraint setup

    # Customer demand
    for (c̄, p̄, t̄) in keys(D)
        @constraint(
            m,
            sum(
                x[(f, c, p, t)] for (f, c, p, t) in
                filter(i -> i[2] == c̄ && i[3] == p̄ && i[4] == t̄, indices)
            ) == D[c̄, p̄, t̄]
        )
    end

    # Production capacity
    for (f̄, t̄) in keys(U)
        @constraint(
            m,
            sum(
                x[(f, c, p, t)] for
                (f, c, p, t) in filter(i -> i[1] == f̄ && i[4] == t̄, indices)
            ) ≤ U[f̄, t̄]
        )
    end

    # Transport capacity
    for (f̄, c̄) in keys(V), t in T
        @constraint(
            m,
            sum(
                x[(f, c, p, t)] for (f, c, p, t) in
                filter(i -> i[1] == f̄ && i[2] == c̄ && i[4] == t, indices)
            ) ≤ V[f̄, c̄]
        )
    end

    return m
end

# ╔═╡ f6bf3148-b32a-48e9-bfa7-c4a16d72fceb
md"## Incremental constraint building
* Build LHS incrementally
* Harder to write
* Harder to read
* Best performance
* Sacrificing convenience
"

# ╔═╡ a14714b1-8993-47af-ad61-1a715c7f58c9
function model_incremental(F, C, P, T, D, U, V, W)
    m = Model()

    # Variable creation
    x = Dict()
    for (c, p, t) in keys(D), f in F
        if W[f, p] == 1
            x[f, c, p, t] = @variable(m, lower_bound = 0)
        end
    end

    # Constraint setup
    pcap = Dict((f, t) => AffExpr() for (f, t) in keys(U))
    cdem = Dict((c, p, t) => AffExpr() for (c, p, t) in keys(D))
    tcap = Dict((f, c, t) => AffExpr() for (f, c) in keys(V), t in T)

    for (f, c, p, t) in keys(x)
        var = x[f, c, p, t]
        if (c, p, t) in keys(D)
            JuMP.add_to_expression!(cdem[c, p, t], var)
        end
        if (f, t) in keys(U)
            JuMP.add_to_expression!(pcap[f, t], var)
        end
        if (f, c) in keys(V)
            JuMP.add_to_expression!(tcap[f, c, t], var)
        end
    end

    # Customer demand
    for (c, p, t) in keys(D)
        @constraint(m, cdem[c, p, t] == D[c, p, t])
    end

    # Production capacity
    for (f, t) in keys(U)
        @constraint(m, pcap[f, t] ≤ U[f, t])
    end

    # Transport capacity
    for (f, c) in keys(V), t in T
        @constraint(m, tcap[f, c, t] ≤ V[f, c])
    end

    return m
end

# ╔═╡ c2ace375-5854-48f6-a6af-68b7d91fc788
md"
## Using SparseVariables.jl
* Dictionaries.jl under the hood
* Expressive
* Convenient
  - Easy to construct sparse variables
  - Incremental building of variables possible
  - Slicing
"

# ╔═╡ ee5ef191-abbe-400b-a172-315873325903
function model_sparse(F, C, P, T, D, U, V, W)
    m = Model()

    # Variable creation
    @sparsevariable(m, x[factory, customer, product, period])

    for f in F, (c, p, t) in keys(D)
        if W[f, p] == 1
            insertvar!(x, f, c, p, t)
        end
    end

    # Constraint creation

    # Customer demand
    for (c, p, t) in keys(D)
        @constraint(m, sum(x[:, c, p, t]) == D[c, p, t])
    end

    # Production capacity
    for (f, t) in keys(U)
        @constraint(m, sum(x[f, :, :, t]) ≤ U[f, t])
    end

    # Transport capacity
    for (f, c) in keys(V), t in T
        @constraint(m, sum(x[f, c, :, t]) ≤ V[f, c])
    end

    return m
end

# ╔═╡ 6bbcbd45-839f-4610-897a-9cada6a65de4
md"# Using SparseAxisArrays
JuMP's SparseAxisArrays now support slicing:"

# ╔═╡ 4a80508b-c664-4337-bf93-06fcf1f746cd
function model_sparse_aa(F, C, P, T, D, U, V, W)
    m = Model()

    # Variable creation
    @variable(
        m,
        x[
            factory = F,
            customer = C,
            product = P,
            period = T;
            W[factory, product] == 1,
        ]
    )

    @sparsevariable(m, x[factory, customer, product, period])

    for f in F, (c, p, t) in keys(D)
        if W[f, p] == 1
            insertvar!(x, f, c, p, t)
        end
    end

    # Constraint creation

    # Customer demand
    for (c, p, t) in keys(D)
        @constraint(m, sum(x[:, c, p, t]) == D[c, p, t])
    end

    # Production capacity
    for (f, t) in keys(U)
        @constraint(m, sum(x[f, :, :, t]) ≤ U[f, t])
    end

    # Transport capacity
    for (f, c) in keys(V), t in T
        @constraint(m, sum(x[f, c, :, t]) ≤ V[f, c])
    end

    return m
end

# ╔═╡ a47ec94a-d9ff-4123-b19e-6292f44fe538
md"# Using IndexedVarArray
A new containter with defined allowed values and performance improvements"

# ╔═╡ 2aff6a71-b37b-4f0a-8b3c-5a09f72e3c7c
function model_indexed(F, C, P, T, D, U, V, W)
    m = Model()

    # Variable creation
    x = SparseVariables.IndexedVarArray(
        m,
        "x",
        (factory = F, customer = C, product = P, period = T),
    )
    m[:x] = x

    for f in F, (c, p, t) in keys(D)
        if W[f, p] == 1
            insertvar!(x, f, c, p, t)
        end
    end

    # Constraint creation

    # Customer demand
    for (c, p, t) in keys(D)
        @constraint(m, sum(x[:, c, p, t]) == D[c, p, t])
    end

    # Production capacity
    for (f, t) in keys(U)
        @constraint(m, sum(x[f, :, :, t]) ≤ U[f, t])
    end

    # Transport capacity
    for (f, c) in keys(V), t in T
        @constraint(m, sum(x[f, c, :, t]) ≤ V[f, c])
    end

    return m
end

# ╔═╡ a25b747b-705a-4cf6-abaa-11d2f1f76272
md"# Increasing problem size
* Increase number of customers (NC)
"

# ╔═╡ 3f883297-9ded-4619-9a92-e6e0ad1e87f7
md"# Varying Sparsity
* Increase probability DP that there is demand from a customer $c$ for product $p$ in time period $t$
"

# ╔═╡ ea9e775e-e25a-46af-b2b4-a29366831b12
md"# Check [SparseVariables.jl](https://github.com/hellemo/SparseVariables.jl) out
* Hope it can be useful
* Experiment with functionality
* Play with performance
* Feedback and PRs are welcome!
* Steal and improve our ideas 😄
"

# ╔═╡ 0a181426-a19f-4c94-a2e3-32d0d48d03d0
md"## "

# ╔═╡ 9d8b6754-1c49-4f4f-b1ad-f5d8eac427c1

# ╔═╡ 4376b3c0-d008-49f3-8b28-d22f6a30324c
md"
# 
# 
"

# ╔═╡ d69fd813-4316-49d5-87d3-dcf50f2c34f0
function create_test(
    nf,
    nc,
    np,
    nt;
    demandprob = 0.05,
    prodprob = 0.2,
    flowprob = 0.8,
    seed = 42,
)
    Random.seed!(seed)
    F = collect(1:nf)
    C = collect(1:nc)
    P = collect(1:np)
    T = collect(1:nt)
    shuffled = shuffle([(c, p, t) for c in C, p in P, t in T])
    D = Dict(
        (c, p, t) => rand() for
        #c in C, p in P, t in T if rand() < demandprob
        (c, p, t) in
        sort(first(shuffled, Int(ceil(demandprob * length(shuffled)))))
    )

    U = Dict((f, t) => rand() * 100 for f in F, t in T)
    V = Dict((f, c) => rand() * 20 for f in F, c in C if rand() < flowprob)
    W = Dict((f, p) => (rand() < prodprob ? 1 : 0) for f in F, p in P)
    return F, C, P, T, D, U, V, W
end

# ╔═╡ c352a486-bbbb-474d-839c-5c867d8a9911
nf, nc, np, nt = 5, 20, 10, 100;

# ╔═╡ d6c417f9-9c9d-4943-876d-a75ceda39336
F, C, P, T, D, U, V, W = create_test(nf, nc, np, nt);

# ╔═╡ 2e583e3b-0ee3-4d98-8dcc-be81d0f4d273
@btime model_standard(F, C, P, T, D, U, V, W)

# ╔═╡ bd1fb6e7-9f51-467a-87e8-b7a9942ce208
@btime model_dict(F, C, P, T, D, U, V, W)

# ╔═╡ e8a917cc-6c9c-438d-ba90-374e0617a3ac
@btime model_index(F, C, P, T, D, U, V, W)

# ╔═╡ b0f05a19-c01c-43dc-82ff-0b3197083b5f
@btime model_incremental(F, C, P, T, D, U, V, W)

# ╔═╡ 1004b0ce-cc9e-4edc-b585-f51a6164e64a
@btime model_sparse(F, C, P, T, D, U, V, W)

# ╔═╡ 49b0a978-48f7-4f1c-9d69-bad1cbea22e5
@btime model_sparse_aa(F, C, P, T, D, U, V, W)

# ╔═╡ de8f21d7-2997-4eb0-acbe-45b863961a32
@btime model_indexed(F, C, P, T, D, U, V, W)

# ╔═╡ 7d205438-8e93-4528-8337-543f02aa84b3
REPS = 5

# ╔═╡ 04570ea7-885c-4d0e-be88-eb2a5f77da90
begin
    res = DataFrame(Method = Symbol[], NC = Int[], Time = Float64[])
    @progress for nc in 5:10:100
        for method in [
            model_standard,
            model_dict,
            model_index,
            model_incremental,
            model_sparse,
            model_sparse_aa,
            model_indexed,
        ]
            t = minimum((
                @elapsed method(create_test(nf, nc, np, nt; seed = r)...)
                for r in 1:REPS
            ))
            push!(res, (Symbol(method), nc, t))
        end
    end
end

# ╔═╡ cc097148-23b1-4584-a150-c7f22376b65c
begin
    sparsity = DataFrame(Method = Symbol[], DP = Float64[], Time = Float64[])
    @progress for dp in 0.05:0.05:1.0
        for method in [
            model_standard,
            model_dict,
            model_index,
            model_incremental,
            model_sparse,
            model_sparse_aa,
            model_indexed,
        ]
            ts = []
            for r in 1:REPS
                GC.gc()
                push!(
                    ts,
                    @elapsed method(
                        create_test(
                            5,
                            40,
                            10,
                            50;
                            demandprob = dp,
                            seed = r,
                        )...,
                    )
                )
            end
            t = minimum(ts)
            push!(sparsity, (Symbol(method), dp, t))
        end
    end
end

# ╔═╡ b0aa0499-e920-4014-b0b2-ce8ea3da7c95
function plot(df, x = :NC, y = :Time)
    CairoMakie.activate!(type = "svg")
    return draw(
        data(df) *
        mapping(x, y => "Time (s)", color = :Method, marker = :Method) *
        (visual(Lines) + visual(Scatter)),
    )
end

# ╔═╡ 4b073bba-940f-4d6f-8ba6-af7355b41e09
plot(res)

# ╔═╡ c71fe88c-5a33-4bbe-bfda-9ba3ca5ff81e
save("res.svg", plot(res))

# ╔═╡ 66eaf973-3c58-4b6a-8ec3-53bf7fa7a20c
plot(sparsity, :DP, :Time)

# ╔═╡ 90cb399b-9944-4e08-acaf-e9411954a18c
save("sparsity.svg", plot(sparsity, :DP, :Time))

# ╔═╡ Cell order:
# ╟─907fdf86-ec90-11ec-1e2e-97884202e0e6
# ╟─3a58880b-d505-4149-bb09-e2658147adc8
# ╟─b9886259-16e7-4704-9560-05011abe3227
# ╟─1ee0b191-292c-4c6d-9e4f-7304fd7d57a6
# ╟─f2fd20fc-4775-4520-bbb4-96e0e8b1c888
# ╠═198a71fb-bcbb-46ad-ad79-b24a720e62c7
# ╠═a78edb02-00c0-4f78-bea1-c13c54c2bfb3
# ╟─5ed6f654-e73f-4bb7-a2fe-ce22cf2fc1d4
# ╟─d415dbdc-c7c4-400d-8546-23bfa0222bad
# ╠═fa24bb0d-7050-4a1c-bbd0-f44ce4f3527b
# ╠═2e583e3b-0ee3-4d98-8dcc-be81d0f4d273
# ╟─f3612117-732c-41c6-a85a-7b38dae49ab8
# ╠═935153cb-f77b-443f-941d-52674502e7b7
# ╠═bd1fb6e7-9f51-467a-87e8-b7a9942ce208
# ╟─f7da2625-887d-46fe-b159-4fa6d89d61e5
# ╠═0fa9dc20-0cef-41b0-ac03-98031e18db7d
# ╠═e8a917cc-6c9c-438d-ba90-374e0617a3ac
# ╟─f6bf3148-b32a-48e9-bfa7-c4a16d72fceb
# ╠═a14714b1-8993-47af-ad61-1a715c7f58c9
# ╠═b0f05a19-c01c-43dc-82ff-0b3197083b5f
# ╟─c2ace375-5854-48f6-a6af-68b7d91fc788
# ╠═ee5ef191-abbe-400b-a172-315873325903
# ╠═1004b0ce-cc9e-4edc-b585-f51a6164e64a
# ╟─6bbcbd45-839f-4610-897a-9cada6a65de4
# ╠═4a80508b-c664-4337-bf93-06fcf1f746cd
# ╠═49b0a978-48f7-4f1c-9d69-bad1cbea22e5
# ╟─a47ec94a-d9ff-4123-b19e-6292f44fe538
# ╠═2aff6a71-b37b-4f0a-8b3c-5a09f72e3c7c
# ╠═de8f21d7-2997-4eb0-acbe-45b863961a32
# ╟─a25b747b-705a-4cf6-abaa-11d2f1f76272
# ╠═4b073bba-940f-4d6f-8ba6-af7355b41e09
# ╠═c71fe88c-5a33-4bbe-bfda-9ba3ca5ff81e
# ╠═04570ea7-885c-4d0e-be88-eb2a5f77da90
# ╟─3f883297-9ded-4619-9a92-e6e0ad1e87f7
# ╠═66eaf973-3c58-4b6a-8ec3-53bf7fa7a20c
# ╠═90cb399b-9944-4e08-acaf-e9411954a18c
# ╠═cc097148-23b1-4584-a150-c7f22376b65c
# ╟─ea9e775e-e25a-46af-b2b4-a29366831b12
# ╟─0a181426-a19f-4c94-a2e3-32d0d48d03d0
# ╟─9d8b6754-1c49-4f4f-b1ad-f5d8eac427c1
# ╟─4376b3c0-d008-49f3-8b28-d22f6a30324c
# ╠═eb67a960-b8a9-4dee-b51d-8202934cab2c
# ╠═d69fd813-4316-49d5-87d3-dcf50f2c34f0
# ╠═c352a486-bbbb-474d-839c-5c867d8a9911
# ╠═d6c417f9-9c9d-4943-876d-a75ceda39336
# ╠═7d205438-8e93-4528-8337-543f02aa84b3
# ╠═b0aa0499-e920-4014-b0b2-ce8ea3da7c95
