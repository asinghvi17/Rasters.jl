
const INVERT_KEYWORD = """
- `invert`: invert the mask, so that areas no missing in `with` are
    masked, and areas missing in `with` are masked.
"""

"""
    mask(A:AbstractRaster; with, missingval=missingval(A))
    mask(x; with)

Return a new array with values of `A` masked by the missing values of `with`,
or by the shape of `with`, if `with` is a geometric object.

# Arguments

- `x`: a `Raster` or `RasterStack`

# Keywords

- `with`: an `AbstractRaster`, or any GeoInterface.jl compatible objects
    or table. The coordinate reference system of the point must match `crs(A)`.
$INVERT_KEYWORD
- `missingval`: the missing value to use in the returned file.
$FILENAME_KEYWORD
$SUFFIX_KEYWORD

# Geometry keywords

These can be used when `with` is a GeoInterface.jl compatible object:

$SHAPE_KEYWORDS

# Example

Mask an unmasked AWAP layer with a masked WorldClim layer,
by first resampling the mask.

```julia
using Rasters, RasterDataSources, ArchGDAL, Plots, Dates

# Load and plot the file
awap = read(Raster(AWAP, :tmax; date=DateTime(2001, 1, 1)))
a = plot(awap; clims=(10, 45))

# Create a mask my resampling a worldclim file
wc = Raster(WorldClim{Climate}, :prec; month=1)
wc_mask = resample(wc; to=awap)

# Mask
awap_masked = mask(awap; with=wc_mask)
b = plot(awap_masked; clims=(10, 45))

savefig(a, "src/assets/api/mask_example_before.png");
savefig(b, "src/assets/api/mask_example_after.png"); nothing
# output

```

### Before `mask`:


### After `mask`:


$EXPERIMENTAL
"""
mask(x; with, kw...) = _mask(x, with; kw...)

# Geometry mask
function _mask(s::AbstractRasterSeries, with; kw...)
    B = boolmask(with; to=dims(first(s), DEFAULT_POINT_ORDER), kw...)
    return _mask(s, B)
end
function _mask(x::RasterStackOrArray, with; kw...)
    # Geometries can only have `X`/`Y`/`Z` dims so limit them here
    B = boolmask(with; to=dims(x, DEFAULT_POINT_ORDER), kw...)
    return _mask(x, B)
end
# Array mask
function _mask(A::AbstractRaster, with::AbstractRaster;
    filename=nothing, suffix=nothing, missingval=_missingval_or_missing(A), kw...
)
    missingval = ismissing(missingval) ? missing : convert(eltype(A), missingval)
    A1 = create(filename, A; suffix, missingval)
    open(A1; write=true) do a
        # The values array will be be written to A1 in `mask!`
        mask!(a; with, missingval, values=A, kw...)
    end
    return A1
end
function _mask(xs::AbstractRasterStack, with::AbstractRaster; suffix=keys(xs), kw...)
    mapargs((x, s) -> mask(x; with, suffix=s, kw...), xs, suffix)
end
function _mask(xs::AbstractRasterSeries, with::AbstractRaster; kw...)
    map(x -> mask(x; with, kw...), xs)
end

"""
    mask!(x; with, missingval=missingval(A))

Mask `A` by the missing values of `with`, or by all values outside `with` if it is a polygon.

If `with` is a polygon, creates a new array where points falling outside the polygon
have been replaced by `missingval(A)`.

Return a new array with values of `A` masked by the missing values of `with`,
or by a polygon.

# Arguments

- `x`: a `Raster` or `RasterStack`.

# Keywords

- `with`: another `AbstractRaster`, a `AbstractVector` of `Tuple` points,
    or any GeoInterface.jl `AbstractGeometry`. The coordinate reference system
    of the point must match `crs(A)`.
$INVERT_KEYWORD
- `missingval`: the missing value to write to A in masked areas,
    by default `missingval(A)`.

# Example

Mask an unmasked AWAP layer with a masked WorldClim layer,
by first resampling the mask to match the size and projection.

```julia
using Rasters, RasterDataSources, ArchGDAL, Plots, Dates

# Load and plot the file
awap = read(RasterStack(AWAP, (:tmin, :tmax); date=DateTime(2001, 1, 1)))
a = plot(awap; clims=(10, 45), c=:imola)

# Create a mask my resampling a worldclim file
wc = Raster(WorldClim{Climate}, :prec; month=1)
wc_mask = resample(wc; to=awap)

# Mask
mask!(awap; with=wc_mask)
b = plot(awap; clims=(10, 45))

savefig(a, "src/assets/api/mask_bang_example_before.png");
savefig(b, "src/assets/api/mask_bang_example_after.png"); nothing

# output

```

### Before `mask!`:


### After `mask!`:


$EXPERIMENTAL
"""
function mask! end
function mask!(xs::AbstractRasterSeries; kw...)
    foreach(x -> mask!(x; kw...), xs)
    return xs
end
mask!(xs::RasterStackOrArray; with, kw...) = _mask!(xs, with; kw...)

# Geometry mask
function _mask!(x::RasterStackOrArray, geom; kw...)
    B = boolmask(geom; to=dims(x), kw...)
    _mask!(x, B; missingval=false)
    return x
end
# Array mask
function _mask!(st::RasterStack, with::AbstractRaster; kw...)
    map(A -> mask!(A; with, kw...), st)
    return st
end

function _mask!(A::AbstractRaster, with::AbstractRaster; 
    missingval=missingval(A), 
    values=A,
    invert=false,
)
    missingval isa Nothing && _nomissingerror()
    missingval = convert(eltype(A), missingval)

    if invert
        broadcast_dims!(A, values, with) do x, w
            if (ismissing(w) || isequal(w, Rasters.missingval(with))) && 
                !(ismissing(x) || isequal(x, Rasters.missingval(values)))
                convert(eltype(A), x)
            else
                missingval
            end
        end
    else
        broadcast_dims!(A, values, with) do x, w
            if (ismissing(w) || isequal(w, Rasters.missingval(with))) || 
                (ismissing(x) || isequal(x, Rasters.missingval(values)))
                missingval
            else
                convert(eltype(A), x)
            end
        end
    end
    return rebuild(A, missingval=missingval)
end

_nomissingerror() = throw(ArgumentError("Array has no `missingval`. Pass a `missingval` keyword compatible with the type, or use `rebuild(A; missingval=somemissingval)` to set it."))

"""
    boolmask(obj::Raster; [missingval])
    boolmask(obj; [to, res, size])
    boolmask(obj::RasterStack; alllayers=true, kw...)

Create a mask array of `Bool` values, from another `Raster`.
`AbstractRasterStack` or `AbstractRasterSeries` are also accepted, if `alllayers` is `true` (the default),
a mask is taken for all layers, otherwise only the first layer is used.

The array returned from calling `boolmask` on a `AbstractRaster` is a
[`Raster`](@ref) with the same dimensions as the original array and a
`missingval` of `false`.

# Arguments

- `obj`: a [`Raster`](@ref), a GeoInterface.jl geometry, or a vector or table of geometries.

# `Raster` / `RasterStack` Keywords

$INVERT_KEYWORD
- `missingval`: The missing value of the source array, with default `missingval(raster)`.

# Keywords

- `alllayers`

$GEOM_KEYWORDS
$THREADED_KEYWORD
$PROGRESS_KEYWORD

And specifically for `shape=:polygon`:

- `boundary`: include pixels where the `:center` is inside the polygon, where
    the line `:touches` the pixel, or that are completely `:inside` inside the polygon.
    The default is `:center`.

For tabular data, feature collections and other iterables

- `collapse`: if `true`, collapse all geometry masks into a single mask. Otherwise
    return a Raster with an additional `geometry` dimension, so that each slice
    along this axis is the mask of the `geometry` opbject of each row of the
    table, feature in the feature collection, or just each geometry in the iterable.

# Example

```jldoctest
using Rasters, RasterDataSources, ArchGDAL, Plots, Dates
wc = Raster(WorldClim{Climate}, :prec; month=1)
boolmask(wc) |> plot

savefig("src/assets/api/boolmask_example.png"); nothing

# output
```

![boolmask](assets/api/boolmask_example.png)

$EXPERIMENTAL
"""
function boolmask end

function boolmask(stack::AbstractRasterStack; 
    alllayers=true, 
    invert=false,
    to=dims(stack), 
    kw...
) 
    if alllayers
        _mask_multilayer(stack, to; 
            invert, kw..., _dest_presentval=!invert, _dest_missingval=invert
        )
    else
        boolmask(layers(stack, 1); invert, kw...)
    end
end

function boolmask(series::AbstractRasterSeries; 
    alllayers=true, 
    to=first(series), 
    invert=false,
    kw...
)
    if alllayers
        _mask_multilayer(series, to; 
            invert, kw..., _dest_presentval=!invert, _dest_missingval=invert
        )
    else
        boolmask(first(series); invert, kw...)
    end
end

function boolmask(source::AbstractRaster; 
    invert::Bool=false, 
    kw...
)
    dest = _init_bools(source, BitArray, nothing; kw..., missingval=invert)
    boolmask!(dest, source; invert, kw...)
    return rebuild(dest; missingval=false)
end
# this method is used where x is a geometry
function boolmask(x; 
    to=nothing, 
    invert::Bool=false, 
    kw...
)
    if to isa Union{AbstractDimArray,AbstractDimStack,DimTuple}
        to = dims(to, DEFAULT_POINT_ORDER)
    end
    dest = _init_bools(to, BitArray, x; kw..., missingval=invert)
    boolmask!(dest, x; invert, kw...)
    return rebuild(dest; missingval=false)
end

function boolmask!(dest::AbstractRaster, src::AbstractRaster;
    missingval=_missingval_or_missing(src),
    invert=false,
)
    if invert
        broadcast_dims!(x -> isequal(x, missingval), dest, src)
    else
        broadcast_dims!(x -> !isequal(x, missingval), dest, src)
    end
end
function boolmask!(dest::AbstractRaster, geoms;
    invert=false,
    lock=nothing, 
    progress=true, 
    threaded=false, 
    allocs=_burning_allocs(dest; threaded), 
    kw...
)
    if hasdim(dest, :geometry)
        range = _geomindices(geoms)
        _run(range, threaded, progress, "Burning each geometry to a BitArray slice...") do i
            geom = _getgeom(geoms, i)
            ismissing(geom) && return nothing
            slice = view(dest, Dim{:geometry}(i))
            # We don't need locks - these are independent slices
            burn_geometry!(slice, geom; kw..., fill=!invert, allocs=_get_alloc(allocs))
            return nothing
        end
    else
        burn_geometry!(dest, geoms; kw..., allocs, lock, progress, threaded, fill=!invert)
    end
    return dest
end

"""
    missingmask(obj::Raster; kw...)
    missingmask(obj; [to, res, size, collapse])
    missingmask(obj::RasterStack; alllayers = true, kw...)

Create a mask array of `missing` and `true` values, from another `Raster`.
`AbstractRasterStack` or `AbstractRasterSeries` are also accepted, if alllayers is `true` (the default),
a mask is taken for all layers, otherwise only the first layer is used.

For [`AbstractRaster`](@ref) the default `missingval` is `missingval(A)`,
but others can be chosen manually.

The array returned from calling `missingmask` on a `AbstractRaster` is a
[`Raster`](@ref) with the same size and fields as the original array.

# Keywords

$INVERT_KEYWORD
$GEOM_KEYWORDS

# Example

```jldoctest
using Rasters, RasterDataSources, ArchGDAL, Plots, Dates
wc = Raster(WorldClim{Climate}, :prec; month=1)
missingmask(wc) |> plot

savefig("src/assets/api/missingmask_example.png"); nothing

# output
```

![missingmask](assets/api/missingmask_example.png)

$EXPERIMENTAL
"""
function missingmask(x; kw...)
    B = boolmask(x; kw...)
    M = Array{Union{Missing,Bool}}(undef, size(B))
    M .= _false_to_missing.(B)
    return rebuild(B; data=M, missingval=missing)
end
function missingmask(source::AbstractRaster; kw...)
    dest = _init_bools(source, Array{Union{Missing,Bool}}, nothing; kw..., missingval=missing)
    return rebuild(missingmask!(dest, source; kw...); missingval=missing)
end

function missingmask!(dest::AbstractRaster, src::AbstractRaster;
    invert=false,
    missingval=_missingval_or_missing(src)
)
    if invert
        broadcast_dims!(dest, src) do x
            isequal(x, missingval) ? true : missing
        end
    else
        broadcast_dims!(dest, src) do x
            isequal(x, missingval) ? missing : true
        end
    end
end
function missingmask!(dest::AbstractRaster, geom; kw...)
    B = boolmask!(dest, geom; kw...) 
    # boolmask! handles `invert` keyword here
    dest .= _false_to_missing.(B)
    return dest
end

_false_to_missing(b::Bool) = (b ? true : missing)::Union{Missing,Bool}

function _mask_multilayer(layers::Union{<:AbstractRasterStack,<:AbstractRasterSeries}, to; 
    _dest_presentval,
    _dest_missingval, 
    missingval=nothing, 
    kw...
)
    T = Union{typeof(_dest_missingval),Bool}
    dest = _init_bools(to, Array{T}, layers; kw..., missingval=_dest_missingval)
    dest .= _dest_presentval

    missingval = if isnothing(missingval)
        map(_missingval_or_missing, layers)
    elseif missingval isa NamedTuple
        missingval
    else
        map(_ -> missingval, layers)
    end

    map(layers, missingval) do layer, mv
        broadcast_dims!(dest, dest, layer) do d, x
            isequal(d, _dest_missingval) || isequal(x, mv) ? _dest_missingval : _dest_presentval
        end
    end
   return dest
end
