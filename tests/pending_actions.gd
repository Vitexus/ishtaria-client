extends SceneTree
## Buttons that talk to the server: spinner and lock at once, back only after the answer (scripts/ui/pending_actions.gd).

const PendingActions := preload("res://scripts/ui/pending_actions.gd")

var _failures := 0

func _check(ok: bool, what: String) -> void:
	if not ok:
		_failures += 1
		push_error("FAILED: " + what)

func _init() -> void:
	_run.call_deferred()

func _run() -> void:
	var host := Control.new()
	root.add_child(host)
	var pending := PendingActions.new(host)
	# Lambdas capture locals by value: the client's flag lives in a dictionary they share.
	var client := {"waiting": false}
	pending.in_flight = func() -> bool: return client.waiting
	var sent: Array = []
	var buy := Button.new()
	var sell := Button.new()
	var close := Button.new()
	for button in [buy, sell, close]:
		button.text = "x"
		host.add_child(button)
	close.disabled = true
	pending.register(buy, "Buy", func() -> void:
		sent.append("buy")
		client.waiting = true
	)
	pending.register(sell, "Sell", func() -> void: sent.append("sell"))
	pending.register(close, "Close", func() -> void: sent.append("close"), true)

	buy.pressed.emit()
	_check(sent == ["buy"], "the press sends the request")
	_check(buy.has_node("PendingSpinner") and buy.disabled and buy.text.is_empty(), "the pressed button spins at once")
	_check(sell.disabled and close.disabled, "every other button is locked while the answer is awaited")
	buy.pressed.emit()
	sell.pressed.emit()
	_check(sent == ["buy"], "no second request while one is awaited")

	# The list is drawn again while waiting: the new button of the same action keeps the spinner.
	pending.forget_buttons()
	var buy_again := Button.new()
	host.add_child(buy_again)
	pending.register(buy_again, "Buy", func() -> void: sent.append("buy again"))
	_check(buy_again.has_node("PendingSpinner") and buy_again.disabled, "a redrawn button of the awaited action spins")

	client.waiting = false
	pending.set_busy(true)
	_check(pending.pending(), "busy keeps waiting")
	pending.set_busy(false)
	_check(buy_again.has_node("PendingSpinner"), "the spinner stays a moment even for a quick answer")
	await create_timer(PendingActions.MIN_PENDING_MS / 1000.0 + 0.1).timeout
	_check(not pending.pending() and not buy_again.has_node("PendingSpinner") and not buy_again.disabled, "the answer brings the button back")
	_check(close.disabled, "a lasting button is restored as it was (disabled before the press)")

	# A press the client refused before sending clears at once.
	sell = Button.new()
	host.add_child(sell)
	pending.register(sell, "Sell", func() -> void: sent.append("sell"))
	sell.pressed.emit()
	_check(sent.back() == "sell" and not sell.has_node("PendingSpinner") and not sell.disabled, "a press that sent nothing does not wait")
	host.queue_free()
	print("Pending actions: %d failures" % _failures)
	quit(1 if _failures > 0 else 0)
