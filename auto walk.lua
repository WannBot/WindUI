-- 🧊 WS Auto Walk Final (Obsidian UI)
-- Ringan, tanpa visual, replay halus, support loncat
-- Repo Path: https://raw.githubusercontent.com/WannBot/WindUI/refs/heads/main/PathX.json
-- By WannBot x ChatGPT

----------------------------------------------------------
-- Library & Service
----------------------------------------------------------
local repo = "https://raw.githubusercontent.com/deividcomsono/Obsidian/main/"
local Library = loadstring(game:HttpGet(repo.."Library.lua"))()
local ThemeManager = loadstring(game:HttpGet(repo.."addons/ThemeManager.lua"))()
local SaveManager = loadstring(game:HttpGet(repo.."addons/SaveManager.lua"))()

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
-- State & Global
----------------------------------------------------------
local recording, replaying, shouldStop = false, false, false
local currentMovements, currentRed, lastYellow = {}, nil, nil
local redPlatforms, yellowPlatforms, mappings = {}, {}, {}
local loadedObject, loadedPoints = nil, {}

_G.__WalkSpeed = 16
_G.__JumpPower = 50
_G.__Noclip = false

----------------------------------------------------------
-- Movement Helper
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
			table.insert(redPlatforms,{position=currentRed,movements=currentMovements})
			return
		end
		table.insert(currentMovements,{position={X=pos.X,Y=pos.Y,Z=pos.Z}})
	end)
	Library:Notify("Recording Started",1.5)
end

local function stopRecording()
	if not recording then return end
	recording=false
	if clickConn then clickConn:Disconnect() end
	local last=currentMovements[#currentMovements] and currentMovements[#currentMovements].position or currentRed
	local yp={position={X=last.X,Y=last.Y,Z=last.Z}}
	table.insert(yellowPlatforms,yp)
	lastYellow=Vector3.new(yp.position.X,yp.position.Y,yp.position.Z)
	Library:Notify("Recording Stopped",1.5)
end

local function undo()
	if recording and #currentMovements>0 then
		table.remove(currentMovements)
	else
		table.remove(redPlatforms)
		table.remove(yellowPlatforms)
	end
end

local function clearAll()
	redPlatforms,yellowPlatforms={},{}
end

----------------------------------------------------------
-- Save / Load System
----------------------------------------------------------
local function buildObj()
	return {redPlatforms=redPlatforms,yellowPlatforms=yellowPlatforms,mappings=mappings}
end

local function save(name)
	writefile((name or "MyRecordedPath")..".json",HttpService:JSONEncode(buildObj()))
	Library:Notify("Saved",1)
end

local function loadJson(str)
	local ok,data=pcall(function()return HttpService:JSONDecode(str)end)
	if not ok then return false end
	loadedObject=nil
	table.clear(loadedPoints)
	if data.redPlatforms then
		loadedObject=data
		for _,seg in ipairs(data.redPlatforms)do
			for _,mv in ipairs(seg.movements or {})do
				if mv.position then table.insert(loadedPoints,mv.position) end
			end
		end
	elseif data[1] and data[1].X then
		for _,p in ipairs(data)do table.insert(loadedPoints,p) end
	else return false end
	return true
end

----------------------------------------------------------
-- Replay System
----------------------------------------------------------
----------------------------------------------------------
-- REPLAY (halus + auto jump detection)
----------------------------------------------------------
local function compressPoints(points, minDist)
	local filtered = {}
	local last
	for _, p in ipairs(points) do
		local pos = Vector3.new(p.X, p.Y, p.Z)
		if not last or (pos - last).Magnitude > (minDist or 5) then
			table.insert(filtered, p)
			last = pos
		end
	end
	return filtered
end

local function replay(points)
	if replaying or #points == 0 then return end
	replaying, shouldStop = true, false
	local h = player.Character:WaitForChild("Humanoid")
	local lastY = hrp.Position.Y

	local runPoints = compressPoints(points, 6) -- skip titik rapat

	for i, p in ipairs(runPoints) do
		if shouldStop then break end
		local target = Vector3.new(p.X, p.Y, p.Z)
		h:MoveTo(target)

		-- ✨ Deteksi loncat otomatis:
		local jumpFlag = false
		if p.isJump or p.jump then
			jumpFlag = true
		else
			local deltaY = math.abs((p.Y or 0) - lastY)
			if deltaY > 4 then jumpFlag = true end
		end

		if jumpFlag then
			task.wait(0.05)
			h.Jump = true
		end

		h.MoveToFinished:Wait()
		lastY = target.Y
	end

	replaying = false
end

local function playRecorded()
	local buf={}
	for _,seg in ipairs(redPlatforms)do
		for _,mv in ipairs(seg.movements or {})do
			table.insert(buf,mv.position)
		end
	end
	replay(buf)
end

local function playLoaded()
	replay(loadedPoints)
end

local function stopPlay()
	shouldStop=true
end

----------------------------------------------------------
-- UI Setup
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
	Callback = function(v) _G.__WalkSpeed=v; applyMovement() end
})
MainBox:AddSlider("JumpPower", {
	Text = "JumpPower", Min = 25, Max = 200, Default = 50,
	Callback = function(v) _G.__JumpPower=v; applyMovement() end
})
MainBox:AddToggle("Noclip", {
	Text = "NoClip",
	Default = false,
	Callback = function(v) _G.__Noclip=v end
})

----------------------------------------------------------
-- TAB AUTO WALK
----------------------------------------------------------
local L = Tabs.Auto:AddLeftGroupbox("Record / Replay")
local R = Tabs.Auto:AddRightGroupbox("Map Antartika")

-- record features
L:AddButton("Start Record", startRecording)
L:AddButton("Stop Record", stopRecording)
L:AddButton("Undo", undo)
L:AddButton("Clear All", clearAll)
L:AddDivider()
L:AddButton("Play Recorded", playRecorded)
L:AddButton("Stop", stopPlay)
L:AddButton("Save", function() save("MyRecordedPath") end)

-- load and play
local baseURL = "https://raw.githubusercontent.com/WannBot/WindUI/refs/heads/main/"

local function loadAndPlay(path)
	local ok,res = pcall(function() return game:HttpGet(baseURL..path) end)
	if ok and res and loadJson(res) then
		playLoaded()
	else
		Library:Notify("Load failed: "..path,2)
	end
end

-- play single path buttons
R:AddButton("BC > CP1 (Path1)", function() loadAndPlay("Path1.json") end)
R:AddButton("CP1 > CP2 (Path2)", function() loadAndPlay("Path2.json") end)
R:AddButton("CP2 > CP3 (Path3)", function() loadAndPlay("Path3.json") end)
R:AddButton("CP3 > CP4 (Path4)", function() loadAndPlay("Path4.json") end)
R:AddButton("CP4 > FINISH (Path5)", function() loadAndPlay("Path5.json") end)
R:AddDivider()
R:AddButton("PLAY ALL (Path1–5)", function()
	task.spawn(function()
		for i=1,5 do
			local ok,res = pcall(function()
				return game:HttpGet(baseURL.."Path"..i..".json")
			end)
			if ok and res and loadJson(res) then
				playLoaded()
				if shouldStop then break end
				task.wait(0.5)
			else
				Library:Notify("Fail Path"..i,2)
				break
			end
		end
	end)
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
