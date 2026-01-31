-- Configuration constants for the attention system
-- All timing values are in ticks (60 ticks = 1 second)

local Config = {}

-- Update frequency (60 ticks = 1 second)
-- Fallback to 60 if settings aren't available yet
Config.UPDATE_INTERVAL = (settings and settings.startup and settings.startup["eiw-update-interval"] and settings.startup["eiw-update-interval"].value) or 60

-- Attention value constraints (read from settings)
-- Note: In data stage, use settings.startup directly
-- In control stage, these are read once at startup
Config.MIN_ATTENTION = settings.startup["eiw-min-attention"].value
Config.MAX_ATTENTION = settings.startup["eiw-max-attention"].value
Config.INITIAL_ATTENTION = 1.0

-- Change rates per update (runtime values, passed from control.lua)
-- Default values here for reference only
-- Decay rate: how fast attention decreases when machines are not observed
Config.ATTENTION_DECAY_RATE = 0.05
-- Growth rate: how fast attention increases when machines are observed
Config.ATTENTION_GROWTH_RATE = 0.05

-- Proximity detection base radius
-- Base: 16 tiles, can be increased to 64 tiles via 6 technology levels
Config.PROXIMITY_RADIUS = settings.startup["eiw-proximity-radius"].value

-- Crafting machine types to track
-- These are the entity types that can craft/process items
Config.CRAFTING_MACHINE_TYPES = {
	"assembling-machine",
	"furnace",
	"chemical-plant", -- Includes oil refineries
	"rocket-silo",
	"agricultural-tower",
	"mining-drill", -- Includes burner/electric drills and pumpjacks
	"lab", -- Research labs
}

-- Visual feedback thresholds (for normalized attention [0.0, 1.0])
Config.DIODE_GREEN_THRESHOLD = 0.5 -- >= 0.5 = green (high attention)
Config.DIODE_YELLOW_THRESHOLD = 0.25 -- 0.25-0.5 = yellow (medium attention)
-- < 0.25 = red (low attention)

-- Factor target values (from startup settings)
Config.PROXIMITY_ATTENTION_TARGET = settings.startup["eiw-proximity-attention-target"].value
Config.VISIBILITY_ATTENTION_TARGET = settings.startup["eiw-visibility-attention-target"].value
Config.GUI_ATTENTION_TARGET = settings.startup["eiw-gui-attention-target"].value
Config.EQUIPMENT_ATTENTION_TARGET = settings.startup["eiw-equipment-attention-target"].value

-- Quantum Zeno mode (invert attention-speed relationship)
Config.QUANTUM_ZENO_MODE = settings.startup["eiw-quantum-zeno-mode"].value

-- Delta reset threshold (target must change by this much to reset delta)
Config.DELTA_RESET_THRESHOLD = 0.1

-- Tiles per pixel at default zoom (Factorio uses ~32 pixels per tile)
Config.TILES_PER_PIXEL = 1 / 32

return Config
