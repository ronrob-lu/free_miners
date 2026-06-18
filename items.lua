free_miners = free_miners or {}
free_miners.debug = false -- Set to true to enable chat debug logs

-- Send a debug message to the entity's owner
function free_miners.log_debug(entity, message)
    if free_miners.debug and entity.owner then
        minetest.chat_send_player(entity.owner, "[Miner DEBUG] " .. message)
    end
end

-- Return the first registered item name from a list of fallbacks
local function get_item_with_fallbacks(list)
    for _, name in ipairs(list) do
        if minetest.registered_items[name] then
            return name
        end
    end
    return list[1]
end

-- Resolved item names, supporting both default and mcl mods
free_miners.items = {
    chest       = get_item_with_fallbacks({"default:chest",       "mcl_chests:chest", "mcl_chests:chest_left"}),
    wood        = get_item_with_fallbacks({"default:wood",        "mcl_core:wood",    "mcl_core:oak_planks"}),
    cobble      = get_item_with_fallbacks({"default:cobble",      "mcl_core:cobble",  "mcl_core:cobblestone"}),
    stick       = get_item_with_fallbacks({"default:stick",       "mcl_core:stick",   "mcl_crafting:stick"}),
    pick_wood   = get_item_with_fallbacks({"default:pick_wood",   "mcl_tools:pick_wood"}),
    pick_stone  = get_item_with_fallbacks({"default:pick_stone",  "mcl_tools:pick_stone"}),
    shovel_wood = get_item_with_fallbacks({"default:shovel_wood", "mcl_tools:shovel_wood"}),
    shovel_stone= get_item_with_fallbacks({"default:shovel_stone","mcl_tools:shovel_stone"}),
    axe_wood    = get_item_with_fallbacks({"default:axe_wood",    "mcl_tools:axe_wood"}),
    axe_stone   = get_item_with_fallbacks({"default:axe_stone",   "mcl_tools:axe_stone"}),
}

-- Group names for wood and stone, adjusted for mcl
free_miners.groups = {
    wood  = "group:wood",
    stone = "group:stone",
}

if minetest.get_modpath("mcl_core") then
    free_miners.groups.wood  = "group:wood_planks"
    free_miners.groups.stone = "group:cobble"
end
