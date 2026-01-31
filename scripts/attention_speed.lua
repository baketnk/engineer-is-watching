-- Speed modification system using hidden beacons
-- Applies attention-based speed modifiers to crafting machines
--
-- BEACON ATTACHMENT MECHANISM:
-- 1. When a crafting machine is registered (on_entity_built), a hidden beacon is spawned
--    at the EXACT SAME POSITION as the machine using surface.create_entity()
-- 2. The beacon entity reference is stored in machine_data.attention_beacon
-- 3. The beacon has supply_area_distance = 1, which affects entities within ~1 tile
-- 4. The beacon uses module_visualisations to display different sprites based on the
--    inserted module's tier (tier 1-11 maps to attention 50%-150%)
-- 5. When attention value changes enough to cross tier boundaries (10% increments),
--    the module is SWAPPED to change the visual appearance and speed effect
-- 6. When the machine is removed/destroyed, the beacon is also destroyed
--
-- VISUAL TIER REPRESENTATION:
-- - Single beacon prototype with module-based visualization
-- - 11 distinct visual sprites (red→yellow→green progress bars)
-- - Module tier (1-11) automatically selects sprite variation
-- - Debug mode controlled via startup setting (eiw-beacon-debug-mode)

local Config = require("scripts.config")

local AttentionSpeed = {}

-- Module-level variables initialized at runtime from settings
local ATTENTION_TIERS = nil
local ATTENTION_INTERVAL = nil
local TIER_MAP = nil

-- Initialize tier system from settings
-- Called from control.lua on_init and on_configuration_changed
function AttentionSpeed.initialize_tiers()
  local min = settings.startup["eiw-min-attention"].value * 100
  local max = settings.startup["eiw-max-attention"].value * 100
  ATTENTION_INTERVAL = settings.startup["eiw-attention-interval"].value

  local tier_count = math.floor((max - min) / ATTENTION_INTERVAL) + 1
  ATTENTION_TIERS = {}
  TIER_MAP = {}

  for i = 1, tier_count do
    local tier_value = min + (i - 1) * ATTENTION_INTERVAL
    ATTENTION_TIERS[i] = tier_value
    TIER_MAP[tier_value] = i
  end
end

-- Convert attention value to tier value
-- @param attention_value number - Current attention value
-- @return number - Tier value (e.g., 50, 55, 60... with 5% interval)
function AttentionSpeed.attention_to_tier(attention_value)
  -- Convert to percentage (0.5 -> 50, 1.5 -> 150)
  local percentage = attention_value * 100

  -- Round to nearest interval
  local half_interval = ATTENTION_INTERVAL / 2
  local tier = math.floor((percentage + half_interval) / ATTENTION_INTERVAL) * ATTENTION_INTERVAL

  -- Clamp to valid range
  local min = ATTENTION_TIERS[1]
  local max = ATTENTION_TIERS[#ATTENTION_TIERS]
  return math.max(min, math.min(max, tier))
end

-- Get beacon prototype name (now constant - single beacon for all tiers)
-- @return string - Beacon prototype name
function AttentionSpeed.get_beacon_name()
  return "eiw-attention-beacon"
end

-- Convert tier value (50, 55, 60...) to tier number (1, 2, 3...)
-- @param tier_value number - Tier value from attention_to_tier()
-- @return number - Tier number for sprite selection
function AttentionSpeed.get_tier_number(tier_value)
  return TIER_MAP[tier_value] or 1  -- Fallback to tier 1
end

-- Get module prototype name for a given tier
-- @param tier number - Tier value (50-150)
-- @return string - Module prototype name
function AttentionSpeed.get_module_name(tier)
  return "eiw-attention-module-" .. tier
end

-- Create a hidden beacon for a machine at the specified tier
-- @param entity LuaEntity - The crafting machine
-- @param tier number - Initial tier (50-150)
-- @return LuaEntity|nil - The created beacon or nil on failure
function AttentionSpeed.create_beacon(entity, tier)
  if not entity or not entity.valid then
    return nil
  end

  local beacon_name = AttentionSpeed.get_beacon_name()
  local module_name = AttentionSpeed.get_module_name(tier)

  -- Create the beacon at the machine's position
  local beacon = entity.surface.create_entity{
    name = beacon_name,
    position = entity.position,
    force = entity.force,
    create_build_effect_smoke = false,
    raise_built = false  -- Don't trigger built events for hidden entities
  }

  if not beacon then
    return nil
  end

  -- Insert the appropriate module into the beacon (determines visual appearance)
  local module_inventory = beacon.get_module_inventory()
  if module_inventory then
    module_inventory.insert{name = module_name, count = 1}
  end

  return beacon
end

-- Destroy an existing attention beacon
-- @param beacon LuaEntity - The beacon to destroy
function AttentionSpeed.destroy_beacon(beacon)
  if beacon and beacon.valid then
    beacon.destroy{raise_destroy = false}
  end
end

-- Update beacon to a new tier (swap module instead of recreating beacon)
-- @param entity LuaEntity - The crafting machine
-- @param beacon LuaEntity - Current beacon
-- @param new_tier number - New tier to apply
-- @return LuaEntity - The same beacon with updated module
function AttentionSpeed.update_beacon_tier(entity, beacon, new_tier)
  if not beacon or not beacon.valid then
    -- Beacon is invalid, create a new one
    return AttentionSpeed.create_beacon(entity, new_tier)
  end

  -- Swap the module to change visual appearance
  local module_inventory = beacon.get_module_inventory()
  if module_inventory then
    module_inventory.clear()
    local module_name = AttentionSpeed.get_module_name(new_tier)
    module_inventory.insert{name = module_name, count = 1}
  end

  return beacon  -- Same beacon, new module
end

-- Helper: Get current tier from beacon's inserted module
-- @param beacon LuaEntity - The beacon to check
-- @return number|nil - Current tier (50-150) or nil if not found
local function get_current_tier(beacon)
  if not beacon or not beacon.valid then
    return nil
  end

  local module_inventory = beacon.get_module_inventory()
  if not module_inventory or module_inventory.is_empty() then
    return nil
  end

  local contents = module_inventory.get_contents()
  for idx, item_data in pairs(contents) do
    -- Inventory format: get_contents() returns slot-indexed items
    -- {[slot_number] = {count=N, name="item-name", quality="quality-name"}}
    -- The numeric index represents the inventory slot (1, 2, 3, etc.)
    -- Each slot contains a stack with count, item name, and quality
    local item_name
    if type(item_data) == "table" and item_data.name then
      -- Standard inventory slot format
      item_name = item_data.name
    elseif type(idx) == "string" then
      -- Legacy/alternative format (if it exists): item name as key
      item_name = idx
    else
      -- Unexpected format, skip
      log("[EIW DEBUG] get_current_tier: Unexpected inventory format. idx=" .. serpent.line(idx) .. ", item_data=" .. serpent.line(item_data))
      goto continue
    end

    local tier = tonumber(item_name:match("eiw%-attention%-module%-(%d+)$"))
    if tier then
      return tier
    end

    ::continue::
  end

  return nil
end

-- Apply speed modifier to a machine based on attention value
-- Called from attention_updater after visual update
-- @param machine_data table - Machine data from storage (includes entity and attention_beacon)
-- @param attention_value number - Current attention value [0.5, 1.5]
-- @return LuaEntity|nil - Updated beacon reference (for storage)
function AttentionSpeed.apply_speed_modifier(machine_data, attention_value)
  local entity = machine_data.entity
  if not entity or not entity.valid then
    -- Clean up beacon if entity is invalid
    AttentionSpeed.destroy_beacon(machine_data.attention_beacon)
    return nil
  end

  local new_tier = AttentionSpeed.attention_to_tier(attention_value)
  local current_beacon = machine_data.attention_beacon

  -- Check if we need to create or update the beacon
  if not current_beacon or not current_beacon.valid then
    -- No beacon exists, create one
    return AttentionSpeed.create_beacon(entity, new_tier)
  end

  -- Check if tier changed by examining current beacon's module
  local current_tier = get_current_tier(current_beacon)
  if current_tier ~= new_tier then
    -- Tier changed, swap module (changes visual)
    return AttentionSpeed.update_beacon_tier(entity, current_beacon, new_tier)
  end

  -- No change needed
  return current_beacon
end

-- Initialize beacon for a newly registered machine
-- @param machine_data table - Machine data from storage
-- @param speed_multiplier number - Speed multiplier value [0.5, 1.5]
-- @return LuaEntity|nil - Created beacon reference
function AttentionSpeed.initialize_beacon(machine_data, speed_multiplier)
  local entity = machine_data.entity
  if not entity or not entity.valid then
    return nil
  end

  local tier = AttentionSpeed.attention_to_tier(speed_multiplier)
  return AttentionSpeed.create_beacon(entity, tier)
end

-- Clean up beacon when machine is removed
-- @param machine_data table - Machine data from storage
function AttentionSpeed.cleanup_beacon(machine_data)
  AttentionSpeed.destroy_beacon(machine_data.attention_beacon)
end

return AttentionSpeed
