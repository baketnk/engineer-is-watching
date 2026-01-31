-- Mod settings for Engineer Is Watching
-- These settings allow customization of the attention system behavior

data:extend({
	-- update interval, tweak for performance as needed
	{
		type = "int-setting",
		name = "eiw-update-interval",
		setting_type = "startup",
		default_value = 60,
		minimum_value = 1,
		maximum_value = 600,
	},
	-- Minimum attention value (startup - affects beacon generation)
	{
		type = "double-setting",
		name = "eiw-min-attention",
		setting_type = "startup",
		default_value = 0.2,
		minimum_value = 0.2,
		maximum_value = 1.0,
		order = "a-a",
	},

	-- Maximum attention value (startup - affects beacon generation)
	{
		type = "double-setting",
		name = "eiw-max-attention",
		setting_type = "startup",
		default_value = 1.2,
		minimum_value = 1.0,
		maximum_value = 3.0,
		order = "a-b",
	},

	-- Attention interval percentage (startup - affects tier count and beacon generation)
	{
		type = "double-setting",
		name = "eiw-attention-interval",
		setting_type = "startup",
		default_value = 5.0,
		minimum_value = 1.0,
		maximum_value = 20.0,
		order = "a-c",
		localised_description = {
			"",
			"Percentage interval between attention tiers. Lower values create more granular speed tiers but require more module prototypes. Default: 5% (21 tiers from 50% to 150%). At 1%: 101 tiers. At 10%: 11 tiers.",
		},
	},

	-- Attention decay rate (runtime-global - how fast attention decreases when unobserved)
	{
		type = "double-setting",
		name = "eiw-attention-rate",
		setting_type = "runtime-global",
		default_value = 0.005,
		minimum_value = 0.001,
		maximum_value = 1.0,
		order = "b-a",
	},

	-- Attention growth rate (runtime-global - how fast attention increases when observed)
	{
		type = "double-setting",
		name = "eiw-attention-growth-rate",
		setting_type = "runtime-global",
		default_value = 0.2,
		minimum_value = 0.01,
		maximum_value = 1.0,
		order = "b-b",
	},

	-- Delta ramp steps (runtime-global - number of updates to reach max growth/decay rate)
	-- unused at the moment, testing just on/off attention
	{
		type = "int-setting",
		name = "eiw-delta-ramp-steps",
		setting_type = "runtime-global",
		default_value = 5,
		minimum_value = 1,
		maximum_value = 20,
		order = "b-c",
	},

	-- Proximity detection radius (startup - affects initial setup)
	{
		type = "int-setting",
		name = "eiw-proximity-radius",
		setting_type = "startup",
		default_value = 16,
		minimum_value = 1,
		maximum_value = 208,
		order = "c-a",
		localised_description = {
			"",
			"Base proximity detection radius before technology research. Default: 16 tiles. Technology adds up to +48 tiles (6 levels × 8 tiles).",
		},
	},

	-- Factor-based attention targeting
	{
		type = "double-setting",
		name = "eiw-proximity-attention-target",
		setting_type = "startup",
		default_value = 1.0,
		minimum_value = 0.0,
		maximum_value = 1.0,
		order = "e-a",
		localised_description = {
			"",
			"Target attention when player is within proximity radius. Default: 1.0 (100%)",
		},
	},
	{
		type = "double-setting",
		name = "eiw-visibility-attention-target",
		setting_type = "startup",
		default_value = 1.0,
		minimum_value = 0.0,
		maximum_value = 1.0,
		order = "e-b",
		localised_description = {
			"",
			"Target attention when machine is visible on screen. Default: 1.0 (100%)",
		},
	},
	{
		type = "double-setting",
		name = "eiw-gui-attention-target",
		setting_type = "startup",
		default_value = 1.0,
		minimum_value = 0.0,
		maximum_value = 1.0,
		order = "e-c",
		localised_description = {
			"",
			"Target attention when machine GUI is open. Default: 1.0 (100%)",
		},
	},
	{
		type = "double-setting",
		name = "eiw-equipment-attention-target",
		setting_type = "startup",
		default_value = 1.0,
		minimum_value = 0.0,
		maximum_value = 1.0,
		order = "e-d",
		localised_description = {
			"",
			"Target attention when attention transmitter equipment is nearby. Default: 1.0 (100%)",
		},
	},
	{
		type = "bool-setting",
		name = "eiw-quantum-zeno-mode",
		setting_type = "startup",
		default_value = false,
		order = "e-e",
		localised_description = {
			"",
			"Invert the attention-speed relationship. When enabled, machines work SLOWER when watched (quantum zeno effect). Default: false (machines work faster when watched)",
		},
	},

	-- Debug: Make beacons selectable (for debugging and inspection)
	{
		type = "bool-setting",
		name = "eiw-beacon-debug-mode",
		setting_type = "startup",
		default_value = false,
		order = "d-a",
		localised_description = {
			"",
			"Makes attention beacons selectable and clickable for debugging. When disabled (default), beacons are completely non-interactive and won't interfere with gameplay. Requires restart to take effect.",
		},
	},

	-- Debug: Enable debug commands
	{
		type = "bool-setting",
		name = "eiw-enable-debug-commands",
		setting_type = "runtime-global",
		default_value = true,
		order = "d-b",
		localised_description = {
			"",
			"Enable debug commands like /attention-debug, /attention-show, etc. Can be toggled at runtime without restart.",
		},
	},
})
