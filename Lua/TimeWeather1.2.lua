script_name('TimeWeather')
script_author('Mipiv')
script_version('1.2')

local imgui = require 'mimgui'
local encoding = require 'encoding'
local vkeys = require 'vkeys'
local ffi = require 'ffi'

encoding.default = 'CP1251'

local u8 = encoding.UTF8
local new = imgui.new


-- =========================================================
-- OPTIONAL SAMP EVENTS
-- =========================================================

local sampev = nil
local hasSampEvents = false

do
    local ok, lib = pcall(
        require,
        'lib.samp.events'
    )

    if not ok then
        ok, lib = pcall(
            require,
            'samp.events'
        )
    end

    if ok and lib then
        sampev = lib
        hasSampEvents = true
    end
end


-- =========================================================
-- UI
-- =========================================================

local ui = {
    opened = false,
    alpha = 0.0,

    configsOpened = false,
    configsAlpha = 0.0,

    time = new.int(0),
    weather = new.int(0),

    appliedTime = 0,
    appliedWeather = 0,

    timeChanged = false,
    weatherChanged = false
}


-- =========================================================
-- SETTINGS
-- =========================================================

local settings = {
    smoothTime = new.bool(false),
    smoothWeather = new.bool(false),
    serverProtection = new.bool(false)
}


-- =========================================================
-- CONFIGS
-- =========================================================

local configs = {}

local selectedConfig = new.int(-1)
local autoApply = new.bool(false)

local nameBuffer = new.char[64]()


-- =========================================================
-- POPUPS
-- =========================================================

local namePopupRequest = false
local namePopupActive = false
local namePopupMode = 'create'

local deletePopupRequest = false
local deletePopupActive = false

local overwritePopupRequest = false
local overwritePopupActive = false

local settingsPopupRequest = false
local settingsPopupActive = false

local focusNameInput = false
local nameErrorText = ''

local closePopupRequest = false


-- =========================================================
-- ORIGINAL VALUES
-- =========================================================

local originalTimeHour = nil
local originalTimeMinute = nil
local originalWeather = nil


-- =========================================================
-- SMOOTH TRANSITIONS
-- =========================================================

local transition = {
    timeActive = false,

    timeStartTick = 0,
    timeDuration = 1800,

    timeFromMinutes = 0,
    timeDifference = 0,

    weatherTransitionUntil = 0
}


-- =========================================================
-- SERVER PROTECTION
-- =========================================================

local protectionReapplyAt = 0
local lastFallbackProtectionCheck = 0


-- =========================================================
-- RESET
-- =========================================================

local resetSyncPending = false
local resetSyncAt = 0


-- =========================================================
-- FONTS
-- =========================================================

local fontMain = nil
local fontTitle = nil
local fontClock = nil
local fontDate = nil


-- =========================================================
-- WINDOW SIZE
-- =========================================================

local MAIN_W = 430
local MAIN_H = 350

local CONFIG_W = 310
local CONFIG_H = 390


-- =========================================================
-- PATHS
-- =========================================================

local workDir = getWorkingDirectory()

local configRoot =
    workDir .. '\\config'

local configDir =
    configRoot .. '\\TimeWeather'

local configsFile =
    configDir .. '\\configs.dat'

local layoutFile =
    configDir .. '\\layout.dat'

local settingsFile =
    configDir .. '\\settings.dat'


-- =========================================================
-- POPUP NAMES
-- =========================================================

local namePopupName =
    'Конфиг##TW_Name'

local deletePopupName =
    'Удаление конфига##TW_Delete'

local overwritePopupName =
    'Перезапись конфига##TW_Overwrite'

local settingsPopupName =
    'Настройки##TW_Settings'


-- =========================================================
-- DATE MONTHS
-- =========================================================

local russianMonths = {
    'января',
    'февраля',
    'марта',
    'апреля',
    'мая',
    'июня',
    'июля',
    'августа',
    'сентября',
    'октября',
    'ноября',
    'декабря'
}


local function getDateText()

    local day =
        tonumber(
            os.date('%d')
        ) or 1

    local month =
        tonumber(
            os.date('%m')
        ) or 1

    return tostring(day)
        .. ' '
        .. (
            russianMonths[month]
            or ''
        )

end


-- =========================================================
-- LAYOUT
-- =========================================================

local layout = {
    mainX = -1,
    mainY = -1,

    configX = -1,
    configY = -1
}

local layoutDirty = false
local lastLayoutSave = 0


-- =========================================================
-- CHAT
-- =========================================================

local function chat(text, colorValue)

    sampAddChatMessage(
        u8:decode(text),
        colorValue or -1
    )

end


-- =========================================================
-- RGBA
-- =========================================================

local function rgba(r, g, b, a)

    r = math.floor(
        math.max(
            0,
            math.min(255, r)
        )
    )

    g = math.floor(
        math.max(
            0,
            math.min(255, g)
        )
    )

    b = math.floor(
        math.max(
            0,
            math.min(255, b)
        )
    )

    a = math.floor(
        math.max(
            0,
            math.min(255, a)
        )
    )

    return r
        + g * 0x100
        + b * 0x10000
        + a * 0x1000000

end


-- =========================================================
-- STRING HELPERS
-- =========================================================

local function trim(value)

    return tostring(
        value or ''
    ):match(
        '^%s*(.-)%s*$'
    )

end


local function cleanName(value)

    value =
        trim(value)

    value =
        value:gsub(
            '[\r\n\t]',
            ' '
        )

    return value

end


local function boolToString(value)

    return value
        and '1'
        or '0'

end


-- =========================================================
-- DIRECTORIES
-- =========================================================

local function ensureDirectories()

    if not doesDirectoryExist(
        configRoot
    ) then

        createDirectory(
            configRoot
        )

    end

    if not doesDirectoryExist(
        configDir
    ) then

        createDirectory(
            configDir
        )

    end

end


-- =========================================================
-- LAYOUT
-- =========================================================

local function saveLayout()

    ensureDirectories()

    local file =
        io.open(
            layoutFile,
            'w'
        )

    if not file then
        return
    end

    file:write(
        string.format(
            '%.2f\n%.2f\n%.2f\n%.2f\n',
            layout.mainX,
            layout.mainY,
            layout.configX,
            layout.configY
        )
    )

    file:close()

    layoutDirty =
        false

    lastLayoutSave =
        getGameTimer()

end


local function loadLayout()

    ensureDirectories()

    local file =
        io.open(
            layoutFile,
            'r'
        )

    if not file then
        return
    end

    local values = {}

    for line in file:lines() do

        values[
            #values + 1
        ] =
            tonumber(line)

    end

    file:close()

    if #values >= 4 then

        layout.mainX =
            values[1] or -1

        layout.mainY =
            values[2] or -1

        layout.configX =
            values[3] or -1

        layout.configY =
            values[4] or -1

    end

end


local function updateWindowPosition(kind)

    local pos =
        imgui.GetWindowPos()

    local oldX
    local oldY

    if kind == 'main' then

        oldX =
            layout.mainX

        oldY =
            layout.mainY

    else

        oldX =
            layout.configX

        oldY =
            layout.configY

    end

    if oldX < 0
    or oldY < 0
    or math.abs(
        pos.x - oldX
    ) > 0.5
    or math.abs(
        pos.y - oldY
    ) > 0.5 then

        if kind == 'main' then

            layout.mainX =
                pos.x

            layout.mainY =
                pos.y

        else

            layout.configX =
                pos.x

            layout.configY =
                pos.y

        end

        layoutDirty =
            true

    end

end


-- =========================================================
-- CONFIG FIELD
-- =========================================================

local function escapeField(text)

    return tostring(
        text or ''
    )
        :gsub(
            '\\',
            '\\\\'
        )
        :gsub(
            '\t',
            '\\t'
        )
        :gsub(
            '\r',
            '\\r'
        )
        :gsub(
            '\n',
            '\\n'
        )

end


local function unescapeField(text)

    return tostring(
        text or ''
    ):gsub(
        '\\(.)',

        function(char)

            if char == 't' then
                return '\t'
            end

            if char == 'r' then
                return '\r'
            end

            if char == 'n' then
                return '\n'
            end

            return char

        end
    )

end


-- =========================================================
-- SETTINGS
-- =========================================================

local function saveSettings()

    ensureDirectories()

    local file =
        io.open(
            settingsFile,
            'wb'
        )

    if not file then
        return
    end

    file:write(
        'TimeWeatherSettings12\n'
    )

    file:write(
        'smoothTime='
        .. boolToString(
            settings.smoothTime[0]
        )
        .. '\n'
    )

    file:write(
        'smoothWeather='
        .. boolToString(
            settings.smoothWeather[0]
        )
        .. '\n'
    )

    file:write(
        'serverProtection='
        .. boolToString(
            settings.serverProtection[0]
        )
        .. '\n'
    )

    file:close()

end


local function loadSettings()

    ensureDirectories()

    local file =
        io.open(
            settingsFile,
            'rb'
        )

    if not file then
        return
    end

    local header =
        file:read('*l')

    if header
    ~= 'TimeWeatherSettings12' then

        file:close()
        return

    end

    for line in file:lines() do

        local key, value =
            line:match(
                '^([^=]+)=(.*)$'
            )

        if key then

            if key
            == 'smoothTime' then

                settings.smoothTime[0] =
                    value == '1'

            elseif key
            == 'smoothWeather' then

                settings.smoothWeather[0] =
                    value == '1'

            elseif key
            == 'serverProtection' then

                settings.serverProtection[0] =
                    value == '1'

            end

        end

    end

    file:close()

end


-- =========================================================
-- CONFIGS
-- =========================================================

local function saveConfigs()

    ensureDirectories()

    local file =
        io.open(
            configsFile,
            'wb'
        )

    if not file then
        return
    end

    file:write(
        'TimeWeatherConfig13\n'
    )

    for i = 1, #configs do

        local cfg =
            configs[i]

        file:write(

            escapeField(
                cfg.name
            ),

            '\t',

            tostring(
                cfg.time or 0
            ),

            '\t',

            tostring(
                cfg.weather or 0
            ),

            '\t',

            boolToString(
                cfg.autoApply == true
            ),

            '\t',

            boolToString(
                cfg.smoothTime == true
            ),

            '\t',

            boolToString(
                cfg.smoothWeather == true
            ),

            '\t',

            boolToString(
                cfg.serverProtection == true
            ),

            '\n'
        )

    end

    file:close()

end


local function loadConfigs()

    configs = {}

    ensureDirectories()

    local file =
        io.open(
            configsFile,
            'rb'
        )

    if not file then
        return
    end

    local header =
        file:read('*l')

    local foundAutoApply =
        false

    for line in file:lines() do

        local fields = {}

        for field in (
            line .. '\t'
        ):gmatch(
            '(.-)\t'
        ) do

            fields[
                #fields + 1
            ] = field

        end

        local cfg = nil


        if header
        == 'TimeWeatherConfig13'
        and #fields >= 7 then

            cfg = {

                name =
                    unescapeField(
                        fields[1]
                    ),

                time =
                    tonumber(
                        fields[2]
                    ) or 0,

                weather =
                    tonumber(
                        fields[3]
                    ) or 0,

                autoApply =
                    fields[4] == '1',

                smoothTime =
                    fields[5] == '1',

                smoothWeather =
                    fields[6] == '1',

                serverProtection =
                    fields[7] == '1'
            }


        elseif header
        == 'TimeWeatherConfig12'
        and #fields >= 4 then

            cfg = {

                name =
                    unescapeField(
                        fields[1]
                    ),

                time =
                    tonumber(
                        fields[2]
                    ) or 0,

                weather =
                    tonumber(
                        fields[3]
                    ) or 0,

                autoApply =
                    fields[4] == '1',

                smoothTime =
                    settings.smoothTime[0],

                smoothWeather =
                    settings.smoothWeather[0],

                serverProtection =
                    settings.serverProtection[0]
            }

        end


        if cfg then

            cfg.time =
                math.max(
                    0,
                    math.min(
                        23,
                        math.floor(
                            cfg.time
                        )
                    )
                )

            cfg.weather =
                math.max(
                    0,
                    math.min(
                        255,
                        math.floor(
                            cfg.weather
                        )
                    )
                )


            if cfg.autoApply then

                if foundAutoApply then

                    cfg.autoApply =
                        false

                else

                    foundAutoApply =
                        true

                end

            end


            configs[
                #configs + 1
            ] = cfg

        end

    end

    file:close()

end


-- =========================================================
-- CURRENT WEATHER
-- =========================================================

local function getCurrentWeatherId()

    local success, value =
        pcall(

            function()

                return readMemory(
                    0xC81320,
                    2,
                    false
                )

            end
        )

    if not success
    or value == nil then

        return tonumber(
            ui.weather[0]
        ) or 0

    end

    value =
        tonumber(value) or 0

    value =
        math.floor(value)

    if value < 0 then
        value = 0
    end

    if value > 255 then
        value = 255
    end

    return value

end


-- =========================================================
-- GREETING
-- =========================================================

local function greeting()

    local hour =
        tonumber(
            os.date('%H')
        )

    if hour >= 5
    and hour < 12 then

        return 'Доброе утро'

    elseif hour >= 12
    and hour < 18 then

        return 'Добрый день'

    elseif hour >= 18
    and hour < 23 then

        return 'Добрый вечер'

    end

    return 'Доброй ночи'

end


local function nickname()

    local result, id =
        sampGetPlayerIdByCharHandle(
            PLAYER_PED
        )

    if result then

        return sampGetPlayerNickname(
            id
        )

    end

    return 'Игрок'

end


-- =========================================================
-- ORIGINAL STATE
-- =========================================================

local function rememberOriginalTime()

    if originalTimeHour ~= nil then
        return
    end

    originalTimeHour,
    originalTimeMinute =
        getTimeOfDay()

end


local function rememberOriginalWeather()

    if originalWeather ~= nil then
        return
    end

    originalWeather =
        getCurrentWeatherId()

end


-- =========================================================
-- TIME MEMORY LOCK
-- =========================================================

local function lockAppliedTimeMemory()

    if not ui.timeChanged then
        return
    end

    if transition.timeActive then
        return
    end

    pcall(
        function()

            writeMemory(
                0xB70150,
                2,
                0,
                false
            )

            writeMemory(
                0xB70152,
                1,
                0,
                false
            )

            writeMemory(
                0xB70153,
                1,
                ui.appliedTime,
                false
            )

        end
    )

end


-- =========================================================
-- SMOOTH TIME
-- =========================================================

local function startSmoothTime(
    targetHour
)

    rememberOriginalTime()

    local hour, minute =
        getTimeOfDay()

    local currentMinutes =
        hour * 60
        + minute

    local targetMinutes =
        targetHour * 60

    local difference =
        targetMinutes
        - currentMinutes


    if difference > 720 then

        difference =
            difference - 1440

    elseif difference < -720 then

        difference =
            difference + 1440

    end


    ui.appliedTime =
        targetHour

    ui.timeChanged =
        true


    if difference == 0 then

        transition.timeActive =
            false

        setTimeOfDay(
            targetHour,
            0
        )

        return

    end


    transition.timeFromMinutes =
        currentMinutes

    transition.timeDifference =
        difference

    transition.timeStartTick =
        getGameTimer()

    transition.timeActive =
        true

end


local function updateSmoothTime()

    if not transition.timeActive then
        return
    end

    local now =
        getGameTimer()

    local elapsed =
        now
        - transition.timeStartTick

    local progress =
        elapsed
        / transition.timeDuration


    if progress >= 1.0 then

        transition.timeActive =
            false

        setTimeOfDay(
            ui.appliedTime,
            0
        )

        return

    end


    if progress < 0 then
        progress = 0
    end


    local smooth =
        progress
        * progress
        * (
            3.0
            - 2.0 * progress
        )


    local minutes =
        transition.timeFromMinutes
        + transition.timeDifference
        * smooth


    minutes =
        math.floor(
            minutes + 0.5
        )


    while minutes < 0 do

        minutes =
            minutes + 1440

    end


    while minutes >= 1440 do

        minutes =
            minutes - 1440

    end


    local hour =
        math.floor(
            minutes / 60
        )

    local minute =
        minutes % 60


    setTimeOfDay(
        hour,
        minute
    )

end


-- =========================================================
-- APPLY TIME
-- =========================================================

local function applyTime(value)

    value =
        tonumber(value)

    if not value then
        return false
    end


    value =
        math.floor(value)


    if value < 0
    or value > 24 then
        return false
    end


    if value == 24 then
        value = 0
    end


    rememberOriginalTime()


    ui.appliedTime =
        value

    ui.timeChanged =
        true


    if settings.smoothTime[0] then

        startSmoothTime(value)

    else

        transition.timeActive =
            false

        setTimeOfDay(
            value,
            0
        )

    end


    return true

end


-- =========================================================
-- APPLY WEATHER
-- =========================================================

local function applyWeather(value)

    value =
        tonumber(value)

    if not value then
        return false
    end


    value =
        math.floor(value)


    if value < 0
    or value > 255 then
        return false
    end


    rememberOriginalWeather()


    ui.appliedWeather =
        value

    ui.weatherChanged =
        true


    if settings.smoothWeather[0] then

        forceWeather(value)

        transition.weatherTransitionUntil =
            getGameTimer()
            + 10000

    else

        forceWeatherNow(value)

        transition.weatherTransitionUntil =
            0

    end


    return true

end


-- =========================================================
-- PROTECTION
-- =========================================================

local function scheduleProtectionRestore(delay)

    if not settings.serverProtection[0] then
        return
    end

    protectionReapplyAt =
        getGameTimer()
        + (
            delay or 700
        )

end


local function restoreProtectedState()

    if not settings.serverProtection[0] then
        return
    end


    if ui.timeChanged then

        transition.timeActive =
            false

        setTimeOfDay(
            ui.appliedTime,
            0
        )

    end


    if ui.weatherChanged then

        if settings.smoothWeather[0] then

            forceWeather(
                ui.appliedWeather
            )

            transition.weatherTransitionUntil =
                getGameTimer()
                + 10000

        else

            forceWeatherNow(
                ui.appliedWeather
            )

        end

    end

end


-- =========================================================
-- RESET
-- =========================================================

local function resetChanges()

    transition.timeActive =
        false

    transition.weatherTransitionUntil =
        0

    protectionReapplyAt =
        0


    ui.timeChanged =
        false

    ui.weatherChanged =
        false


    if originalTimeHour ~= nil then

        setTimeOfDay(
            originalTimeHour,
            originalTimeMinute or 0
        )

        ui.time[0] =
            originalTimeHour

    else

        local hour =
            getTimeOfDay()

        ui.time[0] =
            tonumber(hour) or 0

    end


    releaseWeather()


    if originalWeather ~= nil then

        forceWeatherNow(
            originalWeather
        )

        releaseWeather()

        ui.weather[0] =
            originalWeather

    else

        pcall(
            function()

                setWeatherToAppropriateTypeNow()

            end
        )

        ui.weather[0] =
            getCurrentWeatherId()

    end


    ui.appliedTime =
        0

    ui.appliedWeather =
        0


    originalTimeHour =
        nil

    originalTimeMinute =
        nil

    originalWeather =
        nil


    resetSyncPending =
        true

    resetSyncAt =
        getGameTimer()
        + 800


    chat(
        '{FFFF55}[TimeWeather] Настройки сброшены.'
    )

end


-- =========================================================
-- FIND CONFIG
-- =========================================================

local function findConfig(name)

    local lowered =
        string.lower(
            tostring(
                name or ''
            )
        )

    for i = 1, #configs do

        if string.lower(
            configs[i].name
        ) == lowered then

            return i

        end

    end

    return nil

end


-- =========================================================
-- CREATE CONFIG
-- =========================================================

local function createConfig(name)

    name =
        cleanName(name)

    if name == '' then

        return false,
            'Введите название'

    end


    if findConfig(name) then

        return false,
            'Такой конфиг уже существует'

    end


    local timeValue

    if ui.timeChanged then

        timeValue =
            ui.appliedTime

    else

        timeValue =
            tonumber(
                ui.time[0]
            ) or 0

    end


    local weatherValue

    if ui.weatherChanged then

        weatherValue =
            ui.appliedWeather

    else

        weatherValue =
            tonumber(
                ui.weather[0]
            ) or 0

    end


    local cfg = {

        name =
            name,

        time =
            timeValue,

        weather =
            weatherValue,

        autoApply =
            false,

        smoothTime =
            settings.smoothTime[0],

        smoothWeather =
            settings.smoothWeather[0],

        serverProtection =
            settings.serverProtection[0]
    }


    configs[
        #configs + 1
    ] = cfg


    selectedConfig[0] =
        #configs - 1


    autoApply[0] =
        false


    saveConfigs()

    return true

end


-- =========================================================
-- APPLY CONFIG
-- =========================================================

local function applyConfig(index)

    local cfg =
        configs[index]

    if not cfg then
        return false
    end


    settings.smoothTime[0] =
        cfg.smoothTime == true


    settings.smoothWeather[0] =
        cfg.smoothWeather == true


    settings.serverProtection[0] =
        cfg.serverProtection == true


    saveSettings()


    ui.time[0] =
        cfg.time


    ui.weather[0] =
        cfg.weather


    applyTime(
        cfg.time
    )


    applyWeather(
        cfg.weather
    )


    selectedConfig[0] =
        index - 1


    autoApply[0] =
        cfg.autoApply


    return true

end


-- =========================================================
-- OVERWRITE CONFIG
-- =========================================================

local function overwriteSelectedConfig()

    local index =
        selectedConfig[0] + 1


    local cfg =
        configs[index]


    if not cfg then
        return false
    end


    if ui.timeChanged then

        cfg.time =
            ui.appliedTime

    else

        cfg.time =
            tonumber(
                ui.time[0]
            ) or 0

    end


    if ui.weatherChanged then

        cfg.weather =
            ui.appliedWeather

    else

        cfg.weather =
            tonumber(
                ui.weather[0]
            ) or 0

    end


    cfg.smoothTime =
        settings.smoothTime[0]


    cfg.smoothWeather =
        settings.smoothWeather[0]


    cfg.serverProtection =
        settings.serverProtection[0]


    saveConfigs()

    return true

end


-- =========================================================
-- RENAME
-- =========================================================

local function renameSelectedConfig(name)

    local index =
        selectedConfig[0] + 1


    local cfg =
        configs[index]


    if not cfg then

        return false,
            'Конфиг не выбран'

    end


    name =
        cleanName(name)


    if name == '' then

        return false,
            'Введите название'

    end


    local found =
        findConfig(name)


    if found
    and found ~= index then

        return false,
            'Такой конфиг уже существует'

    end


    cfg.name =
        name


    saveConfigs()

    return true

end


-- =========================================================
-- DELETE
-- =========================================================

local function deleteSelectedConfig()

    local index =
        selectedConfig[0] + 1


    if not configs[index] then
        return false
    end


    table.remove(
        configs,
        index
    )


    selectedConfig[0] =
        -1


    autoApply[0] =
        false


    saveConfigs()

    return true

end


-- =========================================================
-- AUTO APPLY
-- =========================================================

local function setSelectedAutoApply(value)

    local index =
        selectedConfig[0] + 1


    if not configs[index] then
        return
    end


    if value then

        for i = 1, #configs do

            configs[i].autoApply =
                false

        end

    end


    configs[index].autoApply =
        value


    autoApply[0] =
        value


    saveConfigs()

end


-- =========================================================
-- UI HELPERS
-- =========================================================

local function centerText(text)

    local width =
        imgui.GetWindowSize().x


    local textWidth =
        imgui.CalcTextSize(
            text
        ).x


    imgui.SetCursorPosX(
        (
            width
            - textWidth
        ) / 2
    )


    imgui.Text(text)

end


local function centerTextDisabled(text)

    local width =
        imgui.GetWindowSize().x


    local textWidth =
        imgui.CalcTextSize(
            text
        ).x


    imgui.SetCursorPosX(
        (
            width
            - textWidth
        ) / 2
    )


    imgui.TextDisabled(text)

end


local function center(width)

    imgui.SetCursorPosX(
        (
            imgui.GetWindowSize().x
            - width
        ) / 2
    )

end


-- =========================================================
-- GLOW
-- =========================================================

local function drawGlow(
    alpha,
    red,
    green,
    blue
)

    local pos =
        imgui.GetWindowPos()


    local size =
        imgui.GetWindowSize()


    local draw =
        imgui.GetBackgroundDrawList()


    for i = 7, 1, -1 do

        local offset =
            i * 4


        draw:AddRectFilled(

            imgui.ImVec2(
                pos.x - offset,
                pos.y - offset
            ),

            imgui.ImVec2(
                pos.x
                + size.x
                + offset,

                pos.y
                + size.y
                + offset
            ),

            rgba(
                red,
                green,
                blue,

                (
                    4
                    + (8 - i) * 2
                )
                * alpha
            ),

            22
        )

    end

end


-- =========================================================
-- DATE + CLOCK
-- =========================================================

local function drawClockOverlay(screen)

    imgui.SetNextWindowPos(

        imgui.ImVec2(
            screen.x * 0.5,
            70
        ),

        imgui.Cond.Always,

        imgui.ImVec2(
            0.5,
            0.0
        )
    )


    imgui.SetNextWindowSize(

        imgui.ImVec2(
            320,
            120
        ),

        imgui.Cond.Always
    )


    imgui.SetNextWindowBgAlpha(
        0.0
    )


    imgui.PushStyleVarFloat(
        imgui.StyleVar.WindowBorderSize,
        0.0
    )


    imgui.Begin(

        '##TW_ClockOverlay',

        nil,

        imgui.WindowFlags.NoTitleBar
        + imgui.WindowFlags.NoResize
        + imgui.WindowFlags.NoMove
        + imgui.WindowFlags.NoScrollbar
        + imgui.WindowFlags.NoScrollWithMouse
        + imgui.WindowFlags.NoInputs
    )


    imgui.SetCursorPosY(3)


    if fontDate then

        imgui.PushFont(
            fontDate
        )

    end


    centerText(
        getDateText()
    )


    if fontDate then

        imgui.PopFont()

    end


    imgui.SetCursorPosY(27)


    if fontClock then

        imgui.PushFont(
            fontClock
        )

    end


    centerText(
        os.date('%H:%M')
    )


    if fontClock then

        imgui.PopFont()

    end


    imgui.End()


    imgui.PopStyleVar()

end


-- =========================================================
-- BUFFER
-- =========================================================

local function setNameBuffer(text)

    ffi.fill(
        nameBuffer,
        64
    )


    text =
        tostring(
            text or ''
        )


    if #text > 63 then

        text =
            text:sub(
                1,
                63
            )

    end


    if #text > 0 then

        ffi.copy(
            nameBuffer,
            text,
            #text
        )

    end

end


-- =========================================================
-- POPUP OPEN
-- =========================================================

local function openCreatePopup()

    setNameBuffer('')


    namePopupMode =
        'create'


    nameErrorText =
        ''


    focusNameInput =
        true


    namePopupRequest =
        true

end


local function openRenamePopup()

    local index =
        selectedConfig[0] + 1


    if not configs[index] then
        return
    end


    setNameBuffer(
        configs[index].name
    )


    namePopupMode =
        'rename'


    nameErrorText =
        ''


    focusNameInput =
        true


    namePopupRequest =
        true

end


local function openDeletePopup()

    local index =
        selectedConfig[0] + 1


    if not configs[index] then
        return
    end


    deletePopupRequest =
        true

end


local function openOverwritePopup()

    local index =
        selectedConfig[0] + 1


    if not configs[index] then
        return
    end


    overwritePopupRequest =
        true

end


local function openSettingsPopup()

    settingsPopupRequest =
        true

end


-- =========================================================
-- SAMP EVENTS
-- =========================================================

if hasSampEvents then


    function sampev.onSetWorldTime(hour)

        if ui.timeChanged then

            return false

        end

    end


    function sampev.onSetPlayerTime(
        hour,
        minute
    )

        if ui.timeChanged then

            return false

        end

    end


    function sampev.onSetWeather(weatherId)

        if ui.weatherChanged
        and settings.serverProtection[0] then

            return false

        end

    end


    function sampev.onSetInterior(interior)

        scheduleProtectionRestore(
            700
        )

    end


    function sampev.onSetPlayerPos(position)

        scheduleProtectionRestore(
            700
        )

    end


    function sampev.onRequestSpawnResponse(response)

        if response then

            scheduleProtectionRestore(
                900
            )

        end

    end

end


-- =========================================================
-- LOAD
-- =========================================================

loadLayout()
loadSettings()
loadConfigs()


-- =========================================================
-- IMGUI INIT
-- =========================================================

imgui.OnInitialize(function()

    local io =
        imgui.GetIO()


    io.IniFilename =
        nil


    io.ConfigWindowsMoveFromTitleBarOnly =
        false


    local fontPath =
        getFolderPath(0x14)
        .. '\\arial.ttf'


    if doesFileExist(
        fontPath
    ) then


        fontMain =
            io.Fonts:AddFontFromFileTTF(
                fontPath,
                16.0,
                nil,
                io.Fonts:GetGlyphRangesCyrillic()
            )


        fontTitle =
            io.Fonts:AddFontFromFileTTF(
                fontPath,
                22.0,
                nil,
                io.Fonts:GetGlyphRangesCyrillic()
            )


        fontDate =
            io.Fonts:AddFontFromFileTTF(
                fontPath,
                20.0,
                nil,
                io.Fonts:GetGlyphRangesCyrillic()
            )


        fontClock =
            io.Fonts:AddFontFromFileTTF(
                fontPath,
                68.0,
                nil,
                io.Fonts:GetGlyphRangesCyrillic()
            )


        io.FontDefault =
            fontMain

    end


    local style =
        imgui.GetStyle()


    style.WindowRounding = 18
    style.ChildRounding = 10
    style.FrameRounding = 7
    style.PopupRounding = 13
    style.GrabRounding = 7
    style.ScrollbarRounding = 7


    style.WindowPadding =
        imgui.ImVec2(
            18,
            13
        )


    style.FramePadding =
        imgui.ImVec2(
            7,
            5
        )


    style.ItemSpacing =
        imgui.ImVec2(
            7,
            7
        )


    style.WindowBorderSize =
        1


    style.Colors[
        imgui.Col.WindowBg
    ] =
        imgui.ImVec4(
            0.025,
            0.030,
            0.045,
            0.97
        )


    style.Colors[
        imgui.Col.PopupBg
    ] =
        imgui.ImVec4(
            0.025,
            0.030,
            0.045,
            0.99
        )


    style.Colors[
        imgui.Col.Border
    ] =
        imgui.ImVec4(
            0.18,
            0.42,
            0.92,
            0.78
        )


    style.Colors[
        imgui.Col.FrameBg
    ] =
        imgui.ImVec4(
            0.09,
            0.11,
            0.16,
            1.0
        )


    style.Colors[
        imgui.Col.FrameBgHovered
    ] =
        imgui.ImVec4(
            0.12,
            0.16,
            0.24,
            1.0
        )


    style.Colors[
        imgui.Col.FrameBgActive
    ] =
        imgui.ImVec4(
            0.14,
            0.20,
            0.31,
            1.0
        )


    style.Colors[
        imgui.Col.Button
    ] =
        imgui.ImVec4(
            0.10,
            0.29,
            0.62,
            1.0
        )


    style.Colors[
        imgui.Col.ButtonHovered
    ] =
        imgui.ImVec4(
            0.14,
            0.42,
            0.88,
            1.0
        )


    style.Colors[
        imgui.Col.ButtonActive
    ] =
        imgui.ImVec4(
            0.08,
            0.23,
            0.52,
            1.0
        )


    style.Colors[
        imgui.Col.CheckMark
    ] =
        imgui.ImVec4(
            0.30,
            0.65,
            1.0,
            1.0
        )


    style.Colors[
        imgui.Col.Header
    ] =
        imgui.ImVec4(
            0.10,
            0.28,
            0.56,
            0.85
        )


    style.Colors[
        imgui.Col.HeaderHovered
    ] =
        imgui.ImVec4(
            0.13,
            0.39,
            0.78,
            0.95
        )


    style.Colors[
        imgui.Col.HeaderActive
    ] =
        imgui.ImVec4(
            0.10,
            0.31,
            0.68,
            1.0
        )


    style.Colors[
        imgui.Col.SliderGrab
    ] =
        imgui.ImVec4(
            0.30,
            0.60,
            1.0,
            1.0
        )


    style.Colors[
        imgui.Col.SliderGrabActive
    ] =
        imgui.ImVec4(
            0.45,
            0.72,
            1.0,
            1.0
        )


    style.Colors[
        imgui.Col.Text
    ] =
        imgui.ImVec4(
            0.95,
            0.97,
            1.0,
            1.0
        )


    style.Colors[
        imgui.Col.TextDisabled
    ] =
        imgui.ImVec4(
            0.53,
            0.57,
            0.66,
            1.0
        )


    style.Colors[
        imgui.Col.Separator
    ] =
        imgui.ImVec4(
            0.20,
            0.30,
            0.50,
            0.70
        )

end)


-- =========================================================
-- FRAME
-- =========================================================

local frame =
    imgui.OnFrame(

        function()

            return
                ui.opened
                or ui.alpha > 0.01
                or ui.configsAlpha > 0.01

                or namePopupRequest
                or namePopupActive

                or deletePopupRequest
                or deletePopupActive

                or overwritePopupRequest
                or overwritePopupActive

                or settingsPopupRequest
                or settingsPopupActive

        end,

        function()

            local io =
                imgui.GetIO()


            local screen =
                io.DisplaySize


            local mainTarget =
                ui.opened
                and 1.0
                or 0.0


            ui.alpha =
                ui.alpha
                + (
                    mainTarget
                    - ui.alpha
                )
                * math.min(
                    io.DeltaTime * 10.0,
                    1.0
                )


            if not ui.opened then

                ui.configsOpened =
                    false

            end


            local configTarget =
                (
                    ui.opened
                    and ui.configsOpened
                )
                and 1.0
                or 0.0


            ui.configsAlpha =
                ui.configsAlpha
                + (
                    configTarget
                    - ui.configsAlpha
                )
                * math.min(
                    io.DeltaTime * 10.0,
                    1.0
                )


            if ui.alpha < 0.002 then
                ui.alpha = 0
            end


            if ui.configsAlpha < 0.002 then
                ui.configsAlpha = 0
            end


            if ui.alpha > 0.001
            and not isPauseMenuActive() then

                imgui.GetBackgroundDrawList():AddRectFilled(

                    imgui.ImVec2(
                        0,
                        0
                    ),

                    imgui.ImVec2(
                        screen.x,
                        screen.y
                    ),

                    rgba(
                        2,
                        5,
                        12,
                        145 * ui.alpha
                    )
                )

            end


            if ui.alpha > 0.01
            and not isPauseMenuActive() then

                drawClockOverlay(
                    screen
                )

            end


            -- =================================================
            -- MAIN WINDOW
            -- =================================================

            if ui.alpha > 0.01
            and not isPauseMenuActive() then


                if layout.mainX >= 0
                and layout.mainY >= 0 then

                    imgui.SetNextWindowPos(

                        imgui.ImVec2(
                            layout.mainX,
                            layout.mainY
                        ),

                        imgui.Cond.Once
                    )

                else

                    imgui.SetNextWindowPos(

                        imgui.ImVec2(
                            screen.x * 0.42,
                            screen.y * 0.50
                        ),

                        imgui.Cond.Once,

                        imgui.ImVec2(
                            0.5,
                            0.5
                        )
                    )

                end


                imgui.SetNextWindowSize(

                    imgui.ImVec2(
                        MAIN_W,
                        MAIN_H
                    ),

                    imgui.Cond.Always
                )


                imgui.PushStyleVarFloat(
                    imgui.StyleVar.Alpha,
                    ui.alpha
                )


                imgui.Begin(

                    'TimeWeather##TW_Main',

                    nil,

                    imgui.WindowFlags.NoTitleBar
                    + imgui.WindowFlags.NoResize
                    + imgui.WindowFlags.NoCollapse
                    + imgui.WindowFlags.NoScrollbar
                    + imgui.WindowFlags.NoScrollWithMouse
                )


                updateWindowPosition(
                    'main'
                )


                drawGlow(
                    ui.alpha,
                    30,
                    100,
                    255
                )


                centerText(
                    'TimeWeather'
                )


                imgui.SetCursorPosX(18)
                imgui.SetCursorPosY(7)


                if imgui.Button(
                    'Настройки##settings',

                    imgui.ImVec2(
                        90,
                        22
                    )
                ) then

                    openSettingsPopup()

                end


                imgui.SetCursorPosX(
                    imgui.GetWindowSize().x
                    - 40
                )


                imgui.SetCursorPosY(7)


                if imgui.Button(
                    'X##main_close',

                    imgui.ImVec2(
                        24,
                        22
                    )
                ) then

                    ui.opened =
                        false


                    ui.configsOpened =
                        false


                    saveLayout()

                end


                imgui.Separator()


                if fontTitle then
                    imgui.PushFont(fontTitle)
                end


                centerText(
                    greeting()
                    .. ' '
                    .. nickname()
                    .. '!'
                )


                if fontTitle then
                    imgui.PopFont()
                end


                imgui.Spacing()


                centerText(
                    'Время'
                )


                center(270)


                imgui.SetNextItemWidth(
                    270
                )


                imgui.SliderInt(
                    '##tw_time',
                    ui.time,
                    0,
                    23,
                    '%d'
                )


                center(220)


                if imgui.Button(
                    'Установить время',

                    imgui.ImVec2(
                        220,
                        30
                    )
                ) then

                    if applyTime(
                        ui.time[0]
                    ) then

                        chat(
                            string.format(
                                '{55FF55}[TimeWeather] Время: %02d:00',
                                ui.appliedTime
                            )
                        )

                    end

                end


                imgui.Separator()


                centerText(
                    'Погода'
                )


                center(270)


                imgui.SetNextItemWidth(
                    270
                )


                imgui.SliderInt(
                    '##tw_weather',
                    ui.weather,
                    0,
                    255,
                    '%d'
                )


                center(220)


                if imgui.Button(
                    'Установить погоду',

                    imgui.ImVec2(
                        220,
                        30
                    )
                ) then

                    if applyWeather(
                        ui.weather[0]
                    ) then

                        chat(
                            string.format(
                                '{55FF55}[TimeWeather] Погода: %d',
                                ui.appliedWeather
                            )
                        )

                    end

                end


                imgui.Separator()


                center(220)


                if imgui.Button(
                    'Сбросить изменения',

                    imgui.ImVec2(
                        220,
                        30
                    )
                ) then

                    resetChanges()

                end


                imgui.Spacing()


                centerText(
                    '/tw   /twtime   /twweather'
                )


                imgui.End()


                imgui.PopStyleVar()

            end


            -- =================================================
            -- CONFIG WINDOW
            -- =================================================

            if ui.configsAlpha > 0.01
            and not isPauseMenuActive() then


                if layout.configX >= 0
                and layout.configY >= 0 then

                    imgui.SetNextWindowPos(

                        imgui.ImVec2(
                            layout.configX,
                            layout.configY
                        ),

                        imgui.Cond.Once
                    )

                else

                    imgui.SetNextWindowPos(

                        imgui.ImVec2(
                            screen.x * 0.68,
                            screen.y * 0.50
                        ),

                        imgui.Cond.Once,

                        imgui.ImVec2(
                            0.5,
                            0.5
                        )
                    )

                end


                imgui.SetNextWindowSize(

                    imgui.ImVec2(
                        CONFIG_W,
                        CONFIG_H
                    ),

                    imgui.Cond.Always
                )


                imgui.PushStyleVarFloat(
                    imgui.StyleVar.Alpha,
                    ui.configsAlpha
                )


                imgui.Begin(

                    'Конфиги##TW_Configs',

                    nil,

                    imgui.WindowFlags.NoTitleBar
                    + imgui.WindowFlags.NoResize
                    + imgui.WindowFlags.NoCollapse
                    + imgui.WindowFlags.NoScrollbar
                    + imgui.WindowFlags.NoScrollWithMouse
                )


                updateWindowPosition(
                    'config'
                )


                drawGlow(
                    ui.configsAlpha,
                    35,
                    120,
                    255
                )


                centerText(
                    'Конфиги'
                )


                imgui.Separator()


                imgui.BeginChild(

                    '##config_list',

                    imgui.ImVec2(
                        0,
                        125
                    ),

                    true
                )


                if #configs == 0 then

                    imgui.Spacing()


                    centerText(
                        'Конфигов пока нет'
                    )


                    imgui.Spacing()

                else


                    for i = 1, #configs do

                        local cfg =
                            configs[i]


                        local selected =
                            selectedConfig[0]
                            == i - 1


                        local configText =
                            cfg.name


                        if cfg.autoApply then

                            configText =
                                '[AUTO] '
                                .. cfg.name

                        end


                        if imgui.Selectable(

                            configText
                            .. '##cfg_'
                            .. i,

                            selected
                        ) then

                            selectedConfig[0] =
                                i - 1


                            autoApply[0] =
                                cfg.autoApply

                        end

                    end

                end


                if #configs > 0 then
                    imgui.Separator()
                end


                if imgui.Selectable(
                    'Новый +##new_config',
                    false
                ) then

                    openCreatePopup()

                end


                imgui.EndChild()


                local index =
                    selectedConfig[0] + 1


                if configs[index] then


                    autoApply[0] =
                        configs[index].autoApply


                    if imgui.Checkbox(
                        'Автоприменение',
                        autoApply
                    ) then

                        setSelectedAutoApply(
                            autoApply[0]
                        )

                    end


                    center(250)


                    if imgui.Button(
                        'Применить',

                        imgui.ImVec2(
                            250,
                            27
                        )
                    ) then

                        if applyConfig(index) then

                            chat(
                                '{55FF55}[TimeWeather] Конфиг применён: '
                                .. configs[index].name
                            )

                        end

                    end


                    center(250)


                    if imgui.Button(
                        'Перезаписать',

                        imgui.ImVec2(
                            250,
                            27
                        )
                    ) then

                        openOverwritePopup()

                    end


                    center(250)


                    if imgui.Button(
                        'Переименовать конфиг',

                        imgui.ImVec2(
                            250,
                            27
                        )
                    ) then

                        openRenamePopup()

                    end


                    center(250)


                    if imgui.Button(
                        'Удалить конфиг',

                        imgui.ImVec2(
                            250,
                            27
                        )
                    ) then

                        openDeletePopup()

                    end


                else


                    imgui.Dummy(
                        imgui.ImVec2(
                            0,
                            58
                        )
                    )


                    centerTextDisabled(
                        'Выберите конфиг'
                    )

                end


                imgui.End()


                imgui.PopStyleVar()

            end


            -- =================================================
            -- SETTINGS
            -- =================================================

            if settingsPopupRequest then

                imgui.OpenPopup(
                    settingsPopupName
                )


                settingsPopupRequest =
                    false

            end


            imgui.SetNextWindowPos(

                imgui.ImVec2(
                    screen.x / 2,
                    screen.y / 2
                ),

                imgui.Cond.Always,

                imgui.ImVec2(
                    0.5,
                    0.5
                )
            )


            imgui.SetNextWindowSize(

                imgui.ImVec2(
                    430,
                    225
                ),

                imgui.Cond.Always
            )


            if imgui.BeginPopupModal(

                settingsPopupName,

                nil,

                imgui.WindowFlags.NoResize
                + imgui.WindowFlags.NoMove
                + imgui.WindowFlags.NoCollapse
            ) then


                settingsPopupActive =
                    true


                drawGlow(
                    1.0,
                    35,
                    120,
                    255
                )


                if closePopupRequest then

                    imgui.CloseCurrentPopup()


                    closePopupRequest =
                        false


                    settingsPopupActive =
                        false


                else


                    centerText(
                        'Настройки TimeWeather'
                    )


                    imgui.Separator()

                    imgui.Spacing()


                    if imgui.Checkbox(
                        'Плавная смена времени [БЕТА]',
                        settings.smoothTime
                    ) then

                        saveSettings()

                    end


                    if imgui.Checkbox(
                        'Плавная смена погоды [БЕТА]',
                        settings.smoothWeather
                    ) then

                        saveSettings()

                    end


                    if imgui.Checkbox(
                        'Защита от сброса сервером [БЕТА]',
                        settings.serverProtection
                    ) then

                        saveSettings()

                    end


                    imgui.Spacing()

                    imgui.Separator()

                    imgui.Spacing()


                    center(220)


                    if imgui.Button(
                        'Готово',

                        imgui.ImVec2(
                            220,
                            30
                        )
                    ) then

                        saveSettings()


                        imgui.CloseCurrentPopup()


                        settingsPopupActive =
                            false

                    end

                end


                imgui.EndPopup()


            else

                settingsPopupActive =
                    false

            end


            -- =================================================
            -- CREATE / RENAME
            -- =================================================

            if namePopupRequest then

                imgui.OpenPopup(
                    namePopupName
                )


                namePopupRequest =
                    false

            end


            imgui.SetNextWindowPos(

                imgui.ImVec2(
                    screen.x / 2,
                    screen.y / 2
                ),

                imgui.Cond.Always,

                imgui.ImVec2(
                    0.5,
                    0.5
                )
            )


            imgui.SetNextWindowSize(

                imgui.ImVec2(
                    370,
                    185
                ),

                imgui.Cond.Always
            )


            if imgui.BeginPopupModal(

                namePopupName,

                nil,

                imgui.WindowFlags.NoResize
                + imgui.WindowFlags.NoMove
                + imgui.WindowFlags.NoCollapse
            ) then


                namePopupActive =
                    true


                if closePopupRequest then

                    imgui.CloseCurrentPopup()


                    closePopupRequest =
                        false


                    namePopupActive =
                        false


                else


                    if namePopupMode
                    == 'rename' then

                        centerText(
                            'Переименовать конфиг'
                        )

                    else

                        centerText(
                            'Новый конфиг'
                        )

                    end


                    imgui.Spacing()


                    imgui.SetNextItemWidth(
                        -1
                    )


                    if focusNameInput then

                        imgui.SetKeyboardFocusHere()


                        focusNameInput =
                            false

                    end


                    imgui.InputText(
                        '##config_name',
                        nameBuffer,
                        64
                    )


                    if nameErrorText ~= '' then

                        imgui.TextColored(

                            imgui.ImVec4(
                                1.0,
                                0.35,
                                0.35,
                                1.0
                            ),

                            nameErrorText
                        )

                    else

                        imgui.Spacing()

                    end


                    imgui.Spacing()


                    center(300)


                    if imgui.Button(
                        'Отмена',

                        imgui.ImVec2(
                            145,
                            30
                        )
                    ) then

                        imgui.CloseCurrentPopup()


                        namePopupActive =
                            false


                        nameErrorText =
                            ''

                    end


                    imgui.SameLine()


                    local actionText =
                        namePopupMode
                        == 'rename'
                        and 'Переименовать'
                        or 'Создать'


                    if imgui.Button(
                        actionText,

                        imgui.ImVec2(
                            145,
                            30
                        )
                    ) then

                        local name =
                            cleanName(
                                ffi.string(
                                    nameBuffer
                                )
                            )


                        local success
                        local errorText


                        if namePopupMode
                        == 'rename' then

                            success,
                            errorText =
                                renameSelectedConfig(
                                    name
                                )

                        else

                            success,
                            errorText =
                                createConfig(
                                    name
                                )

                        end


                        if success then

                            imgui.CloseCurrentPopup()


                            namePopupActive =
                                false


                            nameErrorText =
                                ''


                            if namePopupMode
                            == 'rename' then

                                chat(
                                    '{55FF55}[TimeWeather] Конфиг переименован: '
                                    .. name
                                )

                            else

                                chat(
                                    '{55FF55}[TimeWeather] Конфиг создан: '
                                    .. name
                                )

                            end


                        else

                            nameErrorText =
                                errorText
                                or 'Ошибка'

                        end

                    end

                end


                imgui.EndPopup()


            else

                namePopupActive =
                    false

            end


            -- =================================================
            -- DELETE
            -- =================================================

            if deletePopupRequest then

                imgui.OpenPopup(
                    deletePopupName
                )


                deletePopupRequest =
                    false

            end


            imgui.SetNextWindowPos(

                imgui.ImVec2(
                    screen.x / 2,
                    screen.y / 2
                ),

                imgui.Cond.Always,

                imgui.ImVec2(
                    0.5,
                    0.5
                )
            )


            imgui.SetNextWindowSize(

                imgui.ImVec2(
                    390,
                    175
                ),

                imgui.Cond.Always
            )


            if imgui.BeginPopupModal(

                deletePopupName,

                nil,

                imgui.WindowFlags.NoResize
                + imgui.WindowFlags.NoMove
                + imgui.WindowFlags.NoCollapse
            ) then


                deletePopupActive =
                    true


                drawGlow(
                    1.0,
                    255,
                    30,
                    40
                )


                if closePopupRequest then

                    imgui.CloseCurrentPopup()


                    closePopupRequest =
                        false


                    deletePopupActive =
                        false


                else


                    local index =
                        selectedConfig[0] + 1


                    centerText(
                        'Точно удалить конфиг?'
                    )


                    imgui.Spacing()


                    if configs[index] then

                        centerText(
                            configs[index].name
                        )

                    end


                    imgui.Spacing()
                    imgui.Spacing()


                    center(300)


                    if imgui.Button(
                        'Отмена',

                        imgui.ImVec2(
                            145,
                            30
                        )
                    ) then

                        imgui.CloseCurrentPopup()


                        deletePopupActive =
                            false

                    end


                    imgui.SameLine()


                    if imgui.Button(
                        'Удалить',

                        imgui.ImVec2(
                            145,
                            30
                        )
                    ) then

                        local deletedName =
                            configs[index]
                            and configs[index].name
                            or ''


                        if deleteSelectedConfig() then

                            imgui.CloseCurrentPopup()


                            deletePopupActive =
                                false


                            chat(
                                '{FF5555}[TimeWeather] Конфиг удалён: '
                                .. deletedName
                            )

                        end

                    end

                end


                imgui.EndPopup()


            else

                deletePopupActive =
                    false

            end


            -- =================================================
            -- OVERWRITE
            -- =================================================

            if overwritePopupRequest then

                imgui.OpenPopup(
                    overwritePopupName
                )


                overwritePopupRequest =
                    false

            end


            imgui.SetNextWindowPos(

                imgui.ImVec2(
                    screen.x / 2,
                    screen.y / 2
                ),

                imgui.Cond.Always,

                imgui.ImVec2(
                    0.5,
                    0.5
                )
            )


            imgui.SetNextWindowSize(

                imgui.ImVec2(
                    420,
                    200
                ),

                imgui.Cond.Always
            )


            if imgui.BeginPopupModal(

                overwritePopupName,

                nil,

                imgui.WindowFlags.NoResize
                + imgui.WindowFlags.NoMove
                + imgui.WindowFlags.NoCollapse
            ) then


                overwritePopupActive =
                    true


                drawGlow(
                    1.0,
                    255,
                    30,
                    40
                )


                if closePopupRequest then

                    imgui.CloseCurrentPopup()


                    closePopupRequest =
                        false


                    overwritePopupActive =
                        false


                else


                    local index =
                        selectedConfig[0] + 1


                    centerText(
                        'Точно перезаписать конфиг?'
                    )


                    imgui.Spacing()


                    if configs[index] then

                        centerText(
                            configs[index].name
                        )

                    end


                    imgui.Spacing()


                    centerText(
                        'Текущие настройки'
                    )


                    centerText(
                        'заменят сохранённые данные.'
                    )


                    imgui.Spacing()


                    center(320)


                    if imgui.Button(
                        'Отмена',

                        imgui.ImVec2(
                            155,
                            30
                        )
                    ) then

                        imgui.CloseCurrentPopup()


                        overwritePopupActive =
                            false

                    end


                    imgui.SameLine()


                    if imgui.Button(
                        'Перезаписать',

                        imgui.ImVec2(
                            155,
                            30
                        )
                    ) then

                        local configName =
                            configs[index]
                            and configs[index].name
                            or ''


                        if overwriteSelectedConfig() then

                            imgui.CloseCurrentPopup()


                            overwritePopupActive =
                                false


                            chat(
                                '{55FF55}[TimeWeather] Конфиг перезаписан: '
                                .. configName
                            )

                        end

                    end

                end


                imgui.EndPopup()


            else

                overwritePopupActive =
                    false

            end


            -- =================================================
            -- VERSION
            -- =================================================

            if ui.opened
            and ui.alpha > 0.01
            and not isPauseMenuActive() then

                local text =
                    'v. 1.2'


                local size =
                    imgui.CalcTextSize(
                        text
                    )


                imgui.GetForegroundDrawList():AddText(

                    imgui.ImVec2(

                        screen.x
                        - size.x
                        - 15,

                        screen.y
                        - size.y
                        - 12
                    ),

                    rgba(
                        255,
                        255,
                        255,
                        180 * ui.alpha
                    ),

                    text
                )

            end

        end
    )


frame.LockPlayer =
    false


frame.HideCursor =
    false


-- =========================================================
-- ESC
-- =========================================================

local escBlocking =
    false


addEventHandler(

    'onWindowMessage',

    function(msg, wparam)

        if wparam
        ~= vkeys.VK_ESCAPE then

            return

        end


        if msg == 0x0100 then


            if settingsPopupActive
            or namePopupActive
            or deletePopupActive
            or overwritePopupActive then

                closePopupRequest =
                    true


                escBlocking =
                    true


                consumeWindowMessage(
                    true,
                    false
                )


                return

            end


            if ui.opened then

                ui.opened =
                    false


                ui.configsOpened =
                    false


                escBlocking =
                    true


                saveLayout()


                consumeWindowMessage(
                    true,
                    false
                )


                return

            end

        end


        if msg == 0x0101
        and escBlocking then

            consumeWindowMessage(
                true,
                false
            )


            escBlocking =
                false


            return

        end

    end
)


-- =========================================================
-- TOGGLE
-- =========================================================

local function toggleMenu()

    if ui.opened then

        ui.opened =
            false


        ui.configsOpened =
            false


        saveLayout()

    else

        ui.opened =
            true


        ui.configsOpened =
            true

    end

end


-- =========================================================
-- COMMAND TIME
-- =========================================================

local function commandTime(arg)

    local value =
        tonumber(arg)


    if not value then

        chat(
            '{FF5555}[TimeWeather] Использование: /twtime [0-24]'
        )


        return

    end


    value =
        math.floor(value)


    if value < 0
    or value > 24 then

        chat(
            '{FF5555}[TimeWeather] Время должно быть от 0 до 24.'
        )


        return

    end


    if value == 24 then
        value = 0
    end


    ui.time[0] =
        value


    if applyTime(value) then

        chat(
            string.format(
                '{55FF55}[TimeWeather] Время: %02d:00',
                ui.appliedTime
            )
        )

    end

end


-- =========================================================
-- COMMAND WEATHER
-- =========================================================

local function commandWeather(arg)

    local value =
        tonumber(arg)


    if not value then

        chat(
            '{FF5555}[TimeWeather] Использование: /twweather [0-255]'
        )


        return

    end


    value =
        math.floor(value)


    if value < 0
    or value > 255 then

        chat(
            '{FF5555}[TimeWeather] ID погоды должен быть от 0 до 255.'
        )


        return

    end


    ui.weather[0] =
        value


    if applyWeather(value) then

        chat(
            string.format(
                '{55FF55}[TimeWeather] Погода: %d',
                ui.appliedWeather
            )
        )

    end

end


-- =========================================================
-- MAIN
-- =========================================================

function main()

    repeat
        wait(100)
    until isSampAvailable()


    wait(1500)


    local currentHour =
        getTimeOfDay()


    ui.time[0] =
        tonumber(
            currentHour
        ) or 0


    ui.weather[0] =
        getCurrentWeatherId()


    sampRegisterChatCommand(
        'tw',
        toggleMenu
    )


    sampRegisterChatCommand(
        'twtime',
        commandTime
    )


    sampRegisterChatCommand(
        'twweather',
        commandWeather
    )


    for i = 1, #configs do

        if configs[i].autoApply then

            selectedConfig[0] =
                i - 1


            autoApply[0] =
                true


            applyConfig(i)


            break

        end

    end


    chat(
        '{55FF55}[TimeWeather] v1.2 | /tw'
    )


    while true do

        wait(0)


        local now =
            getGameTimer()


        updateSmoothTime()


        lockAppliedTimeMemory()


        if protectionReapplyAt > 0
        and now >= protectionReapplyAt then

            protectionReapplyAt =
                0


            restoreProtectedState()

        end


        if not hasSampEvents
        and settings.serverProtection[0]
        and now
            - lastFallbackProtectionCheck
            >= 1500 then


            if ui.weatherChanged
            and now
                >= transition.weatherTransitionUntil then

                local current =
                    getCurrentWeatherId()


                if current
                ~= ui.appliedWeather then

                    forceWeatherNow(
                        ui.appliedWeather
                    )

                end

            end


            lastFallbackProtectionCheck =
                now

        end


        if resetSyncPending
        and now >= resetSyncAt then

            resetSyncPending =
                false


            local hour =
                getTimeOfDay()


            ui.time[0] =
                tonumber(
                    hour
                ) or 0


            ui.weather[0] =
                getCurrentWeatherId()

        end


        if layoutDirty
        and now
            - lastLayoutSave
            >= 500 then

            saveLayout()

        end

    end

end