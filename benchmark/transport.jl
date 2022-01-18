#  Benchmark test problem for a large scale transportation problem
import Pkg;
Pkg.activate(@__DIR__)

using JuMP
using JuMPUtils
# using GLPK
using IndexedTables

struct ProblemParam
    factories
    customers
    products
    periods

    canproduce
    prodcap
    demand
    flowcap
end



function ProblemParam(nf, nc, np, nt)

    #factories = ["f$i" for i in 1:nf]
    #customers = ["c$i" for i in 1:nc]
    #products = ["p$i" for i in 1:np]
    #periods = ["t$i" for i in 1:nt]

    factories = [i for i in 1:nf]
    customers = [i for i in 1:nc]
    products = [i for i in 1:np]
    periods = [i for i in 1:nt]

    prodprob = 0.2
    demandprob = 0.05
    flowprob = 0.8

    
    canproduce = Dict( (f,p) => true for f in factories, p in products if rand() < prodprob)
    prodcap = Dict( (f,t) => rand() * 100 for f in factories, t in periods)
    demand = Dict( (c,p,t) => rand() for c in customers, p in products, t  in periods if rand() < demandprob)
    flowcap = Dict( (f,c) => rand() * 20 for f in factories, c in customers if rand() < flowprob)

    return ProblemParam(factories, customers, products, periods, canproduce, prodcap, demand, flowcap)
end

canproduce(pp, f, p) = get(pp.canproduce, (f,p), false)

function create_vars_dense(m,pp)
    @variable(m, flow[pp.factories,pp.customers,pp.products,pp.periods] ≥ 0 )
end

function create_vars_dict(m, pp)
    flow = Dict()
    for (c,p,t) in keys(pp.demand) 
        for f in pp.factories 
            if canproduce(pp,f,p)
                v = @variable(m, lower_bound = 0)
                flow[f,c,p,t] = v
                set_name(v,"flow[$f,$c,$p,$t]")
            end
        end
    end
    m[:flow] = flow
end

function create_constraints_dict(m, pp)

    flow = m[:flow]
    
    # Production capacity
    for (f,t) in keys(pp.prodcap)
        @constraint(m, sum(flow[(f,c,p,t)] for (ff,c,p,tt) in keys(flow) if ff == f && tt == t) ≤ pp.prodcap[f,t])
    end

    # Customer demand
    for (c,p,t) in keys(pp.demand)
        @constraint(m, sum(flow[(f,c,p,t)] for (f,cc,pp,tt) in keys(flow) if cc == c && pp ==p && tt == t) ≤ pp.demand[c,p,t])
    end

    # Transport capacity
    for (f,c) in keys(pp.flowcap), t in pp.periods
        @constraint(m, sum(flow[f,c,p,t] for (ff,cc,p,tt) in keys(flow) if ff == f && cc == c && tt == t)  ≤ pp.flowcap[f,c])
    end

end

function create_constraints_dict_filter(m, pp)

    flow = m[:flow]
    
    # Production capacity
    for (f,t) in keys(pp.prodcap)
        @constraint(m, sum(flow[(f,c,p,t)] for (f,c,p,t) in filter(k -> k[1] == f && k[4] == t, keys(flow))) ≤ pp.prodcap[f,t])
    end

    # Customer demand
    for (c,p,t) in keys(pp.demand)
        @constraint(m, sum(flow[(f,c,p,t)] for (f,c,p,t) in filter(k -> k[2] == c && k[3] == p && k[4] == t, keys(flow))) ≤ pp.demand[c,p,t])
    end

    # Transport capacity
    for (f,c) in keys(pp.flowcap), t in pp.periods
        @constraint(m, sum(flow[f,c,p,t] for (f,c,p,t) in filter(k -> k[1] == f && k[2] == c && k[4] == t, keys(flow)))  ≤ pp.flowcap[f,c])
    end

end

function create_constraints_dict_alt(m, pp)

    flow = m[:flow]
    
    pcap = Dict()
    for (f,t) in keys(pp.prodcap)
        pcap[f,t] = AffExpr()
    end
    cdem  = Dict()
    for (c,p,t) in keys(pp.demand)
        cdem[c,p,t] = AffExpr()
    end
    tcap = Dict()
    for (f,c) in keys(pp.flowcap), t in pp.periods
        tcap[f,c,t] = AffExpr()
    end

    for (f,c,p,t) in keys(flow)
        var = flow[f,c,p,t]
        if (f,t) in keys(pp.prodcap)
            pcap[f,t] += var
        end
        if (c,p,t) in keys(pp.demand)
            cdem[c,p,t] += var
        end
        if (f,c) in keys(pp.flowcap)
            tcap[f,c,t] += var
        end
    end

    # Production capacity
    for (f,t) in keys(pp.prodcap)
        @constraint(m, pcap[f,t] ≤ pp.prodcap[f,t])
    end

    # Customer demand
    for (c,p,t) in keys(pp.demand)
        @constraint(m, cdem[c,p,t] ≤ pp.demand[c,p,t])
    end

    # Transport capacity
    for (f,c) in keys(pp.flowcap), t in pp.periods
        @constraint(m, tcap[f,c,t] ≤ pp.flowcap[f,c])
    end

end


function create_vars_sparse(m, pp)

    @sparsevariable(m, flow[factory, customer, product, period])
    for (c,p,t) in keys(pp.demand) 
        for f in pp.factories 
            if canproduce(pp,f,p) 
                insertvar!(flow, f, c, p, t)
            end
        end
    end
end


function create_constraints_sparse_slice(m, pp)

    flow = m[:flow]
    
    # Production capacity
    for (f,t) in keys(pp.prodcap)
        @constraint(m, sum(flow[f,:,:,t]) ≤ pp.prodcap[f,t])
    end

    # Customer demand
    for (c,p,t) in keys(pp.demand)
        @constraint(m, sum(flow[:,c,p,t]) ≤ pp.demand[c,p,t])
    end

    # Transport capacity
    for (f,c) in keys(pp.flowcap), t in pp.periods
        @constraint(m, sum(flow[f,c,:,t]) ≤ pp.flowcap[f,c])
    end

end

function create_constraints_sparse_select(m, pp)

    flow = m[:flow]
    
    # Production capacity
    for (f,t) in keys(pp.prodcap)
        @constraint(m, sum(flow[f,c,p,t] for (f,c,p,t) in JuMPUtils.select(flow, f,:,:,t; cache=false)) ≤ pp.prodcap[f,t])
    end

    # Customer demand
    for (c,p,t) in keys(pp.demand)
        @constraint(m, sum(flow[f,p,c,t] for (f,c,p,t) in JuMPUtils.select(flow, :,c,p,t; cache=false)) ≤ pp.demand[c,p,t])
    end

    # Transport capacity
    for (f,c) in keys(pp.flowcap), t in pp.periods
        @constraint(m, sum(flow[f,p,c,t] for (f,p,c,t) in JuMPUtils.select(flow, f,c,:,t; cache=false)) ≤ pp.flowcap[f,c])
    end

end

function create_constraints_sparse_cache(m, pp)

    flow = m[:flow]
    
    # Production capacity
    for (f,t) in keys(pp.prodcap)
        @constraint(m, sum(flow[f,c,p,t] for (f,c,p,t) in JuMPUtils.select(flow, f,:,:,t)) ≤ pp.prodcap[f,t])
    end

    # Customer demand
    for (c,p,t) in keys(pp.demand)
        @constraint(m, sum(flow[f,p,c,t] for (f,c,p,t) in JuMPUtils.select(flow, :,c,p,t)) ≤ pp.demand[c,p,t])
    end

    # Transport capacity
    for (f,c) in keys(pp.flowcap), t in pp.periods
        @constraint(m, sum(flow[f,p,c,t] for (f,p,c,t) in JuMPUtils.select(flow, f,c,:,t)) ≤ pp.flowcap[f,c])
    end

end

function create_constraints_sparse_cache_alt(m, pp)

    flow = m[:flow]
    
    # Production capacity
    for (f,t) in keys(pp.prodcap)
        idx = JuMPUtils.select(flow, f,:,:,t)
        if !isempty(idx)
            @constraint(m, sum(flow[f,c,p,t] for (f,c,p,t) in idx) ≤ pp.prodcap[f,t])
        end
    end

    # Customer demand
    for (c,p,t) in keys(pp.demand)
        idx = JuMPUtils.select(flow, :,c,p,t)
        if !isempty(idx)
            @constraint(m, sum(flow[f,p,c,t] for (f,c,p,t) in idx) ≤ pp.demand[c,p,t])
        end
    end

    # Transport capacity
    for (f,c) in keys(pp.flowcap), t in pp.periods
        idx = JuMPUtils.select(flow, f,c,:,t)
        if !isempty(idx)
            @constraint(m, sum(flow[f,p,c,t] for (f,p,c,t) in idx) ≤ pp.flowcap[f,c])
        end
    end

end


function create_vars_indexedtable(m, pp)

    F = Int16[]
    C = Int16[]
    P = Int16[]
    T = Int16[]
    V = VariableRef[]
    for f in pp.factories     
        for (c,p,t) in keys(pp.demand) 
            if canproduce(pp,f,p) 
                v = @variable(m, lower_bound=0)
                set_name(v, "flow[$f,$c,$p,$t]")
                push!(F, f)
                push!(C, c)
                push!(P, p)
                push!(T, t)
                push!(V, v)
            end
        end
    end
    var_table = table(F, C, P, T, V, names=[:factory, :customer, :product, :period, :var], pkey=[:factory, :customer, :product, :period])
    m[:flow] = var_table
end

function create_constraints_indexedtable(m, pp)

    flow = m[:flow]
    
    # Production capacity
    pc_table = groupby(collect, flow, (:factory, :product), select=:var)
    for r in rows(pc_table)
        if (r.factory, r.product) in keys(pp.prodcap)
            @constraint(m, (ismissing(r.collect) ? 0.0 : sum(r.collect)) ≤ pp.prodcap[r.factory, r.product])
        end
    end

    # Customer demand
    cpp_table = groupby(collect, flow, (:customer, :product, :period), select=:var)
    for r in rows(cpp_table)
        if (r.customer, r.product, r.period) in keys(pp.demand)
            @constraint(m, (ismissing(r.collect) ? 0.0 : sum(r.collect)) ≤ pp.demand[r.customer, r.product, r.period])
        end
    end

    # Transport capacity
    fc_table = groupby(collect, flow, (:factory, :customer, :period), select=:var) 
    for r in rows(fc_table)
        if (r.factory, r.customer) in keys(pp.flowcap)
            @constraint(m, (ismissing(r.collect) ? 0.0 : sum(r.collect)) ≤ pp.flowcap[r.factory, r.customer])
        end
    end

end


function test_sparse_slice(pp)
    println("-- Test sparse array slice--")
    m = Model()
    
    t1 = @elapsed create_vars_sparse(m,pp)
    println("Variable creation: $t1 [nv=$(num_variables(m))]")

    t2 = @elapsed create_constraints_sparse_slice(m,pp)
    println("Constraint creation: $t2 [nc=$(num_constraints(m, AffExpr, MOI.LessThan{Float64}))]")
    println()
end

function test_sparse_select(pp)
    println("-- Test sparse array select --")
    m = Model()
    
    t1 = @elapsed create_vars_sparse(m,pp)
    println("Variable creation: $t1 [nv=$(num_variables(m))]")

    t2 = @elapsed create_constraints_sparse_select(m,pp)
    println("Constraint creation: $t2 [nc=$(num_constraints(m, AffExpr, MOI.LessThan{Float64}))]")
    println()
end

function test_sparse_cache(pp)
    println("-- Test sparse array with cache --")
    m = Model()
    
    t1 = @elapsed create_vars_sparse(m,pp)
    println("Variable creation: $t1 [nv=$(num_variables(m))]")

    t2 = @elapsed create_constraints_sparse_cache(m,pp)
    println("Constraint creation: $t2 [nc=$(num_constraints(m, AffExpr, MOI.LessThan{Float64}))]")
    println()
end

function test_sparse_cache_alt(pp)
    println("-- Test sparse array with cache --")
    m = Model()
    
    t1 = @elapsed create_vars_sparse(m,pp)
    println("Variable creation: $t1 [nv=$(num_variables(m))]")

    t2 = @elapsed create_constraints_sparse_cache_alt(m,pp)
    println("Constraint creation: $t2 [nc=$(num_constraints(m, AffExpr, MOI.LessThan{Float64}))]")
    println()
end

function test_dict(pp)
    println("-- Test dictionary --")
    m = Model()
    
    t1 = @elapsed create_vars_dict(m,pp)
    println("Variable creation: $t1 [nv=$(num_variables(m))]")

    t2 = @elapsed create_constraints_dict(m,pp)
    println("Constraint creation: $t2 [nc=$(num_constraints(m, AffExpr, MOI.LessThan{Float64}))]")
    println()
end

function test_dict_filter(pp)
    println("-- Test dictionary filter--")
    m = Model()
    
    t1 = @elapsed create_vars_dict(m,pp)
    println("Variable creation: $t1 [nv=$(num_variables(m))]")

    t2 = @elapsed create_constraints_dict_filter(m,pp)
    println("Constraint creation: $t2 [nc=$(num_constraints(m, AffExpr, MOI.LessThan{Float64}))]")
    println()
end


function test_dict_alt(pp)
    println("-- Test dictionary alternative --")
    m = Model()
    
    t1 = @elapsed create_vars_dict(m,pp)
    println("Variable creation: $t1 [nv=$(num_variables(m))]")

    t2 = @elapsed create_constraints_dict_alt(m,pp)
    println("Constraint creation: $t2 [nc=$(num_constraints(m, AffExpr, MOI.LessThan{Float64}))]")
    println()
end

function test_indexedtable(pp)
    println("-- Test indexed table --")
    m = Model()
    t1 = @elapsed create_vars_indexedtable(m,pp)
    println("Variable creation: $t1 [nv=$(num_variables(m))]")

    t2 = @elapsed create_constraints_indexedtable(m,pp)
    println("Constraint creation: $t2 [nc=$(num_constraints(m, AffExpr, MOI.LessThan{Float64}))]")
    println()
end


function test( pp = ProblemParam(10, 100, 20, 10))   
    #test_dict(pp)
    test_dict_filter(pp)
    test_dict_alt(pp)
    #test_sparse_slice(pp)
    test_sparse_select(pp) 
    test_sparse_cache(pp) 
    test_sparse_cache_alt(pp) 
    test_indexedtable(pp)
    return
end

test()









