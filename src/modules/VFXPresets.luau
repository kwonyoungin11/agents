--!strict
-- VFXPresets: Pre-configured effect settings for common game scenarios
-- Use with VFXLibrary functions: VFXLibrary.createFireEffect(parent, VFXPresets.Fire.Campfire)

local VFXPresets = {}

--------------------------------------------------------------------------------
-- FIRE PRESETS
--------------------------------------------------------------------------------

VFXPresets.Fire = {
	Campfire = {
		rate = 80,
		speed = {2, 6},
		lifetime = {0.5, 1.5},
		spread = 12,
	},
	Torch = {
		rate = 50,
		speed = {2, 5},
		lifetime = {0.3, 0.8},
		spread = 8,
	},
	Inferno = {
		rate = 200,
		speed = {5, 15},
		lifetime = {0.4, 1.0},
		spread = 25,
		acceleration = Vector3.new(0, 8, 0),
	},
	BlueFire = {
		rate = 100,
		speed = {3, 8},
		lifetime = {0.3, 1.0},
		spread = 15,
	},
	Candle = {
		rate = 20,
		speed = {1, 3},
		lifetime = {0.2, 0.5},
		spread = 5,
	},
}

--------------------------------------------------------------------------------
-- SMOKE PRESETS
--------------------------------------------------------------------------------

VFXPresets.Smoke = {
	Chimney = {
		rate = 20,
		speed = {1, 3},
		lifetime = {3, 6},
		spread = 10,
		color = Color3.fromRGB(80, 80, 80),
	},
	Steam = {
		rate = 30,
		speed = {2, 4},
		lifetime = {1, 2},
		spread = 15,
		color = Color3.fromRGB(220, 220, 230),
	},
	DustCloud = {
		rate = 50,
		speed = {1, 5},
		lifetime = {1, 3},
		spread = 40,
		color = Color3.fromRGB(160, 140, 110),
	},
	Fog = {
		rate = 15,
		speed = {0.5, 1},
		lifetime = {5, 10},
		spread = 20,
		color = Color3.fromRGB(200, 200, 210),
	},
}

--------------------------------------------------------------------------------
-- SPARK PRESETS
--------------------------------------------------------------------------------

VFXPresets.Sparks = {
	Welding = {
		rate = 100,
		speed = {10, 25},
		lifetime = {0.1, 0.5},
		spread = 45,
		color = Color3.fromRGB(255, 230, 100),
	},
	Magic = {
		rate = 40,
		speed = {3, 10},
		lifetime = {0.3, 1.0},
		spread = 60,
		color = Color3.fromRGB(180, 100, 255),
	},
	Electric = {
		rate = 80,
		speed = {8, 20},
		lifetime = {0.1, 0.3},
		spread = 50,
		color = Color3.fromRGB(100, 200, 255),
	},
}

--------------------------------------------------------------------------------
-- AURA PRESETS
--------------------------------------------------------------------------------

VFXPresets.Aura = {
	Healing = {
		rate = 25,
		speed = {0.5, 2},
		lifetime = {1, 2},
		color = Color3.fromRGB(50, 255, 100),
		size = 1.5,
	},
	Dark = {
		rate = 35,
		speed = {0.3, 1.5},
		lifetime = {1, 3},
		color = Color3.fromRGB(80, 0, 120),
		size = 2,
	},
	Fire = {
		rate = 40,
		speed = {1, 3},
		lifetime = {0.5, 1.5},
		color = Color3.fromRGB(255, 100, 20),
		size = 1.8,
	},
	Ice = {
		rate = 20,
		speed = {0.5, 1.5},
		lifetime = {1, 2},
		color = Color3.fromRGB(150, 220, 255),
		size = 1.2,
	},
	PowerUp = {
		rate = 60,
		speed = {2, 5},
		lifetime = {0.5, 1},
		color = Color3.fromRGB(255, 220, 50),
		size = 2,
	},
}

--------------------------------------------------------------------------------
-- BEAM PRESETS
--------------------------------------------------------------------------------

VFXPresets.Beam = {
	Laser = {
		width = 0.5,
		color = Color3.fromRGB(255, 0, 0),
		segments = 1,
		textureSpeed = 0,
	},
	Energy = {
		width = 1.5,
		color = Color3.fromRGB(50, 150, 255),
		segments = 15,
		textureSpeed = 3,
	},
	HealingStream = {
		width = 1,
		color = Color3.fromRGB(50, 255, 100),
		segments = 10,
		textureSpeed = 2,
	},
}

--------------------------------------------------------------------------------
-- LIGHTNING PRESETS
--------------------------------------------------------------------------------

VFXPresets.Lightning = {
	Natural = {
		segments = 20,
		jitter = 6,
		thickness = 0.3,
		color = Color3.fromRGB(200, 220, 255),
		branchChance = 0.4,
		animated = true,
		animInterval = 0.1,
	},
	Electric = {
		segments = 12,
		jitter = 2,
		thickness = 0.2,
		color = Color3.fromRGB(100, 200, 255),
		branchChance = 0.2,
		animated = true,
		animInterval = 0.05,
	},
	Dark = {
		segments = 15,
		jitter = 5,
		thickness = 0.4,
		color = Color3.fromRGB(120, 0, 180),
		branchChance = 0.3,
		animated = true,
		animInterval = 0.08,
	},
}

--------------------------------------------------------------------------------
-- PORTAL PRESETS
--------------------------------------------------------------------------------

VFXPresets.Portal = {
	Nether = {
		size = 10,
		color = Color3.fromRGB(150, 30, 200),
		particleRate = 60,
		rotationSpeed = 45,
	},
	Dimensional = {
		size = 8,
		color = Color3.fromRGB(0, 200, 255),
		particleRate = 80,
		rotationSpeed = 90,
	},
	Dark = {
		size = 6,
		color = Color3.fromRGB(30, 0, 50),
		particleRate = 40,
		rotationSpeed = 30,
	},
	Golden = {
		size = 8,
		color = Color3.fromRGB(255, 200, 50),
		particleRate = 70,
		rotationSpeed = 60,
	},
}

--------------------------------------------------------------------------------
-- EXPLOSION PRESETS
--------------------------------------------------------------------------------

VFXPresets.Explosion = {
	Small = {
		radius = 4,
		color = Color3.fromRGB(255, 150, 30),
		particleCount = 40,
		debrisCount = 6,
		duration = 1.5,
	},
	Large = {
		radius = 15,
		color = Color3.fromRGB(255, 120, 20),
		particleCount = 150,
		debrisCount = 25,
		duration = 3,
	},
	Nuclear = {
		radius = 30,
		color = Color3.fromRGB(255, 255, 200),
		particleCount = 300,
		debrisCount = 50,
		duration = 5,
	},
	Magic = {
		radius = 8,
		color = Color3.fromRGB(150, 50, 255),
		particleCount = 80,
		debrisCount = 0,
		duration = 2,
	},
}

--------------------------------------------------------------------------------
-- LIGHTING PRESETS
--------------------------------------------------------------------------------

VFXPresets.Lighting = {
	Cinematic = {
		brightness = 2,
		clockTime = 16,
		bloomIntensity = 0.5,
		bloomSize = 24,
		ccContrast = 0.15,
		ccSaturation = 0.2,
		sunRaysIntensity = 0.2,
		atmoDensity = 0.3,
	},
	Horror = {
		brightness = 0.5,
		clockTime = 0,
		ambient = Color3.fromRGB(10, 10, 15),
		outdoorAmbient = Color3.fromRGB(10, 15, 20),
		bloomIntensity = 0.8,
		bloomSize = 40,
		bloomThreshold = 0.5,
		ccBrightness = -0.1,
		ccContrast = 0.3,
		ccSaturation = -0.3,
		tintColor = Color3.fromRGB(200, 210, 230),
		atmoDensity = 0.5,
		atmoColor = Color3.fromRGB(50, 50, 70),
		dofFar = 0.5,
		dofFocus = 20,
		dofRadius = 10,
	},
	Sunset = {
		brightness = 2.5,
		clockTime = 18.5,
		bloomIntensity = 0.6,
		ccSaturation = 0.4,
		tintColor = Color3.fromRGB(255, 220, 180),
		sunRaysIntensity = 0.35,
		sunRaysSpread = 0.7,
		atmoDensity = 0.4,
		atmoColor = Color3.fromRGB(255, 180, 120),
		atmoDecay = Color3.fromRGB(200, 100, 60),
	},
	Neon = {
		brightness = 0.3,
		clockTime = 22,
		ambient = Color3.fromRGB(5, 5, 10),
		bloomIntensity = 1,
		bloomSize = 30,
		bloomThreshold = 0.3,
		ccContrast = 0.2,
		ccSaturation = 0.5,
		tintColor = Color3.fromRGB(220, 200, 255),
		atmoDensity = 0.2,
	},
	Underwater = {
		brightness = 1,
		clockTime = 12,
		ambient = Color3.fromRGB(20, 40, 60),
		bloomIntensity = 0.4,
		ccSaturation = 0.1,
		tintColor = Color3.fromRGB(150, 200, 230),
		atmoDensity = 0.6,
		atmoColor = Color3.fromRGB(30, 80, 120),
		dofFar = 0.8,
		dofFocus = 30,
		dofRadius = 15,
	},
}

--------------------------------------------------------------------------------
-- IMPACT PRESETS
--------------------------------------------------------------------------------

VFXPresets.Impact = {
	Sword = {
		color = Color3.fromRGB(255, 255, 255),
		size = 2,
		duration = 0.5,
		particleCount = 15,
	},
	Bullet = {
		color = Color3.fromRGB(255, 200, 50),
		size = 1,
		duration = 0.3,
		particleCount = 10,
	},
	Magic = {
		color = Color3.fromRGB(150, 50, 255),
		size = 4,
		duration = 1,
		particleCount = 40,
	},
	Heavy = {
		color = Color3.fromRGB(200, 150, 100),
		size = 5,
		duration = 1.5,
		particleCount = 60,
	},
}

return VFXPresets
