extends Node
## Autoload "Updates". Knows the running version, asks GitHub for the latest
## release (at most once a day), and on macOS can download it, verify it,
## swap the app bundle and relaunch (R36). Windows gets the release page.

signal checked(available: bool, message: String)
signal progress(step: String, fraction: float)   ## fraction < 0: indeterminate
signal failed(message: String)

const REPO := "bobbymarko/groove"
const API_URL := "https://api.github.com/repos/%s/releases/latest"
const CACHE_PATH := "user://updates.cfg"
const UPDATES_DIR := "user://updates"
const CHECK_EVERY := 24 * 3600
const PREVIOUS_BUNDLE := "Groove.previous.app"

var current_version := ""
var latest: Dictionary = {}     ## {version, url, notes, asset_name, asset_url, asset_size, sha256}
var last_check := 0
var last_error := ""

var _http: HTTPRequest
var _download: HTTPRequest
var _checking := false
var _installing := false
var _zip_path := ""


func _ready() -> void:
	current_version = str(ProjectSettings.get_setting("application/config/version", ""))
	for arg in OS.get_cmdline_user_args():
		if arg.begins_with("version="):
			current_version = arg.trim_prefix("version=")   # dev: pretend to be older
	_load_cache()
	if DisplayServer.get_name() == "headless":
		return
	_http = HTTPRequest.new()
	_http.timeout = 20.0
	_http.request_completed.connect(_on_check_completed)
	add_child(_http)
	_download = HTTPRequest.new()
	_download.timeout = 600.0
	_download.use_threads = true
	_download.request_completed.connect(_on_download_completed)
	add_child(_download)
	_cleanup_previous()
	# Dev: `-- update=install` runs the whole update unattended once the check says one exists.
	if OS.get_cmdline_user_args().has("update=install"):
		checked.connect(func(available: bool, msg: String) -> void:
			print("[updates] check: %s (%s)" % [msg, "installing" if available else "nothing to do"])
			if available:
				install(), CONNECT_ONE_SHOT)
		var last := [""]
		progress.connect(func(step: String, f: float) -> void:
			var line := "%s %s" % [step, ("%d%%" % (int(f * 100.0) / 10 * 10)) if f >= 0.0 else ""]
			if line != last[0]:
				last[0] = line
				print("[updates] ", line))
		failed.connect(func(m: String) -> void: print("[updates] FAILED: ", m))
	check.call_deferred()


func _process(_delta: float) -> void:
	if _installing and _download.get_http_client_status() != HTTPClient.STATUS_DISCONNECTED:
		var total := maxi(_download.get_body_size(), int(latest.get("asset_size", 0)))
		if total > 0:
			progress.emit("Downloading", float(_download.get_downloaded_bytes()) / float(total))


# --- checking -------------------------------------------------------------------

func update_available() -> bool:
	return not latest.is_empty() and compare_versions(str(latest.version), current_version) > 0


## Ask GitHub, unless a fresh answer is cached. `force` skips the cache.
func check(force := false) -> void:
	if _http == null or _checking:
		return
	if not force and latest.size() > 0 and Time.get_unix_time_from_system() - last_check < CHECK_EVERY:
		checked.emit(update_available(), _status_text())
		return
	_checking = true
	var headers := PackedStringArray(["Accept: application/vnd.github+json", "User-Agent: Groove/" + current_version])
	var err := _http.request(API_URL % REPO, headers)
	if err != OK:
		_checking = false
		last_error = "request failed: %s" % error_string(err)
		checked.emit(false, "Could not check for updates")


func _on_check_completed(result: int, code: int, _headers: PackedStringArray, body: PackedByteArray) -> void:
	_checking = false
	if result != HTTPRequest.RESULT_SUCCESS or code != 200:
		last_error = "GitHub answered %d (%d)" % [code, result]
		checked.emit(update_available(), "Could not check for updates")
		return
	var json: Variant = JSON.parse_string(body.get_string_from_utf8())
	if not (json is Dictionary):
		last_error = "unexpected answer"
		checked.emit(update_available(), "Could not check for updates")
		return
	latest = parse_release(json, OS.get_name())
	last_check = int(Time.get_unix_time_from_system())
	last_error = ""
	_save_cache()
	checked.emit(update_available(), _status_text())


func _status_text() -> String:
	if latest.is_empty():
		return "Could not check for updates"
	return ("Groove %s is available" % latest.version) if update_available() else "Up to date"


## The parts of a GitHub release the app needs, with the asset for `platform`
## ("macOS", "Windows", ...). Sha256 comes from GitHub's asset digest.
static func parse_release(json: Dictionary, platform: String) -> Dictionary:
	var out := {
		"version": str(json.get("tag_name", "")).trim_prefix("v"),
		"url": str(json.get("html_url", "")),
		"notes": notes_to_text(str(json.get("body", ""))),
		"asset_name": "", "asset_url": "", "asset_size": 0, "sha256": "",
	}
	var want := "macos" if platform == "macOS" else ("windows" if platform == "Windows" else "linux")
	for a in json.get("assets", []):
		if not (a is Dictionary):
			continue
		var name := str(a.get("name", ""))
		if name.to_lower().contains(want) and name.ends_with(".zip"):
			out.asset_name = name
			out.asset_url = str(a.get("browser_download_url", ""))
			out.asset_size = int(a.get("size", 0))
			var digest := str(a.get("digest", ""))
			if digest.begins_with("sha256:"):
				out.sha256 = digest.trim_prefix("sha256:").to_lower()
			break
	return out


## Release notes are Markdown; the sheet shows plain text.
static func notes_to_text(md: String) -> String:
	var out := md.replace("\r\n", "\n").replace("**", "").replace("`", "")
	var lines: Array[String] = []
	for line in out.split("\n"):
		var l := line.strip_edges()
		if l.begins_with("#"):
			l = l.lstrip("#").strip_edges()
		lines.append(l)
	return "\n".join(lines).strip_edges()


## -1, 0 or 1 comparing dotted versions numerically ("0.0.10" > "0.0.9").
static func compare_versions(a: String, b: String) -> int:
	var pa := a.trim_prefix("v").split(".")
	var pb := b.trim_prefix("v").split(".")
	for i in maxi(pa.size(), pb.size()):
		var x := int(pa[i]) if i < pa.size() else 0
		var y := int(pb[i]) if i < pb.size() else 0
		if x != y:
			return 1 if x > y else -1
	return 0


# --- installing (macOS) -----------------------------------------------------------

## Path of the running .app bundle, or "" when not running from one.
func bundle_path() -> String:
	if OS.get_name() != "macOS":
		return ""
	var exe := OS.get_executable_path()          # .../Groove.app/Contents/MacOS/Groove
	var bundle := exe.get_base_dir().get_base_dir().get_base_dir()
	return bundle if bundle.ends_with(".app") else ""


## Why an in-app install is not possible, or "" when it is.
func install_blocker() -> String:
	if OS.get_name() != "macOS":
		return "In-app updates are macOS only for now"
	if latest.is_empty() or str(latest.asset_url) == "":
		return "No macOS download in this release"
	var bundle := bundle_path()
	if bundle.get_file() != "Groove.app":
		return "Development build: install the release by hand"
	if bundle.contains("/AppTranslocation/"):
		return "Move Groove to Applications first, then update"
	var probe := bundle.get_base_dir().path_join(".groove-write-test")
	var f := FileAccess.open(probe, FileAccess.WRITE)
	if f == null:
		return "No permission to replace %s" % bundle
	f.close()
	DirAccess.remove_absolute(probe)
	return ""


func can_install() -> bool:
	return install_blocker() == ""


## Download, verify, unpack, swap the bundle, relaunch. Progress and failure
## arrive as signals; success ends in the app quitting.
func install() -> void:
	if _installing or not can_install():
		failed.emit(install_blocker() if not can_install() else "Already updating")
		return
	_installing = true
	DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path(UPDATES_DIR))
	_zip_path = UPDATES_DIR.path_join(str(latest.asset_name))
	DirAccess.remove_absolute(_zip_path)
	_download.download_file = _zip_path
	progress.emit("Downloading", 0.0)
	var err := _download.request(str(latest.asset_url), PackedStringArray(["User-Agent: Groove/" + current_version]))
	if err != OK:
		_fail("Download could not start: %s" % error_string(err))


func _on_download_completed(result: int, code: int, _headers: PackedStringArray, _body: PackedByteArray) -> void:
	if not _installing:
		return
	if result != HTTPRequest.RESULT_SUCCESS or code != 200:
		_fail("Download failed (%d, HTTP %d)" % [result, code])
		return
	progress.emit("Verifying", -1.0)
	await get_tree().process_frame
	var zip_abs := ProjectSettings.globalize_path(_zip_path)
	var want := str(latest.sha256)
	if want == "":
		_fail("GitHub gave no checksum for the download")
		return
	if FileAccess.get_sha256(zip_abs) != want:
		_fail("The download did not match its checksum")
		return
	progress.emit("Unpacking", -1.0)
	await get_tree().process_frame
	var unpack_abs := ProjectSettings.globalize_path(UPDATES_DIR.path_join("unpacked"))
	OS.execute("/bin/rm", ["-rf", unpack_abs])
	DirAccess.make_dir_recursive_absolute(unpack_abs)
	var out := []
	if OS.execute("/usr/bin/ditto", ["-x", "-k", zip_abs, unpack_abs], out, true) != 0:
		_fail("Could not unpack the download: %s" % "".join(out).strip_edges().left(200))
		return
	var fresh := unpack_abs.path_join("Groove.app")
	if not FileAccess.file_exists(fresh.path_join("Contents/MacOS/Groove")):
		_fail("The download did not contain Groove.app")
		return
	progress.emit("Installing", -1.0)
	await get_tree().process_frame
	var bundle := bundle_path()
	var previous := bundle.get_base_dir().path_join(PREVIOUS_BUNDLE)
	OS.execute("/bin/rm", ["-rf", previous])
	if OS.execute("/bin/mv", [bundle, previous]) != 0:
		_fail("Could not move the current Groove aside")
		return
	if OS.execute("/bin/mv", [fresh, bundle]) != 0:
		OS.execute("/bin/mv", [previous, bundle])   # put the old one back
		_fail("Could not move the new Groove into place")
		return
	DirAccess.remove_absolute(_zip_path)
	progress.emit("Restarting", -1.0)
	await get_tree().create_timer(0.6).timeout
	OS.create_process("/usr/bin/open", ["-n", bundle])
	get_tree().quit()


func _fail(message: String) -> void:
	_installing = false
	last_error = message
	failed.emit(message)


## After a successful update the old bundle sits beside us; remove it once we
## are running, and clear the download folder.
func _cleanup_previous() -> void:
	var bundle := bundle_path()
	if bundle.get_file() == "Groove.app":
		var previous := bundle.get_base_dir().path_join(PREVIOUS_BUNDLE)
		if DirAccess.dir_exists_absolute(previous):
			OS.execute("/bin/rm", ["-rf", previous])
	var unpacked := ProjectSettings.globalize_path(UPDATES_DIR.path_join("unpacked"))
	if DirAccess.dir_exists_absolute(unpacked):
		OS.execute("/bin/rm", ["-rf", unpacked])


# --- cache ------------------------------------------------------------------------

func _load_cache() -> void:
	var cfg := ConfigFile.new()
	if cfg.load(CACHE_PATH) != OK:
		return
	last_check = int(cfg.get_value("updates", "last_check", 0))
	var parsed: Variant = JSON.parse_string(str(cfg.get_value("updates", "latest", "")))
	if parsed is Dictionary:
		latest = parsed


func _save_cache() -> void:
	var cfg := ConfigFile.new()
	cfg.set_value("updates", "last_check", last_check)
	cfg.set_value("updates", "latest", JSON.stringify(latest))
	cfg.save(CACHE_PATH)
