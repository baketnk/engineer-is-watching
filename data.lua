-- Engineer Is Watching - Data Stage Prototypes
-- Creates hidden beacons and modules for the attention speed system

-- Calculate tier system dynamically from startup settings
local function calculate_tier_system()
  local min = settings.startup["eiw-min-attention"].value * 100  -- 0.5 → 50
  local max = settings.startup["eiw-max-attention"].value * 100  -- 1.5 → 150
  local interval = settings.startup["eiw-attention-interval"].value

  local tier_count = math.floor((max - min) / interval) + 1
  local tiers = {}
  local tier_map = {}

  for i = 1, tier_count do
    local tier_value = min + (i - 1) * interval
    tiers[i] = tier_value
    tier_map[tier_value] = i
  end

  return {
    tiers = tiers,
    tier_map = tier_map,
    tier_count = tier_count,
    interval = interval
  }
end

-- Initialize tier system
local tier_system = calculate_tier_system()
local attention_tiers = tier_system.tiers
local tier_map = tier_system.tier_map

-- Create hidden modules with speed effects for each tier
for _, tier in ipairs(attention_tiers) do
  local speed_modifier = (tier - 100) / 100  -- e.g., 50 -> -0.5, 150 -> +0.5

  local module_prototype = {
    type = "module",
    name = "eiw-attention-module-" .. tier,
    localised_name = {"", "Attention Module (", tostring(tier), "%)"},
    localised_description = "Hidden module for Engineer Is Watching attention system",
    icon = "__base__/graphics/icons/speed-module.png",
    icon_size = 64,
    subgroup = "module",
    category = "eiw-attention",  -- Custom category, won't appear in normal module slots
    tier = tier_map[tier],  -- Sequential 1-11 for sprite variation
    art_style = "eiw-attention",  -- Custom art style for matching with beacon visualization
    order = "z[eiw]-" .. tier,
    stack_size = 1,
    effect = {
      speed = speed_modifier
    },
    -- Hide from player
    hidden = true,
    hidden_in_factoriopedia = true
  }

  data:extend({module_prototype})
end

-- Generate sprite prototypes for indicators
-- Sprite sheets have 101 frames (3232px / 32px per frame)
local sprite_frame_count = 101
for frame_num = 1, sprite_frame_count do
  data:extend({
    {
      type = "sprite",
      name = "eiw-indicator-rect-" .. frame_num,
      filename = "__engineer-is-watching__/assets/indicators/rectangular-sprites.png",
      width = 32,
      height = 32,
      x = (frame_num - 1) * 32,
      y = 0,
      priority = "extra-high"
    },
    {
      type = "sprite",
      name = "eiw-indicator-circle-" .. frame_num,
      filename = "__engineer-is-watching__/assets/indicators/circular-sprites.png",
      width = 32,
      height = 32,
      x = (frame_num - 1) * 32,
      y = 0,
      priority = "extra-high"
    }
  })
end

-- Single beacon prototype with module-based visualization
-- Visual appearance changes based on the inserted module's tier (1-11)
-- Check debug mode setting
local beacon_debug_mode = settings.startup["eiw-beacon-debug-mode"].value

local beacon_prototype = {
  type = "beacon",
  name = "eiw-attention-beacon",  -- No tier suffix
  localised_name = "Attention Beacon",
  localised_description = "Hidden beacon for Engineer Is Watching attention system. Visual appearance changes based on attention level.",
  icon = "__base__/graphics/icons/beacon.png",
  icon_size = 64,

  -- Flags: conditionally add "not-selectable-in-game" based on debug mode
  flags = beacon_debug_mode and {
    "placeable-off-grid",
    "not-on-map",
    "not-blueprintable",
    "not-deconstructable",
    "not-upgradable",
    "no-automated-item-removal",  -- Prevents inserters from extracting modules
    "no-automated-item-insertion",  -- Prevents inserters from inserting items
    "hide-alt-info",
    "not-in-kill-statistics"
  } or {
    "placeable-off-grid",
    "not-on-map",
    "not-blueprintable",
    "not-deconstructable",
    "not-upgradable",
    "not-selectable-in-game",  -- Only when not in debug mode
    "no-automated-item-removal",  -- Prevents inserters from extracting modules
    "no-automated-item-insertion",  -- Prevents inserters from inserting items
    "hide-alt-info",
    "not-in-kill-statistics"
  },

  -- Selectable based on debug mode
  selectable_in_game = beacon_debug_mode,

  -- No collision - always empty
  collision_mask = {layers = {}},
  collision_box = {{0, 0}, {0, 0}},

  -- Selection box: empty unless in debug mode
  selection_box = beacon_debug_mode and {{-0.5, -0.5}, {0.5, 0.5}} or {{0, 0}, {0, 0}},

  -- Beacon mechanics
  supply_area_distance = 1,  -- Minimum viable distance to affect adjacent tile
  distribution_effectivity = 1,  -- Full module effect (no reduction)
  module_slots = 1,  -- Exactly one module slot for our hidden module

  -- Only accept our attention modules
  allowed_module_categories = {"eiw-attention"},
  allowed_effects = {"speed"},

  -- Count separately from player beacons so we don't interfere with their beacon setups
  beacon_counter = "same_type",

  -- Profile: first beacon has full effect, subsequent beacons have zero effect
  -- This prevents stacking issues if multiple attention beacons somehow get placed
  profile = {1, 0},

  -- Energy: void energy source (no power required)
  energy_source = {
    type = "void"
  },
  energy_usage = "1W",  -- Minimal energy usage

  -- Graphics: module visualization system changes sprite based on inserted module tier
  graphics_set = {
    draw_animation_when_idle = false,
    draw_light_when_idle = false,
    random_animation_offset = false,
    module_icons_suppressed = false,  -- Show module visualization

    -- Module visualization: changes sprite based on inserted module tier
    module_visualisations = {
      {
        art_style = "eiw-attention",  -- Matches module art_style
        use_for_empty_slots = false,
        tier_offset = 0,  -- tier 1 → variation 1

        slots = {
          {  -- Slot 1 (our only slot)
            {  -- Layer 1 - the tier sprite
              has_empty_slot = false,
              render_layer = "object",
              pictures = {
                sheet = {
                  filename = "__engineer-is-watching__/assets/beacon/attention-tier-sprites.png",
                  width = 32,
                  height = 32,
                  variation_count = tier_system.tier_count,
                  scale = 0.5,
                  shift = {0, 0}
                }
              }
            }
          }
        }
      }
    },

    animation_list = {}
  },

  -- Not hidden (we want visual feedback)
  hidden = false,
  hidden_in_factoriopedia = false
}

data:extend({beacon_prototype})

-- Create custom module category so attention modules don't appear in normal machines
data:extend({
  {
    type = "module-category",
    name = "eiw-attention"
  }
})

-- Create attention transmitter equipment for testing
-- This equipment can be placed in vehicle grids (spidertrons, tanks, etc.) to act as attention source
data:extend({
  {
    type = "battery-equipment",
    name = "eiw-attention-transmitter",
    localised_name = "Attention Transmitter",
    localised_description = "Nearby machines work faster when this equipment is installed. Used for testing attention mechanics with vehicles.",
    sprite = {
      filename = "__base__/graphics/equipment/battery-mk2-equipment.png",
      width = 64,
      height = 128,
      priority = "medium"
    },
    shape = {
      width = 1,
      height = 2,
      type = "full"
    },
    energy_source = {
      type = "electric",
      buffer_capacity = "100MJ",
      usage_priority = "tertiary"
    },
    categories = {"armor"}
  },
  {
    type = "item",
    name = "eiw-attention-transmitter",
    localised_name = "Attention Transmitter",
    localised_description = "Nearby machines work faster when this equipment is installed. Used for testing attention mechanics with vehicles.",
    icon = "__base__/graphics/icons/battery-mk2-equipment.png",
    icon_size = 64,
    place_as_equipment_result = "eiw-attention-transmitter",
    subgroup = "equipment",
    order = "z[eiw]-a[attention-transmitter]",
    stack_size = 20
  },
  {
    type = "recipe",
    name = "eiw-attention-transmitter",
    enabled = false,  -- Unlocked by technology
    ingredients = {
      {type = "item", name = "processing-unit", amount = 5},
      {type = "item", name = "electronic-circuit", amount = 20},
      {type = "item", name = "steel-plate", amount = 10}
    },
    results = {{type = "item", name = "eiw-attention-transmitter", amount = 1}}
  }
})

-- Create technology to unlock the attention transmitter
data:extend({
  {
    type = "technology",
    name = "eiw-attention-transmitter",
    localised_name = "Attention Transmitter",
    localised_description = "Develop equipment that mimics engineer presence to boost nearby machine productivity. When installed in vehicle equipment grids, nearby machines will maintain higher attention levels.",
    icon = "__base__/graphics/technology/effect-transmission.png",
    icon_size = 256,
    effects = {
      {
        type = "unlock-recipe",
        recipe = "eiw-attention-transmitter"
      }
    },
    prerequisites = {"effect-transmission"},  -- Requires beacon technology
    unit = {
      count = 100,
      ingredients = {
        {"automation-science-pack", 1},
        {"logistic-science-pack", 1},
        {"chemical-science-pack", 1},
        {"production-science-pack", 1}
      },
      time = 30
    },
    order = "i-h-a"
  }
})

-- Create infinite technologies for attention system upgrades
data:extend({
  -- Technology 1: Attention Floor (increases minimum attention)
  {
    type = "technology",
    name = "eiw-attention-floor",
    localised_name = "Attention Floor",
    localised_description = "Machines maintain higher minimum attention when unobserved. Each level increases the minimum attention floor by 0.05.",
    icon = "__base__/graphics/technology/productivity-module-3.png",  -- Placeholder icon
    icon_size = 256,
    effects = {},  -- Custom effect handled in control.lua
    prerequisites = {},
    unit = {
      count_formula = "2^(L-1)*1000",
      ingredients = {
        {"automation-science-pack", 1},
        {"logistic-science-pack", 1},
        {"chemical-science-pack", 1},
        {"production-science-pack", 1}
      },
      time = 60
    },
    max_level = "infinite",
    upgrade = true,
    order = "i-h-b"
  },

  -- Technology 2: Attention Ceiling (increases maximum attention)
  {
    type = "technology",
    name = "eiw-attention-ceiling",
    localised_name = "Attention Ceiling",
    localised_description = "Machines reach higher peak attention when observed. Each level increases the maximum attention ceiling by 0.05.",
    icon = "__base__/graphics/technology/speed-module-3.png",  -- Placeholder icon
    icon_size = 256,
    effects = {},  -- Custom effect handled in control.lua
    prerequisites = {},
    unit = {
      count_formula = "2^(L-1)*1000",
      ingredients = {
        {"automation-science-pack", 1},
        {"logistic-science-pack", 1},
        {"chemical-science-pack", 1},
        {"production-science-pack", 1}
      },
      time = 60
    },
    max_level = "infinite",
    upgrade = true,
    order = "i-h-c"
  },

  -- Technology 3: Attention Retention (reduces decay rate)
  {
    type = "technology",
    name = "eiw-attention-decay-slowdown",
    localised_name = "Attention Retention",
    localised_description = "Machines lose attention more slowly when unobserved. Each level reduces attention decay rate by 0.002.",
    icon = "__base__/graphics/technology/efficiency-module-3.png",  -- Placeholder icon
    icon_size = 256,
    effects = {},  -- Custom effect handled in control.lua
    prerequisites = {},
    unit = {
      count_formula = "2^(L-1)*1000",
      ingredients = {
        {"automation-science-pack", 1},
        {"logistic-science-pack", 1},
        {"chemical-science-pack", 1},
        {"production-science-pack", 1}
      },
      time = 60
    },
    max_level = "infinite",
    upgrade = true,
    order = "i-h-d"
  },

  -- Technology 4: Attention Response (increases growth rate)
  {
    type = "technology",
    name = "eiw-attention-growth-boost",
    localised_name = "Attention Response",
    localised_description = "Machines gain attention more quickly when observed. Each level increases attention growth rate by 0.002.",
    icon = "__base__/graphics/technology/research-speed.png",  -- Placeholder icon
    icon_size = 256,
    effects = {},  -- Custom effect handled in control.lua
    prerequisites = {},
    unit = {
      count_formula = "2^(L-1)*1000",
      ingredients = {
        {"automation-science-pack", 1},
        {"logistic-science-pack", 1},
        {"chemical-science-pack", 1},
        {"production-science-pack", 1}
      },
      time = 60
    },
    max_level = "infinite",
    upgrade = true,
    order = "i-h-e"
  },

  -- Technology 5-10: Attention Range (6 levels, progressive range increase)
  -- Level 1: 24 tiles (16 base + 8)
  {
    type = "technology",
    name = "eiw-attention-range-1",
    localised_name = "Attention Range 1",
    localised_description = "Increases proximity detection radius to 24 tiles.",
    icon = "__base__/graphics/technology/effect-transmission.png",
    icon_size = 256,
    effects = {},  -- Custom effect handled in control.lua
    prerequisites = {},
    unit = {
      count = 100,
      ingredients = {
        {"automation-science-pack", 1}
      },
      time = 30
    },
    order = "i-h-f-1"
  },

  -- Level 2: 32 tiles (16 base + 16)
  {
    type = "technology",
    name = "eiw-attention-range-2",
    localised_name = "Attention Range 2",
    localised_description = "Increases proximity detection radius to 32 tiles.",
    icon = "__base__/graphics/technology/effect-transmission.png",
    icon_size = 256,
    effects = {},
    prerequisites = {"eiw-attention-range-1"},
    unit = {
      count = 200,
      ingredients = {
        {"automation-science-pack", 1},
        {"logistic-science-pack", 1}
      },
      time = 30
    },
    order = "i-h-f-2"
  },

  -- Level 3: 40 tiles (16 base + 24)
  {
    type = "technology",
    name = "eiw-attention-range-3",
    localised_name = "Attention Range 3",
    localised_description = "Increases proximity detection radius to 40 tiles.",
    icon = "__base__/graphics/technology/effect-transmission.png",
    icon_size = 256,
    effects = {},
    prerequisites = {"eiw-attention-range-2"},
    unit = {
      count = 400,
      ingredients = {
        {"automation-science-pack", 1},
        {"logistic-science-pack", 1},
        {"chemical-science-pack", 1}
      },
      time = 30
    },
    order = "i-h-f-3"
  },

  -- Level 4: 48 tiles (16 base + 32)
  {
    type = "technology",
    name = "eiw-attention-range-4",
    localised_name = "Attention Range 4",
    localised_description = "Increases proximity detection radius to 48 tiles.",
    icon = "__base__/graphics/technology/effect-transmission.png",
    icon_size = 256,
    effects = {},
    prerequisites = {"eiw-attention-range-3"},
    unit = {
      count = 800,
      ingredients = {
        {"automation-science-pack", 1},
        {"logistic-science-pack", 1},
        {"chemical-science-pack", 1},
        {"production-science-pack", 1}
      },
      time = 30
    },
    order = "i-h-f-4"
  },

  -- Level 5: 56 tiles (16 base + 40)
  {
    type = "technology",
    name = "eiw-attention-range-5",
    localised_name = "Attention Range 5",
    localised_description = "Increases proximity detection radius to 56 tiles.",
    icon = "__base__/graphics/technology/effect-transmission.png",
    icon_size = 256,
    effects = {},
    prerequisites = {"eiw-attention-range-4"},
    unit = {
      count = 1200,
      ingredients = {
        {"automation-science-pack", 1},
        {"logistic-science-pack", 1},
        {"chemical-science-pack", 1},
        {"production-science-pack", 1}
      },
      time = 30
    },
    order = "i-h-f-5"
  },

  -- Level 6: 64 tiles (16 base + 48)
  {
    type = "technology",
    name = "eiw-attention-range-6",
    localised_name = "Attention Range 6",
    localised_description = "Increases proximity detection radius to 64 tiles.",
    icon = "__base__/graphics/technology/effect-transmission.png",
    icon_size = 256,
    effects = {},
    prerequisites = {"eiw-attention-range-5"},
    unit = {
      count = 1600,
      ingredients = {
        {"automation-science-pack", 1},
        {"logistic-science-pack", 1},
        {"chemical-science-pack", 1},
        {"production-science-pack", 1},
        {"utility-science-pack", 1}
      },
      time = 30
    },
    order = "i-h-f-6"
  }
})
