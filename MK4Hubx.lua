--[[
=====================================================================
   MK4 HUBX v5  |  Blox Fruits  |  WindUI  |  Sem Key
---------------------------------------------------------------------
   Tema: vermelho / preto (WindUI:AddTheme)
   Tabs: Farm, Events, Bau, Frutas, Utilitarios

   v7 (dados reais do MK4Dump + scripts abertos de 2026): o dano nao sai
     mais por RE/RegisterHit. O cliente manda RE/RegisterAttack e um pacote
     criptografado (ReplicatedStorage.Util.<id>) gerado pelo CombatFramework.
     A kill aura/farm agora chamam o golpe do proprio jogo
     (activeController:attack()) com o Mouse apontado pro NPC, e um hook
     conta os hits reais pra voce ver no diagnostico se o dano saiu.
   - MAGNET REMOVIDO. No lugar entrou a KILL AURA. v6 (dados reais do
     MK4Dump): o jogo nao usa mais RE/RegisterHit pra dano de M1, quem
     manda o hit e o proprio cliente (pacote criptografado). A aura
     aponta o Mouse pro NPC, registra o golpe (RE/RegisterAttack 0.5 +
     combo) e ativa a melee; o cliente manda o hit valido sozinho.
     RE/RegisterHit continua como opcao (arma/estilo antigo).
   - Auto Quest real por nivel e por mar: tabela de quests com id, index,
     mob e posicao (StartQuest usa id + index, nao o nivel), do script Axonic.
   - Bau no padrao do jogo: Chest1/2/3 (Prata/Ouro/Diamante), so baús com
     CanTouch ativo, TouchInterest, respawn por tipo e filtro de qualidade.
   - Tambem entraram: SetTeam Pirates, noclip opcional, auto detect de
     metodo de ataque e loops persistentes com auto-restart.

   Remotes usados:
     Remotes.CommF_ (StartQuest/Buso/Cousin/Attack)
     Remotes.CommE, Remotes.Chest, Remotes.Prompt, Remotes.Raids
     Modules.Net["RE/RegisterAttack"], ["RE/RegisterHit"]
     Modules.Net["RE/SpinGacha"], ["RE/ShopNetwork"], ["RE/GachaNetworkRE"]
     Remotes.DoRejoin, Remotes.GetBestQuestNPC, Remotes.GetFruitData

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
	-- Registro de dano no servidor (kill aura sem se mover)
	RegisterAttack = getRemote(ModulesNet, "RE/RegisterAttack")
		or getRemote(ModulesNet, "RegisterAttack")
		or getRemote(Remotes, "RegisterAttack"),
	RegisterHit = getRemote(ModulesNet, "RE/RegisterHit")
		or getRemote(ModulesNet, "RegisterHit")
		or getRemote(Remotes, "RegisterHit"),
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
		AutoDetect = true,
		Verified = false,
		DetectTries = 0,
		ServerHit = true,
		KillAura = true,
		AuraRadius = 250,
		-- Distancia que o servidor aceita por hit (o Axonic usa 65).
		-- Acima disso o RegisterHit e ignorado, por isso separamos.
		AuraRange = 65,
		-- Pega os NPCs fora do alcance levando o personagem ate eles
		-- por um tick e voltando pro lugar depois.
		AuraSweep = true,
		AuraSweepMax = 6,
		AuraAllParts = true,
		TeleportToMob = false,
		AutoQuest = false,
		QuestId = "BanditQuest1",
		QuestIndex = 1,
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
		OnlyActive = true,
		Grade = "Todos",
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
		Noclip = false,
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
local combatLib = nil
local lastCombatLookup = 0

local function getCombatController()
	-- O lib do combate guarda o activeController: pegando o lib o controller
	-- se renova sozinho quando o personagem respawna.
	if combatLib and combatLib.activeController then
		return combatLib.activeController
	end
	if combatController and combatController.Parent ~= nil then
		return combatController
	end
	if (os.clock() - lastCombatLookup) < 5 then
		return combatController
	end
	lastCombatLookup = os.clock()
	-- Caminho direto, igual aos scripts abertos que funcionam hoje:
	-- getupvalues(require(PlayerScripts.CombatFramework))[2].activeController
	do
		local ok, lib = pcall(function()
			local scripts = LP:FindFirstChild("PlayerScripts")
			local module = scripts and scripts:FindFirstChild("CombatFramework")
			module = module or ReplicatedStorage:FindFirstChild("CombatFramework")
			if not module or not module:IsA("ModuleScript") then
				return nil
			end
			local required = require(module)
			if type(required) == "table" then
				if required.activeController then
					return required
				end
				for _, value in pairs(required) do
					if type(value) == "table" and value.activeController then
						return value
					end
				end
				return nil
			end
			if type(required) ~= "function" or not debug or not debug.getupvalues then
				return nil
			end
			local list = debug.getupvalues(required)
			return type(list) == "table" and list[2] or nil
		end)
		if ok and type(lib) == "table" and lib.activeController then
			combatLib = lib
			return lib.activeController
		end
	end
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

-- Lista de estilos de luta do script Axonic. O servidor so aplica o dano
-- do RegisterHit quando existe uma melee/fighting style equipada; arma de
-- fogo, fruta ou nada equipado = hit ignorado (era o bug da aura).
local MELEE_STYLES = {
	["combat"] = true, ["dark step"] = true, ["black leg"] = true,
	["electric"] = true, ["water kung fu"] = true, ["dragon breath"] = true,
	["superhuman"] = true, ["death step"] = true, ["sharkman karate"] = true,
	["electric claw"] = true, ["dragon talon"] = true, ["godhuman"] = true,
	["sanguine art"] = true,
}

local function isMelee(tool)
	if not tool or not tool:IsA("Tool") then
		return false
	end
	if MELEE_STYLES[tool.Name:lower()] then
		return true
	end
	local category = ""
	pcall(function()
		category = tostring(tool:GetAttribute("WeaponType") or tool.ToolTip or "")
	end)
	category = category:lower()
	return category == "melee" or category == "fighting style"
end

local function equippedMelee()
	local char = LP.Character
	if not char then
		return nil
	end
	-- varre todas as Tools do personagem: as vezes sobra arma antiga junto
	for _, item in ipairs(char:GetChildren()) do
		if isMelee(item) then
			return item
		end
	end
	return nil
end

local lastEquipTry = 0
-- force = ignora o toggle (usado pelo RegisterHit, que precisa da melee)
local function ensureWeapon(force)
	if not (Config.Farm.AutoEquip or force) then
		return nil
	end
	local current = equippedMelee()
	if current then
		return current
	end
	if not force and (os.clock() - lastEquipTry) < 0.5 then
		return nil
	end
	lastEquipTry = os.clock()
	local _, _, hum = getChar()
	local backpack = LP:FindFirstChildOfClass("Backpack")
	if not hum or not backpack then
		return nil
	end
	local choice
	for _, item in ipairs(backpack:GetChildren()) do
		if isMelee(item) then
			choice = item
			if item.Name:lower() == "combat" then
				break
			end
		end
	end
	if not choice then
		return nil
	end
	pcall(function()
		hum:EquipTool(choice)
	end)
	return choice
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

-- serverHit/swingReal sao definidos na secao 5 (dependem da lista de
-- mobs); aqui so declaramos pra poder usar no executeAttack
local serverHit
local swingReal

-- Clique do jogo: ClickButton1 e o que os hubs de Blox Fruits usam
-- (Button1Down/Up puro costuma nao passar pelo input do CombatFramework).
local function virtualClick()
	local ok = pcall(function()
		VirtualUser:CaptureController()
		VirtualUser:ClickButton1(Vector2.new(0, 0))
	end)
	if ok then
		return
	end
	local camera = Workspace.CurrentCamera
	ok = pcall(function()
		VirtualUser:CaptureController()
		if camera then
			VirtualUser:Button1Down(Vector2.new(0, 0), camera.CFrame)
			VirtualUser:Button1Up(Vector2.new(0, 0), camera.CFrame)
		else
			VirtualUser:Button1Down(Vector2.new(0, 0))
			VirtualUser:Button1Up(Vector2.new(0, 0))
		end
	end)
	if not ok then
		pcall(function()
			mouse1click()
		end)
	end
end

local function executeAttack(method, position)
	ensureWeapon()
	boostCombat()
	if position then
		facePosition(position)
	end
	local label = method or Config.Farm.AttackMethod
	if label == "CombatFramework" then
		if swingReal then
			swingReal()
		end
	elseif label == "RegisterHit" then
		serverHit(Config.Farm.AuraRadius)
	elseif label == "CommF Attack" then
		invoke("Attack")
	elseif label == "Tool:Activate" then
		local tool = getWeapon()
		if tool then
			pcall(function()
				tool:Activate()
			end)
		end
	elseif label == "ClickButton1" then
		virtualClick()
	elseif label == "Mouse1click" then
		if mouse1click then
			pcall(mouse1click)
		else
			virtualClick()
		end
	else
		-- Auto: o caminho do jogo primeiro (o CombatFramework e quem manda o
		-- pacote de dano real); input/remotes ficam de reforco.
		local swung = swingReal and swingReal()
		local tool = getWeapon()
		if tool then
			pcall(function()
				tool:Activate()
			end)
		elseif not warnedNoWeapon then
			warnedNoWeapon = true
			notify("MK4 Hubx", "Equipe uma arma/fruta (ou ligue Auto Equip).", "alert-triangle", 6)
		end
		if not swung then
			virtualClick()
		end
		if (os.clock() % 1) < 0.25 then
			invoke("Attack")
		end
	end
end

local function attack(position)
	executeAttack(nil, position)
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
	-- Tudo que esta em Workspace.Enemies e mob de farm, aceita direto
	local enemiesFolder = Workspace:FindFirstChild("Enemies")
	if enemiesFolder and model:IsDescendantOf(enemiesFolder) then
		return true
	end
	-- Fora da pasta Enemies: ignora NPC interativo / ancorado
	for _, desc in ipairs(model:GetDescendants()) do
		if desc:IsA("ProximityPrompt") or desc:IsA("ClickDetector") or desc:IsA("Dialog") then
			return false
		end
	end
	local lower = model.Name:lower()
	for _, blocked in ipairs(NON_ATTACKABLE) do
		if lower:find(blocked, 1, true) then
			return false
		end
	end
	if hrp.Anchored then
		return false
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
			local f = filterName:lower()
			local name = mob.Name:lower()
			-- o jogo nomeia os mobs "Bandit" / "Bandit [12]" / "Bandit2"
			match = name == f or name:sub(1, #f + 1) == f .. " " or name:sub(1, #f) == f and tonumber(name:sub(#f + 1)) ~= nil
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

-- ---------------------------------------------------------------
-- Teste de ataque: dispara cada metodo e ve se a vida do mob cai.
-- Assim o hub descobre sozinho o que funciona no seu executor.
-- ---------------------------------------------------------------
local ATTACK_METHODS = { "CombatFramework", "RegisterHit", "ClickButton1", "Tool:Activate", "CommF Attack", "Mouse1click" }

local function testAttackMethod(method, mob)
	mob = mob or nearestMob(Config.Farm.Radius)
	if not mob then
		return nil
	end
	local before = mob.Humanoid.Health
	for _ = 1, 8 do
		if not mob.Model.Parent or mob.Humanoid.Health <= 0 then
			return true
		end
		executeAttack(method, mob.Root.Position)
		task.wait(0.15)
		if mob.Humanoid.Health < before then
			return true
		end
	end
	return false
end

local function detectAttackMethod()
	Config.Farm.DetectTries = (Config.Farm.DetectTries or 0) + 1
	for _, method in ipairs(ATTACK_METHODS) do
		local result = testAttackMethod(method)
		if result == nil then
			notify("Combate", "Nenhum mob atacavel perto para testar", "alert-triangle", 5)
			return nil
		elseif result then
			Config.Farm.AttackMethod = method
			Config.Farm.Verified = true
			notify("Combate", "Metodo que da dano: " .. method, "check", 8)
			return method
		end
	end
	notify("Combate", "Nenhum metodo tirou vida. Equipe uma arma (espada/ fruta) e tente de novo.", "alert-triangle", 8)
	return nil
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

-- Tipos de bau do jogo (do script Chest Farmer): Chest1 Prata,
-- Chest2 Ouro, Chest3 Diamante, cada um com seu respawn.
local CHEST_GRADES = {
	Chest1 = { label = "Prata", respawn = 180 },
	Chest2 = { label = "Ouro", respawn = 360 },
	Chest3 = { label = "Diamante", respawn = 720 },
}

local function chestGradeOf(name)
	for key, data in pairs(CHEST_GRADES) do
		if name:find(key, 1, true) then
			return data.label, data.respawn
		end
	end
	return "Comum", 180
end

-- Bau real do Blox Fruits: Part/Model "Chest" com TouchInterest (ou
-- prompt) dentro de workspace.Map. Sem isso e so decoracao do mapa.
local function chestIsReal(instance)
	return instance:FindFirstChild("TouchInterest") ~= nil
		or instance:FindFirstChild("TouchTransmitter") ~= nil
		or instance:FindFirstChildOfClass("ProximityPrompt") ~= nil
		or instance:FindFirstChildOfClass("ClickDetector") ~= nil
end

local function scanChests()
	local found = {}
	local seen = {}

	local function consider(desc)
		if seen[desc] or not isChestName(desc.Name) then
			return
		end
		if not (desc:IsA("Model") or desc:IsA("BasePart")) then
			return
		end
		local part = desc:IsA("BasePart") and desc
			or desc.PrimaryPart
			or desc:FindFirstChildWhichIsA("BasePart")
		if not part then
			return
		end
		seen[desc] = true
		-- CanTouch e a fonte de verdade: baú ja coletado fica com
		-- CanTouch = false e nao deve ser tentado de novo
		local active = true
		pcall(function()
			if part.CanTouch ~= nil then
				active = part.CanTouch
			end
		end)
		local grade, respawn = chestGradeOf(desc.Name)
		found[#found + 1] = {
			Instance = desc,
			Part = part,
			Real = chestIsReal(desc) or chestIsReal(part),
			Active = active,
			Grade = grade,
			Respawn = respawn,
		}
	end

	local function scan(root)
		local ok, descendants = pcall(function()
			return root:GetDescendants()
		end)
		if not ok then
			return
		end
		for _, desc in ipairs(descendants) do
			consider(desc)
		end
	end

	local map = Workspace:FindFirstChild("Map")
	if map then
		scan(map)
	end
	for _, child in ipairs(Workspace:GetChildren()) do
		if child ~= map and child ~= LP.Character then
			if (child:IsA("Folder") or child:IsA("Model"))
				and child.Name ~= "Characters"
				and child.Name ~= "Enemies"
				and child.Name ~= "Effects" then
				scan(child)
			else
				consider(child)
			end
		end
	end

	table.sort(found, function(a, b)
		return a.Real and not b.Real
	end)
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
	local anyReal = false
	for _, entry in ipairs(chestCache) do
		if entry.Real then
			anyReal = true
			break
		end
	end
	for _, entry in ipairs(chestCache) do
		local part = entry.Part
		local gradeOk = Config.Chest.Grade == "Todos" or entry.Grade == Config.Chest.Grade
		local activeOk = (not Config.Chest.OnlyActive) or entry.Active ~= false
		if part and part.Parent and part:IsDescendantOf(Workspace)
			and not onCooldown(chestCooldown, entry.Instance, 8)
			and (entry.Real or not anyReal)
			and gradeOk and activeOk then
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
-- 5. COMBATE / KILL AURA DE SERVIDOR
--=====================================================================
-- Tecnica do auto farm Axonic: RE/RegisterAttack registra o golpe e
-- RE/RegisterHit recebe a lista {mob, part} de cada parte de cada mob
-- dentro do raio. O dano e aplicado pelo servidor, entao da pra matar
-- todos os NPCs do mapa sem mover o personagem um stud.
-- Contadores de diagnostico (visiveis em Utilitarios > Estado do hub)
local dbg = { attacks = 0, parts = 0, reason = "", sweeps = 0, sweepsSent = 0, m1 = 0, hits = 0, swings = 0, lastHit = 0 }

-- onlyName pode ser string (nome do mob, aceita "Bandit [12]") ou o
-- proprio Model do mob (usado pelo sweep).
local function matchesOnly(mob, onlyName)
	if not onlyName or onlyName == "" then
		return true
	end
	if typeof(onlyName) == "Instance" then
		return mob.Model == onlyName
	end
	if mob.Name == onlyName then
		return true
	end
	return mob.Name:sub(1, #onlyName + 2) == onlyName .. " ["
end

local function buildHitList(radius, onlyName)
	local hrp = getHRP()
	if not hrp then
		return nil, {}
	end
	-- o servidor valida a distancia de cada hit: passar disso e desperdicar
	local limit = math.min(radius or Config.Farm.AuraRadius, Config.Farm.AuraRange)
	local hits, primary, closest = {}, nil, math.huge
	for _, mob in ipairs(collectMobs()) do
		if mob.Humanoid.Health > 0 and matchesOnly(mob, onlyName) then
			local distance = (mob.Root.Position - hrp.Position).Magnitude
			if distance <= limit then
				if distance < closest then
					closest = distance
					primary = mob.Model:FindFirstChild("Head") or mob.Root
				end
				if Config.Farm.AuraAllParts then
					for _, part in ipairs(mob.Model:GetChildren()) do
						-- limite pra nao estourar o remote com uma lista gigante
						if part:IsA("BasePart") and #hits < 250 then
							hits[#hits + 1] = { mob.Model, part }
						end
					end
				else
					hits[#hits + 1] = { mob.Model, mob.Root }
				end
			end
		end
	end
	return primary, hits
end

--=====================================================================
-- 5.0 AURA COM O M1 DO PROPRIO JOGO (dados reais do MK4Dump)
--=====================================================================
-- O que o cliente manda quando voce bate de verdade (dump de 17/11):
--   Tool.EquipEvent:FireServer(true)
--   RE/RegisterAttack:FireServer(0.5, 1..4)      -- golpe + combo
--   Tool.RemoteEvent:FireServer(true) -> (Vector3) -> (false)
--   ReplicatedStorage.Util.536:FireServer(pacote, id, parte do NPC)
-- Esse ultimo e o que tira vida, e o pacote muda a cada golpe: nao da
-- pra forjar. Entao a aura nao forja nada: aponta o Mouse do jogo pro
-- NPC (Hit/Target), ativa a melee e deixa o cliente mandar o pacote
-- valido. E o mesmo caminho de um clique manual.
local mouseTarget = nil
local mouseHookOk = nil
local hitHookOk = nil
local warnedMouseHook = false
local comboIndex = 0

local function setMouseTarget(part)
	mouseTarget = part
end

local function installMouseHook()
	if mouseHookOk ~= nil then
		return mouseHookOk
	end
	if not hookmetamethod then
		mouseHookOk = false
		return false
	end
	local okMouse, mouse = pcall(function()
		return LP:GetMouse()
	end)
	if not okMouse or not mouse then
		mouseHookOk = false
		return false
	end
	local ok = pcall(function()
		local wrap = newcclosure or function(fn)
			return fn
		end
		local oldIndex
		oldIndex = hookmetamethod(game, "__index", wrap(function(self, key)
			if mouseTarget and self == mouse then
				if key == "Hit" then
					return CFrame.new(mouseTarget.Position)
				elseif key == "Target" then
					return mouseTarget
				end
			end
			return oldIndex(self, key)
		end))
	end)
	mouseHookOk = ok
	if not ok and not warnedMouseHook then
		warnedMouseHook = true
		notify("Kill Aura", "Executor sem hookmetamethod: aura manda so os remotes.", "alert-triangle", 8)
	end
	return ok
end

-- Golpe de verdade pelo CombatFramework do cliente. E o unico caminho que
-- gera o pacote de dano que o servidor aceita hoje (Util.<id>):
--   getupvalues(require(PlayerScripts.CombatFramework))[2].activeController:attack()
-- Os hubs abertos atuais (FastAttack, Avka24, HarashimaX) batem assim.
swingReal = function()
	local controller = getCombatController()
	if not controller then
		return false
	end
	pcall(function()
		controller.timeToNextAttack = -(math.huge ^ math.huge ^ math.huge)
		controller.attacking = false
		controller.blocking = false
		controller.focusStart = 0
		controller.increment = Config.Farm.AttackIncrement
		controller.hitboxMagnitude = Config.Farm.HitboxMagnitude
		if controller.humanoid then
			controller.humanoid.AutoRotate = true
		end
	end)
	local ok = pcall(function()
		controller:attack()
	end)
	if ok then
		dbg.swings = dbg.swings + 1
	end
	return ok
end

-- Conta os hits REAIS que o cliente manda depois do golpe (o pacote mora em
-- ReplicatedStorage.Util.<id>). Se dbg.hits sobe, o dano saiu; se fica
-- parado, o golpe nao chegou a ser validado pelo jogo.
local function installHitHook()
	if hitHookOk ~= nil then
		return hitHookOk
	end
	if not hookmetamethod or not getnamecallmethod then
		hitHookOk = false
		return false
	end
	local ok = pcall(function()
		local wrap = newcclosure or function(fn)
			return fn
		end
		local oldNamecall
		oldNamecall = hookmetamethod(game, "__namecall", wrap(function(self, ...)
			if getnamecallmethod() == "FireServer" then
				local nameOk, isHitRemote = pcall(function()
					local parent = self.Parent
					return parent ~= nil and (parent.Name == "Util" or self.Name == "RE/RegisterHit")
				end)
				if nameOk and isHitRemote then
					for _, arg in ipairs({ ... }) do
						if typeof(arg) == "Instance" then
							dbg.hits = dbg.hits + 1
							dbg.lastHit = os.clock()
							break
						end
					end
				end
			end
			return oldNamecall(self, ...)
		end))
	end)
	hitHookOk = ok
	return ok
end

-- Golpe real em um NPC: aponta o mouse, vira o personagem e chama o ataque
-- do CombatFramework (com input/remotes de reserva).
local function m1Attack(mob)
	local hrp = getHRP()
	if not hrp or not mob or not mob.Model.Parent or mob.Humanoid.Health <= 0 then
		return false
	end
	local tool = equippedMelee() or ensureWeapon(true)
	if not tool then
		dbg.reason = "sem melee"
		return false
	end
	local part = mob.Model:FindFirstChild("Head") or mob.Root
	setMouseTarget(part)
	-- o hitbox do M1 nasce na frente do personagem: virar e obrigatorio
	facePosition(part.Position)
	boostCombat()
	dbg.m1 = dbg.m1 + 1
	if swingReal() then
		dbg.reason = "combatframework"
		return true
	end
	-- Sem CombatFramework acessivel: caminho antigo (input + remotes)
	comboIndex = (comboIndex % 4) + 1
	fireOn(REMOTES.RegisterAttack, 0.5, comboIndex)
	local remote = tool:FindFirstChild("RemoteEvent")
	if remote then
		fireOn(remote, true)
		fireOn(remote, part.Position)
		fireOn(remote, false)
	end
	pcall(function()
		tool:Activate()
	end)
	virtualClick()
	dbg.reason = "input"
	return true
end

-- NPC vivo mais perto dentro de um raio
local function nearestAuraMob(limit)
	local hrp = getHRP()
	if not hrp then
		return nil
	end
	local best, bestDistance = nil, limit or Config.Farm.AuraRange
	for _, mob in ipairs(collectMobs()) do
		if mob.Humanoid.Health > 0 then
			local distance = (mob.Root.Position - hrp.Position).Magnitude
			if distance <= bestDistance then
				best, bestDistance = mob, distance
			end
		end
	end
	return best
end

-- Mede dano de verdade: bate 10x no NPC mais perto e compara o HP.
-- Imprime tambem os hits que o cliente mandou (prova de que o pacote saiu).
local function damageProbe()
	installMouseHook()
	installHitHook()
	local mob = nearestAuraMob(Config.Farm.AuraRadius) or nearestMob(Config.Farm.Radius)
	if not mob then
		notify("Motor de dano", "Nenhum NPC vivo por perto. Va ate um mob e teste de novo.", "alert-triangle", 7)
		return false
	end
	local tool = equippedMelee() or ensureWeapon(true)
	local controller = getCombatController()
	local before = mob.Humanoid.Health
	local hitsBefore, swingsBefore = dbg.hits, dbg.swings
	for _ = 1, 10 do
		if not mob.Model.Parent or mob.Humanoid.Health <= 0 then
			break
		end
		m1Attack(mob)
		task.wait(0.12)
	end
	task.wait(0.35)
	local after = before
	pcall(function()
		after = mob.Humanoid.Health
	end)
	local dealt = math.max(0, before - after)
	print(("[MK4 Hubx] NPC %s: %.0f -> %.0f (dano %.0f)"):format(mob.Name, before, after, dealt))
	print(("[MK4 Hubx] golpes: %d | hits que o cliente mandou: %d"):format(dbg.swings - swingsBefore, dbg.hits - hitsBefore))
	print(("[MK4 Hubx] melee: %s | CombatFramework: %s | mouse hook: %s"):format(
		tool and tool.Name or "NENHUMA",
		controller and "OK" or "NAO ACHADO",
		tostring(mouseHookOk)
	))
	notify(
		"Motor de dano",
		("%s: %s (dano %.0f, hits %d)"):format(mob.Name, dealt > 0 and "FUNCIONOU" or "nao tirou vida", dealt, dbg.hits - hitsBefore),
		dealt > 0 and "check" or "alert-triangle",
		10
	)
	return dealt > 0
end

-- Retorna ok, partes enviadas, motivo
serverHit = function(radius, onlyName)
	if not (REMOTES.RegisterAttack and REMOTES.RegisterHit) then
		dbg.reason = "sem remotes"
		return false, 0, dbg.reason
	end
	-- sem melee equipada o servidor descarta o hit: equipe antes de atirar
	if not equippedMelee() then
		ensureWeapon(true)
		if not equippedMelee() then
			dbg.reason = "sem melee"
			return false, 0, dbg.reason
		end
	end
	local primary, hits = buildHitList(radius or Config.Farm.AuraRadius, onlyName)
	if not primary or #hits == 0 then
		dbg.reason = "sem alvo"
		return true, 0, dbg.reason
	end
	fireOn(REMOTES.RegisterAttack, 0.0001)
	fireOn(REMOTES.RegisterHit, primary, hits)
	dbg.attacks = dbg.attacks + 1
	dbg.parts = dbg.parts + #hits
	dbg.reason = "ok"
	return true, #hits, "ok"
end

-- Mobs dentro do raio da aura mas fora do alcance aceito pelo servidor:
-- leva o personagem ate cada um por um tick, bate, e volta pro lugar.
local function sweepFarMobs()
	local hrp = getHRP()
	if not hrp then
		return 0
	end
	dbg.sweeps = dbg.sweeps + 1
	local home = hrp.CFrame
	local origin = hrp.Position
	local sent = 0
	local visited = 0
	for _, mob in ipairs(collectMobs()) do
		if visited >= Config.Farm.AuraSweepMax then
			break
		end
		if mob.Humanoid.Health > 0 then
			local distance = (mob.Root.Position - origin).Magnitude
			if distance > Config.Farm.AuraRange and distance <= Config.Farm.AuraRadius then
				visited = visited + 1
				local current = getHRP()
				if not current then
					break
				end
				pcall(function()
					current.CFrame = CFrame.new(mob.Root.Position + Vector3.new(0, 3, 0))
					-- garante que a validacao de distancia use a posicao nova
					current.Position = current.CFrame.Position
				end)
				-- deixa um frame pro servidor ver a posicao nova antes do golpe
				RunService.Heartbeat:Wait()
				if m1Attack(mob) then
					sent = sent + 1
				end
				if Config.Farm.ServerHit then
					local _, count = serverHit(Config.Farm.AuraRange, mob.Model)
					sent = sent + (count or 0)
				end
			end
		end
	end
	dbg.sweepsSent = dbg.sweepsSent + sent
	-- volta pro lugar de onde saiu
	local back = getHRP()
	if back then
		pcall(function()
			back.CFrame = home
		end)
	end
	return sent
end

local lastSweep = 0
local lastNoMelee = 0
local function killAura()
	installMouseHook()
	installHitHook()
	-- so mira no que o golpe do cliente alcanca (hitbox x alcance do servidor)
	local reach = math.min(Config.Farm.AuraRange, Config.Farm.HitboxMagnitude or 60)
	local mob = nearestAuraMob(reach)
	if mob then
		if not m1Attack(mob) and dbg.reason == "sem melee" and (os.clock() - lastNoMelee) > 20 then
			lastNoMelee = os.clock()
			notify("Kill Aura", "Nenhuma melee equipada. Ligue o Auto Equip ou equipe uma espada/estilo.", "alert-triangle", 8)
		end
		if Config.Farm.ServerHit then
			serverHit(Config.Farm.AuraRange, mob.Model)
		end
		return
	end
	-- Nada dentro do alcance que o servidor aceita: vai ate o NPC, bate e volta
	if Config.Farm.AuraSweep and (os.clock() - lastSweep) > 0.4 then
		lastSweep = os.clock()
		sweepFarMobs()
		return
	end
	-- Ultimo recurso: RegisterHit em tudo que esta no raio
	if Config.Farm.ServerHit then
		serverHit(Config.Farm.AuraRadius)
	end
end

-- keepGoing: funcao que decide se o combate continua
-- O farm de verdade precisa CHEGAR no mob: o M1 nasce no personagem, entao
-- longe do alvo nao existe dano nenhum. Alterna entre andar ate ele e bater.
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
	-- distancia em que o golpe encosta: o hitbox vai de ~30 a ~150 studs
	local reach = math.clamp((Config.Farm.HitboxMagnitude or 60) * 0.35, 8, 45)
	installHitHook()

	while active() and mob.Parent and mhum.Health > 0 and (os.clock() - started) < 25 do
		local hrp = getHRP()
		if not hrp then
			break
		end
		local distance = (mhrp.Position - hrp.Position).Magnitude
		if distance > reach then
			if Config.Farm.TeleportToMob or distance > 400 then
				pcall(function()
					hrp.CFrame = mhrp.CFrame * CFrame.new(0, 2, 3)
				end)
				task.wait(0.1)
			else
				-- tween na direcao do mob (bloqueia ate chegar, ~1s)
				local goal = mhrp.Position + (hrp.Position - mhrp.Position).Unit * reach * 0.6
				moveTo(goal + Vector3.new(0, 2, 0), Config.Farm.Speed)
			end
		end
		if Config.Farm.AutoBuso and (os.clock() - lastBuso) > 2 then
			lastBuso = os.clock()
			invoke("Buso")
		end
		m1Attack(target)
		if Config.Farm.ServerHit then
			serverHit(Config.Farm.AuraRange, mob)
		end
		task.wait(Config.Farm.FastAttack and Config.Farm.AttackDelay or 0.45)
	end
end

--=====================================================================
-- 5.1 QUESTS (tabela do Axonic: id, index, mob e posicao por nivel)
--=====================================================================
local SEA_BY_PLACE = {
	[2753915549] = "sea1", [85211729168715] = "sea1",
	[4442272183] = "sea2", [79091703265657] = "sea2",
	[7449423635] = "sea3", [100117331123089] = "sea3",
}

local QUESTS = {
	sea1 = {
		{ min = 1, max = 9, mob = "Bandit", id = "BanditQuest1", index = 1, position = Vector3.new(1045.96, 27.00, 1560.82) },
		{ min = 10, max = 14, mob = "Monkey", id = "JungleQuest", index = 1, position = Vector3.new(-1448.51, 67.85, 11.46) },
		{ min = 15, max = 29, mob = "Gorilla", id = "JungleQuest", index = 2, position = Vector3.new(-1129.88, 40.46, -525.42) },
		{ min = 30, max = 39, mob = "Pirate", id = "BuggyQuest1", index = 1, position = Vector3.new(-1103.51, 13.75, 3896.09) },
		{ min = 40, max = 59, mob = "Brute", id = "BuggyQuest1", index = 2, position = Vector3.new(-1140.08, 14.80, 4322.92) },
		{ min = 60, max = 74, mob = "Desert Bandit", id = "DesertQuest", index = 1, position = Vector3.new(924.79, 6.44, 4481.58) },
		{ min = 75, max = 89, mob = "Desert Officer", id = "DesertQuest", index = 2, position = Vector3.new(1608.28, 8.61, 4371.00) },
		{ min = 90, max = 99, mob = "Snow Bandit", id = "SnowQuest", index = 1, position = Vector3.new(1354.34, 87.27, -1393.94) },
		{ min = 100, max = 119, mob = "Snowman", id = "SnowQuest", index = 2, position = Vector3.new(1201.64, 144.57, -1550.06) },
		{ min = 120, max = 149, mob = "Chief Petty Officer", id = "MarineQuest2", index = 1, position = Vector3.new(-4881.23, 22.65, 4273.75) },
		{ min = 150, max = 174, mob = "Sky Bandit", id = "SkyQuest", index = 1, position = Vector3.new(-4953.20, 295.74, -2899.22) },
		{ min = 175, max = 189, mob = "Dark Master", id = "SkyQuest", index = 2, position = Vector3.new(-5259.84, 391.39, -2229.03) },
		{ min = 190, max = 209, mob = "Prisoner", id = "PrisonerQuest", index = 1, position = Vector3.new(5098.97, -0.32, 474.23) },
		{ min = 210, max = 249, mob = "Dangerous Prisoner", id = "PrisonerQuest", index = 2, position = Vector3.new(5654.56, 15.63, 866.29) },
		{ min = 250, max = 274, mob = "Toga Warrior", id = "ColosseumQuest", index = 1, position = Vector3.new(-1820.21, 51.68, -2740.66) },
		{ min = 275, max = 299, mob = "Gladiator", id = "ColosseumQuest", index = 2, position = Vector3.new(-1292.83, 56.38, -3339.03) },
		{ min = 300, max = 324, mob = "Military Soldier", id = "MagmaQuest", index = 1, position = Vector3.new(-5411.16, 11.08, 8454.29) },
		{ min = 325, max = 374, mob = "Military Spy", id = "MagmaQuest", index = 2, position = Vector3.new(-5802.86, 86.26, 8828.85) },
		{ min = 375, max = 399, mob = "Fishman Warrior", id = "FishmanQuest", index = 1, position = Vector3.new(60878.30, 18.48, 1543.75) },
		{ min = 400, max = 449, mob = "Fishman Commando", id = "FishmanQuest", index = 2, position = Vector3.new(61922.63, 18.48, 1493.93) },
		{ min = 450, max = 474, mob = "God's Guard", id = "SkyExp1Quest", index = 1, position = Vector3.new(-4710.04, 845.27, -1927.30) },
		{ min = 475, max = 524, mob = "Shanda", id = "SkyExp1Quest", index = 2, position = Vector3.new(-7678.48, 5566.40, -497.21) },
		{ min = 525, max = 549, mob = "Royal Squad", id = "SkyExp2Quest", index = 1, position = Vector3.new(-7624.25, 5658.13, -1467.35) },
		{ min = 550, max = 624, mob = "Royal Soldier", id = "SkyExp2Quest", index = 2, position = Vector3.new(-7836.75, 5645.66, -1790.62) },
		{ min = 625, max = 649, mob = "Galley Pirate", id = "FountainQuest", index = 1, position = Vector3.new(5551.02, 78.90, 3930.41) },
		{ min = 650, max = math.huge, mob = "Galley Captain", id = "FountainQuest", index = 2, position = Vector3.new(5441.95, 42.50, 4950.09) },
	},
	sea2 = {
		{ min = 700, max = 724, mob = "Raider", id = "Area1Quest", index = 1, position = Vector3.new(-728.32, 52.77, 2345.77) },
		{ min = 725, max = 774, mob = "Mercenary", id = "Area1Quest", index = 2, position = Vector3.new(-1004.32, 80.15, 1424.61) },
		{ min = 775, max = 799, mob = "Swan Pirate", id = "Area2Quest", index = 1, position = Vector3.new(1068.66, 137.61, 1322.10) },
		{ min = 800, max = 874, mob = "Factory Staff", id = "Area2Quest", index = 2, position = Vector3.new(73.07, 81.86, -27.47) },
		{ min = 875, max = 899, mob = "Marine Lieutenant", id = "MarineQuest3", index = 1, position = Vector3.new(-2821.37, 75.89, -3070.08) },
		{ min = 900, max = 949, mob = "Marine Captain", id = "MarineQuest3", index = 2, position = Vector3.new(-1861.23, 80.17, -3254.69) },
		{ min = 950, max = 974, mob = "Zombie", id = "ZombieQuest", index = 1, position = Vector3.new(-5657.77, 78.96, -928.68) },
		{ min = 975, max = 999, mob = "Vampire", id = "ZombieQuest", index = 2, position = Vector3.new(-6037.66, 32.18, -1340.65) },
		{ min = 1000, max = 1049, mob = "Snow Trooper", id = "SnowMountainQuest", index = 1, position = Vector3.new(549.14, 427.38, -5563.69) },
		{ min = 1050, max = 1099, mob = "Winter Warrior", id = "SnowMountainQuest", index = 2, position = Vector3.new(1142.74, 475.63, -5199.41) },
		{ min = 1100, max = 1124, mob = "Lab Subordinate", id = "IceSideQuest", index = 1, position = Vector3.new(-5707.47, 15.95, -4513.39) },
		{ min = 1125, max = 1174, mob = "Horned Warrior", id = "IceSideQuest", index = 2, position = Vector3.new(-6341.36, 15.95, -5723.16) },
		{ min = 1175, max = 1199, mob = "Magma Ninja", id = "FireSideQuest", index = 1, position = Vector3.new(-5449.67, 76.65, -5808.20) },
		{ min = 1200, max = 1249, mob = "Lava Pirate", id = "FireSideQuest", index = 2, position = Vector3.new(-5213.33, 49.73, -4701.45) },
		{ min = 1250, max = 1274, mob = "Ship Deckhand", id = "ShipQuest1", index = 1, position = Vector3.new(1206.06, 149.57, 33092.49) },
		{ min = 1275, max = 1299, mob = "Ship Engineer", id = "ShipQuest1", index = 2, position = Vector3.new(1036.78, 64.28, 33074.14) },
		{ min = 1300, max = 1324, mob = "Ship Steward", id = "ShipQuest2", index = 1, position = Vector3.new(1006.88, 149.01, 33366.95) },
		{ min = 1325, max = 1349, mob = "Ship Officer", id = "ShipQuest2", index = 2, position = Vector3.new(1182.53, 204.90, 33445.61) },
		{ min = 1350, max = 1374, mob = "Arctic Warrior", id = "FrostQuest", index = 1, position = Vector3.new(5966.24, 62.97, -6179.38) },
		{ min = 1375, max = 1424, mob = "Snow Lurker", id = "FrostQuest", index = 2, position = Vector3.new(5407.07, 69.19, -6880.88) },
		{ min = 1425, max = 1450, mob = "Sea Soldier", id = "ForgottenQuest", index = 1, position = Vector3.new(-2898.78, 27.01, -9776.41) },
		{ min = 1450, max = math.huge, mob = "Water Fighter", id = "ForgottenQuest", index = 2, position = Vector3.new(-3309.07, 325.17, -10422.44) },
	},
	sea3 = {
		{ min = 1500, max = 1524, mob = "Pirate Millionaire", id = "PiratePortQuest", index = 1, position = Vector3.new(-246.00, 47.31, 5584.10) },
		{ min = 1525, max = 1574, mob = "Pistol Billionaire", id = "PiratePortQuest", index = 2, position = Vector3.new(-187.33, 86.24, 6013.51) },
		{ min = 1575, max = 1599, mob = "Dragon Crew Warrior", id = "DragonCrewQuest", index = 1, position = Vector3.new(7014.84, 196.36, -1024.29) },
		{ min = 1600, max = 1624, mob = "Dragon Crew Archer", id = "DragonCrewQuest", index = 2, position = Vector3.new(6792.60, 535.42, 454.47) },
		{ min = 1625, max = 1649, mob = "Hydra Enforcer", id = "VenomCrewQuest", index = 1, position = Vector3.new(4704.02, 1043.86, 679.61) },
		{ min = 1650, max = 1699, mob = "Venomous Assailant", id = "VenomCrewQuest", index = 2, position = Vector3.new(4731.27, 1090.17, 1078.17) },
		{ min = 1700, max = 1724, mob = "Marine Commodore", id = "MarineTreeIsland", index = 1, position = Vector3.new(2286.00, 73.13, -7159.80) },
		{ min = 1725, max = 1774, mob = "Marine Rear Admiral", id = "MarineTreeIsland", index = 2, position = Vector3.new(3656.77, 160.52, -7001.59) },
		{ min = 1775, max = 1824, mob = "Fishman Raider", id = "DeepForestIsland3", index = 1, position = Vector3.new(-10407.52, 331.76, -8368.51) },
		{ min = 1825, max = 1849, mob = "Forest Pirate", id = "DeepForestIsland", index = 1, position = Vector3.new(-13274.47, 332.37, -7769.58) },
		{ min = 1850, max = 1899, mob = "Mythological Pirate", id = "DeepForestIsland", index = 2, position = Vector3.new(-13680.60, 501.08, -6991.18) },
		{ min = 1900, max = 1924, mob = "Jungle Pirate", id = "DeepForestIsland2", index = 1, position = Vector3.new(-12256.16, 331.73, -10485.83) },
		{ min = 1925, max = 1974, mob = "Musketeer Pirate", id = "DeepForestIsland2", index = 2, position = Vector3.new(-13457.90, 391.54, -9859.17) },
		{ min = 1975, max = 1999, mob = "Reborn Skeleton", id = "HauntedQuest1", index = 1, position = Vector3.new(-8763.72, 165.72, 6159.86) },
		{ min = 2000, max = 2024, mob = "Living Zombie", id = "HauntedQuest1", index = 2, position = Vector3.new(-10144.13, 138.62, 5838.08) },
		{ min = 2025, max = 2049, mob = "Demonic Soul", id = "HauntedQuest2", index = 1, position = Vector3.new(-9505.87, 172.10, 6158.99) },
		{ min = 2050, max = 2074, mob = "Posessed Mummy", id = "HauntedQuest2", index = 2, position = Vector3.new(-9582.02, 6.25, 6205.47) },
		{ min = 2075, max = 2099, mob = "Peanut Scout", id = "NutsIslandQuest", index = 1, position = Vector3.new(-2143.24, 47.72, -10029.99) },
		{ min = 2100, max = 2124, mob = "Peanut President", id = "NutsIslandQuest", index = 2, position = Vector3.new(-1859.35, 38.10, -10422.42) },
		{ min = 2125, max = 2149, mob = "Ice Cream Chef", id = "IceCreamIslandQuest", index = 1, position = Vector3.new(-872.24, 65.81, -10919.95) },
		{ min = 2150, max = 2199, mob = "Ice Cream Commander", id = "IceCreamIslandQuest", index = 2, position = Vector3.new(-558.06, 112.04, -11290.77) },
		{ min = 2200, max = 2224, mob = "Cookie Crafter", id = "CakeQuest1", index = 1, position = Vector3.new(-2374.13, 37.79, -12125.30) },
		{ min = 2225, max = 2249, mob = "Cake Guard", id = "CakeQuest1", index = 2, position = Vector3.new(-1598.30, 43.77, -12244.58) },
		{ min = 2250, max = 2274, mob = "Baking Staff", id = "CakeQuest2", index = 1, position = Vector3.new(-1887.80, 77.61, -12998.35) },
		{ min = 2275, max = 2299, mob = "Head Baker", id = "CakeQuest2", index = 2, position = Vector3.new(-2216.18, 82.88, -12869.29) },
		{ min = 2300, max = 2324, mob = "Cocoa Warrior", id = "ChocQuest1", index = 1, position = Vector3.new(-21.55, 80.57, -12352.38) },
		{ min = 2325, max = 2349, mob = "Chocolate Bar Battler", id = "ChocQuest1", index = 2, position = Vector3.new(582.59, 77.18, -12463.16) },
		{ min = 2350, max = 2374, mob = "Sweet Thief", id = "ChocQuest2", index = 1, position = Vector3.new(165.18, 76.05, -12600.83) },
		{ min = 2375, max = 2399, mob = "Candy Rebel", id = "ChocQuest2", index = 2, position = Vector3.new(134.86, 77.24, -12876.54) },
		{ min = 2400, max = 2449, mob = "Candy Pirate", id = "CandyQuest1", index = 1, position = Vector3.new(-1310.50, 26.01, -14562.40) },
		{ min = 2450, max = 2474, mob = "Isle Outlaw", id = "TikiQuest1", index = 1, position = Vector3.new(-16303.14, 188.16, -268.92) },
		{ min = 2475, max = 2524, mob = "Island Boy", id = "TikiQuest1", index = 2, position = Vector3.new(-16303.14, 188.16, -268.92) },
		{ min = 2525, max = 2549, mob = "Isle Champion", id = "TikiQuest2", index = 2, position = Vector3.new(-16748.46, 94.38, 1129.71) },
		{ min = 2550, max = 2599, mob = "Serpent Hunter", id = "TikiQuest3", index = 1, position = Vector3.new(-16959.27, 110.61, 1669.60) },
		{ min = 2600, max = 2624, mob = "Reef Bandit", id = "SubmergedQuest1", index = 1, position = Vector3.new(11106, -2058, 9154) },
		{ min = 2625, max = 2649, mob = "Coral Pirate", id = "SubmergedQuest1", index = 2, position = Vector3.new(10655, -2018, 9254) },
		{ min = 2650, max = 2674, mob = "Sea Chanter", id = "SubmergedQuest2", index = 1, position = Vector3.new(10699, -1988, 9995) },
		{ min = 2675, max = 2699, mob = "Ocean Prophet", id = "SubmergedQuest2", index = 2, position = Vector3.new(11110, -1950, 10128) },
		{ min = 2700, max = math.huge, mob = "Grand Devotee", id = "SubmergedQuest3", index = 2, position = Vector3.new(9577, -1928, 9936) },
	},
}

local function levelOf()
	return tonumber(getStat("Level")) or 1
end

local function questForLevel()
	local sea = SEA_BY_PLACE[game.PlaceId]
	local list = sea and QUESTS[sea]
	if not list then
		return nil
	end
	local lvl = levelOf()
	local fallback = list[1]
	for _, quest in ipairs(list) do
		if lvl >= quest.min and lvl <= quest.max then
			return quest, sea
		end
		if lvl > quest.max then
			fallback = quest
		end
	end
	return fallback, sea
end

local lastQuestKey = nil

local function questShown()
	local gui = LP:FindFirstChildOfClass("PlayerGui")
	local main = gui and gui:FindFirstChild("Main")
	local frame = main and main:FindFirstChild("Quest")
	return frame ~= nil and frame.Visible == true
end

-- StartQuest usa ID + index da quest, nao o nivel
local function startQuest()
	local quest = questForLevel()
	if quest then
		local key = quest.id .. ":" .. tostring(quest.index)
		if key ~= lastQuestKey or not questShown() then
			invoke("StartQuest", quest.id, quest.index)
			lastQuestKey = key
		end
		Config.Farm.QuestId = quest.id
		Config.Farm.QuestIndex = quest.index
		Config.Farm.QuestLevel = levelOf()
		return quest
	end
	invoke("StartQuest", Config.Farm.QuestId, Config.Farm.QuestIndex)
	return nil
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
			hrp.CFrame = part.CFrame
		end)
		task.wait(0.1)
	else
		moveTo(part.Position + Vector3.new(0, 2, 0), Config.Chest.Speed)
	end

	if Config.Chest.UseRemote then
		fireOn(REMOTES.Chest, entry.Instance)
		fireOn(REMOTES.Chest, part)
	end

	-- Touch e o metodo oficial: o bau tem TouchInterest
	if firetouchinterest then
		pcall(function()
			firetouchinterest(hrp, part, 0)
		end)
		task.wait(0.15)
		pcall(function()
			firetouchinterest(hrp, part, 1)
		end)
	else
		pcall(function()
			hrp.CFrame = part.CFrame
		end)
	end
	interact(entry.Instance)
	task.wait(0.35)

	-- Segunda tentativa: as vezes o primeiro touch nao registra
	if part.Parent and firetouchinterest then
		pcall(function()
			hrp.CFrame = part.CFrame
			firetouchinterest(hrp, part, 0)
		end)
		task.wait(0.15)
		pcall(function()
			firetouchinterest(hrp, part, 1)
		end)
		task.wait(0.2)
	end

	-- Se o bau continuou no mapa, o servidor recusou: espera e tenta outro
	if part.Parent and entry.Instance.Parent then
		chestCooldown[entry.Instance] = os.clock() + 20
		pcall(function()
			part.CanTouch = false
		end)
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

-- Kill Aura: atinge todos os NPCs do raio sem sair do lugar
startLoop("noclip", function()
	if not Config.Misc.Noclip then
		task.wait(0.5)
		return
	end
	local char = LP.Character
	if char then
		for _, part in ipairs(char:GetDescendants()) do
			if part:IsA("BasePart") and part.CanCollide then
				part.CanCollide = false
			end
		end
	end
	task.wait(0.1)
end)

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
	-- Descobre sozinho qual metodo de ataque causa dano neste executor
	if Config.Farm.AutoDetect and not Config.Farm.Verified and (Config.Farm.DetectTries or 0) < 3 then
		detectAttackMethod()
	end
	-- Se o Auto Quest esta ligado, prioriza o mob da quest do nivel
	local quest = questForLevel()
	local filter = Config.Farm.Mode == "Mob especifico" and Config.Farm.Mob or nil
	local target
	if quest and Config.Farm.AutoQuest and Config.Farm.Mode ~= "Mob especifico" then
		target = nearestMob(Config.Farm.AuraRadius, quest.mob)
	end
	target = target or nearestMob(Config.Farm.Radius, filter)
	if not target and quest and Config.Farm.AutoQuest and Config.Farm.Mode ~= "Mob especifico" then
		-- Nenhum mob do nivel por perto: vai pra area da quest e espera o spawn
		if Config.Farm.QuestPos ~= quest.position then
			Config.Farm.QuestPos = quest.position
			moveTo(quest.position + Vector3.new(0, 3, 0), Config.Farm.Speed)
		end
		task.wait(0.2)
		return
	end
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
	Title = "Kill Aura",
	Desc = "Bate nos NPCs do raio sem sair do lugar (M1 real do jogo)",
	Value = true,
	Callback = function(state)
		Config.Farm.KillAura = state
		if not state then
			setMouseTarget(nil)
		end
	end,
})

FarmSection:Toggle({
	Title = "Tambem mandar RegisterHit",
	Desc = "RE/RegisterAttack + RE/RegisterHit (o jogo novo ignora no M1)",
	Value = true,
	Callback = function(state)
		Config.Farm.ServerHit = state
	end,
})

FarmSection:Toggle({
	Title = "Todas as partes do mob",
	Desc = "Registra dano em cada BasePart (mais forte)",
	Value = true,
	Callback = function(state)
		Config.Farm.AuraAllParts = state
	end,
})

FarmSection:Slider({
	Title = "Raio da Kill Aura",
	Desc = "Raio onde a aura procura NPCs",
	Step = 25,
	Value = { Min = 50, Max = 3000, Default = 250 },
	Callback = function(value)
		Config.Farm.AuraRadius = value
	end,
})

FarmSection:Slider({
	Title = "Alcance real do hit",
	Desc = "Distancia que o servidor aceita (Axonic usa 65). Acima disso o hit e ignorado",
	Step = 5,
	Value = { Min = 20, Max = 200, Default = 65 },
	Callback = function(value)
		Config.Farm.AuraRange = value
	end,
})

FarmSection:Toggle({
	Title = "Alcancar NPCs fora do alcance",
	Desc = "Vai ate o NPC por 1 tick, bate e volta pro seu lugar",
	Value = true,
	Callback = function(state)
		Config.Farm.AuraSweep = state
	end,
})

FarmSection:Button({
	Title = "Testar dano da Kill Aura",
	Desc = "Mede o HP do mob mais proximo antes e depois do hit",
	Callback = function()
		task.spawn(function()
			ensureWeapon(true)
			local hrp = getHRP()
			if not hrp then
				return
			end
			local target, bestDistance = nil, math.huge
			for _, mob in ipairs(collectMobs()) do
				local distance = (mob.Root.Position - hrp.Position).Magnitude
				if mob.Humanoid.Health > 0 and distance < bestDistance then
					target, bestDistance = mob, distance
				end
			end
			if not target then
				notify("Kill Aura", "Nenhum mob vivo encontrado", "alert-triangle", 6)
				return
			end
			local tool = equippedMelee()
			local before = target.Humanoid.Health
			local parts, reason = 0, "m1"
			for _ = 1, 4 do
				if m1Attack(target) then
					parts = parts + 1
				end
				if Config.Farm.ServerHit then
					local _, hitParts = serverHit(Config.Farm.AuraRange, target.Model)
					parts = parts + (hitParts or 0)
				end
				task.wait(0.15)
				if target.Humanoid.Health < before then
					break
				end
			end
			task.wait(0.6)
			local after = before
			pcall(function()
				after = target.Humanoid.Health
			end)
			local dealt = math.max(0, before - after)
			notify(
				"Kill Aura",
				("%s: %.0f -> %.0f (dano %.0f) | %d partes | %s | melee: %s"):format(
					tostring(target.Name), before, after, dealt, parts or 0, tostring(reason), tool and tool.Name or "nenhuma"
				),
				dealt > 0 and "check" or "alert-triangle",
				10
			)
		end)
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
		Desc = "Auto = ativa a arma + ClickButton1 (mais confiavel no Blox)",
		Values = { "Auto (todos)", "CombatFramework", "RegisterHit", "ClickButton1", "CommF Attack", "Tool:Activate", "Mouse1click" },
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
	Title = "Teleportar ate o mob",
	Desc = "Desligado = farma parado so com a Kill Aura",
	Value = false,
	Callback = function(state)
		Config.Farm.TeleportToMob = state
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

CombatSection:Toggle({
	Title = "Detectar ataque automaticamente",
	Desc = "Testa os metodos e trava no que tira vida do mob",
	Value = true,
	Callback = function(state)
		Config.Farm.AutoDetect = state
	end,
})

CombatSection:Button({
	Title = "Detectar metodo agora",
	Desc = "Dispara cada metodo e mede o dano no mob mais proximo",
	Callback = function()
		Config.Farm.DetectTries = 0
		task.spawn(function()
			detectAttackMethod()
		end)
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

CombatSection:Button({
	Title = "Diagnostico do motor de dano",
	Desc = "Bate 10x e mostra dano, hits reais e estado do CombatFramework",
	Callback = function()
		task.spawn(function()
			damageProbe()
		end)
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

QuestSection:Paragraph({
	Title = "Quest automatica por nivel",
	Desc = "Usa a tabela de quests do mar atual (id + index): o hub escolhe pelo seu nivel e mantem sempre ativa.",
})

QuestSection:Button({
	Title = "Iniciar quest do meu nivel",
	Desc = "Mostra qual quest foi escolhida",
	Callback = function()
		local quest = startQuest()
		if quest then
			notify("Quest", ("%s (%s) - nivel %d"):format(quest.mob, quest.id, Config.Farm.QuestLevel), "check", 6)
		else
			notify("Quest", "Mar nao reconhecido, use o botao manual abaixo", "alert-triangle", 5)
		end
	end,
})

QuestSection:Button({
	Title = "Ir para a area da quest",
	Callback = function()
		task.spawn(function()
			local quest = questForLevel()
			if quest then
				moveTo(quest.position + Vector3.new(0, 3, 0), Config.Farm.Speed)
			else
				notify("Quest", "Nenhuma quest encontrada para o seu nivel", "alert-triangle", 5)
			end
		end)
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

ChestSection:Toggle({
	Title = "So baús ativos (CanTouch)",
	Desc = "Ignora baú ja coletado que ainda esta no mapa",
	Value = true,
	Callback = function(state)
		Config.Chest.OnlyActive = state
	end,
})

ChestSection:Dropdown({
	Title = "Tipo de bau",
	Desc = "Chest1 Prata / Chest2 Ouro / Chest3 Diamante",
	Values = { "Todos", "Prata", "Ouro", "Diamante" },
	Value = "Todos",
	Callback = function(option)
		Config.Chest.Grade = option
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
		task.spawn(function()
			local chest = nearestChest(Config.Chest.Radius)
			if chest then
				collectChest(chest)
			else
				notify("Auto Bau", "Nenhum bau no raio configurado", "alert-triangle", 4)
			end
		end)
	end,
})

ChestSection:Button({
	Title = "Testar coleta de bau",
	Desc = "Mostra o bau encontrado e se ele sumiu depois do touch",
	Callback = function()
		refreshChests(true)
		local chest = nearestChest(Config.Chest.Radius)
		if not chest then
			notify("Auto Bau", ("Nenhum bau no raio (%d candidatos no mapa)"):format(#chestCache), "alert-triangle", 6)
			print("[MK4 Hubx] bau: nenhum candidato. cache =", #chestCache)
			return
		end
		task.spawn(function()
			print("[MK4 Hubx] bau escolhido:", chest.Part:GetFullName())
			print("[MK4 Hubx] real (TouchInterest/prompt):", tostring(chest.Real))
			print("[MK4 Hubx] firetouchinterest disponivel:", tostring(firetouchinterest ~= nil))
			collectChest(chest)
			task.wait(0.4)
			local stillThere = chest.Part.Parent ~= nil
			print("[MK4 Hubx] bau ainda no mapa depois do touch:", tostring(stillThere))
			notify("Auto Bau", stillThere and "Bau NAO saiu - veja o console (F9)" or "Bau coletado com sucesso", stillThere and "alert-triangle" or "check", 7)
		end)
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
		task.spawn(function()
			local mob = nearestMob(Config.Farm.Radius)
			if mob then
				moveTo(mob.Root.Position + Vector3.new(0, 3, 0), Config.Farm.Speed)
			else
				notify("Teleporte", "Nenhum mob no raio", "alert-triangle", 4)
			end
		end)
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

ServerSection:Toggle({
	Title = "Noclip",
	Desc = "Atravessa paredes (util pra chegar em baús/quests)",
	Value = false,
	Callback = function(state)
		Config.Misc.Noclip = state
	end,
})

ServerSection:Button({
	Title = "Entrar no time Piratas",
	Desc = "CommF_:InvokeServer(\"SetTeam\", \"Pirates\")",
	Callback = function()
		invoke("SetTeam", "Pirates")
		notify("Time", "SetTeam Pirates enviado", "flag", 4)
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
		print("[MK4 Hubx] metodo de ataque:", Config.Farm.AttackMethod, "verificado:", tostring(Config.Farm.Verified))
		print("[MK4 Hubx] executor tem getreg/getfenv:", tostring(getreg ~= nil), tostring(getfenv ~= nil))
		print("[MK4 Hubx] mobs atacaveis no mapa:", #collectMobs(true))
		notify("MK4 Hubx", "Diagnostico impresso no console (F9)", "terminal", 5)
	end,
})

DebugSection:Button({
	Title = "Estado do hub",
	Callback = function()
		print("[MK4 Hubx] Farm:", Config.Farm.Enabled, "Aura:", Config.Farm.KillAura, "RegisterHit:", Config.Farm.ServerHit)
		local tool = equippedMelee()
		print("[MK4 Hubx] melee equipada:", tool and tool.Name or "NENHUMA (dano nao aplica)")
		print("[MK4 Hubx] Raio da aura:", Config.Farm.AuraRadius, "alcance do hit:", Config.Farm.AuraRange)
		print("[MK4 Hubx] remotes:", REMOTES.RegisterAttack ~= nil, REMOTES.RegisterHit ~= nil)
		local sentOk, sentParts, sentReason = serverHit(Config.Farm.AuraRadius)
		print("[MK4 Hubx] envio:", tostring(sentOk), sentParts, sentReason)
		print("[MK4 Hubx] aura -> m1:", dbg.m1, "registerHit:", dbg.attacks, "partes:", dbg.parts, "motivo:", dbg.reason)
		print("[MK4 Hubx] golpes no CombatFramework:", dbg.swings, "| hits reais do cliente:", dbg.hits)
		print("[MK4 Hubx] mouse hook (aura m1):", tostring(mouseHookOk), "| hit hook:", tostring(hitHookOk))
		print("[MK4 Hubx] sweep -> rodadas:", dbg.sweeps, "partes:", dbg.sweepsSent)
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
