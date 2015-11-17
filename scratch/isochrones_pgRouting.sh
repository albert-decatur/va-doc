#!/bin/bash

# use isochrones to select features from one table given features from another
# output is $toJoin_loc_table locations whose nearest node is within $drive_time of $service_loc_table locations, for each $serivce_loc_table location
# respect oneways (using cost and reverse_cost)

db=va-doc # name of postgreSQL database, with PostGIS and pgRouting extensions enabled
service_loc_table=docs # name of table to 
service_nearest_node=docs_nearest_node
toJoin_loc_table=pop
toJoin_nearest_node=pop_nearest_node
drive_time=0.1 # calling this drive time assumes your cost and reverse cost network fields use time rather than say km
# EPSG code for input spatial reference system
EPSG=3969
# NB: this var is for testing purposes only
limit_var="limit 10"

function isochrone_sql { 
	# for each input service_loc_table gid, 
	# first get the nearest network node id
	# then get the geom of network nodes within a driving time of the selected node
	# then convert those into a convex hull (effectively the driving isochrone)
	# NB: hard coded values still there
	echo "
select doc_id,pcp,pop,pcp/pop*100000 as docs_per_100000 from
	$2
	join
	(select sum(pop10) as pop,$1 as doc_id
	from 
		$6
		join (select pop_id
		from
			$5
			join (select 
				'$1'::int as service_loc_id,
				edge_table_vertices_pgr.id as node_id 
			from 
				edge_table_vertices_pgr 
				join ( 
				select 
					id1 
					from 
						pgr_drivingdistance('SELECT gid AS id,source,target,cost_time as cost,rcost_time as reverse_cost FROM edge_table',(select node_id from $4 where doc_id=$1)::int,$3,false,true)) as driving_distance 
				on edge_table_vertices_pgr.id = driving_distance.id1) as serivce_area_nodes
		on ${5}.node_id = serivce_area_nodes.node_id) as toJoin
	on ${6}.blockid10 = toJoin.pop_id) as pop_within_serviceArea
on ${2}.objectid = $1
;
"
}
export -f isochrone_sql

# get list of service_loc_table ids
# NB: name of field objectid is hard coded from shp
echo "copy ( select objectid from $service_loc_table $limit_var) to stdout;" |\
# pass to postgresql db
psql $db |\
# for each serivce loc, get SQL to calculate drive time isochrone poly in pgRouting (given appropriate network table)
parallel -j 1 'isochrone_sql {} '$service_loc_table' '$drive_time' '$service_nearest_node' '$toJoin_nearest_node' '$toJoin_loc_table'' |\
# now actually execute this SQL on the db
psql $db
