script_name('Evolve HUD')
script_author('mentaletion')
script_url('https://www.blast.hk/members/554950/')
script_version('2.3')

require 'lib.moonloader'
local imgui = require('mimgui')
local encoding = require('encoding')
encoding.default = 'CP1251'
local u8 = encoding.UTF8

local wm = require('lib.windows.message')
local vkeys = require('vkeys')
local ffi = require('ffi')
local cjson = require('cjson')
local sampev = require('lib.samp.events')
local bit = require('bit')

local BASE_TD_ID = 1600
local DRUG_TD_ID = 1650
local CAPT_BASE_TD_ID = 1800
local TD_TIME_ID = 2049

local is_logo_shown = false
local MAIN_TEXT = "ARIZONA"
local LOGO_LETTER = "A"

local LOGO_BASE_X = 540.0
local LOGO_BASE_Y = 5.0
local CAPT_BASE_X = 42.366600
local CAPT_BASE_Y = 218.022202
local DRUG_BASE_X = 610.000000
local DRUG_BASE_Y = 65.500000

local TD_TIME_CONFIG = {
    x            = 620.00,
    y            = 310.00,
    letter_w     = 1.00,
    letter_h     = 2.60,
    font         = 3,
    outline      = 2,
    shadow       = 2,
    align        = 3,
    proportional = 1,
    display_time = 5.0
}

local isPositioningLogo = false
local isPositioningCapt = false
local isPositioningDrug = false
local is_test_mode = false
local test_mode_type = 0

local time_hide_tick = 0
local is_time_td_active = false
local last_server_ts = nil
local last_time_show_tick = 0

local player_faction_cache = {}

local IP_TO_SERVER = {
    ['185.169.134.44:7777']  = 'CHANDLER',
    ['80.66.82.200:7777']   = 'QUEEN-CREEK',
    ['185.169.134.173:7777'] = 'WINSLOW',
    ['80.66.82.82:7777']    = 'FARAWAY',
    ['185.169.134.109:7777'] = 'SURPRISE',
    ['80.66.82.168:7777']   = 'PAGE',
    ['80.66.82.54:7777']    = 'CHRISTMAS',
    ['80.66.82.113:7777']   = 'YAVA',
    ['80.66.82.132:7777']   = 'HOLIDAY',
    ['185.169.134.166:7777'] = 'PRESCOTT',
    ['185.169.134.171:7777'] = 'GLENDALE',
    ['80.66.82.191:7777']   = 'GILBERT',
    ['185.169.134.174:7777'] = 'PAYSON',
    ['185.169.134.43:7777']  = 'SCOTTDALE',
    ['185.169.134.172:7777'] = 'KINGMAN',
    ['80.66.82.128:7777']   = 'WEDNESDAY',
    ['80.66.82.144:7777']   = 'SEDONA',
    ['80.66.82.159:7777']   = 'SUN-CITY',
    ['185.169.134.5:7777']   = 'SAINT-ROSE',
    ['80.66.82.190:7777']   = 'SHOW-LOW',
    ['185.169.134.45:7777']  = 'BRAINBURG',
    ['185.169.134.61:7777']  = 'RED-ROCK',
    ['80.66.82.87:7777']    = 'BUMBLE-BEE',
    ['185.169.134.3:7777']   = 'PHOENIX',
    ['185.169.134.107:7777'] = 'YUMA',
    ['80.66.82.39:7777']    = 'MIRAGE',
    ['185.169.134.59:7777']  = 'MESA',
    ['80.66.82.188:7777']   = 'CASA-GRANDE',
    ['80.66.82.33:7777']    = 'LOVE',
    ['185.169.134.4:7777']   = 'TUCSON',
    ['80.66.82.22:7777']    = 'DRAKE',
    ['80.66.82.235:7777']   = 'HOME'
}

local KNOWN_SERVERS = {
    "Phoenix", "Tucson", "Scottdale", "Chandler", "Brainburg", "Saint-Rose",
    "Mesa", "Red-Rock", "Yuma", "Surprise", "Prescott", "Glendale",
    "Kingman", "Winslow", "Payson", "Gilbert", "Show-Low", "Casa-Grande",
    "Page", "Sun-City", "Queen-Creek", "Sedona", "Holiday", "Wednesday",
    "Yava", "Faraway", "Bumble-Bee", "Christmas", "Mirage", "Drake",
    "Love", "Space", "Home"
}

local DEFAULT_CONFIG = {
    showLogo        = true,
    logoType        = 0,
    showCapt        = true,
    showDrugCd      = true,
    replaceDrugChat = true,
    recolorFactions = true,
    showGangZones   = true,
    showEvoTime     = true,
    logoX           = 540.0,
    logoY           = 5.0,
    captX           = 42.366600,
    captY           = 218.022202,
    drugX           = 610.000000,
    drugY           = 65.500000,
    drugAmount      = 0,
    deagleAmount    = 0,
    m4Amount        = 0,
    rifleAmount     = 0,
    shotgunAmount   = 0,
    materialsAmount = 0,
}

local function deepcopy(t)
    if type(t) ~= 'table' then return t end
    local r = {}
    for k, v in pairs(t) do r[k] = deepcopy(v) end
    return r
end

local config = deepcopy(DEFAULT_CONFIG)
local configDir  = getWorkingDirectory() .. '\\config'
local configPath = configDir .. '\\arz_evohud_config.json'

local function saveConfig()
    if not cjson then return end
    if not doesDirectoryExist(configDir) then createDirectory(configDir) end
    local f = io.open(configPath, 'w')
    if f then
        f:write(cjson.encode(config))
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
        for k in pairs(DEFAULT_CONFIG) do
            if data[k] ~= nil then config[k] = data[k] end
        end
    end
end

local function cp1251_lower(s)
    if not s then return "" end
    local res = {}
    for i = 1, #s do
        local b = string.byte(s, i)
        if b >= 65 and b <= 90 then
            b = b + 32
        elseif b >= 0xC0 and b <= 0xDF then
            b = b + 32
        elseif b == 0xA8 then
            b = 0xB8
        end
        res[i] = string.char(b)
    end
    return table.concat(res)
end

local EVO_COLS = {
    [0] = { minX = 1643.71, maxX = 1769.71 },
    [1] = { minX = 1771.71, maxX = 1897.71 },
    [2] = { minX = 1899.71, maxX = 2025.71 },
    [3] = { minX = 2027.71, maxX = 2153.71 },
    [4] = { minX = 2155.71, maxX = 2281.71 },
    [5] = { minX = 2283.71, maxX = 2409.71 },
    [6] = { minX = 2411.71, maxX = 2537.71 },
    [7] = { minX = 2539.71, maxX = 2665.71 },
    [8] = { minX = 2667.71, maxX = 2793.71 },
    [9] = { minX = 2795.71, maxX = 2921.71 }
}

local EVO_ROWS = {
    [0]  = { minY = -2173.57, maxY = -2073.57 },
    [1]  = { minY = -2072.57, maxY = -1973.57 },
    [2]  = { minY = -1971.57, maxY = -1872.57 },
    [3]  = { minY = -1870.57, maxY = -1771.57 },
    [4]  = { minY = -1769.57, maxY = -1670.57 },
    [5]  = { minY = -1668.57, maxY = -1569.57 },
    [6]  = { minY = -1567.57, maxY = -1468.57 },
    [7]  = { minY = -1466.57, maxY = -1367.57 },
    [8]  = { minY = -1365.57, maxY = -1266.57 },
    [9]  = { minY = -1264.57, maxY = -1165.57 },
    [10] = { minY = -1163.57, maxY = -1064.57 },
    [11] = { minY = -1062.57, maxY = -963.57  },
    [12] = { minY = -961.57,  maxY = -862.57  }
}

local function getArzGhettoCoords(zoneId)
    local row, col = nil, nil
    if zoneId == 129 then
        row = 0; col = 0
    elseif zoneId >= 0 and zoneId <= 8 then
        row = 0; col = zoneId + 1
    elseif zoneId >= 9 and zoneId <= 128 then
        local idx = zoneId - 9
        row = math.floor(idx / 10) + 1
        col = idx % 10
    end

    if row and col and EVO_ROWS[row] and EVO_COLS[col] then
        return {
            minX = EVO_COLS[col].minX,
            maxX = EVO_COLS[col].maxX,
            minY = EVO_ROWS[row].minY,
            maxY = EVO_ROWS[row].maxY
        }
    end
    return nil
end

local function convertGangZoneColor(color)
    if not color then return 0xFFFFFFFF end

    local r = bit.band(bit.rshift(color, 16), 0xFF)
    local g = bit.band(bit.rshift(color, 8), 0xFF)
    local b = bit.band(color, 0xFF)

    if (r < 15 and g < 15 and b < 15) or color == 0xFFFFFFFFFF000000 then
        return nil
    end

    if g > 100 and r < 60 and b < 40 then return 0x9906B506 end
    if r > 150 and b > 150 and g < 50 then return 0x99990085 end
    if g > 180 and b > 180 and r < 80 then return 0x9908BECF end
    if r > 180 and g > 200 and b < 50 then return 0x99858F03 end
    if r > 200 and g < 150 and b < 150 then return 0xAAFF7F00 end

    return bit.bor(bit.band(color, 0x00FFFFFF), 0x99000000)
end

local player_nickname = ""
local war_active = false
local total_war_damage = 0
local current_kills = 0
local warData = {}
local war_player_kills = {}
local war_player_faction = {}
local last_war_packet_time = 0
local war_pending_hide = 0

local last_drug_time = 0
local last_hit_time = 0
local last_hp = 100
local last_armour = 0
local last_used_amount = 10
local is_silent_stats_scan = false
local manual_stats_scan = false
local last_auto_sync = 0
local is_player_alive = true
local drug_td_shown = false
local last_drug_text = ""

local buf
local last_taken_weapon = nil
local last_taken_weapon_time = 0
local last_weapon_msg_time = 0
local stats_pages_scanned = 0

local SERVER_LOGO_IDS = {
    [246] = true, [247] = true, [248] = true, [249] = true, [250] = true,
    [251] = true, [252] = true, [253] = true, [254] = true, [255] = true,
    [256] = true, [257] = true, [258] = true, [259] = true, [260] = true,
    [261] = true, [262] = true, [263] = true, [264] = true, [265] = true,
    [280] = true, [281] = true, [282] = true, [283] = true, [284] = true, [285] = true,
    [293] = true, [294] = true, [295] = true,
    [544] = true, [545] = true, [546] = true,
    [605] = true, [606] = true
}

local saved_server_logo_pos = {
    [264] = { x = 501.0, y = 1.0 },
    [265] = { x = 540.0, y = 12.2 }
}

local function sendInfoMessage(text)
    sampAddChatMessage(string.format('{88AA62}[Информация] {A9C4E4}%s', text), -1)
    addOneOffSound(0.0, 0.0, 0.0, 1057)
end

local function sendErrorMessage(text)
    sampAddChatMessage(string.format('{E05454}[Ошибка] {A9C4E4}%s', text), -1)
    addOneOffSound(0.0, 0.0, 0.0, 1085)
end

local function parseHexColor(hex)
    if not hex or type(hex) ~= "string" then return nil end
    hex = hex:gsub("#", ""):gsub("%s+", "")
    if #hex == 6 then
        local num = tonumber(hex, 16)
        if num then return bit.bor(0xFF000000, num) end
    elseif #hex == 8 then
        local num = tonumber(hex, 16)
        if num then return num end
    end
    return nil
end

local function normalizeGang(name)
    if not name then return "" end
    name = name:upper():gsub("%s+", "_")
    if name:find("GROVE") then return "GROVE" end
    if name:find("BALLAS") then return "BALLAS" end
    if name:find("VAGOS") then return "VAGOS" end
    if name:find("AZTEC") then return "AZTECAS" end
    if name:find("RIFA") then return "RIFA" end
    if name:find("WOLV") or name == "NW" or name:find("NIGHT") then return "NW" end
    if name:find("LCN") or name:find("NOSTRA") then return "LCN" end
    if name:find("RM") or name:find("RUSSIAN") then return "RM" end
    if name:find("YAKUZA") then return "YAKUZA" end
    if name:find("WARLOCK") then return "WARLOCK" end
    if name:find("TIERRA") or name:find("BIKERS") or name == "TR_BIKERS" then return "TR_BIKERS" end
    if name:find("GOV") or name:find("ГОС") then return "GOVERNMENT" end
    if name:find("CRIME") or name:find("КРАЙМ") then return "CRIME" end
    return name
end

local ccolors = {
    ['RIFA']        = 0xFF2A9170,
    ['BALLAS']      = 0xFFB313E7,
    ['AZTECAS']     = 0xFF01FCFF,
    ['VAGOS']       = 0xFFFFDE24,
    ['YAKUZA']      = 0xFFFF0000,
    ['RM']          = 0xFFB4B5B7,
    ['LCN']         = 0xFFDDA701,
    ['WARLOCK']     = 0xFFF45000,
    ['GROVE']       = 0xFF009F00,
    ['NW']          = 0xFFA87878,
    ['WOLVES']      = 0xFFA87878,
    ['TR_BIKERS']   = 0xFFCFAF46,
    ['CRIME']       = 0xFFDA3130,
    ['GOVERNMENT']  = 0xFF2596BE
}

local EXACT_CLISTS = {
    [0x009327] = 'GROVE',
    [0xCC00CC] = 'BALLAS',
    [0xD1DB1C] = 'VAGOS',
    [0x00FFE2] = 'AZTECAS',
    [0x6666FF] = 'RIFA',
    [0xA87878] = 'NW',
    [0x960202] = 'YAKUZA',
    [0xCFAF46] = 'TR_BIKERS',
    [0xBA541D] = 'WARLOCK',
    [0x7697D9] = 'RM',
    [0x993366] = 'LCN',

    [0x009F00] = 'GROVE',
    [0xB313E7] = 'BALLAS',
    [0xFFDE24] = 'VAGOS',
    [0x01FCFF] = 'AZTECAS',
    [0x2A9170] = 'RIFA',
    [0xFF0000] = 'YAKUZA',
    [0xB4B5B7] = 'RM',
    [0xDDA701] = 'LCN',
    [0xF45000] = 'WARLOCK'
}

local FACTIONS = {
    ['GROVE']       = { r = 0x00, g = 0x93, b = 0x27 },
    ['BALLAS']      = { r = 0xCC, g = 0x00, b = 0xCC },
    ['VAGOS']       = { r = 0xD1, g = 0xDB, b = 0x1C },
    ['AZTECAS']     = { r = 0x00, g = 0xFF, b = 0xE2 },
    ['RIFA']        = { r = 0x66, g = 0x66, b = 0xFF },
    ['NW']          = { r = 0xA8, g = 0x78, b = 0x78 },
    ['YAKUZA']      = { r = 0x96, g = 0x02, b = 0x02 },
    ['TR_BIKERS']   = { r = 0xCF, g = 0xAF, b = 0x46 },
    ['WARLOCK']     = { r = 0xBA, g = 0x54, b = 0x1D },
    ['RM']          = { r = 0x76, g = 0x97, b = 0xD9 },
    ['LCN']         = { r = 0x99, g = 0x33, b = 0x66 }
}

local CUSTOM_FACTIONS = {
    ['RIFA']        = { argb = 0xFF2A9170, rgba = 0x2A9170FF },
    ['BALLAS']      = { argb = 0xFFB313E7, rgba = 0xB313E7FF },
    ['AZTECAS']     = { argb = 0xFF01FCFF, rgba = 0x01FCFFFF },
    ['VAGOS']       = { argb = 0xFFFFDE24, rgba = 0xFFDE24FF },
    ['YAKUZA']      = { argb = 0xFFFF0000, rgba = 0xFF0000FF },
    ['RM']          = { argb = 0xFFB4B5B7, rgba = 0xB4B5B7FF },
    ['LCN']         = { argb = 0xFFDDA701, rgba = 0xDDA701FF },
    ['WARLOCK']     = { argb = 0xFFF45000, rgba = 0xF45000FF },
    ['GROVE']       = { argb = 0xFF009F00, rgba = 0x009F00FF }
}

local function getFactionByColor(color)
    if not color or color == 0 or color == -1 then return nil end

    local rgb1 = bit.band(color, 0x00FFFFFF)
    local rgb2 = bit.band(bit.rshift(color, 8), 0x00FFFFFF)

    if rgb1 == 0xFFFFFF or rgb1 == 0x000000 or rgb1 == 0xCCCCCC or rgb1 == 0xAFAFAF then return nil end
    if rgb2 == 0xFFFFFF or rgb2 == 0x000000 or rgb2 == 0xCCCCCC or rgb2 == 0xAFAFAF then return nil end

    if EXACT_CLISTS[rgb1] then return EXACT_CLISTS[rgb1] end
    if EXACT_CLISTS[rgb2] then return EXACT_CLISTS[rgb2] end

    local r1 = bit.band(bit.rshift(rgb1, 16), 0xFF)
    local g1 = bit.band(bit.rshift(rgb1, 8), 0xFF)
    local b1 = bit.band(rgb1, 0xFF)

    local r2 = bit.band(bit.rshift(rgb2, 16), 0xFF)
    local g2 = bit.band(bit.rshift(rgb2, 8), 0xFF)
    local b2 = bit.band(rgb2, 0xFF)

    for name, f in pairs(FACTIONS) do
        if ((r1 - f.r)^2 + (g1 - f.g)^2 + (b1 - f.b)^2) < 600 then return name end
        if ((r2 - f.r)^2 + (g2 - f.g)^2 + (b2 - f.b)^2) < 600 then return name end
    end

    for name, f in pairs(CUSTOM_FACTIONS) do
        local cr = bit.band(bit.rshift(f.rgba, 24), 0xFF)
        local cg = bit.band(bit.rshift(f.rgba, 16), 0xFF)
        local cb = bit.band(bit.rshift(f.rgba, 8), 0xFF)

        if ((r1 - cr)^2 + (g1 - cg)^2 + (b1 - cb)^2) < 600 then return name end
        if ((r2 - cr)^2 + (g2 - cg)^2 + (b2 - cb)^2) < 600 then return name end
    end

    return nil
end

local function getGangColor(gangName, fallbackHex)
    local parsed = parseHexColor(fallbackHex)
    if parsed then return parsed end
    local key = normalizeGang(gangName)
    return ccolors[key] or 0xFFFFFFFF
end

local function getPlayerFactionCached(id)
    if player_faction_cache[id] then return player_faction_cache[id] end
    if not sampIsPlayerConnected(id) then
        local _, myId = sampGetPlayerIdByCharHandle(PLAYER_PED)
        if id ~= myId then return "" end
    end
    
    local color = sampGetPlayerColor(id)
    local fName = normalizeGang(getFactionByColor(color))
    
    if fName and fName ~= "" then
        player_faction_cache[id] = fName
    end
    return fName or ""
end

local function consumeWeaponCount()
    local cur_weap = getCurrentCharWeapon(PLAYER_PED)
    local key = nil

    if cur_weap == 24 then key = "deagleAmount"
    elseif cur_weap == 31 then key = "m4Amount"
    elseif cur_weap == 25 then key = "shotgunAmount"
    elseif cur_weap == 33 then key = "rifleAmount"
    end

    if not key and last_taken_weapon and (os.clock() - last_taken_weapon_time < 4.0) then
        local w = last_taken_weapon:lower()
        if w:find("desert") or w:find("eagle") or w:find("дигл") then
            key = "deagleAmount"
        elseif w:find("m4") or w:find("автомат") then
            key = "m4Amount"
        elseif w:find("винтовка") or w:find("rifle") then
            key = "rifleAmount"
        elseif w:find("дробовик") or w:find("shotgun") or w:find("шот") then
            key = "shotgunAmount"
        end
    end

    if not key and cur_weap == 24 then
        key = "deagleAmount"
    end

    if key then
        config[key] = math.max(0, (config[key] or 0) - 1)
        if buf and buf[key] then 
            buf[key][0] = config[key] 
        end
        saveConfig()
        return config[key]
    end

    return config.materialsAmount or 0
end

local td_id = {
    BG2 = CAPT_BASE_TD_ID + 2, BG3 = CAPT_BASE_TD_ID + 3, BG4 = CAPT_BASE_TD_ID + 4,
    BG5 = CAPT_BASE_TD_ID + 5, BG6 = CAPT_BASE_TD_ID + 6, BG7 = CAPT_BASE_TD_ID + 7, BG8 = CAPT_BASE_TD_ID + 8,
    GANG_1 = CAPT_BASE_TD_ID + 27, GANG_2 = CAPT_BASE_TD_ID + 28, TIME = CAPT_BASE_TD_ID + 29,
    KILLS_1 = CAPT_BASE_TD_ID + 25, KILLS_2 = CAPT_BASE_TD_ID + 26,
    MYSCORE = CAPT_BASE_TD_ID + 9, DAMAGE = CAPT_BASE_TD_ID + 10, MYKILLS = CAPT_BASE_TD_ID + 11, TOP = CAPT_BASE_TD_ID + 12,
    NICK1 = CAPT_BASE_TD_ID + 13, NICK2 = CAPT_BASE_TD_ID + 14, DAMAGESROCE = CAPT_BASE_TD_ID + 16, KILLSSCORE = CAPT_BASE_TD_ID + 15,
    KILL1NIZ = CAPT_BASE_TD_ID + 17, KILL2NIZ = CAPT_BASE_TD_ID + 18
}

local RAW_TDD = {
    {id = td_id.BG2,  text = "FixChit",  x = 42.366600,  y = 218.022202, letter_width = 0, letter_height = 0, line_width = 16, line_height = 18, align = 1, letter_color = 0xFFFA3553, use_box = false, box_color = 0x00000000, bg_color = 255, style = 4, proportional = true, shadow = 0, outline = 0},
    {id = td_id.BG3,  text = "FixWhite", x = 50.366600,  y = 220.896301, letter_width = 0, letter_height = 0, line_width = 83.859901, line_height = 19, align = 1, letter_color = 0xFFFA3553, use_box = false, box_color = 0x00000000, bg_color = 255, style = 4, proportional = true, shadow = 0, outline = 0},
    {id = td_id.BG4,  text = "FixChit",  x = 120.732903, y = 281.648102, letter_width = 0, letter_height = 0, line_width = 16, line_height = 18, align = 1, letter_color = 0xFFFA3553, use_box = false, box_color = 0x00000000, bg_color = 255, style = 4, proportional = true, shadow = 0, outline = 0},
    {id = td_id.BG5,  text = "FixWhite", x = 44.833099,  y = 277.726013, letter_width = 0, letter_height = 0, line_width = 83.859901, line_height = 19, align = 1, letter_color = 0xFFFA3553, use_box = false, box_color = 0x00000000, bg_color = 255, style = 4, proportional = true, shadow = 0, outline = 0},
    {id = td_id.BG6,  text = "FixWhite", x = 44.700001,  y = 227.148102, letter_width = 0, letter_height = 0, line_width = 89.569901, line_height = 20, align = 1, letter_color = 0xFF191919, use_box = false, box_color = 0x00000000, bg_color = 255, style = 4, proportional = true, shadow = 0, outline = 0},
    {id = td_id.BG7,  text = "FixWhite", x = 44.666500,  y = 247.533203, letter_width = 0, letter_height = 0, line_width = 89.569903, line_height = 21.1, align = 1, letter_color = 0xFF191919, use_box = false, box_color = 0x00000000, bg_color = 255, style = 4, proportional = true, shadow = 0, outline = 0},
    {id = td_id.BG8,  text = "FixWhite", x = 44.766602,  y = 269.133209, letter_width = 0, letter_height = 0, line_width = 89.569504, line_height = 21.1, align = 1, letter_color = 0xFF191919, use_box = false, box_color = 0x00000000, bg_color = 255, style = 4, proportional = true, shadow = 0, outline = 0},
    {id = td_id.GANG_1, text = "GANG1",    x = 61.500401,  y = 230.525803, letter_width = 0, letter_height = 0, line_width = 12, line_height = 14, align = 1, letter_color = 0xFFFFFFFF, use_box = false, box_color = 0x00000000, bg_color = 0x00000000, style = 5, proportional = false, shadow = 0, outline = 0},
    {id = td_id.GANG_2, text = "GANG2",    x = 105.499802, y = 230.525803, letter_width = 0, letter_height = 0, line_width = 12, line_height = 14, align = 1, letter_color = 0xFFFFEEAA, use_box = false, box_color = 0x00000000, bg_color = 0x00000000, style = 5, proportional = false, shadow = 0, outline = 0},
    {id = td_id.KILL1NIZ, text = "KILLS1NIZ",x = 42.799900,  y = 224.562805, letter_width = 0, letter_height = 0, line_width = 22, line_height = 25, align = 1, letter_color = 0x5E000000, use_box = false, box_color = 0x00000000, bg_color = 0x00000000, style = 5, proportional = false, shadow = 0, outline = 0},
    {id = td_id.KILL2NIZ, text = "KILLS2NIZ",x = 113.833000, y = 224.562805, letter_width = 0, letter_height = 0, line_width = 22, line_height = 25, align = 1, letter_color = 0x5E000000, use_box = false, box_color = 0x00000000, bg_color = 0x00000000, style = 5, proportional = false, shadow = 0, outline = 0},
    {id = td_id.MYSCORE,  text = "MY_PERSONAL_SCORE", x = 89.733200, y = 248.588806, letter_width = 0.141399, letter_height = 0.641700, line_width = 0.0, line_height = 0.0, align = 2, letter_color = 0xFFFFFFFF, use_box = false, box_color = 0, bg_color = 150, style = 1, proportional = true, shadow = 0, outline = 0},
    {id = td_id.DAMAGE,   text = "DAMAGE",   x = 96.699600,  y = 257.299805, letter_width = 0.141200, letter_height = 0.641700, line_width = 0.0, line_height = 0.0, align = 2, letter_color = 0x3CFFFFFF, use_box = false, box_color = 0, bg_color = 150, style = 1, proportional = true, shadow = 0, outline = 0},
    {id = td_id.MYKILLS,  text = "KILLS",    x = 57.900200,  y = 257.299805, letter_width = 0.141200, letter_height = 0.641700, line_width = 0.0, line_height = 0.0, align = 2, letter_color = 0x3CFFFFFF, use_box = false, box_color = 0, bg_color = 150, style = 1, proportional = true, shadow = 0, outline = 0},
    {id = td_id.TOP,      text = "TOP",      x = 89.166603,  y = 270.288605, letter_width = 0.141200, letter_height = 0.641700, line_width = 0.0, line_height = 0.0, align = 2, letter_color = 0xFFFFFFFF, use_box = false, box_color = 0, bg_color = 150, style = 1, proportional = true, shadow = 0, outline = 0},
    {id = td_id.NICK1,    text = "Waiting",  x = 66.166603,  y = 278.585114, letter_width = 0.141200, letter_height = 0.641700, line_width = 0.0, line_height = 0.0, align = 2, letter_color = 0x3CFFFFFF, use_box = false, box_color = 0, bg_color = 150, style = 1, proportional = true, shadow = 0, outline = 0},
    {id = td_id.NICK2,    text = "Waiting",  x = 111.333099, y = 278.585114, letter_width = 0.141200, letter_height = 0.641700, line_width = 0.0, line_height = 0.0, align = 2, letter_color = 0x3CFFFFFF, use_box = false, box_color = 0, bg_color = 150, style = 1, proportional = true, shadow = 0, outline = 0},
    {id = td_id.KILLSSCORE, text = "0",      x = 68.066200,  y = 256.514709, letter_width = 0.138600, letter_height = 0.782800, line_width = 0.0, line_height = 0.0, align = 2, letter_color = 0xFFFFFFFF, use_box = false, box_color = 0, bg_color = 150, style = 1, proportional = true, shadow = 0, outline = 0},
    {id = td_id.DAMAGESROCE, text = "0",     x = 112.500000, y = 256.514709, letter_width = 0.138600, letter_height = 0.782800, line_width = 0.0, line_height = 0.0, align = 2, letter_color = 0xFFFFFFFF, use_box = false, box_color = 0, bg_color = 150, style = 1, proportional = true, shadow = 0, outline = 0},
    {id = td_id.TIME,     text = "Time: 15:00", x = 89.400002, y = 232.610901, letter_width = 0.214399, letter_height = 1.081400, line_width = 0.0, line_height = 0.0, align = 2, letter_color = 0xFFFFFFFF, use_box = false, box_color = 0, bg_color = 150, style = 1, proportional = true, shadow = 0, outline = 0},
    {id = td_id.KILLS_1,  text = "0",        x = 54.400101,  y = 231.651901, letter_width = 0.158600, letter_height = 1.093700, line_width = 0.0, line_height = 0.0, align = 2, letter_color = 0xFFFFFFFF, use_box = false, box_color = 0, bg_color = 150, style = 2, proportional = true, shadow = 0, outline = 0},
    {id = td_id.KILLS_2,  text = "0",        x = 125.166603, y = 231.651901, letter_width = 0.158600, letter_height = 1.093700, line_width = 0.0, line_height = 0.0, align = 2, letter_color = 0xFFFFFFFF, use_box = false, box_color = 0, bg_color = 150, style = 2, proportional = true, shadow = 0, outline = 0},
}

local function isScriptTextdraw(id)
    if not id then return false end
    if id >= BASE_TD_ID and id <= BASE_TD_ID + 25 then return true end
    if id == DRUG_TD_ID then return true end
    if id >= CAPT_BASE_TD_ID and id <= CAPT_BASE_TD_ID + 35 then return true end
    if id == TD_TIME_ID then return true end
    return false
end

local function isServerLogoTD(id, x, y, text)
    if id and isScriptTextdraw(id) then return false end
    if id and SERVER_LOGO_IDS[id] then return true end
    if x and y then
        if x >= 490.0 and y <= 45.0 then return true end
    end
    if text then
        local t = text:lower()
        if (t:find('arizona') or t:find('arz')) and (not y or y <= 60.0) then
            return true
        end
    end
    return false
end

local function isCaptServerTD(id, x, y, text)
    if id and isScriptTextdraw(id) then return false end
    if x and y then
        if (x == 21.0 and y == 230.0) or math.abs(x - 133.3) < 0.2 then return true end
    end
    if text then
        local t = text:lower()
        if t:find('time: %d+:%d+') or t:find('gang wars') or t:find('mafia wars') or t:find('in_zone') then
            return true
        end
    end
    return false
end

local function hideServerCaptTextdraws()
    if not config.showCapt then return end
    for id = 0, 2304 do
        if not isScriptTextdraw(id) and sampTextdrawIsExists(id) then
            local text = sampTextdrawGetString(id)
            local px, py = sampTextdrawGetPos(id)
            if isCaptServerTD(id, px, py, text) then
                sampTextdrawSetPos(id, -1000, -1000)
            end
        end
    end
end

local function hideServerLogo()
    for id = 0, 2304 do
        if not isScriptTextdraw(id) and sampTextdrawIsExists(id) then
            local px, py = sampTextdrawGetPos(id)
            local text = sampTextdrawGetString(id)
            if isServerLogoTD(id, px, py, text) then
                if px > -500 and py > -500 then
                    saved_server_logo_pos[id] = { x = px, y = py }
                end
                sampTextdrawSetPos(id, -1000, -1000)
            end
        end
    end
    for sId, _ in pairs(saved_server_logo_pos) do
        if sampTextdrawIsExists(sId) then
            sampTextdrawSetPos(sId, -1000, -1000)
        end
    end
end

local function restoreServerLogo()
    for sId, pos in pairs(saved_server_logo_pos) do
        if sampTextdrawIsExists(sId) then
            sampTextdrawSetPos(sId, pos.x, pos.y)
        end
    end
end

local function formatTime(seconds)
    if not seconds then return "00:00" end
    local m = math.floor(seconds / 60)
    local s = seconds % 60
    return string.format("%02d:%02d", m, s)
end

local function parseInventoryLine(line)
    local clean = line:gsub('{.-}', '')
    local slot_str, name_str, count_str = clean:match("%[(%d+)%]%s*(.-)\t%s*%[(%d+)")
    if not slot_str then
        slot_str, name_str, count_str = clean:match("%[(%d+)%]%s*(.-)%s*%[(%d+)")
    end

    if not slot_str or not count_str then 
        return nil, nil, nil 
    end

    local slot = tonumber(slot_str)
    local count = tonumber(count_str) or 0
    local lowerName = name_str:lower()
    local itemType = nil

    local ok, u8_name = pcall(u8, name_str)
    local u8_lower = (ok and u8_name) and u8_name:lower() or lowerName

    if lowerName:find("укроп") or u8_lower:find("укроп") or clean:find("[\xD3\xF3][\xCA\xEA][\xD0\xF0][\xCE\xEE][\xCF\xEF]") then
        itemType = "ukrop"
    elseif lowerName:find("desert eagle") or lowerName:find("дигл") or u8_lower:find("дигл") then
        itemType = "deagle"
    elseif lowerName:find("автомат m4") or lowerName:find("m4") or u8_lower:find("автомат m4") then
        itemType = "m4"
    elseif lowerName:find("винтовка") or lowerName:find("rifle") or u8_lower:find("винтовка") or clean:find("[\xC2\xE2][\xE8\xC8][\xED\xCD][\xF2\xD2][\xEE\xCE][\xE2\xC2][\xEA\xCA][\xE0\xC0]") then
        itemType = "rifle"
    elseif lowerName:find("дробовик") or lowerName:find("shotgun") or u8_lower:find("дробовик") or clean:find("[\xC4\xE4][\xF0\xD0][\xEE\xCE][\xE1\xC1][\xEE\xCE][\xE2\xC2][\xE8\xC8][\xEA\xCA]") then
        itemType = "shotgun"
    elseif lowerName:find("материалы") or u8_lower:find("материалы") or clean:find("[\xCC\xEC][\xE0\xC0][\xF2\xD2][\xE5\xC5][\xF0\xD0][\xE8\xC8][\xE0\xC0][\xEB\xCB][\xFB\xDB]") then
        itemType = "materials"
    end

    return slot, itemType, count
end

local function isNextPageLine(line)
    local clean = line:gsub('{.-}', '')
    local ok, u8_text = pcall(u8, clean)
    local text = (ok and u8_text) and u8_text or clean

    if (text:find(">>") or text:find("»") or text:find("Следующая") or clean:find("[\xD1\xF1][\xEB\xCB][\xE5\xC5][\xE4\xC4][\xF3\xD3][\xFE\xDE][\xF9\xD9][\xE0\xC0][\xFF\xDF]"))
       and not text:find("<<") and not text:find("Предыдущая") then
        return true
    end
    return false
end

local scanned_inventory_slots = {}
local sync_in_progress = false

local function triggerBackgroundSync(reason)
    local now = os.clock()
    if sync_in_progress or is_silent_stats_scan or (now - last_auto_sync < 30.0) then 
        return 
    end

    sync_in_progress = true
    last_auto_sync = now

    lua_thread.create(function()
        wait(3000)
        while sampIsDialogActive() or not sampIsLocalPlayerSpawned() do
            wait(1000)
        end

        manual_stats_scan = false
        is_silent_stats_scan = true
        stats_pages_scanned = 0
        scanned_inventory_slots = {}
        sampSendChat('/stats')
        sync_in_progress = false
    end)
end

function startManualStatsScan()
    if is_silent_stats_scan then return end
    is_silent_stats_scan = true
    manual_stats_scan = true
    stats_pages_scanned = 0
    scanned_inventory_slots = {}
    sampSendChat('/stats')
    sendInfoMessage("Запрос инвентаря через /stats...")

    lua_thread.create(function()
        local timeout = os.clock() + 8.0
        while is_silent_stats_scan and os.clock() < timeout do
            wait(100)
        end
        if is_silent_stats_scan then
            is_silent_stats_scan = false
            manual_stats_scan = false
            sendErrorMessage("Таймаут синхронизации инвентаря.")
        end
    end)
end

local function isValidPlayer(id)
    if not id or id == 65535 then return false end
    local res, myId = sampGetPlayerIdByCharHandle(PLAYER_PED)
    if res and id == myId then return true end
    return sampIsPlayerConnected(id)
end

local function isEnemy(targetId)
    if not war_active or not isValidPlayer(targetId) then return false end
    local _, myId = sampGetPlayerIdByCharHandle(PLAYER_PED)
    if targetId == myId then return false end

    local myFaction = getPlayerFactionCached(myId)
    local targetFaction = getPlayerFactionCached(targetId)

    local g1 = normalizeGang(warData.gang1 and warData.gang1.name)
    local g2 = normalizeGang(warData.gang2 and warData.gang2.name)

    if targetFaction and targetFaction ~= "" then
        if myFaction and myFaction ~= "" then
            if targetFaction == myFaction then return false end
            if targetFaction == g1 or targetFaction == g2 then return true end
        else
            if targetFaction == g1 or targetFaction == g2 then return true end
        end
    end

    if g1 ~= "" and g2 ~= "" and targetFaction ~= "" then
        return targetFaction == g1 or targetFaction == g2
    end

    return sampGetPlayerColor(targetId) ~= sampGetPlayerColor(myId)
end

local function destroyWarTextdraws()
    for _, data in ipairs(RAW_TDD) do
        if sampTextdrawIsExists(data.id) then
            sampTextdrawDelete(data.id)
        end
    end
end

local function setupEvolveVisualTextdraws()
    if sampTextdrawIsExists(td_id.BG2) then sampTextdrawSetString(td_id.BG2, "LD_BEAT:chit") end
    if sampTextdrawIsExists(td_id.BG3) then sampTextdrawSetString(td_id.BG3, "LD_SPAC:white") end
    if sampTextdrawIsExists(td_id.BG4) then sampTextdrawSetString(td_id.BG4, "LD_BEAT:chit") end
    if sampTextdrawIsExists(td_id.BG5) then sampTextdrawSetString(td_id.BG5, "LD_SPAC:white") end
    if sampTextdrawIsExists(td_id.BG6) then sampTextdrawSetString(td_id.BG6, "LD_SPAC:white") end
    if sampTextdrawIsExists(td_id.BG7) then sampTextdrawSetString(td_id.BG7, "LD_SPAC:white") end
    if sampTextdrawIsExists(td_id.BG8) then sampTextdrawSetString(td_id.BG8, "LD_SPAC:white") end

    if sampTextdrawIsExists(td_id.GANG_1) then
        sampTextdrawSetModelRotationZoomVehColor(td_id.GANG_1, 1254, 0, 0, 0, 0.828800, 0, 0)
        sampTextdrawSetShadow(td_id.GANG_1, 0, 0)
    end
    if sampTextdrawIsExists(td_id.GANG_2) then
        sampTextdrawSetModelRotationZoomVehColor(td_id.GANG_2, 1254, 0, 0, 0, 0.828800, 0, 0)
        sampTextdrawSetShadow(td_id.GANG_2, 0, 0)
    end

    if sampTextdrawIsExists(td_id.KILL1NIZ) then
        sampTextdrawSetModelRotationZoomVehColor(td_id.KILL1NIZ, 2730, 0, 0, 0, 1.001000, 0, 0)
        sampTextdrawSetShadow(td_id.KILL1NIZ, 0, 0)
    end
    if sampTextdrawIsExists(td_id.KILL2NIZ) then
        sampTextdrawSetModelRotationZoomVehColor(td_id.KILL2NIZ, 2730, 0, 0, 0, 1.001000, 0, 0)
        sampTextdrawSetShadow(td_id.KILL2NIZ, 0, 0)
    end
end

local function recalculateTopPlayers()
    local g1_name = normalizeGang(warData.gang1 and warData.gang1.name)
    local g2_name = normalizeGang(warData.gang2 and warData.gang2.name)

    local max1, max2 = 0, 0
    local top1, top2 = nil, nil

    for nick, kills in pairs(war_player_kills) do
        local fName = war_player_faction[nick] or ""
        if fName == "" then
            for i = 0, sampGetMaxPlayerId(true) do
                if isValidPlayer(i) and sampGetPlayerNickname(i) == nick then
                    fName = getPlayerFactionCached(i)
                    if fName and fName ~= "" then
                        war_player_faction[nick] = fName
                    end
                    break
                end
            end
        end

        if fName == g1_name then
            if kills > max1 then
                max1 = kills
                top1 = nick
            end
        elseif fName == g2_name then
            if kills > max2 then
                max2 = kills
                top2 = nick
            end
        end
    end

    if not warData.gang1 then warData.gang1 = {} end
    if not warData.gang2 then warData.gang2 = {} end

    local def1 = (warData.gang1.name and warData.gang1.name ~= "") and warData.gang1.name or "AZTECAS"
    local def2 = (warData.gang2 and warData.gang2.name ~= "") and warData.gang2.name or "VAGOS"

    warData.gang1.top = top1 or def1
    warData.gang2.top = top2 or def2
end

local function updateWarTextdraws()
    if not war_active or not sampTextdrawIsExists(td_id.TIME) then return end

    local deltaX = config.captX - CAPT_BASE_X
    local deltaY = config.captY - CAPT_BASE_Y

    local g1_name = warData.gang1 and warData.gang1.name or "AZTECAS"
    local g2_name = warData.gang2 and warData.gang2.name or "VAGOS"
    local g1_color = (warData.gang1 and warData.gang1.color) or getGangColor(g1_name, warData.gang1 and warData.gang1.textColor)
    local g2_color = (warData.gang2 and warData.gang2.color) or getGangColor(g2_name, warData.gang2 and warData.gang2.textColor)

    if sampTextdrawIsExists(td_id.GANG_1) then
        sampTextdrawSetLetterSizeAndColor(td_id.GANG_1, 0, 0, g1_color)
    end
    if sampTextdrawIsExists(td_id.GANG_2) then
        sampTextdrawSetLetterSizeAndColor(td_id.GANG_2, 0, 0, g2_color)
    end

    if sampTextdrawIsExists(td_id.KILLSSCORE) then
        sampTextdrawSetString(td_id.KILLSSCORE, tostring(current_kills))
    end
    if sampTextdrawIsExists(td_id.DAMAGESROCE) then
        sampTextdrawSetString(td_id.DAMAGESROCE, string.format("%.0f", total_war_damage))
    end

    if sampTextdrawIsExists(td_id.KILLS_1) then
        sampTextdrawSetString(td_id.KILLS_1, tostring(warData.gang1 and warData.gang1.kills or 0))
    end
    if sampTextdrawIsExists(td_id.KILLS_2) then
        sampTextdrawSetString(td_id.KILLS_2, tostring(warData.gang2 and warData.gang2.kills or 0))
    end
    if sampTextdrawIsExists(td_id.TIME) then
        sampTextdrawSetString(td_id.TIME, formatTime(warData.time or 0))
    end

    local top1 = (warData.gang1 and warData.gang1.top) or g1_name
    local top2 = (warData.gang2 and warData.gang2.top) or g2_name

    local is_long1 = #top1 > 14
    local nick1_display = is_long1 and top1:gsub("_", "~n~") or top1
    local target_y1 = (is_long1 and 273.585114 or 278.585114) + deltaY

    local is_long2 = #top2 > 14
    local nick2_display = is_long2 and top2:gsub("_", "~n~") or top2
    local target_y2 = (is_long2 and 273.585114 or 278.585114) + deltaY

    if sampTextdrawIsExists(td_id.NICK1) then
        sampTextdrawSetPos(td_id.NICK1, 66.166603 + deltaX, target_y1)
        sampTextdrawSetString(td_id.NICK1, nick1_display)
    end
    if sampTextdrawIsExists(td_id.NICK2) then
        sampTextdrawSetPos(td_id.NICK2, 111.333099 + deltaX, target_y2)
        sampTextdrawSetString(td_id.NICK2, nick2_display)
    end
end

local function createWarTextdraws()
    hideServerCaptTextdraws()
    destroyWarTextdraws()

    local deltaX = config.captX - CAPT_BASE_X
    local deltaY = config.captY - CAPT_BASE_Y

    local g1_name = warData.gang1 and warData.gang1.name or "AZTECAS"
    local g2_name = warData.gang2 and warData.gang2.name or "VAGOS"
    local g1_color = (warData.gang1 and warData.gang1.color) or getGangColor(g1_name, warData.gang1 and warData.gang1.textColor)
    local g2_color = (warData.gang2 and warData.gang2.color) or getGangColor(g2_name, warData.gang2 and warData.gang2.textColor)

    for _, data in ipairs(RAW_TDD) do
        local l_color = data.letter_color
        if data.id == td_id.GANG_1 then l_color = g1_color end
        if data.id == td_id.GANG_2 then l_color = g2_color end

        sampTextdrawCreate(data.id, data.text, data.x + deltaX, data.y + deltaY)
        sampTextdrawSetLetterSizeAndColor(data.id, data.letter_width, data.letter_height, l_color)
        sampTextdrawSetAlign(data.id, data.align)
        sampTextdrawSetBoxColorAndSize(data.id, data.use_box and 1 or 0, data.box_color, data.line_width, data.line_height)
        sampTextdrawSetProportional(data.id, data.proportional and 1 or 0)
        sampTextdrawSetStyle(data.id, data.style)
        sampTextdrawSetShadow(data.id, data.shadow, 0xFF000000)
        sampTextdrawSetOutlineColor(data.id, data.outline, 0xFF000000)
    end

    setupEvolveVisualTextdraws()
    updateWarTextdraws()
end

local function applyTestWarData(mType)
    war_player_kills = {}
    war_player_faction = {}
    total_war_damage = 2500
    current_kills = 5

    if mType == 1 then
        warData = {
            eventName = "БИТВА ЗА ЗАВОД",
            time = 600,
            gang1 = { name = "GOVERNMENT", kills = 14, textColor = "#2596be", color = 0xFF2596BE, top = "GOVERNMENT" },
            gang2 = { name = "CRIME", kills = 42, textColor = "#da3130", color = 0xFFDA3130, top = player_nickname }
        }
    else
        warData = {
            eventName = "GHETTO",
            time = 600,
            gang1 = { name = "AZTECAS", kills = 45, textColor = "#01fcff", color = 0xFF01FCFF, top = player_nickname },
            gang2 = { name = "VAGOS", kills = 40, textColor = "#ffde24", color = 0xFFFFDE24, top = "VAGOS" }
        }
    end
end

local function getDynamicServerName()
    local ok, ip, port = pcall(sampGetCurrentServerAddress)
    if ok and ip and port then
        local key = ip .. ":" .. tostring(port)
        if IP_TO_SERVER[key] then
            return IP_TO_SERVER[key]:upper()
        end
    end

    local name = sampGetCurrentServerName()
    if not name or name == '' then return "SERVER" end
    name = name:gsub('{.-}', '')
    local known_servers = { "PHOENIX", "TUCSON", "SCOTTDALE", "CHANDLER", "BRAINBURG", "SAINT-ROSE", "MESA", "RED-ROCK", "YUMA", "SURPRISE", "PRESCOTT", "GLENDALE", "KINGMAN", "WINSLOW", "PAYSON", "GILBERT", "SHOW-LOW", "CASA-GRANDE", "PAGE", "SUN-CITY", "QUEEN-CREEK", "SEDONA", "HOLIDAY", "WEDNESDAY", "YAVA", "FARAWAY", "BUMBLE-BEE", "CHRISTMAS", "MIRAGE", "DRAKE", "LOVE", "SPACE", "HOME" }
    local upperName = name:upper()
    for _, sName in ipairs(known_servers) do
        if upperName:find(sName:gsub("%-", "%%-")) then return sName:gsub("%s+", "-") end
    end
    return "SERVER"
end

local function getFormattedServerName()
    local ok, ip, port = pcall(sampGetCurrentServerAddress)
    if ok and ip and port then
        local key = ip .. ":" .. tostring(port)
        if IP_TO_SERVER[key] then
            local s = IP_TO_SERVER[key]
            return s:sub(1,1):upper() .. s:sub(2):lower()
        end
    end

    local name = sampGetCurrentServerName()
    if name and name ~= '' then
        name = name:gsub('{.-}', '')
        local lowerName = name:lower()
        for _, sName in ipairs(KNOWN_SERVERS) do
            local cleanS = sName:lower():gsub("%-", "%%-")
            if lowerName:find(cleanS) then
                return sName
            end
        end
        local afterPipe = name:match("|%s*([%w%-_]+)")
        if afterPipe and afterPipe:lower() ~= "role" and afterPipe:lower() ~= "play" then
            return afterPipe:sub(1,1):upper() .. afterPipe:sub(2):lower()
        end
    end

    return "Yuma"
end

local function createEmulatorTextDraw(tdId, td)
    local bs = raknetNewBitStream()
    local flags = 0
    if td.useBox == 1 then flags = bit.bor(flags, 0x01) end
    if td.align == 1 then flags = bit.bor(flags, 0x02) elseif td.align == 3 then flags = bit.bor(flags, 0x04) elseif td.align == 2 then flags = bit.bor(flags, 0x08) end
    if td.prop == 1 then flags = bit.bor(flags, 0x10) end

    raknetBitStreamWriteInt16(bs, tdId)
    raknetBitStreamWriteInt8(bs, flags)
    raknetBitStreamWriteFloat(bs, td.letterW or 0.0)
    raknetBitStreamWriteFloat(bs, td.letterH or 0.0)
    raknetBitStreamWriteInt32(bs, td.color or 0xFFFFFFFF)
    raknetBitStreamWriteFloat(bs, td.textW or 0.0)
    raknetBitStreamWriteFloat(bs, td.textH or 0.0)
    raknetBitStreamWriteInt32(bs, td.boxColor or 0)
    raknetBitStreamWriteInt8(bs, td.shadow or 0)
    raknetBitStreamWriteInt8(bs, td.outline or 0)
    raknetBitStreamWriteInt32(bs, td.bg or 0xFF000000)
    raknetBitStreamWriteInt8(bs, td.font or 1)
    raknetBitStreamWriteInt8(bs, td.selectable or 0)
    raknetBitStreamWriteFloat(bs, td.posX)
    raknetBitStreamWriteFloat(bs, td.posY)
    raknetBitStreamWriteInt16(bs, 0)
    raknetBitStreamWriteFloat(bs, 0.0)
    raknetBitStreamWriteFloat(bs, 0.0)
    raknetBitStreamWriteFloat(bs, 0.0)
    raknetBitStreamWriteFloat(bs, 1.0)
    raknetBitStreamWriteInt16(bs, 0)
    raknetBitStreamWriteInt16(bs, 0)
    raknetBitStreamWriteInt16(bs, #td.text)
    raknetBitStreamWriteString(bs, td.text)

    raknetEmulRpcReceiveBitStream(134, bs)
    raknetDeleteBitStream(bs)
end

local function hideEmulatorTextDraw(tdId)
    local bs = raknetNewBitStream()
    raknetBitStreamWriteInt16(bs, tdId)
    raknetEmulRpcReceiveBitStream(135, bs)
    raknetDeleteBitStream(bs)
end

local function getLogoData()
    local sName = getDynamicServerName()
    local cRed = 0xFF4F38FF
    local deltaX = config.logoX - LOGO_BASE_X
    local deltaY = config.logoY - LOGO_BASE_Y

    return {
        { posX = 546.898621 + deltaX, posY = 34.118301 + deltaY, text = "particle:lamp_shad_64", letterW = 0.48, letterH = 1.12, textW = 21.799900, textH = -15.140000, align = 1, color = 0xC1000000, font = 4, prop = 0, bg = 0xFF000000 },
        { posX = 588.565125 + deltaX, posY = 8.354500  + deltaY, text = MAIN_TEXT,              letterW = 0.293700, letterH = 1.519700, textW = 1280.0, textH = 1280.0, align = 2, color = 0xFFFFFFFF, font = 1, prop = 1, outline = 1, bg = 0x18000000 },
        { posX = 544.132019 + deltaX, posY = 3.321800  + deltaY, text = "LD_BEAT:chit",         letterW = 0.48, letterH = 1.12, textW = 28.0, textH = 33.0, align = 1, color = cRed, font = 4, prop = 0, bg = 0xFF000000 },
        { posX = 558.198608 + deltaX, posY = 10.154600 + deltaY, text = LOGO_LETTER,            letterW = 0.454400, letterH = 1.927000, textW = 1280.0, textH = 1280.0, align = 2, color = 0xFFFFFFFF, font = 1, prop = 1, bg = 0x5D000000 },
        { posX = 554.132324 + deltaX, posY = 2.632800  + deltaY, text = "LD_BEAT:chit",         letterW = 0.48, letterH = 1.12, textW = 8.0, textH = 10.0, align = 1, color = cRed, font = 4, prop = 0, bg = 0xFF000000 },
        { posX = 549.865723 + deltaX, posY = 1.647600  + deltaY, text = "LD_BEAT:chit",         letterW = 0.48, letterH = 1.12, textW = 16.0, textH = 28.0, align = 1, color = cRed, font = 4, prop = 0, bg = 0xFF000000 },
        { posX = 547.999329 + deltaX, posY = 5.036700  + deltaY, text = "LD_BEAT:chit",         letterW = 0.48, letterH = 1.12, textW = 7.0, textH = 9.0, align = 1, color = cRed, font = 4, prop = 0, bg = 0xFF000000 },
        { posX = 546.498718 + deltaX, posY = 5.936800  + deltaY, text = "LD_BEAT:chit",         letterW = 0.48, letterH = 1.12, textW = 19.0, textH = 13.0, align = 1, color = cRed, font = 4, prop = 0, bg = 0xFF000000 },
        { posX = 541.999023 + deltaX, posY = 9.814100  + deltaY, text = "LD_BEAT:chit",         letterW = 0.48, letterH = 1.12, textW = 27.0, textH = 13.0, align = 1, color = cRed, font = 4, prop = 0, bg = 0xFF000000 },
        { posX = 545.232422 + deltaX, posY = 8.710500  + deltaY, text = "LD_BEAT:chit",         letterW = 0.48, letterH = 1.12, textW = 4.0, textH = 5.0, align = 1, color = cRed, font = 4, prop = 0, bg = 0xFF000000 },
        { posX = 551.465515 + deltaX, posY = 2.488100  + deltaY, text = "LD_BEAT:chit",         letterW = 0.48, letterH = 1.12, textW = 4.030000, textH = 4.219900, align = 1, color = cRed, font = 4, prop = 0, bg = 0xFF000000 },
        { posX = 546.165527 + deltaX, posY = 4.906700  + deltaY, text = "LD_BEAT:chit",         letterW = 0.48, letterH = 1.12, textW = 3.0, textH = 4.0, align = 1, color = cRed, font = 4, prop = 0, bg = 0xFF000000 },
        { posX = 547.832214 + deltaX, posY = 1.844300  + deltaY, text = "LD_BEAT:chit",         letterW = 0.48, letterH = 1.12, textW = 3.0, textH = 3.0, align = 1, color = cRed, font = 4, prop = 0, bg = 0xFF000000 },
        { posX = 574.599915 + deltaX, posY = 22.429501 + deltaY, text = "LD_SPAC:white",         letterW = 0.48, letterH = 1.12, textW = 27.030001, textH = 5.0, align = 1, color = cRed, font = 4, prop = 0, bg = 0xFF000000 },
        { posX = 571.265625 + deltaX, posY = 21.184700 + deltaY, text = "LD_BEAT:chit",         letterW = 0.48, letterH = 1.12, textW = 6.0, textH = 7.15, align = 1, color = cRed, font = 4, prop = 0, bg = 0xFF000000 },
        { posX = 598.399109 + deltaX, posY = 21.384800 + deltaY, text = "LD_BEAT:chit",         letterW = 0.48, letterH = 1.12, textW = 6.0, textH = 7.15, align = 1, color = cRed, font = 4, prop = 0, bg = 0xFF000000 },
        { posX = 603.465820 + deltaX, posY = 21.584801 + deltaY, text = "LD_BEAT:chit",         letterW = 0.48, letterH = 1.12, textW = 5.0, textH = 6.0, align = 1, color = cRed, font = 4, prop = 0, bg = 0xFF000000 },
        { posX = 607.332703 + deltaX, posY = 24.288401 + deltaY, text = "LD_BEAT:chit",         letterW = 0.48, letterH = 1.12, textW = 3.759900, textH = 4.349800, align = 1, color = cRed, font = 4, prop = 0, bg = 0xFF000000 },
        { posX = 569.233215 + deltaX, posY = 28.181200 + deltaY, text = "particle:lamp_shad_64", letterW = 0.48, letterH = 1.12, textW = 38.0, textH = -6.0, align = 1, color = cRed, font = 4, prop = 0, bg = 0xFF000000 },
        { posX = 588.066711 + deltaX, posY = 22.040501 + deltaY, text = sName,                  letterW = 0.123000, letterH = 0.550400, textW = 1280.0, textH = 1280.0, align = 2, color = 0xFFFFFFFF, font = 1, prop = 1, bg = 0xFFFFFFFF },
        { posX = 569.233215 + deltaX, posY = 24.103701 + deltaY, text = "particle:lamp_shad_64", letterW = 0.48, letterH = 1.12, textW = 38.0, textH = 3.0, align = 1, color = cRed, font = 4, prop = 0, bg = 0xFF000000 }
    }
end

local function getOldLogoData()
    local deltaX = config.logoX - LOGO_BASE_X
    local deltaY = config.logoY - LOGO_BASE_Y

    return {
        {
            posX    = 501.0 + deltaX,
            posY    = 1.0 + deltaY,
            text    = "~r~ARIZONA_ROLE_PLAY",
            letterW = 0.33,
            letterH = 1.3,
            textW   = 640.0,
            textH   = 480.0,
            align   = 1,
            color   = 0xFFFFFFFF,
            font    = 2,
            prop    = 1,
            shadow  = 1,
            outline = 0,
            bg      = 0x95000000
        },
        {
            posX    = 540.0 + deltaX,
            posY    = 12.2 + deltaY,
            text    = "ARIZONA-RP.com",
            letterW = 0.2,
            letterH = 1.0,
            textW   = 640.0,
            textH   = 480.0,
            align   = 1,
            color   = 0xFFFFFFFF,
            font    = 2,
            prop    = 1,
            shadow  = 1,
            outline = 0,
            bg      = 0xFF000000
        }
    }
end

local function getServerNamedLogoData()
    local deltaX = config.logoX - LOGO_BASE_X
    local deltaY = config.logoY - LOGO_BASE_Y
    local sName = getDynamicServerName():gsub("%-", "_")
    local centerX = 570.0 + deltaX

    return {
        {
            posX    = centerX,
            posY    = 1.0 + deltaY,
            text    = string.format("~r~ARIZONA_%s", sName),
            letterW = 0.33,
            letterH = 1.3,
            textW   = 640.0,
            textH   = 480.0,
            align   = 2,
            color   = 0xFFFFFFFF,
            font    = 2,
            prop    = 1,
            shadow  = 1,
            outline = 0,
            bg      = 0x95000000
        },
        {
            posX    = centerX,
            posY    = 12.2 + deltaY,
            text    = "ARIZONA-RP.com",
            letterW = 0.2,
            letterH = 1.0,
            textW   = 640.0,
            textH   = 480.0,
            align   = 2,
            color   = 0xFFFFFFFF,
            font    = 2,
            prop    = 1,
            shadow  = 1,
            outline = 0,
            bg      = 0xFF000000
        }
    }
end

local function hideLogo()
    for i = 1, 25 do
        hideEmulatorTextDraw(BASE_TD_ID + i)
        if sampTextdrawIsExists(BASE_TD_ID + i) then
            sampTextdrawDelete(BASE_TD_ID + i)
        end
    end
    is_logo_shown = false
end

local function showLogo()
    hideLogo()
    hideServerLogo()

    local logoList
    if config.logoType == 1 then
        logoList = getOldLogoData()
    elseif config.logoType == 2 then
        logoList = getServerNamedLogoData()
    else
        logoList = getLogoData()
    end

    for i, td in ipairs(logoList) do
        createEmulatorTextDraw(BASE_TD_ID + i, td)
    end
    is_logo_shown = true
end

local function hideDrugTextDraw()
    if sampTextdrawIsExists(DRUG_TD_ID) then
        sampTextdrawDelete(DRUG_TD_ID)
    end
    drug_td_shown = false
    last_drug_text = ""
end

local function createDrugTextDraw(initialText)
    if sampTextdrawIsExists(DRUG_TD_ID) then
        sampTextdrawDelete(DRUG_TD_ID)
    end
    sampTextdrawCreate(DRUG_TD_ID, initialText or "Use!", config.drugX, config.drugY)
    sampTextdrawSetLetterSizeAndColor(DRUG_TD_ID, 0.300000, 1.000000, 0xFFFFFFFF)
    sampTextdrawSetAlign(DRUG_TD_ID, 1)
    sampTextdrawSetOutlineColor(DRUG_TD_ID, 1, 0xFF000000)
    sampTextdrawSetShadow(DRUG_TD_ID, 0, 0xFF000000)
    sampTextdrawSetProportional(DRUG_TD_ID, 1)
    sampTextdrawSetStyle(DRUG_TD_ID, 1)
    drug_td_shown = true
    last_drug_text = initialText or "Use!"
end

local function updateDrugTextDraw(now_tick)
    if not config.showDrugCd then
        if drug_td_shown or sampTextdrawIsExists(DRUG_TD_ID) then
            hideDrugTextDraw()
        end
        return
    end

    local cd_drug = math.max(0, (last_drug_time + 2.0) - now_tick)
    local cd_hit  = math.max(0, (last_hit_time + 6.0) - now_tick)
    local max_cd  = math.max(cd_drug, cd_hit)

    local str = "Use!"
    if max_cd > 0.05 then
        str = tostring(math.ceil(max_cd))
    end

    if not sampTextdrawIsExists(DRUG_TD_ID) then
        createDrugTextDraw(str)
    elseif str ~= last_drug_text then
        sampTextdrawSetString(DRUG_TD_ID, str)
        last_drug_text = str
    end
end

local function hideTimeTextdraw()
    if sampTextdrawIsExists(TD_TIME_ID) then
        sampTextdrawDelete(TD_TIME_ID)
    end
    is_time_td_active = false
    time_hide_tick = 0
end

local function showTimeTextdraw(customTimestamp)
    local now = os.clock()
    if now - last_time_show_tick < 1.5 and is_time_td_active then
        return
    end
    last_time_show_tick = now

    hideTimeTextdraw()

    local ts = customTimestamp or last_server_ts or os.time()
    local t = os.date("*t", ts)

    local _, myId = sampGetPlayerIdByCharHandle(PLAYER_PED)
    local nick = sampGetPlayerNickname(myId)
    local sName = getFormattedServerName()

    local dateStr = string.format("%02d.%02d.%04d", t.day, t.month, t.year)
    local timeStr = string.format("%02d:%02d:%02d", t.hour, t.min, t.sec)

    local rawText = string.format("~w~%s ~n~~y~%s ~n~~y~%s ~n~~g~%s", nick, dateStr, timeStr, sName)

    sampTextdrawCreate(TD_TIME_ID, rawText, TD_TIME_CONFIG.x, TD_TIME_CONFIG.y)
    sampTextdrawSetLetterSizeAndColor(TD_TIME_ID, TD_TIME_CONFIG.letter_w, TD_TIME_CONFIG.letter_h, 0xFFFFFFFF)
    sampTextdrawSetStyle(TD_TIME_ID, TD_TIME_CONFIG.font)
    sampTextdrawSetAlign(TD_TIME_ID, TD_TIME_CONFIG.align)
    sampTextdrawSetOutlineColor(TD_TIME_ID, TD_TIME_CONFIG.outline, 0xFF000000)
    sampTextdrawSetShadow(TD_TIME_ID, TD_TIME_CONFIG.shadow, 0xFF000000)
    sampTextdrawSetProportional(TD_TIME_ID, TD_TIME_CONFIG.proportional)

    is_time_td_active = true
    time_hide_tick = now + TD_TIME_CONFIG.display_time
end

local new = imgui.new
local window = new.bool(false)

buf = {
    showLogo        = new.bool(config.showLogo),
    logoType        = new.int(config.logoType or 0),
    showCapt        = new.bool(config.showCapt),
    showDrugCd      = new.bool(config.showDrugCd),
    replaceDrugChat = new.bool(config.replaceDrugChat),
    recolorFactions = new.bool(config.recolorFactions or true),
    showGangZones   = new.bool(config.showGangZones or true),
    showEvoTime     = new.bool(config.showEvoTime or true),
    logoX           = new.float(config.logoX),
    logoY           = new.float(config.logoY),
    captX           = new.float(config.captX),
    captY           = new.float(config.captY),
    drugX           = new.float(config.drugX),
    drugY           = new.float(config.drugY),
    drugAmount      = new.int(config.drugAmount or 0),
    deagleAmount    = new.int(config.deagleAmount or 0),
    m4Amount        = new.int(config.m4Amount or 0),
    rifleAmount     = new.int(config.rifleAmount or 0),
    shotgunAmount   = new.int(config.shotgunAmount or 0),
    materialsAmount = new.int(config.materialsAmount or 0),
    testMode        = new.bool(false),
    testModeType    = new.int(0),
}

local function syncFromConfig()
    buf.showLogo[0]        = config.showLogo
    buf.logoType[0]        = config.logoType or 0
    buf.showCapt[0]        = config.showCapt
    buf.showDrugCd[0]      = config.showDrugCd
    buf.replaceDrugChat[0] = config.replaceDrugChat
    buf.recolorFactions[0] = (config.recolorFactions ~= false)
    buf.showGangZones[0]   = (config.showGangZones ~= false)
    buf.showEvoTime[0]     = (config.showEvoTime ~= false)
    buf.logoX[0]           = config.logoX
    buf.logoY[0]           = config.logoY
    buf.captX[0]           = config.captX
    buf.captY[0]           = config.captY
    buf.drugX[0]           = config.drugX
    buf.drugY[0]           = config.drugY
    buf.drugAmount[0]      = config.drugAmount or 0
    buf.deagleAmount[0]    = config.deagleAmount or 0
    buf.m4Amount[0]        = config.m4Amount or 0
    buf.rifleAmount[0]     = config.rifleAmount or 0
    buf.shotgunAmount[0]   = config.shotgunAmount or 0
    buf.materialsAmount[0] = config.materialsAmount or 0
    buf.testMode[0]        = is_test_mode
    buf.testModeType[0]    = test_mode_type
end

local function syncToConfig()
    config.showLogo        = buf.showLogo[0]
    config.logoType        = tonumber(buf.logoType[0]) or 0
    config.showCapt        = buf.showCapt[0]
    config.showDrugCd      = buf.showDrugCd[0]
    config.replaceDrugChat = buf.replaceDrugChat[0]
    config.recolorFactions = buf.recolorFactions[0]
    config.showGangZones   = buf.showGangZones[0]
    config.showEvoTime     = buf.showEvoTime[0]
    config.logoX           = tonumber(buf.logoX[0])
    config.logoY           = tonumber(buf.logoY[0])
    config.captX           = tonumber(buf.captX[0])
    config.captY           = tonumber(buf.captY[0])
    config.drugX           = tonumber(buf.drugX[0])
    config.drugY           = tonumber(buf.drugY[0])
    config.drugAmount      = tonumber(buf.drugAmount[0])
    config.deagleAmount    = tonumber(buf.deagleAmount[0])
    config.m4Amount        = tonumber(buf.m4Amount[0])
    config.rifleAmount     = tonumber(buf.rifleAmount[0])
    config.shotgunAmount   = tonumber(buf.shotgunAmount[0])
    config.materialsAmount = tonumber(buf.materialsAmount[0])
end

local function startPositioningLogo()
    if not config.showLogo then
        config.showLogo = true
        buf.showLogo[0] = true
    end
    showLogo()
    isPositioningLogo = true
    isPositioningCapt = false
    isPositioningDrug = false
    window[0] = false
    sampSetCursorMode(2)
    sendInfoMessage("Режим перемещения {88AA62}логотипа{A9C4E4}. Наведите курсор и нажмите {88AA62}ЛКМ{A9C4E4} для сохранения.")
end

local function startPositioningCapt()
    is_test_mode = true
    buf.testMode[0] = true
    war_active = true
    applyTestWarData(buf.testModeType[0])
    config.showCapt = true
    buf.showCapt[0] = true
    createWarTextdraws()
    isPositioningCapt = true
    isPositioningLogo = false
    isPositioningDrug = false
    window[0] = false
    sampSetCursorMode(2)
    sendInfoMessage("Режим перемещения {88AA62}таблички{A9C4E4}. Наведите курсор и нажмите {88AA62}ЛКМ{A9C4E4} для сохранения.")
end

local function startPositioningDrug()
    if not config.showDrugCd then
        config.showDrugCd = true
        buf.showDrugCd[0] = true
    end
    if not sampTextdrawIsExists(DRUG_TD_ID) then
        createDrugTextDraw("Use!")
    end
    isPositioningDrug = true
    isPositioningLogo = false
    isPositioningCapt = false
    window[0] = false
    sampSetCursorMode(2)
    sendInfoMessage("Режим перемещения {88AA62}Use! / КД{A9C4E4}. Наведите курсор и нажмите {88AA62}ЛКМ{A9C4E4} для сохранения.")
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

imgui.OnInitialize(function()
    imgui.GetIO().IniFilename = nil
    local fontPath = getFolderPath(0x14) .. '\\trebuc.ttf'
    if not doesFileExist(fontPath) then
        fontPath = getFolderPath(0x14) .. '\\arial.ttf'
    end
    local glyphRanges = imgui.GetIO().Fonts:GetGlyphRangesCyrillic()
    imgui.GetIO().Fonts:AddFontFromFileTTF(fontPath, 14.0, nil, glyphRanges)
end)

imgui.OnFrame(
    function() return window[0] end,
    function(self)
        for _, c in ipairs(grayStyles) do
            imgui.PushStyleColor(c[1], imgui.ImVec4(c[2], c[3], c[4], c[5]))
        end

        imgui.SetNextWindowSizeConstraints(imgui.ImVec2(480, 0), imgui.ImVec2(480, 9999))
        imgui.Begin(u8'Evolve HUD - Меню настроек', window, imgui.WindowFlags.NoResize + imgui.WindowFlags.AlwaysAutoResize)

        if imgui.CollapsingHeader(u8'Логотип сервера', imgui.TreeNodeFlags.DefaultOpen) then
            if imgui.Checkbox(u8'Включить логотип', buf.showLogo) then
                config.showLogo = buf.showLogo[0]
                saveConfig()
                if config.showLogo then
                    showLogo()
                else
                    hideLogo()
                    restoreServerLogo()
                end
            end

            imgui.Spacing()
            imgui.Text(u8'Вариант логотипа:')
            local isEvo = new.bool(buf.logoType[0] == 0)
            local isOld = new.bool(buf.logoType[0] == 1)
            local isNamed = new.bool(buf.logoType[0] == 2)

            if imgui.Checkbox(u8'Evolve HUD', isEvo) then
                buf.logoType[0] = 0
                config.logoType = 0
                saveConfig()
                if config.showLogo then showLogo() end
            end
            imgui.SameLine()
            if imgui.Checkbox(u8'Classic (ARIZONA ROLE PLAY)', isOld) then
                buf.logoType[0] = 1
                config.logoType = 1
                saveConfig()
                if config.showLogo then showLogo() end
            end
            imgui.SameLine()
            local currentSrv = getDynamicServerName()
            if imgui.Checkbox(u8'ARIZONA ' .. currentSrv, isNamed) then
                buf.logoType[0] = 2
                config.logoType = 2
                saveConfig()
                if config.showLogo then showLogo() end
            end

            imgui.Spacing()
            if imgui.Button(u8'Изменить позицию логотипа', imgui.ImVec2(-1, 28)) then
                startPositioningLogo()
            end

            if imgui.SliderFloat(u8'Позиция X##Logo', buf.logoX, 0.0, 640.0, '%.1f') then
                config.logoX = buf.logoX[0]
                if config.showLogo then showLogo() end
            end
            if imgui.SliderFloat(u8'Позиция Y##Logo', buf.logoY, 0.0, 480.0, '%.1f') then
                config.logoY = buf.logoY[0]
                if config.showLogo then showLogo() end
            end

            if imgui.Button(u8'Сбросить позицию логотипа') then
                buf.logoX[0] = LOGO_BASE_X
                buf.logoY[0] = LOGO_BASE_Y
                config.logoX = LOGO_BASE_X
                config.logoY = LOGO_BASE_Y
                saveConfig()
                if config.showLogo then showLogo() end
            end
        end

        if imgui.CollapsingHeader(u8'Гангзоны', imgui.TreeNodeFlags.DefaultOpen) then
            if imgui.Checkbox(u8'Включить гангзоны Evolve (требуется перезаход)', buf.showGangZones) then
                config.showGangZones = buf.showGangZones[0]
                saveConfig()
            end
        end

        if imgui.CollapsingHeader(u8'Инвентарь, Оружие и Чат', imgui.TreeNodeFlags.DefaultOpen) then
            if imgui.Checkbox(u8'Включить индикатор Use! / КД', buf.showDrugCd) then
                config.showDrugCd = buf.showDrugCd[0]
                saveConfig()
                if not config.showDrugCd then
                    hideDrugTextDraw()
                end
            end

            imgui.SameLine()
            if imgui.Checkbox(u8'Заменять строки в чате (нарко/оружие/склад)', buf.replaceDrugChat) then
                config.replaceDrugChat = buf.replaceDrugChat[0]
                saveConfig()
            end

            if imgui.Checkbox(u8'Перекрашивать клисты/радар/килл-лист под палитру', buf.recolorFactions) then
                config.recolorFactions = buf.recolorFactions[0]
                saveConfig()
            end

            if imgui.Checkbox(u8'Время /time в стиле Evolve (вместо CEF)', buf.showEvoTime) then
                config.showEvoTime = buf.showEvoTime[0]
                saveConfig()
                if not config.showEvoTime then
                    hideTimeTextdraw()
                end
            end

            imgui.Spacing()
            if imgui.Button(u8'Изменить позицию Use!', imgui.ImVec2(-1, 28)) then
                startPositioningDrug()
            end

            if imgui.SliderFloat(u8'Позиция X##Drug', buf.drugX, 0.0, 640.0, '%.1f') then
                config.drugX = buf.drugX[0]
                if sampTextdrawIsExists(DRUG_TD_ID) then
                    sampTextdrawSetPos(DRUG_TD_ID, config.drugX, config.drugY)
                end
            end
            if imgui.SliderFloat(u8'Позиция Y##Drug', buf.drugY, 0.0, 480.0, '%.1f') then
                config.drugY = buf.drugY[0]
                if sampTextdrawIsExists(DRUG_TD_ID) then
                    sampTextdrawSetPos(DRUG_TD_ID, config.drugX, config.drugY)
                end
            end

            imgui.Separator()
            imgui.Text(u8'Количество предметов (синхронизируется через /stats):')
            if imgui.InputInt(u8'Укроп', buf.drugAmount) then
                config.drugAmount = math.max(0, buf.drugAmount[0])
                saveConfig()
            end
            if imgui.InputInt(u8'Desert Eagle', buf.deagleAmount) then
                config.deagleAmount = math.max(0, buf.deagleAmount[0])
                saveConfig()
            end
            if imgui.InputInt(u8'Автомат M4', buf.m4Amount) then
                config.m4Amount = math.max(0, buf.m4Amount[0])
                saveConfig()
            end
            if imgui.InputInt(u8'Дробовик', buf.shotgunAmount) then
                config.shotgunAmount = math.max(0, buf.shotgunAmount[0])
                saveConfig()
            end
            if imgui.InputInt(u8'Винтовка', buf.rifleAmount) then
                config.rifleAmount = math.max(0, buf.rifleAmount[0])
                saveConfig()
            end
            if imgui.InputInt(u8'Материалы', buf.materialsAmount) then
                config.materialsAmount = math.max(0, buf.materialsAmount[0])
                saveConfig()
            end

            if imgui.Button(u8'Синхронизировать весь инвентарь через /stats', imgui.ImVec2(-1, 28)) then
                startManualStatsScan()
            end
        end

        if imgui.CollapsingHeader(u8'Табличка капта / Завода', imgui.TreeNodeFlags.DefaultOpen) then
            if imgui.Checkbox(u8'Включить кастомный HUD капта', buf.showCapt) then
                config.showCapt = buf.showCapt[0]
                saveConfig()
                if not config.showCapt then
                    destroyWarTextdraws()
                elseif war_active then
                    createWarTextdraws()
                end
            end

            imgui.Spacing()
            if imgui.Button(u8'Изменить позицию таблички капта', imgui.ImVec2(-1, 28)) then
                startPositioningCapt()
            end

            if imgui.SliderFloat(u8'Позиция X##Capt', buf.captX, 0.0, 640.0, '%.1f') then
                config.captX = buf.captX[0]
                if war_active and config.showCapt then createWarTextdraws() end
            end
            if imgui.SliderFloat(u8'Позиция Y##Capt', buf.captY, 0.0, 480.0, '%.1f') then
                config.captY = buf.captY[0]
                if war_active and config.showCapt then createWarTextdraws() end
            end

            imgui.Separator()
            if imgui.Checkbox(u8'Режим предпросмотра (Тест)', buf.testMode) then
                is_test_mode = buf.testMode[0]
                war_active = is_test_mode
                if war_active then
                    applyTestWarData(buf.testModeType[0])
                    createWarTextdraws()
                else
                    destroyWarTextdraws()
                    warData = {}
                    total_war_damage = 0
                    current_kills = 0
                end
            end

            if buf.testMode[0] then
                imgui.Text(u8'Тип тестовой таблички:')
                
                local isGhetto = new.bool(buf.testModeType[0] == 0)
                local isZavod  = new.bool(buf.testModeType[0] == 1)
                
                if imgui.Checkbox(u8'Гетто капт', isGhetto) then
                    buf.testModeType[0] = 0
                    test_mode_type = 0
                    applyTestWarData(0)
                    createWarTextdraws()
                end
                imgui.SameLine()
                if imgui.Checkbox(u8'Битва за завод', isZavod) then
                    buf.testModeType[0] = 1
                    test_mode_type = 1
                    applyTestWarData(1)
                    createWarTextdraws()
                end
            end
        end

        imgui.Separator()

        if imgui.Button(u8'Сохранить настройки', imgui.ImVec2(220, 28)) then
            syncToConfig()
            saveConfig()
            sendInfoMessage("Настройки худа успешно {88AA62}сохранены!")
        end
        imgui.SameLine()
        if imgui.Button(u8'Сбросить всё по умолчанию', imgui.ImVec2(220, 28)) then
            config = deepcopy(DEFAULT_CONFIG)
            is_test_mode = false
            syncFromConfig()
            saveConfig()
            if config.showLogo then
                showLogo()
            else
                hideLogo()
                restoreServerLogo()
            end
            if war_active and config.showCapt then createWarTextdraws() else destroyWarTextdraws() end
            sendErrorMessage("Настройки сброшены {E05454}на стандартные.")
        end

        imgui.End()

        for _ = 1, #grayStyles do imgui.PopStyleColor() end
    end
)

function onWindowMessage(msg, wparam, lparam)
    if isPositioningLogo or isPositioningCapt or isPositioningDrug then
        if msg == wm.WM_LBUTTONDOWN and wparam == vkeys.VK_LBUTTON then
            saveConfig()
            sampSetCursorMode(0)
            if isPositioningLogo then
                isPositioningLogo = false
                sendInfoMessage("Позиция логотипа сохранена: {FFFFFF}X: " .. string.format("%.1f", config.logoX) .. " Y: " .. string.format("%.1f", config.logoY))
            elseif isPositioningCapt then
                isPositioningCapt = false
                sendInfoMessage("Позиция капта сохранена: {FFFFFF}X: " .. string.format("%.1f", config.captX) .. " Y: " .. string.format("%.1f", config.captY))
            elseif isPositioningDrug then
                isPositioningDrug = false
                sendInfoMessage("Позиция Use! сохранена: {FFFFFF}X: " .. string.format("%.1f", config.drugX) .. " Y: " .. string.format("%.1f", config.drugY))
            end
        elseif msg == wm.WM_KEYDOWN and wparam == vkeys.VK_ESCAPE then
            isPositioningLogo = false
            isPositioningCapt = false
            isPositioningDrug = false
            sampSetCursorMode(0)
            loadConfig()
            syncFromConfig()
            if config.showLogo then
                showLogo()
            else
                hideLogo()
                restoreServerLogo()
            end
            if war_active and config.showCapt then createWarTextdraws() else destroyWarTextdraws() end
            sendErrorMessage("Редактирование позиции отменено.")
        end
    end

    if window[0] and wparam == vkeys.VK_ESCAPE and msg == wm.WM_KEYUP then
        window[0] = false
    end
end

function sampev.onSendSpawn()
    triggerBackgroundSync("spawn")
end

function sampev.onSendDeathNotification(reason, killerId)
    is_player_alive = false
end

function sampev.onSendCommand(command)
    local cmd = command:lower()
    if cmd:match("^/usedrugs") or cmd:match("^/drugs") or cmd:match("^/healme") then
        local amt = cmd:match("%s+(%d+)")
        last_used_amount = tonumber(amt) or 10
        last_drug_time = os.clock()
    end
end

function sampev.onSendTakeDamage(issuerId, damage, weapon, bodypart)
    last_hit_time = os.clock()
end

function sampev.onPlayerStreamIn(playerId, team, model, position, rotation, color, fightingStyle)
    local fName = getFactionByColor(color)
    if fName and fName ~= "" then
        player_faction_cache[playerId] = normalizeGang(fName)
    end
    
    if not config.recolorFactions then return end
    if fName and CUSTOM_FACTIONS[fName] then
        return { playerId, team, model, position, rotation, CUSTOM_FACTIONS[fName].rgba, fightingStyle }
    end
end

function sampev.onPlayerStreamOut(playerId)
    player_faction_cache[playerId] = nil
end

function sampev.onPlayerQuit(playerId, reason)
    player_faction_cache[playerId] = nil
end

function sampev.onSetPlayerColor(playerId, color)
    local fName = getFactionByColor(color)
    if fName and fName ~= "" then
        player_faction_cache[playerId] = normalizeGang(fName)
    end
    
    if not config.recolorFactions then return end
    if fName and CUSTOM_FACTIONS[fName] then
        return { playerId, CUSTOM_FACTIONS[fName].rgba }
    end
end

function sampev.onServerMessage(color, text)
    if not config.replaceDrugChat then return end

    local clean = text:gsub('{.-}', '')
    local low = cp1251_lower(clean)

    local isClosedWarning = low:find("склад.*закрыт") or low:find("закрытом складе")
    if not isClosedWarning then
        local isObshchakOpen = (low:find("общак") or low:find("склад")) and low:find("открыл")
        local isObshchakClose = (low:find("общак") or low:find("склад")) and low:find("закрыл")

        if isObshchakOpen then
            local sender = clean:match("%[F%]%s*(.-)%s*%[%d+%]")
                        or clean:match("%[F%]%s*([A-Za-z0-9_]+)")
                        or clean:match("([A-Za-z0-9_]+)%[%d+%]")
            if not sender or sender == "" then
                sender = low:find("лидер") and "Лидер" or "Член банды"
            end
            sampAddChatMessage(string.format('{2A9170}%s Открыл доступ к складу с материалами!', sender), -1)
            return false
        end

        if isObshchakClose then
            if low:find("лидер вашей организации") and clean:find("%[Информация%]") then
                return false
            end
            local sender = clean:match("%[F%]%s*(.-)%s*%[%d+%]")
                        or clean:match("%[F%]%s*([A-Za-z0-9_]+)")
                        or clean:match("([A-Za-z0-9_]+)%[%d+%]")
            if not sender or sender == "" then
                sender = low:find("лидер") and "Лидер" or "Член банды"
            end
            sampAddChatMessage(string.format('{2A9170}%s {880000}Закрыл{2A9170} доступ к складу с материалами!', sender), -1)
            return false
        end
    end

    if low:find("выиграли сражение за территорию") then
        local reason = clean:match("выиграли сражение за территорию%s*(.*)") or ""
        reason = reason:gsub("^[!%s]+", ""):gsub("[!%s]+$", "")
        local newMsg = "{009F00}Вы завоевали под свой контроль новую территорию"
        if reason ~= "" then newMsg = newMsg .. " " .. reason end
        sampAddChatMessage(newMsg, -1)
        return false
    end

    if low:find("проиграли сражение за территорию") then
        local reason = clean:match("проиграли сражение за территорию%s*(.*)") or ""
        reason = reason:gsub("^[!%s]+", ""):gsub("[!%s]+$", "")
        
        local newMsg = "{C17C8D}Вы потеряли контроль одной из своих территорий"
        if reason ~= "" then 
            newMsg = newMsg .. " " .. reason 
        else
            newMsg = newMsg .. " по киллам"
        end
        
        sampAddChatMessage(newMsg, -1)
        return false
    end

    if clean:find("^%[F%]") then
        local newText = clean:gsub("^%[F%]%s*", "")
        return { 0x00FFFFFF, newText }
    end

    local isWeaponUse = low:find("успешное использование") 
                     or low:find("успешно использовали") 
                     or low:find("успешно использован")

    if isWeaponUse then
        local now = os.clock()
        if now - last_weapon_msg_time > 0.6 then
            last_weapon_msg_time = now
            lua_thread.create(function()
                wait(50)
                local count = consumeWeaponCount()
                sampAddChatMessage(string.format('{C2A2DA}Осталось материалов: %d', count), -1)
            end)
        end
        return false
    end

    if low:find("дозу укропа") or low:find("употребил") then
        local nick, id = clean:match("([A-Za-z0-9_]+)%[(%d+)%]")
        if not nick then nick = clean:match("([A-Za-z0-9_]+)") end

        if nick then
            local _, myId = sampGetPlayerIdByCharHandle(PLAYER_PED)
            local isMe = (nick == player_nickname) or (id and tonumber(id) == myId)

            if isMe then
                last_drug_time = os.clock()
                config.drugAmount = math.max(0, (config.drugAmount or 0) - last_used_amount)
                saveConfig()
                if buf and buf.drugAmount then buf.drugAmount[0] = config.drugAmount end
                local cur_hp = getCharHealth(PLAYER_PED)

                sampAddChatMessage(string.format('{C2A2DA}%s употребил субстанцию растительного происхождения', nick), -1)
                sampAddChatMessage(string.format('{AFAFAF}(( Здоровье пополнено до: %d ))', cur_hp), -1)
                sampAddChatMessage(string.format('{FFFFFF}(( Остаток: %d грамм зелёной растительности ))', config.drugAmount), -1)
            else
                sampAddChatMessage(string.format('{C2A2DA}%s употребил субстанцию растительного происхождения', nick), -1)
            end
            return false
        end
    end
end

function sampev.onShowDialog(dialogId, style, title, button1, button2, text)
    if not is_silent_stats_scan then return end

    local cleanTitle = title:gsub('{.-}', '')
    local okT, u8Title = pcall(u8, cleanTitle)
    local titleText = (okT and u8Title) and u8Title or cleanTitle

    local cleanText = text:gsub('{.-}', '')
    local okB, u8Text = pcall(u8, cleanText)
    local bodyText = (okB and u8Text) and u8Text or cleanText

    if dialogId == 235 or (titleText:find("Статистика") and dialogId ~= 25491) then
        lua_thread.create(function()
            wait(200)
            sampSendDialogResponse(dialogId, 1, 0, "")
        end)
        return false
    end

    local isInventoryDialog = (dialogId == 25491) 
                          or bodyText:find("Инвентарь:") 
                          or bodyText:find("%[слот%]") 
                          or cleanText:find("Р?РЅРІРµРЅС‚Р°СЂСЊ")

    if isInventoryDialog then
        stats_pages_scanned = stats_pages_scanned + 1
        local lines = {}
        for l in text:gmatch("[^\r\n]+") do table.insert(lines, l) end

        local start_line = (style == 5) and 2 or 1
        local next_page_idx = nil

        for i = start_line, #lines do
            local item_index = i - start_line
            local line = lines[i]

            local slot, itemType, count = parseInventoryLine(line)
            if slot and itemType and count > 0 then
                scanned_inventory_slots[slot] = { type = itemType, count = count }
            end

            if isNextPageLine(line) then
                next_page_idx = item_index
            end
        end

        if next_page_idx ~= nil and stats_pages_scanned < 5 then
            lua_thread.create(function()
                wait(250)
                sampSendDialogResponse(dialogId, 1, next_page_idx, "")
            end)
            return false
        else
            is_silent_stats_scan = false
            
            local totals = { ukrop = 0, deagle = 0, m4 = 0, rifle = 0, shotgun = 0, materials = 0 }
            for _, item in pairs(scanned_inventory_slots) do
                if totals[item.type] ~= nil then
                    totals[item.type] = totals[item.type] + item.count
                end
            end

            config.drugAmount      = totals.ukrop
            config.deagleAmount    = totals.deagle
            config.m4Amount        = totals.m4
            config.rifleAmount     = totals.rifle
            config.shotgunAmount   = totals.shotgun
            config.materialsAmount = totals.materials
            saveConfig()
            syncFromConfig()

            lua_thread.create(function()
                wait(200)
                sampSendDialogResponse(dialogId, 0, 0, "")
            end)

            if manual_stats_scan then
                sendInfoMessage(string.format("Инвентарь сохранён: {FFFFFF}Укроп: %d | Deagle: %d | M4: %d | Шот: %d | Рифла: %d | Маты: %d",
                    config.drugAmount, config.deagleAmount, config.m4Amount, config.shotgunAmount, config.rifleAmount, config.materialsAmount))
            end
            manual_stats_scan = false
            return false
        end
    end
end

function onReceiveRpc(id, bs)
    if not config.showGangZones then return end
    
    if id == 108 then
        local zoneId = raknetBitStreamReadInt16(bs)
        local minX = raknetBitStreamReadFloat(bs)
        local minY = raknetBitStreamReadFloat(bs)
        local maxX = raknetBitStreamReadFloat(bs)
        local maxY = raknetBitStreamReadFloat(bs)
        local color = raknetBitStreamReadInt32(bs)

        local newColor = config.recolorFactions and convertGangZoneColor(color) or color
        if newColor == nil then
            return false
        end

        local coords = getArzGhettoCoords(zoneId)
        if coords then
            raknetBitStreamSetWriteOffset(bs, 0)
            raknetBitStreamWriteInt16(bs, zoneId)
            raknetBitStreamWriteFloat(bs, coords.minX)
            raknetBitStreamWriteFloat(bs, coords.minY)
            raknetBitStreamWriteFloat(bs, coords.maxX)
            raknetBitStreamWriteFloat(bs, coords.maxY)
            raknetBitStreamWriteInt32(bs, newColor)
            raknetBitStreamSetReadOffset(bs, 0)
        end
    end
end

function onReceivePacket(id, bs)
    if id == 220 then
        raknetBitStreamIgnoreBits(bs, 8)
        if raknetBitStreamReadInt8(bs) == 17 then
            raknetBitStreamIgnoreBits(bs, 32)
            local length = raknetBitStreamReadInt16(bs)
            local encoded = raknetBitStreamReadInt8(bs)
            local str = (encoded ~= 0) and raknetBitStreamDecodeString(bs, length + encoded) or raknetBitStreamReadString(bs, length)

            if not str or str == "" then return end

            if config.showEvoTime then
                if str:find("setTimeWidgetHide") then
                    return false
                end

                if str:find("setTimeWidgetInfo") then
                    local ts = str:match('"timestamp":(%d+)') or str:match('timestamp%s*:%s*(%d+)')
                    if ts then
                        last_server_ts = tonumber(ts)
                    end
                    showTimeTextdraw(last_server_ts)
                    return false
                end
            end

            if str:find("event.damageInformer.ignoredDamageInfo") then
                if str:find('"imageId":770') or str:find("790770") then
                    last_taken_weapon = "Desert Eagle"
                    last_taken_weapon_time = os.clock()
                elseif str:find('"imageId":775') or str:find("790775") then
                    last_taken_weapon = "Автомат M4"
                    last_taken_weapon_time = os.clock()
                elseif str:find('"imageId":776') or str:find("790776") then
                    last_taken_weapon = "Винтовка"
                    last_taken_weapon_time = os.clock()
                elseif str:find('"imageId":772') or str:find("790772") then
                    last_taken_weapon = "Дробовик"
                    last_taken_weapon_time = os.clock()
                end
            end

            if str:find("event.hud.setWarStatsVisibility") then
                local visibility = str:match("setWarStatsVisibility'[%s,]*[`'\"]%[?([%a%d]+)")
                if not visibility then
                    visibility = str:match("setWarStatsVisibility[%s,`'\"]*%[?([%a%d]+)")
                end
                
                if visibility == "false" or visibility == "0" then
                    if not is_test_mode then
                        war_pending_hide = os.clock() + 1.5
                    end
                elseif visibility == "true" or visibility == "1" then
                    war_pending_hide = 0
                end

                if config.showCapt then
                    return false
                end
            elseif str:find("event.warStats.setStats") then
                local json_string = str:match("setStats'[%s,]*[`'\"](%[.+%])[`'\"]")
                if not json_string then
                    json_string = str:match("setStats'[%s,]*[`'\"](.-)[`'\"]%)%s*;?")
                end
                if not json_string then
                    json_string = str:match("setStats'[%s,]*`([^`]+)`")
                end
                
                if json_string then
                    local s, data = pcall(cjson.decode, json_string)
                    if s and data and data[1] then
                        local info = data[1]
                        local newTime = tonumber(info.time) or 0
                        local newEvent = info.name or "GHETTO"
                        local newG1 = info.groups and info.groups[1] and info.groups[1].name or ""
                        local newG2 = info.groups and info.groups[2] and info.groups[2].name or ""

                        if newTime <= 0 and newG1 == "" and newG2 == "" then
                            if war_active and not is_test_mode then
                                destroyWarTextdraws()
                                war_active = false
                                war_pending_hide = 0
                            end
                            if config.showCapt then return false end
                            return
                        end

                        war_pending_hide = 0

                        local isNewWar = false
                        if warData.eventName and warData.eventName ~= newEvent then isNewWar = true end
                        if (warData.gang1 and warData.gang1.name and warData.gang1.name ~= newG1) or
                           (warData.gang2 and warData.gang2.name and warData.gang2.name ~= newG2) then 
                            isNewWar = true 
                        end
                        if (warData.time or 0) < 60 and newTime > 600 then 
                            isNewWar = true 
                        end

                        if isNewWar then
                            total_war_damage = 0
                            current_kills = 0
                            war_player_kills = {}
                            war_player_faction = {}
                        end

                        war_active = true
                        last_war_packet_time = os.clock()

                        warData.time = newTime
                        warData.eventName = newEvent
                        
                        for i = 1, 2 do
                            local g = info.groups and info.groups[i]
                            if not warData['gang'..i] then warData['gang'..i] = {} end
                            if g then
                                warData['gang'..i].name = g.name or "Unknown"
                                warData['gang'..i].kills = g.kills or 0
                                warData['gang'..i].textColor = g.textColor
                                warData['gang'..i].color = parseHexColor(g.textColor) or getGangColor(g.name)
                            end
                        end

                        if not sampTextdrawIsExists(td_id.TIME) and config.showCapt then
                            createWarTextdraws()
                        end

                        recalculateTopPlayers()
                        updateWarTextdraws()
                    end
                end

                if config.showCapt then
                    return false
                end
            elseif str:find("event.warStats.") then
                if config.showCapt then
                    return false
                end
            end
        end
    end
end

function sampev.onShowTextDraw(id, data)
    if isScriptTextdraw(id) then return end
    local text = data.text or ""
    local x = data.position and data.position.x or 0
    local y = data.position and data.position.y or 0

    if config.showCapt and isCaptServerTD(id, x, y, text) then
        return false
    end

    if isServerLogoTD(id, x, y, text) then
        if x > -500 and y > -500 then
            saved_server_logo_pos[id] = { x = x, y = y }
        end
        if config.showLogo then
            data.position.x = -1000.0
            data.position.y = -1000.0
            return { id, data }
        else
            return { id, data }
        end
    end
end

function sampev.onShowPlayerTextDraw(id, data)
    local fullId = id + 2048
    if isScriptTextdraw(fullId) then return end
    local text = data.text or ""
    local x = data.position and data.position.x or 0
    local y = data.position and data.position.y or 0

    if config.showCapt and isCaptServerTD(fullId, x, y, text) then
        return false
    end

    if isServerLogoTD(fullId, x, y, text) then
        if x > -500 and y > -500 then
            saved_server_logo_pos[fullId] = { x = x, y = y }
        end
        if config.showLogo then
            data.position.x = -1000.0
            data.position.y = -1000.0
            return { id, data }
        else
            return { id, data }
        end
    end
end

function sampev.onSendGiveDamage(playerID, damage, weaponID, bodypart)
    if isEnemy(playerID) then
        total_war_damage = total_war_damage + damage
        if sampTextdrawIsExists(td_id.DAMAGESROCE) then
            sampTextdrawSetString(td_id.DAMAGESROCE, string.format("%.0f", total_war_damage))
        end
    end
end

function sampev.onPlayerDeathNotification(killerId, killedId, reason)
    if not war_active then return end

    local _, myId = sampGetPlayerIdByCharHandle(PLAYER_PED)
    if killerId == myId and isEnemy(killedId) then
        current_kills = current_kills + 1
        if sampTextdrawIsExists(td_id.KILLSSCORE) then
            sampTextdrawSetString(td_id.KILLSSCORE, tostring(current_kills))
        end
    end

    if isValidPlayer(killerId) then
        local kNick = sampGetPlayerNickname(killerId)
        local f = getPlayerFactionCached(killerId)
        if f and f ~= "" then
            war_player_faction[kNick] = f
        end
        war_player_kills[kNick] = (war_player_kills[kNick] or 0) + 1
    end

    if isValidPlayer(killedId) then
        local vicNick = sampGetPlayerNickname(killedId)
        local vf = getPlayerFactionCached(killedId)
        if vf and vf ~= "" then
            war_player_faction[vicNick] = vf
        end
    end

    recalculateTopPlayers()
    updateWarTextdraws()
end

function sampev.onGangZoneSetColor(zoneId, color)
    if not config.showGangZones then return end
    if not config.recolorFactions then return end
    local newColor = convertGangZoneColor(color)
    if newColor == nil then
        return false
    end
    if zoneId >= 0 and zoneId <= 129 then
        return { zoneId, newColor }
    end
end

function sampev.onGangZoneFlash(zoneId, color)
    if not config.showGangZones then return end
    if not config.recolorFactions then return end
    local EVOLVE_RED_FLASH = 0xB40000FF
    if zoneId >= 0 and zoneId <= 129 then
        return { zoneId, EVOLVE_RED_FLASH }
    end
end

function main()
    if not isSampLoaded() then return end
    while not isSampAvailable() do wait(100) end

    loadConfig()
    syncFromConfig()

    local _, player_id = sampGetPlayerIdByCharHandle(PLAYER_PED)
    player_nickname = sampGetPlayerNickname(player_id)
    last_hp = getCharHealth(PLAYER_PED)
    last_armour = getCharArmour(PLAYER_PED)

    sendInfoMessage("Скрипт успешно {88AA62}загружен!")
    sendInfoMessage("Меню: {88AA62}/erphud {A9C4E4}или {88AA62}/ehud")

    local toggleMenu = function()
        window[0] = not window[0]
    end

    sampRegisterChatCommand('erphud', toggleMenu)
    sampRegisterChatCommand('ehud', toggleMenu)
    sampRegisterChatCommand('hud', toggleMenu)

    sampRegisterChatCommand('etime', function()
        showTimeTextdraw()
    end)

    sampRegisterChatCommand('logo', function()
        startPositioningLogo()
    end)

    sampRegisterChatCommand('captpos', function()
        startPositioningCapt()
    end)

    sampRegisterChatCommand('usepos', function()
        startPositioningDrug()
    end)

    sampRegisterChatCommand('syncstats', function()
        startManualStatsScan()
    end)

    sampRegisterChatCommand('evologo', function()
        config.showLogo = not config.showLogo
        buf.showLogo[0] = config.showLogo
        saveConfig()
        if config.showLogo then 
            showLogo()
            local lName = "Evolve"
            if config.logoType == 1 then lName = "Classic" end
            if config.logoType == 2 then lName = "ARIZONA " .. getDynamicServerName() end
            sendInfoMessage("Кастомный логотип {88AA62}показан {A9C4E4}[" .. lName .. "].")
        else 
            hideLogo()
            restoreServerLogo()
            sendErrorMessage("Кастомный логотип {E05454}скрыт{A9C4E4}, серверный {88AA62}восстановлен.")
        end
    end)

    sampRegisterChatCommand('evocapt', function(param)
        local arg = param and tostring(param):lower():match("^%s*(.-)%s*$") or ""

        if arg == "2" or arg == "zavod" or arg == "завод" then
            buf.testModeType[0] = 1
            test_mode_type = 1
            is_test_mode = true
        elseif arg == "1" or arg == "ghetto" or arg == "гетто" or arg == "capt" or arg == "капт" then
            buf.testModeType[0] = 0
            test_mode_type = 0
            is_test_mode = true
        else
            is_test_mode = not is_test_mode
        end

        war_active = is_test_mode
        buf.testMode[0] = is_test_mode

        if war_active then
            applyTestWarData(buf.testModeType[0])
            createWarTextdraws()
            local modeName = (buf.testModeType[0] == 1) and "Битва за завод" or "Гетто капт"
            sendInfoMessage("Тестовая табличка {88AA62}" .. modeName .. "{A9C4E4} включена.")
        else
            destroyWarTextdraws()
            warData = {}
            total_war_damage = 0
            current_kills = 0
            war_player_kills = {}
            war_player_faction = {}
            sendErrorMessage("Тестовая табличка {E05454}отключена.")
        end
    end)

    if config.showLogo then
        showLogo()
    else
        restoreServerLogo()
    end
    hideServerCaptTextdraws()

    triggerBackgroundSync("first_start")

    local last_drug_update_tick = 0
    local last_drag_tick = 0

    while true do
        wait(0)
        local now_tick = os.clock()

        if war_pending_hide > 0 and now_tick >= war_pending_hide then
            war_pending_hide = 0
            if not is_test_mode then
                destroyWarTextdraws()
                war_active = false
                warData = {}
            end
        end

        local cur_hp = getCharHealth(PLAYER_PED)
        local cur_arm = getCharArmour(PLAYER_PED)

        if (cur_hp < last_hp) or (cur_arm < last_armour) then
            last_hit_time = now_tick
        end
        last_hp = cur_hp
        last_armour = cur_arm

        if not is_player_alive and cur_hp > 0 and sampIsLocalPlayerSpawned() then
            is_player_alive = true
            triggerBackgroundSync("hospital_respawn")
        end

        if now_tick - last_drug_update_tick >= 0.05 then
            updateDrugTextDraw(now_tick)
            last_drug_update_tick = now_tick
        end

        if is_time_td_active and now_tick >= time_hide_tick then
            hideTimeTextdraw()
        end

        if (isPositioningLogo or isPositioningCapt or isPositioningDrug) and (now_tick - last_drag_tick >= 0.025) then
            last_drag_tick = now_tick
            local cx, cy = getCursorPos()
            local sw, sh = getScreenResolution()
            local newPosX = (cx / sw) * 640.0
            local newPosY = (cy / sh) * 480.0

            if isPositioningLogo then
                if math.abs(config.logoX - newPosX) > 0.2 or math.abs(config.logoY - newPosY) > 0.2 then
                    config.logoX = newPosX
                    config.logoY = newPosY
                    buf.logoX[0] = newPosX
                    buf.logoY[0] = newPosY
                    showLogo()
                end
            elseif isPositioningCapt then
                if math.abs(config.captX - newPosX) > 0.2 or math.abs(config.captY - newPosY) > 0.2 then
                    config.captX = newPosX
                    config.captY = newPosY
                    buf.captX[0] = newPosX
                    buf.captY[0] = newPosY
                    createWarTextdraws()
                end
            elseif isPositioningDrug then
                if math.abs(config.drugX - newPosX) > 0.2 or math.abs(config.drugY - newPosY) > 0.2 then
                    config.drugX = newPosX
                    config.drugY = newPosY
                    buf.drugX[0] = newPosX
                    buf.drugY[0] = newPosY
                    if sampTextdrawIsExists(DRUG_TD_ID) then
                        sampTextdrawSetPos(DRUG_TD_ID, newPosX, newPosY)
                    else
                        createDrugTextDraw("Use!")
                    end
                end
            end
        end

        if not sampIsLocalPlayerSpawned() then
            while not sampIsLocalPlayerSpawned() do wait(200) end
            wait(1000)
            if config.showLogo then
                showLogo()
            else
                restoreServerLogo()
            end
            if war_active and config.showCapt then createWarTextdraws() end
            triggerBackgroundSync("reconnect_spawn")
        end
    end
end

function onScriptTerminate(script)
    if script == thisScript() then
        hideLogo()
        restoreServerLogo()
        destroyWarTextdraws()
        hideDrugTextDraw()
        hideTimeTextdraw()
    end
end