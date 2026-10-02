extends Control
## Presentation only. MerchantApi owns HTTP, persistence, and request guards.
const MerchantApi = preload("res://api/merchant_api.gd")

var _api = MerchantApi.new()
var _connection: Label
var _providers: Label
var _status: Label
var _server_url: LineEdit
var _username: LineEdit
var _password: LineEdit
var _allow_live: CheckBox
var _connect: Button
var _refresh: Button
var _pending: VBoxContainer
var _check_pending: Button
var _history: TextEdit
var _message: LineEdit
var _item: OptionButton
var _quantity: SpinBox
var _talk: Button
var _wallet: Label
var _offer: Label
var _buy: Button
var _decision: TextEdit
var _dialogue: TextEdit
var _revision: Label
var _catalog_cache: Array = []
var _has_connection_settings := false


func _ready() -> void:
	_build_ui()
	add_child(_api)
	_api.changed.connect(_render)
	var offer_clock := Timer.new()
	offer_clock.wait_time = 1.0
	offer_clock.timeout.connect(_update_controls)
	add_child(offer_clock)
	offer_clock.start()
	_has_connection_settings = false
	_api.status_text = "Enter the server address and your tester login, then Connect."
	_render()
	# This client-only release always waits for an explicit connection.


func _build_ui() -> void:
	var scroll := ScrollContainer.new()
	scroll.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	add_child(scroll)
	var margin := MarginContainer.new()
	margin.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	for edge in ["left", "top", "right", "bottom"]:
		margin.add_theme_constant_override("margin_" + edge, 20)
	scroll.add_child(margin)
	var body := VBoxContainer.new()
	body.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	body.add_theme_constant_override("separation", 12)
	margin.add_child(body)
	var title := _label(body, "The Copper Finch · Godot merchant client")
	title.add_theme_font_size_override("font_size", 25)
	_label(body, "Talk for an offer, then choose Buy. The server owns every price, balance, and purchase receipt.")
	_label(body, "Server connection")
	_label(body, "Hosted play: enter the server URL and your tester login, then choose Connect. Login stays in memory for this app session.")
	_label(body, "Server URL")
	_server_url = LineEdit.new()
	_server_url.text = _api.base_url
	_server_url.placeholder_text = "https://your-server.example"
	body.add_child(_server_url)
	_label(body, "Tester username")
	_username = LineEdit.new()
	_username.placeholder_text = "Leave blank for local mock play"
	body.add_child(_username)
	_label(body, "Tester password")
	_password = LineEdit.new()
	_password.secret = true
	_password.placeholder_text = "Never saved; cleared here when you connect"
	body.add_child(_password)
	_allow_live = CheckBox.new()
	_allow_live.text = "Allow this connection to use live AI providers (may incur server costs)"
	_allow_live.button_pressed = false
	body.add_child(_allow_live)
	_connect = _button(body, "Connect with these settings", _on_connect_pressed)
	_connection = _label(body, "Not connected")
	_providers = _label(body, "Active providers: checking server configuration…")
	_status = _label(body, "")
	_refresh = _button(body, "Retry current connection", _on_refresh_pressed)

	_pending = VBoxContainer.new()
	body.add_child(_pending)
	_label(_pending, "A saved purchase needs a receipt check. Talk and Buy stay disabled until it is resolved.")
	_check_pending = _button(_pending, "Check pending purchase", _on_check_pending_pressed)

	_label(body, "Conversation · server history")
	_history = _plain_text(body, 210)
	_history.placeholder_text = "The merchant's conversation will appear here."
	_label(body, "Your message")
	_message = LineEdit.new()
	_message.placeholder_text = "Ask the merchant about an item…"
	_message.max_length = 2000
	_message.text_changed.connect(func(_text: String): _update_controls())
	_message.text_submitted.connect(func(_text: String): _on_talk_pressed())
	body.add_child(_message)
	var request := HBoxContainer.new()
	request.add_theme_constant_override("separation", 12)
	body.add_child(request)
	var item_box := VBoxContainer.new()
	item_box.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	request.add_child(item_box)
	_label(item_box, "Item")
	_item = OptionButton.new()
	item_box.add_child(_item)
	var quantity_box := VBoxContainer.new()
	request.add_child(quantity_box)
	_label(quantity_box, "Quantity")
	_quantity = SpinBox.new()
	_quantity.min_value = 1
	_quantity.max_value = 10
	_quantity.step = 1
	_quantity.value = 1
	_quantity.custom_minimum_size.x = 105
	quantity_box.add_child(_quantity)
	_talk = _button(body, "Talk to merchant", _on_talk_pressed)

	var state_row := HBoxContainer.new()
	state_row.add_theme_constant_override("separation", 20)
	body.add_child(state_row)
	var wallet_box := VBoxContainer.new()
	wallet_box.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	state_row.add_child(wallet_box)
	_label(wallet_box, "Saved game state")
	_wallet = _label(wallet_box, "No state loaded.")
	var offer_box := VBoxContainer.new()
	offer_box.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	state_row.add_child(offer_box)
	_label(offer_box, "Current server offer")
	_offer = _label(offer_box, "No offer yet.")
	_buy = _button(offer_box, "Buy offer", _on_buy_pressed)
	_revision = _label(body, "")
	_label(body, "Latest turn diagnostics · reported separately from active server configuration")
	var diagnostics := HBoxContainer.new()
	diagnostics.add_theme_constant_override("separation", 20)
	body.add_child(diagnostics)
	var decision_box := VBoxContainer.new()
	decision_box.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	diagnostics.add_child(decision_box)
	_label(decision_box, "Decision · action selection")
	_decision = _plain_text(decision_box, 185)
	var dialogue_box := VBoxContainer.new()
	dialogue_box.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	diagnostics.add_child(dialogue_box)
	_label(dialogue_box, "Dialogue · wording only")
	_dialogue = _plain_text(dialogue_box, 185)


func _label(parent: Node, value: String) -> Label:
	var label := Label.new()
	label.text = value
	label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	label.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	parent.add_child(label)
	return label


func _button(parent: Node, value: String, callback: Callable) -> Button:
	var button := Button.new()
	button.text = value
	button.pressed.connect(callback)
	parent.add_child(button)
	return button


func _plain_text(parent: Node, height: float) -> TextEdit:
	var field := TextEdit.new()
	field.editable = false
	field.add_theme_color_override("font_readonly_color", Color(0.92, 0.92, 0.92))
	field.wrap_mode = TextEdit.LINE_WRAPPING_BOUNDARY
	field.custom_minimum_size.y = height
	field.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	parent.add_child(field)
	return field


func _render() -> void:
	_connection.text = "%s · %s%s" % [
		"Connected" if _api.connected else "Not connected", _api.base_url,
		" · Waiting for server…" if _api.busy else ""]
	_status.text = _api.status_text
	_status.modulate = Color(1.0, 0.65, 0.60) if _api.status_is_error else Color.WHITE
	var config: Dictionary = _api.config
	_providers.text = "Active decision: %s · model: %s\nActive dialogue: %s · model: %s\nLive provider requests: %s" % [
		_show(config.get("provider")), _show(config.get("model")),
		_show(config.get("dialogue_provider")), _show(config.get("dialogue_model")),
		"allowed for this connection" if _api.allow_live_providers else "disabled in this client"]
	var state: Dictionary = _api.state
	var player := _dictionary(state.get("player"))
	var merchant := _dictionary(state.get("merchant"))
	_wallet.text = "Gold: %s\nInventory:\n%s\nMerchant stock:\n%s" % [
		_show(player.get("gold")), _counts(player.get("inventory")), _counts(merchant.get("stock"))]
	_render_catalog(state.get("catalog", []))
	var history := PackedStringArray()
	for entry in state.get("history", []):
		if entry is Dictionary:
			history.append("%s: %s" % [_show(entry.get("role")), _show(entry.get("text"))])
	var transcript := "\n\n".join(history)
	if _history.text != transcript:
		_history.text = transcript
		_history.scroll_vertical = _history.get_line_count()
	var offer := _dictionary(state.get("offer"))
	if offer.is_empty():
		_offer.text = "No current offer. Talk to request a price."
		_buy.text = "Buy offer"
	else:
		# Display the exact server values; no client price or quantity calculation.
		_offer.text = "Item: %s\nQuantity: %s\nUnit price: %s gold\nTotal: %s gold\nExpires at (server Unix time): %s" % [
			_show(offer.get("item")), _show(offer.get("quantity")), _show(offer.get("unit_price")),
			_show(offer.get("total")), _show(offer.get("expires_at"))]
		_buy.text = "Buy for %s gold" % _show(offer.get("total"))
	_revision.text = "Server revision: %s · Refresh updates state; only a verified receipt confirms a purchase." % _show(state.get("revision"))
	var diagnostic := _dictionary(state.get("diagnostic"))
	_decision.text = _diagnostic_text(diagnostic, ["provider", "model", "status", "original_action", "action", "original_replaced", "fallback_reason", "enforcement_reason", "probabilities", "confidence", "elapsed_ms", "usage", "total_turn_ms"])
	_dialogue.text = _diagnostic_text(_dictionary(diagnostic.get("dialogue")), ["provider", "configured_model", "model", "status", "fallback_reason", "elapsed_ms", "usage", "requests_used", "live_request_limit"])
	_update_controls()


func _render_catalog(catalog: Variant) -> void:
	if not catalog is Array or catalog == _catalog_cache:
		return
	var selected_id := ""
	if _item.selected >= 0:
		selected_id = str(_item.get_item_metadata(_item.selected))
	_catalog_cache = catalog.duplicate(true)
	_item.clear()
	for entry in catalog:
		if entry is Dictionary and entry.has("id"):
			var index := _item.item_count
			_item.add_item(str(entry.get("name", entry["id"])))
			_item.set_item_metadata(index, str(entry["id"]))
			if str(entry["id"]) == selected_id:
				_item.select(index)


func _update_controls() -> void:
	var can_talk: bool = _api.can_talk()
	_server_url.editable = not _api.busy
	_username.editable = not _api.busy
	_password.editable = not _api.busy
	_allow_live.disabled = _api.busy
	_connect.disabled = _api.busy
	_refresh.disabled = _api.busy or not _has_connection_settings
	_refresh.text = "Refresh state" if _api.connected else "Retry current connection"
	_pending.visible = not _api.pending_purchase.is_empty()
	_check_pending.disabled = _api.busy or _api.pending_purchase.is_empty()
	_message.editable = can_talk
	_item.disabled = not can_talk
	_quantity.editable = can_talk
	_talk.disabled = not can_talk or _item.selected < 0 or _message.text.strip_edges().is_empty()
	_buy.disabled = not _api.can_buy()


func _on_connect_pressed() -> void:
	if _api.busy:
		return
	var configured: bool = _api.configure_connection(
		_server_url.text.strip_edges(), _username.text.strip_edges(), _password.text,
		_allow_live.button_pressed)
	_password.clear()
	if configured:
		_has_connection_settings = true
		_api.connect_session()


func _on_refresh_pressed() -> void:
	if _api.connected:
		_api.refresh_state()
	else:
		_api.connect_session()


func _on_talk_pressed() -> void:
	if _talk.disabled:
		return
	_quantity.apply()
	_api.talk(str(_item.get_item_metadata(_item.selected)), int(_quantity.value), _message.text.strip_edges())


func _on_buy_pressed() -> void:
	_api.buy_offer()


func _on_check_pending_pressed() -> void:
	_api.reconcile_purchase()


func _dictionary(value: Variant) -> Dictionary:
	return value if value is Dictionary else {}


func _show(value: Variant) -> String:
	if value == null:
		return "Unavailable"
	if value is Dictionary or value is Array:
		return JSON.stringify(value)
	if value is float and value == int(value):
		return str(int(value))
	return str(value)


func _counts(value: Variant) -> String:
	if not value is Dictionary:
		return "  Unavailable"
	if value.is_empty():
		return "  Empty"
	var lines := PackedStringArray()
	for key in value:
		lines.append("  %s: %s" % [str(key), _show(value[key])])
	return "\n".join(lines)


func _diagnostic_text(value: Dictionary, fields: Array) -> String:
	if value.is_empty():
		return "No diagnostic yet."
	var lines := PackedStringArray()
	for key in fields:
		lines.append("%s: %s" % [str(key), _show(value.get(key))])
	return "\n".join(lines)
