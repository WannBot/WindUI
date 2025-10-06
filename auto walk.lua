-- ✅ Load Obsidian UI (versi deividcomsono)
local Obsidian = loadstring(game:HttpGet("https://raw.githubusercontent.com/deividcomsono/Obsidian/refs/heads/main/Example.lua"))()

-- ✅ Roblox Services
local Players = game:GetService("Players")
local HttpService = game:GetService("HttpService")
local RunService = game:GetService("RunService")

local player = Players.LocalPlayer
local char = player.Character or player.CharacterAdded:Wait()
local hum = char:WaitForChild("Humanoid")

-- ✅ STATE
local walkEnabled, jumpEnabled, noclipEnabled = false, false, false
local walkSpeedValue, jumpPowerValue = 16, 50
local playAll, autoWalkActive = false, false

----------------------------------------------------
-- ⚙️ UTILITIES
----------------------------------------------------
local function applyWalk()
	if hum then hum.WalkSpeed = walkEnabled and walkSpeedValue or 16 end
end

local function applyJump()
	if hum then hum.JumpPower = jumpEnabled and jumpPowerValue or 50 end
end

local function stopPath()
	autoWalkActive = false
end

local function playPathFile(filename)
	if not isfile(filename .. ".json") then
		warn("❌ File tidak ditemukan:", filename)
		return
	end
	local data = HttpService:JSONDecode(readfile(filename .. ".json"))
	autoWalkActive = true
	print("[AutoWalk] Playing:", filename)
	for _, pos in ipairs(data) do
		if not autoWalkActive then break end
		hum:MoveTo(Vector3.new(pos.X, pos.Y, pos.Z))
		hum.MoveToFinished:Wait()
	end
	autoWalkActive = false
end

-- ✅ Noclip
RunService.Stepped:Connect(function()
	if noclipEnabled and player.Character then
		for _, part in ipairs(player.Character:GetDescendants()) do
			if part:IsA("BasePart") then
				part.CanCollide = false
			end
		end
	end
end)

----------------------------------------------------
-- 🪟 CREATE UI WINDOW
----------------------------------------------------
local Window = Obsidian.new({
	Name = "Antartika Path Controller",
	Theme = "Dark",
	Transparency = 0.1
})

----------------------------------------------------
-- 🟢 TAB 1: MAIN FEATURE
----------------------------------------------------
local TabMain = Window:Tab("Main Fiture")

TabMain:Label("⚙️ WalkSpeed Control")
TabMain:Dropdown("Speed", {"10","16","25","35","50","75","100"}, "16", function(opt)
	walkSpeedValue = tonumber(opt)
	applyWalk()
end)

TabMain:Toggle("WalkSpeed ON/OFF", false, function(state)
	walkEnabled = state
	applyWalk()
end)

TabMain:Label("⚙️ JumpPower Control")
TabMain:Dropdown("Power", {"25","50","75","100","150","200"}, "50", function(opt)
	jumpPowerValue = tonumber(opt)
	applyJump()
end)

TabMain:Toggle("JumpPower ON/OFF", false, function(state)
	jumpEnabled = state
	applyJump()
end)

TabMain:Label("🚫 NoClip")
TabMain:Toggle("NoClip ON/OFF", false, function(state)
	noclipEnabled = state
end)

----------------------------------------------------
-- 🧭 TAB 2: AUTO WALK
----------------------------------------------------
local TabAuto = Window:Tab("Auto Walk")
TabAuto:Label("🗺️ MAP ANTARTIKA")

TabAuto:Toggle("PLAY ALL (Path 1 → 4)", false, function(state)
	playAll = state
	if state then
		task.spawn(function()
			playPathFile("Path1")
			if not playAll then return end
			playPathFile("Path2")
			if not playAll then return end
			playPathFile("Path3")
			if not playAll then return end
			playPathFile("Path4")
			playAll = false
		end)
	else
		stopPath()
	end
end)

TabAuto:Toggle("BC > CP1 (Path 1)", false, function(state)
	if state then playPathFile("Path1") else stopPath() end
end)
TabAuto:Toggle("CP1 > CP2 (Path 2)", false, function(state)
	if state then playPathFile("Path2") else stopPath() end
end)
TabAuto:Toggle("CP2 > CP3 (Path 3)", false, function(state)
	if state then playPathFile("Path3") else stopPath() end
end)
TabAuto:Toggle("CP3 > CP4 (Path 4)", false, function(state)
	if state then playPathFile("Path4") else stopPath() end
end)
TabAuto:Toggle("CP4 > FINISH (Path 5)", false, function(state)
	if state then playPathFile("Path5") else stopPath() end
end)

----------------------------------------------------
-- ⚙️ TAB 3: SETTINGS
----------------------------------------------------
local TabSetting = Window:Tab("Setting")

TabSetting:Label("🎨 Tema UI")
TabSetting:Dropdown("Select Theme", {"Dark","Light","Aqua","Blood","Midnight"}, "Dark", function(opt)
	Window:ChangeTheme(opt)
end)

----------------------------------------------------
-- 🚀 SHOW UI
----------------------------------------------------
Window:Init()
