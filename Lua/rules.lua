script_name('Rules')
script_author('HarikAng')
script_version('1.0')


local imgui = require 'mimgui'
local ffi = require 'ffi'
local encoding = require 'encoding'
encoding.default = 'CP1251'
local u8 = encoding.utf8
local vkeys = require 'vkeys'

local okFa, fa = pcall(require, 'fAwesome6')
if not okFa then fa = nil end

local new = imgui.new
local ImVec2, ImVec4 = imgui.ImVec2, imgui.ImVec4
local floor, max, min, abs, exp, sin, cos, pi = math.floor, math.max, math.min, math.abs, math.exp, math.sin, math.cos, math.pi

local DEFAULT_RULES   
local RULES_REV = 1   
local DIR = ''
local data = nil

-- =====================================================================
--  УТИЛИТЫ
-- =====================================================================
local function clamp(v, a, b) return v < a and a or (v > b and b or v) end
local function easeOut(t) t = 1 - clamp(t, 0, 1); return 1 - t * t * t end

local function lower1251(s)
    s = s:gsub('[\192-\223]', function(c) return string.char(c:byte() + 32) end)
    s = s:gsub('\168', '\184')
    return s:lower()
end

local function upper1251(s)
    s = s:gsub('[\224-\255]', function(c) return string.char(c:byte() - 32) end)
    s = s:gsub('\184', '\168')
    return s:upper()
end

local function trim(s) return (s:gsub('^%s+', ''):gsub('%s+$', '')) end

local function deepcopy(t)
    if type(t) ~= 'table' then return t end
    local r = {}
    for k, v in pairs(t) do r[k] = deepcopy(v) end
    return r
end

local function plural(n)
    local m10, m100 = n % 10, n % 100
    if m10 == 1 and m100 ~= 11 then return 'правило' end
    if m10 >= 2 and m10 <= 4 and (m100 < 10 or m100 >= 20) then return 'правила' end
    return 'правил'
end

local u8cache, u8n = {}, 0
local function U(s)
    local v = u8cache[s]
    if not v then
        if u8n > 2000 then u8cache, u8n = {}, 0 end
        v = u8(s)
        u8cache[s] = v
        u8n = u8n + 1
    end
    return v
end

local function bufFromString(str, size)
    local b = new.char[size]()
    ffi.copy(b, str, min(#str, size - 1))
    return b
end

local function hsv2rgb(h, s, v)
    local i = floor(h * 6)
    local f = h * 6 - i
    local p, q, t = v * (1 - s), v * (1 - f * s), v * (1 - (1 - f) * s)
    i = i % 6
    if i == 0 then return v, t, p
    elseif i == 1 then return q, v, p
    elseif i == 2 then return p, v, t
    elseif i == 3 then return p, q, v
    elseif i == 4 then return t, p, v
    else return v, p, q end
end

local function rgb2hsv(r, g, b)
    local mx, mn = max(r, g, b), min(r, g, b)
    local d = mx - mn
    local h = 0
    if d > 0 then
        if mx == r then h = ((g - b) / d) % 6
        elseif mx == g then h = (b - r) / d + 2
        else h = (r - g) / d + 4 end
        h = h / 6
    end
    return h, (mx == 0) and 0 or d / mx, mx
end

-- =====================================================================
--  СОСТОЯНИЕ И НАСТРОЙКИ
-- =====================================================================
local winState = new.bool(false)

local G = {
    alpha = 1, openT = 0, dt = 0.016,
    px = nil, py = nil, cx = 0, cy = 0, snap = true, dragging = false,
    selected = 1,
    scrollBlock = nil, scrollTarget = 0, scrollFrames = 0, scrollReset = false,
    sdirty = false, sLast = 0,
    settingsOpen = false, gearAng = 0, listen = false, confirmReset = 0,
    wantAdd = false, wantDelete = false,
    toast = nil, inited = false,
    searchRaw = '', qwords = {}, searchList = {},
}

local DEFAULT_S = {
    accent = { 0.165, 0.78, 0.29 },
    textcol = { 0.93, 0.96, 0.93 },
    bgAlpha = 0.97,
    scale = 1.0,
    rounding = 12,
    anim = true,
    highlight = true,
    esc = true,
    hotkey = 0,
    w = 1100, h = 620,
}
local S = deepcopy(DEFAULT_S)

local PRESETS = {
    { n = 'Зелёная',    c = { 0.165, 0.78, 0.29 } },
    { n = 'Бирюзовая',  c = { 0.12, 0.80, 0.78 } },
    { n = 'Синяя',      c = { 0.28, 0.56, 1.00 } },
    { n = 'Фиолетовая', c = { 0.67, 0.42, 1.00 } },
    { n = 'Розовая',    c = { 1.00, 0.42, 0.72 } },
    { n = 'Красная',    c = { 0.95, 0.28, 0.28 } },
    { n = 'Оранжевая',  c = { 1.00, 0.60, 0.20 } },
    { n = 'Графит',     c = { 0.78, 0.80, 0.84 } },
}

local COL, KIND = {}, {}
local fonts = {}
local bufs = {}
local edit = { active = false, name = nil, buf = nil }
local addNameBuf = new.char[128]()
local searchBuf = new.char[256]()
local anim = { sel = setmetatable({}, { __mode = 'k' }), hov = setmetatable({}, { __mode = 'k' }) }
local parsedCache = setmetatable({}, { __mode = 'k' })

local function markDirty() G.sdirty = true; G.sLast = os.clock() end
local function toast(msg) G.toast = { t = os.clock(), text = u8(msg) } end

local function c32(c, am)
    local a = (c[4] or 1) * (am or 1) * G.alpha
    return floor(a * 255 + 0.5) * 16777216 + floor(c[3] * 255 + 0.5) * 65536
        + floor(c[2] * 255 + 0.5) * 256 + floor(c[1] * 255 + 0.5)
end
local function V4(c, am) return ImVec4(c[1], c[2], c[3], (c[4] or 1) * (am or 1)) end

-- =====================================================================
--  ТЕМА (всё строится от одного цвета акцента)
-- =====================================================================
local function rebuildTheme()
    local a = S.accent
    local h, s, v = rgb2hsv(a[1], a[2], a[3])
    local ba = S.bgAlpha
    local function sh(sm, val, al)
        local r, g, b = hsv2rgb(h, clamp(s * sm, 0, 1), val)
        return { r, g, b, al or 1 }
    end
    local ar, ag, ab = hsv2rgb(h, s, max(v, 0.55))

    COL.window  = sh(0.90, 0.070, ba)
    COL.panel   = sh(0.85, 0.150, ba)
    COL.content = sh(0.90, 0.045, ba)
    COL.frame   = sh(0.85, 0.150)
    COL.frameH  = sh(0.85, 0.210)
    COL.button  = sh(0.85, 0.190)
    COL.btnHov  = sh(0.80, 0.310)
    COL.btnAct  = sh(0.80, 0.400)
    COL.accent  = { ar, ag, ab, 1 }
    COL.accentBg = sh(0.90, 0.520)
    COL.sel     = { 0.5 + (ar - 0.5) * 0.08 + 0.46, 0.5 + (ag - 0.5) * 0.08 + 0.46, 0.5 + (ab - 0.5) * 0.08 + 0.46, 1 }
    COL.dark    = sh(0.70, 0.100)
    COL.text    = { S.textcol[1], S.textcol[2], S.textcol[3], 1 }
    local wr, wg, wb = hsv2rgb(h, clamp(s * 0.9, 0, 1), 0.07)
    COL.dim     = { COL.text[1] * 0.55 + wr * 0.45, COL.text[2] * 0.55 + wg * 0.45, COL.text[3] * 0.55 + wb * 0.45, 1 }
    COL.danger  = { 0.65, 0.13, 0.13, 1 }
    COL.dangerH = { 0.85, 0.20, 0.20, 1 }

    KIND.num  = COL.accent
    KIND.pun  = { 1.00, 0.56, 0.46, 1 }
    KIND.note = { 1.00, 0.85, 0.45, 1 }

    if G.inited then
        local st = imgui.GetStyle()
        local r = S.rounding
        st.WindowRounding = r + 2
        st.ChildRounding = max(r - 2, 0)
        st.FrameRounding = max(r - 3, 0)
        st.PopupRounding = r
        st.GrabRounding = max(r - 4, 0)
        st.ScrollbarRounding = 8

        local c = st.Colors
        c[imgui.Col.WindowBg] = V4(COL.window)
        c[imgui.Col.ChildBg] = ImVec4(0, 0, 0, 0)
        c[imgui.Col.PopupBg] = V4(COL.panel, 1)
        c[imgui.Col.Text] = V4(COL.text)
        c[imgui.Col.TextDisabled] = V4(COL.dim)
        c[imgui.Col.Border] = V4(COL.btnHov, 0.8)
        c[imgui.Col.FrameBg] = V4(COL.frame)
        c[imgui.Col.FrameBgHovered] = V4(COL.frameH)
        c[imgui.Col.FrameBgActive] = V4(COL.btnHov)
        c[imgui.Col.Button] = V4(COL.button)
        c[imgui.Col.ButtonHovered] = V4(COL.btnHov)
        c[imgui.Col.ButtonActive] = V4(COL.btnAct)
        c[imgui.Col.Header] = V4(COL.btnHov)
        c[imgui.Col.HeaderHovered] = V4(COL.btnHov)
        c[imgui.Col.HeaderActive] = V4(COL.btnAct)
        c[imgui.Col.Separator] = V4(COL.accent, 0.35)
        c[imgui.Col.ScrollbarBg] = ImVec4(0, 0, 0, 0)
        c[imgui.Col.ScrollbarGrab] = V4(COL.btnHov)
        c[imgui.Col.ScrollbarGrabHovered] = V4(COL.btnAct)
        c[imgui.Col.ScrollbarGrabActive] = V4(COL.accentBg)
        c[imgui.Col.SliderGrab] = V4(COL.accent, 0.9)
        c[imgui.Col.SliderGrabActive] = V4(COL.accent)
        c[imgui.Col.CheckMark] = V4(COL.accent)
        c[imgui.Col.TextSelectedBg] = V4(COL.accentBg, 0.6)
        c[imgui.Col.ModalWindowDimBg] = ImVec4(0, 0, 0, 0.55)
    end
end

-- =====================================================================
--  ФАЙЛЫ: НАСТРОЙКИ И ПРАВИЛА
-- =====================================================================
local function saveSettings()
    local f = io.open(DIR .. 'settings.lua', 'wb')
    if not f then return end
    local o = { 'return {\n' }
    for k, v in pairs(S) do
        local tv = type(v)
        if tv == 'number' or tv == 'boolean' then
            o[#o + 1] = string.format('%s=%s,\n', k, tostring(v))
        elseif tv == 'table' then
            o[#o + 1] = string.format('%s={%.4f,%.4f,%.4f},\n', k, v[1], v[2], v[3])
        end
    end
    o[#o + 1] = '}\n'
    f:write(table.concat(o))
    f:close()
end

local function loadSettings()
    local path = DIR .. 'settings.lua'
    if not doesFileExist(path) then return end
    local chunk = loadfile(path)
    if not chunk then return end
    local ok, t = pcall(chunk)
    if not ok or type(t) ~= 'table' then return end
    for k, dv in pairs(DEFAULT_S) do
        local v = t[k]
        if type(v) == type(dv) then
            if type(v) == 'table' then
                if type(v[1]) == 'number' and type(v[2]) == 'number' and type(v[3]) == 'number' then S[k] = v end
            else
                S[k] = v
            end
        end
    end
    if type(t.x) == 'number' and type(t.y) == 'number' then S.x, S.y = t.x, t.y end
    S.scale = clamp(S.scale, 0.7, 1.6)
    S.bgAlpha = clamp(S.bgAlpha, 0.2, 1)
    S.rounding = clamp(S.rounding, 0, 24)
end

local function validateRules(t)
    if type(t) ~= 'table' or #t == 0 then return false end
    for _, cat in ipairs(t) do
        if type(cat.name) ~= 'string' or type(cat.content) ~= 'table' then return false end
        for _, l in ipairs(cat.content) do if type(l) ~= 'string' then return false end end
    end
    return true
end

local function saveRules()
    local f = io.open(DIR .. 'rules.lua', 'wb')
    if not f then return end
    local o = { string.format('return {rev=%d,data={\n', RULES_REV) }
    for _, cat in ipairs(data) do
        o[#o + 1] = string.format('{name=%q,content={\n', cat.name)
        for _, l in ipairs(cat.content) do o[#o + 1] = string.format('%q,\n', l) end
        o[#o + 1] = '}},\n'
    end
    o[#o + 1] = '}}\n'
    f:write(table.concat(o))
    f:close()
end

local function loadRules()
    local path = DIR .. 'rules.lua'
    if doesFileExist(path) then
        local chunk = loadfile(path)
        if chunk then
            local ok, res = pcall(chunk)
            if ok and type(res) == 'table' and validateRules(res.data) then
                if (res.rev or 0) >= RULES_REV then return res.data end
                os.rename(path, DIR .. 'rules_backup_' .. os.time() .. '.lua')
            end
        end
    end
    return deepcopy(DEFAULT_RULES)
end

-- =====================================================================
--  РАЗБОР РАЗМЕТКИ ПРАВИЛ И ВЁРСТКА
--  # заголовок | {RRGGBB} цвет | {STANDART} сброс | {fa:ИМЯ} иконка | - список
-- =====================================================================
local function hexcol(hex)
    return { tonumber(hex:sub(1, 2), 16) / 255, tonumber(hex:sub(3, 4), 16) / 255, tonumber(hex:sub(5, 6), 16) / 255, 1 }
end

local function addWords(toks, s, col, kind)
    if s:find('^%s') and #toks > 0 then toks[#toks].sp = true end
    for word, sp in s:gmatch('(%S+)(%s*)') do
        toks[#toks + 1] = { t = u8(word), col = col, kind = kind, sp = (sp ~= '') }
    end
end

-- Автоподсветка для строк без цветовых тегов: номер пункта, "Наказание:", примечания
local function highlightPieces(raw)
    local pieces = {}
    local num, rest = raw:match('^(%d[%d%.]*)(%s.*)$')
    if num then
        pieces[#pieces + 1] = { num, 'num' }
        raw = rest
    end
    local a = raw:find('Наказание:', 1, true) or raw:find('Наказания:', 1, true)
    if a then
        if a > 1 then pieces[#pieces + 1] = { raw:sub(1, a - 1), nil } end
        pieces[#pieces + 1] = { raw:sub(a), 'pun' }
        return pieces
    end
    local label = raw:match('^%s*(Примечание:)') or raw:match('^%s*(Исключение:)')
        or raw:match('^%s*(Дополнение:)') or raw:match('^%s*(Пример:)') or raw:match('^%s*(Важно:)')
    if label then
        local s, e = raw:find(label, 1, true)
        pieces[#pieces + 1] = { raw:sub(1, e), 'note' }
        pieces[#pieces + 1] = { raw:sub(e + 1), nil }
    else
        pieces[#pieces + 1] = { raw, nil }
    end
    return pieces
end

local function tokenize(raw, doUpper)
    local toks, plain = {}, {}
    if not raw:find('{', 1, true) then
        for _, p in ipairs(highlightPieces(raw)) do
            local text = doUpper and upper1251(p[1]) or p[1]
            addWords(toks, text, nil, p[2])
            plain[#plain + 1] = text
        end
        return toks, table.concat(plain)
    end
    local col = nil
    local i, n = 1, #raw
    local function lit(s)
        if s == '' then return end
        if doUpper then s = upper1251(s) end
        addWords(toks, s, col, nil)
        plain[#plain + 1] = s
    end
    while i <= n do
        local j = raw:find('{', i, true)
        if not j then lit(raw:sub(i)); break end
        if j > i then lit(raw:sub(i, j - 1)) end
        local hex = raw:match('^{(%x%x%x%x%x%x)}', j)
        if hex then
            col = hexcol(hex); i = j + 8
        elseif raw:find('^{STANDART}', j) then
            col = nil; i = j + 10
        else
            local nm = raw:match('^{fa:([%w_]+)}', j)
            if nm then
                local glyph = fa and fa[nm] or '*'
                toks[#toks + 1] = { t = glyph, col = col, sp = false }
                i = j + 5 + #nm
            else
                lit('{'); i = j + 1
            end
        end
    end
    return toks, table.concat(plain)
end

local function newBlock(kind, font, toks, plain)
    local b = { kind = kind, font = font, toks = toks, plain = plain, padTop = 0, padBot = 5, indent = 0, colKey = nil }
    if kind == 'head' then b.padTop, b.padBot, b.colKey = 16, 8, 'accent'
    elseif kind == 'title' then b.padBot, b.colKey = 10, 'text'
    elseif kind == 'rhead' then b.padTop, b.padBot, b.colKey = 12, 4, 'accent'
    elseif kind == 'info' then b.padBot, b.colKey = 8, 'dim'
    elseif kind == 'list' then b.indent = 24 end
    local url = plain:match('https?://%S+')
    if url then b.url = url end
    return b
end

local function parseCategory(cat)
    local P = { blocks = {}, heads = {}, count = 0 }
    local tt = tokenize(cat.name, true)
    P.blocks[1] = newBlock('title', 'title', tt, cat.name)
    for _, raw in ipairs(cat.content) do
        if raw:find('%S') then
            P.count = P.count + 1
            local first = raw:sub(1, 1)
            local b
            if first == '#' then
                local toks, plain = tokenize(trim(raw:sub(2)), true)
                b = newBlock('head', 'head', toks, plain)
                P.heads[#P.heads + 1] = { block = b, name = plain }
            elseif first == '-' then
                local toks, plain = tokenize(trim(raw:sub(2)), false)
                b = newBlock('list', 'base', toks, plain)
            else
                local toks, plain = tokenize(raw, false)
                b = newBlock('text', 'base', toks, plain)
            end
            P.blocks[#P.blocks + 1] = b
        else
            P.blocks[#P.blocks + 1] = newBlock('blank', 'base', {}, '')
        end
    end
    return P
end

local function getParsed(cat)
    local P = parsedCache[cat]
    if not P then
        P = parseCategory(cat)
        parsedCache[cat] = P
    end
    return P
end

local function invalidate(cat) parsedCache[cat] = nil end

-- Метрики шрифтов и кэш ширины слов
local M = { base = { lh = 20, sp = 5 }, small = { lh = 16, sp = 4 }, item = { lh = 20, sp = 5 },
            title = { lh = 28, sp = 7 }, head = { lh = 24, sp = 6 } }
local WC = { base = {}, small = {}, item = {}, title = {}, head = {} }
local layoutVer, lastScale = 1, -1

local function pushFont(f) if f then imgui.PushFont(f) end end
local function popFont(f) if f then imgui.PopFont() end end

local function refreshMetrics()
    local scale = imgui.GetIO().FontGlobalScale
    local changed = (scale ~= lastScale)
    for name, m in pairs(M) do
        pushFont(fonts[name])
        local lh = imgui.GetTextLineHeight()
        local sp = imgui.CalcTextSize(' ').x
        popFont(fonts[name])
        if sp <= 0 then sp = lh * 0.3 end
        if lh ~= m.lh or sp ~= m.sp then m.lh, m.sp = lh, sp; changed = true end
    end
    if changed then
        layoutVer = layoutVer + 1
        lastScale = scale
        for _, t in pairs(WC) do for k in pairs(t) do t[k] = nil end end
    end
end

local function wordW(fname, t)
    local c = WC[fname]
    local w = c[t]
    if not w then
        pushFont(fonts[fname])
        w = imgui.CalcTextSize(t).x
        popFont(fonts[fname])
        c[t] = w
    end
    return w
end

local function layoutBlock(b, width)
    if b.lw == width and b.lv == layoutVer then return b.h end
    local m = M[b.font]
    if b.kind == 'blank' then
        b.rows = {}
        b.h = M.base.lh * 0.5
    else
        local avail = width - b.indent
        local rows, row, x = {}, {}, 0
        for _, tk in ipairs(b.toks) do
            local w = wordW(b.font, tk.t)
            if x > 0 and x + w > avail then
                rows[#rows + 1] = row
                row, x = {}, 0
            end
            row[#row + 1] = { x = x, tk = tk }
            x = x + w + (tk.sp and m.sp or 0)
        end
        if #row > 0 or #rows == 0 then rows[#rows + 1] = row end
        b.rows = rows
        b.h = #rows * m.lh + b.padTop + b.padBot
    end
    b.lw, b.lv = width, layoutVer
    return b.h
end

local function drawBlock(b, dl, ox, oy, width)
    if b.kind == 'blank' then return end
    local m = M[b.font]
    pushFont(fonts[b.font])
    local defcol = b.colKey and COL[b.colKey] or COL.text
    local y = oy + b.padTop
    local x0 = ox + b.indent
    local hl = S.highlight
    for _, row in ipairs(b.rows) do
        for _, it in ipairs(row) do
            local tk = it.tk
            local col = tk.col
            if not col and hl and tk.kind then col = KIND[tk.kind] end
            dl:AddText(ImVec2(x0 + it.x, y), c32(col or defcol), tk.t)
        end
        y = y + m.lh
    end
    popFont(fonts[b.font])
    if b.kind == 'list' then
        dl:AddCircleFilled(ImVec2(ox + 10, oy + b.padTop + m.lh * 0.5), 2.6, c32(COL.accent), 10)
    elseif b.kind == 'head' or b.kind == 'title' then
        dl:AddLine(ImVec2(ox, y + 3), ImVec2(ox + width, y + 3), c32(COL.accent, b.kind == 'title' and 0.6 or 0.3), 1)
    end
end

-- Виртуализированный вывод списка блоков (рисуются только видимые)
local function drawBlocks(list, search)
    local dl = imgui.GetWindowDrawList()
    local wp = imgui.GetWindowPos()
    local wh = imgui.GetWindowHeight()
    local width = imgui.GetWindowWidth() - 36 - 14
    local start = imgui.GetCursorScreenPos()
    local x0 = start.x
    local mp = imgui.GetMousePos()
    local hovWin = imgui.IsWindowHovered()
    local lclick = imgui.IsMouseClicked(0)
    local rclick = imgui.IsMouseClicked(1)
    local top, bot = wp.y - 60, wp.y + wh + 60
    local y = 0
    local sb = G.scrollBlock

    for i = 1, #list do
        local b = list[i]
        local h = layoutBlock(b, width)
        if b == sb then G.scrollTarget = y end
        local sy = start.y + y
        if sy + h >= top and sy <= bot and b.kind ~= 'blank' then
            local hov = hovWin and mp.x >= x0 - 6 and mp.x <= x0 + width + 6 and mp.y >= sy and mp.y <= sy + h
            local clickable = (b.kind == 'rhead') or b.url
            if hov and clickable then imgui.SetMouseCursor(imgui.MouseCursor.Hand) end
            if hov and clickable then
                dl:AddRectFilled(ImVec2(x0 - 6, sy), ImVec2(x0 + width + 6, sy + h), c32(COL.accent, 0.13), 6)
            elseif search and b.kind ~= 'rhead' and b.kind ~= 'info' then
                dl:AddRectFilled(ImVec2(x0 - 6, sy), ImVec2(x0 + width + 6, sy + h - 2), c32(COL.accent, 0.06), 5)
            end
            drawBlock(b, dl, x0, sy, width)
            if hov then
                if lclick then
                    if b.kind == 'rhead' then
                        G.pendingJump = b
                    elseif b.url then
                        imgui.SetClipboardText(u8(b.url))
                        toast('Ссылка скопирована в буфер обмена')
                    end
                elseif rclick and b.plain ~= '' and b.kind ~= 'rhead' then
                    imgui.SetClipboardText(u8(b.plain))
                    toast('Строка скопирована (ПКМ)')
                end
            end
        end
        y = y + h
    end
    imgui.Dummy(ImVec2(width, y + 14))

    if G.scrollReset then
        imgui.SetScrollY(0)
        G.scrollReset = false
    end
    if sb then
        local target = max(G.scrollTarget - 12, 0)
        local cur = imgui.GetScrollY()
        G.scrollFrames = G.scrollFrames + 1
        if not S.anim then
            imgui.SetScrollY(target); G.scrollBlock = nil
        else
            imgui.SetScrollY(cur + (target - cur) * (1 - exp(-G.dt * 14)))
            if abs(target - cur) < 1.5 or G.scrollFrames > 90 then G.scrollBlock = nil end
        end
    end
end

-- =====================================================================
--  ПОИСК
-- =====================================================================
local function lowerOf(b)
    if not b.lower then b.lower = lower1251(b.plain) end
    return b.lower
end

local function runSearch()
    local list = {}
    if #G.qwords == 0 then G.searchList = list; return end
    local hits, started, groupHead = 0, false, nil
    local function matches(b)
        local lw = lowerOf(b)
        for _, w in ipairs(G.qwords) do
            if not lw:find(w, 1, true) then return false end
        end
        return true
    end
    for ci, cat in ipairs(data) do
        local P = getParsed(cat)
        local lastHead = nil
        started = false
        for _, b in ipairs(P.blocks) do
            if b.kind == 'head' then lastHead = b end
            if b.kind ~= 'blank' and b.kind ~= 'title' and matches(b) then
                if not started or groupHead ~= lastHead then
                    local label = cat.name .. '   >   ' .. (lastHead and lastHead.plain or 'начало раздела')
                    local rb = newBlock('rhead', 'item', (tokenize(label, false)), label)
                    rb.ci, rb.target = ci, lastHead
                    list[#list + 1] = rb
                    started, groupHead = true, lastHead
                end
                list[#list + 1] = b
                hits = hits + 1
                if hits >= 500 then break end
            end
        end
        if hits >= 500 then break end
    end
    local msg = (hits == 0) and 'Ничего не найдено. Попробуйте другие слова.' or ('Совпадений: ' .. hits .. (hits >= 500 and ' (показаны первые 500)' or ''))
    table.insert(list, 1, newBlock('info', 'base', (tokenize(msg, false)), msg))
    G.searchList = list
end

local function updateSearch()
    local raw = ffi.string(searchBuf)
    if raw == G.searchRaw then return end
    G.searchRaw = raw
    G.scrollReset = true
    G.qwords = {}
    local q = lower1251(trim(u8:decode(raw)))
    for w in q:gmatch('%S+') do G.qwords[#G.qwords + 1] = w end
    runSearch()
end

local function clearSearch()
    ffi.fill(searchBuf, 256)
    G.searchRaw, G.qwords, G.searchList = '', {}, {}
end

-- =====================================================================
--  РЕДАКТИРОВАНИЕ
-- =====================================================================
local function startEdit(cat)
    local t8 = u8(table.concat(cat.content, '\n'))
    edit.active = true
    edit.name = bufFromString(u8(cat.name), 256)
    edit.buf = new.char[#t8 + 65536]()
    ffi.copy(edit.buf, t8, #t8)
end

local function stopEdit(save)
    if save and data[G.selected] then
        local cat = data[G.selected]
        local name = trim(u8:decode(ffi.string(edit.name)))
        if name ~= '' then cat.name = name end
        local text = u8:decode(ffi.string(edit.buf)):gsub('\r', '')
        local lines = {}
        for line in (text .. '\n'):gmatch('(.-)\n') do lines[#lines + 1] = line end
        if #lines > 0 then lines[#lines] = nil end
        cat.content = lines
        invalidate(cat)
        saveRules()
        G.searchRaw = '\0'
        toast('Изменения сохранены')
    end
    edit.active, edit.name, edit.buf = false, nil, nil
end

-- =====================================================================
--  ИНИЦИАЛИЗАЦИЯ ИМГУИ (шрифты)
-- =====================================================================
local glyphRanges = new.ImWchar[9](0x0020, 0x00FF, 0x0400, 0x052F, 0x2010, 0x205E, 0x2116, 0x2116, 0)
local faRanges = nil

imgui.OnInitialize(function()
    G.inited = true
    imgui.GetIO().IniFilename = nil

    local st = imgui.GetStyle()
    st.WindowPadding = ImVec2(14, 12)
    st.FramePadding = ImVec2(12, 8)
    st.ItemSpacing = ImVec2(8, 8)
    st.ScrollbarSize = 9
    st.WindowBorderSize = 0
    st.ChildBorderSize = 0
    st.FrameBorderSize = 0
    st.PopupBorderSize = 0

    local atlas = imgui.GetIO().Fonts
    local dir = getFolderPath(0x14) .. '\\'
    local function pick(list)
        for _, name in ipairs(list) do
            if doesFileExist(dir .. name) then return dir .. name end
        end
    end
    local regular = pick({ 'segoeui.ttf', 'arial.ttf', 'tahoma.ttf' })
    local bold = pick({ 'segoeuib.ttf', 'arialbd.ttf', 'tahomabd.ttf' }) or regular

    local function mergeIcons(size)
        if not fa then return end
        pcall(function()
            if not faRanges then faRanges = new.ImWchar[3](fa.min_range, fa.max_range, 0) end
            local cfg = imgui.ImFontConfig()
            cfg.MergeMode = true
            cfg.PixelSnapH = true
            atlas:AddFontFromMemoryCompressedBase85TTF(fa.get_font_data_base85('solid'), size, cfg, faRanges)
        end)
    end

    if regular then
        fonts.base = atlas:AddFontFromFileTTF(regular, 17, nil, glyphRanges); mergeIcons(15)
        fonts.small = atlas:AddFontFromFileTTF(regular, 14, nil, glyphRanges)
        fonts.item = atlas:AddFontFromFileTTF(bold, 17, nil, glyphRanges)
        fonts.title = atlas:AddFontFromFileTTF(regular, 24, nil, glyphRanges)
        fonts.head = atlas:AddFontFromFileTTF(bold, 20, nil, glyphRanges); mergeIcons(17)
    end
    rebuildTheme()
end)

-- =====================================================================
--  ВИДЖЕТЫ ИНТЕРФЕЙСА
-- =====================================================================
local function fit(text, width, fname)
    pushFont(fonts[fname])
    local res = text
    if imgui.CalcTextSize(U(text)).x > width then
        while #res > 1 and imgui.CalcTextSize(U(res .. '...')).x > width do res = res:sub(1, -2) end
        res = res .. '...'
    end
    popFont(fonts[fname])
    return res
end

local function coloredButton(label, size, col, colHov)
    imgui.PushStyleColor(imgui.Col.Button, V4(col))
    imgui.PushStyleColor(imgui.Col.ButtonHovered, V4(colHov))
    imgui.PushStyleColor(imgui.Col.ButtonActive, V4(colHov))
    local r = imgui.Button(label, size)
    imgui.PopStyleColor(3)
    return r
end

-- Шестерёнка, нарисованная вручную (вращается при наведении)
local function gearButton(active, size)
    local p = imgui.GetCursorScreenPos()
    local clicked = imgui.Button('##gear', ImVec2(size, size))
    local hov = imgui.IsItemHovered()
    if S.anim and (hov or active) then G.gearAng = G.gearAng + G.dt * (active and 1.4 or 3.4) end
    local dl = imgui.GetWindowDrawList()
    local cx, cy = p.x + size / 2, p.y + size / 2
    local r = size * 0.21
    local col = c32(active and COL.accent or COL.text)
    for k = 0, 7 do
        local an = G.gearAng + k * pi / 4
        local ca, sa = cos(an), sin(an)
        dl:AddLine(ImVec2(cx + ca * r, cy + sa * r), ImVec2(cx + ca * r * 1.7, cy + sa * r * 1.7), col, 3.4)
    end
    dl:AddCircle(ImVec2(cx, cy), r * 1.18, col, 24, 3.0)
    dl:AddCircle(ImVec2(cx, cy), r * 0.45, col, 14, 2.0)
    return clicked
end

local function hkName()
    if S.hotkey == 0 then return 'не задана' end
    return vkeys.id_to_name(S.hotkey) or tostring(S.hotkey)
end

local function syncBufs()
    bufs.accent = new.float[3](S.accent[1], S.accent[2], S.accent[3])
    bufs.text = new.float[3](S.textcol[1], S.textcol[2], S.textcol[3])
    bufs.alpha = new.float(S.bgAlpha)
    bufs.scale = new.float(S.scale)
    bufs.round = new.float(S.rounding)
    bufs.anim = new.bool(S.anim)
    bufs.hl = new.bool(S.highlight)
    bufs.esc = new.bool(S.esc)
end

local function setAccent(c)
    S.accent = { c[1], c[2], c[3] }
    bufs.accent[0], bufs.accent[1], bufs.accent[2] = c[1], c[2], c[3]
    rebuildTheme(); markDirty()
end

-- =====================================================================
--  ЛЕВАЯ ПАНЕЛЬ
-- =====================================================================
local function drawLeft()
    imgui.PushStyleColor(imgui.Col.ChildBg, V4(COL.panel))
    imgui.BeginChild('##left', ImVec2(300, 0), false)
    imgui.PopStyleColor()

    imgui.SetCursorPos(ImVec2(10, 10))
    if imgui.ArrowButton('##up', imgui.Dir.Up) and G.selected > 1 and not edit.active then
        data[G.selected], data[G.selected - 1] = data[G.selected - 1], data[G.selected]
        G.selected = G.selected - 1
        saveRules()
    end
    imgui.SameLine()
    if imgui.ArrowButton('##down', imgui.Dir.Down) and G.selected < #data and not edit.active then
        data[G.selected], data[G.selected + 1] = data[G.selected + 1], data[G.selected]
        G.selected = G.selected + 1
        saveRules()
    end
    imgui.SameLine()
    if imgui.Button(U('Добавить раздел'), ImVec2(imgui.GetContentRegionAvail().x - 10, 0)) then
        G.wantAdd = true
    end

    imgui.SetCursorPos(ImVec2(6, imgui.GetCursorPosY() + 2))
    imgui.BeginChild('##catlist', ImVec2(288, 0), false)
    local dl = imgui.GetWindowDrawList()
    local k = S.anim and (1 - exp(-G.dt * 16)) or 1
    local rnd = max(S.rounding - 3, 0)
    local width = imgui.GetContentRegionAvail().x - 8

    for i, cat in ipairs(data) do
        imgui.PushIDInt(i)
        local isSel = (i == G.selected)
        local p = imgui.GetCursorScreenPos()
        local clicked = imgui.InvisibleButton('##cat', ImVec2(width, 54))
        local hov = imgui.IsItemHovered()
        if clicked and G.selected ~= i then
            if edit.active then stopEdit(false) end
            G.selected = i
            G.scrollReset = true
            G.scrollBlock = nil
            G.settingsOpen = false
        end

        local sa = (anim.sel[cat] or 0)
        sa = sa + ((isSel and 1 or 0) - sa) * k
        anim.sel[cat] = sa
        local ha = (anim.hov[cat] or 0)
        ha = ha + ((hov and 1 or 0) - ha) * k
        anim.hov[cat] = ha

        local p2 = ImVec2(p.x + width, p.y + 54)
        if ha > 0.01 then dl:AddRectFilled(p, p2, c32(COL.btnHov, ha * (1 - sa)), rnd) end
        if sa > 0.01 then dl:AddRectFilled(p, p2, c32(COL.sel, sa), rnd) end

        local tcol = {
            COL.text[1] + (COL.dark[1] - COL.text[1]) * sa,
            COL.text[2] + (COL.dark[2] - COL.text[2]) * sa,
            COL.text[3] + (COL.dark[3] - COL.text[3]) * sa, 1 }
        local P = getParsed(cat)
        local n = P.count
        local shift = 10 + 3 * ha
        pushFont(fonts.item)
        dl:AddText(ImVec2(p.x + shift, p.y + 8), c32(tcol), U(fit(cat.name, width - 24, 'item')))
        popFont(fonts.item)
        pushFont(fonts.small)
        local scol = {
            COL.dim[1] + (0.30 - COL.dim[1]) * sa,
            COL.dim[2] + (0.38 - COL.dim[2]) * sa,
            COL.dim[3] + (0.32 - COL.dim[3]) * sa, 1 }
        dl:AddText(ImVec2(p.x + shift, p.y + 31), c32(scol), U(n .. ' ' .. plural(n)))
        popFont(fonts.small)
        imgui.PopID()
    end
    imgui.EndChild()
    imgui.EndChild()
end

-- =====================================================================
--  ПРАВАЯ ПАНЕЛЬ
-- =====================================================================
local function drawSettings()
    local function section(txt)
        imgui.Spacing()
        pushFont(fonts.head)
        imgui.TextColored(V4(COL.accent), U(txt))
        popFont(fonts.head)
    end
    local function label(txt)
        imgui.AlignTextToFramePadding()
        imgui.TextColored(V4(COL.dim), U(txt))
    end

    pushFont(fonts.title)
    imgui.Text(U('НАСТРОЙКИ'))
    popFont(fonts.title)
    imgui.Separator()

    section('Цветовая тема')
    label('Готовые темы:')
    for i, p in ipairs(PRESETS) do
        if i > 1 then imgui.SameLine() end
        if imgui.ColorButton('##pre' .. i, ImVec4(p.c[1], p.c[2], p.c[3], 1), 0, ImVec2(34, 34)) then
            setAccent(p.c)
        end
    end
    label('Свой основной цвет (любой):')
    imgui.PushItemWidth(300)
    if imgui.ColorEdit3('##accent', bufs.accent) then
        S.accent = { bufs.accent[0], bufs.accent[1], bufs.accent[2] }
        rebuildTheme(); markDirty()
    end
    imgui.PopItemWidth()
    label('Цвет текста:')
    imgui.PushItemWidth(300)
    if imgui.ColorEdit3('##txt', bufs.text) then
        S.textcol = { bufs.text[0], bufs.text[1], bufs.text[2] }
        rebuildTheme(); markDirty()
    end
    imgui.PopItemWidth()

    section('Внешний вид')
    imgui.PushItemWidth(300)
    label('Прозрачность окна:')
    if imgui.SliderFloat('##alpha', bufs.alpha, 0.20, 1.0, '%.2f') then
        S.bgAlpha = bufs.alpha[0]; rebuildTheme(); markDirty()
    end
    label('Размер текста:')
    if imgui.SliderFloat('##scale', bufs.scale, 0.70, 1.60, '%.2f') then
        S.scale = bufs.scale[0]; markDirty()
    end
    label('Скругление углов:')
    if imgui.SliderFloat('##round', bufs.round, 0, 24, '%.0f') then
        S.rounding = floor(bufs.round[0] + 0.5); rebuildTheme(); markDirty()
    end
    imgui.PopItemWidth()
    imgui.Spacing()
    if imgui.Checkbox(U('Анимации (открытие, перемещение, прокрутка)'), bufs.anim) then S.anim = bufs.anim[0]; markDirty() end
    if imgui.Checkbox(U('Подсветка номеров пунктов и наказаний'), bufs.hl) then S.highlight = bufs.hl[0]; markDirty() end

    section('Управление')
    if imgui.Checkbox(U('Закрывать окно по ESC'), bufs.esc) then S.esc = bufs.esc[0]; markDirty() end
    label('Горячая клавиша открытия:')
    imgui.SameLine()
    local txt = G.listen and 'Нажмите любую клавишу...' or hkName()
    if imgui.Button(U(txt) .. '##hk', ImVec2(210, 0)) then G.listen = not G.listen end
    imgui.SameLine()
    if imgui.Button(U('Сбросить') .. '##hkc') then S.hotkey = 0; G.listen = false; markDirty() end
    pushFont(fonts.small)
    imgui.TextColored(V4(COL.dim), U('Команда /srules работает всегда. Во время назначения ESC отменяет выбор.'))
    popFont(fonts.small)

    section('Сброс и данные')
    if imgui.Button(U('Сбросить внешний вид'), ImVec2(230, 0)) then
        local keep = { x = S.x, y = S.y }
        S = deepcopy(DEFAULT_S)
        S.x, S.y = keep.x, keep.y
        syncBufs(); rebuildTheme(); markDirty()
        toast('Внешний вид сброшен')
    end
    imgui.SameLine()
    local armed = (os.clock() - G.confirmReset) < 3
    if coloredButton(U(armed and 'Нажми ещё раз для подтверждения' or 'Вернуть базу правил') .. '##rr', ImVec2(300, 0), COL.danger, COL.dangerH) then
        if armed then
            if edit.active then stopEdit(false) end
            data = deepcopy(DEFAULT_RULES)
            G.selected = 1
            saveRules(); clearSearch()
            G.confirmReset = 0
            toast('База правил восстановлена')
        else
            G.confirmReset = os.clock()
        end
    end
    imgui.Spacing()
    pushFont(fonts.small)
    imgui.TextColored(V4(COL.dim), U('Папка скрипта: ' .. DIR))
    imgui.TextColored(V4(COL.dim), U('Правая кнопка мыши по строке правил - скопировать её. Клик по ссылке - скопировать ссылку.'))
    popFont(fonts.small)
    imgui.Dummy(ImVec2(0, 14))
end

local function drawEditor()
    pushFont(fonts.small)
    imgui.TextColored(V4(COL.dim), U('Название раздела'))
    popFont(fonts.small)
    imgui.PushItemWidth(-18)
    imgui.InputText('##ename', edit.name, ffi.sizeof(edit.name))
    imgui.PopItemWidth()
    pushFont(fonts.small)
    imgui.TextColored(V4(COL.dim), U('#Заголовок    {RRGGBB} цвет    {STANDART} сброс цвета    - пункт списка    пустая строка = отступ'))
    popFont(fonts.small)
    imgui.InputTextMultiline('##etext', edit.buf, ffi.sizeof(edit.buf), ImVec2(-18, -14), imgui.InputTextFlags.AllowTabInput)
end

local function drawRight()
    imgui.BeginChild('##right', ImVec2(0, 0), false)
    local cat = data[G.selected]
    local avail = imgui.GetContentRegionAvail().x
    local sp = imgui.GetStyle().ItemSpacing.x
    local fh = imgui.GetFrameHeight()
    local wX = fh + 8
    local wGear = fh
    local searching = (not edit.active) and (not G.settingsOpen) and #G.qwords > 0

    if edit.active then
        pushFont(fonts.item)
        imgui.AlignTextToFramePadding()
        imgui.TextColored(V4(COL.accent), U('Режим редактирования'))
        popFont(fonts.item)
        imgui.SameLine(avail - (112 + 96 + wX + sp * 2))
        if coloredButton(U('Сохранить'), ImVec2(112, 0), COL.accentBg, COL.accent) then stopEdit(true) end
        imgui.SameLine()
        if imgui.Button(U('Отмена'), ImVec2(96, 0)) then stopEdit(false) end
    elseif G.settingsOpen then
        pushFont(fonts.item)
        imgui.AlignTextToFramePadding()
        imgui.TextColored(V4(COL.accent), U('Настройки'))
        popFont(fonts.item)
        imgui.SameLine(avail - (wGear + wX + sp))
        if gearButton(true, wGear) then G.settingsOpen = false; if G.sdirty then saveSettings(); G.sdirty = false end end
    else
        local wToc, wEdit, wDel = 112, 100, 92
        local wSearch = max(avail - (wToc + wGear + wEdit + wDel + wX + sp * 5), 120)
        imgui.PushItemWidth(wSearch)
        imgui.InputTextWithHint('##search', U('Поиск информации'), searchBuf, 256)
        imgui.PopItemWidth()
        updateSearch()
        imgui.SameLine()
        if imgui.Button(U('Оглавление'), ImVec2(wToc, 0)) and not searching then imgui.OpenPopup('##toc') end
        imgui.SameLine()
        if gearButton(false, wGear) then G.settingsOpen = true end
        imgui.SameLine()
        if imgui.Button(U('Изменить'), ImVec2(wEdit, 0)) and cat then startEdit(cat) end
        imgui.SameLine()
        if coloredButton(U('Удалить'), ImVec2(wDel, 0), COL.danger, COL.dangerH) and cat then G.wantDelete = true end

        imgui.SetNextWindowSizeConstraints(ImVec2(300, 0), ImVec2(560, 440))
        if imgui.BeginPopup('##toc') then
            if cat then
                local P = getParsed(cat)
                if #P.heads == 0 then imgui.TextColored(V4(COL.dim), U('В этом разделе нет заголовков')) end
                for i, h in ipairs(P.heads) do
                    imgui.PushIDInt(i)
                    if imgui.Selectable(U(h.name)) then
                        G.scrollBlock, G.scrollFrames = h.block, 0
                    end
                    imgui.PopID()
                end
            end
            imgui.EndPopup()
        end
    end
    imgui.SameLine()
    if imgui.Button('X', ImVec2(wX, 0)) then
        if edit.active then stopEdit(false) end
        winState[0] = false
    end
    imgui.Spacing()

    imgui.PushStyleColor(imgui.Col.ChildBg, V4(COL.content))
    imgui.BeginChild('##content', ImVec2(0, 0), false)
    imgui.PopStyleColor()
    imgui.SetCursorPos(ImVec2(18, 14))
    if edit.active then
        drawEditor()
    elseif G.settingsOpen then
        imgui.BeginGroup()
        drawSettings()
        imgui.EndGroup()
    elseif searching then
        drawBlocks(G.searchList, true)
    elseif cat then
        drawBlocks(getParsed(cat).blocks, false)
    else
        imgui.TextColored(V4(COL.dim), U('Нет разделов. Нажмите "Добавить раздел".'))
    end
    imgui.EndChild()
    imgui.EndChild()

    -- Переход по клику на заголовок в результатах поиска
    local j = G.pendingJump
    if j then
        G.pendingJump = nil
        G.selected = j.ci
        G.scrollBlock, G.scrollFrames = j.target, 0
        G.scrollReset = (j.target == nil)
        clearSearch()
    end
end

local function drawPopups()
    if G.wantAdd then
        ffi.fill(addNameBuf, 128)
        imgui.OpenPopup('##addcat')
        G.wantAdd = false
    end
    if G.wantDelete then
        imgui.OpenPopup('##delcat')
        G.wantDelete = false
    end

    local io = imgui.GetIO()
    local center = ImVec2(io.DisplaySize.x / 2, io.DisplaySize.y / 2)
    local pf = imgui.WindowFlags.AlwaysAutoResize + imgui.WindowFlags.NoTitleBar

    imgui.SetNextWindowPos(center, imgui.Cond.Always, ImVec2(0.5, 0.5))
    if imgui.BeginPopupModal('##addcat', nil, pf) then
        pushFont(fonts.item)
        imgui.Text(U('Новый раздел'))
        popFont(fonts.item)
        imgui.PushItemWidth(340)
        imgui.InputTextWithHint('##newname', U('Название раздела'), addNameBuf, 128)
        imgui.PopItemWidth()
        if coloredButton(U('Создать'), ImVec2(165, 0), COL.accentBg, COL.accent) then
            local name = trim(u8:decode(ffi.string(addNameBuf)))
            if name ~= '' then
                if edit.active then stopEdit(false) end
                data[#data + 1] = { name = name, content = { '#Новый заголовок', '', 'Текст правил...' } }
                G.selected = #data
                G.settingsOpen = false
                saveRules()
                startEdit(data[G.selected])
                imgui.CloseCurrentPopup()
            end
        end
        imgui.SameLine()
        if imgui.Button(U('Отмена'), ImVec2(165, 0)) then imgui.CloseCurrentPopup() end
        imgui.EndPopup()
    end

    imgui.SetNextWindowPos(center, imgui.Cond.Always, ImVec2(0.5, 0.5))
    if imgui.BeginPopupModal('##delcat', nil, pf) then
        local cat = data[G.selected]
        pushFont(fonts.item)
        imgui.Text(U('Удалить раздел?'))
        popFont(fonts.item)
        if cat then imgui.TextColored(V4(COL.dim), U(fit(cat.name, 340, 'base'))) end
        if coloredButton(U('Удалить'), ImVec2(165, 0), COL.danger, COL.dangerH) then
            if edit.active then stopEdit(false) end
            table.remove(data, G.selected)
            G.selected = clamp(G.selected, 1, max(#data, 1))
            G.scrollReset = true
            saveRules()
            G.searchRaw = '\0'
            imgui.CloseCurrentPopup()
        end
        imgui.SameLine()
        if imgui.Button(U('Отмена'), ImVec2(165, 0)) then imgui.CloseCurrentPopup() end
        imgui.EndPopup()
    end
end

local function drawToast()
    local t = G.toast
    if not t then return end
    local age = os.clock() - t.t
    if age > 2.2 then G.toast = nil; return end
    local a = (age > 1.7) and (1 - (age - 1.7) / 0.5) or min(age / 0.15, 1)
    local wp, ws = imgui.GetWindowPos(), imgui.GetWindowSize()
    local dl = imgui.GetForegroundDrawList()
    pushFont(fonts.base)
    local sz = imgui.CalcTextSize(t.text)
    local x, y = wp.x + ws.x / 2 - sz.x / 2, wp.y + ws.y - 64 + (1 - a) * 10
    dl:AddRectFilled(ImVec2(x - 18, y - 9), ImVec2(x + sz.x + 18, y + sz.y + 9), c32(COL.accentBg, a * 0.96), 12)
    dl:AddText(ImVec2(x, y), c32({ 1, 1, 1, 1 }, a), t.text)
    popFont(fonts.base)
end

-- =====================================================================
--  ГЛАВНЫЙ КАДР
-- =====================================================================
imgui.OnFrame(function() return data ~= nil and (winState[0] or G.openT > 0.002) end, function(self)
    local io = imgui.GetIO()
    local dt = clamp(io.DeltaTime, 0.001, 0.05)
    G.dt = dt
    io.FontGlobalScale = S.scale

    -- Анимация открытия / закрытия
    local target = winState[0] and 1 or 0
    if S.anim then
        if G.openT < target then G.openT = min(target, G.openT + dt * 7)
        else G.openT = max(target, G.openT - dt * 9) end
    else
        G.openT = target
    end
    local e = easeOut(G.openT)
    G.alpha = e
    self.HideCursor = not winState[0]

    -- Позиция окна (плавное следование за перетаскиванием)
    local sw, sh = io.DisplaySize.x, io.DisplaySize.y
    local ww, wh = min(S.w, sw - 20), min(S.h, sh - 20)
    if not G.px then
        G.px = S.x or (sw - ww) / 2
        G.py = S.y or (sh - wh) / 2
    end
    G.px = clamp(G.px, -ww * 0.6, sw - ww * 0.4)
    G.py = clamp(G.py, 0, sh - 40)
    if G.snap then G.cx, G.cy, G.snap = G.px, G.py, false end
    local kf = S.anim and (1 - exp(-dt * 20)) or 1
    G.cx = G.cx + (G.px - G.cx) * kf
    G.cy = G.cy + (G.py - G.cy) * kf

    imgui.SetNextWindowPos(ImVec2(G.cx, G.cy + (1 - e) * 28), imgui.Cond.Always)
    imgui.SetNextWindowSize(ImVec2(ww, wh), imgui.Cond.FirstUseEver)
    imgui.SetNextWindowSizeConstraints(ImVec2(780, 440), ImVec2(sw, sh))

    local pushedAlpha = pcall(imgui.PushStyleVarFloat, imgui.StyleVar.Alpha, max(e, 0.01))
    pushFont(fonts.base)
    local flags = imgui.WindowFlags.NoTitleBar + imgui.WindowFlags.NoCollapse + imgui.WindowFlags.NoScrollbar
        + imgui.WindowFlags.NoScrollWithMouse + imgui.WindowFlags.NoMove + imgui.WindowFlags.NoSavedSettings
    if imgui.Begin('##swat_rules_window', nil, flags) then
        refreshMetrics()
        local wp, ws = imgui.GetWindowPos(), imgui.GetWindowSize()

        -- Полоска для перетаскивания
        imgui.SetCursorPos(ImVec2(0, 0))
        imgui.InvisibleButton('##grip', ImVec2(ws.x, 14))
        local active = imgui.IsItemActive()
        local gh = imgui.IsItemHovered() or active
        if gh then imgui.SetMouseCursor(imgui.MouseCursor.ResizeAll) end
        if active then
            G.px = G.px + io.MouseDelta.x
            G.py = G.py + io.MouseDelta.y
            G.dragging = true
        elseif G.dragging then
            G.dragging = false
            S.x, S.y = G.px, G.py
            markDirty()
        end
        local dl = imgui.GetWindowDrawList()
        dl:AddRectFilled(ImVec2(wp.x + ws.x / 2 - 24, wp.y + 5), ImVec2(wp.x + ws.x / 2 + 24, wp.y + 8),
            c32(COL.dim, gh and 0.95 or 0.4), 2)

        imgui.SetCursorPos(ImVec2(12, 16))
        drawLeft()
        imgui.SameLine()
        drawRight()
        drawPopups()
        drawToast()

        if G.openT >= 1 and (abs(ws.x - S.w) > 1 or abs(ws.y - S.h) > 1) and not G.dragging then
            S.w, S.h = floor(ws.x), floor(ws.y)
            markDirty()
        end
    end
    imgui.End()
    popFont(fonts.base)
    if pushedAlpha then imgui.PopStyleVar() end
end)

-- =====================================================================
--  MOONLOADER
-- =====================================================================
local function setOpen(v)
    if v and not winState[0] then G.snap = true end
    winState[0] = v
    if not v and G.sdirty then saveSettings(); G.sdirty = false end
end

function main()
    while not isSampAvailable() do wait(0) end

    DIR = getWorkingDirectory() .. '\\SWAT Rules\\'
    createDirectory(DIR)
    loadSettings()
    data = loadRules()
    G.selected = 1
    syncBufs()
    rebuildTheme()

    sampRegisterChatCommand('srules', function(arg)
        if trim(arg or '') == 'reset' then
            if edit.active then stopEdit(false) end
            data = deepcopy(DEFAULT_RULES)
            G.selected = 1
            saveRules()
            clearSearch()
            sampAddChatMessage('{2ACF4A}[SWAT Rules]{FFFFFF} База правил восстановлена.', -1)
            return
        end
        setOpen(not winState[0])
    end)

    sampAddChatMessage('{2ACF4A}[SWAT Rules]{FFFFFF} Скрипт запущен. Активация: {2ACF4A}/srules{FFFFFF}, настройки - шестерёнка в окне.', -1)

    while true do
        wait(0)
        if G.listen then
            for vk = 8, 254 do
                if vk ~= 1 and vk ~= 2 and vk ~= 4 and vk ~= 5 and vk ~= 6 and isKeyJustPressed(vk) then
                    if vk ~= 0x1B then S.hotkey = vk; markDirty() end
                    G.listen = false
                    break
                end
            end
        else
            if S.hotkey ~= 0 and isKeyJustPressed(S.hotkey) and not sampIsChatInputActive()
                and not sampIsDialogActive() and not (G.inited and imgui.GetIO().WantTextInput) then
                setOpen(not winState[0])
            end
            if winState[0] and S.esc and not edit.active and isKeyJustPressed(0x1B) then
                setOpen(false)
            end
        end
        if G.sdirty and os.clock() - G.sLast > 1.0 then
            saveSettings()
            G.sdirty = false
        end
    end
end

function onScriptTerminate(scr, quit)
    if scr == thisScript() and G.sdirty then saveSettings() end
end

-- =====================================================================
--  ВСТРОЕННАЯ БАЗА ПРАВИЛ (формат как в игре: # заголовок, {RRGGBB} цвет, - список)
-- =====================================================================
DEFAULT_RULES = {
{name="FAQ / Разметка",content={
"#Заголовки",
"Используйте символ решетки ({FFDD90}#{STANDART}) в начале строки, чтобы выделить её как заголовок",
"На заголовки можно кликать, чтобы сразу перейти к нужному разделу, если ищите что-то через глобальный поиск",
"Заголовки автоматически пишутся в верхнем регистре (капсом)",
"",
"#Цветовые теги",
"Информацию, выделенную цветом, {4fff6c}легче воспринимать{STANDART} глазу, и поэтому мы советуем выделять ",
"нужные слова или фразы в правилах специальными {4fff6c}цветовыми тегами{STANDART}.",
"Цветовой тег имеет специальный формат: {{FF0000}RR{00FF00}GG{3050FF}BB{STANDART}}.",
"Помимо этого есть тег, возвращающий обычный цвет текста - {{FFDD90}STANDART{STANDART}}",
"{AAAAAA}P.s. Подобрать цвет можно тут (кликни, чтобы скопировать):",
"{00a2ff}https://www.google.com/search?q=color+picker",
"",
"#Иконки",
"Вы можете создавать специальные иконки в тексте, используя тег: {{4fff6c}fa:НАЗВАНИЕ{STANDART}}",
"Например: {{FFDD90}fa:STAR{STANDART}} = {fa:STAR} или {{FFDD90}fa:CIRCLE_EXCLAMATION{STANDART}} = {fa:CIRCLE_EXCLAMATION}",
"Список доступных иконок и их названий вы можете найти в специальном окне, через {4fff6c}команду /fa{STANDART}",
"",
"#Списки",
"Для создания списков с отступами можно использовать символ минуса ({FFDD90}-{STANDART}) в начале ",
"каждой строки и тогда текст будет выглядеть таким образом:",
"- Кошка",
"- Собака",
"- Попугай",
"- Бегемот",
"",
"",
"{666666}[ Данный раздел можно удалить ]",
}},
{name="Основные правила серверов",content={
"#1. Общие положения",
"",
"1.1 Правила проекта могут быть обновлены в любой момент. Незнание любого правила не освобождает от ответственности. Проверяйте данный раздел своевременно.",
"1.2 Правила проекта действуют для всех игроков на всех серверах. Они распространяются на все зоны и мероприятия, но на некоторых из них могут немного меняться. Для таких зон и мероприятий составлены особые правила, в которых указано - какие исключения на нем применяются.",
"Пример: по правилам игрового процесса ПГ (изображение из себя супергероя) запрещено, но по правилам мероприятия “Битва за завод” разрешено - значит, на данном МП это правило можно нарушать.",
"1.3 Попытка нарушения правил сервера равноценна полноценному нарушению (попытка продажи вирт = продаже вирт и т.д.).",
"1.4 В случае нарушения любого правила нельзя оправдать свое нарушение \"рофлом\" или откатом ситуации, например оскорбив родных и написав \"откат\".",
"1.5 Каждая ситуация рассматривается индивидуально, независимо от других. Главная администрация по своему решению может применять иные меры наказания.",
"1.6 При нарушении нескольких пунктов правил в один временной промежуток (в рамках одной ситуации) наказания не суммируются, выдаётся максимальное из указанных в правилах.",
"1.7 За массовые (неоднократные) нарушения правил сервера по решению ГА срок блокировки (и других наказаний) может быть увеличен по нарастающей: 5, 10, 15 и 30 дней. При дальнейшей совокупности нарушений игрок может быть внесён в чёрный список сервера.",
"1.8 За любые серьезные нарушения, такие как продажа виртуальной валюты, использование рванки и т.д, игрок заносится в черный список проекта.",
"1.9 Все виды ЧСов (ЧС Лидеров/Админов/Сервера/Проекта) распространяются на все аккаунты игрока.",
"1.10 Обман администрации (преднамеренное предоставление ложной или вводящей в заблуждение информации и тому подобная деятельность) запрещен в любом виде.",
"1.11 Игровой год на сервере соответствует реальному времени. Место действия - вымышленная игровая вселенная, вдохновлённая атмосферой США, поэтому действия стоит отыгрывать опираясь на американскую модель поведения и манеру общения.",
"1.12 Срок хранения любых опровержений, которые требуют записывать правила, составляет - 5 дней. В течении этого срока администрация может его запросить без объяснения причин.",
"1.13 За нарушения, связанные с нанесением урона, администрация по одобрению ГА может выдавать блокировку на использование оружия.",
"1.14 За использование запрещенных игровых модификаций и прочие серьезные нарушения во время МП, а также отказ или выход из игры от проверки компьютера, главная администрация может системно ограничить доступ к МП.",
"1.15 За нарушения, совершенные во время системного перелета на любой из серверов проекта, администрация имеет право заблокировать ваш игровой аккаунт на основном сервере.",
"",
"",
"Терминология",
"Устное замечание - это предупреждение, которое администратор делает игроку, чтобы он обратил внимание на свою ошибку и начал её исправлять.",
"Кик - это процесс исключения игрока из сервера.",
"Мут - ограничение возможности использования текстового и голосового чата.",
"ТСР - это изоляция игрока в тюрьме строгого режима.",
"Варн - это предупреждение для игрока, устанавливающее определённые временные ограничения: игрок автоматически исключается из своей фракции (если таковая у него была), и на него накладывается ряд ограничений на 10 дней, описанных в /help - [FAQ] Ограничения при варне. По истечении этого срока ограничения снимаются, и игрок сможет снова присоединиться к любой фракции. При получении второго предупреждения их общий срок продлевается до 20 дней. При накоплении трёх предупреждений аккаунт будет автоматически заблокирован на 10 дней.",
"Бан - блокировка игрового аккаунта на определенный срок.",
"ЧСС (Черный Список Сервера) - запрет играть на определенном сервере, в т.ч. с новых аккаунтов.",
"ЧСП (Черный Список Проекта) - запрет играть на всех серверах проектов Arizona Games, в т.ч. с новых аккаунтов.",
"ЧСА (Черный Список Администрации) - запрет занимать пост администратора на всех серверах проектов Arizona Games.",
"Мут репорта - ограничение доступа к функции подачи жалоб и вопросов (/report).",
"Обнуление аккаунта - это удаление всего имущества игрока.",
"Примечание: Удаление инвентаря, аксессуаров, скинов, транспорта, денежных средств.",
"ОФФ - покидание игровой сессии, путем выхода из игры.",
"АФК (от англ. AFK - Away From Keyboard) - состояние игрока, при котором он отошел от компьютера, ушел на паузу или свернул игру.",
"Спавн - телепортация игрока на его место возрождения",
"На усмотрение Главной администрации (по решению ГА) - фраза может означать, что решение по какому-либо вопросу или ситуации будет приниматься на основе мнения, анализа и оценки Главной администрации сервера.",
"",
"#2. Основные положения проекта",
"",
"2.1 Запрещено использовать любые скрипты, моды или иные конструкции, дающие преимущество над другими игроками.",
"2.1.1 Обычные (пример: флай, спидхак) Наказание: Бан 15 дней  2000 при повторном нарушении в течение 180 дней.",
"2.1.2 Значимые (пример: аим, вх) Наказание: Бан 30 дней  2000 при повторном нарушении в течение 180 дней.",
"2.1.3 Тяжкие (пример: валшот, рапид) Наказание: Бан 2000 дней.",
"2.1.4 Вредительские (пример: рванка, дамагер) Наказание: Бан 2000 дней + ЧСП.",
"",
"2.2 Запрещено распространять любые скрипты, моды или иные конструкции, дающие преимущество над другими игроками.",
"2.2.1 Обычные (пример: флай, спидхак) Наказание: Бан 15 дней  2000 при повторном нарушении в течение 180 дней.",
"2.2.2 Значимые (пример: аим, вх) Наказание: Бан 30 дней  2000 при повторном нарушении в течение 180 дней.",
"2.2.3 Тяжкие (пример: валшот, рапид) Наказание: Бан 2000 дней.",
"2.2.4 Вредительские (пример: рванка, дамагер) Наказание: Бан 2000 дней + ЧСП.",
"",
"2.3 Запрещено соучастие с игроком, использующим любые скрипты, моды или иные конструкции, дающие преимущество над другими игроками.",
"2.3.1 Обычные (пример: флай, спидхак) Наказание: Бан 15 дней  2000 при повторном нарушении в течение 180 дней.",
"2.3.2 Значимые (пример: аим, вх) Наказание: Бан 30 дней  2000 при повторном нарушении в течение 180 дней.",
"2.3.3 Тяжкие (пример: валшот, рапид) Наказание: Бан 2000 дней.",
"2.3.4 Вредительские (пример: рванка, дамагер) Наказание: Бан 2000 дней + ЧСП.",
"",
"2.4 Запрещено использование ботов. Наказание: Бан 2000 дней.",
"2.5 Запрещено находиться в игре на 2 аккаунтах с 1 устройства. Наказание: Устное предупреждение  Бан на 10 дней при повторном нарушении в течение 7 дней.",
"2.6 Запрещено уходить от наказания (Офф, смена ника и т.п.). Наказание: Варн  Бан на 3 дня при повторном нарушении в течение 7 дней.",
"2.7 Запрещено выдавать себя за администратора. Наказание: Мут 300 минут  Бан на 2 дня при повторном нарушении в течение 7 дней.",
"2.8 Запрещено создавать помеху игрокам или администрации. Наказание: Устное предупреждение / Спавн / Кик  ТСР 10 level (10 заданий каждого типа и 30 минут) при повторном нарушении в течение 7 дней.",
"2.9 Запрещено использовать недоработки мода или игры.",
"2.9.1 Использование некритических недоработок мода или игры. Пример: перебинд колёсика велосипеда. Наказание: ТСР 30 level (30 заданий каждого типа и 90 минут)",
"2.9.2 Использование критических недоработок мода или игры. Пример: дюп. Наказание: Бан 2000 дней.",
"2.10 Запрещено описание в режиме АФК и визитка, нарушающие РП режим, а также неадекватные, бредовые, содержащие рекламу бизнесов / продажи (покупки) имущества. Наказание: Предупреждение игрока + Очистка описания  ТСР 30 level (30 заданий каждого типа и 90 минут) при повторном нарушении в течение 7 дней.",
"2.11 Запрещено воспроизводить запрещенные материалы в кинотеатрах. Наказание: Бан 2 дня  на 5 дней при повторном нарушении в течение 14 дней.",
"Примечание: запрещенными материалами считаются:",
" Материалы экстремистского характера (призывы к политической и идеологической вражде, призывы или пропаганда терроризма или нацизма, розжиг межнациональной розни, расизм и проявление любого вида нетерпимости и тд);",
" Жестокие кадры (кадры с жестоким обращением или насилием к животным и людям);",
" Пропаганда запрещенных \"укроп\"тических и психотропных веществ, алкоголя и табака, азартных игр и маргинального образа жизни;",
" Пропаганду суицида;",
" Неуважительное отношение, клевету, оскорбления, унижение чести и достоинства, оскорбление чувств верующих и любые другие материалы, дискриминирующие личность;",
" Порнографические материалы (эротические материалы, содержащие сцены с изображением голого тела, натуральный порнографический контент 18+ любого жанра, анимационный порнографический контент по типу \"хентай\" и тд);",
" Реклама.",
"2.12 Запрещено крутить внеигровые рулетки. Наказание: Бан 7 дней  на 14 дней при повторном нарушении в течение 7 дней.",
"2.13 Запрещено неадекватное расположение аксессуаров персонажа, вследствие изменения их местоположения. Наказание: Устное предупреждение + Очистка всех аксессуаров  ТСР 75 level (75 заданий каждого типа и 225 минут) при повторном нарушении в течение 14 дней.",
"2.14 Запрещено взаимодействовать с игроками, находящимися в чёрном списке сервера/проекта. Наказание: Бан 15 дней  на 30 дней при повторном нарушении в течение 60 дней.",
"Примечание: запрещено укрывательство и любое взаимодействие с такими игроками на сервере в случае, если вы знаете об их нахождении в ЧСе.",
"2.15 Запрещён деанон (раскрытие личной информации) игроков на сервере, официальных ресурсах проекта, а также в любых других местах (включая личные сообщения, сторонние Discord-сервера, мессенджеры и иные площадки), если деанон совершён в отношении игрока проекта и установлена личность нарушителя.",
"2.15.1 Лёгкая степень: угроза раскрытия личных данных (адрес, фото, личные контакты и т.д.) без их фактической публикации. Наказание: Бан на 15 дней  на 30 дней при повторном нарушении в течение 30 дней.",
"2.15.2 Средняя степень: призывы к деанону игрока, предложение обмена или продажи личных данных игрока на любых ресурсах. Наказание: Бан на 30 дней  на 120 дней при повторном нарушении в течение 60 дней.",
"2.15.3 Тяжёлая степень: публикация личных данных (ФИО, точный адрес, номер телефона, личные фотографии, место работы/учебы). Наказание: Бан 2000 дней.",
"2.16 Запрещены угрозы расправой в реальной жизни на сервере и ресурсах проекта. Наказание: Бан 15 дней  на 30 дней при повторном нарушении в течение 60 дней.",
"2.17 Запрещено передавать свой игровой аккаунт, а также заходить на чужие (в т.ч. взлом). Наказание: Бан 2000 дней.",
"2.18 Запрещён обход систем мода с целью получения личной выгоды.",
"2.18.1 Незначительный обход систем мода. Пример: абуз заморозки камхаком. Наказание: Бан 7 дней.",
"2.18.2 Средний обход систем мода. Пример: абуз на оружие (патроны). Наказание: Бан 30 дней.",
"2.18.3 Критический обход систем мода. Пример: абуз батл пасса. Наказание: Бан 2000 дней.",
"Примечание: наказание выдается исключительно главной администрацией сервера.",
"2.19 Запрещена любая накрутка игровых ценностей (рефералы, рулетки, голоса, деньги и т.д). Наказание: Бан 2000 дней.",
"2.20 Запрещено вредительство в любом виде.",
"2.20.1 Незначительное вредительство. Пример: слив склада банды в небольшом объёме. Наказание: Бан 20 дней.",
"2.20.2 Тяжёлое вредительство. Пример: рванка, слив организации, слив аккаунта (намеренное вредительство с использованием служебного положения в гос. структуре). Наказание: Бан 2000 дней.",
"Примеры слива аккаунта:",
" массовое снятие розыска без законных оснований;",
" намеренное увольнение ключевых сотрудников;",
" слив казны или имущества организации;",
" иные действия, направленные на разрушение организации изнутри.",
"2.21 Запрещено использование /demoute, /dismiss, /gwarn и подобных команд без объективных причин и наличия доказательств. Наказание: Варн  Бан на 5 дней при повторном нарушении в течение 7 дней.",
"2.22 Запрещено вести «форумную войну» - чрезмерное написание жалоб на других игроков, систематический поиск нарушений на опровержениях других игроков, многочисленные жалобы на незначительные нарушения и т.п. Наказание: Устное замечание  Бан мероприятий (banmp) 10 дней при повторном нарушении в течение 14 дней.",
"Примечание: в случае, если большинство жалоб автора не содержат нарушений игроков / были отклонены.",
"2.23 Запрещена монополизация / вымогательство / шантаж других игроков. Наказание:ТСР от 75 level (75 заданий каждого типа и 225 минут)  Бан 7 дней при повторном нарушении в течение 14 дней.",
"Пример: требование любых игровых ценностей за вход/участие в подземной шахте.",
"2.24 Запрещено нечестное достижение (абуз) топовых мест в любых рейтингах. Наказание: Изъятие приза + Запрет участия в мероприятии.",
"Пример: во время судной ночи два друга договариваются набивать киллы для получения главного приза.",
"2.25 Запрещен выход из игры, покидание зоны мероприятий (каптов), увольнение из фракции/семьи и т.п. с целью не дать противоположной стороне обогнать вас. Наказание: Варн.",
"Примечание: если нарушение данного пункта оказало влияние на исход, то по решению ГА могут быть применены дополнительные наказания (например, изъятие территории).",
"",
"#3. Правила игровых ников",
"3.1 Никнейм игрока должен иметь формат Имя_Фамилия. Запрещено использовать никнейм с отсутствием смысловой нагрузки (Спам символами/числами, а так же ники, не имеющие логической связи с именем).",
"Примечание: Никнеймы, не соответствующие общепринятому формату Имя_Фамилия и не содержащие реальных имен и фамилий, классифицируются как никнеймы non-RP формата.",
"3.2 Создавая аккаунт с non-RP ником Вы должны осознавать, что получить повышение в организациях Вам не представится возможности, в большинстве случаев Вас вообще откажутся принять.",
"3.3 При вступлении в определенную организацию вас могут попросить сменить ник, т.к. Ваш существующий может не соответствовать требованиям данной организации.",
"3.4 Запрещено использовать в нике оскорбительные слова, маты. Наказание: Просьба сменить никнейм, в случае отказа - Бан 10 дней.",
"3.5 Запрещено искажать в оскорбительной форме ники игроков и администраторов. Наказание: Просьба сменить никнейм, в случае отказа - Бан 30 дней.",
"3.6 Запрещено использование фейк ников администрации, ютуберов, игроков высокого уровня данного сервера. Наказание: Просьба сменить никнейм, в случае отказа - Бан 2000 дней.",
"",
"#4. Правила игрового процесса",
"",
"4.1 Запрещен ДМ (от англ. Deathmatch) - нанесение урона игрокам без причины. Наказание: ТСР 30 level (30 заданий каждого типа и 90 минут)  ТСР 60 level (60 заданий каждого типа и 180 минут) при повторном нарушении в течение 7 дней.",
"Примечание: Перестрелка за общедоступные клады не считается ДМ’ом.",
"4.2 Запрещен ДБ (от англ. DriveBy) - нанесение урона машиной. Наказание: ТСР 30 level (30 заданий каждого типа и 90 минут)  ТСР 60 level (60 заданий каждого типа и 180 минут) при повторном нарушении в течение 7 дней.",
"4.3 Запрещен СК (от англ. Spawn Kill) - нанесение урона на респауне. Наказание: ТСР 30 level (30 заданий каждого типа и 90 минут)  ТСР 60 level (60 заданий каждого типа и 180 минут) при повторном нарушении в течение 7 дней.",
"4.4 Запрещен ТК (от англ. Team Kill) - нанесение урона союзникам / членам своей фракции. Наказание: ТСР 30 level (30 заданий каждого типа и 90 минут)  ТСР 60 level (60 заданий каждого типа и 180 минут) при повторном нарушении в течение 7 дней.",
"4.5 Запрещен ПГ (от англ. Power Gaming) - нападение в меньшинстве на группу игроков существенно больше вашей. Наказание: ТСР 30 level (30 заданий каждого типа и 90 минут)  ТСР 60 level (60 заданий каждого типа и 180 минут) при повторном нарушении в течение 7 дней.",
"Примечание: 1 игрок может напасть максимум на двоих, 1 сотрудник ПД/ФБР максимум на троих (2 игрока на четверых и т.д.)",
"Примечание: 2 спутника (бота охранника) приравниваются к 1 игроку.",
"4.6 Запрещен массовый (неоднократный - от 3 пострадавших) ДМ/ДБ/СК/ТК. Наказание: Бан 3 дней + запрет использования оружия/транспорта на 3 дней  Бан 7 дней + запрет использования оружия/транспорта при повторном нарушении в течение 7 дней.",
"4.7 Запрещено нонРП поведение (от англ. Not Role Play) - поведение, которое нарушает реализм и логику игрового мира:",
"4.7.1 От игрока без фракции. Наказание: ТСР 10 level (10 заданий каждого типа и 30 минут)  ТСР 20 level (20 заданий каждого типа и 60 минут) при повторном нарушении в течение 7 дней.",
"4.7.2 От игрока, состоящего во фракции. Наказание: ТСР 30 level (30 заданий каждого типа и 90 минут)  Варн при повторном нарушении в течение 7 дней.",
"4.8 Запрещен ОФФ / АФК / Отказ от РП ситуации. Наказание: ТСР 30 level (30 заданий каждого типа и 90 минут)  ТСР 60 level (60 заданий каждого типа и 180 минут)  при повторном нарушении в течение 14 дней — Варн.",
"Примечание: Повторным нарушением считается любой новый факт ОФФ/АФК/отказа от РП в течение 14 дней после предыдущего наказания по данному пункту. Отсутствие ответа на вопрос в /do от игрока, который не участвовал с вами в РП, не является отказом от РП.",
"4.9 Запрещен ОФФ / АФК / Инта / Уход в ЗЗ / Аксессуары от смерти. Наказание: ТСР 30 level (30 заданий каждого типа и 90 минут)  ТСР 60 level (60 заданий каждого типа и 180 минут)  при повторном нарушении в течение 14 дней — Варн.",
"4.10 Запрещен ОФФ / АФК / Инта / Уход в ЗЗ / Аксессуары от ареста. Наказание: Варн.",
"4.11 Запрещен сбив любых системных анимаций. Наказание: ТСР 15 level (15 заданий каждого типа и 45 минут)  ТСР 30 level (30 заданий каждого типа и 90 минут) при повторном нарушении в течение 7 дней.",
"4.12 Запрещен сбив анимации выстрела любым способом. Наказание: ТСР 30 level (30 заданий каждого типа и 90 минут)  ТСР 60 level (60 заданий каждого типа и 180 минут) при повторном нарушении в течение 7 дней.",
"Исключение: +с в стену при отсутствии других игроков не наказуемо.",
"4.13 Запрещено использование средств пополнения здоровья/бронежилета в бою. Наказание: ТСР 30 level (30 заданий каждого типа и 90 минут)  ТСР 60 level (60 заданий каждого типа и 180 минут) при повторном нарушении в течение 7 дней.",
"Исключение: автоматическое надевание бронежилета; использование на территории подземной шахты; использование на территории с возможностью получения красного розыска.",
"4.14 Запрещены серьезные нарушения в ТСР (ДМ, ПГ, сбивы и т.п). Наказание: Варн.",
"4.15 Запрещено использовать дубинку, тазер и команды, ограничивающее свободное перемещение (например: /cuff) в бою. Наказание: ТСР 60 level (60 заданий каждого типа и 180 минут)  ТСР 120 level (120 заданий каждого типа и 360 минут) при повторном нарушении в течение 14 дней.",
"4.16 Запрещено использование маскировки не по назначению (например: для отправки бредовых сообщений в рацию и т.д.). Наказание: Мут на 60 минут  на 120 минут при повторном нарушении в течение 7 дней.",
"4.17 Руководству казино запрещено выгонять игроков с территории и заносить в ЧС казино без веской причины, а также по выдуманным основаниям. Выгнать игрока допускается только при наличии нарушения правопорядка или правил проекта. Наказание: ТСР 30 level (30 заданий каждого типа и 90 минут)  ТСР 60 level (60 заданий каждого типа и 180 минут) при повторном нарушении в течение 14 дней.",
"4.18 Запрещено запускать системный митинг с неадекватной, либо нонРП причиной. Наказание: Остановка митинга + ТСР 30 level (30 заданий каждого типа и 90 минут)  ТСР 60 level (60 заданий каждого типа и 180 минут) при повторном нарушении в течение 7 дней.",
"4.19 Запрещено гражданским нападать на военную часть и объекты ВЧ не с целью кражи материалов/ингредиентов/убийства ботов(фарма осколков). Нападение ради СК, ДМ-а военных на спавне или \"ради веселья\" — запрещено. Наказание: ТСР 30 level (30 заданий каждого типа и 90 минут)  ТСР 60 level (60 заданий каждого типа и 180 минут) при повторном нарушении в течение 7 дней.",
"4.20 Запрещено РП в свою сторону - умышленное игнорирование или искажение РП-отыгровки другой стороны с целью получения преимущества.",
"Примеры нарушений:",
"- игрок в маске требует предъявить документы или «личное дело», хотя по РП его личность не установлена;",
"отыгровка угрозы (бомба, оружие) воспринимается как «игрушка» без последствий;",
"отказ признавать очевидные РП-факты (форма, удостоверение, значки).",
"Наказание: ТСР 30 level (30 заданий каждого типа и 90 минут)  ТСР 60 level (60 заданий каждого типа и 180 минут) при повторном нарушении в течение 7 дней.",
"",
"#5. Правила игровых чатов",
"",
"5.1 Правила игровых чатов распространяются на все текстовые и голосовые чаты.",
"5.2 Запрещен МГ (от англ. Meta Gaming) - использование игроком знаний (в РП чаты), которые его персонаж не может знать. Наказание: Мут на 10 минут  на 30 минут при повторном нарушении в течение 7 дней.",
"Пример: слова “скин”, “бан”, “мут”, отдельно символы: \"?\", \"/\", \")\" и т.д.",
"5.3 Запрещен капс - написание слов заглавными буквами (даже одно). Наказание: Мут на 10 минут  на 30 минут при повторном нарушении в течение 7 дней.",
"5.4 Запрещен флуд - отправка 3 и более одинаковых строк в 60 секунд. Наказание: Мут на 30 минут  на 60 минут при повторном нарушении в течение 7 дней.",
"Примечание: организованный флуд (от нескольких человек) и схожие сообщения (с той же сутью) наказываются как и обычный флуд.",
"Примечание: к организации флуда также относится провокация игроков на массовую отправку однотипных сообщений (например: «кто первый поставит +», «пишите 123»). Наказание выдается организатору.",
"5.5 Запрещено злоупотребление матом в нонРП чаты. Наказание: Мут на 30 минут  на 60 минут при повторном нарушении в течение 7 дней.",
"Примечание: злоупотребление матом - это чрезмерное употребление ненормативной лексики; за одиночные маты, встречающиеся не в каждом вашем сообщении, наказание выдаваться не будет.",
"5.6 Запрещено злоупотребления символами (Спам). Наказание: Мут на 30 минут  на 60 минут при повторном нарушении в течение 7 дней.",
"Пример: “--------”, “1111111”, “спасиииииииите”",
"5.7. Запрещён розжиг действия или высказывания, направленные на разжигание вражды, ненависти или конфликта между народами, этническими группами или национальностями.",
"5.7.1. Провокация на розжиг. Пример: завуалированные или провокационные высказывания, способные спровоцировать конфликт. Наказание: Мут на 120 минут  на 300 минут при повторном нарушении в течение 7 дней.",
"5.7.2. Розжиг. Пример: прямые оскорбительные или уничижительные высказывания по национальному или этническому признаку и т.п. Наказание: Бан 3 дня  на 7 дней при повторном нарушении в течение 7 дней.",
"5.8 Запрещена реклама:",
"5.8.1 паблика в ВК/сервера, промокода и т.д. Наказание: Мут на 120 минут  на 300 минут при повторном нарушении в течение 14 дней.",
"5.8.2 любых неофициальных сайтов и других сторонних платформ, на которых продается/покупается виртуальная валюта, аккаунты и имущество. Наказание: Бан на 2000 дней",
"5.9 Упоминание родных в т.ч. завуалированное. Наказание: Мут 300 минут  Бан на 7 дней при повторном нарушении в течение 30 дней.",
"5.10 Оскорбление родных в т.ч. завуалированное. Наказание: Бан 10 дней  Бан на 30 дней при повторном нарушении в течение 60 дней.",
"5.11 Пожелание смерти родным. Наказание: Бан 15 дней  на 30 дней при повторном нарушении в течение 60 дней.",
"5.12 Запрещен оффтоп в /report. Наказание: Мут репорта на 10 минут  на 30 минут при повторном нарушении в течение 7 дней.",
"5.13 Запрещено оскорбление сервера/проекта. Наказание: Мут 300 минут  Бан 7 дней при повторном нарушении в течение 14 дней.",
"5.14 Запрещено оскорбление, неадекватное поведение, неуважительное отношение к игрокам/ неадекватное поведение, неуважительное отношение к администрации. Наказание: Мут на 120 минут  на 300 минут при повторном нарушении в течение 7 дней.",
"Примечание: оскорбление игроков в рамках РП ситуации не наказывается",
"5.15 Запрещено оскорбление администрации. Наказание: Мут на 120 минут  Бан 5 дней при повторном нарушении в течение 14 дней.",
"5.16 Запрещено оскорблять или высмеивать других игроков из-за их физических особенностей (например: заикания, нарушения слуха и т.п.). Наказание: Мут 300 минут  Бан 7 дней при повторном нарушении в течение 30 дней.",
"5.17 Запрещено призывать к нарушению правил сервера (Пример: призыв к рванке на слете). Наказание: Мут на 120 минут  на 300 минут при повторном нарушении в течение 7 дней.",
"5.18 В канале департамента (/d) запрещены торги/реклама/неадекватное поведение. Наказание: Мут на 60 минут  на 120 минут при повторном нарушении в течение 7 дней.",
"5.19 В вип чате (/vr) запрещено использовать имя пользователя в соц. сетях (Например: Discord, VK, TG). Наказание: Мут на 60 минут  на 120 минут при повторном нарушении в течение 7 дней.",
"5.20 В вип чате (/vr) запрещена любая реклама (в т.ч. купля/продажа) в обход системы (при отправке сообщения обязательно нажать \"ДА\" в диалоге). Наказание: Мут на 60 минут  на 120 минут при повторном нарушении в течение 7 дней.",
"5.21 В рабочую рацию (/j, /jb) запрещена реклама/торги/обсуждение цен/услуги аренд и т.п., кроме: предметов/имущества/услуг, связанных с работами центра занятости. Наказание: Мут на 60 минут  на 120 минут при повторном нарушении в течение 7 дней.",
"Пример: потерял ключи от автомобиля Porsche, кто найдет - напишите п и т.п.)",
"Дополнение: Реклама в рабочую рацию (/j, /jb) разрешена раз в 3 минуты (1 строчкой), не соблюдение интервала. Наказание: Мут на 60 минут  на 120 минут при повторном нарушении в течение 7 дней.",
"5.22 Запрещено изнасилование и любые насильственные действия сексуального характера.Наказание: Бан 30 дней",
"5.23 Запрещены нонРП Билборды - билборды, содержащие в себе нарушение любого пункта правил чата. Наказание: Удаление билборда + ТСР 30 level (30 заданий каждого типа и 90 минут)  ТСР 60 level (60 заданий каждого типа и 180 минут) при повторном нарушении в течение 7 дней.",
"5.24 Запрещено намеренно неправильно редактировать объявления в СМИ.Наказание: Мут на 120 минут  Варн при повторном нарушении в течение 7 дней.",
"5.25 Запрещено нарушать правила проведения эфиров в СМИ. Наказание: Мут на 120 минут  Варн при повторном нарушении в течение 7 дней.",
"5.26 Запрещено любое употребление нацистских приветствий/лозунгов/символики и прочих проявлений нацизма, ненависти и нетерпимости к другим нациям. Наказание: Бан 7 дней  на 30 дней при повторном нарушении в течение 30 дней.",
"5.27 Запрещено распространение информации, доступной исключительно подписчикам boosty. Наказание: Мут на 300 минут  Бан на 7 дней при повторном нарушении в течение 30 дней.",
"5.28 Запрещено любое упоминание, обсуждение или отыгровка наpкотических веществ из реальной жизни (не относящихся к вымышленным игровым предметам и механикам сервера). Наказание: Мут на 300 минут  Бан на 3 дня при повторном нарушении в течение 14 дней.",
"5.29 Запрещён NonRP-вызов при обращении в полицию. Наказание: Мут на 60 минут  на 120 минут при повторном нарушении в течение 14 дней.",
"Примечание: NonRP-вызов — это обращение без игровой причины: сообщения не по теме, шутки, оскорбления, флуд и провокации.",
"",
"#6. Правила голосового (Voice) чата",
"",
"6.1 Voice чат - IC чат. Разрешено передавать ООС информацию в голосовой (Voice) чат, если рядом с Вами нет игроков, чью RP атмосферу/ситуацию Вы можете испортить.",
"6.2 Разрешена отыгровка действий /me и /do посредством голосового (Voice) чата.",
"Примечание: Отыгровка /me должна производиться от первого лица.",
"Пример: \"/me достал ручку из правого кармана пиджака\" ; \"/do Ручка лежит в центре стола.\"",
"6.3 Запрещено не отключать голосовой чат во время Вашего молчания(гул). Наказание: Мут на 10 минут  на 30 минут при повторном нарушении в течение 7 дней.",
"6.4 Запрещено издавать любые громкие или мешающие звуки, любые помехи микрофона (шорох, треск и т.д.).Наказание: Мут на 30 минут  на 60 минут при повторном нарушении в течение 7 дней.",
"6.5 Запрещено включение любой музыки в общественных местах [Исключение: разрешено исполнение музыки с использованием музыкальных инструментов, а также пение.]. Наказание: Мут на 60 минут  на 120 минут при повторном нарушении в течение 7 дней.",
"6.6 Запрещено включение каких либо записанных голосов/звуков (Например: записанные отрывки фраз блогеров). Наказание: Мут на 30 минут  на 60 минут при повторном нарушении в течение 7 дней.",
"6.7 Запрещено кричать без какой-либо причины. Наказание: Мут на 30 минут  на 60 минут при повторном нарушении в течение 7 дней.",
"6.8 Запрещено неадекватное вмешательство в RP процесс других игроков. Наказание: Мут на 30 минут  на 60 минут при повторном нарушении в течение 7 дней.",
"6.9 Запрещено использование любого софта для изменения голоса (робот, демоны, звуки животных и т.д.). Наказание: Мут на 30 минут  на 60 минут при повторном нарушении в течение 7 дней.",
"",
"#7. Правила экономических взаимодействий и использования бизнесов",
"",
"7.1 Запрещена продажа/обсуждение продажи игровой валюты, услуг, аккаунта или иных игровых ценностей за реальную валюту или какой-либо эквивалент. Наказание: Бан 2000 дней",
"7.2 Запрещена покупка игровой валюты и других игровых ценностей за реальные деньги. Наказание: Бан 2000 дней.",
"Примечание: Игроки, готовые открыто признать нарушение и сотрудничать с администрацией, могут рассчитывать на смягчение меры наказания в индивидуальном порядке — вплоть до полной разблокировки игрового аккаунта с изъятием полученных средств.",
"7.3 Запрещен обмен имуществом / виртами на разных серверах в обход существующей системы перелетов. Наказание: Бан 2000 дней",
"7.4 Запрещена передача/получение любых игровых ценностей перед получением блокировки (если на вас была подана жалоба, по которой вас могут заблокировать). Наказание: Бан 30 дней",
"7.5 Запрещен РП и НонРП развод(попытка развода) - обман игрока, связанный с нарушением условий договора IC и OOC сделок(Правила IC и OOC сделок).",
"7.5.1 Попытка РП или НонРП развода. Наказание: Бан 30 дней.",
"7.5.2 РП или НонРП развод. Наказание: Бан 2000 дней.",
"7.6 На острове ViceCity запрещено дарить, давать в долг или переносить игровые ценности общей стоимостью свыше 10 миллиардов без предварительного согласования с главным администратором. Наказание: Откат сделки - в случае отказа бан 30 дней.",
"7.7 Запрещено проводить фейк конкурсы и розыгрыши (Розыгрыши должны быть заранее согласованы с главной администрацией сервера, на котором проводится конкурс, а итоги проводиться в виде онлайн-трансляции с последующим хранением записи стрима). Наказание: Отмена конкурса , повторно несогласованное проведение после первого случая Бан 30 дней.",
"7.8 Запрещен обход официального доната (например: человек донатит другу, а друг передает в виртах вам, либо любой другой обмен AZ на вирты, кроме /donate). Наказание: Бан 30 дней",
"7.9 Запрещено иметь бизнесы на твинке. Наказание: Изъятие бизнесов",
"7.10 Запрещено назначать заместителей на наземных нефтевышках за любые игровые ценности. Наказание: Бан 30 дней.",
"7.11 Запрещено нарушение функционирования бизнеса сроком более 7 дней (Например: закрытие фермы; временное открытие бизнеса не продлевает срок). Наказание: Требование восстановления функционирования, отказ\\ повторная ситуация в течение 90 дней - Бан 15 дней.",
"7.12 Запрещено иметь больше одной частной фракции в одной структуре (гос/нелегалы) без одобрения от ГА. Наказание: Требование продажи одной из организаций, отказ Изъятие фракции.",
"7.13 Запрещена передача любых игровых ценностей игрокам, которые могут принимать участие в махинациях (в том числе спонсирование игроков для нечестного участия в слетах имущества). Администрация может расценить вас за соучастника.",
"7.14 Не рекомендуется совершать игровые сделки через мусорки, багажники, шкафы и т.п. во избежание ошибочных наказаний, так как подобные сделки вызывают дополнительные подозрения у администрации. Для всех передач имеется системный функционал (Обмен через /trade, центр обмена имуществом, банковский перевод и так далее).",
"7.15 Если Вы получили любые игровые ценности от неизвестного Вам игрока (который теоретически может оказаться махинатором, багоюзером и т.д.), следует сообщить старшей администрации для проверки данного игрока. Если он окажется «чистым», то у вас ничего не заберут. Данными действиями вы сможете обезопасить свой игровой аккаунт от наказаний.",
"7.16 Запрещено владеть несколькими электрокомпаниями на разных аккаунтах в обход системы (системно допустимо владение 1 электрокомпаниями на 1 аккаунте).",
"7.17 Запрещен обход системных комиссий и лимитов. (Например: обход системы дачи взятки, обход продажи рангов в частных фракциях, обход комиссии при продаже дома, обход комиссии при продаже бизнеса). Необходимо осуществлять обмен, продажу и покупку любыми традиционными доступными внутриигровыми способами. Наказание: доначисление неуплаченной комиссии + при отказе блокировка аккаунта 2000 дней.",
"Правильный пример: Продажа бизнеса за 10 000 000 000  в системном меню продажи указывается максимальная сумма (максимальный системный лимит, комиссия оплачена), остаток передаётся через /trade. Дом/Бизнес/Фракция продаётся через системное меню  в окне продажи указывается максимально доступная сумма  оставшаяся разница передаётся путём передачи денег/предметов через /trade.",
"Неправильный пример: В системном меню указывается 1 000 000 (комиссия минимальна), остаток передан через /trade или багажник.",
"Примечание: При добровольной уплате комиссии блокировка аккаунта выдана не будет. Администрация всегда идёт на встречу добросовестным игрокам. При отказе от оплаты комиссии возможна блокировка аккаунта до добровольной уплаты.",
"",
"#8. Правила поведения на слетах и аукционах",
"",
"8.1 За любое нарушение правил, которое оказало влияние на исход слета имущества, Вам могут отказать верификацию.",
"Исключение: Любые сбивы анимации, использование домкрата с целью торможения во время ловли, а также использование отображения трейсера до личного транспорта.",
"8.2 Необходимо записывать опровержения: ловли домов, ловли бизнесов, ловли транспорта (кроме ситуаций, когда транспорт выставлен на продажу в автосалоне более минуты), ловли сгоревших лотерейных билетов.",
"Примечание: если имущество стоит в госе длительное время, то вы можете купить его без записи опровержения.",
"Опровержение должно отражать весь процесс ловли вне зависимости от сезона, соответственно должно отражать: /time, как вы добрались от риэлторского агентства до дома, как вы вводили капчу и т.д.;",
"Каждый участник слёта в обязательном порядке должен записывать слёт и хранить запись пять суток.",
"опровержение должно иметь хорошее качество (720p или выше). Все элементы должны быть читаемы;",
"любой монтаж/изменение/редактирование видео запрещены, в этом администрация в праве",
"отказать в рассмотрении.",
"по желанию записываются звуки клавиатуры и любой пробив, которые могут оказать ключевое значение в спорной ситуации;",
"опровержение должно храниться не менее 5 дней;",
"опровержение должно быть предоставлено в течении 24-х часов после запроса администрацией(могут быть исключения). Наказание: Бан на 5 дней  на 10 дней при повторном нарушении в течение 7 дней.",
"8.3 Запрещено создавать помеху другим игрокам любым образом (Предлагать обмены и т.д.). Наказание: ТСР 30 level (30 заданий каждого типа и 90 минут)  ТСР 60 level (60 заданий каждого типа и 180 минут) при повторном нарушении в течение 7 дней.",
"8.4 Запрещено наносить урон в т.ч. транспортом. Наказание: ТСР 75 level (75 заданий каждого типа и 225 минут)  ТСР 150 level (150 заданий каждого типа и 450 минут) при повторном нарушении в течение 7 дней.",
"8.5 Запрещено убийство игроков. Наказание: Бан на 2 дня  на 5 дней при повторном нарушении в течение 7 дней.",
"8.6 Запрещено соучастие с нарушителем (Например: с рванщиком): Наказание: Аналогичное нарушителю",
"8.7 Запрещено использование недоработок, дающих существенное преимущество (Например: шифт на ловле транспорта). Наказание: Бан на 3 дня  на 7 дней при повторном нарушении в течение 7 дней.",
"8.8 Запрещено использование программ/скриптов/ботов/сайтов, предоставляющих информацию о последнем заходе игрока в игру, его активности, историю наказаний - приравнивается к чекеру ловли. Наказание: Бан 2000 дней.",
"8.9 Разрешено любыми способами удалять/убирать двери транспортного средства во время ловли.",
"8.10 Разрешены любые сбивы анимаций, скорости (ESC, /domkrat, /limit)",
"",
"#9.Правила кастомизации имущества",
"",
"9.1 За неоднократное нарушение правил данного раздела владельцу имущества может быть установлен системный запрет на установку маппинга.",
"9.2 Запрещено нонРП, неадекватное, бредовое название дома/бизнеса. Наказание: ТСР 30 level (30 заданий каждого типа и 90 минут) + Удаление названия администрацией  ТСР 60 level (60 заданий каждого типа и 180 минут) при повторном нарушении в течение 14 дней.",
"9.3 Запрещено реклама бизнесов/семьи/промокодов, продажа имущества и т.д. в названии дома/бизнеса. Наказание: ТСР 30 level (30 заданий каждого типа и 90 минут) + Удаление названия администрацией  ТСР 60 level (60 заданий каждого типа и 180 минут) при повторном нарушении в течение 14 дней.",
"",
"Правила маппинга",
"При нарушении правил размещения маппинга администрация применяет одну из трёх мер в зависимости от ситуации:",
"",
"Слабая мера применяется при незначительных или визуальных нарушениях, которые не мешают игрокам.",
"Наказание: Устное предупреждение на исправление маппинга. Срок исправления: 72 часа. При отказе или игнорировании маппинг удаляется.",
"Средняя мера применяется, если нарушение связано с конкретным объектом или небольшой частью маппинга.",
"Наказание: Удаление отдельного объекта.",
"Высшая мера применяется при грубых нарушениях, массовой помехе игрокам, повторных нарушениях или отказе исправлять маппинг.",
"Наказание: Удаление всего маппинга.",
"Запрещено:",
"9.4 Запрещено размещать маппинг неестественным или нелогичным образом, а также использовать его не по назначению для получения преимуществ.",
"Пример: \"левитирующие\" объекты, использование заборов в качестве перекрытий, размещение растительности на бетоне/крышах и создание вспомогательных конструкций для доступа на труднодоступные объекты.",
"9.5 Запрещено размещать объекты маппинга, препятствующие доступу к территории имущества или мешающие движению транспорта и игроков.",
"Пример: размещение объектов на дорогах, парковках, проходах, путях въезда и выезда.",
"9.6 Запрещено размещать более одного массивного объекта или перегружать территорию крупным маппингом.",
"Пример: несколько больших ёлок, зданий или крупных декораций.",
"9.7 Запрещено размещать любые объекты маппинга, особенно крупные, необычные или сильно выделяющиеся, в популярных местах и зонах с большой проходимостью.",
"Пример: ЦР, ЦБ, АБ, АШ, вокзалы, территории фракций, входы и выходы зданий. Запрещены такие объекты, как огромные сердца, воздушные шары и иные громоздкие или неуместные декорации.",
"9.8 Запрещено неестественный вид тюнинга: Устное предупреждение об изменении тюнинга (В случае отказа - удаление тюнинга)",
"Примечание: НонРП тюнингом является его неестественное размещение, например в воздухе. Тюнинг на авто должен выглядит естественно, как в реальной жизни, транспорт не должен быть похож на постапокалиптический. Доска вместо бампера является нонРП тюнингом. Тюнинг может быть удален, даже если за рулем находится не владелец.",
"9.9 Запрещено использование тюнинга с целью навредить игрокам. Наказание: Запрет использование транспорта на 1 день  Запрет использование транспорта на 3 дня при повторном нарушении в течение 7 дней .",
"Исключение: Таран преступника тюнингом от сотрудников МЮ в процессе погони не является нарушением.",
"9.10 Запрещена парковка трейлеров, создающая помеху движению транспорта, перекрывающая проезжую часть, съезды или въезды. Трейлер не должен находиться в текстурах. Наказание: Спавн трейлера  ТСР 15 level (15 заданий каждого типа и 45 минут) + спавн трейлера при повторном нарушении в течение 7 дней.",
"Примечание: Трейлер не должен находиться на дороге и прилегающей территории или в непосредственной близости к нему, если это препятствует свободному проезду других игроков.",
"9.11 Установленные объекты маппинга на территории бизнеса должны соответствовать типу данного бизнеса и не выбиваться из его тематики.",
"Пример: возле ларька с едой разрешено размещать коробки с продуктами, столики, мусорные баки и другие объекты, связанные с едой или обслуживанием клиентов. Возле оружейного магазина разрешено размещать ящики с патронами, оружие, охранные элементы и другие объекты, связанные с оружейной тематикой.",
"Примечание: допускаются небольшие отклонения для RP-ситуаций или оформления территории, если они логично подходят к бизнесу и не меняют его визуальную тематику.",
"Спойлер: Пример размещения",
"9.12 Запрещено размещать объекты маппинга, которые не относятся к типу бизнеса или выглядят нелогично для его территории.",
"Наказание: Устное предупреждение на исправление маппинга. Срок исправления: 48 часов. При отказе или игнорировании маппинг удаляется.",
"Пример: запрещено размещать несоответствующие объекты: космический кристалл, Пиноккио, робот-заяц и иные объекты, не относящиеся к оружейной тематике.",
"",
"#10. Правила поведения вне сервера",
"",
"10.1 Правила данного раздела относятся исключительно к официальным ресурсам проекта. Ими являются: форум проекта, официальные группы в ВК и ТГ, Discord-сервера, конференции ВК, относящиеся к серверу, и так далее.",
"10.2 Наказания игрокам по данному разделу не выдаются, если:",
"с момента отправки сообщений прошло более 30 дней;",
"игроки нарушали вне официальных ресурсов, например в личных сообщениях.",
"10.3 Запрещено неадекватное поведение. Наказание: Мут на 120 минут  на 300 минут при повторном нарушении в течение 7 дней.",
"10.4 Запрещено оскорбление администрации. Наказание: Мут на 120 минут  Бан 5 дней при повторном нарушении в течение 14 дней.",
"10.5 Запрещено оскорбление проекта. Наказание: Мут 300 минут  Бан 7 дней при повторном нарушении в течение 14 дней.",
"10.6 Запрещено упоминание родных. Наказание: Мут на 300 минут  Бан на 7 дней при повторном нарушении в течение 30 дней.",
"10.7 Запрещено оскорбление родных. Наказание: Бан на 10 дней  Бан на 30 дней при повторном нарушении в течение 60 дней.",
"10.8 Запрещено предлагать (намекать) кому-либо купить/продать любые игровые ценности, либо заниматься иными вредительскими действиями (рванка, DDOS, установка ракботов и т.п.). Наказание: Бан на 2000 дней.",
"Примечание: данный пункт действует вне официальных ресурсов проекта, в т.ч. в личных сообщениях.",
"10.9 Запрещён деанон всех видов (раскрытие личной информации). Наказание: в соответствии с пунктом 2.15, 2.15.1, 2.15.2, 2.15.3 настоящих правил.",
"",
"#11. Правила ограблений и похищений",
"",
"11.1 В течение трех дней после постановления человека на пост лидера государственной организации запрещено совершать его похищение.",
"11.2 Теракты/похищения разрешено проводить с 15:00 до 21:00.",
"11.3 Интервал между проведении терактов/похищений — 2 часа.",
"11.4 Теракты разрешено проводить не более 3 раз в неделю, похищения — не более 1 раза в день (на организацию).",
"11.5 Организаторы теракта обязаны предупредить следящих не менее чем за 24 часа до его проведения. На мероприятии обязан присутствовать 9+ ранг.",
"11.6 Переговорщик от ФБР обязан записывать весь процесс преступного мероприятия на видео с /time с помощью любой программы захвата экрана. Переговорщик от нелегальных структур также обязан вести запись со своей стороны и предоставить видео по первой просьбе администрации (срок хранения записи — 3 дня).",
"11.7 Запрещено пытаться калечить/насиловать похищаемого/заложника.",
"11.8 Запрещено требовать от похищенного/заложника/властей написать заявление об уходе.",
"11.9 Запрещено требовать увольнения кого-либо.",
"11.10 Запрещено находиться в АФК более 120 секунд.",
"11.11 Разрешено убивать заложников только в случае, если начался штурм и материальные требования не были переданы. В ином случае убивать заложника запрещено, за исключением пунктов, которые это прямо разрешают.",
"11.12 Заложнику запрещено: грубить, дерзить или провоцировать преступников; пытаться убежать, если у преступников имеется оружие; обманывать; взаимодействовать с телефоном.",
"11.13 За любое нарушение настоящих правил последует наказание по правилам проекта (от мута до бана в зависимости от нарушения).",
"Похищаемый может покинуть игру досрочно только при обоюдном согласии сторон (отсутствии взаимных претензий). В ином случае выход приравнивается к нарушению и может повлечь наказание.",
"11.14 Максимальная продолжительность теракта или похищения не должна превышать 90 минут.",
"",
"МАСКА",
"11.15 С целью сокрытия своей личности нелегальные структуры вправе использовать маски на похищениях/терактах. Системной маской считается /mask. В случае окончания системной маски во время визуального контакта с агентом разрешается надеть её снова. В случае если маска не была надета в течение 1 минуты, агент может запомнить представителей нелегальных структур.",
"11.16 Любой аксессуар, надеваемый в слот маски или закрывающий лицо, считается аналогом /mask. При наличии такого аксессуара на представителях нелегальных структур их нельзя распознать по лицу, глазам и иным визуальным признакам, даже если аксессуар не закрывает лицо полностью.",
"11.17 В случае отсутствия одновременно обоих видов маски (системной и аксессуара) агенту, видевшему похитителей, разрешено по окончании преступного мероприятия выдать розыск людям, которых он видел.",
"",
"ЗАХВАТ ЗАЛОЖНИКА",
"11.18 Захват заложника должен проходить максимально адекватно. Нелегальные структуры вправе использовать различные способы захвата, включая обман. Также они имеют право ликвидировать лишних лиц или сопровождение похищаемого при условии, что остаются в численном преимуществе в 3 раза.",
"11.19 На одного заложника при похищении необходимо 3 представителя нелегальных структур.",
"11.20 Похищения разрешено проводить только в безлюдных местах, переулках и за пределами города. В зелёных зонах похищение допускается только при отсутствии свидетелей поблизости (исключение: на охраняемых объектах или возле них (по сектору, как в пунктах 5.1), вокруг этих объектов) по типу ФБР, полицейские департаменты, офис ЛВПД, военные базы и т.п.",
"11.21 Сообщение о похищении или теракте необходимо передавать через волну департамента (/d), указав номер телефона переговорщика со стороны нелегальных структур. В случае если указанный телефон выключен или недоступен, ФБР обязаны уведомить об этом нелегальные структуры через /d.",
"11.22 Заложников следует держать в безлюдном месте, где помимо всего прочего удобно проводить переговоры. Это могут быть крыши зданий, заброшенные территории и тому подобное.",
"11.23 При проведении похищения запрещается держать заложников в гетто, в интерьерах, на спавне фракций, в зелёных зонах или иных людных местах, а также на текстурах или в воздухе. Данное ограничение не распространяется на теракты.",
"11.24 Место проведения переговоров должно быть легкодоступным для переговорщика. Если для доступа требуется вертолёт, на территории должна быть открытая площадка или местность, позволяющая без затруднений осуществить посадку.",
"11.25 После завершённой ситуации [ФБР  нелегальные структуры] похищенный получает «иммунитет» от похищений на 48 часов. В течение этого времени он не может быть повторно использован в качестве заложника.",
"11.26 После выполнения всех требований запрещается забирать и увозить с собой заложников (исключение — допускается до момента выхода в зелёный коридор и посадки похитителей в транспорт). Заложник должен оставаться неподалёку от места переговоров и быть в лёгкой доступности для МЮ.",
"",
"ЭТАП ТРЕБОВАНИЙ",
"Как только было объявлено о похищении/теракте, федеральные агенты связываются с нелегальными структурами по указанному номеру телефона и выслушивают их требования. В случае теракта допустимы переговоры лично.",
"Требования должны быть адекватными. В случае если агент посчитает требования невозможными к выполнению, он вправе попросить поменять их.",
"",
"ОБЩИЕ ПРАВИЛА ПО ТРЕБОВАНИЯМ И ПЕРЕГОВОРАМ",
"11.27 Требования нелегальных структур должны быть максимально точными, адекватными, чёткими и понятными для переговорщика, а также соответствовать игровым возможностям ФБР. Пример неправильных требований: «Я не должен видеть копов в поле своего зрения», «Запрашиваю перекрытие территории примерно в радиусе 2 км», «Принеси мне голову живого человека», «Ну принеси это, ну там короче штуку такую», «Приведите мне губернатора штата Show-Low». Пример правильных требований: «Хочу перекрыть квадрат В12 и все прилежащие к нему квадраты», «Я не должен видеть копов в квадрате ведения переговоров», «Принесите мне кейс с 25.000.000$ и 120 грамм \"укропа\"», «Дайте мне возможность связаться с нашим губернатором».",
"11.28 Разговор по телефону/личный разговор считается началом похищения/теракта и самих переговоров. На протяжении всех переговоров нелегальные структуры и ФБР должны вести себя адекватно и в соответствии со своей ролью. Это не означает, что нелегальные структуры обязаны обращаться к агенту на «Вы», но неадекватно вести себя, оскорблять агента прямым текстом запрещено.",
"11.29 Требования могут быть материальные и нематериальные. Материальными требованиями считаются те требования, которые включают в себя физические объекты в ролевом мире. Все остальные требования считаются нематериальными.",
"11.30 Во время похищения/теракта все требования должны быть изложены по выбранному способу (телефон, диалог лицом к лицу и т.д.). Когда переговорщик приступает к выполнению требований, после их обсуждения деталей переговоры считаются оконченными и изменению/дополнению не подлежат. После окончания переговоров запрещено дополнять или изменять требования.",
"11.31 Количество материальных и нематериальных требований ограничено — не более 5. Нелегальные структуры вправе потребовать не более 5 материальных требований и 5 нематериальных. Это правило сделано для того, чтобы нелегальные структуры требовали только то, что им действительно нужно, и похищение/теракт не превращалось в поход в магазин.",
"11.32 Минимальное время, которое нелегальные структуры могут дать переговорщику на выполнение материальных и нематериальных требований, равно 10 минутам. Однако в случае запроса большого количества требований или труднодоступных требований нелегальным структурам желательно пойти навстречу переговорщику и дать больше времени. Минимальное время увеличивается на 15 минут вне зависимости от желания нелегальных структур.",
"ПРИМЕЧАНИЕ: Время, которое уделяется переговорщику на выполнение материальных и нематериальных требований, начинается с момента сброса звонка от нелегальных структур.",
"11.33 Нелегальным структурам запрещено требовать прибытия на переговоры определённого агента. Переговорщика выбирает ФБР.",
"11.34 В случае возникновения у переговорщика вопросов относительно требований нелегальные структуры обязаны ответить на них. Диалог между переговорщиком и нелегальными структурами должен быть максимально живым и соответствовать рамкам ролевой игры.",
"11.35 В случае если агент ФБР нарушил требование, забыл его принести/выполнить и тому подобное, нелегальные структуры имеют право увеличить сумму выкупа на 20% от изначальной суммы за каждое невыполненное требование. Переговорщик со стороны нелегальных структур обязан указать на конкретное требование и запросить дополнительную сумму.",
"ПРИМЕЧАНИЕ: В таком случае не обязательно ехать и пересобирать кейс. Достаточно по РП доложить необходимую сумму на месте.",
"11.36 В случае если агент ФБР нарушил требование, забыл его принести/выполнить и тому подобное, нелегальные структуры имеют право убить заложника, но в этом случае наказания для агента не последует.",
"11.37 ФБР обладает огромным количеством ресурсов и связей, и им не составляет труда достать любые вещи. В связи с этим вы вправе потребовать любое материальное требование, даже отсутствующее по моду.",
"11.38 Нелегальным структурам запрещено требовать от ФБР какие-то скриншоты или «чеки» приобретения этих отсутствующих по моду материальных требований. Переговорщик просто привозит их и передаёт в рамках ролевой игры. Их приобретение или получение отыгрывать не обязательно.",
"11.39 Требования, отсутствующие по моду, должны существовать в реальности и иметь определённую ценность для нелегальных структур. Также нелегальные структуры должны называть правдивое предназначение предмета/животного и т.д. сотрудникам ФБР. Если эти требования бесполезны и нелегальные структуры не могут обосновать их реальную полезность в ООС-чат, то переговорщик вправе отклонить эти требования.",
"11.40 Запрещено включать в условия сделок, выкупа или иных договорённостей передачу любых видов транспорта, аксессуаров, недвижимости (домов/квартир) и прочего внутриигрового имущества (не отмеченных в данной теме).",
"",
"ОСТАЛЬНЫЕ ТРЕБОВАНИЯ",
"11.41 Нелегальным структурам запрещено требовать от переговорщика прибыть в определённых аксессуарах, а также попросить приобрести или привозить определённые аксессуары.",
"11.42 Нелегальным структурам запрещено требовать от государственных структур присылать своих руководящих лиц на переговоры.",
"11.43 Нелегальным структурам запрещено требовать от переговорщиков прибыть в определённой одежде.",
"11.44 Нелегальным структурам запрещено требовать определённый номинал купюр (евро, биткоины и прочее).",
"11.45 Нелегальным структурам запрещено требовать более 1000 граммов \"укропа\" (адреналина и обычных) и более 1000 материалов.",
"11.46 Нелегальным структурам запрещено требовать более 2 одинаковых Т/С на теракте/похищении. Каждый из Т/С считается за отдельное требование, если их 2, то это считается как 2 отдельных требования.",
"11.47 Нелегальным структурам запрещено требовать уникальные, очень редкие класса люкс транспортные средства (уникальные из /donate, различные каргобобы и тому подобное, авто, которое есть у ограниченного количества людей).",
"11.41 - 11.47 В случае двух и более нарушений правил, описанных в пунктах 11.58–11.60, переговорщик ФБР вправе инициировать штурм, не неся ответственности за жизнь заложника.",
"11.48 Допускаются доступные по моду мелкие требования по типу ремкомплектов, канистр и цветов. Они вычитаются из общей суммы выкупа, а также являются материальными и ограничены по количеству.",
"11.49 Допускается требование в виде освобождения кого-либо из-под стражи или мест заключения. В этом случае между нелегальными структурами и ФБР происходит обмен: 1 заложник на 1 освобождённого человека. Работает только на похищениях.",
"11.50 Во время похищения/теракта нелегальным структурам запрещено вмешиваться в РП-ситуацию со второго игрового аккаунта. После выполнения всех требований переговорщик прибывает на заранее указанное место переговоров, и начинается непосредственный диалог с нелегальными структурами и спасение заложников.",
"11.51 При запросе транспорта для отъезда похитителей транспорт должен быть системно для них доступен.",
"11.52 При указании материальных требований в определённом количестве они должны быть системно переданы согласно обговорённому количеству. Если похитители указывают огромное количество (допустим, 5.000 \"укропа\"), переговорщик имеет право отказаться от этого, ссылаясь на требования, невозможные к выполнению. Переговорщик может попросить поменять требование либо предложить адекватное количество, которое системно имеется у Министерства юстиции.",
"11.53 Требования должны быть переданы и выполнены как по РП, так и системно на момент обмена заложников.",
"",
"ПРАВИЛА ПЕРЕГОВОРОВ",
"11.54 Переговорщик вправе потребовать показать заложника, чтобы убедиться в его сохранности. В этом случае нелегальные структуры не могут ему отказать.",
"11.54 Запрещено причинять вред переговорщику и его транспорту, а также сопровождающим его людям, равно как брать их в заложники или связывать.",
"11.55 Запрещено издеваться над переговорщиком, оскорблять его прямым текстом или иным способом унижать его.",
"11.56 Запрещено обыскивать агента ФБР. Нелегальные структуры имеют право потребовать от агента продемонстрировать самому, что требования, связанные с ним, были выполнены. При несоблюдении любого из этих пунктов агент имеет право дать штурм, не неся ответственности за смерть заложника.",
"11.57 Агенты ФБР и нелегальные структуры имеют право использовать любую спецсвязь (Discord и т.п.) для передачи РП-информации вне зависимости от наличия у них РП-способа передачи информации, а также могут давать любую информацию, даже если это могли бы заметить по РП. Говорить информацию, переданную по спецсвязи, другой стороне не нужно. Например, переговорщик может сообщать ход переговоров и давать информацию о нелегальных структурах, а нелегальные структуры — координироваться между собой. Данное правило — игровая условность для предотвращения различных конфликтов.",
"",
"ПЕРЕДАЧА И СОКРЫТИЕ МАТЕРИАЛЬНЫХ ТРЕБОВАНИЙ",
"11.58 Запрещено убивать заложников в случае передачи всех требований. Агентам же запрещено начинать штурм, пока заложник не находится в полной безопасности (кроме исключений, указанных в правилах).",
"11.59 Если представители нелегальных структур, у которых были материальные требования, были убиты или задержаны во время штурма, то они обязаны вернуть все материальные требования.",
"11.60 При убийстве заложников на похищении нелегальные структуры не имеют права забирать кейс.",
"",
"ОТХОД С ПОХИЩЕНИЯ",
"11.61 Разрешено преследовать нелегальные структуры в течение 15 минут после последнего визуального контакта. Под визуальным контактом подразумевается обнаружение представителей нелегальных структур или их транспорта. В случае потери визуального контакта агенты имеют право искать нелегальные структуры в течение 15 минут. В случае если за эти 15 минут визуального контакта не было, то преследование более не ведётся. По истечении 15 минут переговорщик со стороны ФБР должен уведомить нелегальные структуры о том, что преследование не ведётся (ООС-звонок/СМС). Нелегальные структуры также имеют право узнать у переговорщика ФБР, ведётся ли преследование или нет, в случае если такой информации не последовало. В случае игнорирования этой просьбы в течение 3 минут нелегальные структуры считаются потерянными, а преследование не ведётся.",
"11.62 Нелегальным структурам запрещено уходить от преследования неролевым способом. Примером неролевого способа является спрыгивание с гор на машинах и мотоциклах и любое другое превышение физических возможностей человека.",
"11.63 Нелегальным структурам запрещено покидать пределы стандартной карты, скрываться на спавне фракций, в зелёных зонах и иных людных местах, а также заходить в интерьеры или участвовать в войнах за территорию во время преследования (исключение: если нелегальным структурам нужно покинуть пределы стандартной карты из-за маппинга проекта).",
"11.64 Во время преследования нелегальным структурам запрещено уходить в AFK намеренно. Если представители нелегальных структур уходят в AFK или телепортируются из-за плохого интернета, нарушение всё равно засчитывается. В случае поимки нелегальных структур они обязаны отдать полную сумму выкупа переговорщику или любому другому его представителю.",
"11.65 Нелегальным структурам запрещено выходить из игры во время преследования",
"11.66 Нелегальным структурам запрещено пользоваться лётными транспортными средствами более 10 минут после передачи кейса (примечание: в воздухе нельзя просто зависать/летать над одним местом, необходимо реальное движение по карте).",
"11.67 Нелегальным структурам запрещено пользоваться водными транспортными средствами более 10 минут после передачи кейса.",
"",
"ПРАВИЛА ДЛЯ ФБР",
"Агенты ФБР обязаны в полной мере соответствовать адекватности и ролевой игре на похищении точно так же, как и нелегальные структуры.",
"11.68 Агенты ФБР должны вести себя максимально профессионально, показывая наилучший пример остальным игрокам.",
"11.69 Агентам ФБР запрещается не реагировать на похищение или теракт, а также совершать необдуманные действия, которые могут привести к смерти заложника или повреждению важных государственных объектов. Могут не реагировать, если не соблюдается КД в 2 часа, либо же могут реагировать по своему желанию.",
"11.70 Если заложник в опасности, то агенту ФБР запрещено прибегать к штурму (исключение: 2 предупреждения или пункты, разрешающие штурм в любом случае).",
"11.71 Агент ФБР в полной мере обязан выполнить требования нелегальных структур, если они никак не противоречат данным правилам.",
"11.72 Участникам со стороны ФБР можно привязывать жучок к одной из машин и после этого класть его в кейс. Сотруднику из данной машины можно включить /pursuit для отслеживания кейса. При этом действие жучка прекращается, если машина уничтожается или проходит более 15 минут с момента передачи кейса. Также агент ФБР может следить за жучком строго на территории офиса ФБР и только в течение 15 минут.",
"11.73 Агентам ФБР разрешено отслеживать своих агентов по телефону.",
"11.74 Участникам со стороны ФБР строго запрещено использование команд /pursuit, /find, /z, если это не предусмотрено правилами 11.11 и 11.12.",
"11.75 Сотрудники МЮ, которые ведут погоню за нелегальными структурами, обязаны вести видеофиксацию с момента, как переговорщик передал кейс с деньгами нелегальным структурам.",
"oGjsUzi.png",
"МАНИПУЛЯЦИИ С КЕЙСОМ",
"11.76 Кейс обязан собрать переговорщик со стороны ФБР.",
"11.77 В кейсе должна быть сумма, которую запросили преступники.",
"11.78 Сотрудник юстиции может положить жучок в одну из трёх ячеек кейса и доставить его к преступникам, а также обязан иметь доказательства того, в какую ячейку жучок был спрятан.",
"11.79 Преступники имеют право обыскать лишь две ячейки. В случае если жучок не найден или в случае когда жучок был привязан к одной из представленных машин согласно правилу 12.11, сотрудники МЮ имеют право использовать /pursuit на владельца кейса в течение первых 15 минут, исключительно с территории офиса ФБР. По истечении 15 минут жучок разряжается.",
"11.80 Запрещено манипулировать с денежным кейсом после передачи его от переговорщика к нелегальным структурам/мафиям. (Пример: переговорщик от ФБР передал кейс с деньгами нелегальным структурам. Передавать другим нелегальным структурам нельзя.)",
"",
"ДИСЦИПЛИНАРНЫЕ НАКАЗАНИЯ ДЛЯ ЛИДЕРОВ",
"В случае провала государственными структурами теракта/облавы/похищения лидеру выдаётся выговор. Лидер получает выговор за провал операции от старшего ранга (8+).",
"Пункты, по которым оценивается провал от государственных структур:",
"11.81 Убийство заложника.",
"11.82 Подрыв здания.",
"11.83 Потеря контроля за составом во время теракта/облавы/похищения.",
"11.84 Отказ от участия в теракте/облаве/похищении.",
"11.85 В случае провала нелегальных организаций теракта/облавы/похищения лидеру выдаётся выговор.",
"Пункты, по которым оценивается провал от нелегальных организаций:",
"11.85.1 Отказ от контакта с переговорщиками.",
"11.85.2 Систематические нарушения правил терактов/облав/похищений.",
"",
"ВЫКУП :",
"11.86 Выкупы за лидеров организаций при похищении:",
"11.86.1 ФБР - 50.000.000$.",
"11.86.2 Губернатор - 75.000.000$.",
"11.86.3 Судья - 50.000.000$.",
"11.86.4 Директор центра лицензирования и Страховой Компании - 15.000.000$.",
"11.86.5 Полицейские департаменты - 26.500.000$.",
"11.86.6 Армии и Тюрьма - 25.000.000$.",
"11.86.7 СМИ - 15.000.000$.",
"11.86.8 Больница и Пожарная часть - 15.000.000$",
"11.86.9 Выкупы за заместителя равны 50% от стоимости выкупа лидера.",
"11.86.10 Выкупы за сотрудников 5+ рангов равны 25% от стоимости выкупа лидера.",
"11.86.11 Выкупы за сотрудников младше 5 ранга не взымаются.",
"11.87 Выкупы за здания при теракте | ограблении:",
"11.87.1 Мэрия - 45.000.000$.",
"11.87.2 Здания СМИ | Автошколы - 20.000.000$.",
"11.87.3 Здание Банка - не выкупается.",
"11.87.4 Иные места, не указанные в теме - по согласованию с администрацией.",
"11.87.5 Здание FBI не захватывается.",
"11.88 За заложников при теракте выплачивается дополнительно по 20% от суммы указанной за похищение. ",
"11.89 В случае провала операции со стороны МЮ, губернатор и куратор операции делят 30% от этой суммы пополам и компенсируют её государству со своего кармана. Остальные 70% берутся из казны фракций.",
"",
"#12 Правила для руководства организаций и частные организации",
"",
"Минимальные требования для лидера/заместителя:",
"Для лидера гос. организаций [15+ LVL], для замов [10+ LVL]",
"Для лидера нелегальных организаций [10+ LVL], для замов [Без ограничений]",
"Примечание: На новом сервере нет требования к LVL",
"",
"Общее положение.",
"",
"12.1 Лидер фракции - это ответственное лицо за организацию, который в ответе за набор сотрудников, контроль их работы и всех процессов, которые проходят в организации.",
"12.2 Срок лидерства составляет 30 календарных дней.",
"12.3 Лидер фракции должен быть ответственный и адекватный, соблюдающий все нормы.",
"12.4 Лидером фракции можно стать путем собеседования после открытия заявлений на пост лидера, либо же передача от предыдущего лидера своему заместителю, под контролем администрации. На посты лидера ФБР и Правительства нет возможности встать по передаче. В частных организациях лидера назначает владелец.",
"12.4.1 Лидером государственной или нелегальной организации может стать игрок, имеющий гражданство сервера. Игрок с иностранным гражданством (аккаунтом) может занять пост лидера только при наличии официального одобрения/разрешения от Главного администратора сервера, которое выдаётся в исключительных случаях на усмотрение ГА.",
"12.5 Лидер, назначенный на пост по передаче, не может передавать лидерку. Новый лидер назначается только через обзвон.",
"12.6 Губернатор ставится путем дебатов, голосования и т.п. на сервере.",
"12.7 Лидер организации имеет право баллотироваться на пост губернатора.",
"12.8 При условии отличного первого срока, лидер может при своём желании и одобрения от следящих получить второй срок. Один лидер может занимать пост не более трёх сроков подряд. После завершения трёх сроков подряд повторное назначение этого же лидера не допускается. В частных организациях сроки не ограничены.",
"12.9 Губернатору разрешено избираться на второй и третий срок при условиях: его желание, одобрение от следящих, пройдя снова этапы предвыборной гонки (дебаты/голосование/собеседование и т.д.)",
"12.10 Лидер организации который идет на второй и третий срок, имеет право назначить новое доверенное лицо.",
"12.11 Если лидер покидает свой пост раньше срока/снимается, то ему запрещено занимать руководящие должности (10/9 ранги) в течении 30 дней в министерстве, где стоял срок, 15 дней - в другом министерстве. Исключение: частные организации.",
"12.12 Если лидер покидает свой пост не отстояв 15 дней - он получает бан на столько дней сколько он не отстоял. Если лидер ушел после 15 дней - варн. Если заместитель лидера покидает свой пост не отстояв 15 дней - он снимается варном. Исключение: частные организации.",
"12.13 Руководители нелегальных организаций должны иметь ник, соответствующий национальности организаций (Русская Мафия - русский ник и т.д.). Исключение: частные организации.",
"",
"Возможности лидера:",
"",
"12.14 Каждый лидер/заместитель организации может взять неактив максимум на 5 дней 1 раз за срок или 3 дня 2 раза за срок. Исключение: согласование со следящей/главной администрацией и частные организации.",
"12.15 По решению следящей администрации, лидеры государственных структур могут взять с казны от 1% до 30% один раз за срок. В частных организациях лидер и владелец имеют полное право распоряжаться своей казной по своему усмотрению.",
"12.16 Лидер гос организации имеет право, после постановки в течение трех дней взять к себе 3х доверенных лиц на старшие ранги: один 7-й ранг, один 8-й ранг и одно доверенное лицо в виде 9-го ранга.",
"12.17 Лидер нелегальной организации имеет право поставить себе заместителей в количестве 3 человек после проверки их следящей администрацией.",
"12.18 Лидер частной организации имеет право выдавать любые ранги на свое усмотрение в соответствии с игровыми лимитами.",
"12.19 После постановки, лидеры мафий имеют 3 дня мороза. Им нельзя забивать стрелы.",
"12.20 После постановки, лидеры гетто имеют возможность брать заморозку каптов в любой доступный для них период, по текущей системе мода.",
"12.21 Если у лидера/зама отыграна норма, он может играть на других сервера проекта.",
"12.22 Лидер/заместитель организации имеет право уволить без объяснения причины. Причина увольнения должна быть адекватной. В гос. организациях лидер должен иметь возможность объяснить ее следящей администрации и предоставить хотя бы минимальные доказательства.",
"12.23 Лидер/заместитель нелегальных организаций могут принимать игроков с ником без соответствия национальности, но не повышать их выше 7-го ранга. Исключение: частные организации.",
"",
"Лидер/заместитель фракции обязан:",
"",
"12.24 Лидер/заместитель фракции обязан - соблюдать правила проекта/сервера, форума и Discord'а.",
"12.25 Лидер организации обязан после постановлении за 3 дня заполнить свой раздел на форуме, своевременно проверять его и содержать в порядке, в течении всего своего срока. Исключение: частные организации.",
"Примечание: Все локальные правила частной организации (по типу: уставы, регламенты, правила), созданные владельцем или лидером организации, согласовываются с главной администрацией сервера. Они не должны противоречить правилам сервера. При отсутствии необходимых локальных правил, частная фракция придерживается общих правил своей структуры.",
"12.26 Лидер/заместитель организации обязан соблюдать уровень Role Play во фракции.",
"12.27 Лидер/заместитель организации обязан ежедневно активно участвовать в жизни сервера и своей организации.",
"12.28 Лидер/заместитель организации обязан проводить в игре не менее двух активных часов в сутки (но не менее 21 часа в неделю). Исключение: Неактив/Отпуск и частные организации.",
"12.29 Лидер может изменять ранги по согласованию со следящей и главной администрацией.",
"",
"Лидерам/заместителям запрещено",
"",
"12.30 Лидеру/заместителю организации запрещено нарушать правила сервера форума и Discord'а.",
"12.31 Лидеру/заместителю организации запрещено обманывать администрацию сервера.",
"12.32 Лидеру/заместителю организации запрещено оскорблять, провоцировать, скрыто унижать в конференциях.",
"12.33 Лидеру/заместителю организации запрещено использовать запрещённые вредительские и дающие преимущества программы, включая клео скрипты.",
"12.34 Лидеру/заместителю организации запрещено продавать ранги; принимать, повышать, увольнять и оказывать любые иные внутрифракционные услуги (например: выдача похвалы) за деньги. Исключение: система продажи рангов в частных фракциях.",
"12.35 В течении рабочего дня лидеру/заместителю запрещено стоять AFK (AFK без ESC) более 600 секунд (10 минут). Исключение: частные организации.",
"12.36 Категорически запрещен слив казны - приравнивается к махинациям/ЧС сервера. Исключение: частные организации.",
"12.37 Лидеру/заместителю организации запрещено принимать игроков вне интерьера своей фракции, вне территории своего спавна или вне специально отведенной зоны (военкоматы и т.п.).",
"12.38 Лидеру/заместителю организации запрещено выдавать/снимать выговоры, муты, увольнения и т.п. с неадекватными или нонРП причинами.",
"",
"Для нелегальных организаций также запрещено:",
"12.39 Запрещено намеренно сливать территории гетто / бизнесы.",
"12.40 Запрещено выдавать премии составу из общака банды, с намерениями слить общак или получить выгоду для себя.",
"12.41 Запрещено принимать игроков состоящих в ЧС сервера/гетто/мафии, ЧСП. В случае, если это будет выявлено - лидер понесет наказание.",
"",
"Примечание: за эти или иные нарушения правил проекта/сервера со стороны лидера или заместителя организаций, следящая администрация фракции может выдать наказание в виде устных/строгих/неснимаемых предупреждений вместо системных наказаний(мут/ТСР/варн/бан и т.д.). Систему выдачи/снятий этих предупреждений может назначить администрация сервера. Исключение: лидерам/заместителям частных организаций администрация может выдавать наказания в соответствии с правилам сервера и проекта, а за частые нарушения также может потребовать снять лидера или заместителя.",
"",
"За что Вас могут снять с поста лидера/заместителя.",
"",
"12.42 По решению главной администрации.",
"12.43 Неоднократные нарушения правил сервера, форума и Discord'а.",
"12.44 Получение 3/3 предупреждений в гос.фракции, в нелегальных организациях 5/5 строгих предупреждений.",
"12.45 Любое проявление неадекватного поведения/Оскорбления игроков, розжиг национальной розни. (соц.сети игра\\discord).",
"12.46 Отсутствие нормы. Исключение: частные организации.",
"12.47 Фракция потеряла активность (Лидер не активит, не активит 9 ранг без лидера, не проводятся собеседования и т.д.).",
"12.48 По жалобе на форуме.",
"12.49 Неактив в течении 3-х дней (без предупреждения следящих заявления на отпуск). Исключение: частные организации.",
"12.50 Отказ от выполнения поручений, которые выдают следящие администраторы.",
"12.51 За NonRP действия от лидера/заместителя.",
"12.52 Оскорбление, обсуждение администрации сервера, действий администрации сервера! В любом месте, а именно \"Конференция, discord, игра\"",
"12.53 Другие неочевидные причины, которые требуют особого рассмотрения.",
"12.54 Частная организация может быть изъята по решению главной и красной администрации в случае чрезмерных и систематических нарушений правил.",
"Пример: За слив лидерского поста, чрезмерно неадекватное поведение, крупные махинации и тд.тп",
"",
"Получение пенсии для гос. организаций",
"",
"12.55 Для получения пенсии у вас должна быть хорошая игровая активность",
"12.56 Простоять на занимаемой должности не менее 40 дней.",
"12.57 Обеспечение стабильной работы фракции (следящая администрация не должна регулярно делать замечания, вы сами должны контролировать этот процесс).",
"12.58 Участие в РП жизни сервера (взаимодействие со своим составом и другими фракциями, участие в глобальных ситуациях).",
"12.59 У Вас не должны быть серьезных нарушений на занимаемом посту (не снимаемый выговор, действующих 2 из 3 выговор).",
"12.60 В случае перехода на пост администратора, пенсия сохраняется.",
"12.61 При активной пенсии нельзя занимать пост лидера или заместителя.",
"12.62 Если хотите занять пост лидера и заместителя, Вы должны согласовать это с ГС ГОС/ЗГС ГОС. Пенсия снимается без возврата. Получать нужно ее по новой.",
"12.63 Пенсия может быть снята, если за вами было уличено следующее: серьезный бан (блокировка за массовые нарушения, читы и т.п.), внос в реестр ярых нарушителей, неадекватное поведение.",
"",
"#13 Описание разрешенных и запрещенных игровых модификаций",
"",
"В данной теме Вы можете ознакомиться с информацией о разрешенных и запрещенных скриптах, плагинах и других модификациях. Так как их огромное количество и регулярно разрабатываются разными людьми невозможно их по отдельности перечислить, поэтому модификации перечислены по общему их описанию и назначению.",
"К модификациями относятся следующие типы файлов устанавливаемые в игру:",
"cleo скрипты (cs) ;",
"lua [Moonloader] скрипты (lua, .luac) ;",
"js [Cleo Redux] скрипты (js);",
"python [PyLoader] скрипты (py);",
"SAMPFUNCS плагины (sf);",
"ASI плагины (asi, dll);",
"AHK скрипты (ahk, exe)",
"исполняемые программы (exe)",
"текстуры, модели, конфигурации и другие типы файлов, устанавливающиеся в качестве замены в одну из директории игры или загрузчик modloader (txd, dff, ifp, ide, dat, ini, cfg, txt, json и т.д.)",
"Если Вы нашли на просторе интернета интересную для вас модификацию, но не можете определить к какой категории она относится, спросите о ней у Главной Администрации вашего сервера.",
"",
"Внимание! Некоторых категорий может не быть в списке, уточняйте у администрации, если затрудняетесь в легальности модификации.",
"",
"Разрешенные модификации",
"Отображение различного рода дополнительной полезной информации на экране (HP/Armour HUD, ChatID, InputHelper, FPS индикаторы, CTime, Orgmembers, название улиц, колокольчик, дамаг-информер, информация о кол-во сборе чего-либо и т.п.);",
"Изменение игрового базового интерфейса (худ, радар, спидометр, чат) с целью улучшения эстетического вида или удобства функционала;",
"Визуальное изменение времени года, времени, погоды;",
"Визуальные аксессуары на скин персонажа, на авто (без коллизии, т.е. не позволяющие взаимодействовать), в качестве маппинга (для кат-сцен, скриншотов, видео как декорации, разметки на карте, но никак как средство преимущества над другими игроками при наличии у объектов коллизии);",
"Визуальные скины (кроме CJ, роллер и др, имеющие повышенную скорость);",
"Различного рода замены текстур, моделей, аудио-файлов на скины, авто, объекты, игровые звуки соответственно и т.п.:",
"Размещение на карте (меню/радар) подсказки о местоположения чего-либо (клады, укроп и т.п.);",
"Измененные звуки не должны содержать матов и других слов/выражений, которые могут унизить или оскорбить игрока;",
"Размеры моделей не должны сильно изменены в отличии от оригинальных, а текстуры иметь стандартные уровни непрозрачности;",
"Исправления игровых ошибок или недоработок (фиксы, патчи);",
"Модификации, позволяющие работать с камерой (CamHack, CamHunt и т.п);",
"Анти-вредительские модификации, не позволяющие Вас убить с помощью вредоносного воздействий на сервер игроком (Анти-рванка/РПГ/гранаты/мины, Анти-кикер, анти-крашер/лоадер);",
"Модификации для оптимизации производительности игры (FPS unlock/up, удаление 3D-надписей, объектов, не несущие функциональной нагрузки, упрощенные текстуры);",
"Важно! Удаление объектов не должно давать преимущества над другими игроками по их взаимодействую. Например, отсутствие забора в каком-то месте, позволяющее Вам пройти/проехать, но не позволяет пройти другому игроку, будет приравнено к использованию чита \"Коллизии\". (Удаление столбов и заборов запрещено). В то же время, Вы можете очистить ЦР от объектов, что повысит FPS.",
"Модификации, связанные с процессом подключения к серверу (фастконнекты, автореконнекты, внутри игровые samp-клиенты)(Внимание: использование данных скриптов могут блокировать IP);",
"Использование анимаций, которых нет в серверном списке /anims и могут использоваться в RP ситуациях. (быстрая смена для демонстрации перед игроками, баловство - наказуемо);",
"Изменение FOV, растяжение экрана, увеличение угла обзора (рыбий глаз, скрипт asp);",
"Изменение размера иконок на радаре (маленькие, большие и т.д.);",
"Скрипт HeavyFist без скролла.",
"Скрипт fastmap (не ставящий игру на паузу).",
"",
"",
"Примечание: В некоторых разрешенных модификациях могут присутствовать запрещенные функции, к примеру, AntiAFK с GM, CamHack с WH/fly или хелперы, за которые можете получить наказание. Читайте внимательно описание с источников, откуда скачиваете скрипты или плагины.",
"Запрещенные модификации:",
"Различного рода телепорты (tp, coordmaster, click warp и т.п.);",
"Чекеры, уведомления и другая всплывающая информация о наличии на сервере администрации, а также нахождения ее в режиме слежки, чекеры слетов имущества, игроков в масках и т.п.;",
"Модификации, позволяющие летать (FlyCar, метла, AirBreak и т.п.);",
"Модификации, дающие состояние неуязвимости или затрудняющие взаимодействия с игроком (Godmode, анти-пробитие колес, NoBike, невидимка, искусственные лаги и т.п.);",
"Отображение информации на дистанции не предусмотренной настройками сервера (WallHack, рендер объектов, увеличенная дистанция прорисовки 3D-текстов и других сущности игры и т.п.);",
"Модификации, позволяющие навредить серверу (рванки, каршоты, кикеры, лаг-машины и т.п.);",
"Различные виды ботов и других систем, позволяющие автоматизировать действия игрока без самого участия человека (боты для ферм, шахты, грузчика и других работ, RakBot и т.п.);",
"Исключение: авто-реклама вне зависимости за компьютером игрок или нет.",
"Модификации, позволяющие выполнить действия в обход игровой или серверной системы (езда без топлива или с выключенным двигателем, без лицензий, без оплаты, суицид, бесконечный бег, выдача JetPack'а, оружия, нитро, скиллы и т.п.);",
"Модификации, позволяющие редактировать какую-либо информацию или характеристики, которые отображаются или предоставляются сервером (диалоговые окна, игровой чат, 3D-текст, TextDraw, характеристики транспорта и персонажа, настройки сервера) с целью предоставление ложной (фейковой) информации или повышение преимущества над другими игроками;",
"Модификации, изменяющие поведение стрельбы (Aim, autoshot, авто-сколл, бесконечные патроны, Extra WS, анти-разброс, зум и т.п.);",
"Мультичиты, сборки читов, включающие выше перечисленный функционал;",
"Обходы системы лаунчера (эмуляция игры с лаунчера);",
"Модификации, позволяющий воздействовать на какое-либо окружение сервера (машины, игроки, объекты) и на его функционал, недоступному по возможности обычному игроку/человеку (спавн машин, SpeedHack, кликеры и т.п.);",
"Модификации, как-либо изменяющие физику управления транспортом или его параметры (хендлинг).",
"Модификации, в составе которых имеются запрещённые функции (скрипты, дающие преимущество перед другими игроками)",
"Список запрещенных скриптов",
" Wallhack",
" AntiAfk с GM (Без - можно)",
" Aim",
" GodMode и все их виды.",
" Auto-shot",
" Weapon zoom",
" Airbrake",
" Admin checker",
" Cleo warning",
" Быстрая смена оружия",
" Телепорты всех видов",
" Invisible [Невидимка]",
" Все виды ботов [ RAK DROID / RAK BOT и другие]",
" Все виды \"cleo fake\" [Фейковые сообщения]",
" No spread/no recoil",
" SPEED HACK",
" BikeOFF",
" AUTO-REPAIRE",
" DGUN",
" Бесконечные патроны",
" Car Spawner",
" Car Shot",
" Бесконечный бег",
" Suicide",
" Animation (которых нет на сервере)",
" Cleo-паркур",
" Cleo-лёд",
" Extra WS",
" Вид стрельбы как в GTA V (с водительского места)",
" MOP",
" Cleo-skills",
" Cordmaster",
" Cordfly",
" Carshot",
" Rapid",
" House checker",
" Auto repair",
" Nolicenses",
" Auto +c",
" Twist mod",
" Flooder",
" Rvanka",
" Car color pulsator",
" Parser nicks",
" Коллизия",
" Cleo piss",
" SkyWalk",
" Seat for Arizona RP",
" Cleo DriveBy (стрельба с водительского места)",
" Tuning Script",
" Handling Editor",
" MTProject",
" Fast Anim",
" SkyWalk",
" WaterCars",
" Anti CarSkill",
" Nitro",
" AntiHunger",
" WallRun",
" Car Recovery",
" Anti DriveBy",
" Tornado",
" Tramplin",
" BikeHelper",
" Cleo перезарядка",
" Controler (Улучшенный контроль автомобиля)",
" Cleo столбы",
" Anti BunnyHop",
" TWalls",
" Cleo сбив Наказание: Бан на 1 день  Бан на 3 дня при повторном нарушении в течение 5 дней.",
" Rampaga Hack",
" Venom",
" Gonwik",
" Jump car",
" Bpl",
" Обход лаунчера",
" Авто открытие сундуков с рулетками.",
" BulletTracer/ИзменениеТрассеров (Касается опровержений на стрельбу)",
" Sliv Sklada",
" Использование любых плагинов, модификаций или скриптов, направленных на накручивание, нечестное получение или дублирование патронов для любого вида оружия.",
" SprintHook",
" FogDist со значением меньше системного [35] (остальные значения разрешены)",
"Примечание: На мероприятии «Операция Мираж» изменение FogDist системой (буря) не является нарушением. Намеренное использование багов или скриптов для изменения FogDist в обход системных ограничений запрещено.",
" Отключение системных эффектов (например: эффект огня на экране)",
" Любые скрипты выводящие количество людей/транспорта в радиусе на экран.",
" Авторедактирование объявлений для сотрудников СМИ — любые скрипты, расширения или макросы, автоматически редактирующие объявления без прямого участия игрока (кроме скриптов-хелперов, не заменяющих действие игрока).",
" Кликеры (автокликеры, макросы на клик) Наказание: Бан на 1 день  Бан на 3 дня при повторном нарушении в течение 15 дней.",
"ЕСЛИ КАКИХ-ТО CLEO/СКРИПТ ЗДЕСЬ НЕ ХВАТАЕТ, ЭТО НЕ ЗНАЧИТ ТО, ЧТО ИХ МОЖНО ИСПОЛЬЗОВАТЬ!",
"ПОМНИТЕ! ЛЮБЫЕ СКРИПТЫ КОТОРЫЕ ХОТЬ НЕМНОГО ДАЮТ ПРЕИМУЩЕСТВО ПЕРЕД ДРУГИМИ ИГРОКАМИ, ПРИВОДЯТ ВАС К ПОЛУЧЕНИЮ НАКАЗАНИЯ.",
"",
"#14 Правила взаимодействия администрации с игроками",
"",
"14.1 Администрация не несет ответственности за утерянное имущество аккаунта в случае скачивания вами запрещенного софта, а также модов, тематических программ, взлома и так далее.",
"14.2 Администрация не имеет права запрашивать такую информацию, как пароль от аккаунта.",
"14.3 Администрация вне зависимости от уровня должна отвечать на репорт при наличии очереди.",
"14.4 Администратору нельзя нарушать любые правила проекта, включая правила чатов (имеются исключения).",
"14.5 Администратор обязан соблюдать требования от главной администрации, которые могут дополнять данные правила.",
"14.6 Администратор может быть назначен путем обзвона (собеседования) или через полный срок на посту лидера (не менее 25 дней при идеальной работе или не менее 15 дней при полном взятии гетто/бизнесов).",
"14.7 Администратор может быть восстановлен на пост в течении 150 дней после ухода, но не раньше, чем через 7. В течении 90 дней восстановление возможно с -1 админ-уровнем, затем только на 1 админ-уровень. После истечение срока требуется заново отстоять пост лидера или пройти специальный обзвон (собеседование).",
"14.8 Главная администрация самостоятельно определяет состав админов: имеет право снять администратора, отказать в назначении/восстановлении без объяснения причины или выставить дополнительные требования.",
"14.9 Администратор может быть заблокирован или занесен в ЧС администрации при снятии с поста в случае ухода сразу же или при серьезных нарушениях правил проекта. Возможные причины для блокировки обычно озвучиваются при постановлении.",
"14.10 Администратор обязан уважительно относиться к игрокам в игре и за ее пределами.",
"14.11 Администратор является нонРП персонажем в игровом мире, не может препятствовать или мешать RP-процессу.",
"14.12 Администратор не может использовать свой функционал в личных целях (не для выполнения задач / обязанностей от главной администрации).",
"14.13 Администрация не может принимать участие в слетах имущества.",
"14.14 Администрации нельзя иметь любое имущество за пределами админ-зоны, кроме транспорта",
"Исключение: старшая администрация сервера для последующих конкурсов, аукционов, слетов.",
"14.15 Администратор может экономически взаимодействовать с обычными игроками в рамках правил экономических взаимодействий администрации с игроками. (https://forum.arizona-rp.com/threads/10688694/)",
"14.16 Администрация может получать подарки со стороны игроков в одностороннем виде - не оказывая никаких услуг в ответ, но только если главный администратор это разрешает.",
"14.17 Администрации разрешено использовать только стандартное описание персонажа, включая АФК-описание",
"Пример: администратор 1 уровня.",
"14.18 Администрации запрещено играть с твинков на своем сервере",
"Примечание: Разрешено играть на других серверах с одобрения ГА без нарушения общепринятых правил и занимания важных должностей.",
"14.19 Администрации запрещено ставить провокационные реакции на сообщения других игроков на форуме",
"Пример: реакция смеха на жалобу игрока.",
"14.20 Администратору запрещено превышать норму АФК, установленную главной администрацией. Также запрещено систематическое нахождение в АФК, уход в АФК при большой очереди в репорт.",
"14.21 Администрации разрешено проходить праздничные квесты в рабочих целях при отсутствии репорта",
"14.22 Администрации запрещено выпрашивать любые поощрения у игроков",
"Пример: выпрашивание админ ЗП в вип чате.",
"14.23 Администратор вправе отказать игроку в предоставлении каких-либо услуг/одолжений, нарушающих RP режим игры (выдача ХП, машин, денег и т.п.).",
"14.24 Администратор оставляет за собой право выбирать наказание, ориентируясь на тяжесть содеянного (в пределах нормы).",
"14.25 Администратор имеет право наказать игрока в течение 3-х дней, после совершенного игроком нарушения [В случае подачи жалобы].",
"14.26 Игрок, который зафиксировал нарушение со стороны администрации или желающий обжаловать любое наказание, имеет право подать жалобу на форум в раздел «Жалобы на администрацию» с соблюдением соответствующих правил подачи.",
"14.27 Администрация обязана хранить доказательства на нарушения игрока в течении возможного срока подачи жалобы.",
"",
"#15 Правила поведения на центральном рынке(А так же регулирование взаимодействий с лавками)",
"Запрещено:",
"15.1 Нецензурные слова в название лавки - Спавн лавки",
"15.2 Запрещена установка личных лавок на улице у ЦР/Аэропорт/улица аэропорта/Спавны работ/любое место где вы можете помешать другим игрокам - Спавн лавки",
"15.3 Расположение лавок возле центрального рынка в указанной зоны. - Спавн лавки.",
"Спойлер: Территория расположения лавок возле цр",
"Рекомендации, которые могли бы вам помочь, дабы не быть обманутым",
"1. Все сделки и покупки проходят строго через команды сервера и ограничены определенными тарифами(т.е все, что в обход командам или ценовому ограничителю - является разводом/обходом)",
"2. Тщательно проверяйте владельца того или иного имущества( Например машина буллет находится у Rio_Nakamura,а вам пытается продать под его видом RIo_Nakamura)",
"3. Всегда фрапсите любые сделки,чтобы в случае какого либо обмана можно было написать жалобу.",
"4. Перед покупкой например на Автобазаре или Центральном рынке тщательно проверяйте, что и за какую сумму вы покупаете(т.к многие игроки покупают на доверие и не читают,что им продают. Этим и пользуются мошенники.",
"5. Если вас просят продать дом через банк - это опять же развод",
"6. При обмене авто(мото и т.д) проверяйте, какое т/с вам предлагают взамен вашего, дабы не попасть на мошенника.",
"7. Так же при обмене с доплатой, доплату получает тот игрок, который кинул запрос первый, если вам утверждают обратное - это развод.",
"8. Продажа имущества через сим-ку или аксессуар так же является нонрп разводом, при поступлении такого предложения в вашу сторону сообщите администрации /report",
"9. Запрещено использовать ViceCity для ухода от наказаний на основном сервере",
"(Пример: Вам должны выдать блокировку, вы направляетесь на ViceCity и переносите имущество на другой аккаунт на любом сервере) - Блокировка 30-2000 дней зависимости от ситуации + ЧС.",
"10. Не давайте деньги игрокам для того чтобы он приобрел вам какую то вещь на своем сервере.( Подобные покупки делайте на ViceCity у игроков используя системы сервера )",
"",
"Правила взаимодействия между аккаунтами и переноса имущества между серверами",
"Общее взаимодействие",
"Взаимодействие между аккаунтами допустимо только при переходе с одного сервера на другой.",
"Передача средств, включая займы, считается полноценной передачей имущества.",
"Перенос имущества возможен только однократно с одного сервера на другой(Например с 01 на 02). Повторные переводы с сервера, с которого был совершен перенос(с 01 на 02), запрещены. (Исключение по решению Главного администратора двух серверов)",
"Для переноса имущества вы можете использовать два устройства (например, два компьютера).",
"Вход на сервер с одного аккаунта и последующая передача имущества другому аккаунту через встречу в игре.",
"Использование друзей или знакомых, при условии, что их аккаунты не имеют нарушений и не участвуют в махинациях.",
"Соблюдайте правила, чтобы избежать санкций и неприятных ситуаций.",
"",
"Для администрации:",
"Не флипаем игроков которые не застряли в текстурах, либо их читер повредил на ваших глазах.",
"Не заправляем по просьбе игроков что у них мало топлива.(Исключение лодки при перевозе нефти, бывает баг с топливом)",
"Не выдаем мопеды либо другие транспорты,Еду,ХП по просьбе",
"",
"Для всего данного есть ремкомплекты, АЗС, канистры, домкраты, такси и автобусы.",
"",
"Доставать с воды игроков с транспортом можно.",
"",
"#16 ПРАВИЛА СОВЕРШЕНИЯ IC и OOC СДЕЛОК",
"",
"16.1 Рекомендация: Каждому игроку, совершающему IC или OOC сделку рекомендовано записывать видео-опровержение, в целях возникновения и дальнейшего решения подозрительных ситуаций.",
"16.2 Во время проведения сделки все условия должны обсуждаться в IC или OOC чатах.",
"16.3 При начале видеозаписи каждый участник сделки должен пробить /time.",
"16.4 В случае нарушения одной из сторон условий сделки игрок имеет право написать жалобу в раздел Non-RP разводов и при положительном решении игрок, нарушивший условия, может быть заблокирован.",
"16.5 Каждая сделка должна проводиться, не нарушая общие правила сервера и правила по обороту денежных средств на сервере.",
"16.6 В договоре должны обязательно быть прописаны условия сделки.",
"16.7 Каждая сделка должна проводиться согласно Регламенту совершения IC и ООС сделок.",
"16.8 При совершении сделки с указыванием временных промежутков, нужно указать точные временные рамки.",
"16.9 Non-RP разводом является обман игрока, связанный с нарушением условий договора IC и OOC сделок.",
"16.10 Запрещено использовать механику продажи, покупки товаров для намеренного обмана игроков через визуально схожую или заведомо заниженную/завышенную цену, если очевидно, что действия направлены не на честную сделку, а на введение другой стороны в заблуждение.",
"",
"ЗА ЧТО МОЖНО ПОЛУЧИТЬ НАКАЗАНИЕ:",
"Нарушение условий сделки (намеренный обман, развод игрока, обман зрения)",
"Бан 30-2000 дней / Откат сделки [ На усмотрение Главной Администрации ] ",
"Нарушение условий сделки (попытка развода игрока)",
"Бан 30 дней",
"Отсутствие согласия с условиями всех участников сделки",
"Отказ в рассмотрении жалобы",
"Нарушение Регламента совершения IC и ООС сделок",
"Отказ в рассмотрении жалобы",
"",
"ПРАВИЛА ЗАПИСИ ВИДЕО ПРИ ПРОВЕДЕНИИ IC и OOC СДЕЛОК",
"МИНИМАЛЬНЫЕ ТРЕБОВАНИЯ ЗАПИСИ:",
"FPS: 30",
"size: 1280х720",
"Качество: 720p",
"Качество может быть ниже, но должно быть смотрибельно для администрации",
"",
"РЕГЛАМЕНТ СОВЕРШЕНИЯ IC и OOC СДЕЛОК",
"16.11 Сделку нужно начинать с вопроса, готов ли игрок провести сделку. В случае, если в сделке участвуют несколько игроков - положительный ответ должны дать все участники сделки.",
"16.12 После получения положительного ответа от всех участников сделки озвучиваются условия сделки. В них отражается вся суть сделки, что получает каждый участник сделки в результате ее выполнения. ]",
"16.13 После названных условий каждый участник сделки должен согласиться с данными условиями. В случае, если с условиями сделки не согласен участник сделки - допускается замена условий или полная отмена сделки. При отрицательном ответе одного из участников сделки сделка продолжаться не может.",
"16.14 При согласии всех участников сделки с условиями, участники обязаны выполнить данные условия.",
"16.15 После выполнения всех условий сделки - сделка считается проведенной.",
"",
"~ ПРИМЕР СОВЕРШЕНИЯ СДЕЛОК НА БИЗНЕС ~",
"",
"",
"Организатор сделки: /b Привет, готов провести сделку?",
"Участник сделки: /b Готов!",
"Организатор сделки: /b Смотри, я тебе даю N миллионов вирт, а ты мне продаешь магазин ИД N по гос.стоимости",
"Участник сделки: /b Согласен!",
"Примечание: где N - указываете свое значение",
"",
"~ ПРИМЕР СОВЕРШЕНИЯ СДЕЛОК НА ПЕРЕДАЧУ ВИРТ В ДОЛГ ПОД ЗАЛОГ ИМУЩЕСТВА ~",
"",
"Текстовая версия совершения сделки на передачу вирт в долг под залог имущества",
"Организатор сделки: /b Привет, готов провести сделку?",
"Участник сделки: /b Готов!",
"Организатор сделки: /b Смотри, я тебе даю N миллиард вирт в долг до \"дата, месяц, год[/FONT]",
"Организатор сделки: /b под залог твоей АЗС N ИД",
"Участник сделки: /b Согласен!",
"Примечание: где N - указываете свое значение.",
"",
"~ ПРИМЕР СОВЕРШЕНИЯ СДЕЛОК НА СКИН ~",
"",
"Текстовая версия совершения сделки на скин",
"Организатор сделки: /b Привет, готов провести сделку?",
"Участник сделки: /b Готов!",
"Организатор сделки: /b Смотри, я тебе даю через /trade скин N, ты мне переводишь на банк N миллионов",
"Участник сделки: /b Согласен!",
"",
"#17 Правила частных организаций.",
"",
"17.1 Частные организации подчиняются правилам сервера и проекта.",
"17.2 Частные организации не должны создавать помеху работе других организаций.",
"17.3 Минимальный игровой уровень для лидера/заместителя: 10-й уровень.",
"17.4 Лидер имеет полное право распоряжаться своей казной как ему только угодно.",
"17.5 Лидер может взять к себе на пост заместителей своих доверенных лиц на протяжении всего срока неограниченное количество раз.",
"17.6 Лидер/заместитель частной организации могут быть наказаны мутом/ТСР/варном/баном за те или иные нарушения правил проекта.",
"Примечание: У лидеров/заместителей частных организаций отсутствуют выговоры/устные предупреждения за нарушения на руководящих должностях.",
"17.7 Заполнение форума не является обязательной процедурой. Если лидеру необходимо заполнение форума, то в начале срока владельцу семьи/лидеру частной фракции необходимо красиво и понятно оформить раздел своей организации.",
"17.8 Все локальные правила частной организации (по типу: уставы, регламенты, правила) согласовываются с главной администрацией. Такие правила создаются владельцем или лидером частной организации. Они не должны противоречить правилам сервера. Могут быть исключения.",
"17.9 При отсутствии необходимых локальных правил, частная фракция придерживается общих правил сервера и проекта.",
"17.10 Функционирование частной организации в официальном дискорд-канале сервера не является обязательным.",
"17.11 Перевод из частных организаций в обычные организации запрещён.",
"17.12 Действия в отношении состава должны осуществляться в адекватных рамках. Лидер организации может уволить игрока без причины, но имея на это хотя бы минимальные доказательства, в случае жалобы предоставив доказательства администрации.",
"17.13 Владелец, лидер и заместители фракции могут стоять АФК без ЕСК в любое время.",
"17.14 Одной семье в рамках одной нелегальной сферы запрещено владеть более одной частной фракцией.",
"Запрещённый пример: Банда + Банда, Мафия + Мафия,",
"Разрешённый пример: Банда + Мафия, Гос + Мафия, Банда + Гос.",
"17.15 Владельцам и лидерам частных организаций необходимо поддерживать базовый функционал (Оформление страховок, лечение игроков и пр.) и работоспособность своей организации.",
"Примечание: Владельцам/лидерам частных нелегальных организаций необходимо поддерживать активность своей фракции (Принимать участие на мероприятиях AirDrop, Битва за завод, Стрелы за бизнесы, Битва за нефтевышки и т.п)",
"Наказание: На первый раз - устное предупреждение. При систематических/многократных проблемах с частной организацией - изъятие частной организации Руководством сервера при соглашении с Красной Администрацией.",
"17.16 В частных организациях запрещено продавать ранги в обход системы продажи рангов. Наказание: Устное предупреждение  Бан на 30 дней при повторном нарушении в течение 30 дней.",
"Пример: Продажа 9 ранга (Системно продавать нельзя), продажа определённого ранга навсегда (Продажа вечного ранга)",
"17.17 При многократных нарушениях со стороны владельца/лидера частной организации - организация может быть изъята Руководством сервера при соглашении с Красной Администрацией.",
}},
{name="Правила серверных мероприятий",content={
"#18. Правила семейных захватов территорий",
"Видео-опровержения с мероприятия:",
"18.1 Каждый участник семейного захвата территорий в обязательном порядке должен записывать весь капт и хранить запись пять суток | При отсутствии опровержения по просьбе администрации. Наказание: Блокировка игрового аккаунта на 15 дней",
"18.2 Администрации может в любой момент запросить у вас опровержение с капта и вы обязаны его предоставить в течении суток",
"18.3 При получении наказания на капте вы можете написать жалобу, где вы в обязательном порядке должны предоставить опровержение",
"18.4 Начальные условия при записи опровержения (Пробив)",
"На опровержении должно быть зафиксировано /time, /id или /stats.",
"18.5 Запрещено редактировать/рендерить видео/убирать/накладывать звук. Исключение: обрезать момент, если следящий запросил опру момента",
"18.6 Запрещено записывать видео которое не соответствует требованиям (Несмотрибельные опровержения)",
"18.7 На видео с опровержением рекомендуем присутствие звуков игры",
"18.8 Рекомендуем соблюдать баланс звука для приятного восприятия",
"18.9 Запрещено удалять/вырезать эффект крови. Наказание: устное предупреждение  Бан на участие в мероприятиях (бан МП) на 6 дней в течение 7 дней",
"18.10 Запрещено убирать видимость объектов (текстуры, столбы, видимость мусора, деревья, кусты и т.д), в условиях, дающих преимущество над другими игроками",
"",
"Минимальные требования к опровержению",
"FPS: 30",
"Разрешение экрана: 1280x720 (720p)",
"Качество может быть ниже, но должно быть смотрибельно для администрации",
"",
"Правила:",
"18.11 Неприезд (-1 территория)",
"Примечание: Если семья заранее понимает, что она не сможет осуществить приезд на капт по своей инициативе - необходимо до 14:00 серверного времени сообщить об этом следящей администрации, с просьбой отменить ваши встречи.",
"18.12 Запрещено систематически забивать капт, с дальнейшим неприездом (-1 территория. При отсутствии территорий у семьи - системный запрет семьи на войны)",
"18.13 Запрещено намеренно убивать участников своей семьи. Наказание: ТСР 30 level (30 заданий каждого типа и 90 минут)  ТСР 60 level (60 заданий каждого типа и 180 минут) при повторном нарушении в течение 7 дней",
"18.14 Запрещено выгонять человека из семьи дабы его не убили. Наказание: ТСР 30 level (30 заданий каждого типа и 90 минут)  ТСР 60 level (60 заданий каждого типа и 180 минут) при повторном нарушении в течение 7 дней",
"18.15 Запрещено сбивать таймер времени проведения битвы методом заезда в квадрат и выезда (Продлив). Наказание: ТСР 30 level (30 заданий каждого типа и 90 минут)  ТСР 60 level (60 заданий каждого типа и 180 минут) при повторном нарушении в течение 7 дней",
"18.16 Запрещено использовать игрушечный транспорт на р/у (Танк, Вертолёт, Самолёт, Машинка). Наказание: ТСР 30 level (30 заданий каждого типа и 90 минут)  ТСР 60 level (60 заданий каждого типа и 180 минут) при повторном нарушении в течение 7 дней",
"18.17 Бан на капте (-4 территории)",
"18.18 Три и более ТСР/варнов от семьи за капт (-1 территория)",
"18.19 Запрещено убивать игроков до начала проведения мероприятия",
"18.20 Каждые три месяца будет производиться расформ семейных территорий. (т.е. расформ будет в начале месяца, 1 числа)",
"18.20.1 Сезоны длятся по три месяца:",
"зимний [декабрь, январь, февраль]",
"весенний [март, апрель, май]",
"летний [июнь, июль, август]",
"осенний [сентябрь, октябрь, ноябрь]",
"18.21 При получении системного запрета семьи на войны все ее территории аннулируются",
"18.22 Система чёрного списка (ЧС) семей по нарушениям на каптах:",
"18.22.1 Первый уровень ЧС: при достижении семьей 60 нарушений за последние 20 дней — изъятие 30% квадратов + обнуление предприятий (без системной выдачи ЧС).",
"18.22.2 Второй уровень ЧС: при повторном достижении 60 нарушений за последние 20 дней после первого уровня — ЧС семьи на 30 дней + обнуление территорий.",
"18.22.3 Общие положения:",
"",
"60 нарушений отсчитываются за последние 20 дней.",
"Все уровни ЧС имеют накопительный эффект в рамках одного сезона. Новый сезон обнуляет все уровни ЧС всех семей.",
"При получении первого уровня чёрного списка все нарушения, совершённые в течение 20 дней, аннулируются с момента обнуления территорий.",
"Нельзя получить второй уровень ЧС сразу. Сначала применяется первый, обнуляется счётчик нарушений с момента обнуления территорий и начинается первый день подсчёта новых нарушений.",
"18.23 Нарушение, повлиявшее на исход капта — изъятие 1 территории.",
"Примечание: К таким нарушениям относятся случаи, когда действия игрока напрямую повлияли на результат капта (например, антикапт на решающем фраге, уход от смерти при равенстве счёта, сбив таймера в критический момент). Решение о признании нарушения повлиявшим на исход принимается следящей администрацией.",
"",
"#19. Правила мероприятия \"Захват корабля\"",
"19.1 Разрешено ПГ",
"19.2 Запрещено посторонним лицам создавать помеху. Наказание: ТСР 30 level (30 заданий каждого типа и 90 минут)  ТСР 60 level (60 заданий каждого типа и 180 минут) при повторном нарушении в течение 7 дней",
"19.3 Запрещено использовать игрушечный транспорт на р/у (Танк, Вертолёт, Самолёт, Машинка). Наказание: ТСР 30 level (30 заданий каждого типа и 90 минут)  ТСР 60 level (60 заданий каждого типа и 180 минут) при повторном нарушении в течение 7 дней",
"",
"Дополнительная информация:",
"19.4 Игрок имеет право по своему усмотрению и желанию осуществлять запись своего игрового процесса во время участия в серверных мероприятиях.",
"19.5 Игрок, который демонстрирует высокие показатели убийств, частые победы, или вызывает подозрения в использовании читов, может быть обязан записывать свой игровой процесс во время участия в серверных мероприятиях по решению старшей администрации.",
"",
"#20. Правила мероприятия \"Аирдроп\"",
"20.1 Разрешено ПГ",
"20.2 Запрещено посторонним лицам создавать помеху на аирдропе. Наказание: ТСР 30 level (30 заданий каждого типа и 90 минут)  ТСР 60 level (60 заданий каждого типа и 180 минут) при повторном нарушении в течение 7 дней",
"20.3 Запрещено использовать игрушечный транспорт на р/у (Танк, Вертолёт, Самолёт, Машинка). Наказание: ТСР 30 level (30 заданий каждого типа и 90 минут)  ТСР 60 level (60 заданий каждого типа и 180 минут) при повторном нарушении в течение 7 дней",
"",
"Дополнительная информация:",
"20.4 Игрок имеет право по своему усмотрению и желанию осуществлять запись своего игрового процесса во время участия в серверных мероприятиях.",
"20.5 Игрок, который демонстрирует высокие показатели убийств, частые победы, или вызывает подозрения в использовании читов, может быть обязан записывать свой игровой процесс во время участия в серверных мероприятиях по решению старшей администрации.",
"",
"#21. Правила мероприятия \"Битва за нефтевышки\"",
"",
"Общее положение:",
"21.1 Разрешено ПГ",
"21.2 Запрещено намеренно убивать участников своей фракции Наказание: ТСР 30 level (30 заданий каждого типа и 90 минут)  ТСР 60 level (60 заданий каждого типа и 180 минут) при повторном нарушении в течение 7 дней",
"21.3 Запрещён антикапт — нанесение урона/убийство игроков вражеской мафии до начала и во время мероприятия, с целью помехи и увеличения своих шансов на победу. Наказание: ТСР 30 level (30 заданий каждого типа и 90 минут)  ТСР 60 level (60 заданий каждого типа и 180 минут) при повторном нарушении в течение 7 дней.",
"Примечание: При системной войне банд, также запрещён антикапт.",
"21.4 Запрещено убивать игроков до начала проведения мероприятия Наказание: ТСР 30 level (30 заданий каждого типа и 90 минут)  ТСР 60 level (60 заданий каждого типа и 180 минут) при повторном нарушении в течение 7 дней",
"21.5 Запрещено сбивать таймер времени проведения битвы методом заезда в квадрат и выезда (Продлив) Наказание: ТСР 30 level (30 заданий каждого типа и 90 минут)  ТСР 60 level (60 заданий каждого типа и 180 минут) при повторном нарушении в течение 7 дней",
"21.6 10+ нарушений от мафии - изъятие нефтевышек в случае победы. Нефтевышки передаются другой мафии, которая заняла второе место по системным киллам.",
"21.7 Запрещено инвайтиться в противоположную мафию для намеренного слива очков Наказание: Бан на 7 дней  на 15 дней при повторном нарушении в течение 7 дней.",
"Примечание: Намеренный слив смертей персонажа с целью передачи очков (фрагов) противоположной стороне на системных мероприятиях (Нефтевышки, Притоны) запрещён. Наказание выдается всем участникам сделки.",
"21.8 Запрещено использовать игрушечный транспорт на р/у (Танк, Вертолёт, Самолёт, Машинка) Наказание: ТСР 30 level (30 заданий каждого типа и 90 минут)  ТСР 60 level (60 заданий каждого типа и 180 минут) при повторном нарушении в течение 7 дней",
"21.9 Запрещается покидать зону «Битвы за нефтевышки» после получения значительного преимущества по убийствам и намеренно оставаться вне её границ до конца мероприятия с целью снижения шансов оппонентов на победу [Изъятие нефтевышек в случае победы]",
"Примечание: По решению Главной Администрации может быть выдана блокировка участия в мероприятии.",
"21.10 Запрещено вести стрельбу с пассажирского места транспорта с любого оружия. Наказание: ТСР 30 level (30 заданий каждого типа и 90 минут)  ТСР 60 level (60 заданий каждого типа и 180 минут) при повторном нарушении в течение 7 дней",
"",
"Видео-опровержения с мероприятия:",
"",
"21.11 Каждый участник мероприятия в обязательном порядке должен записывать всё мероприятие и хранить запись пять суток | При отсутствии опровержения по просьбе администрации. Наказание: Блокировка игрового аккаунта на 15 дней",
"21.12 Администрации может в любой момент запросить у вас опровержение с мероприятия и вы обязаны его предоставить в течении суток",
"21.13 При получении наказания на мероприятии вы можете написать жалобу, где вы в обязательном порядке должны предоставить опровержение",
"21.14 Начальные условия при записи опровержения (Пробив)",
"На опровержении должно быть зафиксировано /time, /id или /stats.",
"21.15 Запрещено редактировать/рендерить видео/убирать/накладывать звук. Исключение: обрезать момент, если следящий запросил опру момента",
"21.16 Запрещено записывать видео которое не соответствует требованиям (Несмотрибельные опровержения)",
"21.17 На видео с опровержением рекомендуем присутствие звуков игры",
"21.18 Рекомендуем соблюдать баланс звука для приятного восприятия",
"21.19 Запрещено удалять/вырезать эффект крови. Наказание: устное предупреждение  Бан на участие в мероприятиях (бан МП) на 6 дней при повторном нарушении в течение 7 дней.",
"21.20 Запрещено убирать видимость объектов (текстуры, столбы, видимость мусора, деревья, кусты и т.д), в условиях, дающих преимущество над другими игроками",
"",
"",
"Минимальные требования к опровержению",
"FPS: 30",
"Разрешение экрана: 1280x720 (720p)",
"Качество может быть ниже, но должно быть смотрибельно для администрации",
"",
"#22. Правила мероприятия \"Ферма укропа\"",
"Общее положение:",
"22.1 Разрешено ПГ",
"22.2 Запрещено намеренно убивать участников своей фракции. Наказание: ТСР 30 level (30 заданий каждого типа и 90 минут)  ТСР 60 level (60 заданий каждого типа и 180 минут) при повторном нарушении в течение 14 дней",
"22.4 Запрещен побег на респу во время перестрелки. Наказание: ТСР 30 level (30 заданий каждого типа и 90 минут)  ТСР 60 level (60 заданий каждого типа и 180 минут) при повторном нарушении в течение 14 дней",
"22.5 Запрещён антикапт — нанесение урона/убийство игроков вражеской банды до начала и во время мероприятия, с целью помехи и увеличения своих шансов на победу. Наказание: ТСР 30 level (30 заданий каждого типа и 90 минут)  ТСР 60 level (60 заданий каждого типа и 180 минут) при повторном нарушении в течение 7 дней.",
"Примечание: При системной войне банд, также запрещён антикапт.",
"22.6 Запрещено сбивать таймер времени проведения битвы методом заезда в квадрат и выезда (Продлив). Наказание: ТСР 30 level (30 заданий каждого типа и 90 минут)  ТСР 60 level (60 заданий каждого типа и 180 минут) при повторном нарушении в течение 14 дней",
"22.7 10+ нарушений от мафии/банды - изъятие фермы укропа/нефтевышек в случае победы. Нефтевышки/ферма укропа передаются другой банде/мафии которая заняла второе место по системным киллам.)",
"22.8 Запрещено убийство на спавне банд (СК). Наказание: ТСР 30 level (30 заданий каждого типа и 90 минут)  ТСР 60 level (60 заданий каждого типа и 180 минут) при повторном нарушении в течение 14 дней",
"22.9 Запрещено инвайтиться в противоположную банду для намеренного слива очков. Наказание: Бан на 4 дня  на 7 дней при повторном нарушении в течение 30 дней",
"Примечание: Намеренный слив смертей персонажа с целью передачи очков (фрагов) противоположной стороне на системных мероприятиях (Нефтевышки, Притоны) запрещён. Наказание выдается всем участникам сделки.",
"22.10 Запрещено использовать игрушечный транспорт на р/у (Танк, Вертолёт, Самолёт, Машинка). Наказание: ТСР 30 level (30 заданий каждого типа и 90 минут)  ТСР 60 level (60 заданий каждого типа и 180 минут) при повторном нарушении в течение 7 дней",
"22.11 Запрещается покидать зону «Фермы Укропа» после получения значительного преимущества по убийствам и намеренно оставаться вне её границ до конца мероприятия с целью снижения шансов оппонентов на победу [Изъятие фермы укропа в случае победы]",
"Примечание: По решению Главной Администрации может быть выдана блокировка участия в мероприятии.",
"22.12 Запрещено вести стрельбу с пассажирского места транспорта с любого оружия. Наказание: ТСР 30 level (30 заданий каждого типа и 90 минут)  ТСР 60 level (60 заданий каждого типа и 180 минут) при повторном нарушении в течение 14 дней",
"",
"Видео-опровержения с мероприятия:",
"",
"22.13 Каждый участник мероприятия в обязательном порядке должен записывать всё мероприятие и хранить запись пять суток | При отсутствии опровержения по просьбе администрации. Наказание: Блокировка игрового аккаунта на 15 дней",
"22.14 Администрации может в любой момент запросить у вас опровержение с мероприятия и вы обязаны его предоставить в течении суток",
"22.15 При получении наказания на мероприятии вы можете написать жалобу, где вы в обязательном порядке должны предоставить опровержение",
"22.16 Начальные условия при записи опровержения (Пробив)",
"На опровержении должно быть зафиксировано /time, /id или /stats.",
"22.17 Запрещено редактировать/рендерить видео/убирать/накладывать звук. Исключение: обрезать момент, если следящий запросил опру момента",
"22.18 Запрещено записывать видео которое не соответствует требованиям (Несмотрибельные опровержения)",
"22.19 На видео с опровержением рекомендуем присутствие звуков игры",
"22.20 Рекомендуем соблюдать баланс звука для приятного восприятия",
"22.21 Запрещено удалять/вырезать эффект крови. Наказание: устное предупреждение  Бан на участие в мероприятиях (бан МП) на 6 дней при повторном нарушении в течение 7 дней.",
"22.22 Запрещено убирать видимость объектов (текстуры, столбы, видимость мусора, деревья, кусты и т.д), в условиях, дающих преимущество над другими игроками",
"",
"Минимальные требования к опровержению",
"FPS: 30",
"Разрешение экрана: 1280x720 (720p)",
"Качество может быть ниже, но должно быть смотрибельно для администрации",
"",
"#23. Правила мероприятия \"Битва за Завод\"",
"23.1 Разрешено ПГ и использование тазера в бою",
"23.2 Сотрудникам МЮ запрещено выдавать розыск во время проведения мероприятия. Наказание: ТСР 60 level (60 заданий каждого типа и 180 минут)  Варн при повторном нарушении в течение 14 дней",
"23.3 Запрещено участие в мероприятии от игроков, не состоящих в организациях: мю, мо и банды. Наказание: ТСР 30 level (30 заданий каждого типа и 90 минут)  ТСР 60 level (60 заданий каждого типа и 180 минут) при повторном нарушении в течение 7 дней",
"23.4 Запрещено проводить арест на мероприятии. Наказание: ТСР 60 level (60 заданий каждого типа и 180 минут)  Варн при повторном нарушении в течение 7 дней",
"23.5 Запрещено убивать игроков до начала проведения мероприятия.",
"Примечание: запрещено до 19:20 и после 20:00 (в описании МП в игре указано, что правила начинают действовать за 10 минут до начала и заканчивают через 10 минут после окончания МП, фактическое время проведения с 19:30 до 19:50). Наказание: ТСР 30 level (30 заданий каждого типа и 90 минут)  ТСР 60 level (60 заданий каждого типа и 180 минут) при повторном нарушении в течение 7 дней",
"23.6 Запрещено использовать игрушечный транспорт на р/у (Танк, Вертолёт, Самолёт, Машинка). Наказание: ТСР 30 level (30 заданий каждого типа и 90 минут)  ТСР 60 level (60 заданий каждого типа и 180 минут) при повторном нарушении в течение 7 дней",
"",
"Дополнительная информация:",
"23.7 Игрок имеет право по своему усмотрению и желанию осуществлять запись своего игрового процесса во время участия в серверных мероприятиях.",
"23.8 Игрок, который демонстрирует высокие показатели убийств, частые победы, или вызывает подозрения в использовании читов, может быть обязан записывать свой игровой процесс во время участия в серверных мероприятиях по решению старшей администрации.",
"",
"#24. Правила мероприятия \"Операция Мираж\"",
"Общее положение",
"",
"24.1 Разрешено ПГ",
"24.2 За нарушения правил \"Операции Мираж\" от игроков, занявших призовые места (1-3 место) — изъятие выигранных AZ Coins. В случае отсутствия выигранных AZ при первом нарушении — блокировка МП на 5 дней  блокировка на 5 дней при повторном нарушении в течение 14 дней.",
"24.3 Запрещен тиминг между командами. Наказание: ТСР 30 level (30 заданий каждого типа и 90 минут)  ТСР 60 level (60 заданий каждого типа и 180 минут) при повторном нарушении в течение 7 дней",
"24.4 3+ нарушения от одного человека за мероприятие. Наказание: Варн",
"24.5 Запрещается использовать камхак во время мероприятия “Мираж” с целью выявления местоположения оппонентов. Наказание: Бан на 1 день  на 3 дня при повторном нарушении в течение 7 дней",
"",
"Видео-опровержения с мероприятия:",
"",
"24.6 Каждый участник мероприятия в обязательном порядке должен записывать всё мероприятие и хранить запись пять суток | При отсутствии опровержения по просьбе администрации. Наказание: Блокировка игрового аккаунта на 15 дней",
"24.7 В случае если Вы заняли призовое место на мероприятии (ТОП 1, 2, 3) — Вы обязаны предоставить своё опровержение в соответствующем разделе жалоб своего сервера в течение 24 часов. Наказание: изъятие выигранных AZ Coins  блокировка на 5 дней. В случае отсутствия выигранных AZ при первом нарушении — блокировка МП на 5 дней  блокировка на 5 дней при повторном нарушении в течение 14 дней.",
"Примечание: при отсутствии опровержения у победителей мероприятия (ТОП 1,2,3) - приз мероприятия будет изъят.",
"24.8 Администрации может в любой момент запросить у вас опровержение с мероприятия и вы обязаны его предоставить в течении суток",
"24.9 При получении наказания на мероприятии вы можете написать жалобу, где вы в обязательном порядке должны предоставить опровержение",
"24.10 Начальные условия при записи опровержения (Пробив)",
"На опровержении должно быть зафиксировано /time, /id или /stats.",
"24.11 Запрещено редактировать/рендерить видео/убирать/накладывать звук. Исключение: обрезать момент, если следящий запросил опру момента",
"24.12 Запрещено записывать видео которое не соответствует требованиям (Несмотрибельные опровержения)",
"24.13 На видео с опровержением рекомендуем присутствие звуков игры",
"24.14 Рекомендуем соблюдать баланс звука для приятного восприятия",
"24.15 Запрещено удалять/вырезать эффект крови. Наказание: устное предупреждение  Бан на участие в мероприятиях (бан МП) на 6 дней при повторном нарушении в течение 7 дней.",
"24.16 Запрещено убирать видимость объектов (текстуры, столбы, видимость мусора, деревья, кусты и т.д), в условиях, дающих преимущество над другими игроками",
"24.17 При обнаружении факта взаимодействия (игра в одной команде с игроком, использующим читы) у всех участников такой команды изымается выигранный приз.",
"",
"",
"Минимальные требования к опровержению",
"FPS: 30",
"Разрешение экрана: 1280x720 (720p)",
"Качество может быть ниже, но должно быть смотрибельно для администрации",
}},
{name="Правила для государственных организаций",content={
"#25. Общий свод правил государственных организаций",
"",
"25.1 Сотрудникам государственных организаций разрешено стоять в форме AFK без ESC до и после рабочего дня в любом месте, не создавая помех.",
"Примечание: Разрешено находиться AFK/AFK без ESC в форме, не создавая помех, исключительно в интерьерах: личный дом, личная квартира, семейная квартира, арендованные комнаты, отели, трейлеры, личные автомобили с интерьерами (Enforcer/Boxville и т.д.), стрип-клуб, подземные паркинги, отдельно отведённые комнаты для сна в организациях.",
"Дополнение: Нахождение в AFK/AFK без ESC в форме вне выше перечисленных мест может быть наказуемо в рамках законодательства вашего сервера.",
"25.2 Сотрудникам государственных организаций запрещено повышать уровень льготы любыми нечестными способами, в том числе за денежное вознаграждение, оказание услуг или иные формы личной выгоды, а также в обход установленной системы.",
"Наказание: Устное замечание / Предупреждение / Понижение уровня льготы / Аннулирование льготы / Увольнение.",
"25.3 Разрешена агитация в период официально объявленной предвыборной гонки вплоть до дня выборов включительно.",
"25.4 Запрещено использовать материал для кейс-файлов, делопроизводств и т.п., который был получен без использования системного функционала боди-камеры.",
"Наказание: Отказ в рассмотрении.",
"Исключение: Использование записей с камер государственных учреждений или городских камер при наличии соответствующей RP-ситуации.",
"Примечание: При подаче жалобы обычным гражданским лицом дополнительные покупки экшн-камеры или её отыгровки не требуются.",
"25.5 Военнослужащим (Армия, Тюрьма, иные структуры МО) запрещено находиться в форме на территориях с красным розыском. Наказание: Спавн  ТСР 30 level (30 заданий каждого типа и 90 минут)  ТСР 60 level (60 заданий каждого типа и 180 минут) при повторном нарушении в течение 7 дней.",
"Примечание: Наказание также последует, если находиться рядом с зоной и наносить урон игрокам, находящимся в ней.",
"",
"#26 Правила судебной власти",
"Критерии для вступления на пост судьи",
"26.1 Для назначения на пост судьи игрок должен достигнуть 15 игрового уровня.",
"26.2 Судьей может стать игрок, успешно отстоявший 20 дней срока лидера или больше, при этом показывая высокие показатели активности во фракции.",
"26.3 При отсутствии 3-х судей альтернативным вариантом назначения на пост судьи является прохождение обзвона.",
"",
"",
"Устройства судебной власти ",
"26.4 Максимальное количество судей составляет 5 человек.",
"26.5 Судебная ветвь власть подчиняется только губернатору и следящей администрации. Судьи независимы в своих решениях, но должны руководствоваться законодательством штата. При вынесении решений судья обязан учитывать ранее принятые судебные решения по аналогичным делам и сложившуюся судебную практику штата. В случае наличия судебного прецедента его применение имеет приоритет перед личной интерпретацией судьёй норм законодательства. В спорной ситуации перед вынесением решения следует обратиться к следящей/главной администрации сервера.",
"26.6 Следящей администрацией за судебной властью являются администраторы, следящие за правительством.",
"26.7 У членов судейской коллегии 20 дневный срок.",
"26.7.1. В случае успешного срока судьи, судья может остаться на своей должности вплоть до момента, пока не будет нового желающего (при достижении максимального количества судей).",
"26.7.2 По окончанию срока судья может пойти на пост администратора или остаться на своей должности по желанию.",
"26.7.3 Если судья встал на должность через пост лидера, то по окончанию срока он может стать администратором 2-го уровня с сокращенной на 25% системой повышения.",
"26.8 По решению судьи сотрудник ПД может быть уволен при наличии одобрения со стороны следящей администрации.",
"",
"",
"Обязанности членов судебной власти",
"26.9 Работа судьи заключается в своевременном рассмотрении судебных исков: в течение 12 часов с 10:00 до 22:00 и 18 часов в остальное время (включая ночное время и выходные). Судья имеет право на разумную отсрочку при наличии уважительных причин (отпуск, болезнь, форс-мажор), предупредив ГА или старшую следящую администрацию.",
"26.9.1 Заявление (иск) в суд может быть подано в течение 5 дней с момента совершения нарушения, по которому подаётся иск. По истечении этого срока иск не рассматривается.",
"Исключение: случаи, когда истец не мог узнать о нарушении ранее (например, при длительном отсутствии в игре), рассматриваются индивидуально по решению судьи или ГА.",
"26.10 Каждый судья должен знать принципы работы законодательной системы штата и понимать ее устройство.",
"26.11 Каждый судья обязан осуществлять свою деятельность строго в соответствии с законом, оставаясь беспристрастным и руководствуясь логическим и объективным мышлением, не проявляя жалости или сострадания к обвиняемому или другим участникам дела.",
"26.12 Судья обязан избегать конфликтов интересов и ситуаций, которые могут поставить под сомнение его объективность и беспристрастность.",
"26.13 Судья лично несёт ответственность за каждый свой вердикт. Невзирая на чьи советы или подсказки он опирался.",
"",
"",
"Снятие с поста судьи",
"26.14 Судья может быть снят со своего поста по окончании срока, или до его окончания, если:",
"26.14.1 Судья признается виновным в совершении преступления;",
"26.14.2 Судья подрывает авторитет судебной власти (байтит сотрудников ПД, намеренно нарушает законодательство штата, злоупотребляет неприкосновенностью, проявляет неадекватное",
"поведение, оскорбляет и т.п.);",
"26.14.3 Судья неоднократно выносит заведомо неправомерное решение, которое влечет за",
"собой нарушение законных прав и интересов граждан (Согласно пункту 3.5);",
"26.14.4 Судья может быть снят по решению главной следящей администрации.",
"26.15 Судья может быть снят со своего поста только главной следящей администрацией.",
"26.16 Судья может быть повышен до поста администратора спустя 20 дней на посту, отказ в посте администратора может быть по решению главной администрации.",
"",
"",
"Пересмотр решение судьи",
"26.17 Решение судьи пересматриваются главной администрацией сервера в порядке очереди.",
"26.18 Каждый несогласный с решением судьи имеет право обратиться в раздел жалоб на администрацию и получить компенсацию в случае ошибочного вердикта.",
"",
"#27. Правила для сотрудников ПД/ФБР",
"",
"27.1 Разрешены нарушения данных правил, если в процессе ареста игрок грубо нарушает правила сервера и у вас не остается возможности действовать иначе, при этом у вас должны быть доказательства нарушений со стороны игрока.",
"Пример: разрешено арестовывать на респе банды, в центре гетто, если игрок в процессе погони приехал туда; разрешено провести дм арест, если игрок использует воду или аксессуары от ареста и т.д.",
"27.2 Запрещен ДМ арест - убийство игрока для его отправки в тюрьму при наличии возможности провести стандартный арест: Наказание: ТСР 60 level (60 заданий каждого типа и 180 минут)  ТСР 120 level (120 заданий каждого типа и 360 минут) при повторном нарушении в течение 7 дней",
"27.3 Запрещено таскать игроков через /gotome на большие расстояния (разрешено только до автомобиля): Наказание: ТСР 30 level (30 заданий каждого типа и 90 минут)  ТСР 60 level (60 заданий каждого типа и 180 минут) при повторном нарушении в течение 7 дней",
"Примечание: автомобиль должен находиться неподалеку от места проведения ареста. Если он отсутствует, полицейский должен запросить подкрепление.",
"27.4 Запрещено в форме находиться на территориях с красным розыском: Наказание: Устное замечание / ТСР 30 level (30 заданий каждого типа и 90 минут)  ТСР 60 level (60 заданий каждого типа и 180 минут) при повторном нарушении в течение 7 дней.",
"Примечание: наказание также последует, если находится рядом с зоной и наносить урон игрокам, находящимся в ней.",
"27.5 Запрещено выдавать розыск за неподчинение игрокам, находящимся в АФК, РП сне и бездействующим: Наказание: ТСР 60 level (60 заданий каждого типа и 180 минут)  Варн при повторном нарушении в течение 7 дней.",
"Примечание: Если игрок совершал действия, подтверждающие его активность (двигался, управлял транспортом, писал в чат и т.п.) — розыск за неподчинение/начало процесса ареста разрешено производить.",
"27.6 Сотруднику запрещено выдавать розыск после своей смерти или попадания в стадию смерти (если игрок(подозреваемый) в стадии смерти - розыск выдавать можно): Наказание: ТСР 30 level (30 заданий каждого типа и 90 минут)  Варн при повторном нарушении в течение 7 дней.",
"27.7 Запрещено выдавать наказания (розыск, штрафы и т.д.) без причины. Выдача наказаний должна быть в соответствии с ЕФК - Единый Федеральный Кодекс (УК, АК и т.д). - в зависимости от названия на вашем сервере).",
"27.7.1 Ошибочным розыском (штрафом и т.д.) считается тот, который выдан без причины, с нарушением действующего законодательства, или который был снят по решению администрации;",
"27.7.2 Если в результате некорректных действий полицейского игрок понес любые убытки (снял ошибочный розыск у Гурама, выкупил автомобиль на штрафстоянке), лидер данного ПД должен компенсировать расходы за своего сотрудника;",
"27.7.3 За ошибочный розыск, в результате которого игрок не пострадал (розыск был снят). Наказание: Устное предупреждение",
"27.7.4 За ошибочный розыск или некорректный штраф, в результате которого игрок попал в ТСР или понес иные убытки: Наказание: ТСР 60 level (60 заданий каждого типа и 180 минут)  ТСР 120 level (120 заданий каждого типа и 360 минут) при повторном нарушении в течение 7 дней.",
"27.7.5 За намеренную выдачу ошибочного розыска: Наказание: Варн",
"27.7.6 За массовую выдачу намерено розыска (слив): Наказание: Бан на 30 дней",
"27.8 Запрещено начинать задержание игрока без РП диалога, проверки документов и т.п., если вы не видели нарушение своими глазами: Наказание: ТСР 60 level (60 заданий каждого типа и 180 минут)  ТСР 120 level (120 заданий каждого типа и 360 минут) при повторном нарушении в течение 7 дней.",
"Примечание: полицейский должен отыграть, как конкретно узнал, что перед ним игрок в розыске, а не условный брат-близнец.",
"27.9 Запрещено проводить арест (находиться) на территории спавнов банд и мафий без заранее подготовленной облавы. Наказание: ТСР 60 level (60 заданий каждого типа и 180 минут)  Варн при повторном нарушении в течение 7 дней.",
"Примечание: во время проведения каптов\\стрел запрещено проводить облавы, аресты и иные задержания участников на территории спавнов банд\\мафий, а также в зоне их проведения.",
"Исключение: Разрешено продолжение погони и проведение ареста на территории спавна, если подозреваемый намеренно ушел туда во время активного преследования (уход от ареста в безопасную зону). На данные действия у полицейского должны быть доказательства.",
"27.10 Запрещено намеренное затягивание процесса ареста: Наказание: ТСР 60 level (60 заданий каждого типа и 180 минут)  ТСР 120 level (120 заданий каждого типа и 360 минут) при повторном нарушении в течение 7 дней.",
"Пример: полицейский длительное время таскает за собой игрока в наручниках вместо отправки в КПЗ, растягивание процесса допроса на \"час\" и т.д.",
"27.11 Полицейским требуется записывать нарушения со стороны игроков, за которые они их наказывают. Администрация может запросить опровержение на выдачу розыска (/su), штрафы (/ticket), изъятие предметов и лицензий (/take), на отправку машины на штрафстоянку (/strafs). По желанию можно записывать опровержение на полный процесс ареста (/arrest) - от задержания до отправки в КПЗ, которое может помочь в случае жалобы от игрока.",
"27.11.1 Запись должна иметь /time и хорошее качество (720p или выше). Все элементы должны быть читаемы;",
"27.11.2 Запись должна храниться не менее 5 дней;",
"27.11.3 Запись должна быть предоставлена в течении 24-х часов после запроса администрацией. Наказание: Устное предупреждение  Варн при повторном нарушении в течение 14 дней.",
}},
{name="Правила для нелегальных организаций",content={
"#28. Правила проведения стрел мафий ",
"Общее положение:",
"28.1 Назначать встречу за бизнес может только лидер и заместитель фракции",
"28.2 Назначать встречу возможно как за час, так и на 3 дня вперед",
"Примечание: Стрела забитая за час до начала стрелы является обоюдной, противоположная мафия вправе сама решать принять или проигнорировать данный забив.",
"28.3 Если назначать встречу на завтра, то время проведение стрелы с 16:00 до 21:40",
"28.4 В случае, если мафия назначает встречу за час, то работу эффектов от аксессуаров включить невозможно",
"28.5 Возможность включения эффектов от аксессуаров на стреле - платная. Её стоимость 75.000.000$, деньги снимаются со счета организации",
"28.6 Расформ бизнесов происходит спустя 7 дней после взятия всех бизнесов",
"28.7 В забиве разрешено использовать оружие: Deagle, M4, Cuntgun, Shotgun (в забиве обязательно должен быть Deagle)",
"Исключение: любое оружие на стреле с включенными эффектами от аксессуаров",
"28.8 Ранг доступа к стрелам регулируется лидером через /lmenu",
"28.9 За 30 минут до начала МП \"Битва за Наземные нефтевышки\" - система блокирует команду /bizwar",
"28.10 Стрела проводится следующим количеством участников: 2x2, 3х3, 4х4 и 5х5. Можно больше по обоюдному согласию",
"28.11 Запрещено откатывать количество участников после принятия стрелы. Наказание: устный лидеру",
"28.12 Игнор стрелы автоматически приравнивается к неприезду.",
"Примечание: Количество участников на стрелу должно быть подтверждено (пикнуто) не позднее чем за 1 час до начала стрелы.",
"28.13 Запрещено забивать стрелу мафии, которая в это время участвует в ГРП или проводит теракт/ограбление.",
"28.14 Разметка зон стрел (Imgur):",
"Спойлер: Лесопилка",
"Спойлер: Заброшенный аэродром",
"Спойлер: Заброшенная деревня",
"Спойлер: Ферма Вест Стоун",
"Спойлер: Химзавод",
"Спойлер: Угольная шахта",
"Спойлер: Спутниковая тарелка",
"Спойлер: Кладбище",
"Спойлер: Деревня Montgomery",
"Спойлер: Ферма Red County",
"Спойлер: Нефтезавод Red County",
"Спойлер: Бар в Flint County",
"Спойлер: Скала Норстар",
"Спойлер: Район моста SF-LV",
"Спойлер: Отель Валле Окутадо",
"Спойлер: Порт Los-Santos",
"Спойлер: Гора Чиллиад",
"Порядок назначения встречи в конференции",
"",
"28.15 Назначать встречи в конференции возможно только в период с 16:00 до 22:00 МСК. Встречи, назначенные позже или раньше не имеют силы и могут не подчиняться правилами ниже",
"28.17 Для того, чтобы забить стрелу, лидер забивает системный /bizwar в игре по установленным условиям в забиве, после отправляет оповещение в конференцию забивов.",
"28.18 Лидер/заместитель мафии, которой назначили стрелу за час должен дать ответ по количеству участников стрелы в течение 10 минут. Если сообщение игнорируется - это автоматически приравнивается к отказу от стрелы",
"28.19 Если стрела назначена на следующий или последующие дни, противоположная мафия обязана ответить на забив максимум за 1 час до начала стрелы. В случае игнорировая забива - стрела будет считаться принятой.",
"28.20 Лидер/заместитель, в случае, если допустил в написании текста ошибку, может исправить её в течение 1-2х минут после отправки сообщения, с пометкой: upd, ошибка или исправлено. Категорически запрещено редактировать само сообщение и злоупотреблять правилом",
"28.21 Мафия может назначить не более двух стрел на один и тот же бизнес в течение 48 часов. Повторные забивы на один и тот же бизнес в короткий срок считаются нарушением, и лидер получает строгое предупреждение. Запрещено назначать стрелу мафии, которая находится в морозе. Допускается назначение стрелы только при полном выходе мафии из мороза без раннего забива.",
"28.22 Форма забива стрелы в конференции:",
"От кого vs кому.",
"За бизнес (id бизнеса)",
"Оружие",
"Локация",
"По типу стрелы (Обычная/Аксовая)",
"Дата/время",
"",
"На стреле разрешено:",
"",
"28.23 Разрешено использовать оружие, которое было указано в форме забива стрелы",
"28.24 Разрешено использовать укроп в случае, если у Вас началась ломка, и исключительно до фактического начала перестрелки (например, во время РП диалога)",
"28.26 Разрешено при обоюдном согласии телепортировать участников стрелы игроков с помощью администрации",
"28.27 Разрешено начинать стрельбу по игроку, если тот перебегает разметку раньше назначенного времени",
"28.28 Разрешено приезжать в составе меньше, чем было указано в конференции (но не менее 2 . Меньше 2-х человек = неприезд)",
"28.29 Разрешено использовать углубления местности.",
"28.30 Разрешено добраться до зоны стрелы на транспорте и расставить транспортные средства. Использовать транспорт во время стрелы (ездить, стрелять с него, использовать как укрытие(пример: сесть в него и из-за хендлинга вас никто не сможет убить), намеренно мешать обзору(пример: ставить в текстуры, багоюзить и т.п.)) запрещено. Наказание: 1 бизнес.",
"Примечание: Расстановка транспорта до начала стрелы разрешена. Как только начался РП-диалог или отсчёт времени — транспорт считается частью статичной обстановки. Его перемещение и использование в этот период — нарушение.",
"",
"",
"На стреле запрещено:",
"",
"28.31 Запрещено нарушать правила проекта. Наказание: По нормативам правил",
"28.32 Запрещено наносить урон по участникам стрелы, до указанного времени в РП диалоге. Наказание: ТСР 30 level (30 заданий каждого типа и 90 минут)  ТСР 60 level (60 заданий каждого типа и 180 минут) при повторном нарушении в течение 7 дней.",
"Исключение: если игрок с противоположной мафии попросил сбить уровень здоровья.",
"28.33 Запрещены любые баги стрельбы, кроме скролла, багшота, полуслайда. Наказание: ТСР 60 level (60 заданий каждого типа и 180 минут)  Варн при повторном нарушении в течение 7 дней.",
"28.34 Запрещено использовать любые способы восполнения здоровья, маски, бронежилеты на стреле. Наказание: ТСР 30 level (30 заданий каждого типа и 90 минут)  ТСР 60 level (60 заданий каждого типа и 180 минут) при повторном нарушении в течение 7 дней.",
"Исключение: Системные аксовые стрелы.",
"28.35 Запрещено использовать оружие, которое не было назначено в конференции. Наказание: ТСР 30 level (30 заданий каждого типа и 90 минут)  ТСР 60 level (60 заданий каждого типа и 180 минут) при повторном нарушении в течение 7 дней.",
"28.36 Запрещено заходить на территорию стрелы (малый квадрат) после 08:00 на таймере таблицы. Наказание: -1 бизнес",
"Исключение: если противоположная мафия согласна, но бизнес за неприезд будет отдан в любом случае",
"28.37 Запрещено мешать мафии добраться на территорию стрелы. Наказание: ТСР 30 level (30 заданий каждого типа и 90 минут)  ТСР 60 level (60 заданий каждого типа и 180 минут) при повторном нарушении в течение 7 дней.",
"28.38 Запрещено заходить в зону проведения стрелы (малый квадрат) после начала РП диалога. Наказание: ТСР 30 level (30 заданий каждого типа и 90 минут)  ТСР 60 level (60 заданий каждого типа и 180 минут) при повторном нарушении в течение 7 дней.",
"28.39 Запрещено выходить во время стрелы с территории малого квадрата. Наказание: ТСР 30 level (30 заданий каждого типа и 90 минут)  ТСР 60 level (60 заданий каждого типа и 180 минут) при повторном нарушении в течение 7 дней.",
"28.40 Запрещено РК на стрелу (возвращение в виртуальную зону проведения стрелы). Наказание: ТСР 30 level (30 заданий каждого типа и 90 минут)  ТСР 60 level (60 заданий каждого типа и 180 минут) при повторном нарушении в течение 7 дней.",
"28.41 Запрещено использовать любой багоюз бега. Наказание: ТСР 30 level (30 заданий каждого типа и 90 минут)  ТСР 60 level (60 заданий каждого типа и 180 минут) при повторном нарушении в течение 7 дней.",
"28.42 Запрещено выходить из игры с места проведения стрелы. Наказание: ТСР 30 level (30 заданий каждого типа и 90 минут)  ТСР 60 level (60 заданий каждого типа и 180 минут) при повторном нарушении в течение 7 дней.",
"Исключение: краш/кик",
"28.43 Запрещено использовать возвышенности на стрелах. Наказание: ТСР 30 level (30 заданий каждого типа и 90 минут)  ТСР 60 level (60 заданий каждого типа и 180 минут) при повторном нарушении в течение 7 дней.",
"28.44 Запрещен антифраг в любом его проявлении. Наказание: ТСР 30 level (30 заданий каждого типа и 90 минут)  ТСР 60 level (60 заданий каждого типа и 180 минут) при повторном нарушении в течение 7 дней.",
"28.45 Запрещено использование спутника (бота охранника) на стреле. Наказание:ТСР 30 level (30 заданий каждого типа и 90 минут)  ТСР 60 level (60 заданий каждого типа и 180 минут) при повторном нарушении в течение 7 дней.",
"Исключение: Стрела с действующими аксесуарами",
"28.46 Запрещено занимать стартовую позицию не на своей стороне разметки / на жёлтой линии. Наказание: ТСР 30 level (30 заданий каждого типа и 90 минут)  ТСР 60 level (60 заданий каждого типа и 180 минут) при повторном нарушении в течение 7 дней.",
"Примечание: Нарушением считается факт нахождения на неправильной стороне разметки до команды о начале стрельбы. Если игрок перебегает разметку во время стрельбы применяется пункт 28.27.",
"",
"Правила проведения РП диалога",
"",
"28.47 Обе мафии должны приехать в заранее установленном количестве участников на территорию стрелы.",
"28.48 Если обе мафии прибыли в назначенном количестве на территорию стрелы, начинается отсчёт времени (До РП диалога) на подготовку.",
"28.49 Перед началом каждой проведённой стрелы должен присутствовать РП диалог между членами мафий.",
"28.50 РП диалог обязан быть, когда составы уже находятся на месте проведения стрелы и подтвердили готовность. При проведении РП диалога, все участники стрелы обязаны стоять на месте проведения РП диалога (примерно центр локации)",
"28.51 На РП диалоге должно быть обозначено: причина (локация проведения стрелы зависит от той, что была забита в дискорде), какое оружие разрешено использовать, количество участников, локация (разметка), время начала стрелы.",
"Пример: \"Вам была назначена стрела за ограбление АЗС, оружие: дигл/шот, 3х3, наша сторона - ближе к воде, время 12:00\".",
"28.52 Время начала стрелы выбирается строго по таймеру на табличке стрелы.",
"28.53 Обязанность на проведение РП диалога лежит на мафии, которая забила стрелу.",
"28.54 РП диалог ведет один представитель из каждой мафии.",
"28.55 РП диалог должен быть проведен до 6 минуты по табличке, в случае, если мафия, которая забила стрелу, уклоняется от диалога или его не проводит - делается предупреждение об игноре стрелы и начинается стрельба, вне зависимости от стартовых позиций.",
"Примечание: Началом РП диалога считается вопрос о готовности противоположной мафии.",
"Исключение: по согласию сторон",
"28.56 Вышеописанные пункты работают и в обратную сторону, если мафия, которая должна провести диалог затягивает время",
"Примечание: В случае если мафия которая забила стрелу уклоняется от РП диалога после 4 минуты по табличке, отвечающая сторона может предупредить: Игнор стрелы более 2 минут. Открываем огонь.",
"28.57 Минимальное время на разбег - 30 секунд, максимальное - 1 минута.",
"28.58 Запрещено нарушение правил РП диалога. Наказание: 1 бизнес.",
"",
"",
"Правила опровержений и условия при записи опровержения",
"",
"28.59 Каждый участник стрелы в обязательном порядке должен записывать мероприятие и хранить запись пять суток. Начинать запись с момента РП диалога между мафиями. Заканчивать запись по окончании стрелы после исчезновения таблички или отсутствия игроков противоположной мафии в территории.",
"28.60 Администрации может в любой момент запросить у вас опровержение с мероприятия, и Вы должны его предоставить в течение суток.",
"28.61 Если опровержение не было предоставлено в срок (24 часа), опровержение будет рассматриваться, но территории/бизнесы переходят противоположной банде/мафии.",
"Исключение: +12 часов к подаче опровержения",
"28.62 При получении наказания на мероприятии вы можете написать жалобу, где в обязательном порядке должны предоставить опровержение.",
"28.63 На опровержении должно быть зафиксировано /time - При отсутствии на первый раз - напоминание. При повторении: Наказание Варн.",
"28.64 Отсутствие опровержения при запросе - на первый раз бан 7 дней. (влияет на изъятие бизнеса)",
"Исключение: Если есть подозрения на софт по моменту и запрашивается полное опровержение, то в случае непредоставления - выдаётся блокировка эквивалентно нарушению",
"28.65 В опровержении должны быть отчетливо слышны звуки стрельбы и попаданий. Рекомендуется использовать серверный дамаг-информер (колокольчик) для подтверждения нанесения урона. При первом нарушении — предупреждение  при повторном — бан на 1 день.",
"Примечание: Отсутствие звуков попаданий из-за штатной работы лаунчера (при наличии звуков стрельбы) не является нарушением.",
"28.66 Категорически запрещено убирать трейсера/кровь и таргеты из игры. Они должны быть четко видны, в ином случае опровержение будет засчитана, как несмотрибельная. - Бан на первый раз 7 дней, при повторении 15 дней. (влияет на изъятие бизнеса)",
"28.67 Запрещено редактировать/рендерить видео/накладывать звук.",
"Исключение: обрезать момент, если следящий запросил опру момента - На первый раз бан 7 дней, при повторении 15 дней. (влияет на изъятие территорий)",
"28.68 Запрещено записывать видео, которое не соответствует требованиям (несмотрибельное опровержение) - На первый раз бан 7 дней, при повторении 15. (влияет на изъятие бизнеса)",
"28.69 Рекомендуем соблюдать баланс звука для приятного восприятия.",
"",
"Минимальные требования к опровержению",
"",
"FPS: 30.",
"Разрешение экрана: 1280x720 (720p).",
"Качество может быть и ниже, но смотрибельным для администрации.",
"Штрафы за нарушение правил",
"",
"28.70 Бан на стреле -- -10 бизнесов, строгий лидеру.",
"Примечание: Выговор не будет выдан, если бан не за чит.",
"Примечание: За одного игрока максимум 20 бизнесов.",
"28.71 Варн на стреле | -6 бизнеса.",
"28.72 ТСР на стреле | -4 бизнеса.",
"28.73 Неприезд на стрелу | -2 бизнеса; При систематических неприездах | -4 бизнеса (при >6 неприездов за неделю). Неприезды распространяются только на ту мафию, против которой было набрано данное количество неприездов.",
"28.74 ЧСник на стреле -- -12 бизнесов.",
"28.75 Если игрок получает блокировку по одной из жалоб, то бизнесы с других стрел выдаются только в случае, если игрок не предоставил опровержение со стрелы, на которую была залита жалоба.",
"28.76 Администрация ни под каким предлогом не передает бизнесы от одной мафий к другой для упрощения взятия всех бизнесов мафий.",
"",
"#29. Правила проведения каптов ",
"Общее положение:",
"29.1 Два варианта проведения capture:",
"По фрагам - итог капта зависит от количества убийств.",
"По \"мясу\" - итог капта решается от количества игроков оставшихся на территории по окончанию капта.",
"Интервал между каптами 20 минут.",
"29.2 Расформ территорий происходит спустя 7 дней после взятия всех территорий гетто.",
"29.3 Запрещается умышленно удерживать неполный захват территорий гетто с целью предотвращения расформирования территорий. В случае выявления подобного территории перераспределяются между другими бандами/расформировываются [По решению Главной администрации]",
"29.4 Зоны СК (Imgur):",
"Спойлер: Aztec",
"Спойлер: Ballas",
"Спойлер: Grove",
"Спойлер: Night Wolfs",
"Спойлер: Rifa",
"Спойлер: Vagos",
"Формат проведения каптов (разрешённый вид стрельбы: RP / NonRP) на всех серверах чередуется по сезонам.",
"29.5 Расшифровка форматов:",
"RP капты - рп стрельба, разрешено только: отводы после 2, сбив темпа стрельбы, сбив перекатов.",
"NonRP капты - разрешены все виды багов стрельбы и сбивы анимаций.",
"В период сезона RP-капов игроки обязаны придерживаться RP-формата стрельбы.",
"Примечание: Запрещено использование видов стрельбы, не соответствующих RP-формату — ТСР 30 level (30 заданий каждого типа и 90 минут) – ТСР 60 level (60 заданий каждого типа и 180 минут).",
"В период сезона NonRP-капов ограничения на вид стрельбы отсутствуют — допускается использование любых видов стрельбы.",
"29.6 Система сезонности RP / NonRP каптов",
"Сезоны:",
"Зима (Декабрь, Январь, Февраль)",
"Весна (Март, Апрель, Май)",
"Лето (Июнь, Июль, Август)",
"Осень (Сентябрь, Октябрь, Ноябрь)",
" Чётные сервера:",
"[02] Tucson, [04] Chandler, [06] Saint Rose, [08] Red Rock, [10] Surprise, [12] Glendale, [14] Winslow, [16] Gilbert, [18] Casa-Grande, [20] Sun-City, [22] Sedona, [24] Wednesday, [26] Faraway, [28] Christmas, [30] Love, [32] Space, [M2] Mobile 2",
"",
"Формат каптов по сезонам для четных серверов:",
"Зима (Декабрь, Январь, Февраль) — RP капты",
"Весна (Март, Апрель, Май) — NonRP капты",
"Лето (Июнь, Июль, Август) — RP капты",
"Осень (Сентябрь, Октябрь, Ноябрь) — NonRP капты",
" Нечётные сервера:",
"[01] Phoenix, [03] Scottdale, [05] Brainburg, [07] Mesa, [09] Yuma, [11] Prescott, [13] Kingman, [15] Payson, [17] Show Low, [19] Page, [21] Queen Creek, [23] Holiday, [25] Yava, [27] Bumble Bee, [29] Mirage, [31] Drake, [M1] Mobile 1, [M3] Mobile 3",
"",
"Формат каптов по сезонам для нечетных серверов:",
"Зима (Декабрь, Январь, Февраль) — NonRP капты",
"Весна (Март, Апрель, Май) — RP капты",
"Лето (Июнь, Июль, Август) — NonRP капты",
"Осень (Сентябрь, Октябрь, Ноябрь) — RP капты",
"Разрешено:",
"29.7 При сезоне RP каптов разрешено: отводы после 2, сбив темпа стрельбы, сбив перекатов. Наказание: ТСР 30 level (30 заданий каждого типа и 90 минут)  ТСР 60 level (60 заданий каждого типа и 180 минут) при повторном нарушении в течение 7 дней.",
"Примечание: В период сезона RP-капов игроки обязаны придерживаться RP-формата стрельбы. Запрещено использование видов стрельбы, не соответствующих RP-формату, а также использование любых анимаций в бою или с целью ухода от смерти.",
"29.8 При сезоне NonRP каптов - разрешены все виды багов стрельбы и сбивы анимаций.",
"Примечание: В период сезона NonRP-капов ограничения на вид стрельбы отсутствуют — допускается использование любых видов стрельбы.",
"29.9 Разрешенные оружия на капте: Desert Eagle, Shotgun, MP5, M4, AK-47, Cuntgun.",
"29.10 Разрешена любая стрельба с использованием багов (+с, отводы, слайды, дабл-хиты и т.д.).",
"29.11 Разрешено ПГ.",
"29.12 Разрешено использование углубленности и возвышенности.",
"29.13 Разрешается убирать кусты и листву с деревьев. Примечание: столбы и стволы деревьев должны быть в полный размер.",
"",
"Запрещено:",
"29.14 Запрещено не соблюдать формат стрельбы каптов.Наказание: ТСР 30 level (30 заданий каждого типа и 90 минут)  ТСР 60 level (60 заданий каждого типа и 180 минут) при повторном нарушении в течение 7 дней.",
"29.15 Запрещено использование любых оружий на капте, кроме разрешенных: Desert Eagle, Shotgun, MP5, M4, AK-47, Cuntgun. Наказание: ТСР 30 level (30 заданий каждого типа и 90 минут)  ТСР 60 level (60 заданий каждого типа и 180 минут) при повторном нарушении в течение 7 дней.",
"29.16 Запрещен антифраг - не давать противоположной банде забрать килл путем устранения члена своей банды. Наказание: ТСР 30 level (30 заданий каждого типа и 90 минут)  Варн при повторном нарушении в течение 7 дней.",
"29.17 Запрещён антикапт — нанесение урона/убийство игроков вражеской банды до начала и во время капта, с целью помехи и увеличения своих шансов на победу, в том числе в центре гетто. Наказание: ТСР 30 level (30 заданий каждого типа и 90 минут)  ТСР 60 level (60 заданий каждого типа и 180 минут) при повторном нарушении в течение 7 дней.",
"Примечание: При системной войне банд, также запрещён антикапт.",
"29.18 Запрещено использовать обход лаунчера и клиенты на капте. Наказание: Кик  Бан на 3 дня при повторном нарушении в течение 7 дней.",
"29.19 Запрещено СК. Наказание: ТСР 60 level (60 заданий каждого типа и 180 минут)  Варн при повторном нарушении в течение 7 дней.",
"29.20 Запрещено находиться на крышах или возвышенностях на которые нельзя взобраться при помощи 2-х прыжков с земли. Наказание: ТСР 30 level (30 заданий каждого типа и 90 минут)  ТСР 60 level (60 заданий каждого типа и 180 минут) при повторном нарушении в течение 7 дней.",
"29.21 Запрещено использование бронежилетов на каптах. Наказание: ТСР 30 level (30 заданий каждого типа и 90 минут)  ТСР 60 level (60 заданий каждого типа и 180 минут) при повторном нарушении в течение 7 дней.",
"Исключение: Системные аксовые капты.",
"29.22 Запрещается провокация на СК. Наказание: ТСР 30 level (30 заданий каждого типа и 90 минут)  ТСР 60 level (60 заданий каждого типа и 180 минут) при повторном нарушении в течение 7 дней.",
"Примечание: Запрещено наводить прицел, стрелять с СК зоны по игроку с целью вызвать СК",
"29.23 Запрещено офф/уходить от смерти на решающих убийствах. Наказание: ТСР 30 level (30 заданий каждого типа и 90 минут)  ТСР 60 level (60 заданий каждого типа и 180 минут) при повторном нарушении в течение 7 дней.",
"29.24 Запрещено находиться в зоне СК своей банды более 1 минуты (погрешность не более 3 секунд). Наказание: ТСР 30 level (30 заданий каждого типа и 90 минут)  ТСР 60 level (60 заданий каждого типа и 180 минут) при повторном нарушении в течение 7 дней.",
"29.25 Запрещен заход в зону СК противника более чем на 15 секунд. Наказание: ТСР 30 level (30 заданий каждого типа и 90 минут)  ТСР 60 level (60 заданий каждого типа и 180 минут) при повторном нарушении в течение 7 дней.",
"29.26 Запрещено возвращаться в зону СК своей банды в целях ухода от смерти. Наказание: ТСР 30 level (30 заданий каждого типа и 90 минут)  ТСР 60 level (60 заданий каждого типа и 180 минут) при повторном нарушении в течение 7 дней.",
"29.27 Запрещено использование воздушного транспорта. Наказание: ТСР 60 level (60 заданий каждого типа и 180 минут)  Варн при повторном нарушении в течение 7 дней.",
"29.28 Запрещена стрельба из транспорта с пассажирского места. Наказание: ТСР 30 level (30 заданий каждого типа и 90 минут)  ТСР 60 level (60 заданий каждого типа и 180 минут) при повторном нарушении в течение 7 дней",
"",
"",
"Штрафы:",
"29.29 За каждый бан от участника, повлиявший на исход капта - банда теряет две территории.",
"29.30 За три варна или ТСР на одном капте - изъятие одной территории.",
"29.31 Если игрок регулярно нарушает правила каптов - он получит ЧС гетто.",
"29.32 За любые нарушения, дающие преимущества над другой бандой на решающем фраге - банда теряет одну территорию.",
"29.33 Если антифраг решает итог капта - выдача одной территории.",
"29.34 Неприезд на капт (независимо от того, атакует сторона или обороняется) - изъятие одной территории (при систематических нарушениях — изъятие двух территорий).",
"29.35 Обороняющейся банде необходимо совершить приезд (минимум 3 человека) в зону проведения захвата до 10:00 по таймеру - Изъятие одной территории.",
"",
"",
"Видео-опровержения с мероприятия:",
"29.36 Каждый участник капта в обязательном порядке должен записывать мероприятие и хранить запись пять суток. Начинать запись с момента появления таймера (лучше на несколько секунд ранее). Заканчивать запись по окончанию капт после исчезновения таблички",
"29.37 Администрации может в любой момент запросить у вас опровержение с мероприятия и вы должны его предоставить в течении суток",
"29.38 При получении наказания на мероприятии вы можете написать жалобу, где вы в обязательном порядке должны предоставить опровержение",
"",
"",
"Условия при записи опровержения (Пробив)",
"29.39 На опровержении должно быть зафиксировано /time, /id - При отсутствии на первый раз - напоминание. При повторении - варн.",
"29.40 Отсутствие опровержения при запросе - на первый раз бан 7 дней. (влияет на изъятие территорий)[/FONT]",
"Исключение: Если есть подозрения на софт по моменту и запрашивается полное опровержение, то в случае непредоставления - выдаётся блокировка эквивалентно нарушению.",
"29.41 Обязательно нужно фиксировать звуки стрельбы и попаданий, а также серверный дамаг-информер [/settings] с колокольчиком - при отсутствии на первый раз напоминание, при повторении бан на 10 дней. (влияет на изъятие территорий)",
"29.42 Категорически запрещено убирать трейсера/кровь из игры. Они должны быть четко видны, в ином случае опра будет засчитана, как несмотрибельная. - Бан на первый раз 7 дней, при повторении 15 дней. (влияет на изъятие территорий)",
"29.43 Запрещено редактировать/рендерить видео/накладывать звук. Исключение: обрезать момент, если следящий запросил опру момента - На первый раз бан 7 дней, при повторении 15 дней. (влияет на изъятие территорий)",
"29.44 Запрещено записывать видео которое не соответствует требованиям (Несмотрибельные опровержения) - На первый раз бан 7 дней, при повторении 15. (влияет на изъятие территорий)",
"29.45 Рекомендуем соблюдать баланс звука для приятного восприятия.",
"29.46 Запрещены провоцирующие символики и высказывания на записи. | Исключение - флаги. - Просьба убрать.",
"",
"",
"",
"29.47 Минимальные требования к опровержению",
"FPS: 30",
"Разрешение экрана: 1280x720 (720p)",
"Качество может быть и ниже, но смотрибельно для администрации",
}},
}