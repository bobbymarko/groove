# Scenery textures

Photo-scanned PBR texture sets for the Realistic look (spec R43), all **CC0 1.0** (public domain), from
[Poly Haven](https://polyhaven.com) and [ambientCG](https://ambientcg.com). Fetched at 1K by
`tools/fetch-textures.sh` (raw downloads are cached in the git-ignored `build/textures/`; re-run is a no-op when the files exist, `--force` redoes the conversion).

Each slot folder holds:

| file | content |
|---|---|
| `albedo.jpg` | sRGB colour |
| `normal.jpg` | tangent-space normal, **OpenGL (Y+)** convention, as Godot expects (import as Normal Map) |
| `arm.jpg` | R = ambient occlusion, G = roughness, B = metallic (0 everywhere; none of these is metal). Import as linear data, not sRGB. Snow001 and Bark001 ship no AO map, so R is 255 there |
| `height.jpg` | displacement, one 8-bit channel, 512 px on the long side (for height blending and parallax) |

Albedo, normal and ARM are 1024 px (Bark001 is 512 x 1024: tile it at 1 : 2). The `.import` files beside them are committed: they carry each picture's import settings (mipmaps, compression). Godot writes them; change a setting in the editor's Import dock rather than by hand. The tile sizes the shaders use are in `scene/real/surface_tex.gd` (the trail gravel is drawn finer than its scanned size, 1.25 m, so it reads as a ridden gravel path).

## Slots

Tile size is the real-world width of one repeat in metres. Poly Haven states it (its asset page "dimensions"). ambientCG does not, so those values are **estimates** from the grain of the picture; check them against the scene.

| slot | asset | source | author | tile (m) | what it looks like |
|---|---|---|---|---|---|
| `trail_gravel` | Rocky Trail | [polyhaven.com/a/rocky_trail](https://polyhaven.com/a/rocky_trail) | Amal Kumar | 2.0 | Packed brown-grey earth with fine gravel and scattered pebbles; the main trail surface. |
| `trail_mud` | Forest Ground 06 | [polyhaven.com/a/forest_ground_06](https://polyhaven.com/a/forest_ground_06) | Charlotte Baglioni | 2.11 | Dark brown compact damp soil with tiny stones and a few leaf bits; fairly even, little to repeat. |
| `forest_floor` | Forest Leaves 04 | [polyhaven.com/a/forest_leaves_04](https://polyhaven.com/a/forest_leaves_04) | Rob Tuytel | 1.5 | Dry needles, twigs and duff in orange-brown; a couple of darker clumps are the only repeat risk. |
| `grass_ground` | Grass Ground | [polyhaven.com/a/grass_ground](https://polyhaven.com/a/grass_ground) | Charlotte Baglioni | 2.51 | Short muted turf, green and brown, roots showing; sits under 3D blades. |
| `rock_cliff` | Rock 032 | [ambientcg.com/a/Rock032](https://ambientcg.com/a/Rock032) | ambientCG | about 2 (estimate) | Dark neutral grey rock with soft cracks and a little weathering; no strong light baked in. |
| `rock_mossy` | Rock 011 | [ambientcg.com/a/Rock011](https://ambientcg.com/a/Rock011) | ambientCG | about 2 (estimate) | Dark grey-green rock face under moss and lichen, folded strata. |
| `snow` | Snow 001 | [ambientcg.com/a/Snow001](https://ambientcg.com/a/Snow001) | ambientCG | about 2 (estimate) | Soft fresh snow, near white with faint blue shading and gentle lumps. Fine grain is weak; rely on the normal map. |
| `snow_trail` | Snow 013 | [ambientcg.com/a/Snow013](https://ambientcg.com/a/Snow013) | ambientCG | about 2 (estimate) | Compacted, tracked snow: blue-grey with fine scuffs and footprint streaks, running vertically (rotate to follow the trail). |
| `sand` | Dense Sand | [polyhaven.com/a/dense_sand](https://polyhaven.com/a/dense_sand) | Dimitrios Savva | 1.8 | Dry cream-tan compact sand with soft mottling. |
| `desert_gravel` | Gravelly Sand | [polyhaven.com/a/gravelly_sand](https://polyhaven.com/a/gravelly_sand) | Dario Barresi | 2.48 | Tan to ochre coarse sand with small stones and fine debris; warm, a little less rust than a Sonoran wash. |
| `bark_pine` | Bark 004 | [ambientcg.com/a/Bark004](https://ambientcg.com/a/Bark004) | ambientCG | about 0.8 (estimate) | Scots-pine style bark: grey-brown fissures between pinkish-tan plates, running vertically. |
| `bark_oak` | Bark 001 | [ambientcg.com/a/Bark001](https://ambientcg.com/a/Bark001) | ambientCG | about 0.5 wide by 1 tall (estimate) | Deeply furrowed grey broadleaf bark, vertical ridges. The image is 1 : 2. |
| `bark_birch` | Bark 007 | [ambientcg.com/a/Bark007](https://ambientcg.com/a/Bark007) | ambientCG | about 0.5 (estimate) | Pale grey-cream bark with fine cracks and a green-yellow cast. **Not a true birch**: no white paper bark or dark lenticels; brighten it and paint marks in the shader. |
| `wood_planks` | Weathered Brown Planks | [polyhaven.com/a/weathered_brown_planks](https://polyhaven.com/a/weathered_brown_planks) | Dimitrios Savva (photography), Rico Cilliers (processing) | 1.8 | Grey-brown weathered boards, with the planks running left to right; rotate 90 degrees for a deck that runs along the bridge. |

Poly Haven and ambientCG list every asset as CC0 on its page; both sites publish all their assets under CC0. Credit is not required, and is given in `LICENSES.md` anyway.
