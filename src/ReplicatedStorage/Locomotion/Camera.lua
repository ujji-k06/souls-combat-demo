--!strict
local Config = require(script.Parent.Config)
local Assets = require(script.Parent.Assets)

local RunService = game:GetService("RunService")
local UserInputService = game:GetService("UserInputService")

export type Api = {
	start: (player: Player) -> (),
	GetYaw: () -> number,
	GetLookFlat: () -> Vector3,
	NotifyGait: (gait: string) -> (),
	PunchFov: () -> (),
}

local RENDER_NAME = "LocomotionCamera"
local MOUSE_EPS = 0.001

local cfg = Config.Camera

local yaw = 0
local pitch = 0
local pivot = Vector3.zero
local pivotVel = Vector3.zero
local pivotReady = false
local currentDist = cfg.Distance
local targetDist = cfg.Distance
local gait = "idle"
local fovPunch = 0
local character: Model? = nil
local root: BasePart? = nil
local rayParams = RaycastParams.new()

local Camera = {} :: Api

local function refreshCharacter(char: Model)
	character = char
	root = char:WaitForChild("HumanoidRootPart") :: BasePart
	local look = root.CFrame.LookVector
	yaw = math.atan2(-look.X, -look.Z)
	pitch = 0
	pivotReady = false
	pivotVel = Vector3.zero
	rayParams.FilterDescendantsInstances = { char }
end

local function gamepadLook(dt: number)
	if not UserInputService.GamepadEnabled then
		return
	end
	for _, input in UserInputService:GetGamepadState(Enum.UserInputType.Gamepad1) do
		if input.KeyCode == Enum.KeyCode.Thumbstick2 then
			local stick = Vector2.new(input.Position.X, input.Position.Y)
			local mag = stick.Magnitude
			if mag <= cfg.GamepadDeadzone then
				return
			end
			local scale = (mag - cfg.GamepadDeadzone) / (1 - cfg.GamepadDeadzone)
			local dir = stick.Unit * scale
			yaw -= dir.X * cfg.GamepadSensitivity * dt
			pitch -= dir.Y * cfg.GamepadSensitivity * dt
			return
		end
	end
end

local function onRenderStep(dt: number)
	local cam = workspace.CurrentCamera
	if not cam or not root or not character or not character.Parent then
		return
	end

	cam.CameraType = Enum.CameraType.Scriptable
	UserInputService.MouseBehavior = Enum.MouseBehavior.LockCenter
	UserInputService.MouseIconEnabled = false

	local delta = UserInputService:GetMouseDelta()
	if delta.Magnitude > MOUSE_EPS then
		yaw -= delta.X * cfg.Sensitivity
		pitch -= delta.Y * cfg.Sensitivity
	else
		gamepadLook(dt)
	end

	pitch = math.clamp(pitch, cfg.PitchMin, cfg.PitchMax)

	local height = if gait == "crouch" then cfg.CrouchHeight else cfg.Height
	local desiredPivot = root.Position + Vector3.yAxis * height
	if not pivotReady then
		pivot = desiredPivot
		pivotVel = Vector3.zero
		pivotReady = true
	else
		local omega = cfg.SpringFreq
		local zeta = cfg.SpringDamp
		local accel = -2 * zeta * omega * pivotVel - omega * omega * (pivot - desiredPivot)
		pivotVel += accel * dt
		pivot += pivotVel * dt
	end

	local rot = CFrame.fromEulerAnglesYXZ(pitch, yaw, 0)
	local lookTarget = pivot + rot * Vector3.new(cfg.Shoulder, 0, 0)
	cam.Focus = CFrame.new(lookTarget)

	local desiredOffset = rot * Vector3.new(0, 0, targetDist)
	local desiredDist = targetDist
	local mag = desiredOffset.Magnitude
	if mag > 0.01 then
		local hit = workspace:Spherecast(lookTarget, cfg.CollisionRadius, desiredOffset, rayParams)
		if hit then
			desiredDist = math.clamp(hit.Distance - 0.05, cfg.MinDistance, targetDist)
		end
	end

	local occRate = if desiredDist < currentDist then cfg.OcclusionIn else cfg.OcclusionOut
	currentDist += (desiredDist - currentDist) * (1 - math.exp(-occRate * dt))
	currentDist = math.clamp(currentDist, cfg.MinDistance, targetDist)
	cam.CFrame = CFrame.lookAt(lookTarget + rot * Vector3.new(0, 0, currentDist), lookTarget)

	local targetFov = if gait == "run" or gait == "dash" then cfg.SprintFov else cfg.Fov
	targetFov += fovPunch
	cam.FieldOfView += (targetFov - cam.FieldOfView) * (1 - math.exp(-cfg.FovLerp * dt))
	fovPunch *= math.exp(-cfg.DashFovDecay * dt)
end

function Camera.start(player: Player)
	Assets.boot(player)
	rayParams.FilterType = Enum.RaycastFilterType.Exclude
	rayParams.RespectCanCollide = true

	if player.Character then
		refreshCharacter(player.Character)
	end
	player.CharacterAdded:Connect(refreshCharacter)

	UserInputService.InputChanged:Connect(function(input, processed)
		if processed or input.UserInputType ~= Enum.UserInputType.MouseWheel then
			return
		end
		targetDist = math.clamp(targetDist - input.Position.Z * 1.5, cfg.MinDistance, cfg.MaxDistance)
	end)

	RunService:UnbindFromRenderStep(RENDER_NAME)
	RunService:BindToRenderStep(RENDER_NAME, Enum.RenderPriority.Camera.Value + 1, onRenderStep)
end

function Camera.GetYaw(): number
	return yaw
end

function Camera.GetLookFlat(): Vector3
	local flat = Vector3.new(-math.sin(yaw), 0, -math.cos(yaw))
	if flat.Magnitude < 0.001 then
		return Vector3.zAxis
	end
	return flat.Unit
end

function Camera.NotifyGait(newGait: string)
	gait = newGait
end

function Camera.PunchFov()
	fovPunch += cfg.DashFovPunch
end

-- ponytail: lock-on not implemented

return Camera
