# Who's That Trainer?

Ever wanted to play Pokémon as Giovanni, Pikachu, or face yourself as the rival? Now you can!

**Who's That Trainer?** lets you swap between 17 iconic Gen 1 characters — complete with overworld sprites, battle sprites, and trainer portraits. Choose your character, rival, and follower independently from the start menu. You can also add unlimited custom characters by dropping your own sprites into a folder.

## ✨ Features

- **17 Built-in Characters:** RED, GIOVANNI, PIKACHU, BROCK, MISTY, LT. SURGE, ERIKA, KOGA, SABRINA, BLAINE, LORELEI, BRUNO, AGATHA, LANCE, BLUE, JESSIE, and JAMES
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

**2. Add your sprites**

| File | Description |
|---|---|
| `walk.png` | Walking sprite sheet with **exactly 6 frames** laid out horizontally, same format as native sprites. Use `assets/generated/sprites/brock.png` as a size and layout reference. |
| `front.png` | Front-facing sprite — used on the trainer card, intro, and Hall of Fame. |
| `back.png` | Back-facing sprite — used in battles. |
| `bike.png` | Bike sprite sheet with **exactly 6 frames** laid out horizontally. If absent, the game uses the default RED bike sprite. Use `assets/generated/sprites/red_bike.png` as a reference. |

> ⚠️ Both `walk.png` and `bike.png` (when provided) must contain exactly 6 animation frames arranged horizontally in a single sprite sheet.

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
| `starterSpecies` | string | No | `nil` | Species name of the starter Pokémon Oak gives on **Pokémon Yellow** (e.g. `"GEODUDE"`, `"PIKACHU"`). No effect on Red/Blue. |
| `palette` | string | No | `nil` | Borrow the GBC/SGB palette from a built-in character (e.g. `"BROCK"`, `"MISTY"`, `"SPRITE_GIOVANNI"`). Only takes effect in **COLORS = RED++** mode. See palette notes below. |
| `mirrorBack` | boolean | No | `false` | Horizontally flips `back.png` when displayed in battle |
| `trueColor` | boolean | No | `true` | When `true` (the default), your PNG colors are displayed exactly as painted — no recolorization is applied regardless of the COLORS setting. Set to `false` only when you also set `palette`. |

#### 🎨 Palette options explained

There are two ways to handle color for a custom character:

**True color (default — recommended for most custom characters)**

Leave `palette` unset (or `null`). The game renders your PNG with its original colors in every COLORS mode. This is the simplest option and gives you full control over how your character looks.

```json
{ "label": "Ash" }
```

**Borrow a built-in palette**

Set `palette` to the id of any built-in character (e.g. `"BROCK"`) or its sprite id (e.g. `"SPRITE_BROCK"`). The game will then recolorize your sprites using that character's palette ramp.

- Only takes effect in **COLORS = RED++** mode. In all other modes (SGB, OG RED, OG BLUE, etc.) the sprite is still rendered through the standard DMG shade pipeline, the same as any other overworld character.
- Your PNG must use the standard 4-shade DMG grayscale ramp (white / light gray / dark gray / black) for the recolorization to look correct.
- There is no way to define a fully custom palette that has never appeared in the game — the palette system only has slots for palettes already present in the ROM data.

```json
{ "label": "Ash", "palette": "MISTY", "trueColor": false }
```

If `config.json` is absent, the mod uses the folder name in uppercase as the `label` and all other fields at their defaults.

**4. Restart the game**

The character appears automatically in the CHARACTER, RIVAL, and FOLLOWER lists — sorted alphabetically alongside the built-in characters. No additional file editing required.

---

### Example folder structure

```
custom_characters/         ← folder inside the game's data directory
└── ash/
    ├── walk.png           ← required: 6 frames, same layout as brock.png
    ├── front.png          ← required
    ├── back.png           ← required
    ├── bike.png           ← optional: 6 frames, same layout as red_bike.png
    └── config.json        ← optional; label, starterSpecies (Yellow only), mirrorBack, trueColor
```

> 💡 The `custom_characters/example_custom/` folder included in the mod already contains placeholder sprites and a filled-in `config.json` to use as a starting point.

## 🧪 Testing

```sh
# Validate the mod loads cleanly
python tools/modkit.py validate mods/whos-that-trainer

# Run in developer mode
love . --developer
```

## ⚠️ Known Limitations

- **Rival battle portraits:** Currently display in grayscale due to engine palette pipeline limitations. This requires adding a `trainer.pic` hook to the engine core (tracked as future enhancement).
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
- [x] Starter Swap: Syncs the starter with the character.
- [ ] **Custom Starter follow as the default and dont has humor window** In progress.
- [ ] **Custom Rival battle pallete:** a BUG that rival pallete on battles are appearing in mono colors.
- [ ] **follower vanilla and rival:** a BUG that rival and follower back to original sometimes on overworld.

## 📝 Credits

All built-in character sprites are derived from the original Pokémon Red/Blue/Yellow ROMs via runtime transformation. No copyrighted artwork is distributed with this mod.

PS: tested on Pokémon Yellow and recomp version 0.1.6 — custom character support added in v1.1.0
