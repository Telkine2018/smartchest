local mod_gui = require("mod-gui")

local chest_count = 8
local chest_prefix = "sc-chest-"
local chest_prefix_filter = "^sc%-chest%-"
local select_radius = settings.startup["sc-max-range"].value
local tool_filter = {}
local generic_chest_index = 1

local old_sc_button_name = "sc_button"
local sc_button_name = "smart_chest_button"

local tracing = true

local entity_filter = {}
local chest_filter = {}
local chest_filter_set = {}

local use_generic = settings.startup["sc-use-generic"].value

local on_init_gui

local log_index = 1
local function debug(msg)
    if not tracing then return end
    msg = "[" .. log_index .. "] " .. msg
    log_index = log_index + 1
    for _, player in pairs(game.players) do
        player.print(msg)
        log(msg)
    end
end

local function get_child(parent, name)
    for _, e in pairs(parent.children) do

        if e.name == name then return e end
        local child = get_child(e, name)
        if child then return child end
    end
    return nil
end

local close_filter_panel

local function get_id()
    local id = global.id or 1
    id = id + 1
    global.id = id

    return id
end

local function purge_with_name(player, name)
    local map = {}
    local force = player.force
    for _, surface in pairs(game.surfaces) do
        local chests = surface.find_entities_filtered {name = name}
        for _, c in pairs(chests) do map[c.link_id] = true end
    end
    for id = 1, global.id do
        local inv = force.get_linked_inventory(name, id)
        if inv and not map[id] then inv.destroy() end
    end
end

local function purge(player)
    for i = 1, chest_count do
        local name = chest_prefix .. i
        purge_with_name(player, name)
    end
end

local function get_vars(player)
    local players = global.players
    if not players then
        players = {}
        global.players = players
    end
    local vars = players[player.index]
    if not vars then
        vars = {}
        players[player.index] = vars
    end
    return vars
end

local local_purge_index = 1

local function get_genkey_id(genkey)
    local genkeys = global.genkeys
    if not genkeys then
        genkeys = {}
        global.genkeys = genkeys
    end

    local slot = genkeys[genkey]
	local id
    if not slot then
		local tick = game.tick
        local last_scan = global.genkeys_scan
        local period = 1 * 60 * 60
        if not last_scan then
            global.genkeys_scan = tick
        elseif tick - last_scan > period then
			local newkeys = {}
			for key, s in pairs(genkeys) do
				if s.tick and s.tick > tick - period then
					newkeys[key] = s
				end
			end
			genkeys = newkeys
			global.genkeys = newkeys
            global.genkeys_scan = tick
        end

        id = get_id()
		slot = { id=id, tick=tick }
        genkeys[genkey] = slot
    end

    return slot.id
end

local function process_merge(player, entities, selector, id)

    if not id then id = get_id() end
    local inv_to_clear = {}
    local chest_to_restore = {}
    local link_ids = {}

    local overflow =
        settings.get_player_settings(player.index)["sc-overflow-type"].value
    local abort_if_excess = overflow == "abort"
    local spill = overflow == "spill"
    local to_player = overflow == "to_player"
    local to_item = overflow == "to_item"
    local abort = false
    local processed = {}

    local limitations = {}
    local inv_map = {}
    local item_prototypes = game.item_prototypes
    for _, chest in pairs(entities) do
        if chest.valid and selector(chest) then
            local old_id = chest.link_id
            local key = chest.name .. "/" .. old_id
            if not processed[key] then

                table.insert(chest_to_restore, chest)
                local inv = chest.get_inventory(defines.inventory.chest)
                local bar = inv.get_bar()
                local content = inv.get_contents()
                processed[key] = {name = chest.name, id = old_id}
                link_ids[chest.unit_number] = chest.link_id
                if limitations[chest.name] == nil then
                    limitations[chest.name] = bar
                else
                    limitations[chest.name] =
                        math.min(limitations[chest.name], bar)
                end
                chest.link_id = id
                inv = chest.get_inventory(defines.inventory.chest)

                local has_non_item
                for name, count in pairs(content) do
                    local proto = item_prototypes[name]
                    if proto.type ~= "item" then
                        has_non_item = true
                        break
                    end
                end

                local function get_inv()
                    local inv = inv_map[chest.name]
                    if inv then return inv end
                    inv = game.create_inventory(2000)
                    inv_map[chest.name] = inv
                    return inv
                end

                if not has_non_item then
                    for name, count in pairs(content) do
                        local inv_count = inv.insert {
                            name = name,
                            count = count
                        }
                        if inv_count < count then
                            count = count - inv_count
                            if abort_if_excess then
                                abort = true
                                break
                            elseif spill then
                                player.surface.spill_item_stack(player.position,
                                                                {
                                    name = name,
                                    count = count
                                }, false, player.force, false)
                            elseif to_player then
                                local player_inv =
                                    player.get_inventory(defines.inventory
                                                             .character_main)
                                inv_count = player_inv.insert {
                                    name = name,
                                    count = count
                                }
                                if inv_count < count then
                                    player.surface.spill_item_stack(
                                        player.position, {
                                            name = name,
                                            count = count - inv_count
                                        }, false, player.force, false)
                                end
                            elseif to_item then
                                get_inv().insert {name = name, count = count}
                            end
                        end
                    end
                else
                    local src_inv = player.force.get_linked_inventory(
                                        chest.name, old_id)
                    for i = 1, #inv do
                        local stack = src_inv[i]
                        if stack.valid_for_read then
                            local inv_count = inv.insert(stack)
                            local count = stack.count
                            if inv_count < stack.count then
                                if abort_if_excess then
                                    abort = true
                                    break
                                elseif spill then
                                    stack.count = count - inv_count
                                    player.surface.spill_item_stack(
                                        player.position, stack, false,
                                        player.force, false)
                                elseif to_player then
                                    local player_inv =
                                        player.get_inventory(defines.inventory
                                                                 .character_main)
                                    stack.count = count - inv_count
                                    inv_count = player_inv.insert(stack)
                                    if inv_count < stack.count then
                                        stack.count = stack.count - inv_count
                                        player.surface.spill_item_stack(
                                            player.position, stack, false,
                                            player.force, false)
                                    end
                                elseif to_item then
                                    stack.count = count - inv_count
                                    get_inv().insert(stack)
                                end
                            end
                        end
                    end
                end
                if abort then break end
            else
                chest.link_id = id
            end
        end
    end

    if not abort then
        if to_item then
            local player_inv = player.get_inventory(defines.inventory
                                                        .character_main)
            local item_inv
            local temp = game.create_inventory(2000)
            for name, inv in pairs(inv_map) do
                item_inv = nil
                local item_name = "sc-chest-with-content-" ..
                                      string.sub(name, #"sc-chest-" + 1)
                for i = 1, #inv do
                    local src_stack = inv[i]
                    if not src_stack.valid_for_read or src_stack.count == 0 then
                        break
                    end
                    if not item_inv or not item_inv.can_insert(src_stack) then
                        local chest_stack = player_inv.find_item_stack(name)
                        if chest_stack then
                            chest_stack.count = chest_stack.count - 1
                            local item_stack, index = temp.find_empty_stack()
                            if item_stack then
                                temp.insert {name = item_name, count = 1}
                                item_stack = temp[index]
                                item_inv =
                                    item_stack.get_inventory(defines.inventory
                                                                 .item_main)
                            end
                        end
                    end
                    item_inv.insert(src_stack)
                end
                inv.destroy()
            end
            local item_stack, index = temp.find_empty_stack()
            for i = 1, index - 1 do
                if player_inv.insert(temp[i]) == 0 then
                    player.surface.spill_item_stack(player.position, temp[i],
                                                    false, player.force, false)
                end
            end
            temp.destroy()
        end
        local force = player.force
        for _, r in pairs(processed) do
            local inv = force.get_linked_inventory(r.name, r.id)
            inv.clear()
        end
        for name, limitation in pairs(limitations) do
            local inv = force.get_linked_inventory(name, id)
            inv.set_bar(limitation)
        end
    else
        player.print {"messages.abort_merge"}
        for _, chest in pairs(chest_to_restore) do
            chest.link_id = link_ids[chest.unit_number]
        end
    end

    purge_with_name(player, chest_prefix .. local_purge_index)
    local_purge_index = local_purge_index + 1
    if local_purge_index > chest_count then local_purge_index = 1 end

end

local function on_selected_area(event)

    local player = game.players[event.player_index]

    if event.item ~= "sc-merge-tool" then return end

    local entities = event.entities
    local selector = function(chest) return tool_filter[chest.name] end

    process_merge(player, entities, selector)
end

local function on_player_alt_selected_area(event)

    local player = game.players[event.player_index]

    if event.item ~= "sc-merge-tool" then return end

    local entities = event.entities

    local link_map = {}
    for _, chest in pairs(entities) do
        local chest_name = chest.name
        if chest.valid and tool_filter[chest_name] then
            local map = link_map[chest_name]
            if not map then
                map = {}
                link_map[chest_name] = map
            end
            map[chest.link_id] = true
        end
    end

    local names = {}
    for name, _ in pairs(link_map) do table.insert(names, name) end
    if #names == 0 then return player.print("no chest") end

    local area = event.area
    area.left_top.x = area.left_top.x - select_radius
    area.left_top.y = area.left_top.y - select_radius
    area.right_bottom.x = area.right_bottom.x + select_radius
    area.right_bottom.y = area.right_bottom.y + select_radius

    local entities = event.surface.find_entities_filtered {
        area = area,
        name = names,
        force = player.force
    }
    local selector = function(chest)
        return link_map[chest.name][chest.link_id]
    end

    process_merge(player, entities, selector)
end

script.on_event(defines.events.on_player_selected_area, on_selected_area)
script.on_event(defines.events.on_player_alt_selected_area,
                on_player_alt_selected_area)

local function add_to_reader_map(e)
    local index = e.unit_number % 20
    local reader_map = global.reader_map
    local index_map = reader_map[index]
    if not index_map then
        index_map = {}
        reader_map[index] = index_map
    end
    index_map[e.unit_number] = e
end

local function on_built(evt)
    local e = evt.created_entity or evt.entity
    if not e or not e.valid then return end

    local autolink
    local player_index

    local vars
    if e.name == "entity-ghost" and use_generic then
        local name = e.ghost_name
        if not chest_filter_set[name] then return end
        local surface = e.surface
        local force = e.force
        local position = e.position
        local link_id = e.link_id
        local tags = e.tags
        local genkey = link_id and (name .. "/" .. tostring(game.tick) .. "/" .. link_id)
        e.destroy()
        local r = surface.create_entity {
            name = "entity-ghost",
            inner_name = "sc-chest-core",
            force = force,
            position = position
        }
        r.tags = {link_id = link_id, sc_chest = name, genkey = genkey}
        return
    end

    local player_index = evt.player_index
    if player_index then
        vars = get_vars(game.players[player_index])
        autolink = vars.autolink
    end

    if (e.name == "sc-chest-core") then
        local position = e.position
        local surface = e.surface
        local name = chest_prefix .. generic_chest_index
        local force = e.force
        local tags = evt.tags
        if tags and tags.sc_chest then
            name = tags.sc_chest
        else
            if vars then
                local chest_number = vars.chest_number or 1
                name = chest_prefix .. chest_number
            end
        end
        e.destroy()
        e = surface.create_entity {
            name = name,
            position = position,
            force = force
        }
    end

    if chest_filter_set[e.name] then
        local id
        local genkey = evt.tags and evt.tags.genkey
        if genkey then
			id = get_genkey_id(genkey)
        elseif autolink then
            id = vars[e.name]
        end
        if not id then
            id = get_id()
            if autolink then vars[e.name] = id end
        end
        e.link_id = id
        local stack = evt.stack
        if stack and stack.is_item_with_inventory then

            local from_inv = stack.get_inventory(defines.inventory.item_main)
            local inv = e.get_inventory(defines.inventory.chest)
            for i = 1, #from_inv do
                local from_stack = from_inv[i]
                if from_stack.valid_for_read then
                    inv[i].transfer_stack(from_stack)
                end
            end
        end
    elseif e.name == "sc-chest-reader" then
        add_to_reader_map(e)
    end
end

local function process_reader(reader)

    local chest = global.reader_chest[reader.unit_number]

    if chest and not chest.valid then
        global.reader_chest[reader.unit_number] = nil
        chest = nil
    end

    if not chest then
        local direction = reader.direction
        local pos = reader.position
        if direction == defines.direction.north then
            pos.y = pos.y + 1
        elseif direction == defines.direction.south then
            pos.y = pos.y - 1
        elseif direction == defines.direction.east then
            pos.x = pos.x - 1
        elseif direction == defines.direction.west then
            pos.x = pos.x + 1
        end

        local entities = reader.surface.find_entities_filtered {
            position = pos,
            radius = 0.25,
            type = "linked-container"
        }
        if #entities == 0 then return end
        chest = entities[1]
        global.reader_chest[reader.unit_number] = chest
    end

    local inv = chest.get_inventory(defines.inventory.chest)
    local content = inv.get_contents()
    local cb = reader.get_control_behavior()
    if not cb then return end
    local max = cb.signals_count
    local index = 1
    local parameters = {}
    for name, count in pairs(content) do
        if index > max then break end
        table.insert(parameters, {
            signal = {type = "item", name = name},
            count = count,
            index = index
        })
        index = index + 1
    end
    cb.parameters = parameters
end

local function on_tick()
    local index = game.tick % 20
    local readers = global.reader_map[index]

    if readers then
        for id, reader in pairs(readers) do
            if not reader.valid then
                readers[id] = nil
                global.reader_chest[id] = nil
                return
            end
            process_reader(reader)
        end
    end
end

for i = 1, chest_count do
    local name = chest_prefix .. i
    table.insert(entity_filter, {filter = 'name', name = name})
    table.insert(chest_filter, {filter = 'name', name = name})
    chest_filter_set[name] = true
    tool_filter[name] = true
end

table.insert(entity_filter, {filter = 'name', name = "sc-chest-reader"})
table.insert(entity_filter, {filter = 'name', name = "sc-chest-core"})
table.insert(entity_filter, {filter = 'name', name = "entity-ghost"})

local function on_configuration_changed(e)

    local changes = e.mod_changes["smartchest"]
    if changes then

        if not global.reader_chest then global.reader_chest = {} end
        if not global.reader_map then global.reader_map = {} end
        if global.readers then
            for _, reader in pairs(global.readers) do
                add_to_reader_map(reader)
            end
            global.readers = nil
        end
        if changes.old_version == "0.0.1" and changes.new_version then
            for _, force in pairs(game.forces) do
                local tech = force.technologies['sc-chest']
                if tech.researched then
                    tech.researched = false
                    tech.researched = true
                end
            end
        end

        for _, player in pairs(game.players) do
            close_filter_panel(player)
            get_vars(player).sc_show_linked_rectangle = true
            
            local button_flow = mod_gui.get_button_flow(player)
            local b = button_flow[old_sc_button_name]
            if b then
                b.destroy()
            end
        end

        on_init_gui()
    end
end

script.on_configuration_changed(on_configuration_changed)

script.on_event(defines.events.on_built_entity, on_built, entity_filter)
script.on_event(defines.events.on_robot_built_entity, on_built, entity_filter)
script.on_event(defines.events.script_raised_built, on_built, entity_filter)
script.on_event(defines.events.script_raised_revive, on_built, entity_filter)
script.on_event(defines.events.on_tick, on_tick)

local function on_init()
    global.reader_chest = {}
    global.reader_map = {}
end

script.on_init(on_init)

local function on_mined_entity(e)
    local entity = e.entity

    local entities = entity.surface.find_entities_filtered {
        position = entity.position,
        radius = select_radius,
        name = entity.name,
        force = entity.force
    }
    local link_id = entity.link_id
    for _, c in ipairs(entities) do
        if c.link_id == link_id and c ~= entity then return end
    end

    local inv = entity.get_inventory(defines.inventory.chest)
    local content = inv.get_contents()

    if next(content) == nil then return end

    local item_prototypes = game.item_prototypes
    local export_as_item = settings.global["sc-mining-type"].value ==
                               "item_with_tag"

    local to_inv
    if export_as_item then

        local chest_index = tonumber(string.sub(entity.name, #"sc-chest-" + 1))
        e.buffer.clear()
        e.buffer.insert {
            name = "sc-chest-with-content-" .. chest_index,
            count = 1
        }
        local stack = e.buffer[1]
        to_inv = stack.get_inventory(defines.inventory.item_main)
    else
        to_inv = e.buffer
    end

    local has_non_item = false
    for name, count in pairs(content) do
        local proto = item_prototypes[name]
        if proto.type ~= "item" then
            has_non_item = true
            break
        end
    end
    if not has_non_item then
        for name, count in pairs(content) do
            to_inv.insert {name = name, count = count}
        end
    else
        for i = 1, #inv do
            local stack = inv[i]
            if stack.valid_for_read then to_inv.insert(stack) end
        end
    end
    inv.clear()
end

script.on_event(defines.events.on_player_mined_entity, on_mined_entity,
                chest_filter)
script.on_event(defines.events.on_robot_mined_entity, on_mined_entity,
                chest_filter)

-------------------------------------------------------------------------------------

local tints = {
    {1, 0, 0, 1}, {1, 0.5, 0, 1}, {1, 1, 0, 1}, {1, 0, 1, 1}, {0, 1, 0, 1},
    {0.5, 0, 0.25, 1}, {0, 0, 1, 1}, {0, 1, 1, 1}
}

local function on_selected_entity_changed(e)

    local player = game.players[e.player_index]
    local entity = player.selected

    local vars = get_vars(player)
    if vars.previous_selected_graphics then
        for _, id in ipairs(vars.previous_selected_graphics) do
            rendering.destroy(id)
        end
        vars.previous_selected_graphics = nil
    end

    if not entity or not entity.valid or not chest_filter_set[entity.name] then
        return
    end

    local connected_list = entity.surface.find_entities_filtered {
        name = entity.name,
        position = entity.position,
        radius = select_radius,
        force = player.force
    }

    vars.previous_selected_graphics = {}
    local link_id = entity.link_id
    local link_index = tonumber(string.sub(entity.name, #chest_prefix + 1))
    local color = tints[link_index]
    local surface = entity.surface
    local min, max
    local count = 0
    local radius = 0.25
    local width = 4
    local offset = 0.2
    for _, connected in ipairs(connected_list) do

        if link_id == connected.link_id then

            local pos = connected.position
            if not min then
                min = {x = pos.x, y = pos.y}
                max = {x = pos.x, y = pos.y}
            else
                if pos.x < min.x then min.x = pos.x end
                if pos.y < min.y then min.y = pos.y end
                if pos.x > max.x then max.x = pos.x end
                if pos.y > max.y then max.y = pos.y end
            end

            if entity ~= connected then
                local function add_mark(pos)
                    local id = rendering.draw_circle {
                        color = color,
                        radius = radius,
                        width = width,
                        surface = surface,
                        player = player,
                        target = {pos.x - offset, pos.y}
                    }
                    table.insert(vars.previous_selected_graphics, id)
                    local id = rendering.draw_circle {
                        color = color,
                        radius = radius,
                        width = width,
                        surface = surface,
                        player = player,
                        target = {pos.x + offset, pos.y}
                    }
                    table.insert(vars.previous_selected_graphics, id)
                end

                add_mark(pos)
                count = count + 1
            end
        end
    end

    if vars.sc_show_linked_rectangle and count >= 1 then
        local id = rendering.draw_rectangle {
            color = color,
            surface = surface,
            player = player,
            width = 3,
            left_top = {min.x - 1, min.y - 1},
            right_bottom = {max.x + 1, max.y + 1}
        }
        table.insert(vars.previous_selected_graphics, id)
    end
end

script.on_event(defines.events.on_selected_entity_changed,
                on_selected_entity_changed)

-------------------------------------------------------------------------------------

local function create_sc_button(player)
    local button_flow = mod_gui.get_button_flow(player)
    local button = button_flow.add {
        type = "sprite-button",
        name = sc_button_name,
        sprite = "item/sc-chest-1"
    }
    button.style.width = 40
    button.style.height = 40
end

on_init_gui = function()
    for _, player in pairs(game.players) do
        local button_flow = mod_gui.get_button_flow(player)
        local button = button_flow[sc_button_name]
        if button then button.destroy() end
        if player.force.technologies["sc-chest"].researched == true then
            create_sc_button(player)
        end
    end
end

close_filter_panel = function(player)

    local panel = player.gui.left.sc_filter_panel
    if panel then panel.destroy() end
end

local generic_default_size = {height = 40, with = 40}
local generic_selected_size = {height = 50, with = 50}

local function create_filter_panel(player)

    close_filter_panel(player)

    local panel = player.gui.left.add {
        type = "frame",
        name = "sc_filter_panel",
        direction = "vertical"
    }

    local titlebar = panel.add {type = "flow", direction = "horizontal"}
    local title = titlebar.add {
        type = "label",
        style = "caption_label",
        caption = {"smart_space_panel.title"}
    }
    local handle = titlebar.add {
        type = "empty-widget",
        style = "draggable_space"
    }

    handle.style.horizontally_stretchable = true
    handle.style.top_margin = 2
    handle.style.height = 24
    handle.style.width = 120

    local flow_buttonbar = titlebar.add {
        type = "flow",
        direction = "horizontal"
    }
    flow_buttonbar.style.top_margin = 4

    local closeButton = flow_buttonbar.add {
        type = "sprite-button",
        name = "sc_close_filter",
        style = "frame_action_button",
        sprite = "utility/close_white",
        mouse_button_filter = {"left"}
    }
    closeButton.style.left_margin = 2

    for i = 1, 8 do
        local flow = panel.add {type = "flow", direction = "horizontal"}
        local name = chest_prefix .. i
        local state = tool_filter[name] == true
        -- flow.add{type="sprite", sprite="item/" .. name}
        local b = flow.add {
            type = "sprite-button",
            name = "sc_generic_" .. i,
            sprite = "item/" .. name,
            mouse_button_filter = {"left"}
        }
        flow.add {
            type = "checkbox",
            name = name,
            caption = {"entity-name." .. name},
            state = state
        }

    end

    panel.add {type = "line"}
    local vars = get_vars(player)
    panel.add {
        type = "checkbox",
        name = "sc-autolink",
        caption = {"smart_space_panel.sc_autolink"},
        state = (vars.autolink == true)
    }
    panel.add {
        type = "checkbox",
        name = "sc_show_linked_rectangle",
        caption = {"smart_space_panel.sc_show_linked_rectangle"},
        state = (vars.sc_show_linked_rectangle == true)
    }

    local index = get_vars(player).chest_number or 1
    local b = get_child(player.gui.top, sc_button_name)
    if b then
        b.sprite = "item/sc-chest-" .. index
        b.clicked_sprite = b.sprite
    end
end

local function select_chest(player, index, clear_id)
    if not index then return end

    local b = get_child(player.gui.top, sc_button_name)
    if b then 
        b.sprite = "item/sc-chest-" .. index
        b.clicked_sprite = b.sprite
    end
    local vars = get_vars(player)
    vars.chest_number = index
    if clear_id then vars["sc-chest-" .. index] = nil end
end

local function set_cursor_to_chest(player, chest_name)
    local inv = player.get_main_inventory()
    if not chest_name then chest_name = "sc-chest-core" end
    if inv.remove {name = chest_name, count = 1} == 1 then
        inv.insert(player.cursor_stack)
        player.cursor_stack.clear()
        player.cursor_stack.set_stack {name = chest_name, count = 1}
        return true
    end

    return false
end

local function on_gui_click(event)

    local player = game.players[event.player_index]
    local element = event.element
    local element_name = element.name
    if element_name == sc_button_name then
        if player.gui.left.sc_filter_panel then
            close_filter_panel(player)
        else
            create_filter_panel(player)
        end
    elseif element_name == "sc_close_filter" then
        close_filter_panel(player)
    elseif element_name:find("^sc_generic_") then
        local index = tonumber(element_name:sub(string.len("sc_generic_") + 1))

        select_chest(player, index, true)
        if not set_cursor_to_chest(player) then
            set_cursor_to_chest(player, chest_prefix .. index)
        end
    end
end

local function on_gui_checked_state_changed(event)
    local player = game.players[event.player_index]
    local name = event.element.name
    if chest_filter_set[name] then
        tool_filter[name] = event.element.state
    elseif name == "sc-autolink" then
        get_vars(player).autolink = event.element.state
    elseif name == "sc_show_linked_rectangle" then
        get_vars(player).sc_show_linked_rectangle = event.element.state
    end
end

script.on_event(defines.events.on_gui_click, on_gui_click)
script.on_event(defines.events.on_gui_checked_state_changed,
                on_gui_checked_state_changed)

local function on_research_finished(e)
    if e.research.name == "sc-chest" then on_init_gui(); end
end

script.on_event(defines.events.on_research_finished, on_research_finished)

local function on_player_pipette(event)
    local player = game.players[event.player_index]
    local name = event.item.name

    local prefix = chest_prefix
    if not name:find(chest_prefix_filter) or name == "sc-chest-reader" then
        return
    end

    local index = tonumber(name:sub(string.len(chest_prefix) + 1))
    select_chest(player, index)

    if use_generic then
        if event.used_cheat_mode then player.cursor_stack.clear() end
        set_cursor_to_chest(player)
    end

    local vars = get_vars(player)
    if vars.autolink then
        local selected = player.selected
        if selected and selected.name:find(chest_prefix_filter) then
            vars[selected.name] = selected.link_id
        end
    end
end

script.on_event(defines.events.on_player_pipette, on_player_pipette)

local function on_pre_entity_settings_pasted(evt)
    local source = evt.source
    local dest = evt.destination

    if not source.name:find(chest_prefix_filter) or
        not dest.name:find(chest_prefix_filter) then return end

    if source.name == dest.name then
        local player = game.players[evt.player_index]
        process_merge(player, {dest}, function() return true end, source.link_id)
        get_vars(player)[source.name] = source.link_id
    end
end

script.on_event(defines.events.on_pre_entity_settings_pasted,
                on_pre_entity_settings_pasted)

