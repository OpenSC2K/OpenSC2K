class_name ScriptingGameApi
extends ScriptingApiBase
## The `game` functions of scripts that run the game itself: the state of
## the game, the actions of the keys and menus, a new city, and the city
## files. A script uses them in place of the main menu, the File menu and
## their dialogs. Mods cannot open, save or close files; see RESTRICTED.
## See docs/scripting.md.

const GameSpeed = preload("res://src/simulation/core/game_speed_controller.gd")

# the functions that only console scripts and the remote API can call
const RESTRICTED: PackedStringArray = [
	"game.newCity", "game.open", "game.saveAs", "game.files", "game.mainMenu", "game.quit", "game.settings", "game.preferences",
	"game.debugMode",
]
const DIFFICULTIES := {"easy": 1, "medium": 2, "hard": 3}
const CITY_EXTENSIONS: PackedStringArray = ["sc2", "sc2x", "scn"]
# the game closes this long after game.quit, thus the caller gets its answer
const QUIT_DELAY_SEC := 0.25

var ui_api: ScriptingUiApi
# (group: int, subtool: int) -> Dictionary: the script description of a tool
var describe_tool: Callable


func handlers() -> Dictionary[String, Callable]:
	return {
		"game.state": _state,
		"game.actions": _actions,
		"game.action": _action,
		"game.busy": func(_arguments: Array) -> Variant: return app.city_files.load_in_progress or app.city_files.save_in_progress,
		"game.newCity": _new_city,
		"game.open": _open,
		"game.saveAs": _save_as,
		"game.files": _files,
		"game.mainMenu": _main_menu,
		"game.quit": _quit,
		"game.audio": _audio,
		"game.settings": _settings,
		"game.preferences": _preferences,
		"game.debugMode": _debug_mode,
		"sim.suspended": func(_arguments: Array) -> Variant: return suspension(),
	}


## Why the simulation waits now, or an empty text: a prompt of the
## simulation, a window that blocks it, the terrain editor or the end of the game.
func suspension() -> String:
	var engine := app.simulation_state.simulation_engine

	if app.document_state.city == null or engine == null:
		return ""

	if not engine.pending_interaction.is_empty():
		return "prompt: %s" % engine.pending_interaction.replace("_", " ")

	if app.simulation_state.game_over_active or engine.terminal_state:
		return "game over"

	if app.tool_state.landscape_editor:
		return "terrain editor"

	if app.newspaper_state.founding_pending or app.newspaper_state.scheduled_pending:
		return "newspaper"

	for window in ui_api.open_windows():
		if bool(window.blocking):
			return "window: %s" % (window.title if not str(window.title).is_empty() else window.type)

	return ""


## What shows now: "main-menu", "new-city", "terrain-editor", "city",
## "scurk", or "startup" before the main menu.
func screen() -> String:
	if app.scurk_editor != null and app.scurk_editor.is_visible_in_tree():
		return "scurk"

	if app.city_dialogs != null and app.city_dialogs.new_city_dialog != null and app.city_dialogs.new_city_dialog.visible:
		return "new-city"

	if app.main_menu != null and app.main_menu.visible:
		return "main-menu"

	if app.document_state.city == null:
		return "startup"

	return "terrain-editor" if app.tool_state.landscape_editor else "city"


# the state of the game in one value, for a program that plays it
func _state(_arguments: Array) -> Variant:
	var has_city := app.document_state.city != null and app.simulation_state.simulation_engine != null
	var windows := ui_api.open_windows().slice(1)
	var state := {
		"screen": screen(),
		"assetsReady": app.asset_state.assets_ready,
		"busy": app.city_files.load_in_progress or app.city_files.save_in_progress,
		"status": app.status_label.text if app.status_label != null else "",
		"city": null,
		"windows": windows.map(func(window: Dictionary) -> Dictionary:
			return {"id": window.id, "type": window.type, "title": window.title, "text": window.text, "blocking": window.blocking,
				"buttons": window.buttons}),
	}

	if not has_city:
		return state

	var city := app.document_state.city
	var demand := city.rci_demand()
	var engine := app.simulation_state.simulation_engine
	state["city"] = {
		"name": city.city_name(), "mayor": city.mayor_name(), "size": city.map_size, "funds": city.funds(),
		"population": city.population(), "path": app.document_state.current_save_path,
		"date": {"year": city.current_year(), "month": city.current_month(), "day": city.current_day(), "age": city.age_in_days()},
		"demand": {"residential": demand.x, "commercial": demand.y, "industrial": demand.z},
	}
	state["speed"] = app.simulation_state.speed_controller.speed_name()
	state["suspended"] = suspension()
	state["tool"] = describe_tool.call(app.tool_state.selected_group, app.tool_state.selected_subtool)
	state["disaster"] = ({"id": engine.active_disaster_type, "name": CityMenuBar.disaster_name(engine.active_disaster_type)}
		if engine.active_disaster_type != 0 else null)
	var center := app.map_view.center_tile()
	state["view"] = {
		"mode": CityViewMode.key(app.view_state.overlay_mode), "zoom": app.map_view.zoom_percent(),
		"rotation": city.compass_rotation(), "center": {"x": center.x, "y": center.y},
	}

	return state


# the actions of the keys and the menus: [{ id, label, category, scope, kind }]
func _actions(_arguments: Array) -> Variant:
	return ControlActions.all().map(func(action: ControlActions.Action) -> Dictionary:
		return {"id": action.id, "label": action.label, "category": action.category, "scope": action.scope, "kind": action.kind})


# runs an action as its key does. False when the action does nothing now
func _action(arguments: Array) -> Variant:
	var id := str(argument(arguments, 0, ""))

	if not ControlActions.has(id):
		return fail("Unknown action: %s. game.actions() lists them." % id)

	if app.controls == null or app.city_menu_bar == null:
		return fail("The game did not start yet.")

	var blocker := ui_api.blocking_window()

	if not blocker.is_empty():
		return fail("The window %s waits for an answer. Answer it first: ui.accept(), ui.close() or ui.press()." % blocker)

	return app.controls.run(id)


func _discard_error(choices: Dictionary) -> String:
	if app.city_files.load_in_progress or app.city_files.save_in_progress:
		return "A city loads or saves now."

	if app.city_files.has_unsaved_changes() and not bool(choices.get("discard", false)):
		return "The city has changes that are not saved. Save it, or pass { discard: true }."

	return ""


func _choices(arguments: Array, index: int) -> Dictionary:
	var value: Variant = argument(arguments, index, {})

	return value if value is Dictionary else {}


# newCity({ name, mayor, difficulty, year, size, sc2, ocean, river, hills,
# water, trees, features, seed, edit, discard }): makes the terrain and
# founds the city, as the New City window does
func _new_city(arguments: Array) -> Variant:
	var choices := _choices(arguments, 0)

	if not app.asset_state.assets_ready:
		return fail("The game has no graphics yet. Import the game files first.")

	var blocked := _discard_error(choices)

	if not blocked.is_empty():
		return fail(blocked)

	app.new_city.open_new_city_dialog()
	var dialog := app.city_dialogs.new_city_dialog
	var error := _fill_new_city(dialog, choices)

	if error.is_empty():
		if is_number(choices.get("seed")):
			app.new_city_state.session.begin(int(choices.seed), int(choices.seed))

		var generated := app.new_city_state.session.generate_preview(dialog.terrain_options(), true)
		error = "" if generated.ok else "Cannot make the terrain: %s." % generated.error

	if not error.is_empty():
		app.new_city.cancel_new_city()

		return fail(error)

	var previous := app.document_state.current_document
	dialog.candidate_valid = true
	app.new_city.create_new_city_unchecked()

	if app.document_state.current_document == previous or not app.tool_state.landscape_editor:
		app.new_city.cancel_new_city()

		return fail("Cannot create the city: %s" % app.status_label.text)

	if not bool(choices.get("edit", false)):
		app.new_city.start_city()

	return _state([])


# sets the fields of the New City window. Returns an empty text, or the wrong value
func _fill_new_city(dialog: NewCityTerrainDialog, choices: Dictionary) -> String:
	if choices.has("name"):
		dialog.city_name_input.text = str(choices.name)

	if choices.has("mayor"):
		dialog.mayor_name_input.text = str(choices.mayor)

	if choices.has("sc2"):
		dialog.compatibility_input.button_pressed = bool(choices.sc2)

	var difficulty: Variant = choices.get("difficulty", 1)
	var selections := [
		[dialog.difficulty_input, DIFFICULTIES.get(str(difficulty).to_lower(), difficulty), "difficulty", "easy, medium or hard"],
		[dialog.year_input, choices.get("year", 1900), "year", "1900, 1950, 2000 or 2050"],
		[dialog.size_input, choices.get("size", 128), "size", "16, 32, 64, 128, 256, 384, 512, 640, 1024, 2048 or 4096"],
	]

	for selection: Array in selections:
		var input: OptionButton = selection[0]
		var index := input.get_item_index(int(selection[1])) if is_number(selection[1]) else -1

		if index < 0 or input.is_item_disabled(index):
			return "The %s must be %s%s." % [selection[2], selection[3],
				"; an SC2 city has 128 tiles" if selection[2] == "size" and dialog.compatibility_input.button_pressed else ""]

		input.select(index)

	for name: String in ["ocean", "river"]:
		if choices.has(name):
			(dialog.get(name + "_input") as CheckBox).button_pressed = bool(choices[name])

	for name: String in ["hills", "water", "trees"]:
		if choices.has(name):
			if not is_number(choices[name]):
				return "The amount of %s must be a number from 0 to 47." % name

			(dialog.get(name + "_input") as Range).value = float(choices[name])

	var features: Variant = choices.get("features", [])

	for feature: Variant in (features if features is Array else []):
		if not dialog.feature_inputs.has(str(feature)):
			return "Unknown terrain feature: %s. The features: %s." % [str(feature), ", ".join(dialog.feature_inputs.keys())]

		dialog.feature_inputs[str(feature)].button_pressed = true

	return ""


# open(path, { discard }): opens a city or a scenario file
func _open(arguments: Array) -> Variant:
	var path := str(argument(arguments, 0, ""))
	var blocked := _discard_error(_choices(arguments, 1))

	if not blocked.is_empty():
		return fail(blocked)

	if path.is_empty() or not FileAccess.file_exists(path):
		return fail("The file %s does not exist." % path)

	var error := app.city_files.open_city_now(path)

	return _state([]) if error.is_empty() else fail("Cannot open the city: %s" % error)


# saves the city to a path. True when the save finished; false while a
# large city saves on a worker
func _save_as(arguments: Array) -> Variant:
	if not need_city():
		return null

	var path := str(argument(arguments, 0, ""))

	if path.is_empty() or not path.is_absolute_path():
		return fail("The path must be a full path.")

	if app.city_files.load_in_progress or app.city_files.save_in_progress:
		return fail("A city loads or saves now.")

	DirAccess.make_dir_recursive_absolute(path.get_base_dir())
	var saved := app.city_files.save_city_as(path)

	if not saved and not app.city_files.save_in_progress:
		return fail("Cannot save the city: %s" % app.status_label.text)

	return saved


# the city and scenario files that the game knows: { cities, scenarios, saved }
func _files(_arguments: Array) -> Variant:
	var root := app.asset_state.reference_root

	return {
		"cities": _city_files(root.path_join("CITIES")),
		"scenarios": _city_files(root.path_join("SCENARIO")),
		"saved": _city_files(AppPaths.path("cities")),
		"savedFolder": AppPaths.path("cities"),
		"autosaves": _city_files(app.autosave.directory),
	}


static func _city_files(folder: String) -> PackedStringArray:
	var result := PackedStringArray()

	if not DirAccess.dir_exists_absolute(folder):
		return result

	for file in DirAccess.get_files_at(folder):
		if CITY_EXTENSIONS.has(file.get_extension().to_lower()):
			result.append(folder.path_join(file))

	result.sort()

	return result


# shows the main menu, or returns from it to the city
func _main_menu(arguments: Array) -> Variant:
	if app.main_menu == null:
		return fail("The game did not start yet.")

	if bool(argument(arguments, 0, true)):
		app.interface.show_main_menu()
	elif app.document_state.city == null:
		return fail("No city is loaded.")
	else:
		app.interface.hide_main_menu()

	return screen()


# quit({ discard }): closes the game
func _quit(arguments: Array) -> Variant:
	var blocked := _discard_error(_choices(arguments, 0))

	if not blocked.is_empty():
		return fail(blocked)

	app.get_tree().create_timer(QUIT_DELAY_SEC).timeout.connect(app.get_tree().quit)

	return true


# the stored settings: { section: { key: value } }
func _settings(_arguments: Array) -> Variant:
	var file := ConfigFile.new()
	var result := {}

	if file.load(app.preferences.settings_path) != OK:
		return result

	for section in file.get_sections():
		result[section] = {}

		for key in file.get_section_keys(section):
			result[section][key] = file.get_value(section, key)

	return result


# what the game plays now: { music: { enabled, playing, paused, track, name }, sound: { enabled, loop } }.
# A program cannot hear the game; this tells it what a player hears
func _audio(_arguments: Array) -> Variant:
	var controller := app.audio_controller
	var city := app.document_state.city

	if controller == null:
		return fail("The audio did not start yet.")

	return {
		"music": {
			"enabled": city != null and city.music_enabled(), "playing": controller.music_playback_is_active(),
			"paused": controller.music_paused, "track": controller.current_track_id, "name": controller.current_track_name,
		},
		"sound": {"enabled": city != null and city.sound_enabled(), "loop": controller.sound_loop_id},
	}


# the settings that the game uses now, also those that the settings file
# does not hold: { defaultMayorName: 'Mayor', musicVolume: 0.8, ... }
func _preferences(_arguments: Array) -> Variant:
	var result := {}

	for property in app.preferences.get_property_list():
		if int(property.usage) & PROPERTY_USAGE_SCRIPT_VARIABLE == 0:
			continue

		var value: Variant = app.preferences.get(property.name)

		if typeof(value) in [TYPE_BOOL, TYPE_INT, TYPE_FLOAT, TYPE_STRING, TYPE_ARRAY]:
			result[str(property.name).to_camel_case()] = value

	return result


# debugMode(enabled): turns the debug mode on or off. Returns its state
func _debug_mode(arguments: Array) -> Variant:
	if not arguments.is_empty() and arguments[0] != null:
		app.debug_tools.set_debug_mode(bool(arguments[0]))

	return DebugMode.enabled
