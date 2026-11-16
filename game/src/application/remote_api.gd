class_name ApplicationRemoteApi
extends RefCounted
## The remote API: a program outside the game, such as an LLM agent, plays
## the game through a local HTTP port. A request runs JavaScript in the
## console script runtime, with the game API of scripts, and receives the
## value as JSON. Other routes return the game state, an image of the window,
## an image of the city or of some of its tiles, and the API reference. /mcp speaks the Model Context Protocol. The server
## is off until the command line has --api or the console command `api`
## starts it. See docs/remote-api.md.

const OPTION := "--api"
const DEFAULT_PORT := 9240
# a request waits this long for the promise of its script
const DEFAULT_TIMEOUT_MSEC := 30000
const MAX_TIMEOUT_MSEC := 600000
# a script can run this long without a pause; the game does not draw meanwhile
const MAX_RUN_MSEC := 60000
# the console lines of one answer, newest last
const MAX_CONSOLE_LINES := 200
const GUIDE_PATH := "res://assets/scripting/remote-api.md"
const TYPES_PATH := "res://assets/scripting/opensc2k.d.ts"
const STATE_SOURCE := "game.state()"
const LEVEL_NAMES := {
	ConsoleLog.Level.MESSAGE: "log", ConsoleLog.Level.ERROR_OUTPUT: "error", ConsoleLog.Level.WARNING: "warning",
	ConsoleLog.Level.ERROR: "error", ConsoleLog.Level.RESULT: "log",
}

var app: CityApplication
var server := RemoteHttpServer.new()
# request id -> the script that waits for its value
var _pending: Dictionary[int, PendingScript] = {}
var _next_id := 1
# the image requests that wait for the end of the frame
var _captures: Array[Callable] = []


func _init(application: CityApplication) -> void:
	app = application
	server.handler = _handle


## Starts the server when the command line has --api or --api=PORT.
func apply_command_line(arguments: PackedStringArray) -> void:
	for argument in arguments:
		var port := -1

		if argument == OPTION:
			port = DEFAULT_PORT
		elif argument.begins_with(OPTION + "=") and argument.get_slice("=", 1).is_valid_int():
			port = int(argument.get_slice("=", 1))

		if port >= 0:
			var error := start(port)

			# the program that started the game reads its output
			if not error.is_empty():
				printerr("The remote API cannot start. %s" % error)


func attach_console(commands: ConsoleCommands) -> void:
	commands.register("api", "Let other programs control the game on a local port: api [port], or api off.", _command)


func _command(words: PackedStringArray) -> String:
	if not words.is_empty() and words[0].to_lower() == "off":
		stop()

		return "The remote API stopped."

	if not words.is_empty() and (not words[0].is_valid_int() or int(words[0]) < 0 or int(words[0]) > 65535):
		ConsoleLog.append(ConsoleLog.Level.ERROR_OUTPUT, "The port must be a number from 0 to 65535.")

		return ""

	var error := start(int(words[0]) if not words.is_empty() else DEFAULT_PORT)

	if not error.is_empty():
		ConsoleLog.append(ConsoleLog.Level.ERROR_OUTPUT, error)

	return ""


## Starts the server on 127.0.0.1. Port 0 selects a free port. Returns an
## empty text, or why it cannot start.
func start(port := DEFAULT_PORT) -> String:
	var error := server.start(port)

	if error.is_empty():
		_size_headless_window()
		# a line that a program which started the game can wait for
		print("The remote API listens on %s" % url())

	return error


# a headless game has a window of a few pixels, in which each control is
# smaller than one pixel. Callers get places in whole pixels, thus the
# window gets the size of the project
func _size_headless_window() -> void:
	if DisplayServer.get_name() == "headless":
		app.get_tree().root.size = Vector2i(int(ProjectSettings.get_setting("display/window/size/viewport_width")),
			int(ProjectSettings.get_setting("display/window/size/viewport_height")))


func stop() -> void:
	for id: int in _pending.keys():
		_finish(id, false, "The remote API stopped.")

	server.stop()


func is_running() -> bool:
	return server.is_listening()


func url() -> String:
	return "http://%s:%d" % [RemoteHttpServer.ADDRESS, server.port()] if is_running() else ""


func process() -> void:
	if not is_running():
		return

	server.poll()
	var now := Time.get_ticks_msec()

	for id: int in _pending.keys():
		if now >= _pending[id].deadline_msec:
			_finish(id, false, "The script did not finish in %d ms. It continues in the game." % _pending[id].timeout_msec, true)


func close() -> void:
	stop()


## Runs JavaScript and calls `done(result)` when its value settles:
## { ok, value (JSON text), error, console, timedOut }. The script runs as
## console input in a block of its own: `let`, `const` and `class` names
## end with the request, thus the next request can use the same names.
## `var` and function declarations stay, as do the values of globalThis.
func run_script(source: String, timeout_msec: int, done: Callable) -> void:
	if not app.scripting.start():
		done.call({"ok": false, "error": "The script runtime cannot start.", "console": []})

		return

	var id := _next_id
	_next_id += 1
	var pending := PendingScript.new()
	pending.done = done
	pending.timeout_msec = clampi(timeout_msec if timeout_msec > 0 else DEFAULT_TIMEOUT_MSEC, 1, MAX_TIMEOUT_MSEC)
	pending.deadline_msec = Time.get_ticks_msec() + pending.timeout_msec
	pending.console_serial = ConsoleLog.latest_serial()
	_pending[id] = pending
	# the script can take as long as its request waits
	var runtime := app.scripting.runtime
	var limit := runtime.get_time_limit_msec()
	runtime.set_time_limit_msec(clampi(pending.timeout_msec, limit, MAX_RUN_MSEC))
	var started := runtime.eval_request("{%s\n}" % source, id)

	if app.scripting.runtime == runtime:
		runtime.set_time_limit_msec(limit)

	if not bool(started.ok):
		_finish(id, false, str(started.error))


## The value of a request settled: the script runtime calls this through the
## `request` host function.
func on_script_result(id: int, ok: bool, json: String) -> void:
	_finish(id, ok, json)


func _finish(id: int, ok: bool, json: String, timed_out := false) -> void:
	var pending: PendingScript = _pending.get(id)

	if pending == null:
		return

	_pending.erase(id)
	var result := {"ok": ok, "console": _console_lines(pending.console_serial)}

	if ok:
		result["value"] = json
	else:
		result["error"] = json

	if timed_out:
		result["timedOut"] = true

	pending.done.call(result)


# the console output since the request started: [{ level, text }]
func _console_lines(serial: int) -> Array:
	var lines := []

	for entry in ConsoleLog.entries_since(serial):
		if entry.level != ConsoleLog.Level.INPUT:
			lines.append({"level": LEVEL_NAMES.get(entry.level, "log"), "text": entry.text})

	return lines.slice(maxi(0, lines.size() - MAX_CONSOLE_LINES))


## The answer of a script as JSON text. The value of the script is JSON
## text already.
static func result_json(result: Dictionary) -> String:
	var parts := PackedStringArray(['"ok":%s' % ("true" if bool(result.ok) else "false")])

	if result.has("value"):
		parts.append('"value":%s' % str(result.value))

	if result.has("error"):
		parts.append('"error":%s' % JSON.stringify(str(result.error)))

	if result.has("timedOut"):
		parts.append('"timedOut":true')

	parts.append('"console":%s' % JSON.stringify(result.get("console", [])))

	return "{%s}" % ",".join(parts)


## Calls `done(png: PackedByteArray, error: String)` with an image of the
## game window after the current frame is drawn. `scale` makes the image
## smaller.
func capture_window(scale: float, done: Callable) -> void:
	if DisplayServer.get_name() == "headless":
		done.call(PackedByteArray(), "A headless game draws no image. Start the game with a window, or use city.exportPng().")

		return

	_captures.append(_send_capture.bind(scale, done))

	if _captures.size() == 1:
		RenderingServer.frame_post_draw.connect(_run_captures, CONNECT_ONE_SHOT)


func _run_captures() -> void:
	var captures := _captures
	_captures = []

	for capture in captures:
		capture.call()


func _send_capture(scale: float, done: Callable) -> void:
	var image := app.get_viewport().get_texture().get_image()

	if image == null or image.is_empty():
		done.call(PackedByteArray(), "The window has no image.")

		return

	var factor := clampf(scale, 0.05, 1.0)

	if factor < 1.0:
		image.resize(maxi(1, int(image.get_width() * factor)), maxi(1, int(image.get_height() * factor)), Image.INTERPOLATE_LANCZOS)

	done.call(image.save_png_to_buffer(), "")


## Calls `done(png: PackedByteArray, error: String)` with an image of the
## city, or of the tiles of `options.area` only. `options` are those of
## city.exportPng. A headless game can do this.
func capture_city(options: Dictionary, done: Callable) -> void:
	var path := OS.get_temp_dir().path_join("opensc2k-city-%d-%d.png" % [OS.get_process_id(), _next_id])

	run_script("await city.exportPng(%s, %s)" % [JSON.stringify(path), JSON.stringify(options)], MAX_TIMEOUT_MSEC,
		func(result: Dictionary) -> void:
			var png := FileAccess.get_file_as_bytes(path) if bool(result.ok) else PackedByteArray()
			DirAccess.remove_absolute(path)
			done.call(png, "" if bool(result.ok) else str(result.error)))


## The options of city.exportPng from the values of a query or of a tool
## call: x, y, width and height make the area.
## The picture of a control that draws its content, such as the canvas of
## the SCURK editor: { png, error }. A headless game can do this. See ScriptingUiApi.control_png.
func control_image(target: Variant, scale: int) -> Dictionary:
	if app.scripting == null or app.scripting.api == null:
		return {"error": "The game did not start yet."}

	return app.scripting.api.ui_api.control_png(target, scale)


## The script that gives the city as data, from the values of a request:
## { x, y } is one cell; { x, y, width, height } is an area; without them
## the whole city, with its main values. `fields` (names with commas, or an
## array), `format` and `empty` are the options of city.cells.
static func city_data_source(values: Dictionary) -> String:
	var has_point := values.has("x") and values.has("y")
	var has_size := values.has("width") or values.has("height")

	if has_point and not has_size:
		return "city.cell(%d, %d)" % [int(str(values.x)), int(str(values.y))]

	var options := {}
	var fields: Variant = values.get("fields")

	if fields is String and not str(fields).is_empty():
		fields = Array(str(fields).split(",", false)).map(func(name: String) -> String: return name.strip_edges())

	if fields is Array:
		options["fields"] = fields

	if values.has("format"):
		options["format"] = str(values.format)

	if values.has("empty"):
		options["empty"] = str(values.empty).to_lower() in ["true", "1"]

	if not has_point and not has_size:
		return "({ city: city.info(), census: city.census(), ...city.cells(null, %s) })" % JSON.stringify(options)

	var area := {}

	for key: String in ["x", "y", "width", "height"]:
		if values.has(key):
			area[key] = int(str(values[key]))

	return "city.cells(%s, %s)" % [JSON.stringify(area), JSON.stringify(options)]


static func city_image_options(values: Dictionary) -> Dictionary:
	var options := {}
	var area := {}

	for key: String in ["x", "y", "width", "height"]:
		if str(values.get(key, "")).is_valid_float():
			area[key] = int(float(str(values[key])))

	if not area.is_empty():
		options["area"] = area

	for key: String in ["size", "view"]:
		if values.has(key):
			options[key] = str(values[key])

	for key: String in ["signs", "movingThings", "transparent"]:
		if values.has(key):
			options[key] = str(values[key]).to_lower() in ["true", "1"]

	return options


func guide_text() -> String:
	return FileAccess.get_file_as_string(GUIDE_PATH)


func types_text() -> String:
	return FileAccess.get_file_as_string(TYPES_PATH)


func _handle(request: RemoteHttpRequest) -> void:
	match request.path:
		"/":
			_respond_index(request)
		"/eval":
			_handle_eval(request)
		"/state":
			run_script(STATE_SOURCE, DEFAULT_TIMEOUT_MSEC, func(result: Dictionary) -> void:
				request.respond_json_text(200, result_json(result)))
		"/city-data":
			run_script(city_data_source(request.query), DEFAULT_TIMEOUT_MSEC, func(result: Dictionary) -> void:
				request.respond_json_text(200 if bool(result.ok) else 400, result_json(result)))
		"/screenshot":
			_handle_screenshot(request)
		"/city-image":
			capture_city(city_image_options(request.query), func(png: PackedByteArray, error: String) -> void:
				if error.is_empty():
					request.respond(200, "image/png", png)
				else:
					request.respond_error(400, error))
		"/control-image":
			var picture := control_image(request.query.get("target", ""), str(request.query.get("scale", "1")).to_int())

			if str(picture.error).is_empty():
				request.respond(200, "image/png", picture.png)
			else:
				request.respond_error(400, picture.error)
		"/guide":
			request.respond_text(200, guide_text(), "text/markdown; charset=utf-8")
		"/types":
			request.respond_text(200, types_text())
		"/mcp":
			RemoteMcp.handle(request, self)
		_:
			request.respond_error(404, "No such route. GET / lists the routes.")


func _respond_index(request: RemoteHttpRequest) -> void:
	request.respond_json(200, {
		"name": "OpenSC2K remote API",
		"version": str(ProjectSettings.get_setting("application/config/version", "")),
		"routes": {
			"POST /eval": "Run JavaScript with the game API. The body is the source, or JSON { source, timeout }. "
				+ "Answers { ok, value, error, console }.",
			"GET /state": "The value of game.state(): the screen, the city, the open windows and what waits for an answer.",
			"GET /city-data": "The city as JSON, without an image. ?x=40&y=40 gives each value of one cell; "
				+ "?x=40&y=40&width=8&height=8 the cells of an area; no query the whole city. ?fields=structure,zone "
				+ "selects values. Answers { ok, value, error }.",
			"GET /screenshot": "A PNG image of the game window. ?scale=0.5 makes it smaller.",
			"GET /city-image": "A PNG image of the city, also from a headless game. ?x=40&y=40&width=12&height=12 gives "
				+ "only those tiles. ?size=small, medium or large is the size of the tiles.",
			"GET /control-image": "A PNG picture of a control that draws its content, such as the canvas of the SCURK "
				+ "editor, also from a headless game. ?target= names the control, ?scale=8 makes each pixel larger.",
			"GET /guide": "How to play the game through this API.",
			"GET /types": "The TypeScript declarations of the game API.",
			"POST /mcp": "The Model Context Protocol, for MCP clients.",
		},
	})


func _handle_eval(request: RemoteHttpRequest) -> void:
	if request.method != "POST":
		request.respond_error(405, "Send the script with POST.")

		return

	var source := request.body_text()
	var timeout := int(request.query.get("timeout", "0"))

	if request.header("content-type").begins_with(RemoteHttpRequest.JSON_TYPE):
		var data: Variant = request.body_json()

		if not data is Dictionary or not data.get("source") is String:
			request.respond_error(400, "A JSON body must be { \"source\": \"...\" }.")

			return

		source = data.source
		timeout = int(data.get("timeout", timeout)) if typeof(data.get("timeout", 0)) in [TYPE_INT, TYPE_FLOAT] else timeout

	run_script(source, timeout, func(result: Dictionary) -> void:
		request.respond_json_text(200, result_json(result)))


func _handle_screenshot(request: RemoteHttpRequest) -> void:
	var scale: String = request.query.get("scale", "1")

	capture_window(float(scale) if scale.is_valid_float() else 1.0, func(png: PackedByteArray, error: String) -> void:
		if error.is_empty():
			request.respond(200, "image/png", png)
		else:
			request.respond_error(503, error))


## A script of a request that waits for its value.
class PendingScript extends RefCounted:
	# (result: Dictionary) -> void
	var done: Callable
	var timeout_msec := 0
	var deadline_msec := 0
	# the newest console entry when the script started
	var console_serial := 0
