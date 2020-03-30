# ObjectSaving.jl
Convert objects to dictionaries for compatible serialisation

Use by calling `ConvertToDict(obj)` and saving that to file. Then when loading, call `ParseFromDict(saved_dict)`.

Select which types should be converted through extending `ShouldConvertToDict(::T) = true`.

Sometimes, defining an `Empty(::Type{T})` is necessary.
