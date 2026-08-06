# Who's That Trainer?
Ever wanted to play Pokémon as yourself or Giovanni, Pikachu, or face Red as the rival? Now you can!

**Who's That Trainer?** lets you swap between 17 iconic Gen 1 characters — complete with overworld sprites, battle sprites, and trainer portraits. Choose your character, rival, and follower independently from the start menu. You can also add unlimited custom characters by dropping your own sprites into a folder.

## ✨ Features

- **17 Built-in Characters:** RED, GIOVANNI, PIKACHU, BROCK, MISTY, LT. SURGE, ERIKA, KOGA, SABRINA, BLAINE, LORELEI, BRUNO, AGATHA, LANCE, BLUE, OAK, JESSIE, and JAMES
- **Unlimited Custom Characters:** Drop your own sprites into `custom_characters/` — no Lua editing required
- **Independent Selection:** Pick your player character, follower, and rival separately
- **Full Sprite Support:** Overworld walking sprites, bike sprites, battle back sprites, and trainer card portraits
- **Runtime Transforms:** All built-in sprites generated from your ROM cache — no copyrighted artwork shipped
- **Seamless Integration:** Access all three menus from the start menu (CHARACTER, RIVAL, FOLLOWER)

## 🎮 How to Use

1. **Enable the mod** via the in-game mod manager (F10) or edit `options.lua`
2. **Open the start menu** during gameplay
3. Select **CHARACTER** to change your player sprite
4. Select **RIVAL** to change your rival's appearance
5. Select **FOLLOWER** to change your follower appearance
6. Changes apply immediately — no restart needed!

## 🎨 Custom Characters

You can add your own characters to the mod without editing any Lua files. Just create a subfolder with your sprites and an optional config file.

### Step by step

**1. Create the character subfolder**

Inside the game's data directory (see table below), create:

```
custom_characters/<name>/
```

| Platform | Location of `custom_characters/` |
|---|---|
| Windows | `%APPDATA%\LOVE\pokemon-love2d\mods\whos_that_trainer\custom_characters\` |
| macOS | `~/Library/Application Support/LOVE/pokemon-love2d/mods/whos_that_trainer/custom_characters/` |
| Linux | `~/.local/share/love/pokemon-love2d/mods/whos_that_trainer/custom_characters/` |
| Android | External storage: `Android/data/org.love2d.android/files/mods/whos_that_trainer/custom_characters/` |

The subfolder name (lowercase) becomes the character's internal ID. For example, the folder `ash` produces the ID `CUSTOM_ASH`.

**2. Add your sprites** *(all optional — any missing sprites will use vanilla RED as fallback)*

| File | Size | Description |
|---|---|---|
| `walk.png` | **16 × 96 px** | Walking sprite sheet — 6 frames of 16 × 16 stacked vertically (stand down/up/left, walk down/up/left). Right-facing frames are mirrored automatically. Gen 2 overworld sprites must be scaled down manually to fit. If omitted, the game uses the vanilla RED overworld sprite. |
| `front.png` | **56 × 56 px** | Front-facing sprite — used on the trainer card, intro, and Hall of Fame. Drawn at 1×. Gen 2 trainer fronts fit at native size. If omitted, the game uses the vanilla RED front sprite. |
| `back.png` | **56 × 56 px** | Back-facing sprite — used in battles. Drawn at 2×. Gen 2 back sprites fit at native size. If omitted, the game uses the vanilla RED back sprite. |
| `bike.png` | **16 × 96 px** | Bike sprite sheet — same 6-frame layout as `walk.png`. If absent, the game uses the default RED bike sprite. |
| `fish_front.png` | **16 × 8 px** | Fishing pose tile for facing **down**. If absent, RED's fishing tile is used. |
| `fish_back.png` | **16 × 8 px** | Fishing pose tile for facing **up**. If absent, RED's fishing tile is used. |
| `fish_side.png` | **16 × 8 px** | Fishing pose tile for facing **left/right**. If absent, RED's fishing tile is used. |

**3. Create a `config.json`** *(optional)*
(an example is on mod folder at `custom_characters` folder)
```json
{
  "label": "Ash",
  "starterSpecies": "PIKACHU",
  "mirrorBack": false
}
```

| Field | Type | Required | Default | Description |
|---|---|---|---|---|
| `label` | string | **Yes** | Folder name in uppercase | Name shown in the selection menus |
| `starterSpecies` | string | No | `nil` | Species name of the starter Monster, professor gives on **Yellow** (e.g. `"GEODUDE"`, `"PIKACHU"`). No effect on Red/Blue. |
| `palette` | string | No | `nil` | Borrow the GBC/SGB palette from a built-in character (e.g. `"BROCK"`, `"MISTY"`, `"SPRITE_GIOVANNI"`). Only takes effect in **COLORS = RED++** mode. See palette notes below. |
| `mirrorBack` | boolean | No | `false` | Horizontally flips `back.png` when displayed in battle |
| `trueColor` | boolean | No | `true` | When `true` (the default), your PNG colors are displayed exactly as painted — no recolorization is applied regardless of the COLORS setting. Set to `false` only when you also set `palette`. |
| `battleScale` | number | No | `nil` (uses engine default of 2×) | Scale factor for `back.png` in battle. Valid range: `0.25`–`4.0`. The sprite is always feet-pinned (bottom edge stays at the text box). The engine default for the player back sprite is `2.0`; set to `3.0` for a larger character, `1.0` for native pixel size. Note: very large values may be clipped by the battle canvas edges. |

#### 🎨 Palette options explained

There are two ways to handle color for a custom character:

**True color (default — recommended for most custom characters)**

Leave `palette` unset (or `null`). The game renders your PNG with its original colors in every COLORS mode. This is the simplest option and gives you full control over how your character looks.

```json
{ "label": "Ash" }
```

**Borrow a built-in palette**

Set `palette` to the id of any built-in character (e.g. `"BROCK"`, `"MISTY"`, etc.), or any Pokémon species (e.g. `"BULBASAUR"`, `"PIKACHU"`, etc.). You can use either the ID or the sprite ID (both work):
- Character/Species ID: `"BROCK"` → automatically becomes `"SPRITE_BROCK"`
- Sprite ID: `"SPRITE_BROCK"` → used as-is

The game will then recolorize your sprites using that sprite's palette ramp.

- Only takes effect in **COLORS = RED++** mode. In all other modes (SGB, OG RED, OG BLUE, etc.) the sprite is still rendered through the standard DMG shade pipeline, the same as any other overworld character.
- Your PNG must use the standard 4-shade DMG grayscale ramp (white / light gray / dark gray / black) for the recolorization to look correct.
- There is no way to define a fully custom palette that has never appeared in the game — the palette system only has slots for palettes already present in the ROM data.

**Available palette IDs (Trainers):**

| Character | ID | Character | ID |
|---|---|---|---|
| Red | `RED` | Lorelei | `LORELEI` |
| Giovanni | `GIOVANNI` | Bruno | `BRUNO` |
| Brock | `BROCK` | Agatha | `AGATHA` |
| Misty | `MISTY` | Lance | `LANCE` |
| Lt. Surge | `LT_SURGE` | Blue | `BLUE` |
| Erika | `ERIKA` | Jessie | `JESSIE` |
| Koga | `KOGA` | James | `JAMES` |
| Sabrina | `SABRINA` | Oak | `OAK` |
| Blaine | `BLAINE` | Pikachu | `PIKACHU` |

**Available palette IDs (Pokémon species):**

You can also use any Pokémon species as a palette source. For example:
- `"BULBASAUR"` → uses Bulbasaur's green palette
- `"CHARIZARD"` → uses Charizard's red/orange palette
- `"SQUIRTLE"` → uses Squirtle's cyan/blue palette
- `"PIKACHU"` → uses Pikachu's yellow palette

Or any of the 151 Gen 1 Pokémon species names in uppercase (e.g. `"ARCANINE"`, `"GYARADOS"`, `"ALAKAZAM"`, etc.)

**Example:**

```json
{ "label": "Ash", "palette": "MISTY", "trueColor": false }
```

or using a Pokémon palette:

```json
{ "label": "Yellow Trainer", "palette": "PIKACHU", "trueColor": false }
```

If `config.json` is absent, the mod uses the folder name in uppercase as the `label` and all other fields at their defaults.

**4. Restart the game**

The character appears automatically in the CHARACTER, RIVAL, and FOLLOWER lists — sorted alphabetically alongside the built-in characters. No additional file editing required.

---

### Example folder structures

**Full character with custom sprites:**

```
custom_characters/
└── ash/
    ├── walk.png           ← optional: 16 × 96 px, 6 frames of 16 × 16 stacked vertically
    ├── front.png          ← optional: 56 × 56 px
    ├── back.png           ← optional: 56 × 56 px
    ├── bike.png           ← optional: 16 × 96 px, same layout as walk.png
    ├── fish_front.png     ← optional: 16 × 8 px, fishing pose facing down
    ├── fish_back.png      ← optional: 16 × 8 px, fishing pose facing up
    ├── fish_side.png      ← optional: 16 × 8 px, fishing pose facing left/right
    └── config.json        ← optional; label, starterSpecies (Yellow only), mirrorBack, trueColor, battleScale
```

**Minimal character (config-only, uses vanilla RED sprites):**

```
custom_characters/
└── trainer_red/
    └── config.json        ← Just this file!
```

Inside `config.json`:
```json
{
  "label": "Trainer Red",
  "starterSpecies": "BULBASAUR"
}
```

This creates a playable character named "Trainer Red" with vanilla RED sprites but receives BULBASAUR as the starter (Yellow mode only).

> 💡 The `custom_characters/example_custom/` folder included in the mod already contains placeholder sprites and a filled-in `config.json` to use as a starting point.

## 🧪 Testing

```sh
# Validate the mod loads cleanly
python tools/modkit.py validate mods/whos-that-trainer

# Run in developer mode
love . --developer
```

## ⚠️ Known Limitations

- **Palette accuracy:** Some built-in characters may use fallback palettes if their original sprite data is unavailable in your ROM cache.

## 🔄 Updating from Previous Versions

If you're updating from an older version (< 0.0.3), you may need to regenerate back sprites to get the corrected orientation:

1. Delete the `assets/generated/battle/player_back/` folder
2. Restart the game — assets will regenerate automatically
3. Reimport your ROM.

🗺️ **Roadmap**
- [x] Player Sprite Swap (Overworld, Bike & Battle).
- [x] Rival Sprite Swap.
- [x] Select follower Sprite in overworld.
- [x] Custom Sprite Injection: Allow players to load custom PNG files to create their own characters.
- [x] Starter Swap: Syncs the starter with the character(at now just yellow and it add as a 2nd starter).
- [ ] **Change every gym leader and elite 4** allow to setup every gym leader as you want, what about lance as 1st gym leader? or misty as last elite four member ... or maybe YOU?.
- [ ] **Custom Starter follow as the default and dont has humor window**.
- [ ] **follower vanilla and rival:** a BUG that rival and follower back to original sometimes on overworld.


## 📝 Credits

All built-in character sprites are derived from the original Red/Blue/Yellow ROMs via runtime transformation. No copyrighted artwork is distributed with this mod.

The custom character Kawfy was made by the excelent artist that drew it with love. Follow at [bluesky](https://bsky.app/profile/kawfy.bsky.social) and [instagram](https://www.instagram.com/a.kawfy).

PS: tested on Yellow and recomp version 0.1.6