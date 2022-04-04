function variable_name(var::String, index)
    return var * "[" * join(index, ", ") * "]"
end

"""
    make_filter_fun(c, pos)

Return function to use for filtering depending on the type and value of `c` 
to apply at position `pos`
"""
make_filter_fun(c, pos) = x -> x[pos] == c
make_filter_fun(c::Base.Fix2, pos) = x -> c(x[pos])
make_filter_fun(c::Function, pos) = x -> c(x[pos])
make_filter_fun(c::Colon, pos) = x -> true


make_filter_fun(c) = x -> x == c
make_filter_fun(c::Base.Fix2) = x -> c(x)
make_filter_fun(c::Function) = x -> c(x)
make_filter_fun(c::Colon) = x -> true
make_filter_fun(c::UnitRange) = x -> (x ≥ c.start && x ≤ c.stop)

"""
	recursive_filter(fs, data)
Filter `data` recursively with functions `fs`
"""
function recursive_filter(fs, data)
    (f, rest) = Iterators.peel(fs)
    if isempty(rest)
        return filter(f, data)
    else
        return recursive_filter(rest, filter(f, data))
    end
end


"""
    indices_fun(some_tuple)

Return functions to be used for filtering from a tuple following the format
supported by `make_filter_fun`
"""
function indices_fun(some_tuple)
    (make_filter_fun(v, pos) for (pos, v) in enumerate(some_tuple))
end

"""
    _select_rowwise(a, pattern) 

Filter iterable data a by tuple `pattern` by row (slow)
"""
function _select_rowwise(a, pattern)
    filter(x -> reduce(&, f(x) for f in indices_fun(pattern)), a)
end


"""
    _select_colwise(a, pattern) 

Filter iterable data a by tuple `pattern` by column (recursively)
"""
function _select_colwise(a, pattern)
    recursive_filter(indices_fun(pattern), a)
end

"""
    _select_gen(a, pattern)

Filter iterable data `a` by tuple `pattern` by row, using generated function for speed.
See more straight-forward implementations `_select_rowwise` and `_select_colwise` for reference.   
"""
function _select_gen(a, pattern)
    filter(x -> _select_generated(pattern, x), a)
end

"""
    _select_gen_perm(a, pattern, perm)
Filter iterable `data` byt tuple `pattern` by row using generated function that permutes the sequence of
evaluation by the permutation tuple `perm` for improved control as this can give performance advantages, 
depending on the uniqueness of the search pattern and cost of function evaluation.

## Example

```
a = vcat(repeat([("volvo", 1988, "red"), ], 99), ("bmw", 1989, "green"))
pat = (contains("w"), 1989, "green")
_select_gen_perm(a, pat, (1,2,3)) # like _select_gen(a, pat), slower
_select_gen_perm(a, pat, (3,2,1)) # faster
```

"""
function _select_gen_perm(a, pattern, perm)
    p = Permutation(perm)
    filter(x -> _select_gen_permute(pattern, x, p), a)
end

"""
    _select_generated(pat,x,::Val{N}) where N

Compose function from pattern `pat` to filter entire tuple at once, see `_select_rowwise` for reference.
"""
_select_generated(pat, x) = _select_generated(pat, x, Val(length(pat)))

@generated function _select_generated(pat, x, ::Val{N}) where {N}
    ex = :(true)
    for i = 1:N
        ex = :($ex && make_filter_fun(pat[$i])(x[$i]))
    end
    return :($ex)
end

_select_gen_permute(pat, x, permutation) =
    _select_gen_permute(pat, x, permutation, Val(length(pat)))

"""
    Permutation{N,K}
Encode permutation as number of elements to permute `N` and number in sequence of permutations `K`
to use for dispatch.
"""
struct Permutation{N,K} end
Permutation(t::Tuple) = Permutation{length(t),_encode_permutation(t)}()

"""
    _encode_permutation(permutation)

Return integer encoding the `permutation` (as base N)
"""
# encode_permutation(permutation) = sum((permutation .- 1) .* _base_factors(Val(length(permutation))))
@generated function _encode_permutation(permutation::NTuple{N,M}) where {N,M}
    s = :(0)
    if big(N + 1)^(N + 1) > typemax(Int) # Int64 overflows at N=16
        N = big(N)
    end
    for i = 1:N
        bf = N^(N - i)
        s = :($s + (permutation[$i] - 1) * $bf)
    end
    return s
end

"""
    _decode_permutation(N, K)
Return decoded permutation from `N` (base) and `K` (number)
"""

function _decode_permutation(N, K)
    perm = Int[]
    base_factors = _base_factors(Val(N))
    tmp = K
    for i = 1:N
        p = div(tmp, base_factors[i])
        tmp -= p * base_factors[i]
        push!(perm, p + 1)
    end
    return tuple(perm...)
end

@generated function _base_factors(::Val{N}) where {N}
    base_factors = []
    if N > 15 # Int64 overflows at N=16
        N = big(N)
    end
    for i = N:-1:1
        push!(base_factors, N^(i - 1))
    end
    ex = :($base_factors)
    return ex
end


@generated function _select_gen_permute(pat, x, ::Permutation{N,K}) where {N,K}
    ex = :(true)
    fs = []
    for i = 1:N
        push!(fs, :(make_filter_fun(pat[$i])(x[$i])))
    end
    perm = _decode_permutation(N, K)
    for i = 1:N
        p_i = perm[i]
        ex = :($ex && $(fs[p_i]))
    end
    return :($ex)
end

"""
    select(dict, indices)
Return subset of `dict` matching selection defined by indices
"""
select(dict, indices) = _select_gen(dict, indices)
select(dict, indices, permutation) = _select_gen_perm(dict, indices, permutation)
function select(dict, sh_pat::NamedTuple, names)
    pat, perm = expand_shorthand(sh_pat, names)
    select(dict, pat, perm)
end
select(dict::Dictionary, indices) = getindices(dict, select(keys(dict), indices))
select(dict, f::Function) = filter(f, dict)
kselect(sa::SparseVarArray, sh_pat::NamedTuple) =
    select(keys(sa.data), sh_pat, get_index_names(sa))
select(sa::SparseVarArray, sh_pat::NamedTuple) =
    Dictionaries.getindices(sa, kselect(sa, sh_pat))

select_test(dict, indices, cache) =
    cache ? _select_cached(dict, indices) : _select_gen(keys(dict), indices)


function _select_cached(sa, pat)
    indices = Tuple(i for (i, v) in enumerate(pat) if v !== Colon())
    vals = Tuple(v for v in pat if v !== Colon())

    if !(indices in keys(sa.index_cache))
        index = Dict()
        for v in keys(sa)
            vred = Tuple(val for (i, val) in enumerate(v) if i in indices)
            if !(vred in keys(index))
                index[vred] = []
            end
            push!(index[vred], v)
        end
        sa.index_cache[indices] = index
    end
    return get(sa.index_cache[indices], vals, [])
end

function permfromnames(names::NamedTuple, patnames)
    perm = (names[i] for i in patnames)
    rest = setdiff((1:length(names)), perm)
    return (perm..., rest...)
end

function expand_shorthand(sh_pat, names)
    pat = []
    for n in propertynames(names)
        if haskey(sh_pat, n)
            push!(pat, sh_pat[n])
        else
            push!(pat, x -> true)
        end
    end
    perm = permfromnames(names, propertynames(sh_pat))
    return tuple(pat...), perm
end

"""
    isfixed(t)
Return false for functions, wildcards and ranges, true for all other types
Works on types because it is used in generated function
"""
isfixed(t) = true
isfixed(::Type{T} where {T<:Function}) = false
isfixed(::Type{T} where {T<:UnitRange}) = false
iscolon(t) = false
iscolon(::Type{T} where {T<:Colon}) = true


@generated function _getindex(sa::AbstractSparseArray{T,N}, tpl::Tuple) where {T,N}
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
        return :(get(_data(sa), tpl, zero(T)))
    elseif !slice
        return :(retval = select(_data(sa), tpl); length(retval) > 0 ? retval : zero(T))
    else    # Return selection or zero if empty to avoid reduction of empty iterate
        return :(retval = _select_var(sa, tpl); length(retval) > 0 ? retval : zero(T))
    end
end

_select_var(sa, tpl) = getindices(_data(sa), select_test(sa, tpl, true))
