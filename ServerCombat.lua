-- Script -> ServerScriptService

local Players = game:GetService("Players")
local RunSvc  = game:GetService("RunService")
local RS      = game:GetService("ReplicatedStorage")
local TweenS  = game:GetService("TweenService")

local Remotes      = Instance.new("Folder")
Remotes.Name       = "CombatRemotes"
Remotes.Parent     = RS

local function mkRemote(name)
	local r  = Instance.new("RemoteEvent")
	r.Name   = name
	r.Parent = Remotes
	return r
end

local RE_Attack    = mkRemote("Attack")
local RE_Fb        = mkRemote("Feedback")
local RE_Status    = mkRemote("Status")
local RE_ComboSync = mkRemote("ComboSync")

local CONFIG = {
	HIT_RADIUS         = 11,
	HIT_OFFSET         = 1.5,
	COMBO_DAMAGE       = { 8, 10, 14, 22 },
	ATTACK_COOLDOWN    = 0.28,
	COMBO_RESET_TIME   = 2.0,
	KNOCKBACK_FORCE    = 42,
	KNOCKBACK_DURATION = 0.30,
	STUN_DURATION      = 1.5,
	DOT_THRESHOLD      = -0.5,
}

local dummyHpBar   = nil
local dummyStunned = false

local HP_NORMAL  = Color3.fromRGB(60, 200, 90)
local HP_LOW     = Color3.fromRGB(220, 60, 60)
local HP_STUNNED = Color3.fromRGB(160, 80, 220)

local function getHpColor(ratio, stunned)
	if stunned then return HP_STUNNED end
	return Color3.new(
		HP_LOW.R + (HP_NORMAL.R - HP_LOW.R) * ratio,
		HP_LOW.G + (HP_NORMAL.G - HP_LOW.G) * ratio,
		HP_LOW.B + (HP_NORMAL.B - HP_LOW.B) * ratio
	)
end

local function spawnDummy(pos)
	local model   = Instance.new("Model")
	model.Name    = "Dummy"

	local hum     = Instance.new("Humanoid")
	hum.MaxHealth = 350
	hum.Health    = 350
	hum.Parent    = model

	-- turn off the default roblox overhead bar, we have our own
	hum.DisplayDistanceType = Enum.HumanoidDisplayDistanceType.None

	local function part(name, size, color)
		local p      = Instance.new("Part")
		p.Name       = name
		p.Size       = size
		p.BrickColor = BrickColor.new(color)
		p.Anchored   = false
		p.CanCollide = true
		p.Parent     = model
		return p
	end

	local hrp   = part("HumanoidRootPart", Vector3.new(2, 2, 1),       "Medium stone grey")
	local torso = part("Torso",            Vector3.new(2, 2, 1),       "Bright blue")
	local head  = part("Head",             Vector3.new(1.2, 1.2, 1.2), "Pastel yellow")
	local lArm  = part("Left Arm",         Vector3.new(1, 2, 1),       "Bright blue")
	local rArm  = part("Right Arm",        Vector3.new(1, 2, 1),       "Bright blue")
	local lLeg  = part("Left Leg",         Vector3.new(1, 2, 1),       "Reddish brown")
	local rLeg  = part("Right Leg",        Vector3.new(1, 2, 1),       "Reddish brown")

	model.PrimaryPart = hrp
	hrp.CFrame        = CFrame.new(pos)

	local offsets = {
		[torso] = CFrame.new(0,    0,   0),
		[head]  = CFrame.new(0,    1.6, 0),
		[lArm]  = CFrame.new(-1.5, 0,   0),
		[rArm]  = CFrame.new( 1.5, 0,   0),
		[lLeg]  = CFrame.new(-0.5,-2,   0),
		[rLeg]  = CFrame.new( 0.5,-2,   0),
	}

	for p, offset in pairs(offsets) do
		p.CFrame = hrp.CFrame * offset
		local w  = Instance.new("WeldConstraint")
		w.Part0  = hrp
		w.Part1  = p
		w.Parent = model
	end

	-- health bar, AlwaysOnTop so it doesn't flicker when geometry is in the way
	local bb       = Instance.new("BillboardGui")
	bb.Size        = UDim2.new(0, 90, 0, 12)
	bb.StudsOffset = Vector3.new(0, 4.2, 0)
	bb.AlwaysOnTop = true
	bb.Adornee     = hrp
	bb.Parent      = hrp

	local border            = Instance.new("Frame")
	border.Size             = UDim2.new(1, 0, 1, 0)
	border.BackgroundColor3 = Color3.fromRGB(15, 15, 15)
	border.BorderSizePixel  = 0
	border.Parent           = bb
	Instance.new("UICorner", border).CornerRadius = UDim.new(0, 5)

	local innerBg            = Instance.new("Frame")
	innerBg.Size             = UDim2.new(1, -4, 1, -4)
	innerBg.Position         = UDim2.new(0, 2, 0, 2)
	innerBg.BackgroundColor3 = Color3.fromRGB(30, 30, 30)
	innerBg.BorderSizePixel  = 0
	innerBg.Parent           = border
	Instance.new("UICorner", innerBg).CornerRadius = UDim.new(0, 4)

	local hpFill            = Instance.new("Frame")
	hpFill.Size             = UDim2.new(1, 0, 1, 0)
	hpFill.BackgroundColor3 = HP_NORMAL
	hpFill.BorderSizePixel  = 0
	hpFill.Parent           = innerBg
	Instance.new("UICorner", hpFill).CornerRadius = UDim.new(0, 4)

	local hpText                  = Instance.new("TextLabel")
	hpText.Size                   = UDim2.new(1, 0, 1, 0)
	hpText.BackgroundTransparency = 1
	hpText.TextColor3             = Color3.new(1, 1, 1)
	hpText.TextScaled             = true
	hpText.Font                   = Enum.Font.GothamBold
	hpText.Text                   = tostring(hum.MaxHealth)
	hpText.ZIndex                 = 3
	hpText.Parent                 = hpFill

	dummyHpBar = hpFill

	local function refreshBar()
		local ratio = math.clamp(hum.Health / hum.MaxHealth, 0, 1)
		TweenS:Create(hpFill, TweenInfo.new(0.12), {
			Size             = UDim2.new(ratio, 0, 1, 0),
			BackgroundColor3 = getHpColor(ratio, dummyStunned),
		}):Play()
		hpText.Text = tostring(math.floor(hum.Health))
	end

	hum:GetPropertyChangedSignal("Health"):Connect(refreshBar)

	hum.Died:Connect(function()
		dummyHpBar   = nil
		dummyStunned = false
		task.wait(2)
		model:Destroy()
		spawnDummy(pos)
	end)

	model.Parent = workspace
end

spawnDummy(Vector3.new(0, 3, -12))

local function knockback(fromChar, toChar)
	local a = fromChar:FindFirstChild("HumanoidRootPart")
	local b = toChar:FindFirstChild("HumanoidRootPart")
	if not a or not b then return end

	for _, p in ipairs(toChar:GetDescendants()) do
		if p:IsA("BasePart") then p.Anchored = false end
	end

	-- strip out Y so it's a flat shove, not a launch
	local flatDir = Vector3.new(b.Position.X - a.Position.X, 0, b.Position.Z - a.Position.Z)
	if flatDir.Magnitude < 0.01 then flatDir = Vector3.new(0, 0, 1) end

	local bv    = Instance.new("BodyVelocity")
	bv.Velocity = flatDir.Unit * CONFIG.KNOCKBACK_FORCE
	bv.MaxForce = Vector3.new(1e5, 1e5, 1e5)
	bv.P        = 1e4
	bv.Parent   = b

	task.delay(CONFIG.KNOCKBACK_DURATION, function()
		if bv and bv.Parent then bv:Destroy() end
	end)
end

local function stunDummy(toChar)
	local hum = toChar:FindFirstChildOfClass("Humanoid")
	if not hum then return end

	dummyStunned    = true
	local origSpeed = hum.WalkSpeed
	hum.WalkSpeed   = 0

	if dummyHpBar then
		local ratio = math.clamp(hum.Health / hum.MaxHealth, 0, 1)
		TweenS:Create(dummyHpBar, TweenInfo.new(0.1), {
			Size             = UDim2.new(ratio, 0, 1, 0),
			BackgroundColor3 = HP_STUNNED,
		}):Play()
	end

	task.delay(CONFIG.STUN_DURATION, function()
		dummyStunned  = false
		hum.WalkSpeed = origSpeed
		if dummyHpBar then
			local ratio = math.clamp(hum.Health / hum.MaxHealth, 0, 1)
			TweenS:Create(dummyHpBar, TweenInfo.new(0.2), {
				BackgroundColor3 = getHpColor(ratio, false),
			}):Play()
		end
	end)
end

local function detectHits(char, dir)
	local hrp = char:FindFirstChild("HumanoidRootPart")
	if not hrp then return {} end

	local mag = dir.Magnitude
	if mag < 0.01 then return {} end
	local unitDir = dir / mag

	local origin  = hrp.Position + unitDir * CONFIG.HIT_OFFSET
	local results = {}

	for _, p in ipairs(Players:GetPlayers()) do
		local c  = p.Character
		if not c or c == char then continue end
		local h  = c:FindFirstChild("HumanoidRootPart")
		local hm = c:FindFirstChildOfClass("Humanoid")
		if not h or not hm or hm.Health <= 0 then continue end
		local delta = h.Position - origin
		if delta.Magnitude <= CONFIG.HIT_RADIUS and delta.Unit:Dot(unitDir) > CONFIG.DOT_THRESHOLD then
			table.insert(results, { char = c, hum = hm, isPlayer = true })
		end
	end

	for _, obj in ipairs(workspace:GetChildren()) do
		if not obj:IsA("Model") then continue end
		if Players:GetPlayerFromCharacter(obj) then continue end
		local h  = obj:FindFirstChild("HumanoidRootPart")
		local hm = obj:FindFirstChildOfClass("Humanoid")
		if not h or not hm or hm.Health <= 0 then continue end
		local delta = h.Position - origin
		if delta.Magnitude <= CONFIG.HIT_RADIUS and delta.Unit:Dot(unitDir) > CONFIG.DOT_THRESHOLD then
			table.insert(results, { char = obj, hum = hm, isPlayer = false })
		end
	end

	return results
end

local states = {}

local function initState(p)
	states[p] = {
		step       = 1,
		lastSwing  = 0,
		swinging   = false,
		onCooldown = false,
	}
end

-- runs every frame and resets a player's combo if they haven't swung in 2 seconds.
-- has to be a background loop because the old way (checking at the start of the next swing)
-- meant stopping mid-combo never reset anything until you swung again.
RunSvc.Heartbeat:Connect(function()
	local now = tick()
	for player, s in pairs(states) do
		if s.step > 1 and not s.onCooldown and (now - s.lastSwing) >= CONFIG.COMBO_RESET_TIME then
			s.step = 1
			RE_ComboSync:FireClient(player, 1, false)
		end
	end
end)

RE_Attack.OnServerEvent:Connect(function(player, swingDir)
	if typeof(swingDir) ~= "Vector3" then return end
	local mag = swingDir.Magnitude
	if mag ~= mag or mag == math.huge or mag < 0.01 then return end

	local s    = states[player]
	local char = player.Character
	if not s or not char then return end
	if s.swinging or s.onCooldown then return end

	local now = tick()
	if now - s.lastSwing < CONFIG.ATTACK_COOLDOWN then return end

	s.swinging  = true
	s.lastSwing = now

	local hits = detectHits(char, swingDir)

	for _, v in ipairs(hits) do
		local dmg = CONFIG.COMBO_DAMAGE[s.step] or CONFIG.COMBO_DAMAGE[#CONFIG.COMBO_DAMAGE]
		v.hum:TakeDamage(dmg)
		RE_Fb:FireClient(player, "HitConfirm", s.step)
	end

	-- 4th swing knocks back whatever it hits regardless of whether the first 3 landed
	if s.step == 4 and #hits > 0 then
		for _, v in ipairs(hits) do
			knockback(char, v.char)
			stunDummy(v.char)
		end
	end

	if s.step >= 4 then
		s.onCooldown = true
		s.step       = 1
		RE_ComboSync:FireClient(player, 1, true)
		task.delay(2, function()
			if states[player] then
				states[player].onCooldown = false
				RE_ComboSync:FireClient(player, 1, false)
			end
		end)
	else
		s.step += 1
		RE_ComboSync:FireClient(player, s.step, false)
	end

	task.defer(function()
		if states[player] then states[player].swinging = false end
	end)
end)

Players.PlayerAdded:Connect(function(p)
	p.CharacterAdded:Connect(function()
		task.wait()
		initState(p)
	end)
end)

for _, p in ipairs(Players:GetPlayers()) do
	if p.Character then initState(p) end
end

Players.PlayerRemoving:Connect(function(p)
	states[p] = nil
end)
