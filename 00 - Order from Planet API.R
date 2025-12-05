library(httr)
library(jsonlite)
library(sf)
library(magrittr)
library(dplyr)
library(stringr)
library(exiftoolr) #reads in EXIF metadata from downloaded Planet image files
library(lubridate)
##create a file called 'secrets.R' and in it define your API key
##e.g. planet.api.key = ''
source('secrets.R') 

##Ordering script for BARC - subject to change-----------------------
##read in a .geojson or .shp file containing your AOI boundary
aoi <- list.files(pattern='BARC_fields.geojson',
                       recursive = T,
                       full.names = T)

product.name <- 'BARC_' ##this will be part of your order name

extent <- fromJSON(aoi,
                   simplifyVector = F) %>%
  .$features %>%
  .[[1]] %>%
  .$geometry

extent.filter <- list(type='GeometryFilter',
                      field_name='geometry',
                      config = extent) %>% 
  jsonlite::toJSON(auto_unbox = T)

##specify the date range. NOTE: the "to" date will not include imagery
##from that date, as the time would max out at 00:00 hours GMT
dates <- c('2025-05-01','2025-06-01') %>%
  ymd() %>%
  as_datetime() %>%
  format_ISO8601(usetz = 'Z') %>%
  set_names(c('gte','lte')) %>%
  as.list()




date.filter <- list(type='DateRangeFilter',field_name='acquired',
                    config = dates) %>% 
  jsonlite::toJSON(auto_unbox = T)

##an acceptable cloud cover % ranges from 0-60%
##also, we only want "standard" images vs. "test" images

data.search.template <- '{
  "item_types":["PSScene"],
  "filter":{
    "type":"AndFilter",
    "config":[
        ${date.filter}$,
        ${extent.filter}$,
        {
            "type":"RangeFilter",
            "config":{
               "gte":0,
               "lte":0.6
            },
            "field_name":"cloud_cover"
         },
{"type": "StringInFilter",
        "field_name": "quality_category",
        "config": ["standard"]
      },
{"type": "RangeFilter",
        "field_name": "clear_confidence_percent",
        "config": {"gte":90,"lte":100}
      },
{"type":"StringInFilter",
        "config":["true"],
        "field_name":"ground_control"}
    ]
  }
}'

request <-  glue::glue(data.search.template,
                       .open= '${',
                       .close = '}$')

search.results <-  POST(url='https://api.planet.com/data/v1/quick-search',
                        body = as.character(request),
                        authenticate(planet.api.key,
                                     ''), 
                        content_type_json()
);search.results$status_code ##if code is 4XX, check the template and ensure date ranges
##are valid

##if 250 or greater, consider tightening the date range, as pagination of orders 
##is required to retrieve full order, but is not a part of this script.
search.results.c <- content(search.results); search.results.c[[2]] %>% length()

##SETTING UP ORDER##

products <- c('analytic_8b_sr_udm2','analytic_sr_udm2') #8-band or 4-band

products.json <- purrr::map_chr(search.results.c$features,
                                'id') %>% ####CHECK THIS LINE!!!!!
  list(item_ids=.,item_type='PSScene',
       product_bundle=products[1]) %>% #surface reflectance, 8 band. For 4-band or other products, visit https://developers.planet.com/apis/orders/product-bundles-reference/
  toJSON(auto_unbox = T,pretty = T)

##name your order accordingly. this naming convention includes the date range
product.order.name <- paste0(
  product.name,
  dates$gte %>% as.character() %>% str_remove('T00:00:00Z') %>% str_remove_all('-'),
  '-',
  dates$lte %>% as.character() %>% str_remove('T00:00:00Z') %>% str_remove_all('-'),
  '_',
  products.json %>% str_extract('analytic_[8b]{0,2}_{0,1}[sr][:graph:]{0,6}'));product.order.name

## DOWNLOAD OPTION 1 -- this is the preferred method to ensure file integrity
## USE IF ZIPPED DELIVERY IS DESIRED
product.order.template <- '{
  "name":"${product.order.name}$",
  "source_type":"scenes",
  "products":[
    ${products.json}$
  ],
  "tools":[
    {
      "clip":{
        "aoi":${toJSON(extent,auto_unbox=T)}$
      }
    }
  ],
   "delivery":{
  "archive_type":"zip",
  "single_archive":true,
  "archive_filename":"{{name}}.zip"
   }}'

## DOWNLOAD OPTION 2 - USE IF DOWNLOADING BY SINGLE FILES IS DESIRED.
# product.order.template <- '{
#   "name":"${product.order.name}$",
#   "source_type":"scenes",
#   "products":[
#     ${products.json}$
#   ],
#   "tools":[
#     {
#       "clip":{
#         "aoi":${toJSON(extent,auto_unbox=T)}$
#       }
#     }
#   ]
# }
# '

order.request <- glue::glue(
  product.order.template,
  .open ='${',
  .close = '}$'
)


## ONLY EXECUTE order.pending ONCE!!!!!!!##
order.pending <- POST(url='https://api.planet.com/compute/ops/orders/v2',
                      body = as.character(order.request),
                      authenticate(planet.api.key,
                                   ''),
                      content_type_json()
);order.pending$status_code

content(order.pending)[['id']];product.order.name

order.id <-  content(order.pending)[['id']]

order.status <- httr::GET(url=
                            paste0('https://api.planet.com/compute/ops/orders/v2/',
                                   order.id), #change back to order.id
                          authenticate(planet.api.key,
                                       ''),
                          content_type_json()
);content(order.status)[['last_message']]

# order.download <- httr::GET(url=content(order.status)[['_links']][['results']][[1]][['location']],
#                           authenticate(planet.api.key,
#                                        'order.id'),
#                           content_type_json()
# )

##DOWNLOADS FILES INDIVIDUALLY
# downloads <- purrr::imap(
#   content(order.status)[['_links']][['results']],
#   ~{
#     dest = file.path(paste0(
#       'C:\\PSA\\Remote Sensing Team\\Projects\\Planet Orders\\Downloads\\',#change to where you want the images to download
#       product.order.name),#change back to product.order.name
#       basename(.x$name))
#     if(file.exists(dest)){
#       warning('File exists,skipping: ',basename(.x$name),
#               immediate. = T,
#               call. = F)
#       return(NULL)}
#     message(.y, ' ', basename(.x$name))
#     httr::GET(url=.x$location,
#               authenticate(planet.api.key,
#                            ''),
#               content_type_json(),
#               write_disk(dest)
#     )
#   },.progress=T
# )



##REFINED API ORDERING PROCESS (PREFERRED), EXAMPLE FROM PSA ON-FARM------------------------

##ORDERING OPTION 1: IMAGERY ORDERS by single day----------------------------------------------
codes = fields.df %>% 
  dplyr::filter(order.id =='NA') %>%
  select(code) %>% as.vector() %>% unlist() %>% 
  unique()

df.1 = data.frame()
for (i in 1:length(codes)){
  
  print(paste0(
    "Processing ",
    i," of ",length(codes)
  ))
  
  
  aoi <- extent.files.main %>% 
    dplyr::filter(str_detect(Code,codes[i])) %>% 
    select(file) %>% as.character();aoi
  
  product.name <- paste0('Onfarm',str_extract(aoi,'_[A-Z]{3}'),'_');product.name
  
  extent <- fromJSON(aoi,
                     simplifyVector = F) %>%
    .$features %>%
    .[[1]] %>%
    .$geometry
  
  
  extent.filter <- list(type='GeometryFilter',
                        field_name='geometry',
                        config = extent) %>% 
    jsonlite::toJSON(auto_unbox = T)
  
  
  
  codes.sub = st_drop_geometry(fields.df) %>% distinct() %>% 
    dplyr::filter(code == codes[i]) %>% 
    rename('date.begin' = 'cover_planting',
           'date.end' = 'cc_termination_date')
  
  if(nrow(codes.sub) <1)next
  
  
  
  df.dates <- seq(from = min(codes.sub$date.begin), 
                  to = max(codes.sub$date.end), by = "day")  %>% 
    as.data.frame() %>% 
    rename('date' = '.')
  
  for(j in 1:length(df.dates$date)){
    
    print(paste0(
      "Processing ",
      j," of ",length(df.dates$date),
      ' ',code,", ",df.dates$date[j]
    ))
    
    date.begin = df.dates$date[j]
    date.end = df.dates$date[j]+1
    
    dates <- c(date.begin,
               date.end) %>%
      ymd() %>%
      as_datetime() %>%
      format_ISO8601(usetz = 'Z') %>%
      set_names(c('gte','lte')) %>%
      as.list()
    
    date.filter <- list(type='DateRangeFilter',field_name='acquired',
                        config = dates) %>% 
      jsonlite::toJSON(auto_unbox = T)
    
    ##acceptable cloud cover range from 0-60%; only "standard" images vs. "test"
    data.search.template <- '{
        "item_types":["PSScene"],
          "filter":{
            "type":"AndFilter",
            "config":[
                ${date.filter}$,
                ${extent.filter}$,
                {
                    "type":"RangeFilter",
                    "config":{
                       "gte":0,
                       "lte":0.6
                    },
                    "field_name":"cloud_cover"
                 },
        {"type": "StringInFilter",
                "field_name": "quality_category",
                "config": ["standard"]
              },
        {"type": "RangeFilter",
                "field_name": "clear_confidence_percent",
                "config": {"gte":80,"lte":100}
              }
            ]
          }
        }'  
    
    request <-  glue::glue(data.search.template,
                           .open= '${',
                           .close = '}$')
    
    
    search.results <-  POST(url='https://api.planet.com/data/v1/quick-search',
                            body = as.character(request),
                            authenticate(planet.api.key3,
                                         ''), 
                            content_type_json()
    );search.results$status_code
    
    
    search.results.c <- content(search.results); search.results.c[[2]] %>% length()
    
    results.length <- length(search.results.c[[2]])
    
    if(results.length <1)next
    
    ids = data.frame()
    for (o in 1:length(search.results.c$features)){
      
      assets = search.results.c$features[[o]]$assets
      
      if (any('ortho_analytic_8b_sr' ==  unlist(assets))){
        bundle.id = 'analytic_8b_sr_udm2'
      } else if (any('ortho_analytic_4b_sr' ==  unlist(assets))){
        bundle.id = 'analytic_sr_udm2'
      }else{next}
      
      pl.id = search.results.c$features[[o]]$id %>%
        as.data.frame() %>% rename('planet.id' = '.') %>%
        mutate(
          planet.id = paste0(
            str_extract(planet.id,'[0-9]{8}'),
            str_extract(planet.id,'_[0-9]{6}'),
            str_extract(planet.id,'_[:alnum:]{4}$')),
          bundle.id = bundle.id,
          date = str_extract(planet.id,'[0-9]{8}')
        )
      ids = rbind(ids,pl.id) 
    }
    
    if(nrow(ids)<1)next
    
    bundle.first = ids$bundle.id %>% unique() %>% sort()
    bundle.first = ifelse(length(bundle.first)=='2',bundle.first[1],
                          bundle.first)
    #https://docs.planet.com/develop/apis/orders/product_bundles/
    
    row.count = nrow(ids)
    
    row.pos <- c(which(is.na(ids$planet.id) == FALSE))
    
    products.list <- list(
      item_ids = as.list(ids$planet.id),  # Force array structure for single scene days
      item_type = 'PSScene',
      product_bundle = ids$bundle.id)
    
    products.json.1 <- toJSON(products.list, auto_unbox = TRUE, pretty = TRUE)
    
    # products.json.1 <- purrr::map_chr(search.results.c$features,
    #                                   'id') %>% ####CHECK THIS LINE!!!!!
    #   list(item_ids=.,item_type='PSScene',
    #        product_bundle =   "analytic_8b_sr_udm2,analytic_sr_udm2") %>% #surface reflectance, 8 band. For 4-band or other products, visit https://developers.planet.com/apis/orders/product-bundles-reference/
    #   toJSON(auto_unbox = T,pretty = T)
    
    
    products.json.2 <- purrr::map_chr(search.results.c$features[row.pos],
                                      'id') %>% ####CHECK THIS LINE!!!!!
      list(item_ids=.,item_type='PSScene',
           product_bundle =   "analytic_8b_sr_udm2,analytic_sr_udm2") %>% #surface reflectance, 8 band. For 4-band or other products, visit https://developers.planet.com/apis/orders/product-bundles-reference/
      toJSON(auto_unbox = T,pretty = T)
    
    products.json = ifelse(row.count <2,
                           products.json.1 %>% unlist(),
                           products.json.2)
    
    product.order.name <- paste0(
      product.name,
      dates$gte %>% as.character() %>% str_remove('T00:00:00Z') %>% str_remove_all('-'),
      '-',
      dates$lte %>% as.character() %>% str_remove('T00:00:00Z') %>% str_remove_all('-'),
      '_',
      bundle.first);product.order.name
    
    
    product.order.template <- '{
      "name":"${product.order.name}$",
      "source_type":"scenes",
      "products":[
        ${products.json}$
      ],
      "tools":[
        {
          "clip":{
            "aoi":${toJSON(extent,auto_unbox=T)}$
          }
        }
      ],
       "delivery":{
      "archive_type":"zip",
      "single_archive":true,
      "archive_filename":"${product.order.name}$.zip"
       }}'
    
    order.request <- glue::glue(
      product.order.template,
      .open ='${',
      .close = '}$'
    )
    
    # # ONLY EXECUTE order.pending ONCE!!!!!!!
    order.pending <- POST(url='https://api.planet.com/compute/ops/orders/v2',
                          body = as.character(order.request),
                          authenticate(planet.api.key3,
                                       ''),
                          content_type_json()
    );order.pending$status_code
    
    Sys.sleep(5)
    
    order.status = order.pending$status_code %>% as.character()
    
    order.id <-  ifelse(
      is.null(content(order.pending)[['id']]) == T,'NA',
      content(order.pending)[['id']])
    
    order.message = ifelse(order.id =='NA',content(order.pending)$field$Details %>%
                             unlist() %>% as.matrix() %>% as.data.frame() %>%
                             rename('Date' = 'V1') %>%
                             mutate(
                               message = Date,
                               Date = str_extract(Date,'[0-9]{8}')
                             ) %>%
                             distinct() %>%
                             dplyr::arrange(Date) %>%
                             mutate(Code = code),"Success")
    
    df.2 = data.frame(product.order.name,
                      code,
                      date.begin,
                      date.end,
                      order.id,
                      order.status,
                      results.length)
    
    df.1 = rbind(df.1,df.2)
    
    if(str_detect(order.status,'400')==F)next
    
    
    
    # order.message = content(order.pending)$field$Details %>% 
    #   unlist() %>% as.matrix() %>% as.data.frame() %>% 
    #   rename('Date' = 'V1') %>% 
    #   mutate(
    #     Scene = str_extract(Date,'[0-9]{8}_[:graph:]{6}_[:graph:]{4}'),
    #     Date = str_extract(Date,'[0-9]{8}'),
    #   ) %>% 
    #   distinct() %>%
    #   dplyr::arrange(Date) %>% 
    #   mutate(Code = code)
    
    if(length(order.message)<1)next
    
    ids.2 = ids %>% 
      mutate(
        invalid = date %in% order.message$Date
      )
    
    if(nrow(ids.2)<1)next
    
    bundle.first = ids.2$bundle.id %>% unique() %>% sort()
    bundle.first = ifelse(length(bundle.first)=='2',bundle.first[1],
                          bundle.first)
    
    row.count = nrow(ids.2 %>% dplyr::filter(invalid =='FALSE'))
    
    row.pos <- c(which(ids.2$invalid == 'FALSE'))
    
    products.json.2 <- purrr::map_chr(search.results.c$features[row.pos],
                                      'id') %>% ####CHECK THIS LINE!!!!!
      list(item_ids=.,item_type='PSScene',
           product_bundle =   "analytic_8b_sr_udm2,analytic_sr_udm2") %>% #surface reflectance, 8 band. For 4-band or other products, visit https://developers.planet.com/apis/orders/product-bundles-reference/
      toJSON(auto_unbox = T,pretty = T)
    
    products.json = ifelse(row.count <2,products.json.1,products.json.2)
    
    product.order.name <- paste0(
      product.name,
      dates$gte %>% as.character() %>% str_remove('T00:00:00Z') %>% str_remove_all('-'),
      '-',
      dates$lte %>% as.character() %>% str_remove('T00:00:00Z') %>% str_remove_all('-'),
      '_',
      bundle.first);product.order.name
    
    
    product.order.template <- '{
      "name":"${product.order.name}$",
      "source_type":"scenes",
      "products":[
        ${products.json}$
      ],
      "tools":[
        {
          "clip":{
            "aoi":${toJSON(extent,auto_unbox=T)}$
          }
        }
      ],
       "delivery":{
      "archive_type":"zip",
      "single_archive":true,
      "archive_filename":"${product.order.name}$.zip"
       }}'
    
    order.request <- glue::glue(
      product.order.template,
      .open ='${',
      .close = '}$'
    )
    
    # # ONLY EXECUTE order.pending ONCE!!!!!!!
    order.pending <- POST(url='https://api.planet.com/compute/ops/orders/v2',
                          body = as.character(order.request),
                          authenticate(planet.api.key3,
                                       ''),
                          content_type_json()
    );order.pending$status_code
    
    
    Sys.sleep(5)
    
    df.3 = data.frame(product.order.name,
                      code,
                      date.begin,
                      date.end,
                      order.id,
                      order.status,
                      results.length
    )
    
    df.1 = rbind(df.1,df.3)
    
    Sys.sleep(.1)
  }
  
}

##ORDERING OPTION 2: IMAGERY ORDERS by entire date range----------------------------------------------
codes = fields.df %>% 
  # dplyr::filter(order.id =='NA') %>%
  select(code) %>% as.vector() %>% unlist() %>% 
  unique()

df.1 = data.frame()
# codes = codes[c(7,51,54,65,114,138,165,183,184,185)]
for (i in 1:length(codes)){
  
  print(paste0(
    "Processing ",
    i," of ",length(codes)
  ))
  
  code = codes[i];code
  
  aoi <- extent.files.main %>% 
    dplyr::filter(str_detect(Code,codes[i])) %>% 
    select(file) %>% as.character();aoi
  
  product.name <- paste0('Onfarm',str_extract(aoi,'_[A-Z]{3}'),'_');product.name
  
  extent <- fromJSON(aoi,
                     simplifyVector = F) %>%
    .$features %>%
    .[[1]] %>%
    .$geometry
  
  
  extent.filter <- list(type='GeometryFilter',
                        field_name='geometry',
                        config = extent) %>% 
    jsonlite::toJSON(auto_unbox = T)
  
  
  
  codes.sub = st_drop_geometry(fields.df) %>% distinct() %>% 
    dplyr::filter(code == codes[i]) %>% 
    rename('date.begin' = 'cover_planting',
           'date.end' = 'cc_termination_date')
  
  if(nrow(codes.sub) <1)next
  
  
  dates <- c(codes.sub$date.begin,
             codes.sub$date.end) %>%
    ymd() %>%
    as_datetime() %>%
    format_ISO8601(usetz = 'Z') %>%
    set_names(c('gte','lte')) %>%
    as.list()
  
  date.filter <- list(type='DateRangeFilter',field_name='acquired',
                      config = dates) %>% 
    jsonlite::toJSON(auto_unbox = T)
  
  ##acceptable cloud cover range from 0-60%; only "standard" images vs. "test"
  data.search.template <- '{
        "item_types":["PSScene"],
          "filter":{
            "type":"AndFilter",
            "config":[
                ${date.filter}$,
                ${extent.filter}$,
                {
                    "type":"RangeFilter",
                    "config":{
                       "gte":0,
                       "lte":0.6
                    },
                    "field_name":"cloud_cover"
                 },
        {"type": "StringInFilter",
                "field_name": "quality_category",
                "config": ["standard"]
              },
        {"type": "RangeFilter",
                "field_name": "clear_confidence_percent",
                "config": {"gte":80,"lte":100}
              }
            ]
          }
        }'  
  
  request <-  glue::glue(data.search.template,
                         .open= '${',
                         .close = '}$')
  
  
  search.results <-  POST(url='https://api.planet.com/data/v1/quick-search',
                          body = as.character(request),
                          authenticate(planet.api.key3,
                                       ''), 
                          content_type_json()
  );search.results$status_code
  
  
  search.results.c <- content(search.results); search.results.c[[2]] %>% length()
  
  results.length <- length(search.results.c[[2]])
  
  if(results.length <1)next
  
  ids = data.frame()
  for (o in 1:length(search.results.c$features)){
    
    assets = search.results.c$features[[o]]$assets
    
    if (any('ortho_analytic_8b_sr' ==  unlist(assets))){
      bundle.id = 'analytic_8b_sr_udm2'
    } else if (any('ortho_analytic_4b_sr' ==  unlist(assets))){
      bundle.id = 'analytic_sr_udm2'
    }else{next}
    
    pl.id = search.results.c$features[[o]]$id %>%
      as.data.frame() %>% rename('planet.id' = '.') %>%
      mutate(
        row.id = o,
        planet.id = paste0(
          str_extract(planet.id,'[0-9]{8}'),
          str_extract(planet.id,'_[0-9]{6}'),
          str_extract(planet.id,'_[:alnum:]{4}$')),
        bundle.id = bundle.id,
        date = str_extract(planet.id,'[0-9]{8}')
      )
    ids = rbind(ids,pl.id) 
  }
  
  if(nrow(ids)<1)next
  
  bundle.first = ids$bundle.id %>% unique() %>% sort()
  bundle.first = ifelse(length(bundle.first)=='2',bundle.first[1],
                        bundle.first)
  #https://docs.planet.com/develop/apis/orders/product_bundles/
  
  row.count = nrow(ids)
  
  row.pos <- c(which(is.na(ids$planet.id) == FALSE))
  
  products.list <- list(
    item_ids = as.list(ids$planet.id),  # Force array structure for single scene days
    item_type = 'PSScene',
    product_bundle = ids$bundle.id)
  
  products.json.1 <- toJSON(products.list, auto_unbox = TRUE, pretty = TRUE)
  
  # products.json.1 <- purrr::map_chr(search.results.c$features,
  #                                   'id') %>% ####CHECK THIS LINE!!!!!
  #   list(item_ids=.,item_type='PSScene',
  #        product_bundle =   "analytic_8b_sr_udm2,analytic_sr_udm2") %>% #surface reflectance, 8 band. For 4-band or other products, visit https://developers.planet.com/apis/orders/product-bundles-reference/
  #   toJSON(auto_unbox = T,pretty = T)
  
  
  products.json.2 <- purrr::map_chr(search.results.c$features[row.pos],
                                    'id') %>% ####CHECK THIS LINE!!!!!
    list(item_ids=.,item_type='PSScene',
         product_bundle =   "analytic_8b_sr_udm2,analytic_sr_udm2") %>% #surface reflectance, 8 band. For 4-band or other products, visit https://developers.planet.com/apis/orders/product-bundles-reference/
    toJSON(auto_unbox = T,pretty = T)
  
  products.json = ifelse(row.count <2,
                         products.json.1 %>% unlist(),
                         products.json.2)
  
  product.order.name <- paste0(
    product.name,
    dates$gte %>% as.character() %>% str_remove('T00:00:00Z') %>% str_remove_all('-'),
    '-',
    dates$lte %>% as.character() %>% str_remove('T00:00:00Z') %>% str_remove_all('-'),
    '_',
    bundle.first);product.order.name
  
  
  product.order.template <- '{
      "name":"${product.order.name}$",
      "source_type":"scenes",
      "products":[
        ${products.json}$
      ],
      "tools":[
        {
          "clip":{
            "aoi":${toJSON(extent,auto_unbox=T)}$
          }
        }
      ],
       "delivery":{
      "archive_type":"zip",
      "single_archive":true,
      "archive_filename":"${product.order.name}$.zip"
       }}'
  
  order.request <- glue::glue(
    product.order.template,
    .open ='${',
    .close = '}$'
  )
  
  # # ONLY EXECUTE order.pending ONCE!!!!!!!
  order.pending <- POST(url='https://api.planet.com/compute/ops/orders/v2',
                        body = as.character(order.request),
                        authenticate(planet.api.key3,
                                     ''),
                        content_type_json()
  );order.pending$status_code
  
  Sys.sleep(5)
  
  order.status = order.pending$status_code %>% as.character()
  
  order.id <-  ifelse(
    is.null(content(order.pending)[['id']]) == T,'NA',
    content(order.pending)[['id']])
  
  order.message = ifelse(order.id =='NA',content(order.pending)$field$Details %>%
                           unlist() %>% as.matrix() %>% as.data.frame() %>%
                           rename('Date' = 'V1') %>%
                           mutate(
                             message = Date,
                             Date = str_extract(Date,'[0-9]{8}')
                           ) %>%
                           distinct() %>%
                           dplyr::arrange(Date) %>%
                           mutate(Code = code),"Success")
  
  df.2 = data.frame(product.order.name,
                    code,
                    date.begin,
                    date.end,
                    order.id,
                    order.status,
                    results.length)
  
  df.1 = rbind(df.1,df.2)
  
  if(str_detect(order.status,'400')==F)next
  
  
  
  # order.message = content(order.pending)$field$Details %>% 
  #   unlist() %>% as.matrix() %>% as.data.frame() %>% 
  #   rename('Date' = 'V1') %>% 
  #   mutate(
  #     Scene = str_extract(Date,'[0-9]{8}_[:graph:]{6}_[:graph:]{4}'),
  #     Date = str_extract(Date,'[0-9]{8}'),
  #   ) %>% 
  #   distinct() %>%
  #   dplyr::arrange(Date) %>% 
  #   mutate(Code = code)
  
  if(length(order.message)<1)next
  
  ids.2 = ids %>% 
    mutate(
      invalid = date %in% order.message$Date
    )
  
  if(nrow(ids.2)<1)next
  
  bundle.first = ids.2$bundle.id %>% unique() %>% sort()
  bundle.first = ifelse(length(bundle.first)=='2',bundle.first[1],
                        bundle.first)
  
  row.count = nrow(ids.2 %>% dplyr::filter(invalid =='FALSE'))
  
  row.pos <- ids$row.id
  
  # row.pos <- c(which(ids.2$invalid == 'FALSE'))
  
  products.json.2 <- purrr::map_chr(search.results.c$features[row.pos],
                                    'id') %>% ####CHECK THIS LINE!!!!!
    list(item_ids=.,item_type='PSScene',
         product_bundle =   "analytic_8b_sr_udm2,analytic_sr_udm2") %>% #surface reflectance, 8 band. For 4-band or other products, visit https://developers.planet.com/apis/orders/product-bundles-reference/
    toJSON(auto_unbox = T,pretty = T)
  
  products.json = ifelse(row.count <2,products.json.1,products.json.2)
  
  product.order.name <- paste0(
    product.name,
    dates$gte %>% as.character() %>% str_remove('T00:00:00Z') %>% str_remove_all('-'),
    '-',
    dates$lte %>% as.character() %>% str_remove('T00:00:00Z') %>% str_remove_all('-'),
    '_',
    bundle.first);product.order.name
  
  
  product.order.template <- '{
      "name":"${product.order.name}$",
      "source_type":"scenes",
      "products":[
        ${products.json}$
      ],
      "tools":[
        {
          "clip":{
            "aoi":${toJSON(extent,auto_unbox=T)}$
          }
        }
      ],
       "delivery":{
      "archive_type":"zip",
      "single_archive":true,
      "archive_filename":"${product.order.name}$.zip"
       }}'
  
  order.request <- glue::glue(
    product.order.template,
    .open ='${',
    .close = '}$'
  )
  
  # # ONLY EXECUTE order.pending ONCE!!!!!!!
  order.pending <- POST(url='https://api.planet.com/compute/ops/orders/v2',
                        body = as.character(order.request),
                        authenticate(planet.api.key3,
                                     ''),
                        content_type_json()
  );order.pending$status_code
  
  
  Sys.sleep(5)
  
  df.3 = data.frame(product.order.name,
                    code,
                    date.begin,
                    date.end,
                    order.id,
                    order.status,
                    results.length
  )
  
  df.1 = rbind(df.1,df.3)
  
  Sys.sleep(.1)
  
  
}



##DOWNLOAD ORDERS-----------------------------------------

library(tidyverse)
library(glue)
library(curl)
library(purrr)
library(progress);library(httr)
library(jsonlite);source('secrets.R') 


auth = authenticate(planet.api.key3, "")

download_root = "D:\\Projects\\Planet Orders - PSA\\Planet Orders - PSA\\DOWNLOADS 6"

download.code.list <-  df.1 %>% rename('codes' = 'codes.i.')

get_all_orders = function(download.code.list, prefix_column = "product.name") {
  # Extract prefix value from the data frame
  # prefix_value = download.code.list[['code']][1]  # Adjust index if needed
  prefix_value = 'Onfarm_'  # Adjust index if needed
  
  orders = list()
  next_url = "https://api.planet.com/compute/ops/orders/v2?page_size=100"
  while (!is.null(next_url)) {
    resp = GET(next_url, auth)
    stop_for_status(resp)
    content_data = content(resp, as = "parsed", type = "application/json")
    page_orders = content_data$orders
    
    # Filter orders by dynamic prefix
    filtered_orders = Filter(function(order) startsWith(order$name, prefix_value), page_orders)
    
    clean_page = map_dfr(filtered_orders, function(order) {
      tibble(
        id = order$id,
        name = order$name,
        state = order$state,
        created = order$created,
        updated = order$last_modified,
        items_count = length(order$products),
        url = order$`_links`$self
      )
    })
    
    orders = bind_rows(orders, clean_page)
    message(glue("Fetched {nrow(clean_page)} filtered orders from page. Total so far: {nrow(orders)}"))
    next_url = content_data$`_links`$`next`
  }
  return(orders)
}


#call order names
all_orders = get_all_orders(download.code.list) %>% 
  mutate(
    name.short = str_extract(name,
                             'Onfarm_[A-Z]{3}_[0-9]{8}-[0-9]{8}')
  ) %>% 
  dplyr::filter(str_detect(name,'20251103'))##ordered on this date


setwd(download_root)

for(i in 1:length(all_orders$id)){
  # pb$tick()
  print(paste0("Processing order: ",i))
  order_url = paste0("https://api.planet.com/compute/ops/orders/v2/", all_orders$id[i])
  resp = GET(order_url, authenticate(planet.api.key3, "", type = "basic"))
  stop_for_status(resp)
  order_json = content(resp, "text", encoding = "UTF-8")
  order_data = fromJSON(order_json, flatten = TRUE)
  id = all_orders[c(1:2),] %>%
    dplyr::filter(id == all_orders$id[i]) %>%
    pull(name)
  #set name of folders to order name place in org script
  fn = paste0(all_orders$name[i], ".zip")
  # Check results URLs
  file_urls = order_data$`_links`$results$location
  print(file_urls)
  file_url = file_urls[1]
  #Download quietly without printing http information (not working) 
  #TODO: fix for quiet download
  suppressMessages(
    suppressWarnings(
      curl::curl_download(
        url = file_url,
        destfile = fn,
        handle = curl::new_handle(httpauth = 1, userpwd = paste0(planet.api.key3, ":"))
      )
    )
  )
}


##UNZIP FOLDERS----------------------------------------

# Set your target directory
zip_dir <- 'D:\\Projects\\Planet Orders - PSA\\Planet Orders - PSA\\DOWNLOADS 6'

# List all .zip files in the directory
zip_files <- list.files(zip_dir, pattern = "\\.zip$", full.names = TRUE,
                        recursive = F) %>% 
  as.data.frame() %>% rename('file' = '.') 

# Create an output directory for unzipped content
output_dir <- file.path(zip_dir, "unzipped")
dir.create(output_dir, showWarnings = FALSE)

# Loop through and unzip each file
for (zip_file in zip_files$file) {
  unzip(zip_file, exdir = file.path(output_dir, tools::file_path_sans_ext(basename(zip_file))))
}


