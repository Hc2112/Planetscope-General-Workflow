# Planetscope-General-Workflow
A generalized workflow for ordering, processing, and generating scatterplots and time-series outputs for an area-of-interest (AOI). This project is focused on Planetscope surface reflectance (SR), orthorectified product.

<b>Step 1: Order & Download Planetscope scenes using the Planet API </b>

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

<b>Links:</b><br>
  Planet Labs https://www.planet.com/ <br>
  CSDA Application https://csdap.earthdata.nasa.gov/signup/ <br>
  Planet API Resource https://developers.planet.com/docs/apis/ <br>
  Usable Data Mask (UDM) documentation https://docs.planet.com/data/imagery/udm/

Step 2: 
