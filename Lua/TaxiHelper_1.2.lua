script_name('Taxi Helper')

require 'lib.moonloader'
local sampev = require 'samp.events'
local imgui = require 'imgui'
local inicfg = require 'inicfg'
local encoding = require 'encoding'
encoding.default = 'CP1251'
u8 = encoding.UTF8

local config_path = 'TaxiHelper.ini'

local DOLLAR_COLOR     = imgui.ImVec4(0.35, 1.0, 0.35, 1.0)
local HEADER_DAY_COLOR = imgui.ImVec4(0.55, 0.85, 1.0, 1.0)
local TAXI_YELLOW      = imgui.ImVec4(1.0, 0.85, 0.0, 1.0)
local TAXI_WHITE       = imgui.ImVec4(1.0, 1.0, 1.0, 1.0)
local WINDOW_BG        = imgui.ImVec4(0.08, 0.08, 0.10, 0.70)

local SEP_SESSION      = {255, 200, 60}
local SEP_DAY          = {100, 200, 255}

local SEP_PAD_TOP      = 12
local SEP_PAD_BOTTOM   = 12

local UNFINISHED_SAVE_INTERVAL = 5

local gta = true
addEventHandler("onWindowMessage", function(msg, wparam)
    if msg == 6 then
        gta = wparam == 1
    end
end)

local defaults = {
    window  = { x = 100, y = 100, show = true },
    session = { rides = 0, money = 0, best_ride = 0, unfinished = 0 },
    day     = { date = '', rides = 0, money = 0, worked = 0 }
}

local cfg = inicfg.load(defaults, config_path)

local waiting_payment       = false
local payment_deadline      = 0
local last_payment_time     = 0
local session_start         = 0
local session_elapsed       = 0
local last_unfinished_save  = 0

local show      = imgui.ImBool(cfg.window.show == true or cfg.window.show == 'true')
local edit_mode = false

local notification_show = imgui.ImBool(false)

local notification = {
    active = false,
    started = 0,
    ride_money = 0,
    session_money = 0,
    day_money = 0
}

local NOTIFY_DURATION = 5000
local NOTIFY_FADE_IN = 700
local NOTIFY_FADE_OUT = 1000

local function game_ms()
    if type(getGameTimer) == 'function' then
        return getGameTimer()
    end
    return math.floor(os.clock() * 1000)
end

local function show_ride_notification(money)
    notification.active = true
    notification_show.v = true
    notification.started = game_ms()
    notification.ride_money = money
    notification.session_money = tonumber(cfg.session.money) or 0
    notification.day_money = tonumber(cfg.day.money) or 0
end

local function notification_alpha()
    if not notification.active then return 0 end

    local elapsed = game_ms() - notification.started

    if elapsed >= NOTIFY_DURATION then
        notification.active = false
        notification_show.v = false
        return 0
    end

    if elapsed < NOTIFY_FADE_IN then
        return elapsed / NOTIFY_FADE_IN
    end

    local remaining = NOTIFY_DURATION - elapsed
    if remaining < NOTIFY_FADE_OUT then
        return remaining / NOTIFY_FADE_OUT
    end

    return 1
end

local fontsize, fontsizeBig
local fontsizeNotify, fontsizeNotifyBig

local function now()   return os.time() end
local function today() return os.date('%Y-%m-%d') end

local function save()
    cfg.window.show = show.v
    inicfg.save(cfg, config_path)
end

local function check_new_day()
    local d = today()
    if cfg.day.date ~= d then
        cfg.day.date   = d
        cfg.day.rides  = 0
        cfg.day.money  = 0
        cfg.day.worked = 0
        save()
    end
end

local function add_ride(money)
    check_new_day()

    cfg.session.rides     = (tonumber(cfg.session.rides) or 0) + 1
    cfg.session.money     = (tonumber(cfg.session.money) or 0) + money
    cfg.session.best_ride = tonumber(cfg.session.best_ride) or 0

    if money > cfg.session.best_ride then
        cfg.session.best_ride = money
    end

    cfg.day.rides = (tonumber(cfg.day.rides) or 0) + 1
    cfg.day.money = (tonumber(cfg.day.money) or 0) + money

    save()
    show_ride_notification(money)
end

local function reset_session()
    cfg.session.rides      = 0
    cfg.session.money      = 0
    cfg.session.best_ride  = 0
    cfg.session.unfinished = 0
    session_start          = 0
    session_elapsed        = 0
    last_unfinished_save   = 0
    save()
end

local function reset_day()
    cfg.day.date   = today()
    cfg.day.rides  = 0
    cfg.day.money  = 0
    cfg.day.worked = 0
    save()
end

local function format_money(n)
    local s = tostring(math.floor(tonumber(n) or 0))
    while true do
        local r, k = s:gsub('^(-?%d+)(%d%d%d)', '%1.%2')
        s = r
        if k == 0 then break end
    end
    return s
end

local function format_time(sec)
    sec = math.floor(tonumber(sec) or 0)
    return string.format('%d:%02d:%02d',
        math.floor(sec / 3600),
        math.floor((sec % 3600) / 60),
        sec % 60)
end

local function draw_money(value)
    imgui.TextColored(DOLLAR_COLOR, '$')
    imgui.SameLine(nil, 0)
    imgui.Text(' ' .. format_money(value))
end

local function utf8_chars(s)
    local t = {}
    for ch in s:gmatch('[%z\1-\127\194-\244][\128-\191]*') do
        t[#t + 1] = ch
    end
    return t
end

local function checkered_header(text)
    local win_w  = imgui.GetWindowWidth()
    local text_w = imgui.CalcTextSize(text).x
    imgui.SetCursorPosX((win_w - text_w) / 2)

    for i, ch in ipairs(utf8_chars(text)) do
        if ch == ' ' then
            imgui.Text(' ')
        else
            imgui.TextColored((i % 2 == 1) and TAXI_YELLOW or TAXI_WHITE, ch)
        end
        imgui.SameLine(nil, 0)
    end
    imgui.NewLine()
end

local function colored_centered_header(text, color)
    local win_w = imgui.GetWindowWidth()
    imgui.SetCursorPosX((win_w - imgui.CalcTextSize(text).x) / 2)
    imgui.PushStyleColor(imgui.Col.Text, color)
    imgui.Text(text)
    imgui.PopStyleColor()
end

local function colored_separator(r, g, b)
    imgui.Dummy(imgui.ImVec2(0, SEP_PAD_TOP))
    local x = imgui.GetCursorScreenPos().x
    local y = imgui.GetCursorScreenPos().y
    imgui.GetWindowDrawList():AddLine(
        imgui.ImVec2(x, y),
        imgui.ImVec2(x + imgui.GetWindowWidth(), y),
        imgui.ImColor(r, g, b, 255):GetU32(),
        1.5
    )
    imgui.Dummy(imgui.ImVec2(0, SEP_PAD_BOTTOM))
end

local function clean_text(text)
    return text and tostring(text):gsub('{%x%x%x%x%x%x}', '') or ''
end

function sampev.onServerMessage(_, text)
    text = clean_text(text)

    if text:find('Вы начали работу таксистом') then
        session_start        = os.time()
        session_elapsed      = 0
        last_unfinished_save = session_start
    elseif text:find('Вы закончили работу таксистом') then
        if session_start > 0 then
            session_elapsed = now() - session_start
            cfg.day.worked  = (tonumber(cfg.day.worked) or 0) + session_elapsed
            cfg.session.unfinished = 0
        end
        session_start        = 0
        last_unfinished_save = 0
        save()
    elseif text:find('Вы доставили клиента по имени') then
        waiting_payment  = true
        payment_deadline = now() + 10
    elseif waiting_payment and now() <= payment_deadline then
        local m = text:match('Клиент оплатил:%s*[^%d]*([%d%.%s,]+)')
        if m then
            m = tonumber((m:gsub('%s+', ''):gsub('%.', ''):gsub(',', '')))
            if m and now() - last_payment_time >= 1 then
                add_ride(m)
                last_payment_time = now()
            end
            waiting_payment = false
        end
    end
end

function imgui.OnInitialize()
    imgui.GetIO().IniFilename = nil

    local style = imgui.GetStyle()
    style.WindowRounding      = 8
    style.FrameRounding       = 4
    style.ChildWindowRounding = 4
    style.WindowPadding       = imgui.ImVec2(12, 10)
    style.FramePadding        = imgui.ImVec2(6, 4)
    style.ItemSpacing         = imgui.ImVec2(6, 6)
    style.ItemInnerSpacing    = imgui.ImVec2(4, 4)
end

function imgui.BeforeDrawFrame()
    if not fontsize then
        local fonts = imgui.GetIO().Fonts
        fontsize    = fonts:AddFontFromFileTTF(getFolderPath(0x14) .. '\\trebucbd.ttf', 17.0, nil, fonts:GetGlyphRangesCyrillic())
        fontsizeBig = fonts:AddFontFromFileTTF(getFolderPath(0x14) .. '\\trebucbd.ttf', 22.0, nil, fonts:GetGlyphRangesCyrillic())
    end
    if not fontsizeNotify then
        local fonts = imgui.GetIO().Fonts
        fontsizeNotify    = fonts:AddFontFromFileTTF(getFolderPath(0x14) .. '\\trebucbd.ttf', 19.0, nil, fonts:GetGlyphRangesCyrillic())
        fontsizeNotifyBig = fonts:AddFontFromFileTTF(getFolderPath(0x14) .. '\\trebucbd.ttf', 26.0, nil, fonts:GetGlyphRangesCyrillic())
    end
end

function imgui.OnDrawFrame()
    imgui.ShowCursor = edit_mode

    if show.v then
        local flags = imgui.WindowFlags.NoTitleBar + imgui.WindowFlags.AlwaysAutoResize
        if not edit_mode then
            flags = flags + imgui.WindowFlags.NoMove + imgui.WindowFlags.NoInputs
        end

        imgui.SetNextWindowPos(
            imgui.ImVec2(tonumber(cfg.window.x) or 100, tonumber(cfg.window.y) or 100),
            imgui.Cond.FirstUseEver
        )

        imgui.PushStyleColor(imgui.Col.WindowBg, WINDOW_BG)
        imgui.Begin(u8'Taxi Helper', show, flags)

        if edit_mode then
            imgui.PushFont(fontsize)
            imgui.TextColored(imgui.ImVec4(1.0, 0.8, 0.0, 1.0), u8'[РЕЖИМ ПЕРЕМЕЩЕНИЯ]')
            if imgui.Button(u8'Сохранить положение', imgui.ImVec2(-1, 28)) then
                local pos = imgui.GetWindowPos()
                cfg.window.x = math.floor(pos.x)
                cfg.window.y = math.floor(pos.y)
                cfg.window.show = show.v
                inicfg.save(cfg, config_path)
                edit_mode = false
                imgui.ShowCursor = false
            end
            colored_separator(255, 220, 60)
            imgui.PopFont()
        end

        imgui.PushFont(fontsizeBig)
        checkered_header(u8'TAXI HELPER')
        imgui.PopFont()

        imgui.PushFont(fontsize)

        imgui.Text(u8'Рейсов:')
        imgui.SameLine(170)
        imgui.Text(tostring(cfg.session.rides))

        imgui.Text(u8'Заработано:')
        imgui.SameLine(170)
        draw_money(cfg.session.money)

        imgui.Text(u8'Лучший рейс:')
        imgui.SameLine(170)
        local best = tonumber(cfg.session.best_ride) or 0
        if best > 0 then
            draw_money(best)
        else
            imgui.TextDisabled(u8'-')
        end

        imgui.Text(u8'Время сессии:')
        imgui.SameLine(170)
        if session_start > 0 then
            imgui.Text(format_time(now() - session_start))
        elseif session_elapsed > 0 then
            imgui.TextDisabled(format_time(session_elapsed))
        else
            imgui.TextDisabled(u8'—')
        end

        imgui.PopFont()

        colored_separator(SEP_SESSION[1], SEP_SESSION[2], SEP_SESSION[3])

        imgui.PushFont(fontsizeBig)
        colored_centered_header(u8'ЗАРАБОТОК ЗА ДЕНЬ', HEADER_DAY_COLOR)
        imgui.PopFont()

        imgui.PushFont(fontsize)

        imgui.Text(u8'Заработано:')
        imgui.SameLine(170)
        draw_money(cfg.day.money)

        imgui.Text(u8'Отработано:')
        imgui.SameLine(170)
        local worked = tonumber(cfg.day.worked) or 0
        if worked > 0 then
            imgui.Text(format_time(worked))
        else
            imgui.TextDisabled(u8'—')
        end

        imgui.Text(u8'Рейсов:')
        imgui.SameLine(170)
        imgui.Text(tostring(cfg.day.rides))

        imgui.PopFont()

        colored_separator(SEP_DAY[1], SEP_DAY[2], SEP_DAY[3])

        imgui.End()
        imgui.PopStyleColor()
    end

    local alpha = notification_alpha()
    if alpha > 0 then
        local io = imgui.GetIO()
        local flagsNotify = imgui.WindowFlags.NoTitleBar
            + imgui.WindowFlags.NoResize
            + imgui.WindowFlags.NoMove
            + imgui.WindowFlags.NoSavedSettings
            + imgui.WindowFlags.NoInputs
            + imgui.WindowFlags.AlwaysAutoResize

        imgui.SetNextWindowPos(
            imgui.ImVec2(io.DisplaySize.x / 2, 135),
            imgui.Cond.Always,
            imgui.ImVec2(0.5, 0.0)
        )

        imgui.PushStyleColor(
            imgui.Col.WindowBg,
            imgui.ImVec4(0.05, 0.06, 0.08, 0.70 * alpha)
        )
        imgui.PushStyleColor(
            imgui.Col.Border,
            imgui.ImVec4(1.0, 0.82, 0.20, 0.60 * alpha)
        )
        imgui.PushStyleColor(
            imgui.Col.Text,
            imgui.ImVec4(1.0, 1.0, 1.0, alpha)
        )

        notification_show.v = true
        imgui.Begin(u8'##TaxiRideNotification', notification_show, flagsNotify)

        imgui.PushFont(fontsizeNotifyBig)
        local title = u8'РЕЙС ЗАВЕРШЁН'
        local title_w = imgui.CalcTextSize(title).x
        imgui.SetCursorPosX((imgui.GetWindowWidth() - title_w) / 2)
        imgui.TextColored(imgui.ImVec4(1.0, 0.85, 0.15, alpha), title)
        imgui.PopFont()

        imgui.Spacing()

        imgui.PushFont(fontsizeNotify)

        local plus = u8'+ ' .. format_money(notification.ride_money)
        local plus_w = imgui.CalcTextSize(plus).x
        imgui.SetCursorPosX((imgui.GetWindowWidth() - plus_w) / 2)
        imgui.TextColored(imgui.ImVec4(0.35, 1.0, 0.35, alpha), plus)

        imgui.Spacing()
        imgui.Text(u8'Заработано за сессию:')
        imgui.SameLine(200)
        imgui.TextColored(imgui.ImVec4(0.35, 1.0, 0.35, alpha), '$')
        imgui.SameLine(nil, 0)
        imgui.Text(' ' .. format_money(notification.session_money))

        imgui.Text(u8'Заработано сегодня:')
        imgui.SameLine(200)
        imgui.TextColored(imgui.ImVec4(0.35, 1.0, 0.35, alpha), '$')
        imgui.SameLine(nil, 0)
        imgui.Text(' ' .. format_money(notification.day_money))

        imgui.PopFont()

        imgui.End()

        if not notification_show.v then
            notification.active = false
        end

        imgui.PopStyleColor(3)
    end
end

function main()
    while not isSampAvailable() do wait(100) end

    check_new_day()

    if tonumber(cfg.session.unfinished) and tonumber(cfg.session.unfinished) > 0 then
        cfg.day.worked = (tonumber(cfg.day.worked) or 0) + tonumber(cfg.session.unfinished)
        cfg.session.unfinished = 0
        inicfg.save(cfg, config_path)
    end

    reset_session()

    sampRegisterChatCommand('th', function()
        show.v = not show.v
        save()
        sampAddChatMessage('{AA66FF}[Taxi Helper]{FFFFFF} Окно ' ..
            (show.v and 'показано' or 'скрыто') .. '.', -1)
    end)

    sampRegisterChatCommand('thmove', function()
        edit_mode = true
        show.v = true
        sampAddChatMessage('{AA66FF}[Taxi Helper]{FFFFFF} Режим перемещения включён. Перетащи окно и нажми «Сохранить положение».', -1)
    end)

    sampRegisterChatCommand('threset', function()
        reset_day()
        sampAddChatMessage('{AA66FF}[Taxi Helper]{FFFFFF} Статистика дня сброшена.', -1)
    end)

    sampAddChatMessage('{AA66FF}[Taxi Helper]{FFFFFF} Загружен. /th - окно, /thmove - переместить, /threset - сброс дня.', -1)

    while true do
        wait(0)
        imgui.Process = gta and (show.v or notification.active)

        if session_start > 0 and now() - last_unfinished_save >= UNFINISHED_SAVE_INTERVAL then
            cfg.session.unfinished = now() - session_start
            inicfg.save(cfg, config_path)
            last_unfinished_save = now()
        end

        check_new_day()
        wait(50)
    end
end