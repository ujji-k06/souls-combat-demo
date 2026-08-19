--!strict
local RunService = game:GetService("RunService")
local UserInputService = game:GetService("UserInputService")
local ContextActionService = game:GetService("ContextActionService")

local Assets = {}

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
		UserInputService.MouseIconEnabled = false
		scale.Scale = 1 + 0.03 * math.sin(os.clock() * 3.1)
	end)
end

function Assets.boot(player: Player)
	Assets.unbindShiftLock()
	UserInputService.MouseIconEnabled = false
	Assets.mountCursor(player)
end

local function feetDust(hrp: BasePart): ParticleEmitter
	local att = hrp:FindFirstChild("DustAttachment") :: Attachment?
	if not att then
		att = Instance.new("Attachment")
		att.Name = "DustAttachment"
		att.Position = Vector3.new(0, -3, 0)
		att.Parent = hrp
	end
	local pe = att:FindFirstChild("DashDust") :: ParticleEmitter?
	if pe then
		return pe
	end
	pe = Instance.new("ParticleEmitter")
	pe.Name = "DashDust"
	pe.Texture = "rbxasset://textures/particles/smoke_main.dds"
	pe.Enabled = false
	pe.LockedToPart = true
	pe.LightEmission = 0
	pe.LightInfluence = 1
	pe.Rate = 28
	pe.Lifetime = NumberRange.new(0.22, 0.4)
	pe.Speed = NumberRange.new(0.4, 1.6)
	pe.SpreadAngle = Vector2.new(80, 25)
	pe.Acceleration = Vector3.new(0, 1.5, 0)
	pe.Drag = 4
	pe.Rotation = NumberRange.new(0, 360)
	pe.RotSpeed = NumberRange.new(-40, 40)
	pe.Size = NumberSequence.new({
		NumberSequenceKeypoint.new(0, 0.28),
		NumberSequenceKeypoint.new(0.35, 0.55),
		NumberSequenceKeypoint.new(1, 0.7),
	})
	pe.Transparency = NumberSequence.new({
		NumberSequenceKeypoint.new(0, 0.35),
		NumberSequenceKeypoint.new(0.45, 0.7),
		NumberSequenceKeypoint.new(1, 1),
	})
	pe.Color = ColorSequence.new(Color3.fromRGB(92, 80, 64), Color3.fromRGB(58, 50, 40))
	pe.EmissionDirection = Enum.NormalId.Top
	pe.VelocityInheritance = 0.25
	pe.Parent = att
	return pe
end

function Assets.setDashDust(hrp: BasePart, _dashDir: Vector3, on: boolean)
	local pe = feetDust(hrp)
	pe.Enabled = on
	if on then
		pe:Emit(6)
	end
end

return Assets
