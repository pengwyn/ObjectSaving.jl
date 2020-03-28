module ObjectSaving


export OBJECT_DICT,
    ShouldConvertToDict,
    ParseFromDict,
    Empty

##########################################
# * Conversion to Dict
#----------------------------------------

mutable struct OBJECT_DICT# <: Associative{Symbol,Any}
    object_type_name::String
    dict::Dict{Symbol,Any}
end

ShouldConvertToDict(::Any) = false
MaybeConvertToDict(obj) = ShouldConvertToDict(obj) ? ConvertToDict(obj) : obj
function ConvertToDict(obj::Any, ignore_fields::Vector{Symbol}=Symbol[])
    # buf = IOBuffer()
    # Base.show_datatype(buf, typeof(obj))
    # type_str = String(take!(buf))
    type_str = sprint(Base.show_datatype, typeof(obj))

    dict = Dict()
    for fname in setdiff(fieldnames(typeof(obj)), ignore_fields)
        val = getfield(obj, fname)

        val = MaybeConvertToDict(val)

        dict[fname] = val
    end

    return OBJECT_DICT(type_str, dict)
end

##########################################
# * Conversion from Dict
#----------------------------------------

ParseFromDict(obj::Any, keep_on_error=false) = obj

function ParseFromDict(obj_dict::OBJECT_DICT, keep_on_error=false)
    thetype = Main.eval(Meta.parse(obj_dict.object_type_name))
    @assert thetype isa Type

    new_dict = Dict()
    for (key,val) in obj_dict.dict
        new_dict[key] = ParseFromDict(val, keep_on_error)
    end

    local obj
    try
        obj = CreateObjectFromDict(thetype, new_dict)
    catch exc
        exc isa InterruptException && rethrow()

        try
            obj = CreateObjectFromDict(thetype, new_dict)
        catch exc

            if keep_on_error
                @warn "Got an error with exception: $exc"
                obj = obj_dict
            else
                rethrow()
            end
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

            if ftype == Any
                push!(args, nothing)
            elseif hasmethod(zero, Tuple{Type{ftype}})
                push!(args, zero(ftype))
            elseif hasmethod(Empty, Tuple{Type{ftype}})
                push!(args, Empty(ftype))
            elseif hasmethod(ftype, Tuple{})
                push!(args, ftype())
            else
                @warn "No default func for $ftype. Trying 0."
                push!(args, 0)
            end
        end
    end

    local obj
    try
        obj = T(args...)
    catch exc
        if exc isa MethodError
            T2 = T.name.wrapper
            # while T2 isa UnionAll
            #     T2 = T2.body
            # end

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
ShouldConvertToDict(::Function) = true
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

function ParseFromDict(obj::CONVERTED_DICT, keep_on_error=false)
    map(collect(obj.dict)) do pair
        key,val = pair
        key => ParseFromDict(val, keep_on_error)
    end |> Dict
end

################################################################################

struct CONVERTED_TUPLE
    tuple::Tuple
end
ShouldConvertToDict(tuple::Tuple) = any(ShouldConvertToDict.(tuple))
function ConvertToDict(tuple::Tuple)
    new_tuple = MaybeConvertToDict.(tuple)

    CONVERTED_TUPLE(new_tuple)
end

ParseFromDict(obj::CONVERTED_TUPLE, keep_on_error=false) = ParseFromDict.(obj.tuple, keep_on_error)

################################################################################

struct CONVERTED_ARRAY
    array::Array
end
ShouldConvertToDict(array::Array) = any(ShouldConvertToDict.(array))
function ConvertToDict(array::Array)
    new_array = MaybeConvertToDict.(array)

    CONVERTED_ARRAY(new_array)
end

ParseFromDict(obj::CONVERTED_ARRAY, keep_on_error=false) = ParseFromDict.(obj.array, keep_on_error)

end # module