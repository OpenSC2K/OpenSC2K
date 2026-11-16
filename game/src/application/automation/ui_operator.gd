class_name UiOperator
extends RefCounted
## Uses the interface for scripts, as the player does with the mouse and the
## keyboard: presses a button, sets a value, chooses an item, answers a
## dialog. Each function changes the control and sends the signals that the
## player's action sends, thus the game reacts in the same way. A function
## returns an empty text, or why the action is not possible.


## Presses a button. A check box or a toggle button changes its state.
static func press(control: Control) -> String:
	if not control is BaseButton:
		return "%s is not a button." % control.name

	var button := control as BaseButton

	if button.disabled:
		return "The button %s is disabled." % _label(button)

	if button is OptionButton or button is MenuButton:
		return "%s opens a list. Choose one of its items." % _label(button)

	if button.toggle_mode:
		# a radio button that is on stays on
		var keeps := button.button_pressed and button.button_group != null and not button.button_group.allow_unpress

		if not keeps:
			button.button_pressed = not button.button_pressed
	elif button.has_method("_pressed"):
		button.call("_pressed")

	button.pressed.emit()

	return ""


## Sets the value of a control: the text of a text field, the number of a
## spin box or a slider, the state of a check box. `submit` also sends the
## Enter key of a text field.
static func set_value(control: Control, value: Variant, submit := false) -> String:
	if control is LineEdit:
		var line := control as LineEdit

		if not line.editable:
			return "The text field %s cannot change." % line.name

		line.text = str(value)
		line.caret_column = line.text.length()
		line.text_changed.emit(line.text)

		if submit:
			line.text_submitted.emit(line.text)

		return ""

	if control is TextEdit:
		var edit := control as TextEdit

		if not edit.editable:
			return "The text field %s cannot change." % edit.name

		edit.text = str(value)
		edit.text_changed.emit()

		# a text area has no submit signal: a window that takes Enter in it reads the key
		if submit:
			var enter := InputEventKey.new()
			enter.keycode = KEY_ENTER
			enter.physical_keycode = KEY_ENTER
			enter.pressed = true
			edit.gui_input.emit(enter)

		return ""

	if control is Range and not control is ProgressBar:
		if not typeof(value) in [TYPE_INT, TYPE_FLOAT]:
			return "%s needs a number." % control.name

		if control.get("editable") == false:
			return "%s cannot change." % control.name

		(control as Range).value = float(value)

		return ""

	if control is BaseButton and (control as BaseButton).toggle_mode:
		var button := control as BaseButton

		if not value is bool:
			return "%s needs true or false." % _label(button)

		return press(button) if button.button_pressed != bool(value) else ""

	if control is OptionButton or control is TabBar or control is TabContainer or control is ItemList:
		return choose(control, value)

	return "%s has no value that a script can set." % control.name


## Chooses an item by its text or its index: an option of an option button,
## a tab, a row of a list or a tree, an item of a menu button. `activate`
## also sends the double click of a list or a tree.
static func choose(control: Control, item: Variant, activate := false) -> String:
	if control is OptionButton or control is MenuButton:
		if (control as BaseButton).disabled:
			return "%s is disabled." % _label(control)

		var popup: PopupMenu = control.call("get_popup")
		var index := _find_item(item, popup.item_count, popup.get_item_text)

		if index < 0:
			return _no_item(control, item)

		if control is OptionButton:
			if popup.is_item_disabled(index):
				return "The item %s is disabled." % popup.get_item_text(index)

			(control as OptionButton).select(index)
			(control as OptionButton).item_selected.emit(index)

			return ""

		return choose_menu_item(popup, [index])

	if control is TabBar or control is TabContainer:
		var bar := UiProbe.tab_bar(control)
		var tab := _find_item(item, bar.tab_count, func(index: int) -> String: return UiProbe.tab_text(bar, index))

		if tab < 0:
			return _no_item(control, item)

		if bar.is_tab_disabled(tab):
			return "The tab %s is disabled." % UiProbe.tab_text(bar, tab)

		control.set("current_tab", tab)

		return ""

	if control is ItemList:
		var list := control as ItemList
		var row := _find_item(item, list.item_count, list.get_item_text)

		if row < 0:
			return _no_item(control, item)

		list.select(row)
		list.item_selected.emit(row)

		if activate:
			list.item_activated.emit(row)

		return ""

	if control is Tree:
		return _choose_tree_row(control as Tree, item, activate)

	return "%s has no items." % control.name


static func _choose_tree_row(tree: Tree, item: Variant, activate: bool) -> String:
	var rows := UiProbe.tree_rows(tree)
	var index := _find_item(item, rows.size(), func(row: int) -> String: return rows[row].text)

	if index < 0:
		return _no_item(tree, item)

	var row := UiProbe.tree_item(tree, index)
	tree.set_selected(row, 0)
	tree.scroll_to_item(row)

	if activate:
		tree.item_activated.emit()

	return ""


## Chooses an item of a popup menu by a path of texts or indices, through
## its submenus. The menu reacts as it does to a click.
static func choose_menu_item(menu: PopupMenu, path: Array) -> String:
	var current := menu

	for step in path.size():
		# a menu fills or checks its items when it opens
		current.about_to_popup.emit()
		var index := _find_item(path[step], current.item_count, current.get_item_text)

		if index < 0 or current.is_item_separator(index):
			return "The menu has no item %s. Its items: %s." % [str(path[step]), ", ".join(_menu_texts(current))]

		if current.is_item_disabled(index):
			return "The menu item %s is disabled." % current.get_item_text(index)

		var submenu := current.get_item_submenu_node(index)

		if step == path.size() - 1:
			if submenu != null:
				return "%s opens a submenu: %s." % [current.get_item_text(index), ", ".join(_menu_texts(submenu))]

			current.id_pressed.emit(current.get_item_id(index))
			current.index_pressed.emit(index)

			# the top menu closes after a choice, as after a click
			if menu.visible:
				menu.hide()

			return ""

		if submenu == null:
			return "%s has no submenu." % current.get_item_text(index)

		current = submenu

	return "Name a menu item."


## Answers a dialog with its OK button.
static func accept(window: Window) -> String:
	if not window is AcceptDialog:
		return "%s has no OK button. Press one of its buttons." % window.name

	var dialog := window as AcceptDialog
	var error := press(dialog.get_ok_button())

	# a dialog hides itself after the frame; the next script line sees it closed
	if error.is_empty() and dialog.dialog_hide_on_ok and dialog.visible:
		dialog.hide()

	return error


## Closes a window as its close button does. A dialog takes it as Cancel.
static func close(window: Window) -> String:
	var error := ""

	if window is ConfirmationDialog:
		error = press((window as ConfirmationDialog).get_cancel_button())
	else:
		window.notification(Node.NOTIFICATION_WM_CLOSE_REQUEST)
		window.close_requested.emit()

	# a dialog hides itself after the frame; the next script line sees it closed
	if error.is_empty() and (window is Popup or window is AcceptDialog) and window.visible:
		window.hide()

	return error


## Selects a path in a file dialog, as a double click on the file does.
static func choose_file(dialog: FileDialog, path: String) -> String:
	if dialog.file_mode in [FileDialog.FILE_MODE_OPEN_FILE, FileDialog.FILE_MODE_OPEN_FILES, FileDialog.FILE_MODE_OPEN_ANY]:
		var folder_allowed := dialog.file_mode == FileDialog.FILE_MODE_OPEN_ANY and DirAccess.dir_exists_absolute(path)

		if not FileAccess.file_exists(path) and not folder_allowed:
			return "The file %s does not exist." % path
	elif dialog.file_mode == FileDialog.FILE_MODE_OPEN_DIR and not DirAccess.dir_exists_absolute(path):
		return "The folder %s does not exist." % path

	dialog.current_path = path
	dialog.hide()

	match dialog.file_mode:
		FileDialog.FILE_MODE_OPEN_FILES:
			dialog.files_selected.emit(PackedStringArray([path]))
		FileDialog.FILE_MODE_OPEN_DIR:
			dialog.dir_selected.emit(path)
		FileDialog.FILE_MODE_OPEN_ANY:
			if DirAccess.dir_exists_absolute(path):
				dialog.dir_selected.emit(path)
			else:
				dialog.file_selected.emit(path)
		_:
			dialog.file_selected.emit(path)

	return ""


# the index of the item that `value` names: an index, or a text. An exact
# text wins; then a text that differs only in case, an "&" or an ending "..."
static func _find_item(value: Variant, count: int, text_of: Callable) -> int:
	if typeof(value) in [TYPE_INT, TYPE_FLOAT]:
		return int(value) if int(value) >= 0 and int(value) < count else -1

	if not value is String:
		return -1

	for index in count:
		if str(text_of.call(index)) == value:
			return index

	for index in count:
		if plain_text(str(text_of.call(index))) == plain_text(value):
			return index

	return -1


## A text for comparison: lower case, without the "&" of a shortcut letter
## and without an ending "..." or ":".
static func plain_text(text: String) -> String:
	return text.to_lower().replace("&", "").replace("…", "").replace("...", "").strip_edges().trim_suffix(":").strip_edges()


static func _menu_texts(menu: PopupMenu) -> PackedStringArray:
	var texts := PackedStringArray()

	for index in menu.item_count:
		if not menu.is_item_separator(index):
			texts.append(menu.get_item_text(index))

	return texts


static func _no_item(control: Control, item: Variant) -> String:
	return "%s has no item %s." % [control.name, str(item)]


static func _label(control: Control) -> String:
	var text := UiProbe.control_text(control)

	return text if not text.is_empty() else str(control.name)
