free_miners = free_miners or {}

-- ============================================================
-- SPAWNER NODE
-- ============================================================

local spawner_tiles = {"default_steel_block.png^default_tool_steelpick.png"}
if minetest.get_modpath("mcl_core") then
    spawner_tiles = {"mcl_core_iron_block.png"}
end

minetest.register_node("free_miners:spawner", {
    description = "Miner Spawner (Spawns a Miner NPC and places a chest)",
    tiles = spawner_tiles,
    groups = {cracky = 3, oddly_breakable_by_hand = 3},
    drawtype = "normal",

    after_place_node = function(pos, placer, itemstack, pointed_thing)
        if not placer or not placer:is_player() then return end
        local owner_name = placer:get_player_name()

        -- Spawn Miner entity at the placed position
        local obj = minetest.add_entity(pos, "free_miners:miner")
        if obj then
            local ent = obj:get_luaentity()
            if ent then
                ent.owner = owner_name
                ent:initialize_miner()
            end
        end
        -- The Miner's initialize_miner() places a chest at this position,
        -- which replaces the spawner node automatically.
    end,
})

-- ============================================================
-- CRAFTING RECIPE
-- ============================================================

local items = free_miners.items
local recipe = {
    output = "free_miners:spawner",
    recipe = {
        {items.cobble, items.pick_wood, items.cobble},
        {items.wood,   items.chest,     items.wood},
        {items.cobble, items.stick,     items.cobble},
    },
}

if minetest.get_modpath("mcl_core") then
    recipe.recipe = {
        {"mcl_core:cobblestone", "mcl_tools:pick_wood", "mcl_core:cobblestone"},
        {"mcl_core:wood",        "mcl_chests:chest",     "mcl_core:wood"},
        {"mcl_core:cobblestone", "mcl_core:stick",        "mcl_core:cobblestone"},
    }
end

minetest.register_craft(recipe)

-- ============================================================
-- CHAT COMMANDS
-- ============================================================

minetest.register_chatcommand("kill_miners", {
    description = "Removes all loaded Miner NPCs from the game",
    privs = {},
    func = function(name, param)
        local count = 0

        -- Remove from global entity list
        for _, obj in pairs(minetest.luaentities) do
            if obj.name == "free_miners:miner" then
                obj.object:remove()
                count = count + 1
            end
        end

        -- Also search nearby objects as fallback
        local player = minetest.get_player_by_name(name)
        if player then
            local ppos = player:get_pos()
            local objs = minetest.get_objects_inside_radius(ppos, 150)
            for _, obj in ipairs(objs) do
                local ent = obj:get_luaentity()
                if ent and ent.name == "free_miners:miner" then
                    obj:remove()
                    count = count + 1
                end
            end
        end

        return true, "Successfully removed " .. count .. " Miner NPCs."
    end,
})
