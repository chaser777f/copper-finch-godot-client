extends Node
## HTTP-only client. No merchant decisions, prices, or game-state mutations live here.
signal changed

var base_url: String = str(ProjectSettings.get_setting("merchant/backend_url", "")).trim_suffix("/")
var allow_live_providers: bool = bool(ProjectSettings.get_setting("merchant/allow_live_providers", false))
var state: Dictionary = {}
var config: Dictionary = {}
var pending_purchase: Dictionary = {}
var busy := false
var connected := false
var status_text := "Not connected."
var status_is_error := false
# Tests can use a separate local profile without touching the interactive client.
var storage_prefix := "user://merchant-session-"
var request_timeout := 30.0
var _session_id := ""
var _token := ""
var _http: HTTPRequest
var _storage_loaded := false
var _storage_valid := true
var _basic_auth := "" # Memory only; never serialized or logged.
var _tester_id := ""


func _ready() -> void:
	_http = HTTPRequest.new()
	_http.timeout = request_timeout
	_http.max_redirects = 0 # Never forward the session capability to a redirect target.
	_http.body_size_limit = 1048576
	add_child(_http)


func configure_connection(url: String, username: String, password: String, live: bool) -> bool:
	if busy:
		return false
	var target := url.strip_edges().trim_suffix("/")
	var valid_url := RegEx.new()
	valid_url.compile("^https?://[A-Za-z0-9.-]+(:[0-9]{1,5})?$")
	var loopback := target == "http://127.0.0.1" or target.begins_with("http://127.0.0.1:") or target == "http://localhost" or target.begins_with("http://localhost:")
	if valid_url.search(target) == null or (not target.begins_with("https://") and not loopback):
		_finish("Use an HTTPS server address with no path, password, query or fragment. HTTP is allowed only on localhost.", true)
		return false
	if username.contains(":") or username.contains("\n") or username.contains("\r") or username.is_empty() != password.is_empty():
		_finish("Enter both tester username and password, or leave both empty for local mock mode.", true)
		return false
	base_url = target
	allow_live_providers = live
	_basic_auth = "" if username.is_empty() else "Basic " + Marshalls.utf8_to_base64(username + ":" + password)
	_tester_id = ""
	_session_id = ""
	_token = ""
	state = {}
	config = {}
	pending_purchase = {} # Old profile remains saved for reconciliation when reconnected.
	_storage_loaded = false
	_storage_valid = true
	connected = false
	_finish("Connection settings applied. Password is kept only in memory for this run.")
	return true


func can_talk() -> bool:
	return connected and not busy and pending_purchase.is_empty() and _storage_valid


func can_buy() -> bool:
	var offer: Variant = state.get("offer")
	return can_talk() and offer is Dictionary and float(offer.get("expires_at", 0)) > Time.get_unix_time_from_system()


func _start(message: String) -> void:
	busy = true
	status_text = message
	status_is_error = false
	changed.emit()


func _finish(message: String, failed := false) -> void:
	busy = false
	status_text = message
	status_is_error = failed
	changed.emit()


func _storage_path() -> String:
	var scope := base_url if _tester_id.is_empty() else base_url + "|" + _tester_id
	return storage_prefix + scope.sha256_text().substr(0, 16) + ".json"


func _load_session() -> bool:
	if _storage_loaded:
		return _storage_valid
	_storage_loaded = true
	if not FileAccess.file_exists(_storage_path()):
		return true
	var file := FileAccess.open(_storage_path(), FileAccess.READ)
	if file == null:
		_storage_valid = false
		return false
	var saved: Variant = JSON.parse_string(file.get_as_text())
	file.close()
	if not saved is Dictionary or saved.get("base_url") != base_url or not saved.get("session_id") is String or not saved.get("token") is String or not saved.get("pending_purchase") is Dictionary:
		_storage_valid = false
		return false
	_session_id = saved.session_id
	_token = saved.token
	pending_purchase = saved.pending_purchase
	# Godot parses every JSON number as float; the API requires a JSON integer.
	if not pending_purchase.is_empty():
		var quantity: Variant = pending_purchase.get("quantity")
		if not (quantity is float or quantity is int) or quantity != int(quantity) or quantity < 1 or quantity > 10:
			_storage_valid = false
			return false
		pending_purchase["quantity"] = int(quantity)
	_storage_valid = not _session_id.is_empty() and not _token.is_empty()
	return _storage_valid


func _save_session() -> bool:
	var path := _storage_path()
	var file := FileAccess.open(path + ".tmp", FileAccess.WRITE)
	if file == null:
		return false
	file.store_string(JSON.stringify({"base_url": base_url, "session_id": _session_id, "token": _token, "pending_purchase": pending_purchase}))
	file.flush()
	var result := file.get_error()
	file.close()
	if result != OK:
		return false
	return DirAccess.rename_absolute(path + ".tmp", path) == OK


func _session_path() -> String:
	return "/v1/merchant/sessions/" + _session_id.uri_encode()


func _request(path: String, method := HTTPClient.METHOD_GET, body: Dictionary = {}, authenticated := true) -> Dictionary:
	var headers := PackedStringArray(["Accept: application/json", "Content-Type: application/json"])
	if not _basic_auth.is_empty():
		headers.append("Authorization: " + _basic_auth)
	if authenticated:
		if not _basic_auth.is_empty():
			headers.append("X-NPC-Session-Token: " + _token)
		else:
			headers.append("Authorization: Bearer " + _token)
	if method != HTTPClient.METHOD_GET:
		headers.append("X-NPC-Request: 1")
	var error := _http.request(base_url + path, headers, method, "" if method == HTTPClient.METHOD_GET else JSON.stringify(body))
	if error != OK:
		return {"ok": false, "status": 0, "error": "Could not start HTTP request (%s)." % error}
	var response: Array = await _http.request_completed
	if response[0] != HTTPRequest.RESULT_SUCCESS:
		return {"ok": false, "status": 0, "error": "Connection failed or timed out (HTTP transport %s). No automatic retry." % response[0]}
	var code := int(response[1])
	var data: Variant = JSON.parse_string(response[3].get_string_from_utf8())
	if not data is Dictionary:
		return {"ok": false, "status": code, "error": "Server returned an unreadable response; outcome may be uncertain."}
	if code < 200 or code >= 300:
		var detail: Variant = data.get("detail", "Request rejected.")
		var message := "Request rejected."
		var reason := ""
		if detail is Dictionary:
			message = str(detail.get("message", message))
			reason = str(detail.get("code", ""))
		elif detail is String:
			message = detail
		elif detail is Array:
			message = "Input validation failed. Check item, quantity, and message."
		return {"ok": false, "status": code, "code": reason, "error": "HTTP %s: %s" % [code, message]}
	return {"ok": true, "status": code, "data": data}


func _check_config() -> bool:
	var response := await _request("/v1/npc/config", HTTPClient.METHOD_GET, {}, false)
	if not response.ok:
		status_text = response.error
		return false
	config = response.data
	if config.get("hosted", false):
		var identity := str(config.get("tester_id", ""))
		if _basic_auth.is_empty() or identity.is_empty() or (not _tester_id.is_empty() and _tester_id != identity):
			status_text = "Hosted tester identity is missing or changed. Connect again with the intended tester login."
			return false
		_tester_id = identity
	elif not _basic_auth.is_empty():
		status_text = "Tester credentials require a hosted-authentication backend. Check the address."
		return false
	if not allow_live_providers and (config.get("provider") != "mock" or config.get("dialogue_provider") != "template"):
		status_text = "Live or unknown providers blocked. This example defaults to mock/template; change project configuration explicitly to allow live."
		return false
	return true


func connect_session() -> void:
	if busy:
		return
	_start("Connecting and checking active providers…")
	connected = false
	if not await _check_config():
		_finish(status_text, true)
		return
	if not _load_session():
		_finish("Saved session cannot be read. Preserve the file for recovery; no replacement session was created.", true)
		return
	if _session_id.is_empty():
		var response := await _request("/v1/merchant/sessions", HTTPClient.METHOD_POST, {}, false)
		if not response.ok:
			_finish(response.error, true)
			return
		var data: Dictionary = response.data
		if not data.get("session_id") is String or not data.get("token") is String or not data.get("state") is Dictionary:
			_finish("Invalid session response.", true)
			return
		_session_id = data.session_id
		_token = data.token
		state = data.state
		if not _save_session():
			_storage_valid = false
			_finish("Cannot save session locally; actions are disabled.", true)
			return
		connected = true
	else:
		if not await _fetch_state():
			_finish(status_text, true)
			return
	_finish("Session ready." if pending_purchase.is_empty() else "Session resumed. Check the pending purchase receipt before continuing.")


func _fetch_state() -> bool:
	var response := await _request(_session_path())
	if not response.ok or not response.get("data", {}).get("player") is Dictionary:
		connected = false
		state = {}
		status_text = response.get("error", "Invalid state response.")
		return false
	state = response.data
	connected = true
	return true


func refresh_state() -> void:
	if busy:
		return
	if _session_id.is_empty():
		await connect_session()
		return
	_start("Refreshing authoritative state…")
	var valid := await _fetch_state()
	_finish("State refreshed." if valid else status_text, not valid)


func talk(item: String, quantity: int, message: String) -> void:
	if not can_talk():
		return
	_start("Waiting for merchant response…")
	# Recheck before each model-capable endpoint, in case the server was replaced.
	if not await _check_config():
		connected = false
		_finish(status_text, true)
		return
	var response := await _request(_session_path() + "/decide", HTTPClient.METHOD_POST, {"item": item, "quantity": quantity, "player_message": message})
	if not response.ok or not response.get("data", {}).get("state") is Dictionary:
		connected = false
		state = {} # Never leave an old offer actionable after an uncertain conversation.
		_finish(response.get("error", "Invalid conversation response.") + " Refresh state before continuing.", true)
		return
	state = response.data.state
	var application: Dictionary = response.data.get("application", {})
	if not application.is_empty() and application.get("status") != "accepted":
		_finish("Application · %s: %s" % [str(application.get("status", "unavailable")), str(application.get("message", "Conversation was not committed."))], true)
		return
	var diagnostic: Dictionary = state.get("diagnostic", {})
	var fallback: bool = diagnostic.get("status") == "fallback" or diagnostic.get("dialogue", {}).get("status") == "fallback"
	_finish("Response received with a fallback; see diagnostics." if fallback else "Merchant replied. No purchase was made.", fallback)


func buy_offer() -> void:
	if not can_buy():
		return
	var offer: Dictionary = state.offer
	pending_purchase = {"request_id": Crypto.new().generate_random_bytes(16).hex_encode(), "offer_id": offer.id, "item": offer.item, "quantity": int(offer.quantity)}
	if not _save_session():
		_storage_valid = false
		_finish("Cannot save the purchase request; nothing was sent. Actions disabled.", true)
		return
	await reconcile_purchase()


func reconcile_purchase() -> void:
	if busy or pending_purchase.is_empty() or not _storage_valid:
		return
	_start("Checking purchase receipt using the saved request ID…")
	var response := await _request(_session_path() + "/purchases", HTTPClient.METHOD_POST, pending_purchase)
	if not response.ok:
		# Only explicit backend rejection codes prove this request did not commit.
		var definite := ["stale_offer", "stale_price", "offer_consumed", "insufficient_stock", "insufficient_gold", "discount_not_permitted", "offer_mismatch", "offer_not_found", "invalid_purchase"]
		if response.get("code", "") in definite:
			var saved := pending_purchase.duplicate(true)
			pending_purchase = {}
			if not _save_session():
				pending_purchase = saved
			await _fetch_state()
		_finish(response.error + (" Purchase not confirmed. Use Check pending purchase; the same request ID will be used." if not pending_purchase.is_empty() else (" Purchase rejected; state refreshed." if connected else " Purchase rejected; reconnect to refresh state.")), true)
		return
	var receipt: Variant = response.data.get("purchase")
	if not receipt is Dictionary:
		_finish("Missing receipt. Purchase outcome uncertain; check the pending request.", true)
		return
	for key in ["request_id", "offer_id", "item", "quantity"]:
		if receipt.get(key) != pending_purchase.get(key):
			_finish("Receipt does not match the saved request. Purchase outcome uncertain.", true)
			return
	var saved := pending_purchase.duplicate(true)
	pending_purchase = {}
	if not _save_session():
		pending_purchase = saved
	var refreshed := await _fetch_state()
	var confirmation := "Purchase confirmed by server: %s × %s, %s gold. %s" % [int(receipt.quantity), receipt.item, str(int(receipt.total)) if receipt.has("total") else "unavailable", "Recorded receipt replayed; no second charge." if response.data.get("replayed", false) else ""]
	if not refreshed:
		confirmation += " State refresh failed; reconnect to refresh."
	if not pending_purchase.is_empty():
		confirmation += " Could not clear local pending record; check it again safely."
	_finish(confirmation, not refreshed or not pending_purchase.is_empty())
