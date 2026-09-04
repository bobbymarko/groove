# Groove — design system

Working name: **Groove**. Source: Bob's "Groove UI System" board (design/reference/ui-inspo.png, 2026-09-03). Inspiration, not a component spec: we take the tokens, the tone and the shapes and keep our own layouts. The board's pixel font does not exist; we keep Lato until we find or draw a bitmap face. Code lives in `ui/hud/hud_style.gd` (tokens, controls) and `ui/hud/workout_colors.gd` (effort colours); change them there, not per screen.

## Tone
Night-sky navy over ink, one cyan for anything interactive, orange only for "active / focus", the workout zone ramp for effort. Dark, quiet panels with a hairline border; big numbers, small uppercase labels. Pixel-art world behind, crisp vector UI in front.

## Colour tokens
| Token | Hex | Use |
|---|---|---|
| Ink 950 | `#000c18` | page background, text on cyan |
| Navy 900 | `#012041` | header bands, sheet background |
| Ice 100 | `#f4f5f5` | text, icons |
| Cyan 400 | `#00b7f5` | primary buttons, selected tab, links, section labels, focus |
| Teal 400 | `#01b5cc` | endurance zone, secondary accents |
| Yellow 400 | `#feb801` | tempo zone, power icon |
| Orange 500 | `#ef6a01` | active state, current block, warnings |
| Red 500 | `#dc352d` | VO2 zone, heart rate, errors |
| Green (check) | `#3ccf6a` | connected / success |
| Panel | `#020e1f` @ 82 % | panel fill |
| Row | `#0b2a52` @ 75 % | list rows, buttons at rest |
| Border | `#6585a8` @ 35 % | 1 px hairline on every panel and input |

Derived: dim text is Ice at 60 %; disabled anything is 40 % opacity.

## Workout zones (the one effort palette)
| Zone | % FTP | Colour |
|---|---|---|
| Recovery | < 55 | `#174c8b` |
| Endurance | 55–75 | Teal 400 |
| Tempo / sweet spot | 76–89 | Yellow 400 |
| Threshold | 90–104 | Orange 500 |
| VO2 and above | ≥ 105 | Red 500 |
| Free ride | — | `#6b7a8c` |

Used by the plan graph, the ride trace, the block rows in the HUD and sheets, and the workout cards.

## The groove (timeline views)
The workout is not a row of blocks but one continuous path: height is target power, colour is the zone, steps between blocks are drawn as risers so the line never breaks. Under it a faint fill in the same colour. While riding, a white glowing marker (soft halo, hard centre) sits on the path at the current time; the path behind the marker brightens, the path ahead sits at 55 %. The rider's actual power runs as a 1.5 px ice line and heart rate as a 1.5 px red line, so "following the groove" is literal. Cards and sheets show the same path without the marker.

## Type (Lato for now)
| Role | Size | Weight | Case |
|---|---|---|---|
| Display | 48 | 900 | as written |
| Metric | 36–96 | 900 | digits |
| Title | 20–24 | 900 | as written (workout names) |
| Section label | 12 | 700 | UPPERCASE, Cyan |
| Body | 14–15 | 500 | as written |
| Label / unit | 12–13 | 700 | lowercase units, uppercase for HUD units |
| Buttons | 13–18 | 700 | UPPERCASE |

## Shapes
- Corner radius 4 everywhere (6 on big buttons). Hairline border on panels, cards, inputs.
- Panel states: default (border), focus (cyan border), active (orange text or outline, no side bars), disabled (40 %).
- Buttons: **primary** cyan fill + ink text; **secondary** cyan outline + cyan text; **ghost** row-colour fill + ice text (HUD and toolbars); disabled 40 %.
- Segmented control: ink track, selected segment cyan with ink text.
- Cards: image on top, title in Cyan, one line of dim body text, chevron on the right when it opens something; highlighted = cyan border. Today's planned ride gets an orange day subhead, not a bar on the card (Bob, 2026-09-04).
- Live metrics: icon (coloured by metric: power yellow, cadence cyan, heart red, speed/grade teal) + big number + small unit.
- Nav tabs: uppercase text, selected in cyan with a 3 px underline.

## Icons
Vector, 24-unit grid, single colour (tinted at runtime), in `assets/icons/*.svg`: play, pause, gear, bluetooth, heart, signal, camera, sound, lock, check, warning, trash, bolt, bike, gauge, chevron-left/right, close, mountain, history, home, share, flag, pizza.

## Backgrounds
Home uses `assets/images/menu-bg.png` (pixel night mountains) under a 45 % ink wash so cards stay legible. The ride HUD floats over the live world; panels stay translucent.

## Not yet
Bitmap font; motion language for panel transitions beyond the sheet slide; sound.
