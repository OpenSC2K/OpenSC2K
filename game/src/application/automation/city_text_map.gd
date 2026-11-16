class_name CityTextMap
extends RefCounted
## A part of the city as text for scripts: one character for each tile, thus
## a program that cannot see the map can read it. Row `j` of the result is
## the tile row y + j, and character `i` of a row is the tile x + i.

@warning_ignore_start("integer_division")

const LAYERS: PackedStringArray = ["surface", "zones", "underground", "altitude", "power", "water"]
# the tiles of one text map at most
const MAX_TILES := 512 * 512
const ALTITUDE_DIGITS := "0123456789abcdefghijklmnopqrstuv"
const SURFACE_LEGEND := {
	".": "clear land", "/": "slope", "~": "water", "t": "trees", "%": "rubble", "!": "radioactive waste",
	"=": "road or road bridge", "#": "rail", "H": "highway or onramp", "+": "power line", "n": "tunnel entrance",
	"r": "empty residential zone", "c": "empty commercial zone", "i": "empty industrial zone",
	"m": "military zone", "a": "airport zone", "s": "seaport zone",
	"R": "residential building", "C": "commercial building", "I": "industrial building",
	"x": "construction", "X": "abandoned building",
	"P": "power plant", "W": "water pump, tower, treatment or desalinization", "S": "police, fire, hospital or prison",
	"E": "school, college, library or museum", "K": "park, zoo, stadium or marina",
	"T": "bus depot, rail station or subway station", "A": "airport or seaport structure",
	"G": "city hall, mayor's house, statue, church, arcology or other reward", "M": "military structure",
	"*": "other structure",
}
const ZONE_LEGEND := {
	".": "no zone", "~": "water", "r": "light residential", "R": "dense residential", "c": "light commercial",
	"C": "dense commercial", "i": "light industrial", "I": "dense industrial", "m": "military", "a": "airport", "s": "seaport",
}
const UNDERGROUND_LEGEND := {
	".": "nothing", "-": "water pipe", "s": "subway", "x": "pipe and subway", "S": "subway station",
	"n": "tunnel", "M": "missile silo", "?": "other",
}
const FLAG_LEGENDS := {
	"power": {".": "needs no power", "+": "powered", "!": "not powered", "~": "water"},
	"water": {".": "needs no water", "+": "watered", "!": "not watered", "-": "has a pipe, without water", "~": "water"},
}
const ZONE_SYMBOLS := ".rRcCiImas"
const EMPTY_ZONE_SYMBOLS := ".rrcciimas"
const Ids = preload("res://src/tools/shared/building_tile_ids.gd")


## { x, y, width, height, layer, legend, rows } for a rectangle of tiles.
## The rectangle is cut to the map.
static func build(city: CityState, area: Rect2i, layer: String) -> Dictionary:
	var map := Rect2i(0, 0, city.map_size, city.map_size)
	var cut := area.intersection(map)
	var rows := PackedStringArray()

	for y in range(cut.position.y, cut.end.y):
		var row := PackedByteArray()
		row.resize(cut.size.x)

		for x in range(cut.position.x, cut.end.x):
			row[x - cut.position.x] = _symbol(city, x, y, layer).unicode_at(0)

		rows.append(row.get_string_from_ascii())

	return {"x": cut.position.x, "y": cut.position.y, "width": cut.size.x, "height": cut.size.y, "layer": layer,
		"legend": legend(layer), "rows": rows}


static func legend(layer: String) -> Dictionary:
	match layer:
		"zones":
			return ZONE_LEGEND
		"underground":
			return UNDERGROUND_LEGEND
		"altitude":
			return {"0-9, a-v": "the land altitude, 0 to 31", "~": "water"}
		"power", "water":
			return FLAG_LEGENDS[layer]

	return SURFACE_LEGEND


static func _symbol(city: CityState, x: int, y: int, layer: String) -> String:
	match layer:
		"zones":
			return "~" if city.is_water(x, y) and city.zone_id(x, y) == 0 else _zone_symbol(city.zone_id(x, y), ZONE_SYMBOLS)
		"underground":
			var symbol := _underground_symbol(city.underground_id(x, y))

			return "n" if symbol == "." and city.tunnel_levels(x, y) > 0 else symbol
		"altitude":
			return "~" if city.is_water(x, y) else ALTITUDE_DIGITS[clampi(city.land_altitude(x, y), 0, ALTITUDE_DIGITS.length() - 1)]
		"power":
			if city.is_powered(x, y):
				return "+"

			return "!" if city.is_powerable(x, y) else ("~" if city.is_water(x, y) else ".")
		"water":
			if city.is_watered(x, y):
				return "+"

			if city.is_piped(x, y):
				return "-"

			return "!" if city.building_id(x, y) >= Ids.DEVELOPED_FIRST else ("~" if city.is_water(x, y) else ".")

	return surface_symbol(city.building_id(x, y), city.zone_id(x, y), city.terrain_id(x, y), city.is_water(x, y))


## The character of a tile on the surface layer.
static func surface_symbol(building: int, zone: int, terrain: int, water: bool) -> String:
	if building == Ids.EMPTY:
		if zone != 0:
			return _zone_symbol(zone, EMPTY_ZONE_SYMBOLS)

		if water:
			return "~"

		return "." if terrain == TerrainTileIds.FLAT else "/"

	if building <= Ids.RUBBLE_LAST:
		return "%"

	if building == Ids.RADIOACTIVE_WASTE:
		return "!"

	if building <= Ids.TREE_LAST:
		return "t"

	if building == Ids.SMALL_PARK:
		return "K"

	if building < Ids.DEVELOPED_FIRST:
		return _network_symbol(building)

	if building <= Ids.DEVELOPED_3X3_LAST:
		return _developed_symbol(building)

	return _structure_symbol(building)


static func _zone_symbol(zone: int, symbols: String) -> String:
	return symbols[zone] if zone >= 0 and zone < symbols.length() else "?"


static func _network_symbol(building: int) -> String:
	if building <= Ids.POWER_LINE_LAST or building == Ids.POWER_BRIDGE:
		return "+"

	if building <= Ids.LAST_ROAD:
		return "="

	if building <= Ids.RAIL_LAST:
		return "#"

	if building <= Ids.TUNNEL_LAST:
		return "n"

	if building <= Ids.ROAD_RAIL_CROSSING_2:
		return "="

	if building <= Ids.RAIL_POWER_CROSSING_2 or building in [Ids.RAIL_BRIDGE, Ids.RAIL_BRIDGE_PYLON] or building >= Ids.RAIL_SUBWAY_FIRST:
		return "#"

	if building <= Ids.HIGHWAY_POWER_CROSSING_2 or building >= Ids.ONRAMP_FIRST:
		return "H"

	# the road bridges
	return "="


static func _developed_symbol(building: int) -> String:
	for range_ids: Array in [
		[Ids.DEVELOPED_FIRST, Ids.RESIDENTIAL_1X1_LAST, "R"], [Ids.COMMERCIAL_1X1_FIRST, Ids.COMMERCIAL_1X1_LAST, "C"],
		[Ids.INDUSTRIAL_1X1_FIRST, Ids.INDUSTRIAL_1X1_LAST, "I"], [Ids.CONSTRUCTION_1X1_FIRST, Ids.CONSTRUCTION_1X1_LAST, "x"],
		[Ids.ABANDONED_1X1_FIRST, Ids.DEVELOPED_1X1_LAST, "X"], [Ids.RESIDENTIAL_2X2_FIRST, Ids.RESIDENTIAL_2X2_LAST, "R"],
		[Ids.COMMERCIAL_2X2_FIRST, Ids.COMMERCIAL_2X2_LAST, "C"], [Ids.INDUSTRIAL_2X2_FIRST, Ids.INDUSTRIAL_2X2_LAST, "I"],
		[Ids.CONSTRUCTION_2X2_FIRST, Ids.CONSTRUCTION_2X2_LAST, "x"], [Ids.ABANDONED_2X2_FIRST, Ids.DEVELOPED_2X2_LAST, "X"],
		[Ids.RESIDENTIAL_3X3_FIRST, Ids.RESIDENTIAL_3X3_LAST, "R"], [Ids.COMMERCIAL_3X3_FIRST, Ids.COMMERCIAL_3X3_LAST, "C"],
		[Ids.INDUSTRIAL_3X3_FIRST, Ids.INDUSTRIAL_3X3_LAST, "I"], [Ids.CONSTRUCTION_3X3_FIRST, Ids.CONSTRUCTION_3X3_LAST, "x"],
		[Ids.ABANDONED_3X3_FIRST, Ids.DEVELOPED_3X3_LAST, "X"],
	]:
		if building >= int(range_ids[0]) and building <= int(range_ids[1]):
			return range_ids[2]

	return "*"


static func _structure_symbol(building: int) -> String:
	if building <= Ids.LARGE_POWER_LAST:
		return "P"

	if building in [Ids.WATER_PUMP, Ids.WATER_TOWER, Ids.WATER_TREATMENT, Ids.DESALINIZATION]:
		return "W"

	if building in [Ids.POLICE_STATION, Ids.FIRE_STATION, Ids.HOSPITAL, Ids.PRISON]:
		return "S"

	if building in [Ids.SCHOOL, Ids.COLLEGE, Ids.LIBRARY, Ids.MUSEUM]:
		return "E"

	if building in [Ids.BIG_PARK, Ids.ZOO, Ids.STADIUM, Ids.MARINA]:
		return "K"

	if building in [Ids.SUBWAY_STATION, Ids.BUS_DEPOT, Ids.RAIL_STATION]:
		return "T"

	if building in [Ids.RUNWAY, Ids.RUNWAY_CROSSING, Ids.PIER, Ids.CRANE, Ids.CONTROL_TOWER_1, Ids.SEAPORT_WAREHOUSE,
			Ids.AIRPORT_BUILDING_1, Ids.AIRPORT_BUILDING_2, Ids.TARMAC, Ids.HANGAR_1, Ids.PARKING_LOT_1, Ids.PARKING_LOT_2,
			Ids.LOADING_BAY, Ids.CARGO_YARD]:
		return "A"

	if building in [Ids.CONTROL_TOWER_2, Ids.FIGHTER_JET, Ids.RADAR, Ids.TOP_SECRET, Ids.HANGAR_2, Ids.MISSILE_SILO]:
		return "M"

	if building in [Ids.CITY_HALL, Ids.STATUE, Ids.MAYOR_HOUSE, Ids.CHURCH, Ids.LLAMA_DOME] or building >= Ids.ARCOLOGY_FIRST:
		return "G"

	return "*"


static func _underground_symbol(id: int) -> String:
	if id == UndergroundTileIds.EMPTY:
		return "."

	if id <= UndergroundTileIds.SUBWAY_LAST:
		return "s"

	if id <= UndergroundTileIds.PIPE_LAST:
		return "-"

	if id in [UndergroundTileIds.PIPE_TB_SUBWAY_LR, UndergroundTileIds.PIPE_LR_SUBWAY_TB]:
		return "x"

	if id == UndergroundTileIds.SUBWAY_ENTRANCE:
		return "S"

	if id == UndergroundTileIds.MISSILE_SILO:
		return "M"

	return "?"
