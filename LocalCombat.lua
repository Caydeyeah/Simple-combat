-- Connected Discord-GitHub
-- Client-side combat controller for local player input, UI synchronization, and sensory animations.
-- Credits: Discord Username (Caydeyeah) / Roblox Username (Caydeyeah)

local Players = game:GetService("Players")
local RS      = game:GetService("ReplicatedStorage")
local UIS     = game:GetService("UserInputService")
local TweenS  = game:GetService("TweenService")
local RunSvc  = game:GetService("RunService")

-- The player instance driving this local client script.
local player = Players.LocalPlayer

-- Fetch network remotes used to bridge the client commands and server execution.
-- Setting an explicit timeout (10 seconds) prevents infinite yielding if assets/remotes fail to initialize.
local Remotes      = RS:WaitForChild("CombatRemotes", 10)
local RE_Attack    = Remotes:WaitForChild("Attack",    10)
local RE_Fb        = Remotes:WaitForChild("Feedback",  10)
local RE_Status    = Remotes:WaitForChild("Status",    10)
local RE_ComboSync = Remotes:WaitForChild("ComboSync", 10)

-- Game design constants matching the server-side configuration.
local COMBO_MAX     = 4
local COOLDOWN_TIME = 2

-- State tracking variables.
-- client doesn't track step itself anymore, the server tells us via ComboSync
local onCD     = false
local debounce = false

-- SCREEN GUI SETUP
-- Set up client HUD indicators for combat combo states.
local gui = Instance.new("ScreenGui")
gui.Name           = "CombatGui"
gui.ResetOnSpawn   = false -- Keeps UI alive if character respawns during cooldowns.
gui.ZIndexBehavior = Enum.ZIndexBehavior.Sibling
gui.Parent         = player:WaitForChild("PlayerGui")

-- Container layout for tracking visual pips of the combo chain.
local pipFrame = Instance.new("Frame")
pipFrame.Size                   = UDim2.new(0, 260, 0, 14)
pipFrame.Position               = UDim2.new(0.5, -130, 1, -50)
pipFrame.BackgroundTransparency = 1
pipFrame.Parent                 = gui

-- Align the combo pips horizontally centered.
local layout = Instance.new("UIListLayout")
layout.FillDirection       = Enum.FillDirection.Horizontal
layout.HorizontalAlignment = Enum.HorizontalAlignment.Center
layout.Padding             = UDim.new(0, 6)
layout.Parent              = pipFrame

-- Cooldown countdown timer text label.
local cdLabel = Instance.new("TextLabel")
cdLabel.Size                   = UDim2.new(0, 260, 0, 18)
cdLabel.Position               = UDim2.new(0.5, -130, 1, -72)
cdLabel.BackgroundTransparency = 1
cdLabel.TextColor3             = Color3.fromRGB(220, 70, 70)
cdLabel.TextScaled             = true
-- BEST PRACTICE: Enum.Font is deprecated; Font.fromEnum is the modern and forward-compatible way.
cdLabel.FontFace               = Font.fromEnum(Enum.Font.GothamBold)
cdLabel.Text                   = ""
cdLabel.Parent                 = gui

-- Instantiate and style visual combo pips (one per hit index).
local pips = {}
for i = 1, COMBO_MAX do
	local p = Instance.new("Frame")
	p.Size             = UDim2.new(0, 54, 0, 14)
	p.BackgroundColor3 = Color3.fromRGB(55, 55, 55)
	p.BorderSizePixel  = 0
	p.Parent           = pipFrame
	
	-- BEST PRACTICE: Do not pass a parent argument to Instance.new(className, parent) as it
	-- incurs performance overhead by forcing property updates to trigger hierarchy calculations.
	local corner = Instance.new("UICorner")
	corner.CornerRadius = UDim.new(0, 5)
	corner.Parent = p
	
	pips[i] = p
end

-- Renders the active/inactive state of combo chain indicators.
-- locked = true denotes that the player has completed the combo or suffered cooldown.
local function setPips(step, locked)
	for i, p in ipairs(pips) do
		local col
		if locked then
			-- Heavy warning red when combo is locked during cooldown
			col = Color3.fromRGB(180, 40, 40)
		elseif i < step then
			-- Gold color indicating combo hits successfully completed
			col = Color3.fromRGB(255, 200, 50)
		else
			-- Inactive gray for pending swings in the chain
			col = Color3.fromRGB(55, 55, 55)
		end
		
		-- Use smooth tweens to ease the color transition, preventing visual jarring.
		TweenS:Create(p, TweenInfo.new(0.1), { BackgroundColor3 = col }):Play()
	end
end

local cdConn = nil

-- Starts a frame-rate independent timer on the client to show remaining cooldown time.
local function startCooldownUI()
	onCD = true
	if cdConn then cdConn:Disconnect() end
	
	-- BEST PRACTICE: Replacing tick() with os.clock(). tick() is deprecated, timezone-bound,
	-- and lacks sub-millisecond precision on certain architectures.
	local start = os.clock()
	cdConn = RunSvc.Heartbeat:Connect(function()
		local rem = COOLDOWN_TIME - (os.clock() - start)
		if rem <= 0 then
			cdConn:Disconnect()
			cdConn       = nil
			cdLabel.Text = ""
		else
			cdLabel.Text = string.format("Cooldown  %.1fs", rem)
		end
	end)
end

-- Force-halts the cooldown animation timer (e.g. if reset by server).
local function stopCooldownUI()
	onCD = false
	if cdConn then
		cdConn:Disconnect()
		cdConn = nil
	end
	cdLabel.Text = ""
end

-- Server synchronization event.
-- The server acts as the source of truth for the combo sequence. The client used to manage
-- its own step counter, but latency/hit validation caused visual pips to desync from what the
-- server recorded. Now, the client strictly draws the UI based on server-instructed states.
RE_ComboSync.OnClientEvent:Connect(function(step, locked)
	setPips(step, locked)
	if locked then
		startCooldownUI()
	else
		stopCooldownUI()
	end
end)

-- CAMERA SHAKE FX
-- Instantiates a brief camera roll twitch that gets stronger as the player advances in the combo chain.
-- Design Note: Previously, the 4th hit used a RenderStepped loop writing directly to workspace.CurrentCamera.CFrame.
-- This fought against Roblox's default camera scripts, locking player rotation and causing camera zooms.
-- Using TweenService allows Roblox to run its normal camera script first, then smoothly overlay our CFrame offset.
local function doShake(step)
	local cam = workspace.CurrentCamera
	if not cam then return end

	-- Calculate angular roll offset proportional to the current step (increases impact feel for combo hits).
	local roll   = math.rad(0.5 + step * 0.35)
	local origin = cam.CFrame

	-- Pivot the camera slightly to the side.
	TweenS:Create(cam, TweenInfo.new(0.04, Enum.EasingStyle.Quad, Enum.EasingDirection.Out), {
		CFrame = origin * CFrame.Angles(0, 0, roll)
	}):Play()

	-- Schedule restoration to the original camera orientation.
	task.delay(0.04, function()
		TweenS:Create(cam, TweenInfo.new(0.07, Enum.EasingStyle.Quad, Enum.EasingDirection.Out), {
			CFrame = origin
		}):Play()
	end)
end

-- HIT STOP/FREEZE EFFECT
-- Briefly freezes character movement and anim speed when a hit confirms.
-- This is a classic game design technique ("hitstop") to make attacks feel weightful and impactful.
local function doHitStop(step)
	local char = player.Character
	if not char then return end
	local hum = char:FindFirstChildOfClass("Humanoid")
	if not hum then return end

	-- Finisher (4th hit) has a longer hit-stop duration to emphasize final impact.
	local pauseTime = (step == 4) and 0.09 or 0.04
	local origSpeed = hum.WalkSpeed
	hum.WalkSpeed   = 0

	-- Pause all active animations to freeze the character mid-swing.
	local animator = hum:FindFirstChildOfClass("Animator")
	if animator then
		for _, track in ipairs(animator:GetPlayingAnimationTracks()) do
			track:AdjustSpeed(0)
			
			-- Safely restore animation speeds after hit-stop duration.
			task.delay(pauseTime, function()
				if track and track.IsPlaying then track:AdjustSpeed(1) end
			end)
		end
	end

	-- Restore player mobility.
	task.delay(pauseTime, function()
		if char and char.Parent then hum.WalkSpeed = origSpeed end
	end)
end

-- Remote event listener for hit confirmations.
-- When the server successfully hits an NPC, it fires this to trigger visual impact feedback.
RE_Fb.OnClientEvent:Connect(function(signal, step)
	step = step or 1
	if signal == "HitConfirm" then
		doShake(step)
		doHitStop(step)
	end
end)

-- INPUT LISTENER
-- Listens for MouseButton1 (left click) to execute attacks.
UIS.InputBegan:Connect(function(input, gp)
	-- Ignore inputs if the player is typing in chat or using game-integrated text boxes.
	if gp then return end
	if input.UserInputType ~= Enum.UserInputType.MouseButton1 then return end
	if onCD or debounce then return end

	local char = player.Character
	if not char then return end
	local hrp = char:FindFirstChild("HumanoidRootPart")
	if not hrp then return end

	-- Apply a client-side debounce to prevent networking spam.
	-- We pass the LookVector so the server can align hitboxes, but the server validates positioning internally.
	debounce = true
	RE_Attack:FireServer(hrp.CFrame.LookVector)
	task.delay(0.3, function() debounce = false end)
end)
