module ObjectSaving


export OBJECT_DICT,
    ShouldConvertToDict,
    ConvertToDict,
    ParseFromDict,
    Empty

##########################################
# * Conversion to Dict
#----------------------------------------

mutable struct TYPE_INFO
    type_name::Symbol
    type_params::Tuple
end

mutable struct OBJECT_DICT# <: Associative{Symbol,Any}
    object_type
    dict::Dict{Symbol,Any}
end

ShouldConvertToDict(::Any) = false
MaybeConvertToDict(obj) = ShouldConvertToDict(obj) ? ConvertToDict(obj) : obj
function ConvertToDict(obj::Any, ignore_fields::Vector{Symbol}=Symbol[])
    # buf = IOBuffer()
    # Base.show_datatype(buf, typeof(obj))
    # type_str = String(take!(buf))
    # type_str = sprint(Base.show_datatype, typeof(obj))

    dict = Dict()
    for fname in setdiff(fieldnames(typeof(obj)), ignore_fields)
        val = getfield(obj, fname)

        val = MaybeConvertToDict(val)

        dict[fname] = val
    end

    object_type = MaybeConvertToDict(typeof(obj))
    return OBJECT_DICT(object_type, dict)
end

function ConvertToDict(T::Type)
    type_name = nameof(T)
    type_params = filter(x -> !(x isa TypeVar),
                             tuple(Base.unwrap_unionall(T).parameters...))
    type_params = MaybeConvertToDict.(type_params)
    return TYPE_INFO(type_name, type_params)
end

##########################################
# * Conversion from Dict
#----------------------------------------

ParseFromTypeInfo(T::Type ; kwds...) = T
ParseFromTypeInfo(sym::Symbol ; kwds...) = sym
ParseFromTypeInfo(N::Integer ; kwds...) = N
function ParseFromTypeInfo(type_info::TYPE_INFO ; eval_module=Main)
    try
        thetype = getproperty(eval_module, type_info.type_name)
        if(type_info.type_params != ())
            params = ParseFromTypeInfo.(type_info.type_params ; eval_module)
            thetype{params...}
        else
            thetype
        end
    catch exc
        @error "Unable to generate type for object" type_info.type_name type_info.type_params eval_module
        rethrow()
    end
end

# Default keep_on_error
ParseFromDict(obj ; kwds...) = ParseFromDict(obj, false ; kwds...)
# Fallback
ParseFromDict(obj, keep_on_error ; kwds...) = obj

function ParseFromDict(obj_dict::OBJECT_DICT, keep_on_error ; eval_module=Main)
    thetype = ParseFromTypeInfo(obj_dict.object_type ; eval_module)
    @assert thetype isa Type

    new_dict = Dict()
    for (key,val) in obj_dict.dict
        new_dict[key] = ParseFromDict(val, keep_on_error ; eval_module)
    end

    local obj
    try
        obj = CreateObjectFromDict(thetype, new_dict)
    catch exc
        exc isa InterruptException && rethrow()

        if keep_on_error
            @warn "Got an error with exception: $exc"
            obj = obj_dict
        else
            rethrow()
        end
    end
        
    return obj
end

FieldNames(T::DataType) = fieldnames(T)
FieldNames(T::UnionAll) = fieldnames(T.body)

FieldType(T::DataType, n) = fieldtype(T, n)
FieldType(T::UnionAll, n) = fieldtype(T.body, n)

function CreateObjectFromDict(T::Type, dict::Dict)
    if Set(keys(dict)) == Set(FieldNames(T))
        CreateObjectFromDict_AllArgs(T, dict)
    elseif (T isa DataType) && T.mutable && (hasmethod(T, Tuple{}) || hasmethod(zero, Tuple{T}))
        if hasmethod(T, Tuple{})
            obj = T()
        elseif hasmethod(zero, Tuple{T})
            obj = zero(T)
        else
            error("dsfkjsdf")
        end

        for (field,val) in dict
            setfield!(obj, field, val)
        end
        return obj
    else
        obj = CreateObjectFromDict_AllArgs(T, dict)

        return obj
    end
end

Empty(::Type{T}) where {T <: Matrix} = T(undef,0,0)

function CreateObjectFromDict_AllArgs(T::Type, dict::Dict)
    #@assert isempty(setdiff(keys(dict), FieldNames(T)))
    for key in setdiff(keys(dict), FieldNames(T))
        @warn "Don't know about $key for type $T, going to ignore it."
    end

    args = []
    for (n,fname) in enumerate(FieldNames(T))
        if fname in keys(dict)
            push!(args, dict[fname])
        else
            ftype = FieldType(T,n)

            # Search for a defaults dictionary from my AutoParameters package
            sym = Symbol(:AUTOPARM_, nameof(T), :_defaults)
            @show T
            if isdefined(parentmodule(T), sym)
                defaults = getproperty(parentmodule(T), sym)
                if fname ∈ keys(defaults)
                    push!(args, defaults[fname]())
                else
                    if ftype == Any
                        push!(args, nothing)
                    elseif hasmethod(zero, Tuple{Type{ftype}})
                        push!(args, zero(ftype))
                    elseif hasmethod(Empty, Tuple{Type{ftype}})
                        push!(args, Empty(ftype))
                    elseif hasmethod(ftype, Tuple{})
                        push!(args, ftype())
                    else
                        @warn "No default func for $fname of type $ftype. Trying 0."
                        push!(args, 0)
                    end
                end
            end
        end
    end

    local obj
    try
        obj = T(args...)
    catch exc
        if exc isa MethodError
            # T2 = T.name.wrapper
            # while T2 isa UnionAll
            #     T2 = T2.body
            # end
            T2 = Base.unwrap_unionall(T).name.wrapper

            @warn "Wasn't able to instantiate a $T object, try a $T2."

            if T2 !== T
                obj = T2(args...)
            else
                rethrow()
            end
        else
            rethrow()
        end
    end

    return obj
end

################################
# * Special (but generic) cases
#------------------------------

struct FAKE_FUNC <: Function
    name::String
end
ShouldConvertToDict(x::Function) = !(x isa FAKE_FUNC)
ConvertToDict(func::Function) = FAKE_FUNC(string(func))

################################################################################

struct CONVERTED_DICT
    dict::Dict
end
ShouldConvertToDict(dict::Dict) = any(ShouldConvertToDict(z) for z in values(dict))
function ConvertToDict(dict::Dict)
    new_dict = Dict()
    for (key,val) in dict
        val = MaybeConvertToDict(val)
        
        new_dict[key] = val
    end

    CONVERTED_DICT(new_dict)
end

function ParseFromDict(obj::CONVERTED_DICT, keep_on_error ; kwds...)
    map(collect(obj.dict)) do pair
        key,val = pair
        key => ParseFromDict(val, keep_on_error)
    end |> Dict
end

################################################################################

const ITER_types = Union{Tuple,Array}
struct CONVERTED_ITER
    itr::ITER_types
end
ShouldConvertToDict(itr::ITER_types) = any(ShouldConvertToDict, itr)
ConvertToDict(itr::ITER_types) = CONVERTED_ITER(MaybeConvertToDict.(itr))

ParseFromDict(obj::CONVERTED_ITER, keep_on_error ; kwds...) = ParseFromDict.(obj.itr, keep_on_error ; kwds...)


###############################################################################

struct CONVERTED_TUPLE_TYPE
    parameters
end
ShouldConvertToDict(T::Type{<:Tuple}) = any(ShouldConvertToDict, T.parameters)
ConvertToDict(T::Type{<:Tuple}) = CONVERTED_TUPLE_TYPE(MaybeConvertToDict.(T.parameters))

ParseFromTypeInfo(type_info::CONVERTED_TUPLE_TYPE ; eval_module=Main) = Tuple{ParseFromTypeInfo.(type_info.parameters ; eval_module)...}

end # module
