extends TestCase


func test_auth_header_is_basic_api_key() -> void:
	var c := IntervalsConnector.new()
	c.api_key = "abc123"
	assert_eq(c.auth_header(), "Authorization: Basic " + Marshalls.utf8_to_base64("API_KEY:abc123"))
	assert_true(c.is_configured())
	c.api_key = "   "
	assert_true(not c.is_configured())
	c.free()


func test_upload_url_encodes_query() -> void:
	var url := IntervalsConnector.upload_url("Cadence: Corner Exit", "Ride · 200 W")
	assert_true(url.begins_with("https://intervals.icu/api/v1/athlete/0/activities?name="))
	assert_true(not (" " in url))
	assert_true("Corner" in url)


func test_multipart_body_layout() -> void:
	var body := IntervalsConnector.build_multipart("ride.fit", PackedByteArray([1, 2, 3]), "BOUND")
	var text := body.get_string_from_utf8()
	assert_true(text.begins_with("--BOUND\r\nContent-Disposition: form-data; name=\"file\"; filename=\"ride.fit\"\r\n"))
	assert_true(text.ends_with("\r\n--BOUND--\r\n"))
	var payload_start := text.find("\r\n\r\n") + 4
	assert_eq(body[payload_start], 1)
	assert_eq(body[payload_start + 2], 3)
