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
		Shoulder = 1.9,
		ShoulderLerp = 12,
		CollisionRadius = 0.4,
		PitchMin = math.rad(-75),
		PitchMax = math.rad(50),
		Sensitivity = 0.0036,
		GamepadSensitivity = 2.4,
		GamepadDeadzone = 0.18,
		PositionLag = 48,
		SpringFreq = 20,
		SpringDampX = 1.18, -- camera-local strafe
		SpringDampZ = 0.5, -- camera-local forward/back
		AirDampY = 22,
		OcclusionIn = 50,
		OcclusionOut = 12,
		Fov = 70,
		SprintFov = 73,
		FovLerp = 14,
		DashFovPunch = 9,
		DashFovDecay = 9,
	},
	Movement = {
		WalkSpeed = 13.8,
		RunSpeed = 22.4,
		CrouchSpeed = 7.2,
		TurnSpeed = 24,
		DashSpeed = 66,
		DashTime = 0.33,
		DashSteer = 110,
		DashCooldown = 2,
		JumpCooldown = 1.15,
		IFrameStart = 0.02,
		IFrameEnd = 0.22,
		InputBuffer = 0.14,
		DashForce = 1e5,
		Accel = 62,
		Decel = 44,
		RunRampTime = 0.2,
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
		Walk = 121003867646949,
		Crouch = 93723000396728,
		Run2 = 119916300262849,
		DashForward = 97251256073597,
		DashBack = 81129945967470,
	},
}

return Config
