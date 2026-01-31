-- data-final-fixes.lua
-- Modify base game entities to accept speed beacon effects from our attention system
--
-- This runs after all other mods, ensuring our changes take precedence.
-- We only enable "speed" effects since our hidden beacons only provide speed bonuses.

-- Furnaces without module slots don't accept beacon effects by default
local furnaces_to_modify = {
  "stone-furnace",
  "steel-furnace"
}

for _, furnace_name in pairs(furnaces_to_modify) do
  local furnace = data.raw["furnace"][furnace_name]
  if furnace then
    furnace.allowed_effects = {"speed"}
    furnace.effect_receiver = {
      base_effect = {},
      uses_module_effects = false,  -- Stone/steel have no module slots
      uses_beacon_effects = true,    -- Explicitly enable beacon effects
      uses_surface_effects = true
    }
  end
end

-- Mining drills (set explicitly for consistency)
local drills_to_modify = {
  "burner-mining-drill",
  "electric-mining-drill"
}

for _, drill_name in pairs(drills_to_modify) do
  local drill = data.raw["mining-drill"][drill_name]
  if drill then
    drill.allowed_effects = {"speed"}
  end
end

-- Research labs (enable beacon effects for consistent behavior)
local labs_to_modify = {
  "lab"
}

for _, lab_name in pairs(labs_to_modify) do
  local lab = data.raw["lab"][lab_name]
  if lab then
    lab.allowed_effects = {"speed"}
    lab.effect_receiver = {
      base_effect = {},
      uses_module_effects = true,   -- Labs have module slots
      uses_beacon_effects = true,   -- Enable beacon effects
      uses_surface_effects = true
    }
  end
end
