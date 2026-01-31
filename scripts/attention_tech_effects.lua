-- Technology effects for attention system
-- Calculates effective attention parameters based on researched technology levels

local Config = require("scripts.config")

local AttentionTechEffects = {}

-- Cache for technology modifiers per force
-- storage.tech_modifier_cache = {
--   [force_index] = {
--     floor_modifier = number,
--     ceiling_modifier = number,
--     decay_modifier = number,
--     growth_modifier = number,
--     last_update_tick = number
--   }
-- }

-- Initialize technology effects storage
function AttentionTechEffects.init()
  if not storage.tech_modifier_cache then
    storage.tech_modifier_cache = {}
  end
end

-- Invalidate the cache for a specific force
-- Called when technologies are researched
-- @param force LuaForce - The force to invalidate cache for
function AttentionTechEffects.invalidate_cache(force)
  if not force or not force.valid then
    return
  end

  local force_index = force.index
  storage.tech_modifier_cache[force_index] = nil
end

-- Invalidate all caches
-- Called on configuration changes
function AttentionTechEffects.invalidate_all_caches()
  storage.tech_modifier_cache = {}
end

-- Read technology level from force
-- @param force LuaForce - The force to check
-- @param tech_name string - Technology name
-- @return number - Technology level (0 if not researched)
local function get_tech_level(force, tech_name)
  if not force or not force.valid then
    return 0
  end

  local tech = force.technologies[tech_name]
  if tech and tech.researched then
    return tech.level
  end
  return 0
end

-- Calculate technology modifiers for a force
-- @param force LuaForce - The force to calculate modifiers for
-- @return table - Table with floor_modifier, ceiling_modifier, decay_modifier, growth_modifier
local function calculate_modifiers(force)
  -- Floor tech: +0.05 per level (increases minimum)
  local floor_modifier = get_tech_level(force, "eiw-attention-floor") * 0.05

  -- Ceiling tech: +0.05 per level (increases maximum)
  local ceiling_modifier = get_tech_level(force, "eiw-attention-ceiling") * 0.05

  -- Decay slowdown: -0.002 per level (reduces decay rate)
  local decay_modifier = get_tech_level(force, "eiw-attention-decay-slowdown") * -0.002

  -- Growth boost: +0.002 per level (increases growth rate)
  local growth_modifier = get_tech_level(force, "eiw-attention-growth-boost") * 0.002

  -- Range modifier: Check which range level is researched (1-6)
  local range_level = 0
  for i = 1, 6 do
    local tech_name = "eiw-attention-range-" .. i
    local tech = force.technologies[tech_name]
    if tech and tech.researched then
      range_level = i
    else
      break  -- Technologies must be researched in order
    end
  end

  local range_modifier = range_level * 8

  return {
    floor_modifier = floor_modifier,
    ceiling_modifier = ceiling_modifier,
    decay_modifier = decay_modifier,
    growth_modifier = growth_modifier,
    range_modifier = range_modifier
  }
end

-- Get cached modifiers for a force, or calculate and cache if needed
-- @param force LuaForce - The force to get modifiers for
-- @return table - Table with floor_modifier, ceiling_modifier, decay_modifier, growth_modifier
local function get_cached_modifiers(force)
  if not force or not force.valid then
    return {
      floor_modifier = 0,
      ceiling_modifier = 0,
      decay_modifier = 0,
      growth_modifier = 0,
      range_modifier = 0
    }
  end

  local force_index = force.index
  local cached = storage.tech_modifier_cache[force_index]

  -- Use cached value if available and recent (less than 60 seconds old)
  if cached and cached.last_update_tick and (game.tick - cached.last_update_tick) < 3600 then
    return cached
  end

  -- Calculate and cache
  local modifiers = calculate_modifiers(force)
  modifiers.last_update_tick = game.tick
  storage.tech_modifier_cache[force_index] = modifiers

  return modifiers
end

-- Calculate effective attention parameters for a force
-- @param force LuaForce - The force to calculate parameters for
-- @param runtime_config table - Runtime configuration with base values
-- @return table - Effective parameters {min, max, decay_rate, growth_rate}
function AttentionTechEffects.get_effective_attention_params(force, runtime_config)
  -- Get base values from runtime config or Config
  local base_min = runtime_config.min_attention or Config.MIN_ATTENTION
  local base_max = runtime_config.max_attention or Config.MAX_ATTENTION
  local base_decay = runtime_config.attention_decay_rate or Config.ATTENTION_DECAY_RATE
  local base_growth = runtime_config.attention_growth_rate or Config.ATTENTION_GROWTH_RATE

  -- Get technology modifiers
  local modifiers = get_cached_modifiers(force)

  -- Calculate effective values
  local effective_min = base_min + modifiers.floor_modifier
  local effective_max = base_max + modifiers.ceiling_modifier
  local effective_decay = math.max(0.01, base_decay + modifiers.decay_modifier)
  local effective_growth = base_growth + modifiers.growth_modifier

  return {
    min = effective_min,
    max = effective_max,
    decay_rate = effective_decay,
    growth_rate = effective_growth
  }
end

-- Calculate effective proximity radius for a force
-- @param force LuaForce - The force to calculate radius for
-- @return number - Effective proximity radius in tiles
function AttentionTechEffects.get_effective_proximity_radius(force)
  local base_radius = Config.PROXIMITY_RADIUS  -- Base from settings (default 16)
  local modifiers = get_cached_modifiers(force)
  return base_radius + modifiers.range_modifier
end

return AttentionTechEffects
