-- Edit these values before uploading the file.
local CONFIG = {
	enabled = true,
	maxDistanceStuds = 3000,
	updatesPerSecond = 30,
	textSize = 16,
	color = Color3.fromRGB(235, 240, 255),
	transparency = 1,
	toggleKey = Enum.KeyCode.F4,
	unloadKey = Enum.KeyCode.End,
	showDisplayNames = true,
	showNames = true,
	showDistance = true,
	outline = true,
	menuKey = Enum.KeyCode.RightShift,
	maxPlayers = 256,
}

assert(type(Drawing) == "table" and type(Drawing.new) == "function", "Drawing API is unavailable.")
assert(CONFIG.updatesPerSecond > 0 and CONFIG.maxDistanceStuds > 0, "Invalid update rate or distance.")

local playersService = game:GetService("Players")
local runService = game:GetService("RunService")
local userInputService = game:GetService("UserInputService")
local localPlayer = playersService.LocalPlayer
assert(localPlayer, "Wait until the client has a LocalPlayer.")

local environment = type(getgenv) == "function" and getgenv() or _G
local previous = environment.AR2ESP
if type(previous) == "table" and type(previous.destroy) == "function" then
	previous:destroy()
end

local Overlay = {
	config = CONFIG,
	entries = {},
	connections = {},
	drawings = {},
	tracked = 0,
	destroyed = false,
	lastError = nil,
	menuOpen = true,
	visibleCount = 0,
	uiRefreshers = {},
}
environment.AR2ESP = Overlay

-- Own every drawing immediately so initialization failures can clean up.
local function newText(centered)
	local text = Drawing.new("Text")
	table.insert(Overlay.drawings, text)
	text.Visible = false
	text.Center = centered
	text.Outline = true
	text.OutlineColor = Color3.fromRGB(0, 0, 0)
	text.Font = 2
	text.Size = CONFIG.textSize
	text.Color = CONFIG.color
	text.Transparency = CONFIG.transparency
	text.ZIndex = 10
	return text
end

local function destroyDrawing(drawing)
	pcall(function() drawing:Destroy() end)
	local index = table.find(Overlay.drawings, drawing)
	if index then table.remove(Overlay.drawings, index) end
end

function Overlay:destroy()
	if self.destroyed then return end
	self.destroyed = true
	for _, connection in ipairs(self.connections) do connection:Disconnect() end
	if self.gui then self.gui:Destroy(); self.gui = nil end
	for _, drawing in ipairs(self.drawings) do pcall(function() drawing:Destroy() end) end
	table.clear(self.connections)
	table.clear(self.drawings)
	table.clear(self.entries)
	table.clear(self.uiRefreshers)
	self.tracked = 0
	if environment.AR2ESP == self then environment.AR2ESP = nil end
end

function Overlay:refreshUi()
	for _, refresh in ipairs(self.uiRefreshers) do refresh() end
end

function Overlay:setMenuOpen(open)
	self.menuOpen = open
	if self.panel then self.panel.Visible = open end
	if self.launcher then self.launcher.Visible = not open end
	if self.cancelDrag then self.cancelDrag() end
end

local function connect(signal, callback)
	local connection = signal:Connect(callback)
	table.insert(Overlay.connections, connection)
	return connection
end

-- All controls update the renderer's existing settings table.
local function buildPanel()
	local palette = {
		background = Color3.fromRGB(17, 21, 29), card = Color3.fromRGB(25, 31, 42),
		line = Color3.fromRGB(43, 52, 68), text = Color3.fromRGB(235, 240, 250),
		muted = Color3.fromRGB(144, 157, 179), accent = Color3.fromRGB(126, 165, 255),
		green = Color3.fromRGB(134, 225, 189),
	}
	local function create(class, parent, props)
		local object = Instance.new(class)
		object.Parent = parent
		for key, value in pairs(props or {}) do object[key] = value end
		return object
	end
	local function corner(object, radius)
		return create("UICorner", object, { CornerRadius = UDim.new(0, radius or 10) })
	end
	local function stroke(object, color, thickness)
		return create("UIStroke", object, {
			Color = color or palette.line, Thickness = thickness or 1,
			ApplyStrokeMode = Enum.ApplyStrokeMode.Border,
		})
	end
	local function label(parent, text, x, y, width, height, size, color)
		return create("TextLabel", parent, {
			BackgroundTransparency = 1, BorderSizePixel = 0,
			Position = UDim2.fromOffset(x, y), Size = UDim2.fromOffset(width, height),
			Font = Enum.Font.Gotham, Text = text, TextSize = size or 13,
			TextColor3 = color or palette.text, TextXAlignment = Enum.TextXAlignment.Left,
		})
	end
	local function button(parent, text, x, y, width, height)
		local object = create("TextButton", parent, {
			BackgroundColor3 = palette.card, BorderSizePixel = 0,
			Position = UDim2.fromOffset(x, y), Size = UDim2.fromOffset(width, height),
			Font = Enum.Font.GothamMedium, Text = text, TextSize = 12,
			TextColor3 = palette.text, AutoButtonColor = true,
		})
		corner(object, 8)
		return object
	end
	local playerGui = localPlayer:FindFirstChildOfClass("PlayerGui") or localPlayer:WaitForChild("PlayerGui", 10)
	assert(playerGui, "PlayerGui is unavailable.")
	if Overlay.destroyed then return end
	local gui = Instance.new("ScreenGui")
	Overlay.gui = gui
	gui.Name = "AR2FieldPanel"
	gui.ResetOnSpawn = false
	gui.IgnoreGuiInset = true
	gui.DisplayOrder = 100
	gui.ZIndexBehavior = Enum.ZIndexBehavior.Sibling
	gui.Parent = playerGui
	local panel = create("Frame", gui, {
		Name = "Panel", Size = UDim2.fromOffset(376, 554), Position = UDim2.fromOffset(24, 96),
		BackgroundColor3 = palette.background, BorderSizePixel = 0, Active = true,
	})
	Overlay.panel = panel
	corner(panel, 16)
	stroke(panel)
	local scale = create("UIScale", panel, { Scale = 1 })
	local header = button(panel, "", 0, 0, 316, 76)
	header.Name = "DragHeader"
	header.BackgroundTransparency = 1
	header.Modal = true
	header.AutoButtonColor = false
	local badge = create("Frame", header, {
		Position = UDim2.fromOffset(20, 20), Size = UDim2.fromOffset(42, 36),
		BackgroundColor3 = palette.accent, BorderSizePixel = 0,
	})
	corner(badge, 10)
	local badgeText = label(badge, "AR2", 0, 0, 42, 36, 13, palette.background)
	badgeText.Font = Enum.Font.GothamBold
	badgeText.TextXAlignment = Enum.TextXAlignment.Center
	local title = label(header, "Field panel", 74, 17, 210, 24, 19)
	title.Font = Enum.Font.GothamBold
	label(header, "PLAYER OVERLAY  /  01", 75, 43, 220, 16, 10, palette.muted)
	local hide = button(panel, "-", 325, 22, 30, 30)
	hide.Name = "HidePanel"
	connect(hide.Activated, function() Overlay:setMenuOpen(false) end)
	create("Frame", panel, {
		Position = UDim2.fromOffset(20, 77), Size = UDim2.fromOffset(336, 1),
		BackgroundColor3 = palette.line, BorderSizePixel = 0,
	})
	local summary = create("Frame", panel, {
		Position = UDim2.fromOffset(20, 92), Size = UDim2.fromOffset(336, 55),
		BackgroundColor3 = palette.card, BorderSizePixel = 0,
	})
	corner(summary)
	local visibleText = label(summary, "0", 14, 7, 112, 23, 21, palette.green)
	visibleText.Font = Enum.Font.GothamBold
	label(summary, "ON SCREEN", 15, 31, 112, 16, 9, palette.muted)
	local trackedText = label(summary, "0", 130, 7, 112, 23, 21)
	trackedText.Font = Enum.Font.GothamBold
	label(summary, "TRACKED", 131, 31, 112, 16, 9, palette.muted)
	local liveText = label(summary, "LIVE", 265, 17, 58, 20, 10, palette.green)
	liveText.TextXAlignment = Enum.TextXAlignment.Right
	Overlay.updateStats = function()
		visibleText.Text = tostring(Overlay.visibleCount)
		trackedText.Text = tostring(Overlay.tracked)
		liveText.Text = CONFIG.enabled and "LIVE" or "PAUSED"
		liveText.TextColor3 = CONFIG.enabled and palette.green or palette.muted
	end
	local function toggle(key, text, y)
		local row = button(panel, "", 20, y, 336, 34)
		row.Name = key
		row.BackgroundTransparency = 1
		label(row, text, 0, 0, 260, 34, 13)
		local track = create("Frame", row, {
			Position = UDim2.fromOffset(294, 7), Size = UDim2.fromOffset(42, 22), BorderSizePixel = 0,
		})
		corner(track, 11)
		local knob = create("Frame", track, {
			Size = UDim2.fromOffset(16, 16), BorderSizePixel = 0,
			BackgroundColor3 = Color3.fromRGB(247, 250, 255),
		})
		corner(knob, 8)
		local function refresh()
			track.BackgroundColor3 = CONFIG[key] and palette.accent or palette.line
			knob.Position = UDim2.fromOffset(CONFIG[key] and 23 or 3, 3)
		end
		table.insert(Overlay.uiRefreshers, refresh)
		connect(row.Activated, function() CONFIG[key] = not CONFIG[key]; Overlay:refreshUi() end)
		refresh()
	end
	toggle("enabled", "Enable player ESP", 158)
	toggle("showNames", "Player names", 192)
	toggle("showDisplayNames", "Use display names", 226)
	toggle("showDistance", "Distance labels", 260)
	toggle("outline", "Text outline", 294)
	local drag = nil
	Overlay.cancelDrag = function() drag = nil end
	local function slider(key, titleText, y, minimum, maximum, step, suffix)
		label(panel, titleText, 20, y, 210, 22, 12, palette.muted)
		local valueText = label(panel, "", 228, y, 128, 22, 12)
		valueText.TextXAlignment = Enum.TextXAlignment.Right
		local hit = button(panel, "", 20, y + 23, 336, 20)
		hit.Name = key
		hit.BackgroundTransparency = 1
		local track = create("Frame", hit, {
			Position = UDim2.fromOffset(0, 7), Size = UDim2.new(1, 0, 0, 5),
			BackgroundColor3 = palette.line, BorderSizePixel = 0,
		})
		corner(track, 3)
		local fill = create("Frame", track, { BackgroundColor3 = palette.accent, BorderSizePixel = 0 })
		corner(fill, 3)
		local knob = create("Frame", track, {
			AnchorPoint = Vector2.new(0.5, 0.5), Size = UDim2.fromOffset(12, 12),
			BackgroundColor3 = palette.text, BorderSizePixel = 0,
		})
		corner(knob, 6)
		local function refresh()
			local ratio = math.clamp((CONFIG[key] - minimum) / (maximum - minimum), 0, 1)
			fill.Size = UDim2.new(ratio, 0, 1, 0)
			knob.Position = UDim2.fromScale(ratio, 0.5)
			valueText.Text = tostring(CONFIG[key]) .. suffix
		end
		local function change(x)
			local ratio = math.clamp((x - track.AbsolutePosition.X) / math.max(track.AbsoluteSize.X, 1), 0, 1)
			CONFIG[key] = math.clamp(math.floor((minimum + ratio * (maximum - minimum)) / step + 0.5) * step, minimum, maximum)
			refresh()
		end
		connect(hit.InputBegan, function(input)
			if input.UserInputType == Enum.UserInputType.MouseButton1 or input.UserInputType == Enum.UserInputType.Touch then
				drag = { kind = "slider", input = input, change = change }
				change(input.Position.X)
			end
		end)
		table.insert(Overlay.uiRefreshers, refresh)
		refresh()
	end
	slider("maxDistanceStuds", "Maximum distance", 336, 100, 10000, 100, " studs")
	slider("textSize", "Label size", 389, 12, 24, 1, " px")
	label(panel, "LABEL COLOR", 20, 446, 140, 20, 10, palette.muted)
	local colors = {
		Color3.fromRGB(235, 240, 255), Color3.fromRGB(126, 165, 255),
		Color3.fromRGB(134, 225, 189), Color3.fromRGB(245, 176, 211),
	}
	for index, color in ipairs(colors) do
		local swatch = button(panel, "", 234 + (index - 1) * 33, 443, 23, 23)
		swatch.Name = "Color" .. index
		swatch.BackgroundColor3 = color
		local outline = stroke(swatch, palette.text, 2)
		local function refresh() outline.Transparency = CONFIG.color == color and 0 or 1 end
		table.insert(Overlay.uiRefreshers, refresh)
		connect(swatch.Activated, function() CONFIG.color = color; Overlay:refreshUi() end)
		refresh()
	end
	label(panel, "Enemy HP is not verified.", 20, 477, 245, 18, 11, palette.muted)
	local unload = button(panel, "Unload", 270, 502, 86, 30)
	unload.Name = "Unload"
	unload.TextColor3 = Color3.fromRGB(246, 167, 175)
	connect(unload.Activated, function() Overlay:destroy() end)
	label(panel, "RSHIFT menu  /  F4 ESP", 20, 505, 245, 24, 10, palette.muted)
	local launcher = button(gui, "AR2  /  Open panel", 20, 102, 155, 34)
	launcher.Name = "OpenPanel"
	launcher.BackgroundColor3 = palette.background
	launcher.Visible = false
	stroke(launcher)
	Overlay.launcher = launcher
	connect(launcher.Activated, function() Overlay:setMenuOpen(true) end)
	local function placePanel(x, y)
		local camera = workspace.CurrentCamera
		local viewport = camera and camera.ViewportSize or Vector2.new(1920, 1080)
		local maxX = math.max(8, viewport.X - 376 * scale.Scale - 8)
		local maxY = math.max(8, viewport.Y - 554 * scale.Scale - 8)
		panel.Position = UDim2.fromOffset(math.clamp(x, 8, maxX), math.clamp(y, 8, maxY))
	end
	Overlay.layoutPanel = function(viewport)
		scale.Scale = math.clamp(math.min((viewport.X - 24) / 376, (viewport.Y - 24) / 554), 0.2, 1)
		placePanel(panel.Position.X.Offset, panel.Position.Y.Offset)
	end
	connect(header.InputBegan, function(input)
		if input.UserInputType == Enum.UserInputType.MouseButton1 or input.UserInputType == Enum.UserInputType.Touch then
			drag = { kind = "panel", input = input, pointer = input.Position, start = panel.Position }
		end
	end)
	connect(userInputService.InputChanged, function(input)
		if not drag then return end
		local mouse = drag.input.UserInputType == Enum.UserInputType.MouseButton1
		if (mouse and input.UserInputType ~= Enum.UserInputType.MouseMovement) or (not mouse and input ~= drag.input) then return end
		if drag.kind == "slider" then
			drag.change(input.Position.X)
		else
			local delta = input.Position - drag.pointer
			placePanel(drag.start.X.Offset + delta.X, drag.start.Y.Offset + delta.Y)
		end
	end)
	connect(userInputService.InputEnded, function(input)
		if drag and (input == drag.input or input.UserInputType == Enum.UserInputType.MouseButton1) then drag = nil end
	end)
	connect(userInputService.WindowFocusReleased, function() drag = nil end)
	Overlay:refreshUi()
	Overlay.updateStats()
end

local function track(player)
	if Overlay.destroyed or player == localPlayer or Overlay.entries[player] then return end
	if Overlay.tracked >= CONFIG.maxPlayers then return end
	Overlay.entries[player] = { label = newText(true), character = nil, root = nil, head = nil }
	Overlay.tracked = Overlay.tracked + 1
end

local function untrack(player)
	local entry = Overlay.entries[player]
	if not entry then return end
	destroyDrawing(entry.label)
	Overlay.entries[player] = nil
	Overlay.tracked = Overlay.tracked - 1
end

local function finite(value)
	return value == value and value > -math.huge and value < math.huge
end

local function updateEntry(player, entry, camera, origin)
	entry.label.Visible = false
	local character = player.Character
	if not character or not character:IsDescendantOf(workspace) then return false end
	if entry.character ~= character then
		entry.character, entry.root, entry.head = character, nil, nil
	end
	if not entry.root or not entry.root:IsDescendantOf(character) then
		entry.root = character:FindFirstChild("HumanoidRootPart")
	end
	if not entry.head or not entry.head:IsDescendantOf(character) then
		entry.head = character:FindFirstChild("Head")
	end
	local root = entry.root
	if not root or not root:IsA("BasePart") then return false end
	local distance = (root.Position - origin).Magnitude
	if not finite(distance) or distance > CONFIG.maxDistanceStuds then return false end
	local head = entry.head
	local anchor = root.Position + Vector3.new(0, 3, 0)
	if head and head:IsA("BasePart") then
		anchor = head.Position + Vector3.new(0, head.Size.Y * 0.5 + 0.5, 0)
	end
	local point, onScreen = camera:WorldToViewportPoint(anchor)
	if not onScreen or point.Z <= 0 or not finite(point.X) or not finite(point.Y) then return false end
	local name = player.Name
	if CONFIG.showDisplayNames and player.DisplayName ~= player.Name then
		name = player.DisplayName .. " (@" .. player.Name .. ")"
	end
	local lines = {}
	if CONFIG.showNames then table.insert(lines, name) end
	if CONFIG.showDistance then table.insert(lines, string.format("%d studs", math.floor(distance + 0.5))) end
	if #lines == 0 then return false end
	entry.label.Text = table.concat(lines, "\n")
	entry.label.Size = CONFIG.textSize
	entry.label.Color = CONFIG.color
	entry.label.Outline = CONFIG.outline
	entry.label.Position = Vector2.new(point.X, point.Y - CONFIG.textSize * (#lines + 0.5))
	entry.label.Visible = true
	return true
end

local function initialize()
	buildPanel()
	if Overlay.destroyed then return end
	local status = newText(false)
	status.Position = Vector2.new(20, 60)
	status.Visible = true
	local function guardedTrack(player)
		local ok, err = pcall(track, player)
		if not ok then
			Overlay:destroy()
			warn("AR2 ESP could not create a label: " .. tostring(err))
		end
	end
	table.insert(Overlay.connections, playersService.PlayerAdded:Connect(guardedTrack))
	table.insert(Overlay.connections, playersService.PlayerRemoving:Connect(untrack))
	for _, player in ipairs(playersService:GetPlayers()) do track(player) end
	table.insert(Overlay.connections, userInputService.InputBegan:Connect(function(input, processed)
		if userInputService:GetFocusedTextBox() then return end
		if input.KeyCode == CONFIG.unloadKey then Overlay:destroy(); return end
		if not processed and input.KeyCode == CONFIG.menuKey then Overlay:setMenuOpen(not Overlay.menuOpen); return end
		if not processed and input.KeyCode == CONFIG.toggleKey then
			CONFIG.enabled = not CONFIG.enabled
			Overlay:refreshUi()
		end
	end))

	local accumulated = 0
	local lastViewport = nil
	local function render(deltaTime)
		if Overlay.destroyed then return end
		accumulated = accumulated + deltaTime
		if accumulated < 1 / CONFIG.updatesPerSecond then return end
		accumulated = 0
		local camera = workspace.CurrentCamera
		if camera and camera.ViewportSize ~= lastViewport then
			lastViewport = camera.ViewportSize
			Overlay.layoutPanel(lastViewport)
		end
		local origin = camera and camera.CFrame.Position
		local distanceFrom = "camera"
		local character = localPlayer.Character
		local root = character and character:FindFirstChild("HumanoidRootPart")
		if root and root:IsA("BasePart") and root:IsDescendantOf(workspace) then
			origin = root.Position
			distanceFrom = "player"
		end
		local visible = 0
		for player, entry in pairs(Overlay.entries) do
			entry.label.Visible = false
			if CONFIG.enabled and camera and origin then
				local ok, shown = pcall(updateEntry, player, entry, camera, origin)
				if ok and shown then visible = visible + 1 end
				if not ok then Overlay.lastError = tostring(shown):sub(1, 200) end
			end
		end
		status.Visible = not Overlay.menuOpen
		Overlay.visibleCount = visible
		Overlay.updateStats()
		status.Text = string.format("AR2 ESP %s | %d/%d on screen | distance: %s\n%s toggle | %s unload%s",
			CONFIG.enabled and "ON" or "OFF", visible, Overlay.tracked, distanceFrom,
			CONFIG.toggleKey.Name, CONFIG.unloadKey.Name, Overlay.lastError and " | label error: check AR2ESP.lastError" or "")
	end
	table.insert(Overlay.connections, runService.RenderStepped:Connect(function(deltaTime)
		local ok, err = pcall(render, deltaTime)
		if not ok then
			Overlay:destroy()
			warn("AR2 ESP stopped: " .. tostring(err))
		end
	end))
end

local ok, err = xpcall(initialize, function(message) return debug.traceback(tostring(message), 2) end)
if not ok then
	Overlay:destroy()
	error("AR2 ESP initialization failed: " .. tostring(err), 0)
end
