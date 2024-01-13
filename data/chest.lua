---@diagnostic disable: undefined-field

local tint_core = { 0.6, 0.6, 0.6, 1 }

local use_generic = settings.startup["sc-use-generic"].value

data:extend
{
	{
		type = "item",
		name = "sc-chest-core",
		icon_size = 64,
		icons = {
			{
				icon = "__smartchest__/graphics/icons/chest.png",
			},
			{
				icon = "__smartchest__/graphics/icons/chest-mask.png",
				tint = tint_core
			}
		},
		icon_mipmaps = 4,
		subgroup = "storage",
		order = "s[mart-chest-core]",
		stack_size = 50,
		place_result = "sc-chest-core"
	}
	, {
		type = "recipe",
		name = "sc-chest-core",
		enabled = false,
		ingredients =
		{
			{ "iron-plate", 20 },
			{ "steel-plate", 10 },
			{ "electronic-circuit", 5 },
			{ "copper-cable", 10 }
		},
		result = "sc-chest-core"
	}

}


local chest_core = table.deepcopy(data.raw["linked-container"]["linked-chest"])

chest_core.name = "sc-chest-core"
chest_core.icon_size = 64
chest_core.icons = {
	{
		icon = "__smartchest__/graphics/icons/chest.png",
	},
	{
		icon = "__smartchest__/graphics/icons/chest-mask.png",
		tint = tint_core
	}
}
chest_core.inventory_size = 8
chest_core.allow_copy_paste = false
chest_core.minable = { hardness = 0.2, mining_time = 0.2, result = chest_core.name }
chest_core.gui_mode = "none"

chest_core.picture.layers[1].filename = "__smartchest__/graphics/entity/chest.png"
chest_core.picture.layers[1].hr_version.filename = "__smartchest__/graphics/entity/hr-chest.png"

data:extend
{
	chest_core
}

local steel_chest = table.deepcopy(data.raw["container"]["steel-chest"])

local function create_chest(index, tint, is_core)

	local chest_data   = table.deepcopy(data.raw["linked-container"]["linked-chest"])
	local name         = "sc-chest-" .. index
	local content_name = "sc-chest-with-content-" .. index

	chest_data.name = name
	chest_data.icon_size = 64
	chest_data.icons = {
		{
			icon = "__smartchest__/graphics/icons/chest.png",
		},
		{
			icon = "__smartchest__/graphics/icons/chest-mask.png",
			tint = tint
		}
	}
	chest_data.icon_mipmaps = 4
	chest_data.inventory_size = settings.startup["sc-chest-slot-" .. index].value

	chest_data.allow_copy_paste = true
	chest_data.minable = { hardness = 0.2, mining_time = 0.2, result = (use_generic and "sc-chest-core") or name }
	chest_data.gui_mode = "none"
	chest_data.inventory_type = "with_filters_and_bar"

	chest_data.circuit_connector_sprites = steel_chest.circuit_connector_sprites
	chest_data.circuit_wire_connection_point = steel_chest.circuit_wire_connection_point
	chest_data.circuit_wire_max_distance = steel_chest.circuit_wire_max_distance

	chest_data.picture.layers[1].filename = "__smartchest__/graphics/entity/chest.png"
	chest_data.picture.layers[1].hr_version.filename = "__smartchest__/graphics/entity/hr-chest.png"

	local color_layer = table.deepcopy(chest_data.picture.layers[1])
	table.insert(chest_data.picture.layers, 2, color_layer)

	color_layer.tint = tint
	color_layer.apply_runtime_tint = true
	color_layer.filename = "__smartchest__/graphics/entity/chest-mask.png"

	color_layer.hr_version.tint = tint
	color_layer.hr_version.apply_runtime_tint = true
	color_layer.hr_version.filename = "__smartchest__/graphics/entity/hr-chest-mask.png"

	-- log(serpent.block(chest_data))

	local inv_def = nil
	if not mods["space-exploration"] then
		inv_def = {
			type = "item-with-inventory",
			name = content_name,
			icon_size = 64,
			icons = {
				{
					icon = "__smartchest__/graphics/icons/chest-with-content.png",
				},
				{
					icon = "__smartchest__/graphics/icons/chest-mask.png",
					tint = tint
				}
			},
			icon_mipmaps = 4,
			subgroup = "storage",
			order = "s[mart-chest-" .. index .. "]",
			place_result = name,
			flags = { "hidden", "not-stackable" },
			stack_size = 1,
			inventory_size = settings.startup["sc-chest-slot-" .. index].value,
			extends_inventory_by_default = true
		}
	end

	local def =
	{
		chest_data,
		{
			type = "item",
			name = name,
			icon_size = 64,
			icons = {
				{
					icon = "__smartchest__/graphics/icons/chest.png",
				},
				{
					icon = "__smartchest__/graphics/icons/chest-mask.png",
					tint = tint
				}
			},
			icon_mipmaps = 4,
			subgroup = "storage",
			order = "s[mart-chest-" .. index .. "]",
			place_result = name,
			stack_size = 50
		}
	}
	if (inv_def) then
		table.insert(def, inv_def)
	end

	if (not use_generic) then

		table.insert(def, {
			type = "recipe",
			name = name,
			enabled = false,
			ingredients =
			{
				{ "iron-plate", 20 },
				{ "steel-plate", 10 },
				{ "electronic-circuit", 5 },
				{ "copper-cable", 10 }
			},
			result = name
		})

		table.insert(def,
			{
				type = "recipe",
				name = name .. "-core",
				enabled = false,
				ingredients =
				{
					{ "sc-chest-core", 1 }
				},
				result = name
			})
	end

	data:extend(def)
end

local tints = {
	{ 1, 0, 0, 1 },
	{ 1, 0.5, 0, 1 },
	{ 1, 1, 0, 1 },
	{ 1, 0, 1, 1 },
	{ 0, 1, 0, 1 },
	{ 0.5, 0, 0.25, 1 },
	{ 0, 0, 1, 1 },
	{ 0, 1, 1, 1 }
}

local recipe_effects = {}
local names = {}
for i = 1, #tints do
	create_chest(i, tints[i])
	local name = "sc-chest-" .. i
	table.insert(names, name)
	if not use_generic then
		table.insert(recipe_effects, { type = "unlock-recipe", recipe = name })
		table.insert(recipe_effects, { type = "unlock-recipe", recipe = name .. "-core" })
	end
end
table.insert(recipe_effects, { type = "unlock-recipe", recipe = "sc-chest-core" })
table.insert(recipe_effects, { type = "unlock-recipe", recipe = "sc-chest-reader" })

data:extend(
	{
		{
			type = "technology",
			name = "sc-chest",
			icon = "__smartchest__/graphics/icons/chest.png",
			icon_size = 64,
			effects = recipe_effects,
			prerequisites = { "steel-processing", "electronics" },
			unit =
			{
				count = 100,
				ingredients =
				{
					{ "automation-science-pack", 1 },
					{ "logistic-science-pack", 1 }
				},
				time = 10
			},
			order = "a-b-b"
		}
	}
)


local merge_tool = {

	type = "selection-tool",
	name = "sc-merge-tool",
	icon = "__smartchest__/graphics/icons/merge-tool.png",
	icon_size = 32,
	selection_color = { r = 1, g = 0, b = 0 },
	alt_selection_color = { r = 1, g = 1, b = 0 },
	selection_mode = { "same-force", "buildable-type" },
	alt_selection_mode = { "same-force", "buildable-type" },
	selection_cursor_box_type = "entity",
	alt_selection_cursor_box_type = "entity",
	flags = { "hidden", "not-stackable", "only-in-cursor", "spawnable" },
	subgroup = "other",
	stack_size = 1,
	entity_filters = names,
	alt_entity_filters = names,
	stackable = false,
	show_in_library = false
}

data:extend { merge_tool }

data:extend
{
	{
		type = "shortcut",
		name = "sc-chest-shortcut",
		order = "h[hotkeys]-s[c-chest]",
		action = "spawn-item",
		technology_to_unlock = "sc-chest",
		item_to_spawn = "sc-merge-tool",
		icon =
		{
			filename = "__smartchest__/graphics/icons/merge-tool-x32.png",
			priority = "extra-high-no-scale",
			size = 32,
			scale = 1,
			flags = { "gui-icon" }
		},
		small_icon =
		{
			filename = "__smartchest__/graphics/icons/merge-tool-x24.png",
			priority = "extra-high-no-scale",
			size = 24,
			scale = 1,
			flags = { "gui-icon" }
		},
	},
}

local reader = table.deepcopy(data.raw["constant-combinator"]["constant-combinator"])
reader.name = "sc-chest-reader"
reader.icon_size = 64
reader.icon = "__smartchest__/graphics/icons/reader.png"
reader.item_slot_count = settings.startup["sc-reader-count"].value
reader.minable = { hardness = 0.2, mining_time = 0.2, result = "sc-chest-reader" }

for _, dir in pairs(reader.sprites) do
	dir.layers[1].filename = "__smartchest__/graphics/entity/reader.png"
	dir.layers[1].hr_version.filename = "__smartchest__/graphics/entity/hr-reader.png"
	dir.layers[2].filename = "__smartchest__/graphics/entity/reader-shadow.png"
	dir.layers[2].hr_version.filename = "__smartchest__/graphics/entity/hr-reader-shadow.png"
end

data:extend
{
	reader,
	{
		type = "item",
		name = "sc-chest-reader",
		icon_size = 64,
		icons = {
			{
				icon = "__smartchest__/graphics/icons/reader.png",
			},
		},
		icon_mipmaps = 4,
		subgroup = "storage",
		order = "s[mart-chest-reader]",
		stack_size = 50,
		place_result = "sc-chest-reader"
	}
	, {
		type = "recipe",
		name = "sc-chest-reader",
		enabled = false,
		ingredients =
		{
			{ "iron-plate", 5 },
			{ "electronic-circuit", 5 },
			{ "copper-cable", 5 }
		},
		result = "sc-chest-reader"
	}
}
