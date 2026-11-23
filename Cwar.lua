--[[ ColdWar.lua — Cold War [VIETNAM] (place 13687899540)
   Rebranded: Sill X | Fixed ESP & Legit Defaults
]]

local Players           = game:GetService("Players")
local RunService        = game:GetService("RunService")
local UserInputService  = game:GetService("UserInputService")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local Lighting          = game:GetService("Lighting")

local plr    = Players.LocalPlayer
local camera = workspace.CurrentCamera
workspace:GetPropertyChangedSignal("CurrentCamera"):Connect(function()
	if workspace.CurrentCamera then camera = workspace.CurrentCamera end
end)

if type(_G.__CWAR_CLEANUP) == "function" then
	pcall(_G.__CWAR_CLEANUP)
end
pcall(function() RunService:UnbindFromRenderStep("CWAim") end)
pcall(function() RunService:UnbindFromRenderStep("CWESP") end)
pcall(function() RunService:UnbindFromRenderStep("CWSpec") end)

_G.__CWAR = (_G.__CWAR or 0) + 1
local GEN = _G.__CWAR

local STUDS_PER_M = 3.5714285714285716
local LIMBS = { "Head", "Torso", "Left Arm", "Right Arm", "Left Leg", "Right Leg" }
local LIMBSET = {}
for _, n in ipairs(LIMBS) do LIMBSET[n] = true end
local HAS_DRAWING = (Drawing ~= nil and Drawing.new ~= nil)

if not HAS_DRAWING then
    warn("[Sill X] Executor ของคุณไม่รองรับ Drawing API ทำให้ ESP ใช้ไม่ได้")
end

local mouse1click = mouse1click or function() end
local mouse1press = mouse1press or function() end
local mouse1release = mouse1release or function() end

--------------------------------------------------------------------------------
-- CONFIG (Legit Defaults)
--------------------------------------------------------------------------------

local CONFIG = {
	-- ESP
	esp         = true, espBox      = true, espName     = true, espInfo     = true,
	espClass    = true, espHealth   = true, espLimbs    = false, espFlags    = true,
	espSkeleton = false, espTracer  = false, espHeadDot  = false, espVisOnly  = false,
	espDimHidden = true, espTeam    = false, espVehicles = true, espEmptyVeh = false,
	espVehBox   = true, espVehCrew  = true, 
	espMaxM     = 1000, espTextSize = 13,

	-- AIM (Legit Settings)
	aim         = false, aimActive   = "Hotkey", aimKey      = "MouseButton2",
	aimPart     = "Torso", aimFov      = 80, aimSmoothH  = 35, aimSmoothV  = 35,
	aimVisible  = true, aimPredict  = true, aimSticky   = true, aimMaxM     = 600,
	aimCircle   = true, aimDeliver  = "Camera", hum         = true, humReactMin = 120,
	humReactMax = 220, humRampMs   = 250, humMaxDegS  = 180,

	-- TRIGGERBOT
	triggerBot    = false, triggerPart  = "Torso", triggerMode  = "Click",
	triggerRadius = 10, triggerDelay = 150, triggerVis   = true,

	-- SILENT
	silent      = false, silentFovDeg = 3, silentPart  = "Torso", silentChance = 80,
	silentMaxM  = 600, silentLead  = true, silentCircle = true,

	skipDowned  = true, skipSpawn   = true,
	noFog       = false, fullbright  = false, noSuppress  = false,
	noRecoil    = true, 
	panicKey    = "F1",
}

local COL = {
	enemy   = Color3.fromRGB(255, 86, 86), visible = Color3.fromRGB(255, 214, 90),
	team    = Color3.fromRGB(90, 160, 255), text    = Color3.fromRGB(240, 240, 240),
	fov     = Color3.fromRGB(255, 255, 255), silent  = Color3.fromRGB(255, 120, 200),
	veh     = Color3.fromRGB(255, 160, 60), vehTeam = Color3.fromRGB(110, 170, 255),
	vehCrew = Color3.fromRGB(255, 50, 50), 
}

local STATE = { enemies = 0, drawn = 0, target = "-", bent = 0, panelOpen = false }

--------------------------------------------------------------------------------
-- GAME HANDLES & LOGIC
--------------------------------------------------------------------------------

local GAME = {}
local function req(inst) if not inst then return nil end local ok, m = pcall(require, inst) return ok and m or nil end
local function resolveGame()
	if GAME.ok then return true end
	local shared = ReplicatedStorage:FindFirstChild("Shared")
	local bal = shared and shared:FindFirstChild("Ballistics")
	local src = bal and bal:FindFirstChild("Sources")
	local ps = plr:FindFirstChild("PlayerScripts")
	local bc = ps and ps:FindFirstChild("BallisticsClient")
	
	GAME.Traj = GAME.Traj or req(bal and bal:FindFirstChild("Trajectory"))
	GAME.WS = GAME.WS or req(src and src:FindFirstChild("WeaponSource"))
	GAME.CF = GAME.CF or req(bc and bc:FindFirstChild("ClientFire"))
	GAME.Armor = GAME.Armor or req(shared and shared.TerminalBallistics and shared.TerminalBallistics:FindFirstChild("ArmorModel"))
	
	GAME.ok = (GAME.Traj and GAME.WS and GAME.CF) and true or false
	return GAME.ok
end

local COMBAT = { NATO = true, PACT = true }
local function teamName(p) local t = p.Team return t and t.Name or nil end
local function isEnemy(p)
	if p == plr then return false end
	local mine, theirs = teamName(plr), teamName(p)
	-- ถ้ายังไม่เข้าเกม (ไม่มีทีม) ให้คืนค่า false ก่อน
	if not COMBAT[mine] or not COMBAT[theirs] then return false end
	return COMBAT[mine] == true and COMBAT[theirs] == true and mine ~= theirs
end
local function isMate(p)
	if p == plr then return false end
	local mine = teamName(plr)
	return COMBAT[mine] == true and teamName(p) == mine
end

local function limbHealth(char, name)
	local part = char:FindFirstChild(name)
	local h = part and part:FindFirstChild("Health")
	if h and h:IsA("NumberValue") then return h.Value, (h:GetAttribute("MaxHealth") or h.Value) end
	return nil
end

local function liveChar(p)
	local char = p.Character
	if not char or not char.Parent then return nil end
	if char:GetAttribute("Ragdolled") ~= nil then return nil end
	local root = char:FindFirstChild("HumanoidRootPart")
	if not root then return nil end
	local hh = limbHealth(char, "Head")
	local th = limbHealth(char, "Torso")
	if (hh and hh <= 0) or (th and th <= 0) then return nil end
	local sum, max = 0, 0
	for _, n in ipairs(LIMBS) do local v, m = limbHealth(char, n) if v then sum = sum + math.max(v, 0) max = max + m end end
	return char, root, sum, max
end

local function isDowned(char) local cv = char:FindFirstChild("CharacterValues") local u = cv and cv:FindFirstChild("Unconscious") return u ~= nil and u.Value == true end
local function hasSpawnShield(char) return char:FindFirstChildOfClass("ForceField") ~= nil end
local function isDisguised(char) return char:GetAttribute("DisguiseName") ~= nil end

local function shootable(p)
	if not isEnemy(p) then return nil end
	local char, root = liveChar(p)
	if not char then return nil end
	if CONFIG.skipDowned and isDowned(char) then return nil end
	if CONFIG.skipSpawn and hasSpawnShield(char) then return nil end
	return char, root
end

local ROLE_PREFIX = { "EastGerman", "WestGer", "NavySeals", "DeltaForce", "Soviet", "Polish", "Czech", "French", "Spetsnaz", "Reserve", "VDV", "VMF", "GRU", "US", "UK", "NG" }
local function roleOf(p)
	local cn = p:GetAttribute("ClassName")
	if type(cn) ~= "string" or cn == "" then local ct = p:GetAttribute("ClassType") return type(ct) == "string" and ct or nil end
	local s = cn
	for _ = 1, 3 do for _, pre in ipairs(ROLE_PREFIX) do if s:sub(1, #pre) == pre and #s > #pre then s = s:sub(#pre + 1) end end end
	return s
end
local function weaponOf(char)
	local tool = char:FindFirstChildOfClass("Tool")
	if tool then return tool.Name end
	for _, k in ipairs(char:GetChildren()) do if k:IsA("Model") and k.Name:sub(-5) == "Model" then return k.Name:sub(1, -6) end end
	return nil
end

-- Ballistics
local fpCache = { tool = nil, at = 0, fp = nil }
local function fireParamsFor(tool, origin, dir, mi, bi)
	if not resolveGame() then return nil end
	local ok, fp = pcall(GAME.WS.toFireParams, { Tool = tool, MuzzleIndex = mi or 1, BulletIndex = bi or 1, Origin = origin, Direction = dir or Vector3.new(0, 0, -1), Owner = plr })
	return ok and fp or nil
end
local function heldWeapon() local char = plr.Character local tool = char and char:FindFirstChildOfClass("Tool") if tool and tool:GetAttribute("ToolType") == "Weapon" then return tool end return nil end
local function cachedFireParams()
	local tool = heldWeapon() local now = os.clock()
	if tool ~= fpCache.tool or now - fpCache.at > 1 then fpCache.tool, fpCache.at = tool, now fpCache.fp = tool and fireParamsFor(tool, camera.CFrame.Position) or nil end
	return fpCache.fp
end

local visParams = RaycastParams.new() visParams.FilterType = Enum.RaycastFilterType.Exclude visParams.IgnoreWater = true
local visAt = 0
local function refreshVisParams()
	local now = os.clock() if now - visAt < 1 then return end
	visAt = now local list = { plr.Character } local ign = workspace:FindFirstChild("Ignore") if ign then table.insert(list, ign) end visParams.FilterDescendantsInstances = list
end
local function seen(char, part) local o = camera.CFrame.Position local fp = cachedFireParams() local params = fp and fp.RaycastParams or visParams local r = workspace:Raycast(o, part.Position - o, params) return (r == nil) or r.Instance:IsDescendantOf(char) end
local function trajOf(o, dir, w) return GAME.Traj.new({ Origin = o, Direction = dir, MuzzleSpeed = w.MuzzleSpeed, K = w.K }) end

local function solveArc(o, T, w, vel)
	local tr = trajOf(o, Vector3.new(0, 0, -1), w)
	local t = GAME.Traj.GetTimeForDistance(tr, (T - o).Magnitude)
	if not t then return nil end
	local aim
	for _ = 1, 6 do
		local Tl = vel and (T + vel * t) or T
		aim = (Tl - o) + Vector3.new(0, tr.Gravity * 0.5 * t * t, 0)
		t = GAME.Traj.GetTimeForDistance(tr, aim.Magnitude)
		if not t then return nil end
	end
	return aim.Unit, t
end

local function leadOf(root, on) if not on then return nil end local v = root.AssemblyLinearVelocity if v.Magnitude > 80 or v.Magnitude < 0.5 then return nil end return v end
local function centre() local vp = camera.ViewportSize return Vector2.new(vp.X / 2, vp.Y / 2) end
local function focalPx() local vp = camera.ViewportSize return (vp.Y / 2) / math.tan(math.rad(camera.FieldOfView) / 2) end
local function degToPx(deg) if deg >= 89 then return 4000 end return focalPx() * math.tan(math.rad(deg)) end
local function angleTo(pos) local cf = camera.CFrame local d = (pos - cf.Position) if d.Magnitude < 1e-3 then return 0 end return math.deg(math.acos(math.clamp(cf.LookVector:Dot(d.Unit), -1, 1))) end

-- 🚀 NO RECOIL LOGIC 🚀
task.spawn(function()
	local Client = ReplicatedStorage:WaitForChild("Client", 5)
	if Client then
		local RC = Client:FindFirstChild("Tools")
		RC = RC and RC:FindFirstChild("Weapon")
		RC = RC and RC:FindFirstChild("controllers")
		RC = RC and RC:FindFirstChild("RecoilController")
		if RC then
			local success, mod = pcall(require, RC)
			if success and mod then
				local oldUpdate = mod.update
				mod.update = function(self, dt)
					if CONFIG.noRecoil then return end
					if oldUpdate then return oldUpdate(self, dt) end
				end
			end
		end
	end
end)

-- Drawing
local pool = {}
if _G.__CWAR_POOL then for _, obj in ipairs(_G.__CWAR_POOL) do pcall(function() obj:Remove() end) end end
_G.__CWAR_POOL = pool
local function make(kind, props)
	if not HAS_DRAWING then return nil end
	local ok, obj = pcall(function() return Drawing.new(kind) end)
	if not ok or not obj then return nil end
	obj.Visible = false
	for k, v in pairs(props or {}) do pcall(function() obj[k] = v end) end
	table.insert(pool, obj) return obj
end

local drawn, vdrawn = {}, {}
local function objectsFor(p)
	local set = drawn[p] if set then return set end
	set = { outline = make("Square", { Thickness = 3, Filled = false, ZIndex = 1, Color = Color3.new(0, 0, 0), Transparency = 0.6 }), box = make("Square", { Thickness = 1, Filled = false, ZIndex = 2 }), hpBg = make("Square", { Filled = true, ZIndex = 1, Color = Color3.new(0, 0, 0), Transparency = 0.6 }), hp = make("Square", { Filled = true, ZIndex = 2 }), name = make("Text", { Size = 13, Center = true, Outline = true, ZIndex = 3 }), role = make("Text", { Size = 12, Center = true, Outline = true, ZIndex = 3 }), info = make("Text", { Size = 12, Center = true, Outline = true, ZIndex = 3 }), flags = make("Text", { Size = 12, Center = false, Outline = true, ZIndex = 3 }), tracer = make("Line", { Thickness = 1, ZIndex = 1 }), head = make("Circle", { Thickness = 1, Filled = false, NumSides = 14, ZIndex = 3 }) }
	drawn[p] = set return set
end
local function hideSet(set)
	for k, obj in pairs(set) do if obj and obj.Visible ~= nil then obj.Visible = false end end
end
local function hideAll() for _, set in pairs(drawn) do hideSet(set) end for _, t in pairs(vdrawn) do if t.box then t.box.Visible = false end end end
local fovCircle = make("Circle", { Thickness = 1, NumSides = 48, Filled = false, Transparency = 0.5, ZIndex = 1 })

local function screenBox(char)
	local head = char:FindFirstChild("Head") local ll, rl = char:FindFirstChild("Left Leg"), char:FindFirstChild("Right Leg")
	if not head or not (ll or rl) then return nil end
	local low = ll or rl if ll and rl then low = (ll.Position.Y <= rl.Position.Y) and ll or rl end
	local top = head.Position + Vector3.new(0, head.Size.Y / 2 + 0.3, 0) local bot = low.Position - Vector3.new(0, low.Size.Y / 2, 0)
	local sTop = camera:WorldToViewportPoint(top) local sBot = camera:WorldToViewportPoint(bot)
	if sTop.Z <= 0 or sBot.Z <= 0 then return nil end
	local h = math.abs(sBot.Y - sTop.Y) if h < 1 then return nil end
	local w = math.max(h * 0.5, math.abs(sBot.X - sTop.X)) local cx = (sTop.X + sBot.X) / 2
	return cx - w / 2, math.min(sTop.Y, sBot.Y), w, h
end

local visCache = setmetatable({}, { __mode = "k" })
local function visibleCached(p, char, part)
	local now = os.clock() local c = visCache[p]
	if c and now - c.at < 0.12 then return c.v end
	local v = seen(char, part) visCache[p] = { at = now + math.random() * 0.04, v = v }
	return v
end

-- 🚀 VEHICLE ESP (Box & Crew) 🚀
local function draw3DBox(model, color, alpha)
	if not model.PrimaryPart then return end
	local cf, size = model:GetBoundingBox()
	local corners = {
		cf * CFrame.new(-size.X/2, -size.Y/2, -size.Z/2),
		cf * CFrame.new( size.X/2, -size.Y/2, -size.Z/2),
		cf * CFrame.new(-size.X/2,  size.Y/2, -size.Z/2),
		cf * CFrame.new( size.X/2,  size.Y/2, -size.Z/2),
		cf * CFrame.new(-size.X/2, -size.Y/2,  size.Z/2),
		cf * CFrame.new( size.X/2, -size.Y/2,  size.Z/2),
		cf * CFrame.new(-size.X/2,  size.Y/2,  size.Z/2),
		cf * CFrame.new( size.X/2,  size.Y/2,  size.Z/2)
	}
	local minX, maxX = math.huge, -math.huge
	local minY, maxY = math.huge, -math.huge
	local valid = false
	for _, c in ipairs(corners) do
		local sp = camera:WorldToViewportPoint(c.Position)
		if sp.Z > 0 then
			valid = true
			minX = math.min(minX, sp.X) maxX = math.max(maxX, sp.X)
			minY = math.min(minY, sp.Y) maxY = math.max(maxY, sp.Y)
		end
	end
	if not valid then return nil end
	return minX, minY, maxX - minX, maxY - minY
end

local function renderVehicles()
	local V = workspace:FindFirstChild("Vehicles")
	local used = {}
	if CONFIG.espVehicles and V then
		local mine = teamName(plr) local camPos = camera.CFrame.Position local maxStuds = CONFIG.espMaxM * STUDS_PER_M
		for _, m in ipairs(V:GetChildren()) do
			if m:IsA("Model") and m:GetAttribute("Wrecked") ~= true then
				local crew = m:GetAttribute("CrewTeam") local side = crew or m:GetAttribute("Team")
				local hostile = side ~= nil and COMBAT[side] and side ~= mine local manned = crew ~= nil
				
				if (manned or CONFIG.espEmptyVeh) and (hostile or CONFIG.espTeam) then
					local root = m:FindFirstChild("RootPart") or m.PrimaryPart
					if root and root:IsA("BasePart") then
						local d = (root.Position - camPos).Magnitude
						if d <= maxStuds then
							local sp = camera:WorldToViewportPoint(root.Position + Vector3.new(0, 4, 0))
							if sp.Z > 0 then
								local t = vdrawn[m]
								if not t then
									t = { box = make("Square", { Thickness = 1, Filled = false, ZIndex = 2 }), text = make("Text", { Size = 13, Center = true, Outline = true, ZIndex = 3 }), crew = {} }
									vdrawn[m] = t
								end
								if t then
									local col = hostile and COL.veh or COL.vehTeam
									if CONFIG.espVehBox then
										local bx, by, bw, bh = draw3DBox(m, col, 1)
										if bx then
											t.box.Position = Vector2.new(bx, by)
											t.box.Size = Vector2.new(bw, bh)
											t.box.Color = col
											t.box.Visible = true
										else
											t.box.Visible = false
										end
									else
										t.box.Visible = false
									end
									
									if CONFIG.espVehCrew and GAME.Armor then
										local hitbox = GAME.Armor.find(m)
										if hitbox and hitbox.Seats then
											for i, seatData in ipairs(hitbox.Seats) do
												local seatPart = seatData.Part
												if seatPart then
													local ssp = camera:WorldToViewportPoint(seatPart.Position)
													if ssp.Z > 0 then
														local dot = t.crew[i]
														if not dot then
															dot = make("Circle", { Thickness = 2, Filled = false, NumSides = 12, ZIndex = 4 })
															t.crew[i] = dot
														end
														dot.Position = Vector2.new(ssp.X, ssp.Y)
														dot.Radius = 10
														dot.Color = COL.vehCrew
														dot.Visible = true
													end
												end
											end
										end
									end
									
									t.text.Text = string.format("%s  %s  %dm%s", tostring(m:GetAttribute("VehicleName") or m.Name), tostring(m:GetAttribute("VehicleType") or ""), math.floor(d / STUDS_PER_M), manned and "" or "  (empty)")
									t.text.Position = Vector2.new(sp.X, sp.Y)
									t.text.Color = col
									t.text.Size = math.max(12, CONFIG.espTextSize)
									t.text.Visible = true
									used[m] = true
								end
							end
						end
					end
				end
			end
		end
	end
	for m, t in pairs(vdrawn) do
		if not used[m] then
			if t then 
				if t.box then t.box.Visible = false end 
				if t.text then t.text.Visible = false end 
				if t.crew then for _, dot in pairs(t.crew) do dot.Visible = false end end
			end
			if not m.Parent then pcall(function() t.box:Remove() t.text:Remove() end) vdrawn[m] = nil end
		end
	end
end

local function renderPass()
	if _G.__CWAR ~= GEN then return end
	refreshVisParams() local mid = centre()
	if fovCircle then fovCircle.Visible = CONFIG.aim and CONFIG.aimCircle if fovCircle.Visible then fovCircle.Position = mid fovCircle.Radius = CONFIG.aimFov fovCircle.Color = COL.fov end end
	if not CONFIG.esp or not HAS_DRAWING then hideAll() STATE.drawn = 0 return end
	local camPos = camera.CFrame.Position local maxStuds = CONFIG.espMaxM * STUDS_PER_M local count, enemies = 0, 0 local txt = math.max(12, math.floor(CONFIG.espTextSize))
	
	for _, p in ipairs(Players:GetPlayers()) do
		local set = objectsFor(p) local shown = false local enemy = isEnemy(p)
		if enemy then enemies = enemies + 1 end
		if set.box and (enemy or (CONFIG.espTeam and isMate(p))) then
			local char, root, hp, maxHp = liveChar(p)
			if char then
				local dist = (camPos - root.Position).Magnitude
				if dist <= maxStuds then
					local head = char:FindFirstChild("Head") or root local vis = enemy and visibleCached(p, char, head) or false
					if vis or not CONFIG.espVisOnly or not enemy then
						local x, y, w, h = screenBox(char)
						if x then
							count = count + 1 shown = true local col = (not enemy) and COL.team or (vis and COL.visible or COL.enemy)
							local alpha = (vis or not enemy or not CONFIG.espDimHidden) and 1 or 0.55
							
							if CONFIG.espBox then set.outline.Position = Vector2.new(x, y) set.outline.Size = Vector2.new(w, h) set.outline.Transparency = 0.6 * alpha set.outline.Visible = true set.box.Position = Vector2.new(x, y) set.box.Size = Vector2.new(w, h) set.box.Color = col set.box.Transparency = alpha set.box.Visible = true else set.outline.Visible = false set.box.Visible = false end
							
							if CONFIG.espHealth and maxHp > 0 then local frac = math.clamp(hp / maxHp, 0, 1) set.hpBg.Position = Vector2.new(x - 6, y) set.hpBg.Size = Vector2.new(3, h) set.hpBg.Visible = true set.hp.Position = Vector2.new(x - 6, y + h * (1 - frac)) set.hp.Size = Vector2.new(3, h * frac) set.hp.Color = Color3.fromRGB(255, 70, 70):Lerp(Color3.fromRGB(90, 235, 110), frac) set.hp.Visible = true else set.hpBg.Visible = false set.hp.Visible = false end
							
							local nameY = y - txt - 2
							if CONFIG.espName then set.name.Text = (p.DisplayName ~= "" and p.DisplayName) or p.Name set.name.Size = txt set.name.Position = Vector2.new(x + w / 2, nameY) set.name.Color = COL.text set.name.Transparency = alpha set.name.Visible = true else set.name.Visible = false end
							
							local role = CONFIG.espClass and roleOf(p) or nil
							if role then set.role.Text = role set.role.Size = math.max(12, txt - 1) set.role.Position = Vector2.new(x + w / 2, nameY - txt) set.role.Color = col set.role.Transparency = alpha set.role.Visible = true else set.role.Visible = false end
							
							if CONFIG.espInfo or CONFIG.espLimbs then
								local parts = {}
								if CONFIG.espInfo then table.insert(parts, math.floor(dist / STUDS_PER_M) .. "m") local wpn = weaponOf(char) if wpn then table.insert(parts, wpn) end end
								if CONFIG.espLimbs then local hh = limbHealth(char, "Head") local th = limbHealth(char, "Torso") table.insert(parts, "H" .. math.floor(hh or 0) .. " T" .. math.floor(th or 0)) end
								set.info.Text = table.concat(parts, "  ") set.info.Size = math.max(12, txt - 1) set.info.Position = Vector2.new(x + w / 2, y + h + 1) set.info.Color = COL.text set.info.Transparency = alpha set.info.Visible = true
							else set.info.Visible = false end
							
							if CONFIG.espFlags then
								local f = {}
								if isDowned(char) then table.insert(f, "DOWNED") end if hasSpawnShield(char) then table.insert(f, "SPAWN") end if isDisguised(char) then table.insert(f, "DISGUISED") end if char:GetAttribute("InVehicle") ~= nil then table.insert(f, "VEHICLE") end
								if #f > 0 then set.flags.Text = table.concat(f, "\n") set.flags.Size = 12 set.flags.Position = Vector2.new(x + w + 4, y) set.flags.Color = COL.visible set.flags.Transparency = alpha set.flags.Visible = true else set.flags.Visible = false end
							else set.flags.Visible = false end
							
							if CONFIG.espTracer then set.tracer.From = Vector2.new(mid.X, camera.ViewportSize.Y) set.tracer.To = Vector2.new(x + w / 2, y + h) set.tracer.Color = col set.tracer.Transparency = alpha set.tracer.Visible = true else set.tracer.Visible = false end
							
							if CONFIG.espHeadDot then local sp = camera:WorldToViewportPoint(head.Position) if sp.Z > 0 then set.head.Position = Vector2.new(sp.X, sp.Y) set.head.Radius = math.max(2, h * 0.07) set.head.Color = col set.head.Transparency = alpha set.head.Visible = true else set.head.Visible = false end else set.head.Visible = false end
						end
					end
				end
			end
		end
		if not shown then hideSet(set) end
	end
	STATE.drawn = count STATE.enemies = enemies
	renderVehicles()
end

Players.PlayerRemoving:Connect(function(p) local set = drawn[p] if set then hideSet(set) drawn[p] = nil end end)

-- Aim Logic
local function keyFromName(name) if type(name) ~= "string" then return nil end if name:sub(1, 11) == "MouseButton" then return Enum.UserInputType[name] end return Enum.KeyCode[name] end
local function hotkeyHeld(name) local k = keyFromName(name) if not k then return false end local ok, held = pcall(function() if k.EnumType == Enum.UserInputType then return UserInputService:IsMouseButtonPressed(k) end return UserInputService:IsKeyDown(k) end) return ok and held or false end
local Spectate -- Forward declaration for Zone Separation

local function aimActive()
	if Spectate and Spectate.IsActive and Spectate.IsActive() then return false end
	if not CONFIG.aim then return false end
	if CONFIG.aimActive == "Always" then return true end
	if CONFIG.aimActive == "While firing" then return UserInputService:IsMouseButtonPressed(Enum.UserInputType.MouseButton1) end
	return hotkeyHeld(CONFIG.aimKey)
end
local function approach(smooth, dt) local base = 1 / math.max(1, smooth) return 1 - (1 - base) ^ math.max(dt * 60, 0.0001) end
local function angleDelta(a, b) local d = (b - a) % (math.pi * 2) if d > math.pi then d = d - math.pi * 2 end return d end
local function aimPointFor(part, root)
	local camPos = camera.CFrame.Position if not CONFIG.aimPredict then return part.Position end
	local fp = cachedFireParams() if not fp or not fp.Weapon or (fp.Weapon.MuzzleSpeed or 0) <= 0 then return part.Position end
	local vel = leadOf(root, true) local dir = solveArc(camPos, part.Position, fp.Weapon, vel)
	if not dir then return part.Position end
	return camPos + dir * (part.Position - camPos).Magnitude
end
local function aimPartOf(char) if CONFIG.aimPart == "Torso" then return char:FindFirstChild("Torso") or char:FindFirstChild("Head") end if CONFIG.aimPart == "Nearest" then local h, t = char:FindFirstChild("Head"), char:FindFirstChild("Torso") if h and t then return (angleTo(h.Position) <= angleTo(t.Position)) and h or t end end return char:FindFirstChild("Head") or char:FindFirstChild("Torso") end
local function pickAimTarget(sticky)
	local mid = centre() local maxStuds = CONFIG.aimMaxM * STUDS_PER_M local camPos = camera.CFrame.Position local best, bestPx
	for _, p in ipairs(Players:GetPlayers()) do
		local char, root = shootable(p)
		if char then
			local part = aimPartOf(char)
			if part and (part.Position - camPos).Magnitude <= maxStuds then
				local sp = camera:WorldToViewportPoint(part.Position)
				if sp.Z > 0 then
					local px = (Vector2.new(sp.X, sp.Y) - mid).Magnitude local limit = (sticky == p) and CONFIG.aimFov * 1.35 or CONFIG.aimFov
					if px <= limit and ((not CONFIG.aimVisible) or seen(char, part)) then if not bestPx or px < bestPx or sticky == p then best, bestPx = { player = p, part = part, root = root, px = px }, px if sticky == p then return best end end end
				end
			end
		end
	end
	return best
end

local stickyTarget, lockedAt, reactUntil = nil, 0, 0
local lastTriggerTime = 0

local function aimPass(dt)
	if _G.__CWAR ~= GEN then return end
	
	if aimActive() then
		local nowMs = os.clock() * 1000 local pick = pickAimTarget(CONFIG.aimSticky and stickyTarget or nil)
		if pick then
			if pick.player ~= stickyTarget then
				local lo = math.min(CONFIG.humReactMin, CONFIG.humReactMax) local hi = math.max(CONFIG.humReactMin, CONFIG.humReactMax)
				reactUntil = (CONFIG.hum and hi > 0) and (nowMs + math.random(lo, hi)) or 0 lockedAt = nowMs
			end
			stickyTarget = pick.player STATE.target = pick.player.Name
			if reactUntil <= nowMs then
				local smoothH, smoothV = CONFIG.aimSmoothH, CONFIG.aimSmoothV
				if CONFIG.hum and CONFIG.humRampMs > 0 then local age = nowMs - lockedAt if age < CONFIG.humRampMs then local slow = 3 - 2 * (age / CONFIG.humRampMs) smoothH, smoothV = smoothH * slow, smoothV * slow end end
				local cf = camera.CFrame local pitchNow, yawNow = cf:ToOrientation()
				local want = CFrame.lookAt(cf.Position, aimPointFor(pick.part, pick.root)) local wantPitch, wantYaw = want:ToOrientation()
				local dYaw, dPitch = angleDelta(yawNow, wantYaw), angleDelta(pitchNow, wantPitch)
				local moveYaw, movePitch = dYaw * approach(smoothH, dt), dPitch * approach(smoothV, dt)
				if CONFIG.hum and CONFIG.humMaxDegS > 0 then
					local cap = math.rad(CONFIG.humMaxDegS) * dt local mag = math.sqrt(moveYaw * moveYaw + movePitch * movePitch)
					if mag > cap and mag > 0 then local k = cap / mag moveYaw, movePitch = moveYaw * k, movePitch * k end
				end
				if CONFIG.aimDeliver == "Mouse" and moveMouse then
					local dx, dy = -moveYaw / 0.007, -movePitch / 0.007
					if math.abs(dx) >= 1 or math.abs(dy) >= 1 then pcall(function() moveMouse(math.floor(dx + 0.5), math.floor(dy + 0.5)) end) end
				else
					camera.CFrame = CFrame.new(cf.Position) * CFrame.fromOrientation(pitchNow + movePitch, yawNow + moveYaw, 0)
				end
			end
		else
			STATE.target, stickyTarget = "-", nil
		end
	else
		STATE.target, stickyTarget = "-", nil
	end

	if CONFIG.triggerBot and not (Spectate and Spectate.IsActive and Spectate.IsActive()) then
		local targetChar = stickyTarget and stickyTarget.Character
		if targetChar then
			local triggerPart = targetChar:FindFirstChild(CONFIG.triggerPart == "Head" and "Head" or "Torso") or targetChar:FindFirstChild("Head")
			if triggerPart then
				local mid = centre()
				local sp = camera:WorldToViewportPoint(triggerPart.Position)
				if sp.Z > 0 and (Vector2.new(sp.X, sp.Y) - mid).Magnitude <= CONFIG.triggerRadius then
					if not CONFIG.triggerVis or seen(targetChar, triggerPart) then
						local nowMs = os.clock() * 1000
						if nowMs - lastTriggerTime >= CONFIG.triggerDelay then
							if CONFIG.triggerMode == "Click" then
								pcall(mouse1click)
							else
								pcall(function() mouse1press() task.wait(CONFIG.triggerDelay/1000) mouse1release() end)
							end
							lastTriggerTime = nowMs
						end
					end
				end
			end
		end
	end
end

-- World
local WORLD = { atm = {}, light = {}, fx = {} }
local function worldPass()
	if _G.__CWAR ~= GEN then return end
	local atm = Lighting:FindFirstChildOfClass("Atmosphere")
	if atm then
		if CONFIG.noFog then if atm.Density ~= 0 then WORLD.atm.Density = atm.Density end if atm.Haze ~= 0 then WORLD.atm.Haze = atm.Haze end atm.Density, atm.Haze = 0, 0 WORLD.atmOn = true
		elseif WORLD.atmOn then if WORLD.atm.Density then atm.Density = WORLD.atm.Density end if WORLD.atm.Haze then atm.Haze = WORLD.atm.Haze end WORLD.atmOn = false end
	end
	local FB = { Ambient = Color3.fromRGB(178, 178, 178), OutdoorAmbient = Color3.fromRGB(178, 178, 178), GlobalShadows = false }
	if CONFIG.fullbright then for k, v in pairs(FB) do if Lighting[k] ~= v then WORLD.light[k] = Lighting[k] Lighting[k] = v end end WORLD.lightOn = true
	elseif WORLD.lightOn then for k, v in pairs(WORLD.light) do Lighting[k] = v end WORLD.light = {} WORLD.lightOn = false end
	if CONFIG.noSuppress then for _, n in ipairs({ "SuppressionDepthOfField", "Blur" }) do local e = Lighting:FindFirstChild(n) if e and e.Enabled then WORLD.fx[e] = true e.Enabled = false end end WORLD.fxOn = true
	elseif WORLD.fxOn then for e in pairs(WORLD.fx) do if e.Parent then e.Enabled = true end end WORLD.fx = {} WORLD.fxOn = false end
end

--------------------------------------------------------------------------------
-- ZONE 2: SPECTATE SYSTEM (HARDENED, ISOLATED & QOL-ENHANCED FOR COLD WAR)
--------------------------------------------------------------------------------
Spectate = {}

Spectate.Config = {
	Sensitivity        = 0.0025,
	Smoothness         = 14,
	RotationSmoothness = 12,
	DefaultDistance    = 14,
	MinDistance        = 3,
	MaxDistance        = 65,
	OrbitSpeed         = 0.45,
	FilterMode         = "Enemies Only", -- "Enemies Only", "Teammates Only", "All Players"
	AliveOnly          = true,
	AutoSwitchOnDeath  = true,
	WallCollision      = true,
	ShowHUD            = true,
	QuickSpecKey       = "V", -- Press V while looking near a player to spectate them
}

local specActive        = false
local currentTarget     = nil
local specMode          = 1 -- 1: Follow, 2: Orbit, 3: First Person
local currentDist       = Spectate.Config.DefaultDistance

local lookHeld          = false
local yaw               = 0
local pitch             = math.rad(-10)
local targetYaw         = 0
local targetPitch       = math.rad(-10)

local specFocus         = nil
local specFPCF          = nil
local savedCameraType   = nil

local specInputBegan    = nil
local specInputEnded    = nil
local specInputChanged  = nil
local specCamrayParams  = RaycastParams.new()
specCamrayParams.FilterType = Enum.RaycastFilterType.Exclude
specCamrayParams.IgnoreWater = true

-- Spectate HUD Drawing Banner (Top-Center of Screen)
local specHudTitle = make("Text", { Size = 16, Center = true, Outline = true, ZIndex = 4, Color = Color3.fromRGB(90, 225, 255) })
local specHudSub   = make("Text", { Size = 13, Center = true, Outline = true, ZIndex = 4, Color = Color3.fromRGB(235, 235, 235) })

local function hideSpecHud()
	if specHudTitle then specHudTitle.Visible = false end
	if specHudSub then specHudSub.Visible = false end
end

local function angleDiffSpec(from, to)
	return math.atan2(math.sin(to - from), math.cos(to - from))
end

local function smoothAngleSpec(current, target, alpha)
	return current + angleDiffSpec(current, target) * alpha
end

-- Get filtered & sorted list of valid Spectate candidates in Cold War
function Spectate.GetCandidateList()
	local list = {}
	local mode = Spectate.Config.FilterMode
	for _, p in ipairs(Players:GetPlayers()) do
		if p ~= plr then
			local passTeam = true
			if mode == "Enemies Only" then
				passTeam = isEnemy(p)
			elseif mode == "Teammates Only" then
				passTeam = isMate(p)
			end

			if passTeam then
				if Spectate.Config.AliveOnly then
					local ch = liveChar(p)
					if ch then table.insert(list, p) end
				else
					table.insert(list, p)
				end
			end
		end
	end
	table.sort(list, function(a, b)
		return a.Name:lower() < b.Name:lower()
	end)
	return list
end

function Spectate.GetDropdownNames()
	local list = Spectate.GetCandidateList()
	local names = {}
	for _, p in ipairs(list) do
		local r = roleOf(p)
		local tag = isEnemy(p) and "[ENEMY]" or (isMate(p) and "[TEAM]" or "[NEUTRAL]")
		table.insert(names, string.format("%s %s%s", p.Name, tag, r and (" (" .. r .. ")") or ""))
	end
	if #names == 0 then
		table.insert(names, "- No Players Found -")
	end
	return names
end

local function unbindSpecInputs()
	if specInputBegan then specInputBegan:Disconnect(); specInputBegan = nil end
	if specInputEnded then specInputEnded:Disconnect(); specInputEnded = nil end
	if specInputChanged then specInputChanged:Disconnect(); specInputChanged = nil end
	if lookHeld then
		lookHeld = false
		pcall(function() UserInputService.MouseBehavior = Enum.MouseBehavior.Default end)
	end
end

local function bindSpecInputs()
	if specInputBegan then return end

	specInputBegan = UserInputService.InputBegan:Connect(function(input, gameProcessed)
		if not specActive then return end
		if not gameProcessed and input.UserInputType == Enum.UserInputType.MouseButton2 then
			lookHeld = true
			pcall(function() UserInputService.MouseBehavior = Enum.MouseBehavior.LockCurrentPosition end)
		end
	end)

	specInputEnded = UserInputService.InputEnded:Connect(function(input)
		if input.UserInputType == Enum.UserInputType.MouseButton2 and lookHeld then
			lookHeld = false
			if specActive then
				pcall(function() UserInputService.MouseBehavior = Enum.MouseBehavior.Default end)
			end
		end
	end)

	specInputChanged = UserInputService.InputChanged:Connect(function(input, gameProcessed)
		if not specActive then return end

		if lookHeld and input.UserInputType == Enum.UserInputType.MouseMovement then
			local delta = UserInputService:GetMouseDelta()
			targetYaw = targetYaw - (delta.X * Spectate.Config.Sensitivity)
			targetPitch = math.clamp(
				targetPitch - (delta.Y * Spectate.Config.Sensitivity),
				math.rad(-85),
				math.rad(85)
			)
		end

		if not gameProcessed and input.UserInputType == Enum.UserInputType.MouseWheel then
			local dir = input.Position.Z
			currentDist = math.clamp(
				currentDist - (dir * 2.5),
				Spectate.Config.MinDistance,
				Spectate.Config.MaxDistance
			)
		end
	end)
end

local function onSpecRender(dt)
	if _G.__CWAR ~= GEN or not specActive or not currentTarget then
		hideSpecHud()
		return
	end

	camera = workspace.CurrentCamera
	if not camera then return end

	-- Verify target is still in server
	if not currentTarget.Parent or currentTarget.Parent ~= Players then
		if Spectate.Config.AutoSwitchOnDeath then
			Spectate.Cycle(1)
			if not currentTarget or not currentTarget.Parent then
				Spectate.Stop()
			end
		else
			Spectate.Stop()
		end
		return
	end

	-- Verify target is alive (using Cold War's limb health + ragdoll check)
	local char, root, hp, maxHp = liveChar(currentTarget)
	if not char or not root then
		-- Also check if they are inside a Vehicle in Cold War!
		local rawChar = currentTarget.Character
		local rawRoot = rawChar and (rawChar:FindFirstChild("HumanoidRootPart") or rawChar:FindFirstChild("Head"))
		if rawChar and rawRoot and rawChar:GetAttribute("InVehicle") ~= nil then
			char, root, hp, maxHp = rawChar, rawRoot, 100, 100
		elseif Spectate.Config.AutoSwitchOnDeath then
			local candidates = Spectate.GetCandidateList()
			if #candidates > 0 and (candidates[1] ~= currentTarget or #candidates > 1) then
				Spectate.Cycle(1)
				return
			else
				Spectate.Stop()
				return
			end
		else
			Spectate.Stop()
			return
		end
	end

	local head = char:FindFirstChild("Head")

	if specMode == 2 and not lookHeld then
		targetYaw = targetYaw + (Spectate.Config.OrbitSpeed * dt)
	end

	local rotAlpha = 1 - math.exp(-Spectate.Config.RotationSmoothness * dt)
	yaw   = smoothAngleSpec(yaw, targetYaw, rotAlpha)
	pitch = pitch + (targetPitch - pitch) * rotAlpha

	local rotation       = CFrame.Angles(0, yaw, 0) * CFrame.Angles(pitch, 0, 0)
	local targetFocusPos = root.Position + Vector3.new(0, 1.6, 0)

	if specFocus then
		specFocus = specFocus:Lerp(targetFocusPos, 1 - math.exp(-Spectate.Config.Smoothness * dt))
	else
		specFocus = targetFocusPos
	end

	-- Ensure CameraSubject points to target's Humanoid/Head so Roblox streams distant chunks around them!
	local targetHum = char:FindFirstChildOfClass("Humanoid")
	if targetHum and camera.CameraSubject ~= targetHum then
		pcall(function() camera.CameraSubject = targetHum end)
	end

	camera.CameraType = Enum.CameraType.Scriptable

	if specMode == 3 and (head or root) then
		local basePart = head or root
		local firstPersonCF = basePart.CFrame * CFrame.new(0, 0.15, -0.65)
		if specFPCF then
			specFPCF = specFPCF:Lerp(firstPersonCF, 1 - math.exp(-22 * dt))
		else
			specFPCF = firstPersonCF
		end
		camera.CFrame = specFPCF
		camera.Focus  = specFPCF
	else
		local desiredOffset = -(rotation.LookVector * currentDist)
		local camPos = specFocus + desiredOffset

		-- QoL: Camera Wall-Collision Prevention so camera doesn't clip inside hills/walls
		if Spectate.Config.WallCollision then
			local ignoreList = { char, plr.Character }
			local ignFolder = workspace:FindFirstChild("Ignore")
			if ignFolder then table.insert(ignoreList, ignFolder) end
			specCamrayParams.FilterDescendantsInstances = ignoreList

			local hit = workspace:Raycast(specFocus, desiredOffset, specCamrayParams)
			if hit and hit.Position then
				local safeDist = math.max(1.5, (hit.Position - specFocus).Magnitude - 0.8)
				camPos = specFocus - (rotation.LookVector * safeDist)
			end
		end

		local camCF = CFrame.new(camPos) * rotation
		camera.CFrame = camCF
		camera.Focus  = CFrame.new(specFocus)
	end

	-- QoL: Render Top-Center Spectate Telemetry HUD
	if Spectate.Config.ShowHUD and specHudTitle and specHudSub then
		local vp = camera.ViewportSize
		local myRoot = plr.Character and plr.Character:FindFirstChild("HumanoidRootPart")
		local distM = myRoot and math.floor((root.Position - myRoot.Position).Magnitude / STUDS_PER_M) or 0
		local roleStr = roleOf(currentTarget) or "Soldier"
		local wpnStr  = weaponOf(char) or "Unarmed"
		local hpPct   = (maxHp and maxHp > 0) and math.floor(math.clamp(hp / maxHp, 0, 1) * 100) or 100
		local sideTag = isEnemy(currentTarget) and "ENEMY" or (isMate(currentTarget) and "TEAM" or "NEUTRAL")
		local modeNames = { [1] = "Follow", [2] = "Orbit", [3] = "First-Person" }

		specHudTitle.Text = string.format("🎥 SPECTATING: %s [%s - %s]", currentTarget.DisplayName or currentTarget.Name, sideTag, roleStr)
		specHudTitle.Position = Vector2.new(vp.X / 2, 42)
		specHudTitle.Color = isEnemy(currentTarget) and COL.enemy or COL.team
		specHudTitle.Visible = true

		specHudSub.Text = string.format("HP: %d%%   |   Weapon: %s   |   Dist: %dm   |   Cam: %s   |   [ [ / ] : Next/Prev · Backspace : Exit ]", hpPct, wpnStr, distM, modeNames[specMode] or "Follow")
		specHudSub.Position = Vector2.new(vp.X / 2, 62)
		specHudSub.Visible = true
	else
		hideSpecHud()
	end
end

function Spectate.Start(targetPlayer)
	if not targetPlayer or targetPlayer == plr then return false end
	camera = workspace.CurrentCamera
	if not camera then return false end

	if not specActive then
		savedCameraType = camera.CameraType
		bindSpecInputs()
		pcall(function() RunService:UnbindFromRenderStep("CWSpec") end)
		RunService:BindToRenderStep("CWSpec", Enum.RenderPriority.Camera.Value + 3, function(dt)
			pcall(onSpecRender, dt)
		end)
	end

	specActive    = true
	currentTarget = targetPlayer
	specFocus     = nil
	specFPCF      = nil

	local character = targetPlayer.Character
	local root = character and character:FindFirstChild("HumanoidRootPart")
	if root then
		local look = root.CFrame.LookVector
		yaw         = math.atan2(-look.X, -look.Z)
		targetYaw   = yaw
		pitch       = math.rad(-10)
		targetPitch = pitch
		specFocus   = root.Position + Vector3.new(0, 1.6, 0)
	end
	return true
end

function Spectate.Stop()
	if not specActive then
		hideSpecHud()
		return
	end

	specActive    = false
	currentTarget = nil
	specFocus     = nil
	specFPCF      = nil
	hideSpecHud()

	pcall(function() RunService:UnbindFromRenderStep("CWSpec") end)
	unbindSpecInputs()

	camera = workspace.CurrentCamera
	if camera then
		-- Always restore current LocalPlayer's live Humanoid (even if LocalPlayer respawned while spectating!)
		local myChar = plr.Character
		local myHum  = myChar and myChar:FindFirstChildOfClass("Humanoid")
		camera.CameraType = Enum.CameraType.Custom
		if myHum then
			camera.CameraSubject = myHum
		end
	end
end

function Spectate.Toggle(targetPlayer)
	if specActive then
		Spectate.Stop()
	else
		if targetPlayer and targetPlayer ~= plr then
			Spectate.Start(targetPlayer)
		else
			Spectate.Cycle(1)
		end
	end
end

function Spectate.Cycle(direction)
	local players = Spectate.GetCandidateList()
	if #players == 0 then
		Spectate.Stop()
		return nil
	end

	local currentIndex = 0
	for i, p in ipairs(players) do
		if p == currentTarget then
			currentIndex = i
			break
		end
	end

	local nextIndex = 1
	if currentIndex == 0 then
		nextIndex = (direction >= 0) and 1 or #players
	else
		nextIndex = ((currentIndex - 1 + direction) % #players) + 1
	end

	local chosen = players[nextIndex]
	if chosen then
		Spectate.Start(chosen)
	end
	return chosen
end

-- QoL: Spectate the player closest to the center of your crosshair!
function Spectate.SpectateCrosshairTarget()
	local mid = centre()
	local bestP, bestDist = nil, math.huge
	local list = Spectate.GetCandidateList()
	for _, p in ipairs(list) do
		local ch, root = liveChar(p)
		if ch and root then
			local sp = camera:WorldToViewportPoint(root.Position)
			if sp.Z > 0 then
				local px = (Vector2.new(sp.X, sp.Y) - mid).Magnitude
				if px < bestDist then
					bestDist = px
					bestP = p
				end
			end
		end
	end
	if bestP then
		Spectate.Start(bestP)
		return bestP
	end
	return nil
end

function Spectate.SetMode(mode)
	if mode == 1 or mode == 2 or mode == 3 then
		specMode = mode
		specFPCF = nil
	end
end

function Spectate.SetDistance(distance)
	currentDist = math.clamp(distance, Spectate.Config.MinDistance, Spectate.Config.MaxDistance)
end

function Spectate.GetTarget()
	return currentTarget
end

function Spectate.IsActive()
	return specActive
end

_G.ColdWarSpectate = Spectate

--------------------------------------------------------------------------------
-- ZONE 3: SILL X UI INTEGRATION (ESP · AIMBOT · TRIGGERBOT · SPECTATE · WORLD)
--------------------------------------------------------------------------------

local UI_URL = "https://raw.githubusercontent.com/sillbuilt/Sill-UI/refs/heads/main/SilL-X-UI.lua?t=" .. tostring(os.time()) .. math.random(1, 1000)
local success, SilL = pcall(function() return loadstring(game:HttpGet(UI_URL))() end)

local win
if success and SilL then
	win = SilL:CreateWindow({
		Name = "Sill X | Cold War Suite",
		Subtitle = "ESP · Aimbot · Spectate System",
		ToggleKey = Enum.KeyCode.Home,
		Watermark = true,
		SettingsTab = true,
		Size = UDim2.fromOffset(620, 480)
	})

	-- ✅ TAB 1: ESP
	local espTab = win:CreateTab("ESP")
	local espSec = espTab:CreateSection("Visuals")
	espSec:CreateToggle({ Name = "ESP Master", CurrentValue = CONFIG.esp, Callback = function(v) CONFIG.esp = v end })
	espSec:CreateToggle({ Name = "Box", CurrentValue = CONFIG.espBox, Callback = function(v) CONFIG.espBox = v end })
	espSec:CreateToggle({ Name = "Name", CurrentValue = CONFIG.espName, Callback = function(v) CONFIG.espName = v end })
	espSec:CreateToggle({ Name = "Class", CurrentValue = CONFIG.espClass, Callback = function(v) CONFIG.espClass = v end })
	espSec:CreateToggle({ Name = "Health Bar", CurrentValue = CONFIG.espHealth, Callback = function(v) CONFIG.espHealth = v end })
	espSec:CreateToggle({ Name = "Distance & Weapon", CurrentValue = CONFIG.espInfo, Callback = function(v) CONFIG.espInfo = v end })

	local espFilter = espTab:CreateSection("Filters & Colors")
	espFilter:CreateToggle({ Name = "Visible Only", CurrentValue = CONFIG.espVisOnly, Callback = function(v) CONFIG.espVisOnly = v end })
	espFilter:CreateToggle({ Name = "Dim Hidden", CurrentValue = CONFIG.espDimHidden, Callback = function(v) CONFIG.espDimHidden = v end })
	espFilter:CreateSlider({ Name = "Max Range (m)", Range = {50, 1500}, CurrentValue = CONFIG.espMaxM, Callback = function(v) CONFIG.espMaxM = v end })
	espFilter:CreateColorPicker({ Name = "Enemy Color", Color = COL.enemy, Callback = function(c) COL.enemy = c end })
	espFilter:CreateColorPicker({ Name = "Visible Color", Color = COL.visible, Callback = function(c) COL.visible = c end })

	local vehSec = espTab:CreateSection("Vehicles")
	vehSec:CreateToggle({ Name = "Vehicle ESP", CurrentValue = CONFIG.espVehicles, Callback = function(v) CONFIG.espVehicles = v end })
	vehSec:CreateToggle({ Name = "Draw Vehicle Box", CurrentValue = CONFIG.espVehBox, Callback = function(v) CONFIG.espVehBox = v end })
	vehSec:CreateToggle({ Name = "Draw Crew (Inside)", CurrentValue = CONFIG.espVehCrew, Callback = function(v) CONFIG.espVehCrew = v end })
	vehSec:CreateColorPicker({ Name = "Crew Color", Color = COL.vehCrew, Callback = function(c) COL.vehCrew = c end })

	-- ✅ TAB 2: AIMBOT
	local aimTab = win:CreateTab("Aimbot")
	local aimSec = aimTab:CreateSection("Aim Settings")
	aimSec:CreateToggle({ Name = "Aimbot Master", CurrentValue = CONFIG.aim, Callback = function(v) CONFIG.aim = v end })
	aimSec:CreateDropdown({ Name = "Key", Options = { "MouseButton2", "MouseButton1", "LeftShift", "E", "Q", "C" }, CurrentOption = CONFIG.aimKey, Callback = function(v) CONFIG.aimKey = v end })
	aimSec:CreateDropdown({ Name = "Target Bone", Options = { "Head", "Torso", "Nearest" }, CurrentOption = CONFIG.aimPart, Callback = function(v) CONFIG.aimPart = v end })
	aimSec:CreateToggle({ Name = "Predict Drop/Lead", CurrentValue = CONFIG.aimPredict, Callback = function(v) CONFIG.aimPredict = v end })
	aimSec:CreateToggle({ Name = "Visibility Check", CurrentValue = CONFIG.aimVisible, Callback = function(v) CONFIG.aimVisible = v end })

	local aimTune = aimTab:CreateSection("Aim Tuning")
	aimTune:CreateSlider({ Name = "FOV Size (px)", Range = {5, 600}, CurrentValue = CONFIG.aimFov, Callback = function(v) CONFIG.aimFov = v end })
	aimTune:CreateSlider({ Name = "Smoothness H", Range = {1, 100}, CurrentValue = CONFIG.aimSmoothH, Callback = function(v) CONFIG.aimSmoothH = v end })
	aimTune:CreateSlider({ Name = "Smoothness V", Range = {1, 100}, CurrentValue = CONFIG.aimSmoothV, Callback = function(v) CONFIG.aimSmoothV = v end })
	aimTune:CreateToggle({ Name = "No Recoil (Safe)", CurrentValue = CONFIG.noRecoil, Callback = function(v) CONFIG.noRecoil = v end })

	-- ✅ TAB 3: TRIGGERBOT
	local trigTab = win:CreateTab("Triggerbot")
	local trigSec = trigTab:CreateSection("Trigger Settings")
	trigSec:CreateToggle({ Name = "Enable Triggerbot", CurrentValue = CONFIG.triggerBot, Callback = function(v) CONFIG.triggerBot = v end })
	trigSec:CreateDropdown({ Name = "Trigger Bone", Options = { "Head", "Torso" }, CurrentOption = CONFIG.triggerPart, Callback = function(v) CONFIG.triggerPart = v end })
	trigSec:CreateDropdown({ Name = "Weapon Mode", Options = { "Click (Semi/Sniper)", "Hold (Auto/LMG)" }, CurrentOption = "Click (Semi/Sniper)", Callback = function(v)
		if tostring(v):find("Click") then CONFIG.triggerMode = "Click" else CONFIG.triggerMode = "Hold" end
	end })

	local trigTune = trigTab:CreateSection("Trigger Tuning")
	trigTune:CreateSlider({ Name = "Trigger Radius (px)", Range = {1, 50}, CurrentValue = CONFIG.triggerRadius, Callback = function(v) CONFIG.triggerRadius = v end })
	trigTune:CreateSlider({ Name = "Trigger Delay (ms)", Range = {10, 1500}, CurrentValue = CONFIG.triggerDelay, Callback = function(v) CONFIG.triggerDelay = v end })

	-- ✅ TAB 4: SPECTATE (ISOLATED CAMERA ZONE + QOL)
	local specTab = win:CreateTab("Spectate")
	local specCtrl = specTab:CreateSection("Spectate Controls (แยกโซนกล้องปลอดภัย)")

	local selectedPlayerName = nil
	local playerDropdown = nil

	local specMasterToggle = specCtrl:CreateToggle({
		Name = "🎥 Enable Spectate (เปิด/ปิดโหมดส่องผู้เล่น)",
		Description = "พักระบบ Aimbot/Triggerbot อัตโนมัติขณะส่อง และคืนกล้องให้ตัวเองทันทีที่ปิด",
		CurrentValue = false,
		Callback = function(v)
			if v then
				local target = selectedPlayerName and Players:FindFirstChild(selectedPlayerName) or nil
				if target and target ~= plr then
					Spectate.Start(target)
				else
					Spectate.Cycle(1)
				end
			else
				Spectate.Stop()
			end
		end
	})

	specCtrl:CreateDropdown({
		Name = "🎯 Target Filter (กรองเป้าหมายที่จะส่อง)",
		Options = { "Enemies Only", "Teammates Only", "All Players" },
		CurrentOption = Spectate.Config.FilterMode,
		Callback = function(opt)
			local val = type(opt) == "table" and opt[1] or opt
			Spectate.Config.FilterMode = tostring(val or "Enemies Only")
			if playerDropdown and playerDropdown.Refresh then
				pcall(function() playerDropdown:Refresh(Spectate.GetDropdownNames()) end)
			end
		end
	})

	playerDropdown = specCtrl:CreateDropdown({
		Name = "👤 Select Player (เลือกชื่อผู้เล่นที่จะส่อง)",
		Options = Spectate.GetDropdownNames(),
		CurrentOption = "- No Players Found -",
		Callback = function(opt)
			local raw = type(opt) == "table" and opt[1] or opt
			local pName = tostring(raw or ""):match("^(%S+)")
			if pName and pName ~= "-" then
				selectedPlayerName = pName
				local pObj = Players:FindFirstChild(pName)
				if pObj then
					Spectate.Start(pObj)
					if specMasterToggle and specMasterToggle.Set then
						pcall(function() specMasterToggle:Set(true, true) end)
					end
				end
			end
		end
	})

	specCtrl:CreateButton({
		Name = "🔄 Refresh Player List (อัปเดตรายชื่อผู้เล่นล่าสุด)",
		Callback = function()
			if playerDropdown and playerDropdown.Refresh then
				pcall(function() playerDropdown:Refresh(Spectate.GetDropdownNames()) end)
			end
		end
	})

	specCtrl:CreateButton({
		Name = "⏮️ Previous Player (ส่องคนก่อนหน้า [ ปุ่ม [ ])",
		Callback = function()
			Spectate.Cycle(-1)
		end
	})

	specCtrl:CreateButton({
		Name = "⏭️ Next Player (ส่องคนถัดไป [ ปุ่ม ] ])",
		Callback = function()
			Spectate.Cycle(1)
		end
	})

	specCtrl:CreateButton({
		Name = "🎯 Spectate Crosshair Target (ส่องคนที่อยู่กลางเป้า [ ปุ่ม V ])",
		Callback = function()
			Spectate.SpectateCrosshairTarget()
		end
	})

	specCtrl:CreateButton({
		Name = "🛑 Stop & Return Camera (ออกจากโหมดส่องทันที [ Backspace ])",
		Callback = function()
			Spectate.Stop()
			if specMasterToggle and specMasterToggle.Set then
				pcall(function() specMasterToggle:Set(false, true) end)
			end
		end
	})

	local specCamSec = specTab:CreateSection("Camera Mode & QoL Settings")

	specCamSec:CreateDropdown({
		Name = "📷 Camera View Mode (มุมมองกล้อง)",
		Options = { "1: Follow (ตามหลัง)", "2: Orbit (หมุนรอบตัวอัตโนมัติ)", "3: First Person (มุมมองบุคคลที่ 1)" },
		CurrentOption = "1: Follow (ตามหลัง)",
		Callback = function(opt)
			local s = tostring(type(opt) == "table" and opt[1] or opt)
			if s:find("^1") then Spectate.SetMode(1)
			elseif s:find("^2") then Spectate.SetMode(2)
			elseif s:find("^3") then Spectate.SetMode(3) end
		end
	})

	specCamSec:CreateSlider({
		Name = "📏 Camera Distance (ระยะซูมกล้อง Studs)",
		Range = { 3, 65 },
		Increment = 1,
		CurrentValue = Spectate.Config.DefaultDistance,
		Callback = function(v)
			Spectate.SetDistance(v)
		end
	})

	specCamSec:CreateSlider({
		Name = "🌀 Orbit Speed (ความเร็วหมุนรอบตัว)",
		Range = { 0.1, 3.0 },
		Increment = 0.1,
		CurrentValue = Spectate.Config.OrbitSpeed,
		Callback = function(v)
			Spectate.Config.OrbitSpeed = v
		end
	})

	specCamSec:CreateToggle({
		Name = "🛡️ Camera Wall-Collision (กันกล้องจมดิน/ทะลุกำแพง)",
		CurrentValue = Spectate.Config.WallCollision,
		Callback = function(v) Spectate.Config.WallCollision = v end
	})

	specCamSec:CreateToggle({
		Name = "🔁 Auto-Switch on Target Death (สลับคนอัตโนมัติเมื่อเป้าหมายตาย)",
		CurrentValue = Spectate.Config.AutoSwitchOnDeath,
		Callback = function(v) Spectate.Config.AutoSwitchOnDeath = v end
	})

	specCamSec:CreateToggle({
		Name = "📊 Show Spectate Telemetry HUD (แสดงข้อมูล HP/ปืน/อาชีพ ด้านบนจอ)",
		CurrentValue = Spectate.Config.ShowHUD,
		Callback = function(v)
			Spectate.Config.ShowHUD = v
			if not v then hideSpecHud() end
		end
	})

	-- ✅ TAB 5: WORLD
	local worldTab = win:CreateTab("World")
	local worldSec = worldTab:CreateSection("Environment")
	worldSec:CreateToggle({ Name = "No Fog", CurrentValue = CONFIG.noFog, Callback = function(v) CONFIG.noFog = v end })
	worldSec:CreateToggle({ Name = "Fullbright", CurrentValue = CONFIG.fullbright, Callback = function(v) CONFIG.fullbright = v end })
	worldSec:CreateToggle({ Name = "No Suppression", CurrentValue = CONFIG.noSuppress, Callback = function(v) CONFIG.noSuppress = v end })
else
	warn("[Sill X] UI ไม่สามารถโหลดได้ แต่ระบบ ESP/Aimbot จะยังทำงานอยู่เบื้องหลัง")
end

--------------------------------------------------------------------------------
-- LOOPS, HOTKEYS & CLEANUP BINDINGS
--------------------------------------------------------------------------------

RunService:BindToRenderStep("CWAim", Enum.RenderPriority.Camera.Value + 1, function(dt) pcall(aimPass, dt) end)
RunService:BindToRenderStep("CWESP", Enum.RenderPriority.Camera.Value + 2, function() pcall(renderPass) pcall(worldPass) end)

local mainInputConn = UserInputService.InputBegan:Connect(function(input, typing)
	if _G.__CWAR ~= GEN or typing then return end

	-- Panic Key (F1): Disables Aimbot, Silent, Triggerbot AND immediately exits Spectate!
	local k = keyFromName(CONFIG.panicKey)
	if k and input.KeyCode == k then
		CONFIG.aim, CONFIG.silent, CONFIG.triggerBot = false, false, false
		Spectate.Stop()
		return
	end

	-- Spectate Quick Hotkeys:
	-- [ : Previous Player | ] : Next Player | Backspace : Stop Spectating | V : Spectate Crosshair Target
	if input.KeyCode == Enum.KeyCode.LeftBracket then
		Spectate.Cycle(-1)
	elseif input.KeyCode == Enum.KeyCode.RightBracket then
		Spectate.Cycle(1)
	elseif input.KeyCode == Enum.KeyCode.Backspace and Spectate.IsActive() then
		Spectate.Stop()
	elseif input.KeyCode == Enum.KeyCode.V and UserInputService:IsKeyDown(Enum.KeyCode.LeftAlt) then
		-- LeftAlt + V: Quick-Spectate player near crosshair (avoids accidental V presses in-game!)
		if Spectate.IsActive() then
			Spectate.Stop()
		else
			Spectate.SpectateCrosshairTarget()
		end
	end
end)

_G.__CWAR_CLEANUP = function()
	pcall(function() Spectate.Stop() end)
	pcall(function() RunService:UnbindFromRenderStep("CWAim") end)
	pcall(function() RunService:UnbindFromRenderStep("CWESP") end)
	pcall(function() RunService:UnbindFromRenderStep("CWSpec") end)
	if mainInputConn then pcall(function() mainInputConn:Disconnect() end) end
	if SilL and SilL.Destroy then pcall(function() SilL:Destroy() end) end
end

print("[Sill X | Cold War] Loaded with Isolated Spectate System. Press Home to toggle UI.")
