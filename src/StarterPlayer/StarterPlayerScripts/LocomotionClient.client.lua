--!strict
local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local folder = ReplicatedStorage:WaitForChild("Locomotion")
local Camera = require(folder:WaitForChild("Camera"))
local Movement = require(folder:WaitForChild("Movement"))

local player = Players.LocalPlayer
Camera.start(player)
Movement.start(player, Camera)
