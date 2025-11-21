library(dplyr);library(lubridate)
library(terra);library(tidyverse);library(magrittr)
library(sf);library(beepr);library(httr)
library(exactextractr);library(stringr);library(plyr)
library(tidyterra);library(jsonlite);library(geojsonio)
library(ggplot2);library(ggtext);source('secrets.R') 

##OBJECTIVE: Convert json files exported from Esri to geojson files.

##SETTING UP THE DATA--------------------------------------


##convert json files to geojson

library(jsonlite)
library(geojsonio)
library(sf)

# Set the directory containing your .json files

agro = read.csv(
  'C:\\PSA\\Remote Sensing Team\\Projects\\Planet Orders\\CO Yield Variability 20251120\\DATA\\field boundaries for yield variability examples\\summary of fields and years for corn and wheat yield variability.csv'
)  %>% 
  dplyr::arrange(Field)

json_dir <- "C:\\PSA\\Remote Sensing Team\\Projects\\Planet Orders\\CO Yield Variability 20251120\\DATA\\field boundaries for yield variability examples"
json_files <- list.files(json_dir, pattern = "\\.json$", full.names = TRUE,
                         recursive = T) %>%
  as.data.frame() %>% 
  dplyr::rename('file' = '.') %>% 
  dplyr::arrange(file) %>% 
  cbind(agro) %>% 
  mutate(
    file.short = list.files(json_dir, pattern = "\\.json$", full.names = F,
                            recursive = F),
    date.begin = (ifelse(Crop == 'Corn',
                         paste0(Crop_Year,
                                '-05-01'),
                         paste0((Crop_Year %>% 
                                   as.integer()-1),
                                '-09-01'))) %>% 
      as.Date(),
    date.end = (ifelse(Crop == 'Corn',
                       paste0(Crop_Year,
                              '-12-01'),
                       paste0((Crop_Year %>% 
                                 as.integer()),
                              '-07-02'))) %>% 
      as.Date(),
    key = paste0('season',Crop_Year,'_',Crop)
  )  

date.key <- json_files[,c(7:9)] %>% 
  distinct()



## Loop 2 through each file and convert to .geojson----------------------------
esri_to_geojson <- function(esri_json) {
  tryCatch({
    # Validate structure
    if (!("features" %in% names(esri_json)) || !is.data.frame(esri_json$features)) {
      stop("Invalid Esri JSON: Missing or malformed features data.frame")
    }
    
    # Extract the geometry list from the first feature
    first_geometry <- esri_json$features$geometry[[1]]
    
    # Check if rings exist
    if (!is.list(first_geometry) || is.null(first_geometry$rings)) {
      stop("Invalid Esri JSON: Missing geometry$rings")
    }
    
    rings <- first_geometry$rings
    
    # Validate rings format
    if (!is.list(rings) || !all(sapply(rings, is.list))) {
      stop("Invalid rings format: Must be list of coordinate lists")
    }
    
    # Construct GeoJSON Polygon
    geojson <- list(
      type = "Polygon",
      coordinates = rings
    )
    
    return(geojson)
  }, error = function(e) {
    message("Error converting Esri JSON: ", e$message)
    return(NULL)
  })
}

input_file <- json_files[i]
output_file <- input_file %>% str_replace('.json','.geojson') %>% 
  str_extract('/[:graph:].geojson')

for (i in 1:nrow(json_files)) {
  tryCatch({
    esri_data <- fromJSON(json_files$file[i])
    
    # Extract the 3D array
    geom_array <- esri_data$features$geometry[[1]][[1]]
    
    # Convert the first ring to a 2D matrix
    rings_matrix <- geom_array[1, , ]  # shape: [73, 2]
    
    
    # Check if the first and last coordinates are the same
    if (!all(rings_matrix[1, ] == rings_matrix[nrow(rings_matrix), ])) {
      # If not, append the first row to the end to close the ring
      rings_matrix <- rbind(rings_matrix, rings_matrix[1, ])
    }
    
    
    polygon <- st_polygon(list(as.matrix(rings_matrix)))
    sf_data <- st_sf(geometry = st_sfc(polygon, crs = 4326)) %>% 
      st_transform('epsg:32613') %>% 
      st_buffer(dist = 20) %>% 
      st_simplify(dTolerance = 20) %>% 
      st_transform('epsg:4326')
    
    # st_crs(sf_data) <- 4326
    
    st_write(sf_data,paste0(json_files$Crop_Year[i],'_',
                            json_files$Crop[i],'_',
                            '_',json_files$file.short[i] %>% 
                              str_remove('.json'),
                            'buffer20m.geojson'),
             driver = "GeoJSON")
  })
}


##Read geojson files, dissolve, save--------------------------------------------
files = list.files(path=
                     paste0(getwd(),
                            '\\DATA'),
                   full.names = T, recursive = F,
                   pattern = 'geojson$') %>% 
  as.data.frame() %>% 
  dplyr::rename('file' = '.') %>% 
  mutate(
    key = str_extract(file,'season20[123459]{2}_[:alpha:]{4,5}')
  ) %>% 
  left_join(date.key,by='key')

for(i in 1:nrow(files)){
  
  sf = read_sf(files$file[i]) 
  sf = st_sf(geometry = st_union(sf))
  
  st_write(sf,paste0(files$key[i],'_','dissolved.geojson'),
           driver = "GeoJSON")
}

