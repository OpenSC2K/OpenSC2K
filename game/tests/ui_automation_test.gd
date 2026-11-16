extends "res://tests/support/scene_test_case.gd"
## The interface control of scripts: UiProbe lists the windows and the
## controls, UiOperator uses each kind of control as the player does, and
## InputSender sends mouse and key input to the place that UiProbe reports,
## in the main window and in an embedded window.

var presses: Array[String] = []


func _initialize() -> void:
	call_deferred("_run")


func _run() -> void:
	# the headless window of the test runner is too small for places in whole pixels
	var window_size := root.size
	root.size = Vector2i(1280, 800)
	await _frames(2)
	var panel := _build_panel()
	root.add_child(panel)
	var window := _build_window()
	panel.add_child(window)
	# a popup takes its size limit from the screen, and a headless screen has no size
	window.position = Vector2i(300, 120)
	window.size = Vector2i(260, 160)
	window.show()
	await _frames(3)

	_check_probe(panel, window)
	_check_operator(panel)
	_check_menus_and_dialogs(panel)
	await _check_input(panel, window)
	_check_keys()
	panel.queue_free()
	root.size = window_size
	await process_frame
	print("PASS: interface probe, each control kind, menus, dialogs, mouse places in the main and an embedded window, keys")
	quit()


func _frames(count: int) -> void:
	for _frame in count:
		await process_frame


func _named(node: Node, node_name: String) -> Node:
	node.name = node_name

	return node


func _build_panel() -> Control:
	var panel := Control.new()
	panel.name = "Panel"
	panel.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	var layout := VBoxContainer.new()
	layout.position = Vector2(20, 20)
	panel.add_child(layout)

	var button := _named(Button.new(), "Build") as Button
	button.text = "&Build..."
	button.pressed.connect(func() -> void: presses.append("build"))
	layout.add_child(button)
	var blocked := _named(Button.new(), "Blocked") as Button
	blocked.text = "Blocked"
	blocked.disabled = true
	layout.add_child(blocked)
	var check := _named(CheckBox.new(), "Auto") as CheckBox
	check.text = "Auto-Budget"
	check.toggled.connect(func(on: bool) -> void: presses.append("auto %s" % on))
	layout.add_child(check)
	var line := _named(LineEdit.new(), "CityName") as LineEdit
	line.custom_minimum_size = Vector2(160, 0)
	line.text_submitted.connect(func(text: String) -> void: presses.append("submit " + text))
	layout.add_child(line)
	var spin := _named(SpinBox.new(), "Tax") as SpinBox
	spin.max_value = 22
	layout.add_child(spin)
	var option := _named(OptionButton.new(), "Difficulty") as OptionButton

	for text: String in ["Easy", "Medium", "Hard"]:
		option.add_item(text)

	option.item_selected.connect(func(index: int) -> void: presses.append("difficulty %d" % index))
	layout.add_child(option)
	var tabs := _named(TabContainer.new(), "Tabs") as TabContainer

	for text: String in ["Overview", "Bonds"]:
		tabs.add_child(_named(Label.new(), text))

	layout.add_child(tabs)
	var list := _named(ItemList.new(), "Cities") as ItemList
	list.custom_minimum_size = Vector2(160, 60)
	list.add_item("Island")
	list.add_item("Lakeland")
	list.item_activated.connect(func(index: int) -> void: presses.append("open %d" % index))
	layout.add_child(list)
	var tree := _named(Tree.new(), "Records") as Tree
	tree.custom_minimum_size = Vector2(160, 60)
	tree.hide_root = true
	var tree_root := tree.create_item()
	tree.create_item(tree_root).set_text(0, "Police")
	tree.create_item(tree_root).set_text(0, "Fire")
	layout.add_child(tree)
	var menu := _named(MenuButton.new(), "File") as MenuButton
	menu.text = "File"
	menu.get_popup().add_item("Save City", 7)
	menu.get_popup().add_item("Exit", 6)
	menu.get_popup().set_item_disabled(1, true)
	var submenu := PopupMenu.new()
	submenu.add_item("Traffic", 4)
	submenu.id_pressed.connect(func(id: int) -> void: presses.append("view %d" % id))
	menu.get_popup().add_submenu_node_item("Views", submenu)
	menu.get_popup().id_pressed.connect(func(id: int) -> void: presses.append("menu %d" % id))
	layout.add_child(menu)

	return panel


func _build_window() -> Window:
	var window := Window.new()
	window.name = "Report"
	window.title = "Report"
	var inner := _named(Button.new(), "Inner") as Button
	inner.text = "Inner"
	inner.position = Vector2(30, 40)
	inner.size = Vector2(120, 40)
	inner.pressed.connect(func() -> void: presses.append("inner"))
	window.add_child(inner)

	return window


func _control(scope: Node, node_name: String) -> Dictionary:
	for control in UiProbe.controls(scope):
		if control.name == node_name:
			return control

	return {}


func _check_probe(panel: Control, window: Window) -> void:
	var windows := UiProbe.windows(root)
	assert(windows[0].id == UiProbe.MAIN_ID and windows[-1].title == "Report" and windows[-1].buttons == ["Inner"],
		"The probe lists the main window and the open window with its buttons")

	var kinds := {}

	for control in UiProbe.controls(root):
		kinds[control.name] = control.kind

	assert(kinds == {"Build": "button", "Blocked": "button", "Auto": "check", "CityName": "text", "Tax": "number",
		"Difficulty": "option", "Tabs": "tabs", "Cities": "list", "Records": "tree", "File": "menu"},
		"Each control has its kind, and the controls of the other window are not here: %s" % str(kinds))
	assert(_control(root, "Build").text == "&Build..." and bool(_control(root, "Blocked").disabled))
	assert(_control(root, "Tax").max == 22.0 and _control(root, "Difficulty").items.size() == 3)
	assert(_control(root, "File").items[1].disabled and _control(root, "File").items[2].submenu[0].text == "Traffic")
	assert(_control(window, "Inner").kind == "button" and _control(panel, "Inner").is_empty())
	assert(UiProbe.texts(panel).has("Auto-Budget") and UiProbe.texts(window) == PackedStringArray(["Inner"]))


func _check_operator(panel: Control) -> void:
	var find := func(node_name: String) -> Control: return panel.find_child(node_name, true, false)
	assert(UiOperator.press(find.call("Build")).is_empty() and presses == ["build"], "A press sends the pressed signal")
	assert(UiOperator.press(find.call("Blocked")).contains("disabled"), "A disabled button cannot be pressed")
	assert(UiOperator.set_value(find.call("Auto"), true).is_empty() and presses[-1] == "auto true")
	assert(UiOperator.set_value(find.call("Auto"), true).is_empty() and presses.count("auto true") == 1, "The same state is no change")
	assert(UiOperator.set_value(find.call("CityName"), "Springfield", true).is_empty() and presses[-1] == "submit Springfield")
	assert((find.call("CityName") as LineEdit).text == "Springfield")
	assert(UiOperator.set_value(find.call("Tax"), 9).is_empty() and (find.call("Tax") as SpinBox).value == 9.0)
	assert(UiOperator.set_value(find.call("Tax"), "nine").contains("number"))
	assert(UiOperator.choose(find.call("Difficulty"), "hard").is_empty() and presses[-1] == "difficulty 2", "An item matches without case")
	assert(UiOperator.choose(find.call("Difficulty"), "Impossible").contains("no item"))
	assert(UiOperator.choose(find.call("Tabs"), "Bonds").is_empty() and (find.call("Tabs") as TabContainer).current_tab == 1)
	assert(UiOperator.choose(find.call("Cities"), 1, true).is_empty() and presses[-1] == "open 1")
	assert(UiOperator.choose(find.call("Records"), "Fire").is_empty() and UiProbe.tree_rows(find.call("Records"))[1].selected)


func _check_menus_and_dialogs(panel: Control) -> void:
	var menu := (panel.find_child("File", true, false) as MenuButton).get_popup()
	assert(UiOperator.choose_menu_item(menu, ["save city"]).is_empty() and presses[-1] == "menu 7")
	assert(UiOperator.choose_menu_item(menu, ["Exit"]).contains("disabled"))
	assert(UiOperator.choose_menu_item(menu, ["Views", "Traffic"]).is_empty() and presses[-1] == "view 4", "A path opens a submenu")
	assert(UiOperator.choose_menu_item(menu, ["Views"]).contains("submenu"))

	var answers: Array[String] = []
	var dialog := ConfirmationDialog.new()
	dialog.confirmed.connect(func() -> void: answers.append("yes"))
	dialog.canceled.connect(func() -> void: answers.append("no"))
	panel.add_child(dialog)
	dialog.popup_centered()
	assert(UiProbe.windows(root)[-1].modal, "A dialog is modal")
	assert(UiOperator.accept(dialog).is_empty() and answers == ["yes"] and not dialog.visible, "OK answers and closes a dialog")
	dialog.popup_centered()
	assert(UiOperator.close(dialog).is_empty() and answers == ["yes", "no"] and not dialog.visible, "A close is a Cancel")

	var files := FileDialog.new()
	files.file_mode = FileDialog.FILE_MODE_OPEN_FILE
	files.access = FileDialog.ACCESS_FILESYSTEM
	files.use_native_dialog = false
	files.file_selected.connect(func(path: String) -> void: answers.append(path))
	panel.add_child(files)
	files.popup_centered(Vector2i(400, 300))
	var path := ProjectSettings.globalize_path("res://project.godot")
	assert(UiOperator.choose_file(files, path + ".missing").contains("does not exist"))
	assert(UiOperator.choose_file(files, path).is_empty() and answers[-1] == path and not files.visible, "A file dialog takes a path")


func _check_input(panel: Control, window: Window) -> void:
	var sender := InputSender.new()
	presses.clear()

	for target: Array in [[root, "Build", "build"], [window, "Inner", "inner"]]:
		var rect: Dictionary = _control(target[0], target[1]).rect
		sender.move(Vector2(rect.x + rect.width / 2.0, rect.y + rect.height / 2.0))
		sender.press_button(MOUSE_BUTTON_LEFT, true)
		sender.press_button(MOUSE_BUTTON_LEFT, false)
		await _frames(2)
		assert(presses == [target[2]], "A click at the place of %s presses it: %s at %s" % [target[1], str(presses), str(rect)])
		presses.clear()

	# the keys go to the window with the focus
	window.hide()
	var line := panel.find_child("CityName", true, false) as LineEdit
	line.text = ""
	line.grab_focus()
	sender.type_text("Ab 1")
	await _frames(2)
	assert(line.text == "Ab 1", "Typed text goes to the control with the focus: " + line.text)
	var select_all := "Cmd+A" if OS.get_name() == "macOS" else "Ctrl+A"
	assert(sender.press_key(select_all, true).is_empty() and sender.press_key(select_all, false).is_empty())
	assert(sender.press_key("Backspace", true).is_empty() and sender.press_key("Backspace", false).is_empty())
	await _frames(2)
	assert(line.text.is_empty(), "Key commands reach the control with the focus: " + line.text)
	sender.release_all()


func _check_keys() -> void:
	assert(InputSender.parse_key("Ctrl+Shift+S") == {"keycode": KEY_S, "modifiers": KEY_MASK_CTRL | KEY_MASK_SHIFT})
	assert(InputSender.parse_key("escape").keycode == KEY_ESCAPE and InputSender.parse_key("F12").keycode == KEY_F12)
	assert(InputSender.parse_key("Cmd++").keycode == KEY_PLUS and InputSender.parse_key("Shift").keycode == KEY_SHIFT)
	assert(InputSender.parse_key("Hyper+S").is_empty() and InputSender.parse_key("NoSuchKey").is_empty())
	assert(InputSender.button("Right") == MOUSE_BUTTON_RIGHT and InputSender.button("fifth") == MOUSE_BUTTON_NONE)
