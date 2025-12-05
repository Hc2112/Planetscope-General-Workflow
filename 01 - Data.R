library(dplyr)
library(terra)
library(sf)
library(exactextractr);library(stringr)
library(tidyterra);library(jsonlite)

##Example for preparing data for extractions

fields.sf = st_read(
  'D:\\Remote Sensing Team\\PENNSYLVANIA\\DATA\\CONTROLLED\\BMPs20250724\\BMPs_MULTIPOLYGON.shp') %>% 
  st_transform('epsg:32618') %>% ##reproject to appropriate UTM code
  dplyr::filter(practice == 'Cover Crop' &
                  status == 'Implemented' &
                  (str_detect(implement2,'2025')==T)) %>% 
  select(identifier, implement2, practice, status) %>%
  st_buffer(dist = -5) %>% ##reverse buffer may render small geometries invalid.
  dplyr::arrange(identifier)

fields.sf <- fields.sf[!st_is_empty(fields.sf),] ##retain only valid geometries.

field.id <- fields.sf$identifier ##to be used for compiling extractions data frame

# #export to shapefile and manipulate in GIS. Break multi-part polygons into single parts
# write_sf(fields.sf,'pa_cumberland_2025_enrolled_fields_implemented_covercrops.geojson')



##READ IMAGERY METADATA------------------------------

#list all metadata files with the path
pl.m <- list.files(path= 'D:\\Remote Sensing Team\\PENNSYLVANIA\\IMAGERY\\Planet\\', #name path where all files reside
                   recursive = T, full.names = T,
                   pattern = '*metadata.json$') %>% 
  as.data.frame() %>% rename('file' = '.') %>% 
  dplyr::filter(str_detect(file,'Cumberland') |
                  str_detect(file,'Perry')) %>% 
  mutate(
    County = ifelse(str_detect(file,'Cumberland')==T,
                    'Cumberland','Perry'),
    scene = paste0(County,'_',
                   str_extract(
                     file,'[0-9]{8}_[0-9]{6}[_0-9]{0,3}_[:alnum:]{4}'))
  ) %>% 
  dplyr::filter(!(duplicated(scene))) ##duplicate scenes exist 



##Loop through list of metadata files to create a dataframe. To be used
##for further investigation if needed.
meta.df <- data.frame()
for (m in 1:nrow(pl.m)){
  print(paste("Loop m at:", m))
  
  if(file.size(pl.m$file[m])<200)next
  
  file = fromJSON(pl.m$file[m])
  
  county = pl.m$County[m]
  
  id = pl.m$scene[m] #the scene id
  
  instrument = file$properties$instrument
  
  Date = file$properties$acquired
  
  satellite_id = file$properties$satellite_id
  
  strip_id = file$properties$strip_id
  
  quality_category = (file$properties$quality_category %>% as.character())
  
  clear_confidence_percent = (file$properties$clear_confidence_percent %>% as.numeric())
  
  clear_percent = (file$properties$clear_confidence_percent %>% as.numeric())
  
  sun_elevation = (file$properties$sun_elevation %>% as.numeric())
  
  sun_azimuth = (file$properties$sun_azimuth %>% as.numeric())
  
  view_angle = (file$properties$view_angle %>% as.numeric()) #aka off-nadir angle
  
  # Print the length of each variable
  print(paste("Length of county:", length(county)))
  print(paste("Length of id:", length(id)))
  print(paste("Length of instrument:", length(instrument)))
  print(paste("Length of Date:", length(Date)))
  print(paste("Length of satellite_id:", length(satellite_id)))
  print(paste("Length of strip_id:", length(strip_id)))
  print(paste("Length of quality_category:", length(quality_category)))
  print(paste("Length of clear_confidence_percent:", length(clear_confidence_percent)))
  print(paste("Length of clear_percent:", length(clear_percent)))
  print(paste("Length of sun_elevation:", length(sun_elevation)))
  print(paste("Length of sun_azimuth:", length(sun_azimuth)))
  print(paste("Length of view_angle:", length(view_angle)))
  
  df <- data.frame(county,
                   id,
                   instrument, 
                   Date, 
                   satellite_id, 
                   strip_id, 
                   quality_category,
                   clear_confidence_percent, 
                   clear_percent, 
                   sun_elevation, 
                   sun_azimuth, 
                   view_angle)
  
  meta.df <- rbind(meta.df,df)
}

write.csv(meta.df,'planet_scene_metadata.csv',row.names = F)

##Optional
# meta.df.fin <- meta.df %>% 
#   mutate(
#     scene = str_extract(id,'[0-9]{8}_[0-9]{6}[_0-9]{0,3}_[:alnum:]{4}')
#   ) %>% 
#   dplyr::filter(clear_confidence_percent >= 90)

##read in Planet metadata from disk and filter to highest quality imagery
pl.meta = read.csv('planet_scene_metadata.csv') %>% ##excludes conf % <90
  dplyr::filter(clear_confidence_percent >= 90)
