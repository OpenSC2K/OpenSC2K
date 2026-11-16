class_name UiProbe
extends RefCounted
## Reads the interface for scripts: the visible windows and the controls in
## them, as plain data. A window or control is named by its node path, which
## stays the same while the node lives. The first window is "main": the game
## window itself, with every control that is not in another window. A
## position is in pixels of the game window, as an image of the window shows it.

const MAIN_ID := "main"
# the controls that take input, and the kind that scripts see
const KIND_BUTTON := "button"
const KIND_CHECK := "check"
const KIND_OPTION := "option"
const KIND_MENU := "menu"
const KIND_TEXT := "text"
const KIND_NUMBER := "number"
const KIND_TABS := "tabs"
const KIND_LIST := "list"
const KIND_TREE := "tree"
const KIND_CUSTOM := "custom"
# a tree or a list shows this many rows to scripts
const MAX_ROWS := 200
const MAX_LABEL_LENGTH := 4000


## The visible windows, the lowest first: [{ id, type, title, text, modal,
## focused, rect, buttons, items }]. The last one takes the input.
static func windows(root: Window) -> Array[Dictionary]:
	var result: Array[Dictionary] = [{
		"id": MAIN_ID, "type": "main", "title": root.title, "text": "", "modal": false, "focused": root.has_focus(),
		"rect": rect_data(Rect2(Vector2.ZERO, Vector2(root.size))), "buttons": [],
	}]
	for window in visible_windows(root):
		result.append(window_data(window))

	return result


## The visible windows without the main window, the lowest first.
static func visible_windows(root: Window) -> Array[Window]:
	var found: Array[Window] = []
	_collect_windows(root, found)
	# a modal window is above the others, and the window with the focus is the top one
	found.sort_custom(func(first: Window, second: Window) -> bool: return _window_rank(first) < _window_rank(second))

	return found


static func _window_rank(window: Window) -> int:
	return (2 if window.has_focus() else 0) + (1 if window.exclusive or window is Popup else 0)


static func _collect_windows(node: Node, found: Array[Window]) -> void:
	for child in node.get_children(true):
		if child is Window:
			if not (child as Window).visible:
				continue

			found.append(child)

		_collect_windows(child, found)


static func window_data(window: Window) -> Dictionary:
	var data := {
		"id": str(window.get_path()), "type": type_name(window), "title": window.title, "text": "",
		"modal": window.exclusive, "focused": window.has_focus(),
		"rect": rect_data(window_rect(window)), "buttons": [],
	}

	if window is AcceptDialog:
		data["text"] = (window as AcceptDialog).dialog_text

	if window is PopupMenu:
		data["items"] = menu_items(window)
	else:
		for control in controls(window):
			if control.kind == KIND_BUTTON and not str(control.text).is_empty():
				data["buttons"].append(control.text)

	return data


## The items of a popup menu: [{ index, id, text, checked, disabled, separator, submenu }].
static func menu_items(menu: PopupMenu) -> Array[Dictionary]:
	var items: Array[Dictionary] = []

	for index in menu.item_count:
		var item := {
			"index": index, "id": menu.get_item_id(index), "text": menu.get_item_text(index),
			"disabled": menu.is_item_disabled(index),
		}

		if menu.is_item_separator(index):
			item["separator"] = true

		if menu.is_item_checkable(index) or menu.is_item_radio_checkable(index):
			item["checked"] = menu.is_item_checked(index)

		if menu.get_item_submenu_node(index) != null:
			item["submenu"] = menu_items(menu.get_item_submenu_node(index))

		items.append(item)

	return items


## The controls of a window that take input and show now: [{ id, kind, type,
## name, text, value, disabled, rect, ... }]. `scope` is a window, the root
## window for the main window, or a panel of the game. Controls of other
## windows are not included.
static func controls(scope: Node) -> Array[Dictionary]:
	var result: Array[Dictionary] = []
	_collect_controls(scope, result)

	return result


static func _collect_controls(node: Node, result: Array[Dictionary]) -> void:
	# the tab bar of a tab container is a part of it, not a control of its own
	for child in node.get_children(not node is TabContainer):
		if child is Window:
			continue

		if child is CanvasItem and not (child as CanvasItem).visible:
			continue

		var kind := control_kind(child)

		if not kind.is_empty():
			result.append(control_data(child, kind))

		# the parts of a control that takes input are not controls of their own
		if kind.is_empty() or kind == KIND_TABS or kind == KIND_CUSTOM:
			_collect_controls(child, result)


## The kind of a control that takes input, or an empty text.
static func control_kind(node: Node) -> String:
	if not node is Control or node is ScrollBar:
		return ""

	if node is OptionButton:
		return KIND_OPTION

	if node is MenuButton:
		return KIND_MENU

	if node is BaseButton:
		return KIND_CHECK if (node as BaseButton).toggle_mode else KIND_BUTTON

	if node is LineEdit or node is TextEdit:
		return KIND_TEXT

	if node is Range and not node is ProgressBar:
		return KIND_NUMBER

	if node is TabBar or node is TabContainer:
		return KIND_TABS

	if node is ItemList:
		return KIND_LIST

	if node is Tree:
		return KIND_TREE

	# a control with its own input code, such as the map or a drawing canvas
	if (node as Control).mouse_filter == Control.MOUSE_FILTER_STOP and node.get_script() != null and node.has_method("_gui_input"):
		return KIND_CUSTOM

	return ""


static func control_data(control: Control, kind: String) -> Dictionary:
	var data := {
		"id": str(control.get_path()), "kind": kind, "type": type_name(control), "name": str(control.name),
		"text": control_text(control), "rect": rect_data(screen_rect(control)),
	}

	if not control.tooltip_text.is_empty():
		data["tooltip"] = control.tooltip_text

	match kind:
		KIND_BUTTON:
			data["disabled"] = (control as BaseButton).disabled
		KIND_CHECK:
			data["disabled"] = (control as BaseButton).disabled
			data["value"] = (control as BaseButton).button_pressed
		KIND_OPTION:
			var option := control as OptionButton
			data["disabled"] = option.disabled
			data["value"] = option.get_item_text(option.selected) if option.selected >= 0 else ""
			data["items"] = menu_items(option.get_popup())
		KIND_MENU:
			data["disabled"] = (control as MenuButton).disabled
			data["items"] = menu_items((control as MenuButton).get_popup())
		KIND_TEXT:
			data["value"] = str(control.get("text"))
			data["disabled"] = not bool(control.get("editable"))
		KIND_NUMBER:
			var number := control as Range
			data.merge({"value": number.value, "min": number.min_value, "max": number.max_value, "step": number.step})

			if control is SpinBox:
				data["disabled"] = not (control as SpinBox).editable
			elif control is Slider:
				data["disabled"] = not (control as Slider).editable
		KIND_TABS:
			var bar := tab_bar(control)
			data["value"] = bar.get_tab_title(bar.current_tab) if bar.current_tab >= 0 and bar.tab_count > 0 else ""
			data["items"] = range(bar.tab_count).map(func(index: int) -> Dictionary:
				return {"index": index, "text": bar.get_tab_title(index), "disabled": bar.is_tab_disabled(index)})
		KIND_LIST:
			var list := control as ItemList
			data["value"] = Array(list.get_selected_items()).map(func(index: int) -> String: return list.get_item_text(index))
			data["items"] = range(mini(list.item_count, MAX_ROWS)).map(func(index: int) -> Dictionary:
				return {"index": index, "text": list.get_item_text(index), "disabled": list.is_item_disabled(index)})
		KIND_TREE:
			data["items"] = tree_rows(control as Tree)

	return data


## The rows of a tree, top to bottom: [{ index, depth, text, cells, selected }].
static func tree_rows(tree: Tree) -> Array[Dictionary]:
	var rows: Array[Dictionary] = []
	var item := tree.get_root()

	if item != null and tree.hide_root:
		item = item.get_next_in_tree()

	while item != null and rows.size() < MAX_ROWS:
		var cells := range(tree.columns).map(func(column: int) -> String: return item.get_text(column))
		var depth := 0
		var parent := item.get_parent()

		while parent != null:
			depth += 1
			parent = parent.get_parent()

		rows.append({"index": rows.size(), "depth": depth, "text": cells[0] if not cells.is_empty() else "", "cells": cells,
			"selected": range(tree.columns).any(func(column: int) -> bool: return item.is_selected(column))})
		item = item.get_next_in_tree()

	return rows


## The tree row at an index of tree_rows(), or null.
static func tree_item(tree: Tree, index: int) -> TreeItem:
	var item := tree.get_root()

	if item != null and tree.hide_root:
		item = item.get_next_in_tree()

	for _step in index:
		if item == null:
			return null

		item = item.get_next_in_tree()

	return item


static func tab_bar(control: Control) -> TabBar:
	return (control as TabContainer).get_tab_bar() if control is TabContainer else control as TabBar


## The text that names a control for the player: its label, or its tooltip.
static func control_text(control: Control) -> String:
	for property in ["text", "placeholder_text"]:
		# a text field shows its content as its value, not as its name
		if property == "text" and (control is LineEdit or control is TextEdit):
			continue

		var value: Variant = control.get(property)

		if value is String and not (value as String).is_empty():
			return value

	return control.tooltip_text


## The texts that a window shows, top to bottom: labels, rich text, buttons
## and text fields. `scope` is a window, the root window for the main window,
## or a panel of the game.
static func texts(scope: Node) -> PackedStringArray:
	var result := PackedStringArray()
	_collect_texts(scope, result)

	return result


static func _collect_texts(node: Node, result: PackedStringArray) -> void:
	for child in node.get_children(true):
		if child is Window or (child is CanvasItem and not (child as CanvasItem).visible):
			continue

		var text := ""

		if child is RichTextLabel:
			text = (child as RichTextLabel).get_parsed_text()
		elif child is Label or child is Button or child is LineEdit or child is TextEdit:
			text = str(child.get("text"))

		if not text.strip_edges().is_empty():
			result.append(text.left(MAX_LABEL_LENGTH))

		if not (child is LineEdit or child is TextEdit or child is RichTextLabel or child is OptionButton):
			_collect_texts(child, result)


## The script class of a node, or its engine class.
static func type_name(node: Node) -> String:
	var script: Script = node.get_script()

	while script != null:
		if not script.get_global_name().is_empty():
			return script.get_global_name()

		script = script.get_base_script()

	return node.get_class()


## The transform from the local coordinates of a control, in the main
## window or in an embedded window, to pixels of the game window.
static func window_transform(item: CanvasItem) -> Transform2D:
	return item.get_viewport().get_screen_transform() * item.get_global_transform_with_canvas()


## The rectangle of a control in pixels of the game window.
static func screen_rect(control: Control) -> Rect2:
	return window_transform(control) * Rect2(Vector2.ZERO, control.size)


## The rectangle of a window in pixels of the game window.
static func window_rect(window: Window) -> Rect2:
	return window.get_screen_transform() * Rect2(Vector2.ZERO, window.get_visible_rect().size)


static func rect_data(rect: Rect2) -> Dictionary:
	return {"x": roundi(rect.position.x), "y": roundi(rect.position.y), "width": roundi(rect.size.x), "height": roundi(rect.size.y)}
