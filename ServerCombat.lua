-- Connected Discord-GitHub
-- Server-side combat validation, hit detection, stun, and knockback handling.
-- Credits: Discord Username (Caydeyeah) / Roblox Username (Caydeyeah)
--
-- This script acts as the main referee for the combat. The client just tells us when they want to swing,
-- but the server does all the actual hit checking, damage dealing, stun applying, and knockback calculating.
-- Doing this on the server makes it much harder for players to cheat.

local Players = game:GetService("Players")
local RunService = game:GetService("RunService")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local TweenService = game:GetService("TweenService")
local Debris = game:GetService("Debris")

-- Create the remote folder. ReplicatedStorage is accessible to both server and client.
local Remotes = Instance.new("Folder")
Remotes.Name = "CombatRemotes"
Remotes.Parent = ReplicatedStorage

-- Helper to set up our remote events. We configure properties first and parent last,
-- which is the recommended practice to avoid unnecessary replication updates.
local function createRemote(name)
	local remote = Instance.new("RemoteEvent")
	remote.Name = name
	remote.Parent = Remotes
	return remote
end

local RE_Attack = createRemote("Attack")
local RE_Feedback = createRemote("Feedback")
local RE_ComboSync = createRemote("ComboSync")

-- Combat tuning config. Feel free to tweak these values to change how the game feels!
local Config = {
	HitboxSize = Vector3.new(7, 6, 7.5), -- Width, height, length of the swing area.
	HitboxOffset = 4, -- How far in front of the player the hitbox is centered.
	DotThreshold = 0.5, -- Determines how narrow the frontal cone is (0.5 means roughly 60 degrees).
	ComboDamage = {10, 12, 16, 25}, -- Damage for hits 1, 2, 3, and the finisher.
	KnockbackForce = {18, 22, 28, 55}, -- Knockback speed. Notice how the finisher has a massive kick.
	StunDuration = {0.2, 0.2, 0.3, 1.5}, -- How long the target stays stun-locked.
	AttackCooldown = 0.3, -- Safety delay between swings.
	ComboResetTime = 1.5, -- If you wait longer than this, your combo resets to hit 1.
	MaxCombo = 4, -- 4-hit combo chain.
	SlashColors = {
		Color3.fromRGB(255, 255, 255), -- White
		Color3.fromRGB(255, 215, 0),   -- Gold
		Color3.fromRGB(0, 191, 255),   -- Sky Blue
		Color3.fromRGB(255, 50, 50)    -- Crimson Red (Finisher)
	}
}

local CombatHandler = {}
CombatHandler.__index = CombatHandler

-- Constructor: Sets up the state for a new player.
function CombatHandler.new(player)
	local self = setmetatable({}, CombatHandler)
	self.Player = player
	self.Combo = 1
	self.LastSwing = 0
	self.OnCooldown = false
	return self
end

-- Checks if the player is actually allowed to attack right now.
function CombatHandler:CanSwing()
	local char = self.Player.Character
	if not char then return false end
	
	local hum = char:FindFirstChildOfClass("Humanoid")
	if not hum or hum.Health <= 0 then return false end
	
	-- If they're in the heavy cooldown after a full combo, block the swing.
	if self.OnCooldown then return false end
	
	-- Prevent rapid-click macro spamming by enforcing the cooldown.
	if os.clock() - self.LastSwing < Config.AttackCooldown then return false end
	
	return true
end

-- Visual Effects: Spawns the neon slash indicators when you swing.
local function spawnVFX(cf, step)
	local vfx = Instance.new("Part")
	vfx.Anchored = true
	vfx.CanCollide = false
	vfx.CastShadow = false
	vfx.Material = Enum.Material.Neon
	vfx.Color = Config.SlashColors[step]
	vfx.Size = Vector3.new(0.1, 0.1, 0.1)
	
	-- Add a slight random tilt to the slash so every swing looks a little different.
	vfx.CFrame = cf * CFrame.Angles(0, 0, math.rad(math.random(-15, 15)))
	vfx.Parent = workspace
	
	-- We tween the neon part to look like a quick slash expanding and fading away.
	local targetSize = Vector3.new(Config.HitboxSize.X, 0.1, 2.5)
	local tweenInfo = TweenInfo.new(0.2, Enum.EasingStyle.Quad, Enum.EasingDirection.Out)
	
	TweenService:Create(vfx, tweenInfo, {
		Size = targetSize,
		Transparency = 1,
		CFrame = vfx.CFrame * CFrame.new(0, 0, -2)
	}):Play()
	
	Debris:AddItem(vfx, 0.25)
end

-- Spawns color-coded impact particles on the target when they get hit.
local function spawnHitParticles(pos, color)
	local att = Instance.new("Attachment")
	att.Position = pos
	att.Parent = workspace.Terrain
	
	local particles = Instance.new("ParticleEmitter")
	particles.Color = ColorSequence.new(color)
	particles.Size = NumberSequence.new({
		NumberSequenceKeypoint.new(0, 0.5),
		NumberSequenceKeypoint.new(1, 0)
	})
	particles.Speed = NumberRange.new(10, 20)
	particles.SpreadAngle = Vector2.new(180, 180)
	particles.Lifetime = NumberRange.new(0.15, 0.3)
	particles.Rate = 0
	particles.Parent = att
	
	particles:Emit(10)
	Debris:AddItem(att, 0.4)
end

-- Floating damage indicators. Makes combat feel way more arcade-like and satisfying.
local function spawnDamageText(pos, dmg, isFinisher)
	local gui = Instance.new("BillboardGui")
	gui.Size = UDim2.fromOffset(80, 25)
	gui.StudsOffsetWorldSpace = pos + Vector3.new(0, 2, 0)
	gui.AlwaysOnTop = true
	gui.Parent = workspace.Terrain
	
	local label = Instance.new("TextLabel")
	label.Size = UDim2.fromScale(1, 1)
	label.BackgroundTransparency = 1
	label.Text = tostring(dmg)
	label.TextColor3 = isFinisher and Color3.fromRGB(255, 50, 50) or Color3.fromRGB(255, 255, 255)
	-- BEST PRACTICE: Font is deprecated. We use FontFace with Font.fromEnum for clean modern formatting.
	label.FontFace = Font.fromEnum(Enum.Font.GothamBold)
	label.TextScaled = true
	label.Parent = gui
	
	-- Drift the text upwards and to the side slightly, fading out at the same time.
	local drift = Vector3.new(math.random(-2, 2), 3, math.random(-2, 2))
	local info = TweenInfo.new(0.5, Enum.EasingStyle.Quad, Enum.EasingDirection.Out)
	
	TweenService:Create(gui, info, {StudsOffsetWorldSpace = gui.StudsOffsetWorldSpace + drift}):Play()
	TweenService:Create(label, info, {TextTransparency = 1}):Play()
	
	Debris:AddItem(gui, 0.55)
end

-- Applies a velocity push to the target root part.
-- Modern Roblox uses LinearVelocity rather than the deprecated BodyVelocity.
function CombatHandler:ApplyKnockback(targetRoot, dir, force)
	-- Clean up any lingering knockback objects so they don't stack up and fly the player into orbit.
	for _, child in ipairs(targetRoot:GetChildren()) do
		if child.Name == "CombatKB" or child.Name == "CombatAtt" then
			child:Destroy()
		end
	end
	
	local att = Instance.new("Attachment")
	att.Name = "CombatAtt"
	att.Parent = targetRoot
	
	local lv = Instance.new("LinearVelocity")
	lv.Name = "CombatKB"
	lv.Attachment0 = att
	lv.MaxForce = 150000 -- Big enough to push standard humanoids.
	-- Add a slight upward angle to the knockback so the target gets lifted off the ground.
	lv.VectorVelocity = (dir * force) + Vector3.new(0, force * 0.1, 0)
	lv.Parent = targetRoot
	
	Debris:AddItem(lv, 0.2)
	Debris:AddItem(att, 0.2)
end

-- Applies a stun effect by slowing down the humanoid and setting a state flag.
-- Fixed a major bug here: previously, if you hit someone multiple times, their WalkSpeed
-- got permanently stuck at a slow speed because the second hit saved their *already slowed* speed
-- as their "original" walkspeed. Now we store the true speed in an attribute and don't overwrite it.
function CombatHandler:ApplyStun(hum, duration)
	local char = hum.Parent
	if not char then return end
	
	-- If they are already stunned, we want to reset/extend the stun.
	-- We only capture the "OriginalWalkSpeed" if it hasn't been set yet.
	local originalSpeed = char:GetAttribute("OriginalWalkSpeed")
	if not originalSpeed then
		originalSpeed = hum.WalkSpeed
		char:SetAttribute("OriginalWalkSpeed", originalSpeed)
	end
	
	char:SetAttribute("Stunned", true)
	-- Reduce their walkspeed, but make sure it doesn't go below 0.
	hum.WalkSpeed = math.max(0, originalSpeed - 12)
	
	-- Use a timestamp token to verify that this specific stun instance is the most recent one.
	-- If another hit occurs, the timestamp changes and the old stun cleanup is safely cancelled.
	local stunTime = os.clock()
	char:SetAttribute("LastStunTime", stunTime)
	
	task.delay(duration, function()
		if hum and hum.Parent and char:GetAttribute("LastStunTime") == stunTime then
			hum.WalkSpeed = char:GetAttribute("OriginalWalkSpeed") or 16
			char:SetAttribute("Stunned", nil)
			char:SetAttribute("OriginalWalkSpeed", nil)
			char:SetAttribute("LastStunTime", nil)
		end
	end)
end

-- Checks for targets inside a box in front of the player.
function CombatHandler:ScanHitbox(root)
	local hitboxCF = root.CFrame * CFrame.new(0, 0, -Config.HitboxOffset)
	local params = OverlapParams.new()
	params.FilterType = Enum.RaycastFilterType.Exclude
	params.FilterDescendantsInstances = {self.Player.Character}
	params.MaxParts = 50
	
	-- Spatial query to grab all parts inside the hitbox region.
	local parts = workspace:GetPartBoundsInBox(hitboxCF, Config.HitboxSize, params)
	local matched = {}
	local targets = {}
	
	for _, part in ipairs(parts) do
		local model = part:FindFirstAncestorOfClass("Model")
		if model and not matched[model] then
			matched[model] = true
			
			local hum = model:FindFirstChildOfClass("Humanoid")
			local targetRoot = model:FindFirstChild("HumanoidRootPart")
			
			if hum and targetRoot and hum.Health > 0 then
				local diff = targetRoot.Position - root.Position
				local dist = diff.Magnitude
				
				-- Safe unit vector logic: if they are basically on top of each other,
				-- we hit them directly without dividing by zero (which would produce NaN).
				if dist > 0.01 then
					local toTarget = diff / dist
					local facing = root.CFrame.LookVector
					
					-- Dot product check: makes sure the target is actually in front of the player.
					-- Prevents hitting people behind you.
					if toTarget:Dot(facing) >= Config.DotThreshold then
						table.insert(targets, model)
					end
				else
					table.insert(targets, model)
				end
			end
		end
	end
	
	return targets
end

-- Core attack logic. Runs the combo updates, spawns the visuals, and applies damage.
function CombatHandler:Swing()
	local char = self.Player.Character
	if not char then return end
	
	local root = char:FindFirstChild("HumanoidRootPart")
	if not root then return end
	
	-- If you wait too long between clicks, your combo resets back to hit 1.
	local now = os.clock()
	if now - self.LastSwing > Config.ComboResetTime then
		self.Combo = 1
	end
	
	self.LastSwing = now
	local step = self.Combo
	
	-- Track the combo state and notify the client to sync their UI.
	if step >= Config.MaxCombo then
		self.OnCooldown = true
		self.Combo = 1
		RE_ComboSync:FireClient(self.Player, 1, true)
		-- Locks the player out of attacking for 2 seconds after completing the finisher.
		task.delay(2, function()
			self.OnCooldown = false
			RE_ComboSync:FireClient(self.Player, 1, false)
		end)
	else
		self.Combo = step + 1
		RE_ComboSync:FireClient(self.Player, self.Combo, false)
	end
	
	-- Visual swing trail.
	spawnVFX(root.CFrame * CFrame.new(0, 0, -Config.HitboxOffset + 1), step)
	
	-- Detect and process hits.
	local targets = self:ScanHitbox(root)
	for _, target in ipairs(targets) do
		local hum = target:FindFirstChildOfClass("Humanoid")
		local targetRoot = target:FindFirstChild("HumanoidRootPart")
		
		if hum and targetRoot then
			local dmg = Config.ComboDamage[step]
			local force = Config.KnockbackForce[step]
			local stun = Config.StunDuration[step]
			
			hum:TakeDamage(dmg)
			
			-- Tell the client they successfully hit someone so they can run hit-stop and camera shakes.
			RE_Feedback:FireClient(self.Player, "HitConfirm", step)
			
			-- Visual feedback.
			spawnHitParticles(targetRoot.Position, Config.SlashColors[step])
			spawnDamageText(targetRoot.Position, dmg, step == Config.MaxCombo)
			
			-- Push the target away from us.
			local kbDir = (targetRoot.Position - root.Position).Unit
			if kbDir.Magnitude < 0.01 then kbDir = root.CFrame.LookVector end
			
			self:ApplyKnockback(targetRoot, kbDir, force)
			self:ApplyStun(hum, stun)
		end
	end
end

local combatRegistry = {}

-- Safely register a player to the combat handler. Prevent double-registration.
local function registerPlayer(player)
	if not combatRegistry[player] then
		combatRegistry[player] = CombatHandler.new(player)
	end
end

local function removePlayer(player)
	combatRegistry[player] = nil
end

-- Programmatic Training Dummy builder for testing combat.
local function spawnTrainingDummy(pos)
	local dummy = Instance.new("Model")
	dummy.Name = "Training Dummy"
	
	local hum = Instance.new("Humanoid")
	hum.MaxHealth = 300
	hum.Health = 300
	hum.DisplayDistanceType = Enum.HumanoidDisplayDistanceType.None
	hum.Parent = dummy
	
	local function createPart(name, size, color)
		local part = Instance.new("Part")
		part.Name = name
		part.Size = size
		part.Color = color
		part.Material = Enum.Material.SmoothPlastic
		part.Anchored = false
		part.CanCollide = true
		part.Parent = dummy
		return part
	end
	
	-- Build the body parts.
	local hrp = createPart("HumanoidRootPart", Vector3.new(2, 2, 1), Color3.fromRGB(120, 120, 120))
	local torso = createPart("Torso", Vector3.new(2, 2, 1), Color3.fromRGB(45, 120, 210))
	local head = createPart("Head", Vector3.new(1.2, 1.2, 1.2), Color3.fromRGB(255, 220, 150))
	local rArm = createPart("Right Arm", Vector3.new(1, 2, 1), Color3.fromRGB(45, 120, 210))
	local lArm = createPart("Left Arm", Vector3.new(1, 2, 1), Color3.fromRGB(45, 120, 210))
	local rLeg = createPart("Right Leg", Vector3.new(1, 2, 1), Color3.fromRGB(80, 80, 80))
	local lLeg = createPart("Left Leg", Vector3.new(1, 2, 1), Color3.fromRGB(80, 80, 80))
	
	dummy.PrimaryPart = hrp
	hrp.CFrame = CFrame.new(pos)
	
	-- Position parts relative to the root part.
	local welds = {
		[torso] = CFrame.new(0, 0, 0),
		[head] = CFrame.new(0, 1.6, 0),
		[rArm] = CFrame.new(1.5, 0, 0),
		[lArm] = CFrame.new(-1.5, 0, 0),
		[rLeg] = CFrame.new(0.5, -2, 0),
		[lLeg] = CFrame.new(-0.5, -2, 0)
	}
	
	for part, offset in pairs(welds) do
		part.CFrame = hrp.CFrame * offset
		local weld = Instance.new("WeldConstraint")
		weld.Part0 = hrp
		weld.Part1 = part
		weld.Parent = dummy
	end
	
	-- Overhead Health Bar GUI.
	local ui = Instance.new("BillboardGui")
	ui.Name = "StatusUI"
	ui.Size = UDim2.fromOffset(100, 16)
	ui.StudsOffset = Vector3.new(0, 3.5, 0)
	ui.AlwaysOnTop = true
	ui.Adornee = hrp
	ui.Parent = hrp
	
	local bg = Instance.new("Frame")
	bg.Size = UDim2.fromScale(1, 1)
	bg.BackgroundColor3 = Color3.fromRGB(20, 20, 20)
	bg.BorderSizePixel = 0
	bg.Parent = ui
	
	local bgCorner = Instance.new("UICorner")
	bgCorner.CornerRadius = UDim.new(0, 5)
	bgCorner.Parent = bg
	
	local barBg = Instance.new("Frame")
	barBg.Size = UDim2.new(1, -4, 1, -4)
	barBg.Position = UDim2.new(0, 2, 0, 2)
	barBg.BackgroundColor3 = Color3.fromRGB(40, 40, 40)
	barBg.BorderSizePixel = 0
	barBg.Parent = bg
	
	local barBgCorner = Instance.new("UICorner")
	barBgCorner.CornerRadius = UDim.new(0, 4)
	barBgCorner.Parent = barBg
	
	local barFill = Instance.new("Frame")
	barFill.Size = UDim2.fromScale(1, 1)
	barFill.BackgroundColor3 = Color3.fromRGB(60, 200, 90)
	barFill.BorderSizePixel = 0
	barFill.Parent = barBg
	
	local barFillCorner = Instance.new("UICorner")
	barFillCorner.CornerRadius = UDim.new(0, 4)
	barFillCorner.Parent = barFill
	
	local text = Instance.new("TextLabel")
	text.Size = UDim2.fromScale(1, 1)
	text.BackgroundTransparency = 1
	text.TextColor3 = Color3.fromRGB(255, 255, 255)
	text.FontFace = Font.fromEnum(Enum.Font.GothamBold)
	text.TextSize = 9
	text.Text = "HP: 300/300"
	text.Parent = barBg
	
	-- Animates the health bar color transitions smoothly.
	local function updateUI()
		local ratio = math.clamp(hum.Health / hum.MaxHealth, 0, 1)
		local stunned = dummy:GetAttribute("Stunned")
		
		local color = Color3.fromRGB(60, 200, 90) -- Green
		if stunned then
			color = Color3.fromRGB(160, 80, 220) -- Purple when stunned
		elseif ratio < 0.35 then
			color = Color3.fromRGB(220, 60, 60) -- Red when low HP
		elseif ratio < 0.65 then
			color = Color3.fromRGB(240, 170, 40) -- Orange when medium HP
		end
		
		TweenService:Create(barFill, TweenInfo.new(0.1), {
			Size = UDim2.fromScale(ratio, 1),
			BackgroundColor3 = color
		}):Play()
		
		text.Text = stunned and "STUNNED" or string.format("HP: %d/%d", math.floor(hum.Health), hum.MaxHealth)
	end
	
	hum:GetPropertyChangedSignal("Health"):Connect(updateUI)
	dummy:GetAttributeChangedSignal("Stunned"):Connect(updateUI)
	
	-- Automatically respawn the dummy 2 seconds after it dies.
	hum.Died:Connect(function()
		task.wait(2)
		dummy:Destroy()
		spawnTrainingDummy(pos)
	end)
	
	dummy.Parent = workspace
end

-- Handle swing requests sent by client click events.
RE_Attack.OnServerEvent:Connect(function(player, dir)
	local handler = combatRegistry[player]
	-- Security: validate timing and player states on the server to block rapid fires or stun exploits.
	if handler and handler:CanSwing() then
		handler:Swing()
	end
end)

Players.PlayerAdded:Connect(registerPlayer)
Players.PlayerRemoving:Connect(removePlayer)

-- Catch any players that joined before the script started running.
for _, p in ipairs(Players:GetPlayers()) do
	registerPlayer(p)
end

-- Populate the demo scene with a few dummies.
spawnTrainingDummy(Vector3.new(0, 3, -15))
spawnTrainingDummy(Vector3.new(8, 3, -13))
spawnTrainingDummy(Vector3.new(-8, 3, -13))
