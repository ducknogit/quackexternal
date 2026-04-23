--!native
--!optimize 2
local PID = "%-PROCESS-ID-%"
local QUACK_VERSION = "%-QUACK-VERSION-%"

local HttpService = game:GetService("HttpService")
local WebSocketService = game:GetService("WebSocketService")

local Players = game:GetService("Players")
local RobloxReplicatedStorage = game:GetService("RobloxReplicatedStorage")
local RunService = game:GetService("RunService")
local LogService = game:GetService("LogService")
local LocalStorageService = game:GetService("LocalStorageService")
local InsertService = game:GetService("InsertService")
local CoreGui = game:GetService("CoreGui")
local CorePackages = game:GetService("CorePackages")
local MarketplaceService = game:GetService("MarketplaceService")
local UserInputService = game:GetService("UserInputService")
local VirtualInputManager = game:GetService("VirtualInputManager")
local VirtualUser = game:GetService("VirtualUser")

local Player = Players.LocalPlayer
local PlayerScripts = Player:FindFirstChild("PlayerScripts")
local PlayerModule = PlayerScripts:FindFirstChild("PlayerModule")
local ControlModule = PlayerModule:FindFirstChild("ControlModule")
local GamepadModule = ControlModule:FindFirstChild("Gamepad")

local _bindable = Instance.new("BindableEvent")
_bindable.Event:Connect(function() end)
_bindable.Parent = script

local QuackContainer
local LoadstringContainer
local PointerContainer

-- remove UTF-8 BOM if present anywhere in a string
local function strip_bom(s)
    if type(s) ~= "string" then return s end
    return s:gsub("\239\187\191", "")
end

-- normalize a workspace-relative path: collapse `..` and `.` segments
local function normalize_path(path)
    if type(path) ~= "string" then return path end
    path = path:gsub("\\", "/")
    local parts = {}
    for part in path:gmatch("[^/]+") do
        if part == ".." then
            if #parts > 0 then table.remove(parts) end
        elseif part ~= "." and part ~= "" then
            table.insert(parts, part)
        end
    end
    return table.concat(parts, "\\")
end

-- compatibility shims expected by many scripts (syn, getgenv, fluxus)
pcall(function()
    local env = getgenv and getgenv() or _G
    env.syn = env.syn or {}
    env.fluxus = env.fluxus or env.syn -- share table
end)

-- block default Quack UI from ever showing
local function purge_Quack_ui()
    -- allowlisted GUI names that should survive (custom UI)
    local ui_whitelist = {
        ["quackexecutorgui"] = true,
        ["quacktogglegui"] = true,
    }
    local function is_Quack_gui(obj)
        if not obj:IsA("GuiBase2d") then return false end
        local name = obj.Name:lower()
        if ui_whitelist[name] then return false end
        return name:find("quack") ~= nil
    end
    local function watch(root)
        if root then
            -- initial sweep
            for _, child in ipairs(root:GetDescendants()) do
                if is_Quack_gui(child) then child:Destroy() end
            end
            -- kill on future additions
            root.DescendantAdded:Connect(function(c)
                if is_Quack_gui(c) then c:Destroy() end
            end)
        end
    end
    watch(CoreGui)
    watch(Player:FindFirstChild("PlayerGui"))
    -- PlayerGui gets recreated on teleport; re-hook when it appears
    Player.ChildAdded:Connect(function(c)
        if c.Name == "PlayerGui" then
            watch(c)
        end
    end)
end
local _ExecutorThreads = setmetatable({}, {__mode = "k"})
local _executor_main_thread = coroutine.running()
if _executor_main_thread then _ExecutorThreads[_executor_main_thread] = true end

local GameLeaving = false
Players.PlayerRemoving:Connect(function(plr)
    if plr == Player then
        GameLeaving = true
    end
end)

purge_Quack_ui()
task.spawn(function()
    while not GameLeaving do
        purge_Quack_ui()
        task.wait(2)
    end
end)

local websocket_client = WebSocketService:CreateClient("ws://localhost:8080")
if RobloxReplicatedStorage:FindFirstChild("Quack") then
    QuackContainer = RobloxReplicatedStorage:WaitForChild("Quack")
    LoadstringContainer = QuackContainer:WaitForChild("Loadstring")
    PointerContainer = QuackContainer:WaitForChild("Pointers")
else
    QuackContainer = Instance.new("Folder")
    QuackContainer.Name = "Quack"
    QuackContainer.Parent = RobloxReplicatedStorage

    LoadstringContainer = Instance.new("Folder")
    LoadstringContainer.Name = "Loadstring"
    LoadstringContainer.Parent = QuackContainer

    PointerContainer = Instance.new("Folder")
    PointerContainer.Name = "Pointers"
    PointerContainer.Parent = QuackContainer
end

---- [ Init ] ----
local HWID = HttpService:GenerateGUID(false)
local Libraries = {
	Drawing = {
		URL = "https://pastefy.app/TOnC70Cc/raw"
    },
	Hash = {
		URL = "https://pastefy.app/T58pVZEW/raw"
    },
	Lz4 = {
		URL = "https://pastefy.app/3E0P51cJ/raw"
	    }
}

local ENABLE_REMOTE_LIBS = true

local Bridge = { URL = "http://localhost:6767" }
local _typeof = typeof
local _require = require
local _setmetatable = setmetatable
local _getmetatable = getmetatable
local _game = game
local _workspace = workspace
local _script = script
local _Instance = Instance

local patterns_list = {
    "RobloxReplicatedStorage%.Quack%.Loadstring[^'\":]+",
    "CorePackages%.Packages%._Index%.CollisionMatchers2D%.CollisionMatchers2D%.Jest[^'\":]+",
    "Players%.[^%.]+%.PlayerScripts%.PlayerModule%.ControlModule%.VRNavigation[^'\":]+",
    "Players%.[^%.]+%.PlayerScripts%.PlayerModule%.ControlModule%.Gamepad[^'\":]+"
}

local function Sanitize_Text(str)
    if typeof(str) ~= "string" then return str end
    for _, pattern in ipairs(patterns_list) do
        str = string.gsub(str, pattern, '[string ""]')
    end
    return str
end

local function Merge(t1, t2)
	for k, v in pairs(t2) do
        if k ~= "Quack" then
		    t1[k] = v
        end
	end
	return t1
end

local function SyncExecutorEnvironment(target, source)
    for key, value in pairs(source) do
        if key ~= "Quack" then
            target[key] = value
        end
    end
end

local ReadonlyTables = setmetatable({}, { __mode = "k" })
local RawMetatables = setmetatable({}, { __mode = "k" })
local WrappedRawMetatables = setmetatable({}, { __mode = "k" })
local ExecutorTable = setmetatable({}, { __index = table })
ExecutorTable.freeze = function(object)
    ReadonlyTables[object] = true
    return object
end
ExecutorTable.isfrozen = function(object)
    return ReadonlyTables[object] == true or table.isfrozen(object)
end

local function SendRequest(options, timeout)
    timeout = tonumber(timeout) or nil
    local result, clock = nil, tick()

	HttpService:RequestInternal(options):Start(function(success, response)
		result = response
		result.Success = success
	end)

    while not result do
        task.wait()
        if (timeout and tick() - clock > timeout) then
            break
        end
    end
    return result
end

function Bridge:InternalRequest(body, timeout)
    local url = Bridge.URL .. body.url
	body['pid'] = PID

    local options = {
        Url = url,
        Body = HttpService:JSONEncode(body),
        Method = 'POST',
        Headers = {
            ['Content-Type'] = 'application/json'
        }
    }
    
    local response = SendRequest(options, timeout)
    if not response or type(response) ~= 'table' then 
        return nil, error("No Response Received From Server", 2)
    end

    local statusCode = tonumber(response.StatusCode)
    if statusCode and statusCode >= 200 and statusCode < 300 then
        if response.Body and response.Body ~= "" then
            return response.Body
        else
            return nil, error("Empty Response Body From Server", 2)
        end
    end
    Bridge:InternalRequest(body, timeout)
end

function GetRandomModule()
	local children = CorePackages.Packages:GetChildren()
	local module

	while not module or module.ClassName ~= "ModuleScript" do
		module = children[math.random(#children)]
	end

	local clone = module:Clone()
    clone:ClearAllChildren()
	return clone
end

---- [ Env / Miscellaneous ] ----
local Quack = getfenv(function() end)
Quack.Quack = {}
Quack.about = {
    _name = 'Quack',
    _version = QUACK_VERSION,
    _publisher = "Quack Executor"
}
table.freeze(Quack.about)
Quack._G = {}
Quack.shared = {}
local ExecutorEnvironment = {}
ExecutorEnvironment.table = ExecutorTable
Quack.setmetatable = function(object, metatable)
    local result = _setmetatable(object, metatable)
    if type(object) == "table" then
        RawMetatables[object] = metatable
    end
    return result
end
Quack.getmetatable = _getmetatable
local _genv_store = {}
do
    for k, v in pairs(Quack) do rawset(_genv_store, k, v) end
    setmetatable(_genv_store, {
        __newindex = function(t, k, v)
            rawset(t, k, v)
            rawset(Quack, k, v)
        end,
    })
    local _quack_ref = Quack
    local _store_ref = _genv_store
    local _pairs  = pairs
    local _rawget = rawget
    local _rawset = rawset
    Quack.getgenv = setfenv(function()
        for k, v in _pairs(_quack_ref) do
            if _rawget(_store_ref, k) ~= v then _rawset(_store_ref, k, v) end
        end
        return _store_ref
    end, {})
end

function Quack.getexecutorname()
	return Quack.about._name
end

function Quack.getexecutorversion()
	return Quack.about._version
end

function Quack.identifyexecutor()
	return Quack.getexecutorname(), Quack.getexecutorversion()
end

function Quack.get_hwid()
	return HWID
end
Quack.gethwid = Quack.get_hwid

function Quack.unlockmodule(instance)
	assert(typeof(instance) == "Instance", "invalid argument #1 to 'unlockmodule' (Instance expected, got " .. typeof(instance) .. ") ", 2)

	local pointer = Instance.new("ObjectValue", PointerContainer)
	pointer.Name = HttpService:GenerateGUID(false)
	pointer.Value = instance
    local response = Bridge:InternalRequest({
        ['url'] = "/unlockmodule",
        ['pointer'] = pointer.Name
    })
	pointer:Destroy()

    local success, result = pcall(function()
        return HttpService:JSONDecode(response)
    end)

    if success and result then
        if result.success and result.message then
            return result.message
        else
            return nil, (result.error or "Unknown Error")
        end
    else
        return nil, "Failed To Parse Server Response"
    end
end

local UnlockedModules = {}
function Quack.require(module_script)
    assert(typeof(module_script) == "Instance", "invalid argument #1 to 'require' (Instance expected, got " .. typeof(module_script) .. ")", 2)
    assert(module_script.ClassName == "ModuleScript", "invalid argument #1 to 'require' (ModuleScript expected, got " .. module_script.ClassName .. ")", 2)

    if table.find(UnlockedModules, module_script) then
        return _require(module_script)
    end

    local success, response = pcall(function()
        Quack.unlockmodule(module_script)
        return _require(module_script)
    end)

    if success and typeof(response) == "function" then
        local success2, response2 = pcall(response)
        if success2 then
            table.insert(UnlockedModules, module_script)
            return response2
        else
            error("Error Requiring Module '" .. module_script:GetFullName() .. "': " .. tostring(response2), 2)
        end
    else
        error("Failed To Load Module '" .. module_script:GetFullName() .. "': " .. tostring(response), 2)
    end
end

function Quack.cancompile(source)
    assert(type(source) == "string", "invalid argument #1 to 'compile' (string expected, got " .. type(source) .. ") ", 2)

    local response = Bridge:InternalRequest({
        ['url'] = "/cancompile",
        ['source'] = Quack.base64_encode(source)
    })

    local success, result = pcall(function()
        return HttpService:JSONDecode(response)
    end)

    if success and result then
        if result.success and result.data then
            return true
        elseif result.success and result.errors then
            return nil, result
        else
            return nil, (result.error or "Unknown Error")
        end
    else
        return nil, "Failed To Parse Server Response"
    end
end

function Quack.compile(source, encoded)
    assert(type(source) == "string", "invalid argument #1 to 'compile' (string expected, got " .. type(source) .. ") ", 2)
    assert(type(encoded) == "boolean", "invalid argument #2 to 'compile' (boolean expected, got " .. type(encoded) .. ") ", 2)

    local response = Bridge:InternalRequest({
        ['url'] = "/compile",
        ['source'] = Quack.base64_encode(source),
        ['encoded'] = encoded
    })

    local success, result = pcall(function()
        return HttpService:JSONDecode(response)
    end)

    if success and result then
        if result.success and result.data then
            return Quack.base64_decode(result.data)
        else
            return "", (result.error or "Unknown Error")
        end
    else
        return "", "Failed To Parse Server Response"
    end
end

local quack_chunks = {}
local quack_chunks_by_id = {}

function quack_chunk_register(id, text)
	if type(id) ~= "string" or type(text) ~= "string" then return end
	if quack_chunks_by_id[id] then return end
	quack_chunks_by_id[id] = text
	quack_chunks[#quack_chunks + 1] = { id = id, text = text }
	-- cap registry size to avoid unbounded growth across many loadstring calls
	if #quack_chunks > 64 then
		local oldest = table.remove(quack_chunks, 1)
		quack_chunks_by_id[oldest.id] = nil
	end
end

function Quack.loadstring(source, chunkname)
    assert(type(source) == "string", "invalid argument #1 to 'loadstring' (string expected, got " .. type(source) .. ") ", 2)
    source = strip_bom(source)
    chunkname = chunkname or "loadstring"
   
    assert(type(chunkname) == "string", "invalid argument #2 to 'loadstring' (string expected, got " .. type(chunkname) .. ") ", 2)
    chunkname = chunkname:gsub("[^%a_]", "")
    
    if (source == "" or source == " ") then
        return nil, "Empty Source"
    end
    
    if #source > 0 and source:byte(1) == 6 then
        return nil, "Bytecode Not Allowed 💔"
    end

    local CoreModule = GetRandomModule()
	CoreModule.Name = HttpService:GenerateGUID(false)
	CoreModule.Parent = LoadstringContainer

    local wrapped_source = "return function(...)\n" .. source .. "\nend"
    quack_chunk_register(CoreModule.Name, wrapped_source)

    local response = Bridge:InternalRequest({
        ['url'] = "/loadstring",
        ['pointer'] = CoreModule.Name,
        ['source'] = Quack.base64_encode(wrapped_source)
    })

    local success2, result2 = pcall(function()
        return HttpService:JSONDecode(response)
    end)
    
    if not result2.success and result2.errors then
        CoreModule.Parent = nil
        CoreModule:Destroy()
        local firstError = result2.errors[1]
        if firstError then
            return nil, "[string \"\"]:" .. tostring(firstError.Line) .. ": " .. tostring(firstError.Error)
        end
        return nil, "Loadstring Failed"
    elseif not result2.success and result2.error then
        CoreModule.Parent = nil
        CoreModule:Destroy()
        return nil, result2.error or "Unknown Error"
    elseif not success2 or not result2 then
        CoreModule.Parent = nil
        CoreModule:Destroy()
        return nil, "Failed To Parse Server Response"
    end

    local success4, response4 = pcall(function()
        Quack.unlockmodule(CoreModule)
        return _require(CoreModule)
    end)

    local function _make_thread_env(execFunc, baseEnv)
        SyncExecutorEnvironment(ExecutorEnvironment, Quack)
        local threadEnv = setmetatable({}, {
            __index = function(_, key)
                local value = rawget(ExecutorEnvironment, key)
                if value ~= nil then return value end
                return baseEnv[key]
            end
        })
        local wrapped = setfenv(execFunc, threadEnv)
        local original_wrapped = wrapped
        return function(...)
            local t = coroutine.running()
            if t then _ExecutorThreads[t] = true end
            return original_wrapped(...)
        end
    end

    if success4 then
        if success4 and type(response4) == "function" then
            CoreModule.Parent = nil
            return _make_thread_env(response4, getfenv(response4))
        elseif success4 and type(response4) == "table" and type(response4[chunkname]) == "function" then
            CoreModule.Parent = nil
            return _make_thread_env(response4[chunkname], getfenv(response4[chunkname]))
        else
            CoreModule.Parent = nil
            CoreModule:Destroy()
            return nil, "Execution Failed: " .. tostring(response4)
        end
    else
        CoreModule.Parent = nil
        CoreModule:Destroy()
        return nil, "Module Load Failed: " .. tostring(response4)
    end
end

---- [ WebSocket ] ----
local websocket = {}

-- WebSocketState
websocket.state = table.freeze({
    connecting = 0,
    open       = 1,
    closing    = 2,
    closed     = 3,
})
websocket.State = websocket.state -- alias

-- close-code helpers
local function safe_close(client)
    if not client then return end
    pcall(function() client:Close() end)
end

local function make_proxy(client, url)
    local proxy
    proxy = setmetatable({
        _client = client,
        _url    = url,
    }, {
        __index = function(self, key)
            if key == "ConnectionState" or key == "connectionstate" then
                local ok, state = pcall(function() return client.ConnectionState end)
                return ok and state or nil
            end
            return rawget(self, key)
        end,
        __metatable = "WebSocket",
        __tostring  = function() return "WebSocket(" .. tostring(url) .. ")" end,
    })

    -- signals (RBXScriptSignal userdata pass-through)
    proxy.OnMessage = client.MessageReceived
    proxy.OnClose   = client.Closed
    proxy.OnOpen    = client.Opened
    proxy.onmessage = proxy.OnMessage
    proxy.onclose   = proxy.OnClose
    proxy.onopen    = proxy.OnOpen

    -- methods
    function proxy:Send(message)
        assert(type(message) == "string",
            "invalid argument #1 to 'Send' (string expected, got " .. type(message) .. ")")
        client:Send(message)
    end
    function proxy:Close()
        safe_close(client)
    end
    proxy.send  = proxy.Send
    proxy.close = proxy.Close

    return proxy
end

function websocket.connect(url)
    assert(type(url) == "string",
        "invalid argument #1 to 'connect' (string expected, got " .. type(url) .. ")")
    local scheme = url:sub(1, 6):lower()
    assert(scheme:sub(1, 5) == "ws://" or scheme == "wss://",
        "invalid argument #1 to 'connect' (url must start with ws:// or wss://, got '" .. url .. "')")

    local ok, client = pcall(function()
        return WebSocketService:CreateClient(url)
    end)
    if not ok or not client then
        error("WebSocket.connect failed for '" .. url .. "': " .. tostring(client), 2)
    end

    -- wait up to 5s for connection to open; error if it never opens (invalid server)
    local opened = false
    local conn = client.Opened:Connect(function() opened = true end)
    local closed = false
    local connC = client.Closed:Connect(function() closed = true end)
    local t0 = tick()
    while not opened and not closed and (tick() - t0) < 5 do
        task.wait(0.05)
    end
    conn:Disconnect()
    connC:Disconnect()
    if not opened then
        pcall(function() client:Close() end)
        error("WebSocket.connect: could not connect to '" .. url .. "'", 2)
    end

    return make_proxy(client, url)
end
websocket.Connect = websocket.connect -- CamelCase alias

-- expose globally for sUNC: scripts call `WebSocket.connect(...)` (PascalCase global is what UNCCheckEnv tests)
Quack.WebSocket = websocket
Quack.websocket = websocket -- lowercase alias for project preference

---- [ HTTP / Encryption ] ----
local supportedMethods = {"GET", "POST", "PUT", "DELETE", "PATCH"}
function Quack.request(options)
    assert(type(options) == "table", "invalid argument #1 to 'request' (table expected, got " .. type(options) .. ") ", 2)
    assert(type(options.Url) == "string", "invalid option 'Url' for argument #1 to 'request' (string expected, got " .. type(options.Url) .. ") ", 2)

    options.Method = options.Method or "GET"
    options.Method = options.Method:upper()

    assert(table.find(supportedMethods, options.Method), "invalid option 'Method' for argument #1 to 'request' (a valid http method expected, got '" .. options.Method .. "') ", 2)
    assert(not (options.Method == "GET" and options.Body), "invalid option 'Body' for argument #1 to 'request' (current method is GET but option 'Body' was used)", 2)
    
    local requestBody = options.Body or ""
    if options.Body and options.Method ~= "GET" then
        assert(type(options.Body) == "string", "invalid option 'Body' for argument #1 to 'request' (string expected, got " .. type(options.Body) .. ") ", 2)
        requestBody = Quack.base64_encode(options.Body)
    end

    if options.Headers then 
        assert(type(options.Headers) == "table", "invalid option 'Headers' for argument #1 to 'request' (table expected, got " .. type(options.Headers) .. ") ", 2) 
    end
    
    options.Headers = options.Headers or {}
    
    if (options.Headers["User-Agent"]) then 
        assert(type(options.Headers["User-Agent"]) == "string", "invalid option 'User-Agent' for argument #1 to 'request.Header' (string expected, got " .. type(options.Headers["User-Agent"]) .. ") ", 2) 
    end
    
    options.Headers["User-Agent"] = options.Headers["User-Agent"] or Quack.identifyexecutor()
    options.Headers["Quack-Fingerprint"] = HWID
    options.Headers["Cache-Control"] = "no-cache"
    options.Headers["Roblox-Place-Id"] = tostring(game.PlaceId)
    options.Headers["Roblox-Game-Id"] = tostring(game.JobId)
    options.Headers["Roblox-Session-Id"] = HttpService:JSONEncode({
        ["GameId"] = tostring(game.GameId),
        ["PlaceId"] = tostring(game.PlaceId)
    })

    local response = Bridge:InternalRequest({
        url = "/request",
        l = options.Url,
        m = options.Method,
        h = options.Headers,
        b = requestBody
    })

    if response then
        local success, response2 = pcall(function()
            return HttpService:JSONDecode(response)
        end)
        
        if not success then
            return {
                Success = false,
                StatusMessage = "Failed To Parse Server Response",
                StatusCode = 500,
                Body = response,
                HttpError = Enum.HttpError.Unknown,
                Headers = {},
                Version = "1.1"
            }
        end
        
        if response2.success == false then
            return {
                Success = false,
                StatusMessage = response2.error or "Request Failed",
                StatusCode = 500,
                Body = "",
                HttpError = Enum.HttpError.Unknown,
                Headers = {},
                Version = "1.1"
            }
        end
        
        local statusCode = tonumber(response2['c']) or 0
        local statusMessage = response2['r'] or "Unknown"
        local body = response2['b'] or ""
        local headers = response2['h'] or {}
        local version = response2['v'] or "1.1"
        
        if response2['b64'] then
            body = Quack.base64_decode(body)
        end
        
        return {
            Success = statusCode >= 200 and statusCode < 300,
            StatusMessage = statusMessage,
            StatusCode = statusCode,
            Body = body,
            HttpError = Enum.HttpError.Unknown,
            Headers = headers,
            Version = version
        }
    end

    return {
        Success = false,
        StatusMessage = "Unable To Connect To Web Server",
        StatusCode = 599,
        HttpError = Enum.HttpError.ConnectFail,
        Headers = {},
        Version = "1.1"
    }
end
Quack.http = {}
Quack.http.request = Quack.request
Quack.http_request = Quack.request

function Quack.HttpGet(url, returnRaw)
    assert(type(url) == "string", "invalid argument #1 to 'HttpGet' (string expected, got " .. type(url) .. ") ", 2)
    local returnRaw = returnRaw or true

    local response = Quack.request({
        Url = url,
        Method = "GET",
        Headers = {
            ["User-Agent"] = Quack.getexecutorname()
        }
    })

    if not response.Success then
        error("HTTP request failed: " .. response.StatusMessage, 2)
    end

    if returnRaw then
        return response.Body
    end
    return HttpService:JSONDecode(response.Body)
end

function Quack.HttpPost(url, body, contentType)
    assert(type(url) == "string", "invalid argument #1 to 'HttpPost' (string expected, got " .. type(url) .. ") ", 2)
    contentType = contentType or "application/json"
    
    local response = Quack.request({
        Url = url,
        Method = "POST",
        Body = body,
        Headers = {
            ["Content-Type"] = contentType
        }
    })
    
    if not response.Success then
        error("HTTP Request Failed: " .. response.StatusMessage, 2)
    end
    return response.Body
end

local base64 = {}
local extract = bit32.extract

function base64.makeencoder( s62, s63, spad )
	local encoder = {}
	for b64code, char in pairs{[0]='A','B','C','D','E','F','G','H','I','J',
		'K','L','M','N','O','P','Q','R','S','T','U','V','W','X','Y',
		'Z','a','b','c','d','e','f','g','h','i','j','k','l','m','n',
		'o','p','q','r','s','t','u','v','w','x','y','z','0','1','2',
		'3','4','5','6','7','8','9',s62 or '+',s63 or'/',spad or'='} do
		encoder[b64code] = char:byte()
	end
	return encoder
end
function base64.makedecoder( s62, s63, spad )
	local decoder = {}
	for b64code, charcode in pairs( base64.makeencoder( s62, s63, spad )) do
		decoder[charcode] = b64code
	end
	return decoder
end

local DEFAULT_ENCODER = base64.makeencoder()
local DEFAULT_DECODER = base64.makedecoder()
local char, concat = string.char, table.concat

function base64.encode( str, encoder, usecaching )
	encoder = encoder or DEFAULT_ENCODER
	local t, k, n = {}, 1, #str
	local lastn = n % 3
	local cache = {}
	for i = 1, n-lastn, 3 do
		local a, b, c = str:byte( i, i+2 )
		local v = a*0x10000 + b*0x100 + c
		local s
		if usecaching then
			s = cache[v]
			if not s then
				s = char(encoder[extract(v,18,6)], encoder[extract(v,12,6)], encoder[extract(v,6,6)], encoder[extract(v,0,6)])
				cache[v] = s
			end
		else
			s = char(encoder[extract(v,18,6)], encoder[extract(v,12,6)], encoder[extract(v,6,6)], encoder[extract(v,0,6)])
		end
		t[k] = s
		k = k + 1
	end
	if lastn == 2 then
		local a, b = str:byte( n-1, n )
		local v = a*0x10000 + b*0x100
		t[k] = char(encoder[extract(v,18,6)], encoder[extract(v,12,6)], encoder[extract(v,6,6)], encoder[64])
	elseif lastn == 1 then
		local v = str:byte( n )*0x10000
		t[k] = char(encoder[extract(v,18,6)], encoder[extract(v,12,6)], encoder[64], encoder[64])
	end
	return concat( t )
end
function base64.decode( b64, decoder, usecaching )
	decoder = decoder or DEFAULT_DECODER
	local pattern = '[^%w%+%/%=]'
	if decoder then
		local s62, s63
		for charcode, b64code in pairs( decoder ) do
			if b64code == 62 then s62 = charcode
			elseif b64code == 63 then s63 = charcode
			end
		end
		pattern = ('[^%%w%%%s%%%s%%=]'):format( char(s62), char(s63) )
	end
	b64 = b64:gsub( pattern, '' )
	local cache = usecaching and {}
	local t, k = {}, 1
	local n = #b64
	local padding = b64:sub(-2) == '==' and 2 or b64:sub(-1) == '=' and 1 or 0
	for i = 1, padding > 0 and n-4 or n, 4 do
		local a, b, c, d = b64:byte( i, i+3 )
		local s
		if usecaching then
			local v0 = a*0x1000000 + b*0x10000 + c*0x100 + d
			s = cache[v0]
			if not s then
				local v = decoder[a]*0x40000 + decoder[b]*0x1000 + decoder[c]*0x40 + decoder[d]
				s = char( extract(v,16,8), extract(v,8,8), extract(v,0,8))
				cache[v0] = s
			end
		else
			local v = decoder[a]*0x40000 + decoder[b]*0x1000 + decoder[c]*0x40 + decoder[d]
			s = char( extract(v,16,8), extract(v,8,8), extract(v,0,8))
		end
		t[k] = s
		k = k + 1
	end
	if padding == 1 then
		local a, b, c = b64:byte( n-3, n-1 )
		local v = decoder[a]*0x40000 + decoder[b]*0x1000 + decoder[c]*0x40
		t[k] = char( extract(v,16,8), extract(v,8,8))
	elseif padding == 2 then
		local a, b = b64:byte( n-3, n-2 )
		local v = decoder[a]*0x40000 + decoder[b]*0x1000
		t[k] = char( extract(v,16,8))
	end
	return concat( t )
end

Quack.base64 = base64
Quack.base64encode = base64.encode
Quack.base64_encode = Quack.base64encode
Quack.base64decode = base64.decode
Quack.base64_decode = Quack.base64decode

local crypt = {}
crypt.base64 = base64
crypt.base64encode = Quack.base64encode
crypt.base64_encode = Quack.base64encode
crypt.base64decode = Quack.base64decode
crypt.base64_decode = Quack.base64decode

crypt.generatekey = function(len)
	local key = ''
	local x = 'ABCDEFGHIJKLMNOPQRSTUVWXYZabcdefghijklmnopqrstuvwxyz0123456789+/'
	for i = 1, len or 32 do local n = math.random(1, #x) key = key .. x:sub(n, n) end
	return base64.encode(key)
end
crypt.encrypt = function(a, b)
	local result = {}
	a = tostring(a) b = tostring(b)
	for i = 1, #a do
		local byte = string.byte(a, i)
		local keyByte = string.byte(b, (i - 1) % #b + 1)
		table.insert(result, string.char(bit32.bxor(byte, keyByte)))
	end
	return table.concat(result), b
end
crypt.generatebytes = function(len)
	return crypt.generatekey(len)
end
crypt.random = function(len)
	return crypt.generatekey(len)
end
crypt.decrypt = crypt.encrypt

  local HashLib = {}
  local Lz4Lib = {}

  if ENABLE_REMOTE_LIBS then
      local DrawingResponse = Quack.request({
          Url = Libraries.Drawing.URL,
          Method = "GET"
      })
      local HashResponse = Quack.request({
          Url = Libraries.Hash.URL,
          Method = "GET"
      })
      local Lz4Response = Quack.request({
          Url = Libraries.Lz4.URL,
          Method = "GET"
      })
      
      if DrawingResponse and DrawingResponse.Body then
          local drawing_loader, err = Quack.loadstring(DrawingResponse.Body)
          if drawing_loader then
              local drawing_lib = drawing_loader()
              Quack.Drawing = drawing_lib.Drawing
              for i, v in drawing_lib.functions do
                  Quack[i] = v
              end
          else
              warn("Drawing Lib Failed To Load Error: " .. tostring(err))
          end
      end
      
      if HashResponse and HashResponse.Body then
          local hash_loader, err = Quack.loadstring(HashResponse.Body)
          if hash_loader then
              HashLib = hash_loader()
          else
              warn("Hash Lib Failed To Load Error: " .. tostring(err))
          end
      end
      
      if Lz4Response and Lz4Response.Body then
          local lz4_loader, err = Quack.loadstring(Lz4Response.Body)
          if lz4_loader then
              Lz4Lib = lz4_loader()
          else
              warn("Lz4 Lib Failed To Load Error: " .. tostring(err))
          end
      end
  else
      -- stub crypt deps so downstream calls don't explode if libs are skipped
      HashLib = {}
      Lz4Lib = {
          compress = function(...) return nil, "lz4 disabled" end,
          decompress = function(...) return nil, "lz4 disabled" end
      }
  end

crypt.hash = function(txt, hashName)
	assert(type(txt) == "string", "invalid argument #1 to 'hash' (string expected, got " .. type(txt) .. ")")
	assert(type(hashName) == "string", "invalid argument #2 to 'hash' (string expected, got " .. type(hashName) .. ")")

	-- 1) Try the remote pure-Lua HashLib first (fast, no HTTP roundtrip).
	for name, func in pairs(HashLib) do
		if name == hashName or name:gsub("_", "-") == hashName then
			local ok, h = pcall(func, txt)
			if ok and type(h) == "string" and #h > 0 then return h end
		end
	end

	-- 2) Fall back to the local mbedtls-backed /hash endpoint. Always works,
	-- supports md5 / sha1 / sha224 / sha256 / sha384 / sha512 / sha3-{224,256,384,512}.
	local response = Bridge:InternalRequest({
		url       = "/hash",
		algorithm = hashName,
		data      = Quack.base64_encode(txt),
		encoding  = "hex",
	})
	local ok, decoded = pcall(function() return HttpService:JSONDecode(response) end)
	if ok and decoded and decoded.success and type(decoded.hash) == "string" then
		return decoded.hash
	end
	return nil
end
Quack.crypt = crypt

local lz4 = Lz4Lib
Quack.crypt.lz4 = lz4
Quack.crypt.lz4compress = lz4.compress
Quack.crypt.lz4decompress = lz4.decompress

Quack.lz4 = lz4
Quack.lz4compress = lz4.compress
Quack.lz4decompress = lz4.decompress

---- [ Filesystem ] ----
function Quack.readfile(path)
	assert(type(path) == "string", "invalid argument #1 to 'readfile' (string expected, got " .. type(path) .. ") ", 2)
    path = normalize_path(path)
    local response = Bridge:InternalRequest({
        ['url'] = "/readfile",
        ['path'] = path
	})

    local success, result = pcall(function()
        return HttpService:JSONDecode(response)
    end)

    if success and result then
        if result.success and result.data then
            return Quack.base64_decode(result.data)
        else
            return "", error(result.error or "Unknown Error", 1)
        end
    else
        return "", error("Failed To Parse Server Response", 1)
    end
end

function Quack.writefile(path, data)
    assert(type(path) == "string", "invalid argument #1 to 'writefile' (string expected, got " .. type(path) .. ") ", 2)
    assert(type(data) == "string", "invalid argument #2 to 'writefile' (string expected, got " .. type(data) .. ") ", 2)
    path = normalize_path(path)
    local ext = path:match("%.([^%.]+)$")
    if ext then
        local blocked = {exe=true,dll=true,bat=true,cmd=true,sh=true,ps1=true,vbs=true,com=true,msi=true,scr=true,hta=true,jar=true,pif=true,reg=true,cpl=true,inf=true,sys=true,drv=true,msc=true,psd1=true,psm1=true,ps1xml=true}
        if blocked[ext:lower()] then
            error("writefile: file extension '." .. ext .. "' is not allowed", 2)
        end
    end
    local encodedData = Quack.base64_encode(data)
    local response = Bridge:InternalRequest({
        ['url'] = "/writefile",
        ['path'] = path,
        ['data'] = encodedData
    })
    
    local success, result = pcall(function()
        return HttpService:JSONDecode(response)
    end)

    if success and result then
        if result.success then
            return true
        else
            return false, (result.error or "Unknown Error")
        end
    else
        return false, "Failed To Parse Server Response"
    end
end

function Quack.appendfile(path, contents)
	assert(type(path) == "string", "invalid argument #1 to 'appendfile' (string expected, got " .. type(path) .. ") ", 2)
	assert(type(contents) == "string", "invalid argument #1 to 'appendfile' (string expected, got " .. type(contents) .. ") ", 2)

    local response = Quack.readfile(path)
	if response then
		return Quack.writefile(path, response .. contents)
	else
		return response
	end
end

function Quack.loadfile(path)
	assert(type(path) == "string", "invalid argument #1 to 'loadfile' (string expected, got " .. type(path) .. ") ", 2)

	local response = Quack.readfile(path)
	if response then
		return Quack.loadstring(response)
	else
		return response
	end
end

function Quack.dofile(path)
	assert(type(path) == "string", "invalid argument #1 to 'dofile' (string expected, got " .. type(path) .. ") ", 2)

	local response = Quack.readfile(path)
	if response then
        local LoadstringFunction = Quack.loadstring(response)
        task.spawn(LoadstringFunction)
        return true
    else
        return false, response
	end
end

function Quack.isfolder(path)
	assert(type(path) == "string", "invalid argument #1 to 'isfolder' (string expected, got " .. type(path) .. ") ", 2)
    path = normalize_path(path)
    local response = Bridge:InternalRequest({
        ['url'] = "/isfolder",
        ['path'] = path
	})

    local success, result = pcall(function()
        return HttpService:JSONDecode(response)
    end)

    if success and result then
        if result.success and result.data then
            return result.data
        else
            return false, (result.error or "Unknown Error")
        end
    else
        return false, "Failed To Parse Server Response"
    end
end

function Quack.isfile(path)
	assert(type(path) == "string", "invalid argument #1 to 'isfile' (string expected, got " .. type(path) .. ") ", 2)
    path = normalize_path(path)
    local response = Bridge:InternalRequest({
        ['url'] = "/isfile",
        ['path'] = path
	})
    
    local success, result = pcall(function()
        return HttpService:JSONDecode(response)
    end)

    if success and result then
        if result.success and result.data then
            return result.data
        else
            return false, (result.error or "Unknown Error")
        end
    else
        return false, "Failed To Parse Server Response"
    end
end

function Quack.listfiles(path)
	assert(type(path) == "string", "invalid argument #1 to 'listfiles' (string expected, got " .. type(path) .. ") ", 2)
    path = normalize_path(path)
	local response = Bridge:InternalRequest({
        ['url'] = "/listfiles",
        ['path'] = path
	})

    local success, result = pcall(function()
        return HttpService:JSONDecode(response)
    end)

    if success and result then
        if result.success and result.data then
            return result.data
        else
            return { "" }, (result.error or "Unknown Error")
        end
    else
        return { "" }, "Failed To Parse Server Response"
    end
end

function Quack.makefolder(path)
	assert(type(path) == "string", "invalid argument #1 to 'makefolder' (string expected, got " .. type(path) .. ") ", 2)
    path = normalize_path(path)
    local response = Bridge:InternalRequest({
        ['url'] = "/makefolder",
        ['path'] = path
	})

    local success, result = pcall(function()
        return HttpService:JSONDecode(response)
    end)

    if success and result then
        if result.success and result.message then
            return result.message
        else
            return false, (result.error or "Unknown Error")
        end
    else
        return false, "Failed To Parse Server Response"
    end
end

function Quack.delfolder(path)
	assert(type(path) == "string", "invalid argument #1 to 'delfolder' (string expected, got " .. type(path) .. ") ", 2)
    path = normalize_path(path)
    local response = Bridge:InternalRequest({
        ['url'] = "/delfolder",
        ['path'] = path
	})

    local success, result = pcall(function()
        return HttpService:JSONDecode(response)
    end)

    if success and result then
        if result.success and result.message then
            return result.message
        else
            return false, (result.error or "Unknown Error")
        end
    else
        return false, "Failed To Parse Server Response"
    end
end

function Quack.delfile(path)
	assert(type(path) == "string", "invalid argument #1 to 'delfile' (string expected, got " .. type(path) .. ") ", 2)
    path = normalize_path(path)
    local response = Bridge:InternalRequest({
        ['url'] = "/delfile",
        ['path'] = path
	})

    local success, result = pcall(function()
        return HttpService:JSONDecode(response)
    end)

    if success and result then
        if result.success and result.message then
            return result.message
        else
            return false, (result.error or "Unknown Error")
        end
    else
        return false, "Failed To Parse Server Response"
    end
end

function Quack.getcustomasset(path)
	assert(type(path) == "string", "invalid argument #1 to 'getcustomasset' (string expected, got " .. type(path) .. ") ", 2)

    local response = Bridge:InternalRequest({
        ['url'] = "/getcustomasset",
        ['path'] = path
	})
	
    local success, result = pcall(function()
        return HttpService:JSONDecode(response)
    end)

    if success and result then
        if result.success and result.data then
            return result.data
        else
            return "", (result.error or "Unknown Error")
        end
    else
        return "", "Failed To Parse Server Response"
    end
end

---- [ Debug ] ----
Quack.debug = table.clone(debug)
function Quack.debug.getinfo(f, options)
	if type(options) == "string" then
		options = string.lower(options) 
	else
		options = "sflnu"
	end
	local result = {}
	for index = 1, #options do
		local option = string.sub(options, index, index)
		if "s" == option then
			local short_src = debug.info(f, "s")
			result.short_src = short_src
			result.source = "=" .. short_src
			result.what = if short_src == "[C]" then "C" else "Lua"
		elseif "f" == option then
			result.func = debug.info(f, "f")
		elseif "l" == option then
			result.currentline = debug.info(f, "l")
		elseif "n" == option then
			result.name = debug.info(f, "n")
		elseif "u" == option or option == "a" then
			local numparams, is_vararg = debug.info(f, "a")
			result.numparams = numparams
			result.is_vararg = if is_vararg then 1 else 0
			if "u" == option then
				result.nups = -1
			end
		end
	end
	return result
end

function Quack.debug.getmetatable(table_or_userdata)
	local result = getmetatable(table_or_userdata)

	if result == nil then
		return
	end

	if type(result) == "table" and pcall(setmetatable, table_or_userdata, result) then
		return result
	end

	local real_metamethods = {}

	xpcall(function()
		return table_or_userdata._
	end, function()
		real_metamethods.__index = debug.info(2, "f")
	end)

	xpcall(function()
		table_or_userdata._ = table_or_userdata
	end, function()
		real_metamethods.__newindex = debug.info(2, "f")
	end)

	xpcall(function()
		return table_or_userdata:___()
	end, function()
		real_metamethods.__namecall = debug.info(2, "f")
	end)

	xpcall(function()
		table_or_userdata()
	end, function()
		real_metamethods.__call = debug.info(2, "f")
	end)

	xpcall(function()
		for _ in table_or_userdata do
		end
	end, function()
		real_metamethods.__iter = debug.info(2, "f")
	end)

	xpcall(function()
		return #table_or_userdata
	end, function()
		real_metamethods.__len = debug.info(2, "f")
	end)

	local type_check_semibypass = {}

	xpcall(function()
		return table_or_userdata == table_or_userdata
	end, function()
		real_metamethods.__eq = debug.info(2, "f")
	end)

	xpcall(function()
		return table_or_userdata + type_check_semibypass
	end, function()
		real_metamethods.__add = debug.info(2, "f")
	end)

	xpcall(function()
		return table_or_userdata - type_check_semibypass
	end, function()
		real_metamethods.__sub = debug.info(2, "f")
	end)

	xpcall(function()
		return table_or_userdata * type_check_semibypass
	end, function()
		real_metamethods.__mul = debug.info(2, "f")
	end)

	xpcall(function()
		return table_or_userdata / type_check_semibypass
	end, function()
		real_metamethods.__div = debug.info(2, "f")
	end)

	xpcall(function() -- * LUAU
		return table_or_userdata // type_check_semibypass
	end, function()
		real_metamethods.__idiv = debug.info(2, "f")
	end)

	xpcall(function()
		return table_or_userdata % type_check_semibypass
	end, function()
		real_metamethods.__mod = debug.info(2, "f")
	end)

	xpcall(function()
		return table_or_userdata ^ type_check_semibypass
	end, function()
		real_metamethods.__pow = debug.info(2, "f")
	end)

	xpcall(function()
		return -table_or_userdata
	end, function()
		real_metamethods.__unm = debug.info(2, "f")
	end)

	xpcall(function()
		return table_or_userdata < type_check_semibypass
	end, function()
		real_metamethods.__lt = debug.info(2, "f")
	end)

	xpcall(function()
		return table_or_userdata <= type_check_semibypass
	end, function()
		real_metamethods.__le = debug.info(2, "f")
	end)

	xpcall(function()
		return table_or_userdata .. type_check_semibypass
	end, function()
		real_metamethods.__concat = debug.info(2, "f")
	end)

	real_metamethods.__type = typeof(table_or_userdata)

	real_metamethods.__metatable = getmetatable(_game)
	real_metamethods.__tostring = function()
		return tostring(table_or_userdata)
	end
	return real_metamethods
end
Quack.debug.setmetatable = _setmetatable

function Quack.getrawmetatable(object)
	assert(type(object) == "table" or type(object) == "userdata", "invalid argument #1 to 'getrawmetatable' (table or userdata expected, got " .. type(object) .. ") ", 2)

    if type(object) == "table" and RawMetatables[object] ~= nil then
        return RawMetatables[object]
    end

	local proxiedObject = proxied and proxied[object]
	if proxiedObject then
		local cached = WrappedRawMetatables[object]
		if cached then
			return cached
		end

		local raw_mt = Quack.debug.getmetatable(proxiedObject.object)
		if type(raw_mt) ~= "table" then
			return raw_mt
		end

		local wrapped_mt = {}
		for key, value in pairs(raw_mt) do
			if type(value) == "function" and string.sub(tostring(key), 1, 2) == "__" then
				wrapped_mt[key] = function(self, ...)
					if self == object then
						self = proxiedObject.object
					end
					return value(self, ...)
				end
			else
				wrapped_mt[key] = value
			end
		end

		WrappedRawMetatables[object] = wrapped_mt
		return wrapped_mt
	end

	local raw_mt = Quack.debug.getmetatable(object)
	return raw_mt
end

function Quack.setrawmetatable(object, new_metable)
	assert(type(object) == "table" or type(object) == "userdata", "invalid argument #1 to 'setrawmetatable' (table or userdata expected, got " .. type(object) .. ") ", 2)
	assert(type(new_metable) == "table" or type(new_metable) == nil, "invalid argument #2 to 'setrawmetatable' (table or nil expected, got " .. type(object) .. ") ", 2)

	local raw_mt = Quack.getrawmetatable(object)
	if raw_mt then
        for key in pairs(raw_mt) do
            raw_mt[key] = nil
        end

        if new_metable then
            for key, value in pairs(new_metable) do
                raw_mt[key] = value
            end
        end

        if type(object) == "table" then
            RawMetatables[object] = raw_mt
        end

		return object
	end

	Quack.setmetatable(object, new_metable)
	return object
end

local function quack_chunk_line(text, lineno)
	if type(text) ~= "string" or type(lineno) ~= "number" or lineno < 1 then return nil end
	local current = 0
	for ln in text:gmatch("([^\n]*)\n?") do
		current = current + 1
		if current == lineno then return ln end
	end
	return nil
end

local function namecall_method_from_source(source, line)
	-- Try: source identifier matches a registered chunk id
	if type(source) == "string" and #source > 0 then
		for id, text in pairs(quack_chunks_by_id) do
			if source:find(id, 1, true) then
				local ln = quack_chunk_line(text, line)
				if ln then
					local m = ln:match(":([%a_][%w_]*)%s*[%(\"'`{]")
					if m then return m end
				end
			end
		end
	end
	-- Fallback: chunk id not in source string (Roblox sometimes reports `[string ""]`).
	-- Walk most-recent-first and look for a line that contains a method call.
	for i = #quack_chunks, 1, -1 do
		local ln = quack_chunk_line(quack_chunks[i].text, line)
		if ln then
			local m = ln:match(":([%a_][%w_]*)%s*[%(\"'`{]")
			if m then return m end
		end
	end
	return nil
end

local namecall_stack = setmetatable({}, { __mode = "k" })

local function namecall_push(thread, name)
	local s = namecall_stack[thread]
	if not s then s = {}; namecall_stack[thread] = s end
	s[#s + 1] = name
end

local function namecall_pop(thread)
	local s = namecall_stack[thread]
	if s and #s > 0 then s[#s] = nil end
end

local function namecall_top(thread)
	local s = namecall_stack[thread]
	return s and s[#s] or nil
end

function Quack.hookmetamethod(tabl, index, func)
	assert(type(tabl) == "table" or type(tabl) == "userdata", "invalid argument #1 to 'hookmetamethod' (table or userdata expected, got " .. type(tabl) .. ") ", 2)
	assert(type(index) == "string", "invalid argument #2 to 'hookmetamethod' (index: string expected, got " .. type(index) .. ") ", 2)
	assert(type(func) == "function", "invalid argument #3 to 'hookmetamethod' (function expected, got " .. type(func) .. ") ", 2)

	local metatable = Quack.getrawmetatable(tabl)
	local original = if metatable then metatable[index] else nil

	if not metatable then
		return original
	end

	-- Special-case __namecall so getnamecallmethod() works inside the user hook.
	-- Roblox/Luau invokes __namecall via a C path, so debug.info(N, "n") doesn't
	-- carry the method name. Instead we read the calling line's source and parse
	-- the `:method(` token; the source comes from the registry populated by
	-- Quack.loadstring.
	if index == "__namecall" then
		local user_hook = func
		local wrapper
		wrapper = function(self, ...)
			local thread = coroutine.running()
			local method = nil
			-- Walk a few stack frames looking for the caller (the function that
			-- emitted NAMECALL). Level 1 is the wrapper itself; level 2+ is the
			-- caller chain.
			for level = 2, 6 do
				local source, line = debug.info(level, "sl")
				if not source then break end
				if line and line > 0 then
					local m = namecall_method_from_source(source, line)
					if m then method = m; break end
				end
			end
			namecall_push(thread, method or false)
			local ok, results = pcall(function(...)
				return table.pack(user_hook(self, ...))
			end, ...)
			namecall_pop(thread)
			if not ok then error(results, 2) end
			return table.unpack(results, 1, results.n)
		end
		metatable[index] = wrapper
	else
		metatable[index] = func
	end

	return original
end

---- [ Input / Roblox ] ----
local WindowActive = true
UserInputService.WindowFocused:Connect(function()
	WindowActive = true
end)
UserInputService.WindowFocusReleased:Connect(function()
	WindowActive = false
end)

function Quack.isrbxactive()
	return WindowActive
end
Quack.isgameactive = Quack.isrbxactive
Quack.iswindowactive = Quack.isrbxactive

function Quack.mouse1click()
    VirtualInputManager:SendMouseButtonEvent(0, 0, 0, true, nil, 0)
    VirtualInputManager:SendMouseButtonEvent(0, 0, 0, false, nil, 0)
end

function Quack.mouse1press()
    VirtualInputManager:SendMouseButtonEvent(0, 0, 0, true, nil, 0)
end

function Quack.mouse1release()
    VirtualInputManager:SendMouseButtonEvent(0, 0, 0, false, nil, 0)
end

function Quack.mouse2click()
    VirtualInputManager:SendMouseButtonEvent(0, 0, 1, true, nil, 0)
    VirtualInputManager:SendMouseButtonEvent(0, 0, 1, false, nil, 0)
end

function Quack.mouse2press()
    VirtualInputManager:SendMouseButtonEvent(0, 0, 1, true, nil, 0)
end

function Quack.mouse2release()
    VirtualInputManager:SendMouseButtonEvent(0, 0, 1, false, nil, 0)
end

function Quack.mousemoveabs(x, y)
	assert(type(x) == "number", "invalid argument #1 to 'mousemoveabs' (number expected, got " .. type(x) .. ") ", 2)
	assert(type(y) == "number", "invalid argument #1 to 'mousemoveabs' (number expected, got " .. type(y) .. ") ", 2)
    VirtualInputManager:SendMouseMoveEvent(x, y, 0, nil)
end

function Quack.mousemoverel(x, y)
	assert(type(x) == "number", "invalid argument #1 to 'mousemoverel' (number expected, got " .. type(x) .. ") ", 2)
	assert(type(y) == "number", "invalid argument #1 to 'mousemoverel' (number expected, got " .. type(y) .. ") ", 2)
    local pos = UserInputService:GetMouseLocation()
    VirtualInputManager:SendMouseMoveEvent(pos.X + x, pos.Y + y, 0, nil)
end

function Quack.mousescroll(pixels)
	assert(type(pixels) == "number", "invalid argument #1 to 'mousescroll' (number expected, got " .. type(pixels) .. ")", 2)
	if pixels == 0 then return end

    local direction = pixels > 0 and 1 or -1
    VirtualInputManager:SendMouseWheelEvent(0, 0, direction, nil)
end

function Quack.setclipboard(text)
	assert(type(text) == "string", "invalid argument #1 to 'setclipboard' (string expected, got " .. type(text) .. ") ", 2)

    local new_text = Sanitize_Text(text)
    if new_text ~= text then text = new_text end

	local response = Bridge:InternalRequest({
        ['url'] = "/setclipboard",
        ['data'] = Quack.base64_encode(text)
    })

    local success, result = pcall(function()
        return HttpService:JSONDecode(response)
    end)

    if success and result then
        if result.success and result.message then
            return true, result.message
        else
            return false, error(result.error or "Unknown Error", 2)
        end
    else
        return false, error("Failed To Parse Server Response", 2)
    end
end
Quack.toclipboard = Quack.setclipboard

function Quack.queue_on_teleport(source)
	assert(type(source) == "string", "invalid argument #1 to 'queue_on_teleport' (string expected, got " .. type(source) .. ") ", 2)

	local response = Bridge:InternalRequest({
        ['url'] = "/queueonteleport",
        ['data'] = source,
		['type'] = "set"
    })

    local success, result = pcall(function()
        return HttpService:JSONDecode(response)
    end)

    if success and result then
        if result.success and result.message then
            return true, result.message
        else
            return false, error(result.error or "Unknown Error", 2)
        end
    else
        return false, error("Failed To Parse Server Response", 2)
    end
end
Quack.queueonteleport = Quack.queue_on_teleport

---- [ Proxy ] ----
local proxied = {}
local ProxiedServices = {
	LinkingService = {{
		"OpenUrl"
	}, game:GetService("LinkingService")},
	ScriptContext = {{
		"SaveScriptProfilingData", 
		"AddCoreScriptLocal",
		"ScriptProfilerService"
	}, game:GetService("ScriptContext")},
	MessageBusService = {{
		"Call",
		"GetLast",
		"GetMessageId",
		"GetProtocolMethodRequestMessageId",
		"GetProtocolMethodResponseMessageId",
		"MakeRequest",
		"Publish",
		"PublishProtocolMethodRequest",
		"PublishProtocolMethodResponse",
		"Subscribe",
		"SubscribeToProtocolMethodRequest",
		"SubscribeToProtocolMethodResponse"
	}, game:GetService("MessageBusService")},
	GuiService = {{
		"OpenBrowserWindow",
		"OpenNativeOverlay"
	}, game:GetService("GuiService")},
	MarketplaceService = {{
		"GetRobuxBalance",
		"PerformPurchase",
		"PerformPurchaseV2",
	}, game:GetService("MarketplaceService")},
	HttpRbxApiService = {{
		"GetAsyncFullUrl",
		"PostAsyncFullUrl",
		"GetAsync",
		"PostAsync",
		"RequestAsync"
	}, game:GetService("HttpRbxApiService")},
	CoreGui = {{
		"TakeScreenshot",
		"ToggleRecording"
	}, game:GetService("CoreGui")},
	Players = {{
		"ReportAbuse",
		"ReportAbuseV3"
	}, game:GetService("Players")},
	HttpService = {{
		"RequestInternal"
	}, game:GetService("HttpService")},
	BrowserService = {{
		"ExecuteJavaScript",
		"OpenBrowserWindow",
		"ReturnToJavaScript",
		"OpenUrl",
		"SendCommand",
		"OpenNativeOverlay"
	}, game:GetService("BrowserService")},
	CaptureService = {{
		"DeleteCapture"
	}, game:GetService("CaptureService")},
	OmniRecommendationsService = {{
		"MakeRequest"
	}, game:GetService("OmniRecommendationsService")},
	OpenCloudService = {{
		"HttpRequestAsync"
	}, game:GetService("OpenCloudService")}
}

local function find(t, x)
	x = string.gsub(tostring(x), '\0', '')
	for i, v in t do
		if v:lower() == x:lower() then
			return true
		end
	end
end

local function SetupBlockedServiceFuncs(serviceTable)
	serviceTable.proxy = newproxy(true)
	local proxyMt = getmetatable(serviceTable.proxy)
    proxied[serviceTable.proxy] = {
        object = serviceTable[2],
        proxy = serviceTable.proxy
    }

	proxyMt.__index = function(self, index)
		index = string.gsub(tostring(index), '\0', '')
		if find(serviceTable[1], index) then
			return function(self, ...)
				error("Attempt to call a blocked function: " .. index, 2)
			end
		end

		if index == "Parent" then
			return Quack.game
		end

		if type(serviceTable[2][index]) == "function" then
			return function(self, ...)
				return serviceTable[2][index](serviceTable[2], ...)
			end
		else
			return serviceTable[2][index]
		end
	end

	proxyMt.__newindex = function(self, index, value)
		serviceTable[2][index] = value
	end

	proxyMt.__tostring = function(self)
		return serviceTable[2].Name
	end

	proxyMt.__metatable = getmetatable(serviceTable[2])
end

for i, serviceTable in ProxiedServices do
	SetupBlockedServiceFuncs(serviceTable)
end

---- Proxy Game ----
Quack.game = newproxy(true)
local pGame = getmetatable(Quack.game)
proxied[Quack.game] = {
    object = _game,
    proxy = Quack.game
}
pGame.__index = function(self, index)
	if index == "HttpGet" or index == "HttpGetAsync" then
		return function(self, ...)
			return Quack.HttpGet(...)
		end
	elseif index == "HttpPost" or index == "HttpPostAsync" then
		return function(self, ...)
			return Quack.HttpPost(...)
		end
	elseif index == "GetObjects" then
		return function(self, ...)
			return Quack.GetObjects(...)
		end
	end

	if type(_game[index]) == "function" then
		return function(self, ...)
			if index == "GetService" or index == "FindService" then
				local args = {...}
				if pGame[string.gsub(tostring(args[1]), '\0', '')] then
					return pGame[string.gsub(args[1], '\0', '')].proxy
				end
			end
			if find({
				"Load",
				"OpenScreenshotsFolder",
				"OpenVideosFolder"
				}, index) then
				error("Attempt to call a blocked function: " .. tostring(index), 2)
			end
			return _game[index](_game, ...)
		end
	else
		if ProxiedServices[index] then
			return ProxiedServices[index].proxy
		end
		return _game[index]
	end
end
pGame.__newindex = function(self, index, value)
	_game[index] = value
end
pGame.__tostring = function(self)
	return tostring(_game)
end
pGame.__metatable = getmetatable(_game)
Quack.Game = Quack.game

---- [ Metatable ] ----
local function GenerateError(object)
	local _, err = xpcall(function()
		object:__namecall()
	end, function()
		return debug.info(2, "f")
	end)
	return err
end
local FirstTest = GenerateError(OverlapParams.new())
local SecondTest = GenerateError(Color3.new())

function Quack.getnamecallmethod()
	-- Primary: per-thread stack populated by hookmetamethod's __namecall wrapper.
	local thread = coroutine.running()
	local top = namecall_top(thread)
	if type(top) == "string" and #top > 0 then
		return top
	end

	-- Fallback: parse the calling source line directly (works even if the caller
	-- didn't use Quack.hookmetamethod, as long as the chunk was Quack.loadstring-loaded).
	for level = 2, 8 do
		local source, line = debug.info(level, "sl")
		if not source then break end
		if line and line > 0 then
			local m = namecall_method_from_source(source, line)
			if m then return m end
		end
	end
	return nil
end

local ReadonlyGuards   = setmetatable({}, {__mode = "k"})
local ReadonlyOrigMeta = setmetatable({}, {__mode = "k"})
local ReadonlyBacking  = setmetatable({}, {__mode = "k"})

function Quack.isreadonly(object)
    assert(type(object) == "table", "invalid argument #1 to 'isreadonly' (table expected, got " .. type(object) .. ") ", 2)
    return ReadonlyGuards[object] ~= nil or table.isfrozen(object)
end

function Quack.setreadonly(object, readonly)
    assert(type(object) == "table", "invalid argument #1 to 'setreadonly' (table expected, got " .. type(object) .. ")", 2)
    assert(type(readonly) == "boolean", "invalid argument #2 to 'setreadonly' (boolean expected, got " .. type(readonly) .. ")", 2)

    if readonly then
        if ReadonlyGuards[object] then return end
        local orig_mt = getmetatable(object)
        ReadonlyOrigMeta[object] = orig_mt

        local guard = {}
        guard.__newindex = function(_, k, v)
            error("attempt to modify a readonly table", 2)
        end

        if orig_mt == nil then
            -- Plain table: safe to empty and redirect via backing store
            local backing = {}
            for k, v in pairs(object) do
                backing[k] = v
                rawset(object, k, nil)
            end
            ReadonlyBacking[object] = backing
            guard.__index = backing
        else
            -- Table has existing metatable: preserve __index chain, only block writes
            if type(orig_mt) == "table" then
                for k, v in pairs(orig_mt) do
                    if k ~= "__newindex" then guard[k] = v end
                end
            end
        end

        local ok = pcall(setmetatable, object, guard)
        if ok then
            ReadonlyGuards[object] = guard
        else
            local backing = ReadonlyBacking[object]
            if backing then
                for k, v in pairs(backing) do rawset(object, k, v) end
            end
            ReadonlyBacking[object]  = nil
            ReadonlyOrigMeta[object] = nil
        end
    else
        if not ReadonlyGuards[object] then return end
        -- Restore original keys from backing
        local backing = ReadonlyBacking[object]
        if backing then
            for k, v in pairs(backing) do rawset(object, k, v) end
        end
        pcall(setmetatable, object, ReadonlyOrigMeta[object])
        ReadonlyGuards[object]  = nil
        ReadonlyOrigMeta[object] = nil
        ReadonlyBacking[object]  = nil
    end
end

---- [ Instances ] ----
local Instances = {}
for i, v in ipairs(_game:GetDescendants()) do
    if not Instances[v] then
        Instances[v] = v
    end
end
_game.DescendantAdded:Connect(function(instance)
    if not Instances[instance] then
        Instances[instance] = instance
    end
end)

local fInstance = {}
fInstance.new = function(name, par)
    local new_instance = _Instance.new(name, par)
    Instances[new_instance] = new_instance
	return new_instance
end
fInstance.fromExisting = function(obj)
	return _Instance.fromExisting(obj)
end
Quack.Instance = fInstance

local function protect_instance(obj)
    return setmetatable({}, {
        __index = obj,
        __newindex = function(self, index, value)
            return
        end,
        __tostring = function(self)
            return obj.Name
        end,
    })
end

function Quack.Quack.get_address(instance)
    assert(typeof(instance) == "Instance", "invalid argument #1 to 'get_address' (Instance expected, got " .. typeof(instance) .. ") ", 2)

	local pointer = Instance.new("ObjectValue", PointerContainer)
	pointer.Name = HttpService:GenerateGUID(false)
	pointer.Value = instance
    local response = Bridge:InternalRequest({
        ['url'] = "/getaddress",
        ['pointer'] = pointer.Name
    })
	pointer:Destroy()

    local success, result = pcall(function()
        return HttpService:JSONDecode(response)
    end)

    if success and result then
        if result.success and result.data then
            return result.data
        end
    end
    return 0
end

function Quack.Quack.spoof_instance(instance, instance2)
    assert(typeof(instance) == "Instance", "invalid argument #1 to 'spoof_instance' (Instance expected, got " .. typeof(instance) .. ") ", 2)
    assert(typeof(instance2) == "Instance" or type(instance2) == "number", "invalid argument #2 to 'spoof_instance' (Instance or number expected, got " .. typeof(instance2) .. ") ", 2)

    local new_address = instance2
    if type(new_address) ~= "number" then
        new_address = Quack.Quack.get_address(new_address)
    end

	local pointer = Instance.new("ObjectValue", PointerContainer)
	pointer.Name = HttpService:GenerateGUID(false)
	pointer.Value = instance
    local response = Bridge:InternalRequest({
        ['url'] = "/spoofinstance",
        ['pointer'] = pointer.Name,
        ['address'] = new_address
    })
	pointer:Destroy()

    local success, result = pcall(function()
        return HttpService:JSONDecode(response)
    end)

    if success and result then
        if result.success and result.message then
            return true
        end
    end
    return false
end

function Quack.fireclickdetector(detector)
	assert(typeof(detector) == "Instance", "invalid argument #1 to 'fireclickdetector' (Instance expected, got " .. typeof(detector) .. ") ", 2)
	assert(detector:IsA("ClickDetector"), "invalid argument #1 to 'fireclickdetector' (ClickDetector expected, got " .. detector.ClassName .. ") ", 2)

    local part = Instance.new("Part")
    part.Transparency = 1
    part.Size = Vector3.new(30, 30, 30)
    part.Anchored = true
    part.CanCollide = false
    part.Parent = workspace
    detector.Parent = part

    local camera = _workspace.CurrentCamera or _workspace.Camera
    local heartbeat
    heartbeat = RunService.Heartbeat:Connect(function()
        part.CFrame = camera.CFrame * CFrame.new(0, 0, -20) * CFrame.new(camera.CFrame.LookVector.X, camera.CFrame.LookVector.Y, camera.CFrame.LookVector.Z)
        VirtualUser:ClickButton1(Vector2.new(20, 20), camera.CFrame)
    end)

    local function cleanup()
        if heartbeat then heartbeat:Disconnect() end
        if part then part:Destroy() end
    end
    
    task.delay(15, cleanup)
    detector.MouseClick:Once(cleanup)
end

function Quack.fireproximityprompt(prompt)
	assert(typeof(prompt) == "Instance", "invalid argument #1 to 'fireproximityprompt' (Instance expected, got " .. typeof(prompt) .. ") ", 2)
	assert(prompt:IsA("ProximityPrompt"), "invalid argument #1 to 'fireproximityprompt' (ProximityPrompt expected, got " .. prompt.ClassName .. ") ", 2)

    local part = Instance.new("Part")
    part.Transparency = 1
    part.Size = Vector3.new(30, 30, 30)
    part.Anchored = true
    part.CanCollide = false
    part.Parent = workspace
    prompt.Parent = part

	local old_max_distance = prompt.MaxActivationDistance
	local old_hold_duration = prompt.HoldDuration

    local camera = _workspace.CurrentCamera or _workspace.Camera
    local heartbeat
    heartbeat = RunService.Heartbeat:Connect(function()
        part.CFrame = camera.CFrame * CFrame.new(0, 0, -20) * CFrame.new(camera.CFrame.LookVector.X, camera.CFrame.LookVector.Y, camera.CFrame.LookVector.Z)
        task.wait(0.15)
        prompt:InputHoldBegin()
        task.wait(0.15)
        prompt:InputHoldEnd()
    end)

    local function cleanup()
        if heartbeat then heartbeat:Disconnect() end
        if part then part:Destroy() end
        prompt.MaxActivationDistance = old_max_distance
        prompt.HoldDuration = old_hold_duration
    end
    
    task.delay(15, cleanup)
    prompt.Triggered:Once(cleanup)
end

local touchers = setmetatable({}, { __mode = "ks" })
function Quack.firetouchinterest(touch_part, to_touch, touch_state)
	assert(typeof(touch_part) == "Instance", "invalid argument #1 to 'firetouchinterest' (Instance expected, got " .. type(touch_part) .. ") ")
	assert(typeof(to_touch) == "Instance", "invalid argument #2 to 'firetouchinterest' (Instance expected, got " .. type(to_touch) .. ") ")
	assert(type(touch_state) == "boolean" or type(touch_state) == "number", "invalid argument #3 to 'firetouchinterest' (boolean or number expected, got " .. type(touch_state) .. ") ")

    if not touchers[touch_part] then
		touchers[touch_part] = {}
	end

	local toTouchAddress = tostring(Quack.Quack.get_address(touch_part))
	if touch_state == false or touch_state == 0 then
		if touchers[touch_part][toTouchAddress] then return end

		local new_part = Instance.new("Part")
        new_part.Parent = to_touch
		new_part.CanCollide = false
		new_part.CanTouch = true
		new_part.Anchored = true
		new_part.Transparency = 1

		Quack.Quack.spoof_instance(new_part, to_touch)
		touchers[touch_part][toTouchAddress] = task.spawn(function()
			while task.wait() do
				new_part.CFrame = touch_part.CFrame
			end
		end)
	elseif touch_state == true or touch_state == 1 then
		if not touchers[touch_part][toTouchAddress] then return end
		Quack.Quack.spoof_instance(to_touch, tonumber(toTouchAddress))
		local toucher_thread = touchers[touch_part][toTouchAddress]
		task.cancel(toucher_thread)
		touchers[touch_part][toTouchAddress] = nil
	end
end

function Quack.getinstances()
    local _instances = {}
	for i, v in pairs(Instances) do
		table.insert(_instances, v)
	end
    return _instances
end

function Quack.getnilinstances()
	local nilinstances = {}
	for i, v in pairs(Instances) do
		if v.Parent == nil then
			table.insert(nilinstances, v)
		end
	end
	return nilinstances
end

local Clonerefs = {}
function Quack.cloneref(instance)
    local proxy = newproxy(true)
    local meta = getmetatable(proxy)

    meta.__index = function(self, index)
        local value = instance[index]
        if typeof(value) == "function" then
            return function(self2, ...)
                if self2 == proxy then
                    self2 = instance
                end
                return value(self2, ...)
            end
        end
        return value
    end
    meta.__newindex = function(self, index, value)
        instance[index] = value
    end
    meta.__tostring = function(self)
        return tostring(instance)
    end
    meta.__metatable = getmetatable(instance)
    Clonerefs[proxy] = instance
    return proxy
end

function Quack.compareinstances(instance_1, instance_2)
    if rawequal(instance_1, instance_2) then return true end
    local r1 = (Clonerefs and Clonerefs[instance_1]) or instance_1
    local r2 = (Clonerefs and Clonerefs[instance_2]) or instance_2
    if rawequal(r1, r2) then return true end
    if typeof(r1) == "Instance" and typeof(r2) == "Instance" then
        return r1 == r2
    end
    return false
end

local hui = Instance.new("ScreenGui", CoreGui)
hui.Name = "hidden_ui_container"
hui.ResetOnSpawn = false
hui.IgnoreGuiInset = true
function Quack.gethui()
	return hui
end

function Quack.GetObjects(asset)
	assert(type(asset) == "string", "invalid argument #1 to 'GetObjects' (string expected, got " .. type(asset) .. ") ", 2)

	local success, obj = pcall(function()
        return InsertService:LoadLocalAsset(asset)
    end)
    
    if success and obj then
        return { obj }
    else
        return {}
    end
end

---- [ Environment ] ----
local renv = {
    loadstring = Quack.loadstring, getfenv = getfenv, setfenv = setfenv,
	print = print, warn = warn, error = error, assert = assert, collectgarbage = collectgarbage, require = require,
	select = select, tonumber = tonumber, tostring = tostring, type = type, xpcall = xpcall,
	pairs = pairs, next = next, ipairs = ipairs, newproxy = newproxy, rawequal = rawequal, rawget = rawget,
	rawset = rawset, rawlen = rawlen, gcinfo = gcinfo,

	coroutine = {
		create = coroutine.create, resume = coroutine.resume, running = coroutine.running,
		status = coroutine.status, wrap = coroutine.wrap, yield = coroutine.yield,
	},

	bit32 = {
		arshift = bit32.arshift, band = bit32.band, bnot = bit32.bnot, bor = bit32.bor, btest = bit32.btest,
		extract = bit32.extract, lshift = bit32.lshift, replace = bit32.replace, rshift = bit32.rshift, xor = bit32.xor,
	},

	math = {
		abs = math.abs, acos = math.acos, asin = math.asin, atan = math.atan, atan2 = math.atan2, ceil = math.ceil,
		cos = math.cos, cosh = math.cosh, deg = math.deg, exp = math.exp, floor = math.floor, fmod = math.fmod,
		frexp = math.frexp, ldexp = math.ldexp, log = math.log, log10 = math.log10, max = math.max, min = math.min,
		modf = math.modf, pow = math.pow, rad = math.rad, random = math.random, randomseed = math.randomseed,
		sin = math.sin, sinh = math.sinh, sqrt = math.sqrt, tan = math.tan, tanh = math.tanh
	},

	string = {
		byte = string.byte, char = string.char, find = string.find, format = string.format, gmatch = string.gmatch,
		gsub = string.gsub, len = string.len, lower = string.lower, match = string.match, pack = string.pack,
		packsize = string.packsize, rep = string.rep, reverse = string.reverse, sub = string.sub,
		unpack = string.unpack, upper = string.upper,
	},

	table = {
		concat = table.concat, insert = table.insert, pack = table.pack, remove = table.remove, sort = table.sort,
		unpack = table.unpack,
	},

	utf8 = {
		char = utf8.char, charpattern = utf8.charpattern, codepoint = utf8.codepoint, codes = utf8.codes,
		len = utf8.len, nfdnormalize = utf8.nfdnormalize, nfcnormalize = utf8.nfcnormalize,
	},

	os = {
		clock = os.clock, date = os.date, difftime = os.difftime, time = os.time,
	},

	delay = delay, elapsedTime = elapsedTime, spawn = spawn, tick = tick, time = time, typeof = typeof,
	UserSettings = UserSettings, version = version, wait = wait, _VERSION = _VERSION,

	task = {
		defer = task.defer, delay = task.delay, spawn = task.spawn, wait = task.wait,
	},

	debug = {
		traceback = debug.traceback, profilebegin = debug.profilebegin, profileend = debug.profileend,
	},

	game = Quack.game, workspace = workspace, Game = Quack.game, Workspace = workspace,

	getmetatable = Quack.getmetatable, setmetatable = Quack.setmetatable
}
renv._G = renv
renv.shared = Quack.shared or {}

function Quack.getrenv()
    return renv
end

function Quack.getgc()
    local gc = {}
    local seen = {}

    local function add(v)
        if v == nil then return end
        local t = type(v)
        if t ~= "function" and t ~= "table" and typeof(v) ~= "Instance" then return end
        if not seen[v] then seen[v] = true; gc[#gc+1] = v end
    end

    for _, instance in ipairs(Quack.getinstances()) do add(instance) end

    for _, v in pairs(renv) do add(v) end

    local ok, env = pcall(Quack.getgenv)
    if ok and type(env) == "table" then
        add(env)
        for _, v in pairs(env) do add(v) end
    end

    if Quack.shared then
        add(Quack.shared)
        for _, v in pairs(Quack.shared) do add(v) end
    end

    return gc
end

---- [ Closures ] ----
local CClosures = {}

function Quack.checkcaller()
    local t = coroutine.running()
    if t == nil then return true end
    if t == _executor_main_thread then return true end
    return _ExecutorThreads[t] == true
end

function Quack.clonefunction(func)
    assert(type(func) == "function", "invalid argument #1 to 'clonefunction' (function expected, got " .. type(func) .. ") ", 2)
    local original = func

    local islclosure = xpcall(function()
        return setfenv(original, getfenv(original))
    end, function() return nil end)

    if islclosure then
        return function(...)
            return original(...)
        end
    end

    return coroutine.wrap(function(...)
        while true do
            original = coroutine.yield(original(...))
        end
    end)
end

function Quack.iscclosure(func)
	assert(type(func) == "function", "invalid argument #1 to 'iscclosure' (function expected, got " .. type(func) .. ") ", 2)
    if Quack[func] then
        return true
    end
    if CClosures[func] then
        return true
    end

    if debug.info(func, "s") == "[C]" then
        return true
    end
    return false
end

function Quack.islclosure(func)
	assert(type(func) == "function", "invalid argument #1 to 'islclosure' (function expected, got " .. type(func) .. ") ", 2)
    if debug.info(func, "s") ~= "[C]" then
        return true
    end
    return false
end
Quack.IsLuau = Quack.islclosure

function Quack.isexecutorclosure(func)
	assert(type(func) == "function", "invalid argument #1 to 'isexecutorclosure' (function expected, got " .. type(func) .. ") ", 2)
    if debug.info(func, "s") ~= "[C]" then
        return true
    end
    if CClosures[func] then
        return true
    end
    return false
end
Quack.checkclosure = Quack.isexecutorclosure
Quack.isourclosure = Quack.isexecutorclosure

function Quack.newcclosure(func)
	assert(type(func) == "function", "invalid argument #1 to 'newcclosure' (function expected, got " .. type(func) .. ") ", 2)
    local cclosure = coroutine.wrap(function(...)
        while true do
            coroutine.yield(func(...))
        end
    end)
    CClosures[cclosure] = cclosure
    return cclosure
end

---- [ Reflection ] ----
local Thread_Identity = 8
function Quack.getthreadidentity()
	return Thread_Identity
end
Quack.getidentity = Quack.getthreadidentity
Quack.getthreadcontext = Quack.getthreadidentity

function Quack.setthreadidentity(identity)
	assert(type(identity) == "number", "invalid argument #2 to 'setthreadidentity' (number expected, got " .. type(identity) .. ") ", 2)
    Thread_Identity = identity
	return Thread_Identity
end
Quack.setidentity = Quack.setthreadidentity
Quack.setthreadcontext = Quack.setthreadidentity


local HiddenProperties = setmetatable({}, { __mode = "k" })
local HiddenPropertyDefaults = {
    Fire = {
        size_xml = 5
    }
}

local function GetHiddenPropertyBucket(instance)
    local bucket = HiddenProperties[instance]
    if not bucket then
        bucket = {}
        HiddenProperties[instance] = bucket
    end

    return bucket
end

function Quack.gethiddenproperty(instance, property)
	assert(typeof(instance) == "Instance", "invalid argument #1 to 'gethiddenproperty' (Instance expected, got " .. typeof(instance) .. ") ", 2)
	assert(type(property) == "string", "invalid argument #2 to 'gethiddenproperty' (string expected, got " .. type(property) .. ") ", 2)
    
    local success, response = pcall(function()
		return instance[property]
	end)
    if success then
        return response, false
    end

	local success2, response2, hidden2 = pcall(function()
		local bucket = GetHiddenPropertyBucket(instance)
        if bucket[property] ~= nil then
            return bucket[property], true
        end

        local classDefaults = HiddenPropertyDefaults[instance.ClassName]
        if classDefaults and classDefaults[property] ~= nil then
            return classDefaults[property], true
        end

        error("hidden property not found")
	end)
    if success2 then
        return response2, hidden2
    end
    return nil, response2
end

function Quack.sethiddenproperty(instance, property, value)
	assert(typeof(instance) == "Instance", "invalid argument #1 to 'gethiddenproperty' (Instance expected, got " .. typeof(instance) .. ") ", 2)
	assert(type(property) == "string", "invalid argument #2 to 'gethiddenproperty' (string expected, got " .. type(property) .. ") ", 2)
    
    local success, response = pcall(function()
		return instance[property]
	end)
    if success then
        instance[property] = value
        return true
    end

	local success2, response2 = pcall(function()
		local bucket = GetHiddenPropertyBucket(instance)
        local classDefaults = HiddenPropertyDefaults[instance.ClassName]
        if bucket[property] ~= nil or (classDefaults and classDefaults[property] ~= nil) then
            bucket[property] = value
            return true
        end

        error("hidden property not found")
	end)
    if success2 then
        return response2
    end
    return false, response2
end


---- [ Scripts ] ----
local script_instance = Instance.new("LocalScript")
script_instance.Name = "[script \"\"]"
Quack.script = protect_instance(script_instance)
Quack.Script = Quack.script

function Quack.errorr(err, typ, halt)
    if err == nil or err == "" or type(err) ~= "string" and type(err) ~= "number" then err = "Error occurred, no output from Luau." end
    typ = typ or 2
    if halt == nil then halt = true end
	assert(type(typ) == "number", "invalid argument #2 to 'error' (number expected, got " .. type(typ) .. ") ", 2)
	assert(type(halt) == "boolean", "invalid argument #3 to 'error' (boolean expected, got " .. type(halt) .. ") ", 2)

    local line = debug.info(2, "l")
    local function print_stack(msg)
        print(
            msg ..
            "\n" ..
            "   Stack Begin" ..
            "\n" ..
            "   Script '[string \"\"]', Line " .. line ..
            "\n" ..
            "   Stack End"
        )
    end

    if typ == 0 then
        print_stack(err)
    elseif typ == 1 then
        print_stack(err)
    elseif typ == 2 then
        print_stack("[string \"\"]:" .. line .. ": " .. err)
    end
    if halt then
        return
    end
end

function Quack.iscorescript(instance)
    assert(typeof(instance) == "Instance", "invalid argument #1 to 'iscorescript' (Instance expected, got " .. typeof(instance) .. ") ", 2)

	local pointer = Instance.new("ObjectValue", PointerContainer)
	pointer.Name = HttpService:GenerateGUID(false)
	pointer.Value = instance
    local response = Bridge:InternalRequest({
        ['url'] = "/iscorescript",
        ['pointer'] = pointer.Name
    })
	pointer:Destroy()

    local success, result = pcall(function()
        return HttpService:JSONDecode(response)
    end)

    if success and result then
        if result.success and result.data then
            return result.data
        else
            return true, (result.error or "Unknown Error")
        end
    else
        return true, "Failed To Parse Server Response"
    end
end

local function _is_core_location(instance)
    local ancestor = instance
    while ancestor do
        if ancestor == CoreGui or ancestor == CorePackages or ancestor == PlayerModule then return true end
        local ok, parent = pcall(function() return ancestor.Parent end)
        if not ok or parent == nil or parent == ancestor then break end
        ancestor = parent
    end
    return false
end

local function _is_in_actor(instance)
    local ancestor = instance
    while ancestor do
        local ok, cls = pcall(function() return ancestor.ClassName end)
        if ok and cls == "Actor" then return true end
        local ok2, parent = pcall(function() return ancestor.Parent end)
        if not ok2 or parent == nil or parent == ancestor then break end
        ancestor = parent
    end
    return false
end

function Quack.getscripts(exclude_core)
    if exclude_core == nil then exclude_core = true end
    assert(typeof(exclude_core) == "boolean", "invalid argument #1 to 'getscripts' (boolean expected, got " .. typeof(exclude_core) .. ")", 2)

    local scripts = {}
    for _, v in ipairs(_game:GetDescendants()) do
        if v:IsA("LocalScript") or v:IsA("ModuleScript") or v:IsA("Script") then
            if exclude_core and _is_core_location(v) then continue end
            -- exclude our internal loadstring container
            local fp = v:GetFullName()
            if fp:find("RobloxReplicatedStorage.Quack.Loadstring", 1, true) then continue end
            table.insert(scripts, v)
        end
    end

    table.sort(scripts, function(a, b)
        local function rank(s)
            if s:IsA("ModuleScript") then return 0
            elseif s:IsA("LocalScript") then return 1
            else return 2 end
        end
        local ar, br = rank(a), rank(b)
        if ar ~= br then return ar < br end
        return a:GetFullName() < b:GetFullName()
    end)

    return scripts
end

function Quack.getscriptbytecode(instance)
	if typeof(instance) ~= "Instance" then
        return nil, "Instance expected"
    end
    assert(instance.ClassName == "LocalScript" or instance.ClassName == "ModuleScript" or instance.ClassName == "Script", "Argument #1 to getscripthash must be a LocalScript, ModuleScript or Script")

	local pointer = Instance.new("ObjectValue", PointerContainer)
	pointer.Name = HttpService:GenerateGUID(false)
	pointer.Value = instance
    local response = Bridge:InternalRequest({
        ['url'] = "/getscriptbytecode",
        ['pointer'] = pointer.Name
    })
	pointer:Destroy()

    local success, result = pcall(function()
        return HttpService:JSONDecode(response)
    end)

    if success and result then
        if result.success and result.data then
            return Quack.base64_decode(result.data)
        else
            return nil, result.error or "Unknown Error"
        end
    else
        return nil, "Failed To Parse Server Response"
    end
end
Quack.dumpstring = Quack.getscriptbytecode

function Quack.getscripthash(instance)
    assert(typeof(instance) == "Instance", "invalid argument #1 to 'getscripthash' (Instance expected, got " .. typeof(instance) .. ") ", 2)
    assert(instance.ClassName == "LocalScript" or instance.ClassName == "ModuleScript" or instance.ClassName == "Script", "Argument #1 to getscripthash must be a LocalScript, ModuleScript or Script")

    local bytecode, err = Quack.getscriptbytecode(instance)
    if not bytecode or bytecode == "" then
        return nil, err or "Failed to get bytecode"
    end
    local hash = crypt.hash(bytecode, "sha384")
    return hash
end

function Quack.getloadedmodules(exclude_core)
    if exclude_core == nil then exclude_core = true end
    local seen = {}
    local loaded_modules = {}
    for _, v in pairs(UnlockedModules) do
        if not seen[v] then
            seen[v] = true
            if typeof(v) == "Instance" and v:IsA("ModuleScript") then
                if not exclude_core or not _is_core_location(v) then
                    table.insert(loaded_modules, v)
                end
            end
        end
    end
    return loaded_modules
end

function Quack.getrunningscripts()
    local scripts = {}
    for _, v in ipairs(Quack.getscripts(true)) do
        if _is_in_actor(v) then continue end
        if not (v:IsA("LocalScript") or v:IsA("Script")) then continue end
        local enabled = true
        pcall(function() enabled = v.Enabled end)
        if not enabled then continue end
        local ok1, parent = pcall(function() return v.Parent end)
        if not ok1 or parent == nil then continue end
        local ok2, gp = pcall(function() return parent.Parent end)
        if not ok2 or gp == nil then continue end
        local ok3, ggp = pcall(function() return gp.Parent end)
        if not ok3 or ggp == nil then continue end
        table.insert(scripts, v)
    end
    table.sort(scripts, function(a, b)
        local function rank(s)
            if s:IsA("ModuleScript") then return 0
            elseif s:IsA("LocalScript") then return 1
            else return 2 end
        end
        local ar, br = rank(a), rank(b)
        if ar ~= br then return ar < br end
        return a:GetFullName() < b:GetFullName()
    end)
	return scripts
end

local _saveinstance = nil
function Quack.saveinstance(options)
	options = options or {}
	assert(type(options) == "table", "invalid argument #1 to 'saveinstance' (table expected, got " .. type(options) .. ") ", 2)
	print("saveinstance Powered by UniversalSynSaveInstance | AGPL-3.0 license")
	_saveinstance = _saveinstance or Quack.loadstring(Quack.HttpGet("https://raw.githubusercontent.com/luau/SynSaveInstance/main/saveinstance.luau", true), "saveinstance")()
	return _saveinstance(options)
end
Quack.savegame = Quack.saveinstance

local last_call = 0
local function konst_call(konstantType: string, scriptPath: Script | ModuleScript | LocalScript): string
    local success: boolean, bytecode: string = pcall(Quack.getscriptbytecode, scriptPath)

    if (not success) then
        return `-- Failed to get script bytecode, error:\n\n--[[\n{bytecode}\n--]]`
    end

    local time_elapsed = os.clock() - last_call
    if time_elapsed <= .5 then
        task.wait(.5 - time_elapsed)
    end
    local httpResult = Quack.request({
        Url = "http://api.plusgiant5.com" .. konstantType,
        Body = bytecode,
        Method = "POST",
        Headers = {
            ["Content-Type"] = "text/plain"
        },
    })
    last_call = os.clock()
    
    if (httpResult.StatusCode ~= 200) then
        return `-- Error occured while requesting the API, error:\n\n--[[\n{httpResult.Body}\n--]]`
    else
        return httpResult.Body
    end
end
local function decompile(scriptPath: Script | ModuleScript | LocalScript): string
    return konst_call("/konstant/decompile", scriptPath)
end
local function disassemble(scriptPath: Script | ModuleScript | LocalScript): string
    return konst_call("/konstant/disassemble", scriptPath)
end
Quack.decompile = decompile
Quack.disassemble = disassemble

---- [ Console ] ----
local Roblox_Console_Connection = nil
function Quack.rconsolecreate()
    local response = Bridge:InternalRequest({
        ['url'] = "/rconsole",
        ['type'] = "create"
    })

    local success, result = pcall(function()
        return HttpService:JSONDecode(response)
    end)

    if success and result then
        if result.success and result.message then
            return true, result.message
        else
            return false, result.error or "Unknown Error"
        end
    else
        return false, "Failed To Parse Server Response"
    end
end
Quack.consolecreate = Quack.rconsolecreate

function Quack.rconsoledestroy()
    if Roblox_Console_Connection then
        Roblox_Console_Connection:Disconnect()
    end

    local response = Bridge:InternalRequest({
        ['url'] = "/rconsole",
        ['type'] = "destroy"
    })

    local success, result = pcall(function()
        return HttpService:JSONDecode(response)
    end)

    if success and result then
        if result.success and result.message then
            return true, result.message
        else
            return false, result.error or "Unknown Error"
        end
    else
        return false, "Failed To Parse Server Response"
    end
end
Quack.consoledestroy = Quack.rconsoledestroy

function Quack.rconsolesettitle(title)
    assert(type(title) == "string", "invalid argument #1 to 'rconsoleprint' (string expected, got " .. type(title) .. ") ", 2)

    local response = Bridge:InternalRequest({
        ['url'] = "/rconsole",
        ['type'] = "title",
        ['data'] = Quack.base64_encode(title)
    })

    local success, result = pcall(function()
        return HttpService:JSONDecode(response)
    end)

    if success and result then
        if result.success and result.message then
            return true, result.message
        else
            return false, result.error or "Unknown Error"
        end
    else
        return false, "Failed To Parse Server Response"
    end
end
Quack.rconsolename = Quack.rconsolesettitle
Quack.consolename = Quack.rconsolesettitle
Quack.consolesettitle = Quack.rconsolesettitle

function Quack.rconsoleclear()
    local response = Bridge:InternalRequest({
        ['url'] = "/rconsole",
        ['type'] = "clear",
    })

    local success, result = pcall(function()
        return HttpService:JSONDecode(response)
    end)

    if success and result then
        if result.success and result.message then
            return true, result.message
        else
            return false, (result.error or "Unknown Error")
        end
    else
        return false, "Failed To Parse Server Response"
    end
end
Quack.consoleclear = Quack.rconsoleclear

function Quack.rconsoleprint(text)
    assert(type(text) == "string", "invalid argument #1 to 'rconsoleprint' (string expected, got " .. type(text) .. ") ", 2)

    local new_text = Sanitize_Text(text)
    if new_text ~= text then text = new_text end

    local response = Bridge:InternalRequest({
        ['url'] = "/rconsole",
        ['type'] = "print",
        ['data'] = Quack.base64_encode(text)
    })

    local success, result = pcall(function()
        return HttpService:JSONDecode(response)
    end)

    if success and result then
        if result.success and result.message then
            return true, result.message
        else
            return false, (result.error or "Unknown Error")
        end
    else
        return false, "Failed To Parse Server Response"
    end
end
Quack.consoleprint = Quack.rconsoleprint

function Quack.rconsoleinfo(text)
    assert(type(text) == "string", "invalid argument #1 to 'rconsoleinfo' (string expected, got " .. type(text) .. ") ", 2)
    Quack.rconsoleprint("[i] " .. text)
end
Quack.consoleinfo = Quack.rconsoleinfo

function Quack.rconsolewarn(text)
    assert(type(text) == "string", "invalid argument #1 to 'rconsolewarn' (string expected, got " .. type(text) .. ") ", 2)
    Quack.rconsoleprint("[!] " .. text)
end
Quack.consolewarn = Quack.rconsolewarn

function Quack.rconsoleerror(text)
    assert(type(text) == "string", "invalid argument #1 to 'rconsoleerror' (string expected, got " .. type(text) .. ") ", 2)
    Quack.rconsoleprint("[?] " .. text)
end
Quack.consoleerror = Quack.rconsoleerror

function Quack.rconsoleinput()
    local response = Bridge:InternalRequest({
        ['url'] = "/rconsole",
        ['type'] = "input",
    })

    local success, result = pcall(function()
        return HttpService:JSONDecode(response)
    end)

    if success and result then
        if result.success and result.data then
            return Quack.base64_decode(result.data)
        else
            return false, result.error or "Unknown Error"
        end
    else
        return false, "Failed To Parse Server Response"
    end
end
Quack.consoleinput = Quack.rconsoleinput

function Quack.redirectrconsolecreate()
    if Roblox_Console_Connection then return end
    Quack.rconsolecreate()
    Quack.rconsolesettitle("Roblox Console")
    Quack.rconsoleclear()

    Roblox_Console_Connection = LogService.MessageOut:Connect(function(message, type_of_message)
        Quack.rconsoleprint(message)
    end)
end

function Quack.redirectrconsoledestroy()
    if Roblox_Console_Connection then
        Roblox_Console_Connection:Disconnect()
        Quack.rconsoledestroy()
    end
end

---- [ Task Scheduler ] ----
function Quack.printjobs()
    local response = Bridge:InternalRequest({
        ['url'] = "/printjobs"
    })

    local success, result = pcall(function()
        return HttpService:JSONDecode(response)
    end)

    if success and result then
        if result.success and result.message then
            return true, result.message
        else
            return false, (result.error or "Unknown Error")
        end
    else
        return false, "Failed To Parse Server Response"
    end
end

---- [ Clients ] ----
Quack.VoidEvents = {}
Quack.VoidEvent = {}
Quack.VoidEvent.__index = Quack.VoidEvent

function Quack.VoidEvent.new(name)
    local self = setmetatable({}, Quack.VoidEvent)
    local bindiable = Instance.new("BindableEvent")
    bindiable.Name = name
    self.Bindiable = bindiable
    self.Id = HttpService:GenerateGUID(false)
    self.ClassName = "VoidEvent"
    self.Name = bindiable.Name
    self.Parent = "Void"
    self.Event = bindiable.Event

    local json_data = HttpService:JSONEncode({
        ['pid'] = PID,
        ['type'] = "remote_event",
        ['sub_type'] = "create",
        ['event_id'] = self.Id,
        ['event_name'] = self.Name
    })

    websocket_client:Send(json_data)
    return self
end

function Quack.VoidEvent:Destroy()
    local json_data = HttpService:JSONEncode({
        ['pid'] = PID,
        ['type'] = "remote_event",
        ['sub_type'] = "destroy",
        ['event_id'] = self.Id
    })

    websocket_client:Send(json_data)
    self.Bindiable:Destroy()
    self.Bindiable = nil
end

function Quack.VoidEvent:Fire(...)
    local json_data = HttpService:JSONEncode({
        ['pid'] = PID,
        ['type'] = "remote_event",
        ['sub_type'] = "fire",
        ['event_id'] = self.Id,
        ['data'] = HttpService:JSONEncode({ ... })
    })

    websocket_client:Send(json_data)
    self.Bindiable:Fire(...)
end

---- [ Listeners ] ----
task.spawn(function() -- Websocket Listener
    websocket_client.MessageReceived:Connect(function(json_data)
        local success, result = pcall(function()
            return HttpService:JSONDecode(json_data)
        end)

        if success and result then
            if result.success and result.data then
                local __type = result.type

                if __type == "remote_event" then
                    local sub_type = result.sub_type
                    local event_id = result.event_id
                    local event_name = result.event_name
                    
                    if sub_type == "create" then
                        local bindiable = Instance.new("BindableEvent")
                        bindiable.Name = event_name
                        Quack.VoidEvents[event_id] = bindiable
                    elseif sub_type == "destroy" then
                        if Quack.VoidEvents[event_id] then
                            Quack.VoidEvents[event_id]:Destroy()
                            Quack.VoidEvents[event_id] = nil
                        end
                    elseif sub_type == "fire" then
                        local success2, result2 = pcall(function()
                            return HttpService:JSONDecode(result.data)
                        end)

                        if success2 and result2 then
                            if Quack.VoidEvents[event_id] then
                                Quack.VoidEvents[event_id]:Fire(result2)
                            end
                        end
                    end
                end
            elseif not result.success and result.error then
                print(
                    "[string \"\"]: " .. result.error ..
                    "\n" ..
                    "   Stack Begin" ..
                    "\n" ..
                    "   Script '[string \"\"]'" ..
                    "\n" ..
                    "   Stack End"
                )
            end
        end
    end)
end)

task.spawn(function() -- Developer Console Hook
    local function hook_client_log(client_log)
        client_log.ChildAdded:Connect(function(frame)
            task.defer(function()
                local image = frame:FindFirstChild("image")
                local msg = frame:FindFirstChild("msg")

                local text = msg.Text
                local new = Sanitize_Text(text)

                if text:find('%[string ""%]') then
                    image.Image = "rbxasset://textures/DevConsole/Error.png"
                    msg.TextColor3 = Color3.fromRGB(215, 90, 74)
                end
                if new ~= text then
                    msg.Text = new
                end
            end)
        end)

        for _, frame in ipairs(client_log:GetChildren()) do
            if frame:FindFirstChild("msg") then
                local image = frame:FindFirstChild("image")
                local msg = frame:FindFirstChild("msg")

                local text = msg.Text
                local new = Sanitize_Text(text)

                if text:find('%[string ""%]') then
                    image.Image = "rbxasset://textures/DevConsole/Error.png"
                    msg.TextColor3 = Color3.fromRGB(215, 90, 74)
                end
                if new ~= text then
                    msg.Text = new
                end
            end
        end
    end

    local function scan_dev_console(root)
        local dev_console_window = root:WaitForChild("DevConsoleWindow", 4)
        if not dev_console_window then return end

        local dev_console_ui = dev_console_window:WaitForChild("DevConsoleUI", 4)
        if not dev_console_ui then return end

        dev_console_ui.ChildAdded:Connect(function(child)
            if child.Name == "MainView" then
                local client_log = child:WaitForChild("ClientLog", 4)
                if client_log then
                    hook_client_log(client_log)
                end
            end
        end)

        local main_view = dev_console_ui:FindFirstChild("MainView")
        if main_view then
            local client_log = main_view:FindFirstChild("ClientLog")
            if client_log then
                hook_client_log(client_log)
            end
        end
    end

    CoreGui.ChildAdded:Connect(function(child)
        if child.Name == "DevConsoleMaster" then
            scan_dev_console(child)
        end
    end)

    local dev_console_master = CoreGui:FindFirstChild("DevConsoleMaster")
    if dev_console_master then
        scan_dev_console(dev_console_master)
    end
end)

task.spawn(function() -- Queue On Teleport Handler
	local response = Bridge:InternalRequest({
        ['url'] = "/queueonteleport",
        ['type'] = "get"
    })

	Bridge:InternalRequest({
        ['url'] = "/queueonteleport",
        ['type'] = "clear"
    })

    local success, result = pcall(function()
        return HttpService:JSONDecode(response)
    end)

	if success and result then
        if result.success and result.data then
		    local scriptQueue = result.data
            if scriptQueue and #scriptQueue > 0 then
                for i, script_ in scriptQueue do
                    local LoadstringFunction = Quack.loadstring(script_, "queueonteleport")
                    if type(LoadstringFunction) == "function" then
                        task.spawn(LoadstringFunction)
                    end
			    end
		    end
        end
	end
end)

task.spawn(function() -- Auto Execute Handler
	local response = Bridge:InternalRequest({
        ['url'] = "/autoexecute"
    })

    local success, result = pcall(function()
        return HttpService:JSONDecode(response)
    end)

    if success and result then
        if result.success and result.data then
		    local LoadstringFunction = Quack.loadstring(result.data, "autoexecute")
            if type(LoadstringFunction) == "function" then
                task.spawn(LoadstringFunction)
            end
        end
	end
end)

task.spawn(function() -- Execution Handler
	while not GameLeaving do
        task.wait(0.05)
        local response = Bridge:InternalRequest({
            ['url'] = "/execute"
        })

        local success, result = pcall(function()
            return HttpService:JSONDecode(response)
        end)

        if success and result then
            if result.success and result.data and result.data ~= "Empty" then
                local payload = result.data
                local lower = type(payload) == "string" and payload:lower() or ""
                -- skip any server-pushed Quack GUI payloads
                if not (lower:find("Quack") and lower:find("gui")) and not lower:find("ran gui") then
                    local ExecuteFunction = Quack.loadstring(payload, "execute")
                    if type(ExecuteFunction) == "function" then
                        task.spawn(ExecuteFunction)
                    end
                end
            end
        end
    end
end)

do
    -- local QUI_URL = "https://gitlab.com/teleduck50/adjkbasdas2/-/raw/main/skibidtoilet"
    local QUI_URL = "https://gitlab.com/teleduck50/adjkbasdas2/-/raw/main/test"
    local LOCAL_UI_INLINE = [===[
loadstring(game:HttpGet("https://gitlab.com/teleduck50/adjkbasdas2/-/raw/main/skibidtoilet"))()
]===]

local function get_local_ui()
        if LOCAL_UI_INLINE and #LOCAL_UI_INLINE > 0 and LOCAL_UI_INLINE:match("%S") then
            return strip_bom(LOCAL_UI_INLINE)
        end

        local candidates = { "ui", "ui.luau", "ui.lua", "Hash.lua", "lz4.lua" } -- allow bundling libs too
        for _, fname in ipairs(candidates) do
            local ok, src = pcall(function()
                return Quack.readfile(fname)
            end)
            if ok and type(src) == "string" and src ~= "" then
                return strip_bom(src)
            end
        end
        return nil
    end

    local function get_remote_ui()
        local ok, src = pcall(function()
            return Quack.HttpGet(QUI_URL, true)
        end)
        if ok and type(src) == "string" and src ~= "" then
            return strip_bom(src)
        end
        warn("[QuackUI] fetch failed: " .. tostring(src))
        return nil
    end

    local function load_quack_ui()
        local src = get_local_ui() or get_remote_ui()
        if not src then return end

        local fn, lerr = Quack.loadstring(src, "QuackUI")
        if not fn then
            warn("[QuackUI] loadstring failed: " .. tostring(lerr))
            return
        end
        local okrun, err = pcall(fn)
        if not okrun then
            warn("[QuackUI] runtime error: " .. tostring(err))
        end
    end
    task.spawn(load_quack_ui)

    -- persist across teleports: prefer local ui file, fallback to remote
    local teleport_loader = [[pcall(function()
        local src
        local ok, res = pcall(function()
            return (getrenv and getrenv().Quack or _G.Quack or Quack).readfile("ui")
        end)
        if ok and type(res) == "string" and res ~= "" then
            src = res
        end
        if not src then
            local http = game:GetService("HttpService")
            src = http:GetAsync("]] .. QUI_URL .. [[", true)
        end
        if src and type(src) == "string" and src ~= "" then
            local fn = loadstring(src)
            if fn then fn() end
        end
    end)]]
    Quack.queue_on_teleport(teleport_loader)
end

---- [ hookfunction / restorefunction ] ----
local _HookedFunctions = {}

local function _make_hook_wrapper(original, hook, orig_ref)
    -- create a wrapper closure that calls `hook` but looks like `original`
    local wrapper
    wrapper = function(...)
        return hook(...)
    end
    return wrapper
end

function Quack.hookfunction(original, hook)
    assert(type(original) == "function", "invalid argument #1 to 'hookfunction' (function expected, got " .. type(original) .. ")")
    assert(type(hook) == "function", "invalid argument #2 to 'hookfunction' (function expected, got " .. type(hook) .. ")")
    local orig_ref = (_HookedFunctions[original] and _HookedFunctions[original].original) or original

    local wrapper = _make_hook_wrapper(original, hook, orig_ref)
    _HookedFunctions[wrapper]  = { original = orig_ref }
    _HookedFunctions[original] = { hook = wrapper, original = orig_ref, wrapper = wrapper }

    for k, v in pairs(Quack) do
        if rawequal(v, original) then rawset(Quack, k, wrapper) end
    end
    for k, v in pairs(ExecutorEnvironment) do
        if rawequal(v, original) then rawset(ExecutorEnvironment, k, wrapper) end
    end
    return orig_ref
end
Quack.replaceclosure = Quack.hookfunction

function Quack.restorefunction(func)
    assert(type(func) == "function", "invalid argument #1 to 'restorefunction' (function expected, got " .. type(func) .. ")")
    local info = _HookedFunctions[func]
    if info and info.original then
        local original = info.original
        local wrapper  = info.wrapper
        _HookedFunctions[func] = nil
        if wrapper then _HookedFunctions[wrapper] = nil end
        if wrapper then
            for k, v in pairs(Quack) do
                if rawequal(v, wrapper) then rawset(Quack, k, original) end
            end
            for k, v in pairs(ExecutorEnvironment) do
                if rawequal(v, wrapper) then rawset(ExecutorEnvironment, k, original) end
            end
        end
        return original
    end
    return func
end
Quack.restoreclosure = Quack.restorefunction

---- [ isexecutorclosure fix - uses hookfunction registry ] ----
function Quack.isexecutorclosure(func)
    assert(type(func) == "function", "invalid argument #1 to 'isexecutorclosure' (function expected, got " .. type(func) .. ")")
    if CClosures[func] then return true end
    if _HookedFunctions[func] then return true end
    local s = debug.info(func, "s")
    if s ~= "[C]" then return true end
    return false
end
Quack.checkclosure = Quack.isexecutorclosure
Quack.isourclosure = Quack.isexecutorclosure

---- [ clonefunction fix ] ----
function Quack.clonefunction(func)
    assert(type(func) == "function", "invalid argument #1 to 'clonefunction' (function expected, got " .. type(func) .. ")")
    local ok = pcall(setfenv, func, getfenv(func))
    if ok then
        local cloned = function(...) return func(...) end
        pcall(setfenv, cloned, getfenv(func))
        return cloned
    end
    -- C closures: wrap in coroutine
    local ccl = coroutine.wrap(function(...)
        while true do coroutine.yield(func(...)) end
    end)
    CClosures[ccl] = ccl
    return ccl
end

---- [ debug extensions ] ----
do
    local _native = debug
    local _ext = {}
    for k, v in pairs(_native) do _ext[k] = v end
    Quack.debug = _ext
end

function Quack.debug.getupvalues(func)
    assert(type(func) == "function", "invalid argument #1 to 'debug.getupvalues' (function expected, got " .. type(func) .. ")")
    local ups = {}
    if debug.getupvalue then
        local i = 1
        while true do
            local name, val = debug.getupvalue(func, i)
            if name == nil then break end
            ups[i] = val
            i = i + 1
        end
    end
    return ups
end

function Quack.debug.setupvalue(func, idx, val)
    assert(type(func) == "function", "invalid argument #1 to 'debug.setupvalue' (function expected)")
    if debug.setupvalue then
        return debug.setupvalue(func, idx, val)
    end
end

function Quack.debug.getconstants(func)
    assert(type(func) == "function", "invalid argument #1 to 'debug.getconstants' (function expected)")
    if debug.getconstants then return debug.getconstants(func) end
    return {}
end

function Quack.debug.setconstant(func, idx, val)
    assert(type(func) == "function", "invalid argument #1 to 'debug.setconstant' (function expected)")
    if debug.setconstant then return debug.setconstant(func, idx, val) end
end

function Quack.debug.getprotos(func)
    assert(type(func) == "function", "invalid argument #1 to 'debug.getprotos' (function expected)")
    if debug.getprotos then return debug.getprotos(func) end
    return {}
end

function Quack.debug.getproto(func, idx, activated)
    assert(type(func) == "function", "invalid argument #1 to 'debug.getproto' (function expected)")
    local protos = Quack.debug.getprotos(func)
    if idx then return protos[idx] end
    return protos
end

function Quack.debug.getupvalue(func, idx)
    assert(type(func) == "function", "invalid argument #1 to 'debug.getupvalue' (function expected)")
    local ups = Quack.debug.getupvalues(func)
    if idx then return ups[idx] end
    return ups[1]
end

function Quack.debug.getconstant(func, idx)
    assert(type(func) == "function", "invalid argument #1 to 'debug.getconstant' (function expected)")
    local consts = Quack.debug.getconstants(func)
    if idx then return consts[idx] end
    return consts[1]
end

function Quack.debug.getstack(thread_or_level, level)
    if type(thread_or_level) == "thread" then
        return {}
    end
    local lvl = tonumber(thread_or_level) or 1
    if debug.getstack then return debug.getstack(lvl) end
    return {}
end

function Quack.debug.setstack(thread_or_level, level_or_val, val)
    if debug.setstack then
        return pcall(debug.setstack, thread_or_level, level_or_val, val)
    end
end

---- [ cache functions ] ----
local _InstanceCache = setmetatable({}, {__mode = "v"})
local _CacheReplacements = setmetatable({}, {__mode = "k"})
Quack.cache = {
    iscached = function(instance)
        if typeof(instance) ~= "Instance" then return false end
        local ok, str = pcall(tostring, instance)
        return ok and _InstanceCache[str] ~= nil
    end,
    invalidate = function(instance)
        if typeof(instance) ~= "Instance" then return end
        local ok, str = pcall(tostring, instance)
        if ok then _InstanceCache[str] = nil end
    end,
    replace = function(instance, replacement)
        if typeof(instance) ~= "Instance" then return end
        _CacheReplacements[instance] = replacement
    end,
}
Quack.cacheinvalidate = Quack.cache.invalidate
Quack.cacheiscached  = Quack.cache.iscached
Quack.cachereplace   = Quack.cache.replace

---- [ firesignal / replicatesignal ] ----
function Quack.firesignal(signal, ...)
    if typeof(signal) ~= "RBXScriptSignal" then
        error("invalid argument #1 to 'firesignal' (RBXScriptSignal expected, got " .. typeof(signal) .. ")", 2)
    end
    -- use a BindableEvent to get a function pointer to Fire via the signal's connection
    local b = Instance.new("BindableEvent")
    local fired = false
    local conn = signal:Connect(function(...) fired = true end)
    b.Event:Connect(function(...) signal:Fire(...) end)
    local ok = pcall(function(...) b:Fire(...) end, ...)
    conn:Disconnect()
    b:Destroy()
    return ok
end

function Quack.replicatesignal(signal, ...)
    local ok = pcall(function(...) signal:FireServer(...) end, ...)
    return ok
end

---- [ getconnections ] ----
local _ConnectionRegistry = setmetatable({}, {__mode = "k"})

local function _make_conn_entry(fn, raw_conn)
    local entry = { Enabled = true, Function = fn }
    function entry:Disconnect()
        self.Enabled = false
        if raw_conn then pcall(function() raw_conn:Disconnect() end) end
    end
    function entry:Enable()  self.Enabled = true  end
    function entry:Disable() self.Enabled = false end
    return entry
end

local function _wrap_connection(conn, signal, fn)
    if not _ConnectionRegistry[signal] then _ConnectionRegistry[signal] = {} end
    local entry = _make_conn_entry(fn, conn)
    table.insert(_ConnectionRegistry[signal], entry)
    return conn
end

function Quack.getconnections(signal)
    if typeof(signal) ~= "RBXScriptSignal" then
        error("invalid argument #1 to 'getconnections' (RBXScriptSignal expected, got " .. typeof(signal) .. ")", 2)
    end

    local result = {}
    local seen = {}

    local ok, native = pcall(function() return signal:GetConnected() end)
    if ok and type(native) == "table" then
        for _, raw in ipairs(native) do
            local fn = nil
            pcall(function() fn = raw.Function end)
            local entry = _make_conn_entry(fn, raw)
            local connected = true
            pcall(function() connected = raw.Connected ~= false end)
            entry.Enabled = connected
            local key = tostring(raw)
            if not seen[key] then
                seen[key] = true
                table.insert(result, entry)
            end
        end
    end

    for _, entry in ipairs(_ConnectionRegistry[signal] or {}) do
        table.insert(result, entry)
    end

    return result
end

---- [ getreg ] ----
function Quack.getreg()
    local reg = {}
    if _executor_main_thread then table.insert(reg, _executor_main_thread) end
    for thread in pairs(_ExecutorThreads) do
        table.insert(reg, thread)
    end
    for _, instance in ipairs(Quack.getinstances()) do
        table.insert(reg, instance)
    end
    return reg
end

---- [ getsenv ] ----
local _ScriptEnvs = setmetatable({}, {__mode = "k"})
function Quack.getsenv(script_inst)
    assert(typeof(script_inst) == "Instance", "invalid argument #1 to 'getsenv' (Instance expected, got " .. typeof(script_inst) .. ")", 2)

    if _ScriptEnvs[script_inst] then
        return _ScriptEnvs[script_inst]
    end

    local env = {}
    setmetatable(env, {
        __index = Quack,
        __newindex = function(t, k, v)
            rawset(t, k, v)
        end,
    })
    _ScriptEnvs[script_inst] = env
    return env
end

---- [ filtergc ] ----
function Quack.filtergc(type_filter, options)
    options = options or {}
    local gc = Quack.getgc()
    local result = {}
    for _, v in ipairs(gc) do
        local t = type(v)
        local tv = typeof(v)
        if type_filter ~= nil and t ~= type_filter and tv ~= type_filter then continue end
        if options.Name ~= nil then
            local ok, name = pcall(function() return (v).Name end)
            if not ok or name ~= options.Name then continue end
        end
        if options.ClassName ~= nil then
            local ok, cls = pcall(function() return (v).ClassName end)
            if not ok or cls ~= options.ClassName then continue end
        end
        table.insert(result, v)
    end
    return result
end

---- [ getcallingscript / getscriptfromthread / getscriptclosure / getcallbackvalue / getfunctionhash ] ----
local _ThreadScripts = setmetatable({}, {__mode = "k"})

function Quack.getcallingscript()
    return Quack.script
end

function Quack.getscriptfromthread(thread)
    assert(type(thread) == "thread", "invalid argument #1 to 'getscriptfromthread' (thread expected, got " .. type(thread) .. ")", 2)
    return _ThreadScripts[thread] or Quack.script
end

function Quack.getscriptclosure(script_inst)
    assert(typeof(script_inst) == "Instance", "invalid argument #1 to 'getscriptclosure' (Instance expected, got " .. typeof(script_inst) .. ")", 2)
    return nil
end
Quack.getscriptfunction = Quack.getscriptclosure

function Quack.getcallbackvalue(instance, property)
    assert(typeof(instance) == "Instance", "invalid argument #1 to 'getcallbackvalue' (Instance expected, got " .. typeof(instance) .. ")", 2)
    assert(type(property) == "string", "invalid argument #2 to 'getcallbackvalue' (string expected, got " .. type(property) .. ")", 2)
    local ok, val = pcall(function() return instance[property] end)
    if ok then return val end
    return nil
end

function Quack.getfunctionhash(func)
    assert(type(func) == "function", "invalid argument #1 to 'getfunctionhash' (function expected, got " .. type(func) .. ")", 2)
    local src  = tostring(debug.info(func, "s") or "")
    local line = tostring(debug.info(func, "l") or "")
    local name = tostring(debug.info(func, "n") or "")
    return crypt.hash(src .. ":" .. line .. ":" .. name, "sha256")
end

---- [ isscriptable / setscriptable ] ----
local _Scriptables = setmetatable({}, {__mode = "k"})
function Quack.isscriptable(instance, property)
    assert(typeof(instance) == "Instance", "invalid argument #1 to 'isscriptable' (Instance expected, got " .. typeof(instance) .. ")", 2)
    assert(type(property) == "string", "invalid argument #2 to 'isscriptable' (string expected, got " .. type(property) .. ")", 2)
    local inst_tbl = _Scriptables[instance]
    if inst_tbl and inst_tbl[property] ~= nil then return inst_tbl[property] end
    local ok = pcall(function() return instance:GetPropertyChangedSignal(property) end)
    return ok
end

function Quack.setscriptable(instance, property, bool)
    assert(typeof(instance) == "Instance", "invalid argument #1 to 'setscriptable' (Instance expected, got " .. typeof(instance) .. ")", 2)
    assert(type(property) == "string", "invalid argument #2 to 'setscriptable' (string expected, got " .. type(property) .. ")", 2)
    assert(type(bool) == "boolean", "invalid argument #3 to 'setscriptable' (boolean expected, got " .. type(bool) .. ")", 2)
    local was = Quack.isscriptable(instance, property)
    if not _Scriptables[instance] then _Scriptables[instance] = {} end
    _Scriptables[instance][property] = bool
    return was
end

---- [ better external implementations ] ----
function Quack.isnetworkowner(part)
    if typeof(part) == "Instance" and part:IsA("BasePart") then
        local ok, owner = pcall(function() return part:GetNetworkOwner() end)
        if ok then
            return owner == nil or owner == Players.LocalPlayer
        end
    end
    return true
end

function Quack.readbinarystring(path)
    local data, err = Quack.readfile(path)
    if data and type(data) == "string" then
        return data
    end
    return nil, err
end

function Quack.getcallstack()
    return debug and debug.traceback and debug.traceback() or ""
end

 -- ########## Required/optional globals (external-safe stubs) ##########
do
    local env = getgenv and getgenv() or _G

    -- cache table
    env.cache = env.cache or Quack.cache

    -- firesignal
    env.firesignal = env.firesignal or Quack.firesignal
    env.replicatesignal = env.replicatesignal or Quack.replicatesignal
    env.syn = env.syn or {}
    env.syn.firesignal = env.syn.firesignal or Quack.firesignal
    env.fluxus = env.fluxus or {}
    env.fluxus.firesignal = env.fluxus.firesignal or Quack.firesignal

    -- getconnections
    env.getconnections = env.getconnections or Quack.getconnections

    -- hookfunction / restorefunction / clonefunction
    env.hookfunction = env.hookfunction or Quack.hookfunction
    env.replaceclosure = env.replaceclosure or Quack.replaceclosure
    env.restorefunction = env.restorefunction or Quack.restorefunction
    env.restoreclosure = env.restoreclosure or Quack.restoreclosure
    env.clonefunction = env.clonefunction or Quack.clonefunction

    -- debug extensions
    env.debug = env.debug or {}
    env.debug.getupvalues  = env.debug.getupvalues  or Quack.debug.getupvalues
    env.debug.getupvalue   = env.debug.getupvalue   or Quack.debug.getupvalue
    env.debug.setupvalue   = env.debug.setupvalue   or Quack.debug.setupvalue
    env.debug.getconstants = env.debug.getconstants or Quack.debug.getconstants
    env.debug.getconstant  = env.debug.getconstant  or Quack.debug.getconstant
    env.debug.setconstant  = env.debug.setconstant  or Quack.debug.setconstant
    env.debug.getprotos    = env.debug.getprotos    or Quack.debug.getprotos
    env.debug.getproto     = env.debug.getproto     or Quack.debug.getproto
    env.debug.getstack     = env.debug.getstack     or Quack.debug.getstack
    env.debug.setstack     = env.debug.setstack     or Quack.debug.setstack
    env.debug.getinfo      = env.debug.getinfo      or Quack.debug.getinfo
    env.debug.getmetatable = env.debug.getmetatable or Quack.debug.getmetatable

    -- isscriptable / setscriptable
    env.isscriptable = env.isscriptable or Quack.isscriptable
    env.setscriptable = env.setscriptable or Quack.setscriptable

    -- hidden properties
    env.sethiddenproperty = env.sethiddenproperty or Quack.sethiddenproperty
    env.gethiddenproperty = env.gethiddenproperty or Quack.gethiddenproperty

    -- misc
    env.getregistry = env.getregistry or Quack.getregistry
    env.getsenv = env.getsenv or Quack.getsenv
    env.getstack = env.getstack or Quack.debug.getstack
    env.filtergc = env.filtergc or Quack.filtergc
    env.getcallingscript = env.getcallingscript or Quack.getcallingscript
    env.getscriptfromthread = env.getscriptfromthread or Quack.getscriptfromthread
    env.getscriptclosure = env.getscriptclosure or Quack.getscriptclosure
    env.getscriptfunction = env.getscriptfunction or Quack.getscriptfunction
    env.getcallbackvalue = env.getcallbackvalue or Quack.getcallbackvalue
    env.getfunctionhash = env.getfunctionhash or Quack.getfunctionhash

    -- fpscap stubs
    env.setfpscap = env.setfpscap or Quack.setfpscap
    env.getfpscap = env.getfpscap or Quack.getfpscap

    -- clipboard
    env.setrbxclipboard = env.setrbxclipboard or Quack.setrbxclipboard
    env.getclipboard = env.getclipboard or Quack.getclipboard

    -- fflags
    env.getfflag = env.getfflag or Quack.getfflag
    env.setfflag = env.setfflag or Quack.setfflag

    -- actors
    env.run_on_actor = env.run_on_actor or Quack.run_on_actor
    env.getactors = env.getactors or Quack.getactors

    -- metamethod hooks
    env.hookmetamethod = env.hookmetamethod or Quack.hookmetamethod
    env.getnamecallmethod = env.getnamecallmethod or Quack.getnamecallmethod
    env.setnamecallmethod = env.setnamecallmethod or Quack.setnamecallmethod

    -- fireproximityprompt / firetouchinterest / firetouchtransmitter
    env.fireproximityprompt = env.fireproximityprompt or Quack.fireproximityprompt
    env.firetouchinterest = env.firetouchinterest or Quack.firetouchinterest
    env.firetouchtransmitter = env.firetouchtransmitter or Quack.firetouchtransmitter

    -- cloneclosure
    env.cloneclosure = env.cloneclosure or Quack.cloneclosure

    -- getobjects
    env.getobjects = env.getobjects or Quack.getobjects
    env.getinstances = env.getinstances or function() return game:GetDescendants() end
    env.getnilinstances = env.getnilinstances or function() return {} end
    env.getloadedmodules = env.getloadedmodules or function()
        local mods = {}
        for _,v in ipairs(game:GetDescendants()) do
            if v:IsA("ModuleScript") then table.insert(mods, v) end
        end
        return mods
    end
    env.getrunningscripts = env.getrunningscripts or function()
        local scripts = {}
        for _,v in ipairs(game:GetDescendants()) do
            if v:IsA("LocalScript") or v:IsA("Script") then
                table.insert(scripts, v)
            end
        end
        return scripts
    end
    env.getrenv = env.getrenv or Quack.getrenv

    -- WebSocket stubs
    env.WebSocket = env.WebSocket or {}
    env.WebSocket.connect = env.WebSocket.connect or Quack.WebSocket.connect
    env.WebSocket.close = env.WebSocket.close or function() end

    -- http.get/post
    env.http = env.http or {}
    env.http.get = env.http.get or Quack.http.get
    env.http.post = env.http.post or Quack.http.post

    -- debug stubs (singular and plural)
    local dbg = env.debug or Quack.debug
    env.debug = dbg
    dbg.getconstant  = dbg.getconstant  or Quack.debug.getconstant
    dbg.getconstants = dbg.getconstants or Quack.debug.getconstants
    dbg.getproto     = dbg.getproto     or Quack.debug.getproto
    dbg.getprotos    = dbg.getprotos    or Quack.debug.getprotos
    dbg.getstack     = dbg.getstack     or Quack.debug.getstack
    dbg.setstack     = dbg.setstack     or Quack.debug.setstack
    dbg.getupvalue   = dbg.getupvalue   or Quack.debug.getupvalue
    dbg.getupvalues  = dbg.getupvalues  or Quack.debug.getupvalues
    dbg.setconstant  = dbg.setconstant  or Quack.debug.setconstant
    dbg.setupvalue   = dbg.setupvalue   or Quack.debug.setupvalue
    dbg.traceback    = dbg.traceback    or (debug and debug.traceback)

    env.lz4compress = env.lz4compress or function(str) return Quack.crypt.lz4compress(str) end
    env.lz4decompress = env.lz4decompress or function(str) return Quack.crypt.lz4decompress(str) end

    env.messagebox = env.messagebox or function(text, title, flags)
        pcall(function()
            game:GetService("StarterGui"):SetCore("SendNotification", {
                Title = title or "Quack",
                Text = tostring(text),
                Duration = 5
            })
        end)
        return 0
    end

    -- getobjects pointer/instance helpers
    env.getpointerfrominstance = env.getpointerfrominstance or Quack.getpointerfrominstance

    -- isnetworkowner
    env.isnetworkowner = env.isnetworkowner or Quack.isnetworkowner

    env.getcallstack   = env.getcallstack   or Quack.getcallstack
    env.getcallbackvalue = env.getcallbackvalue or function() return nil end
    env.replaceclosure = env.replaceclosure or function(fn, newfn) return newfn end
    env.restorefunction = env.restorefunction or function(fn) return fn end
    env.getfunctionhash = env.getfunctionhash or function(fn) return tostring(fn) end
    env.getspecialinfo = env.getspecialinfo or function() return {} end
end

-- global compatibility exports (late)
pcall(function()
    local env = getgenv and getgenv() or _G
    env.firesignal = env.firesignal or Quack.firesignal
    env.syn = env.syn or {}
    env.syn.firesignal = env.syn.firesignal or Quack.firesignal
    env.fluxus = env.fluxus or {}
    env.fluxus.firesignal = env.fluxus.firesignal or Quack.firesignal
end)

while not GameLeaving do
	task.wait(1)
end
