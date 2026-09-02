class_name Connector
extends Node
## A destination for finished rides. Implementations upload a FIT file and
## report the outcome; the UploadQueue handles retries and persistence.

signal upload_finished(ok: bool, message: String, remote_id: String)
signal test_finished(ok: bool, message: String)


func id() -> String:
	return "connector"


func display_name() -> String:
	return "Connector"


func is_configured() -> bool:
	return false


func upload_fit(_fit_path: String, _activity_name: String, _description: String) -> void:
	upload_finished.emit(false, "not implemented", "")


func test_connection() -> void:
	test_finished.emit(false, "not implemented")
