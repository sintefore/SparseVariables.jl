"""
    TranslateVarArray{V,N,T}

    Structure for holding an optimization variable with a sparse structure with extra indexing
    Translate from abstract types to type stable id for performance in dictionaries
"""
struct TranslateVarArray{V<:AbstractVariableRef,N,T} <: AbstractSparseArray{V,N}
    f::Function
    data::Dictionary{T,V}
    index_names::NamedTuple
    index_cache::Vector{Dictionary}
end

"""
    translate
    Function to translate from type instance to type stable (e.g. Int or String) for performance in dictionaries.
    Extend this for types (e.g. Node or Link types) to improve performance
"""
function translate(x)
    return x
end
function translate(::Type{T}) where {T}
    return T
end

_data(sa::TranslateVarArray) = sa.data

"""
    insertvar!(var::IndexedVarArray{V,N,T}, index...)

Insert a new variable with the given index only after checking if keys are valid and not already defined.
"""
function insertvar!(var::TranslateVarArray{V,N,T}, index...) where {V,N,T}
    return insertvar!(var, SafeInsert(), index...)
end
function insertvar!(
    var::TranslateVarArray{V,N,T},
    ::SafeInsert = SafeInsert(),
    index...,
) where {V,N,T}
    tindex = translate.(index)
    !valid_index(var, index) && throw(BoundsError(var, index))# "Not a valid index for $(var.name): $index"g
    already_defined(var, tindex) && error("$index already defined for array")
    var[tindex] = var.f(tindex...)
    clear_cache!(var)
    return var[tindex]
end

# Extension for standard JuMP macros
function Containers.container(
    f::Function,
    indices,
    D::Type{TranslateVarArray},
    names,
)
    iva_names = NamedTuple{tuple(names...)}(indices.prod.iterators)
    T = Tuple{translate.(eltype.(indices.prod.iterators))...}
    N = length(names)
    V = first(Base.return_types(f))
    return TranslateVarArray{V,N,T}(
        f,
        Dictionary{T,V}(),
        iva_names,
        Vector{Dictionary}(undef, 2^N),
    )
end

@generated function _getindex(
    sa::TranslateVarArray{T,N},
    tpl::Tuple,
) where {T,N}
    lookup = true
    slice = true
    for t in fieldtypes(tpl)
        if !isfixed(t)
            lookup = false
            if !iscolon(t)
                slice = false
            end
        end
    end

    if lookup
        return :(get(_data(sa), translate.(tpl), zero(T)))
    elseif !slice
        return :(retval = select(_data(sa), translate.(tpl));
        length(retval) > 0 ? retval : zero(T))
    else    # Return selection or zero if empty to avoid reduction of empty iterate
        return :(retval = _select_var(sa, translate.(tpl));
        length(retval) > 0 ? retval : zero(T))
    end
end

function Base.firstindex(sa::TranslateVarArray, d)
    return first(sort(sa.index_names[d]))
end
function Base.lastindex(sa::TranslateVarArray, d)
    return last(sort(sa.index_names[d]))
end

function build_cache!(cache, pat, sa::TranslateVarArray{V,N,T}) where {V,N,T}
    if isempty(cache)
        for v in keys(sa)
            vred = _active(v, translate.(pat))
            nv = get!(cache, vred, T[])
            push!(nv, v)
        end
    end
    return cache
end

function _select_cached(sa::TranslateVarArray{V,N,T}, pat) where {V,N,T}
    # TODO: Benchmark to find good cutoff-value for caching
    # TODO: Return same type for type stability
    tpat = translate.(pat)
    length(_data(sa)) < 100 && return _select_gen(keys(_data(sa)), tpat)
    cache =
        _getcache(sa, tpat)::Dictionary{_decode_nonslices(sa, tpat),Vector{T}}
    build_cache!(cache, tpat, sa)
    vals = _dropslices_gen(tpat)
    return get!(cache, vals, T[])
end
