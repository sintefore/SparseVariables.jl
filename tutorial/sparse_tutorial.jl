### A Pluto.jl notebook ###
# v0.18.0

using Markdown
using InteractiveUtils

# ╔═╡ 9150eed0-89e1-11ec-2363-1d1d3d46c3ff
begin
	import Pkg
	Pkg.activate(".")

	using DataFrames 
	using JuMPUtils
	using JuMP
	using Gadfly
	import Random
end

# ╔═╡ 93dce568-6cac-4c62-bd7c-7e33edaacd8d
md"
# Large scale optimization with sparse structures

An often forgotten aspect when modeling real world applications as large scale linear optimization problems, is that the setup of the model itself can take considerable time. Modern solvers for LPs are extremely efficient and for large problems the creation of the problem may take time that is comparable or even longer than the solution time.

"

# ╔═╡ dfeae97f-76bc-49d8-ad72-bee061af7cd4
md" 
## An example problem
Throughout this tutorial we are going to illustrate different approaches based on a simple supply chain problem. Consider a company that produces a large selection of different products and sells these to geographically dispersed customers. The company has several factories that can produce each product and they need a decision support system that helps them in deciding which factory should service each customer order. 

Let $P$ denote the set of products, $F$ the factories, $C$ the customers and $T$ the set of time periods. We are given the customer demand, $D_{c,p,t}$, for some combinations of customers, products and periods and want to find how this demand should be assigned to one or more factories in a cost optimal way. Introducing non-negative decision variables $x_{f,p,c,t}$, this corresponds to 

$\sum_{f} x_{f,p,c,t} = D_{f,p,c,t}.$

In addition to fulfilling demand there are constraints on the feasible solutions. Each factory has an upper limit on total production per period

$\sum_{c,p} x_{f,p,c,t} \le U_{f,t}.$

For some of combinations of factory and customer there can be an upper limit $V_{f,c}$ on the transport capacity per time period

$\sum_{p} x_{f,p,c,t} \le V_{f,c}.$

Finally, not all factories can produce every product. Let $W_{f,p}$ be a parameter with value 1 if the factory $f$ can produce product $p$ and 0 otherwise. Then we have that

$W_{f,p} = 0 \implies x_{f,p,c,t} = 0.$
"

# ╔═╡ 6890dae5-48de-4552-bb51-1dedd0405031
begin
	function create_test(nf, nc, np, nt; demandprob = 0.05, prodprob = 0.2, flowprob = 0.8)

		Random.seed!(42)
		
		F = collect(1:nf)
    	C = collect(1:nc)
    	P = collect(1:np)
    	T = collect(1:nt)

		D = Dict((c,p,t) => rand() for c in C, p in P, t in T if rand() < demandprob)
    	U = Dict((f,t) => rand() * 100 for f in F, t in T)
    	V = Dict((f,c) => rand() * 20 for f in F, c in C if rand() < flowprob)
		W = Dict((f,p) => (rand() < prodprob ? 1 : 0) for f in F, p in P)
		return F,C,P,T,D,U,V,W
	end
end

# ╔═╡ 10de4874-b081-4e7e-a4d2-14eb3d44dd24
nf, nc, np, nt = 5, 20, 10 ,100;

# ╔═╡ 3196b821-559d-418c-9026-32b6af86f4f5
 F,C,P,T,D,U,V,W = create_test(nf, nc, np, nt);

# ╔═╡ 3621ab6a-1c9b-4239-b762-089959ed011c
md" 
## Standard approach

Our first approach will be based on using JuMP directly without consideration of any sparse structures.
"

# ╔═╡ 408e9db0-5528-48ef-85f6-65d33ab855a3
begin
	function model_standard(F,C,P,T,D,U,V,W)
		m = Model()
		@variable(m, x[F,C,P,T] ≥ 0)
		
		for f in F, c in C, p in P, t in T
			@constraint(m, sum(x[f,c,p,t] for f in F) == get(D, (c,p,t), 0.0))
		end
		
		for f in F, t in T
			@constraint(m, sum(x[f,c,p,t] for c in C, p in P) ≤ U[f,t])
		end
		
		for (f,c) in keys(V), t in T
			@constraint(m, sum(x[f,c,p,t] for p in P) ≤ V[f,c])
		end

		for f in F, c in C, p in P, t in T
			if W[f,p] == 0
				@constraint(m, x[f,c,p,t] == 0)
			end
		end

		
		return m
	end
end

# ╔═╡ a78b435c-4716-40a4-a249-6f6b4067d1c3
t1 = @timed model_standard(F,C,P,T,D,U,V,W)

# ╔═╡ 11e9233a-d518-4731-b677-7127bde16a8f
md"
## Using dictionaries
"

# ╔═╡ 1228a399-f27a-4710-9090-7cf5bc473f86
begin
	function model_dict(F,C,P,T,D,U,V,W)
		m = Model()

		# Variable creation
		x = Dict()
		for (c,p,t) in keys(D), f in F 
			if W[f,p] == 1 
				x[f,c,p,t] = @variable(m, lower_bound = 0)
			end
		end
		
		# Constraint setup
		indices = [(f,c,p,t) for (c,p,t) in keys(D), f in F if W[f,p] == 1]

		# Customer demand
	    for (c̄,p̄,t̄) in keys(D)
	        @constraint(m, sum(x[f,c,p,t] for (f,c,p,t) in 
				filter(i->i[2]==c̄ && i[3]==p̄ && i[4]==t̄, indices)) == D[c̄,p̄,t̄])
	    end
		
		# Production capacity
	    for (f̄,t̄) in keys(U)
	        @constraint(m, sum(x[f,c,p,t] for (f,c,p,t) in 
				filter(i->i[1]==f̄ && i[4]==t̄, indices)) ≤ U[f̄,t̄])
	    end
	
	    # Transport capacity
	    for (f̄,c̄) in keys(V), t̄ in T
	    	@constraint(m, sum(x[f,c,p,t] for (f,c,p,t) in  
				filter(i->i[1]==f̄ && i[2]==c̄ && i[4]==t̄, indices)) ≤ V[f̄,c̄])
	    end

		return m
	end
end

# ╔═╡ 0a87d15d-3c6c-411d-97cc-75a7cd8c21c1
t2 = @timed model_dict(F,C,P,T,D,U,V,W)

# ╔═╡ e5182068-4bd7-41cc-b313-16b083735b9d
md"
## Using tuples as indices

"

# ╔═╡ 5dbb16da-798a-4eed-92f9-2b5d01f597c2
begin
	function model_index(F,C,P,T,D,U,V,W)
		m = Model()

		# Variable creation
		indices =[(f,c,p,t) for (c,p,t) in keys(D), f in F if W[f,p] == 1]
		@variable(m, x[indices] ≥ 0)
		
		# Constraint setup

		# Customer demand
	    for (c̄,p̄,t̄) in keys(D)
	        @constraint(m, sum(x[(f,c,p,t)] for (f,c,p,t) in 
				filter(i->i[2]==c̄ && i[3]==p̄ && i[4]==t̄, indices)) == D[c̄,p̄,t̄])
	    end
		
		# Production capacity
		for (f̄,t̄) in keys(U)
	        @constraint(m, sum(x[(f,c,p,t)] for (f,c,p,t) in 
				filter(i->i[1]==f̄ && i[4]==t̄, indices)) ≤ U[f̄,t̄])
	    end
	
	    # Transport capacity
	    for (f̄,c̄) in keys(V), t in T
	    	@constraint(m, sum(x[(f,c,p,t)] for (f,c,p,t) in 
				filter(i->i[1]==f̄ && i[2]==c̄ && i[4]==t, indices)) ≤ V[f̄,c̄])
	    end
		
		return m
	end
end

# ╔═╡ fe7ec5c3-e41c-4b6e-9938-72e5b342157e
t3 = @timed model_index(F,C,P,T,D,U,V,W)

# ╔═╡ 09d44792-82de-4b2a-9cbd-605d243dab80
md"
## Incremental constraint building

"

# ╔═╡ 759cb8ed-5d23-41d9-90cd-d734fea98c0b
begin
	function model_incremental(F,C,P,T,D,U,V,W)

		m = Model()
		
		# Variable creation
		x = Dict()
		for (c,p,t) in keys(D), f in F 
			if W[f,p] == 1 
				x[f,c,p,t] = @variable(m, lower_bound = 0)
			end
		end
		
		# Constraint setup
		pcap = Dict((f,t) => AffExpr() for (f,t) in keys(U))
    	cdem  = Dict((c,p,t) => AffExpr() for (c,p,t) in keys(D))
    	tcap = Dict((f,c,t) => AffExpr() for (f,c) in keys(V), t in T)
    
	    for (f,c,p,t) in keys(x)
	        var = x[f,c,p,t]
	        if (c,p,t) in keys(D)
	            JuMP.add_to_expression!(cdem[c,p,t], var)
	        end
			if (f,t) in keys(U)
	            JuMP.add_to_expression!(pcap[f,t], var)
	        end
	        if (f,c) in keys(V)
	            JuMP.add_to_expression!(tcap[f,c,t], var)
	        end
	    end

		# Customer demand
	    for (c,p,t) in keys(D)
	        @constraint(m, cdem[c,p,t] == D[c,p,t])
	    end
		
	    # Production capacity
	    for (f,t) in keys(U)
	        @constraint(m, pcap[f,t] ≤ U[f,t])
	    end
	
	    # Transport capacity
	    for (f,c) in keys(V), t in T
	        @constraint(m, tcap[f,c,t] ≤ V[f,c])
	    end

		return m
	end
end

# ╔═╡ a17d8b7e-c02e-41b3-bbdf-d8dc018022c4
t4 = @timed model_incremental(F,C,P,T,D,U,V,W)

# ╔═╡ 10bbfb4d-ca07-4d4f-9c07-9e805b8744bb
md"
## Using SparseOptUtil.jl
"

# ╔═╡ 80d8a95d-61a3-41f7-bf2a-bf2e26221582
begin
	function model_sparse(F,C,P,T,D,U,V,W)
		m = Model()

		# Variable creation
		@sparsevariable(m, x[factory, customer, product, period])

		for (c,p,t) in keys(D), f in F 
			if W[f,p] == 1 
				insertvar!(x, f, c, p, t)
			end
		end

		# Constraint creation
	
		# Customer demand
	    for (c,p,t) in keys(D)
	        @constraint(m, sum(x[:,c,p,t]) == D[c,p,t])
	    end
	
		# Production capacity
	    for (f,t) in keys(U)
	        @constraint(m, sum(x[f,:,:,t]) ≤ U[f,t])
	    end
	
	    # Transport capacity
	    for (f,c) in keys(V), t in T
	        @constraint(m, sum(x[f,c,:,t]) ≤ V[f,c])
	    end
		
		return m
	end
end

# ╔═╡ 0041a12e-1dd8-48a5-b44b-7fb8ba5dfbb2
t5 = @timed model_sparse(F,C,P,T,D,U,V,W)

# ╔═╡ 084f9445-27cd-4a36-b031-42b54f934ec8
md"
## Varying problem size
"

# ╔═╡ c49a3599-65fd-442b-b5c9-625b87e05efa
begin
	res = DataFrame(Method=Symbol[], NC=Int[], Time=Float64[])
	for nc in 5:5:50
		for method in [model_standard, model_dict, model_index, model_incremental, model_sparse]
			t = @timed method(create_test(nf, nc, np, nt)...)
			push!(res,(Symbol(method), nc, t.time))
		end
	end
end

# ╔═╡ 3881bb13-7ab7-4b52-bd35-5a9e9d6bce29
res

# ╔═╡ 3bf1a58c-72db-4120-9b64-71a83d65bf87
plot(res, x=:NC, y=:Time, color=:Method, Geom.point, Geom.line)

# ╔═╡ 67903213-e5e2-4c56-ab32-2c93c8092830
md"
## Varying sparsity
"

# ╔═╡ 1d68c8c0-1dbc-4d8b-97ae-3db1d2b06a4f
begin
	sparsity = DataFrame(Method=Symbol[], DP=Float64[], Time=Float64[])
	for dp in 0.05:0.05:1.0
		for method in [model_standard, model_dict, model_index, model_incremental, model_sparse]
			t = @timed method(create_test(5, 20, 10, 20; demandprob=dp)...)
			push!(sparsity,(Symbol(method), dp, t.time))
		end
	end
end

# ╔═╡ b5dbba7e-6e57-49b8-b277-66e9421fa38b
sparsity

# ╔═╡ b9e552e8-d10b-40f8-a13c-75919c99563f
plot(sparsity, x=:DP, y=:Time, color=:Method, Geom.point, Geom.line)

# ╔═╡ deefc30f-4846-49db-8ce8-69b4aec14924
begin
	large = DataFrame(Method=Symbol[], nc=Int[], vars=Int[], Time=Float64[])
	for nc in 500:500:5000
		for method in [model_incremental, model_sparse]
			t = @timed method(create_test(nf, nc, np, nt)...)
			push!(large,(Symbol(method), nc, num_variables(t.value), t.time))
		end
	end
end

# ╔═╡ a6b7741f-b02d-43c2-bc10-0d1a6dbd12e2
large

# ╔═╡ d233df91-10cf-4799-b7ed-9db7e6bada8a
plot(large, x=:vars, y=:Time, color=:Method, Geom.point, Geom.line)

# ╔═╡ Cell order:
# ╟─9150eed0-89e1-11ec-2363-1d1d3d46c3ff
# ╟─93dce568-6cac-4c62-bd7c-7e33edaacd8d
# ╟─dfeae97f-76bc-49d8-ad72-bee061af7cd4
# ╟─6890dae5-48de-4552-bb51-1dedd0405031
# ╠═10de4874-b081-4e7e-a4d2-14eb3d44dd24
# ╠═3196b821-559d-418c-9026-32b6af86f4f5
# ╟─3621ab6a-1c9b-4239-b762-089959ed011c
# ╠═408e9db0-5528-48ef-85f6-65d33ab855a3
# ╠═a78b435c-4716-40a4-a249-6f6b4067d1c3
# ╠═11e9233a-d518-4731-b677-7127bde16a8f
# ╠═1228a399-f27a-4710-9090-7cf5bc473f86
# ╠═0a87d15d-3c6c-411d-97cc-75a7cd8c21c1
# ╠═e5182068-4bd7-41cc-b313-16b083735b9d
# ╠═5dbb16da-798a-4eed-92f9-2b5d01f597c2
# ╠═fe7ec5c3-e41c-4b6e-9938-72e5b342157e
# ╠═09d44792-82de-4b2a-9cbd-605d243dab80
# ╠═759cb8ed-5d23-41d9-90cd-d734fea98c0b
# ╠═a17d8b7e-c02e-41b3-bbdf-d8dc018022c4
# ╠═10bbfb4d-ca07-4d4f-9c07-9e805b8744bb
# ╠═80d8a95d-61a3-41f7-bf2a-bf2e26221582
# ╠═0041a12e-1dd8-48a5-b44b-7fb8ba5dfbb2
# ╟─084f9445-27cd-4a36-b031-42b54f934ec8
# ╠═c49a3599-65fd-442b-b5c9-625b87e05efa
# ╠═3881bb13-7ab7-4b52-bd35-5a9e9d6bce29
# ╠═3bf1a58c-72db-4120-9b64-71a83d65bf87
# ╟─67903213-e5e2-4c56-ab32-2c93c8092830
# ╠═1d68c8c0-1dbc-4d8b-97ae-3db1d2b06a4f
# ╠═b5dbba7e-6e57-49b8-b277-66e9421fa38b
# ╠═b9e552e8-d10b-40f8-a13c-75919c99563f
# ╠═deefc30f-4846-49db-8ce8-69b4aec14924
# ╠═a6b7741f-b02d-43c2-bc10-0d1a6dbd12e2
# ╠═d233df91-10cf-4799-b7ed-9db7e6bada8a
