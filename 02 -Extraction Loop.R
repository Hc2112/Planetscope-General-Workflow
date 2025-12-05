library(dplyr)
library(terra)
library(sf)
library(exactextractr);library(stringr)

##Objective is to extract Planetscope values by polygon,
##export resulting mask and masked files.

##identify which imagery files to read in

##lists all 8-band raster files in the directory


pl.files <- list.files(
  path= 'D:\\Remote Sensing Team\\PENNSYLVANIA\\IMAGERY\\Planet\\Cumberland\\2024-2025' ,
  recursive = T, full.names = T,
  pattern = '*8b_clip.tif$') %>% 
  as.data.frame() %>% 
  rename('file' = '.') %>% 
  mutate(
    scene = paste0(str_extract(
      file,'[0-9]{8}_[0-9]{6}[_0-9]{0,3}_[:alnum:]{4}')),
    date = str_extract(file,'[0-9]{8}_[0-9]{6}'),
    date = str_remove(date,'_[0-9]{6}'),
    Date = paste0(str_sub(date,1,4),'-',
                  str_sub(date,5,6),'-',
                  str_sub(date,7,8)) %>% as.Date(),
    bands = ifelse(str_detect(file,'AnalyticMS_SR_8b'),'8','4')
  ) %>% 
  dplyr::arrange(date)  %>% 
  dplyr::filter(scene %in% pl.meta$scene) ##selects only high quality imagery from metadata


pl.df <- field.id %>% as.data.frame() %>% rename('identifier' = '.')

for (i in 1:nrow(pl.files)){
  
  gc()
  
  tryCatch({
    
    print(paste0(
      i,' of ',nrow(pl.files)))
    
    raster.initial = terra::rast(pl.files$file[i])
    
    crs.rast = paste0('epsg: ',crs(raster.initial,describe=T)[3])
    
    field = fields.sf %>% 
      st_transform(crs.rast) #reprojection may be unnessary,depending on the project.
    
    ##identify corresponding udm mask file
    mask.file = str_replace(pl.files$file[i],'AnalyticMS_SR[_8b]{0,3}_clip','udm2_clip')
    
    #resource for UDM2 cloud mask https://developers.planet.com/docs/data/udm-2/
    udm.mask = rast(mask.file,
                    lyrs = c(1,7))  %>% 
      terra::mask(field)
    
    #resource for UDM2 cloud mask https://developers.planet.com/docs/data/udm-2/
    udm.mask[udm.mask$clear != 1] <- NA
    udm.mask[udm.mask$confidence <90] <- NA
    udm.mask[udm.mask$confidence >=90] <-  1
    
    ##OPTIONAL##
    mask.cells = ncell(udm.mask)
    df.na = ifelse(
      is.na((values(udm.mask$confidence) %>% is.na() %>% 
               table() %>% as.data.frame() %>% dplyr::filter(. == 'TRUE') %>% 
               select(Freq) %>% as.integer()))==F,
      values(udm.mask$confidence) %>% is.na() %>% 
        table() %>% as.data.frame() %>% dplyr::filter(. == 'TRUE') %>% 
        select(Freq) %>% as.integer(),
      0
    )
    
    ##OPTIONAL. SKIPS SCENES WHERE MASK HAS LITTLE TO NO COVERAGE##
    if((df.na >= mask.cells*.9999)==T)next

    ##OPTIONAL Comment out if necessary##
    writeRaster(udm.mask,paste0('cumberland_',
                                pl.files$scene[i],
                                '_','udm2.tif'),
                overwrite = T)
    
    stk.mask1 = mask(raster.initial, mask = udm.mask$clear) # mask by clear band
    raster = mask(stk.mask1, mask = udm.mask$confidence) # mask by confidence band
    
    rm(stk.mask1)
    rm(udm.mask)
    rm(raster.initial)
    gc()
    
    # raster = stk.mask %>% 
    #   terra::mask(stk.mask)
    
    raster$NDVI = (raster$nir - raster$red)/(raster$nir + raster$red)
    
    if (pl.files$bands[i] == '8') {
      raster$NDRE <- (raster$nir - raster$rededge) / (raster$nir + raster$rededge)
    } else {
      raster$NDRE <- rast(raster, nlyr=1)
      values(raster$NDRE) <- NA
    }
  
  ifelse(
    pl.files$bands[i]=='4',
    set.names(raster,c(      
      paste0('x',str_extract(pl.files$file[i],'[0-9]{8}_[0-9]{6}[_0-9]{0,3}_[:alnum:]{4}'),'_',pl.files$bands[i],'b','_blue'),
      paste0('x',str_extract(pl.files$file[i],'[0-9]{8}_[0-9]{6}[_0-9]{0,3}_[:alnum:]{4}'),'_',pl.files$bands[i],'b','_green'),
      paste0('x',str_extract(pl.files$file[i],'[0-9]{8}_[0-9]{6}[_0-9]{0,3}_[:alnum:]{4}'),'_',pl.files$bands[i],'b','_red'),
      paste0('x',str_extract(pl.files$file[i],'[0-9]{8}_[0-9]{6}[_0-9]{0,3}_[:alnum:]{4}'),'_',pl.files$bands[i],'b','_nir'),
      paste0('x',str_extract(pl.files$file[i],'[0-9]{8}_[0-9]{6}[_0-9]{0,3}_[:alnum:]{4}'),'_',pl.files$bands[i],'b','_NDVI'),
      paste0('x',str_extract(pl.files$file[i],'[0-9]{8}_[0-9]{6}[_0-9]{0,3}_[:alnum:]{4}'),'_',pl.files$bands[i],'b','_NDRE'))
    ),
    set.names(raster,c(
      paste0('x',str_extract(pl.files$file[i],'[0-9]{8}_[0-9]{6}_[0-9]{2}_[:graph:]{4}'),'_',pl.files$bands[i],'b','_cb'),
      paste0('x',str_extract(pl.files$file[i],'[0-9]{8}_[0-9]{6}_[0-9]{2}_[:graph:]{4}'),'_',pl.files$bands[i],'b','_blue'),
      paste0('x',str_extract(pl.files$file[i],'[0-9]{8}_[0-9]{6}_[0-9]{2}_[:graph:]{4}'),'_',pl.files$bands[i],'b','_greeni'),
      paste0('x',str_extract(pl.files$file[i],'[0-9]{8}_[0-9]{6}_[0-9]{2}_[:graph:]{4}'),'_',pl.files$bands[i],'b','_green'),
      paste0('x',str_extract(pl.files$file[i],'[0-9]{8}_[0-9]{6}_[0-9]{2}_[:graph:]{4}'),'_',pl.files$bands[i],'b','_yellow'),
      paste0('x',str_extract(pl.files$file[i],'[0-9]{8}_[0-9]{6}_[0-9]{2}_[:graph:]{4}'),'_',pl.files$bands[i],'b','_red'),
      paste0('x',str_extract(pl.files$file[i],'[0-9]{8}_[0-9]{6}_[0-9]{2}_[:graph:]{4}'),'_',pl.files$bands[i],'b','_rededge'),
      paste0('x',str_extract(pl.files$file[i],'[0-9]{8}_[0-9]{6}_[0-9]{2}_[:graph:]{4}'),'_',pl.files$bands[i],'b','_nir'),
      paste0('x',str_extract(pl.files$file[i],'[0-9]{8}_[0-9]{6}_[0-9]{2}_[:graph:]{4}'),'_',pl.files$bands[i],'b','_NDVI'),
      paste0('x',str_extract(pl.files$file[i],'[0-9]{8}_[0-9]{6}_[0-9]{2}_[:graph:]{4}'),'_',pl.files$bands[i],'b','_NDRE'))
    ))
  
  
  extracted = exactextractr::exact_extract(
    x= raster,
    y= fields.sf,
    fun = 'median')
  
  
  pl.df = cbind(pl.df,extracted)
  
  ##OPTIONAL Comment out if necessary##
  writeRaster(raster,
              filename = paste0('cumberland_',
                              pl.files$scene[i],
                              '_',pl.files$bands[i],
                              'b_masked.tif'),
              overwrite = T)
  
  rm(stk.mask)
  
  }, error=function(e){cat("ERROR :",conditionMessage(e), "\n")
  })
  
  gc()
  tmpFiles(remove = TRUE)
  
  Sys.sleep(5) ##Comment out or adjust if needed.
  
}

