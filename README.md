# 👤 Who's That Trainer?

**Who's That Trainer?** is a dynamic character customization mod for the *Pokémon Gen 1 Recompilation Project*. 

Break the rules of Kanto! Take control of Gym Leaders, Elite 4 members, or even Team Rocket. Or better yet: inject your very own custom pixel art to create a truly unique journey!

## ✨ Features

* 🧢 **Dynamic Player Swap:** Play as Giovanni, Brock, Misty, Lance, and more. Changes apply to the overworld walking sprites, battle intro cards, and battle back sprites.
* 😠 **Rival Swap:** Choose your nemesis! Replace Blue with any available character in the mod.
* 💛 **Follower Swap:** The overworld follower system has been updated to reflect your custom choices seamlessly.
* 🎨 **Flawless Pixel Art (Integer Scaling):** The mod dynamically crops and scales native ROM assets using perfect Integer Scaling, ensuring back sprites look sharp, authentic, and perfectly aligned with the battle UI.
* ✏️ **Custom Sprite Injection:** Easily load your own `.png` files to play as your original character, using a simple folder structure!
* 💾 **Zero-Asset Distribution:** The core mod distributes zero copyrighted images, generating everything at runtime via the `transforms.lua` pipeline using the player's own ROM cache.

## 🎮 How to Use

1. Ensure you have the `gen1recomp` engine.
2. Load the `whos-that-trainer.zip` from recomp launcher.
3. Press **F10** to open the Mod Manager, enable **Who's That Trainer?**, and configure your characters in the mod options menu.
4. play the game xD
PS:. just tested with pokemon yellow and engine 1.4.4

## 🖌️ How to Add Custom Characters

You can now inject your own characters into the game! 

1. Edit zip file and Navigate to `whos-that-trainer/custom_characters/`.
2. Duplicate the `example_custom` folder and rename it to your character's name (no spaces).
3. Inside your new folder, replace the existing image files with your own pixel art:
   * `walk.png`: The overworld walking sprite sheet.
   * `front.png`: The trainer card / battle intro portrait.
   * `back.png`: The battle back sprite.
4. Open the `config.json` inside your folder and update the character's `id` and `label` (the name that will appear in the game's mod menu).
5. Restart the game, and your custom character will be available in the Mod Manager options!

## 🗺️ Roadmap

* [x] Player Sprite Swap (Overworld & Battle).
* [x] Rival Sprite Swap.
* [x] Slect follower visuals.
* [x] **Custom Sprite Injection:** Allow players to load custom PNG files.

## 🤝 Credits
* Mod developed by **MyFriendDev**.
* Built for the amazing `gen1recomp` architecture made with love.