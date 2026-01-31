-- Visual feedback for attention system using custom_status and sprite indicators

local Config = require("scripts.config")
local AttentionSpeed = require("scripts.attention_speed")

local AttentionVisual = {}

-- Get sprite name based on state and normalized attention
-- @param has_attention boolean - Current attention state
-- @param attention_value number - Normalized attention [0.0, 1.0]
-- @return string - Sprite prototype name
local function get_indicator_sprite(has_attention, attention_value)
  -- Sprite sheets have 101 frames (3232px / 32px = 101)
  -- Map normalized attention [0, 1] to full sprite range [1, 101]
  local sprite_frame_count = 101
  local frame_number = math.floor(attention_value * (sprite_frame_count - 1)) + 1
  frame_number = math.max(1, math.min(sprite_frame_count, frame_number))  -- Clamp to [1, 101]

  local sprite_type = has_attention and "rect" or "circle"
  return "eiw-indicator-" .. sprite_type .. "-" .. frame_number
end

-- Get diode color based on attention value
-- Green: >= 0.5 (high attention)
-- Yellow: 0.25-0.5 (medium attention)
-- Red: < 0.25 (low attention)
-- @param attention_value number - Normalized attention value [0.0, 1.0]
-- @return defines.entity_status_diode - Color constant
function AttentionVisual.get_diode_color(attention_value)
  if attention_value >= Config.DIODE_GREEN_THRESHOLD then
    return defines.entity_status_diode.green
  elseif attention_value >= Config.DIODE_YELLOW_THRESHOLD then
    return defines.entity_status_diode.yellow
  else
    return defines.entity_status_diode.red
  end
end

-- Format attention value as percentage label
-- @param attention_value number - Normalized attention value [0.0, 1.0]
-- @param machine_data table|nil - Machine data with delta info (optional, for debug)
-- @return LocalisedString - Formatted label
function AttentionVisual.format_label(attention_value, machine_data)
  -- Convert [0, 1] to [0, 100]
  local percentage = math.floor(attention_value * 100)

  -- Check if debug commands are enabled
  local debug_enabled = settings.global["eiw-enable-debug-commands"] and settings.global["eiw-enable-debug-commands"].value

  if debug_enabled and machine_data then
    -- Show debug info: raw value and delta
    local raw_str = string.format("%.3f", machine_data.attention)
    local delta_str = string.format("%.5f", machine_data.attention_delta or 0)
    return {"", "Attention: ", tostring(percentage), "%\nRaw: ", raw_str, " Δ: ", delta_str}
  else
    return {"", "Attention: ", tostring(percentage), "%"}
  end
end

-- Create status table for custom_status
-- @param attention_value number - Normalized attention value [0.0, 1.0]
-- @param machine_data table|nil - Machine data with delta info (optional, for debug)
-- @return table - Status table with diode and label
function AttentionVisual.create_status(attention_value, machine_data)
  return {
    diode = AttentionVisual.get_diode_color(attention_value),
    label = AttentionVisual.format_label(attention_value, machine_data)
  }
end

-- Update entity's custom_status and create/update sprite indicator
-- @param entity LuaEntity - The crafting machine to update
-- @param attention_value number - Normalized attention value [0.0, 1.0]
-- @param existing_sprite_id number|nil - Existing rendering ID to update, or nil to create new
-- @param machine_data table - Machine data with has_attention and delta info
-- @return number|nil - Rendering ID for the sprite, or nil if creation failed
function AttentionVisual.update(entity, attention_value, existing_sprite_id, machine_data)
  if not entity or not entity.valid then
    return nil
  end

  -- Set custom status
  entity.custom_status = AttentionVisual.create_status(attention_value, machine_data)

  -- Destroy existing sprite
  if existing_sprite_id then
    existing_sprite_id:destroy()
  end

  -- Calculate corner position relative to entity center
  local box = entity.selection_box or entity.bounding_box
  local offset = {0, -1.5}  -- Default fallback

  if box then
    -- Get box dimensions
    local width = box.right_bottom.x - box.left_top.x
    local height = box.right_bottom.y - box.left_top.y

    -- Position at bottom-left corner
    -- box coordinates are absolute world coordinates, so convert to relative
    local horizontal_position = 0.3
    local indicator_size = 0.3
    local vertical_padding = 0.1

    -- Calculate offset relative to entity center
    offset[1] = -(width / 2) + (width * horizontal_position)
    offset[2] = (height / 2) - indicator_size - vertical_padding
  end

  -- Get sprite name based on state and normalized attention
  local sprite_name = get_indicator_sprite(machine_data.has_attention, attention_value)

  -- Create sprite rendering
  local sprite_id = rendering.draw_sprite{
    sprite = sprite_name,
    target = {entity = entity, offset = offset},
    surface = entity.surface,
    x_scale = 1.0,
    y_scale = 1.0,
    visible = true,
    render_layer = "object"
  }

  return sprite_id
end

-- Clear custom_status and sprite from entity
-- @param entity LuaEntity - The crafting machine to clear
-- @param sprite_id number|nil - Rendering ID to destroy
function AttentionVisual.clear(entity, sprite_id)
  -- Destroy the sprite rendering
  if sprite_id then
    sprite_id:destroy()
  end

  if not entity or not entity.valid then
    return
  end

  entity.custom_status = nil
end

return AttentionVisual
