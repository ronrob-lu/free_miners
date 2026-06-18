free_miners = free_miners or {}

-- Define the recipes the NPC knows.
-- Uses the mapped item names from free_miners.items.
function free_miners.get_recipes()
    local items = free_miners.items
    return {
        [items.stick] = {
            ingredients = { { name = items.wood, count = 1 } },
            yield = 4,
        },
        [items.chest] = {
            ingredients = { { name = items.wood, count = 8 } },
            yield = 1,
        },
        [items.pick_wood] = {
            ingredients = { { name = items.wood, count = 3 }, { name = items.stick, count = 2 } },
            yield = 1,
        },
        [items.pick_stone] = {
            ingredients = { { name = items.cobble, count = 3 }, { name = items.stick, count = 2 } },
            yield = 1,
        },
        [items.shovel_wood] = {
            ingredients = { { name = items.wood, count = 1 }, { name = items.stick, count = 2 } },
            yield = 1,
        },
        [items.shovel_stone] = {
            ingredients = { { name = items.cobble, count = 1 }, { name = items.stick, count = 2 } },
            yield = 1,
        },
        [items.axe_wood] = {
            ingredients = { { name = items.wood, count = 3 }, { name = items.stick, count = 2 } },
            yield = 1,
        },
        [items.axe_stone] = {
            ingredients = { { name = items.cobble, count = 3 }, { name = items.stick, count = 2 } },
            yield = 1,
        },
    }
end

-- Check if the entity has all ingredients for a recipe
local function has_ingredients(entity, recipe)
    for _, ing in ipairs(recipe.ingredients) do
        if not free_miners.inventory_has(entity, ing.name, ing.count) then
            return false
        end
    end
    return true
end

-- Consume ingredients and add the crafted item to inventory
local function craft_recipe(entity, target_item, recipe)
    for _, ing in ipairs(recipe.ingredients) do
        free_miners.inventory_remove(entity, ing.name, ing.count)
    end
    local yield_stack = ItemStack(target_item)
    yield_stack:set_count(recipe.yield)
    free_miners.inventory_add(entity, yield_stack)
    return true
end

-- Attempt to craft target_item, dynamically crafting sticks first if needed.
function free_miners.auto_craft(entity, target_item)
    local recipes = free_miners.get_recipes()
    local recipe = recipes[target_item]
    if not recipe then return false end

    -- Check if we can craft it immediately
    if has_ingredients(entity, recipe) then
        return craft_recipe(entity, target_item, recipe)
    end

    -- If we are missing sticks, try to craft sticks first
    local items = free_miners.items
    local sticks_needed = 0
    for _, ing in ipairs(recipe.ingredients) do
        if ing.name == items.stick then
            sticks_needed = ing.count
        end
    end

    if sticks_needed > 0 then
        -- Count sticks currently in inventory
        local current_sticks = 0
        for i = 1, 32 do
            local stack = entity.inventory[i]
            if not stack:is_empty() and stack:get_name() == items.stick then
                current_sticks = current_sticks + stack:get_count()
            end
        end

        local missing_sticks = sticks_needed - current_sticks
        if missing_sticks > 0 then
            -- 1 wood yields 4 sticks
            local stick_batches = math.ceil(missing_sticks / 4)
            for _ = 1, stick_batches do
                if not free_miners.auto_craft(entity, items.stick) then
                    return false
                end
            end
        end
    end

    -- Check again after crafting sticks
    if has_ingredients(entity, recipe) then
        return craft_recipe(entity, target_item, recipe)
    end

    return false
end
