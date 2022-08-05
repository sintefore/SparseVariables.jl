# Experimental sparse var array with typed indexing


"""
    IndexedVarArray{N,T}

    Structure for holding an optimization variable with a sparse structure with extra indexing
"""
struct IndexedVarArray{N,T} <: AbstractSparseArray{VariableRef,N}
    model::Model
    name
    data::Dictionary{T,VariableRef}
    index_names::NamedTuple

    index_cache::Vector{Dictionary}
end

# function IndexedVarArray{N,T}(model::Model, name::String) where {N,T}
#     dict = Dictionary{T,VariableRef}()
#     index_names = _default_index_names(N)
#     return N
#     return IndexedVarArray{N}(model, name, dict, index_names)
# end
function IndexedVarArray{N,T}(
    model::Model,
    name::String,
    indices::NamedTuple{Ns, T};
    lower_bound = 0,
    kw_args...,
) where {N,T, Ns}
    dict = Dictionary{T,VariableRef}()
    ind_names = Ns
    return model[Symbol(name)] =
        IndexedVarArray{N,T}(model, name, dict, ind_names, Vector{Dictionary}(undef, 2^N))
end


function IndexedVarArray{N,T}(
    model::Model,
    name::String,
    ind_names,
    indices::Vector{<:Tuple};
    lower_bound = 0,
    kw_args...,
) where {N,T}
    dict = Dictionary(
        indices,
        (createvar(model, name, k; lower_bound, kw_args...) for k in indices),
    )
    return model[Symbol(name)] =
        IndexedVarArray{N,T}(model, name, dict, ind_names, Vector{Dictionary}(undef, 2^N))
end


function IndexedVarArray{N,T}(
    model::Model,
    name::String,
    ind_names,
    indices::Dictionaries.Indices{<:Tuple};
    lower_bound = 0,
    kw_args...,
) where {N,T}
    return IndexedVarArray{N,T}(
        model,
        name,
        ind_names,
        collect(indices);
        lower_bound,
        kw_args...,
    )
end

function IndexedVarArray{N,T}(model::Model, name::String, ind_names) where {N,T}
    dict = Dictionary{T,VariableRef}()
    index_names = ind_names
    return IndexedVarArray{N,T}(model, name, dict, index_names, Vector{Dictionary}(undef, 2^N))
end

# function IndexedVarArray(m, n, ind_names)
#     N = length(ind_names)
#     return IndexedVarArray{N, NTuple{N,Any}}(m, n, ind_names)
# end

# function IndexedVarArray(model::Model, name::String, ind_names)
#     dict = Dictionary{NTuple{length(ind_names),Any},VariableRef}()
#     index_names = ind_names
#     return IndexedVarArray{length(ind_names),typeof((2,2,2))}(model, name ,dict, index_names, Vector{Dictionary}(undef, 2^length(ind_names)))
# end

_data(sa::IndexedVarArray) = sa.data
"""
    insertvar!(var::SparseVarArray{N}, index...; lower_bound = 0, kw_args...)

Insert a new variable with the given index. 
"""
function insertvar!(
    var::IndexedVarArray{N,T},
    index...;
    lower_bound = 0,
    kw_args...,
) where {N,T}
    var[index] = createvar(var.model, var.name, index; lower_bound, kw_args...)

    #TODO: Reactivate this later
    # If active caches, update with new variable
    # cache = _getcache(var.sa, index)
    # for ind in keys(cache)
    #     vred = Tuple(val for (i, val) in enumerate(index) if i in ind)
    #     if !(vred in keys(var.index_cache[ind]))
    #         var.index_cache[ind][vred] = []
    #     end
    #     push!(var.index_cache[ind][vred], index)
    # end
end


function _active(idx, active)
    Tuple((idx[i] for i ∈ 1:length(idx) if active[i]))
end

function _has_index(idx, active, pat)
    for (i,a) in enumerate(active)
        if a
            idx[i] != pat[i] && return false
        end
    end
    return true
end


function _select_cached(sa::IndexedVarArray{N,T}, pat) where {N,T}
    # TODO: Benchmark to find good cutoff-value for caching
    # TODO: Return same type for type stability
   length(_data(sa)) < 100 && return _select_gen(keys(_data(sa)), pat)

    cache = _getcache(sa, pat)
    active_indices = _nonslices(pat)
    vals = _dropslices(pat)
    if isempty(cache)
        for v in keys(sa)
            vred = _active(v, active_indices)
            nv = get!(cache, vred, T[])
            push!(nv, v)    
        end
    end
    return get(cache, vals, T[])
end



using LinearAlgebra
struct Dim{N} end
bin2int(v) = bin2int(v,Dim{length(v)}())
@generated function bin2int(v, ::Dim{N}) where {N}
    w = reverse([2^(i-1) for i in 1:N])
    :(dot($w,v))
end


function _nonslices(t)
    Tuple(ti != Colon() for ti in t)
end

function _dropslices(t)
    Tuple(ti for ti in t if ti != Colon())
end


@generated function _encode_nonslices(t::P) where {P}
    tf = Tuple(ti != Colon for ti in fieldtypes(P))
    i = bin2int(tf) 
    :($i)
end

function _decode_nonslices(::IndexedVarArray{N,T}, v::Integer) where {N,T}
    fts = fieldtypes(T)
    Tuple{(fts[i] for (i, c) in enumerate(last(bitstring(v),N)) if c == '1')...}
end

@generated function _decode_nonslices(::IndexedVarArray{N,T}, ::P) where {N,T,P}
    fts = fieldtypes(T)
    fts2 = fieldtypes(P)
    t = Tuple{(fts[i] for (i, v) in enumerate(fts2) if v != Colon)...}
    :($t)
end

function _getcache(sa::IndexedVarArray{N,T}, pat::P) where {N,T,P}
    t = _encode_nonslices(pat)
    try
        return sa.index_cache[t]
    catch err
        @debug err
        sa.index_cache[t] = Dictionary{_decode_nonslices(sa, t), Vector{T}}()  
    end
    return sa.index_cache[t]
end