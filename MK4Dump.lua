--[[=========================================================================
  MK4 Dump  |  script separado do hub
  -------------------------------------------------------------------------
  O que ele faz:
    - lista TODOS os remotes que o cliente ve (RemoteEvent/RemoteFunction)
    - espiona as chamadas FireServer/InvokeServer com os argumentos reais
      e o script do jogo que chamou (__namecall hook)
    - manda tudo para o canal MK4 (HTTP POST), junto com estado do player
  Como usar:
    - execute dentro do Blox Fruits, no executor, uma vez por sessao
    - nao depende da WindUI nem do MK4Hubx.lua
    - pode rodar junto com o hub sem conflito de remote (o hook respeita
      o que ja existe e chama a funcao original)
  Console: mostra o run id e os contadores. Nada de interface.
=========================================================================]]

local ENDPOINT = "https://mk4-channel-u7emdu-preview.freebuff.page"
local KEY = "24fd78a1bcc03ad77faf1d6c445b7a6b"

local CONFIG = {
	flushEvery = 4, -- segundos entre envios
	batchSize = 180, -- eventos por POST (servidor aceita ate 300)
	maxQueue = 2000, -- se passar disso e porque o canal caiu: descarta
	heartbeat = 20, -- segundos entre snapshot/stats
	maxRemotes = 800,
	maxSpyShapes = 6,
}

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local HttpService = game:GetService("HttpService")
local Stats = game:GetService("Stats")

local LP = Players.LocalPlayer
local RUN = tostring(math.floor((os.time and os.time() or 0))) .. "-" .. tostring(math.random(100000, 999999))

--=====================================================================
-- HELPERS
--=====================================================================
local function clip(value, limit)
	local text = tostring(value)
	if #text > limit then
		return text:sub(1, limit) .. "..."
	end
	return text
end

local function fullName(inst)
	if not inst then
		return "nil"
	end
	local ok, name = pcall(function()
		return inst:GetFullName()
	end)
	if ok and name then
		return name
	end
	local ok2, alt = pcall(function()
		return inst.Name
	end)
	if ok2 and alt then
		return tostring(alt)
	end
	return "?"
end

local function kindOf(value)
	if typeof then
		local ok, kind = pcall(typeof, value)
		if ok and kind then
			return kind
		end
	end
	return type(value)
end

-- resumo curto de um valor sem recursao (usado quando JSONEncode falha em tabelas com Instance)
local function shallow(value)
	local kind = kindOf(value)
	if kind == "Instance" then
		return "Instance:" .. clip(fullName(value), 48)
	elseif kind == "string" then
		return "string:" .. clip(value, 24)
	elseif kind == "number" or kind == "boolean" or kind == "nil" then
		return kind .. ":" .. tostring(value)
	end
	return kind
end

local function shape(value)
	local kind = kindOf(value)
	if kind == "Instance" then
		return "Instance:" .. clip(fullName(value), 70)
	elseif kind == "string" then
		return "string:" .. clip(value, 48)
	elseif kind == "number" or kind == "boolean" or kind == "nil" then
		return kind .. ":" .. tostring(value)
	elseif kind == "table" then
		local ok, encoded = pcall(function()
			return HttpService:JSONEncode(value)
		end)
		if ok and encoded then
			return "table:" .. clip(encoded, 200)
		end
		-- tabela com Instance dentro nao serializa: descreve a forma
		local entries = {}
		local count = 0
		for key, entry in pairs(value) do
			count = count + 1
			if count <= 4 then
				entries[#entries + 1] = tostring(key) .. "=" .. shallow(entry)
			end
		end
		return ("table[%d]{%s}"):format(count, table.concat(entries, ", "))
	end
	return tostring(kind)
end

-- Executor: acha a funcao HTTP qualquer que seja o nome dela
local function firstFunction(...)
	for i = 1, select("#", ...) do
		local candidate = select(i, ...)
		if type(candidate) == "function" then
			return candidate
		end
	end
	return nil
end

local env = _G
if getgenv then
	local ok, value = pcall(getgenv)
	if ok and type(value) == "table" then
		env = value
	end
end

local httpRequest = firstFunction(
	env.request,
	_G.request,
	syn and syn.request,
	http and http.request,
	fluxus and fluxus.request,
	_G.http_request,
	_G.HttpRequest,
	krnl and krnl.request
)

local function executorName()
	if not identifyexecutor then
		return "desconhecido"
	end
	local ok, name = pcall(identifyexecutor)
	if ok and name then
		return tostring(name)
	end
	return "desconhecido"
end

local stats = { sent = 0, failed = 0, dropped = 0, batches = 0, lastError = nil }
local queue = {}
local flush

local function post(events)
	if not httpRequest then
		return false, "executor sem funcao request/http_request"
	end
	local encoded
	local okEncode = pcall(function()
		encoded = HttpService:JSONEncode({ run = RUN, events = events })
	end)
	if not okEncode or not encoded then
		return false, "JSONEncode falhou"
	end
	local response
	local okCall = pcall(function()
		response = httpRequest({
			Url = ENDPOINT .. "/log?k=" .. KEY,
			Method = "POST",
			Headers = { ["Content-Type"] = "application/json" },
			Body = encoded,
		})
	end)
	if not okCall then
		stats.failed = stats.failed + 1
		return false, "request lancou erro"
	end
	local code = 0
	if type(response) == "table" then
		code = response.StatusCode or response.status or response.Status or 0
	end
	if tonumber(code) and tonumber(code) >= 200 and tonumber(code) < 300 then
		stats.sent = stats.sent + #events
		stats.batches = stats.batches + 1
		return true
	end
	stats.failed = stats.failed + 1
	return false, "status " .. tostring(code)
end

flush = function()
	if #queue == 0 then
		return
	end
	local count = math.min(#queue, CONFIG.batchSize)
	local batch = {}
	for i = 1, count do
		batch[i] = queue[i]
	end
	local ok, err = post(batch)
	if ok then
		local rest = {}
		for i = count + 1, #queue do
			rest[#rest + 1] = queue[i]
		end
		queue = rest
		return
	end
	stats.lastError = err
	if #queue > CONFIG.maxQueue then
		queue = {}
		stats.dropped = stats.dropped + 1
	end
end

-- So empilha: nunca faz HTTP de dentro do hook __namecall (yield ali trava o remote)
local function enqueue(kind, data)
	queue[#queue + 1] = { kind = kind, data = data }
end

--=====================================================================
-- COLETA: REMOTES / NET
--=====================================================================
local function scanRemotes()
	local list = {}
	local total = 0
	local function consider(obj)
		local ok, cls = pcall(function()
			return obj.ClassName
		end)
		if not ok then
			return
		end
		if cls == "RemoteEvent" or cls == "RemoteFunction" or cls == "UnreliableRemoteEvent" then
			total = total + 1
			if #list < CONFIG.maxRemotes then
				list[#list + 1] = { p = fullName(obj), c = cls }
			end
		end
	end
	local ok = pcall(function()
		for _, obj in ipairs(game:GetDescendants()) do
			consider(obj)
		end
	end)
	if not ok then
		pcall(function()
			for _, obj in ipairs(ReplicatedStorage:GetDescendants()) do
				consider(obj)
			end
		end)
	end
	return list, total
end

local function scanNet()
	local out = { replicado = {}, modules = {}, net = {} }
	pcall(function()
		for _, child in ipairs(ReplicatedStorage:GetChildren()) do
			out.replicado[#out.replicado + 1] = child.Name .. " (" .. child.ClassName .. ")"
		end
	end)
	pcall(function()
		local modules = ReplicatedStorage:FindFirstChild("Modules")
		if not modules then
			return
		end
		for _, child in ipairs(modules:GetChildren()) do
			out.modules[#out.modules + 1] = child.Name .. " (" .. child.ClassName .. ")"
		end
		local net = modules:FindFirstChild("Net")
		if net then
			for _, remote in ipairs(net:GetChildren()) do
				out.net[#out.net + 1] = remote.Name .. " (" .. remote.ClassName .. ")"
			end
		end
	end)
	return out
end

--=====================================================================
-- ESTADO DO PLAYER
--=====================================================================
local function readVec(vec)
	if not vec then
		return nil
	end
	local ok, pos = pcall(function()
		return { math.floor(vec.X), math.floor(vec.Y), math.floor(vec.Z) }
	end)
	if ok then
		return pos
	end
	return nil
end

local function snapshot()
	local snap = {}
	pcall(function()
		local char = LP and LP.Character
		local hrp = char and char:FindFirstChild("HumanoidRootPart")
		local humanoid = char and char:FindFirstChildOfClass("Humanoid")
		local tool = char and char:FindFirstChildOfClass("Tool")
		snap.pos = readVec(hrp and hrp.Position)
		snap.tool = tool and tool.Name or nil
		if humanoid then
			snap.hp = math.floor(humanoid.Health)
			snap.maxHp = math.floor(humanoid.MaxHealth)
		end
		local data = LP and LP:FindFirstChild("Data")
		local level = data and data:FindFirstChild("Level")
		if level then
			snap.level = level.Value
		end
		local backpack = LP and LP:FindFirstChildOfClass("Backpack")
		if backpack then
			local tools = {}
			for _, item in ipairs(backpack:GetChildren()) do
				if item:IsA("Tool") then
					tools[#tools + 1] = item.Name
				end
			end
			snap.tools = tools
		end
		local enemies = workspace:FindFirstChild("Enemies")
		if enemies then
			snap.mobs = #enemies:GetChildren()
		end
	end)
	pcall(function()
		if Stats and Stats.Network and Stats.Network.ServerStatsItem then
			snap.ping = math.floor(Stats.Network.ServerStatsItem["Data Ping"]:GetValue())
		end
	end)
	return snap
end

--=====================================================================
-- SPY (__namecall)
--=====================================================================
local spy = { installed = false, method = "none", calls = 0 }
local seen = {}
local oldNamecall

local function callerName()
	if getcallingscript then
		local ok, scriptObj = pcall(getcallingscript)
		if ok and scriptObj then
			return fullName(scriptObj)
		end
	end
	if debug and debug.info then
		for level = 2, 4 do
			local ok, info = pcall(function()
				return debug.info(level, "s")
			end)
			if ok and info then
				return tostring(info)
			end
		end
	end
	return "?"
end

local function onCall(self, method, args)
	local path = fullName(self)
	local shapes = {}
	for i = 1, math.min(#args, CONFIG.maxSpyShapes) do
		shapes[i] = shape(args[i])
	end
	local key = path .. "|" .. method .. "|" .. table.concat(shapes, ",")
	local known = seen[key]
	if known then
		known.n = known.n + 1
		return
	end
	seen[key] = { n = 1 }
	spy.calls = spy.calls + 1
	enqueue("spy", { p = path, m = method, a = shapes, n = #args, caller = callerName() })
end

local function spyGate(self, ...)
	local okMethod, method = pcall(getnamecallmethod)
	if okMethod and (method == "FireServer" or method == "InvokeServer") then
		pcall(onCall, self, method, { ... })
	end
	return oldNamecall(self, ...)
end

local function installSpy()
	if spy.installed then
		return true
	end
	local gate = spyGate
	if newcclosure then
		local ok, wrapped = pcall(newcclosure, spyGate)
		if ok and wrapped then
			gate = wrapped
		end
	end
	if hookmetamethod then
		local ok, original = pcall(function()
			return hookmetamethod(game, "__namecall", gate)
		end)
		if ok and original then
			oldNamecall = original
			spy.installed = true
			spy.method = "hookmetamethod"
			return true
		end
	end
	local okMt, mt = pcall(function()
		return getrawmetatable and getrawmetatable(game)
	end)
	if okMt and mt then
		local okRaw, original = pcall(function()
			return rawget(mt, "__namecall")
		end)
		if okRaw and original then
			oldNamecall = original
			if setreadonly then
				pcall(setreadonly, mt, false)
			end
			local okSet = pcall(function()
				mt.__namecall = gate
			end)
			if setreadonly then
				pcall(setreadonly, mt, true)
			end
			if okSet then
				spy.installed = true
				spy.method = "getrawmetatable"
				return true
			end
		end
	end
	return false
end

--=====================================================================
-- LOOP
--=====================================================================
local function say(message)
	print("[MK4 Dump] " .. message)
end

local function start()
	enqueue("hello", {
		run = RUN,
		executor = executorName(),
		place = game.PlaceId,
		job = game.JobId,
		player = LP and LP.Name,
		userId = LP and LP.UserId,
		snapshot = snapshot(),
		hasRequest = httpRequest ~= nil,
	})

	local remotes, total = scanRemotes()
	enqueue("remotes", { total = total, listados = #remotes, lista = remotes })
	enqueue("net", scanNet())
	flush()

	say(("run %s | remotes: %d (listados %d) | request: %s"):format(RUN, total, #remotes, tostring(httpRequest ~= nil)))
	if not httpRequest then
		say("seu executor nao expoe request/http_request: o dump nao vai sair daqui")
		return
	end
	if stats.failed > 0 then
		say("falha no primeiro envio: " .. tostring(stats.lastError))
	end

	local installed = installSpy()
	enqueue("spy_status", { installed = installed, method = spy.method })
	flush()
	if installed then
		say("spy ligado via " .. spy.method .. " - pode jogar/atacar que eu recebo as chamadas")
	else
		say("seu executor nao suporta hookmetamethod/getrawmetatable: so a lista de remotes vai")
	end

	task.spawn(function()
		local lastBeat = 0
		while true do
			task.wait(CONFIG.flushEvery)
			flush()
			local now = os.time and os.time() or 0
			if now - lastBeat >= CONFIG.heartbeat then
				lastBeat = now
				enqueue("state", snapshot())
				enqueue("stats", {
					sent = stats.sent,
					failed = stats.failed,
					dropped = stats.dropped,
					batches = stats.batches,
					calls = spy.calls,
					lastError = stats.lastError,
				})
				say(("enviados %d | falhas %d | chamadas unicas %d"):format(stats.sent, stats.failed, spy.calls))
			end
		end
	end)
end

local ok, err = pcall(start)
if not ok then
	say("erro: " .. tostring(err))
end
