class_name ScenePreset
extends RefCounted
## The selectable looks for the world. Each preset recolours the Palette,
## picks which Quaternius props to scatter, and says whether it snows.
## Winter is the reference look; the others reuse the same trail, terrain and
## mountains with different colours, trees and ground cover.

const ORDER := ["winter", "summer", "autumn", "spring"]

const PRESETS := {
	"winter": {
		"name": "Winter", "description": "Groomed fat-bike trail through snowy pines",
		"colors": {},   # the Palette defaults
		"trees": ["Pine_1", "Pine_2", "Pine_3", "Pine_4", "Pine_5"],
		"dead": ["DeadTree_1", "DeadTree_2", "DeadTree_3", "DeadTree_4", "DeadTree_5"],
		"rocks": ["Rock_Medium_1", "Rock_Medium_2", "Rock_Medium_3"],
		"cover": [],
		"snow": true, "prop_snow": true, "sun_lift": 0.0, "dead_share": 0.04,
	},
	"summer": {
		"name": "Summer", "description": "Dusty singletrack under leafy trees",
		"colors": {
			"SKY_TOP": "4f8fd9", "SKY_MID": "8fb8e6", "SKY_LOW": "c9def0", "SKY_HORIZON": "e6eef5", "FOG": "d3e0ea",
			"SNOW": "7fb04f", "SNOW_MID": "6e9f43", "SNOW_SHADE": "5c8b3a", "SNOW_SHADOW": "56765e", "SNOW_BRIGHT": "9cc466",
			"TRAIL": "a08256", "TRAIL_DARK": "7f6443", "ROCK": "8b8f97", "ROCK_DARK": "5d6168",
			"MOUNTAIN_FAR": "c5d3df", "MOUNTAIN_FAR2": "aebfd0", "MOUNTAIN_MID": "8fa6ba", "MOUNTAIN_MID2": "7590a5", "MOUNTAIN_NEAR": "5b7a86",
			"MOUNTAIN_SNOW": "eef2f6",
			"PINE": "4d8f3c", "PINE_LIGHT": "9ccd5a", "PINE_DARK": "2c5a25", "TRUNK": "5a4634", "BRANCH": "6f5741", "BERRY": "d04a4a",
			"FLOWER": "e8e070", "FLOWER_DARK": "b08a30",
		},
		"trees": ["CommonTree_1", "CommonTree_2", "CommonTree_3", "CommonTree_4", "CommonTree_5", "Pine_2", "Pine_4"],
		"dead": [],
		"rocks": ["Rock_Medium_1", "Rock_Medium_2", "Rock_Medium_3"],
		"cover": ["Grass_Common_Tall", "Grass_Wispy_Tall", "Bush_Common", "Bush_Common_Flowers"],
		"snow": false, "prop_snow": false, "sun_lift": 28.0, "dead_share": 0.0,
	},
	"autumn": {
		"name": "Autumn", "description": "Amber woods, cool air, soft late light",
		"colors": {
			"SKY_TOP": "6f9ad4", "SKY_MID": "a9bfe0", "SKY_LOW": "e0cdbc", "SKY_HORIZON": "f3dfc8", "FOG": "e5d4c2",
			"SNOW": "b39a4c", "SNOW_MID": "a08a42", "SNOW_SHADE": "8a7638", "SNOW_SHADOW": "6a5a3c", "SNOW_BRIGHT": "c8b060",
			"TRAIL": "7d5c3c", "TRAIL_DARK": "5f4530", "ROCK": "8e8478", "ROCK_DARK": "5f574d",
			"MOUNTAIN_FAR": "d9c8c8", "MOUNTAIN_FAR2": "c4aeb4", "MOUNTAIN_MID": "a9909d", "MOUNTAIN_MID2": "8c7a8c", "MOUNTAIN_NEAR": "6f6a7e",
			"MOUNTAIN_SNOW": "f1ebe6",
			"PINE": "c2652a", "PINE_LIGHT": "eaa83c", "PINE_DARK": "7a3a18", "TRUNK": "4f3a2e", "BRANCH": "654a3a", "BERRY": "b8302e",
			"FLOWER": "d9a441", "FLOWER_DARK": "8a5a20",
		},
		"trees": ["CommonTree_1", "CommonTree_2", "CommonTree_3", "CommonTree_4", "CommonTree_5", "TwistedTree_1", "TwistedTree_2", "TwistedTree_3"],
		"dead": ["DeadTree_1", "DeadTree_2", "DeadTree_3"],
		"rocks": ["Rock_Medium_1", "Rock_Medium_2", "Rock_Medium_3"],
		"cover": ["Mushroom_Common", "Bush_Common", "Grass_Wispy_Tall"],
		"snow": false, "prop_snow": false, "sun_lift": 14.0, "dead_share": 0.06,
	},
	"spring": {
		"name": "Spring", "description": "Fresh green meadows and wildflowers",
		"colors": {
			"SKY_TOP": "6aa6e6", "SKY_MID": "a4c8ef", "SKY_LOW": "d8e6f4", "SKY_HORIZON": "eef4f8", "FOG": "dde8ef",
			"SNOW": "8cc45c", "SNOW_MID": "7ab24e", "SNOW_SHADE": "669c42", "SNOW_SHADOW": "4f7f4a", "SNOW_BRIGHT": "a8d86c",
			"TRAIL": "8f7a58", "TRAIL_DARK": "705e45", "ROCK": "8d929a", "ROCK_DARK": "60656d",
			"MOUNTAIN_FAR": "d6d5e6", "MOUNTAIN_FAR2": "bfc0da", "MOUNTAIN_MID": "9fa8c8", "MOUNTAIN_MID2": "8290b4", "MOUNTAIN_NEAR": "667c98",
			"MOUNTAIN_SNOW": "f6f6fa",
			"PINE": "5ea64a", "PINE_LIGHT": "b5e078", "PINE_DARK": "35702c", "TRUNK": "5a4634", "BRANCH": "6f5741", "BERRY": "e86aa0",
			"FLOWER": "f2a6c8", "FLOWER_DARK": "b0407a",
		},
		"trees": ["CommonTree_1", "CommonTree_2", "CommonTree_3", "CommonTree_4", "CommonTree_5", "Pine_1", "Pine_3"],
		"dead": [],
		"rocks": ["Rock_Medium_1", "Rock_Medium_2", "Rock_Medium_3"],
		"cover": ["Flower_3_Group", "Flower_4_Group", "Grass_Common_Tall", "Bush_Common_Flowers"],
		"snow": false, "prop_snow": false, "sun_lift": 22.0, "dead_share": 0.0,
	},
}


static func get_preset(id: String) -> Dictionary:
	return PRESETS.get(id, PRESETS["winter"])


static func thumbnail_path(id: String) -> String:
	return "res://assets/images/scenes/%s.png" % id
