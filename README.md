# free_miners

A Minetest mod that spawns a player-like Miner NPC to automate mining operations. The Miner mines a defined area layer-by-layer, deposits harvested materials into chests, automatically handles tool wear by crafting or retrieving replacement tools, and relocates to mine adjacent areas when done.

Author: **ronrob-lu**

---

## Features

* **3D Flight & Navigation:** Navigates via direct 3D flying vectors rather than needing complex stair construction.
* **Layer-by-Layer Mining:** Systematically clears a 14x14x7 area block-by-block, returning to the chest after each layer to deposit items.
* **Smart Inventory & Chest Handling:** 
  * Deposits mined items to chest networks.
  * Dynamically crafts new chests if existing ones run out of space.
  * Drops off any excess blocks/items and retains or retrieves necessary tools.
* **Auto-Crafting & Tool Retrieval:** Automatically retrieves materials from chests to craft wood/stone tools (pickaxes, shovels, axes) when current ones break.
* **Sword Vulnerability:** Miner NPCs can be killed in-world using a sword or normal weapons.
* **Multi-Game Compatibility:** Dynamically resolves item names and crafting recipes for both standard **Minetest Game** (`default:`) and **MineClone2** (`mcl_`).
* **Chat Commands:** Run `/kill_miners` to clear all active Miner NPCs in loaded sectors.
* **Debug Support:** Toggleable chat debug output (`free_miners.debug = true` in `items.lua`) to inspect miner thoughts and actions.

---

## Installation

1. Copy the `free_miners` directory into your Minetest `mods/` directory.
2. Enable the mod in your world configuration.
3. Ensure optional dependencies (`default` or `mcl_core`/`mcl_chests`/`mcl_tools`) are enabled depending on your game.

---

## How to Use

### 1. Craft the Miner Spawner Block
* **Minetest Game Recipe:**
  * Shape: Chest in the middle, surrounded by iron ingots.
  ```
  [Steel Ingot] [Steel Ingot] [Steel Ingot]
  [Steel Ingot] [    Chest  ] [Steel Ingot]
  [Steel Ingot] [Steel Ingot] [Steel Ingot]
  ```
* **MineClone2 Recipe:**
  * Shape: Chest in the middle, surrounded by iron ingots.
  ```
  [Iron Ingot]  [Iron Ingot]  [Iron Ingot]
  [Iron Ingot]  [    Chest ]  [Iron Ingot]
  [Iron Ingot]  [Iron Ingot]  [Iron Ingot]
  ```

### 2. Set Up Mining
1. Place the **Miner Spawner** block.
2. A chest and a Miner NPC will spawn at the location.
3. The Miner will begin digging out a 14x14x7 volume underneath or near the chest.
4. When finished with a sector, the miner will search for a new adjacent spot, build a new chest, and continue mining.

---

## License

Licensed under the **GNU Lesser General Public License v2.1 or later** (LGPL-2.1-or-later). See [LICENCE.md](file:///Users/theo/development/free-miners/LICENCE.md) for the full text.
