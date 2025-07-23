# Planetscope-General-Workflow
A generalized workflow for ordering, processing, and generating scatterplots and time-series outputs for an area-of-interest (AOI).

Step 1: Order & Download Planetscope scenes using the Planet API.

  The script for calling the Planet API requires an API key, which can be found under the user's Planet account profile under "My Settings". Anyone can create
  a Planet account, but to have download access to Planetscope 8-band imagery one must apply to the Commercial Satellite Data Acquisition (CSDA) program. The quota for CSDA accounts is 
  5,000,000 km2 per user.

  Planet requires that areas-of-interest (AOIs) be projected in geographic coordinates (EPSG: 4326) and contain no more than 1,500 vertices. AOIs can be in .shp or .geojson file format, but must not   contain multi-polyons. Ensure that your AOI is dissolved into one polygon and constrained to your feature(s) of interest in order to maximize on your Planet quota.

  Each downloaded scene contains four files:
    (1) the imagery itself, with a file name usually ending with "AnalyticMS_SR_8b_clip.tif" for 8-band imagery or "AnalyticMS_SR_clip.tif" for 4-band imagery. "Clip" may omitted for when ordering       an entire scene.

  Links:
  Planet Labs https://www.planet.com/
  CSDA Application https://csdap.earthdata.nasa.gov/signup/
  Planet API Resource https://developers.planet.com/docs/apis/
  Usable Data Mask (UDM) documentation https://docs.planet.com/data/imagery/udm/

Step 2: 
