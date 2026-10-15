-- FuelStation
-- Заменяет стандартный или CEF-диалог заправки /z на интерфейс mimgui.
-- Оба режима распознаются по содержимому, без постоянных id диалога.
-- Если формат изменится, серверное окно будет показано как обычно.
-- Кодировка файла: UTF-8.

script_name("Fuel Station")
script_author("Back1ng")
script_version("1.1.0")
script_description("Окно заправки вместо SA-MP/CEF-диалога /z (mimgui)")

require "lib.moonloader"

local imgui    = require 'lib.mimgui'
local sampev   = require 'lib.samp.events'
local encoding = require 'encoding'
local ffi      = require 'ffi'

encoding.default = 'CP1251'
local u8 = encoding.UTF8

----------------------------------------------------------------------
-- Константы
----------------------------------------------------------------------

local TANK_MAX      = 150   -- литров, максимум у всех машин
local ARM_TIMEOUT   = 10    -- сек: сколько ждём диалог после /z
local BUY_TIMEOUT   = 8     -- сек: сколько ждём подтверждения покупки
local CEF_PACKET_ID = 0xFA
local CEF_MAX_PACKET = 8192
local CEF_EVENT_IN  = 0x0C
local CEF_EVENT_OUT = 0x0D
local CEF_DIALOG_EVENT = 'cef:dialog'
local CEF_DIALOG_RESPONSE_EVENT = 'cef:dialogResponse'
local CEF_HUD_EVENT = 'cef:hud'

-- Якоря в тексте диалога (текст приходит в CP1251, конвертируется в UTF-8)
local ANCHOR_FREE    = 'поместится ещё%s+(%d+)'
local ANCHOR_PRICE   = 'топлива:%s+(%d+)'
local ANCHOR_STOCK   = 'АЗС:%s+(%d+)'
local ANCHOR_SUCCESS = 'SUCCESS'
local ANCHOR_LITRES  = 'Litres:'

-- Единая тёмная палитра. Жёлтый используется как основной акцент.
local C = {
  accent   = imgui.ImVec4(1.00, 0.80, 0.00, 1), -- #FFCC00
  accentHv = imgui.ImVec4(1.00, 0.86, 0.25, 1),
  accentAc = imgui.ImVec4(0.92, 0.70, 0.00, 1),
  ink      = imgui.ImVec4(0.09, 0.10, 0.11, 1), -- #16191D, текст на жёлтых кнопках
  panel    = imgui.ImVec4(0.12, 0.13, 0.16, 1), -- #1F2229
  title    = imgui.ImVec4(0.10, 0.11, 0.14, 1),
  card     = imgui.ImVec4(0.16, 0.17, 0.20, 1),
  frame    = imgui.ImVec4(0.20, 0.22, 0.25, 1),
  frameHv  = imgui.ImVec4(0.24, 0.26, 0.30, 1),
  second   = imgui.ImVec4(0.22, 0.24, 0.28, 1),
  secondHv = imgui.ImVec4(0.28, 0.30, 0.34, 1),
  border   = imgui.ImVec4(0.31, 0.34, 0.39, 1),
  text     = imgui.ImVec4(0.91, 0.92, 0.93, 1), -- #E8EAED
  muted    = imgui.ImVec4(0.60, 0.64, 0.68, 1), -- #9AA2AD
  low      = imgui.ImVec4(0.88, 0.31, 0.25, 1), -- #E0503F
  mid      = imgui.ImVec4(1.00, 0.69, 0.13, 1), -- #FFB020
  high     = imgui.ImVec4(0.49, 0.78, 0.31, 1), -- #7EC850
}

-- Точки статусбара (ImU32: 0xAABBGGRR)
local DOT = {
  muted = 0xFFADA29A,
  accent = 0xFF00CCFF,
  err = 0xFF3F50E0,
}

----------------------------------------------------------------------
-- Состояние
----------------------------------------------------------------------

local armed = false        -- ждём диалог заправки после /z
local armedUntil = 0

local S = {                -- данные текущей заправки (из перехваченного диалога)
  active = false,          -- окно открыто
  mode = nil,              -- 'dialog' или 'cef'
  dialogId = nil,
  station = nil,           -- название АЗС (UTF-8)
  price = nil,             -- $ за литр
  stock = nil,             -- остаток на АЗС, л
  free = nil,              -- сколько поместится, л
}

local fuelValue = nil -- топливо из TextDraw

local busy = false         -- покупка отправлена, ждём подтверждение
local busyUntil = 0

local windowOpen = imgui.new.bool(true)
local litres = imgui.new.int(0)

local statusText = ''
local statusCol = C.muted
local statusDot = DOT.muted

----------------------------------------------------------------------
-- Утилиты
----------------------------------------------------------------------

local function setStatus(text, col, dot)
  statusText = text
  statusCol = col
  statusDot = dot
end

local function stripColors(s)
  return (s:gsub('{%x%x%x%x%x%x}', ''))
end

local function formatNumber(value)
  if value == nil then return '—' end
  return tostring(math.floor(value)):reverse():gsub('(%d%d%d)', '%1 '):reverse():gsub('^%s+', '')
end

-- Диалоги приходят в CP1251 -> конвертируем в UTF-8 для сопоставления и imgui
local function toUtf8(s)
  if s == nil then return '' end
  local ok, res = pcall(function() return u8:encode(s) end)
  if ok and res then return res end
  return tostring(s)
end

local function getBitStreamReadOffset(bs)
  if type(raknetBitStreamGetReadOffset) ~= 'function' then return nil end
  local ok, offset = pcall(raknetBitStreamGetReadOffset, bs)
  return ok and offset or nil
end

local function restoreBitStreamReadOffset(bs, offset)
  if offset ~= nil and type(raknetBitStreamSetReadOffset) == 'function' then
    local ok = pcall(raknetBitStreamSetReadOffset, bs, offset)
    if ok then return end
  end
  raknetBitStreamResetReadPointer(bs)
end

local function readPacketBytes(bs)
  if bs == nil or bs == 0 then return '' end
  local size = raknetBitStreamGetNumberOfBytesUsed(bs)
  if not size or size <= 0 or size > CEF_MAX_PACKET then return '' end

  local savedOffset = getBitStreamReadOffset(bs)
  local buffer = ffi.new('uint8_t[?]', size)
  raknetBitStreamResetReadPointer(bs)
  local ok = raknetBitStreamReadBuffer(
    bs,
    tonumber(ffi.cast('intptr_t', buffer)),
    size)
  restoreBitStreamReadOffset(bs, savedOffset)

  if ok == false then return '' end
  return ffi.string(buffer, size)
end

local function parseCefEvent(bs)
  local raw = readPacketBytes(bs)
  if #raw < 6 then return nil end

  local index = 1
  if raw:byte(index) == CEF_PACKET_ID then index = index + 1 end
  if raw:byte(index) ~= CEF_EVENT_IN then return nil end
  index = index + 1

  local nameLength = raw:byte(index)
  if not nameLength or nameLength <= 0 or nameLength > 63 then return nil end
  index = index + 1

  local nameEnd = index + nameLength - 1
  if nameEnd + 2 > #raw then return nil end
  local eventName = raw:sub(index, nameEnd)
  index = nameEnd + 1

  local payloadLength = raw:byte(index) + raw:byte(index + 1) * 256
  index = index + 2
  if payloadLength < 0 or index + payloadLength - 1 > #raw then return nil end

  return eventName, raw:sub(index, index + payloadLength - 1)
end

local function sendCefEvent(eventName, payload)
  local bs = raknetNewBitStream()
  if not bs or bs == 0 then return false end

  local ok = pcall(function()
    raknetBitStreamWriteInt8(bs, CEF_PACKET_ID)
    raknetBitStreamWriteInt8(bs, CEF_EVENT_OUT)
    raknetBitStreamWriteInt8(bs, #eventName)
    raknetBitStreamWriteString(bs, eventName)
    raknetBitStreamWriteInt16(bs, #payload)
    raknetBitStreamWriteString(bs, payload)
    raknetSendBitStreamEx(bs, 1, 9, 0)
  end)

  raknetDeleteBitStream(bs)
  return ok
end

local function parseCefDialog(payload)
  local decoded = toUtf8(payload)
  if decoded:match('"DIALOG_SHOW"%s*:%s*(%a+)') ~= 'true' then return nil end
  if tonumber(decoded:match('"DIALOG_TYPE"%s*:%s*(-?%d+)')) ~= 1 then return nil end

  local title = decoded:match('"DIALOG_HEADER"%s*:%s*"(.-)"')
  local text = decoded:match('"DIALOG_TEXT"%s*:%s*"(.-)"%s*,%s*"DIALOG_KEYS"')
  if not title or not text then return nil end

  text = text:gsub('<br%s*/?>', '\n')
  return stripColors(title), stripColors(text)
end

-- Сколько литров реально доступно: свободное место, ограниченное деньгами
local function computeAvail()
  if not S.free or S.free <= 0 then return 0 end
  local cap = S.free
  if S.price and S.price > 0 then
    local money = math.max(0, math.floor(getPlayerMoney()))
    cap = math.min(cap, math.floor(money / S.price))
  end
  return cap
end

local function openSession(mode, station, price, stock, free, dialogId)
  armed = false
  busy = false

  S.active = true
  S.mode = mode
  S.dialogId = dialogId
  S.station = station
  S.price = price and tonumber(price) or nil
  S.stock = stock and tonumber(stock) or nil
  S.free = tonumber(free) or 0

  windowOpen[0] = true
  litres[0] = math.max(0, math.min(litres[0], computeAvail()))

  if S.free <= 0 then
    setStatus('Бак полон — заправка не требуется', C.accent, DOT.accent)
  elseif computeAvail() <= 0 then
    setStatus('Не хватает денег', C.low, DOT.err)
  else
    setStatus('', C.muted, DOT.muted)
  end
end

local function fuelColor(value)
  if not value then return C.muted end
  local frac = value / TANK_MAX
  if frac < 0.25 then return C.low end
  if frac < 0.55 then return C.mid end
  return C.high
end

local function closeSession()
  S.active = false
  S.mode = nil
  S.dialogId = nil
  armed = false
  busy = false
  windowOpen[0] = true -- следующий /z откроет окно заново
end

local function sendSessionResponse(button, input)
  input = tostring(input or '')

  if S.mode == 'dialog' and S.dialogId then
    sampSendDialogResponse(S.dialogId, button, -1, input)
    return true
  end

  if S.mode == 'cef' then
    local payload = string.format('%d 0 %s', button, input)
    return sendCefEvent(CEF_DIALOG_RESPONSE_EVENT, payload)
  end

  return false
end

local function cancelSession()
  if not S.active then return end
  if not busy then sendSessionResponse(0, '') end
  closeSession()
end

-- Покупка: способ ответа зависит от источника диалога
local function buy(count)
  if busy or not S.active or not S.mode then return end
  count = math.floor(tonumber(count) or 0)
  if count <= 0 then return end

  if not sendSessionResponse(1, tostring(count)) then
    setStatus('Не удалось отправить запрос', C.low, DOT.err)
    return
  end

  busy = true
  busyUntil = os.clock() + BUY_TIMEOUT
  setStatus('Идёт заправка…', C.accent, DOT.accent)
end

----------------------------------------------------------------------
-- Перехват SA-MP
----------------------------------------------------------------------

-- Топливо приходит в любом TextDraw с подстрокой Fuel_<N>; id не важен
local function trackFuelText(text)
  local v = tostring(text or ''):match('Fuel_(%d+)')
  if v then
    fuelValue = tonumber(v)
  end
end

function sampev.onShowTextDraw(_, data)
  trackFuelText(data and data.text)
end

function sampev.onTextDrawSetString(_, text)
  trackFuelText(text)
end

local function trackCefHud(payload)
  local value = toUtf8(payload):match('"fuel"%s*:%s*(%d+)')
  if value then fuelValue = tonumber(value) end
end

-- CEF лаунчера передаёт диалоги и HUD в RakNet-пакете 0xFA.
addEventHandler('onReceivePacket', function(id, bs)
  if id ~= CEF_PACKET_ID then return end

  local eventName, payload = parseCefEvent(bs)
  if not eventName then return end

  if eventName == CEF_HUD_EVENT then
    trackCefHud(payload)
    return
  end

  if not armed or eventName ~= CEF_DIALOG_EVENT then return end

  local title, text = parseCefDialog(payload)
  if not title or not text then return end

  local free = text:match(ANCHOR_FREE)
  if not free then return end -- не заправка: CEF должен показать родное окно

  local price = text:match(ANCHOR_PRICE)
  local stock = text:match(ANCHOR_STOCK)
  openSession('cef', title, price, stock, free, nil)

  return false
end)

-- /z ставит флаг: ближайший подходящий диалог перехватываем
function sampev.onSendCommand(command)
  if type(command) == 'string' and command:match('^/z%s*$') then
    armed = true
    armedUntil = os.clock() + ARM_TIMEOUT
  end
end

-- Возвращаем false (глушим) только наш диалог; чужие не трогаем
function sampev.onShowDialog(dialogId, style, title, button1, button2, text)
  if not armed then return end

  local utfText = stripColors(toUtf8(text))
  local free = utfText:match(ANCHOR_FREE)
  if not free then return end -- не заправка: показать родной диалог

  local price = utfText:match(ANCHOR_PRICE)
  local stock = utfText:match(ANCHOR_STOCK)
  openSession('dialog', stripColors(toUtf8(title)), price, stock, free, dialogId)

  return false
end

-- Подтверждение покупки: "~p~~h~SUCCESS!~n~~w~Summa: 5$~n~~w~Litres: 1"
-- Окно закрывается: покупка завершена, сервер сам показывает GameText
function sampev.onDisplayGameText(style, time, text)
  if not busy then return end
  local t = tostring(text or '')
  if not (t:find(ANCHOR_SUCCESS, 1, true) and t:find(ANCHOR_LITRES, 1, true)) then return end

  busy = false
  closeSession()
end

----------------------------------------------------------------------
-- Окно
----------------------------------------------------------------------

local function drawWindow()
  local cx, cy = getScreenResolution()
  local hasStatus = statusText ~= ''
  local windowW = 440
  local windowH = hasStatus and 370 or 346
  imgui.SetNextWindowPos(imgui.ImVec2(cx * 0.5 - windowW * 0.5, cy * 0.5 - windowH * 0.5), imgui.Cond.FirstUseEver)
  imgui.SetNextWindowSize(imgui.ImVec2(windowW, windowH), imgui.Cond.Always)

  imgui.PushStyleVarVec2(imgui.StyleVar.WindowPadding, imgui.ImVec2(12, 10))
  imgui.PushStyleVarFloat(imgui.StyleVar.WindowRounding, 6)
  imgui.PushStyleVarFloat(imgui.StyleVar.WindowBorderSize, 1)
  imgui.PushStyleVarVec2(imgui.StyleVar.FramePadding, imgui.ImVec2(8, 6))
  imgui.PushStyleVarFloat(imgui.StyleVar.FrameRounding, 4)
  imgui.PushStyleVarVec2(imgui.StyleVar.ItemSpacing, imgui.ImVec2(8, 6))
  imgui.PushStyleVarFloat(imgui.StyleVar.GrabMinSize, 12)
  imgui.PushStyleVarFloat(imgui.StyleVar.GrabRounding, 4)
  imgui.PushStyleVarFloat(imgui.StyleVar.ChildRounding, 4)

  imgui.PushStyleColor(imgui.Col.Text, C.text)
  imgui.PushStyleColor(imgui.Col.WindowBg, C.panel)
  imgui.PushStyleColor(imgui.Col.ChildBg, C.card)
  imgui.PushStyleColor(imgui.Col.Border, C.border)
  imgui.PushStyleColor(imgui.Col.TitleBg, C.title)
  imgui.PushStyleColor(imgui.Col.TitleBgActive, C.title)
  imgui.PushStyleColor(imgui.Col.TitleBgCollapsed, C.title)
  imgui.PushStyleColor(imgui.Col.Separator, C.border)
  imgui.PushStyleColor(imgui.Col.FrameBg, C.frame)
  imgui.PushStyleColor(imgui.Col.FrameBgHovered, C.frameHv)
  imgui.PushStyleColor(imgui.Col.FrameBgActive, C.frameHv)
  imgui.PushStyleColor(imgui.Col.SliderGrab, C.accent)
  imgui.PushStyleColor(imgui.Col.SliderGrabActive, C.accentHv)

  local flags = imgui.WindowFlags.NoCollapse + imgui.WindowFlags.NoResize
  imgui.Begin('Заправочная станция##fuelstation', windowOpen, flags)

  local function alignRight(txt, rightPadding)
    rightPadding = rightPadding or 12
    imgui.SameLine(imgui.GetWindowWidth() - imgui.CalcTextSize(txt).x - rightPadding)
  end

  local function infoRow(label, value, valueColor)
    imgui.PushStyleColor(imgui.Col.Text, C.muted)
    imgui.Text(label)
    imgui.PopStyleColor(1)
    alignRight(value)
    imgui.PushStyleColor(imgui.Col.Text, valueColor or C.text)
    imgui.TextUnformatted(value)
    imgui.PopStyleColor(1)
  end

  -- Название станции крупнее остальных данных.
  imgui.SetWindowFontScale(1.10)
  imgui.PushStyleColor(imgui.Col.Text, C.accent)
  imgui.TextUnformatted(S.station or 'АЗС')
  imgui.PopStyleColor(1)
  imgui.SetWindowFontScale(1.00)

  imgui.Separator()

  infoRow('Цена топлива', S.price and (formatNumber(S.price) .. ' $/л') or '—')
  infoRow('Запас станции', S.stock and (formatNumber(S.stock) .. ' л') or '—')

  imgui.Separator()

  -- Количество топлива вынесено из полосы, чтобы цифры читались сразу.
  local fuel = fuelValue
  local fuelText = fuel and string.format('%d / %d л', fuel, TANK_MAX) or 'данных нет'
  infoRow('Топливо в баке', fuelText)
  imgui.PushStyleColor(imgui.Col.PlotHistogram, fuelColor(fuel))
  imgui.ProgressBar(fuel and math.min(1.0, fuel / TANK_MAX) or 0.0, imgui.ImVec2(-1, 18), '')
  imgui.PopStyleColor(1)

  imgui.Separator()

  -- Выбор объёма: текущее значение, предел, кнопки шага и ползунок.
  local avail = computeAvail()
  local canBuy = avail > 0 and not busy
  if litres[0] > avail then litres[0] = avail end
  local readout = string.format('%d / %d л', litres[0], avail)
  infoRow('Объём заправки', readout, C.accent)

  local stepButtonW = 30
  local sliderW = imgui.GetContentRegionAvail().x - stepButtonW * 2 - 16
  local oldLitres = litres[0]
  if not canBuy then imgui.PushStyleVarFloat(imgui.StyleVar.Alpha, 0.6) end

  imgui.PushStyleColor(imgui.Col.Button, C.second)
  imgui.PushStyleColor(imgui.Col.ButtonHovered, C.secondHv)
  imgui.PushStyleColor(imgui.Col.ButtonActive, C.frameHv)
  if imgui.Button('-##litresMinus', imgui.ImVec2(stepButtonW, 28)) and canBuy then
    litres[0] = math.max(0, litres[0] - 1)
  end
  imgui.SameLine()
  imgui.PushItemWidth(sliderW)
  imgui.SliderInt('##litres', litres, 0, math.max(avail, 1), '')
  imgui.PopItemWidth()
  imgui.SameLine()
  if imgui.Button('+##litresPlus', imgui.ImVec2(stepButtonW, 28)) and canBuy then
    litres[0] = math.min(avail, litres[0] + 1)
  end
  imgui.PopStyleColor(3)

  if not canBuy then
    litres[0] = oldLitres
    imgui.PopStyleVar()
  end

  -- Итог выделен отдельным спокойным блоком.
  local total = (S.price or 0) * litres[0]
  local totalTxt = formatNumber(total) .. ' $'
  imgui.BeginChild('##fuelTotal', imgui.ImVec2(0, 42), false)
  imgui.SetCursorPos(imgui.ImVec2(10, 10))
  imgui.PushStyleColor(imgui.Col.Text, C.muted)
  imgui.Text('К оплате')
  imgui.PopStyleColor(1)
  imgui.SetWindowFontScale(1.10)
  alignRight(totalTxt, 10)
  imgui.PushStyleColor(imgui.Col.Text, C.accent)
  imgui.TextUnformatted(totalTxt)
  imgui.PopStyleColor(1)
  imgui.SetWindowFontScale(1.00)
  imgui.EndChild()

  -- Главная кнопка сообщает точную сумму покупки.
  local canSubmit = canBuy and litres[0] > 0
  if not canSubmit then imgui.PushStyleVarFloat(imgui.StyleVar.Alpha, 0.55) end
  imgui.PushStyleColor(imgui.Col.Button, C.accent)
  imgui.PushStyleColor(imgui.Col.ButtonHovered, C.accentHv)
  imgui.PushStyleColor(imgui.Col.ButtonActive, C.accentAc)
  imgui.PushStyleColor(imgui.Col.Text, C.ink)
  local buyLabel = litres[0] > 0 and ('ЗАПРАВИТЬ — ' .. totalTxt) or 'ЗАПРАВИТЬ'
  if imgui.Button(buyLabel .. '##fuelBuy', imgui.ImVec2(-1, 36)) and canSubmit then
    buy(litres[0])
  end
  imgui.PopStyleColor(4)
  if not canSubmit then imgui.PopStyleVar() end

  if not canBuy then imgui.PushStyleVarFloat(imgui.StyleVar.Alpha, 0.55) end
  imgui.PushStyleColor(imgui.Col.Button, C.second)
  imgui.PushStyleColor(imgui.Col.ButtonHovered, C.secondHv)
  imgui.PushStyleColor(imgui.Col.ButtonActive, C.frameHv)
  imgui.PushStyleColor(imgui.Col.Text, C.text)
  if imgui.Button('ЗАПРАВИТЬ ПОЛНЫЙ БАК##fuelFull', imgui.ImVec2(-1, 30)) and canBuy then
    buy(avail)
    litres[0] = 0
  end
  imgui.PopStyleColor(4)
  if not canBuy then imgui.PopStyleVar() end

  -- Статус показывается только тогда, когда он действительно полезен.
  if hasStatus then
    imgui.Separator()
    local p = imgui.GetCursorScreenPos()
    local dl = imgui.GetWindowDrawList()
    local lineH = imgui.GetTextLineHeight()
    dl:AddCircleFilled(imgui.ImVec2(p.x + 4, p.y + lineH * 0.5), 4, statusDot)
    imgui.Dummy(imgui.ImVec2(8, lineH))
    imgui.SameLine()
    imgui.PushStyleColor(imgui.Col.Text, statusCol)
    imgui.TextUnformatted(statusText)
    imgui.PopStyleColor(1)
  end

  imgui.End()
  imgui.PopStyleColor(13)
  imgui.PopStyleVar(9)

  if not windowOpen[0] then
    if busy then
      windowOpen[0] = true
    else
      cancelSession()
    end
  end
end

----------------------------------------------------------------------
-- main
----------------------------------------------------------------------

function main()
  if not isSampLoaded() or not isSampfuncsLoaded() then return end
  while not isSampAvailable() do wait(100) end

  imgui.Process = true
  imgui.OnFrame(function() return S.active end, drawWindow)

  while true do
    wait(250)
    local now = os.clock()
    if armed and now > armedUntil then
      armed = false -- диалог не пришёл: окна нет, родной /z не тронут
    end
    if busy and now > busyUntil then
      busy = false
      setStatus('Сервер не подтвердил покупку', C.low, DOT.err)
    end
  end
end