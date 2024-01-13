

for i = 1, 8 do
	data:extend({
		{
			type = "int-setting",
			name = "sc-chest-slot-" .. i,
			setting_type = "startup",
			default_value = 80,
			minimum_value=1,
			maximum_value=2000
		}
	})
end

local allowed_values = {"to_player"}
local def_value = "item_with_tag"

if not mods["space-exploration"] then
	table.insert(allowed_values, "item_with_tag")
else
	def_value = "to_player"
end

data:extend({
	{
		type = "string-setting",
		name = "sc-overflow-type",
		setting_type = "runtime-per-user",
		default_value = "destroy",
		allowed_values = {"abort", "destroy","spill", "to_player", "to_item" }
	},
	{
		type = "string-setting",
		name = "sc-mining-type",
		setting_type = "runtime-global",
		default_value = def_value,
		allowed_values = allowed_values
	},
	{
		type = "bool-setting",
		name = "sc-use-generic",
		setting_type = "startup",
		default_value = false
	},
	{
		type = "int-setting",
		name = "sc-reader-count",
		setting_type = "startup",
		default_value = 20,
		minimum_value=20,
		maximum_value=128
	},
	{
		type = "int-setting",
		name = "sc-max-range",
		setting_type = "startup",
		default_value = 200,
		minimum_value=100,
		maximum_value=20000
	}
})
