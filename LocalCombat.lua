-- Connected Discord-GitHub
-- Client side combat controller. Handles clicks, UI, and visual effects.
-- Credits: Caydeyeah (Discord/Roblox)

local Players = game:GetService("Players")
local RS      = game:GetService("ReplicatedStorage")
local UIS     = game:GetService("UserInputService")
local TweenS  = game:GetService("TweenService")
local RunSvc  = game:GetService("RunService")

local player = Players.LocalPlayer

-- get the network events. 10s timeout so it doesn't freeze loading if something is missing
local Remotes      = RS:WaitForChild("CombatRemotes", 10)
local RE_Attack    = Remotes:WaitForChild("Attack",    10)
local RE_Fb        = Remotes:WaitForChild("Feedback",  10)
local RE_Status    = Remotes:WaitForChild("Status",    10)
local RE_ComboSync = Remotes:WaitForChild("ComboSync", 10)

-- match these with the server configs
local COMBO_MAX     = 4
local COOLDOWN_TIME = 2

local onCD     = false
local debounce = false

-- set up the screen gui. resetonspawn false so it stays active if they die mid-cooldown
local gui = Instance.new("ScreenGui")
gui.Name           = "CombatGui"
gui.ResetOnSpawn   = false
gui.ZIndexBehavior = Enum.ZIndexBehavior.Sibling
gui.Parent         = player:WaitForChild("PlayerGui")

-- container for the combo pips
local pipFrame = Instance.new("Frame")
pipFrame.Size                   = UDim2.new(0, 260, 0, 14)
pipFrame.Position               = UDim2.new(0.5, -130, 1, -50)
pipFrame.BackgroundTransparency = 1
pipFrame.Parent                 = gui

-- lines up the pips horizontally
local layout = Instance.new("UIListLayout")
layout.FillDirection       = Enum.FillDirection.Horizontal
layout.HorizontalAlignment = Enum.HorizontalAlignment.Center
layout.Padding             = UDim.new(0, 6)
layout.Parent              = pipFrame

-- cooldown display label
local cdLabel = Instance.new("TextLabel")
cdLabel.Size                   = UDim2.new(0, 260, 0, 18)
cdLabel.Position               = UDim2.new(0.5, -130, 1, -72)
cdLabel.BackgroundTransparency = 1
cdLabel.TextColor3             = Color3.fromRGB(220, 70, 70)
cdLabel.TextScaled             = true
-- Font is deprecated, using FontFace instead so roblox doesn't complain
cdLabel.FontFace               = Font.fromEnum(Enum.Font.GothamBold)
cdLabel.Text                   = ""
cdLabel.Parent                 = gui

-- generate the pips. setting parent in Instance.new constructor is slow, so doing it after config
local pips = {}
for i = 1, COMBO_MAX do
	local p = Instance.new("Frame")
	p.Size             = UDim2.new(0, 54, 0, 14)
	p.BackgroundColor3 = Color3.fromRGB(55, 55, 55)
	p.BorderSizePixel  = 0
	p.Parent           = pipFrame
	
	local corner = Instance.new("UICorner")
	corner.CornerRadius = UDim.new(0, 5)
	corner.Parent = p
	
	pips[i] = p
end

-- colors the combo blocks. yellow = hit, red = locked/cooldown, gray = empty
local function setPips(step, locked)
	for i, p in ipairs(pips) do
		local col
		if locked then
			col = Color3.fromRGB(180, 40, 40)
		elseif i < step then
			col = Color3.fromRGB(255, 200, 50)
		else
			col = Color3.fromRGB(55, 55, 55)
		end
		-- quick tween to keep it smooth
		TweenS:Create(p, TweenInfo.new(0.1), { BackgroundColor3 = col }):Play()
	end
end

local cdConn = nil

-- updates the cooldown text every frame. os.clock is the replacement for tick()
local function startCooldownUI()
	onCD = true
	if cdConn then cdConn:Disconnect() end
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

-- stops the cooldown text updater
local function stopCooldownUI()
	onCD = false
	if cdConn then
		cdConn:Disconnect()
		cdConn = nil
	end
	cdLabel.Text = ""
end

-- server is the boss of the combo steps to avoid desyncs, we just sync visuals to what it says
RE_ComboSync.OnClientEvent:Connect(function(step, locked)
	setPips(step, locked)
	if locked then
		startCooldownUI()
	else
		stopCooldownUI()
	end
end)

-- quick camera tilt. tweens won't fight with roblox's camera scripts like renderstepped loops did
local function doShake(step)
	local cam = workspace.CurrentCamera
	if not cam then return end

	local roll   = math.rad(0.5 + step * 0.35)
	local origin = cam.CFrame

	TweenS:Create(cam, TweenInfo.new(0.04, Enum.EasingStyle.Quad, Enum.EasingDirection.Out), {
		CFrame = origin * CFrame.Angles(0, 0, roll)
	}):Play()

	task.delay(0.04, function()
		TweenS:Create(cam, TweenInfo.new(0.07, Enum.EasingStyle.Quad, Enum.EasingDirection.Out), {
			CFrame = origin
		}):Play()
	end)
end

-- hitstop. briefly halts movement and animation tracks so hits feel heavy/punchy
local function doHitStop(step)
	local char = player.Character
	if not char then return end
	local hum = char:FindFirstChildOfClass("Humanoid")
	if not hum then return end

	local pauseTime = (step == 4) and 0.09 or 0.04
	local origSpeed = hum.WalkSpeed
	hum.WalkSpeed   = 0

	local animator = hum:FindFirstChildOfClass("Animator")
	if animator then
		for _, track in ipairs(animator:GetPlayingAnimationTracks()) do
			track:AdjustSpeed(0)
			task.delay(pauseTime, function()
				if track and track.IsPlaying then track:AdjustSpeed(1) end
			end)
		end
	end

	task.delay(pauseTime, function()
		if char and char.Parent then hum.WalkSpeed = origSpeed end
	end)
end

-- server confirmed a hit, run the screen effects
RE_Fb.OnClientEvent:Connect(function(signal, step)
	step = step or 1
	if signal == "HitConfirm" then
		doShake(step)
		doHitStop(step)
	end
end)

-- click input listener. checks cooldowns and debounces so they can't spam
UIS.InputBegan:Connect(function(input, gp)
	if gp then return end
	if input.UserInputType ~= Enum.UserInputType.MouseButton1 then return end
	if onCD or debounce then return end

	local char = player.Character
	if not char then return end
	local hrp = char:FindFirstChild("HumanoidRootPart")
	if not hrp then return end

	debounce = true
	RE_Attack:FireServer(hrp.CFrame.LookVector)
	task.delay(0.3, function() debounce = false end)
end)
