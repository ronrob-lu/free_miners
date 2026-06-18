local modpath = minetest.get_modpath("free_miners")

dofile(modpath .. "/items.lua")
dofile(modpath .. "/inventory.lua")
dofile(modpath .. "/crafting.lua")
dofile(modpath .. "/pathfinding.lua")
dofile(modpath .. "/miner.lua")
dofile(modpath .. "/spawner.lua")

minetest.log("action", "[free_miners] Mod loaded successfully!")
