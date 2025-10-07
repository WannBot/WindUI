-- WS Auto Walk Controller (FINAL - platform kotak, smooth replay)
-- UI: Obsidian (deividcomsono / Linoria-based)
-- Fitur: Record/Stop/Undo/Clear/Play/Save/Load (struktur "auto walk 1")
-- Visual: platform kotak (red/yellow/loaded), tanpa label; Replay: skip titik rapat
-- by WannBot x ChatGPT

----------------------------------------------------------------
-- LOAD LIB
----------------------------------------------------------------
local repo = "https://raw.githubusercontent.com/deividcomsono/Obsidian/main/"
local Library      = loadstring(game:HttpGet(repo .. "Library.lua"))()
local ThemeManager = loadstring(game:HttpGet(repo .. "addons/ThemeManager.lua"))()
local SaveManager  = loadstring(game:HttpGet(repo .. "addons/SaveManager.lua"))()

----------------------------------------------------------------
-- SERVICES
----------------------------------------------------------------
local Players      = game:GetService("Players")
local RunService   = game:GetService("RunService")
local HttpService  = game:GetService("HttpService")
local UIS          = game:GetService("UserInputService")

local player    = Players.LocalPlayer
local mouse     = player:GetMouse()
local character = player.Character or player.CharacterAdded:Wait()
local hum       = character:WaitForChild("Humanoid")
local hrp       = character:WaitForChild("HumanoidRootPart")

player.CharacterAdded:Connect(function(char)
	character = char
	hum = char:WaitForChild("Humanoid")
	hrp = char:WaitForChild("HumanoidRootPart")
	task.wait(0.25)
	if _G.__WS_walkEnabled then hum.WalkSpeed = _G.__WS_walkSpeedValue or 16 end
	if _G.__WS_jumpEnabled then hum.UseJumpPower = true; hum.JumpPower = _G.__WS_jumpPowerValue or 50 end
end)

----------------------------------------------------------------
-- MOVEMENT SETTINGS
----------------------------------------------------------------
_G.__WS_walkEnabled     = false
_G.__WS_jumpEnabled     = false
_G.__WS_noclipEnabled   = false
_G.__WS_walkSpeedValue  = 16
_G.__WS_jumpPowerValue  = 50

RunService.Stepped:Connect(function()
	if _G.__WS_noclipEnabled and player.Character then
		for _, part in ipairs(player.Character:GetDescendants()) do
			if part:IsA("BasePart") then part.CanCollide = false end
		end
	end
end)

local function applyWalk()
	if hum and hum.Parent then
		hum.WalkSpeed = _G.__WS_walkEnabled and _G.__WS_walkSpeedValue or 16
	end
end

local function applyJump()
	if hum and hum.Parent then
		hum.UseJumpPower = true
		hum.JumpPower   = _G.__WS_jumpEnabled and _G.__WS_jumpPowerValue or 50
	end
end

----------------------------------------------------------------
-- DATA (sesuai script "auto walk 1")
----------------------------------------------------------------
-- object:
-- { redPlatforms=[{position, movements=[{position,orientation}]}...],
--   yellowPlatforms=[{position}...], mappings=[] }

-- record buffer (satu segmen)
local currentMovements    = {}       -- { {position={X,Y,Z}, orientation={X,Y,Z}}, ... }
local currentRedPosition  = nil      -- {X,Y,Z}
local lastYellowPosition  = nil      -- Vector3 untuk auto-continue

-- semua segmen hasil record
local redPlatforms        = {}
local yellowPlatforms     = {}
local mappings            = {}

-- LOADED dari JSON
local loadedObject        = nil
local loadedPoints        = {}       -- flattened points utk replay cepat

-- flags
local recording           = false
local replaying           = false
local shouldStop          = false

----------------------------------------------------------------
-- VISUAL (platform kotak NEON, tanpa text)
----------------------------------------------------------------
local recordedParts   = {}   -- visual untuk recorded (red/yellow + sampling moves)
local loadedParts     = {}   -- visual untuk loaded

local function makePlatform(pos: Vector3, color: Color3, size: Vector3, name: string)
	local p = Instance.new("Part")
	p.Name = name
	p.Anchored = true
	p.CanCollide = false
	p.Material = Enum.Material.Neon
	p.Size = size
	p.Color = color
	p.CFrame = CFrame.new(pos)
	p.Parent = workspace
	return p
end

local function clearParts(listTbl)
	for _, part in ipairs(listTbl) do
		if part and part.Parent then part:Destroy() end
	end
	table.clear(listTbl)
end

-- sampling visual untuk movements supaya tidak spam ribuan part
local function samplePoints(points, minStep, minDist)
	local out = {}
	local last
	local step = math.max(minStep or 1, 1)
	for i = 1, #points, step do
		local p = points[i]
		if not last or (Vector3.new(p.X,p.Y,p.Z) - last).Magnitude >= (minDist or 6) then
			table.insert(out, p)
			last = Vector3.new(p.X,p.Y,p.Z)
		end
	end
	-- pastikan titik terakhir ikut
	if #points > 0 then
		local tail = points[#points]
		if not last or (Vector3.new(tail.X,tail.Y,tail.Z) - last).Magnitude >= 0.01 then
			table.insert(out, tail)
		end
	end
	return out
end

local function visualizeRecorded()
	clearParts(recordedParts)

	-- red start for each segment
	for i, seg in ipairs(redPlatforms) do
		local rp = seg.position
		table.insert(recordedParts, makePlatform(Vector3.new(rp.X,rp.Y,rp.Z), Color3.fromRGB(255,60,60), Vector3.new(2,0.2,2), "RED_"..i))

		-- OPTIONAL: sampling kecil untuk movements biar kelihatan garis halus (tanpa label)
		local moves = {}
		for _, mv in ipairs(seg.movements or {}) do
			if mv.position then table.insert(moves, mv.position) end
		end
		moves = samplePoints(moves, 5, 8)
		for _, p in ipairs(moves) do
			table.insert(recordedParts, makePlatform(Vector3.new(p.X,p.Y,p.Z), Color3.fromRGB(255,120,120), Vector3.new(1,0.15,1), "RM"))
		end
	end

	-- yellow end for each segment
	for i, yp in ipairs(yellowPlatforms) do
		local p = yp.position
		table.insert(recordedParts, makePlatform(Vector3.new(p.X,p.Y,p.Z), Color3.fromRGB(255,220,80), Vector3.new(2.2,0.2,2.2), "YEL_"..i))
	end
end

local function visualizeLoaded()
	clearParts(loadedParts)

	if loadedObject and loadedObject.redPlatforms then
		for i, seg in ipairs(loadedObject.redPlatforms) do
			if seg.position then
				local rp = seg.position
				table.insert(loadedParts, makePlatform(Vector3.new(rp.X,rp.Y,rp.Z), Color3.fromRGB(80,190,255), Vector3.new(2,0.2,2), "LRED_"..i))
			end
			local moves = {}
			for _, mv in ipairs(seg.movements or {}) do
				if mv.position then table.insert(moves, mv.position) end
			end
			moves = samplePoints(moves, 5, 8)
			for _, p in ipairs(moves) do
				table.insert(loadedParts, makePlatform(Vector3.new(p.X,p.Y,p.Z), Color3.fromRGB(100,230,255), Vector3.new(1,0.15,1), "LM"))
			end
		end
	end

	if loadedObject and loadedObject.yellowPlatforms then
		for i, yp in ipairs(loadedObject.yellowPlatforms) do
			local p = yp.position
			table.insert(loadedParts, makePlatform(Vector3.new(p.X,p.Y,p.Z), Color3.fromRGB(150,240,120), Vector3.new(2.2,0.2,2.2), "LYEL_"..i))
		end
	end
end

----------------------------------------------------------------
-- RECORD / STOP (klik dunia → movement)
----------------------------------------------------------------
local clickConn

local function startRecording()
	if recording then return end

	-- auto-continue: bila ada yellow terakhir → gerakkan avatar ke sana dulu
	if lastYellowPosition then
		local h = player.Character:WaitForChild("Humanoid")
		h:MoveTo(lastYellowPosition + Vector3.new(0,3,0))
		h.MoveToFinished:Wait()
	end

	currentMovements = {}
	currentRedPosition = nil
	recording = true

	clickConn = mouse.Button1Down:Connect(function()
		if UIS:GetFocusedTextBox() then return end
		local cf = mouse.Hit; if not cf then return end
		local pos = cf.p
		local look = hrp.CFrame.LookVector

		-- set red (start) jika belum ada
		if not currentRedPosition then
			currentRedPosition = {X=pos.X, Y=pos.Y, Z=pos.Z}
			table.insert(redPlatforms, { position = currentRedPosition, movements = currentMovements })
			visualizeRecorded()
			return
		end

		-- tambahkan movement point
		table.insert(currentMovements, {
			position    = {X=pos.X, Y=pos.Y, Z=pos.Z},
			orientation = {X=look.X, Y=look.Y, Z=look.Z}
		})

		-- visual kecil (ringan)
		table.insert(recordedParts, makePlatform(pos, Color3.fromRGB(255,120,120), Vector3.new(1,0.15,1), "RM"))
	end)

	Library:Notify("Recording ON (klik ground buat titik)", 2)
end

local function stopRecording()
	if not recording then return end
	recording = false
	if clickConn then clickConn:Disconnect(); clickConn=nil end

	-- yellow = titik akhir segmen (titik movement terakhir jika ada; jika tidak, pakai red)
	local lastPoint
	if #currentMovements > 0 then
		lastPoint = currentMovements[#currentMovements].position
	else
		lastPoint = currentRedPosition or {X=hrp.Position.X, Y=hrp.Position.Y, Z=hrp.Position.Z}
	end
	local yp = { position = { X = lastPoint.X, Y = lastPoint.Y, Z = lastPoint.Z } }
	table.insert(yellowPlatforms, yp)
	lastYellowPosition = Vector3.new(yp.position.X, yp.position.Y, yp.position.Z)

	visualizeRecorded()
	Library:Notify("Recording OFF (yellow created)", 2)
end

local function undoLastRecorded()
	if recording and #currentMovements > 0 then
		currentMovements[#currentMovements] = nil
	else
		if #yellowPlatforms > 0 then yellowPlatforms[#yellowPlatforms] = nil end
		if #redPlatforms    > 0 then redPlatforms[#redPlatforms]       = nil end
		if #yellowPlatforms > 0 then
			local yp = yellowPlatforms[#yellowPlatforms].position
			lastYellowPosition = Vector3.new(yp.X, yp.Y, yp.Z)
		else
			lastYellowPosition = nil
		end
	end
	visualizeRecorded()
end

local function clearRecordedAll()
	table.clear(currentMovements)
	currentRedPosition = nil
	table.clear(redPlatforms)
	table.clear(yellowPlatforms)
	lastYellowPosition = nil
	visualizeRecorded()
end

----------------------------------------------------------------
-- SERIALIZE / DESERIALIZE (objek penuh)
----------------------------------------------------------------
local function buildObject()
	return {
		redPlatforms    = redPlatforms,
		yellowPlatforms = yellowPlatforms,
		mappings        = mappings
	}
end

local function saveToFile(filenameNoExt)
	local json = HttpService:JSONEncode(buildObject())
	local fn = (filenameNoExt or "MyRecordedPath") .. ".json"
	writefile(fn, json)
	Library:Notify("Saved: "..fn, 2)
end

-- terima objek penuh (atau fallback array [{X,Y,Z}])
local function loadFromString(jsonStr)
	local ok, data = pcall(function() return HttpService:JSONDecode(jsonStr) end)
	if not ok or not data then return false end

	loadedObject = nil
	table.clear(loadedPoints)

	if data.redPlatforms then
		loadedObject = data
		-- flatten movements untuk replay cepat
		for _, seg in ipairs(data.redPlatforms) do
			for _, mv in ipairs(seg.movements or {}) do
				if mv.position then table.insert(loadedPoints, mv.position) end
			end
		end
		visualizeLoaded()
		return true
	elseif typeof(data)=="table" and data[1] and data[1].X then
		loadedObject = {
			redPlatforms    = { { position = data[1], movements = {} } },
			yellowPlatforms = { { position = data[#data] } },
			mappings        = {}
		}
		for _, p in ipairs(data) do table.insert(loadedPoints, p) end
		visualizeLoaded()
		return true
	end
	return false
end

----------------------------------------------------------------
-- REPLAY (smooth: skip titik rapat)
----------------------------------------------------------------
local function compressForRun(points, minDist)
	return samplePoints(points, 1, minDist or 4)  -- default 4 stud minimal
end

local function replayPositions(pointsList)
	if replaying or #pointsList == 0 then return end
	replaying, shouldStop = true, false
	local h = player.Character:WaitForChild("Humanoid")

	local run = compressForRun(pointsList, 4)  -- makin besar → makin cepat
	for i, p in ipairs(run) do
		if shouldStop then break end
		h:MoveTo(Vector3.new(p.X,p.Y,p.Z) + Vector3.new(0,3,0))
		h.MoveToFinished:Wait()
		task.wait(0.05)
	end

	replaying = false
end

local function replayRecorded()
	local buf = {}
	for _, seg in ipairs(redPlatforms) do
		for _, mv in ipairs(seg.movements or {}) do
			if mv.position then table.insert(buf, mv.position) end
		end
	end
	replayPositions(buf)
end

local function replayLoaded()
	if loadedObject and loadedObject.redPlatforms then
		local buf = {}
		for _, seg in ipairs(loadedObject.redPlatforms) do
			for _, mv in ipairs(seg.movements or {}) do
				if mv.position then table.insert(buf, mv.position) end
			end
		end
		replayPositions(buf)
	else
		replayPositions(loadedPoints)
	end
end

local function stopReplay()
	shouldStop = true
	replaying  = false
end

----------------------------------------------------------------
-- UI WINDOW & TABS
----------------------------------------------------------------
local Window = Library:CreateWindow({
	Title = "WS",
	Footer = "Antartika Path Controller",
	Icon = 95816097006870,
	NotifySide = "Right",
	ShowCustomCursor = true,
})

local Tabs = {
	Main    = Window:AddTab("Main Fiture", "user"),
	Auto    = Window:AddTab("Auto Walk",   "move"),
	Setting = Window:AddTab("Setting",     "settings"),
}

----------------------------------------------------------------
-- TAB: MAIN
----------------------------------------------------------------
local MainBox = Tabs.Main:AddLeftGroupbox("Movement")

MainBox:AddToggle("WS_Walk_Toggle", {
	Text = "WalkSpeed ON/OFF",
	Default = false,
	Callback = function(v) _G.__WS_walkEnabled = v; applyWalk() end
})

MainBox:AddSlider("WS_Walk_Slider", {
	Text = "Speed",
	Default = 16, Min = 10, Max = 100, Rounding = 0,
	Callback = function(v) _G.__WS_walkSpeedValue = v; if _G.__WS_walkEnabled then applyWalk() end end
})

MainBox:AddToggle("WS_Jump_Toggle", {
	Text = "JumpPower ON/OFF",
	Default = false,
	Callback = function(v) _G.__WS_jumpEnabled = v; applyJump() end
})

MainBox:AddSlider("WS_Jump_Slider", {
	Text = "JumpPower",
	Default = 50, Min = 25, Max = 200, Rounding = 0,
	Callback = function(v) _G.__WS_jumpPowerValue = v; if _G.__WS_jumpEnabled then applyJump() end end
})

MainBox:AddToggle("WS_NoClip_Toggle", {
	Text = "NoClip ON/OFF",
	Default = false,
	Callback = function(v) _G.__WS_noclipEnabled = v end
})

----------------------------------------------------------------
-- TAB: AUTO WALK (semua kontrol)
----------------------------------------------------------------
local AutoL  = Tabs.Auto:AddLeftGroupbox("Record / Replay")
local AutoR  = Tabs.Auto:AddRightGroupbox("Save / Load / Preset")

-- Record
AutoL:AddButton("Start Record", function() startRecording() end)
AutoL:AddButton("Stop Record",  function() stopRecording()  end)
AutoL:AddButton("Undo Last",    function() undoLastRecorded() end)
AutoL:AddButton("Clear RECORDED", function() clearRecordedAll() end)

AutoL:AddDivider()
AutoL:AddButton("Play RECORDED", function() replayRecorded() end)
AutoL:AddButton("Stop Replay",   function() stopReplay() end)

-- Save local
AutoR:AddInput("SaveName", {
	Text = "Filename (no .json)",
	Default = "MyRecordedPath",
	Finished = true,
	Callback = function(v) _G.__WS_SaveName = (v and #v>0) and v or "MyRecordedPath" end
})
AutoR:AddButton("Save RECORDED → file (.json)", function()
	saveToFile(_G.__WS_SaveName or "MyRecordedPath")
end)

-- Load URL / Raw JSON
local currentURL = "https://raw.githubusercontent.com/WannBot/WindUI/refs/heads/main/Path1.json"
AutoR:AddInput("URLInput", {
	Text = "GitHub RAW URL / Raw JSON",
	Default = currentURL,
	Placeholder = "https://raw.githubusercontent.com/<user>/<repo>/<branch>/PathX.json",
	Finished = true,
	Callback = function(v) if v and #v>0 then currentURL = v end end
})

AutoR:AddButton("Load to LOADED (visualize)", function()
	local src = currentURL or ""
	local ok, res
	if src:match("^https?://") then
		ok, res = pcall(function() return game:HttpGet(src) end)
	else
		ok, res = true, src
	end
	if not ok or not res then
		Library:Notify("Load failed", 2)
		return
	end
	local ok2 = loadFromString(res)
	if not ok2 then Library:Notify("Invalid JSON structure", 2) else Library:Notify("Loaded OK", 1.5) end
end)

AutoR:AddButton("Play LOADED", function() replayLoaded() end)

AutoR:AddButton("Clear LOADED", function()
	loadedObject = nil
	table.clear(loadedPoints)
	clearParts(loadedParts)
	Library:Notify("LOADED cleared", 1.2)
end)

-- Preset Path1..Path5
AutoR:AddDivider()
local baseURL = "https://raw.githubusercontent.com/WannBot/WindUI/refs/heads/main/"
AutoR:AddButton("Play ALL (Path1→Path5)", function()
	task.spawn(function()
		for i=1,5 do
			local ok, res = pcall(function() return game:HttpGet(baseURL.."Path"..i..".json") end)
			if not ok then break end
			if loadFromString(res) then
				replayLoaded()
				if shouldStop then break end
				task.wait(0.25)
			else break end
		end
	end)
end)

for i=1,5 do
	AutoR:AddButton("Play Path"..i, function()
		local ok, res = pcall(function() return game:HttpGet(baseURL.."Path"..i..".json") end)
		if not ok then Library:Notify("DL fail Path"..i, 2) return end
		if not loadFromString(res) then Library:Notify("JSON invalid Path"..i, 2) return end
		replayLoaded()
	end)
end

----------------------------------------------------------------
-- TAB: SETTING
----------------------------------------------------------------
local SettingBox = Tabs.Setting:AddLeftGroupbox("Theme / Config")
SettingBox:AddDropdown("ThemeSelect", {
	Values = { "Dark", "Light", "Aqua", "Midnight" },
	Default = "Dark",
	Text = "Select Theme",
	Callback = function(opt) Window:SetTheme(opt) end,
})

ThemeManager:SetLibrary(Library)
SaveManager:SetLibrary(Library)
ThemeManager:SetFolder("WS")
SaveManager:SetFolder("WS/config")
SaveManager:BuildConfigSection(Tabs.Setting)
ThemeManager:ApplyToTab(Tabs.Setting)
Library.ToggleKeybind = Enum.KeyCode.RightShift
