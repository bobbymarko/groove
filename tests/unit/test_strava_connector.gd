extends TestCase


func test_query_param_from_request_line() -> void:
	var line := "GET /exchange_token?state=&code=abc123&scope=read,activity:write HTTP/1.1\r\nHost: localhost:8734\r\n"
	assert_eq(StravaConnector._query_param(line, "code"), "abc123")
	assert_eq(StravaConnector._query_param(line, "scope"), "read,activity:write")
	assert_eq(StravaConnector._query_param(line, "missing"), "")
	assert_eq(StravaConnector._query_param("GET /exchange_token?error=access_denied HTTP/1.1", "code"), "")


func test_configured_requires_app_and_refresh_token() -> void:
	var s := StravaConnector.new()
	assert_true(not s.is_configured())
	s.client_id = "1"
	s.client_secret = "x"
	assert_true(s.has_app())
	assert_true(not s.is_configured())
	s.refresh_token = "r"
	assert_true(s.is_configured())
	s.free()


func test_multipart_fields_and_file() -> void:
	var body := Multipart.build({"data_type": "fit", "trainer": "1"}, "file", "ride.fit", PackedByteArray([9, 8, 7]))
	var text := body.get_string_from_utf8()
	assert_true(text.contains("name=\"data_type\"\r\n\r\nfit\r\n"))
	assert_true(text.contains("name=\"trainer\"\r\n\r\n1\r\n"))
	assert_true(text.contains("name=\"file\"; filename=\"ride.fit\""))
	assert_true(text.ends_with("--%s--\r\n" % Multipart.BOUNDARY))
	var payload_start := text.find("application/octet-stream\r\n\r\n") + "application/octet-stream\r\n\r\n".length()
	assert_eq(body[payload_start], 9)
	assert_eq(body[payload_start + 2], 7)
