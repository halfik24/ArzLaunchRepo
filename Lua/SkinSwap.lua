script_name('SkinSwap')
local imgui = require('mimgui')
local encoding = require('encoding')
encoding.default = 'UTF-8'
local u8 = encoding.UTF8
local events = require('samp.events')
local inicfg = require('inicfg')

math.randomseed(os.time())

local configName = 'SkinSwap/config'
local mappingsName = 'SkinSwap/mappings'
local cacheName = 'SkinSwap/random_cache'
local whitelistName = 'SkinSwap/whitelist'

local defaultConfig = {
    main = {
        enabled = true,
        replaceCustom = true,
        replaceStandard = false,
        protectLocal = false,
        mode = 0,
        fixedSkin = 74
    }
}

local defaultMappings = {
    mappings = {}
}

local defaultCache = {
    random = {}
}

local cfg = inicfg.load(defaultConfig, configName)
local mappings = inicfg.load(defaultMappings, mappingsName)
local randomCache = inicfg.load(defaultCache, cacheName)

inicfg.save(cfg, configName)
inicfg.save(mappings, mappingsName)
inicfg.save(randomCache, cacheName)

local window = imgui.new.bool(false)

local enabled = imgui.new.bool(cfg.main.enabled)
local replaceCustom = imgui.new.bool(cfg.main.replaceCustom)
local replaceStandard = imgui.new.bool(cfg.main.replaceStandard)
local protectLocal = imgui.new.bool(cfg.main.protectLocal)

local selectedMode = imgui.new.int(cfg.main.mode)
local fixedSkin = imgui.new.int(cfg.main.fixedSkin)

local addFromSkin = imgui.new.int(0)
local addToSkin = imgui.new.int(74)

local debugInfo = {}

local modeNames = {
    'CJ (74)',
    'Случайные',
    'Фиксированный ID',
    'Ручные замены'
}

function saveConfig()
    cfg.main.enabled = enabled[0]
    cfg.main.replaceCustom = replaceCustom[0]
    cfg.main.replaceStandard = replaceStandard[0]
    cfg.main.protectLocal = protectLocal[0]
    cfg.main.mode = selectedMode[0]
    cfg.main.fixedSkin = fixedSkin[0]

    pcall(function()
        inicfg.save(cfg, configName)
    end)
end

function saveMappings()
    pcall(function()
        inicfg.save(mappings, mappingsName)
    end)
end

function saveRandomCache()

    local clean = {}

    for k, v in pairs(randomCache.random) do
        clean[tostring(k)] = tonumber(v)
    end

    randomCache.random = clean

    pcall(function()
        inicfg.save(randomCache, cacheName)
    end)

end

function clearRandomCache()
    randomCache.random = {}
    saveRandomCache()
end

function isLocalPlayer(id)
    local result, myId = sampGetPlayerIdByCharHandle(PLAYER_PED)
    return result and myId == id
end

function shouldReplaceSkin(skin)
    if skin > 311 then
        return replaceCustom[0]
    end

    return replaceStandard[0]
end

local defaultWhitelist = {
    list = {}
}

local whitelist = inicfg.load(defaultWhitelist, whitelistName)
inicfg.save(whitelist, whitelistName)

local function isWhitelisted(skin)
    return whitelist.list[skin]
        or whitelist.list[tostring(skin)]
        or whitelist.list[tonumber(skin)]
        or tostring(whitelist.list[tostring(skin)]) == 'true'
        or tostring(whitelist.list[tonumber(skin)]) == 'true'
end

local function normKey(v)
    return tostring(v)
end

function getRandomSkinFor(originalSkin)

    local key = tostring(originalSkin)

    if randomCache.random[key] then
        return tonumber(randomCache.random[key])
    end

    local randomSkin = math.random(1, 311)

    randomCache.random[key] = randomSkin

    return randomSkin
end

function getReplacementSkin(originalSkin)

    originalSkin = tonumber(originalSkin)

    if isWhitelisted(originalSkin) then
        return originalSkin
    end

    if not shouldReplaceSkin(originalSkin) then
        return originalSkin
    end

    local mode = selectedMode[0]

    if mode == 0 then
        return 74
    end

    if mode == 1 then
        return getRandomSkinFor(originalSkin)
    end

    if mode == 2 then
        if fixedSkin[0] < 1 then fixedSkin[0] = 1 end
        if fixedSkin[0] > 311 then fixedSkin[0] = 311 end
        return fixedSkin[0]
    end

    if mode == 3 then

        local key = tostring(originalSkin)

        if mappings.mappings[key] then
            return tonumber(mappings.mappings[key])
        end

        if originalSkin > 311 then
            return getRandomSkinFor(originalSkin)
        end

        return getRandomSkinFor(originalSkin)
    end

    return originalSkin
end

function events.onPlayerStreamIn(id, team, model, position, rotation, color, fightingStyle)

    if not enabled[0] then
        return
    end

    if protectLocal[0] and isLocalPlayer(id) then
        return
    end

    if isWhitelisted(model) then
        return
    end

    local newSkin = getReplacementSkin(model)

    table.insert(debugInfo, {
        id = id,
        original = model,
        replaced = newSkin
    })

    if #debugInfo > 100 then
        table.remove(debugInfo, 1)
    end

    if newSkin ~= model then
        return {
            id,
            team,
            newSkin,
            position,
            rotation,
            color,
            fightingStyle
        }
    end

end

function events.onSetPlayerSkin(id, skin)

    if not enabled[0] then
        return
    end

    if protectLocal[0] and isLocalPlayer(id) then
        return
    end

    if isWhitelisted(skin) then
        return
    end

    local newSkin = getReplacementSkin(skin)

    table.insert(debugInfo, {
        id = id,
        original = skin,
        replaced = newSkin
    })

    if #debugInfo > 100 then
        table.remove(debugInfo, 1)
    end

    if newSkin ~= skin then
        return {
            id,
            newSkin
        }
    end

end

function main()

    repeat
        wait(0)
    until isSampAvailable()

    sampRegisterChatCommand('skinswap', function()
        window[0] = not window[0]
    end)

    local lastSave = os.clock()

    while true do
        wait(1000)

        if os.clock() - lastSave > 10 then
            saveRandomCache()
            lastSave = os.clock()
        end
    end

end

imgui.OnInitialize(function()

    imgui.GetIO().IniFilename = nil
    imgui.SwitchContext()

    local style = imgui.GetStyle()
    local colors = style.Colors

    colors[imgui.Col.WindowBg]        = imgui.ImVec4(0.06, 0.08, 0.12, 1.00)
    colors[imgui.Col.TitleBg]         = imgui.ImVec4(0.08, 0.10, 0.16, 1.00)
    colors[imgui.Col.TitleBgActive]   = imgui.ImVec4(0.10, 0.14, 0.22, 1.00)

    colors[imgui.Col.FrameBg]         = imgui.ImVec4(0.08, 0.12, 0.18, 1.00)
    colors[imgui.Col.FrameBgHovered]  = imgui.ImVec4(0.12, 0.18, 0.28, 1.00)
    colors[imgui.Col.FrameBgActive]   = imgui.ImVec4(0.14, 0.22, 0.34, 1.00)

    colors[imgui.Col.Button]          = imgui.ImVec4(0.10, 0.16, 0.26, 1.00)
    colors[imgui.Col.ButtonHovered]   = imgui.ImVec4(0.16, 0.28, 0.45, 1.00)
    colors[imgui.Col.ButtonActive]    = imgui.ImVec4(0.20, 0.36, 0.58, 1.00)

    colors[imgui.Col.Text]            = imgui.ImVec4(0.80, 0.92, 1.00, 1.00)
    colors[imgui.Col.Border]          = imgui.ImVec4(0.12, 0.20, 0.32, 1.00)

    local io = imgui.GetIO()
    io.Fonts:Clear()

    local ranges = io.Fonts:GetGlyphRangesCyrillic()

    main_font = io.Fonts:AddFontFromFileTTF(
        getFolderPath(0x14)..'\\tahomabd.ttf',
        14.0,
        nil,
        ranges
    )

    io.Fonts:Build()
    imgui.InvalidateFontsTexture()

    assert(main_font, "Font load failed")

end)

imgui.OnFrame(
function() return window[0] end,
function()

    if main_font == nil then return end

    imgui.PushFont(main_font)

    imgui.SetNextWindowSize(imgui.ImVec2(750, 500), imgui.Cond.FirstUseEver)

    imgui.Begin(u8'SkinSwap', window)

    if imgui.BeginTabBar('##tabs') then

        if imgui.BeginTabItem(u8'Основное') then

            imgui.Text(u8'SkinSwap - система замены скинов SA:MP')
            imgui.Text(u8'Режимы работают по приоритету: WhiteList > Ручные замены > Случайные')
            imgui.Text(u8'Кэш случайной замены сохраняет стабильные замены для одних и тех же ID')
            imgui.Separator()

            if imgui.Checkbox(u8'Включить SkinSwap', enabled) then
                saveConfig()
            end

            if imgui.Checkbox(u8'Заменять кастомные скины (> 311)', replaceCustom) then
                saveConfig()
            end

            if imgui.Checkbox(u8'Заменять стандартные скины (1-311)', replaceStandard) then
                saveConfig()
            end

            if imgui.Checkbox(u8'Защита локального игрока', protectLocal) then
                saveConfig()
            end

            imgui.Separator()

            imgui.Text(u8'Режим замены')

            for i = 0, 3 do

                local selected = (selectedMode[0] == i)

                if selected then
                    imgui.PushStyleColor(
                        imgui.Col.Button,
                        imgui.ImVec4(0.20, 0.40, 0.70, 1.00)
                    )
                end

                if imgui.Button(u8(modeNames[i + 1])) then
                    selectedMode[0] = i
                end

                if selected then
                    imgui.PopStyleColor()
                end

                if i < 3 then
                    imgui.SameLine()
                end
            end

            if selectedMode[0] == 2 then

                imgui.Text(u8'ID скина')

                if imgui.InputInt('##fixedSkin', fixedSkin) then

                    if fixedSkin[0] < 1 then
                        fixedSkin[0] = 1
                    end

                    if fixedSkin[0] > 311 then
                        fixedSkin[0] = 311
                    end

                    saveConfig()

                end

            end

            imgui.EndTabItem()

        end

        if imgui.BeginTabItem(u8'Ручные замены') then

            imgui.InputInt(u8'Исходный ID', addFromSkin)
            imgui.InputInt(u8'Новый ID', addToSkin)

            if imgui.Button(u8'Добавить правило') then

                if addToSkin[0] >= 1 and addToSkin[0] <= 311 then

                    local key = tostring(tonumber(addFromSkin[0]))
                    mappings.mappings[key] = addToSkin[0]

                    saveMappings()

                end

            end

            imgui.Separator()

            local safeMappings = {}

            for k, v in pairs(mappings.mappings) do
                safeMappings[k] = v
            end

            for k, v in pairs(safeMappings) do
                imgui.Text(u8(k .. ' -> ' .. tostring(v)))

                imgui.SameLine()

                local toDelete = nil

                if imgui.SmallButton(u8('Удалить##' .. k)) then
                    toDelete = k
                end

                if toDelete then
                    mappings.mappings[toDelete] = nil
                    saveMappings()
                end
            end

            imgui.EndTabItem()

        end

        if imgui.BeginTabItem(u8'Кэш') then

            imgui.Text(u8'Кэш хранит случайные замены.')
            imgui.Text(u8'Один и тот же исходный ID всегда получает один и тот же случайный скин.')
            imgui.Text(u8'Кэш автоматически сохраняется каждые 10 секунд.')
            imgui.Text(u8'Файл: random_cache.ini')

            imgui.Separator()

            local count = 0
            for _ in pairs(randomCache.random) do
                count = count + 1
            end

            imgui.Text(u8('Количество записей: '..count))

            imgui.Separator()

            if imgui.Button(u8'Очистить кэш случайных замен') then
                clearRandomCache()
            end

            imgui.Separator()

            for k, v in pairs(randomCache.random) do
                imgui.Text(u8(k .. ' -> ' .. tostring(v)))
            end

            imgui.EndTabItem()
        end

        if imgui.BeginTabItem(u8'Whitelist') then

            imgui.Text(u8'Скины, которые НЕ будут заменяться')

            imgui.InputInt(u8'ID скина', addFromSkin)

            if imgui.Button(u8'Добавить в whitelist') then
                addWhitelist(addFromSkin[0])
            end

            imgui.SameLine()

            if imgui.Button(u8'Удалить из whitelist') then
                removeWhitelist(addFromSkin[0])
            end

            imgui.Separator()

            for k, _ in pairs(whitelist.list) do
                imgui.Text(u8('Защищенный скин: ' .. k))
            end

            imgui.EndTabItem()
        end

        if imgui.BeginTabItem(u8'Отладка') then

            imgui.Text(u8'Последние замены (новые сверху)')
            imgui.Separator()

            if imgui.Button(u8'Очистить журнал') then
                debugInfo = {}
            end

            imgui.Separator()

            local maxShow = 25
            local count = 0

            for i = #debugInfo, 1, -1 do
                local data = debugInfo[i]

                imgui.Text(string.format(
                    '%d) ID игрока: %d | Исходный ID: %d -> Замененный ID: %d',
                    i,
                    data.id,
                    data.original,
                    data.replaced
                ))

                count = count + 1
                if count >= maxShow then break end
            end

            imgui.EndTabItem()
        end

        imgui.EndTabBar()

    end

    imgui.End()

    imgui.PopFont()

end)

function getStreamedPlayers()
    local result = {}

    for i = 0, 1000 do
        if sampIsPlayerConnected(i) then
            local res, ped = sampGetCharHandleBySampPlayerId(i)
            if res then
                table.insert(result, i)
            end
        end
    end

    return result
end

function deleteAllStreamedPeds()
    for i = 0, 1000 do
        if sampIsPlayerConnected(i) then
            local res, ped = sampGetCharHandleBySampPlayerId(i)

            if res then
                deleteChar(ped)
                markCharAsNoLongerNeeded(ped)
            end
        end
    end
end

function forceStreamRefresh()
    lua_thread.create(function()
        deleteAllStreamedPeds()
        wait(100)
        deleteAllStreamedPeds()
    end)
end

function resetMappings()

    mappings.mappings = {}
    saveMappings()

end

function addMapping(fromSkin, toSkin)

    fromSkin = tonumber(fromSkin)
    toSkin = tonumber(toSkin)

    if not fromSkin or not toSkin then
        return false
    end

    if toSkin < 1 or toSkin > 311 then
        return false
    end

    mappings.mappings[tostring(fromSkin)] = toSkin
    saveMappings()

    return true

end

function removeMapping(fromSkin)

    fromSkin = tostring(fromSkin)

    if mappings.mappings[fromSkin] then

        mappings.mappings[fromSkin] = nil
        saveMappings()

        return true

    end

    return false

end

function clearDebugInfo()

    debugInfo = {}

end

function addWhitelist(skin)
    skin = tonumber(skin)
    if not skin then return false end

    whitelist.list[skin] = true

    saveWhitelist()

    return true
end

function removeWhitelist(skin)
    skin = tonumber(skin)
    whitelist.list[skin] = nil
    whitelist.list[tostring(skin)] = nil
    saveWhitelist()
end

function saveWhitelist()

    local clean = {}

    for k, v in pairs(whitelist.list) do
        clean[tostring(k)] = true
    end

    whitelist.list = clean

    pcall(function()
        inicfg.save(whitelist, whitelistName)
    end)

end

function resetEverything()

    mappings.mappings = {}
    randomCache.random = {}
    whitelist.list = {}
    debugInfo = {}

    saveMappings()
    saveRandomCache()
    saveWhitelist()

end

function reloadSettings()

    cfg = inicfg.load(defaultConfig, configName)
    mappings = inicfg.load(defaultMappings, mappingsName)
    randomCache = inicfg.load(defaultCache, cacheName)
    whitelist = inicfg.load(defaultWhitelist, whitelistName)

end

function onScriptTerminate(script)

    if script == thisScript() then

        saveConfig()
        saveMappings()
        saveRandomCache()
        saveWhitelist()

    end

end