class_name Multipart
extends RefCounted
## multipart/form-data body builder shared by connectors.

const BOUNDARY := "----RideFormBoundary9f3a1c7e"


static func content_type() -> String:
	return "Content-Type: multipart/form-data; boundary=" + BOUNDARY


## fields: {name: value}; file_field/file_name/file_bytes add one binary part.
static func build(fields: Dictionary, file_field := "", file_name := "", file_bytes := PackedByteArray()) -> PackedByteArray:
	var body := PackedByteArray()
	for k in fields:
		body.append_array(("--%s\r\nContent-Disposition: form-data; name=\"%s\"\r\n\r\n%s\r\n" % [BOUNDARY, k, str(fields[k])]).to_utf8_buffer())
	if file_field != "":
		body.append_array(("--%s\r\nContent-Disposition: form-data; name=\"%s\"; filename=\"%s\"\r\nContent-Type: application/octet-stream\r\n\r\n" % [BOUNDARY, file_field, file_name]).to_utf8_buffer())
		body.append_array(file_bytes)
		body.append_array("\r\n".to_utf8_buffer())
	body.append_array(("--%s--\r\n" % BOUNDARY).to_utf8_buffer())
	return body
