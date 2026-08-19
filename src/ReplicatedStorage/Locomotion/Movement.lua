--!strict
-- ponytail: dash is client-authoritative; server should validate when combat exists.

local RunService = game:GetService("RunService")
local UserInputService = game:GetService("UserInputService")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local AnimationClipProvider = game:GetService("AnimationClipProvider")

local Config = require(script.Parent.Config)
local Assets = require(script.Parent.Assets)

export type State = {
	gait: string,
	invulnerable: boolean,
	canAct: boolean,
	moveVector: Vector3,
}

export type CameraApi = {
	GetYaw: () -> number,
	GetLookFlat: () -> Vector3,
	NotifyGait: (gait: string) -> (),
	PunchFov: () -> (),
}

type Tracks = {
	idle: AnimationTrack?,
	walk: AnimationTrack?,
	run: AnimationTrack?,
	jump: AnimationTrack?,
	fall: AnimationTrack?,
	crouchIdle: AnimationTrack?,
	crouchWalk: AnimationTrack?,
	dashForward: AnimationTrack?,
	dashBack: AnimationTrack?,
	dashLeft: AnimationTrack?,
	dashRight: AnimationTrack?,
}

local RENDER_NAME = "SoulsMovement"
local MOVE_DEADZONE = 0.12

local FALLBACKS: { [string]: number } = {
	idle = 180435571,
	walk = 180426354,
	run = 180426354,
	jump = 125750702,
	fall = 180436148,
}

local STEAL_FOLDERS: { [string]: string } = {
	Idle = "idle",
	Walk = "walk",
	Run = "run",
	Jump = "jump",
	Fall = "fall",
}

local Movement = {}

local camera: CameraApi? = nil
local controls: any = nil
local character: Model? = nil
local humanoid: Humanoid? = nil
local hrp: BasePart? = nil
local tracks: Tracks = {}
local currentLocoTrack: AnimationTrack? = nil
local currentDashTrack: AnimationTrack? = nil
local airTrack: AnimationTrack? = nil
local currentGait = "idle"

local sprintHeld = false
local isCrouching = false
local isDashing = false
local dashDir = Vector3.zero
local dashStart = 0.0
local dashCooldownEnd = 0.0
local dashBufferedAt: number? = nil
local dashQueued = false
local dashConstraint: LinearVelocity? = nil
local currentSpeed = 0
local lastMove = Vector3.new(0, 0, -1)

local state: State = {
	gait = "idle",
	invulnerable = false,
	canAct = true,
	moveVector = Vector3.zero,
}

local function inputBlocked(): boolean
	return UserInputService:GetFocusedTextBox() ~= nil
end

local function sprintDown(): boolean
	if UserInputService:IsKeyDown(Config.Keys.Sprint) or UserInputService:IsKeyDown(Config.Keys.SprintAlt) then
		return true
	end
	return UserInputService.GamepadEnabled
		and UserInputService:IsGamepadButtonDown(Enum.UserInputType.Gamepad1, Config.Keys.GamepadSprint)
end

local function parseAnimId(raw: string): number
	local digits = string.match(raw, "%d+")
	return if digits then tonumber(digits) :: number else 0
end

local function stealAnimId(animate: Instance, folderName: string): number
	local folder = animate:FindFirstChild(folderName)
	if not folder then
		return 0
	end
	local anim = folder:FindFirstChildWhichIsA("Animation", true)
	if not anim then
		return 0
	end
	return parseAnimId(anim.AnimationId)
end

local function resolveAnimId(configKey: string, configValue: number, animate: Instance?): number
	if configValue ~= 0 then
		return configValue
	end
	local folderName = STEAL_FOLDERS[configKey]
	if animate and folderName then
		local stolen = stealAnimId(animate, folderName)
		if stolen ~= 0 then
			return stolen
		end
	end
	return FALLBACKS[string.lower(configKey)] or 0
end

local function loadTrack(
	animator: Animator,
	id: number,
	priority: Enum.AnimationPriority,
	looped: boolean
): AnimationTrack?
	if id == 0 then
		return nil
	end
	local anim = Instance.new("Animation")
	anim.AnimationId = `rbxassetid://{id}`
	local track = animator:LoadAnimation(anim)
	track.Priority = priority
	track.Looped = looped
	return track
end

local clipHash: { [KeyframeSequence]: string } = {}

local function presetClip(name: string): KeyframeSequence?
	local presets = ReplicatedStorage:FindFirstChild("AnimationPresets")
	local folder = presets and presets:FindFirstChild("Movement")
	if not folder then
		return nil
	end
	local clip = folder:FindFirstChild(name, true)
	if clip and clip:IsA("KeyframeSequence") then
		return clip
	end
	return nil
end

local function loadClip(
	animator: Animator,
	clip: KeyframeSequence?,
	priority: Enum.AnimationPriority,
	looped: boolean
): AnimationTrack?
	if not clip then
		return nil
	end
	local hash = clipHash[clip]
	if not hash then
		local ok, registered = pcall(AnimationClipProvider.RegisterAnimationClip, AnimationClipProvider, clip)
		if not ok or typeof(registered) ~= "string" or registered == "" then
			return nil
		end
		hash = registered
		clipHash[clip] = hash
	end
	local anim = Instance.new("Animation")
	anim.AnimationId = hash
	local track = animator:LoadAnimation(anim)
	track.Priority = priority
	track.Looped = looped
	return track
end

local function dashSide(moveVector: Vector3): string
	if moveVector.Magnitude < MOVE_DEADZONE then
		return "forward"
	end
	if math.abs(moveVector.X) > math.abs(moveVector.Z) then
		return if moveVector.X > 0 then "right" else "left"
	end
	return if moveVector.Z > 0 then "back" else "forward"
end

local function stopTrack(track: AnimationTrack?, fade: number)
	if track and track.IsPlaying then
		track:Stop(fade)
	end
end

local function playLoco(track: AnimationTrack?, fade: number)
	if currentLocoTrack == track then
		return
	end
	stopTrack(currentLocoTrack, fade)
	currentLocoTrack = track
	if track then
		track:Play(fade)
	end
end

local function yawFromDirection(dir: Vector3): number
	return math.atan2(-dir.X, -dir.Z)
end

local function lerpYaw(current: number, target: number, alpha: number): number
	local delta = (target - current + math.pi) % (2 * math.pi) - math.pi
	return current + delta * alpha
end

local function setHumanoidYaw(root: BasePart, targetYaw: number, dt: number)
	local pos = root.Position
	local _, currentYaw = root.CFrame:ToEulerAnglesYXZ()
	local alpha = 1 - math.exp(-Config.Movement.TurnSpeed * dt)
	local yaw = lerpYaw(currentYaw, targetYaw, alpha)
	root.CFrame = CFrame.new(pos) * CFrame.Angles(0, yaw, 0)
end

local function cameraRelativeDir(moveVector: Vector3): Vector3
	if not camera then
		return Vector3.zero
	end
	local look = camera.GetLookFlat()
	local right = look:Cross(Vector3.yAxis).Unit
	return right * moveVector.X + look * -moveVector.Z
end

local function notifyGait(gait: string)
	if gait == currentGait then
		return
	end
	currentGait = gait
	state.gait = gait
	if camera then
		camera.NotifyGait(gait)
	end
end

local function playGaitAnim(gait: string, moving: boolean)
	if isDashing then
		if currentDashTrack and not currentDashTrack.IsPlaying then
			stopTrack(currentLocoTrack, 0.12)
			currentLocoTrack = nil
			currentDashTrack:Play(0.06)
		end
		return
	end

	if currentDashTrack and currentDashTrack.IsPlaying then
		currentDashTrack:Stop(0.12)
	end

	if humanoid and humanoid.FloorMaterial == Enum.Material.Air then
		return
	end

	if gait == "crouch" then
		playLoco(if moving then (tracks.crouchWalk or tracks.walk) else (tracks.crouchIdle or tracks.idle), 0.12)
	elseif gait == "run" then
		playLoco(tracks.run or tracks.walk, 0.12)
		if currentLocoTrack then
			currentLocoTrack:AdjustSpeed(1)
		end
	elseif gait == "walk" then
		playLoco(tracks.walk, 0.12)
		if currentLocoTrack then
			currentLocoTrack:AdjustSpeed(1)
		end
	else
		playLoco(tracks.idle, 0.12)
	end
end

local function updateAirAnim()
	if not humanoid or not hrp or isDashing then
		return
	end
	if humanoid.FloorMaterial ~= Enum.Material.Air then
		if airTrack then
			airTrack:Stop(0.12)
			airTrack = nil
		end
		return
	end

	local track = if hrp.AssemblyLinearVelocity.Y > 2 then tracks.jump else tracks.fall
	if track and airTrack ~= track then
		stopTrack(airTrack, 0.12)
		stopTrack(currentLocoTrack, 0.12)
		currentLocoTrack = nil
		airTrack = track
		track:Play(0.12)
	end
end

local function destroyDashConstraint()
	if dashConstraint then
		dashConstraint:Destroy()
		dashConstraint = nil
	end
end

local function endDash()
	if not isDashing then
		return
	end
	isDashing = false
	destroyDashConstraint()
	if character then
		character:SetAttribute("Invulnerable", false)
	end
	stopTrack(currentDashTrack, 0.12)
	currentDashTrack = nil
	currentSpeed = Config.Movement.WalkSpeed * 0.55
	if hrp then
		Assets.setDashDust(hrp, dashDir, false)
	end
end

local function startDash()
	if not humanoid or not hrp or not character or not camera then
		return
	end
	if isDashing or humanoid.FloorMaterial == Enum.Material.Air or tick() < dashCooldownEnd then
		return
	end
	dashQueued = false
	dashBufferedAt = nil

	local moveVector = controls:GetMoveVector()
	local dir: Vector3
	if moveVector.Magnitude > MOVE_DEADZONE then
		dir = cameraRelativeDir(moveVector)
	else
		dir = camera.GetLookFlat()
	end
	if dir.Magnitude < 0.01 then
		return
	end

	dashDir = dir.Unit
	dashStart = tick()
	dashCooldownEnd = dashStart + Config.Movement.DashCooldown
	isDashing = true
	local side = dashSide(moveVector)
	currentDashTrack = if side == "left"
		then tracks.dashLeft
		elseif side == "right" then tracks.dashRight
		elseif side == "back" then tracks.dashBack
		else tracks.dashForward

	humanoid.WalkSpeed = 0
	notifyGait("dash")
	camera.PunchFov()

	local att = hrp:FindFirstChild("DashAttachment") :: Attachment?
	if not att then
		att = Instance.new("Attachment")
		att.Name = "DashAttachment"
		att.Parent = hrp
	end

	local lv = Instance.new("LinearVelocity")
	lv.Name = "DashVelocity"
	lv.Attachment0 = att
	lv.VelocityConstraintMode = Enum.VelocityConstraintMode.Vector
	lv.RelativeTo = Enum.ActuatorRelativeTo.World
	lv.ForceLimitsEnabled = true
	lv.ForceLimitMode = Enum.ForceLimitMode.PerAxis
	lv.MaxAxesForce = Vector3.new(Config.Movement.DashForce, 0, Config.Movement.DashForce)
	lv.VectorVelocity = dashDir * Config.Movement.DashSpeed
	lv.Parent = hrp
	dashConstraint = lv

	currentSpeed = 0
	Assets.setDashDust(hrp, dashDir, true)
	playGaitAnim("dash", true)
end

local function requestDash()
	if inputBlocked() then
		return
	end
	local now = tick()
	if isDashing then
		dashQueued = true
		return
	end
	if now < dashCooldownEnd then
		dashBufferedAt = now
		return
	end
	startDash()
end

local function tryConsumeDashBuffer()
	if isDashing or tick() < dashCooldownEnd then
		return
	end
	if dashQueued then
		dashQueued = false
		startDash()
		return
	end
	if dashBufferedAt and tick() - dashBufferedAt <= Config.Movement.InputBuffer then
		dashBufferedAt = nil
		startDash()
	else
		dashBufferedAt = nil
	end
end

local function resolveGait(moveMag: number): string
	if isDashing then
		return "dash"
	end
	if isCrouching then
		return "crouch"
	end
	if sprintHeld and moveMag > MOVE_DEADZONE then
		return "run"
	end
	if moveMag > MOVE_DEADZONE then
		return "walk"
	end
	return "idle"
end

local function onRender(dt: number)
	if not humanoid or not hrp or not controls then
		return
	end

	local moveVector = controls:GetMoveVector()
	state.moveVector = moveVector
	sprintHeld = sprintDown()
	if sprintHeld then
		isCrouching = false
	end

	if isDashing then
		local elapsed = tick() - dashStart
		local t = elapsed / Config.Movement.DashTime
		if t >= 1 then
			endDash()
		else
			local speed = Config.Movement.DashSpeed * (1 - t) ^ 0.65
			if dashConstraint then
				dashConstraint.VectorVelocity = dashDir * speed
			end
			local invuln = elapsed >= Config.Movement.IFrameStart and elapsed <= Config.Movement.IFrameEnd
			if character then
				character:SetAttribute("Invulnerable", invuln)
			end
			state.invulnerable = invuln
			humanoid:Move(Vector3.zero, true)
			humanoid.Jump = false
			setHumanoidYaw(hrp, yawFromDirection(dashDir), dt)
			playGaitAnim("dash", true)
			state.canAct = false
			tryConsumeDashBuffer()
			return
		end
	end

	state.invulnerable = false
	if character then
		character:SetAttribute("Invulnerable", false)
	end

	local targetSpeed = 0
	if moveVector.Magnitude > MOVE_DEADZONE then
		lastMove = moveVector
		if isCrouching then
			targetSpeed = Config.Movement.CrouchSpeed
		elseif sprintHeld then
			targetSpeed = Config.Movement.RunSpeed
		else
			targetSpeed = Config.Movement.WalkSpeed
		end
	end
	local limit = (if currentSpeed < targetSpeed then Config.Movement.Accel else Config.Movement.Decel) * dt
	local diff = targetSpeed - currentSpeed
	if math.abs(diff) <= limit then
		currentSpeed = targetSpeed
	else
		currentSpeed += if diff > 0 then limit else -limit
	end
	humanoid.WalkSpeed = currentSpeed
	if currentSpeed > 0.35 then
		humanoid:Move(lastMove, true)
	else
		humanoid:Move(Vector3.zero, true)
	end
	if camera then
		setHumanoidYaw(hrp, camera.GetYaw(), dt)
	end

	local gait = resolveGait(moveVector.Magnitude)
	if gait ~= currentGait then
		notifyGait(gait)
	end

	local moving = moveVector.Magnitude > MOVE_DEADZONE
	updateAirAnim()
	if humanoid.FloorMaterial ~= Enum.Material.Air then
		playGaitAnim(gait, moving)
	end

	state.canAct = not isDashing
	tryConsumeDashBuffer()
end

local function setupHumanoid(h: Humanoid)
	h.AutoRotate = false
	h:SetStateEnabled(Enum.HumanoidStateType.FallingDown, false)
	h:SetStateEnabled(Enum.HumanoidStateType.Ragdoll, false)
	h:SetStateEnabled(Enum.HumanoidStateType.GettingUp, false)
	h.WalkSpeed = 0
end

local function setupAnimations(char: Model, h: Humanoid)
	local anim = h:FindFirstChildOfClass("Animator")
	if not anim then
		anim = Instance.new("Animator")
		anim.Parent = h
	end
	local animate = char:FindFirstChild("Animate")

	local animCfg = Config.Animations
	local ids = {
		idle = resolveAnimId("Idle", 0, animate),
		jump = resolveAnimId("Jump", 0, animate),
		fall = resolveAnimId("Fall", 0, animate),
	}

	if animate then
		if animate:IsA("LocalScript") then
			animate.Disabled = true
		elseif animate:IsA("Script") then
			animate.Disabled = true
		end
	end
	for _, playing in anim:GetPlayingAnimationTracks() do
		playing:Stop(0)
	end

	local walkTrack = loadClip(anim, presetClip(animCfg.WalkClip), Enum.AnimationPriority.Movement, true)
		or loadTrack(anim, resolveAnimId("Walk", 0, animate), Enum.AnimationPriority.Movement, true)
	local runTrack = loadClip(anim, presetClip(animCfg.RunClip), Enum.AnimationPriority.Movement, true) or walkTrack
	tracks = {
		idle = loadTrack(anim, ids.idle, Enum.AnimationPriority.Idle, true),
		walk = walkTrack,
		run = runTrack,
		jump = loadTrack(anim, ids.jump, Enum.AnimationPriority.Movement, false),
		fall = loadTrack(anim, ids.fall, Enum.AnimationPriority.Movement, true),
		crouchIdle = loadClip(anim, presetClip(animCfg.CrouchIdleClip), Enum.AnimationPriority.Idle, true),
		crouchWalk = loadClip(anim, presetClip(animCfg.CrouchWalkClip), Enum.AnimationPriority.Movement, true),
		dashForward = loadTrack(anim, animCfg.DashForward, Enum.AnimationPriority.Action2, false),
		dashBack = loadTrack(anim, animCfg.DashBack, Enum.AnimationPriority.Action2, false),
		dashLeft = loadTrack(anim, animCfg.DashLeft, Enum.AnimationPriority.Action2, false),
		dashRight = loadTrack(anim, animCfg.DashRight, Enum.AnimationPriority.Action2, false),
	}

	currentLocoTrack = nil
	currentDashTrack = nil
	airTrack = nil
end

local function onCharacterAdded(char: Model)
	endDash()
	character = char
	humanoid = char:WaitForChild("Humanoid") :: Humanoid
	hrp = char:WaitForChild("HumanoidRootPart") :: BasePart

	isCrouching = false
	isDashing = false
	currentSpeed = 0
	dashQueued = false
	dashBufferedAt = nil
	dashCooldownEnd = 0
	currentGait = "idle"
	state.gait = "idle"
	state.invulnerable = false
	state.canAct = true

	setupHumanoid(humanoid)
	setupAnimations(char, humanoid)
	currentGait = ""
	notifyGait("idle")
end

local function bindRender()
	pcall(function()
		RunService:UnbindFromRenderStep(RENDER_NAME)
	end)
	RunService:BindToRenderStep(RENDER_NAME, Enum.RenderPriority.Character.Value, onRender)
end

function Movement.GetState(): State
	return {
		gait = state.gait,
		invulnerable = state.invulnerable,
		canAct = state.canAct,
		moveVector = state.moveVector,
	}
end

function Movement.start(player: Player, cameraApi: CameraApi)
	camera = cameraApi

	local playerModule = require(player:WaitForChild("PlayerScripts"):WaitForChild("PlayerModule"))
	controls = playerModule:GetControls()
	controls.moveFunction = function() end
	Assets.unbindShiftLock()
	task.defer(Assets.unbindShiftLock)

	local function onInputBegan(input: InputObject, _gameProcessed: boolean)
		if input.KeyCode == Config.Keys.ShiftLock then
			if camera then
				camera.ToggleShiftLock()
			end
			return
		end
		if inputBlocked() then
			return
		end
		local key = input.KeyCode
		local keys = Config.Keys
		if key == keys.Crouch or key == keys.GamepadCrouch then
			isCrouching = not isCrouching
		elseif key == keys.Dash or key == keys.GamepadDash then
			requestDash()
		end
	end

	UserInputService.InputBegan:Connect(onInputBegan)

	player.CharacterAdded:Connect(onCharacterAdded)
	if player.Character then
		onCharacterAdded(player.Character)
	end

	bindRender()
end

return Movement
