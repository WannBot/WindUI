-- ✅ Load core WindUI (pakai path repo kamu sendiri)
local WindUI = loadstring(game:HttpGet("https://raw.githubusercontent.com/WannBot/WindUI/main/src/init.lua"))()

-- ✅ Services
local Players = game:GetService("Players")
local HttpService = game:GetService("HttpService")
local RunService = game:GetService("RunService")

local player = Players.LocalPlayer
local char = player.Character or player.CharacterAdded:Wait()
local hum = char:WaitForChild("Humanoid")
local hrp = char:WaitForChild("HumanoidRootPart")

-- ✅ STATE
local walkEnabled, jumpEnabled, noclipEnabled = false, false, false
local walkSpeedValue, jumpPowerValue = 16, 50
local playAll, autoWalkActive = false, false

-- ✅ Utility
local function applyWalk()
	if hum then
		hum.WalkSpeed = walkEnabled and walkSpeedValue or 16
	end
end

local function applyJump()
	if hum then
		hum.JumpPower = jumpEnabled and jumpPowerValue or 50
	end
end

local function stopPath()
	autoWalkActive = false
end

local function playPathFile(filename)
	if not isfile(filename .. ".json") then
		warn("❌ File tidak ditemukan:", filename)
		return
	end
	local json = readfile(filename .. ".json")
	local data = HttpService:JSONDecode(json)
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
-- 🪟 WINDOW SETUP
----------------------------------------------------
local Window = WindUI:CreateWindow({
	Name = "Antartika Path Controller",
	ConfigurationSaving = false
})

----------------------------------------------------
-- 🟢 TAB 1: MAIN FEATURE
----------------------------------------------------
local TabMain = Window:CreateTab("Main Fiture")

TabMain:CreateLabel("⚙️ WalkSpeed Control")
TabMain:CreateDropdown({
	Name = "Input Speed",
	Options = {"10","16","25","35","50","75","100"},
	CurrentOption = {"16"},
	Callback = function(opt)
		walkSpeedValue = tonumber(opt[1])
		applyWalk()
	end
})
TabMain:CreateToggle({
	Name = "WalkSpeed ON/OFF",
	CurrentValue = false,
	Callback = function(state)
		walkEnabled = state
		applyWalk()
	end
})

TabMain:CreateLabel("⚙️ JumpPower Control")
TabMain:CreateDropdown({
	Name = "Input Power",
	Options = {"25","50","75","100","150","200"},
	CurrentOption = {"50"},
	Callback = function(opt)
		jumpPowerValue = tonumber(opt[1])
		applyJump()
	end
})
TabMain:CreateToggle({
	Name = "JumpPower ON/OFF",
	CurrentValue = false,
	Callback = function(state)
		jumpEnabled = state
		applyJump()
	end
})

TabMain:CreateLabel("🚫 NoClip")
TabMain:CreateToggle({
	Name = "NoClip ON/OFF",
	CurrentValue = false,
	Callback = function(state)
		noclipEnabled = state
	end
})

----------------------------------------------------
-- 🧭 TAB 2: AUTO WALK
----------------------------------------------------
local TabAuto = Window:CreateTab("Auto Walk")

TabAuto:CreateLabel("🗺️ MAP ANTARTIKA")

TabAuto:CreateToggle({
	Name = "PLAY ALL (Path1 → Path4)",
	CurrentValue = false,
	Callback = function(state)
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
	end
})

TabAuto:CreateToggle({
	Name = "BC > CP1 (Path 1)",
	CurrentValue = false,
	Callback = function(state)
		if state then playPathFile("Path1") else stopPath() end
	end
})
TabAuto:CreateToggle({
	Name = "CP1 > CP2 (Path 2)",
	CurrentValue = false,
	Callback = function(state)
		if state then playPathFile("Path2") else stopPath() end
	end
})
TabAuto:CreateToggle({
	Name = "CP2 > CP3 (Path 3)",
	CurrentValue = false,
	Callback = function(state)
		if state then playPathFile("Path3") else stopPath() end
	end
})
TabAuto:CreateToggle({
	Name = "CP3 > CP4 (Path 4)",
	CurrentValue = false,
	Callback = function(state)
		if state then playPathFile("Path4") else stopPath() end
	end
})
TabAuto:CreateToggle({
	Name = "CP4 > FINISH (Path 5)",
	CurrentValue = false,
	Callback = function(state)
		if state then playPathFile("Path5") else stopPath() end
	end
})

----------------------------------------------------
-- ⚙️ TAB 3: SETTINGS
----------------------------------------------------
local TabSetting = Window:CreateTab("Setting")

TabSetting:CreateLabel("🎨 Pilih Tema")
TabSetting:CreateDropdown({
	Name = "Select Theme",
	Options = {"Dark","Light","Ocean","Emerald","Crimson"},
	CurrentOption = {"Dark"},
	Callback = function(opt)
		if WindUI.SetTheme then
			WindUI:SetTheme(opt[1])
		elseif WindUI.ChangeTheme then
			WindUI:ChangeTheme(opt[1])
		end
	end
})
