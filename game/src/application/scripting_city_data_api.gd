class_name ScriptingCityDataApi
extends ScriptingApiBase
## The script functions that give the city as data: `city.cell` for one
## tile and `city.cells` for an area or the whole map. A program reads
## the city from these values and needs no image. See docs/scripting.md.

@warning_ignore_start("integer_division")

# the values of a cell, in the order of an answer. x and y are always there
const FIELDS: PackedStringArray = [
	"altitude", "slope", "water", "structure", "structureId", "zone", "density", "underground", "undergroundId",
	"powered", "needsPower", "watered", "piped", "sign", "traffic", "pollution", "landValue", "crime", "police", "fire",
	"populationDensity", "growth", "symbol",
]
const FORMAT_CELLS := "cells"
const FORMAT_COLUMNS := "columns"
# an area with more cells than this gets columns, when the script names no format
const MAX_DEFAULT_CELL_OBJECTS := 4096
# one answer holds this many values at most: cells times fields
const MAX_VALUES := 2000000

var city_api: ScriptingCityApi


func handlers() -> Dictionary[String, Callable]:
	return {
		"city.cell": _cell,
		"city.cells": _cells,
		"city.cellFields": func(_arguments: Array) -> Variant: return FIELDS,
	}


# cell(x, y): each value of one tile, and what the Query tool tells about it
func _cell(arguments: Array) -> Variant:
	if not need_city():
		return null

	var tile := point(arguments, 0)

	if not inside_map(tile):
		return fail("The tile %d, %d is outside the map." % [tile.x, tile.y])

	var source := Source.new(app.document_state.city)
	var result := {"x": tile.x, "y": tile.y}

	for field in FIELDS:
		result[field] = source.value(field, tile.x, tile.y)

	var query: Variant = city_api.handlers()["city.query"].call([{"x": tile.x, "y": tile.y}])

	if query is Dictionary:
		result["query"] = {
			"title": query.title, "kind": query.kind, "altitudeFeet": query.altitude, "landValue": query.landValue,
			"crime": query.crime, "pollution": query.pollution, "lines": query.lines, "flags": query.flags, "things": query.things,
			"text": query.text,
		}
	else:
		# a tile that the Query tool cannot read still has its stored values
		take_failure()

	return result


# cells(area, { fields, format, empty }): the values of each tile of an area, or of the whole map
func _cells(arguments: Array) -> Variant:
	if not need_city():
		return null

	var area := city_api._area(arguments, 0)

	if not area.has_area():
		return null

	var options: Dictionary = argument(arguments, 1, {}) if argument(arguments, 1, {}) is Dictionary else {}
	var fields := _fields(options.get("fields"))

	if fields.is_empty():
		return null

	var format := str(options.get("format", FORMAT_CELLS if area.get_area() <= MAX_DEFAULT_CELL_OBJECTS else FORMAT_COLUMNS))

	if format not in [FORMAT_CELLS, FORMAT_COLUMNS]:
		return fail("The format must be cells or columns.")

	if area.get_area() * fields.size() > MAX_VALUES:
		return fail("The answer would hold %d values, and %d is the limit. Ask for a smaller area, or for fewer fields: { fields: ['structure', 'zone'] }."
			% [area.get_area() * fields.size(), MAX_VALUES])

	var source := Source.new(app.document_state.city)
	var result := {
		"x": area.position.x, "y": area.position.y, "width": area.size.x, "height": area.size.y, "format": format,
		"fields": fields,
	}

	if format == FORMAT_COLUMNS:
		var columns := {}

		for field in fields:
			var values := []
			values.resize(area.get_area())
			var at := 0

			for y in range(area.position.y, area.end.y):
				for x in range(area.position.x, area.end.x):
					values[at] = source.value(field, x, y)
					at += 1

			columns[field] = values

		result["columns"] = columns

		return result

	var keep_empty := bool(options.get("empty", false))
	var cells := []

	for y in range(area.position.y, area.end.y):
		for x in range(area.position.x, area.end.x):
			var cell := {"x": x, "y": y}

			for field in fields:
				var value: Variant = source.value(field, x, y)

				# a cell tells only what it has, thus an answer for clear land is short
				if keep_empty or field == "altitude" or not _is_empty(value):
					cell[field] = value

			cells.append(cell)

	result["cells"] = cells

	return result


static func _is_empty(value: Variant) -> bool:
	return (value is String and (value as String).is_empty()) or (value is bool and not value) or (value is int and value == 0)


# the fields of an option, or each field without one. Empty, with a failure, for a wrong name
func _fields(value: Variant) -> PackedStringArray:
	if value == null:
		return FIELDS

	var result := PackedStringArray()

	for name: Variant in (value if value is Array else [value]):
		if not FIELDS.has(str(name)):
			fail("Unknown field %s. The fields are: %s." % [str(name), ", ".join(FIELDS)])

			return PackedStringArray()

		if not result.has(str(name)):
			result.append(str(name))

	if result.is_empty():
		fail("Name one field or more. The fields are: %s." % ", ".join(FIELDS))

	return result


## Reads the values of cells. It holds the tables that all cells share.
class Source extends RefCounted:
	var city: CityState
	var signs: Dictionary[int, String]
	# data map name -> the bytes of its chunk
	var data_maps: Dictionary[String, PackedByteArray] = {}

	func _init(value: CityState) -> void:
		city = value
		signs = city.sign_texts()
		signs.merge(CityNeighbors.connection_sign_texts(city))

		for name: String in ScriptingCityApi.DATA_MAPS:
			var chunk := city.document.find_chunk(ScriptingCityApi.DATA_MAPS[name])
			data_maps[name] = chunk.decoded_payload if chunk != null else PackedByteArray()

	func value(field: String, x: int, y: int) -> Variant:
		match field:
			"altitude":
				return city.land_altitude(x, y)
			"slope":
				return city.terrain_id(x, y) != TerrainTileIds.FLAT and not city.is_water(x, y)
			"water":
				return "" if not city.is_water(x, y) else ("salt" if city.is_salt_water(x, y) else "fresh")
			"structure":
				return QueryStrings.tile_name(city.building_id(x, y)) if city.building_id(x, y) != 0 else ""
			"structureId":
				return city.building_id(x, y)
			"zone":
				return _name(QueryInfo.ZONE_NAMES, city.zone_id(x, y))
			"density":
				return _name(QueryInfo.ZONE_DENSITIES, city.zone_id(x, y))
			"underground":
				return _name(QueryInfo.UNDERGROUND_NAMES, city.underground_id(x, y))
			"undergroundId":
				return city.underground_id(x, y)
			"powered":
				return city.is_powered(x, y)
			"needsPower":
				return city.is_powerable(x, y)
			"watered":
				return city.is_watered(x, y)
			"piped":
				return city.is_piped(x, y)
			"sign":
				return signs.get(city.index_of(x, y), "")
			"symbol":
				return CityTextMap.surface_symbol(city.building_id(x, y), city.zone_id(x, y), city.terrain_id(x, y), city.is_water(x, y))

		var bytes: PackedByteArray = data_maps.get(field, PackedByteArray())
		var at := CityDataGrid.index(bytes, city.map_size, x, y)

		return bytes[at] if at >= 0 else 0

	# the name of an id of 1 or more; an empty text for 0 and for an id without a name
	static func _name(names: PackedStringArray, id: int) -> String:
		return names[id] if id > 0 and id < names.size() else ""
