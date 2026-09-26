class_name MonsterPresets
extends RefCounted
## Starter riders, built from the same parts. The editor starts from one.

const SIZE_DEFAULTS := {
	"girth": 1.0, "height": 1.0, "head": 1.0, "eye": 1.0, "horn": 1.0,
	"arm": 0.62, "leg": 0.66, "limb": 0.055, "hand": 1.0, "foot": 1.0,
}

const FUZZ := {
	"name": "Fuzz", "body": "round", "fur": true, "head": "", "eyes": "cyclops", "mouth": "teeth",
	"extras": ["horns", "cap_back"], "hands": "mitt", "feet": "shoe",
	"size": {"girth": 1.05, "height": 1.0, "horn": 1.7, "arm": 0.60, "leg": 0.62, "limb": 0.07, "hand": 1.1},
	"colours": {"primary": Color("7443c4"), "secondary": Color("9a70e0"), "limb": Color("6a3bb8"),
		"cap": Color("d93a2e"), "cloth": Color("f2e8d8"), "accent": Color("feb801"), "dark": Color("2a2b31")},
	"bike": {"frame": Color("ef6a01"), "accent": Color("f4f5f5")},
}

const BOT := {
	"name": "Bot", "body": "square", "fur": false, "head": "screen", "eyes": "screen", "mouth": "grill",
	"extras": ["antenna", "backpack"], "hands": "claw", "feet": "shoe",
	"size": {"girth": 0.95, "height": 1.05, "head": 1.0, "arm": 0.66, "leg": 0.74, "limb": 0.035, "hand": 0.95},
	"colours": {"primary": Color("8795a6"), "secondary": Color("4d5968"), "accent": Color("ef6a01"),
		"limb": Color("3c424c"), "cloth": Color("2f5f3a"), "horn": Color("3c424c"), "dark": Color("30343c"),
		"glow": Color("35f2ff")},
	"bike": {"frame": Color("3e8f4b"), "accent": Color("feb801")},
}

const SPIKE := {
	"name": "Spike", "body": "bean", "fur": false, "head": "", "eyes": "squint", "mouth": "teeth",
	"extras": ["spikes"], "hands": "claw", "feet": "shoe",
	"size": {"girth": 1.0, "height": 1.05, "eye": 1.1, "arm": 0.58, "leg": 0.64, "limb": 0.06},
	"colours": {"primary": Color("d6442f"), "secondary": Color("8a1f1c"), "limb": Color("c23b2a"),
		"cloth": Color("1d2f5a"), "accent": Color("feb801"), "dark": Color("1e1f24"), "horn": Color("f0e2c4")},
	"bike": {"frame": Color("01b5cc"), "accent": Color("ef6a01")},
}

const SKULLY := {
	"name": "Skully", "body": "bean", "fur": false, "head": "skull", "eyes": "", "mouth": "",
	"extras": ["cap_back", "backpack"], "hands": "mitt", "feet": "shoe",
	"size": {"girth": 1.0, "height": 0.9, "head": 1.1, "arm": 0.64, "leg": 0.70, "limb": 0.05},
	"colours": {"primary": Color("2b2e36"), "secondary": Color("20232a"), "limb": Color("2b2e36"),
		"cap": Color("feb801"), "cloth": Color("7a4a2a"), "accent": Color("dc352d"), "dark": Color("121316"),
		"teeth": Color("ece3cc")},
	"bike": {"frame": Color("dc352d"), "accent": Color("1b1b1d")},
}

static func all() -> Array[Dictionary]:
	return [FUZZ, BOT, SPIKE, SKULLY]
