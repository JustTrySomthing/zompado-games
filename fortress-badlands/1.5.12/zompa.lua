-- Zompa game SDK v5. This module also runs in desktop LÖVE for development.
local sdk = {version = 5}
local slots = "zompado-saves"

local function savePath(slot)
    assert(type(slot) == "string" and #slot <= 32 and slot:match("^[a-z0-9][a-z0-9_-]*$"),
        "Use a save slot name with 1 to 32 lowercase letters, digits, underscores, or hyphens.")
    return slots .. "/" .. slot
end

-- The game owns serialization. Keep saved data small and version the format.
function sdk.save(slot, data)
    local path = savePath(slot)
    assert(type(data) == "string" and #data <= 262144, "Save data must fit in 256 KiB.")
    if not love.filesystem.createDirectory(slots) then
        return false, "Could not create the save directory."
    end
    return love.filesystem.write(path, data)
end

function sdk.load(slot)
    local path = savePath(slot)
    if not love.filesystem.getInfo(path, "file") then return nil end
    return love.filesystem.read(path, 262144)
end

function sdk.clear(slot)
    local path = savePath(slot)
    return not love.filesystem.getInfo(path) or love.filesystem.remove(path)
end

local function readHost(name, limit)
    local file = io.open("/zompado/" .. name, "r")
    if not file then return nil end
    local value = file:read(limit)
    file:close()
    return value
end

-- Advertise an in-game Advanced Settings screen to the host toolbar.
function sdk.enableAdvancedSettings()
    local file = io.open("/zompado/advanced-settings", "wb")
    if file then file:write("1"); file:close() end
end

function sdk.settingsRequest()
    return tonumber(readHost("settings-request", 12))
end

function sdk.mode()
    local mode = readHost("mode", 8)
    if not mode then return "solo", false end
    if mode == "local" or mode == "online" then return mode, true end
    return "solo", true
end

function sdk.onlineState()
    if sdk.mode() == "online" then return readHost("match", 56) end
end

function sdk.submitOnlineMove(move)
    if sdk.mode() ~= "online" then return false, "No online match is running." end
    if type(move) ~= "number" or move % 1 ~= 0 or move < 0 or move > 6 then
        return false, "This player accepts a Cats vs Dogs column from 0 to 6."
    end
    local file, err = io.open("/zompado/move", "wb")
    if not file then return false, err end
    local written, writeError = file:write(tostring(move))
    local closed, closeError = file:close()
    if not written or not closed then return false, writeError or closeError end
    return true
end

local cachedTurns, cachedRevision, cachedPageCount

-- Read the complete turn log on either transport. The inviter is player 1.
-- Each call returns a new table because games may consume or trim the list.
function sdk.readTurns()
    if sdk.mode() ~= "online" then return nil end
    local header = readHost("match-pages", 32)
    local player, allowed
    local turns = {}
    if header then
        local count
        player, allowed, count = header:match("^([12]):([01]):(%d+)$")
        if not count then return nil end
        count = tonumber(count)
        local revision = readHost("match-revision", 24)
        if revision and revision == cachedRevision and count == cachedPageCount then
            for i, move in ipairs(cachedTurns) do turns[i] = move end
            return turns, tonumber(player), allowed == "1"
        end
        for page = 0, count - 1 do
            local data = readHost("match-page-" .. page, 32896)
            if not data or #data > 32895 or data:sub(1, 1) == "," or data:sub(-1) == ","
                    or data:find(",,", 1, true) then return nil end
            local size = 0
            for move in data:gmatch("[^,]+") do
                if #move > 256 or not move:match("^[A-Za-z0-9_-]+$") then return nil end
                size = size + 1
                turns[#turns + 1] = move
            end
            if size == 0 or size > 128 or (page + 1 < count and size ~= 128) then return nil end
        end
        if revision then
            cachedTurns, cachedRevision, cachedPageCount = {}, revision, count
            for i, move in ipairs(turns) do cachedTurns[i] = move end
        else
            cachedTurns, cachedRevision, cachedPageCount = nil, nil, nil
        end
    else
        cachedTurns, cachedRevision, cachedPageCount = nil, nil, nil
        local state = readHost("match", 132001)
        if not state then return nil end
        local history
        player, allowed, history = state:match("^([12]):([01]):([A-Za-z0-9_,-]*)$")
        if not player then return nil end
        for move in history:gmatch("[^,]+") do turns[#turns + 1] = move end
    end
    return turns, tonumber(player), allowed == "1"
end

function sdk.submitTurn(payload, outcome)
    if sdk.mode() ~= "online" then return false, "No online match is running." end
    if type(payload) ~= "string" or #payload > 256 or not payload:match("^[A-Za-z0-9_-]+$") then
        return false, "Use a 1 to 256 character move token."
    end
    if outcome ~= nil and outcome ~= 0 and outcome ~= 1 and outcome ~= 2 then
        return false, "Outcome must be nil, 0 (draw), 1 or 2 (winner)."
    end
    local file, err = io.open("/zompado/move", "wb")
    if not file then return false, err end
    local written, writeError = file:write((outcome or "-") .. ":" .. payload)
    local closed, closeError = file:close()
    if not written or not closed then return false, writeError or closeError end
    return true
end

-- Local display metadata, independent of the synchronized turn history.
function sdk.opponentName()
    local name = readHost("opponent", 512)
    if name and name ~= "" then return name end
end

local function sessionPath(mode)
    return "/home/web_user/love/.zompado-session-" .. mode
end

function sdk.saveSession(data)
    assert(type(data) == "string" and #data > 0 and #data <= 262144,
        "Session data must be between 1 byte and 256 KiB.")
    local mode, hosted = sdk.mode()
    if mode == "online" then return false, "Online progress is managed by the host." end
    if not hosted then return sdk.save("session-solo", data) end
    local file, err = io.open(sessionPath(mode), "wb")
    if not file then return false, err end
    local written, writeError = file:write(data)
    local closed, closeError = file:close()
    if not written or not closed then return false, writeError or closeError end
    return true
end

function sdk.loadSession()
    local mode, hosted = sdk.mode()
    if mode == "online" then return nil end
    if not hosted then return sdk.load("session-solo") end
    local file = io.open(sessionPath(mode), "rb")
    if not file then return nil end
    local data = file:read(262145)
    file:close()
    if data and #data > 0 and #data <= 262144 then return data end
end

local function removeHostFile(path)
    local file = io.open(path, "rb")
    if not file then return true end
    file:close()
    return os.remove(path)
end

function sdk.clearSession()
    local mode, hosted = sdk.mode()
    if mode == "online" then return true end
    if not hosted then return sdk.clear("session-solo") end
    if mode == "local" then
        -- Older hosts mark the start of Pass & Play before a game has a save.
        -- Clear the marker too so finishing a migrated match hides Resume.
        local ok, err = removeHostFile("/home/web_user/love/.zompado-local-started")
        if not ok then return false, err end
    end
    return removeHostFile(sessionPath(mode))
end

function sdk.audio()
    local gains = {music = 1, effects = 1}
    local hostGains = {music = 1, effects = 1}
    local hostSettings, elapsed = nil, 0
    local sources = setmetatable({}, {__mode = "k"})
    local muted = false
    local mixer = {}

    local function apply(source, settings)
        source:setVolume(muted and 0 or gains[settings.bus] * hostGains[settings.bus] * settings.volume)
    end

    function mixer:update(dt)
        elapsed = elapsed + dt
        if elapsed < 0.2 then return end
        elapsed = 0
        local settings = readHost("audio", 8)
        if not settings or settings == hostSettings then return end
        local music, effects = settings:match("^(%d%d?%d?):(%d%d?%d?)$")
        if not music or tonumber(music) > 100 or tonumber(effects) > 100 then return end
        hostSettings = settings
        hostGains.music, hostGains.effects = tonumber(music) / 100, tonumber(effects) / 100
        for source, sourceSettings in pairs(sources) do apply(source, sourceSettings) end
    end

    function mixer:register(source, bus)
        self:update(0.2)
        assert(gains[bus] ~= nil, "Choose the music or effects bus.")
        assert(not sources[source], "This source is already registered.")
        sources[source] = {bus = bus, volume = source:getVolume()}
        apply(source, sources[source])
        return source
    end

    function mixer:setGain(bus, gain)
        assert(gains[bus] ~= nil, "Choose the music or effects bus.")
        assert(type(gain) == "number" and gain >= 0 and gain <= 1, "Gain must be between 0 and 1.")
        gains[bus] = gain
        for source, settings in pairs(sources) do
            if settings.bus == bus then apply(source, settings) end
        end
    end

    function mixer:setMuted(value)
        muted = not not value
        for source, settings in pairs(sources) do apply(source, settings) end
    end

    return mixer
end

return sdk
