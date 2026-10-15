script_author = "A7MED"
script_name = "Hud Stats"
script_version = "4.7"
script_properties('work-in-pause')

--------------------- [ IMPORTS ] --------------
local moonloaderOk, moonloader = pcall(require, 'moonloader')
local imguiOk, imgui = pcall(require, 'mimgui')
local inicfgOk, inicfg = pcall(require, 'inicfg')
local sampOk, samp = pcall(require, 'samp.events')
local wmOk, wm = pcall(require, 'windows.message')

if not (moonloaderOk and imguiOk and inicfgOk and sampOk) then
    local missing = {}
    if not moonloaderOk then table.insert(missing, "moonloader") end
    if not imguiOk then table.insert(missing, "mimgui") end
    if not inicfgOk then table.insert(missing, "inicfg") end
    if not sampOk then table.insert(missing, "samp.events") end
    local msg = "[HUD Stats] Missing required library: " .. table.concat(missing, ". ") .. " - mod disabled."
    print(msg)
    if type(sampAddChatMessage) == "function" then
        pcall(sampAddChatMessage, "{FF0000}" .. msg, -1)
    end
    return
end
-----------------------------
--------------------- [ CONFIG ] --------------
local defaultConfig = {
    settings = {
        showHUD = false,
        showKills = false,
        showDeaths = false,
        showKD = false,
        showDamage = false,
        showKillStreak = false,
        showKillsLife = false,
        showDmgLife = false,
        showMaxDmgLife = false,
        showShots = false,
        showHits = false,
        showMisses = false,
        showAccuracy = false,
        showTime = false,
        showDate = false,
        showFPS = false,
        showPing = false,
        showHealth = false,
        showBestStreak = false,
        showNemesis = false,
        showDamageTaken = false,
        showStyle = false,
        showKPM = false,
        showTopWeapon = false,
        showHeadshots = false,
        showZone = false,
        showNearestEnemy = false,
        showPlayersOnline = false,
        showMyId = false,
        posX = 0,
        posY = 395,
        colorR = 1.0,
        colorG = 1.0,
        colorB = 1.0,
        colorA = 1.0,
        numberColorR = 1.0,
        numberColorG = 1.0,
        numberColorB = 1.0,
        numberColorA = 1.0,
        fontSize = 10,
        itemOrder = "kills|nemesis|deaths|kd|damagetaken|damage|killstreak|beststreak|killslife|dmglife|maxdmglife|shots|hits|misses|health|accuracy|fps|ping|time|date|style|kpm|topweapon|headshots|zone|nearestenemy|playersonline|myid",
        reversedItems = "",
        mergedItems = "",
        independentItems = "",
        itemPositions = "",
        showPlusKill = false,
        plusKillFormat = 0, -- 0=STYLED 1=CUSTOM
        plusKillColorIndex = 0,
        plusKillColorR = 1.0,
        plusKillColorG = 0.0,
        plusKillColorB = 0.0,
        plusKillColorA = 1.0,
        plusKillPosX = 884,
        plusKillPosY = 185,
        plusKillFontSize = 30,
        plusKillDuration = 1.2,
        plusKillRiseDelay = 0.6,
        plusKillRiseSpeed = 0.6,
        plusKillFadeSpeed = 0.03
    }
}

local function deepCopyTable(t)
    local copy = {}
    for k, v in pairs(t) do
        if type(v) == "table" then
            copy[k] = deepCopyTable(v)
        else
            copy[k] = v
        end
    end
    return copy
end

local FACTORY_DEFAULTS = deepCopyTable(defaultConfig)

local configOk, config = pcall(inicfg.load, defaultConfig, 'HUD_Stats.ini')
if not configOk or not config or not config.settings then
    config = defaultConfig
    pcall(inicfg.save, defaultConfig, 'HUD_Stats.ini')
end
-----------------------------
--------------------- [ VARIABLES ] --------------
local renderWindow = imgui.new.bool(false)
local settingsPage = 1
local scriptTerminated = false

local guiFadeAlpha = 0
local guiFadeLastStep = 0
local guiOpenSpeed = 18   -- OPEN SPEED
local guiCloseSpeed = 32  -- CLOSE SPEED

local pkFadeAlpha = 0
local pkFadeLastStep = 0

local escHintFadeAlpha = 0
local escHintFadeLastStep = 0

local kills = 0
local deaths = 0
local totalDamage = 0
local damageTaken = 0
local killStreak = 0
local bestStreak = 0
local killerCounts = {}
local nemesisName = "-"
local nemesisCount = 0
local killsThisLife = 0
local damageThisLife = 0
local maxDmgPerLife = 0
local shotsFired = 0
local hits = 0
local headshots = 0
local weaponKillCounts = {}
local topWeaponName = "-"
local topWeaponCount = 0
local lastDamageBodypart = {}
local lastTechniqueStyle = "-"
local sessionStartTime = os.clock()
local lastCPressTime = -9999
local lastSprintMoveTime = -9999

local weaponNames = {
    [0] = "Fist", [1] = "Brass Knuckles", [2] = "Golf Club", [3] = "Nightstick", [4] = "Knife",
    [5] = "Bat", [6] = "Shovel", [7] = "Pool Cue", [8] = "Katana", [9] = "Chainsaw",
    [16] = "Grenade", [17] = "Teargas", [18] = "Molotov", [22] = "Colt45",
    [23] = "Silenced Pistol", [24] = "Deagle", [25] = "Shotgun", [26] = "Sawnoff",
    [27] = "Combat Shotgun", [28] = "Uzi", [29] = "MP5", [30] = "AK47", [31] = "M4",
    [32] = "Tec9", [33] = "Rifle", [34] = "Sniper Rifle", [35] = "RPG",
    [36] = "Heat-Seeker", [37] = "Flamethrower", [38] = "Minigun", [39] = "Satchel Charge",
    [41] = "Spraycan", [42] = "Fire Extinguisher", [43] = "Camera", [46] = "Parachute",
    [49] = "Vehicle"
}
local frameCount = 0
local lastFpsTime = os.clock()
local currentFPS = 0
local hudFont = nil

local itemsOrder = {}
local itemLabels = {
    time = "Server Time",
    date = "Current Date",
    kills = "Kills Tracker",
    deaths = "Deaths Tracker",
    kd = "Kill Death Ratio",
    damage = "Damage Counter",
    killstreak = "Kill Streak",
    killslife = "Kills/life",
    dmglife = "Dmg/life",
    maxdmglife = "Max dmg/life",
    shots = "Ammo In Clip",
    hits = "Hits",
    misses = "Misses",
    accuracy = "Accuracy",
    fps = "FPS Counter",
    ping = "Network Ping",
    health = "Health",
    beststreak = "Best Kill Streak",
    nemesis = "Nemesis (Top Killer)",
    damagetaken = "Damage Taken",
    style = "Combat Style",
    kpm = "Kills Per Minute",
    topweapon = "Top Kill Weapon",
    headshots = "Headshot Kills",
    zone = "Current Zone",
    nearestenemy = "Nearest Enemy",
    playersonline = "Players Online",
    myid = "My Player ID"
}

local ALL_ITEM_KEYS = {"kills", "deaths", "kd", "damage", "killstreak", "killslife", "dmglife", "maxdmglife", "shots", "hits", "misses", "accuracy", "time", "date", "fps", "ping", "health", "beststreak", "nemesis", "damagetaken", "style", "kpm", "topweapon", "headshots", "zone", "nearestenemy", "playersonline", "myid"}

local cfg_showHUD = imgui.new.bool(config.settings.showHUD)
local cfg_toggles = {
    kills = imgui.new.bool(config.settings.showKills),
    deaths = imgui.new.bool(config.settings.showDeaths),
    kd = imgui.new.bool(config.settings.showKD),
    damage = imgui.new.bool(config.settings.showDamage),
    killstreak = imgui.new.bool(config.settings.showKillStreak),
    killslife = imgui.new.bool(config.settings.showKillsLife),
    dmglife = imgui.new.bool(config.settings.showDmgLife),
    maxdmglife = imgui.new.bool(config.settings.showMaxDmgLife),
    shots = imgui.new.bool(config.settings.showShots),
    hits = imgui.new.bool(config.settings.showHits),
    misses = imgui.new.bool(config.settings.showMisses),
    accuracy = imgui.new.bool(config.settings.showAccuracy),
    time = imgui.new.bool(config.settings.showTime),
    date = imgui.new.bool(config.settings.showDate),
    fps = imgui.new.bool(config.settings.showFPS),
    ping = imgui.new.bool(config.settings.showPing),
    health = imgui.new.bool(config.settings.showHealth),
    beststreak = imgui.new.bool(config.settings.showBestStreak),
    nemesis = imgui.new.bool(config.settings.showNemesis),
    damagetaken = imgui.new.bool(config.settings.showDamageTaken),
    style = imgui.new.bool(config.settings.showStyle),
    kpm = imgui.new.bool(config.settings.showKPM),
    topweapon = imgui.new.bool(config.settings.showTopWeapon),
    headshots = imgui.new.bool(config.settings.showHeadshots),
    zone = imgui.new.bool(config.settings.showZone),
    nearestenemy = imgui.new.bool(config.settings.showNearestEnemy),
    playersonline = imgui.new.bool(config.settings.showPlayersOnline),
    myid = imgui.new.bool(config.settings.showMyId)
}

local function parseKeySet(str)
    local set = {}
    for item in string.gmatch(str or "", "[^|]+") do
        set[item] = true
    end
    return set
end

local reversedSet = parseKeySet(config.settings.reversedItems)
local mergedSet = parseKeySet(config.settings.mergedItems)
local independentSet = parseKeySet(config.settings.independentItems)
local cfg_itemReversed = {}
local cfg_itemMerge = {}
local cfg_itemIndependent = {}
local cfg_itemPosX = {}
local cfg_itemPosY = {}

local function parseItemPositions(str)
    local positions = {}
    for key, x, y in string.gmatch(str or "", "([^:|]+):(-?%d+):(-?%d+)") do
        positions[key] = {tonumber(x), tonumber(y)}
    end
    return positions
end

local itemPositionsParsed = parseItemPositions(config.settings.itemPositions)
for _, key in ipairs(ALL_ITEM_KEYS) do
    cfg_itemReversed[key] = imgui.new.bool(reversedSet[key] or false)
    cfg_itemMerge[key] = imgui.new.bool(mergedSet[key] or false)
    cfg_itemIndependent[key] = imgui.new.bool(independentSet[key] or false)
    local pos = itemPositionsParsed[key]
    cfg_itemPosX[key] = imgui.new.int(pos and pos[1] or config.settings.posX)
    cfg_itemPosY[key] = imgui.new.int(pos and pos[2] or config.settings.posY)
end

local cfg_posX = imgui.new.int(config.settings.posX)
local cfg_posY = imgui.new.int(config.settings.posY)
local cfg_color = imgui.new.float[4](
    config.settings.colorR or 0.0,
    config.settings.colorG or 0.65,
    config.settings.colorB or 1.0,
    config.settings.colorA or 1.0
)
local cfg_numberColor = imgui.new.float[4](
    config.settings.numberColorR or 0.52,
    config.settings.numberColorG or 1.0,
    config.settings.numberColorB or 0.0,
    config.settings.numberColorA or 1.0
)
local cfg_fontSize = imgui.new.int(config.settings.fontSize or 10)

local cfg_showPlusKill = imgui.new.bool(config.settings.showPlusKill)
local cfg_plusKillFormat = imgui.new.int(config.settings.plusKillFormat or 1)
local cfg_plusKillColorIndex = imgui.new.int(config.settings.plusKillColorIndex or 0)
local cfg_plusKillColor = imgui.new.float[4](
    config.settings.plusKillColorR or 0.0,
    config.settings.plusKillColorG or 0.85,
    config.settings.plusKillColorB or 1.0,
    config.settings.plusKillColorA or 1.0
)
local cfg_plusKillPosX = imgui.new.int(config.settings.plusKillPosX or 700)
local cfg_plusKillPosY = imgui.new.int(config.settings.plusKillPosY or 400)
local cfg_plusKillFontSize = imgui.new.int(config.settings.plusKillFontSize or 30)
local cfg_plusKillDuration = imgui.new.float(config.settings.plusKillDuration or 1.2)
local cfg_plusKillRiseDelay = imgui.new.float(config.settings.plusKillRiseDelay or 0.6)
local cfg_plusKillRiseSpeed = imgui.new.float(config.settings.plusKillRiseSpeed or 0.6)
local cfg_plusKillFadeSpeed = imgui.new.float(config.settings.plusKillFadeSpeed or 0.03)

local plusKillFont = nil
local renderPlusKillWindow = imgui.new.bool(false)

local plusKillActive = false
local plusKillFirst = true
local plusKillDrawY = 0
local plusKillAlpha = 1.0
local plusKillTimeStart = 0

local plusKillStyledCodes = {"r", "g", "b", "w", "y", "p", "l"}
-----------------------------
--------------------- [ FUNCTIONS ] --------------
local function applyFontSize()
    local ok, font = pcall(renderCreateFont, "Arial", cfg_fontSize[0], 5)
    if ok then
        if hudFont then
            pcall(renderReleaseFont, hudFont)
        end
        hudFont = font
    end
end

local function applyPlusKillFont()
    local ok, font = pcall(renderCreateFont, "Arial", cfg_plusKillFontSize[0], 5)
    if ok then
        if plusKillFont then
            pcall(renderReleaseFont, plusKillFont)
        end
        plusKillFont = font
    end
end

local function parseOrder(str)
    local t = {}
    for item in string.gmatch(str, "[^|]+") do
        table.insert(t, item)
    end
    return t
end

local function serializeOrder(t)
    return table.concat(t, "|")
end

itemsOrder = parseOrder(config.settings.itemOrder or "kills|deaths|kd|damage|killstreak|killslife|dmglife|maxdmglife|shots|hits|misses|accuracy|fps|ping|time|date")

local function saveConfiguration()
    config.settings.showHUD = cfg_showHUD[0]
    config.settings.showKills = cfg_toggles.kills[0]
    config.settings.showDeaths = cfg_toggles.deaths[0]
    config.settings.showKD = cfg_toggles.kd[0]
    config.settings.showDamage = cfg_toggles.damage[0]
    config.settings.showKillStreak = cfg_toggles.killstreak[0]
    config.settings.showKillsLife = cfg_toggles.killslife[0]
    config.settings.showDmgLife = cfg_toggles.dmglife[0]
    config.settings.showMaxDmgLife = cfg_toggles.maxdmglife[0]
    config.settings.showShots = cfg_toggles.shots[0]
    config.settings.showHits = cfg_toggles.hits[0]
    config.settings.showMisses = cfg_toggles.misses[0]
    config.settings.showAccuracy = cfg_toggles.accuracy[0]
    config.settings.showTime = cfg_toggles.time[0]
    config.settings.showDate = cfg_toggles.date[0]
    config.settings.showFPS = cfg_toggles.fps[0]
    config.settings.showPing = cfg_toggles.ping[0]
    config.settings.showHealth = cfg_toggles.health[0]
    config.settings.showBestStreak = cfg_toggles.beststreak[0]
    config.settings.showNemesis = cfg_toggles.nemesis[0]
    config.settings.showDamageTaken = cfg_toggles.damagetaken[0]
    config.settings.showStyle = cfg_toggles.style[0]
    config.settings.showKPM = cfg_toggles.kpm[0]
    config.settings.showTopWeapon = cfg_toggles.topweapon[0]
    config.settings.showHeadshots = cfg_toggles.headshots[0]
    config.settings.showZone = cfg_toggles.zone[0]
    config.settings.showNearestEnemy = cfg_toggles.nearestenemy[0]
    config.settings.showPlayersOnline = cfg_toggles.playersonline[0]
    config.settings.showMyId = cfg_toggles.myid[0]
    config.settings.posX = cfg_posX[0]
    config.settings.posY = cfg_posY[0]
    config.settings.colorR = cfg_color[0]
    config.settings.colorG = cfg_color[1]
    config.settings.colorB = cfg_color[2]
    config.settings.colorA = cfg_color[3]
    config.settings.numberColorR = cfg_numberColor[0]
    config.settings.numberColorG = cfg_numberColor[1]
    config.settings.numberColorB = cfg_numberColor[2]
    config.settings.numberColorA = cfg_numberColor[3]
    config.settings.fontSize = cfg_fontSize[0]
    config.settings.itemOrder = serializeOrder(itemsOrder)

    local reversedList, mergedList, independentList, positionList = {}, {}, {}, {}
    for _, key in ipairs(ALL_ITEM_KEYS) do
        if cfg_itemReversed[key][0] then table.insert(reversedList, key) end
        if cfg_itemMerge[key][0] then table.insert(mergedList, key) end
        if cfg_itemIndependent[key][0] then
            table.insert(independentList, key)
            table.insert(positionList, key .. ":" .. cfg_itemPosX[key][0] .. ":" .. cfg_itemPosY[key][0])
        end
    end
    config.settings.reversedItems = serializeOrder(reversedList)
    config.settings.mergedItems = serializeOrder(mergedList)
    config.settings.independentItems = serializeOrder(independentList)
    config.settings.itemPositions = serializeOrder(positionList)

    config.settings.showPlusKill = cfg_showPlusKill[0]
    config.settings.plusKillFormat = cfg_plusKillFormat[0]
    config.settings.plusKillColorIndex = cfg_plusKillColorIndex[0]
    config.settings.plusKillColorR = cfg_plusKillColor[0]
    config.settings.plusKillColorG = cfg_plusKillColor[1]
    config.settings.plusKillColorB = cfg_plusKillColor[2]
    config.settings.plusKillColorA = cfg_plusKillColor[3]
    config.settings.plusKillPosX = cfg_plusKillPosX[0]
    config.settings.plusKillPosY = cfg_plusKillPosY[0]
    config.settings.plusKillFontSize = cfg_plusKillFontSize[0]
    config.settings.plusKillDuration = cfg_plusKillDuration[0]
    config.settings.plusKillRiseDelay = cfg_plusKillRiseDelay[0]
    config.settings.plusKillRiseSpeed = cfg_plusKillRiseSpeed[0]
    config.settings.plusKillFadeSpeed = cfg_plusKillFadeSpeed[0]

    pcall(inicfg.save, config, 'HUD_Stats.ini')
end

local function resetStats()
    kills = 0
    deaths = 0
    totalDamage = 0
    damageTaken = 0
    killStreak = 0
    bestStreak = 0
    killsThisLife = 0
    damageThisLife = 0
    maxDmgPerLife = 0
    shotsFired = 0
    hits = 0
    killerCounts = {}
    nemesisName = "-"
    nemesisCount = 0
    headshots = 0
    weaponKillCounts = {}
    topWeaponName = "-"
    topWeaponCount = 0
    lastDamageBodypart = {}
    lastTechniqueStyle = "-"
    sessionStartTime = os.clock()
end

local function resetConfiguration()
    local d = FACTORY_DEFAULTS.settings

    cfg_showHUD[0] = d.showHUD
    cfg_toggles.kills[0] = d.showKills
    cfg_toggles.deaths[0] = d.showDeaths
    cfg_toggles.kd[0] = d.showKD
    cfg_toggles.damage[0] = d.showDamage
    cfg_toggles.killstreak[0] = d.showKillStreak
    cfg_toggles.killslife[0] = d.showKillsLife
    cfg_toggles.dmglife[0] = d.showDmgLife
    cfg_toggles.maxdmglife[0] = d.showMaxDmgLife
    cfg_toggles.shots[0] = d.showShots
    cfg_toggles.hits[0] = d.showHits
    cfg_toggles.misses[0] = d.showMisses
    cfg_toggles.accuracy[0] = d.showAccuracy
    cfg_toggles.time[0] = d.showTime
    cfg_toggles.date[0] = d.showDate
    cfg_toggles.fps[0] = d.showFPS
    cfg_toggles.ping[0] = d.showPing
    cfg_toggles.health[0] = d.showHealth
    cfg_toggles.beststreak[0] = d.showBestStreak
    cfg_toggles.nemesis[0] = d.showNemesis
    cfg_toggles.damagetaken[0] = d.showDamageTaken
    cfg_toggles.style[0] = d.showStyle
    cfg_toggles.kpm[0] = d.showKPM
    cfg_toggles.topweapon[0] = d.showTopWeapon
    cfg_toggles.headshots[0] = d.showHeadshots
    cfg_toggles.zone[0] = d.showZone
    cfg_toggles.nearestenemy[0] = d.showNearestEnemy
    cfg_toggles.playersonline[0] = d.showPlayersOnline
    cfg_toggles.myid[0] = d.showMyId

    cfg_posX[0] = d.posX
    cfg_posY[0] = d.posY
    cfg_color[0] = d.colorR
    cfg_color[1] = d.colorG
    cfg_color[2] = d.colorB
    cfg_color[3] = d.colorA
    cfg_numberColor[0] = d.numberColorR
    cfg_numberColor[1] = d.numberColorG
    cfg_numberColor[2] = d.numberColorB
    cfg_numberColor[3] = d.numberColorA
    cfg_fontSize[0] = d.fontSize
    applyFontSize()
    itemsOrder = parseOrder(d.itemOrder)

    local rSet = parseKeySet(d.reversedItems)
    local mSet = parseKeySet(d.mergedItems)
    local iSet = parseKeySet(d.independentItems)
    local posMap = parseItemPositions(d.itemPositions)
    for _, key in ipairs(ALL_ITEM_KEYS) do
        cfg_itemReversed[key][0] = rSet[key] or false
        cfg_itemMerge[key][0] = mSet[key] or false
        cfg_itemIndependent[key][0] = iSet[key] or false
        local pos = posMap[key]
        cfg_itemPosX[key][0] = pos and pos[1] or d.posX
        cfg_itemPosY[key][0] = pos and pos[2] or d.posY
    end

    cfg_showPlusKill[0] = d.showPlusKill
    cfg_plusKillFormat[0] = d.plusKillFormat
    cfg_plusKillColorIndex[0] = d.plusKillColorIndex
    cfg_plusKillColor[0] = d.plusKillColorR
    cfg_plusKillColor[1] = d.plusKillColorG
    cfg_plusKillColor[2] = d.plusKillColorB
    cfg_plusKillColor[3] = d.plusKillColorA
    cfg_plusKillPosX[0] = d.plusKillPosX
    cfg_plusKillPosY[0] = d.plusKillPosY
    cfg_plusKillFontSize[0] = d.plusKillFontSize
    applyPlusKillFont()
    cfg_plusKillDuration[0] = d.plusKillDuration
    cfg_plusKillRiseDelay[0] = d.plusKillRiseDelay
    cfg_plusKillRiseSpeed[0] = d.plusKillRiseSpeed
    cfg_plusKillFadeSpeed[0] = d.plusKillFadeSpeed

    saveConfiguration()
end

local function joinColor(r, g, b, a)
    return bit.bor(
        bit.lshift(math.floor(a * 255), 24),
        bit.lshift(math.floor(r * 255), 16),
        bit.lshift(math.floor(g * 255), 8),
        math.floor(b * 255)
    )
end

local function triggerPlusKill()
    if cfg_plusKillFormat[0] == 0 then
        local colChar = plusKillStyledCodes[cfg_plusKillColorIndex[0] + 1] or "r"
        local msg = "~" .. colChar .. "~~h~+KILL"
        local duration = math.floor(cfg_plusKillDuration[0] * 1000)
        lua_thread.create(function()
            wait(50)
            pcall(printStyledString, msg, duration, 7)
        end)
    else
        plusKillActive = true
        plusKillFirst = true
    end
end

local function drawStatPart(font, label, value, reversed, x, y, wordColor, numberColor)
    local seg1Text, seg1Color, seg2Text, seg2Color
    if reversed then
        seg1Text, seg1Color = value, numberColor
        seg2Text, seg2Color = " " .. label, wordColor
    else
        seg1Text, seg1Color = label .. ": ", wordColor
        seg2Text, seg2Color = value, numberColor
    end
    renderFontDrawText(font, seg1Text, x, y, seg1Color)
    local w1 = renderGetFontDrawTextLength(font, seg1Text)
    renderFontDrawText(font, seg2Text, x + w1, y, seg2Color)
    local w2 = renderGetFontDrawTextLength(font, seg2Text)
    return w1 + w2
end

local function calculateZone(x, y, z)
    local streets = {
    {"Avispa Country Club", -2667.810, -302.135, -28.831, -2646.400, -262.320, 71.169},
    {"Easter Bay Airport", -1315.420, -405.388, 15.406, -1264.400, -209.543, 25.406},
    {"Avispa Country Club", -2550.040, -355.493, 0.000, -2470.040, -318.493, 39.700},
    {"Easter Bay Airport", -1490.330, -209.543, 15.406, -1264.400, -148.388, 25.406},
    {"Garcia", -2395.140, -222.589, -5.3, -2354.090, -204.792, 200.000},
    {"Shady Cabin", -1632.830, -2263.440, -3.0, -1601.330, -2231.790, 200.000},
    {"East Los Santos", 2381.680, -1494.030, -89.084, 2421.030, -1454.350, 110.916},
    {"LVA Freight Depot", 1236.630, 1163.410, -89.084, 1277.050, 1203.280, 110.916},
    {"Blackfield Intersection", 1277.050, 1044.690, -89.084, 1315.350, 1087.630, 110.916},
    {"Avispa Country Club", -2470.040, -355.493, 0.000, -2270.040, -318.493, 46.100},
    {"Temple", 1252.330, -926.999, -89.084, 1357.000, -910.170, 110.916},
    {"Unity Station", 1692.620, -1971.800, -20.492, 1812.620, -1932.800, 79.508},
    {"LVA Freight Depot", 1315.350, 1044.690, -89.084, 1375.600, 1087.630, 110.916},
    {"Los Flores", 2581.730, -1454.350, -89.084, 2632.830, -1393.420, 110.916},
    {"Starfish Casino", 2437.390, 1858.100, -39.084, 2495.090, 1970.850, 60.916},
    {"Easter Bay Chemicals", -1132.820, -787.391, 0.000, -956.476, -768.027, 200.000},
    {"Downtown Los Santos", 1370.850, -1170.870, -89.084, 1463.900, -1130.850, 110.916},
    {"Esplanade East", -1620.300, 1176.520, -4.5, -1580.010, 1274.260, 200.000},
    {"Market Station", 787.461, -1410.930, -34.126, 866.009, -1310.210, 65.874},
    {"Linden Station", 2811.250, 1229.590, -39.594, 2861.250, 1407.590, 60.406},
    {"Montgomery Intersection", 1582.440, 347.457, 0.000, 1664.620, 401.750, 200.000},
    {"Frederick Bridge", 2759.250, 296.501, 0.000, 2774.250, 594.757, 200.000},
    {"Yellow Bell Station", 1377.480, 2600.430, -21.926, 1492.450, 2687.360, 78.074},
    {"Downtown Los Santos", 1507.510, -1385.210, 110.916, 1582.550, -1325.310, 335.916},
    {"Jefferson", 2185.330, -1210.740, -89.084, 2281.450, -1154.590, 110.916},
    {"Mulholland", 1318.130, -910.170, -89.084, 1357.000, -768.027, 110.916},
    {"Avispa Country Club", -2361.510, -417.199, 0.000, -2270.040, -355.493, 200.000},
    {"Jefferson", 1996.910, -1449.670, -89.084, 2056.860, -1350.720, 110.916},
    {"Julius Thruway West", 1236.630, 2142.860, -89.084, 1297.470, 2243.230, 110.916},
    {"Jefferson", 2124.660, -1494.030, -89.084, 2266.210, -1449.670, 110.916},
    {"Julius Thruway North", 1848.400, 2478.490, -89.084, 1938.800, 2553.490, 110.916},
    {"Rodeo", 422.680, -1570.200, -89.084, 466.223, -1406.050, 110.916},
    {"Cranberry Station", -2007.830, 56.306, 0.000, -1922.000, 224.782, 100.000},
    {"Downtown Los Santos", 1391.050, -1026.330, -89.084, 1463.900, -926.999, 110.916},
    {"Redsands West", 1704.590, 2243.230, -89.084, 1777.390, 2342.830, 110.916},
    {"Little Mexico", 1758.900, -1722.260, -89.084, 1812.620, -1577.590, 110.916},
    {"Blackfield Intersection", 1375.600, 823.228, -89.084, 1457.390, 919.447, 110.916},
    {"Los Santos International", 1974.630, -2394.330, -39.084, 2089.000, -2256.590, 60.916},
    {"Beacon Hill", -399.633, -1075.520, -1.489, -319.033, -977.516, 198.511},
    {"Rodeo", 334.503, -1501.950, -89.084, 422.680, -1406.050, 110.916},
    {"Richman", 225.165, -1369.620, -89.084, 334.503, -1292.070, 110.916},
    {"Downtown Los Santos", 1724.760, -1250.900, -89.084, 1812.620, -1150.870, 110.916},
    {"The Strip", 2027.400, 1703.230, -89.084, 2137.400, 1783.230, 110.916},
    {"Downtown Los Santos", 1378.330, -1130.850, -89.084, 1463.900, -1026.330, 110.916},
    {"Blackfield Intersection", 1197.390, 1044.690, -89.084, 1277.050, 1163.390, 110.916},
    {"Conference Center", 1073.220, -1842.270, -89.084, 1323.900, -1804.210, 110.916},
    {"Montgomery", 1451.400, 347.457, -6.1, 1582.440, 420.802, 200.000},
    {"Foster Valley", -2270.040, -430.276, -1.2, -2178.690, -324.114, 200.000},
    {"Blackfield Chapel", 1325.600, 596.349, -89.084, 1375.600, 795.010, 110.916},
    {"Los Santos International", 2051.630, -2597.260, -39.084, 2152.450, -2394.330, 60.916},
    {"Mulholland", 1096.470, -910.170, -89.084, 1169.130, -768.027, 110.916},
    {"Yellow Bell Gol Course", 1457.460, 2723.230, -89.084, 1534.560, 2863.230, 110.916},
    {"The Strip", 2027.400, 1783.230, -89.084, 2162.390, 1863.230, 110.916},
    {"Jefferson", 2056.860, -1210.740, -89.084, 2185.330, -1126.320, 110.916},
    {"Mulholland", 952.604, -937.184, -89.084, 1096.470, -860.619, 110.916},
    {"Aldea Malvada", -1372.140, 2498.520, 0.000, -1277.590, 2615.350, 200.000},
    {"Las Colinas", 2126.860, -1126.320, -89.084, 2185.330, -934.489, 110.916},
    {"Las Colinas", 1994.330, -1100.820, -89.084, 2056.860, -920.815, 110.916},
    {"Richman", 647.557, -954.662, -89.084, 768.694, -860.619, 110.916},
    {"LVA Freight Depot", 1277.050, 1087.630, -89.084, 1375.600, 1203.280, 110.916},
    {"Julius Thruway North", 1377.390, 2433.230, -89.084, 1534.560, 2507.230, 110.916},
    {"Willowfield", 2201.820, -2095.000, -89.084, 2324.000, -1989.900, 110.916},
    {"Julius Thruway North", 1704.590, 2342.830, -89.084, 1848.400, 2433.230, 110.916},
    {"Temple", 1252.330, -1130.850, -89.084, 1378.330, -1026.330, 110.916},
    {"Little Mexico", 1701.900, -1842.270, -89.084, 1812.620, -1722.260, 110.916},
    {"Queens", -2411.220, 373.539, 0.000, -2253.540, 458.411, 200.000},
    {"Las Venturas Airport", 1515.810, 1586.400, -12.500, 1729.950, 1714.560, 87.500},
    {"Richman", 225.165, -1292.070, -89.084, 466.223, -1235.070, 110.916},
    {"Temple", 1252.330, -1026.330, -89.084, 1391.050, -926.999, 110.916},
    {"East Los Santos", 2266.260, -1494.030, -89.084, 2381.680, -1372.040, 110.916},
    {"Julius Thruway East", 2623.180, 943.235, -89.084, 2749.900, 1055.960, 110.916},
    {"Willowfield", 2541.700, -1941.400, -89.084, 2703.580, -1852.870, 110.916},
    {"Las Colinas", 2056.860, -1126.320, -89.084, 2126.860, -920.815, 110.916},
    {"Julius Thruway East", 2625.160, 2202.760, -89.084, 2685.160, 2442.550, 110.916},
    {"Rodeo", 225.165, -1501.950, -89.084, 334.503, -1369.620, 110.916},
    {"Las Brujas", -365.167, 2123.010, -3.0, -208.570, 2217.680, 200.000},
    {"Julius Thruway East", 2536.430, 2442.550, -89.084, 2685.160, 2542.550, 110.916},
    {"Rodeo", 334.503, -1406.050, -89.084, 466.223, -1292.070, 110.916},
    {"Vinewood", 647.557, -1227.280, -89.084, 787.461, -1118.280, 110.916},
    {"Rodeo", 422.680, -1684.650, -89.084, 558.099, -1570.200, 110.916},
    {"Julius Thruway North", 2498.210, 2542.550, -89.084, 2685.160, 2626.550, 110.916},
    {"Downtown Los Santos", 1724.760, -1430.870, -89.084, 1812.620, -1250.900, 110.916},
    {"Rodeo", 225.165, -1684.650, -89.084, 312.803, -1501.950, 110.916},
    {"Jefferson", 2056.860, -1449.670, -89.084, 2266.210, -1372.040, 110.916},
    {"Hampton Barns", 603.035, 264.312, 0.000, 761.994, 366.572, 200.000},
    {"Temple", 1096.470, -1130.840, -89.084, 1252.330, -1026.330, 110.916},
    {"Kincaid Bridge", -1087.930, 855.370, -89.084, -961.950, 986.281, 110.916},
    {"Verona Beach", 1046.150, -1722.260, -89.084, 1161.520, -1577.590, 110.916},
    {"Commerce", 1323.900, -1722.260, -89.084, 1440.900, -1577.590, 110.916},
    {"Mulholland", 1357.000, -926.999, -89.084, 1463.900, -768.027, 110.916},
    {"Rodeo", 466.223, -1570.200, -89.084, 558.099, -1385.070, 110.916},
    {"Mulholland", 911.802, -860.619, -89.084, 1096.470, -768.027, 110.916},
    {"Mulholland", 768.694, -954.662, -89.084, 952.604, -860.619, 110.916},
    {"Julius Thruway South", 2377.390, 788.894, -89.084, 2537.390, 897.901, 110.916},
    {"Idlewood", 1812.620, -1852.870, -89.084, 1971.660, -1742.310, 110.916},
    {"Ocean Docks", 2089.000, -2394.330, -89.084, 2201.820, -2235.840, 110.916},
    {"Commerce", 1370.850, -1577.590, -89.084, 1463.900, -1384.950, 110.916},
    {"Julius Thruway North", 2121.400, 2508.230, -89.084, 2237.400, 2663.170, 110.916},
    {"Temple", 1096.470, -1026.330, -89.084, 1252.330, -910.170, 110.916},
    {"Glen Park", 1812.620, -1449.670, -89.084, 1996.910, -1350.720, 110.916},
    {"Easter Bay Airport", -1242.980, -50.096, 0.000, -1213.910, 578.396, 200.000},
    {"Martin Bridge", -222.179, 293.324, 0.000, -122.126, 476.465, 200.000},
    {"The Strip", 2106.700, 1863.230, -89.084, 2162.390, 2202.760, 110.916},
    {"Willowfield", 2541.700, -2059.230, -89.084, 2703.580, -1941.400, 110.916},
    {"Marina", 807.922, -1577.590, -89.084, 926.922, -1416.250, 110.916},
    {"Las Venturas Airport", 1457.370, 1143.210, -89.084, 1777.400, 1203.280, 110.916},
    {"Idlewood", 1812.620, -1742.310, -89.084, 1951.660, -1602.310, 110.916},
    {"Esplanade East", -1580.010, 1025.980, -6.1, -1499.890, 1274.260, 200.000},
    {"Downtown Los Santos", 1370.850, -1384.950, -89.084, 1463.900, -1170.870, 110.916},
    {"The Mako Span", 1664.620, 401.750, 0.000, 1785.140, 567.203, 200.000},
    {"Rodeo", 312.803, -1684.650, -89.084, 422.680, -1501.950, 110.916},
    {"Pershing Square", 1440.900, -1722.260, -89.084, 1583.500, -1577.590, 110.916},
    {"Mulholland", 687.802, -860.619, -89.084, 911.802, -768.027, 110.916},
    {"Gant Bridge", -2741.070, 1490.470, -6.1, -2616.400, 1659.680, 200.000},
    {"Las Colinas", 2185.330, -1154.590, -89.084, 2281.450, -934.489, 110.916},
    {"Mulholland", 1169.130, -910.170, -89.084, 1318.130, -768.027, 110.916},
    {"Julius Thruway North", 1938.800, 2508.230, -89.084, 2121.400, 2624.230, 110.916},
    {"Commerce", 1667.960, -1577.590, -89.084, 1812.620, -1430.870, 110.916},
    {"Rodeo", 72.648, -1544.170, -89.084, 225.165, -1404.970, 110.916},
    {"Roca Escalante", 2536.430, 2202.760, -89.084, 2625.160, 2442.550, 110.916},
    {"Rodeo", 72.648, -1684.650, -89.084, 225.165, -1544.170, 110.916},
    {"Market", 952.663, -1310.210, -89.084, 1072.660, -1130.850, 110.916},
    {"Las Colinas", 2632.740, -1135.040, -89.084, 2747.740, -945.035, 110.916},
    {"Mulholland", 861.085, -674.885, -89.084, 1156.550, -600.896, 110.916},
    {"King's", -2253.540, 373.539, -9.1, -1993.280, 458.411, 200.000},
    {"Redsands East", 1848.400, 2342.830, -89.084, 2011.940, 2478.490, 110.916},
    {"Downtown", -1580.010, 744.267, -6.1, -1499.890, 1025.980, 200.000},
    {"Conference Center", 1046.150, -1804.210, -89.084, 1323.900, -1722.260, 110.916},
    {"Richman", 647.557, -1118.280, -89.084, 787.461, -954.662, 110.916},
    {"Ocean Flats", -2994.490, 277.411, -9.1, -2867.850, 458.411, 200.000},
    {"Greenglass College", 964.391, 930.890, -89.084, 1166.530, 1044.690, 110.916},
    {"Glen Park", 1812.620, -1100.820, -89.084, 1994.330, -973.380, 110.916},
    {"LVA Freight Depot", 1375.600, 919.447, -89.084, 1457.370, 1203.280, 110.916},
    {"Regular Tom", -405.770, 1712.860, -3.0, -276.719, 1892.750, 200.000},
    {"Verona Beach", 1161.520, -1722.260, -89.084, 1323.900, -1577.590, 110.916},
    {"East Los Santos", 2281.450, -1372.040, -89.084, 2381.680, -1135.040, 110.916},
    {"Caligula's Palace", 2137.400, 1703.230, -89.084, 2437.390, 1783.230, 110.916},
    {"Idlewood", 1951.660, -1742.310, -89.084, 2124.660, -1602.310, 110.916},
    {"Pilgrim", 2624.400, 1383.230, -89.084, 2685.160, 1783.230, 110.916},
    {"Idlewood", 2124.660, -1742.310, -89.084, 2222.560, -1494.030, 110.916},
    {"Queens", -2533.040, 458.411, 0.000, -2329.310, 578.396, 200.000},
    {"Downtown", -1871.720, 1176.420, -4.5, -1620.300, 1274.260, 200.000},
    {"Commerce", 1583.500, -1722.260, -89.084, 1758.900, -1577.590, 110.916},
    {"East Los Santos", 2381.680, -1454.350, -89.084, 2462.130, -1135.040, 110.916},
    {"Marina", 647.712, -1577.590, -89.084, 807.922, -1416.250, 110.916},
    {"Richman", 72.648, -1404.970, -89.084, 225.165, -1235.070, 110.916},
    {"Vinewood", 647.712, -1416.250, -89.084, 787.461, -1227.280, 110.916},
    {"East Los Santos", 2222.560, -1628.530, -89.084, 2421.030, -1494.030, 110.916},
    {"Rodeo", 558.099, -1684.650, -89.084, 647.522, -1384.930, 110.916},
    {"Easter Tunnel", -1709.710, -833.034, -1.5, -1446.010, -730.118, 200.000},
    {"Rodeo", 466.223, -1385.070, -89.084, 647.522, -1235.070, 110.916},
    {"Redsands East", 1817.390, 2202.760, -89.084, 2011.940, 2342.830, 110.916},
    {"The Clown's Pocket", 2162.390, 1783.230, -89.084, 2437.390, 1883.230, 110.916},
    {"Idlewood", 1971.660, -1852.870, -89.084, 2222.560, -1742.310, 110.916},
    {"Montgomery Intersection", 1546.650, 208.164, 0.000, 1745.830, 347.457, 200.000},
    {"Willowfield", 2089.000, -2235.840, -89.084, 2201.820, -1989.900, 110.916},
    {"Temple", 952.663, -1130.840, -89.084, 1096.470, -937.184, 110.916},
    {"Prickle Pine", 1848.400, 2553.490, -89.084, 1938.800, 2863.230, 110.916},
    {"Los Santos International", 1400.970, -2669.260, -39.084, 2189.820, -2597.260, 60.916},
    {"Garver Bridge", -1213.910, 950.022, -89.084, -1087.930, 1178.930, 110.916},
    {"Garver Bridge", -1339.890, 828.129, -89.084, -1213.910, 1057.040, 110.916},
    {"Kincaid Bridge", -1339.890, 599.218, -89.084, -1213.910, 828.129, 110.916},
    {"Kincaid Bridge", -1213.910, 721.111, -89.084, -1087.930, 950.022, 110.916},
    {"Verona Beach", 930.221, -2006.780, -89.084, 1073.220, -1804.210, 110.916},
    {"Verdant Bluffs", 1073.220, -2006.780, -89.084, 1249.620, -1842.270, 110.916},
    {"Vinewood", 787.461, -1130.840, -89.084, 952.604, -954.662, 110.916},
    {"Vinewood", 787.461, -1310.210, -89.084, 952.663, -1130.840, 110.916},
    {"Commerce", 1463.900, -1577.590, -89.084, 1667.960, -1430.870, 110.916},
    {"Market", 787.461, -1416.250, -89.084, 1072.660, -1310.210, 110.916},
    {"Rockshore West", 2377.390, 596.349, -89.084, 2537.390, 788.894, 110.916},
    {"Julius Thruway North", 2237.400, 2542.550, -89.084, 2498.210, 2663.170, 110.916},
    {"East Beach", 2632.830, -1668.130, -89.084, 2747.740, -1393.420, 110.916},
    {"Fallow Bridge", 434.341, 366.572, 0.000, 603.035, 555.680, 200.000},
    {"Willowfield", 2089.000, -1989.900, -89.084, 2324.000, -1852.870, 110.916},
    {"Chinatown", -2274.170, 578.396, -7.6, -2078.670, 744.170, 200.000},
    {"El Castillo del Diablo", -208.570, 2337.180, 0.000, 8.430, 2487.180, 200.000},
    {"Ocean Docks", 2324.000, -2145.100, -89.084, 2703.580, -2059.230, 110.916},
    {"Easter Bay Chemicals", -1132.820, -768.027, 0.000, -956.476, -578.118, 200.000},
    {"The Visage", 1817.390, 1703.230, -89.084, 2027.400, 1863.230, 110.916},
    {"Ocean Flats", -2994.490, -430.276, -1.2, -2831.890, -222.589, 200.000},
    {"Richman", 321.356, -860.619, -89.084, 687.802, -768.027, 110.916},
    {"Green Palms", 176.581, 1305.450, -3.0, 338.658, 1520.720, 200.000},
    {"Richman", 321.356, -768.027, -89.084, 700.794, -674.885, 110.916},
    {"Starfish Casino", 2162.390, 1883.230, -89.084, 2437.390, 2012.180, 110.916},
    {"East Beach", 2747.740, -1668.130, -89.084, 2959.350, -1498.620, 110.916},
    {"Jefferson", 2056.860, -1372.040, -89.084, 2281.450, -1210.740, 110.916},
    {"Downtown Los Santos", 1463.900, -1290.870, -89.084, 1724.760, -1150.870, 110.916},
    {"Downtown Los Santos", 1463.900, -1430.870, -89.084, 1724.760, -1290.870, 110.916},
    {"Garver Bridge", -1499.890, 696.442, -179.615, -1339.890, 925.353, 20.385},
    {"Julius Thruway South", 1457.390, 823.228, -89.084, 2377.390, 863.229, 110.916},
    {"East Los Santos", 2421.030, -1628.530, -89.084, 2632.830, -1454.350, 110.916},
    {"Greenglass College", 964.391, 1044.690, -89.084, 1197.390, 1203.220, 110.916},
    {"Las Colinas", 2747.740, -1120.040, -89.084, 2959.350, -945.035, 110.916},
    {"Mulholland", 737.573, -768.027, -89.084, 1142.290, -674.885, 110.916},
    {"Ocean Docks", 2201.820, -2730.880, -89.084, 2324.000, -2418.330, 110.916},
    {"East Los Santos", 2462.130, -1454.350, -89.084, 2581.730, -1135.040, 110.916},
    {"Ganton", 2222.560, -1722.330, -89.084, 2632.830, -1628.530, 110.916},
    {"Avispa Country Club", -2831.890, -430.276, -6.1, -2646.400, -222.589, 200.000},
    {"Willowfield", 1970.620, -2179.250, -89.084, 2089.000, -1852.870, 110.916},
    {"Esplanade North", -1982.320, 1274.260, -4.5, -1524.240, 1358.900, 200.000},
    {"The High Roller", 1817.390, 1283.230, -89.084, 2027.390, 1469.230, 110.916},
    {"Ocean Docks", 2201.820, -2418.330, -89.084, 2324.000, -2095.000, 110.916},
    {"Last Dime Motel", 1823.080, 596.349, -89.084, 1997.220, 823.228, 110.916},
    {"Bayside Marina", -2353.170, 2275.790, 0.000, -2153.170, 2475.790, 200.000},
    {"King's", -2329.310, 458.411, -7.6, -1993.280, 578.396, 200.000},
    {"El Corona", 1692.620, -2179.250, -89.084, 1812.620, -1842.270, 110.916},
    {"Blackfield Chapel", 1375.600, 596.349, -89.084, 1558.090, 823.228, 110.916},
    {"The Pink Swan", 1817.390, 1083.230, -89.084, 2027.390, 1283.230, 110.916},
    {"Julius Thruway West", 1197.390, 1163.390, -89.084, 1236.630, 2243.230, 110.916},
    {"Los Flores", 2581.730, -1393.420, -89.084, 2747.740, -1135.040, 110.916},
    {"The Visage", 1817.390, 1863.230, -89.084, 2106.700, 2011.830, 110.916},
    {"Prickle Pine", 1938.800, 2624.230, -89.084, 2121.400, 2861.550, 110.916},
    {"Verona Beach", 851.449, -1804.210, -89.084, 1046.150, -1577.590, 110.916},
    {"Robada Intersection", -1119.010, 1178.930, -89.084, -862.025, 1351.450, 110.916},
    {"Linden Side", 2749.900, 943.235, -89.084, 2923.390, 1198.990, 110.916},
    {"Ocean Docks", 2703.580, -2302.330, -89.084, 2959.350, -2126.900, 110.916},
    {"Willowfield", 2324.000, -2059.230, -89.084, 2541.700, -1852.870, 110.916},
    {"King's", -2411.220, 265.243, -9.1, -1993.280, 373.539, 200.000},
    {"Commerce", 1323.900, -1842.270, -89.084, 1701.900, -1722.260, 110.916},
    {"Mulholland", 1269.130, -768.027, -89.084, 1414.070, -452.425, 110.916},
    {"Marina", 647.712, -1804.210, -89.084, 851.449, -1577.590, 110.916},
    {"Battery Point", -2741.070, 1268.410, -4.5, -2533.040, 1490.470, 200.000},
    {"The Four Dragons Casino", 1817.390, 863.232, -89.084, 2027.390, 1083.230, 110.916},
    {"Blackfield", 964.391, 1203.220, -89.084, 1197.390, 1403.220, 110.916},
    {"Julius Thruway North", 1534.560, 2433.230, -89.084, 1848.400, 2583.230, 110.916},
    {"Yellow Bell Gol Course", 1117.400, 2723.230, -89.084, 1457.460, 2863.230, 110.916},
    {"Idlewood", 1812.620, -1602.310, -89.084, 2124.660, -1449.670, 110.916},
    {"Redsands West", 1297.470, 2142.860, -89.084, 1777.390, 2243.230, 110.916},
    {"Doherty", -2270.040, -324.114, -1.2, -1794.920, -222.589, 200.000},
    {"Hilltop Farm", 967.383, -450.390, -3.0, 1176.780, -217.900, 200.000},
    {"Las Barrancas", -926.130, 1398.730, -3.0, -719.234, 1634.690, 200.000},
    {"Pirates in Men's Pants", 1817.390, 1469.230, -89.084, 2027.400, 1703.230, 110.916},
    {"City Hall", -2867.850, 277.411, -9.1, -2593.440, 458.411, 200.000},
    {"Avispa Country Club", -2646.400, -355.493, 0.000, -2270.040, -222.589, 200.000},
    {"The Strip", 2027.400, 863.229, -89.084, 2087.390, 1703.230, 110.916},
    {"Hashbury", -2593.440, -222.589, -1.0, -2411.220, 54.722, 200.000},
    {"Los Santos International", 1852.000, -2394.330, -89.084, 2089.000, -2179.250, 110.916},
    {"Whitewood Estates", 1098.310, 1726.220, -89.084, 1197.390, 2243.230, 110.916},
    {"Sherman Reservoir", -789.737, 1659.680, -89.084, -599.505, 1929.410, 110.916},
    {"El Corona", 1812.620, -2179.250, -89.084, 1970.620, -1852.870, 110.916},
    {"Downtown", -1700.010, 744.267, -6.1, -1580.010, 1176.520, 200.000},
    {"Foster Valley", -2178.690, -1250.970, 0.000, -1794.920, -1115.580, 200.000},
    {"Las Payasadas", -354.332, 2580.360, 2.0, -133.625, 2816.820, 200.000},
    {"Valle Ocultado", -936.668, 2611.440, 2.0, -715.961, 2847.900, 200.000},
    {"Blackfield Intersection", 1166.530, 795.010, -89.084, 1375.600, 1044.690, 110.916},
    {"Ganton", 2222.560, -1852.870, -89.084, 2632.830, -1722.330, 110.916},
    {"Easter Bay Airport", -1213.910, -730.118, 0.000, -1132.820, -50.096, 200.000},
    {"Redsands East", 1817.390, 2011.830, -89.084, 2106.700, 2202.760, 110.916},
    {"Esplanade East", -1499.890, 578.396, -79.615, -1339.890, 1274.260, 20.385},
    {"Caligula's Palace", 2087.390, 1543.230, -89.084, 2437.390, 1703.230, 110.916},
    {"Royal Casino", 2087.390, 1383.230, -89.084, 2437.390, 1543.230, 110.916},
    {"Richman", 72.648, -1235.070, -89.084, 321.356, -1008.150, 110.916},
    {"Starfish Casino", 2437.390, 1783.230, -89.084, 2685.160, 2012.180, 110.916},
    {"Mulholland", 1281.130, -452.425, -89.084, 1641.130, -290.913, 110.916},
    {"Downtown", -1982.320, 744.170, -6.1, -1871.720, 1274.260, 200.000},
    {"Hankypanky Point", 2576.920, 62.158, 0.000, 2759.250, 385.503, 200.000},
    {"K.A.C.C. Military Fuels", 2498.210, 2626.550, -89.084, 2749.900, 2861.550, 110.916},
    {"Harry Gold Parkway", 1777.390, 863.232, -89.084, 1817.390, 2342.830, 110.916},
    {"Bayside Tunnel", -2290.190, 2548.290, -89.084, -1950.190, 2723.290, 110.916},
    {"Ocean Docks", 2324.000, -2302.330, -89.084, 2703.580, -2145.100, 110.916},
    {"Richman", 321.356, -1044.070, -89.084, 647.557, -860.619, 110.916},
    {"Randolph Industrial Estate", 1558.090, 596.349, -89.084, 1823.080, 823.235, 110.916},
    {"East Beach", 2632.830, -1852.870, -89.084, 2959.350, -1668.130, 110.916},
    {"Flint Water", -314.426, -753.874, -89.084, -106.339, -463.073, 110.916},
    {"Blueberry", 19.607, -404.136, 3.8, 349.607, -220.137, 200.000},
    {"Linden Station", 2749.900, 1198.990, -89.084, 2923.390, 1548.990, 110.916},
    {"Glen Park", 1812.620, -1350.720, -89.084, 2056.860, -1100.820, 110.916},
    {"Downtown", -1993.280, 265.243, -9.1, -1794.920, 578.396, 200.000},
    {"Redsands West", 1377.390, 2243.230, -89.084, 1704.590, 2433.230, 110.916},
    {"Richman", 321.356, -1235.070, -89.084, 647.522, -1044.070, 110.916},
    {"Gant Bridge", -2741.450, 1659.680, -6.1, -2616.400, 2175.150, 200.000},
    {"Lil' Probe Inn", -90.218, 1286.850, -3.0, 153.859, 1554.120, 200.000},
    {"Flint Intersection", -187.700, -1596.760, -89.084, 17.063, -1276.600, 110.916},
    {"Las Colinas", 2281.450, -1135.040, -89.084, 2632.740, -945.035, 110.916},
    {"Sobell Rail Yards", 2749.900, 1548.990, -89.084, 2923.390, 1937.250, 110.916},
    {"The Emerald Isle", 2011.940, 2202.760, -89.084, 2237.400, 2508.230, 110.916},
    {"El Castillo del Diablo", -208.570, 2123.010, -7.6, 114.033, 2337.180, 200.000},
    {"Santa Flora", -2741.070, 458.411, -7.6, -2533.040, 793.411, 200.000},
    {"Playa del Seville", 2703.580, -2126.900, -89.084, 2959.350, -1852.870, 110.916},
    {"Market", 926.922, -1577.590, -89.084, 1370.850, -1416.250, 110.916},
    {"Queens", -2593.440, 54.722, 0.000, -2411.220, 458.411, 200.000},
    {"Pilson Intersection", 1098.390, 2243.230, -89.084, 1377.390, 2507.230, 110.916},
    {"Spinybed", 2121.400, 2663.170, -89.084, 2498.210, 2861.550, 110.916},
    {"Pilgrim", 2437.390, 1383.230, -89.084, 2624.400, 1783.230, 110.916},
    {"Blackfield", 964.391, 1403.220, -89.084, 1197.390, 1726.220, 110.916},
    {"'The Big Ear'", -410.020, 1403.340, -3.0, -137.969, 1681.230, 200.000},
    {"Dillimore", 580.794, -674.885, -9.5, 861.085, -404.790, 200.000},
    {"El Quebrados", -1645.230, 2498.520, 0.000, -1372.140, 2777.850, 200.000},
    {"Esplanade North", -2533.040, 1358.900, -4.5, -1996.660, 1501.210, 200.000},
    {"Easter Bay Airport", -1499.890, -50.096, -1.0, -1242.980, 249.904, 200.000},
    {"Fisher's Lagoon", 1916.990, -233.323, -100.000, 2131.720, 13.800, 200.000},
    {"Mulholland", 1414.070, -768.027, -89.084, 1667.610, -452.425, 110.916},
    {"East Beach", 2747.740, -1498.620, -89.084, 2959.350, -1120.040, 110.916},
    {"San Andreas Sound", 2450.390, 385.503, -100.000, 2759.250, 562.349, 200.000},
    {"Shady Creeks", -2030.120, -2174.890, -6.1, -1820.640, -1771.660, 200.000},
    {"Market", 1072.660, -1416.250, -89.084, 1370.850, -1130.850, 110.916},
    {"Rockshore West", 1997.220, 596.349, -89.084, 2377.390, 823.228, 110.916},
    {"Prickle Pine", 1534.560, 2583.230, -89.084, 1848.400, 2863.230, 110.916},
    {"Easter Basin", -1794.920, -50.096, -1.04, -1499.890, 249.904, 200.000},
    {"Leafy Hollow", -1166.970, -1856.030, 0.000, -815.624, -1602.070, 200.000},
    {"LVA Freight Depot", 1457.390, 863.229, -89.084, 1777.400, 1143.210, 110.916},
    {"Prickle Pine", 1117.400, 2507.230, -89.084, 1534.560, 2723.230, 110.916},
    {"Blueberry", 104.534, -220.137, 2.3, 349.607, 152.236, 200.000},
    {"El Castillo del Diablo", -464.515, 2217.680, 0.000, -208.570, 2580.360, 200.000},
    {"Downtown", -2078.670, 578.396, -7.6, -1499.890, 744.267, 200.000},
    {"Rockshore East", 2537.390, 676.549, -89.084, 2902.350, 943.235, 110.916},
    {"San Fierro Bay", -2616.400, 1501.210, -3.0, -1996.660, 1659.680, 200.000},
    {"Paradiso", -2741.070, 793.411, -6.1, -2533.040, 1268.410, 200.000},
    {"The Camel's Toe", 2087.390, 1203.230, -89.084, 2640.400, 1383.230, 110.916},
    {"Old Venturas Strip", 2162.390, 2012.180, -89.084, 2685.160, 2202.760, 110.916},
    {"Juniper Hill", -2533.040, 578.396, -7.6, -2274.170, 968.369, 200.000},
    {"Juniper Hollow", -2533.040, 968.369, -6.1, -2274.170, 1358.900, 200.000},
    {"Roca Escalante", 2237.400, 2202.760, -89.084, 2536.430, 2542.550, 110.916},
    {"Julius Thruway East", 2685.160, 1055.960, -89.084, 2749.900, 2626.550, 110.916},
    {"Verona Beach", 647.712, -2173.290, -89.084, 930.221, -1804.210, 110.916},
    {"Foster Valley", -2178.690, -599.884, -1.2, -1794.920, -324.114, 200.000},
    {"Arco del Oeste", -901.129, 2221.860, 0.000, -592.090, 2571.970, 200.000},
    {"Fallen Tree", -792.254, -698.555, -5.3, -452.404, -380.043, 200.000},
    {"The Farm", -1209.670, -1317.100, 114.981, -908.161, -787.391, 251.981},
    {"The Sherman Dam", -968.772, 1929.410, -3.0, -481.126, 2155.260, 200.000},
    {"Esplanade North", -1996.660, 1358.900, -4.5, -1524.240, 1592.510, 200.000},
    {"Financial", -1871.720, 744.170, -6.1, -1701.300, 1176.420, 300.000},
    {"Garcia", -2411.220, -222.589, -1.14, -2173.040, 265.243, 200.000},
    {"Montgomery", 1119.510, 119.526, -3.0, 1451.400, 493.323, 200.000},
    {"Creek", 2749.900, 1937.250, -89.084, 2921.620, 2669.790, 110.916},
    {"Los Santos International", 1249.620, -2394.330, -89.084, 1852.000, -2179.250, 110.916},
    {"Santa Maria Beach", 72.648, -2173.290, -89.084, 342.648, -1684.650, 110.916},
    {"Mulholland Intersection", 1463.900, -1150.870, -89.084, 1812.620, -768.027, 110.916},
    {"Angel Pine", -2324.940, -2584.290, -6.1, -1964.220, -2212.110, 200.000},
    {"Verdant Meadows", 37.032, 2337.180, -3.0, 435.988, 2677.900, 200.000},
    {"Octane Springs", 338.658, 1228.510, 0.000, 664.308, 1655.050, 200.000},
    {"Come-A-Lot", 2087.390, 943.235, -89.084, 2623.180, 1203.230, 110.916},
    {"Redsands West", 1236.630, 1883.110, -89.084, 1777.390, 2142.860, 110.916},
    {"Santa Maria Beach", 342.648, -2173.290, -89.084, 647.712, -1684.650, 110.916},
    {"Verdant Bluffs", 1249.620, -2179.250, -89.084, 1692.620, -1842.270, 110.916},
    {"Las Venturas Airport", 1236.630, 1203.280, -89.084, 1457.370, 1883.110, 110.916},
    {"Flint Range", -594.191, -1648.550, 0.000, -187.700, -1276.600, 200.000},
    {"Verdant Bluffs", 930.221, -2488.420, -89.084, 1249.620, -2006.780, 110.916},
    {"Palomino Creek", 2160.220, -149.004, 0.000, 2576.920, 228.322, 200.000},
    {"Ocean Docks", 2373.770, -2697.090, -89.084, 2809.220, -2330.460, 110.916},
    {"Easter Bay Airport", -1213.910, -50.096, -4.5, -947.980, 578.396, 200.000},
    {"Whitewood Estates", 883.308, 1726.220, -89.084, 1098.310, 2507.230, 110.916},
    {"Calton Heights", -2274.170, 744.170, -6.1, -1982.320, 1358.900, 200.000},
    {"Easter Basin", -1794.920, 249.904, -9.1, -1242.980, 578.396, 200.000},
    {"Los Santos Inlet", -321.744, -2224.430, -89.084, 44.615, -1724.430, 110.916},
    {"Doherty", -2173.040, -222.589, -1.0, -1794.920, 265.243, 200.000},
    {"Mount Chiliad", -2178.690, -2189.910, -47.917, -2030.120, -1771.660, 576.083},
    {"Fort Carson", -376.233, 826.326, -3.0, 123.717, 1220.440, 200.000},
    {"Foster Valley", -2178.690, -1115.580, 0.000, -1794.920, -599.884, 200.000},
    {"Ocean Flats", -2994.490, -222.589, -1.0, -2593.440, 277.411, 200.000},
    {"Fern Ridge", 508.189, -139.259, 0.000, 1306.660, 119.526, 200.000},
    {"Bayside", -2741.070, 2175.150, 0.000, -2353.170, 2722.790, 200.000},
    {"Las Venturas Airport", 1457.370, 1203.280, -89.084, 1777.390, 1883.110, 110.916},
    {"Blueberry Acres", -319.676, -220.137, 0.000, 104.534, 293.324, 200.000},
    {"Palisades", -2994.490, 458.411, -6.1, -2741.070, 1339.610, 200.000},
    {"North Rock", 2285.370, -768.027, 0.000, 2770.590, -269.740, 200.000},
    {"Hunter Quarry", 337.244, 710.840, -115.239, 860.554, 1031.710, 203.761},
    {"Los Santos International", 1382.730, -2730.880, -89.084, 2201.820, -2394.330, 110.916},
    {"Missionary Hill", -2994.490, -811.276, 0.000, -2178.690, -430.276, 200.000},
    {"San Fierro Bay", -2616.400, 1659.680, -3.0, -1996.660, 2175.150, 200.000},
    {"Restricted Area", -91.586, 1655.050, -50.000, 421.234, 2123.010, 250.000},
    {"Mount Chiliad", -2997.470, -1115.580, -47.917, -2178.690, -971.913, 576.083},
    {"Mount Chiliad", -2178.690, -1771.660, -47.917, -1936.120, -1250.970, 576.083},
    {"Easter Bay Airport", -1794.920, -730.118, -3.0, -1213.910, -50.096, 200.000},
    {"The Panopticon", -947.980, -304.320, -1.1, -319.676, 327.071, 200.000},
    {"Shady Creeks", -1820.640, -2643.680, -8.0, -1226.780, -1771.660, 200.000},
    {"Back o Beyond", -1166.970, -2641.190, 0.000, -321.744, -1856.030, 200.000},
    {"Mount Chiliad", -2994.490, -2189.910, -47.917, -2178.690, -1115.580, 576.083},
    {"Tierra Robada", -1213.910, 596.349, -242.990, -480.539, 1659.680, 900.000},
    {"Flint County", -1213.910, -2892.970, -242.990, 44.615, -768.027, 900.000},
    {"Whetstone", -2997.470, -2892.970, -242.990, -1213.910, -1115.580, 900.000},
    {"Bone County", -480.539, 596.349, -242.990, 869.461, 2993.870, 900.000},
    {"Tierra Robada", -2997.470, 1659.680, -242.990, -480.539, 2993.870, 900.000},
    {"San Fierro", -2997.470, -1115.580, -242.990, -1213.910, 1659.680, 900.000},
    {"Las Venturas", 869.461, 596.349, -242.990, 2997.060, 2993.870, 900.000},
    {"Red County", -1213.910, -768.027, -242.990, 2997.060, 596.349, 900.000},
    {"Los Santos", 44.615, -2892.970, -242.990, 2997.060, -768.027, 900.000}}

    for i, v in ipairs(streets) do
        if (x >= v[2]) and (y >= v[3]) and (z >= v[4]) and (x <= v[5]) and (y <= v[6]) and (z <= v[7]) then
            return v[1]
        end
    end
    return "Unknown"
end

local zoneCache = "Unknown"
local zoneCacheTime = -9999
local ZONE_REFRESH_INTERVAL = 1.0

local ammoCache = "-"
local ammoCacheTime = -9999
local AMMO_REFRESH_INTERVAL = 0.15

local timeCache = "00:00:00 000"
local timeCacheTime = -9999
local TIME_REFRESH_INTERVAL = 0.1

local dateCache = "-"
local dateCacheTime = -9999
local DATE_REFRESH_INTERVAL = 5.0

local pingCache = "-"
local pingCacheTime = -9999
local PING_REFRESH_INTERVAL = 0.5

local healthCache = "-"
local healthCacheTime = -9999
local HEALTH_REFRESH_INTERVAL = 0.15

local cachedMyId = -1
local cachedMyIdTime = -9999
local MYID_REFRESH_INTERVAL = 2.0

local function getMyPlayerId()
    local now = os.clock()
    if now - cachedMyIdTime >= MYID_REFRESH_INTERVAL then
        cachedMyIdTime = now
        local active, pId = sampGetPlayerIdByCharHandle(PLAYER_PED)
        cachedMyId = (active and pId) or -1
    end
    return cachedMyId
end

local nearestCache = nil
local nearestCacheTime = -9999
local NEAREST_REFRESH_INTERVAL = 0.5

local function getNearestEnemyDistance()
    local okMe, myX, myY, myZ = pcall(getCharCoordinates, PLAYER_PED)
    if not okMe then return nil end
    local maxId = sampGetMaxPlayerId(false)
    local myId = getMyPlayerId()
    local nearestDist = nil
    for id = 0, maxId do
        if id ~= myId and sampIsPlayerConnected(id) then
            local streamed, handle = sampGetCharHandleBySampPlayerId(id)
            if streamed and doesCharExist(handle) then
                local okPos, ex, ey, ez = pcall(getCharCoordinates, handle)
                if okPos then
                    local dx, dy, dz = ex - myX, ey - myY, ez - myZ
                    local dist = math.sqrt(dx * dx + dy * dy + dz * dz)
                    if not nearestDist or dist < nearestDist then
                        nearestDist = dist
                    end
                end
            end
        end
    end
    return nearestDist
end

local function getItemLabelValue(key)
    if key == "kills" then
        return "Kills", tostring(kills)
    elseif key == "deaths" then
        return "Deaths", tostring(deaths)
    elseif key == "kd" then
        local kd = deaths > 0 and (kills / deaths) or kills
        return "KD", string.format("%.2f", kd)
    elseif key == "damage" then
        return "Damage", tostring(totalDamage)
    elseif key == "killstreak" then
        return "Streak", tostring(killStreak)
    elseif key == "killslife" then
        return "Kills/Life", tostring(killsThisLife)
    elseif key == "dmglife" then
        return "Dmg/Life", tostring(damageThisLife)
    elseif key == "maxdmglife" then
        return "Max Dmg/Life", tostring(maxDmgPerLife)
    elseif key == "shots" then
        local now = os.clock()
        if now - ammoCacheTime >= AMMO_REFRESH_INTERVAL then
            ammoCacheTime = now
            local wOk, weapon = pcall(getCurrentCharWeapon, PLAYER_PED)
            if wOk and weapon and weapon ~= 0 then
                local aOk, ammo = pcall(getAmmoInCharWeapon, PLAYER_PED, weapon)
                ammoCache = (aOk and type(ammo) == "number") and tostring(ammo) or "-"
            else
                ammoCache = "-"
            end
        end
        return "Ammo", ammoCache
    elseif key == "hits" then
        return "Hits", tostring(hits)
    elseif key == "misses" then
        return "Misses", tostring(shotsFired - hits)
    elseif key == "accuracy" then
        local acc = shotsFired > 0 and (hits / shotsFired * 100) or 0
        return "Accuracy", string.format("%.1f%%", acc)
    elseif key == "time" then
        local now = os.clock()
        if now - timeCacheTime >= TIME_REFRESH_INTERVAL then
            timeCacheTime = now
            local ms = math.floor((now % 1) * 1000)
            timeCache = os.date("%H:%M:%S") .. string.format(" %03d", ms)
        end
        return "Time", timeCache
    elseif key == "date" then
        local now = os.clock()
        if now - dateCacheTime >= DATE_REFRESH_INTERVAL then
            dateCacheTime = now
            dateCache = os.date("%Y-%m-%d")
        end
        return "Date", dateCache
    elseif key == "fps" then
        return "FPS", tostring(currentFPS)
    elseif key == "ping" then
        local now = os.clock()
        if now - pingCacheTime >= PING_REFRESH_INTERVAL then
            pingCacheTime = now
            local myId = getMyPlayerId()
            if myId ~= -1 then
                pingCache = string.format("%d ms", sampGetPlayerPing(myId))
            else
                pingCache = "-"
            end
        end
        return "Ping", pingCache
    elseif key == "health" then
        local now = os.clock()
        if now - healthCacheTime >= HEALTH_REFRESH_INTERVAL then
            healthCacheTime = now
            local ok, hp = pcall(getCharHealth, PLAYER_PED)
            healthCache = (ok and type(hp) == "number") and tostring(math.floor(hp)) or "-"
        end
        return "Health", healthCache
    elseif key == "beststreak" then
        return "Best Streak", tostring(bestStreak)
    elseif key == "nemesis" then
        if nemesisCount > 0 then
            return "Nemesis", nemesisName .. " (" .. nemesisCount .. "x)"
        end
        return "Nemesis", "-"
    elseif key == "damagetaken" then
        return "Dmg Taken", tostring(damageTaken)
    elseif key == "style" then
        return "Style", lastTechniqueStyle
    elseif key == "kpm" then
        local elapsedMin = (os.clock() - sessionStartTime) / 60
        if elapsedMin < (1 / 60) then
            return "KPM", "0.00"
        end
        local kpm = kills / elapsedMin
        return "KPM", string.format("%.2f", kpm)
    elseif key == "topweapon" then
        if topWeaponCount > 0 then
            return "Top Weapon", topWeaponName .. " (" .. topWeaponCount .. ")"
        end
        return "Top Weapon", "-"
    elseif key == "headshots" then
        return "Headshots", tostring(headshots)
    elseif key == "zone" then
        local now = os.clock()
        if now - zoneCacheTime >= ZONE_REFRESH_INTERVAL then
            zoneCacheTime = now
            local okPos, zx, zy, zz = pcall(getCharCoordinates, PLAYER_PED)
            if okPos then
                local zOk, zoneName = pcall(calculateZone, zx, zy, zz)
                zoneCache = (zOk and zoneName) or "Unknown"
            else
                zoneCache = "Unknown"
            end
        end
        return "Zone", zoneCache
    elseif key == "nearestenemy" then
        local now = os.clock()
        if now - nearestCacheTime >= NEAREST_REFRESH_INTERVAL then
            nearestCacheTime = now
            local nOk, dist = pcall(getNearestEnemyDistance)
            nearestCache = (nOk and dist) and string.format("%.0fm", dist) or "-"
        end
        return "Nearest", nearestCache
    elseif key == "playersonline" then
        local ok, count = pcall(sampGetPlayerCount, false)
        return "Online", (ok and count) and tostring(count) or "-"
    elseif key == "myid" then
        local myId = getMyPlayerId()
        return "Id", (myId ~= -1) and tostring(myId) or "-"
    end
    return nil, nil
end

local function updateCombatTechniqueTracking()
    local now = os.clock()

    local cOk, cDown = pcall(isKeyDown, 0x43) -- C
    if cOk and cDown then
        lastCPressTime = now
    end

    local aOk, aDown = pcall(isKeyDown, 0x41) -- A
    local dOk, dDown = pcall(isKeyDown, 0x44) -- D
    local shiftOk, shiftDown = pcall(isKeyDown, 0x10) -- Shift
    local spaceOk, spaceDown = pcall(isKeyDown, 0x20) -- Space
    local moving = (aOk and aDown) or (dOk and dDown)
    local sprinting = (shiftOk and shiftDown) or (spaceOk and spaceDown)
    if moving and sprinting then
        lastSprintMoveTime = now
    end
end

local function updateGuiFade()
    local now = os.clock() * 1000
    if now - guiFadeLastStep >= 30 then
        guiFadeLastStep = now
        local target = (renderWindow[0] or renderPlusKillWindow[0]) and 200 or 0
        if guiFadeAlpha < target then
            guiFadeAlpha = math.min(target, guiFadeAlpha + guiOpenSpeed)
        elseif guiFadeAlpha > target then
            guiFadeAlpha = math.max(target, guiFadeAlpha - guiCloseSpeed)
        end
    end

    if now - pkFadeLastStep >= 30 then
        pkFadeLastStep = now
        local pkTarget = renderPlusKillWindow[0] and 200 or 0
        if pkFadeAlpha < pkTarget then
            pkFadeAlpha = math.min(pkTarget, pkFadeAlpha + guiOpenSpeed)
        elseif pkFadeAlpha > pkTarget then
            pkFadeAlpha = math.max(pkTarget, pkFadeAlpha - guiCloseSpeed)
        end
    end
end

local toggleAnimState = {}

local function updateToggleAnim(id, isOn)
    local st = toggleAnimState[id]
    if not st then
        st = { t = isOn and 1.0 or 0.0, lastStep = 0 }
        toggleAnimState[id] = st
    end
    local now = os.clock() * 1000
    if now - st.lastStep >= 16 then
        st.lastStep = now
        local target = isOn and 1.0 or 0.0
        local speed = 0.25 -- ANIM SPEED
        if st.t < target then
            st.t = math.min(target, st.t + speed)
        elseif st.t > target then
            st.t = math.max(target, st.t - speed)
        end
    end
    return st.t
end

local function safeComboStr(label, ref, nullSepString, itemsTable)
    if imgui.ComboStr then
        local ok, changed = pcall(imgui.ComboStr, label, ref, nullSepString)
        if ok then return changed end
    end
    if imgui.Combo then
        local ok, changed = pcall(imgui.Combo, label, ref, itemsTable)
        if ok then return changed end
    end
    return false
end

local function drawToggleSwitch(id, bool_ptr)
    local p = imgui.GetCursorScreenPos()
    local draw_list = imgui.GetWindowDrawList()
    local width = 36.0
    local height = 18.0
    local radius = height * 0.5

    if imgui.InvisibleButton(id, imgui.ImVec2(width, height)) then
        bool_ptr[0] = not bool_ptr[0]
        saveConfiguration()
    end

    local t = updateToggleAnim(id, bool_ptr[0])

    local off_col = { 0.20, 0.24, 0.28 }
    local on_col  = { 0.00, 0.65, 1.00 }
    local bg_col = imgui.GetColorU32Vec4(imgui.ImVec4(
        off_col[1] + (on_col[1] - off_col[1]) * t,
        off_col[2] + (on_col[2] - off_col[2]) * t,
        off_col[3] + (on_col[3] - off_col[3]) * t,
        1.00
    ))
    local circle_col = imgui.GetColorU32Vec4(imgui.ImVec4(0.95, 0.97, 1.00, 1.00))

    draw_list:AddRectFilled(p, imgui.ImVec2(p.x + width, p.y + height), bg_col, radius)
    local circle_x = p.x + radius + (width - radius * 2) * t
    draw_list:AddCircleFilled(imgui.ImVec2(circle_x, p.y + radius), radius - 2.5, circle_col)
end

local function drawArrowButton(id, direction)
    local p = imgui.GetCursorScreenPos()
    local draw_list = imgui.GetWindowDrawList()
    local size = 20.0

    local clicked = imgui.InvisibleButton(id, imgui.ImVec2(size, size))
    local is_hovered = imgui.IsItemHovered()
    
    local bg_col = is_hovered and imgui.GetColorU32Vec4(imgui.ImVec4(0.00, 0.65, 1.00, 1.00)) or imgui.GetColorU32Vec4(imgui.ImVec4(0.14, 0.18, 0.24, 1.00))
    local arrow_col = imgui.GetColorU32Vec4(imgui.ImVec4(0.92, 0.96, 1.00, 1.00))

    draw_list:AddRectFilled(p, imgui.ImVec2(p.x + size, p.y + size), bg_col, 5.0)

    local cx, cy = p.x + size * 0.5, p.y + size * 0.5
    if direction == "up" then
        draw_list:AddTriangleFilled(
            imgui.ImVec2(cx, cy - 3),
            imgui.ImVec2(cx - 3, cy + 3),
            imgui.ImVec2(cx + 3, cy + 3),
            arrow_col
        )
    else
        draw_list:AddTriangleFilled(
            imgui.ImVec2(cx, cy + 3),
            imgui.ImVec2(cx - 3, cy - 3),
            imgui.ImVec2(cx + 3, cy - 3),
            arrow_col
        )
    end

    return clicked
end

local function drawCloseButton(id, size)
    size = size or 20.0
    local p = imgui.GetCursorScreenPos()
    local draw_list = imgui.GetWindowDrawList()

    local clicked = imgui.InvisibleButton(id, imgui.ImVec2(size, size))
    local is_hovered = imgui.IsItemHovered()

    local bg_col = is_hovered and imgui.GetColorU32Vec4(imgui.ImVec4(0.80, 0.20, 0.20, 1.00)) or imgui.GetColorU32Vec4(imgui.ImVec4(0.14, 0.18, 0.24, 1.00))
    local line_col = imgui.GetColorU32Vec4(imgui.ImVec4(0.95, 0.97, 1.00, 1.00))

    draw_list:AddRectFilled(p, imgui.ImVec2(p.x + size, p.y + size), bg_col, 5.0)

    local pad = size * 0.28
    local x1, y1 = p.x + pad, p.y + pad
    local x2, y2 = p.x + size - pad, p.y + size - pad
    draw_list:AddLine(imgui.ImVec2(x1, y1), imgui.ImVec2(x2, y2), line_col, 2.2)
    draw_list:AddLine(imgui.ImVec2(x2, y1), imgui.ImVec2(x1, y2), line_col, 2.2)

    return clicked, is_hovered
end

local escHintShownThisFrame = false
local function drawEscHintAbove(winPos)
    escHintShownThisFrame = true
    local now = os.clock() * 1000
    if now - escHintFadeLastStep >= 30 and escHintFadeAlpha < 200 then
        escHintFadeLastStep = now
        escHintFadeAlpha = math.min(200, escHintFadeAlpha + 30)
    end

    imgui.SetNextWindowPos(imgui.ImVec2(winPos.x, winPos.y - 50))
    imgui.PushStyleColor(imgui.Col.WindowBg, imgui.ImVec4(0.0, 0.0, 0.0, 0.85))
    imgui.PushStyleVarFloat(imgui.StyleVar.Alpha, imgui.GetStyle().Alpha * (escHintFadeAlpha / 200))

    imgui.Begin("##esc_hint", nil,
        imgui.WindowFlags.NoTitleBar + imgui.WindowFlags.NoResize +
        imgui.WindowFlags.NoMove + imgui.WindowFlags.NoScrollbar +
        imgui.WindowFlags.NoInputs + imgui.WindowFlags.NoFocusOnAppearing +
        imgui.WindowFlags.AlwaysAutoResize)

    imgui.TextColored(imgui.ImVec4(0.65, 0.65, 0.65, 1.0), "Hint:")
    imgui.TextColored(imgui.ImVec4(0.97, 0.97, 0.97, 1.0), "ESC - close menu")

    imgui.End()
    imgui.PopStyleVar()
    imgui.PopStyleColor()
end

local function drawSquareButton(id, glyph, size)
    size = size or 28.0
    local p = imgui.GetCursorScreenPos()
    local draw_list = imgui.GetWindowDrawList()

    local clicked = imgui.InvisibleButton(id, imgui.ImVec2(size, size))
    local is_hovered = imgui.IsItemHovered()

    local bg_col = is_hovered and imgui.GetColorU32Vec4(imgui.ImVec4(0.00, 0.65, 1.00, 1.00)) or imgui.GetColorU32Vec4(imgui.ImVec4(0.14, 0.18, 0.24, 1.00))
    local line_col = imgui.GetColorU32Vec4(imgui.ImVec4(0.92, 0.96, 1.00, 1.00))

    draw_list:AddRectFilled(p, imgui.ImVec2(p.x + size, p.y + size), bg_col, 6.0)

    local cx, cy = p.x + size * 0.5, p.y + size * 0.5
    local half = size * 0.22
    draw_list:AddLine(imgui.ImVec2(cx - half, cy), imgui.ImVec2(cx + half, cy), line_col, 2.2)
    if glyph == "+" then
        draw_list:AddLine(imgui.ImVec2(cx, cy - half), imgui.ImVec2(cx, cy + half), line_col, 2.2)
    end

    return clicked
end

local function drawValueBox(text, width, height)
    width = width or 46.0
    height = height or 28.0
    local p = imgui.GetCursorScreenPos()
    local draw_list = imgui.GetWindowDrawList()

    draw_list:AddRectFilled(p, imgui.ImVec2(p.x + width, p.y + height), imgui.GetColorU32Vec4(imgui.ImVec4(0.10, 0.13, 0.17, 1.00)), 6.0)
    draw_list:AddRect(p, imgui.ImVec2(p.x + width, p.y + height), imgui.GetColorU32Vec4(imgui.ImVec4(0.15, 0.22, 0.30, 0.90)), 6.0, 0, 1.2)

    local textSize = imgui.CalcTextSize(text)
    draw_list:AddText(imgui.ImVec2(p.x + (width - textSize.x) * 0.5, p.y + (height - textSize.y) * 0.5), imgui.GetColorU32Vec4(imgui.ImVec4(0.92, 0.96, 1.00, 1.00)), text)

    imgui.Dummy(imgui.ImVec2(width, height))
end

local function drawIconButton(id, text, size, active, tooltip, ghost)
    size = size or 20.0
    local p = imgui.GetCursorScreenPos()
    local draw_list = imgui.GetWindowDrawList()

    local clicked = imgui.InvisibleButton(id, imgui.ImVec2(size, size))
    local is_hovered = imgui.IsItemHovered()

    local bg_col
    if active then
        bg_col = imgui.GetColorU32Vec4(imgui.ImVec4(0.00, 0.65, 1.00, 1.00))
    elseif is_hovered then
        bg_col = imgui.GetColorU32Vec4(imgui.ImVec4(0.24, 0.30, 0.38, 1.00))
    elseif not ghost then
        bg_col = imgui.GetColorU32Vec4(imgui.ImVec4(0.14, 0.18, 0.24, 1.00))
    end
    local text_col = imgui.GetColorU32Vec4(imgui.ImVec4(0.92, 0.96, 1.00, 1.00))

    if bg_col then
        draw_list:AddRectFilled(p, imgui.ImVec2(p.x + size, p.y + size), bg_col, 5.0)
    end

    if text ~= "" then
        local textSize = imgui.CalcTextSize(text)
        draw_list:AddText(imgui.ImVec2(p.x + (size - textSize.x) * 0.5, p.y + (size - textSize.y) * 0.5), text_col, text)
    end

    if is_hovered and tooltip then
        imgui.BeginTooltip()
        imgui.Text(tooltip)
        imgui.EndTooltip()
    end

    return clicked
end

local function getActiveCount()
    local cnt = 0
    for _, key in ipairs(itemsOrder) do
        if cfg_toggles[key] and cfg_toggles[key][0] then
            cnt = cnt + 1
        end
    end
    return cnt
end

local function applyCustomStyle()
    local style = imgui.GetStyle()
    local colors = style.Colors

    style.WindowRounding = 10.0
    style.ChildRounding = 6.0
    style.FrameRounding = 5.0
    style.PopupRounding = 5.0
    style.ScrollbarRounding = 0.0
    style.GrabRounding = 5.0
    style.WindowPadding = imgui.ImVec2(12, 12)
    style.FramePadding = imgui.ImVec2(6, 4)
    style.ItemSpacing = imgui.ImVec2(6, 6)

    colors[imgui.Col.WindowBg] = imgui.ImVec4(0.06, 0.08, 0.10, 0.98)
    colors[imgui.Col.ChildBg] = imgui.ImVec4(0.10, 0.13, 0.17, 0.90)
    colors[imgui.Col.Border] = imgui.ImVec4(0.15, 0.22, 0.30, 0.50)
    colors[imgui.Col.FrameBg] = imgui.ImVec4(0.13, 0.17, 0.22, 1.00)
    colors[imgui.Col.FrameBgHovered] = imgui.ImVec4(0.18, 0.25, 0.34, 1.00)
    colors[imgui.Col.FrameBgActive] = imgui.ImVec4(0.22, 0.32, 0.44, 1.00)
    colors[imgui.Col.Button] = imgui.ImVec4(0.00, 0.55, 0.90, 0.85)
    colors[imgui.Col.ButtonHovered] = imgui.ImVec4(0.00, 0.65, 1.00, 1.00)
    colors[imgui.Col.ButtonActive] = imgui.ImVec4(0.00, 0.45, 0.75, 1.00)
    colors[imgui.Col.SliderGrab] = imgui.ImVec4(0.00, 0.65, 1.00, 1.00)
    colors[imgui.Col.SliderGrabActive] = imgui.ImVec4(0.20, 0.75, 1.00, 1.00)
    colors[imgui.Col.Text] = imgui.ImVec4(0.92, 0.96, 1.00, 1.00)
    colors[imgui.Col.TextDisabled] = imgui.ImVec4(0.45, 0.52, 0.60, 1.00)
end

local function drawPickHint()
    local ok, sw = pcall(function() return select(1, getScreenResolution()) end)
    sw = (ok and sw) or 640
    local text = "Left Click To Save Position."
    if hudFont then
        local textW = renderGetFontDrawTextLength(hudFont, text)
        renderFontDrawText(hudFont, text, (sw - textW) / 2, 40, joinColor(1.0, 1.0, 1.0, 1.0))
    end
end

local function pickHudPosition()
    local wasRenderWindow = renderWindow[0]
    renderWindow[0] = false
    sampSetCursorMode(3)

    while true do
        wait(0)
        local mx, my = getCursorPos()
        cfg_posX[0] = mx
        cfg_posY[0] = my

        drawPickHint()
        if hudFont then
            local wordColor = joinColor(cfg_color[0], cfg_color[1], cfg_color[2], cfg_color[3])
            local numberColor = joinColor(cfg_numberColor[0], cfg_numberColor[1], cfg_numberColor[2], cfg_numberColor[3])
            local previewDrawn = false
            for _, key in ipairs(itemsOrder) do
                local isIndependent = cfg_itemIndependent[key] and cfg_itemIndependent[key][0]
                if cfg_toggles[key] and cfg_toggles[key][0] and not isIndependent then
                    local label, value = getItemLabelValue(key)
                    if label then
                        local reversed = cfg_itemReversed[key] and cfg_itemReversed[key][0]
                        drawStatPart(hudFont, label, value, reversed, mx, my, wordColor, numberColor)
                        previewDrawn = true
                        break
                    end
                end
            end
            if not previewDrawn then
                renderFontDrawText(hudFont, "HUD Position", mx, my, wordColor)
            end
        end

        if isKeyJustPressed(1) then
            sampSetCursorMode(0)
            saveConfiguration()
            pcall(sampAddChatMessage, "{00FF00}[HUD Stats]{FFFFFF} Position saved.", -1)
            renderWindow[0] = wasRenderWindow
            break
        end
    end
end

local function pickItemPosition(key)
    local wasRenderWindow = renderWindow[0]
    renderWindow[0] = false
    sampSetCursorMode(3)

    while true do
        wait(0)
        local mx, my = getCursorPos()
        cfg_itemPosX[key][0] = mx
        cfg_itemPosY[key][0] = my

        drawPickHint()
        if hudFont then
            local wordColor = joinColor(cfg_color[0], cfg_color[1], cfg_color[2], cfg_color[3])
            local numberColor = joinColor(cfg_numberColor[0], cfg_numberColor[1], cfg_numberColor[2], cfg_numberColor[3])
            local label, value = getItemLabelValue(key)
            if label then
                local reversed = cfg_itemReversed[key] and cfg_itemReversed[key][0]
                drawStatPart(hudFont, label, value, reversed, mx, my, wordColor, numberColor)
            else
                renderFontDrawText(hudFont, itemLabels[key] or key, mx, my, wordColor)
            end
        end

        if isKeyJustPressed(1) then
            sampSetCursorMode(0)
            saveConfiguration()
            pcall(sampAddChatMessage, "{00FF00}[HUD Stats]{FFFFFF} Position saved.", -1)
            renderWindow[0] = wasRenderWindow
            break
        end
    end
end

local function pickPlusKillPosition()
    local wasRenderWindow = renderWindow[0]
    renderWindow[0] = false
    renderPlusKillWindow[0] = false
    sampSetCursorMode(3)

    while true do
        wait(0)
        local mx, my = getCursorPos()
        cfg_plusKillPosX[0] = mx
        cfg_plusKillPosY[0] = my

        drawPickHint()
        if plusKillFont then
            local col = joinColor(cfg_plusKillColor[0], cfg_plusKillColor[1], cfg_plusKillColor[2], 1.0)
            renderFontDrawText(plusKillFont, "+KILL", mx, my, col)
        end

        if isKeyJustPressed(1) then
            sampSetCursorMode(0)
            saveConfiguration()
            pcall(sampAddChatMessage, "{00FF00}[HUD Stats]{FFFFFF} Position saved.", -1)
            renderWindow[0] = wasRenderWindow
            renderPlusKillWindow[0] = true
            break
        end
    end
end
-----------------------------
--------------------- [ EVENTS ] --------------
function samp.onPlayerDeathNotification(killerId, killedId, reason)
    local ok, err = pcall(function()
        local res, myId = sampGetPlayerIdByCharHandle(PLAYER_PED)
        if res and myId ~= -1 then
            if killerId == myId then
                kills = kills + 1
                killStreak = killStreak + 1
                killsThisLife = killsThisLife + 1
                if killStreak > bestStreak then
                    bestStreak = killStreak
                end

                local weaponName = weaponNames[reason] or ("Weapon #" .. tostring(reason))
                weaponKillCounts[weaponName] = (weaponKillCounts[weaponName] or 0) + 1
                if weaponKillCounts[weaponName] > topWeaponCount then
                    topWeaponCount = weaponKillCounts[weaponName]
                    topWeaponName = weaponName
                end

                if lastDamageBodypart[killedId] == 9 then
                    headshots = headshots + 1
                end
                lastDamageBodypart[killedId] = nil

                if cfg_showPlusKill[0] then
                    triggerPlusKill()
                end
            end
            if killedId == myId then
                deaths = deaths + 1
                killStreak = 0
                killsThisLife = 0
                if damageThisLife > maxDmgPerLife then
                    maxDmgPerLife = damageThisLife
                end
                damageThisLife = 0

                if killerId ~= 65535 and killerId ~= myId then
                    local nameOk, killerName = pcall(sampGetPlayerNickname, killerId)
                    if nameOk and killerName and killerName ~= "" then
                        killerCounts[killerName] = (killerCounts[killerName] or 0) + 1
                        if killerCounts[killerName] > nemesisCount then
                            nemesisCount = killerCounts[killerName]
                            nemesisName = killerName
                        end
                    end
                end
            end
        end
    end)
    if not ok then print("[HUD Stats] onPlayerDeathNotification error: " .. tostring(err)) end
end

function samp.onSendGiveDamage(playerId, damage, weapon, bodypart)
    local ok, err = pcall(function()
        totalDamage = totalDamage + math.floor(damage)
        damageThisLife = damageThisLife + math.floor(damage)
        lastDamageBodypart[playerId] = bodypart
    end)
    if not ok then print("[HUD Stats] onSendGiveDamage error: " .. tostring(err)) end
end

function samp.onSendTakeDamage(issuerId, damage, weapon, bodypart)
    local ok, err = pcall(function()
        damageTaken = damageTaken + math.floor(damage)
    end)
    if not ok then print("[HUD Stats] onSendTakeDamage error: " .. tostring(err)) end
end

function samp.onPlayerQuit(playerId, reason)
    lastDamageBodypart[playerId] = nil
end

function samp.onSendBulletSync(data)
    local ok, err = pcall(function()
        shotsFired = shotsFired + 1
        if data.targetType and data.targetType == 1 then
            hits = hits + 1
        end

        local now = os.clock()
        local wOk, weapon = pcall(getCurrentCharWeapon, PLAYER_PED)
        local isCbugWeapon = wOk and (weapon == 24 or weapon == 25 or weapon == 26 or weapon == 27)
        if isCbugWeapon then
            if (now - lastCPressTime) < 0.30 then
                lastTechniqueStyle = "Cbug"
            end
            if (now - lastSprintMoveTime) < 0.30 then
                lastTechniqueStyle = "Lifefoot"
            end
        end
    end)
    if not ok then print("[HUD Stats] onSendBulletSync error: " .. tostring(err)) end
end

if wmOk then
    addEventHandler('onWindowMessage', function(msg, wparam, lparam)
        local ok, err = pcall(function()
            if wparam == 27 and (renderWindow[0] or renderPlusKillWindow[0]) then -- ESC
                if msg == wm.WM_KEYDOWN then
                    consumeWindowMessage(true, false)
                elseif msg == wm.WM_KEYUP then
                    if renderPlusKillWindow[0] then
                        renderPlusKillWindow[0] = false
                    else
                        renderWindow[0] = false
                    end
                end
            end
        end)
        if not ok then print("[HUD Stats] onWindowMessage error: " .. tostring(err)) end
    end)
end
-----------------------------
--------------------- [ UI ] --------------
imgui.OnInitialize(function()
    applyCustomStyle()
end)

local function plusKillFrameCondition()
    if scriptTerminated then return false end
    updateGuiFade()
    return renderWindow[0] or renderPlusKillWindow[0] or guiFadeAlpha > 0 or pkFadeAlpha > 0
end

local function plusKillFrameDraw(player)
    if scriptTerminated then return end
    imgui.PushStyleVarFloat(imgui.StyleVar.Alpha, guiFadeAlpha / 200)

    imgui.SetNextWindowSizeConstraints(imgui.ImVec2(770, 0), imgui.ImVec2(770, 4000))

    local window_flags = imgui.WindowFlags.NoTitleBar + imgui.WindowFlags.NoResize + imgui.WindowFlags.NoScrollbar + imgui.WindowFlags.NoScrollWithMouse + imgui.WindowFlags.AlwaysAutoResize
    if imgui.Begin("HUD Stats Compact Wide Panel", renderWindow, window_flags) then
        local p = imgui.GetCursorScreenPos()
        local draw_list = imgui.GetWindowDrawList()
        local titleLineHeight = imgui.GetTextLineHeight()
        draw_list:AddRectFilled(p, imgui.ImVec2(p.x + 4, p.y + titleLineHeight), imgui.GetColorU32Vec4(imgui.ImVec4(0.00, 0.65, 1.00, 1.00)), 2.0)
        
        imgui.Indent(10)
        imgui.TextColored(imgui.ImVec4(0.00, 0.75, 1.00, 1.00), "HUD STATS PANEL")
        imgui.SameLine()
        imgui.TextColored(imgui.ImVec4(0.45, 0.52, 0.60, 1.00), "DEVELOPER " .. script_author)
        imgui.Unindent(10)
        
        local winWidth = imgui.GetWindowWidth()
        local totalPages = math.max(1, math.ceil(#itemsOrder / 12))

        imgui.SetCursorPos(imgui.ImVec2(winWidth - 221, 8))
        if imgui.Button("Back", imgui.ImVec2(55, 22)) and settingsPage > 1 then
            settingsPage = settingsPage - 1
        end
        imgui.SetCursorPos(imgui.ImVec2(winWidth - 158, 8))
        if imgui.Button("Next", imgui.ImVec2(55, 22)) and settingsPage < totalPages then
            settingsPage = settingsPage + 1
        end

        imgui.SetCursorPos(imgui.ImVec2(winWidth - 95, 10))
        drawToggleSwitch("sw_master", cfg_showHUD)
        
        imgui.SetCursorPos(imgui.ImVec2(winWidth - 36, 9))
        local closeClicked, closeHovered = drawCloseButton("close_btn", 20)
        if closeClicked then
            renderWindow[0] = false
        end
        if closeHovered then
            drawEscHintAbove(imgui.GetWindowPos())
        end
        imgui.Separator()

        local child_flags = imgui.WindowFlags.NoScrollbar + imgui.WindowFlags.NoScrollWithMouse
        imgui.Columns(2, "WideGrid", false)
        imgui.SetColumnWidth(0, 375)
        imgui.SetColumnWidth(1, 375)

        local pageStart = (settingsPage - 1) * 12 + 1
        local pageEnd = math.min(pageStart + 11, #itemsOrder)
        local shownCount = 0

        for i, key in ipairs(itemsOrder) do
            if i >= pageStart and i <= pageEnd and cfg_toggles[key] then
                shownCount = shownCount + 1
                imgui.BeginChild("card_" .. key, imgui.ImVec2(365, 38), true, child_flags)
                
                imgui.SetCursorPos(imgui.ImVec2(8, 10))
                imgui.Text(itemLabels[key])
                
                imgui.SetCursorPos(imgui.ImVec2(168, 9))
                if drawIconButton("btn_rev_" .. key, "R", 20, cfg_itemReversed[key][0], "Reverse order (value first)") then
                    cfg_itemReversed[key][0] = not cfg_itemReversed[key][0]
                    saveConfiguration()
                end
                
                imgui.SetCursorPos(imgui.ImVec2(192, 9))
                local mLabel = cfg_itemIndependent[key][0] and "M" or ""
                if drawIconButton("btn_ind_" .. key, mLabel, 20, cfg_itemIndependent[key][0], "Move independently (toggle on/off)") then
                    cfg_itemIndependent[key][0] = not cfg_itemIndependent[key][0]
                    if cfg_itemIndependent[key][0] then
                        lua_thread.create(function() pickItemPosition(key) end)
                    else
                        saveConfiguration()
                    end
                end
                
                imgui.SetCursorPos(imgui.ImVec2(216, 9))
                if drawIconButton("btn_mrg_" .. key, "/", 20, cfg_itemMerge[key][0], "Merge with next item") then
                    cfg_itemMerge[key][0] = not cfg_itemMerge[key][0]
                    saveConfiguration()
                end
                
                imgui.SetCursorPos(imgui.ImVec2(252, 9))
                if drawArrowButton("btn_up_" .. key, "up") and i > 1 then
                    itemsOrder[i], itemsOrder[i - 1] = itemsOrder[i - 1], itemsOrder[i]
                    saveConfiguration()
                end
                
                imgui.SetCursorPos(imgui.ImVec2(276, 9))
                if drawArrowButton("btn_dn_" .. key, "down") and i < #itemsOrder then
                    itemsOrder[i], itemsOrder[i + 1] = itemsOrder[i + 1], itemsOrder[i]
                    saveConfiguration()
                end
                
                imgui.SetCursorPos(imgui.ImVec2(305, 10))
                drawToggleSwitch("sw_" .. key, cfg_toggles[key])
                
                imgui.EndChild()

                if shownCount == 6 then
                    imgui.NextColumn()
                end
            end
        end

        imgui.Columns(1)
        imgui.Separator()

        imgui.BeginChild("PositionContainer", imgui.ImVec2(746, 76), true, child_flags)
        imgui.SetCursorPos(imgui.ImVec2(8, 8))
        imgui.PushItemWidth(480)
        if imgui.SliderInt("Pos X", cfg_posX, 0, 1920) then saveConfiguration() end
        imgui.SetCursorPos(imgui.ImVec2(8, 40))
        if imgui.SliderInt("Pos Y", cfg_posY, 0, 1080) then saveConfiguration() end
        imgui.PopItemWidth()
        imgui.SetCursorPos(imgui.ImVec2(560, 24))
        if imgui.Button("Pick Position On Screen", imgui.ImVec2(155, 28)) then
            lua_thread.create(pickHudPosition)
        end
        imgui.EndChild()

        imgui.BeginChild("ColorsContainer", imgui.ImVec2(746, 44), true, child_flags)
        imgui.SetCursorPos(imgui.ImVec2(8, 10))
        imgui.PushItemWidth(20)
        if imgui.ColorEdit4("##wordColorSwatch", cfg_color, imgui.ColorEditFlags.AlphaBar + imgui.ColorEditFlags.NoInputs) then saveConfiguration() end
        imgui.SameLine(0, 10)
        imgui.Text("Word Color")
        imgui.SameLine(300)
        if imgui.ColorEdit4("##numberColorSwatch", cfg_numberColor, imgui.ColorEditFlags.AlphaBar + imgui.ColorEditFlags.NoInputs) then saveConfiguration() end
        imgui.SameLine(0, 10)
        imgui.Text("Number Color")
        imgui.PopItemWidth()
        imgui.EndChild()

        imgui.BeginChild("FontSizeContainer", imgui.ImVec2(746, 44), true, child_flags)
        imgui.SetCursorPos(imgui.ImVec2(8, 14))
        imgui.Text("Text Size")
        imgui.SetCursorPos(imgui.ImVec2(100, 8))
        if drawSquareButton("fontsize_minus", "-", 28) and cfg_fontSize[0] > 6 then
            cfg_fontSize[0] = cfg_fontSize[0] - 1
            applyFontSize()
            saveConfiguration()
        end
        imgui.SameLine(0, 8)
        drawValueBox(tostring(cfg_fontSize[0]), 46, 28)
        imgui.SameLine(0, 8)
        if drawSquareButton("fontsize_plus", "+", 28) and cfg_fontSize[0] < 30 then
            cfg_fontSize[0] = cfg_fontSize[0] + 1
            applyFontSize()
            saveConfiguration()
        end
        imgui.EndChild()

        imgui.BeginChild("PlusKillContainer", imgui.ImVec2(746, 44), true, child_flags)
        imgui.SetCursorPos(imgui.ImVec2(8, 14))
        imgui.Text("+KILL Effect")
        imgui.SetCursorPos(imgui.ImVec2(300, 13))
        drawToggleSwitch("sw_pluskill", cfg_showPlusKill)
        imgui.SetCursorPos(imgui.ImVec2(360, 10))
        if imgui.Button("SETTINGS", imgui.ImVec2(90, 24)) then
            renderPlusKillWindow[0] = true
        end
        imgui.EndChild()

        imgui.Separator()

        local active_count = getActiveCount()
        imgui.TextColored(imgui.ImVec4(0.45, 0.52, 0.60, 1.00), string.format("ACTIVE ELEMENTS %d / %d", active_count, #itemsOrder))

        local btnGroupWidth = 60 + 8 + 90 + 8 + 60 -- BTN WIDTH
        imgui.SetCursorPosX((winWidth - btnGroupWidth) * 0.5)
        if imgui.Button("SAVE", imgui.ImVec2(60, 24)) then
            saveConfiguration()
            pcall(sampAddChatMessage, "{00FF00}[HUD Stats]{FFFFFF} Settings saved.", -1)
            renderWindow[0] = false
        end
        imgui.SameLine(0, 8)
        imgui.PushStyleColor(imgui.Col.Button, imgui.ImVec4(0.55, 0.35, 0.00, 0.85))
        imgui.PushStyleColor(imgui.Col.ButtonHovered, imgui.ImVec4(0.75, 0.48, 0.00, 1.00))
        imgui.PushStyleColor(imgui.Col.ButtonActive, imgui.ImVec4(0.45, 0.28, 0.00, 1.00))
        if imgui.Button("RESET STATS", imgui.ImVec2(90, 24)) then
            local rOk, rErr = pcall(resetStats)
            if rOk then
                pcall(sampAddChatMessage, "{00FF00}[HUD Stats]{FFFFFF} Stats reset.", -1)
            else
                pcall(sampAddChatMessage, "{FF0000}[HUD Stats] Reset stats error: " .. tostring(rErr), -1)
            end
        end
        imgui.PopStyleColor(3)
        imgui.SameLine(0, 8)
        if imgui.Button("RESET", imgui.ImVec2(60, 24)) then
            local rOk, rErr = pcall(resetConfiguration)
            if rOk then
                pcall(sampAddChatMessage, "{00FF00}[HUD Stats]{FFFFFF} Settings reset.", -1)
            else
                pcall(sampAddChatMessage, "{FF0000}[HUD Stats] Reset error: " .. tostring(rErr), -1)
            end
        end
        
        imgui.End()
    end
    -----------------------------
    --------------------- [ PLUSKILL ] --------------
    if renderPlusKillWindow[0] or pkFadeAlpha > 0 then
        imgui.SetNextWindowSizeConstraints(imgui.ImVec2(420, 0), imgui.ImVec2(420, 4000))
        local pk_flags = imgui.WindowFlags.NoTitleBar + imgui.WindowFlags.NoResize + imgui.WindowFlags.NoScrollbar + imgui.WindowFlags.NoScrollWithMouse + imgui.WindowFlags.AlwaysAutoResize
        local child_flags = imgui.WindowFlags.NoScrollbar + imgui.WindowFlags.NoScrollWithMouse
        imgui.PushStyleVarFloat(imgui.StyleVar.Alpha, pkFadeAlpha / 200)
        if imgui.Begin("PlusKill Settings Panel", renderPlusKillWindow, pk_flags) then
            local p2 = imgui.GetCursorScreenPos()
            local draw_list2 = imgui.GetWindowDrawList()
            local titleLineHeight2 = imgui.GetTextLineHeight()
            draw_list2:AddRectFilled(p2, imgui.ImVec2(p2.x + 4, p2.y + titleLineHeight2), imgui.GetColorU32Vec4(imgui.ImVec4(0.00, 0.65, 1.00, 1.00)), 2.0)

            imgui.Indent(10)
            imgui.TextColored(imgui.ImVec4(0.00, 0.75, 1.00, 1.00), "+KILL SETTINGS")
            imgui.SameLine()
            imgui.TextColored(imgui.ImVec4(0.45, 0.52, 0.60, 1.00), "DEVELOPER " .. script_author)
            imgui.Unindent(10)

            local pkWinWidth = imgui.GetWindowWidth()
            imgui.SetCursorPos(imgui.ImVec2(pkWinWidth - 36, 9))
            local pkCloseClicked, pkCloseHovered = drawCloseButton("pk_close_btn", 20)
            if pkCloseClicked then
                renderPlusKillWindow[0] = false
            end
            if pkCloseHovered then
                drawEscHintAbove(imgui.GetWindowPos())
            end
            imgui.Separator()

            imgui.BeginChild("PkEnableContainer", imgui.ImVec2(396, 40), true, child_flags)
            imgui.SetCursorPos(imgui.ImVec2(8, 11))
            imgui.Text("Enable +KILL")
            imgui.SetCursorPos(imgui.ImVec2(200, 11))
            drawToggleSwitch("sw_pluskill_inner", cfg_showPlusKill)
            imgui.EndChild()

            imgui.BeginChild("PkFormatContainer", imgui.ImVec2(396, 40), true, child_flags)
            imgui.SetCursorPos(imgui.ImVec2(8, 8))
            imgui.PushItemWidth(240)
            if safeComboStr("Format", cfg_plusKillFormat, "Styled String\0Custom Text\0\0", {"Styled String", "Custom Text"}) then
                saveConfiguration()
            end
            imgui.PopItemWidth()
            imgui.EndChild()

            if cfg_plusKillFormat[0] == 0 then
                imgui.BeginChild("PkStyledColorContainer", imgui.ImVec2(396, 40), true, child_flags)
                imgui.SetCursorPos(imgui.ImVec2(8, 8))
                imgui.PushItemWidth(240)
                if safeComboStr("Color", cfg_plusKillColorIndex, "Red\0Green\0Blue\0White\0Yellow\0Purple\0Black\0\0", {"Red", "Green", "Blue", "White", "Yellow", "Purple", "Black"}) then
                    saveConfiguration()
                end
                imgui.PopItemWidth()
                imgui.EndChild()

                imgui.BeginChild("PkStyledDurationContainer", imgui.ImVec2(396, 40), true, child_flags)
                imgui.SetCursorPos(imgui.ImVec2(8, 8))
                imgui.PushItemWidth(240)
                if imgui.SliderFloat("Duration (s)", cfg_plusKillDuration, 0.3, 5.0) then saveConfiguration() end
                imgui.PopItemWidth()
                imgui.EndChild()
            else
                imgui.BeginChild("PkColorContainer", imgui.ImVec2(396, 40), true, child_flags)
                imgui.SetCursorPos(imgui.ImVec2(8, 10))
                if imgui.ColorEdit4("Text Color", cfg_plusKillColor, imgui.ColorEditFlags.AlphaBar + imgui.ColorEditFlags.NoInputs) then saveConfiguration() end
                imgui.EndChild()

                imgui.BeginChild("PkFontSizeContainer", imgui.ImVec2(396, 44), true, child_flags)
                imgui.SetCursorPos(imgui.ImVec2(8, 14))
                imgui.Text("Font Size")
                imgui.SetCursorPos(imgui.ImVec2(100, 8))
                if drawSquareButton("pk_fontsize_minus", "-", 28) and cfg_plusKillFontSize[0] > 10 then
                    cfg_plusKillFontSize[0] = cfg_plusKillFontSize[0] - 1
                    applyPlusKillFont()
                    saveConfiguration()
                end
                imgui.SameLine(0, 8)
                drawValueBox(tostring(cfg_plusKillFontSize[0]), 46, 28)
                imgui.SameLine(0, 8)
                if drawSquareButton("pk_fontsize_plus", "+", 28) and cfg_plusKillFontSize[0] < 100 then
                    cfg_plusKillFontSize[0] = cfg_plusKillFontSize[0] + 1
                    applyPlusKillFont()
                    saveConfiguration()
                end
                imgui.EndChild()

                imgui.BeginChild("PkPositionContainer", imgui.ImVec2(396, 76), true, child_flags)
                imgui.SetCursorPos(imgui.ImVec2(8, 8))
                imgui.PushItemWidth(260)
                if imgui.SliderInt("Pos X", cfg_plusKillPosX, 0, 1920) then saveConfiguration() end
                imgui.SetCursorPos(imgui.ImVec2(8, 40))
                if imgui.SliderInt("Pos Y", cfg_plusKillPosY, 0, 1080) then saveConfiguration() end
                imgui.PopItemWidth()
                imgui.EndChild()

                imgui.BeginChild("PkPickContainer", imgui.ImVec2(396, 40), true, child_flags)
                imgui.SetCursorPos(imgui.ImVec2(8, 8))
                if imgui.Button("Pick Position On Screen", imgui.ImVec2(240, 24)) then
                    lua_thread.create(pickPlusKillPosition)
                end
                imgui.EndChild()

                imgui.BeginChild("PkTimingContainer", imgui.ImVec2(396, 108), true, child_flags)
                imgui.SetCursorPos(imgui.ImVec2(8, 8))
                imgui.PushItemWidth(200)
                if imgui.SliderFloat("Duration before fade", cfg_plusKillDuration, 0.2, 5.0) then saveConfiguration() end
                imgui.SetCursorPos(imgui.ImVec2(8, 40))
                if imgui.SliderFloat("Delay before rise", cfg_plusKillRiseDelay, 0.0, 5.0) then saveConfiguration() end
                imgui.SetCursorPos(imgui.ImVec2(8, 72))
                if imgui.SliderFloat("Rise speed", cfg_plusKillRiseSpeed, 0.0, 3.0) then saveConfiguration() end
                imgui.PopItemWidth()
                imgui.EndChild()

                imgui.BeginChild("PkFadeContainer", imgui.ImVec2(396, 40), true, child_flags)
                imgui.SetCursorPos(imgui.ImVec2(8, 8))
                imgui.PushItemWidth(200)
                if imgui.SliderFloat("Fade speed", cfg_plusKillFadeSpeed, 0.0, 0.2) then saveConfiguration() end
                imgui.PopItemWidth()
                imgui.EndChild()
            end

            imgui.Separator()
            local pkBtnWidth = 90
            imgui.SetCursorPosX((pkWinWidth - pkBtnWidth) * 0.5)
            if imgui.Button("TEST", imgui.ImVec2(pkBtnWidth, 24)) then
                triggerPlusKill()
            end

            imgui.End()
        end
        imgui.PopStyleVar()
    end

    if not escHintShownThisFrame then
        escHintFadeAlpha = 0
    end
    escHintShownThisFrame = false

    imgui.PopStyleVar()
end

imgui.OnFrame(plusKillFrameCondition, function(player)
    local ok, err = pcall(plusKillFrameDraw, player)
    if not ok then print("[HUD Stats] OnFrame render error: " .. tostring(err)) end
end)
-----------------------------
--------------------- [ CLEANUP ] --------------
function onScriptTerminate(scr, quitGame)
    if scr == thisScript() then
        scriptTerminated = true
        renderWindow[0] = false
        cfg_showHUD[0] = false
        guiFadeAlpha = 0
        escHintFadeAlpha = 0
    end
end
-----------------------------
--------------------- [ MAIN ] --------------
function main()
    repeat wait(100) until isSampAvailable()
    
    applyFontSize()
    applyPlusKillFont()

    sampAddChatMessage("{00FF00}[" .. script_name .. "]{FFFFFF} v" .. script_version .. " active{00FFFF}.{FFFFFF} Developed by {00FFFF}" .. script_author .. "{00FFFF}.{FFFFFF} Type {FFFF00}/hudstats{FFFFFF} for menu", -1)

    sampRegisterChatCommand("hudstats", function()
        renderWindow[0] = not renderWindow[0]
    end)
    
    while true do
        wait(0)

        local ok, err = pcall(function()
        frameCount = frameCount + 1
        updateCombatTechniqueTracking()
        local now = os.clock()
        if now - lastFpsTime >= 1.0 then
            currentFPS = frameCount
            frameCount = 0
            lastFpsTime = now
        end
        
        if not isGamePaused() then
        if cfg_showHUD[0] and hudFont then
            local wordColor = joinColor(cfg_color[0], cfg_color[1], cfg_color[2], cfg_color[3])
            local numberColor = joinColor(cfg_numberColor[0], cfg_numberColor[1], cfg_numberColor[2], cfg_numberColor[3])
            local yOffset = cfg_posY[0]
            local lineSpacing = cfg_fontSize[0] + 8

            local i = 1
            while i <= #itemsOrder do
                local key = itemsOrder[i]
                local isIndependent = cfg_itemIndependent[key] and cfg_itemIndependent[key][0]
                if cfg_toggles[key] and cfg_toggles[key][0] and not isIndependent then
                    local rowKeys = {key}
                    local j = i
                    while cfg_itemMerge[rowKeys[#rowKeys]] and cfg_itemMerge[rowKeys[#rowKeys]][0] and j < #itemsOrder do
                        local nextKey = itemsOrder[j + 1]
                        local nextIndependent = cfg_itemIndependent[nextKey] and cfg_itemIndependent[nextKey][0]
                        if cfg_toggles[nextKey] and cfg_toggles[nextKey][0] and not nextIndependent then
                            table.insert(rowKeys, nextKey)
                        end
                        j = j + 1
                    end
                    i = j + 1

                    local drawX = cfg_posX[0]
                    local drewAny = false
                    for _, rk in ipairs(rowKeys) do
                        local label, value = getItemLabelValue(rk)
                        if label then
                            if drewAny then
                                renderFontDrawText(hudFont, " / ", drawX, yOffset, wordColor)
                                drawX = drawX + renderGetFontDrawTextLength(hudFont, " / ")
                            end
                            local reversed = cfg_itemReversed[rk] and cfg_itemReversed[rk][0]
                            drawX = drawX + drawStatPart(hudFont, label, value, reversed, drawX, yOffset, wordColor, numberColor)
                            drewAny = true
                        end
                    end
                    if drewAny then
                        yOffset = yOffset + lineSpacing
                    end
                else
                    i = i + 1
                end
            end

            for _, key in ipairs(itemsOrder) do
                if cfg_toggles[key] and cfg_toggles[key][0] and cfg_itemIndependent[key] and cfg_itemIndependent[key][0] then
                    local label, value = getItemLabelValue(key)
                    if label then
                        local reversed = cfg_itemReversed[key] and cfg_itemReversed[key][0]
                        drawStatPart(hudFont, label, value, reversed, cfg_itemPosX[key][0], cfg_itemPosY[key][0], wordColor, numberColor)
                    end
                end
            end
        end

        -- CUSTOM DRAW
        if cfg_showPlusKill[0] and plusKillActive and plusKillFont then
            if plusKillFirst then
                plusKillDrawY = cfg_plusKillPosY[0]
                plusKillAlpha = 1.0
                plusKillTimeStart = os.clock()
                plusKillFirst = false
            end

            local plusKillCol = joinColor(cfg_plusKillColor[0], cfg_plusKillColor[1], cfg_plusKillColor[2], plusKillAlpha)
            renderFontDrawText(plusKillFont, "+KILL", cfg_plusKillPosX[0], plusKillDrawY, plusKillCol)

            if os.clock() - plusKillTimeStart >= cfg_plusKillRiseDelay[0] then
                plusKillDrawY = plusKillDrawY - cfg_plusKillRiseSpeed[0]
            end

            if os.clock() - plusKillTimeStart >= cfg_plusKillDuration[0] then
                if cfg_plusKillFadeSpeed[0] > 0 then
                    plusKillAlpha = plusKillAlpha - cfg_plusKillFadeSpeed[0]
                    if plusKillAlpha <= 0 then
                        plusKillAlpha = 0
                        plusKillActive = false
                    end
                else
                    plusKillActive = false
                end
            end
        end

        end
        end)
        if not ok then print("[HUD Stats] main loop error: " .. tostring(err)) end
    end
end
-----------------------------
--------------------- [ END ] --------------
-----------------------------