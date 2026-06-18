free_miners = free_miners or {}

-- ============================================================
-- ANIMATION HELPERS
-- ============================================================

local function get_animations(mesh_name)
    mesh_name = mesh_name or "character.b3d"
    local player_api_ref = player_api or (mcl_player and mcl_player.player_api) or core.player_api
    if player_api_ref and player_api_ref.registered_models and player_api_ref.registered_models[mesh_name] then
        return player_api_ref.registered_models[mesh_name].animations
    end
    return {
        stand = {x = 0, y = 79},
        walk  = {x = 80, y = 99},
        dig   = {x = 189, y = 198},
    }
end

local function set_animation(entity, anim_type)
    if entity.current_animation == anim_type then return end
    entity.current_animation = anim_type

    local props = entity.object:get_properties()
    local mesh = props and props.mesh or "character.b3d"
    local anims = get_animations(mesh)

    local range = anims.stand or {x = 0, y = 79}
    local speed = 30
    local loop = true

    if anim_type == "walk" then
        range = anims.walk or {x = 80, y = 99}
    elseif anim_type == "dig" then
        range = anims.dig or {x = 189, y = 198}
    end

    entity.object:set_animation(range, speed, 0, loop)
end

-- ============================================================
-- SCAN HELPERS
-- ============================================================

-- Advance the scan coordinates to the next block position.
-- Returns true if we just completed a full layer (x wrapped).
local function advance_scan(entity)
    entity.scan_z = entity.scan_z + 1
    if entity.scan_z > 6 then
        entity.scan_z = -7
        entity.scan_x = entity.scan_x + 1
        if entity.scan_x > 6 then
            entity.scan_x = -7
            entity.scan_y = entity.scan_y - 1
            return true -- layer just finished
        end
    end
    return false
end

-- Check if the entire 14x14x7 mining region has no walkable blocks left
local function is_area_empty(mining_center)
    for y = 0, -6, -1 do
        for x = -7, 6 do
            for z = -7, 6 do
                local p = {
                    x = mining_center.x + x,
                    y = mining_center.y + y,
                    z = mining_center.z + z,
                }
                local node = minetest.get_node(p)
                local def = minetest.registered_nodes[node.name]
                if node.name ~= "air" and node.name ~= "ignore"
                   and node.name ~= free_miners.items.chest
                   and def and def.walkable then
                    return false
                end
            end
        end
    end
    return true
end

-- ============================================================
-- MINER ENTITY
-- ============================================================

minetest.register_entity("free_miners:miner", {
    initial_properties = {
        hp_max = 20,
        physical = true,
        collisionbox = {-0.3, 0.0, -0.3, 0.3, 1.7, 0.3},
        visual = "mesh",
        mesh = "character.b3d",
        textures = {"character.png"},
        visual_size = {x = 1, y = 1, z = 1},
        static_save = true,
    },

    -- ==================================
    -- ON ACTIVATE (spawn / reload)
    -- ==================================
    on_activate = function(self, staticdata, dtime_s)
        self.object:set_armor_groups({fleshy = 100})
        free_miners.init_inventory(self)

        -- Ephemeral state
        self.state_time = 0
        self.prev_state = nil
        self.dig_sound_timer = 0
        self.mined_something = false
        self.checked_chest = false

        -- Load saved data
        if staticdata and staticdata ~= "" then
            local data = minetest.deserialize(staticdata)
            if data then
                self.owner = data.owner
                self.chest_pos = data.chest_pos
                self.chests = data.chests or {data.chest_pos}
                self.mining_center = data.mining_center
                self.state = data.state
                self.scan_x = data.scan_x or -7
                self.scan_y = data.scan_y or 0
                self.scan_z = data.scan_z or -7
                self.checked_chest = data.checked_chest or false
                self.mined_something = data.mined_something or false
                if data.inventory then
                    for i = 1, 32 do
                        self.inventory[i] = ItemStack(data.inventory[i])
                    end
                end
            end
        end

        -- Default state
        self.state = self.state or "init"

        -- If we were mid-dig or mid-flight when saved, go back to scan
        if self.state == "dig" then
            self.state = "scan"
        end

        -- Copy owner's skin after a short delay (owner may not be loaded yet)
        minetest.after(1.0, function()
            if self.object:get_pos() then
                self:copy_owner_skin()
                if self.owner then
                    self.object:set_properties({
                        nametag = self.owner .. "'s Miner",
                        nametag_color = "#FFFFFF",
                    })
                end
            end
        end)
    end,

    -- ==================================
    -- ON PUNCH (killable with sword)
    -- ==================================
    on_punch = function(self, puncher, time_from_last_punch, tool_capabilities, dir)
        local hp = self.object:get_hp()
        if hp <= 0 then
            minetest.sound_play("default_death", {pos = self.object:get_pos(), gain = 0.8}, true)
            self.object:remove()
        else
            minetest.sound_play("player_damage", {pos = self.object:get_pos(), gain = 0.5}, true)
        end
    end,

    -- ==================================
    -- SAVE DATA
    -- ==================================
    get_staticdata = function(self)
        local inv_raw = {}
        for i = 1, 32 do
            inv_raw[i] = self.inventory[i]:to_string()
        end
        return minetest.serialize({
            owner = self.owner,
            chest_pos = self.chest_pos,
            chests = self.chests,
            mining_center = self.mining_center,
            state = self.state,
            scan_x = self.scan_x,
            scan_y = self.scan_y,
            scan_z = self.scan_z,
            checked_chest = self.checked_chest,
            mined_something = self.mined_something,
            inventory = inv_raw,
        })
    end,

    -- ==================================
    -- COPY OWNER SKIN
    -- ==================================
    copy_owner_skin = function(self)
        if not self.owner then return end
        local player = minetest.get_player_by_name(self.owner)
        if player then
            local prop = player:get_properties()
            self.object:set_properties({
                visual = prop.visual,
                mesh = prop.mesh,
                textures = prop.textures,
                visual_size = prop.visual_size,
                collisionbox = prop.collisionbox,
            })
        end
    end,

    -- ==================================
    -- INITIALIZE MINER (called once on first spawn)
    -- ==================================
    initialize_miner = function(self)
        local pos = self.object:get_pos()
        if not pos then return end
        local spawn_pos = vector.round(pos)

        -- Place chest at spawn
        minetest.set_node(spawn_pos, {name = free_miners.items.chest})
        minetest.sound_play("default_place_node", {pos = spawn_pos, gain = 0.5}, true)

        self.chest_pos = spawn_pos
        self.chests = {spawn_pos}

        -- Determine mining direction from player's look or random
        local dir = {x = 1, y = 0, z = 0}
        local player = minetest.get_player_by_name(self.owner)
        if player then
            local yaw = player:get_look_horizontal()
            dir = {x = -math.sin(yaw), y = 0, z = math.cos(yaw)}
        else
            local angle = math.random() * 2 * math.pi
            dir = {x = math.cos(angle), y = 0, z = math.sin(angle)}
        end

        self.mining_center = {
            x = math.floor(spawn_pos.x + dir.x * 15 + 0.5),
            y = spawn_pos.y,
            z = math.floor(spawn_pos.z + dir.z * 15 + 0.5),
        }

        -- Start scan at top-left of first layer
        self.scan_x = -7
        self.scan_y = 0
        self.scan_z = -7
        self.checked_chest = false
        self.mined_something = false

        self.state = "fly_to_mine"
        free_miners.log_debug(self, "Initialized. Mining center: " .. minetest.pos_to_string(self.mining_center))
    end,

    -- ==================================
    -- MAIN STEP FUNCTION
    -- ==================================
    on_step = function(self, dtime)
        local pos = self.object:get_pos()
        if not pos then return end

        -- Track state changes for debug logging
        if self.state ~= self.prev_state then
            free_miners.log_debug(self, "STATE: " .. tostring(self.prev_state) .. " -> " .. tostring(self.state)
                .. " at " .. minetest.pos_to_string(vector.round(pos)))
            self.prev_state = self.state
            self.state_time = 0
        else
            self.state_time = (self.state_time or 0) + dtime
        end

        -- =============================================
        -- STATE: init
        -- =============================================
        if self.state == "init" then
            self:initialize_miner()

        -- =============================================
        -- STATE: fly_to_mine (fly from chest to mining area)
        -- =============================================
        elseif self.state == "fly_to_mine" then
            -- Calculate target: current scan position in the mining grid
            local target = {
                x = self.mining_center.x + (self.scan_x or 0),
                y = self.mining_center.y + (self.scan_y or 0),
                z = self.mining_center.z + (self.scan_z or 0),
            }

            -- Timeout safety: teleport after 15 seconds
            if self.state_time > 15.0 then
                free_miners.log_debug(self, "TIMEOUT fly_to_mine -> teleporting")
                self.object:set_pos(target)
                self.object:set_velocity({x = 0, y = 0, z = 0})
                self.state = "scan"
                return
            end

            set_animation(self, "walk")
            local result = free_miners.fly_toward(self, target, 2.0)
            if result == "arrived" then
                self.state = "scan"
            end

        -- =============================================
        -- STATE: scan (find next block to mine)
        -- =============================================
        elseif self.state == "scan" then
            -- Stop moving, apply gravity
            self.object:set_velocity({x = 0, y = 0, z = 0})
            self.object:set_acceleration({x = 0, y = -9.81, z = 0})
            set_animation(self, "stand")

            -- Check inventory first
            if free_miners.inventory_get_empty_slots(self) <= 2 then
                free_miners.log_debug(self, "Inventory full (" .. free_miners.inventory_get_empty_slots(self) .. " slots). Going to chest.")
                self.state = "fly_to_chest"
                return
            end

            -- Scan for next solid block in the mining grid
            local found = false
            local scans = 0
            while not found and self.scan_y >= -6 do
                local target_pos = {
                    x = self.mining_center.x + self.scan_x,
                    y = self.mining_center.y + self.scan_y,
                    z = self.mining_center.z + self.scan_z,
                }
                local node = minetest.get_node(target_pos)
                local def = minetest.registered_nodes[node.name]

                if node.name ~= "air" and node.name ~= "ignore"
                   and node.name ~= free_miners.items.chest
                   and def and def.walkable then
                    -- Found a solid block
                    found = true
                    self.target_block = target_pos
                    self.target_node_name = node.name
                else
                    advance_scan(self)
                end

                scans = scans + 1
                if scans > 250 then break end -- safety: don't freeze the server
            end

            if not found then
                -- Scan exhausted (scan_y went past -6)
                if self.scan_y < -6 then
                    if is_area_empty(self.mining_center) then
                        free_miners.log_debug(self, "Area fully mined. Relocating.")
                        self.state = "relocate"
                    else
                        -- Blocks remain but we couldn't mine them on this pass.
                        -- Go to chest once for tools, then relocate if still stuck.
                        if not self.checked_chest then
                            free_miners.log_debug(self, "Blocks remain. Going to chest for tools.")
                            self.checked_chest = true
                            -- Reset scan so after chest visit we do another pass
                            self.scan_x = -7
                            self.scan_y = 0
                            self.scan_z = -7
                            self.state = "fly_to_chest"
                        else
                            -- Already tried chest, still can't mine. Relocate.
                            free_miners.log_debug(self, "Can't mine remaining blocks. Relocating.")
                            if self.owner then
                                minetest.chat_send_player(self.owner,
                                    self.owner .. "'s Miner: Can't mine some blocks. Moving to new area.")
                            end
                            self.state = "relocate"
                        end
                    end
                end
                return
            end

            -- We found a block. Check if we can dig it.
            local def = minetest.registered_nodes[self.target_node_name]
            local groups = def and def.groups or {}
            local slot, dp = free_miners.find_best_tool(self, groups)

            if not dp.diggable then
                -- Try crafting the right tool
                local target_tool = nil
                if groups.cracky and groups.cracky > 0 then
                    target_tool = free_miners.items.pick_stone
                    if not free_miners.inventory_has(self, free_miners.items.cobble, 3) then
                        target_tool = free_miners.items.pick_wood
                    end
                elseif groups.crumbly and groups.crumbly > 0 then
                    target_tool = free_miners.items.shovel_stone
                    if not free_miners.inventory_has(self, free_miners.items.cobble, 1) then
                        target_tool = free_miners.items.shovel_wood
                    end
                elseif groups.choppy and groups.choppy > 0 then
                    target_tool = free_miners.items.axe_stone
                    if not free_miners.inventory_has(self, free_miners.items.cobble, 3) then
                        target_tool = free_miners.items.axe_wood
                    end
                end

                local crafted = false
                if target_tool then
                    crafted = free_miners.auto_craft(self, target_tool)
                    if crafted then
                        free_miners.log_debug(self, "Crafted tool: " .. target_tool)
                    end
                end

                if not crafted then
                    if not self.checked_chest then
                        free_miners.log_debug(self, "Need tool for " .. self.target_node_name .. ". Going to chest.")
                        self.checked_chest = true
                        self.state = "fly_to_chest"
                    else
                        free_miners.log_debug(self, "Skipping unminable block: " .. self.target_node_name
                            .. " at " .. minetest.pos_to_string(self.target_block))
                        advance_scan(self)
                        -- Stay in scan state, will re-enter next tick
                    end
                    return
                end

                -- Re-evaluate after crafting
                slot, dp = free_miners.find_best_tool(self, groups)
                if not dp.diggable then
                    advance_scan(self)
                    return
                end
            end

            -- We can dig this block. Are we close enough?
            local dist = vector.distance(pos, self.target_block)
            if dist <= 4.5 then
                -- Close enough -> start digging
                self.dig_target = self.target_block
                self.dig_timer = dp.time
                self.dig_tool_slot = slot
                self.dig_wear = dp.wear
                self.state = "dig"
                free_miners.log_debug(self, "Digging " .. self.target_node_name
                    .. " at " .. minetest.pos_to_string(self.target_block)
                    .. " (" .. string.format("%.1fs", dp.time) .. ")")
            else
                -- Need to fly closer
                self.fly_target = self.target_block
                self.state = "fly_to_block"
            end

        -- =============================================
        -- STATE: fly_to_block (fly to a specific mining target)
        -- =============================================
        elseif self.state == "fly_to_block" then
            if not self.fly_target then
                self.state = "scan"
                return
            end

            -- Timeout safety
            if self.state_time > 10.0 then
                free_miners.log_debug(self, "TIMEOUT fly_to_block -> teleporting near target")
                self.object:set_pos(vector.add(self.fly_target, {x = 0, y = 1, z = 0}))
                self.object:set_velocity({x = 0, y = 0, z = 0})
                self.state = "scan"
                return
            end

            set_animation(self, "walk")
            local result = free_miners.fly_toward(self, self.fly_target, 3.5)
            if result == "arrived" then
                self.state = "scan" -- re-evaluate the block at close range
            end

        -- =============================================
        -- STATE: dig (digging animation + timer)
        -- =============================================
        elseif self.state == "dig" then
            -- Stop horizontal movement, apply gravity
            local vel = self.object:get_velocity()
            self.object:set_velocity({x = 0, y = vel and vel.y or 0, z = 0})
            self.object:set_acceleration({x = 0, y = -9.81, z = 0})

            if not self.dig_target then
                self.state = "scan"
                return
            end

            free_miners.look_at(self, self.dig_target)
            set_animation(self, "dig")

            -- Play dig sound periodically
            self.dig_sound_timer = (self.dig_sound_timer or 0) - dtime
            if self.dig_sound_timer <= 0 then
                self.dig_sound_timer = 0.4
                local node = minetest.get_node(self.dig_target)
                local ndef = minetest.registered_nodes[node.name]
                local sound = ndef and ndef.sounds and (ndef.sounds.dig or ndef.sounds.dug)
                if sound then
                    minetest.sound_play(sound, {pos = self.dig_target, gain = 0.4}, true)
                end
            end

            -- Count down
            self.dig_timer = self.dig_timer - dtime
            if self.dig_timer <= 0 then
                -- === DIG COMPLETE ===
                local target = self.dig_target
                self.dig_target = nil

                local node = minetest.get_node(target)
                local ndef = minetest.registered_nodes[node.name]

                if node.name ~= "air" and node.name ~= "ignore" then
                    -- Determine tool for drops
                    local tool_name = ""
                    if self.dig_tool_slot then
                        local stack = self.inventory[self.dig_tool_slot]
                        if not stack:is_empty() then
                            tool_name = stack:get_name()
                        end
                    end

                    local drops = minetest.get_node_drops(node.name, tool_name)

                    -- Remove the node
                    minetest.remove_node(target)

                    -- Wear the tool
                    if self.dig_tool_slot and self.dig_wear then
                        free_miners.wear_tool(self, self.dig_tool_slot, self.dig_wear)
                    end

                    -- Play dug sound
                    if ndef and ndef.sounds and ndef.sounds.dug then
                        minetest.sound_play(ndef.sounds.dug, {pos = target, gain = 0.5}, true)
                    end

                    -- Collect drops into inventory
                    for _, drop in ipairs(drops) do
                        local stack = ItemStack(drop)
                        local leftover = free_miners.inventory_add(self, stack)
                        if not leftover:is_empty() then
                            minetest.add_item(target, leftover)
                        end
                    end

                    -- Track that we actually mined something
                    self.mined_something = true
                    self.checked_chest = false
                end

                -- Advance scan to next position
                local old_layer = self.scan_y
                advance_scan(self)

                -- Did we just finish a layer?
                if self.scan_y ~= old_layer then
                    free_miners.log_debug(self, "Layer " .. old_layer .. " complete. Going to chest to deposit.")
                    self.state = "fly_to_chest"
                else
                    self.state = "scan"
                end
            end

        -- =============================================
        -- STATE: fly_to_chest
        -- =============================================
        elseif self.state == "fly_to_chest" then
            if not self.chest_pos then
                free_miners.log_debug(self, "ERROR: No chest position!")
                self.state = "idle"
                return
            end

            -- Timeout safety
            if self.state_time > 15.0 then
                free_miners.log_debug(self, "TIMEOUT fly_to_chest -> teleporting to chest")
                self.object:set_pos({x = self.chest_pos.x, y = self.chest_pos.y + 1, z = self.chest_pos.z})
                self.object:set_velocity({x = 0, y = 0, z = 0})
                self.state = "deposit"
                return
            end

            set_animation(self, "walk")
            local result = free_miners.fly_toward(self, self.chest_pos, 2.0)
            if result == "arrived" then
                self.state = "deposit"
            end

        -- =============================================
        -- STATE: deposit (at chest, deposit items and get tools)
        -- =============================================
        elseif self.state == "deposit" then
            self.object:set_velocity({x = 0, y = 0, z = 0})
            self.object:set_acceleration({x = 0, y = -9.81, z = 0})
            set_animation(self, "stand")

            local success = free_miners.deposit_and_retrieve(self)

            if success then
                free_miners.log_debug(self, "Deposit complete. Returning to mine.")
                -- Only reset checked_chest if we actually mined something
                if self.mined_something then
                    self.checked_chest = false
                end
                self.mined_something = false
                self.state = "fly_to_mine"
            else
                if self.owner then
                    minetest.chat_send_player(self.owner,
                        self.owner .. "'s Miner: All chests are full!")
                end
                self.state = "idle"
            end

        -- =============================================
        -- STATE: idle (waiting, chests full)
        -- =============================================
        elseif self.state == "idle" then
            self.object:set_velocity({x = 0, y = 0, z = 0})
            self.object:set_acceleration({x = 0, y = -9.81, z = 0})
            set_animation(self, "stand")

            if self.state_time > 5.0 then
                free_miners.log_debug(self, "Retrying deposit after idle wait.")
                self.state = "deposit"
            end

        -- =============================================
        -- STATE: relocate (move to new mining area)
        -- =============================================
        elseif self.state == "relocate" then
            self.object:set_velocity({x = 0, y = 0, z = 0})
            set_animation(self, "stand")

            -- Calculate direction: extend further from chest
            local dir = vector.subtract(self.mining_center, self.chest_pos)
            dir.y = 0
            local len = vector.length(dir)
            if len > 0.1 then
                dir = vector.normalize(dir)
            else
                dir = {x = 1, y = 0, z = 0}
            end

            self.mining_center = {
                x = math.floor(self.mining_center.x + dir.x * 20 + 0.5),
                y = self.chest_pos.y,
                z = math.floor(self.mining_center.z + dir.z * 20 + 0.5),
            }

            -- Reset scan to top of new area
            self.scan_x = -7
            self.scan_y = 0
            self.scan_z = -7
            self.checked_chest = false

            if self.owner then
                minetest.chat_send_player(self.owner,
                    self.owner .. "'s Miner relocating to: " .. minetest.pos_to_string(self.mining_center))
            end

            free_miners.log_debug(self, "Relocating to: " .. minetest.pos_to_string(self.mining_center))
            self.state = "fly_to_mine"
        end
    end,
})
