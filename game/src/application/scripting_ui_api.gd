class_name ScriptingUiApi
extends ScriptingApiBase
## The `ui` functions of scripts: message windows, sounds, and control of
## the interface. A script reads the open windows and their controls, then
## presses buttons, sets values, chooses menu items and answers dialogs as
## the player does. UiProbe reads the interface and UiOperator uses it. Mods
## cannot use the control functions; see RESTRICTED. See docs/scripting.md.

# the functions that only console scripts and the remote API can call
const RESTRICTED: PackedStringArray = [
	"ui.windows", "ui.controls", "ui.texts", "ui.press", "ui.set", "ui.choose", "ui.menus", "ui.menu", "ui.accept",
	"ui.close", "ui.chooseFile", "ui.screen", "ui.screenshot",
]
const SCREENSHOT_FOLDER := "screenshots"

# the newest message window
var last_alert: AcceptDialog


func handlers() -> Dictionary[String, Callable]:
	return {
		"ui.alert": _alert,
		"ui.playSound": _play_sound,
		"ui.windows": func(_arguments: Array) -> Variant: return open_windows(),
		"ui.controls": _controls,
		"ui.texts": _texts,
		"ui.press": _press,
		"ui.set": _set_value,
		"ui.choose": _choose,
		"ui.menus": _menus,
		"ui.menu": _menu,
		"ui.accept": _accept,
		"ui.close": _close,
		"ui.chooseFile": _choose_file,
		"ui.screen": _screen,
		"ui.screenshot": _screenshot,
	}


## The visible windows, the lowest first. The first is "main", the game
## window. A full-screen panel of the game, such as the main menu or the
## query result, is a window too. `blocking` tells that the simulation waits
## while the window shows.
func open_windows() -> Array[Dictionary]:
	var root := app.get_tree().root
	var result: Array[Dictionary] = [UiProbe.windows(root)[0]]
	result[0]["blocking"] = false

	for panel in _panels():
		var data := {
			"id": str(panel.get_path()), "type": UiProbe.type_name(panel), "title": str(panel.name), "text": "", "modal": true,
			"focused": false, "rect": UiProbe.rect_data(UiProbe.screen_rect(panel)), "buttons": [],
			"blocking": _blocks(panel),
		}

		for control in UiProbe.controls(panel):
			if control.kind == UiProbe.KIND_BUTTON and not str(control.text).is_empty():
				data.buttons.append(control.text)

		result.append(data)

	for window in UiProbe.visible_windows(root):
		var data := UiProbe.window_data(window)
		data["blocking"] = _blocks(window)
		result.append(data)

	return result


# the visible panels of the game that are not engine windows
func _panels() -> Array[Control]:
	var result: Array[Control] = []

	# the panels of the main overlays are above the panels of the city
	for registry: Variant in [app.city_dialogs, app.main_overlays]:
		if registry == null:
			continue

		for node: Node in registry.blocking_windows + registry.modeless_windows:
			if node is Control and (node as Control).is_visible_in_tree():
				result.append(node)

	return result


func _blocks(node: Node) -> bool:
	for registry: Variant in [app.main_overlays, app.city_dialogs]:
		if registry != null and registry.blocking_windows.has(node):
			return true

	return node is Window and (node as Window).exclusive


# the node of a window argument: nothing for the top window, "main", an id
# or a title. Null, with a failure, when no window matches
func _window(target: Variant) -> Node:
	var windows := open_windows()

	if target == null:
		return _node(windows[-1].id)

	var text := str(target)

	for index in range(windows.size() - 1, -1, -1):
		if windows[index].id == text:
			return _node(text)

	for index in range(windows.size() - 1, -1, -1):
		var title: String = windows[index].title

		if UiOperator.plain_text(title) == UiOperator.plain_text(text) or str(windows[index].type).to_lower() == text.to_lower():
			return _node(windows[index].id)

	fail("No window %s shows now. ui.windows() lists the windows." % text)

	return null


func _node(id: String) -> Node:
	return app.get_tree().root if id == UiProbe.MAIN_ID else app.get_tree().root.get_node_or_null(NodePath(id))


# the control of a target: its id, its text or its node name, or { id },
# or { text, window }. The top window is searched first. Controls under a
# modal window are not searched. Null, with a failure, without one match
func _control(target: Variant) -> Control:
	var id := ""
	var text := ""
	var window: Variant = null

	if target is Dictionary:
		id = str(target.get("id", ""))
		text = str(target.get("text", target.get("name", "")))
		window = target.get("window")
	elif target is String and str(target).begins_with("/"):
		id = target
	else:
		text = str(target) if target != null else ""

	if not id.is_empty():
		var node := app.get_tree().root.get_node_or_null(NodePath(id))

		if node is Control and (node as Control).is_visible_in_tree():
			return node

		fail("No control %s shows now. ui.controls() lists the controls." % id)

		return null

	if text.is_empty():
		fail("Name a control: its id, or its text.")

		return null

	var scopes: Array[Node] = []

	if window != null:
		var scope := _window(window)

		if scope == null:
			return null

		scopes.append(scope)
	else:
		var windows := open_windows()

		for index in range(windows.size() - 1, -1, -1):
			scopes.append(_node(windows[index].id))

			if bool(windows[index].modal):
				break

	for scope in scopes:
		var matches := _matches(scope, text)

		if matches.size() == 1:
			return app.get_tree().root.get_node(NodePath(matches[0]))

		if matches.size() > 1:
			fail("%d controls match %s: %s. Use the id of one." % [matches.size(), text, ", ".join(matches)])

			return null

	fail("No control %s shows now. ui.controls() lists the controls." % text)

	return null


# the ids of the controls of a window whose text or node name is `text`
func _matches(scope: Node, text: String) -> PackedStringArray:
	var exact := PackedStringArray()
	var close := PackedStringArray()

	for control in UiProbe.controls(scope):
		if control.text == text or control.name == text:
			exact.append(control.id)
		elif UiOperator.plain_text(control.text) == UiOperator.plain_text(text) or str(control.name).to_lower() == text.to_lower():
			close.append(control.id)

	return exact if not exact.is_empty() else close


func _done(error: String) -> Variant:
	return true if error.is_empty() else fail(error)


func _controls(arguments: Array) -> Variant:
	var scope := _window(argument(arguments, 0))

	return UiProbe.controls(scope) if scope != null else null


func _texts(arguments: Array) -> Variant:
	var scope := _window(argument(arguments, 0))

	return UiProbe.texts(scope) if scope != null else null


func _press(arguments: Array) -> Variant:
	var control := _control(argument(arguments, 0))

	return _done(UiOperator.press(control)) if control != null else null


func _set_value(arguments: Array) -> Variant:
	var control := _control(argument(arguments, 0))

	if control == null:
		return null

	return _done(UiOperator.set_value(control, argument(arguments, 1), bool(argument(arguments, 2, false))))


func _choose(arguments: Array) -> Variant:
	var target: Variant = argument(arguments, 0)
	var item: Variant = argument(arguments, 1)

	# a popup menu that shows, such as the menu of a right click on the map
	if target is String:
		var window := app.get_tree().root.get_node_or_null(NodePath(target)) if str(target).begins_with("/") else null

		if window is PopupMenu:
			return _done(UiOperator.choose_menu_item(window, item if item is Array else [item]))

	var control := _control(target)

	if control == null:
		return null

	if control is MenuButton and item is Array:
		return _done(UiOperator.choose_menu_item((control as MenuButton).get_popup(), item))

	return _done(UiOperator.choose(control, item, bool(argument(arguments, 2, false))))


# the menus of the menu bar: [{ text, disabled, items }]
func _menus(_arguments: Array) -> Variant:
	var result := []

	for button in _menu_buttons():
		button.get_popup().about_to_popup.emit()
		result.append({"text": button.text, "disabled": button.disabled, "items": UiProbe.menu_items(button.get_popup())})

	return result


# the menu buttons of the menu bar that show now
func _menu_buttons() -> Array[MenuButton]:
	var result: Array[MenuButton] = []

	if app.city_menu_bar != null and app.city_menu_bar.is_visible_in_tree():
		for node in app.city_menu_bar.find_children("*", "MenuButton", true, false):
			if (node as MenuButton).is_visible_in_tree():
				result.append(node)

	return result


# chooses an item of the menu bar by its path: ["File", "Save City"]
func _menu(arguments: Array) -> Variant:
	var path: Array = argument(arguments, 0, []) if argument(arguments, 0, []) is Array else []

	if path.size() < 2:
		return fail("Name a menu and an item, such as ui.menu('File', 'Save City').")

	var buttons := _menu_buttons()

	if buttons.is_empty():
		return fail("The menu bar does not show now.")

	for button in buttons:
		if UiOperator.plain_text(button.text) == UiOperator.plain_text(str(path[0])):
			if button.disabled:
				return fail("The menu %s is disabled." % button.text)

			return _done(UiOperator.choose_menu_item(button.get_popup(), path.slice(1)))

	return fail("The menu bar has no menu %s. Its menus: %s." % [str(path[0]),
		", ".join(buttons.map(func(button: MenuButton) -> String: return button.text))])


func _accept(arguments: Array) -> Variant:
	var window := _window(argument(arguments, 0))

	if window == null:
		return null

	return _done(UiOperator.accept(window)) if window is Window else fail("%s has no OK button. Press one of its buttons." % window.name)


func _close(arguments: Array) -> Variant:
	var window := _window(argument(arguments, 0))

	if window == null:
		return null

	if window == app.get_tree().root:
		return fail("No window is open. game.quit() closes the game.")

	if window is Window:
		return _done(UiOperator.close(window))

	return fail("%s is a panel of the game. Press one of its buttons: %s." % [window.name,
		", ".join(UiProbe.controls(window).filter(func(control: Dictionary) -> bool:
			return control.kind == UiProbe.KIND_BUTTON and not str(control.text).is_empty()).map(
			func(control: Dictionary) -> String: return control.text))])


# selects a path in the file dialog that shows
func _choose_file(arguments: Array) -> Variant:
	var path := str(argument(arguments, 0, ""))
	var dialogs := UiProbe.visible_windows(app.get_tree().root).filter(func(window: Window) -> bool: return window is FileDialog)

	if dialogs.is_empty():
		return fail("No file dialog shows now.")

	if path.is_empty() or not path.is_absolute_path():
		return fail("The path must be a full path.")

	return _done(UiOperator.choose_file(dialogs[-1], path))


# the size of the game window in pixels, and the pointer of scripts
func _screen(_arguments: Array) -> Variant:
	var size := app.get_tree().root.size

	return {"width": size.x, "height": size.y, "headless": DisplayServer.get_name() == "headless"}


# saves an image of the game window to a PNG file: settles the promise of
# the script with { path, width, height }
func _screenshot(arguments: Array) -> Variant:
	var token := int(argument(arguments, 0, 0))
	var path := str(argument(arguments, 1, ""))
	var scale: Variant = argument(arguments, 2, 1.0)
	var context: ScriptContext = call_state.get("context")

	if path.is_empty():
		var stamp := Time.get_datetime_string_from_system().replace(":", "-").replace("T", "_")
		path = AppPaths.path(SCREENSHOT_FOLDER).path_join("screen_%s_%d.png" % [stamp, Time.get_ticks_msec() % 1000])

	if not path.is_absolute_path():
		return fail("The path must be a full path.")

	app.remote_api.capture_window(float(scale) if is_number(scale) else 1.0, func(png: PackedByteArray, error: String) -> void:
		if error.is_empty():
			DirAccess.make_dir_recursive_absolute(path.get_base_dir())
			var file := FileAccess.open(path, FileAccess.WRITE)

			if file == null:
				error = "Cannot write %s: %s." % [path, error_string(FileAccess.get_open_error())]
			else:
				file.store_buffer(png)
				file.close()

		var image := Image.new()

		if error.is_empty():
			image.load_png_from_buffer(png)

		app.scripting.settle(context, token, {"path": path, "width": image.get_width(), "height": image.get_height()}, error))

	return null


# a message window with an OK button. The game continues while it shows
func _alert(arguments: Array) -> Variant:
	var dialog := AcceptDialog.new()
	dialog.theme = AppUiTheme.current()
	dialog.title = str(argument(arguments, 1, "Script"))
	dialog.dialog_text = str(argument(arguments, 0, ""))
	dialog.confirmed.connect(dialog.queue_free)
	dialog.canceled.connect(dialog.queue_free)
	app.add_child(dialog)
	dialog.popup_centered()
	last_alert = dialog

	return null


# plays a sound of the sound pack: the number of SOUNDS/<id>.WAV
func _play_sound(arguments: Array) -> Variant:
	var id: Variant = argument(arguments, 0)

	if not is_number(id) or int(id) < 0:
		return fail("The sound must be a number, such as 500 for SOUNDS/500.WAV.")

	var ids: Array[int] = [int(id)]
	app.effects_audio.play_sound_ids(ids)

	return null
