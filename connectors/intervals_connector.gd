class_name IntervalsConnector
extends Connector
## intervals.icu: personal API key over HTTP basic auth, FIT upload as
## multipart form data. Docs: https://intervals.icu/api-docs.html

const BASE_URL := "https://intervals.icu/api/v1"
const BOUNDARY := "----RideFitUpload7f3a9c"

var api_key := ""

var _http: HTTPRequest
var _busy := false
var _mode := ""


func _ready() -> void:
	_http = HTTPRequest.new()
	_http.timeout = 60.0
	_http.request_completed.connect(_on_completed)
	add_child(_http)


func id() -> String:
	return "intervals"


func display_name() -> String:
	return "intervals.icu"


func is_configured() -> bool:
	return api_key.strip_edges() != ""


func auth_header() -> String:
	return "Authorization: Basic " + Marshalls.utf8_to_base64("API_KEY:" + api_key.strip_edges())


static func upload_url(activity_name: String, description: String) -> String:
	return "%s/athlete/0/activities?name=%s&description=%s" % [
		BASE_URL, activity_name.uri_encode(), description.uri_encode()]


static func build_multipart(filename: String, bytes: PackedByteArray, boundary := BOUNDARY) -> PackedByteArray:
	var head := ("--%s\r\nContent-Disposition: form-data; name=\"file\"; filename=\"%s\"\r\n" +
		"Content-Type: application/octet-stream\r\n\r\n") % [boundary, filename]
	var body := head.to_utf8_buffer()
	body.append_array(bytes)
	body.append_array(("\r\n--%s--\r\n" % boundary).to_utf8_buffer())
	return body


func upload_fit(fit_path: String, activity_name: String, description: String) -> void:
	if _busy:
		upload_finished.emit(false, "busy", "")
		return
	var f := FileAccess.open(fit_path, FileAccess.READ)
	if f == null:
		upload_finished.emit(false, "cannot read %s" % fit_path, "")
		return
	var body := build_multipart(fit_path.get_file(), f.get_buffer(f.get_length()))
	var headers := PackedStringArray([auth_header(), "Content-Type: multipart/form-data; boundary=" + BOUNDARY])
	_mode = "upload"
	_busy = true
	var err := _http.request_raw(upload_url(activity_name, description), headers, HTTPClient.METHOD_POST, body)
	if err != OK:
		_busy = false
		upload_finished.emit(false, "request failed: %s" % error_string(err), "")


func test_connection() -> void:
	if _busy:
		test_finished.emit(false, "busy")
		return
	_mode = "test"
	_busy = true
	var err := _http.request(BASE_URL + "/athlete/0", PackedStringArray([auth_header()]))
	if err != OK:
		_busy = false
		test_finished.emit(false, "request failed: %s" % error_string(err))


func _on_completed(result: int, code: int, _headers: PackedStringArray, body: PackedByteArray) -> void:
	_busy = false
	var text := body.get_string_from_utf8()
	var json: Variant = JSON.parse_string(text)
	if result != HTTPRequest.RESULT_SUCCESS:
		_emit(false, "network error (%d)" % result, "")
		return
	if code == 401 or code == 403:
		_emit(false, "intervals.icu rejected the API key", "")
		return
	if code < 200 or code >= 300:
		var msg := str(json.get("error", text)) if json is Dictionary else text
		_emit(false, "intervals.icu returned %d: %s" % [code, msg.left(200)], "")
		return
	if _mode == "test":
		var who := str(json.get("name", json.get("id", "ok"))) if json is Dictionary else "ok"
		test_finished.emit(true, "Connected as %s" % who)
	else:
		var rid := ""
		if json is Dictionary:
			rid = str(json.get("id", ""))
			if rid == "" and json.has("icu_athlete_id"):
				rid = "uploaded"
		upload_finished.emit(true, "Uploaded to intervals.icu", rid)


func _emit(ok: bool, message: String, rid: String) -> void:
	if _mode == "test":
		test_finished.emit(ok, message)
	else:
		upload_finished.emit(ok, message, rid)
