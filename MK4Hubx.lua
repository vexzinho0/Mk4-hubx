--[[
=====================================================================
   MK4 HUBX  |  Blox Fruits  |  WindUI  |  Sem Key
---------------------------------------------------------------------
   Tabs: Farm, Events, Bau, Frutas, Utilitarios
   Recursos: Auto Farm, Auto Quest, Kill Aura / Fast Attack, Auto Buso,
             Auto Events (Sea Beast, Elite, Factory, Cursed Ship,
             Ghost Ship, Dough King, Darkbeard, Kitsune),
             Auto Bau, Auto Frutas, Auto Rolar / Comprar Frutas,
             Teleportes, Server Hop, Anti-AFK e Remote Spy.

   Execucao:
     loadstring(game:HttpGet("SEU_LINK_AQUI"))()
=====================================================================
]]

--=====================================================================
-- 0. CARREGAMENTO DA WINDUI
--=====================================================================
local windOk, WindUI = pcall(function()
	return loadstring(game:HttpGet("https://github.com/Footagesus/WindUI/releases/latest/download/main.lua"))()
end)

if not windOk or not WindUI then
	return warn("[MK4 Hubx] Falha ao carregar a WindUI: " .. tostring(WindUI))
end

--=====================================================================
-- 1. SERVICOS E REFERENCIAS
--=====================================================================
local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local TweenService = game:GetService("TweenService")
local VirtualUser = game:GetService("VirtualUser")
local TeleportService = game:GetService("TeleportService")
local HttpService = game:GetService("HttpService")

local Workspace = workspace
local LP = Players.LocalPlayer

local Remotes = ReplicatedStorage:WaitForChild("Remotes", 30)
local CommF = Remotes and Remotes:FindFirstChild("CommF_")
local CommE = Remotes and Remotes:FindFirstChild("CommE")

if not CommF then
	WindUI:Notify({
		Title = "MK4 Hubx",
		Content = "Nao encontrei os Remotes do Blox Fruits. Execute o script dentro do jogo.",
		Icon = "x",
		Duration = 8,
	})
	return
end

--=====================================================================
-- 2. CONFIGURACAO GLOBAL
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
		AutoQuest = false,
		QuestId = "BanditQuest1",
		QuestLevel = 1,
		AutoBuso = false,
	},
	Chest = {
		Enabled = false,
		Speed = 170,
		Delay = 0.15,
		Radius = 400,
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
	Events = {}, -- preenchido depois com Config.Events[id] = false
	Misc = {
		AntiAfk = true,
	},
}

local Connections = {}
local currentTween = nil
local busyAction = false

--=====================================================================
-- 3. HELPERS GERAIS
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

local function invoke(...)
	local args = table.pack(...)
	local ok, result = pcall(function()
		return CommF:InvokeServer(table.unpack(args, 1, args.n))
	end)
	if ok then
		return result
	end
	return nil
end

local function fireRemote(...)
	if not CommE then
		return
	end
	local args = table.pack(...)
	pcall(function()
		CommE:FireServer(table.unpack(args, 1, args.n))
	end)
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

-- Movimento suave ate uma posicao (evita teleporte seco/caindo do mapa)
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

local warnedNoWeapon = false
local function attackOnce()
	local tool = getWeapon()
	if tool then
		pcall(function()
			tool:Activate()
		end)
	elseif not warnedNoWeapon then
		warnedNoWeapon = true
		notify("MK4 Hubx", "Equipe uma arma (espada / fruta) para o auto farm atacar.", "alert-triangle", 6)
	end
end

-- Interage com ProximityPrompt / ClickDetector (baus, frutas no chao, etc.)
local function interact(instance)
	for _, desc in ipairs(instance:GetDescendants()) do
		if desc:IsA("ProximityPrompt") then
			local hold = desc.HoldDuration or 0
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
-- 4. COLETA DE MOBS / BAUIS / FRUTAS
--=====================================================================
local function collectMobs()
	local list = {}
	local seen = {}

	local function add(model)
		if seen[model] or model == LP.Character then
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

-- Cache de baus (evita varrer o mapa inteiro a cada ciclo)
local chestCache = {}
local lastChestScan = 0

local function isChestName(name)
	local lower = name:lower()
	return lower == "chest" or lower == "chest2" or lower == "chest3" or lower:find("chest", 1, true) ~= nil
		or lower:find("treasure", 1, true) ~= nil
		or lower:find("bau", 1, true) ~= nil
end

local function scanChests()
	local found = {}
	for _, region in ipairs(Workspace:GetChildren()) do
		if region:IsA("Folder") or region:IsA("Model") then
			local candidates = {}
			local ok, descendants = pcall(function()
				return region:GetDescendants()
			end)
			if ok then
				for _, desc in ipairs(descendants) do
					if isChestName(desc.Name) and (desc:IsA("Model") or desc:IsA("BasePart")) then
						candidates[#candidates + 1] = desc
					end
				end
			end
			for _, desc in ipairs(candidates) do
				local part = desc:IsA("BasePart") and desc
					or desc.PrimaryPart
					or desc:FindFirstChildWhichIsA("BasePart")
				if part then
					found[#found + 1] = { Instance = desc, Part = part }
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
		if part and part.Parent and part:IsDescendantOf(Workspace) then
			local distance = (part.Position - hrp.Position).Magnitude
			if distance < bestDistance then
				best, bestDistance = entry, distance
			end
		end
	end
	return best
end

local function touchPart(part)
	local hrp = getHRP()
	if not hrp or not part then
		return
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
		hrp.CFrame = part.CFrame
		task.wait(0.1)
	end
end

local function collectChest(entry)
	local part = entry.Part
	if not part or not part.Parent then
		return false
	end
	local hrp = getHRP()
	if not hrp then
		return false
	end
	moveTo(part.Position + Vector3.new(0, 3, 0), Config.Chest.Speed)
	touchPart(part)
	if not interact(entry.Instance) then
		task.wait(0.1)
		touchPart(part)
	end
	return true
end

-- Frutas no chao: Tools/Models com nome "Fruta-Fruta" (ex: Rocket-Rocket)
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
		if part and part.Parent then
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
local function startQuest()
	invoke("StartQuest", Config.Farm.QuestId, Config.Farm.QuestLevel)
end

-- keepGoing: funcao que decide se o combate continua (farm ou evento)
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
	moveTo(mhrp.Position + Vector3.new(0, 3, 0), Config.Farm.Speed)

	while active() and mob.Parent and mhum.Health > 0 and (os.clock() - started) < 8 do
		local hrp = getHRP()
		if not hrp then
			break
		end
		if (hrp.Position - mhrp.Position).Magnitude > 14 then
			hrp.CFrame = CFrame.new(mhrp.Position + Vector3.new(0, 3, 0))
		end
		if Config.Farm.AutoBuso and (os.clock() - lastBuso) > 2 then
			lastBuso = os.clock()
			invoke("Buso")
		end
		attackOnce()
		if not Config.Farm.FastAttack then
			task.wait(0.45)
		else
			task.wait(Config.Farm.AttackDelay)
		end
	end
end

local function farmLoop()
	task.spawn(function()
		local lastQuestStart = 0
		while true do
			task.wait(0.1)
			if Config.Farm.Enabled then
				if getChar() then
					local filter = Config.Farm.Mode == "Mob especifico" and Config.Farm.Mob or nil
					local target = nearestMob(Config.Farm.Radius, filter)
					if target then
						farmTarget(target, function()
							return Config.Farm.Enabled
						end)
					elseif Config.Farm.AutoQuest then
						if (os.clock() - lastQuestStart) > 5 then
							lastQuestStart = os.clock()
							startQuest()
						end
						task.wait(0.5)
					else
						task.wait(0.5)
					end
				end
			else
				task.wait(0.2)
			end
		end
	end)
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

-- Retorna o primeiro mob que bate com algum evento ativo
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

local function eventLoop()
	task.spawn(function()
		local lastNotice = 0
		while true do
			task.wait(0.25)
			local anyActive = false
			for _, enabled in pairs(Config.Events) do
				if enabled then
					anyActive = true
					break
				end
			end
			if anyActive then
				local mob, id = findEventTarget()
				if mob then
					if (os.clock() - lastNotice) > 5 then
						lastNotice = os.clock()
						notify("Evento", ("Engajando: %s (%s)"):format(mob.Name, EVENT_TARGETS[id].label), "swords", 3)
					end
					farmTarget(mob, function()
						return Config.Events[id] == true
					end)
				end
			else
				task.wait(0.5)
			end
		end
	end)
end

--=====================================================================
-- 7. BAUIS / FRUTAS / ROLAGEM
--=====================================================================
local function chestLoop()
	task.spawn(function()
		while true do
			task.wait(Config.Chest.Delay)
			if Config.Chest.Enabled then
				local chest = nearestChest(Config.Chest.Radius)
				if chest then
					pcall(collectChest, chest)
				else
					task.wait(0.6)
				end
			else
				task.wait(0.3)
			end
		end
	end)
end

local function fruitLoop()
	task.spawn(function()
		while true do
			task.wait(Config.Fruit.Delay)
			if Config.Fruit.Enabled then
				local fruit = nearestFruit()
				if fruit then
					local fruitName = fruit.Instance.Name
					moveTo(fruit.Part.Position + Vector3.new(0, 3, 0), Config.Fruit.Speed)
					touchPart(fruit.Part)
					interact(fruit.Instance)
					task.wait(0.4)
					if Config.Fruit.Notify and not fruit.Part.Parent then
						notify("Fruta coletada", fruitName, "apple", 4)
					end
				else
					task.wait(0.5)
				end
			else
				task.wait(0.4)
			end
		end
	end)
end

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

local function rollLoop()
	task.spawn(function()
		local lastReroll = 0
		while true do
			task.wait(1)
			if Config.Roll.Enabled and not busyAction then
				if getBeli() >= Config.Roll.MinBeli then
					local fruit = buyRandomFruit()
					if fruit and Config.Roll.Notify then
						notify("Rolagem", "Saiu: " .. fruit, "dice-5", 5)
					end
					if fruit and isWantedFruit(fruit) then
						Config.Roll.Enabled = false
						notify("Rolagem", "Fruta desejada encontrada: " .. fruit, "party-popper", 8)
					end
				end
			end
			if Config.Roll.Reroll and (os.clock() - lastReroll) > 6 then
				lastReroll = os.clock()
				invoke("BlackbeardReward", "Fruit", "2")
			end
		end
	end)
end

--=====================================================================
-- 8. REMOTE SPY (para voce coletar os remotes do jogo)
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
		local oldNamecall
		oldNamecall = hookmetamethod(game, "__namecall", function(self, ...)
			local method = getnamecallmethod()
			if spyEnabled and (self == CommF or self == CommE) and (method == "InvokeServer" or method == "FireServer") then
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
-- 9. ANTI-AFK E UTILITARIOS
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

--=====================================================================
-- 10. INTERFACE (WINDUI)
--=====================================================================
local Window = WindUI:CreateWindow({
	Title = "MK4 Hubx",
	Icon = "grip",
	Author = "MK4",
	Folder = "MK4Hubx",
	Size = UDim2.fromOffset(640, 520),
	Theme = "Dark",
	Transparency = 0.15,
	SideBarWidth = 180,
	User = { Enabled = true, Anonymous = true },
})

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
		if state then
			notify("Auto Farm", "Ligado", "play", 3)
		end
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
	Desc = "Escaneia os mobs ao redor",
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
	Desc = "Usa o delay configurado acima",
	Value = true,
	Callback = function(state)
		Config.Farm.FastAttack = state
	end,
})

FarmSection:Toggle({
	Title = "Auto Buso Haki",
	Desc = "Ativa o Busoshoku enquanto farma",
	Value = false,
	Callback = function(state)
		Config.Farm.AutoBuso = state
	end,
})

local QuestSection = FarmTab:Section({ Title = "Quest" })

QuestSection:Toggle({
	Title = "Auto Quest",
	Desc = "Inicia a quest selecionada quando nao houver alvo",
	Value = false,
	Callback = function(state)
		Config.Farm.AutoQuest = state
	end,
})

QuestSection:Dropdown({
	Title = "Quest",
	Desc = "ID usado no StartQuest",
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
		notify("Quest", ("Quest %s iniciada"):format(Config.Farm.QuestId), "check", 4)
	end,
})

QuestSection:Button({
	Title = "Abandonar quest",
	Desc = "Remove a quest atual",
	Callback = function()
		invoke("AbandonQuest")
		notify("Quest", "Quest abandonada", "x", 3)
	end,
})

-- ---------------------------- EVENTS ----------------------------
local EventSection = EventTab:Section({ Title = "Auto Events" })
EventSection:Paragraph({
	Title = "Eventos detectados automaticamente",
	Desc = "O hub procura os mobs do evento no mapa e engaja quando o evento estiver ativo.",
})

for _, id in ipairs({ "SeaBeast", "Elite", "Factory", "CursedShip", "GhostShip", "DoughKing", "Darkbeard", "Kitsune" }) do
	local data = EVENT_TARGETS[id]
	EventSection:Toggle({
		Title = data.label,
		Desc = "Procurar e atacar automaticamente",
		Value = false,
		Callback = function(state)
			Config.Events[id] = state
		end,
	})
end

local SummonSection = EventTab:Section({ Title = "Invocar / Iniciar" })

SummonSection:Button({
	Title = "Invocar Darkbeard",
	Desc = "Precisa do Fist of Darkness",
	Callback = function()
		fireRemote("Darkbeard")
		invoke("Darkbeard", "Summon")
		notify("Darkbeard", "Tentativa de invocacao enviada", "flame", 5)
	end,
})

SummonSection:Button({
	Title = "Invocar Dough King",
	Desc = "Precisa dos requisitos do evento",
	Callback = function()
		invoke("DoughKing", "Summon")
		notify("Dough King", "Tentativa de invocacao enviada", "flame", 5)
	end,
})

SummonSection:Button({
	Title = "Iniciar Factory Raid",
	Desc = "Precisa da chave da fabrica",
	Callback = function()
		invoke("FactoryRaid", "Start")
		fireRemote("FactoryRaid")
		notify("Factory", "Tentativa de inicio enviada", "factory", 5)
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
	Desc = "Voa ate os baus e coleta",
	Value = false,
	Callback = function(state)
		Config.Chest.Enabled = state
		if state then
			refreshChests(true)
			notify("Auto Bau", ("Ligado - %d baus no mapa"):format(#chestCache), "package", 4)
		end
	end,
})

ChestSection:Slider({
	Title = "Raio de busca",
	Step = 10,
	Value = { Min = 50, Max = 2000, Default = 400 },
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

local FruitCollect = FruitTab:Section({ Title = "Auto Frutas" })

FruitCollect:Toggle({
	Title = "Auto Coletar Frutas",
	Desc = "Pega frutas que caem no chao",
	Value = false,
	Callback = function(state)
		Config.Fruit.Enabled = state
	end,
})

FruitCollect:Toggle({
	Title = "Avisar no canto da tela",
	Desc = "Mostra o nome da fruta coletada",
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

-- ---------------------------- ROLAGEM ----------------------------
local RollSection = FruitTab:Section({ Title = "Rolar / Comprar Frutas" })

RollSection:Toggle({
	Title = "Auto Rolar Frutas (Cousin)",
	Desc = "Compra fruta aleatoria ate achar uma desejada",
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
	Desc = "Custo do vendedor de frutas",
	Callback = function()
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
	Desc = "Entra em outro servidor do mesmo mapa",
	Callback = serverHop,
})

ServerSection:Button({
	Title = "Reconectar",
	Callback = function()
		TeleportService:Teleport(game.PlaceId, LP)
	end,
})

ServerSection:Toggle({
	Title = "Anti-AFK",
	Desc = "Evita kick por inatividade",
	Value = true,
	Callback = function(state)
		Config.Misc.AntiAfk = state
		applyAntiAfk()
	end,
})

local DebugSection = UtilTab:Section({ Title = "Debug / Remote Spy" })

DebugSection:Toggle({
	Title = "Remote Spy",
	Desc = "Printa CommF_ / CommE no console (F9)",
	Value = false,
	Callback = function(state)
		if state and not installRemoteSpy() then
			return
		end
		spyEnabled = state
		if state then
			notify("Remote Spy", "Ligado - use o jogo e veja o console (F9)", "terminal", 5)
		end
	end,
})

DebugSection:Button({
	Title = "Estado do hub",
	Desc = "Mostra as configuracoes atuais",
	Callback = function()
		print("[MK4 Hubx] Farm:", Config.Farm.Enabled, "Mob:", Config.Farm.Mob)
		print("[MK4 Hubx] Bau:", Config.Chest.Enabled, "Frutas:", Config.Fruit.Enabled)
		print("[MK4 Hubx] Rolagem:", Config.Roll.Enabled, "Beli:", getBeli())
		notify("MK4 Hubx", "Estado impresso no console (F9)", "terminal", 4)
	end,
})

DebugSection:Button({
	Title = "Descarregar hub",
	Desc = "Para todos os loops e fecha a interface",
	Callback = function()
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
-- 11. START
--=====================================================================
farmLoop()
eventLoop()
chestLoop()
fruitLoop()
rollLoop()

notify("MK4 Hubx", "Hub carregado. Sem key, bom farm!", "check-check", 6)
