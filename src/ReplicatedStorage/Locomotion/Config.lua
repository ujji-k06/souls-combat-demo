--!strict
-- Tunables for camera + locomotion. Combat later reads Movement.GetState() and Camera.GetYaw().
-- ponytail: lock-on is a Camera.SetLockOn stub later; stamina later.

local Config = {
	Camera = {
		Distance = 9,
		MinDistance = 3.5,
		MaxDistance = 16,
		Height = 1.65,
		CrouchHeight = 0.85,
		Shoulder = 2.4,
		CollisionRadius = 0.4,
		PitchMin = math.rad(-75),
		PitchMax = math.rad(50),
		Sensitivity = 0.0036,
		GamepadSensitivity = 2.4,
		GamepadDeadzone = 0.18,
		PositionLag = 16,
		SpringFreq = 22,
		SpringDamp = 0.62,
		OcclusionIn = 50,
		OcclusionOut = 8,
		Fov = 70,
		SprintFov = 76,
		FovLerp = 9,
		DashFovPunch = 5,
		DashFovDecay = 12,
	},
	Movement = {
		WalkSpeed = 11,
		RunSpeed = 21,
		CrouchSpeed = 6.5,
		TurnSpeed = 24,
		DashSpeed = 50,
		DashTime = 0.38,
		DashCooldown = 0.5,
		IFrameStart = 0.05,
		IFrameEnd = 0.28,
		InputBuffer = 0.14,
		DashForce = 1e5,
		Accel = 54,
		Decel = 68,
	},
	Keys = {
		Sprint = Enum.KeyCode.LeftShift,
		SprintAlt = Enum.KeyCode.RightShift,
		ShiftLock = Enum.KeyCode.LeftAlt,
		Crouch = Enum.KeyCode.C,
		Dash = Enum.KeyCode.Q,
		GamepadSprint = Enum.KeyCode.ButtonL3,
		GamepadCrouch = Enum.KeyCode.ButtonX,
		GamepadDash = Enum.KeyCode.ButtonB,
	},
	-- Walk/run/crouch: KeyframeSequence names under ReplicatedStorage.AnimationPresets.Movement
	Animations = {
		WalkClip = "Walk_1",
		RunClip = "Run_2",
		CrouchIdleClip = "Crouch_1",
		CrouchWalkClip = "Crouch_2",
		DashForward = 97251256073597,
		DashBack = 81129945967470,
		DashLeft = 121116320851783,
		DashRight = 105272155526000,
	},
}

return Config
