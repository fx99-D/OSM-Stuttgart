# *** The trekking profile is for slow travel
# *** and avoiding car traffic, but still with
# *** a focus on approaching your destination
# *** efficiently.
# === specail version on bicycle routes only

---context:global   # following code refers to global config

# Bike profile
assign validForBikes = true

# Use the following switches to change behaviour
assign allow_steps              = true   # %allow_steps% | Set to false to disallow steps | boolean
assign allow_ferries            = true   # %allow_ferries% | set to false to disallow ferries | boolean
assign ignore_cycleroutes       = false  # %ignore_cycleroutes% | Set to true for better elevation results | boolean
assign stick_to_cycleroutes     = true  # %stick_to_cycleroutes% | Set to true to just follow cycleroutes | boolean
assign avoid_unsafe             = false  # %avoid_unsafe% | Set to true to avoid standard highways | boolean
assign considerTurnRestrictions = false  # %considerTurnRestrictions% | Set to true to take turn restrictions into account | boolean
assign processUnusedTags        = false  # %processUnusedTags% | Set to true to output unused tags in data tab | boolean

# Change elevation parameters
assign consider_elevation = true  # %consider_elevation% | Set to false to ignore elevation in routing | boolean
assign downhillcost       = 60    # %downhillcost% | Cost for going downhill | number
assign downhillcutoff     = 1.5   # %downhillcutoff% | Gradients below this value in percents are not counted. | number
assign uphillcost         = 0     # %uphillcost% | Cost for going uphill | number
assign uphillcutoff       = 1.5   # %uphillcutoff% | Gradients below this value in percents are not counted.  | number

assign downhillcost       = if consider_elevation then downhillcost else 0
assign uphillcost         = if consider_elevation then uphillcost else 0

# Kinematic model parameters (travel time computation)
assign totalMass  = 90     # %totalMass% | Mass (in kg) of the bike + biker, for travel time computation | number
assign maxSpeed   = 45     # %maxSpeed% | Absolute maximum speed (in km/h), for travel time computation | number
assign S_C_x      = 0.225  # %S_C_x% | Drag coefficient times the reference area (in m^2), for travel time computation | number
assign C_r        = 0.01   # %C_r% | Rolling resistance coefficient (dimensionless), for travel time computation | number
assign bikerPower = 200    # %bikerPower% | Average power (in W) provided by the biker, for travel time computation | number

# Turn instructions settings
assign turnInstructionMode          = 0     # %turnInstructionMode% | Mode for the generated turn instructions | [0=none, 1=auto-choose, 2=locus-style, 3=osmand-style]
assign turnInstructionCatchingRange = 40    # %turnInstructionCatchingRange% | Within this distance (in m) several turning instructions are combined into one and the turning angles are better approximated to the general direction | number
assign turnInstructionRoundabouts   = true  # %turnInstructionRoundabouts% | Set to "false" to avoid generating special turning instructions for roundabouts | boolean


---context:way   # following code refers to way-tags

# classifier constants
assign classifier_none  = 1
assign classifier_ferry = 2

#
# pre-calculate some logical expressions
#

assign any_cycleroute =
     if      route_bicycle_icn=yes then true
     else if route_bicycle_ncn=yes then true
     else if route_bicycle_rcn=yes then true
     else if route_bicycle_lcn=yes then true
     else false

assign nodeaccessgranted =
     if any_cycleroute then true
     else lcn=yes

assign is_ldcr =
     if ignore_cycleroutes then false
     else any_cycleroute

assign isbike = or bicycle_road=yes or bicycle=yes or or bicycle=permissive bicycle=designated lcn=yes
assign ispaved = surface=paved|asphalt|concrete|paving_stones
assign isunpaved = not or surface= or ispaved surface=fine_gravel|cobblestone
assign probablyGood = or ispaved and ( or isbike highway=footway ) not isunpaved


#
# this is the cost (in Meter) for a 90-degree turn
# The actual cost is calculated as turncost*cos(angle)
# (Suppressing turncost while following longdistance-cycleways
# makes them a little bit more magnetic)
#
assign turncost = if is_ldcr then 0
                  else if junction=roundabout then 0
                  else 90


#
# for any change in initialclassifier, initialcost is added once
#
assign initialclassifier =
     if route=ferry then classifier_ferry
     else classifier_none


#
# calculate the initial cost
# this is added to the total cost each time the costfactor
# changed
#
assign initialcost =
     if ( equal initialclassifier classifier_ferry ) then 10000
     else 0

#
# implicit access here just from the motorroad tag
# (implicit access rules from highway tag handled elsewhere)
#
assign defaultaccess =
       if access= then not motorroad=yes
       else if access=private|no then false
       else true

#
# calculate logical bike access
#
assign bikeaccess =
       if any_cycleroute then true
# new hr
       else false
# de-activated begin hr
#       else if bicycle= then
#       (
#         if bicycle_road=yes then true
#         else if vehicle= then ( if highway=footway then false else defaultaccess )
#         else not vehicle=private|no
#       )
#       else not bicycle=private|no|dismount
# de-activated end hr

#
# calculate logical foot access
#
assign footaccess =
       if bikeaccess then true
       else if bicycle=dismount then true
       else if foot= then defaultaccess
       else not foot=private|no

#
# if not bike-, but foot-acess, just a moderate penalty,
# otherwise access is forbidden
#
assign accesspenalty =
       if bikeaccess then 0
       else if footaccess then 4
       else 10000

#
# handle one-ways. On primary roads, wrong-oneways should
# be close to forbidden, while on other ways we just add
# 4 to the costfactor (making it at least 5 - you are allowed
# to push your bike)
#
assign badoneway =
       if reversedirection=yes then
         if oneway:bicycle=yes then true
         else if oneway= then junction=roundabout
         else oneway=yes|true|1
       else oneway=-1

assign onewaypenalty =
       if ( badoneway ) then
       (
         if ( cycleway=opposite|opposite_lane|opposite_track ) then 0
         else if ( oneway:bicycle=no                         ) then 0
         else if ( highway=primary|primary_link              ) then 50
         else if ( highway=secondary|secondary_link          ) then 30
         else if ( highway=tertiary|tertiary_link            ) then 20
         else 4.0
       )
       else 0.0

#
# calculate the cost-factor, which is the factor
# by which the distance of a way-segment is multiplied
# to calculate the cost of that segment. The costfactor
# must be >=1 and it's supposed to be close to 1 for
# the type of way the routing profile is searching for
#
assign isresidentialorliving = or highway=residential|living_street living_street=yes
assign costfactor

  #
  # exclude rivers, rails etc.
  #
  if ( and highway= not route=ferry ) then 10000

  #
  # exclude motorways and proposed roads
  #
  else if ( highway=motorway|motorway_link ) then   10000
  else if ( highway=proposed|abandoned     ) then   10000

  #
  # all other exclusions below (access, steps, ferries,..)
  # should not be deleted by the decoder, to be available
  # in voice-hint-processing
  #
  else min 9999

  #
  # apply oneway-and access-penalties
  #
  add max onewaypenalty accesspenalty

  #
  # steps and ferries are special. Note this is handled
  # before the cycleroute-switch, to be able
  # to really exlude them be setting cost to infinity
  #
  if ( highway=steps ) then ( if allow_steps then 40 else 10000 )
  else if ( route=ferry   ) then ( if allow_ferries then 5.67 else 10000 )

  #
  # handle long-distance cycle-routes.
  #
  else if ( is_ldcr ) then 1                   # always treated as perfect (=1)
  else
  add ( if stick_to_cycleroutes then 0.5 else 0.05 )  # everything else somewhat up

  #
  # some other highway types
  #
  if      ( highway=pedestrian                ) then 3
  else if ( highway=bridleway                 ) then 5
  else if ( highway=cycleway                  ) then 1
  else if ( isresidentialorliving             ) then ( if isunpaved then 1.5 else 1.1 )
  else if ( highway=service                   ) then ( if isunpaved then 1.6 else 1.3 )

  #
  # tracks and track-like ways are rated mainly be tracktype/grade
  # But note that if no tracktype is given (mainly for road/path/footway)
  # it can be o.k. if there's any other hint for quality
  #
  else if ( highway=track|road|path|footway ) then
  (
    if      ( tracktype=grade1 ) then ( if probablyGood then 1.0 else 1.3 )
    else if ( tracktype=grade2 ) then ( if probablyGood then 1.1 else 2.0 )
    else if ( tracktype=grade3 ) then ( if probablyGood then 1.5 else 3.0 )
    else if ( tracktype=grade4 ) then ( if probablyGood then 2.0 else 5.0 )
    else if ( tracktype=grade5 ) then ( if probablyGood then 3.0 else 5.0 )
    else                              ( if probablyGood then 1.0 else 5.0 )
  )

  #
  # When avoiding unsafe ways, avoid highways without a bike hint
  #
  else add ( if ( and avoid_unsafe not isbike ) then 2 else 0 )

  #
  # actuals roads are o.k. if we have a bike hint
  #
       if ( highway=trunk|trunk_link         ) then ( if isbike then 1.5 else 10  )
  else if ( highway=primary|primary_link     ) then ( if isbike then 1.2 else  3  )
  else if ( highway=secondary|secondary_link ) then ( if isbike then 1.1 else 1.6 )
  else if ( highway=tertiary|tertiary_link   ) then ( if isbike then 1.0 else 1.4 )
  else if ( highway=unclassified             ) then ( if isbike then 1.0 else 1.3 )

  #
  # default for any other highway type not handled above
  #
  else 2.0


# way priorities used for voice hint generation

assign priorityclassifier =

  if      ( highway=motorway                          ) then  30
  else if ( highway=motorway_link                     ) then  29
  else if ( highway=trunk                             ) then  28
  else if ( highway=trunk_link                        ) then  27
  else if ( highway=primary                           ) then  26
  else if ( highway=primary_link                      ) then  25
  else if ( highway=secondary                         ) then  24
  else if ( highway=secondary_link                    ) then  23
  else if ( highway=tertiary                          ) then  22
  else if ( highway=tertiary_link                     ) then  21
  else if ( highway=unclassified                      ) then  20
  else if ( isresidentialorliving                     ) then  6
  else if ( highway=service                           ) then  6
  else if ( highway=cycleway                          ) then  6
  else if ( or bicycle=designated bicycle_road=yes    ) then  6
  else if ( highway=track                             ) then if tracktype=grade1 then 6 else 4
  else if ( highway=bridleway|road|path|footway       ) then  4
  else if ( highway=steps                             ) then  2
  else if ( highway=pedestrian                        ) then  2
  else 0

# some more classifying bits used for voice hint generation...

assign isbadoneway = not equal onewaypenalty 0
assign isgoodoneway = if reversedirection=yes then oneway=-1
                      else if oneway= then junction=roundabout else oneway=yes|true|1
assign isroundabout = junction=roundabout
assign islinktype = highway=motorway_link|trunk_link|primary_link|secondary_link|tertiary_link
assign isgoodforcars = if greater priorityclassifier 6 then true
                  else if ( or isresidentialorliving highway=service ) then true
                  else if ( and highway=track tracktype=grade1 ) then true
                  else false

# ... encoded into a bitmask

assign classifiermask add          isbadoneway
                      add multiply isgoodoneway   2
                      add multiply isroundabout   4
                      add multiply islinktype     8
                          multiply isgoodforcars 16


---context:node  # following code refers to node tags

assign defaultaccess =
       if ( access= ) then true # add default barrier restrictions here!
       else if ( access=private|no ) then false
       else true

assign bikeaccess =
       if nodeaccessgranted=yes then true
       else if bicycle= then
       (
         if vehicle= then defaultaccess
         else not vehicle=private|no
       )
       else not bicycle=private|no|dismount

assign footaccess =
       if bicycle=dismount then true
       else if foot= then defaultaccess
       else not foot=private|no

assign initialcost =
       if bikeaccess then 0
       else ( if footaccess then 100 else 1000000 )
