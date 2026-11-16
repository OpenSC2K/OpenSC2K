extends SceneTree
## The remote API in the running application: a client outside the script
## runtime plays the game through the local HTTP port. It runs scripts and
## gets JSON values, also after a promise; reads the state; starts, opens
## and saves cities; builds and runs the simulation; answers a prompt; uses
## the menu bar, the windows and the mouse; and speaks MCP. The server
## refuses requests of web pages.

const AppFixture = preload("res://tests/support/app_fixture.gd")
const GameSpeed = preload("res://src/simulation/core/game_speed_controller.gd")

var main: CityApplication
var port := 0
var folder := ""


func _initialize() -> void:
	_run.call_deferred()


func _run() -> void:
	main = (load("res://main.tscn") as PackedScene).instantiate() as CityApplication
	AppFixture.configure(main)
	root.add_child(main)
	await process_frame
	assert(main.asset_state.assets_ready and not main.remote_api.is_running(), "The remote API is off until it is started")
	main.console_window.commands.execute("api 0")
	assert(main.remote_api.is_running(), "The api command starts the server")
	port = main.remote_api.server.port()
	folder = OS.get_user_data_dir().path_join("remote_api_test")
	DirAccess.make_dir_recursive_absolute(folder)

	await _check_routes()
	await _check_scripts()
	await _check_city_files()
	await _check_play()
	await _check_interface()
	await _check_mcp()

	main.console_window.commands.execute("api off")
	assert(not main.remote_api.is_running(), "The api command stops the server")
	main.queue_free()
	await process_frame
	print("PASS: remote API routes, scripts, city files, play, interface control and MCP")
	quit()


# sends one HTTP request to the game and waits for the answer: { status, type, text }
func _request(method: HTTPClient.Method, path: String, body := "", headers := PackedStringArray()) -> Dictionary:
	var client := HTTPClient.new()
	assert(client.connect_to_host("127.0.0.1", port) == OK)

	while client.get_status() in [HTTPClient.STATUS_CONNECTING, HTTPClient.STATUS_RESOLVING]:
		client.poll()
		await process_frame

	assert(client.get_status() == HTTPClient.STATUS_CONNECTED, "The client connects to the game")
	assert(client.request(method, path, headers, body) == OK)

	while client.get_status() == HTTPClient.STATUS_REQUESTING:
		client.poll()
		await process_frame

	var bytes := PackedByteArray()

	while client.get_status() == HTTPClient.STATUS_BODY:
		client.poll()
		bytes.append_array(client.read_response_body_chunk())
		await process_frame

	var type := ""

	for header in client.get_response_headers():
		if header.to_lower().begins_with("content-type:"):
			type = header.get_slice(":", 1).strip_edges()

	return {"status": client.get_response_code(), "type": type, "size": bytes.size(),
		"text": "" if type.begins_with("image/") else bytes.get_string_from_utf8()}


# runs JavaScript through POST /eval: the answer { ok, value, error, console }
func _eval(source: String, timeout := 0) -> Dictionary:
	var answer := await _request(HTTPClient.METHOD_POST, "/eval" + ("?timeout=%d" % timeout if timeout > 0 else ""), source)
	assert(answer.status == 200 and str(answer.type).begins_with("application/json"), str(answer))

	return JSON.parse_string(answer.text)


# the value of a script that must succeed
func _value(source: String) -> Variant:
	var answer := await _eval(source)
	assert(bool(answer.ok), "%s failed: %s" % [source, str(answer.get("error", ""))])

	return answer.value


func _check_routes() -> void:
	var index := await _request(HTTPClient.METHOD_GET, "/")
	assert(index.status == 200 and JSON.parse_string(index.text).routes.has("POST /eval"), "GET / lists the routes")
	var state: Dictionary = JSON.parse_string((await _request(HTTPClient.METHOD_GET, "/state")).text)
	assert(bool(state.ok) and state.value.screen == "main-menu" and state.value.city == null, "GET /state tells what shows")
	assert(state.value.windows[0].buttons.has("Start New City"), "The state lists the windows and their buttons")
	var types := await _request(HTTPClient.METHOD_GET, "/types")
	assert(types.status == 200 and str(types.text).contains("interface GameInput"), "GET /types returns the declarations")
	assert((await _request(HTTPClient.METHOD_GET, "/guide")).status == 200)
	assert((await _request(HTTPClient.METHOD_GET, "/missing")).status == 404)
	assert((await _request(HTTPClient.METHOD_GET, "/eval")).status == 405, "A script needs POST")
	var screenshot := await _request(HTTPClient.METHOD_GET, "/screenshot")

	if DisplayServer.get_name() == "headless":
		assert(screenshot.status == 503 and str(screenshot.text).contains("headless"), "A headless game has no image")
	else:
		assert(screenshot.status == 200 and screenshot.type == "image/png" and int(screenshot.size) > 100)

	# a web page cannot use the port: its requests carry an Origin, or another Host
	var page := await _request(HTTPClient.METHOD_POST, "/eval", "1", PackedStringArray(["Origin: https://example.com"]))
	assert(page.status == 403, "A request with an Origin header is refused")
	var rebound := await _request(HTTPClient.METHOD_GET, "/state", "", PackedStringArray(["Host: example.com"]))
	assert(rebound.status == 403, "A request for another host name is refused")


func _check_scripts() -> void:
	assert((await _value("[1, 2].map((value) => value * 2)")) == [2.0, 4.0], "A script returns its value as JSON")
	assert((await _value("const total = 5; var kept = total * 2; total")) == 5.0)
	assert((await _value("const total = kept + 1; total")) == 11.0, "const ends with its request, and var stays")
	assert((await _value("await game.wait(50); await game.frames(2); 'later'")) == "later", "The answer waits for a promise")
	assert((await _value("undefined")) == null)
	var logged := await _eval("console.log('to the caller'); console.warn('careful'); 1")
	assert(logged.console == [{"level": "log", "text": "to the caller"}, {"level": "warning", "text": "careful"}],
		"The answer has the console output of the script: " + str(logged.console))
	var thrown := await _eval("city.info()")
	assert(not bool(thrown.ok) and str(thrown.error).begins_with("Error: No city is loaded."), "A game error is the error of the answer")
	var syntax := await _eval("const = 1")
	assert(not bool(syntax.ok) and str(syntax.error).begins_with("SyntaxError"))
	var slow := await _eval("await game.wait(5000); 1", 100)
	assert(not bool(slow.ok) and bool(slow.timedOut), "A request ends at its timeout")
	var body := JSON.stringify({"source": "'json body'", "timeout": 1000})
	var json := await _request(HTTPClient.METHOD_POST, "/eval", body, PackedStringArray(["Content-Type: application/json"]))
	assert(JSON.parse_string(json.text).value == "json body", "A JSON body holds the source")
	# two scripts at the same time: the second answers while the first waits
	var waiting := [false]
	main.remote_api.run_script("await game.wait(300); 'first'", 5000, func(result: Dictionary) -> void: waiting[0] = bool(result.ok))
	assert((await _value("'second'")) == "second" and not waiting[0], "Requests do not wait for each other")


func _check_city_files() -> void:
	var created: Dictionary = await _value(
		"game.newCity({ name: 'Remoteville', mayor: 'Agent', seed: 11, year: 1950, difficulty: 'hard' })")
	assert(created.screen == "city" and created.city.name == "Remoteville" and created.city.funds == 10000.0, str(created))
	assert(main.document_state.city.current_year() == 1950 and not main.tool_state.landscape_editor)
	assert(created.suspended == "newspaper" and created.windows.size() == 1, "The founding newspaper waits: " + str(created.windows))
	assert((await _value("ui.close(); sim.suspended")) == "", "A close of the newspaper starts the game")
	var again: Array = await _value(
		"const s = game.newCity({ seed: 11, discard: true, edit: true }); [s.screen, s.city.size, city.census().water]")
	assert(again[0] == "terrain-editor" and again[1] == 128.0, "edit keeps the terrain editor open: " + str(again))
	assert((await _value("game.newCity({ name: 'Savedtown', seed: 11, discard: true }); ui.close(); city.census().water")) == again[2],
		"The same seed makes the same terrain")
	var refused := await _eval("game.newCity({ size: 100 })")
	assert(not bool(refused.ok) and str(refused.error).contains("not saved"), "Unsaved changes stop a new city: " + str(refused))
	var wrong := await _eval("game.newCity({ size: 100, discard: true })")
	assert(not bool(wrong.ok) and str(wrong.error).contains("The size must be"), str(wrong))

	var path := folder.path_join("remote.sc2x")
	assert((await _value("await game.saveAs(%s)" % JSON.stringify(path))) == path and FileAccess.file_exists(path),
		"saveAs writes the file")
	assert((await _value("city.unsaved")) == false, "A saved city has no unsaved changes")
	var fixture := ProjectSettings.globalize_path(GeneratedCityFixture.path(128))
	var opened: Dictionary = await _value("game.open(%s).city" % JSON.stringify(fixture))
	assert(opened.size == 128.0 and main.document_state.city.population() == int(opened.population), "open loads a city file")
	assert(not bool((await _eval("game.open('/no/such/city.sc2')")).ok))
	assert((await _value("game.open(%s, { discard: true }).city.name" % JSON.stringify(path))) == "Savedtown",
		"The saved city opens again")
	assert((await _value("game.files().saved")) is Array)
	assert((await _value("game.mainMenu()")) == "main-menu" and (await _value("game.mainMenu(false)")) == "city")


func _check_play() -> void:
	await _value("game.newCity({ name: 'Playtown', seed: 11, discard: true }); ui.close(); budget.set({ autoBudget: false })")
	var site: Variant = await _value("\n".join([
		"var site = null;",
		"const map = city.textMap().rows;",
		"for (let y = 4; y < 120 && !site; y++) {",
		"  const x = map[y].indexOf('.'.repeat(12));",
		"  if (x >= 4 && [1, 2, 3, 4, 5].every((row) => map[y + row].slice(x, x + 12) === '.'.repeat(12))) site = { x, y };",
		"}",
		"site",
	]))
	assert(site is Dictionary, "The text map shows a clear site")
	var built: Array = await _value("\n".join([
		"view.follow = true;",
		"const use = (group, tool, from, to) => { tools.select(group, tool); return tools.apply(from, to).changed; };",
		"[use('Roads', 'Road', [site.x, site.y], [site.x + 11, site.y]),",
		" use('Residential', 'Light Residential', [site.x, site.y + 1], [site.x + 5, site.y + 2]),",
		" view.screenOf(site.x, site.y).visible, view.layers.buildings]",
	]))
	assert(built == [true, true, true, true], "Tools build, and the view follows them: " + str(built))
	var row: String = await _value("city.textMap({ x: site.x, y: site.y, width: 12, height: 2 }).rows.join('|')")
	assert(row == "============|rrrrrr......", "The text map shows the road and the zone: " + row)
	assert((await _value("city.textMap({ x: site.x, y: site.y + 1, width: 3, height: 1 }, 'zones').rows[0]")) == "rrr")
	assert((await _value("const r = city.region(site.x, site.y, 2, 2); [r.building[0] > 0, r.zone[2]]")) == [true, 1.0])
	assert((await _value("city.find('road').length")) == 12.0 and (await _value("city.census().structures.Road")) == 12.0)
	var query: Dictionary = await _value("city.query(site.x, site.y + 1)")
	assert(query.zone == "Residential" and str(query.text).contains("Zone: Residential"), "A query returns the data of the tile")
	assert((await _value("const t = city.tile(site.x, site.y); t.name + t.symbol")) == "Road=")
	var place: Dictionary = await _value("const p = view.screenOf(site.x, site.y); view.tileAt(p.x, p.y)")
	assert(place == site, "A tile and its place in the window agree: %s %s" % [str(place), str(site)])

	# the days run until the yearly budget asks for an answer
	var run: Dictionary = await _value("await sim.advance(40)")
	assert(run.days == 40.0 and run.stopped == "" and main.simulation_state.speed_controller.speed == GameSpeed.Speed.PAUSED)
	var year: Dictionary = (await _eval("await sim.advance(400)", 120000)).value
	assert(year.stopped == "prompt: annual budget" and year.date.month == 1.0 and year.date.day == 1.0, str(year))
	var state: Dictionary = await _value("game.state()")
	assert(state.suspended == "prompt: annual budget" and state.windows[-1].type == "BudgetDialog" and bool(state.windows[-1].blocking))
	assert((await _value("ui.accept(); sim.suspended")) == "", "OK answers the yearly budget")
	assert((await _value("(await sim.advance(3)).days")) == 3.0)
	# a disaster runs its ticks in place of days
	var fire: Array = await _value("\n".join([
		"sim.startDisaster('Fire', site.x, site.y + 1);",
		"let run = await sim.advance(2);",
		"const notices = [];",
		"while (run.stopped.startsWith('window')) { notices.push(ui.windows().at(-1).text); ui.accept(); run = await sim.advance(2); }",
		"sim.endDisaster();",
		"[run.days, run.stopped, notices.length]",
	]))
	assert(fire[0] == 0.0 and fire[1] == "disaster: Fire", "advance stops at an active disaster: " + str(fire))
	var until: Dictionary = (
		await _eval("sim.noDisasters = true; await sim.runTo({ year: city.date.year, month: 3, day: 1 }, 5)", 120000)).value
	assert(until.date.month == 3.0 and until.stopped == "", "runTo resolves on the date: " + str(until))


func _check_interface() -> void:
	var menus: Array = await _value("ui.menus().map((menu) => menu.text)")
	assert(menus.has("File") and menus.has("Windows"), str(menus))
	assert((await _value("ui.menu('Windows', 'Graphs'); ui.windows().at(-1).type")) == "CityGraphWindow", "A menu item opens its window")
	var toggled: Array = await _value("\n".join([
		"const before = ui.controls().find((control) => control.name === 'Residents').value;",
		"ui.press('Residents');",
		"[before, ui.controls().find((control) => control.name === 'Residents').value]",
	]))
	assert(toggled == [true, false], "A press changes a check box")
	assert((await _value("ui.close(); ui.windows().length")) == 1.0)
	assert((await _value("game.action('window_population'); const open = ui.windows().at(-1).type; ui.close(); open"))
		== "CityPopulationWindow", "An action runs as its key does")
	assert(not bool((await _eval("game.action('no_such_action')")).ok) and not bool((await _eval("ui.press('No Such Button')")).ok))

	# a prompt of a menu item, answered with one of its buttons
	var prompt: Dictionary = await _value("ui.menu('File', 'Main Menu'); ui.windows().at(-1)")
	assert(prompt.title == "Return to Main Menu" and prompt.buttons == ["Cancel", "OK"] and bool(prompt.modal), str(prompt))
	assert((await _value("ui.accept(); game.state().screen")) == "main-menu")
	assert((await _value("ui.press('Continue City'); game.state().screen")) == "city")

	# the Save As dialog takes a path
	var path := folder.path_join("dialog.sc2x")
	await _value("ui.menu('File', 'Save City As'); ui.chooseFile(%s)" % JSON.stringify(path))
	assert(FileAccess.file_exists(path) and main.document_state.current_save_path == path, "A file dialog takes a path")

	# the mouse and the keys: a query click on a tile opens the query window
	var clicked: Array = await _value("\n".join([
		"tools.select('Query');",
		"view.centerOn(site.x, site.y);",
		"const place = view.screenOf(site.x, site.y);",
		"input.click(place.x, place.y);",
		"await game.frames(2);",
		"const shown = [ui.windows().at(-1).type, ui.texts().some((text) => text.includes('Road'))];",
		"ui.press('OK');",
		"shown",
	]))
	assert(clicked == ["CityQueryDialog", true], "A click on the map uses the selected tool: " + str(clicked))
	var zoom: Array = await _value("const zoom = view.zoom; input.key('E'); await game.frames(2); [view.zoom > zoom, input.position.x > 0]")
	assert(zoom == [true, true], "A key runs its action: " + str(zoom))
	assert(not bool((await _eval("input.key('NoSuchKey')")).ok))

	if DisplayServer.get_name() != "headless":
		var image: Dictionary = await _value("await ui.screenshot(%s, { scale: 0.5 })" % JSON.stringify(folder.path_join("screen.png")))
		assert(FileAccess.file_exists(image.path) and image.width > 0.0)
	else:
		assert(str((await _eval("await ui.screenshot()")).error).contains("headless"))

	var export_path := folder.path_join("city.png")
	var exported: Dictionary = (await _eval("sim.pause(); await city.exportPng(%s)" % JSON.stringify(export_path), 120000)).value
	assert(FileAccess.file_exists(export_path) and exported.width > 0.0, "exportPng writes an image of the city without a window")

	# an area of the city is a small image: that part of the whole image
	var part_path := folder.path_join("part.png")
	var part: Dictionary = await _value("await city.exportPng(%s, { area: { x: site.x - 3, y: site.y - 3, width: 6, height: 6 } })"
		% JSON.stringify(part_path))
	var part_rect := Rect2i(int(part.origin.x), int(part.origin.y), int(part.width), int(part.height))
	assert(part.width < exported.width / 4.0 and part.height < exported.height / 4.0, "The image of an area is small: " + str(part))
	assert(Image.load_from_file(part_path).get_data() == Image.load_from_file(export_path).get_region(part_rect).get_data(),
		"The image of an area is that part of the image of the city")
	assert(str((await _eval("await city.exportPng(%s, { area: { x: 500, y: 500 } })" % JSON.stringify(part_path))).error).contains("outside"))
	assert(str((await _eval("await city.exportPng(%s, { view: 'pollution' })" % JSON.stringify(part_path))).error).contains("underground"))

	# the route returns the image itself, also from a headless game
	var drawn := await _request(HTTPClient.METHOD_GET, "/city-image?x=40&y=40&width=6&height=6&size=medium&view=underground")
	assert(drawn.status == 200 and drawn.type == "image/png" and int(drawn.size) > 100, str(drawn.status))
	assert((await _request(HTTPClient.METHOD_GET, "/city-image?x=500&y=500")).status == 400)


func _mcp(message: Dictionary) -> Dictionary:
	var answer := await _request(HTTPClient.METHOD_POST, "/mcp", JSON.stringify(message),
		PackedStringArray(["Content-Type: application/json", "Accept: application/json, text/event-stream"]))

	var data: Variant = JSON.parse_string(answer.text) if not str(answer.text).is_empty() else null

	return {"status": answer.status, "text": answer.text, "data": data}


func _check_mcp() -> void:
	var started := await _mcp({"jsonrpc": "2.0", "id": 1, "method": "initialize",
		"params": {"protocolVersion": "2025-06-18", "capabilities": {}, "clientInfo": {"name": "test", "version": "1"}}})
	assert(started.status == 200 and str(started.text).contains('"id":1,') and started.data.result.protocolVersion == "2025-06-18")
	assert(started.data.result.capabilities.has("tools") and started.data.result.serverInfo.name == "opensc2k")
	assert((await _mcp({"jsonrpc": "2.0", "method": "notifications/initialized"})).status == 202, "A notification has no answer")
	var listed := await _mcp({"jsonrpc": "2.0", "id": "list", "method": "tools/list"})
	var names: Array = listed.data.result.tools.map(func(tool: Dictionary) -> String: return tool.name)
	assert(listed.data.id == "list" and names == ["eval", "state", "screenshot", "city_image", "guide"], str(names))
	var called := await _mcp({"jsonrpc": "2.0", "id": 2, "method": "tools/call",
		"params": {"name": "eval", "arguments": {"source": "console.log('noted'); city.name"}}})
	assert(called.data.result.content[0].text == "\"Playtown\"\n\nConsole:\nnoted" and not bool(called.data.result.isError))
	var failed := await _mcp({"jsonrpc": "2.0", "id": 3, "method": "tools/call",
		"params": {"name": "eval", "arguments": {"source": "nope()"}}})
	assert(bool(failed.data.result.isError) and str(failed.data.result.content[0].text).begins_with("Error: ReferenceError"))
	var state := await _mcp({"jsonrpc": "2.0", "id": 4, "method": "tools/call", "params": {"name": "state"}})
	assert(JSON.parse_string(state.data.result.content[0].text).screen == "city")
	var drawn := await _mcp({"jsonrpc": "2.0", "id": 7, "method": "tools/call",
		"params": {"name": "city_image", "arguments": {"x": 40, "y": 40, "width": 6, "height": 6, "size": "large"}}})
	var picture := Image.new()
	assert(drawn.data.result.content[0].type == "image" and not bool(drawn.data.result.isError)
		and picture.load_png_from_buffer(Marshalls.base64_to_raw(drawn.data.result.content[0].data)) == OK and picture.get_width() == 6 * 32,
		"The city_image tool returns the image of an area")
	var guide := await _mcp({"jsonrpc": "2.0", "id": 5, "method": "tools/call", "params": {"name": "guide", "arguments": {"types": true}}})
	assert(str(guide.data.result.content[0].text).contains("interface GameInput"))
	var unknown := await _mcp({"jsonrpc": "2.0", "id": 6, "method": "resources/list"})
	assert(unknown.data.error.code == -32601.0)
	assert((await _request(HTTPClient.METHOD_GET, "/mcp")).status == 405, "The server offers no event stream")
