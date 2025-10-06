-- ✅ Load Obsidian (Linoria-based)
local repo = "https://raw.githubusercontent.com/deividcomsono/Obsidian/main/"
local Library = loadstring(game:HttpGet(repo .. "Library.lua"))()
local ThemeManager = loadstring(game:HttpGet(repo .. "addons/ThemeManager.lua"))()
local SaveManager = loadstring(game:HttpGet(repo .. "addons/SaveManager.lua"))()

-- ✅ Services
local Players = game:GetService("Players")
local HttpService = game:GetService("HttpService")
local RunService = game:GetService("RunService")
local player = Players.LocalPlayer
local hum = player.Character or player.CharacterAdded:Wait():WaitForChild("Humanoid")

-- ✅ State
local walkEnabled, jumpEnabled, noclipEnabled = false, false, false
local walkSpeedValue, jumpPowerValue = 16, 50
local playAll, autoWalkActive = false, false

-- ✅ Functions
local function applyWalk()  if hum then hum.WalkSpeed = walkEnabled and walkSpeedValue or 16 end end
local function applyJump()  if hum then hum.JumpPower = jumpEnabled and jumpPowerValue or 50 end end
local function stopPath()   autoWalkActive = false end
local function playPathFile(filename)
	if not isfile(filename .. ".json") then return warn("❌ Missing:", filename) end
	local data = HttpService:JSONDecode(readfile(filename .. ".json"))
	autoWalkActive = true
	for _, p in ipairs(data) do
		if not autoWalkActive then break end
		hum:MoveTo(Vector3.new(p.X, p.Y, p.Z))
		hum.MoveToFinished:Wait()
	end
	autoWalkActive = false
end
RunService.Stepped:Connect(function()
	if noclipEnabled and player.Character then
		for _, part in ipairs(player.Character:GetDescendants()) do
			if part:IsA("BasePart") then part.CanCollide = false end
		end
	end
end)

-- ✅ Window
local Window = Library:CreateWindow({
	Title = "WS",
	Footer = "Antartika Path Controller",
	Icon = 95816097006870,
	NotifySide = "Right",
	ShowCustomCursor = true,
})

-- ✅ Tabs
local Tabs = {
	Main = Window:AddTab("Main Fiture", "user"),
	Auto = Window:AddTab("Auto Walk", "move"),
	Setting = Window:AddTab("Setting", "settings"),
}

----------------------------------------------------
-- 🟢 MAIN FITURE
----------------------------------------------------
local MainBox = Tabs.Main:AddLeftGroupbox("Movement Control")

MainBox:AddToggle("WalkspeedToggle", {
	Text = "WalkSpeed ON/OFF",
	Default = false,
	Callback = function(v) walkEnabled = v; applyWalk() end,
})

MainBox:AddSlider("WalkspeedValue", {
	Text = "Speed",
	Default = 16, Min = 10, Max = 100, Rounding = 0,
	Callback = function(v) walkSpeedValue = v; applyWalk() end,
})

MainBox:AddToggle("JumpToggle", {
	Text = "JumpPower ON/OFF",
	Default = false,
	Callback = function(v) jumpEnabled = v; applyJump() end,
})

MainBox:AddSlider("JumpPowerValue", {
	Text = "JumpPower",
	Default = 50, Min = 25, Max = 200, Rounding = 0,
	Callback = function(v) jumpPowerValue = v; applyJump() end,
})

MainBox:AddToggle("NoClip", {
	Text = "NoClip ON/OFF",
	Default = false,
	Callback = function(v) noclipEnabled = v end,
})

----------------------------------------------------
-- 🧭 AUTO WALK
----------------------------------------------------
local AutoBox = Tabs.Auto:AddLeftGroupbox("MAP ANTARTIKA")

AutoBox:AddToggle("PlayAll", {
	Text = "PLAY ALL (Path 1→4)",
	Default = false,
	Callback = function(state)
		playAll = state
		if state then
			task.spawn(function()
				for i = 1, 4 do
					playPathFile("Path" .. i)
					if not playAll then break end
				end
				playAll = false
			end)
		else
			stopPath()
		end
	end,
})

for i, name in ipairs({
	"BC > CP1 (Path1)",
	"CP1 > CP2 (Path2)",
	"CP2 > CP3 (Path3)",
	"CP3 > CP4 (Path4)",
	"CP4 > FINISH (Path5)",
}) do
	AutoBox:AddToggle("Path" .. i, {
		Text = name,
		Default = false,
		Callback = function(s) if s then playPathFile("Path" .. i) else stopPath() end end,
	})
end

----------------------------------------------------
-- ⚙️ SETTINGS
----------------------------------------------------
local SettingBox = Tabs.Setting:AddLeftGroupbox("Theme")

SettingBox:AddDropdown("Theme", {
	Values = { "Dark", "Light", "Aqua", "Midnight" },
	Default = "Dark",
	Text = "Select Theme",
	Callback = function(opt)
		Window:SetTheme(opt)
	end,
})

-- ✅ Theme/Save Manager setup
ThemeManager:SetLibrary(Library)
SaveManager:SetLibrary(Library)
ThemeManager:SetFolder("WS")
SaveManager:SetFolder("WS/config")
SaveManager:BuildConfigSection(Tabs.Setting)
ThemeManager:ApplyToTab(Tabs.Setting)

Library.ToggleKeybind = Enum.KeyCode.RightShift
