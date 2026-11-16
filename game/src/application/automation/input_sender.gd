class_name InputSender
extends RefCounted
## Sends mouse and keyboard input to the game for scripts, as the devices of
## the player do. The events go through the input of the engine, thus the
## interface, the map and the key bindings react as to real input, also in
## a headless game. A position is in pixels of the game window.

const BUTTONS := {
	"left": MOUSE_BUTTON_LEFT, "right": MOUSE_BUTTON_RIGHT, "middle": MOUSE_BUTTON_MIDDLE,
	"wheelup": MOUSE_BUTTON_WHEEL_UP, "wheeldown": MOUSE_BUTTON_WHEEL_DOWN,
	"wheelleft": MOUSE_BUTTON_WHEEL_LEFT, "wheelright": MOUSE_BUTTON_WHEEL_RIGHT,
	"back": MOUSE_BUTTON_XBUTTON1, "forward": MOUSE_BUTTON_XBUTTON2,
}
const BUTTON_MASKS := {
	MOUSE_BUTTON_LEFT: MOUSE_BUTTON_MASK_LEFT, MOUSE_BUTTON_RIGHT: MOUSE_BUTTON_MASK_RIGHT,
	MOUSE_BUTTON_MIDDLE: MOUSE_BUTTON_MASK_MIDDLE, MOUSE_BUTTON_XBUTTON1: MOUSE_BUTTON_MASK_MB_XBUTTON1,
	MOUSE_BUTTON_XBUTTON2: MOUSE_BUTTON_MASK_MB_XBUTTON2,
}
# the names of the modifier keys in a key text such as "Ctrl+Shift+S"
const MODIFIERS := {
	"shift": KEY_MASK_SHIFT, "ctrl": KEY_MASK_CTRL, "control": KEY_MASK_CTRL, "alt": KEY_MASK_ALT, "option": KEY_MASK_ALT,
	"cmd": KEY_MASK_META, "command": KEY_MASK_META, "meta": KEY_MASK_META, "win": KEY_MASK_META, "super": KEY_MASK_META,
}
# the modifier keys, and the modifier that each one holds
const MODIFIER_KEYS := {KEY_SHIFT: KEY_MASK_SHIFT, KEY_CTRL: KEY_MASK_CTRL, KEY_ALT: KEY_MASK_ALT, KEY_META: KEY_MASK_META}
# key names that differ from the names of the engine
const KEY_ALIASES := {
	"esc": "Escape", "return": "Enter", "del": "Delete", "ins": "Insert", "pgup": "PageUp", "pgdn": "PageDown",
	"pagedown": "PageDown", "pageup": "PageUp", "plus": "Plus", "minus": "Minus", "space": "Space", "spacebar": "Space",
	"backspace": "Backspace", "capslock": "CapsLock",
}

# the pressed mouse buttons, and the place of the pointer
var _button_mask := 0
var _position := Vector2.ZERO
# the modifier keys that scripts hold
var _modifiers := 0


func position() -> Vector2:
	return _position


## The mouse button of a name such as "left", or MOUSE_BUTTON_NONE.
static func button(name: Variant) -> MouseButton:
	return BUTTONS.get(str(name).to_lower().replace("_", "").replace(" ", ""), MOUSE_BUTTON_NONE) as MouseButton


## Moves the pointer.
func move(point: Vector2) -> void:
	var event := InputEventMouseMotion.new()
	event.position = point
	event.global_position = point
	event.relative = point - _position
	event.screen_relative = event.relative
	event.button_mask = _button_mask as MouseButtonMask
	_position = point
	_modify(event)
	_send(event)


## Presses or releases a mouse button at the pointer.
func press_button(mouse_button: MouseButton, pressed: bool, double_click := false) -> void:
	var mask: int = BUTTON_MASKS.get(mouse_button, 0)
	_button_mask = (_button_mask | mask) if pressed else (_button_mask & ~mask)
	var event := InputEventMouseButton.new()
	event.position = _position
	event.global_position = _position
	event.button_index = mouse_button
	event.pressed = pressed
	event.double_click = double_click and pressed
	event.button_mask = _button_mask as MouseButtonMask
	event.factor = 1.0
	_modify(event)
	_send(event)


## Turns the mouse wheel one step at the pointer.
func scroll(mouse_button: MouseButton) -> void:
	press_button(mouse_button, true)
	press_button(mouse_button, false)


## Presses or releases a key. `text` is a key with its modifiers, such as
## "Ctrl+S", "Shift+Tab" or "F12". Returns an empty text, or why the text
## names no key.
func press_key(text: String, pressed: bool) -> String:
	var parsed := parse_key(text)

	if parsed.is_empty():
		return "Unknown key: %s. Use a name such as A, F12, Escape, Space, Up or Ctrl+Shift+S." % text

	var keycode: Key = parsed.keycode

	if MODIFIER_KEYS.has(keycode):
		_modifiers = (_modifiers | MODIFIER_KEYS[keycode]) if pressed else (_modifiers & ~int(MODIFIER_KEYS[keycode]))

	var event := InputEventKey.new()
	event.keycode = keycode
	event.physical_keycode = keycode
	event.key_label = keycode
	event.pressed = pressed
	var modifiers := int(parsed.modifiers) | _modifiers
	event.shift_pressed = modifiers & KEY_MASK_SHIFT != 0
	event.ctrl_pressed = modifiers & KEY_MASK_CTRL != 0
	event.alt_pressed = modifiers & KEY_MASK_ALT != 0
	event.meta_pressed = modifiers & KEY_MASK_META != 0

	# a key that types a character sends it, unless a command modifier is down
	if pressed and modifiers & (KEY_MASK_CTRL | KEY_MASK_ALT | KEY_MASK_META) == 0:
		event.unicode = _unicode(keycode, event.shift_pressed)

	_send(event)

	return ""


## Types a text, one character at a time, into the control with the focus.
func type_text(text: String) -> void:
	for index in text.length():
		var code := text.unicode_at(index)

		for pressed: bool in [true, false]:
			var event := InputEventKey.new()
			event.pressed = pressed
			event.unicode = code if pressed else 0

			if code == 10:
				event.keycode = KEY_ENTER
				event.physical_keycode = KEY_ENTER
				event.unicode = 0

			_send(event)


## Releases every mouse button and modifier key that a script holds.
func release_all() -> void:
	for mouse_button: MouseButton in BUTTON_MASKS:
		if _button_mask & int(BUTTON_MASKS[mouse_button]) != 0:
			press_button(mouse_button, false)

	_modifiers = 0


## The key of a text such as "Ctrl+Shift+S": { keycode, modifiers }, or an
## empty Dictionary.
static func parse_key(text: String) -> Dictionary:
	var modifiers := 0
	var words := text.strip_edges().split("+", false)

	# "+" is also a key: "Ctrl++"
	if text.strip_edges().ends_with("+"):
		words.append("Plus")

	if words.is_empty():
		return {}

	for index in words.size() - 1:
		var modifier: int = MODIFIERS.get(words[index].strip_edges().to_lower(), 0)

		if modifier == 0:
			return {}

		modifiers |= modifier

	var name := words[words.size() - 1].strip_edges()
	var keycode := OS.find_keycode_from_string(KEY_ALIASES.get(name.to_lower(), name))

	if keycode == KEY_NONE and MODIFIERS.has(name.to_lower()):
		keycode = MODIFIER_KEYS.find_key(MODIFIERS[name.to_lower()])

	if keycode == KEY_NONE:
		return {}

	return {"keycode": keycode, "modifiers": modifiers}


# the character that a key types, or 0
static func _unicode(keycode: Key, shift: bool) -> int:
	if keycode >= KEY_A and keycode <= KEY_Z:
		return keycode if shift else keycode + 32

	if keycode >= KEY_SPACE and keycode <= KEY_ASCIITILDE and not shift:
		return keycode

	return 0


func _modify(event: InputEventWithModifiers) -> void:
	event.shift_pressed = _modifiers & KEY_MASK_SHIFT != 0
	event.ctrl_pressed = _modifiers & KEY_MASK_CTRL != 0
	event.alt_pressed = _modifiers & KEY_MASK_ALT != 0
	event.meta_pressed = _modifiers & KEY_MASK_META != 0


func _send(event: InputEvent) -> void:
	Input.parse_input_event(event)
