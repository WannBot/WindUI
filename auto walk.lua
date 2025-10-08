-- 🧊 WS Auto Walk FINAL (Obsidian UI + red/yellow Platforms + Auto Jump)
-- Support: https://raw.githubusercontent.com/WannBot/WindUI/refs/heads/main/Path1.json

----------------------------------------------------------
-- Library
----------------------------------------------------------
local repo = "https://raw.githubusercontent.com/deividcomsono/Obsidian/main/"
local Library = loadstring(game:HttpGet(repo.."Library.lua"))()
local ThemeManager = loadstring(game:HttpGet(repo.."addons/ThemeManager.lua"))()
local SaveManager = loadstring(game:HttpGet(repo.."addons/SaveManager.lua"))()

----------------------------------------------------------
-- Services
----------------------------------------------------------
local Players = game:GetService("Players")
local RunService = game:GetService("RunService")
local HttpService = game:GetService("HttpService")
local UIS = game:GetService("UserInputService")

local player = Players.LocalPlayer
local mouse = player:GetMouse()
local character = player.Character or player.CharacterAdded:Wait()
local hum = character:WaitForChild("Humanoid")
local hrp = character:WaitForChild("HumanoidRootPart")

player.CharacterAdded:Connect(function(char)
	character = char
	hum = char:WaitForChild("Humanoid")
	hrp = char:WaitForChild("HumanoidRootPart")
end)

----------------------------------------------------------
-- State
----------------------------------------------------------
local recording, replaying, shouldStop = false, false, false
local redPlatforms, yellowPlatforms, mappings = {}, {}, {}
local loadedPoints = {}

_G.__WalkSpeed = 16
_G.__JumpPower = 50
_G.__Noclip = false

----------------------------------------------------------
-- Helpers
----------------------------------------------------------
RunService.Stepped:Connect(function()
	if _G.__Noclip and player.Character then
		for _, v in ipairs(player.Character:GetDescendants()) do
			if v:IsA("BasePart") then v.CanCollide = false end
		end
	end
end)

local function applyMovement()
	if hum and hum.Parent then
		hum.WalkSpeed = _G.__WalkSpeed
		hum.UseJumpPower = true
		hum.JumpPower = _G.__JumpPower
	end
end

----------------------------------------------------------
-- LOAD JSON (red/yellow Platforms)
----------------------------------------------------------
local function loadJson(str)
	local ok, data = pcall(function()
		return HttpService:JSONDecode(str)
	end)
	if not ok then
		Library:Notify("❌ Gagal decode JSON", 2)
		return false
	end

	table.clear(loadedPoints)

	-- Format record lama
	if data.redPlatforms then
		for _, seg in ipairs(data.redPlatforms) do
			for _, mv in ipairs(seg.movements or {}) do
				table.insert(loadedPoints, {
					position = mv.position,
					isJumping = mv.isJumping or false,
					orientation = mv.orientation or {X = 0, Y = 0, Z = 0}
				})
			end
		end

	-- Format path biasa
	elseif typeof(data) == "table" and data[1] then
		for _, mv in ipairs(data) do
			table.insert(loadedPoints, mv)
		end
	else
		Library:Notify("⚠️ Format JSON tidak dikenali", 2)
		return false
	end

	Library:Notify("✅ Loaded " .. tostring(#loadedPoints) .. " titik", 1.5)
	return true
end

----------------------------------------------------------
-- REPLAY (auto-jump dari redPlatforms.movements)
----------------------------------------------------------
local function replay(points)
	if replaying or #points == 0 then return end
	replaying, shouldStop = true, false

	local h = player.Character:WaitForChild("Humanoid")
	local hrp = player.Character:WaitForChild("HumanoidRootPart")

	local function compress(points, minDist)
		local out, last = {}, nil
		for _, p in ipairs(points) do
			local pos = p.position
			if pos then
				local v3 = Vector3.new(pos.X, pos.Y, pos.Z)
				if not last or (v3 - last).Magnitude > (minDist or 5) then
					table.insert(out, p)
					last = v3
				end
			end
		end
		return out
	end

	local runPoints = compress(points, 6)

	for _, mv in ipairs(runPoints) do
		if shouldStop then break end
		if not mv.position then continue end

		local target = Vector3.new(mv.position.X, mv.position.Y, mv.position.Z)

		-- 🟢 Jump hanya jika isJumping = true
		if mv.isJumping == true then
			task.spawn(function()
				h:ChangeState(Enum.HumanoidStateType.Jumping)
			end)
			task.wait(0.1)
		end

		h:MoveTo(target)
		h.MoveToFinished:Wait()
	end

	replaying = false
	Library:Notify("✅ Replay selesai", 1)
end

----------------------------------------------------------
-- UI SETUP
----------------------------------------------------------
local Window = Library:CreateWindow({
	Title = "WS Auto Walk",
	Footer = "Antartika Path Control",
	Icon = 95816097006870,
})

local Tabs = {
	Main = Window:AddTab("Main Fiture"),
	Auto = Window:AddTab("Auto Walk"),
	Setting = Window:AddTab("Setting")
}

----------------------------------------------------------
-- MAIN TAB
----------------------------------------------------------
local MainBox = Tabs.Main:AddLeftGroupbox("Movement Settings")

MainBox:AddSlider("WalkSpeed", {
	Text = "WalkSpeed", Min = 10, Max = 100, Default = 16,
	Callback = function(v) _G.__WalkSpeed = v; applyMovement() end
})
MainBox:AddSlider("JumpPower", {
	Text = "JumpPower", Min = 25, Max = 200, Default = 50,
	Callback = function(v) _G.__JumpPower = v; applyMovement() end
})
MainBox:AddToggle("Noclip", {
	Text = "NoClip",
	Default = false,
	Callback = function(v) _G.__Noclip = v end
})

----------------------------------------------------------
-- AUTO WALK TAB
----------------------------------------------------------
local L = Tabs.Auto:AddLeftGroupbox("Manual Control")
local R = Tabs.Auto:AddRightGroupbox("MAP ANTARTIKA")

L:AddButton("Play Loaded", function() replay(loadedPoints) end)
L:AddButton("⛔ Stop Play", function()
	shouldStop = true
	replaying = false
	Library:Notify("⛔ Playback stopped", 1)
end)

----------------------------------------------------------
-- PATH BUTTONS
----------------------------------------------------------
local baseURL = "https://raw.githubusercontent.com/WannBot/WindUI/refs/heads/main/"

local function loadAndPlay(path)
	local ok, res = pcall(function()
		return game:HttpGet(baseURL .. path)
	end)
	if ok and res and loadJson(res) then
		replay(loadedPoints)
	else
		Library:Notify("❌ Gagal Load: " .. path, 2)
	end
end

R:AddButton("BC > CP1 (Path1)", function() loadAndPlay("Path1.json") end)
R:AddButton("CP1 > CP2 (Path2)", function() loadAndPlay("Path2.json") end)
R:AddButton("CP2 > CP3 (Path3)", function() loadAndPlay("Path3.json") end)
R:AddButton("CP3 > CP4 (Path4)", function() loadAndPlay("Path4.json") end)
R:AddButton("CP4 > FINISH (Path5)", function() loadAndPlay("Path5.json") end)
R:AddDivider()
R:AddButton("PLAY ALL (Path1–5)", function()
	task.spawn(function()
		for i = 1, 5 do
			local ok, res = pcall(function()
				return game:HttpGet(baseURL .. "Path" .. i .. ".json")
			end)
			if ok and res and loadJson(res) then
				replay(loadedPoints)
				if shouldStop then break end
				task.wait(0.5)
			else
				Library:Notify("❌ Fail Path" .. i, 2)
				break
			end
		end
	end)
end)
R:AddButton("⛔ Stop Play (All Path)", function()
	shouldStop = true
	replaying = false
	Library:Notify("⛔ Playback stopped", 1)
end)

----------------------------------------------------------
-- SETTINGS TAB
----------------------------------------------------------
local Set = Tabs.Setting:AddLeftGroupbox("Theme Config")
ThemeManager:SetLibrary(Library)
SaveManager:SetLibrary(Library)
ThemeManager:SetFolder("WSAutoWalk")
SaveManager:SetFolder("WSAutoWalk/config")
SaveManager:BuildConfigSection(Tabs.Setting)
ThemeManager:ApplyToTab(Tabs.Setting)
Library.ToggleKeybind = Enum.KeyCode.RightShift
