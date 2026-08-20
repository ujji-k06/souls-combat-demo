--!strict
local RunService = game:GetService("RunService")
local UserInputService = game:GetService("UserInputService")
local ContextActionService = game:GetService("ContextActionService")
local StarterGui = game:GetService("StarterGui")
local TweenService = game:GetService("TweenService")
local Debris = game:GetService("Debris")

local Assets = {}
local cursorRoot: Frame? = nil
local shiftLockEnabled = true

function Assets.unbindShiftLock()
	for _, name in { "MouseLockSwitchAction", "MouseLockSwitch", "ShiftLockSwitch" } do
		pcall(ContextActionService.UnbindAction, ContextActionService, name)
	end
end

function Assets.mountCursor(player: Player)
	local playerGui = player:WaitForChild("PlayerGui")
	if playerGui:FindFirstChild("SoulsCursor") then
		return
	end

	local gui = Instance.new("ScreenGui")
	gui.Name = "SoulsCursor"
	gui.IgnoreGuiInset = true
	gui.ResetOnSpawn = false
	gui.DisplayOrder = 1e5
	gui.Parent = playerGui

	local root = Instance.new("Frame")
	root.Name = "Root"
	root.BackgroundTransparency = 1
	root.AnchorPoint = Vector2.new(0.5, 0.5)
	root.Position = UDim2.fromScale(0.5, 0.5)
	root.Size = UDim2.fromOffset(22, 22)
	root.Parent = gui
	cursorRoot = root
	root.Visible = shiftLockEnabled

	local ring = Instance.new("Frame")
	ring.AnchorPoint = Vector2.new(0.5, 0.5)
	ring.Position = UDim2.fromScale(0.5, 0.5)
	ring.Size = UDim2.fromOffset(10, 10)
	ring.BackgroundTransparency = 1
	ring.Parent = root
	local corner = Instance.new("UICorner")
	corner.CornerRadius = UDim.new(1, 0)
	corner.Parent = ring
	local stroke = Instance.new("UIStroke")
	stroke.Color = Color3.fromRGB(244, 239, 228)
	stroke.Thickness = 1
	stroke.Parent = ring

	local dot = Instance.new("Frame")
	dot.AnchorPoint = Vector2.new(0.5, 0.5)
	dot.Position = UDim2.fromScale(0.5, 0.5)
	dot.Size = UDim2.fromOffset(2, 2)
	dot.BackgroundColor3 = Color3.fromRGB(244, 239, 228)
	dot.BorderSizePixel = 0
	dot.Parent = root
	local dotCorner = Instance.new("UICorner")
	dotCorner.CornerRadius = UDim.new(1, 0)
	dotCorner.Parent = dot

	local function tick(pos: UDim2, size: UDim2)
		local f = Instance.new("Frame")
		f.BorderSizePixel = 0
		f.BackgroundColor3 = Color3.fromRGB(244, 239, 228)
		f.Position = pos
		f.Size = size
		f.Parent = root
	end
	tick(UDim2.fromOffset(10, 1), UDim2.fromOffset(2, 4))
	tick(UDim2.fromOffset(10, 17), UDim2.fromOffset(2, 4))
	tick(UDim2.fromOffset(1, 10), UDim2.fromOffset(4, 2))
	tick(UDim2.fromOffset(17, 10), UDim2.fromOffset(4, 2))

	local scale = Instance.new("UIScale")
	scale.Parent = root
	pcall(RunService.UnbindFromRenderStep, RunService, "SoulsCursor")
	RunService:BindToRenderStep("SoulsCursor", Enum.RenderPriority.Last.Value, function()
		UserInputService.MouseIconEnabled = not shiftLockEnabled
		if cursorRoot then
			cursorRoot.Visible = shiftLockEnabled
		end
		scale.Scale = 1 + 0.03 * math.sin(os.clock() * 3.1)
	end)
end

function Assets.setShiftLock(enabled: boolean)
	shiftLockEnabled = enabled
	if cursorRoot then
		cursorRoot.Visible = enabled
	end
	UserInputService.MouseIconEnabled = not enabled
end

local function disableNativeUi()
	pcall(StarterGui.SetCoreGuiEnabled, StarterGui, Enum.CoreGuiType.All, false)
	pcall(StarterGui.SetCore, StarterGui, "TopbarEnabled", false)
end

function Assets.boot(player: Player)
	Assets.unbindShiftLock()
	Assets.setShiftLock(true)
	Assets.mountCursor(player)
	disableNativeUi()
	task.delay(1, disableNativeUi)
end

local PUFF_TEXTURE = "rbxassetid://108381592137074"
local LINE_TEXTURE = "rbxassetid://6423572458"

local floorRay = RaycastParams.new()
floorRay.FilterType = Enum.RaycastFilterType.Exclude
floorRay.RespectCanCollide = true

local lastRockPos: Vector3? = nil

local function named(parent: Instance, className: string, name: string, pos: Vector3?): Instance
	local existing = parent:FindFirstChild(name)
	if existing and existing.ClassName == className then
		return existing
	end
	local inst = Instance.new(className)
	inst.Name = name
	if inst:IsA("Attachment") and pos then
		inst.Position = pos
	end
	if inst:IsA("ParticleEmitter") then
		inst.Enabled = false
	end
	inst.Parent = parent
	return inst
end

local function cartoonFloor(color: Color3): (Color3, Color3)
	local h, s, v = color:ToHSV()
	local base = Color3.fromHSV(h, math.clamp(s * 0.68, 0, 0.9), math.clamp(math.max(v, 0.26) * 1.18, 0, 1))
	return base:Lerp(Color3.new(1, 1, 1), 0.22), base:Lerp(Color3.fromRGB(36, 28, 24), 0.22)
end

local function paint(pe: ParticleEmitter, hi: Color3, lo: Color3, emit: number)
	pe.Color = ColorSequence.new(hi, lo)
	pe.LightInfluence = 0
	pe.LightEmission = emit
	pe.Brightness = 2.1
end

local function stylePuffs(pe: ParticleEmitter)
	pe.Texture = PUFF_TEXTURE
	pe.FlipbookLayout = Enum.ParticleFlipbookLayout.Grid4x4
	pe.FlipbookMode = Enum.ParticleFlipbookMode.OneShot
	pe.FlipbookFramerate = NumberRange.new(24, 30)
	pe.FlipbookStartRandom = false
	pe.LockedToPart = false
	pe.Rate = 18
	pe.Lifetime = NumberRange.new(0.38, 0.58)
	pe.Speed = NumberRange.new(4, 10)
	pe.SpreadAngle = Vector2.new(32, 18)
	pe.Acceleration = Vector3.new(0, 11, 0)
	pe.Drag = 4.5
	pe.Orientation = Enum.ParticleOrientation.FacingCamera
	pe.Rotation = NumberRange.new(-25, 25)
	pe.RotSpeed = NumberRange.new(-40, 40)
	pe.Squash = NumberSequence.new(0.08)
	pe.ZOffset = 1.4
	pe.Size = NumberSequence.new({
		NumberSequenceKeypoint.new(0, 2.4),
		NumberSequenceKeypoint.new(0.2, 4.8),
		NumberSequenceKeypoint.new(1, 6.2),
	})
	pe.Transparency = NumberSequence.new({
		NumberSequenceKeypoint.new(0, 0.06),
		NumberSequenceKeypoint.new(0.55, 0.2),
		NumberSequenceKeypoint.new(1, 1),
	})
	pe.EmissionDirection = Enum.NormalId.Back
	pe.VelocityInheritance = 0.16
end

local function styleSkid(pe: ParticleEmitter)
	pe.Texture = PUFF_TEXTURE
	pe.FlipbookLayout = Enum.ParticleFlipbookLayout.Grid4x4
	pe.FlipbookMode = Enum.ParticleFlipbookMode.OneShot
	pe.FlipbookFramerate = NumberRange.new(26, 30)
	pe.FlipbookStartRandom = false
	pe.LockedToPart = false
	pe.Rate = 22
	pe.Lifetime = NumberRange.new(0.3, 0.48)
	pe.Speed = NumberRange.new(8, 16)
	pe.SpreadAngle = Vector2.new(22, 8)
	pe.Acceleration = Vector3.zero
	pe.Drag = 5.5
	pe.Orientation = Enum.ParticleOrientation.FacingCameraWorldUp
	pe.Rotation = NumberRange.new(-16, 16)
	pe.RotSpeed = NumberRange.new(-18, 18)
	pe.Squash = NumberSequence.new(-0.62)
	pe.ZOffset = 0.4
	pe.Size = NumberSequence.new({
		NumberSequenceKeypoint.new(0, 1.8),
		NumberSequenceKeypoint.new(0.28, 4.2),
		NumberSequenceKeypoint.new(1, 5.4),
	})
	pe.Transparency = NumberSequence.new({
		NumberSequenceKeypoint.new(0, 0.08),
		NumberSequenceKeypoint.new(0.5, 0.3),
		NumberSequenceKeypoint.new(1, 1),
	})
	pe.EmissionDirection = Enum.NormalId.Back
	pe.VelocityInheritance = 0.2
end

local function styleLines(pe: ParticleEmitter)
	pe.Texture = LINE_TEXTURE
	pe.FlipbookLayout = Enum.ParticleFlipbookLayout.None
	pe.LockedToPart = false
	pe.Rate = 64
	pe.Lifetime = NumberRange.new(0.08, 0.16)
	pe.Speed = NumberRange.new(28, 52)
	pe.SpreadAngle = Vector2.new(10, 7)
	pe.Acceleration = Vector3.zero
	pe.Drag = 1.2
	pe.Orientation = Enum.ParticleOrientation.VelocityParallel
	pe.Rotation = NumberRange.new(0, 0)
	pe.RotSpeed = NumberRange.new(0, 0)
	pe.Squash = NumberSequence.new(-0.82)
	pe.ZOffset = 2.2
	pe.Size = NumberSequence.new({
		NumberSequenceKeypoint.new(0, 1.15),
		NumberSequenceKeypoint.new(0.35, 0.7),
		NumberSequenceKeypoint.new(1, 0.12),
	})
	pe.Transparency = NumberSequence.new({
		NumberSequenceKeypoint.new(0, 0.12),
		NumberSequenceKeypoint.new(0.55, 0.4),
		NumberSequenceKeypoint.new(1, 1),
	})
	pe.EmissionDirection = Enum.NormalId.Back
	pe.VelocityInheritance = 0.45
end

local function sampleFloor(hrp: BasePart): (Color3, Vector3, Vector3)
	floorRay.FilterDescendantsInstances = { hrp.Parent }
	local hit = workspace:Raycast(hrp.Position, Vector3.new(0, -12, 0), floorRay)
	if not hit then
		return Color3.fromRGB(198, 178, 148), hrp.Position + Vector3.new(0, -3, 0), Vector3.yAxis
	end
	local color = Color3.fromRGB(198, 178, 148)
	if hit.Instance:IsA("Terrain") then
		color = workspace.Terrain:GetMaterialColor(hit.Material)
	elseif hit.Instance:IsA("BasePart") then
		color = hit.Instance.Color
	end
	return color, hit.Position, hit.Normal
end

local function lookAlong(dir: Vector3, normal: Vector3, fallback: Vector3): Vector3
	local look = if dir.Magnitude > 0.01 then dir.Unit else fallback
	if math.abs(look:Dot(normal)) > 0.97 then
		look = fallback
	end
	return look
end

local function axisCFrame(pos: Vector3, xAxis: Vector3): CFrame
	local x = xAxis.Unit
	local helper = if math.abs(x.Y) < 0.94 then Vector3.yAxis else Vector3.zAxis
	local z = x:Cross(helper)
	if z.Magnitude < 1e-4 then
		z = Vector3.zAxis
	end
	z = z.Unit
	return CFrame.fromMatrix(pos, x, z:Cross(x).Unit, z)
end

local function shockRing(
	pos: Vector3,
	normal: Vector3,
	color: Color3,
	startDia: number,
	endDia: number,
	thick: number,
	time: number,
	neon: boolean
)
	local ring = Instance.new("Part")
	ring.Name = "DashShock"
	ring.Shape = Enum.PartType.Cylinder
	ring.Anchored = true
	ring.CanCollide = false
	ring.CanQuery = false
	ring.CanTouch = false
	ring.CastShadow = false
	ring.Material = if neon then Enum.Material.Neon else Enum.Material.SmoothPlastic
	ring.Color = color
	ring.Transparency = 0.12
	ring.Size = Vector3.new(thick, startDia, startDia)
	ring.CFrame = axisCFrame(pos + normal * 0.07, normal)
	ring.Parent = workspace
	local tw = TweenService:Create(
		ring,
		TweenInfo.new(time, Enum.EasingStyle.Quad, Enum.EasingDirection.Out),
		{ Size = Vector3.new(thick * 0.3, endDia, endDia), Transparency = 1 }
	)
	tw:Play()
	Debris:AddItem(ring, time + 0.05)
end

local function spawnRocks(origin: Vector3, normal: Vector3, dir: Vector3, color: Color3, count: number)
	local side = dir:Cross(normal)
	side = if side.Magnitude > 0.01 then side.Unit else Vector3.xAxis
	for _ = 1, count do
		local s = 0.28 + math.random() * 0.55
		local rock = Instance.new("Part")
		rock.Name = "DashRock"
		rock.Size = Vector3.new(s, s * (0.45 + math.random() * 0.7), s * (0.55 + math.random() * 0.85))
		rock.Color = color
		rock.Material = Enum.Material.SmoothPlastic
		rock.TopSurface = Enum.SurfaceType.Smooth
		rock.BottomSurface = Enum.SurfaceType.Smooth
		rock.CanCollide = false
		rock.CanQuery = false
		rock.CanTouch = false
		rock.CastShadow = false
		rock.Massless = true
		rock.CFrame = CFrame.new(origin + normal * 0.18)
			* CFrame.Angles(math.random() * 6.2, math.random() * 6.2, math.random() * 6.2)
		rock.Parent = workspace
		rock.AssemblyLinearVelocity = dir * -(6 + math.random() * 12)
			+ side * ((math.random() - 0.5) * 18)
			+ normal * (16 + math.random() * 14)
		rock.AssemblyAngularVelocity = Vector3.new(math.random() * 14, math.random() * 14, math.random() * 14)
		Debris:AddItem(rock, 0.6)
	end
end

local function dashKit(
	hrp: BasePart
): (Attachment, Attachment, ParticleEmitter, ParticleEmitter, ParticleEmitter, Trail)
	local feet = named(hrp, "Attachment", "DustAttachment") :: Attachment
	local linesAtt = named(hrp, "Attachment", "DashLineAttachment", Vector3.new(0, 0.45, 0)) :: Attachment
	named(hrp, "Attachment", "DashTrail0", Vector3.new(-1.15, 0.55, 0.25))
	named(hrp, "Attachment", "DashTrail1", Vector3.new(1.15, 0.55, 0.25))
	local puffs = named(feet, "ParticleEmitter", "DashDust") :: ParticleEmitter
	local skid = named(feet, "ParticleEmitter", "DashSkid") :: ParticleEmitter
	local lines = named(linesAtt, "ParticleEmitter", "DashLines") :: ParticleEmitter
	local leftover = feet:FindFirstChild("DashSpecks")
	if leftover then
		leftover:Destroy()
	end
	local trail = named(hrp, "Trail", "DashTrail") :: Trail
	return feet, linesAtt, puffs, skid, lines, trail
end

local function alignDash(hrp: BasePart, dashDir: Vector3): (Color3, Vector3, Vector3)
	local feet, linesAtt = dashKit(hrp)
	local color, pos, normal = sampleFloor(hrp)
	local look = lookAlong(dashDir, normal, hrp.CFrame.LookVector)
	local worldPos = pos + normal * 0.14
	feet.CFrame = hrp.CFrame:ToObjectSpace(CFrame.lookAt(worldPos, worldPos + look, normal))
	local body = hrp.Position + Vector3.new(0, 0.45, 0)
	linesAtt.CFrame = hrp.CFrame:ToObjectSpace(CFrame.lookAt(body, body + look))
	return color, pos, normal
end

function Assets.setDashDust(hrp: BasePart, dashDir: Vector3, on: boolean)
	local _, _, puffs, skid, lines, trail = dashKit(hrp)
	stylePuffs(puffs)
	styleSkid(skid)
	styleLines(lines)
	trail.Attachment0 = hrp:FindFirstChild("DashTrail0") :: Attachment
	trail.Attachment1 = hrp:FindFirstChild("DashTrail1") :: Attachment
	trail.FaceCamera = true
	trail.LightEmission = 0.55
	trail.LightInfluence = 0
	trail.Lifetime = 0.2
	trail.MinLength = 0.05
	trail.Texture = LINE_TEXTURE
	trail.TextureLength = 1.4
	trail.TextureMode = Enum.TextureMode.Stretch
	trail.Color = ColorSequence.new(Color3.fromRGB(255, 252, 245))
	trail.Transparency = NumberSequence.new({
		NumberSequenceKeypoint.new(0, 0.28),
		NumberSequenceKeypoint.new(1, 1),
	})
	trail.WidthScale = NumberSequence.new({
		NumberSequenceKeypoint.new(0, 1.35),
		NumberSequenceKeypoint.new(1, 0.12),
	})
	local color, pos, normal = alignDash(hrp, dashDir)
	local hi, lo = cartoonFloor(color)
	paint(puffs, hi, lo, 0.1)
	paint(skid, hi, lo, 0.08)
	paint(lines, Color3.fromRGB(255, 252, 240), Color3.fromRGB(220, 210, 190), 0.72)
	puffs.Enabled = on
	skid.Enabled = on
	lines.Enabled = on
	trail.Enabled = on
	if on then
		lastRockPos = hrp.Position
		puffs:Emit(12)
		skid:Emit(16)
		lines:Emit(18)
		spawnRocks(pos, normal, lookAlong(dashDir, normal, hrp.CFrame.LookVector), hi, 8)
		shockRing(pos, normal, Color3.fromRGB(255, 250, 240), 2.2, 11, 0.22, 0.26, true)
		shockRing(pos, normal, hi, 3.4, 16.5, 0.16, 0.38, false)
	else
		puffs:Emit(4)
		skid:Emit(5)
		lastRockPos = nil
	end
end

function Assets.stepDashDust(hrp: BasePart, dashDir: Vector3)
	local color, pos, normal = alignDash(hrp, dashDir)
	if lastRockPos and (hrp.Position - lastRockPos).Magnitude >= 3.4 then
		lastRockPos = hrp.Position
		local hi = cartoonFloor(color)
		spawnRocks(pos, normal, lookAlong(dashDir, normal, hrp.CFrame.LookVector), hi, 3)
	end
end

return Assets
