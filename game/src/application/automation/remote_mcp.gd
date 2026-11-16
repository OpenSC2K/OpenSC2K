class_name RemoteMcp
extends RefCounted
## The Model Context Protocol on the /mcp route of the remote API, thus an
## MCP client such as an LLM agent uses the game as a tool server. This is
## the Streamable HTTP transport without a server stream: each POST holds
## one JSON-RPC message and receives one JSON answer. The tools run scripts,
## read the game state, capture the window, draw the city and return the API
## reference.

const PROTOCOL_VERSIONS: PackedStringArray = ["2025-06-18", "2025-03-26", "2024-11-05"]
const PARSE_ERROR := -32700
const INVALID_REQUEST := -32600
const METHOD_NOT_FOUND := -32601
const INVALID_PARAMS := -32602
const INSTRUCTIONS := ("OpenSC2K is an open-source remake of SimCity 2000. Call the guide tool first: it explains the game API. "
	+ "The eval tool runs JavaScript in the game and returns its value. The state tool tells what the game shows now.")
const TOOLS := [
	{
		"name": "eval",
		"description": ("Run JavaScript in the game with the game API (game, city, budget, sim, tools, view, ui, input) "
			+ "and return the value of the last expression as JSON, then the console output. Top-level await is permitted. "
			+ "Declarations stay for the next call. Example: tools.select('Roads', 'Road'); tools.apply([30, 30], [40, 30])"),
		"inputSchema": {
			"type": "object",
			"properties": {
				"source": {"type": "string", "description": "The JavaScript source."},
				"timeout_ms": {"type": "integer", "description": "How long to wait for a promise. The default is 30000."},
			},
			"required": ["source"],
		},
	},
	{
		"name": "state",
		"description": ("Return game.state(): the screen, the city values, the selected tool, the open windows and dialogs, "
			+ "and what waits for an answer."),
		"inputSchema": {"type": "object", "properties": {}},
	},
	{
		"name": "city_data",
		"description": ("Return the city as JSON data, without an image. Give x and y for each value of one cell: the "
			+ "structure, the zone, the terrain, power, water, the data maps and what the Query tool tells. Give x, y, width "
			+ "and height for the cells of an area. Give nothing for the whole city with its main values."),
		"inputSchema": {
			"type": "object",
			"properties": {
				"x": {"type": "integer", "description": "The tile column of the cell, or the first column of the area."},
				"y": {"type": "integer", "description": "The tile row of the cell, or the first row of the area."},
				"width": {"type": "integer", "description": "The number of tile columns of the area."},
				"height": {"type": "integer", "description": "The number of tile rows of the area."},
				"fields": {"type": "array", "items": {"type": "string"},
					"description": "The values to return, such as structure, zone, powered. The default is each value."},
				"format": {"type": "string", "enum": ["cells", "columns"],
					"description": "cells: one object for each cell, without its empty values. columns: one array for each value. "
						+ "The default is cells for 4096 cells or fewer."},
				"empty": {"type": "boolean", "description": "With the cells format: also return the empty values of each cell."},
			},
		},
	},
	{
		"name": "screenshot",
		"description": "Return a PNG image of the game window. A headless game has no image.",
		"inputSchema": {
			"type": "object",
			"properties": {"scale": {"type": "number", "description": "From 0.05 to 1. A smaller image costs less. The default is 1."}},
		},
	},
	{
		"name": "city_image",
		"description": ("Return a PNG image of the city, drawn as the game draws it. A headless game can do this. "
			+ "Give x, y, width and height in tiles to get only that part: a small area is a small image."),
		"inputSchema": {
			"type": "object",
			"properties": {
				"x": {"type": "integer", "description": "The first tile column of the area."},
				"y": {"type": "integer", "description": "The first tile row of the area."},
				"width": {"type": "integer", "description": "The number of tile columns."},
				"height": {"type": "integer", "description": "The number of tile rows."},
				"size": {"type": "string", "enum": ["small", "medium", "large"],
					"description": "The size of the tiles. The default is small: a tile is 8 pixels wide. Large is 32."},
				"view": {"type": "string", "description": "city (the default) or underground."},
			},
		},
	},
	{
		"name": "control_image",
		"description": ("Return a PNG picture of a control that draws its content, such as the pixel canvas of the SCURK "
			+ "editor. A headless game can do this. The eval of ui.controls() marks such a control with image: true."),
		"inputSchema": {
			"type": "object",
			"properties": {
				"target": {"type": "string", "description": "The id or the name of the control. The default is the first such control of the top window."},
				"scale": {"type": "integer", "description": "From 1 to 16: each picture pixel becomes this many pixels wide. The default is 1."},
			},
		},
	},
	{
		"name": "guide",
		"description": "Return how to play the game through this API. With types true, also the TypeScript declarations of every function.",
		"inputSchema": {
			"type": "object",
			"properties": {"types": {"type": "boolean", "description": "Add the TypeScript declarations of the game API."}},
		},
	},
]

## Answers one request of the /mcp route. `api` runs the tools.
static func handle(request: RemoteHttpRequest, api: ApplicationRemoteApi) -> void:
	if request.method != "POST":
		request.respond(405, RemoteHttpRequest.JSON_TYPE, PackedByteArray(), {"Allow": "POST"})

		return

	var message: Variant = request.body_json()

	if not message is Dictionary:
		request.respond_json(400, _error(null, PARSE_ERROR if message == null else INVALID_REQUEST, "Send one JSON-RPC message."))

		return

	var id: Variant = message.get("id")
	var method: Variant = message.get("method")

	# the JSON parser reads each number as a float; the answer needs the id as the client wrote it
	if id is float and is_equal_approx(id, roundf(id)):
		id = int(id)

	# a notification or an answer of the client needs no answer
	if not method is String or id == null:
		request.respond(202, RemoteHttpRequest.JSON_TYPE, PackedByteArray())

		return

	var parameters: Dictionary = message.get("params") if message.get("params") is Dictionary else {}

	match method:
		"initialize":
			request.respond_json(200, _result(id, _initialize(parameters)))
		"ping":
			request.respond_json(200, _result(id, {}))
		"tools/list":
			request.respond_json(200, _result(id, {"tools": TOOLS}))
		"tools/call":
			_call_tool(request, id, parameters, api)
		_:
			request.respond_json(200, _error(id, METHOD_NOT_FOUND, "The method %s is not supported." % method))


static func _initialize(parameters: Dictionary) -> Dictionary:
	var requested := str(parameters.get("protocolVersion", ""))

	return {
		"protocolVersion": requested if PROTOCOL_VERSIONS.has(requested) else PROTOCOL_VERSIONS[0],
		"capabilities": {"tools": {}},
		"serverInfo": {
			"name": "opensc2k", "title": "OpenSC2K", "version": str(ProjectSettings.get_setting("application/config/version", "")),
		},
		"instructions": INSTRUCTIONS,
	}


static func _call_tool(request: RemoteHttpRequest, id: Variant, parameters: Dictionary, api: ApplicationRemoteApi) -> void:
	var arguments: Dictionary = parameters.get("arguments") if parameters.get("arguments") is Dictionary else {}

	match str(parameters.get("name", "")):
		"eval":
			if not arguments.get("source") is String:
				request.respond_json(200, _error(id, INVALID_PARAMS, "The eval tool needs a source text."))

				return

			var timeout: Variant = arguments.get("timeout_ms", 0)
			api.run_script(arguments.source, int(timeout) if typeof(timeout) in [TYPE_INT, TYPE_FLOAT] else 0,
				func(result: Dictionary) -> void: request.respond_json(200, _result(id, _script_content(result))))
		"state":
			api.run_script(ApplicationRemoteApi.STATE_SOURCE, 0,
				func(result: Dictionary) -> void: request.respond_json(200, _result(id, _script_content(result))))
		"city_data":
			api.run_script(ApplicationRemoteApi.city_data_source(arguments), 0,
				func(result: Dictionary) -> void: request.respond_json(200, _result(id, _script_content(result))))
		"screenshot":
			var scale: Variant = arguments.get("scale", 1.0)
			api.capture_window(float(scale) if typeof(scale) in [TYPE_INT, TYPE_FLOAT] else 1.0,
				func(png: PackedByteArray, error: String) -> void: request.respond_json(200, _result(id, _image_content(png, error))))
		"city_image":
			api.capture_city(ApplicationRemoteApi.city_image_options(arguments),
				func(png: PackedByteArray, error: String) -> void: request.respond_json(200, _result(id, _image_content(png, error))))
		"control_image":
			var factor: Variant = arguments.get("scale", 1)
			var picture := api.control_image(arguments.get("target", ""), int(factor) if typeof(factor) in [TYPE_INT, TYPE_FLOAT] else 1)
			request.respond_json(200, _result(id, _image_content(picture.get("png", PackedByteArray()), str(picture.error))))
		"guide":
			var text := api.guide_text()

			if bool(arguments.get("types", false)):
				text += "\n\n## TypeScript declarations\n\n```ts\n%s\n```\n" % api.types_text()

			request.respond_json(200, _result(id, _text_content(text, false)))
		_:
			request.respond_json(200, _error(id, INVALID_PARAMS, "Unknown tool: %s." % str(parameters.get("name", ""))))


# the value of a script, then its console output, as the text of a tool result
static func _script_content(result: Dictionary) -> Dictionary:
	var ok := bool(result.ok)
	var text := str(result.value) if ok else "Error: %s" % str(result.get("error", ""))
	var lines := PackedStringArray()

	for line: Dictionary in result.get("console", []):
		lines.append(str(line.text) if line.level == "log" else "[%s] %s" % [line.level, line.text])

	if not lines.is_empty():
		text += "\n\nConsole:\n" + "\n".join(lines)

	return _text_content(text, not ok)


static func _image_content(png: PackedByteArray, error: String) -> Dictionary:
	if not error.is_empty():
		return _text_content(error, true)

	return {"content": [{"type": "image", "data": Marshalls.raw_to_base64(png), "mimeType": "image/png"}], "isError": false}


static func _text_content(text: String, is_error: bool) -> Dictionary:
	return {"content": [{"type": "text", "text": text}], "isError": is_error}


static func _result(id: Variant, result: Dictionary) -> Dictionary:
	return {"jsonrpc": "2.0", "id": id, "result": result}


static func _error(id: Variant, code: int, message: String) -> Dictionary:
	return {"jsonrpc": "2.0", "id": id, "error": {"code": code, "message": message}}
