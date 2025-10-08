-- 🧊 WS Auto Walk FINAL (Auto Jump Fix + Stop Path)
-- Ringan, tanpa visual, smooth, support isJumping, isJump, jump
-- By WannBot x ChatGPT

----------------------------------------------------------
-- Load UI Library
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
-- State & Variables
----------------------------------------------------------
local recording, replaying, shouldStop = false, false, false
local currentMovements, currentRed, lastYellow = {}, nil, nil
local redPlatforms, yellowPlatforms, mappings = {}, {}, {}
local loadedObject, loadedPoints = nil, {}

_G.__WalkSpeed = 16
_G.__JumpPower = 50
_G.__Noclip = false

----------------------------------------------------------
-- Movement Helpers
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
-- Record System
----------------------------------------------------------
local clickConn
local function startRecording()
	if recording then return end
	recording = true
	currentMovements, currentRed = {}, nil
	clickConn = mouse.Button1Down:Connect(function()
		if UIS:GetFocusedTextBox() then return end
		local cf = mouse.Hit; if not cf then return end
		local pos = cf.p
		if not currentRed then
			currentRed = {X=pos.X, Y=pos.Y, Z=pos.Z}
			table.insert(redPlatforms, {position=currentRed, movements=currentMovements})
			return
		end
		table.insert(currentMovements, {position={X=pos.X, Y=pos.Y, Z=pos.Z}})
	end)
	Library:Notify("Recording Started", 1.5)
end

local function stopRecording()
	if not recording then return end
	recording = false
	if clickConn then clickConn:Disconnect() end
	local last = currentMovements[#currentMovements] and currentMovements[#currentMovements].position or currentRed
	local yp = {position={X=last.X, Y=last.Y, Z=last.Z}}
	table.insert(yellowPlatforms, yp)
	lastYellow = Vector3.new(yp.position.X, yp.position.Y, yp.position.Z)
	Library:Notify("Recording Stopped", 1.5)
end

local function undo()
	if recording and #currentMovements > 0 then
		table.remove(currentMovements)
	else
		table.remove(redPlatforms)
		table.remove(yellowPlatforms)
	end
end

local function clearAll()
	redPlatforms, yellowPlatforms = {}, {}
end

----------------------------------------------------------
-- Save / Load
----------------------------------------------------------
local function buildObj()
	return {redPlatforms=redPlatforms, yellowPlatforms=yellowPlatforms, mappings=mappings}
end

local function save(name)
	writefile((name or "MyRecordedPath")..".json", HttpService:JSONEncode(buildObj()))
	Library:Notify("Saved", 1)
end

----------------------------------------------------------
-- LOAD JSON FIX (simpan isJumping, bukan hanya posisi)
----------------------------------------------------------
local function loadJson(str)
	local ok, data = pcall(function()
		return HttpService:JSONDecode(str)
	end)
	if not ok then
		Library:Notify("❌ Gagal baca JSON", 2)
		return false
	end

	table.clear(loadedPoints)

	-- Format hasil record (ada redPlatforms)
	if data.redPlatforms then
		for _, seg in ipairs(data.redPlatforms) do
			for _, mv in ipairs(seg.movements or {}) do
				-- Simpan seluruh object movement, bukan hanya posisi
				table.insert(loadedPoints, mv)
			end
		end

	-- Format file path eksternal (seperti CP0-1.json)
	elseif typeof(data) == "table" and data[1] and data[1].position then
		for _, mv in ipairs(data) do
			table.insert(loadedPoints, mv)
		end

	-- Format minimal {X,Y,Z}
	elseif typeof(data) == "table" and data[1] and data[1].X then
		for _, p in ipairs(data) do
			table.insert(loadedPoints, {position = p})
		end
	else
		Library:Notify("⚠️ Format JSON tidak dikenali", 2)
		return false
	end

	Library:Notify("✅ Loaded " .. tostring(#loadedPoints) .. " titik", 1.2)
	return true
end

----------------------------------------------------------
-- REPLAY ULTIMATE FIX (Force Jump + Auto Jumping)
----------------------------------------------------------
----------------------------------------------------------
-- REPLAY FINAL (Auto Jump 100% + ChangeState)
----------------------------------------------------------
local function replay(points)
	if replaying or #points == 0 then return end
	replaying, shouldStop = true, false

	local h = player.Character:WaitForChild("Humanoid")
	local hrp = player.Character:WaitForChild("HumanoidRootPart")
	local lastY = hrp.Position.Y

	-- hilangkan titik rapat biar halus
	local function compress(points, minDist)
		local out, last = {}, nil
		for _, p in ipairs(points) do
			local pos = p.position or p
			local v3 = Vector3.new(pos.X, pos.Y, pos.Z)
			if not last or (v3 - last).Magnitude > (minDist or 5) then
				table.insert(out, p)
				last = v3
			end
		end
		return out
	end

	local runPoints = compress(points, 6)

	for _, mv in ipairs(runPoints) do
		if shouldStop then break end

		local pos = mv.position or mv
		local target = Vector3.new(pos.X, pos.Y, pos.Z)
		local jumpFlag = mv.isJumping or mv.isJump or mv.jump or
			(pos.isJumping or pos.isJump or pos.jump)

		local deltaY = math.abs((pos.Y or 0) - lastY)
		if deltaY > 4 then jumpFlag = true end

		-- 💥 Trigger loncat
		if jumpFlag then
			task.spawn(function()
				h:ChangeState(Enum.HumanoidStateType.Jumping)
			end)
			task.wait(0.15)
		end

		h:MoveTo(target)
		h.MoveToFinished:Wait()
		lastY = target.Y
	end

	replaying = false
	Library:Notify("✅ Replay selesai", 1)
end

local function playRecorded()
	local buf = {}
	for _, seg in ipairs(redPlatforms) do
		for _, mv in ipairs(seg.movements or {}) do
			table.insert(buf, mv)
		end
	end
	replay(buf)
end

local function playLoaded()
	replay(loadedPoints)
end

local function stopPlay()
	shouldStop = true
	replaying = false
	Library:Notify("⛔ Playback stopped", 1)
end

----------------------------------------------------------
-- UI
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
-- TAB MAIN
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
-- TAB AUTO WALK
----------------------------------------------------------
local L = Tabs.Auto:AddLeftGroupbox("Record / Replay")
local R = Tabs.Auto:AddRightGroupbox("MAP ANTARTIKA")

L:AddButton("Start Record", startRecording)
L:AddButton("Stop Record", stopRecording)
L:AddButton("Undo", undo)
L:AddButton("Clear All", clearAll)
L:AddDivider()
L:AddButton("Play Recorded", playRecorded)
L:AddButton("⛔ Stop Play", stopPlay)
L:AddButton("Save", function() save("MyRecordedPath") end)

----------------------------------------------------------
-- Path Buttons
----------------------------------------------------------
local baseURL = "https://raw.githubusercontent.com/WannBot/WindUI/refs/heads/main/"

local function loadAndPlay(path)
	local ok, res = pcall(function() return game:HttpGet(baseURL .. path) end)
	if ok and res and loadJson(res) then
		playLoaded()
	else
		Library:Notify("Load failed: " .. path, 2)
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
				playLoaded()
				if shouldStop then break end
				task.wait(0.5)
			else
				Library:Notify("Fail Path" .. i, 2)
				break
			end
		end
	end)
end)

-- 🟥 Stop button di bawah Play All
R:AddButton("⛔ Stop Play (All Path)", function()
	stopPlay()
end)

----------------------------------------------------------
-- TAB SETTING
----------------------------------------------------------
local Set = Tabs.Setting:AddLeftGroupbox("Theme Config")
ThemeManager:SetLibrary(Library)
SaveManager:SetLibrary(Library)
ThemeManager:SetFolder("WSAutoWalk")
SaveManager:SetFolder("WSAutoWalk/config")
SaveManager:BuildConfigSection(Tabs.Setting)
ThemeManager:ApplyToTab(Tabs.Setting)
Library.ToggleKeybind = Enum.KeyCode.RightShift
