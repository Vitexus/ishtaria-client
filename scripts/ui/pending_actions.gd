extends RefCounted
## Buttons that send a request to the server (the pattern of `survival_panel.gd`, shared by the other windows):
## the pressed button shows a rotating spinner at once and every registered button is locked until the server has
## answered. The spinner stays at least MIN_PENDING_MS, so the answer of a near server is still seen, and gives up
## after MAX_PENDING_MS if no answer ever comes. A press that did not become a request (the client refused it before
## sending, `in_flight` still false right after it) clears at once.

const UiKit := preload("res://scripts/ui/ui_kit.gd")
const MIN_PENDING_MS := 400
const MAX_PENDING_MS := 10000

## Whether the client behind these buttons has a request in flight; set by the window's owner (main.gd).
var in_flight: Callable = func() -> bool: return false

var _host: Node
var _buttons: Array[Button] = []
var _key := ""
var _since := 0

func _init(host: Node) -> void:
	_host = host

## Whether a press is waiting for its answer.
func pending() -> bool:
	return not _key.is_empty()

## Registers a button whose press sends a request (`act`); `key` names the action so a list drawn again while it is
## awaited puts the spinner back on the new button. A `lasting` button (outside the lists) survives `forget_buttons`.
func register(button: Button, key: String, act: Callable, lasting := false) -> void:
	_buttons.append(button)
	button.set_meta("pending_lasting", lasting)
	button.set_meta("pending_key", key)
	button.pressed.connect(func() -> void: _press(button, key, act))
	if pending():
		button.set_meta("pending_was_disabled", button.disabled)
		button.disabled = true
		if key == _key:
			UiKit.set_pending(button, true)

## Forgets the buttons of a list that is being drawn again (the pending action itself is kept).
func forget_buttons() -> void:
	_buttons.assign(_buttons.filter(func(button: Button) -> bool: return is_instance_valid(button) and button.get_meta("pending_lasting", false)))

## The client's waiting flag changed; when it drops, the pressed button comes back after the minimum moment.
func set_busy(value: bool) -> void:
	if value or not pending():
		return
	var key := _key
	var left := MIN_PENDING_MS - (Time.get_ticks_msec() - _since)
	if left > 0 and _host.is_inside_tree():
		await _host.get_tree().create_timer(left / 1000.0).timeout
	if _key == key:
		finish()

## Drops the spinner and restores every button as it was before the press.
func finish() -> void:
	_key = ""
	for button in _buttons:
		if not is_instance_valid(button):
			continue
		UiKit.set_pending(button, false)
		if button.has_meta("pending_was_disabled"):
			button.disabled = button.get_meta("pending_was_disabled")
			button.remove_meta("pending_was_disabled")

func _press(button: Button, key: String, act: Callable) -> void:
	if pending() or button.has_node("PendingSpinner"):
		return
	_key = key
	_since = Time.get_ticks_msec()
	for other in _buttons:
		if is_instance_valid(other):
			other.set_meta("pending_was_disabled", other.disabled)
			other.disabled = true
	UiKit.set_pending(button, true)
	act.call()
	if not in_flight.call():
		finish()
		return
	var sent := _since
	if _host.is_inside_tree():
		_host.get_tree().create_timer(MAX_PENDING_MS / 1000.0).timeout.connect(func() -> void:
			if _key == key and _since == sent:
				finish()
		)
