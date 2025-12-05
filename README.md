# Planetscope-General-Workflow
A generalized workflow for ordering, processing, and generating scatterplots and time-series outputs for an area-of-interest (AOI). This project is focused on Planetscope surface reflectance (SR), orthorectified product.

<b>Order & Download Planetscope scenes using the Planet API (00 - Order from Planet API.R)</b>

  The script for calling the Planet API requires an API key, which can be found under the user's Planet account profile under "My Settings". Anyone can create
  a Planet account, but to have download access to Planetscope 8-band imagery one must apply to the Commercial Satellite Data Acquisition (CSDA) program. The quota for CSDA accounts is 
  5,000,000 km<sup>2</sup> per user.

  Planet requires that areas-of-interest (AOIs) be projected in geographic coordinates (EPSG: 4326) and contain no more than 1,500 vertices. AOIs can be in .shp or .geojson file format, but must not   contain multi-polyons. Ensure that your AOI is dissolved into one polygon and constrained to your feature(s) of interest in order to maximize on your Planet quota. Another factor that may prevent an order from executing is an AOI's topology. If such an error occurs, calling ```content(order.status)[['last_message']]``` will reveal where in the AOI the first error occurred. This can be an iterative process, so inspecting an AOI's topology using GIS software before attempting to place an order is recommended.

  Availability for 8-band imagery 

  <u>Querying</u>
  To check the status of a query, ```search.results$status_code``` will show whether your query is valid. Status code 2XX means the query is valid, while status code 4XX denotes an error. Ensure that the date ranges are valid (e.g. end date does not chronologically precede begin date).<br>

  Each downloaded scene contains four files:<br>
    (1) the imagery itself, with a file name usually ending with "AnalyticMS_SR_8b_clip.tif" for 8-band imagery or "AnalyticMS_SR_clip.tif" for 4-band imagery. "Clip" may omitted for when ordering       an entire scene. <br>
    (2) usable data mask (udm) file. The latest UDM version (version 2.1) contains eight mask layers. Mask file names ending with "udm2.tif" or "udm2_clip.tif".<br>
    (3) metadata file, with file name ending with "metadata.json".<br>
    (4) XML file containing order information and coefficient for converting digital number (DN) values to top-of-atmosphere (TOA) reflectance values.<br>

<b>Prepare Spatial Data for Extrations (01 - Data.R)</b><br>

A few things to bear in mind when preparing your spatial data for extractions using the exactextractr::exact_extract function are that (1) it is an sf, sfc, or SpatialPolygonsDataFrame object; (2) it's projected in UTM and it corresponds to the image you're extracting from; (3) does not contain empty polygons. <br>

This script also reads in metadata for Planet imagery and prepares a summary that can be used for making proper data selection.<br><br>.

<b>Extractions (02 -Extraction Loop.R)</b><br>

The objective of this script is to iterate through a list of Planetscope files and compile extractions of median values from polygons. If the objective is to extract by points, this can be adjusted by replacing with the function exactextractr::exact_extract with terra::extract and turning the sf object into a SpatVector object by using terra::vect(). <br>

The masking process within this loop uses two layers from the udm file (usable data mask), namely "clear" (0 = not clear and 1 = clear) and "clear_confidence_percent" (an integer from 0-100).  Through previous observations, we've found that constricting the use of imagery having a clear confidence percentage of >= 90 provides the most reliable results.<br><br>


<b>Links:</b><br>
  Planet Labs https://www.planet.com/ <br>
  CSDA Application https://csdap.earthdata.nasa.gov/signup/ <br>
  Planet API Resource https://developers.planet.com/docs/apis/ <br>
  Usable Data Mask (UDM) documentation https://docs.planet.com/data/imagery/udm/

Step 2: 
