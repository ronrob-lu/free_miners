free_miners = free_miners or {}

-------------------------------------------------------------------------------
-- Core inventory helpers
-------------------------------------------------------------------------------

-- Initialize the NPC inventory with 32 slots
function free_miners.init_inventory(entity)
    entity.inventory = {}
    for i = 1, 32 do
        entity.inventory[i] = ItemStack("")
    end
end

-- Add an itemstack to the NPC inventory.
-- Returns the leftover ItemStack (empty if fully added).
function free_miners.inventory_add(entity, itemstack)
    local stack = ItemStack(itemstack)

    -- First pass: try to stack with existing items
    for i = 1, 32 do
        local inv_stack = entity.inventory[i]
        if not inv_stack:is_empty() and inv_stack:get_name() == stack:get_name() then
            local free_space = inv_stack:get_stack_max() - inv_stack:get_count()
            if free_space > 0 then
                local add_count = math.min(free_space, stack:get_count())
                inv_stack:set_count(inv_stack:get_count() + add_count)
                stack:set_count(stack:get_count() - add_count)
                if stack:is_empty() then
                    return stack
                end
            end
        end
    end

    -- Second pass: place in empty slots
    for i = 1, 32 do
        if entity.inventory[i]:is_empty() then
            entity.inventory[i] = stack
            return ItemStack("")
        end
    end

    return stack
end

-- Check if NPC has at least `count` of `itemname`
function free_miners.inventory_has(entity, itemname, count)
    local total = 0
    for i = 1, 32 do
        local inv_stack = entity.inventory[i]
        if not inv_stack:is_empty() and inv_stack:get_name() == itemname then
            total = total + inv_stack:get_count()
            if total >= count then
                return true
            end
        end
    end
    return false
end

-- Remove up to `count` of `itemname` from NPC inventory.
-- Returns the ItemStack of removed items.
function free_miners.inventory_remove(entity, itemname, count)
    local remaining = count
    local removed_stack = ItemStack(itemname)
    removed_stack:set_count(0)

    for i = 1, 32 do
        local inv_stack = entity.inventory[i]
        if not inv_stack:is_empty() and inv_stack:get_name() == itemname then
            local take_count = math.min(remaining, inv_stack:get_count())
            inv_stack:set_count(inv_stack:get_count() - take_count)
            removed_stack:set_count(removed_stack:get_count() + take_count)
            remaining = remaining - take_count
            if remaining <= 0 then
                break
            end
        end
    end
    return removed_stack
end

-- Get the number of empty slots in the NPC inventory
function free_miners.inventory_get_empty_slots(entity)
    local empty = 0
    for i = 1, 32 do
        if entity.inventory[i]:is_empty() then
            empty = empty + 1
        end
    end
    return empty
end

-- Find the best tool in the NPC inventory for a given set of node groups.
-- Returns (slot_index, dig_params) for the best tool, or (nil, hand_dig_params).
function free_miners.find_best_tool(entity, node_groups)
    local hand_def = minetest.registered_items[""]
    local hand_caps = hand_def and hand_def.tool_capabilities
    local hand_dp = minetest.get_dig_params(node_groups, hand_caps)

    local best_slot = nil
    local best_time = hand_dp.diggable and hand_dp.time or math.huge
    local best_dp = hand_dp

    for i = 1, 32 do
        local inv_stack = entity.inventory[i]
        if not inv_stack:is_empty() then
            local def = minetest.registered_items[inv_stack:get_name()]
            local tool_caps = def and def.tool_capabilities
            if tool_caps then
                local dp = minetest.get_dig_params(node_groups, tool_caps)
                if dp.diggable and dp.time < best_time then
                    best_slot = i
                    best_time = dp.time
                    best_dp = dp
                end
            end
        end
    end

    if best_slot then
        return best_slot, best_dp
    elseif hand_dp.diggable then
        return nil, hand_dp
    else
        return nil, { diggable = false }
    end
end

-- Wear down a tool in a slot by a given amount
function free_miners.wear_tool(entity, slot, wear_amount)
    if not slot then return end
    local inv_stack = entity.inventory[slot]
    if inv_stack:is_empty() then return end

    local wear = inv_stack:get_wear() + wear_amount
    if wear >= 65535 then
        -- Tool breaks!
        entity.inventory[slot] = ItemStack("")
        minetest.sound_play("default_tool_breaks", {
            pos = entity.object:get_pos(),
            gain = 0.5,
        }, true)
    else
        inv_stack:set_wear(wear)
    end
end

-------------------------------------------------------------------------------
-- Chest placement helper
-------------------------------------------------------------------------------

-- Find a new chest position adjacent to the last chest.
-- Tries horizontal neighbors first, then above.
function free_miners.find_new_chest_pos(entity)
    local last_chest = entity.chests[#entity.chests]
    if not last_chest then return nil end

    local dirs = {
        { x = 1, y = 0, z = 0 },
        { x = -1, y = 0, z = 0 },
        { x = 0, y = 0, z = 1 },
        { x = 0, y = 0, z = -1 },
    }

    for _, d in ipairs(dirs) do
        local pos = vector.add(last_chest, d)
        local node = minetest.get_node(pos)
        local def = minetest.registered_nodes[node.name]
        if node.name == "air" or (def and def.buildable_to) then
            return pos
        end
    end

    -- Try placing on top of last chest
    local pos_above = vector.add(last_chest, { x = 0, y = 1, z = 0 })
    local node = minetest.get_node(pos_above)
    local def = minetest.registered_nodes[node.name]
    if node.name == "air" or (def and def.buildable_to) then
        return pos_above
    end

    return nil
end

-------------------------------------------------------------------------------
-- Chest interaction: deposit
-------------------------------------------------------------------------------

-- Deposit all inventory items except those in keep_slots to chests.
-- For each item:
--   1. Try all existing chests with room_for_item / add_item
--   2. If full, try to place a new chest (craft one if needed)
-- Returns true if all items were deposited, false if some items are stuck.
function free_miners.deposit_to_chests(entity, keep_slots)
    local items = free_miners.items
    local deposited_all = true

    for i = 1, 32 do
        local stack = entity.inventory[i]
        if not stack:is_empty() and not keep_slots[i] then
            local item_deposited = false
            local deposit_name = stack:get_name()
            local deposit_count = stack:get_count()

            -- Try existing chests
            for _, cpos in ipairs(entity.chests) do
                local meta = minetest.get_meta(cpos)
                local inv = meta:get_inventory()
                if inv then
                    local leftover = inv:add_item("main", stack)
                    local added = deposit_count - leftover:get_count()
                    if added > 0 then
                        free_miners.log_debug(entity,
                            "Deposited " .. added .. "x " .. deposit_name
                            .. " into chest at " .. minetest.pos_to_string(cpos))
                    end
                    if leftover:is_empty() then
                        entity.inventory[i] = ItemStack("")
                        item_deposited = true
                        break
                    else
                        -- Partial deposit, update stack to remainder
                        stack = leftover
                        entity.inventory[i] = leftover
                        deposit_count = leftover:get_count()
                    end
                end
            end

            -- If not fully deposited, try to place a new chest
            if not item_deposited then
                local new_chest_pos = free_miners.find_new_chest_pos(entity)
                if new_chest_pos then
                    local has_chest = free_miners.inventory_has(entity, items.chest, 1)
                    if not has_chest then
                        free_miners.log_debug(entity, "Chests full. Attempting to craft a new chest.")
                        free_miners.retrieve_crafting_materials(entity)
                        free_miners.auto_craft(entity, items.chest)
                        has_chest = free_miners.inventory_has(entity, items.chest, 1)
                        free_miners.deposit_crafting_materials(entity)
                    end

                    if has_chest then
                        minetest.set_node(new_chest_pos, {name = items.chest})
                        free_miners.inventory_remove(entity, items.chest, 1)
                        table.insert(entity.chests, new_chest_pos)
                        entity.chest_pos = new_chest_pos
                        minetest.sound_play("default_place_node", {
                            pos = new_chest_pos, gain = 0.5,
                        }, true)
                        free_miners.log_debug(entity,
                            "Placed new chest at " .. minetest.pos_to_string(new_chest_pos))

                        local meta2 = minetest.get_meta(new_chest_pos)
                        local inv2 = meta2:get_inventory()
                        if inv2 then
                            local leftover = inv2:add_item("main", stack)
                            local added = stack:get_count() - leftover:get_count()
                            if added > 0 then
                                free_miners.log_debug(entity,
                                    "Deposited " .. added .. "x " .. deposit_name
                                    .. " into new chest at " .. minetest.pos_to_string(new_chest_pos))
                            end
                            if leftover:is_empty() then
                                entity.inventory[i] = ItemStack("")
                                item_deposited = true
                            else
                                entity.inventory[i] = leftover
                            end
                        end
                    end
                else
                    free_miners.log_debug(entity, "Could not find a place to put a new chest!")
                end
            end

            if not item_deposited then
                free_miners.log_debug(entity, "Failed to deposit: " .. entity.inventory[i]:to_string())
                deposited_all = false
            end
        end
    end

    return deposited_all
end

-------------------------------------------------------------------------------
-- Chest interaction: retrieve tools
-------------------------------------------------------------------------------

-- Retrieve ONLY tools (pickaxe, shovel, axe) from chests. NOT materials.
-- Uses inv:get_stack / inv:set_stack pattern.
function free_miners.retrieve_tools_from_chests(entity)
    local items = free_miners.items

    for _, cpos in ipairs(entity.chests) do
        local meta = minetest.get_meta(cpos)
        local inv = meta:get_inventory()
        if inv then
            for j = 1, inv:get_size("main") do
                local stack = inv:get_stack("main", j)
                if not stack:is_empty() then
                    local name = stack:get_name()
                    local is_tool = minetest.get_item_group(name, "pickaxe") > 0
                                 or minetest.get_item_group(name, "shovel") > 0
                                 or minetest.get_item_group(name, "axe") > 0
                                 or name:find("pick") or name:find("shovel") or name:find("axe")
                                 or name == items.pick_wood   or name == items.pick_stone
                                 or name == items.shovel_wood or name == items.shovel_stone
                                 or name == items.axe_wood    or name == items.axe_stone

                    if is_tool then
                        local leftover = free_miners.inventory_add(entity, stack)
                        local retrieved_count = stack:get_count() - leftover:get_count()
                        if retrieved_count > 0 then
                            free_miners.log_debug(entity,
                                "Retrieved tool " .. retrieved_count .. "x " .. name
                                .. " from chest at " .. minetest.pos_to_string(cpos))
                        end
                        inv:set_stack("main", j, leftover)
                    end
                end
            end
        end
    end
end

-------------------------------------------------------------------------------
-- Chest interaction: retrieve crafting materials
-------------------------------------------------------------------------------

-- Retrieve up to 8 each of wood, cobble, stick from chests for crafting.
-- Uses inv:remove_item("main", take_stack) to take items from chests.
function free_miners.retrieve_crafting_materials(entity)
    local items = free_miners.items
    local limits = {
        [items.wood]   = 8,
        [items.cobble] = 8,
        [items.stick]  = 8,
    }

    for name, limit in pairs(limits) do
        -- Count how many we already have in inventory
        local current = 0
        for i = 1, 32 do
            local stack = entity.inventory[i]
            if not stack:is_empty() and stack:get_name() == name then
                current = current + stack:get_count()
            end
        end

        local needed = limit - current
        if needed > 0 then
            for _, cpos in ipairs(entity.chests) do
                local meta = minetest.get_meta(cpos)
                local inv = meta:get_inventory()
                if inv then
                    for j = 1, inv:get_size("main") do
                        local stack = inv:get_stack("main", j)
                        if not stack:is_empty() and stack:get_name() == name then
                            local take_count = math.min(needed, stack:get_count())
                            local take_stack = ItemStack(name)
                            take_stack:set_count(take_count)
                            -- Use inv:remove_item (NOT inv:take_item which doesn't exist)
                            local removed = inv:remove_item("main", take_stack)
                            if not removed:is_empty() then
                                free_miners.inventory_add(entity, removed)
                                free_miners.log_debug(entity,
                                    "Retrieved " .. removed:get_count() .. "x " .. name
                                    .. " for crafting from chest at " .. minetest.pos_to_string(cpos))
                                needed = needed - removed:get_count()
                                if needed <= 0 then break end
                            end
                        end
                    end
                end
                if needed <= 0 then break end
            end
        end
    end
end

-------------------------------------------------------------------------------
-- Chest interaction: deposit crafting materials
-------------------------------------------------------------------------------

-- Deposit any remaining wood, cobble, sticks back into chests after crafting.
function free_miners.deposit_crafting_materials(entity)
    local items = free_miners.items
    local materials = { items.wood, items.cobble, items.stick }

    for i = 1, 32 do
        local stack = entity.inventory[i]
        if not stack:is_empty() then
            local name = stack:get_name()
            local is_mat = false
            for _, m in ipairs(materials) do
                if name == m then is_mat = true break end
            end

            if is_mat then
                for _, cpos in ipairs(entity.chests) do
                    local meta = minetest.get_meta(cpos)
                    local inv = meta:get_inventory()
                    if inv and inv:room_for_item("main", stack) then
                        inv:add_item("main", stack)
                        free_miners.log_debug(entity,
                            "Deposited leftover " .. stack:get_count() .. "x " .. name
                            .. " into chest at " .. minetest.pos_to_string(cpos))
                        entity.inventory[i] = ItemStack("")
                        break
                    end
                end
            end
        end
    end
end

-------------------------------------------------------------------------------
-- Main deposit-and-retrieve orchestrator
-------------------------------------------------------------------------------

-- Main function called from the miner entity.
-- Flow:
--   1. Find best tool slots to keep (pick, shovel, axe with best speed)
--   2. Deposit everything else to chests
--   3. Retrieve tools from chests
--   4. Craft any missing tools (stone first, wood fallback)
-- Returns true if all items were deposited successfully.
function free_miners.deposit_and_retrieve(entity)
    local items = free_miners.items

    ---------------------------------------------------------------------------
    -- Step 1: Identify best tools to keep
    ---------------------------------------------------------------------------
    local keep_slots = {}
    local best_pick_slot, best_pick_speed = nil, 0
    local best_shovel_slot, best_shovel_speed = nil, 0
    local best_axe_slot, best_axe_speed = nil, 0

    for i = 1, 32 do
        local stack = entity.inventory[i]
        if not stack:is_empty() then
            local name = stack:get_name()
            local def = minetest.registered_items[name]
            if def and def.tool_capabilities then
                local is_pick   = minetest.get_item_group(name, "pickaxe") > 0 or name:find("pick")
                local is_shovel = minetest.get_item_group(name, "shovel") > 0  or name:find("shovel")
                local is_axe    = minetest.get_item_group(name, "axe") > 0     or name:find("axe")

                -- Compute a speed score from groupcaps
                local speed = 1
                local groupcaps = def.tool_capabilities.groupcaps
                if groupcaps then
                    for _, cap in pairs(groupcaps) do
                        if cap.times then
                            for _, t in pairs(cap.times) do
                                if t > 0 then
                                    speed = math.max(speed, 1 / t)
                                end
                            end
                        end
                    end
                end

                if is_pick and speed > best_pick_speed then
                    best_pick_slot = i
                    best_pick_speed = speed
                elseif is_shovel and speed > best_shovel_speed then
                    best_shovel_slot = i
                    best_shovel_speed = speed
                elseif is_axe and speed > best_axe_speed then
                    best_axe_slot = i
                    best_axe_speed = speed
                end
            end
        end
    end

    if best_pick_slot   then keep_slots[best_pick_slot]   = true end
    if best_shovel_slot then keep_slots[best_shovel_slot] = true end
    if best_axe_slot    then keep_slots[best_axe_slot]    = true end

    ---------------------------------------------------------------------------
    -- Step 2: Deposit everything except kept tools
    ---------------------------------------------------------------------------
    local deposited_all = free_miners.deposit_to_chests(entity, keep_slots)

    ---------------------------------------------------------------------------
    -- Step 3: Retrieve tools from chests
    ---------------------------------------------------------------------------
    free_miners.retrieve_tools_from_chests(entity)

    ---------------------------------------------------------------------------
    -- Step 4: Check for missing tools and craft them
    ---------------------------------------------------------------------------
    local has_pick = false
    local has_shovel = false
    local has_axe = false

    for i = 1, 32 do
        local stack = entity.inventory[i]
        if not stack:is_empty() then
            local name = stack:get_name()
            if minetest.get_item_group(name, "pickaxe") > 0 or name:find("pick")
               or name == items.pick_wood or name == items.pick_stone then
                has_pick = true
            elseif minetest.get_item_group(name, "shovel") > 0 or name:find("shovel")
               or name == items.shovel_wood or name == items.shovel_stone then
                has_shovel = true
            elseif minetest.get_item_group(name, "axe") > 0 or name:find("axe")
               or name == items.axe_wood or name == items.axe_stone then
                has_axe = true
            end
        end
    end

    local missing_any = (not has_pick) or (not has_shovel) or (not has_axe)

    if missing_any then
        free_miners.retrieve_crafting_materials(entity)

        if not has_pick then
            local crafted = free_miners.auto_craft(entity, items.pick_stone)
            if crafted then
                free_miners.log_debug(entity, "Auto-crafted pickaxe: " .. items.pick_stone)
            else
                crafted = free_miners.auto_craft(entity, items.pick_wood)
                if crafted then
                    free_miners.log_debug(entity, "Auto-crafted pickaxe: " .. items.pick_wood)
                end
            end
        end

        if not has_shovel then
            local crafted = free_miners.auto_craft(entity, items.shovel_stone)
            if crafted then
                free_miners.log_debug(entity, "Auto-crafted shovel: " .. items.shovel_stone)
            else
                crafted = free_miners.auto_craft(entity, items.shovel_wood)
                if crafted then
                    free_miners.log_debug(entity, "Auto-crafted shovel: " .. items.shovel_wood)
                end
            end
        end

        if not has_axe then
            local crafted = free_miners.auto_craft(entity, items.axe_stone)
            if crafted then
                free_miners.log_debug(entity, "Auto-crafted axe: " .. items.axe_stone)
            else
                crafted = free_miners.auto_craft(entity, items.axe_wood)
                if crafted then
                    free_miners.log_debug(entity, "Auto-crafted axe: " .. items.axe_wood)
                end
            end
        end

        free_miners.deposit_crafting_materials(entity)
    end

    return deposited_all
end
