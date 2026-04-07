local ChangeHistoryService = game:GetService("ChangeHistoryService")
local RunService = game:GetService("RunService")
local HttpService = game:GetService("HttpService") 
local wsUrl = "ws://localhost:5000"
local webStreamClient = nil

local toolbar = plugin:CreateToolbar("Better Studio Tools")
local connectBtn = toolbar:CreateButton("Connect", "Click to connect", "")
local statusBtn = toolbar:CreateButton("Status", "Click to fetch status", "")
local disconnectBtn = toolbar:CreateButton("Disconnect", "Click to disconnect", "")
local openProjectBtn = toolbar:CreateButton("Open Project", "Click to open a project", "")
local closeProjectBtn = toolbar:CreateButton("Close Project", "Click to close the current project", "")

local projectOpen = false
local pendingRequests = {}
local connected = false
local cleaningUp = false

local function cleanup()
	if cleaningUp then return end
	cleaningUp = true

	if webStreamClient then
		pcall(function()
			webStreamClient:Close()
		end)
		webStreamClient = nil
	end

	connected = false
end

cleanup()

-- ------------------- GUI Setup -------------------

local screenGui = Instance.new("ScreenGui")
screenGui.Name = "BetterStudioGui"
screenGui.ResetOnSpawn = false
screenGui.ZIndexBehavior = Enum.ZIndexBehavior.Sibling
screenGui.Parent = game:GetService("CoreGui")

local backdrop = Instance.new("TextButton")
backdrop.Text = ""
backdrop.AutoButtonColor = false
backdrop.Name = "Backdrop"
backdrop.Size = UDim2.fromScale(1, 1)
backdrop.BackgroundColor3 = Color3.fromRGB(0, 0, 0)
backdrop.BackgroundTransparency = 0.5
backdrop.BorderSizePixel = 0
backdrop.Visible = false
backdrop.ZIndex = 10
backdrop.Parent = screenGui

local dialog = Instance.new("Frame")
dialog.Name = "Dialog"
dialog.Size = UDim2.fromOffset(360, 420)
dialog.Position = UDim2.fromScale(0.5, 0.5)
dialog.AnchorPoint = Vector2.new(0.5, 0.5)
dialog.BackgroundColor3 = Color3.fromRGB(30, 30, 30)
dialog.BorderSizePixel = 0
dialog.ZIndex = 11
dialog.Parent = backdrop

local corner = Instance.new("UICorner")
corner.CornerRadius = UDim.new(0, 8)
corner.Parent = dialog

local titleLabel = Instance.new("TextLabel")
titleLabel.Size = UDim2.new(1, -40, 0, 40)
titleLabel.Position = UDim2.fromOffset(20, 12)
titleLabel.BackgroundTransparency = 1
titleLabel.Text = "Select a Project"
titleLabel.TextColor3 = Color3.fromRGB(220, 220, 220)
titleLabel.TextSize = 16
titleLabel.Font = Enum.Font.GothamBold
titleLabel.TextXAlignment = Enum.TextXAlignment.Left
titleLabel.ZIndex = 12
titleLabel.Parent = dialog

local cancelBtn = Instance.new("TextButton")
cancelBtn.Size = UDim2.fromOffset(24, 24)
cancelBtn.Position = UDim2.new(1, -32, 0, 14)
cancelBtn.BackgroundTransparency = 1
cancelBtn.Text = "X"
cancelBtn.TextColor3 = Color3.fromRGB(160, 160, 160)
cancelBtn.TextSize = 16
cancelBtn.Font = Enum.Font.GothamBold
cancelBtn.ZIndex = 12
cancelBtn.Parent = dialog

local divider = Instance.new("Frame")
divider.Size = UDim2.new(1, 0, 0, 1)
divider.Position = UDim2.fromOffset(0, 52)
divider.BackgroundColor3 = Color3.fromRGB(60, 60, 60)
divider.BorderSizePixel = 0
divider.ZIndex = 12
divider.Parent = dialog

local scrollFrame = Instance.new("ScrollingFrame")
scrollFrame.Size = UDim2.new(1, -20, 1, -110)
scrollFrame.Position = UDim2.fromOffset(10, 62)
scrollFrame.BackgroundTransparency = 1
scrollFrame.BorderSizePixel = 0
scrollFrame.ScrollBarThickness = 4
scrollFrame.ScrollBarImageColor3 = Color3.fromRGB(100, 100, 100)
scrollFrame.CanvasSize = UDim2.fromOffset(0, 0)
scrollFrame.AutomaticCanvasSize = Enum.AutomaticSize.Y
scrollFrame.ZIndex = 12
scrollFrame.Parent = dialog

local listLayout = Instance.new("UIListLayout")
listLayout.Padding = UDim.new(0, 4)
listLayout.SortOrder = Enum.SortOrder.LayoutOrder
listLayout.Parent = scrollFrame

local listPadding = Instance.new("UIPadding")
listPadding.PaddingTop = UDim.new(0, 4)
listPadding.PaddingBottom = UDim.new(0, 4)
listPadding.Parent = scrollFrame

local openSelectedBtn = Instance.new("TextButton")
openSelectedBtn.Size = UDim2.new(1, -20, 0, 36)
openSelectedBtn.Position = UDim2.new(0, 10, 1, -48)
openSelectedBtn.BackgroundColor3 = Color3.fromRGB(0, 120, 212)
openSelectedBtn.BorderSizePixel = 0
openSelectedBtn.Text = "Open"
openSelectedBtn.TextColor3 = Color3.fromRGB(255, 255, 255)
openSelectedBtn.TextSize = 14
openSelectedBtn.Font = Enum.Font.GothamBold
openSelectedBtn.ZIndex = 12
openSelectedBtn.Parent = dialog

local openSelectedCorner = Instance.new("UICorner")
openSelectedCorner.CornerRadius = UDim.new(0, 6)
openSelectedCorner.Parent = openSelectedBtn

-- ------------------- GUI State -------------------

local selectedProject = nil
local projectButtons = {}
local resolveDialog = nil

local SELECTED_COLOR = Color3.fromRGB(0, 100, 180)
local NORMAL_COLOR = Color3.fromRGB(45, 45, 45)
local HOVER_COLOR = Color3.fromRGB(55, 55, 55)

local function closeDialog()
	backdrop.Visible = false
	selectedProject = nil
	if resolveDialog then
		resolveDialog(nil)
		resolveDialog = nil
	end
end

local function showProjectDialog(projects)
	-- Clear old buttons
	for _, b in ipairs(projectButtons) do b:Destroy() end
	projectButtons = {}
	selectedProject = nil

	for i, name in ipairs(projects) do
		local btn = Instance.new("TextButton")
		btn.Size = UDim2.new(1, 0, 0, 38)
		btn.BackgroundColor3 = NORMAL_COLOR
		btn.BorderSizePixel = 0
		btn.Text = name
		btn.TextColor3 = Color3.fromRGB(210, 210, 210)
		btn.TextSize = 13
		btn.Font = Enum.Font.Gotham
		btn.TextXAlignment = Enum.TextXAlignment.Left
		btn.LayoutOrder = i
		btn.ZIndex = 13
		btn.Parent = scrollFrame

		local btnCorner = Instance.new("UICorner")
		btnCorner.CornerRadius = UDim.new(0, 5)
		btnCorner.Parent = btn

		local btnPadding = Instance.new("UIPadding")
		btnPadding.PaddingLeft = UDim.new(0, 12)
		btnPadding.Parent = btn

		btn.MouseEnter:Connect(function()
			if selectedProject ~= name then
				btn.BackgroundColor3 = HOVER_COLOR
			end
		end)
		btn.MouseLeave:Connect(function()
			if selectedProject ~= name then
				btn.BackgroundColor3 = NORMAL_COLOR
			end
		end)

		btn.MouseButton1Click:Connect(function()
			-- Deselect all
			for _, other in ipairs(projectButtons) do
				other.BackgroundColor3 = NORMAL_COLOR
			end
			selectedProject = name
			btn.BackgroundColor3 = SELECTED_COLOR
		end)

		table.insert(projectButtons, btn)
	end

	backdrop.Visible = true

	print("-------------\nProject dialog opened with", #projects, "projects\n-------------")

	-- Return a "promise" resolved when user picks or cancels
	return function(callback)
		resolveDialog = callback
	end
end

cancelBtn.MouseButton1Click:Connect(closeDialog)
backdrop.MouseButton1Click:Connect(function()
	closeDialog()
end)

openSelectedBtn.MouseButton1Click:Connect(function()
	if selectedProject and resolveDialog then
		local pick = selectedProject
		backdrop.Visible = false
		selectedProject = nil
		local cb = resolveDialog
		resolveDialog = nil
		cb(pick)
	end
end)

-- ------------------- Helpers -------------------

local function updateButtonStates()
	print(projectOpen)
	print(connected)
	openProjectBtn.Enabled = not projectOpen and connected
	closeProjectBtn.Enabled = projectOpen and connected
	disconnectBtn.Enabled = connected
	connectBtn.Enabled = not connected
	statusBtn.Enabled = connected
end

local function generateId()
	return HttpService:GenerateGUID(false)
end

local function sendCliCommandWithCallback(command, args, callback)
	if not webStreamClient then
		print("Not connected to server")
		return
	end
	local id = generateId()
	local payload = { type = "cli", command = command, id = id }
	if args then
		payload.args = args
	end
	pendingRequests[id] = { callback = callback }
	webStreamClient:Send(HttpService:JSONEncode(payload))
end

local function onMessage(message)
	local ok, data = pcall(function()
		return HttpService:JSONDecode(message)
	end)
	if not ok or type(data) ~= "table" then return end

	if data.type == "response" and data.id and pendingRequests[data.id] then
		local entry = pendingRequests[data.id]
		pendingRequests[data.id] = nil
		if entry.callback then
			entry.callback(data)
		end
	end
end

local function fetchStatus(callback)
	sendCliCommandWithCallback("status", nil, function(data)
		if data.projectOpen ~= nil then
			projectOpen = data.projectOpen
		end
		updateButtonStates()
		if callback then callback(data) end
	end)
end

-- ------------------- Button Handlers -------------------

local function onConnect()
	webStreamClient = HttpService:CreateWebStreamClient(
		Enum.WebStreamClientType.WebSocket,
		{ Url = wsUrl }
	)

	webStreamClient.MessageReceived:Connect(onMessage)

	webStreamClient.Error:Connect(function(message)
		print("WebSocket error: " .. message)
	end)

	webStreamClient.Closed:Connect(function()
		print("Disconnected from server")
		projectOpen = false
		connected = false
		pendingRequests = {}
		updateButtonStates()
	end)

	fetchStatus(function(data)
		print("Connected. Project open: " .. tostring(projectOpen))
		if data.currentProject then
			print("Current project: " .. tostring(data.currentProject))
		end
		connected = true
		updateButtonStates()
	end)
end

local function onDisconnect()
	if webStreamClient then
		webStreamClient:Close()
		webStreamClient = nil
	end
	pendingRequests = {}
	projectOpen = false
	connected = false
	updateButtonStates()
	print("Disconnected from web server")
end

local function onStatus()
	fetchStatus(function(data)
		print("Status:")
		print("  Project open: " .. tostring(projectOpen))
		if data.currentProject then
			print("  Current project: " .. tostring(data.currentProject))
		end
		if data.unpackedPath then
			print("  Unpacked path: " .. tostring(data.unpackedPath))
		end
	end)
end

local function onOpenProject()
	sendCliCommandWithCallback("list-projects", nil, function(data)
		local projects = data.projects or {}
		if #projects == 0 then
			print("No projects found on server")
			return
		end

		local registerCallback = showProjectDialog(projects)
		registerCallback(function(pick)
			if not pick then
				print("Project selection cancelled")
				return
			end

			sendCliCommandWithCallback("open-project", { name = pick }, function(openData)
				if openData.status == "opened" then
					projectOpen = true
					updateButtonStates()
					print("Opened project: " .. pick)
				else
					print("Failed to open project")
				end
			end)
		end)
	end)
end

local function onCloseProject()
	sendCliCommandWithCallback("close-project", nil, function(data)
		print("Project closed")
		projectOpen = false
		updateButtonStates()
	end)
end

local function SanitizeFolderName(name)
	-- Define invalid filename characters (same as Windows / C#)
	local invalidChars = '<>:"/\\|?*'

	-- Iterate each character like C# foreach
	for i = 1, #invalidChars do
		local c = invalidChars:sub(i, i)
		-- Replace all occurrences of the character with '_'
		-- Escape gsub pattern characters
		local pattern = c:match("[%p]") and "%" .. c or c
		name = name:gsub(pattern, "_")
	end

	return name
end

local function edit(instance: Instance, editType: string, property: string, value: string)
	local uuid = instance:GetAttribute("UUID")
	if not webStreamClient then
		print("Not connected to server")
		return
	end
	local id = generateId()
	local payload = {
		type = "edit",
		id = id,
		args = {
			target = editType,
			property = property,
			value = value,
			uuid = uuid,
			action = "modify"
		}
	}
	webStreamClient:Send(HttpService:JSONEncode(payload))
end

local function delete(instance: Instance)
	local uuid = instance:GetAttribute("UUID")
	if not webStreamClient then
		print("Not connected to server")
		return
	end
	local id = generateId()
	local payload = {
		type = "edit",
		id = id,
		args = {
			action = "delete",
			uuid = uuid
		}
	}
end

-- ------------------- Wire up buttons -------------------

connectBtn.ClickableWhenViewportHidden = true
statusBtn.ClickableWhenViewportHidden = true
disconnectBtn.ClickableWhenViewportHidden = true
openProjectBtn.ClickableWhenViewportHidden = true
closeProjectBtn.ClickableWhenViewportHidden = true

connectBtn.Click:Connect(onConnect)
disconnectBtn.Click:Connect(onDisconnect)
statusBtn.Click:Connect(onStatus)
openProjectBtn.Click:Connect(onOpenProject)
closeProjectBtn.Click:Connect(onCloseProject)

updateButtonStates()

local scriptSources = {}

local function trackInstance(instance)
	-- Track property changes
	instance.Changed:Connect(function(prop)
		local value = instance[prop]
		edit(instance, "property", prop, value)
	end)

	-- Track script edits
	if instance:IsA("ModuleScript") or instance:IsA("LocalScript") or instance:IsA("Script") then
		scriptSources[instance] = instance.Source

		instance:GetPropertyChangedSignal("Source"):Connect(function()
			local newValue = instance.Source
			edit(instance, "script", "", newValue)
			scriptSources[instance] = newValue
		end)
	end
end

-- Track all existing descendants
for _, obj in ipairs(game:GetDescendants()) do
	trackInstance(obj)
end

-- Track future descendants
game.DescendantAdded:Connect(trackInstance)

-- Track deletion for a single instance
local function trackDeletion(instance)
	-- Fires when the instance is destroyed
	instance.Destroying:Connect(function()
		delete(instance)
	end)

	-- Optional: Detect when instance is removed from parent (could indicate deletion)
	instance.AncestryChanged:Connect(function(_, newParent)
		if not newParent then
			delete(instance)
		end
	end)
end

-- Track existing instances
for _, obj in ipairs(game:GetDescendants()) do
	trackDeletion(obj)
end

-- Track new instances added in the future
game.DescendantAdded:Connect(trackDeletion)
