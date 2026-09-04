extends Node
## Autoload "Sync". Persists pending uploads and pushes them to connectors,
## retrying on launch and on demand. A ride that fails to upload is never
## lost: the FIT file stays in the rides folder and the job stays queued.

signal changed
signal job_finished(job: Dictionary, ok: bool, message: String)

const QUEUE_PATH := "user://uploads.cfg"
const MAX_ATTEMPTS := 20

var connectors: Dictionary = {}     ## id -> Connector
var jobs: Array[Dictionary] = []    ## {id, connector, fit_path, name, description, status, attempts, last_error, remote_id}

var _active: Dictionary = {}


func _ready() -> void:
	var icu := IntervalsConnector.new()
	icu.name = "IntervalsConnector"
	add_child(icu)
	icu.upload_finished.connect(_on_upload_finished)
	connectors[icu.id()] = icu
	var strava := StravaConnector.new()
	strava.name = "StravaConnector"
	add_child(strava)
	strava.upload_finished.connect(_on_upload_finished)
	strava.auth_state_changed.connect(func(_c: bool, _m: String) -> void: _save_strava_tokens(); process_next())
	connectors[strava.id()] = strava
	_load()
	call_deferred("process_next")


func intervals() -> IntervalsConnector:
	return connectors["intervals"]


func configure_intervals(api_key: String) -> void:
	intervals().api_key = api_key
	process_next()


func strava() -> StravaConnector:
	return connectors["strava"]


func configure_strava(client_id: String, client_secret: String) -> void:
	var s := strava()
	s.client_id = client_id
	s.client_secret = client_secret
	s.access_token = App.get_secret("strava_access_token")
	s.refresh_token = App.get_secret("strava_refresh_token")
	s.expires_at = int(App.get_secret("strava_expires_at")) if App.get_secret("strava_expires_at") != "" else 0
	s.athlete_name = App.get_secret("strava_athlete")
	process_next()


func _save_strava_tokens() -> void:
	var s := strava()
	App.set_secret("strava_access_token", s.access_token)
	App.set_secret("strava_refresh_token", s.refresh_token)
	App.set_secret("strava_expires_at", str(s.expires_at))
	App.set_secret("strava_athlete", s.athlete_name)


## Connectors that are ready to receive uploads.
func configured_connectors() -> Array[Connector]:
	var out: Array[Connector] = []
	for c in connectors.values():
		if c.is_configured():
			out.append(c)
	return out


func enqueue(connector_id: String, fit_path: String, activity_name: String, description: String) -> Dictionary:
	var job := {
		"id": "%s-%d" % [connector_id, Time.get_unix_time_from_system()],
		"connector": connector_id, "fit_path": fit_path, "name": activity_name,
		"description": description, "status": "pending", "attempts": 0, "last_error": "", "remote_id": "",
	}
	jobs.append(job)
	_save()
	changed.emit()
	process_next()
	return job


func jobs_for(fit_path: String) -> Array[Dictionary]:
	var out: Array[Dictionary] = []
	for j in jobs:
		if j.fit_path == fit_path:
			out.append(j)
	return out


func retry(job_id: String) -> void:
	for j in jobs:
		if j.id == job_id:
			j.status = "pending"
			j.attempts = 0
	_save()
	process_next()


func process_next() -> void:
	if not _active.is_empty():
		return
	for j in jobs:
		if j.status != "pending":
			continue
		var c: Connector = connectors.get(j.connector)
		if c == null or not c.is_configured():
			continue
		if int(j.attempts) >= MAX_ATTEMPTS:
			j.status = "failed"
			continue
		_active = j
		j.status = "uploading"
		j.attempts = int(j.attempts) + 1
		changed.emit()
		c.upload_fit(j.fit_path, j.name, j.description)
		return


func _on_upload_finished(ok: bool, message: String, remote_id: String) -> void:
	if _active.is_empty():
		return
	var j := _active
	_active = {}
	if ok:
		j.status = "done"
		j.remote_id = remote_id
		j.last_error = ""
	else:
		j.status = "pending" if int(j.attempts) < MAX_ATTEMPTS else "failed"
		j.last_error = message
	_save()
	changed.emit()
	job_finished.emit(j, ok, message)
	# Do not hammer a failing service: only continue on success.
	if ok:
		process_next()


func _load() -> void:
	var cfg := ConfigFile.new()
	if cfg.load(QUEUE_PATH) != OK:
		return
	for section in cfg.get_sections():
		var j := {"id": section}
		for k in ["connector", "fit_path", "name", "description", "status", "last_error", "remote_id"]:
			j[k] = str(cfg.get_value(section, k, ""))
		j["attempts"] = int(cfg.get_value(section, "attempts", 0))
		if j.status == "uploading":
			j.status = "pending"
		jobs.append(j)


func _save() -> void:
	var cfg := ConfigFile.new()
	for j in jobs:
		for k in j:
			if k != "id":
				cfg.set_value(j.id, k, j[k])
	cfg.save(QUEUE_PATH)
