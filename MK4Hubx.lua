--[[
=====================================================================
   MK4 HUBX v2  |  Blox Fruits  |  WindUI  |  Sem Key
---------------------------------------------------------------------
   Tema: vermelho / preto (WindUI:AddTheme)
   Tabs: Farm, Events, Bau, Frutas, Utilitarios

   v3:
   - Ataque de verdade: tweak no CombatFramework (activeController) +
     Tool:Activate + clique virtual, com metodo selecionavel
   - Magnet puxa APENAS NPCs hostis (sem ProximityPrompt/ClickDetector,
     sem lojistas/quest givers/anchorados)
   - Bau com teleporte instantaneo e espera longa quando o servidor
     recusa, para nao travar em um bau inalcancavel
   - Todos os recursos rodam em loops persistentes (scheduler com pcall
     e auto-restart, nada morre silenciosamente)
   - Remotes reais do jogo (dump PlaceId 2753915549):
       Remotes.CommF_ (RemoteFunction)  Remotes.CommE
       Remotes.Chest                    Remotes.Prompt
       Remotes.Raids                    Remotes.OnTalkToNPC
       Remotes.GetBestQuestNPC          Remotes.GetFruitData
       Modules.Net["RE/SpinGacha"]      Modules.Net["RE/ShopNetwork"]
       Modules.Net["RE/GachaNetworkRE"] Remotes.SetLocalMovers
       Remotes.BodyMover                Remotes.DoRejoin

   Execucao:
     loadstring(game:HttpGet("SEU_LINK_AQUI"))()
=====================================================================
]]

--=====================================================================
-- 0. WINDUI
--=====================================================================
local windOk, WindUI = pcall(function()
	return loadstring(game:HttpGet("https://github.com/Footagesus/WindUI/releases/latest/download/main.lua"))()
end)

if not windOk or not WindUI then
	return warn("[MK4 Hubx] Falha ao carregar a WindUI: " .. tostring(WindUI))
end

--=====================================================================
-- 1. SERVICOS / REMOTES
--=====================================================================
local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")
local TweenService = game:GetService("TweenService")
local VirtualUser = game:GetService("VirtualUser")
local TeleportService = game:GetService("TeleportService")
local HttpService = game:GetService("HttpService")

local Workspace = workspace
local LP = Players.LocalPlayer

local Remotes = ReplicatedStorage:WaitForChild("Remotes", 30)
local ModulesNet = ReplicatedStorage:FindFirstChild("Modules")
ModulesNet = ModulesNet and ModulesNet:FindFirstChild("Net")

local function getRemote(container, name)
	if not container then
		return nil
	end
	return container:FindFirstChild(name)
end

local REMOTES = {
	CommF = getRemote(Remotes, "CommF_"),
	CommE = getRemote(Remotes, "CommE"),
	Chest = getRemote(Remotes, "Chest"),
	Prompt = getRemote(Remotes, "Prompt"),
	Raids = getRemote(Remotes, "Raids"),
	OnTalkToNPC = getRemote(Remotes, "OnTalkToNPC"),
	GetBestQuestNPC = getRemote(Remotes, "GetBestQuestNPC"),
	GetFruitData = getRemote(Remotes, "GetFruitData"),
	DoRejoin = getRemote(Remotes, "DoRejoin"),
	SetLocalMovers = getRemote(Remotes, "SetLocalMovers"),
	BodyMover = getRemote(Remotes, "BodyMover"),
	SegmentHit = getRemote(Remotes, "SegmentHit"),
	QuestUpdate = getRemote(Remotes, "QuestUpdate"),
	SpinGacha = getRemote(ModulesNet, "RE/SpinGacha"),
	GachaNetwork = getRemote(ModulesNet, "RE/GachaNetworkRE"),
	ShopNetwork = getRemote(ModulesNet, "RE/ShopNetwork"),
	ReadPlayerData = getRemote(ModulesNet, "RF/ReadPlayerData"),
}

if not REMOTES.CommF then
	WindUI:Notify({
		Title = "MK4 Hubx",
		Content = "Remotes do Blox Fruits nao encontrados. Execute dentro do jogo.",
		Icon = "x",
		Duration = 8,
	})
	return
end

--=====================================================================
-- 2. CONFIG
--=====================================================================
local Config = {
	Farm = {
		Enabled = false,
		Mode = "Mais proximo",
		Mob = "",
		Radius = 300,
		Speed = 130,
		AttackDelay = 0.15,
		FastAttack = true,
		AttackMethod = "Auto (todos)",
		CombatTweak = true,
		AttackIncrement = 4,
		HitboxMagnitude = 150,
		AutoEquip = true,
		Pull = true,
		PullRadius = 600,
		PullDistance = 6,
		KillAura = true,
		AuraRadius = 40,
		AutoQuest = false,
		UseBestQuest = true,
		QuestId = "BanditQuest1",
		QuestLevel = 1,
		AutoBuso = false,
	},
	Chest = {
		Enabled = false,
		Speed = 170,
		Delay = 0.15,
		Radius = 500,
		UseRemote = true,
		Instant = true,
	},
	Fruit = {
		Enabled = false,
		Speed = 140,
		Delay = 0.4,
		Notify = true,
	},
	Roll = {
		Enabled = false,
		MinBeli = 1000000,
		Wanted = {},
		Notify = true,
		Reroll = false,
	},
	Events = {},
	Misc = {
		AntiAfk = true,
	},
}

local currentTween = nil
local busyAction = false
local warnedNoWeapon = false

--=====================================================================
-- 3. HELPERS
--=====================================================================
local function notify(title, content, icon, duration)
	pcall(function()
		WindUI:Notify({
			Title = title,
			Content = content,
			Icon = icon or "info",
			Duration = duration or 5,
		})
	end)
end

-- Invoke seguro em qualquer RemoteFunction
local function invokeOn(remote, ...)
	if not remote then
		return nil
	end
	local args = table.pack(...)
	local ok, result = pcall(function()
		return remote:InvokeServer(table.unpack(args, 1, args.n))
	end)
	if ok then
		return result
	end
	return nil
end

-- Fire seguro em qualquer RemoteEvent
local function fireOn(remote, ...)
	if not remote then
		return false
	end
	local args = table.pack(...)
	local ok = pcall(function()
		remote:FireServer(table.unpack(args, 1, args.n))
	end)
	return ok
end

local function invoke(...)
	return invokeOn(REMOTES.CommF, ...)
end

local function fireRemote(...)
	return fireOn(REMOTES.CommE, ...)
end

local function getChar()
	local char = LP.Character
	if not char then
		return nil
	end
	local hrp = char:FindFirstChild("HumanoidRootPart")
	local hum = char:FindFirstChildOfClass("Humanoid")
	if hrp and hum then
		return char, hrp, hum
	end
	return nil
end

local function getHRP()
	local _, hrp = getChar()
	return hrp
end

local function getStat(name)
	local data = LP:FindFirstChild("Data")
	local value = data and data:FindFirstChild(name)
	if value then
		return value.Value
	end
	local stats = LP:FindFirstChild("leaderstats")
	local ls = stats and stats:FindFirstChild(name)
	return ls and ls.Value or nil
end

local function getBeli()
	return getStat("Beli") or 0
end

local function moveTo(position, speed)
	local hrp = getHRP()
	if not hrp then
		return false
	end
	if currentTween then
		pcall(function()
			currentTween:Cancel()
		end)
		currentTween = nil
	end
	local distance = (hrp.Position - position).Magnitude
	if distance < 6 then
		return true
	end
	local duration = math.clamp(distance / math.max(speed or 100, 1), 0.05, 5)
	local tweenOk, tween = pcall(function()
		return TweenService:Create(hrp, TweenInfo.new(duration, Enum.EasingStyle.Linear), { CFrame = CFrame.new(position) })
	end)
	if not tweenOk or not tween then
		return false
	end
	currentTween = tween
	pcall(function()
		tween:Play()
	end)
	local finished = false
	local conn = tween.Completed:Connect(function()
		finished = true
	end)
	local timeout = os.clock() + duration + 0.5
	while not finished and os.clock() < timeout do
		task.wait()
	end
	pcall(function()
		conn:Disconnect()
	end)
	currentTween = nil
	local newHRP = getHRP()
	if newHRP then
		newHRP.CFrame = CFrame.new(position)
	end
	return true
end

local function getWeapon()
	local char = LP.Character
	if not char then
		return nil
	end
	return char:FindFirstChildOfClass("Tool")
end

-- ---------------- COMBATE ----------------
-- tool:Activate() sozinho nao registra hit no Blox Fruits: quem manda no
-- ataque e o CombatFramework (PlayerScripts). Alem de ativar a arma,
-- mexemos no activeController e mandamos clique virtual.
local combatController = nil
local lastCombatLookup = 0

local function getCombatController()
	if combatController and combatController.Parent ~= nil then
		return combatController
	end
	if (os.clock() - lastCombatLookup) < 5 then
		return combatController
	end
	lastCombatLookup = os.clock()
	if not getreg or not getfenv or not debug or not debug.getupvalues then
		return nil
	end
	local ok, found = pcall(function()
		for _, fn in pairs(getreg()) do
			if type(fn) == "function" then
				local envOk, env = pcall(getfenv, fn)
				if envOk and type(env) == "table" and env.script and env.script.Name == "CombatFramework" then
					for _, up in pairs(debug.getupvalues(fn)) do
						if type(up) == "table" and up.activeController then
							return up.activeController
						end
					end
				end
			end
		end
	end)
	if ok and found then
		combatController = found
	end
	return combatController
end

local function boostCombat()
	if not Config.Farm.CombatTweak then
		return
	end
	local controller = getCombatController()
	if not controller then
		return
	end
	pcall(function()
		controller.timeToNextAttack = -(math.huge ^ math.huge ^ math.huge)
		controller.attacking = false
		controller.increment = Config.Farm.AttackIncrement
		controller.blocking = false
		controller.hitboxMagnitude = Config.Farm.HitboxMagnitude
		controller.focusStart = 0
		if controller.humanoid then
			controller.humanoid.AutoRotate = true
		end
	end)
end

local MELEE_KEYWORDS = { "sword", "katana", "blade", "cutlass", "saber", "melee", "combat", "claw", "axe", "mace", "trident", "spear", "gun", "fruit" }

local lastEquipTry = 0
local function ensureWeapon()
	if not Config.Farm.AutoEquip then
		return
	end
	if (os.clock() - lastEquipTry) < 1 then
		return
	end
	lastEquipTry = os.clock()
	local char, _, hum = getChar()
	if not char or not hum then
		return
	end
	if char:FindFirstChildOfClass("Tool") then
		return
	end
	local backpack = LP:FindFirstChild("Backpack")
	if not backpack then
		return
	end
	local fallback
	for _, item in ipairs(backpack:GetChildren()) do
		if item:IsA("Tool") then
			fallback = fallback or item
			local lower = item.Name:lower()
			for _, word in ipairs(MELEE_KEYWORDS) do
				if lower:find(word, 1, true) then
					pcall(function()
						hum:EquipTool(item)
					end)
					return
				end
			end
		end
	end
	if fallback then
		pcall(function()
			hum:EquipTool(fallback)
		end)
	end
end

local function facePosition(position)
	local hrp = getHRP()
	if not hrp or not position then
		return
	end
	pcall(function()
		hrp.CFrame = CFrame.new(hrp.Position, Vector3.new(position.X, hrp.Position.Y, position.Z))
	end)
end

local function virtualClick()
	local point = Vector2.new(0, 0)
	local camera = Workspace.CurrentCamera
	local ok = pcall(function()
		VirtualUser:CaptureController()
		if camera then
			VirtualUser:Button1Down(point, camera.CFrame)
			VirtualUser:Button1Up(point, camera.CFrame)
		else
			VirtualUser:Button1Down(point)
			VirtualUser:Button1Up(point)
		end
	end)
	if not ok and mouse1click then
		pcall(mouse1click)
	end
end

local function attack(position)
	ensureWeapon()
	boostCombat()
	if position then
		facePosition(position)
	end

	local method = Config.Farm.AttackMethod
	if method == "CommF Attack" then
		invoke("Attack")
		return
	elseif method == "Tool:Activate" then
		local tool = getWeapon()
		if tool then
			pcall(function()
				tool:Activate()
			end)
		end
		return
	elseif method == "Clique virtual" then
		virtualClick()
		return
	end

	-- Auto: ativa a arma e manda clique virtual (o CombatFramework
	-- interpreta os dois como ataque)
	local tool = getWeapon()
	if tool then
		pcall(function()
			tool:Activate()
		end)
	elseif not warnedNoWeapon then
		warnedNoWeapon = true
		notify("MK4 Hubx", "Equipe uma arma/fruta (ou ligue Auto Equip).", "alert-triangle", 6)
	end
	virtualClick()
	if not tool then
		invoke("Attack")
	end
end

-- ProximityPrompt: usa o remote Remotes.Prompt quando existir, com
-- fallback para InputHoldBegin/End e ClickDetector.
local function interact(instance)
	for _, desc in ipairs(instance:GetDescendants()) do
		if desc:IsA("ProximityPrompt") then
			local hold = desc.HoldDuration or 0
			if REMOTES.Prompt then
				fireOn(REMOTES.Prompt, desc)
			end
			pcall(function()
				desc:InputHoldBegin()
			end)
			task.wait(hold + 0.15)
			pcall(function()
				desc:InputHoldEnd()
			end)
			return true
		end
	end
	for _, desc in ipairs(instance:GetDescendants()) do
		if desc:IsA("ClickDetector") then
			pcall(function()
				fireclickdetector(desc)
			end)
			return true
		end
	end
	return false
end

--=====================================================================
-- 4. LEITURA DO MUNDO
--=====================================================================
local mobCache = nil
local mobCacheTime = 0

-- NPCs com interacao (lojas, quest givers, barcos) nunca entram no magnet
local NON_ATTACKABLE = {
	"dealer", "quest", "giver", "cousin", "shop", "seller", "merchant", "store",
	"teacher", "trainer", "haki", "boat", "shipwright", "spawn", "portal", "npc",
	"dialog", "sign", "barrel", "chest", "stand",
}

local function isAttackable(model)
	local myChar = LP.Character
	if not model:IsA("Model") then
		return false
	end
	if myChar and (model == myChar or model:IsDescendantOf(myChar)) then
		return false
	end
	local hum = model:FindFirstChildOfClass("Humanoid")
	local hrp = model:FindFirstChild("HumanoidRootPart")
	if not hum or not hrp or hum.Health <= 0 then
		return false
	end
	for _, desc in ipairs(model:GetDescendants()) do
		if desc:IsA("ProximityPrompt") or desc:IsA("ClickDetector") or desc:IsA("Dialog") then
			return false
		end
	end
	local enemiesFolder = Workspace:FindFirstChild("Enemies")
	local inEnemies = enemiesFolder ~= nil and model:IsDescendantOf(enemiesFolder)
	if not inEnemies then
		local lower = model.Name:lower()
		for _, blocked in ipairs(NON_ATTACKABLE) do
			if lower:find(blocked, 1, true) then
				return false
			end
		end
		if hrp.Anchored then
			return false
		end
	end
	return true
end

local function collectMobs(force)
	if not force and mobCache and (os.clock() - mobCacheTime) < 0.2 then
		return mobCache
	end
	local list = {}
	local seen = {}

	local function add(model)
		if seen[model] or model == LP.Character then
			return
		end
		if not isAttackable(model) then
			return
		end
		local hum = model:FindFirstChildOfClass("Humanoid")
		local hrp = model:FindFirstChild("HumanoidRootPart")
		if hum and hrp and hum.Health > 0 then
			seen[model] = true
			list[#list + 1] = { Model = model, Humanoid = hum, Root = hrp, Name = model.Name }
		end
	end

	local enemies = Workspace:FindFirstChild("Enemies")
	if enemies then
		for _, mob in ipairs(enemies:GetChildren()) do
			add(mob)
		end
	end

	for _, child in ipairs(Workspace:GetChildren()) do
		if child:IsA("Model") then
			add(child)
		elseif child:IsA("Folder") and child.Name ~= "Map" and child.Name ~= "Effects" then
			for _, mob in ipairs(child:GetChildren()) do
				if mob:IsA("Model") then
					add(mob)
				end
			end
		end
	end

	mobCache = list
	mobCacheTime = os.clock()
	return list
end

local function nearestMob(radius, filterName)
	local hrp = getHRP()
	if not hrp then
		return nil
	end
	local best, bestDistance = nil, radius or 300
	for _, mob in ipairs(collectMobs()) do
		local match = true
		if filterName and filterName ~= "" then
			match = mob.Name:lower() == filterName:lower()
		end
		if match then
			local distance = (mob.Root.Position - hrp.Position).Magnitude
			if distance < bestDistance then
				best, bestDistance = mob, distance
			end
		end
	end
	return best
end

local chestCache = {}
local lastChestScan = 0
local chestCooldown = {}
local fruitCooldown = {}

-- Evita repetir o mesmo bau/fruta sem parar (spam de remote)
local function onCooldown(map, instance, seconds)
	local last = map[instance]
	return last ~= nil and (os.clock() - last) < (seconds or 8)
end

local function isChestName(name)
	local lower = name:lower()
	return lower == "chest" or lower == "chest2" or lower == "chest3"
		or lower:find("chest", 1, true) ~= nil
		or lower:find("treasure", 1, true) ~= nil
		or lower:find("bau", 1, true) ~= nil
end

local function scanChests()
	local found = {}
	for _, region in ipairs(Workspace:GetChildren()) do
		if region:IsA("Folder") or region:IsA("Model") then
			local ok, descendants = pcall(function()
				return region:GetDescendants()
			end)
			if ok then
				for _, desc in ipairs(descendants) do
					if isChestName(desc.Name) and (desc:IsA("Model") or desc:IsA("BasePart")) then
						local part = desc:IsA("BasePart") and desc
							or desc.PrimaryPart
							or desc:FindFirstChildWhichIsA("BasePart")
						if part then
							found[#found + 1] = { Instance = desc, Part = part }
						end
					end
				end
			end
		end
	end
	return found
end

local function refreshChests(force)
	if not force and os.clock() - lastChestScan < 5 then
		return
	end
	lastChestScan = os.clock()
	chestCache = scanChests()
end

local function nearestChest(radius)
	refreshChests(false)
	local hrp = getHRP()
	if not hrp then
		return nil
	end
	local best, bestDistance = nil, radius or 400
	for _, entry in ipairs(chestCache) do
		local part = entry.Part
		if part and part.Parent and part:IsDescendantOf(Workspace) and not onCooldown(chestCooldown, entry.Instance, 8) then
			local distance = (part.Position - hrp.Position).Magnitude
			if distance < bestDistance then
				best, bestDistance = entry, distance
			end
		end
	end
	return best
end

local function isFruit(instance)
	if instance:IsDescendantOf(LP.Character) then
		return false
	end
	local parent = instance.Parent
	if parent and (parent:IsA("Backpack") or parent:IsA("Player")) then
		return false
	end
	if not (instance:IsA("Tool") or instance:IsA("Model")) then
		return false
	end
	local name = instance.Name
	local parentName = parent and parent.Name:lower() or ""
	if parentName:find("fruit", 1, true) or parentName:find("fruta", 1, true) then
		return true
	end
	if name:find("%-") and #name >= 5 and instance:FindFirstChild("Handle") then
		return true
	end
	return false
end

local function scanFruits()
	local fruits = {}
	local function add(instance)
		if isFruit(instance) then
			local handle = instance:FindFirstChild("Handle")
				or instance.PrimaryPart
				or instance:FindFirstChildWhichIsA("BasePart")
			if handle then
				fruits[#fruits + 1] = { Instance = instance, Part = handle }
			end
		end
	end
	for _, child in ipairs(Workspace:GetChildren()) do
		add(child)
		if child:IsA("Folder") and child.Name:lower():find("fruit", 1, true) then
			for _, sub in ipairs(child:GetChildren()) do
				add(sub)
			end
		end
	end
	return fruits
end

local function nearestFruit()
	local hrp = getHRP()
	if not hrp then
		return nil
	end
	local best, bestDistance = nil, math.huge
	for _, fruit in ipairs(scanFruits()) do
		local part = fruit.Part
		if part and part.Parent and not onCooldown(fruitCooldown, fruit.Instance, 8) then
			local distance = (part.Position - hrp.Position).Magnitude
			if distance < bestDistance then
				best, bestDistance = fruit, distance
			end
		end
	end
	return best
end

--=====================================================================
-- 5. COMBATE / FARM
--=====================================================================
-- Puxa todos os NPCs do raio para uma roda ao redor do player.
-- NPCs em Blox Fruits costumam ter network ownership do jogador mais
-- proximo, por isso escrever o CFrame replica para o servidor.
local function pullMobs()
	local hrp = getHRP()
	if not hrp then
		return 0
	end
	local pulled = 0
	local ring = Config.Farm.PullDistance
	local origin = hrp.Position
	for _, mob in ipairs(collectMobs()) do
		local mhrp = mob.Root
		local delta = mhrp.Position - origin
		local distance = delta.Magnitude
		if distance <= Config.Farm.PullRadius and distance > ring then
			pulled = pulled + 1
			local angle = (pulled * 2.399963) % (math.pi * 2)
			local target = origin
				+ Vector3.new(math.cos(angle) * ring, 2, math.sin(angle) * ring)
			pcall(function()
				mhrp.CFrame = CFrame.new(target, Vector3.new(origin.X, target.Y, origin.Z))
				mhrp.AssemblyLinearVelocity = Vector3.zero
			end)
		end
	end
	return pulled
end

local function killAura()
	local hrp = getHRP()
	if not hrp then
		return
	end
	local best, bestDistance = nil, Config.Farm.AuraRadius
	for _, mob in ipairs(collectMobs()) do
		local distance = (mob.Root.Position - hrp.Position).Magnitude
		if distance <= bestDistance and mob.Humanoid.Health > 0 then
			best, bestDistance = mob, distance
		end
	end
	if best then
		attack(best.Root.Position)
	end
end

-- keepGoing: funcao que decide se o combate continua
local function farmTarget(target, keepGoing)
	if not target then
		return
	end
	local mob = target.Model
	local mhrp = target.Root
	local mhum = target.Humanoid
	local started = os.clock()
	local lastBuso = 0
	local active = keepGoing or function()
		return Config.Farm.Enabled
	end

	if not Config.Farm.Pull then
		moveTo(mhrp.Position + Vector3.new(0, 3, 0), Config.Farm.Speed)
	end

	while active() and mob.Parent and mhum.Health > 0 and (os.clock() - started) < 8 do
		local hrp = getHRP()
		if not hrp then
			break
		end
		if not Config.Farm.Pull and (hrp.Position - mhrp.Position).Magnitude > 14 then
			hrp.CFrame = CFrame.new(mhrp.Position + Vector3.new(0, 3, 0))
		end
		if Config.Farm.AutoBuso and (os.clock() - lastBuso) > 2 then
			lastBuso = os.clock()
			invoke("Buso")
		end
		attack(mhrp.Position)
		task.wait(Config.Farm.FastAttack and Config.Farm.AttackDelay or 0.45)
	end
end

local function startQuest()
	local questId = Config.Farm.QuestId
	-- GetBestQuestNPC: escolhe a melhor quest pro nivel atual quando existir
	if Config.Farm.UseBestQuest and REMOTES.GetBestQuestNPC then
		local best = invokeOn(REMOTES.GetBestQuestNPC)
		if type(best) == "string" and #best > 0 then
			questId = best
		end
	end
	invoke("StartQuest", questId, Config.Farm.QuestLevel)
end

local function collectChest(entry)
	local part = entry.Part
	if not part or not part.Parent then
		return false
	end
	chestCooldown[entry.Instance] = os.clock()
	local hrp = getHRP()
	if not hrp then
		return false
	end

	-- Teleporte instantaneo: com tween o trajeto longo (raio alto) gastava
	-- segundos e o player caia no meio do caminho, nunca chegando no bau.
	if Config.Chest.Instant then
		pcall(function()
			hrp.CFrame = CFrame.new(part.Position + Vector3.new(0, 3, 0))
		end)
		task.wait(0.05)
	else
		moveTo(part.Position + Vector3.new(0, 3, 0), Config.Chest.Speed)
	end

	if Config.Chest.UseRemote then
		fireOn(REMOTES.Chest, entry.Instance)
		fireOn(REMOTES.Chest, part)
	end
	if firetouchinterest then
		pcall(function()
			firetouchinterest(hrp, part, 0)
		end)
		task.wait(0.05)
		pcall(function()
			firetouchinterest(hrp, part, 1)
		end)
	else
		pcall(function()
			hrp.CFrame = part.CFrame
		end)
		task.wait(0.1)
	end
	interact(entry.Instance)
	task.wait(0.3)

	-- Se o bau continuou no mapa, o servidor recusou: coloca em espera longa
	if part.Parent and entry.Instance.Parent then
		chestCooldown[entry.Instance] = os.clock() + 20
	end
	return true
end

--=====================================================================
-- 6. EVENTOS
--=====================================================================
local EVENT_TARGETS = {
	SeaBeast = { label = "Sea Beast / Terrorshark", names = { "terrorshark", "terror shark", "sea beast", "seabeast" } },
	Elite = { label = "Elite Pirate / Elite Hunter", names = { "elite pirate", "elite hunter", "elite" } },
	Factory = { label = "Factory Raid", names = { "factory", "core", "raid boss" } },
	CursedShip = { label = "Cursed Ship", names = { "cursed ship", "cursed captain", "cursed soldier" } },
	GhostShip = { label = "Ghost Ship", names = { "ghost ship", "ghost captain", "ghost" } },
	DoughKing = { label = "Dough King", names = { "dough king", "doughking" } },
	Darkbeard = { label = "Darkbeard", names = { "darkbeard", "dark beard" } },
	Kitsune = { label = "Kitsune", names = { "kitsune", "kitsune shrine" } },
}

for id in pairs(EVENT_TARGETS) do
	Config.Events[id] = false
end

local function matchesEventName(name, names)
	local lower = name:lower()
	for _, wanted in ipairs(names) do
		if lower == wanted or lower:find(wanted, 1, true) then
			return true
		end
	end
	return false
end

local function findEventTarget()
	for id, enabled in pairs(Config.Events) do
		if enabled then
			local data = EVENT_TARGETS[id]
			if data then
				for _, mob in ipairs(collectMobs()) do
					if mob.Humanoid.Health > 0 and matchesEventName(mob.Name, data.names) then
						return mob, id
					end
				end
			end
		end
	end
	return nil
end

--=====================================================================
-- 7. FRUTAS / ROLAGEM
--=====================================================================
local function isWantedFruit(name)
	if type(name) ~= "string" then
		return true
	end
	local count = 0
	for _ in pairs(Config.Roll.Wanted) do
		count = count + 1
	end
	if count == 0 then
		return false
	end
	local lower = name:lower()
	for wanted, enabled in pairs(Config.Roll.Wanted) do
		if enabled and lower:find(wanted:lower(), 1, true) then
			return true
		end
	end
	return false
end

local function readFruitResult(result)
	if type(result) == "string" then
		return result
	elseif type(result) == "table" then
		for _, value in pairs(result) do
			if type(value) == "string" then
				return value
			end
		end
	end
	return nil
end

local function buyRandomFruit()
	if busyAction then
		return nil
	end
	busyAction = true
	local result = readFruitResult(invoke("Cousin", "Buy"))
	busyAction = false
	return result
end

--=====================================================================
-- 8. REMOTE SPY
--=====================================================================
local spyEnabled = false
local spyInstalled = false

local function installRemoteSpy()
	if spyInstalled then
		return true
	end
	if not hookmetamethod then
		notify("Remote Spy", "Seu executor nao suporta hookmetamethod.", "x", 6)
		return false
	end
	local ok = pcall(function()
		local targets = {}
		for _, remote in pairs(REMOTES) do
			if remote then
				targets[remote] = true
			end
		end
		local oldNamecall
		oldNamecall = hookmetamethod(game, "__namecall", function(self, ...)
			local method = getnamecallmethod()
			if spyEnabled and targets[self] and (method == "InvokeServer" or method == "FireServer") then
				local args = table.pack(...)
				local parts = {}
				for i = 1, args.n do
					parts[i] = tostring(args[i])
				end
				print(("[MK4 Hubx][REMOTE] %s:%s(%s)"):format(self.Name, method, table.concat(parts, ", ")))
			end
			return oldNamecall(self, ...)
		end)
	end)
	spyInstalled = ok
	if not ok then
		notify("Remote Spy", "Nao foi possivel instalar o hook.", "x", 6)
	end
	return ok
end

--=====================================================================
-- 9. UTILITARIOS
--=====================================================================
local antiAfkConn
local function applyAntiAfk()
	if antiAfkConn then
		pcall(function()
			antiAfkConn:Disconnect()
		end)
		antiAfkConn = nil
	end
	if Config.Misc.AntiAfk then
		antiAfkConn = LP.Idled:Connect(function()
			pcall(function()
				VirtualUser:CaptureController()
				VirtualUser:ClickButton2(Vector2.new(0, 0))
			end)
		end)
	end
end
applyAntiAfk()

local function serverHop()
	local ok = pcall(function()
		local url = "https://games.roblox.com/v1/games/%d/servers/Public?sortOrder=Asc&limit=100"
		local response = HttpService:JSONDecode(game:HttpGet(url:format(game.PlaceId)))
		for _, server in ipairs(response.data or {}) do
			if server.playing < server.maxPlayers and server.id ~= game.JobId then
				TeleportService:TeleportToPlaceInstance(game.PlaceId, server.id, LP)
				return
			end
		end
	end)
	if not ok then
		notify("Server Hop", "Nao encontrei servidores disponiveis.", "alert-triangle", 5)
	end
end

local function rejoin()
	if REMOTES.DoRejoin then
		fireOn(REMOTES.DoRejoin)
	else
		TeleportService:Teleport(game.PlaceId, LP)
	end
end

--=====================================================================
-- 10. SCHEDULER (todos os recursos em loop, com auto-restart)
--=====================================================================
local Loops = {}
local LoopErrors = {}

local function startLoop(name, body)
	Loops[name] = body
	task.spawn(function()
		while Loops[name] do
			local ok, err = pcall(body)
			if not ok then
				LoopErrors[name] = (LoopErrors[name] or 0) + 1
				if LoopErrors[name] <= 3 then
					warn(("[MK4 Hubx] loop '%s' falhou: %s"):format(name, tostring(err)))
				end
				task.wait(1)
			end
		end
	end)
end

-- Magnet: mantem todos os NPCs do raio colados no player
startLoop("pull", function()
	if not (Config.Farm.Enabled and Config.Farm.Pull) then
		task.wait(0.3)
		return
	end
	pullMobs()
	task.wait(0.05)
end)

-- Kill Aura independente do auto farm
startLoop("aura", function()
	if not Config.Farm.KillAura then
		task.wait(0.3)
		return
	end
	killAura()
	task.wait(Config.Farm.FastAttack and Config.Farm.AttackDelay or 0.45)
end)

startLoop("farm", function()
	if not Config.Farm.Enabled then
		task.wait(0.3)
		return
	end
	if not getChar() then
		task.wait(0.5)
		return
	end
	local filter = Config.Farm.Mode == "Mob especifico" and Config.Farm.Mob or nil
	local target = nearestMob(Config.Farm.Pull and Config.Farm.PullRadius or Config.Farm.Radius, filter)
	if target then
		farmTarget(target, function()
			return Config.Farm.Enabled
		end)
	else
		task.wait(0.4)
	end
end)

startLoop("quest", function()
	if not (Config.Farm.Enabled and Config.Farm.AutoQuest) then
		task.wait(0.5)
		return
	end
	startQuest()
	task.wait(5)
end)

startLoop("buso", function()
	if not Config.Farm.AutoBuso then
		task.wait(1)
		return
	end
	invoke("Buso")
	task.wait(2)
end)

startLoop("events", function()
	local any = false
	for _, enabled in pairs(Config.Events) do
		if enabled then
			any = true
			break
		end
	end
	if not any then
		task.wait(0.5)
		return
	end
	local mob, id = findEventTarget()
	if mob then
		farmTarget(mob, function()
			return Config.Events[id] == true
		end)
	else
		task.wait(0.5)
	end
end)

startLoop("chest", function()
	if not Config.Chest.Enabled then
		task.wait(0.3)
		return
	end
	local chest = nearestChest(Config.Chest.Radius)
	if chest then
		collectChest(chest)
		task.wait(Config.Chest.Delay)
	else
		refreshChests(true)
		task.wait(0.6)
	end
end)

startLoop("fruit", function()
	if not Config.Fruit.Enabled then
		task.wait(0.4)
		return
	end
	local fruit = nearestFruit()
	if not fruit then
		task.wait(0.5)
		return
	end
	local fruitName = fruit.Instance.Name
	fruitCooldown[fruit.Instance] = os.clock()
	moveTo(fruit.Part.Position + Vector3.new(0, 3, 0), Config.Fruit.Speed)
	if firetouchinterest then
		local hrp = getHRP()
		if hrp then
			pcall(function()
				firetouchinterest(hrp, fruit.Part, 0)
			end)
			task.wait(0.05)
			pcall(function()
				firetouchinterest(hrp, fruit.Part, 1)
			end)
		end
	else
		local hrp = getHRP()
		if hrp then
			hrp.CFrame = fruit.Part.CFrame
		end
	end
	interact(fruit.Instance)
	task.wait(0.4)
	if Config.Fruit.Notify and not fruit.Part.Parent then
		notify("Fruta coletada", fruitName, "apple", 4)
	end
end)

startLoop("roll", function()
	if not Config.Roll.Enabled then
		task.wait(1)
		return
	end
	if busyAction then
		task.wait(0.5)
		return
	end
	if getBeli() < Config.Roll.MinBeli then
		task.wait(2)
		return
	end
	local fruit = buyRandomFruit()
	if fruit and Config.Roll.Notify then
		notify("Rolagem", "Saiu: " .. fruit, "dice-5", 5)
	end
	if fruit and isWantedFruit(fruit) then
		Config.Roll.Enabled = false
		notify("Rolagem", "Fruta desejada encontrada: " .. fruit, "party-popper", 8)
	end
	task.wait(1)
end)

startLoop("reroll", function()
	if not Config.Roll.Reroll then
		task.wait(1)
		return
	end
	invoke("BlackbeardReward", "Fruit", "2")
	task.wait(6)
end)

--=====================================================================
-- 11. TEMA VERMELHO / PRETO
--=====================================================================
local MK4_RED = {
	Name = "MK4 Red",
	Background = Color3.fromHex("#0b0505"),
	Accent = Color3.fromHex("#1a0606"),
	Dialog = Color3.fromHex("#140404"),
	Outline = Color3.fromHex("#3b0f0f"),
	Text = Color3.fromHex("#f6e9e9"),
	Placeholder = Color3.fromHex("#8d6a6a"),
	Button = Color3.fromHex("#c81e1e"),
	Icon = Color3.fromHex("#ff4d4d"),
	Toggle = Color3.fromHex("#e11d1d"),
	Slider = Color3.fromHex("#ff3b3b"),
}

pcall(function()
	WindUI:AddTheme(MK4_RED)
	WindUI:SetTheme("MK4 Red")
end)

--=====================================================================
-- 12. INTERFACE
--=====================================================================
local Window = WindUI:CreateWindow({
	Title = "MK4 Hubx",
	Icon = "grip",
	Author = "MK4 | Blox Fruits",
	Folder = "MK4Hubx",
	Size = UDim2.fromOffset(660, 540),
	Theme = "MK4 Red",
	Transparency = 0.1,
	SideBarWidth = 185,
	User = { Enabled = true, Anonymous = true },
})

if not Window then
	return warn("[MK4 Hubx] Nao foi possivel criar a janela (outra instancia da WindUI aberta).")
end

local FarmTab = Window:Tab({ Title = "Farm", Icon = "swords" })
local EventTab = Window:Tab({ Title = "Events", Icon = "flame" })
local ChestTab = Window:Tab({ Title = "Bau", Icon = "package" })
local FruitTab = Window:Tab({ Title = "Frutas", Icon = "apple" })
local UtilTab = Window:Tab({ Title = "Utilitarios", Icon = "settings" })

-- ---------------------------- FARM ----------------------------
local FarmSection = FarmTab:Section({ Title = "Auto Farm" })

FarmSection:Toggle({
	Title = "Auto Farm",
	Desc = "Ataca automaticamente o alvo escolhido",
	Value = false,
	Callback = function(state)
		Config.Farm.Enabled = state
		notify("Auto Farm", state and "Ligado" or "Desligado", state and "play" or "pause", 3)
	end,
})

FarmSection:Toggle({
	Title = "Puxar Mobs (Magnet)",
	Desc = "Traz todos os NPCs do raio pra perto do player",
	Value = true,
	Callback = function(state)
		Config.Farm.Pull = state
	end,
})

FarmSection:Slider({
	Title = "Raio do magnet",
	Step = 25,
	Value = { Min = 50, Max = 3000, Default = 600 },
	Callback = function(value)
		Config.Farm.PullRadius = value
	end,
})

FarmSection:Slider({
	Title = "Distancia do agrupamento",
	Step = 1,
	Value = { Min = 3, Max = 25, Default = 6 },
	Callback = function(value)
		Config.Farm.PullDistance = value
	end,
})

FarmSection:Toggle({
	Title = "Kill Aura",
	Desc = "Bate em todos os mobs ao redor sem se mover",
	Value = true,
	Callback = function(state)
		Config.Farm.KillAura = state
	end,
})

FarmSection:Slider({
	Title = "Raio da Kill Aura",
	Step = 5,
	Value = { Min = 10, Max = 300, Default = 40 },
	Callback = function(value)
		Config.Farm.AuraRadius = value
	end,
})

FarmSection:Button({
	Title = "Puxar todos agora",
	Desc = "Uma vez, sem precisar do auto farm ligado",
	Callback = function()
		local pulled = pullMobs()
		notify("Magnet", ("%d NPCs puxados"):format(pulled), "magnet", 4)
	end,
})

FarmSection:Dropdown({
	Title = "Modo",
	Values = { "Mais proximo", "Mob especifico" },
	Value = "Mais proximo",
	Callback = function(option)
		Config.Farm.Mode = option
	end,
})

local mobNames = { "Nenhum" }
for _, mob in ipairs(collectMobs()) do
	if not table.find(mobNames, mob.Name) then
		mobNames[#mobNames + 1] = mob.Name
	end
end

local mobDropdown
mobDropdown = FarmSection:Dropdown({
	Title = "Mob",
	Desc = "Use 'Atualizar lista' se o mob nao aparecer",
	Values = mobNames,
	Value = "Nenhum",
	Callback = function(option)
		Config.Farm.Mob = option == "Nenhum" and "" or option
	end,
})

FarmSection:Button({
	Title = "Atualizar lista de mobs",
	Callback = function()
		local names = { "Nenhum" }
		for _, mob in ipairs(collectMobs()) do
			if not table.find(names, mob.Name) then
				names[#names + 1] = mob.Name
			end
		end
		pcall(function()
			mobDropdown:Refresh(names)
		end)
		notify("Mobs", ("%d mobs encontrados"):format(#names - 1), "refresh-cw", 4)
	end,
})

FarmSection:Slider({
	Title = "Raio de busca",
	Step = 10,
	Value = { Min = 50, Max = 2000, Default = 300 },
	Callback = function(value)
		Config.Farm.Radius = value
	end,
})

FarmSection:Slider({
	Title = "Velocidade do teleporte",
	Step = 5,
	Value = { Min = 20, Max = 400, Default = 130 },
	Callback = function(value)
		Config.Farm.Speed = value
	end,
})

FarmSection:Slider({
	Title = "Delay de ataque",
	Desc = "Menor = mais rapido",
	Step = 0.01,
	Value = { Min = 0.05, Max = 1, Default = 0.15 },
	Callback = function(value)
		Config.Farm.AttackDelay = value
	end,
})

FarmSection:Toggle({
	Title = "Fast Attack",
	Value = true,
	Callback = function(state)
		Config.Farm.FastAttack = state
	end,
})

FarmSection:Toggle({
	Title = "Auto Buso Haki",
	Desc = "Reinvoca o Busoshoku a cada 2s",
	Value = false,
	Callback = function(state)
		Config.Farm.AutoBuso = state
	end,
})

local CombatSection = FarmTab:Section({ Title = "Combate" })

CombatSection:Dropdown({
	Title = "Metodo de ataque",
	Desc = "Auto = ativa a arma + clique virtual (mais confiavel)",
	Values = { "Auto (todos)", "CommF Attack", "Tool:Activate", "Clique virtual" },
	Value = "Auto (todos)",
	Callback = function(option)
		Config.Farm.AttackMethod = option
	end,
})

CombatSection:Toggle({
	Title = "Combat tweak (ataque rapido real)",
	Desc = "Ajusta o CombatFramework: cooldown 0, increment e hitbox",
	Value = true,
	Callback = function(state)
		Config.Farm.CombatTweak = state
	end,
})

CombatSection:Slider({
	Title = "Increment",
	Desc = "Quantos hits por ativacao o CombatFramework manda",
	Step = 1,
	Value = { Min = 1, Max = 20, Default = 4 },
	Callback = function(value)
		Config.Farm.AttackIncrement = value
	end,
})

CombatSection:Slider({
	Title = "Hitbox",
	Desc = "Alcance do golpe",
	Step = 10,
	Value = { Min = 30, Max = 500, Default = 150 },
	Callback = function(value)
		Config.Farm.HitboxMagnitude = value
	end,
})

CombatSection:Toggle({
	Title = "Auto Equip",
	Desc = "Equipa arma da mochila se nenhuma estiver na mao",
	Value = true,
	Callback = function(state)
		Config.Farm.AutoEquip = state
	end,
})

CombatSection:Button({
	Title = "Testar ataque",
	Desc = "Ataca o mob mais proximo uma vez (conferir no jogo)",
	Callback = function()
		local mob = nearestMob(Config.Farm.Radius)
		if mob then
			attack(mob.Root.Position)
			notify("Combate", "Ataque enviado em " .. mob.Name .. " (metodo: " .. Config.Farm.AttackMethod .. ")", "swords", 4)
		else
			notify("Combate", "Nenhum mob atacavel no raio", "alert-triangle", 4)
		end
	end,
})

local QuestSection = FarmTab:Section({ Title = "Quest" })

QuestSection:Toggle({
	Title = "Auto Quest",
	Desc = "Mantem a quest sempre iniciada (loop)",
	Value = false,
	Callback = function(state)
		Config.Farm.AutoQuest = state
	end,
})

QuestSection:Toggle({
	Title = "Usar GetBestQuestNPC",
	Desc = "Pede ao servidor a melhor quest do nivel",
	Value = true,
	Callback = function(state)
		Config.Farm.UseBestQuest = state
	end,
})

QuestSection:Dropdown({
	Title = "Quest",
	Desc = "ID usado no StartQuest (fallback)",
	Values = {
		"BanditQuest1",
		"MonkeyQuest1",
		"PirateQuest1",
		"MarineQuest1",
		"MarineQuest2",
		"BanditQuest2",
		"SnowQuest1",
		"JungleQuest1",
		"SkyQuest1",
		"FountainQuest1",
		"CursedShipQuest1",
		"KingdomQuest1",
	},
	Value = "BanditQuest1",
	Callback = function(option)
		Config.Farm.QuestId = option
	end,
})

QuestSection:Slider({
	Title = "Nivel da quest",
	Step = 1,
	Value = { Min = 1, Max = 3000, Default = 1 },
	Callback = function(value)
		Config.Farm.QuestLevel = value
	end,
})

QuestSection:Button({
	Title = "Iniciar quest agora",
	Callback = function()
		startQuest()
		notify("Quest", "StartQuest enviado", "check", 4)
	end,
})

QuestSection:Button({
	Title = "Abandonar quest",
	Callback = function()
		invoke("AbandonQuest")
		notify("Quest", "Quest abandonada", "x", 3)
	end,
})

-- ---------------------------- EVENTS ----------------------------
local EventSection = EventTab:Section({ Title = "Auto Events" })
EventSection:Paragraph({
	Title = "Loop de eventos",
	Desc = "O hub procura os mobs do evento no mapa e engaja automaticamente enquanto o toggle estiver ligado.",
})

for _, id in ipairs({ "SeaBeast", "Elite", "Factory", "CursedShip", "GhostShip", "DoughKing", "Darkbeard", "Kitsune" }) do
	local data = EVENT_TARGETS[id]
	EventSection:Toggle({
		Title = data.label,
		Desc = "Procurar e atacar automaticamente",
		Value = false,
		Callback = function(state)
			Config.Events[id] = state
			if state then
				Config.Farm.EventsEnabled = true
			end
		end,
	})
end

local SummonSection = EventTab:Section({ Title = "Invocar / Iniciar" })

SummonSection:Button({
	Title = "Invocar Darkbeard",
	Desc = "Precisa do Fist of Darkness",
	Callback = function()
		invoke("Darkbeard", "Summon")
		fireRemote("Darkbeard")
		notify("Darkbeard", "Invocacao enviada", "flame", 5)
	end,
})

SummonSection:Button({
	Title = "Invocar Dough King",
	Callback = function()
		invoke("DoughKing", "Summon")
		notify("Dough King", "Invocacao enviada", "flame", 5)
	end,
})

SummonSection:Button({
	Title = "Iniciar Factory Raid",
	Desc = "Precisa da chave da fabrica",
	Callback = function()
		invoke("FactoryRaid", "Start")
		fireOn(REMOTES.Raids, "Factory")
		notify("Factory", "Tentativa de inicio enviada", "factory", 5)
	end,
})

SummonSection:Button({
	Title = "Iniciar Raid (Remotes.Raids)",
	Desc = "Usa o RemoteEvent Raids do jogo",
	Callback = function()
		local ok = fireOn(REMOTES.Raids)
		notify("Raids", ok and "Raids:FireServer() enviado" or "Remote Raids nao encontrado", "ship", 5)
	end,
})

SummonSection:Button({
	Title = "Entrar na Cursed Ship",
	Callback = function()
		invoke("CursedShip", "Enter")
		notify("Cursed Ship", "Tentativa de entrada enviada", "ship", 5)
	end,
})

SummonSection:Button({
	Title = "Ir para Ghost Ship",
	Callback = function()
		invoke("GhostShip", "Enter")
		notify("Ghost Ship", "Tentativa de entrada enviada", "ship", 5)
	end,
})

-- ---------------------------- BAU ----------------------------
local ChestSection = ChestTab:Section({ Title = "Auto Bau" })

ChestSection:Toggle({
	Title = "Auto Coletar Baus",
	Desc = "Loop continuo: voa ate os baus e coleta",
	Value = false,
	Callback = function(state)
		Config.Chest.Enabled = state
		if state then
			refreshChests(true)
			notify("Auto Bau", ("Ligado - %d baus no mapa"):format(#chestCache), "package", 4)
		end
	end,
})

ChestSection:Toggle({
	Title = "Usar Remotes.Chest",
	Desc = "Dispara o remote oficial de bau alem do touch",
	Value = true,
	Callback = function(state)
		Config.Chest.UseRemote = state
	end,
})

ChestSection:Toggle({
	Title = "Teleporte instantaneo",
	Desc = "Recomendado: alcanca baus longe sem cair no caminho",
	Value = true,
	Callback = function(state)
		Config.Chest.Instant = state
	end,
})

ChestSection:Slider({
	Title = "Raio de busca",
	Step = 10,
	Value = { Min = 50, Max = 3000, Default = 500 },
	Callback = function(value)
		Config.Chest.Radius = value
	end,
})

ChestSection:Slider({
	Title = "Velocidade",
	Step = 5,
	Value = { Min = 20, Max = 400, Default = 170 },
	Callback = function(value)
		Config.Chest.Speed = value
	end,
})

ChestSection:Slider({
	Title = "Delay entre baus",
	Step = 0.05,
	Value = { Min = 0.05, Max = 2, Default = 0.15 },
	Callback = function(value)
		Config.Chest.Delay = value
	end,
})

ChestSection:Button({
	Title = "Escanear baus",
	Callback = function()
		refreshChests(true)
		notify("Auto Bau", ("%d baus encontrados"):format(#chestCache), "search", 4)
	end,
})

ChestSection:Button({
	Title = "Coletar o mais proximo",
	Callback = function()
		local chest = nearestChest(Config.Chest.Radius)
		if chest then
			collectChest(chest)
		else
			notify("Auto Bau", "Nenhum bau no raio configurado", "alert-triangle", 4)
		end
	end,
})

-- ---------------------------- FRUTAS ----------------------------
local FruitCollect = FruitTab:Section({ Title = "Auto Frutas" })

FruitCollect:Toggle({
	Title = "Auto Coletar Frutas",
	Desc = "Loop continuo de coleta",
	Value = false,
	Callback = function(state)
		Config.Fruit.Enabled = state
	end,
})

FruitCollect:Toggle({
	Title = "Avisar no canto da tela",
	Value = true,
	Callback = function(state)
		Config.Fruit.Notify = state
	end,
})

FruitCollect:Slider({
	Title = "Velocidade",
	Step = 5,
	Value = { Min = 20, Max = 400, Default = 140 },
	Callback = function(value)
		Config.Fruit.Speed = value
	end,
})

FruitCollect:Button({
	Title = "Escanear frutas no chao",
	Callback = function()
		local fruits = scanFruits()
		notify("Frutas", ("%d frutas no chao"):format(#fruits), "apple", 4)
	end,
})

local RollSection = FruitTab:Section({ Title = "Rolar / Comprar Frutas" })

RollSection:Toggle({
	Title = "Auto Rolar Frutas (Cousin)",
	Desc = "Loop de compra ate achar uma fruta desejada",
	Value = false,
	Callback = function(state)
		Config.Roll.Enabled = state
		if state then
			notify("Rolagem", "Ligado - comprando frutas aleatorias", "dice-5", 4)
		end
	end,
})

RollSection:Slider({
	Title = "Beli minimo",
	Step = 50000,
	Value = { Min = 0, Max = 50000000, Default = 1000000 },
	Callback = function(value)
		Config.Roll.MinBeli = value
	end,
})

RollSection:Dropdown({
	Title = "Frutas desejadas",
	Desc = "Para quando encontrar uma dessas",
	Values = {
		"Kitsune",
		"Leopard",
		"Dough",
		"Dragon",
		"Yeti",
		"Gas",
		"Venom",
		"Shadow",
		"Control",
		"Spirit",
		"Mammoth",
		"T-Rex",
		"Buddha",
		"Portal",
		"Rumble",
	},
	Multi = true,
	Value = {},
	Callback = function(option)
		Config.Roll.Wanted = {}
		if type(option) == "table" then
			for _, name in ipairs(option) do
				Config.Roll.Wanted[name] = true
			end
		elseif type(option) == "string" then
			Config.Roll.Wanted[option] = true
		end
	end,
})

RollSection:Button({
	Title = "Comprar 1 fruta aleatoria agora",
	Callback = function()
		-- usa GetFruitData pra tentar mostrar info da fruta do vendedor
		pcall(function()
			invokeOn(REMOTES.GetFruitData, "Cousin")
		end)
		local fruit = buyRandomFruit()
		notify("Rolagem", fruit and ("Saiu: " .. fruit) or "Compra nao concluida (Beli insuficiente?)", "dice-5", 5)
	end,
})

RollSection:Toggle({
	Title = "Auto Reroll (Blackbeard)",
	Desc = "Precisa do reward do Blackbeard liberado",
	Value = false,
	Callback = function(state)
		Config.Roll.Reroll = state
	end,
})

RollSection:Button({
	Title = "Testar SpinGacha",
	Desc = "Dispara RE/SpinGacha (experimental)",
	Callback = function()
		local ok = fireOn(REMOTES.SpinGacha)
		notify("SpinGacha", ok and "Evento enviado" or "SpinGacha nao encontrado", "dice-5", 5)
	end,
})

-- ---------------------------- UTILITARIOS ----------------------------
local UtilSection = UtilTab:Section({ Title = "Teleporte" })

local function playerNames()
	local names = {}
	for _, player in ipairs(Players:GetPlayers()) do
		if player ~= LP then
			names[#names + 1] = player.Name
		end
	end
	if #names == 0 then
		names[1] = "Nenhum"
	end
	return names
end

local targetPlayer = "Nenhum"
local playerDropdown
playerDropdown = UtilSection:Dropdown({
	Title = "Jogador",
	Values = playerNames(),
	Value = "Nenhum",
	Callback = function(option)
		targetPlayer = option
	end,
})

UtilSection:Button({
	Title = "Atualizar jogadores",
	Callback = function()
		pcall(function()
			playerDropdown:Refresh(playerNames())
		end)
	end,
})

UtilSection:Button({
	Title = "Teleportar para o jogador",
	Callback = function()
		local player = Players:FindFirstChild(targetPlayer)
		local hrp = getHRP()
		if player and player.Character and player.Character:FindFirstChild("HumanoidRootPart") and hrp then
			hrp.CFrame = player.Character.HumanoidRootPart.CFrame * CFrame.new(0, 3, 5)
		else
			notify("Teleporte", "Jogador invalido", "alert-triangle", 4)
		end
	end,
})

UtilSection:Button({
	Title = "Ir para o mob mais proximo",
	Callback = function()
		local mob = nearestMob(Config.Farm.Radius)
		if mob then
			moveTo(mob.Root.Position + Vector3.new(0, 3, 0), Config.Farm.Speed)
		else
			notify("Teleporte", "Nenhum mob no raio", "alert-triangle", 4)
		end
	end,
})

UtilSection:Button({
	Title = "Voltar ao spawn",
	Callback = function()
		local spawn = Workspace:FindFirstChildOfClass("SpawnLocation")
		local hrp = getHRP()
		if spawn and hrp then
			hrp.CFrame = spawn.CFrame + Vector3.new(0, 3, 0)
		end
	end,
})

local ServerSection = UtilTab:Section({ Title = "Servidor" })

ServerSection:Button({
	Title = "Server Hop",
	Callback = serverHop,
})

ServerSection:Button({
	Title = "Reconectar",
	Desc = "Usa Remotes.DoRejoin quando disponivel",
	Callback = rejoin,
})

ServerSection:Toggle({
	Title = "Anti-AFK",
	Value = true,
	Callback = function(state)
		Config.Misc.AntiAfk = state
		applyAntiAfk()
	end,
})

local ThemeSection = UtilTab:Section({ Title = "Tema" })

local themeNames = { "MK4 Red" }
pcall(function()
	for name in pairs(WindUI:GetThemes()) do
		if not table.find(themeNames, name) then
			themeNames[#themeNames + 1] = name
		end
	end
end)

ThemeSection:Dropdown({
	Title = "Tema",
	Desc = "MK4 Red = vermelho / preto",
	Values = themeNames,
	Value = "MK4 Red",
	Callback = function(option)
		pcall(function()
			Window:SetTheme(option)
		end)
	end,
})

local DebugSection = UtilTab:Section({ Title = "Debug / Remote Spy" })

DebugSection:Toggle({
	Title = "Remote Spy",
	Desc = "Printa os remotes usados no console (F9)",
	Value = false,
	Callback = function(state)
		if state and not installRemoteSpy() then
			return
		end
		spyEnabled = state
		if state then
			notify("Remote Spy", "Ligado - veja o console (F9)", "terminal", 5)
		end
	end,
})

DebugSection:Button({
	Title = "Remotes detectados",
	Desc = "Lista o que o dump confirmou e o que existe agora",
	Callback = function()
		for name, remote in pairs(REMOTES) do
			print(("[MK4 Hubx] %s: %s"):format(name, remote and tostring(remote:GetFullName()) or "AUSENTE"))
		end
		if LoopErrors and next(LoopErrors) then
			for name, count in pairs(LoopErrors) do
				print(("[MK4 Hubx] loop %s: %d erros"):format(name, count))
			end
		end
		notify("MK4 Hubx", "Lista impressa no console (F9)", "terminal", 4)
	end,
})

DebugSection:Button({
	Title = "Diagnostico de combate",
	Desc = "Mostra arma equipada e se o CombatFramework foi achado",
	Callback = function()
		local tool = getWeapon()
		print("[MK4 Hubx] arma equipada:", tool and tool.Name or "NENHUMA")
		print("[MK4 Hubx] CombatFramework:", getCombatController() and "OK (tweak ativo)" or "NAO ENCONTRADO")
		print("[MK4 Hubx] metodo de ataque:", Config.Farm.AttackMethod)
		print("[MK4 Hubx] executor tem getreg/getfenv:", tostring(getreg ~= nil), tostring(getfenv ~= nil))
		print("[MK4 Hubx] mobs atacaveis no mapa:", #collectMobs(true))
		notify("MK4 Hubx", "Diagnostico impresso no console (F9)", "terminal", 5)
	end,
})

DebugSection:Button({
	Title = "Estado do hub",
	Callback = function()
		print("[MK4 Hubx] Farm:", Config.Farm.Enabled, "Pull:", Config.Farm.Pull, "Aura:", Config.Farm.KillAura)
		print("[MK4 Hubx] Bau:", Config.Chest.Enabled, "Frutas:", Config.Fruit.Enabled, "Roll:", Config.Roll.Enabled)
		print("[MK4 Hubx] Beli:", getBeli())
		notify("MK4 Hubx", "Estado impresso no console (F9)", "terminal", 4)
	end,
})

DebugSection:Button({
	Title = "Descarregar hub",
	Desc = "Para todos os loops e fecha a interface",
	Callback = function()
		for name in pairs(Loops) do
			Loops[name] = nil
		end
		Config.Farm.Enabled = false
		Config.Chest.Enabled = false
		Config.Fruit.Enabled = false
		Config.Roll.Enabled = false
		Config.Roll.Reroll = false
		for id in pairs(Config.Events) do
			Config.Events[id] = false
		end
		if antiAfkConn then
			pcall(function()
				antiAfkConn:Disconnect()
			end)
		end
		pcall(function()
			Window:Destroy()
		end)
		print("[MK4 Hubx] Hub descarregado.")
	end,
})

--=====================================================================
-- 13. START
--=====================================================================
notify("MK4 Hubx", "v2 carregado - tema vermelho, magnet e loops ativos", "check-check", 6)
