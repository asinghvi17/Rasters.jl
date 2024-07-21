module RastersNCDatasetsExt

@static if isdefined(Base, :get_extension) # julia < 1.9
    using Rasters, NCDatasets, CommonDataModel
else    
    using ..Rasters, ..NCDatasets, ..CommonDataModel
end

import DiskArrays,
    FillArrays,
    Extents,
    GeoInterface,
    Missings

using Dates, 
    DimensionalData,
    GeoFormatTypes

using Rasters.Lookups
using Rasters.Dimensions
using Rasters: CDMsource, NCDsource, NoKW, nokw, isnokw

using CommonDataModel: AbstractDataset

const RA = Rasters
const DD = DimensionalData
const DA = DiskArrays
const GI = GeoInterface
const LA = Lookups

include("ncdatasets_source.jl")

end
