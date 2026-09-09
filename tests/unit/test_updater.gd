extends TestCase

const Updater := preload("res://core/update/updater.gd")


func test_compare_versions_numerically() -> void:
	assert_eq(Updater.compare_versions("0.0.10", "0.0.9"), 1)
	assert_eq(Updater.compare_versions("v0.0.2", "0.0.2"), 0)
	assert_eq(Updater.compare_versions("0.1", "0.1.0"), 0)
	assert_eq(Updater.compare_versions("0.0.2", "1.0"), -1)
	assert_eq(Updater.compare_versions("1.2.3", "1.2"), 1)


func test_parse_release_picks_platform_asset_and_digest() -> void:
	var json := {
		"tag_name": "v0.0.3", "html_url": "https://github.com/bobbymarko/groove/releases/tag/v0.0.3",
		"body": "**Bold** and `code`\r\n\r\n## Install\r\n- step",
		"assets": [
			{"name": "Groove-0.0.3-windows-x86_64.zip", "browser_download_url": "https://x/win.zip", "size": 5, "digest": "sha256:ABC"},
			{"name": "Groove-0.0.3-macos.zip", "browser_download_url": "https://x/mac.zip", "size": 7, "digest": "sha256:def"},
		],
	}
	var mac := Updater.parse_release(json, "macOS")
	assert_eq(mac.version, "0.0.3")
	assert_eq(mac.asset_name, "Groove-0.0.3-macos.zip")
	assert_eq(mac.asset_url, "https://x/mac.zip")
	assert_eq(mac.asset_size, 7)
	assert_eq(mac.sha256, "def")
	assert_eq(mac.notes, "Bold and code\n\nInstall\n- step")
	var win := Updater.parse_release(json, "Windows")
	assert_eq(win.asset_name, "Groove-0.0.3-windows-x86_64.zip")
	assert_eq(win.sha256, "abc")
	var linux := Updater.parse_release(json, "Linux")
	assert_eq(linux.asset_url, "")


func test_parse_release_without_digest_leaves_sha_empty() -> void:
	var json := {"tag_name": "v9", "assets": [{"name": "Groove-9-macos.zip", "browser_download_url": "u", "size": 1}]}
	assert_eq(Updater.parse_release(json, "macOS").sha256, "")
	assert_eq(Updater.parse_release(json, "macOS").version, "9")
