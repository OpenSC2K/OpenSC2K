class_name ScriptingInputApi
extends ScriptingApiBase
## The `input` functions of scripts: mouse and keyboard input, as the
## devices of the player send it. A script uses them for an action that has
## no function of its own, such as a drag on a drawing canvas. A position is
## in pixels of the game window. Mods cannot use these functions. See
## docs/scripting.md.

const RESTRICTED: PackedStringArray = [
	"input.move", "input.button", "input.scroll", "input.key", "input.text", "input.release", "input.position",
]

var sender: InputSender


func handlers() -> Dictionary[String, Callable]:
	return {
		"input.move": _move,
		"input.button": _button,
		"input.scroll": _scroll,
		"input.key": _key,
		"input.text": _text,
		"input.release": _release,
		"input.position": func(_arguments: Array) -> Variant: return _point_data(_sender().position()),
	}


func _sender() -> InputSender:
	if sender == null:
		sender = InputSender.new()

	return sender


static func _point_data(value: Vector2) -> Dictionary:
	return {"x": roundi(value.x), "y": roundi(value.y)}


# a window position from a script argument { x, y }, or the pointer when
# the script gave none. Vector2.INF, with a failure, for a wrong argument
func _position(arguments: Array, index: int) -> Vector2:
	var value: Variant = argument(arguments, index)

	if value == null:
		return _sender().position()

	if not value is Dictionary or not is_number(value.get("x")) or not is_number(value.get("y")):
		fail("A position is { x, y } in pixels of the game window.")

		return Vector2.INF

	return Vector2(float(value.x), float(value.y))


func _move(arguments: Array) -> Variant:
	var position := _position(arguments, 0)

	if not position.is_finite():
		return null

	_sender().move(position)

	return _point_data(position)


# button(name, pressed, position, doubleClick): presses or releases a mouse button
func _button(arguments: Array) -> Variant:
	var button := InputSender.button(argument(arguments, 0, "left"))
	var position := _position(arguments, 2)

	if button == MOUSE_BUTTON_NONE:
		return fail("The mouse button must be one of: %s." % ", ".join(InputSender.BUTTONS.keys()))

	if not position.is_finite():
		return null

	if position != _sender().position():
		_sender().move(position)

	_sender().press_button(button, bool(argument(arguments, 1, true)), bool(argument(arguments, 3, false)))

	return _point_data(position)


# scroll(steps, position, horizontal): turns the wheel; a positive step scrolls down
func _scroll(arguments: Array) -> Variant:
	var steps := integer(argument(arguments, 0, 1), 1)
	var position := _position(arguments, 1)

	if not position.is_finite():
		return null

	if position != _sender().position():
		_sender().move(position)

	var button := MOUSE_BUTTON_WHEEL_DOWN if steps > 0 else MOUSE_BUTTON_WHEEL_UP

	if bool(argument(arguments, 2, false)):
		button = MOUSE_BUTTON_WHEEL_RIGHT if steps > 0 else MOUSE_BUTTON_WHEEL_LEFT

	for _step in absi(steps):
		_sender().scroll(button)

	return _point_data(position)


# key(text, pressed): presses or releases a key such as "Ctrl+S"
func _key(arguments: Array) -> Variant:
	var error := _sender().press_key(str(argument(arguments, 0, "")), bool(argument(arguments, 1, true)))

	return true if error.is_empty() else fail(error)


func _text(arguments: Array) -> Variant:
	_sender().type_text(str(argument(arguments, 0, "")))

	return true


func _release(_arguments: Array) -> Variant:
	_sender().release_all()

	return true
