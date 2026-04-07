--!strict
-- VFXLibrary: Modern Roblox VFX effects with precise attachment positioning
-- Supports particles, beams, trails, lighting, and composite effects

local VFXLibrary = {}

local TweenService = game:GetService("TweenService")
local RunService = game:GetService("RunService")
local Lighting = game:GetService("Lighting")

--------------------------------------------------------------------------------
-- UTILITY HELPERS
--------------------------------------------------------------------------------

local function ensureAttachment(parent: BasePart, name: string?, position: Vector3?): Attachment
	local att = Instance.new("Attachment")
	att.Name = name or "VFXAttachment"
	att.Position = position or Vector3.zero
	att.Parent = parent
	return att
end

local function makeFolder(name: string, parent: Instance?): Folder
	local folder = Instance.new("Folder")
	folder.Name = name
	folder.Parent = parent or workspace
	return folder
end

local function mergeConfig(defaults: {[string]: any}, overrides: {[string]: any}?): {[string]: any}
	local result = table.clone(defaults)
	if overrides then
		for k, v in overrides do
			result[k] = v
		end
	end
	return result
end

--------------------------------------------------------------------------------
-- PARTICLE EFFECTS
--------------------------------------------------------------------------------

function VFXLibrary.createFireEffect(parent: BasePart, config: {[string]: any}?): ParticleEmitter
	local c = mergeConfig({
		rate = 120,
		speed = {3, 8},
		lifetime = {0.4, 1.2},
		spread = 15,
		lightEmission = 1,
		lightInfluence = 0,
		acceleration = Vector3.new(0, 3, 0),
	}, config)

	local att = ensureAttachment(parent, "FireAttachment")
	local emitter = Instance.new("ParticleEmitter")
	emitter.Name = "Fire"
	emitter.Rate = c.rate
	emitter.Speed = NumberRange.new(c.speed[1], c.speed[2])
	emitter.Lifetime = NumberRange.new(c.lifetime[1], c.lifetime[2])
	emitter.SpreadAngle = Vector2.new(c.spread, c.spread)
	emitter.EmissionDirection = Enum.NormalId.Top
	emitter.LightEmission = c.lightEmission
	emitter.LightInfluence = c.lightInfluence
	emitter.Acceleration = c.acceleration
	emitter.RotSpeed = NumberRange.new(-120, 120)
	emitter.Rotation = NumberRange.new(0, 360)
	emitter.Size = NumberSequence.new({
		NumberSequenceKeypoint.new(0, 0.8),
		NumberSequenceKeypoint.new(0.2, 2.5),
		NumberSequenceKeypoint.new(0.6, 3.0),
		NumberSequenceKeypoint.new(1, 0),
	})
	emitter.Transparency = NumberSequence.new({
		NumberSequenceKeypoint.new(0, 0.2),
		NumberSequenceKeypoint.new(0.5, 0.5),
		NumberSequenceKeypoint.new(0.8, 0.85),
		NumberSequenceKeypoint.new(1, 1),
	})
	emitter.Color = ColorSequence.new({
		ColorSequenceKeypoint.new(0, Color3.fromRGB(255, 230, 80)),
		ColorSequenceKeypoint.new(0.3, Color3.fromRGB(255, 140, 20)),
		ColorSequenceKeypoint.new(0.7, Color3.fromRGB(200, 50, 10)),
		ColorSequenceKeypoint.new(1, Color3.fromRGB(80, 15, 0)),
	})
	emitter.Parent = att

	-- Add glow light
	local light = Instance.new("PointLight")
	light.Color = Color3.fromRGB(255, 150, 50)
	light.Brightness = 2
	light.Range = 16
	light.Parent = parent

	return emitter
end

function VFXLibrary.createSmokeEffect(parent: BasePart, config: {[string]: any}?): ParticleEmitter
	local c = mergeConfig({
		rate = 40,
		speed = {1, 4},
		lifetime = {2, 4},
		spread = 25,
		color = Color3.fromRGB(100, 100, 100),
	}, config)

	local att = ensureAttachment(parent, "SmokeAttachment")
	local emitter = Instance.new("ParticleEmitter")
	emitter.Name = "Smoke"
	emitter.Rate = c.rate
	emitter.Speed = NumberRange.new(c.speed[1], c.speed[2])
	emitter.Lifetime = NumberRange.new(c.lifetime[1], c.lifetime[2])
	emitter.SpreadAngle = Vector2.new(c.spread, c.spread)
	emitter.EmissionDirection = Enum.NormalId.Top
	emitter.LightEmission = 0
	emitter.LightInfluence = 1
	emitter.Drag = 3
	emitter.Acceleration = Vector3.new(0, 1, 0)
	emitter.RotSpeed = NumberRange.new(-30, 30)
	emitter.Rotation = NumberRange.new(0, 360)
	emitter.Size = NumberSequence.new({
		NumberSequenceKeypoint.new(0, 1),
		NumberSequenceKeypoint.new(0.5, 4),
		NumberSequenceKeypoint.new(1, 6),
	})
	emitter.Transparency = NumberSequence.new({
		NumberSequenceKeypoint.new(0, 0.4),
		NumberSequenceKeypoint.new(0.5, 0.7),
		NumberSequenceKeypoint.new(1, 1),
	})
	emitter.Color = ColorSequence.new(c.color)
	emitter.Parent = att

	return emitter
end

function VFXLibrary.createSparkEffect(parent: BasePart, config: {[string]: any}?): ParticleEmitter
	local c = mergeConfig({
		rate = 60,
		speed = {8, 20},
		lifetime = {0.2, 0.8},
		spread = 60,
		color = Color3.fromRGB(255, 220, 100),
	}, config)

	local att = ensureAttachment(parent, "SparkAttachment")
	local emitter = Instance.new("ParticleEmitter")
	emitter.Name = "Sparks"
	emitter.Rate = c.rate
	emitter.Speed = NumberRange.new(c.speed[1], c.speed[2])
	emitter.Lifetime = NumberRange.new(c.lifetime[1], c.lifetime[2])
	emitter.SpreadAngle = Vector2.new(c.spread, c.spread)
	emitter.LightEmission = 1
	emitter.LightInfluence = 0
	emitter.Drag = 5
	emitter.Acceleration = Vector3.new(0, -30, 0) -- gravity pull
	emitter.Size = NumberSequence.new({
		NumberSequenceKeypoint.new(0, 0.3),
		NumberSequenceKeypoint.new(1, 0),
	})
	emitter.Transparency = NumberSequence.new({
		NumberSequenceKeypoint.new(0, 0),
		NumberSequenceKeypoint.new(0.7, 0.3),
		NumberSequenceKeypoint.new(1, 1),
	})
	emitter.Color = ColorSequence.new(c.color)
	emitter.Parent = att

	return emitter
end

function VFXLibrary.createMagicAuraEffect(parent: BasePart, config: {[string]: any}?): ParticleEmitter
	local c = mergeConfig({
		rate = 30,
		speed = {0.5, 2},
		lifetime = {1, 2},
		color = Color3.fromRGB(100, 50, 255),
		size = 1.5,
	}, config)

	local att = ensureAttachment(parent, "AuraAttachment")
	local emitter = Instance.new("ParticleEmitter")
	emitter.Name = "MagicAura"
	emitter.Rate = c.rate
	emitter.Speed = NumberRange.new(c.speed[1], c.speed[2])
	emitter.Lifetime = NumberRange.new(c.lifetime[1], c.lifetime[2])
	emitter.SpreadAngle = Vector2.new(360, 360)
	emitter.LightEmission = 1
	emitter.LightInfluence = 0
	emitter.Drag = 2
	emitter.RotSpeed = NumberRange.new(-180, 180)
	emitter.Size = NumberSequence.new({
		NumberSequenceKeypoint.new(0, 0),
		NumberSequenceKeypoint.new(0.3, c.size),
		NumberSequenceKeypoint.new(1, 0),
	})
	emitter.Transparency = NumberSequence.new({
		NumberSequenceKeypoint.new(0, 0.5),
		NumberSequenceKeypoint.new(0.5, 0.2),
		NumberSequenceKeypoint.new(1, 1),
	})
	emitter.Color = ColorSequence.new(c.color)
	emitter.Parent = att

	-- Glow light
	local light = Instance.new("PointLight")
	light.Color = c.color
	light.Brightness = 1.5
	light.Range = 12
	light.Parent = parent

	return emitter
end

--- Burst explosion effect (one-shot)
function VFXLibrary.createExplosionEffect(position: Vector3, config: {[string]: any}?): Model
	local c = mergeConfig({
		radius = 8,
		color = Color3.fromRGB(255, 150, 30),
		particleCount = 80,
		debrisCount = 12,
		duration = 2,
	}, config)

	local model = Instance.new("Model")
	model.Name = "Explosion"

	-- Central flash
	local core = Instance.new("Part")
	core.Shape = Enum.PartType.Ball
	core.Size = Vector3.new(1, 1, 1)
	core.Position = position
	core.Material = Enum.Material.Neon
	core.Color = Color3.new(1, 1, 1)
	core.Anchored = true
	core.CanCollide = false
	core.CastShadow = false
	core.Parent = model

	-- Flash expand + fade
	local expandTween = TweenService:Create(core, TweenInfo.new(0.3, Enum.EasingStyle.Expo, Enum.EasingDirection.Out), {
		Size = Vector3.new(c.radius, c.radius, c.radius),
		Transparency = 0.5,
	})

	local fadeTween = TweenService:Create(core, TweenInfo.new(0.5), {
		Transparency = 1,
		Size = Vector3.new(c.radius * 1.5, c.radius * 1.5, c.radius * 1.5),
	})

	-- Particle burst
	local att = ensureAttachment(core, "ExplosionEmitter")
	local emitter = Instance.new("ParticleEmitter")
	emitter.Name = "ExplosionParticles"
	emitter.Rate = 0
	emitter.Speed = NumberRange.new(10, 30)
	emitter.Lifetime = NumberRange.new(0.5, 1.5)
	emitter.SpreadAngle = Vector2.new(360, 360)
	emitter.LightEmission = 1
	emitter.Size = NumberSequence.new({
		NumberSequenceKeypoint.new(0, 2),
		NumberSequenceKeypoint.new(0.3, 3),
		NumberSequenceKeypoint.new(1, 0),
	})
	emitter.Transparency = NumberSequence.new({
		NumberSequenceKeypoint.new(0, 0),
		NumberSequenceKeypoint.new(0.5, 0.5),
		NumberSequenceKeypoint.new(1, 1),
	})
	emitter.Color = ColorSequence.new({
		ColorSequenceKeypoint.new(0, Color3.new(1, 1, 1)),
		ColorSequenceKeypoint.new(0.3, c.color),
		ColorSequenceKeypoint.new(1, Color3.fromRGB(50, 20, 0)),
	})
	emitter.Drag = 5
	emitter.Acceleration = Vector3.new(0, -10, 0)
	emitter.Parent = att

	-- Light flash
	local light = Instance.new("PointLight")
	light.Color = c.color
	light.Brightness = 10
	light.Range = c.radius * 4
	light.Parent = core

	model.Parent = workspace

	-- Animate
	expandTween:Play()
	emitter:Emit(c.particleCount)

	expandTween.Completed:Connect(function()
		fadeTween:Play()
		TweenService:Create(light, TweenInfo.new(1), {Brightness = 0}):Play()
	end)

	-- Debris
	for i = 1, c.debrisCount do
		local debris = Instance.new("Part")
		debris.Size = Vector3.new(0.5, 0.5, 0.5)
		debris.Position = position
		debris.Material = Enum.Material.Neon
		debris.Color = c.color
		debris.Anchored = false
		debris.CanCollide = true
		debris.CastShadow = false
		debris.Parent = model

		local direction = Vector3.new(
			math.random() - 0.5,
			math.random() * 0.5 + 0.3,
			math.random() - 0.5
		).Unit
		debris:ApplyImpulse(direction * math.random(50, 150))

		-- Fade out debris
		task.delay(c.duration * 0.6, function()
			if debris.Parent then
				TweenService:Create(debris, TweenInfo.new(c.duration * 0.4), {
					Transparency = 1,
					Size = Vector3.zero,
				}):Play()
			end
		end)
	end

	-- Cleanup
	task.delay(c.duration + 1, function()
		if model.Parent then model:Destroy() end
	end)

	return model
end

--------------------------------------------------------------------------------
-- BEAM EFFECTS
--------------------------------------------------------------------------------

function VFXLibrary.createLaserBeam(from: BasePart, to: BasePart, config: {[string]: any}?): Beam
	local c = mergeConfig({
		width = 1,
		color = Color3.fromRGB(255, 30, 30),
		lightEmission = 1,
		textureSpeed = 2,
		segments = 1,
	}, config)

	local att0 = ensureAttachment(from, "LaserAtt0")
	local att1 = ensureAttachment(to, "LaserAtt1")

	local beam = Instance.new("Beam")
	beam.Name = "LaserBeam"
	beam.Attachment0 = att0
	beam.Attachment1 = att1
	beam.Width0 = c.width
	beam.Width1 = c.width * 0.8
	beam.LightEmission = c.lightEmission
	beam.LightInfluence = 0
	beam.FaceCamera = true
	beam.Segments = c.segments
	beam.TextureSpeed = c.textureSpeed
	beam.Color = ColorSequence.new(c.color)
	beam.Transparency = NumberSequence.new({
		NumberSequenceKeypoint.new(0, 0),
		NumberSequenceKeypoint.new(1, 0),
	})
	beam.Parent = from

	-- Core glow (thinner bright center)
	local core = Instance.new("Beam")
	core.Name = "LaserCore"
	core.Attachment0 = att0
	core.Attachment1 = att1
	core.Width0 = c.width * 0.3
	core.Width1 = c.width * 0.2
	core.LightEmission = 1
	core.LightInfluence = 0
	core.FaceCamera = true
	core.Color = ColorSequence.new(Color3.new(1, 1, 1))
	core.Transparency = NumberSequence.new(0)
	core.Parent = from

	return beam
end

function VFXLibrary.createLightningEffect(from: BasePart, to: BasePart, config: {[string]: any}?): Folder
	local c = mergeConfig({
		segments = 15,
		jitter = 4,
		thickness = 0.25,
		color = Color3.fromRGB(140, 200, 255),
		branchChance = 0.3,
		branchLength = 0.4,
		animated = true,
		animInterval = 0.08,
	}, config)

	local folder = makeFolder("Lightning")

	local function buildBolt(origin: Vector3, target: Vector3, segments: number, thickness: number, parent: Instance)
		local direction = target - origin
		local step = direction / segments

		local points = {origin}
		for i = 1, segments - 1 do
			local base = origin + step * i
			local offset = Vector3.new(
				(math.random() - 0.5) * c.jitter,
				(math.random() - 0.5) * c.jitter,
				(math.random() - 0.5) * c.jitter
			)
			table.insert(points, base + offset)
		end
		table.insert(points, target)

		local parts = {}
		for i = 1, #points - 1 do
			local p1 = points[i]
			local p2 = points[i + 1]
			local mid = (p1 + p2) / 2
			local dist = (p2 - p1).Magnitude

			local part = Instance.new("Part")
			part.Size = Vector3.new(thickness, thickness, dist)
			part.CFrame = CFrame.lookAt(mid, p2)
			part.Material = Enum.Material.Neon
			part.Color = c.color
			part.Anchored = true
			part.CanCollide = false
			part.CastShadow = false
			part.Parent = parent
			table.insert(parts, part)

			-- Branch
			if math.random() < c.branchChance then
				local branchDir = Vector3.new(
					(math.random() - 0.5) * 2,
					(math.random() - 0.5) * 2,
					(math.random() - 0.5) * 2
				).Unit
				local branchEnd = p1 + branchDir * (dist * c.branchLength * 3)
				buildBolt(p1, branchEnd, 3, thickness * 0.5, parent)
			end
		end

		-- Lights at intervals
		for i = 1, #parts, 4 do
			local light = Instance.new("PointLight")
			light.Color = c.color
			light.Brightness = 3
			light.Range = 10
			light.Parent = parts[i]
		end

		return parts
	end

	local function regenerate()
		for _, child in folder:GetChildren() do
			child:Destroy()
		end
		buildBolt(from.Position, to.Position, c.segments, c.thickness, folder)
	end

	regenerate()

	-- Animated re-generation for flickering lightning
	if c.animated then
		local conn
		local elapsed = 0
		conn = RunService.Heartbeat:Connect(function(dt)
			if not folder.Parent then
				conn:Disconnect()
				return
			end
			elapsed += dt
			if elapsed >= c.animInterval then
				elapsed = 0
				regenerate()
			end
		end)
	end

	return folder
end

function VFXLibrary.createEnergyTether(from: BasePart, to: BasePart, config: {[string]: any}?): Beam
	local c = mergeConfig({
		width = 0.8,
		color = Color3.fromRGB(50, 200, 255),
		curveSize = 4,
		textureSpeed = 3,
		segments = 20,
	}, config)

	local att0 = ensureAttachment(from, "TetherAtt0")
	local att1 = ensureAttachment(to, "TetherAtt1")

	local beam = Instance.new("Beam")
	beam.Name = "EnergyTether"
	beam.Attachment0 = att0
	beam.Attachment1 = att1
	beam.Width0 = c.width
	beam.Width1 = c.width
	beam.LightEmission = 1
	beam.LightInfluence = 0
	beam.FaceCamera = true
	beam.Segments = c.segments
	beam.CurveSize0 = c.curveSize
	beam.CurveSize1 = -c.curveSize
	beam.TextureSpeed = c.textureSpeed
	beam.Color = ColorSequence.new({
		ColorSequenceKeypoint.new(0, c.color),
		ColorSequenceKeypoint.new(0.5, Color3.new(1, 1, 1)),
		ColorSequenceKeypoint.new(1, c.color),
	})
	beam.Transparency = NumberSequence.new({
		NumberSequenceKeypoint.new(0, 0.3),
		NumberSequenceKeypoint.new(0.5, 0),
		NumberSequenceKeypoint.new(1, 0.3),
	})
	beam.Parent = from

	return beam
end

--------------------------------------------------------------------------------
-- TRAIL EFFECTS
--------------------------------------------------------------------------------

function VFXLibrary.createMotionTrail(part: BasePart, config: {[string]: any}?): Trail
	local c = mergeConfig({
		lifetime = 0.8,
		color = Color3.fromRGB(255, 255, 255),
		lightEmission = 0.5,
		widthScale = 1,
		axis = "Y", -- trail spans along Y axis of part
	}, config)

	local halfSize = part.Size / 2
	local pos0, pos1

	if c.axis == "Y" then
		pos0 = Vector3.new(0, -halfSize.Y, 0)
		pos1 = Vector3.new(0, halfSize.Y, 0)
	elseif c.axis == "X" then
		pos0 = Vector3.new(-halfSize.X, 0, 0)
		pos1 = Vector3.new(halfSize.X, 0, 0)
	else
		pos0 = Vector3.new(0, 0, -halfSize.Z)
		pos1 = Vector3.new(0, 0, halfSize.Z)
	end

	local att0 = ensureAttachment(part, "TrailAtt0", pos0)
	local att1 = ensureAttachment(part, "TrailAtt1", pos1)

	local trail = Instance.new("Trail")
	trail.Name = "MotionTrail"
	trail.Attachment0 = att0
	trail.Attachment1 = att1
	trail.Lifetime = c.lifetime
	trail.MinLength = 0.1
	trail.FaceCamera = true
	trail.LightEmission = c.lightEmission
	trail.Color = ColorSequence.new(c.color)
	trail.Transparency = NumberSequence.new({
		NumberSequenceKeypoint.new(0, 0),
		NumberSequenceKeypoint.new(0.7, 0.5),
		NumberSequenceKeypoint.new(1, 1),
	})
	trail.WidthScale = NumberSequence.new({
		NumberSequenceKeypoint.new(0, c.widthScale),
		NumberSequenceKeypoint.new(1, 0),
	})
	trail.Parent = part

	return trail
end

function VFXLibrary.createSwordSlash(tool: Instance, config: {[string]: any}?): Trail
	local c = mergeConfig({
		lifetime = 0.15,
		color = Color3.fromRGB(255, 255, 255),
		lightEmission = 0.8,
	}, config)

	local handle = tool:FindFirstChild("Handle")
	if not handle then
		error("Tool must have a Handle part")
	end

	local att0 = ensureAttachment(handle, "SlashAtt0", Vector3.new(0, -handle.Size.Y/2, 0))
	local att1 = ensureAttachment(handle, "SlashAtt1", Vector3.new(0, handle.Size.Y/2, 0))

	local trail = Instance.new("Trail")
	trail.Name = "SwordSlash"
	trail.Attachment0 = att0
	trail.Attachment1 = att1
	trail.Lifetime = c.lifetime
	trail.MinLength = 0.05
	trail.FaceCamera = true
	trail.LightEmission = c.lightEmission
	trail.Color = ColorSequence.new(c.color)
	trail.Transparency = NumberSequence.new({
		NumberSequenceKeypoint.new(0, 0),
		NumberSequenceKeypoint.new(1, 1),
	})
	trail.WidthScale = NumberSequence.new({
		NumberSequenceKeypoint.new(0, 1),
		NumberSequenceKeypoint.new(0.5, 0.5),
		NumberSequenceKeypoint.new(1, 0),
	})
	trail.Parent = handle

	return trail
end

--------------------------------------------------------------------------------
-- LIGHTING & ATMOSPHERE
--------------------------------------------------------------------------------

function VFXLibrary.setupDramaticLighting(config: {[string]: any}?)
	local c = mergeConfig({
		technology = Enum.Technology.Future,
		ambient = Color3.fromRGB(30, 30, 40),
		outdoorAmbient = Color3.fromRGB(50, 50, 60),
		brightness = 2,
		clockTime = 14,
		bloomIntensity = 0.5,
		bloomSize = 24,
		bloomThreshold = 0.8,
		ccBrightness = 0.05,
		ccContrast = 0.1,
		ccSaturation = 0.2,
		tintColor = Color3.fromRGB(255, 245, 230),
		sunRaysIntensity = 0.15,
		sunRaysSpread = 0.5,
		atmoDensity = 0.3,
		atmoOffset = 0.25,
		atmoColor = Color3.fromRGB(199, 199, 210),
		atmoDecay = Color3.fromRGB(92, 100, 120),
		dofFar = 0.2,
		dofFocus = 50,
		dofRadius = 30,
		dofNear = 0.5,
	}, config)

	Lighting.Technology = c.technology
	Lighting.Ambient = c.ambient
	Lighting.OutdoorAmbient = c.outdoorAmbient
	Lighting.Brightness = c.brightness
	Lighting.ClockTime = c.clockTime

	-- Bloom
	local bloom = Lighting:FindFirstChildOfClass("BloomEffect") or Instance.new("BloomEffect")
	bloom.Intensity = c.bloomIntensity
	bloom.Size = c.bloomSize
	bloom.Threshold = c.bloomThreshold
	bloom.Parent = Lighting

	-- Color Correction
	local cc = Lighting:FindFirstChildOfClass("ColorCorrectionEffect") or Instance.new("ColorCorrectionEffect")
	cc.Brightness = c.ccBrightness
	cc.Contrast = c.ccContrast
	cc.Saturation = c.ccSaturation
	cc.TintColor = c.tintColor
	cc.Parent = Lighting

	-- Sun Rays
	local rays = Lighting:FindFirstChildOfClass("SunRaysEffect") or Instance.new("SunRaysEffect")
	rays.Intensity = c.sunRaysIntensity
	rays.Spread = c.sunRaysSpread
	rays.Parent = Lighting

	-- Atmosphere
	local atmo = Lighting:FindFirstChildOfClass("Atmosphere") or Instance.new("Atmosphere")
	atmo.Density = c.atmoDensity
	atmo.Offset = c.atmoOffset
	atmo.Color = c.atmoColor
	atmo.Decay = c.atmoDecay
	atmo.Glare = 0.5
	atmo.Haze = 1.5
	atmo.Parent = Lighting

	-- Depth of Field
	local dof = Lighting:FindFirstChildOfClass("DepthOfFieldEffect") or Instance.new("DepthOfFieldEffect")
	dof.FarIntensity = c.dofFar
	dof.FocusDistance = c.dofFocus
	dof.InFocusRadius = c.dofRadius
	dof.NearIntensity = c.dofNear
	dof.Parent = Lighting

	print("[VFX] Dramatic lighting configured")
end

function VFXLibrary.createGodRays(config: {[string]: any}?)
	local c = mergeConfig({
		intensity = 0.25,
		spread = 0.8,
		clockTime = 7, -- sunrise angle
	}, config)

	Lighting.ClockTime = c.clockTime

	local rays = Lighting:FindFirstChildOfClass("SunRaysEffect") or Instance.new("SunRaysEffect")
	rays.Intensity = c.intensity
	rays.Spread = c.spread
	rays.Parent = Lighting

	-- Enhance with atmosphere
	local atmo = Lighting:FindFirstChildOfClass("Atmosphere") or Instance.new("Atmosphere")
	atmo.Density = 0.4
	atmo.Offset = 0
	atmo.Haze = 2
	atmo.Glare = 1
	atmo.Parent = Lighting

	print("[VFX] God rays configured")
end

function VFXLibrary.setupNeonGlow(part: BasePart, color: Color3?, intensity: number?)
	color = color or Color3.fromRGB(0, 170, 255)
	intensity = intensity or 2

	part.Material = Enum.Material.Neon
	part.Color = color

	local light = Instance.new("PointLight")
	light.Color = color
	light.Brightness = intensity
	light.Range = math.max(part.Size.X, part.Size.Y, part.Size.Z) * 3
	light.Parent = part

	print("[VFX] Neon glow applied to " .. part.Name)
end

--------------------------------------------------------------------------------
-- COMPOSITE EFFECTS
--------------------------------------------------------------------------------

function VFXLibrary.createPortalEffect(position: Vector3, config: {[string]: any}?): Model
	local c = mergeConfig({
		size = 8,
		color = Color3.fromRGB(100, 50, 255),
		particleRate = 50,
		rotationSpeed = 60, -- degrees per second
		name = "Portal",
	}, config)

	local model = Instance.new("Model")
	model.Name = c.name

	-- Outer ring
	local ring = Instance.new("Part")
	ring.Name = "Ring"
	ring.Shape = Enum.PartType.Cylinder
	ring.Size = Vector3.new(0.5, c.size, c.size)
	ring.CFrame = CFrame.new(position) * CFrame.Angles(0, 0, math.rad(90))
	ring.Material = Enum.Material.Neon
	ring.Color = c.color
	ring.Anchored = true
	ring.CanCollide = false
	ring.CastShadow = false
	ring.Parent = model

	-- Inner core (bright white center)
	local inner = Instance.new("Part")
	inner.Name = "InnerCore"
	inner.Shape = Enum.PartType.Cylinder
	inner.Size = Vector3.new(0.3, c.size * 0.8, c.size * 0.8)
	inner.CFrame = ring.CFrame
	inner.Material = Enum.Material.Neon
	inner.Color = Color3.new(1, 1, 1)
	inner.Transparency = 0.4
	inner.Anchored = true
	inner.CanCollide = false
	inner.CastShadow = false
	inner.Parent = model

	-- Swirling particles
	local att = ensureAttachment(ring, "PortalParticles")
	local emitter = Instance.new("ParticleEmitter")
	emitter.Rate = c.particleRate
	emitter.Speed = NumberRange.new(1, 3)
	emitter.Lifetime = NumberRange.new(0.8, 2)
	emitter.SpreadAngle = Vector2.new(360, 360)
	emitter.LightEmission = 1
	emitter.LightInfluence = 0
	emitter.Size = NumberSequence.new({
		NumberSequenceKeypoint.new(0, 0.5),
		NumberSequenceKeypoint.new(0.5, 0.8),
		NumberSequenceKeypoint.new(1, 0),
	})
	emitter.Color = ColorSequence.new({
		ColorSequenceKeypoint.new(0, c.color),
		ColorSequenceKeypoint.new(0.5, Color3.new(1, 1, 1)),
		ColorSequenceKeypoint.new(1, c.color),
	})
	emitter.Transparency = NumberSequence.new({
		NumberSequenceKeypoint.new(0, 0.3),
		NumberSequenceKeypoint.new(1, 1),
	})
	emitter.Parent = att

	-- Central light
	local light = Instance.new("PointLight")
	light.Color = c.color
	light.Brightness = 3
	light.Range = c.size * 2.5
	light.Parent = ring

	-- Rotation animation
	local conn
	conn = RunService.Heartbeat:Connect(function(dt)
		if not ring.Parent then
			conn:Disconnect()
			return
		end
		inner.CFrame = inner.CFrame * CFrame.Angles(math.rad(c.rotationSpeed * dt), 0, 0)
	end)

	model.Parent = workspace
	print("[VFX] Portal created at " .. tostring(position))
	return model
end

function VFXLibrary.createTeleportEffect(character: Model, config: {[string]: any}?): ()
	local c = mergeConfig({
		color = Color3.fromRGB(50, 200, 255),
		duration = 1.5,
		particleCount = 100,
	}, config)

	local root = character:FindFirstChild("HumanoidRootPart")
	if not root then return end

	-- Rising particles
	local att = ensureAttachment(root, "TeleportEmitter")
	local emitter = Instance.new("ParticleEmitter")
	emitter.Rate = 0
	emitter.Speed = NumberRange.new(5, 15)
	emitter.Lifetime = NumberRange.new(0.5, 1)
	emitter.EmissionDirection = Enum.NormalId.Top
	emitter.SpreadAngle = Vector2.new(30, 30)
	emitter.LightEmission = 1
	emitter.Size = NumberSequence.new({
		NumberSequenceKeypoint.new(0, 0.5),
		NumberSequenceKeypoint.new(1, 0),
	})
	emitter.Color = ColorSequence.new(c.color)
	emitter.Transparency = NumberSequence.new({
		NumberSequenceKeypoint.new(0, 0),
		NumberSequenceKeypoint.new(1, 1),
	})
	emitter.Parent = att

	-- Light flash
	local light = Instance.new("PointLight")
	light.Color = c.color
	light.Brightness = 0
	light.Range = 20
	light.Parent = root

	-- Animate
	emitter:Emit(c.particleCount)
	TweenService:Create(light, TweenInfo.new(c.duration * 0.3, Enum.EasingStyle.Expo), {Brightness = 5}):Play()

	task.delay(c.duration * 0.5, function()
		TweenService:Create(light, TweenInfo.new(c.duration * 0.5), {Brightness = 0}):Play()
	end)

	task.delay(c.duration + 0.5, function()
		att:Destroy()
		light:Destroy()
	end)
end

function VFXLibrary.createImpactEffect(position: Vector3, normal: Vector3?, config: {[string]: any}?): Model
	local c = mergeConfig({
		color = Color3.fromRGB(255, 200, 50),
		size = 3,
		duration = 0.8,
		particleCount = 30,
	}, config)

	normal = normal or Vector3.new(0, 1, 0)

	local model = Instance.new("Model")
	model.Name = "Impact"

	-- Ground crack/mark
	local mark = Instance.new("Part")
	mark.Size = Vector3.new(c.size, 0.1, c.size)
	mark.CFrame = CFrame.lookAt(position, position + normal) * CFrame.Angles(math.rad(-90), 0, 0)
	mark.Material = Enum.Material.Neon
	mark.Color = c.color
	mark.Anchored = true
	mark.CanCollide = false
	mark.CastShadow = false
	mark.Transparency = 0.3
	mark.Parent = model

	-- Particle burst along normal
	local att = ensureAttachment(mark, "ImpactEmitter")
	local emitter = Instance.new("ParticleEmitter")
	emitter.Rate = 0
	emitter.Speed = NumberRange.new(5, 15)
	emitter.Lifetime = NumberRange.new(0.3, 0.8)
	emitter.SpreadAngle = Vector2.new(60, 60)
	emitter.LightEmission = 1
	emitter.Drag = 8
	emitter.Size = NumberSequence.new({
		NumberSequenceKeypoint.new(0, 1),
		NumberSequenceKeypoint.new(1, 0),
	})
	emitter.Color = ColorSequence.new(c.color)
	emitter.Transparency = NumberSequence.new({
		NumberSequenceKeypoint.new(0, 0),
		NumberSequenceKeypoint.new(1, 1),
	})
	emitter.Parent = att
	emitter:Emit(c.particleCount)

	-- Light flash
	local light = Instance.new("PointLight")
	light.Color = c.color
	light.Brightness = 5
	light.Range = c.size * 3
	light.Parent = mark

	model.Parent = workspace

	-- Fade and cleanup
	TweenService:Create(mark, TweenInfo.new(c.duration), {Transparency = 1, Size = Vector3.new(c.size * 1.5, 0.1, c.size * 1.5)}):Play()
	TweenService:Create(light, TweenInfo.new(c.duration), {Brightness = 0}):Play()

	task.delay(c.duration + 0.5, function()
		if model.Parent then model:Destroy() end
	end)

	return model
end

--------------------------------------------------------------------------------
-- ANIMATION UTILITIES
--------------------------------------------------------------------------------

--- Smooth pulsating effect on any part
function VFXLibrary.pulseEffect(part: BasePart, config: {[string]: any}?): Tween
	local c = mergeConfig({
		scale = 1.15,
		duration = 1,
		maxTransparency = 0.3,
	}, config)

	local tweenInfo = TweenInfo.new(
		c.duration,
		Enum.EasingStyle.Sine,
		Enum.EasingDirection.InOut,
		-1,
		true
	)

	local tween = TweenService:Create(part, tweenInfo, {
		Size = part.Size * c.scale,
		Transparency = c.maxTransparency,
	})
	tween:Play()
	return tween
end

--- Floating hover effect (up and down bobbing)
function VFXLibrary.floatEffect(part: BasePart, config: {[string]: any}?): ()
	local c = mergeConfig({
		amplitude = 1,
		speed = 1,
	}, config)

	local originalY = part.Position.Y
	local conn
	conn = RunService.Heartbeat:Connect(function()
		if not part.Parent then
			conn:Disconnect()
			return
		end
		local offset = math.sin(tick() * c.speed * math.pi) * c.amplitude
		part.Position = Vector3.new(part.Position.X, originalY + offset, part.Position.Z)
	end)
end

--- Spinning rotation effect
function VFXLibrary.spinEffect(part: BasePart, config: {[string]: any}?): ()
	local c = mergeConfig({
		speed = 90, -- degrees per second
		axis = "Y",
	}, config)

	local conn
	conn = RunService.Heartbeat:Connect(function(dt)
		if not part.Parent then
			conn:Disconnect()
			return
		end
		local angle = math.rad(c.speed * dt)
		if c.axis == "Y" then
			part.CFrame = part.CFrame * CFrame.Angles(0, angle, 0)
		elseif c.axis == "X" then
			part.CFrame = part.CFrame * CFrame.Angles(angle, 0, 0)
		elseif c.axis == "Z" then
			part.CFrame = part.CFrame * CFrame.Angles(0, 0, angle)
		end
	end)
end

return VFXLibrary
