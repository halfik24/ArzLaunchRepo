require 'lib.moonloader'
local imgui = require 'mimgui'
local ffi = require 'ffi'
local cjson = nil
local IsExists, Create, Delete = sampTextdrawIsExists, sampTextdrawCreate, sampTextdrawDelete

local weapons = {
    [0] = "Fist", [1] = "Brassknucles", [2] = "Golf_club", [3] = "Nightstick", [4] = "Knife", 
    [5] = "Bat", [6] = "Shovel", [7] = "Poolstick", [8] = "Katana", [9] = "Chainsaw", 
    [16] = "Grenade", [17] = "Teargas", [22] = "Pistol", [23] = "Silenced_pistol", 
    [24] = "Deagle", [25] = "Shotgun", [26] = "Sawn-off", [27] = "Combat_Shotgun", 
    [28] = "Mac-10", [29] = "Mp5", [30] = "Ak-47", [31] = "M4", [32] = "Tec-9", 
    [33] = "Rifle", [34] = "Sniper", [37] = "Flamethrower", [41] = "Spraycan",
    [71] = "Deagle", [72] = "Deagle", [73] = "Pistol", [74] = "Deagle", [75] = "Deagle", 
    [76] = "Deagle", [77] = "Tec-9", [78] = "Tec-9", [79] = "M4", [80] = "Combat_Shotgun", 
    [81] = "Mp5", [82] = "M4", [83] = "Tec-9", [84] = "Mp5", [85] = "Ak-47", 
    [86] = "Combat_Shotgun", [87] = "Deagle", [88] = "Katana", [89] = "Pistol", 
    [90] = "Grenade", [91] = "Grenade", [92] = "Sniper", [93] = "Deagle", [94] = "Shotgun", 
    [95] = "Rifle", [96] = "M4", [97] = "Combat_Shotgun", [98] = "Mac-10", [99] = "Bat", 
    [100] = "Bat", [101] = "Deagle", [102] = "Ak-47", [103] = "Shotgun", [104] = "Knife", 
    [105] = "Deagle", [106] = "Knife", [107] = "Katana", [108] = "Knife", [109] = "Deagle", 
    [110] = "Bat", [111] = "Mac-10", [112] = "Mac-10", [113] = "Mac-10", [114] = "Mac-10", 
    [115] = "Tec-9", [116] = "Tec-9", [117] = "Tec-9", [118] = "Tec-9", [119] = "Sawn-off", 
    [120] = "Sawn-off", [121] = "Sawn-off", [122] = "Sawn-off", [123] = "Deagle", 
    [124] = "Deagle", [125] = "Deagle", [126] = "Ak-47", [127] = "Ak-47", [128] = "Ak-47", 
    [129] = "M4", [130] = "M4", [131] = "M4", [132] = "M4", [133] = "Ak-47", 
    [134] = "Ak-47", [135] = "Ak-47", [136] = "Ak-47", [137] = "Deagle", [138] = "Deagle", 
    [139] = "Deagle", [140] = "Deagle", [141] = "M4", [142] = "M4", [143] = "M4", 
    [144] = "M4", [145] = "Sniper", [146] = "Sniper", [147] = "Sniper", [148] = "Sniper", 
    [149] = "Shotgun", [150] = "Shotgun", [151] = "Shotgun", [152] = "Shotgun", 
    [153] = "Deagle", [154] = "Mac-10", [155] = "Ak-47", [156] = "M4", [157] = "Sawn-off", 
    [158] = "Tec-9"
}

local TD_OUT_BASE, TD_IN_BASE = 2105, 2115
local TD_RANGE = 16

local DEFAULT_CONFIG = {
    active         = true,
    passCEFNotices = true,
    outX           = 200.0,
    outY           = 275.0,
    inX            = 440.0,
    inY            = 275.0,
    lineSpacing    = 8.3,
    letterSizeX    = 0.215,
    letterSizeY    = 0.85,
    style          = 1,
    align          = 2,
    proportional   = true,
    outlineSize    = 1,
    colorOut       = 0xFF88AA62,
    colorIn        = 0xFFE05454, 
    outlineColor   = 0x20000000,
    timeout        = 2.5,
    maxSlots       = 4,
    prefixOut      = "+",
    prefixIn       = "-",
    textFormat     = "{name}_-_{weapon}({gunid})_{prefix}{sum}",
    soundEnabled   = true,
    soundId        = 17802,
}

local function deepcopy(t)
    if type(t) ~= 'table' then return t end
    local r = {}
    for k, v in pairs(t) do r[k] = deepcopy(v) end
    return r
end

local config  = deepcopy(DEFAULT_CONFIG)
local presets = {}

local damageOut, damageIn = {}, {}

local configDir  = getWorkingDirectory() .. '\\config'
local configPath = configDir .. '\\arz_damage_informer_config.json'

local function saveConfig()
    if not cjson then return end
    if not doesDirectoryExist(configDir) then createDirectory(configDir) end
    local f = io.open(configPath, 'w')
    if f then
        f:write(cjson.encode({ config = config, presets = presets }))
        f:close()
    end
end

local function loadConfig()
    if not cjson then return end
    local f = io.open(configPath, 'r')
    if not f then return end
    local content = f:read('*a')
    f:close()
    if not content or content == '' then return end
    local ok, data = pcall(cjson.decode, content)
    if ok and type(data) == 'table' then
        if type(data.config) == 'table' then
            for k in pairs(DEFAULT_CONFIG) do
                if data.config[k] ~= nil then config[k] = data.config[k] end
            end
        end
        if type(data.presets) == 'table' then
            presets = data.presets
        end
    end
end

local function argb2f(argb)
    local a = bit.band(bit.rshift(argb, 24), 0xFF)
    local r = bit.band(bit.rshift(argb, 16), 0xFF)
    local g = bit.band(bit.rshift(argb, 8), 0xFF)
    local b = bit.band(argb, 0xFF)
    return r / 255, g / 255, b / 255, a / 255
end

local function f2argb(r, g, b, a)
    local R = math.floor(r * 255 + 0.5)
    local G = math.floor(g * 255 + 0.5)
    local B = math.floor(b * 255 + 0.5)
    local A = math.floor(a * 255 + 0.5)
    return bit.bor(bit.lshift(A, 24), bit.lshift(R, 16), bit.lshift(G, 8), B)
end

local function formatText(slot, prefix)
    local weapon = slot.customWeapon or weapons[slot.gunId] or 'Gun'
    local s = config.textFormat

    if slot.customWeapon == 'Collision' then
        local hasVal = s:find("{val}") ~= nil
        s = "Collision_{prefix}" .. (hasVal and "{val}" or "{sum}")
    else
        s = s:gsub('{name}', function() return slot.name end)
        s = s:gsub('{weapon}', function() return weapon end)
        s = s:gsub('{gunid}', tostring(slot.gunId))
    end

    s = s:gsub('{prefix}', function() return prefix end)
    s = s:gsub('{sum}', function() return string.format('%.2f', slot.sum) end)
    s = s:gsub('{val}', function() return string.format('%.2f', slot.val) end)
    s = s:gsub('{lb}', '{')
    s = s:gsub('{rb}', '}')
    return s
end

local function renderList(list, x, y, prefix, baseId, color)
    local count = #list
    for i = 1, count do
        local slot = list[i]
        local pos = count - i + 1
        local tid = baseId + pos
        local infoText = formatText(slot, prefix)

        Create(tid, infoText, x, y + (pos * config.lineSpacing))
        sampTextdrawSetAlign(tid, config.align)
        sampTextdrawSetStyle(tid, config.style)
        sampTextdrawSetOutlineColor(tid, config.outlineSize, config.outlineColor)
        sampTextdrawSetLetterSizeAndColor(tid, config.letterSizeX, config.letterSizeY, color)
        sampTextdrawSetProportional(tid, config.proportional and 1 or 0)
    end
end

function refreshAll()
    for i = 1, TD_RANGE do
        if IsExists(TD_OUT_BASE + i) then Delete(TD_OUT_BASE + i) end
        if IsExists(TD_IN_BASE + i) then Delete(TD_IN_BASE + i) end
    end
    renderList(damageOut, config.outX, config.outY, config.prefixOut, TD_OUT_BASE, config.colorOut)
    renderList(damageIn, config.inX, config.inY, config.prefixIn, TD_IN_BASE, config.colorIn)
end

function clearOldTDs()
    for i = 1, TD_RANGE do
        if IsExists(TD_OUT_BASE + i) then Delete(TD_OUT_BASE + i) end
        if IsExists(TD_IN_BASE + i) then Delete(TD_IN_BASE + i) end
    end
    damageOut, damageIn = {}, {}
end

function updateDamage(name, dtype, value, gunId, customWeapon)
    local list = (dtype == 'outgoing') and damageOut or damageIn
    local foundIdx = -1
    for i, v in ipairs(list) do if v.name == name then foundIdx = i; break end end

    if foundIdx ~= -1 then
        list[foundIdx].sum = list[foundIdx].sum + value
        list[foundIdx].val = value
        list[foundIdx].lastTime = os.clock()
        list[foundIdx].gunId = gunId
        list[foundIdx].customWeapon = customWeapon
        table.insert(list, table.remove(list, foundIdx))
    else
        if #list >= config.maxSlots then
            table.remove(list, 1)
        end
        table.insert(list, { name = name, sum = value, val = value, gunId = gunId, customWeapon = customWeapon, lastTime = os.clock() })
    end
    refreshAll()
end

local testMode = false

local function loadTestData()
    damageOut = {
        { name = 'TestPlayer_A', sum = 45.50, val = 15.00, gunId = 24, lastTime = os.clock() },
        { name = 'TestPlayer_B', sum = 123.00, val = 41.00, gunId = 30, lastTime = os.clock() },
        { name = 'TestPlayer_C', sum = 7.25, val = 7.25, gunId = 0, customWeapon = nil, lastTime = os.clock() },
    }
    damageIn = {
        { name = 'Enemy_One', sum = 88.75, val = 20.50, gunId = 31, lastTime = os.clock() },
        { name = 'Collision', sum = 30.00, val = 30.00, gunId = 0, customWeapon = 'Collision', lastTime = os.clock() },
    }
    refreshAll()
end

local new = imgui.new
local window = new.bool(false)

local buf = {
    passCEFNotices = new.bool(config.passCEFNotices),
    outX           = new.float(config.outX),
    outY           = new.float(config.outY),
    inX            = new.float(config.inX),
    inY            = new.float(config.inY),
    lineSpacing    = new.float(config.lineSpacing),
    letterSizeX    = new.float(config.letterSizeX),
    letterSizeY    = new.float(config.letterSizeY),
    style          = new.int(config.style),
    align          = new.int(config.align),
    proportional   = new.bool(config.proportional),
    outlineSize    = new.int(config.outlineSize),
    timeout        = new.float(config.timeout),
    maxSlots       = new.int(config.maxSlots),
    soundEnabled   = new.bool(config.soundEnabled),
    soundId        = new.int(config.soundId),
    colorOut       = new.float[4](),
    colorIn        = new.float[4](),
    outlineColor   = new.float[4](),
    prefixOut      = new.char[8](config.prefixOut),
    prefixIn       = new.char[8](config.prefixIn),
    textFormat     = new.char[128](config.textFormat),
    presetName     = new.char[64](),
    testMode       = new.bool(false),
}

local function setStr(cbuf, str, size)
    str = str or ''
    ffi.fill(cbuf, size, 0)
    ffi.copy(cbuf, str, math.min(#str, size - 1))
end

local function syncFromConfig()
    buf.passCEFNotices[0] = config.passCEFNotices
    buf.outX[0]           = config.outX
    buf.outY[0]           = config.outY
    buf.inX[0]            = config.inX
    buf.inY[0]            = config.inY
    buf.lineSpacing[0]    = config.lineSpacing
    buf.letterSizeX[0]    = config.letterSizeX
    buf.letterSizeY[0]    = config.letterSizeY
    buf.style[0]          = config.style
    buf.align[0]          = config.align
    buf.proportional[0]   = config.proportional
    buf.outlineSize[0]    = config.outlineSize
    buf.timeout[0]        = config.timeout
    buf.maxSlots[0]       = config.maxSlots
    buf.soundEnabled[0]   = config.soundEnabled
    buf.soundId[0]        = config.soundId

    local r, g, b, a = argb2f(config.colorOut)
    buf.colorOut[0], buf.colorOut[1], buf.colorOut[2], buf.colorOut[3] = r, g, b, a
    r, g, b, a = argb2f(config.colorIn)
    buf.colorIn[0], buf.colorIn[1], buf.colorIn[2], buf.colorIn[3] = r, g, b, a
    r, g, b, a = argb2f(config.outlineColor)
    buf.outlineColor[0], buf.outlineColor[1], buf.outlineColor[2], buf.outlineColor[3] = r, g, b, a

    setStr(buf.prefixOut, config.prefixOut, 8)
    setStr(buf.prefixIn, config.prefixIn, 8)
    setStr(buf.textFormat, config.textFormat, 128)
end

local function syncToConfig()
    config.passCEFNotices = buf.passCEFNotices[0]
    config.outX           = tonumber(buf.outX[0])
    config.outY           = tonumber(buf.outY[0])
    config.inX            = tonumber(buf.inX[0])
    config.inY            = tonumber(buf.inY[0])
    config.lineSpacing    = tonumber(buf.lineSpacing[0])
    config.letterSizeX    = tonumber(buf.letterSizeX[0])
    config.letterSizeY    = tonumber(buf.letterSizeY[0])
    config.style          = tonumber(buf.style[0])
    config.align          = tonumber(buf.align[0])
    config.proportional   = buf.proportional[0]
    config.outlineSize    = tonumber(buf.outlineSize[0])
    config.timeout        = tonumber(buf.timeout[0])
    config.maxSlots       = tonumber(buf.maxSlots[0])
    config.soundEnabled   = buf.soundEnabled[0]
    config.soundId        = tonumber(buf.soundId[0])

    config.colorOut     = f2argb(buf.colorOut[0], buf.colorOut[1], buf.colorOut[2], buf.colorOut[3])
    config.colorIn      = f2argb(buf.colorIn[0], buf.colorIn[1], buf.colorIn[2], buf.colorIn[3])
    config.outlineColor = f2argb(buf.outlineColor[0], buf.outlineColor[1], buf.outlineColor[2], buf.outlineColor[3])

    config.prefixOut    = ffi.string(buf.prefixOut)
    config.prefixIn     = ffi.string(buf.prefixIn)
    config.textFormat   = ffi.string(buf.textFormat)
end

local grayStyles = {
    { imgui.Col.WindowBg,          0.17, 0.17, 0.18, 0.96 },
    { imgui.Col.ChildBg,           0.19, 0.19, 0.20, 1.00 },
    { imgui.Col.PopupBg,           0.15, 0.15, 0.16, 1.00 },
    { imgui.Col.Border,            0.30, 0.30, 0.32, 1.00 },
    { imgui.Col.TitleBg,           0.12, 0.12, 0.13, 1.00 },
    { imgui.Col.TitleBgActive,     0.22, 0.22, 0.24, 1.00 },
    { imgui.Col.FrameBg,           0.25, 0.25, 0.27, 1.00 },
    { imgui.Col.FrameBgHovered,    0.30, 0.30, 0.33, 1.00 },
    { imgui.Col.FrameBgActive,     0.35, 0.35, 0.38, 1.00 },
    { imgui.Col.Button,            0.28, 0.28, 0.30, 1.00 },
    { imgui.Col.ButtonHovered,     0.36, 0.36, 0.39, 1.00 },
    { imgui.Col.ButtonActive,      0.44, 0.44, 0.47, 1.00 },
    { imgui.Col.Header,            0.28, 0.28, 0.30, 1.00 },
    { imgui.Col.HeaderHovered,     0.36, 0.36, 0.39, 1.00 },
    { imgui.Col.HeaderActive,      0.44, 0.44, 0.47, 1.00 },
    { imgui.Col.SliderGrab,        0.55, 0.55, 0.58, 1.00 },
    { imgui.Col.SliderGrabActive,  0.67, 0.67, 0.70, 1.00 },
    { imgui.Col.CheckMark,         0.82, 0.82, 0.85, 1.00 },
    { imgui.Col.Separator,         0.30, 0.30, 0.32, 1.00 },
    { imgui.Col.Text,              0.90, 0.90, 0.92, 1.00 },
}

imgui.OnFrame(
    function() return window[0] end,
    function(self)
        for _, c in ipairs(grayStyles) do
            imgui.PushStyleColor(c[1], imgui.ImVec4(c[2], c[3], c[4], c[5]))
        end

        imgui.SetNextWindowSizeConstraints(imgui.ImVec2(585, 0), imgui.ImVec2(585, 9999))
        imgui.Begin('Damage Informer - Editor', window, imgui.WindowFlags.NoResize + imgui.WindowFlags.AlwaysAutoResize)

        local changed = false

        if imgui.CollapsingHeader('Position & Size', imgui.TreeNodeFlags.DefaultOpen) then
            if imgui.SliderFloat('Outgoing X', buf.outX, 0.0, 640.0, '%.1f') then changed = true end
            if imgui.SliderFloat('Outgoing Y', buf.outY, 0.0, 480.0, '%.1f') then changed = true end
            if imgui.SliderFloat('Incoming X', buf.inX, 0.0, 640.0, '%.1f') then changed = true end
            if imgui.SliderFloat('Incoming Y', buf.inY, 0.0, 480.0, '%.1f') then changed = true end
            if imgui.SliderFloat('Line spacing', buf.lineSpacing, 1.0, 30.0, '%.2f') then changed = true end
            if imgui.SliderFloat('Letter size X', buf.letterSizeX, 0.05, 1.0, '%.3f') then changed = true end
            if imgui.SliderFloat('Letter size Y', buf.letterSizeY, 0.1, 3.0, '%.2f') then changed = true end
        end

        if imgui.CollapsingHeader('Colors') then
            if imgui.ColorEdit4('Outgoing color', buf.colorOut) then changed = true end
            if imgui.ColorEdit4('Incoming color', buf.colorIn) then changed = true end
            if imgui.ColorEdit4('Outline color', buf.outlineColor) then changed = true end
            if imgui.SliderInt('Outline size', buf.outlineSize, 0, 4) then changed = true end
        end

        if imgui.CollapsingHeader('Text Style', imgui.TreeNodeFlags.DefaultOpen) then
            if imgui.SliderInt('Font style', buf.style, 0, 3) then changed = true end
            if imgui.Checkbox('Proportional', buf.proportional) then changed = true end
            if imgui.InputText('Prefix out', buf.prefixOut, ffi.sizeof(buf.prefixOut)) then changed = true end
            if imgui.InputText('Prefix in', buf.prefixIn, ffi.sizeof(buf.prefixIn)) then changed = true end
            
            imgui.Separator()
            imgui.Text('Quick Format Presets:')
            
            if imgui.Button('Default (Nick - M4(31) -94)') then
                setStr(buf.textFormat, '{name}_-_{weapon}({gunid})_{prefix}{sum}', 128)
                changed = true
            end
            imgui.SameLine()
            if imgui.Button('No ID (Nick - M4 -94)') then
                setStr(buf.textFormat, '{name}_-_{weapon}_{prefix}{sum}', 128)
                changed = true
            end
            
            if imgui.Button('Damage + Sum (Nick - Deagle +35 (70))') then
                setStr(buf.textFormat, '{name}_-_{weapon}_{prefix}{val}_({sum})', 128)
                changed = true
            end
            imgui.SameLine()
            if imgui.Button('Compact (Nick -94)') then
                setStr(buf.textFormat, '{name}_{prefix}{sum}', 128)
                changed = true
            end
            imgui.SameLine()
            if imgui.Button('Damage Only (-94)') then
                setStr(buf.textFormat, '{prefix}{sum}', 128)
                changed = true
            end

            imgui.Spacing()
            if imgui.InputText('Text format', buf.textFormat, ffi.sizeof(buf.textFormat)) then changed = true end
            imgui.TextDisabled('Tokens: {name} {weapon} {gunid} {prefix} {sum} {val}')
        end

        if imgui.CollapsingHeader('Behaviour') then
            if imgui.Checkbox('Show other CEF notices (doors, skills, etc.)', buf.passCEFNotices) then changed = true end
            if imgui.SliderFloat('Hide timeout (sec)', buf.timeout, 0.5, 15.0, '%.1f') then changed = true end
            if imgui.SliderInt('Max slots', buf.maxSlots, 1, 10) then changed = true end
        end

        if imgui.CollapsingHeader('Test Display', imgui.TreeNodeFlags.DefaultOpen) then
            buf.testMode[0] = testMode
            if imgui.Checkbox('Show test sample', buf.testMode) then
                testMode = buf.testMode[0]
                if testMode then loadTestData() else clearOldTDs() end
            end
            if imgui.Button('Add test OUT') then
                testMode = true
                updateDamage('RandomGuy_' .. math.random(1, 99), 'outgoing', math.random(10, 150) + math.random(), 30)
            end
            imgui.SameLine()
            if imgui.Button('Add test IN') then
                testMode = true
                updateDamage('Enemy_' .. math.random(1, 99), 'incoming', math.random(10, 150) + math.random(), 31)
            end
            imgui.SameLine()
            if imgui.Button('Clear') then
                clearOldTDs()
            end
        end

        if imgui.CollapsingHeader('Presets') then
            imgui.InputText('Preset name', buf.presetName, ffi.sizeof(buf.presetName))
            imgui.SameLine()
            if imgui.Button('Save preset') then
                local pname = ffi.string(buf.presetName)
                if pname ~= '' then
                    syncToConfig()
                    local replaced = false
                    for _, p in ipairs(presets) do
                        if p.name == pname then
                            p.config = deepcopy(config)
                            replaced = true
                            break
                        end
                    end
                    if not replaced then
                        table.insert(presets, { name = pname, config = deepcopy(config) })
                    end
                    saveConfig()
                end
            end

            imgui.Separator()
            if #presets == 0 then
                imgui.TextDisabled('No saved presets')
            end
            for i = #presets, 1, -1 do
                local p = presets[i]
                imgui.Text(p.name)
                imgui.SameLine()
                if imgui.Button('Load##' .. i) then
                    for k in pairs(DEFAULT_CONFIG) do
                        if p.config[k] ~= nil then config[k] = p.config[k] end
                    end
                    syncFromConfig()
                    refreshAll()
                    saveConfig()
                end
                imgui.SameLine()
                if imgui.Button('Delete##' .. i) then
                    table.remove(presets, i)
                    saveConfig()
                end
            end
        end

        imgui.Separator()

        if imgui.Button('Save settings', imgui.ImVec2(200, 30)) then
            syncToConfig()
            saveConfig()
            refreshAll()
        end
        imgui.SameLine()
        if imgui.Button('Reset to defaults', imgui.ImVec2(200, 30)) then
            config = deepcopy(DEFAULT_CONFIG)
            syncFromConfig()
            saveConfig()
            refreshAll()
        end

        imgui.End()

        for _ = 1, #grayStyles do imgui.PopStyleColor() end

        if changed then
            syncToConfig()
            refreshAll()
        end
    end
)

function main()
    while not isSampAvailable() do wait(100) end
    pcall(function() cjson = require('cjson') end)

    loadConfig()
    syncFromConfig()

    sampRegisterChatCommand('dmgon', function()
        config.active = not config.active
        if not config.active then clearOldTDs() end
        saveConfig()
    end)

    sampRegisterChatCommand('dmg', function()
        window[0] = not window[0]
    end)
    while true do
        wait(100)
        if config.active then
            local now = os.clock()
            local changed = false

            if not testMode then
                for _, list in ipairs({ damageOut, damageIn }) do
                    local baseId = (list == damageOut and TD_OUT_BASE or TD_IN_BASE)
                    for i = #list, 1, -1 do
                        if now - list[i].lastTime > config.timeout then
                            for k = 1, TD_RANGE do
                                if IsExists(baseId + k) then Delete(baseId + k) end
                            end
                            table.remove(list, i)
                            changed = true
                        end
                    end
                end

                if changed then refreshAll() end

                if getCharHealth(PLAYER_PED) <= 0 and (#damageOut > 0 or #damageIn > 0) then
                    clearOldTDs()
                end
            end
        end
    end
end

function onReceivePacket(id, bs)
    if id ~= 220 or not config.active or not cjson then return true end
    local initialPos = raknetBitStreamGetReadOffset(bs)
    raknetBitStreamIgnoreBits(bs, 8)
    if raknetBitStreamReadInt8(bs) == 17 then
        raknetBitStreamIgnoreBits(bs, 32)
        local length = raknetBitStreamReadInt16(bs)
        local encoded = raknetBitStreamReadInt8(bs)
        if length > 0 and length < 65535 then
            local str = (encoded ~= 0) and raknetBitStreamDecodeString(bs, length) or raknetBitStreamReadString(bs, length)
            if str:find('initializeDamageInfo', 1, true) then
                local json_raw = str:match('%[?(%b{})%]?') or str:match('({.+})')
                local ok, data = pcall(cjson.decode, json_raw)
                if ok and data then
                    local info = (data[1] and type(data[1]) == 'table') and data[1] or (data.args or data)
                    local rawType = tostring(info.type or ''):lower()
                    local rawVal = tonumber(info.value)
                    local val = rawVal and math.abs(rawVal) or nil
                    local gunId = tonumber(info.imageId) or 0
                    local rawName = tostring(info.name or '')
                    local lowerName = rawName:lower()
                    local isCollision = tonumber(info.id) == 989999 
                        or rawName:find('кружен') 
                        or rawName:find('Окружен') 
                        or lowerName:find('collision') 
                        or (rawName == '' and val ~= nil and val > 0)
                    local isNotice = (not isCollision) and (rawType:find('skill') or (val == nil or val == 0) or (gunId == -1))
                    if not isNotice then
                        local customWeapon = nil
                        if isCollision then
                            customWeapon = 'Collision'
                            rawName = 'Collision'
                        end
                        local dmgType = (rawType == 'outgoing') and 'outgoing' or 'incoming'
                        updateDamage(rawName, dmgType, val, gunId, customWeapon)
                        local newStr = str:gsub('initializeDamageInfo', 'ignoredDamageInfo')
                        raknetBitStreamSetWriteOffset(bs, initialPos + 72)
                        if encoded ~= 0 then raknetBitStreamEncodeString(bs, newStr) else raknetBitStreamWriteString(bs, newStr) end
                    elseif not config.passCEFNotices then
                        local newStr = str:gsub('initializeDamageInfo', 'ignoredDamageInfo')
                        raknetBitStreamSetWriteOffset(bs, initialPos + 72)
                        if encoded ~= 0 then raknetBitStreamEncodeString(bs, newStr) else raknetBitStreamWriteString(bs, newStr) end
                    end
                end
            end
        end
    end
    raknetBitStreamSetReadOffset(bs, initialPos)
    return true
end