class_name StravaConnector
extends Connector
## Strava: OAuth 2 authorization-code flow through the system browser with a
## loopback redirect, token refresh, and FIT upload with a processing poll.
## Needs the user's own Strava API application (client id + secret); the app's
## "Authorization Callback Domain" must be "localhost". Photos cannot be
## attached through the public API (partner apps only).

signal auth_state_changed(connected: bool, message: String)

const AUTH_URL := "https://www.strava.com/oauth/authorize"
const TOKEN_URL := "https://www.strava.com/oauth/token"
const API := "https://www.strava.com/api/v3"
const SCOPE := "read,activity:write"
const PORTS := [8734, 8735, 8736, 8737]
const POLL_SECONDS := 2.0
const POLL_LIMIT := 20

var client_id := ""
var client_secret := ""
var access_token := ""
var refresh_token := ""
var expires_at := 0
var athlete_name := ""

var _http: HTTPRequest
var _mode := ""              # "token" | "refresh" | "upload" | "poll" | "test"
var _server: TCPServer
var _redirect_uri := ""
var _pending_upload: Dictionary = {}
var _poll_id := ""
var _polls := 0
var _poll_timer: Timer
var _after_refresh: Callable


func _ready() -> void:
	_http = HTTPRequest.new()
	_http.timeout = 60.0
	_http.request_completed.connect(_on_completed)
	add_child(_http)
	_poll_timer = Timer.new()
	_poll_timer.one_shot = true
	_poll_timer.timeout.connect(_poll_upload)
	add_child(_poll_timer)


func id() -> String:
	return "strava"


func display_name() -> String:
	return "Strava"


func has_app() -> bool:
	return client_id.strip_edges() != "" and client_secret.strip_edges() != ""


func is_configured() -> bool:
	return has_app() and refresh_token != ""


# --- OAuth --------------------------------------------------------------------

## Open the browser for consent and wait for the redirect on a loopback port.
func connect_account() -> void:
	if not has_app():
		auth_state_changed.emit(false, "Enter your Strava client ID and secret first")
		return
	_server = TCPServer.new()
	var bound := -1
	for p in PORTS:
		if _server.listen(p, "127.0.0.1") == OK:
			bound = p
			break
	if bound < 0:
		auth_state_changed.emit(false, "Could not open a local port for the Strava redirect")
		return
	_redirect_uri = "http://localhost:%d/exchange_token" % bound
	var url := "%s?client_id=%s&response_type=code&redirect_uri=%s&approval_prompt=force&scope=%s" % [
		AUTH_URL, client_id.strip_edges().uri_encode(), _redirect_uri.uri_encode(), SCOPE.uri_encode()]
	OS.shell_open(url)
	auth_state_changed.emit(false, "Waiting for you to authorize Ride in the browser…")


func disconnect_account() -> void:
	access_token = ""
	refresh_token = ""
	expires_at = 0
	athlete_name = ""
	auth_state_changed.emit(false, "Disconnected")


func _process(_delta: float) -> void:
	if _server == null or not _server.is_connection_available():
		return
	var peer := _server.take_connection()
	# Give the browser a moment to send the request line.
	var waited := 0
	while peer.get_available_bytes() == 0 and waited < 50:
		OS.delay_msec(10)
		waited += 1
	var request := peer.get_utf8_string(peer.get_available_bytes())
	var code := _query_param(request, "code")
	var body := "<html><body style='font-family:sans-serif;background:#12151f;color:#eee;text-align:center;padding-top:20vh'><h2>%s</h2><p>You can close this tab and return to Ride.</p></body></html>" % (
		"Ride is connected to Strava." if code != "" else "Strava did not return a code.")
	peer.put_data(("HTTP/1.1 200 OK\r\nContent-Type: text/html; charset=utf-8\r\nContent-Length: %d\r\nConnection: close\r\n\r\n" % body.to_utf8_buffer().size()).to_utf8_buffer())
	peer.put_data(body.to_utf8_buffer())
	peer.disconnect_from_host()
	_server.stop()
	_server = null
	if code == "":
		auth_state_changed.emit(false, "Authorization was cancelled or denied")
		return
	_mode = "token"
	_http.request(TOKEN_URL, PackedStringArray(["Content-Type: application/x-www-form-urlencoded"]), HTTPClient.METHOD_POST,
		"client_id=%s&client_secret=%s&code=%s&grant_type=authorization_code" % [client_id.strip_edges().uri_encode(), client_secret.strip_edges().uri_encode(), code.uri_encode()])


static func _query_param(request_line: String, key: String) -> String:
	var q := request_line.find("?")
	var sp := request_line.find(" HTTP/")
	if q < 0 or sp < 0 or sp < q:
		return ""
	for pair in request_line.substr(q + 1, sp - q - 1).split("&"):
		var kv := pair.split("=", true, 1)
		if kv.size() == 2 and kv[0] == key:
			return kv[1].uri_decode()
	return ""


## Refresh if the access token is within a minute of expiring, then run `then`.
func _with_token(then: Callable) -> void:
	if access_token != "" and expires_at - 60 > int(Time.get_unix_time_from_system()):
		then.call()
		return
	_after_refresh = then
	_mode = "refresh"
	_http.request(TOKEN_URL, PackedStringArray(["Content-Type: application/x-www-form-urlencoded"]), HTTPClient.METHOD_POST,
		"client_id=%s&client_secret=%s&grant_type=refresh_token&refresh_token=%s" % [client_id.strip_edges().uri_encode(), client_secret.strip_edges().uri_encode(), refresh_token.uri_encode()])


# --- Upload --------------------------------------------------------------------

func upload_fit(fit_path: String, activity_name: String, description: String) -> void:
	if not is_configured():
		upload_finished.emit(false, "Strava is not connected", "")
		return
	var f := FileAccess.open(fit_path, FileAccess.READ)
	if f == null:
		upload_finished.emit(false, "cannot read %s" % fit_path, "")
		return
	_pending_upload = {"bytes": f.get_buffer(f.get_length()), "file": fit_path.get_file(), "name": activity_name, "description": description}
	_with_token(_send_upload)


func _send_upload() -> void:
	var body := Multipart.build({
		"data_type": "fit", "name": _pending_upload.name, "description": _pending_upload.description,
		"trainer": "1", "external_id": _pending_upload.file,
	}, "file", _pending_upload.file, _pending_upload.bytes)
	_mode = "upload"
	var err := _http.request_raw(API + "/uploads", PackedStringArray(["Authorization: Bearer " + access_token, Multipart.content_type()]), HTTPClient.METHOD_POST, body)
	if err != OK:
		upload_finished.emit(false, "request failed: %s" % error_string(err), "")


func _poll_upload() -> void:
	_mode = "poll"
	_http.request(API + "/uploads/" + _poll_id, PackedStringArray(["Authorization: Bearer " + access_token]))


func test_connection() -> void:
	if not is_configured():
		test_finished.emit(false, "Not connected")
		return
	_with_token(func() -> void:
		_mode = "test"
		_http.request(API + "/athlete", PackedStringArray(["Authorization: Bearer " + access_token])))


# --- Responses -------------------------------------------------------------------

func _on_completed(result: int, code: int, _headers: PackedStringArray, body: PackedByteArray) -> void:
	var text := body.get_string_from_utf8()
	var json: Variant = JSON.parse_string(text)
	var ok := result == HTTPRequest.RESULT_SUCCESS and code >= 200 and code < 300
	var err_msg := ""
	if not ok:
		err_msg = "network error (%d)" % result if result != HTTPRequest.RESULT_SUCCESS else "Strava returned %d: %s" % [code, (str(json.get("message", text)) if json is Dictionary else text).left(200)]
	match _mode:
		"token", "refresh":
			if not ok or not (json is Dictionary):
				if _mode == "token":
					auth_state_changed.emit(false, "Token exchange failed: " + err_msg)
				else:
					upload_finished.emit(false, "Strava token refresh failed: " + err_msg, "")
				return
			access_token = str(json.get("access_token", ""))
			refresh_token = str(json.get("refresh_token", refresh_token))
			expires_at = int(json.get("expires_at", 0))
			if json.has("athlete"):
				athlete_name = "%s %s" % [str(json.athlete.get("firstname", "")), str(json.athlete.get("lastname", ""))]
			auth_state_changed.emit(true, "Connected as %s" % athlete_name if athlete_name.strip_edges() != "" else "Connected")
			if _mode == "refresh" and _after_refresh.is_valid():
				var cb := _after_refresh
				_after_refresh = Callable()
				cb.call()
		"upload":
			if not ok or not (json is Dictionary):
				upload_finished.emit(false, err_msg, "")
				return
			if json.get("error") != null:
				upload_finished.emit(false, "Strava: %s" % str(json.error), "")
				return
			_poll_id = str(json.get("id_str", str(json.get("id", ""))))
			_polls = 0
			_poll_timer.start(POLL_SECONDS)
		"poll":
			if not ok or not (json is Dictionary):
				upload_finished.emit(false, err_msg, "")
				return
			if json.get("error") != null:
				upload_finished.emit(false, "Strava: %s" % str(json.error), "")
				return
			if json.get("activity_id") != null:
				upload_finished.emit(true, "Posted to Strava", str(json.activity_id))
				return
			_polls += 1
			if _polls >= POLL_LIMIT:
				upload_finished.emit(true, "Uploaded; Strava is still processing it", "")
				return
			_poll_timer.start(POLL_SECONDS)
		"test":
			if ok and json is Dictionary:
				athlete_name = "%s %s" % [str(json.get("firstname", "")), str(json.get("lastname", ""))]
				test_finished.emit(true, "Connected as %s" % athlete_name)
			else:
				test_finished.emit(false, err_msg)
