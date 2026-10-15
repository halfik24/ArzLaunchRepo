-- House Notes v1.0.0 | Arizona RP / SA-MP
-- Автор: Aurelien
-- Требуется MoonLoader, mimgui, samp.events, encoding.
-- /hnotes: редактор примечаний после выбора спавна.
-- Хранилище: moonloader/config/HouseNotes.txt (локально для каждого игрока).
-- ВАЖНО: поддерживается только диалог ID 25524 с ожидаемой разметкой.
-- Распространяется без автозагрузки, удаленного кода и сетевой синхронизации.

script_name('House Notes')
script_author('Aurelien')
script_version('1.0.0')

require 'lib.moonloader'

local sampev = require 'samp.events'
local imgui = require 'mimgui'
local encoding = require 'encoding'
local ffi = require 'ffi'

encoding.default = 'CP1251'
local u8 = encoding.UTF8
local new = imgui.new

-- =====================================
-- НАСТРОЙКИ
-- =====================================

local DIALOG_ID = 25524

local SPAWN_WINDOW_W = 400
local SPAWN_WINDOW_H = 800
local EDITOR_WINDOW_W = 700
local EDITOR_WINDOW_H = 600

local CARD_H = 35
local FONT_SCALE = 1.2
local MAX_NOTE_LENGTH = 20
-- Примечания хранятся только на компьютере игрока.

local window = new.bool(false)
local editorWindow = new.bool(false)
local noteInput = new.char[256]()

local rows = {}
local notes = {}
local selected = 0
local editorSelected = 0
local captured = false
local scrollSelected = false
local consumeEscapeRelease = false

-- Исправление фокуса редактора
local editorFocusPending = false
-- Команда приходит из SA-MP чата: открываем GUI только после закрытия чата.
local pendingEditorOpen = false
local pendingEditorAt = 0
local editorSession = 0

-- mimgui: параметры захвата задаются каждому OnFrame отдельно.
-- Глобальное переключение imgui.LockPlayer убрано, чтобы при
-- закрытии и повторном открытии не терять захват ввода.

-- =====================================
-- СОХРАНЕНИЕ
-- =====================================

local configDir = getWorkingDirectory() .. '\\config'
local notesPath = configDir .. '\\HouseNotes.txt'
local oldIniPath = configDir .. '\\HouseNotes.ini'

local function hexEncode(str)
    return (str:gsub('.', function(c)
        return string.format('%02X', string.byte(c))
    end))
end

local function hexDecode(str)
    if #str % 2 ~= 0 or str:find('[^%x]') then
        return nil
    end

    return (str:gsub('%x%x', function(h)
        return string.char(tonumber(h, 16))
    end))
end

local function trimUtf8(str, limit)
    local i, count = 1, 0

    while i <= #str and count < limit do
        local b = str:byte(i)
        local n = (b < 128 and 1)
            or (b < 224 and 2)
            or (b < 240 and 3)
            or 4

        if i + n - 1 > #str then break end

        i = i + n
        count = count + 1
    end

    return str:sub(1, i - 1), count
end

local function loadNotes()
    local file = io.open(notesPath, 'rb')
    if not file then return false end

    for line in file:lines() do
        line = line:gsub('\r$', '')
        local id, hex = line:match('^(%d+)=(%x*)$')

        if id then
            local decoded = hexDecode(hex)
            if decoded then notes[id] = decoded end
        end
    end

    file:close()
    return true
end

local function saveNotes()
    if not doesDirectoryExist(configDir) then
        createDirectory(configDir)
    end

    local file, err = io.open(notesPath, 'wb')
    if not file then
        print('[HouseNotes] Save error: ' .. tostring(err))
        return false
    end

    local ids = {}
    for id in pairs(notes) do
        ids[#ids + 1] = id
    end

    table.sort(ids, function(a, b)
        return tonumber(a) < tonumber(b)
    end)

    for _, id in ipairs(ids) do
        local note = notes[id]
        if note and note ~= '' then
            local ok = file:write(
                id .. '=' .. hexEncode(note) .. '\n'
            )
            if not ok then
                file:close()
                return false
            end
        end
    end

    local ok = file:close()
    return ok ~= nil
end

local function importOldNotes()
    local file = io.open(oldIniPath, 'rb')
    if not file then return end

    local inNotes = false
    local imported = 0

    for line in file:lines() do
        line = line:gsub('\r$', '')
        local section = line:match('^%s*%[([^%]]+)%]')

        if section then
            inNotes = section:lower() == 'notes'
        elseif inNotes then
            local id, note = line:match('^%s*(%d+)%s*=(.*)$')
            if id and note and note ~= '' and notes[id] == nil then
                notes[id] = note
                imported = imported + 1
            end
        end
    end

    file:close()
    if imported > 0 then saveNotes() end
end

loadNotes()
importOldNotes()

-- =====================================
-- ORANGE EDITION
-- =====================================

local function color(r, g, b)
    return imgui.ImVec4(r / 255, g / 255, b / 255, 1)
end

local BG = color(25, 21, 18)
local PANEL = color(47, 36, 28)
local PANEL_HOVER = color(75, 48, 28)
local PANEL_ACTIVE = color(125, 65, 24)

local WHITE = color(245, 238, 230)
local MUTED = color(207, 163, 123)
local BORDER = color(94, 61, 39)

local ORANGE = color(255, 163, 60)
local ORANGE_HOVER = color(255, 185, 90)
local ORANGE_ACTIVE = color(225, 121, 30)
local DARK_TEXT = color(25, 21, 18)

local STYLE_COLOR_COUNT = 16

local function pushStyle()
    imgui.PushStyleColor(imgui.Col.WindowBg, BG)
    imgui.PushStyleColor(imgui.Col.ChildBg, BG)

    imgui.PushStyleColor(imgui.Col.FrameBg, PANEL)
    imgui.PushStyleColor(imgui.Col.FrameBgHovered, PANEL_HOVER)
    imgui.PushStyleColor(imgui.Col.FrameBgActive, PANEL_ACTIVE)

    imgui.PushStyleColor(imgui.Col.Button, PANEL)
    imgui.PushStyleColor(imgui.Col.ButtonHovered, PANEL_HOVER)
    imgui.PushStyleColor(imgui.Col.ButtonActive, PANEL_ACTIVE)

    imgui.PushStyleColor(imgui.Col.Header, PANEL_ACTIVE)
    imgui.PushStyleColor(imgui.Col.HeaderHovered, PANEL_HOVER)
    imgui.PushStyleColor(imgui.Col.HeaderActive, PANEL_ACTIVE)

    imgui.PushStyleColor(imgui.Col.Text, WHITE)
    imgui.PushStyleColor(imgui.Col.Border, BORDER)

    -- Оранжевая верхняя панель
    imgui.PushStyleColor(imgui.Col.TitleBg, ORANGE)
    imgui.PushStyleColor(imgui.Col.TitleBgActive, ORANGE)
    imgui.PushStyleColor(imgui.Col.TitleBgCollapsed, ORANGE)
end

local function windowFlags()
    return imgui.WindowFlags.NoMove
        + imgui.WindowFlags.NoResize
        + imgui.WindowFlags.NoCollapse
        + imgui.WindowFlags.NoSavedSettings
end

local function beginOrangeWindow(title)
    imgui.PushStyleColor(imgui.Col.Text, DARK_TEXT)
    local opened = imgui.Begin(title, nil, windowFlags())
    imgui.PopStyleColor()
    return opened
end

local function orangeButton(label, w, h)
    local style = imgui.GetStyle()
    local oldRounding = style.FrameRounding

    style.FrameRounding = 9

    imgui.PushStyleColor(imgui.Col.Button, ORANGE)
    imgui.PushStyleColor(imgui.Col.ButtonHovered, ORANGE_HOVER)
    imgui.PushStyleColor(imgui.Col.ButtonActive, ORANGE_ACTIVE)
    imgui.PushStyleColor(imgui.Col.Text, DARK_TEXT)

    local clicked = imgui.Button(label, imgui.ImVec2(w, h))

    imgui.PopStyleColor(4)
    style.FrameRounding = oldRounding

    return clicked
end

local function centerWindow(w, h)
    local io = imgui.GetIO()

    imgui.SetNextWindowPos(
        imgui.ImVec2(
            (io.DisplaySize.x - w) / 2,
            (io.DisplaySize.y - h) / 2
        ),
        imgui.Cond.Always
    )

    imgui.SetNextWindowSize(
        imgui.ImVec2(w, h),
        imgui.Cond.Always
    )
end

-- =====================================
-- СЛУЖЕБНЫЕ ФУНКЦИИ
-- =====================================

local function chat(text, colorValue)
    sampAddChatMessage(
        '[HouseNotes] ' .. u8:decode(text),
        colorValue or 0xFFFFFF
    )
end

local function getHouseNumber(content)
    local text = u8(content or '')

    local number =
        text:match('Дом%s*№?%s*(%d+)')
        or text:match('дом%s*№?%s*(%d+)')

    return number and tonumber(number) or nil
end

local function parseDialog(text)
    local parsed = {}
    local responseIndex = 0

    for line in text:gmatch('[^\r\n]+') do
        local clean = line:gsub('{%x%x%x%x%x%x}', '')

        local index, content = clean:match(
            '^%s*%[(%d+)%]%s*(.*)$'
        )

        if index then
            content = content or ''
            local house = getHouseNumber(content)
            local label

            if house then
                label = 'Дом №' .. house
            else
                local cleaned = content
                    :gsub('^%s+', '')
                    :gsub('%s+$', '')

                label = cleaned ~= ''
                    and u8(cleaned)
                    or ('Место спавна №' .. index)
            end

            parsed[#parsed + 1] = {
                index = tonumber(index),
                responseIndex = responseIndex,
                house = house,
                label = label
            }

            responseIndex = responseIndex + 1
        end
    end

    return parsed
end

-- =====================================
-- ВЫБОР ДОМА
-- =====================================

local function selectRow(i)
    selected = i
end

local function selectEditorRow(i)
    if not rows[i] then return end

    editorSelected = i

    local row = rows[i]
    local note = ''

    if row.house then
        note = notes[tostring(row.house)] or ''
    end

    imgui.StrCopy(
        noteInput,
        trimUtf8(note, MAX_NOTE_LENGTH)
    )

    -- После выбора дома передаём фокус полю ввода
    editorFocusPending = true
end

-- =====================================
-- ПЕРЕХВАТ ДИАЛОГА
-- =====================================

function sampev.onShowDialog(
    dialogId, style, title, button1, button2, text
)
    if dialogId ~= DIALOG_ID then return end

    local parsed = parseDialog(text)
    if #parsed == 0 then return end

    rows = parsed
    selected = 0
    editorSelected = 0
    editorWindow[0] = false
    captured = true
    window[0] = true
    editorFocusPending = false

    imgui.StrCopy(noteInput, '')

    return false
end

-- =====================================
-- ПРИМЕЧАНИЯ
-- =====================================

local function saveNote()
    local row = rows[editorSelected]
    if not row or not row.house then return end

    local id = tostring(row.house)
    local previous = notes[id]

    notes[id] = trimUtf8(
        ffi.string(noteInput),
        MAX_NOTE_LENGTH
    )

    if saveNotes() then
        imgui.StrCopy(noteInput, notes[id])
        chat('Примечание сохранено.', 0xAAFFAA)
    else
        notes[id] = previous
        chat('Ошибка сохранения!', 0xFF4444)
    end
end

local function deleteNote()
    local row = rows[editorSelected]
    if not row or not row.house then return end

    local id = tostring(row.house)
    local previous = notes[id]

    notes[id] = nil

    if saveNotes() then
        imgui.StrCopy(noteInput, '')
        chat('Примечание удалено.', 0xFFCC66)
    else
        notes[id] = previous
        chat('Ошибка удаления!', 0xFF4444)
    end
end

-- =====================================
-- ВЫБОР СПАВНА
-- =====================================

local function chooseSpawn()
    local row = rows[selected]

    if not row or not captured then
        chat('Выбери место спавна.', 0xFFAAAA)
        return
    end

    local ok, err = pcall(function()
        sampSendDialogResponse(
            DIALOG_ID,
            1,
            row.responseIndex,
            ''
        )
    end)

    if not ok then
        print('[HouseNotes] Spawn error: ' .. tostring(err))
        chat('Ошибка выбора спавна.', 0xFFAAAA)
        return
    end

    captured = false
    window[0] = false
end

-- =====================================
-- MIMGUI
-- =====================================

imgui.OnInitialize(function()
    local io = imgui.GetIO()
    io.IniFilename = nil
    io.FontGlobalScale = FONT_SCALE
end)

-- =====================================
-- КАРТОЧКИ ДОМОВ
-- =====================================

local function drawRow(i, row, editor)
    local active =
        (editor and editorSelected or selected) == i

    imgui.PushStyleColor(
        imgui.Col.ChildBg,
        active and PANEL_ACTIVE or PANEL
    )

    local width = math.max(
        80,
        imgui.GetContentRegionAvail().x - 8
    )

    imgui.BeginChild(
        '##Card' .. (editor and 'E' or 'S') .. i,
        imgui.ImVec2(width, CARD_H),
        true
    )

    local x = imgui.GetCursorPosX()
    local y = imgui.GetCursorPosY()
    local avail = imgui.GetContentRegionAvail().x

    imgui.Text(row.label)

    if row.house then
        local note = notes[tostring(row.house)]

        if note and note ~= '' then
            local noteWidth = imgui.CalcTextSize(note).x
            local rightX = x + avail - noteWidth - 5

            if rightX >=
                x + imgui.CalcTextSize(row.label).x + 12 then

                imgui.SetCursorPos(
                    imgui.ImVec2(rightX, y)
                )

                imgui.TextColored(MUTED, note)
            end
        end
    end

    -- Обрабатываем клик только внутри этой карточки.
    -- Это не даёт списку перехватывать клики
    -- по полю ввода в соседней панели.
    local hovered = imgui.IsWindowHovered()

    if hovered and imgui.IsMouseClicked(0) then
        if editor then
            if editorSelected ~= i then
                selectEditorRow(i)
            end
        else
            selectRow(i)
        end
    end

    if hovered
        and not editor
        and imgui.IsMouseDoubleClicked(0) then

        selectRow(i)
        chooseSpawn()
    end

    if not editor and scrollSelected and selected == i then
        imgui.SetScrollHereY(0.5)
    end

    imgui.EndChild()
    imgui.PopStyleColor()
end

-- =====================================
-- ОКНО ВЫБОРА СПАВНА
-- =====================================

local function drawSpawnWindow()

    pushStyle()
    centerWindow(SPAWN_WINDOW_W, SPAWN_WINDOW_H)

    if beginOrangeWindow('House Notes v1.0') then
        local count = 0

        for _, row in ipairs(rows) do
            if row.house then count = count + 1 end
        end

        imgui.TextColored(MUTED, 'Автор: Aurelien')
        imgui.SameLine()
        imgui.TextColored(MUTED, tostring(count) .. ' домов')
        imgui.Separator()

        local remaining = imgui.GetContentRegionAvail().y

        imgui.BeginChild(
            '##SpawnList',
            imgui.ImVec2(0, math.max(50, remaining - 78)),
            false
        )

        for i, row in ipairs(rows) do
            drawRow(i, row, false)
        end

        scrollSelected = false
        imgui.EndChild()
        imgui.Separator()

        local bw = math.min(260, SPAWN_WINDOW_W - 35)
        local bh = 40

        local avail = imgui.GetContentRegionAvail()
        local cx = imgui.GetCursorPosX()
        local cy = imgui.GetCursorPosY()

        imgui.SetCursorPos(
            imgui.ImVec2(
                cx + math.max(0, (avail.x - bw) / 2),
                cy + math.max(0, (avail.y - bh) / 2)
            )
        )

        if orangeButton(
            'Выбрать место спавна', bw, bh
        ) then
            chooseSpawn()
        end
    end

    imgui.End()
    imgui.PopStyleColor(STYLE_COLOR_COUNT)
end

-- =====================================
-- ОКНО РЕДАКТОРА
-- =====================================

local function drawEditorWindow()

    pushStyle()
    centerWindow(EDITOR_WINDOW_W, EDITOR_WINDOW_H)

    if beginOrangeWindow('HouseNotes - Редактор##session' .. editorSession) then
        imgui.TextColored(MUTED, 'Дома')
        imgui.Separator()

        local avail = imgui.GetContentRegionAvail()
        local leftWidth = math.max(130, avail.x * 0.42)
        local contentHeight = math.max(80, avail.y - 55)

        -- Список домов
        imgui.BeginChild(
            '##EditorList',
            imgui.ImVec2(leftWidth, contentHeight),
            false
        )

        for i, row in ipairs(rows) do
            drawRow(i, row, true)
        end

        imgui.EndChild()
        imgui.SameLine()

        -- Редактор текста
        imgui.BeginChild(
            '##EditorPanel',
            imgui.ImVec2(0, contentHeight),
            false
        )

        local row = rows[editorSelected]

        if row then
            imgui.TextColored(
                MUTED,
                'Примечание для ' .. row.label
            )

            if row.house then

                -- Исправление:
                -- устанавливаем фокус непосредственно
                -- перед созданием поля ввода.
                if editorFocusPending then
                    imgui.SetKeyboardFocusHere()
                    editorFocusPending = false
                end

                -- Не переустанавливаем фокус каждый кадр: это сбивает курсор.
                -- ImGui самостоятельно сохраняет активность поля после клика.
                imgui.InputTextMultiline(
                    '##note',
                    noteInput,
                    ffi.sizeof(noteInput),
                    imgui.ImVec2(-1, 90)
                )

                local current = ffi.string(noteInput)

                local trimmed, count = trimUtf8(
                    current,
                    MAX_NOTE_LENGTH
                )

                -- Не переписываем буфер во время редактирования.
                -- Ограничение в 20 символов применяется в saveNote().

                imgui.TextColored(
                    MUTED,
                    tostring(count) .. ' / ' .. MAX_NOTE_LENGTH
                )

                if imgui.Button(
                    'Сохранить',
                    imgui.ImVec2(-1, 42)
                ) then
                    saveNote()
                end

                if imgui.Button(
                    'Удалить',
                    imgui.ImVec2(-1, 42)
                ) then
                    deleteNote()
                end
            else
                editorFocusPending = false
                imgui.TextColored(
                    MUTED,
                    'Для этого места нет номера дома'
                )
            end
        else
            imgui.TextColored(MUTED, 'Выбери дом')
        end

        imgui.EndChild()
        imgui.Separator()

        -- Кнопка закрытия
        local closeWidth = 180
        local closeHeight = 40
        local closeAvail = imgui.GetContentRegionAvail()

        local closeX = imgui.GetCursorPosX()
        local closeY = imgui.GetCursorPosY()

        imgui.SetCursorPos(
            imgui.ImVec2(
                closeX + math.max(
                    0, (closeAvail.x - closeWidth) / 2
                ),
                closeY + math.max(
                    0, (closeAvail.y - closeHeight) / 2
                )
            )
        )

        if orangeButton(
            'Закрыть', closeWidth, closeHeight
        ) then
            editorWindow[0] = false
            editorFocusPending = false
        end
    end

    imgui.End()
    imgui.PopStyleColor(STYLE_COLOR_COUNT)
end

-- Один общий OnFrame вместо двух независимых обработчиков mimgui.
-- Так окна не конкурируют за обработку клавиатуры и состояние курсора.
local mainFrame = imgui.OnFrame(function()
    return window[0] or editorWindow[0]
end, function()
    if window[0] then
        drawSpawnWindow()
    elseif editorWindow[0] then
        drawEditorWindow()
    end
end)
mainFrame.LockPlayer = true
mainFrame.HideCursor = false

-- =====================================
-- ESC БЕЗ ОТКРЫТИЯ ПАУЗЫ
-- =====================================

addEventHandler('onWindowMessage', function(msg, wparam, lparam)
    if wparam ~= 0x1B then return end

    if msg == 0x100 or msg == 0x104 then
        if editorWindow[0] or window[0] then
            if window[0] and captured then
                pcall(sampSendDialogResponse, DIALOG_ID, 0, 0, '')
                captured = false
            end
            editorWindow[0] = false
            window[0] = false
            editorFocusPending = false
            pendingEditorOpen = false
            consumeEscapeRelease = true
            consumeWindowMessage(true, false)

        elseif consumeEscapeRelease then
            consumeWindowMessage(true, false)
        end

    elseif msg == 0x101 or msg == 0x105 then
        if consumeEscapeRelease then
            consumeWindowMessage(true, false)
            consumeEscapeRelease = false
        end
    end
end)

-- =====================================
-- ЗАПУСК
-- =====================================

function main()
    while not isSampAvailable() do
        wait(100)
    end

    sampRegisterChatCommand('hnotes', function()
        if #rows == 0 then
            chat('Список домов ещё не получен.', 0xFFAAAA)
            return
        end

        if captured then
            chat('Редактор доступен после спавна.', 0xFFCC66)
            return
        end

        if editorWindow[0] then
            -- Закрытие уже открытого окна.
            editorWindow[0] = false
            pendingEditorOpen = false
            editorFocusPending = false
        else
            -- Не открывать ImGui внутри обработки команды чата:
            -- SA-MP может сбросить захват клавиатуры после callback.
            pendingEditorOpen = true
            pendingEditorAt = getGameTimer() + 250
        end
    end)

    chat('House Notes 1.0.0 загружен. /hnotes', 0xFFA33C)

    while true do
        wait(0)

        -- Открытие после полного закрытия игрового чата.
        if pendingEditorOpen and getGameTimer() >= pendingEditorAt then
            if not sampIsChatInputActive() and not sampIsDialogActive() then
                pendingEditorOpen = false
                editorSession = editorSession + 1
                editorWindow[0] = true
                -- Не принуждаем фокус при открытии: пользователь нажимает на поле сам.
                -- Новый ID окна сбрасывает сохранённое ImGui-состояние предыдущей сессии.
                local target = editorSelected > 0 and editorSelected or 1
                selectEditorRow(target)
                editorFocusPending = false
            end
        end

    
        if window[0] and captured then
            if isKeyJustPressed(0x26) and #rows > 0 then
                selectRow(
                    selected <= 1 and #rows or selected - 1
                )
                scrollSelected = true

            elseif isKeyJustPressed(0x28) and #rows > 0 then
                selectRow(
                    selected >= #rows and 1 or selected + 1
                )
                scrollSelected = true

            elseif isKeyJustPressed(0x0D) then
                chooseSpawn()
            end
        end
    end
end