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
local character = player.Character or player.CharacterAdded:Wait()
local hum = character:WaitForChild("Humanoid")

-- 🔁 Auto update Humanoid saat respawn
player.CharacterAdded:Connect(function(char)
	character = char
	hum = char:WaitForChild("Humanoid")
	task.wait(0.5)
	if walkEnabled then hum.WalkSpeed = walkSpeedValue end
	if jumpEnabled then hum.JumpPower = jumpPowerValue end
end)

-- ✅ State
local walkEnabled, jumpEnabled, noclipEnabled = false, false, false
local walkSpeedValue, jumpPowerValue = 16, 50
local playAll, autoWalkActive = false, false

----------------------------------------------------
-- ⚙️ Utility
----------------------------------------------------
local function applyWalk()
	if hum and hum.Parent then
		hum.WalkSpeed = walkEnabled and walkSpeedValue or 16
	end
end

local function applyJump()
	if hum and hum.Parent then
		-- Pastikan karakter pakai JumpPower mode
		if hum:FindFirstChild("UseJumpPower") then
			hum.UseJumpPower = true
			hum.JumpPower = jumpEnabled and jumpPowerValue or 50
		else
			-- Fallback: kalau pakai JumpHeight
			local baseHeight = 7.2 -- default jump height kira-kira 50 JumpPower
			hum.JumpHeight = jumpEnabled and (jumpPowerValue / 7) or baseHeight
		end
	end
end

local function stopPath()
	autoWalkActive = false
end

local function playPathFile(filename)
	local url = "https://raw.githubusercontent.com/WannBot/<WindUI/refs/heads/main/" .. filename .. ".json"

	-- Contoh:
	-- local url = "https://raw.githubusercontent.com/WannBot/WindUI/refs/heads/main/Path1.json"

	print("[AutoWalk] Downloading:", url)
	local success, result = pcall(function()
		return game:HttpGet(url)
	end)

	if not success then
		warn("❌ Tidak bisa ambil file:", filename, result)
		return
	end

	local successDecode, data = pcall(function()
		return HttpService:JSONDecode(result)
	end)

	if not successDecode or typeof(data) ~= "table" then
		warn("❌ Format JSON tidak valid di:", filename)
		return
	end

	autoWalkActive = true
	print("[AutoWalk] Playing:", filename)

	for _, pos in ipairs(data) do
		if not autoWalkActive then break end
		hum:MoveTo(Vector3.new(pos.X, pos.Y, pos.Z))
		hum.MoveToFinished:Wait()
	end

	autoWalkActive = false
	print("[AutoWalk] Selesai:", filename)
end

-- ✅ Noclip loop
RunService.Stepped:Connect(function()
	if noclipEnabled and player.Character then
		for _, part in ipairs(player.Character:GetDescendants()) do
			if part:IsA("BasePart") then
				part.CanCollide = false
			end
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
	Callback = function(v)
		walkEnabled = v
		applyWalk()
	end,
})

MainBox:AddSlider("WalkspeedValue", {
	Text = "Speed",
	Default = 16,
	Min = 10,
	Max = 100,
	Rounding = 0,
	Callback = function(v)
		walkSpeedValue = v
		if walkEnabled then applyWalk() end
	end,
})

MainBox:AddToggle("JumpToggle", {
	Text = "JumpPower ON/OFF",
	Default = false,
	Callback = function(v)
		jumpEnabled = v
		applyJump()
	end,
})

MainBox:AddSlider("JumpPowerValue", {
	Text = "JumpPower",
	Default = 50,
	Min = 25,
	Max = 200,
	Rounding = 0,
	Callback = function(v)
		jumpPowerValue = v
		if jumpEnabled then applyJump() end
	end,
})

MainBox:AddToggle("NoClip", {
	Text = "NoClip ON/OFF",
	Default = false,
	Callback = function(v)
		noclipEnabled = v
	end,
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
