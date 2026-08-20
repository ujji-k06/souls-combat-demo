--!strict
-- ponytail: dash is client-authoritative; server should validate when combat exists.

local RunService = game:GetService("RunService")
local UserInputService = game:GetService("UserInputService")

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
	IsShiftLockEnabled: () -> boolean,
	NotifyGait: (gait: string) -> (),
	PunchFov: () -> (),
}

type Tracks = {
	idle: AnimationTrack?,
	walk: AnimationTrack?,
	jump: AnimationTrack?,
	fall: AnimationTrack?,
	crouchIdle: AnimationTrack?,
	crouchWalk: AnimationTrack?,
	run2: AnimationTrack?,
	dashForward: AnimationTrack?,
	dashBack: AnimationTrack?,
}

type DashSide = "forward" | "back" | "left" | "right"

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
local dashBackward = false
local dashSpeed = 0
local dashDuration = 0
local dashStart = 0.0
local dashCooldownEnds: { [DashSide]: number } = {
	forward = 0,
	back = 0,
	left = 0,
	right = 0,
}
local jumpCooldownEnd = 0.0
local dashBufferedAt: number? = nil
local dashQueued = false
local dashConstraint: LinearVelocity? = nil
local currentSpeed = 0
local runStartedAt: number? = nil
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

local function dashSide(moveVector: Vector3): DashSide
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
	if gait == "run" then
		runStartedAt = tick()
	else
		runStartedAt = nil
	end
	if camera then
		camera.NotifyGait(gait)
	end
end

local function playRunAnim()
	if not tracks.run2 then
		playLoco(tracks.walk, 0.2)
		return
	end

	playLoco(tracks.run2, 0.2)
	tracks.run2:AdjustSpeed(math.clamp(currentSpeed / Config.Movement.RunSpeed, 0.74, 1.06))
end

local function playGaitAnim(gait: string, moving: boolean)
	if isDashing then
		if currentDashTrack then
			if not currentDashTrack.IsPlaying then
				stopTrack(currentLocoTrack, 0.08)
				currentLocoTrack = nil
				currentDashTrack:Play(0.04)
			end
			if currentDashTrack.Length > 0.05 then
				currentDashTrack:AdjustSpeed(currentDashTrack.Length / dashDuration)
			end
		end
		return
	end

	if currentDashTrack and currentDashTrack.IsPlaying then
		currentDashTrack:Stop(0.12)
	end
	if gait ~= "run" then
		stopTrack(tracks.run2, 0.12)
	end

	if humanoid and humanoid.FloorMaterial == Enum.Material.Air then
		return
	end

	if gait == "crouch" then
		playLoco(tracks.crouchWalk or tracks.walk, 0.12)
		if currentLocoTrack then
			currentLocoTrack:AdjustSpeed(if moving then 1 else 0)
		end
	elseif gait == "run" then
		playRunAnim()
	elseif gait == "walk" then
		playLoco(tracks.walk, 0.2)
		if currentLocoTrack then
			currentLocoTrack:AdjustSpeed(math.clamp(currentSpeed / Config.Movement.WalkSpeed, 0.85, 1.08))
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
	stopTrack(currentDashTrack, 0.08)
	currentDashTrack = nil
	if controls and controls:GetMoveVector().Magnitude > MOVE_DEADZONE then
		currentSpeed = if sprintDown() then Config.Movement.RunSpeed else Config.Movement.WalkSpeed
	else
		currentSpeed = Config.Movement.WalkSpeed * 0.45
	end
	if hrp then
		Assets.setDashDust(hrp, dashDir, false)
	end
end

local function startDash(): boolean
	if not humanoid or not hrp or not character or not camera then
		return false
	end
	if isDashing or humanoid.FloorMaterial == Enum.Material.Air then
		return false
	end

	local moveVector = controls:GetMoveVector()
	local side = dashSide(moveVector)
	if tick() < dashCooldownEnds[side] then
		return false
	end

	local dir: Vector3
	if moveVector.Magnitude > MOVE_DEADZONE then
		dir = cameraRelativeDir(moveVector)
	else
		dir = camera.GetLookFlat()
	end
	if dir.Magnitude < 0.01 then
		return false
	end

	dashQueued = false
	dashBufferedAt = nil
	dashDir = dir.Unit
	dashBackward = side == "back"
	dashSpeed = Config.Movement.DashSpeed
	dashDuration = Config.Movement.DashTime
	dashStart = tick()
	dashCooldownEnds[side] = dashStart + Config.Movement.DashCooldown
	isDashing = true
	currentDashTrack = if side == "back" then tracks.dashBack else tracks.dashForward

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
	lv.VectorVelocity = dashDir * dashSpeed
	lv.Parent = hrp
	dashConstraint = lv

	currentSpeed = 0
	Assets.setDashDust(hrp, dashDir, true)
	playGaitAnim("dash", true)
	return true
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
	local side = dashSide(controls:GetMoveVector())
	if now < dashCooldownEnds[side] then
		dashBufferedAt = now
		return
	end
	startDash()
end

local function tryConsumeDashBuffer()
	if isDashing then
		return
	end
	local now = tick()
	local side = dashSide(controls:GetMoveVector())
	if now < dashCooldownEnds[side] then
		return
	end
	if dashQueued then
		if startDash() then
			dashQueued = false
		end
		return
	end
	if dashBufferedAt then
		if now - dashBufferedAt <= Config.Movement.InputBuffer then
			if startDash() then
				dashBufferedAt = nil
			end
		else
			dashBufferedAt = nil
		end
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
	if camera then
		humanoid.AutoRotate = not camera.IsShiftLockEnabled()
	end
	if tick() < jumpCooldownEnd then
		humanoid.Jump = false
	elseif humanoid.Jump then
		jumpCooldownEnd = tick() + Config.Movement.JumpCooldown
	end

	if isDashing then
		local elapsed = tick() - dashStart
		local t = elapsed / dashDuration
		if t >= 1 then
			endDash()
		else
			local wish = cameraRelativeDir(moveVector)
			if wish.Magnitude > MOVE_DEADZONE then
				local flat = Vector3.new(wish.X, 0, wish.Z)
				if flat.Magnitude > 0.01 then
					local target = flat.Unit
					local angle = math.acos(math.clamp(dashDir:Dot(target), -1, 1))
					if angle > 1e-3 then
						local maxTurn = math.rad(Config.Movement.DashSteer) * dt
						dashDir = dashDir:Lerp(target, math.min(1, maxTurn / angle)).Unit
					end
				end
			end
			local hold = 0.75
			local coast = math.clamp((t - hold) / (1 - hold), 0, 1)
			local speed = dashSpeed * (1 - coast * coast)
			if dashConstraint then
				dashConstraint.VectorVelocity = dashDir * speed
			end
			if hrp then
				Assets.stepDashDust(hrp, dashDir)
			end
			local invuln = elapsed >= Config.Movement.IFrameStart and elapsed <= Config.Movement.IFrameEnd
			if character then
				character:SetAttribute("Invulnerable", invuln)
			end
			state.invulnerable = invuln
			humanoid:Move(Vector3.zero, true)
			humanoid.Jump = false
			if not dashBackward then
				setHumanoidYaw(hrp, yawFromDirection(dashDir), dt)
			end
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

	local isSprinting = sprintHeld and moveVector.Magnitude > MOVE_DEADZONE
	local targetSpeed = 0
	if moveVector.Magnitude > MOVE_DEADZONE then
		lastMove = moveVector
		if isCrouching then
			targetSpeed = Config.Movement.CrouchSpeed
		elseif isSprinting then
			local t = if runStartedAt
				then math.clamp((tick() - runStartedAt) / Config.Movement.RunRampTime, 0, 1)
				else 0
			local runProgress = 1 - (1 - t) * (1 - t)
			targetSpeed = Config.Movement.WalkSpeed
				+ (Config.Movement.RunSpeed - Config.Movement.WalkSpeed) * runProgress
		else
			targetSpeed = Config.Movement.WalkSpeed
		end
	end

	local speedRate = if targetSpeed >= currentSpeed then Config.Movement.Accel else Config.Movement.Decel
	local limit = speedRate * dt
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
	if camera and camera.IsShiftLockEnabled() then
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

	local walkTrack = loadTrack(anim, animCfg.Walk, Enum.AnimationPriority.Movement, true)
		or loadTrack(anim, resolveAnimId("Walk", 0, animate), Enum.AnimationPriority.Movement, true)
	local run2Track = loadTrack(anim, animCfg.Run2, Enum.AnimationPriority.Movement, true)
	tracks = {
		idle = loadTrack(anim, ids.idle, Enum.AnimationPriority.Idle, true),
		walk = walkTrack,
		run2 = run2Track,
		jump = loadTrack(anim, ids.jump, Enum.AnimationPriority.Movement, false),
		fall = loadTrack(anim, ids.fall, Enum.AnimationPriority.Movement, true),
		crouchIdle = nil,
		crouchWalk = loadTrack(anim, animCfg.Crouch, Enum.AnimationPriority.Movement, true),
		dashForward = loadTrack(anim, animCfg.DashForward, Enum.AnimationPriority.Action2, false),
		dashBack = loadTrack(anim, animCfg.DashBack, Enum.AnimationPriority.Action2, false),
	}

	currentLocoTrack = nil
	currentDashTrack = nil
	airTrack = nil
	runStartedAt = nil
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
	dashCooldownEnds = {
		forward = 0,
		back = 0,
		left = 0,
		right = 0,
	}
	jumpCooldownEnd = 0
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
			if not sprintDown() then
				isCrouching = true
			end
		elseif key == keys.Dash or key == keys.GamepadDash then
			requestDash()
		end
	end

	local function onInputEnded(input: InputObject, _gameProcessed: boolean)
		local key = input.KeyCode
		local keys = Config.Keys
		if key == keys.Crouch or key == keys.GamepadCrouch then
			isCrouching = false
		end
	end

	UserInputService.InputBegan:Connect(onInputBegan)
	UserInputService.InputEnded:Connect(onInputEnded)

	player.CharacterAdded:Connect(onCharacterAdded)
	if player.Character then
		onCharacterAdded(player.Character)
	end

	bindRender()
end

return Movement
