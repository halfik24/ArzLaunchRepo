script_name('Clava Races')
script_author('by Pryanix')
script_version(1.0)

local ok_imgui, imgui = pcall(require, 'mimgui')
assert(ok_imgui, 'Не найдена библиотека mimgui. Установите её через MoonLoader (Библиотеки).')
local ffi = require 'ffi'
local encoding = require 'encoding'
local ok_ini, inicfg = pcall(require, 'inicfg')
local ok_lfs, lfs = pcall(require, 'lfs')

pcall(ffi.cdef, [[
    short GetAsyncKeyState(int vKey);
    void* GetForegroundWindow(void);
    unsigned long GetWindowThreadProcessId(void* hWnd, unsigned long* lpdwProcessId);
    unsigned long GetKeyboardLayout(unsigned long idThread);
]])

encoding.default = 'CP1251'
local u8 = encoding.UTF8
local new = imgui.new

local cfg



do
    local seed = os.time() + math.floor(os.clock() * 1000000)
    math.randomseed(seed)
    math.random(); math.random(); math.random()
end

local ui

function colorVec(r, g, b, a) return imgui.ImVec4(r, g, b, a or 1.0) end
function darken(c, f) return colorVec(c[1] * f, c[2] * f, c[3] * f, 1.0) end
function darkenImVec4(c, f) return colorVec(c.x * f, c.y * f, c.z * f, 1.0) end
function brighten(c, f)
    return colorVec(math.min(1, c[1] * f), math.min(1, c[2] * f), math.min(1, c[3] * f), 1.0)
end

function utf8_lead_len(b)
    if b < 0x80 then return 1
    elseif b >= 0xF0 then return 4
    elseif b >= 0xE0 then return 3
    elseif b >= 0xC0 then return 2
    else return 1 end
end

function utf8_chars(s)
    local out, i, n = {}, 1, #s
    while i <= n do
        local b = s:byte(i)
        local len = utf8_lead_len(b)
        out[#out + 1] = s:sub(i, i + len - 1)
        i = i + len
    end
    return out
end

function utf8_codepoint(ch)
    local b1 = ch:byte(1)
    if not b1 then return 0 end
    if b1 < 0x80 then return b1 end
    local len = utf8_lead_len(b1)
    local cp
    if len == 2 then cp = b1 % 0x20
    elseif len == 3 then cp = b1 % 0x10
    elseif len == 4 then cp = b1 % 0x08
    else return b1 end
    for i = 2, len do
        local b = ch:byte(i)
        if not b then break end
        cp = cp * 0x40 + (b % 0x40)
    end
    return cp
end

function utf8_encode(cp)
    if cp < 0x80 then
        return string.char(cp)
    elseif cp < 0x800 then
        return string.char(0xC0 + math.floor(cp / 0x40), 0x80 + cp % 0x40)
    elseif cp < 0x10000 then
        return string.char(0xE0 + math.floor(cp / 0x1000),
            0x80 + math.floor(cp / 0x40) % 0x40, 0x80 + cp % 0x40)
    else
        return string.char(0xF0 + math.floor(cp / 0x40000),
            0x80 + math.floor(cp / 0x1000) % 0x40,
            0x80 + math.floor(cp / 0x40) % 0x40, 0x80 + cp % 0x40)
    end
end

function utf8_lower_char(ch)
    local cp = utf8_codepoint(ch)
    if cp >= 0x410 and cp <= 0x42F then cp = cp + 0x20
    elseif cp == 0x401 then cp = 0x451
    elseif cp >= 0x41 and cp <= 0x5A then cp = cp + 0x20 end
    return utf8_encode(cp)
end

function utf8_is_upper(ch)
    local cp = utf8_codepoint(ch)
    return (cp >= 0x410 and cp <= 0x42F) or cp == 0x401 or (cp >= 0x41 and cp <= 0x5A)
end

function charsEquivalent(a, b)
    if a == b then return true end
    local la, lb = utf8_lower_char(a), utf8_lower_char(b)
    if (la == u8"ё" and lb == u8"е") or (la == u8"е" and lb == u8"ё") then return true end
    return false
end

local RU_KB_ROWS = {
    {
        { label = u8"Ё", code = 0xC0, w = 1, finger = 1 },
        { label = "1", code = 0x31, w = 1, finger = 1 },
        { label = "2", code = 0x32, w = 1, finger = 2 },
        { label = "3", code = 0x33, w = 1, finger = 3 },
        { label = "4", code = 0x34, w = 1, finger = 4 },
        { label = "5", code = 0x35, w = 1, finger = 4 },
        { label = "6", code = 0x36, w = 1, finger = 5 },
        { label = "7", code = 0x37, w = 1, finger = 5 },
        { label = "8", code = 0x38, w = 1, finger = 6 },
        { label = "9", code = 0x39, w = 1, finger = 7 },
        { label = "0", code = 0x30, w = 1, finger = 8 },
        { label = "-", code = 0xBD, w = 1, finger = 8 },
        { label = "=", code = 0xBB, w = 1, finger = 8 },
        { label = "Backspace", code = 0x08, w = 2.4, finger = 8 },
    },
    {
        { label = u8"Tab", code = 0x09, w = 1.5, finger = 1 },
        { label = u8"Й", code = 0x51, w = 1, finger = 1 },
        { label = u8"Ц", code = 0x57, w = 1, finger = 2 },
        { label = u8"У", code = 0x45, w = 1, finger = 3 },
        { label = u8"К", code = 0x52, w = 1, finger = 4 },
        { label = u8"Е", code = 0x54, w = 1, finger = 4 },
        { label = u8"Н", code = 0x59, w = 1, finger = 5 },
        { label = u8"Г", code = 0x55, w = 1, finger = 5 },
        { label = u8"Ш", code = 0x49, w = 1, finger = 6 },
        { label = u8"Щ", code = 0x4F, w = 1, finger = 7 },
        { label = u8"З", code = 0x50, w = 1, finger = 8 },
        { label = u8"Х", code = 0xDB, w = 1, finger = 8 },
        { label = u8"Ъ", code = 0xDD, w = 1, finger = 8 },
        { label = "\\", code = 0xDC, w = 1.3, finger = 8 },
    },
    {
        { label = u8"Caps Lock", code = 0x14, w = 1.9, finger = 1 },
        { label = u8"Ф", code = 0x41, w = 1, finger = 1 },
        { label = u8"Ы", code = 0x53, w = 1, finger = 2 },
        { label = u8"В", code = 0x44, w = 1, finger = 3 },
        { label = u8"А", code = 0x46, w = 1, finger = 4, homeBump = true },
        { label = u8"П", code = 0x47, w = 1, finger = 4 },
        { label = u8"Р", code = 0x48, w = 1, finger = 5 },
        { label = u8"О", code = 0x4A, w = 1, finger = 5, homeBump = true },
        { label = u8"Л", code = 0x4B, w = 1, finger = 6 },
        { label = u8"Д", code = 0x4C, w = 1, finger = 7 },
        { label = u8"Ж", code = 0xBA, w = 1, finger = 8 },
        { label = u8"Э", code = 0xDE, w = 1, finger = 8 },
        { label = u8"Enter", code = 0x0D, w = 1.9, finger = 8 },
    },
    {
        { label = u8"Shift", code = 0x10, w = 2.4, finger = 1 },
        { label = u8"Я", code = 0x5A, w = 1, finger = 1 },
        { label = u8"Ч", code = 0x58, w = 1, finger = 2 },
        { label = u8"С", code = 0x43, w = 1, finger = 3 },
        { label = u8"М", code = 0x56, w = 1, finger = 4 },
        { label = u8"И", code = 0x42, w = 1, finger = 4 },
        { label = u8"Т", code = 0x4E, w = 1, finger = 5 },
        { label = u8"Ь", code = 0x4D, w = 1, finger = 5 },
        { label = u8"Б", code = 0xBC, w = 1, finger = 6 },
        { label = u8"Ю", code = 0xBE, w = 1, finger = 7 },
        { label = ".", code = 0xBF, w = 1, finger = 8 },
        { label = u8"Shift", code = 0x10, w = 2.4, finger = 8 },
    },
    {
        { label = u8"Ctrl", code = 0x11, w = 1.3, finger = 1 },
        { label = u8"Win", code = 0x5B, w = 1.1, finger = 1 },
        { label = u8"Alt", code = 0x12, w = 1.1, finger = 1 },
        { label = u8"Пробел", code = 0x20, w = 6.2, finger = 9 },
        { label = u8"Alt", code = 0x12, w = 1.1, finger = 1 },
        { label = u8"Win", code = 0x5B, w = 1.1, finger = 1 },
        { label = u8"Menu", code = 0x5D, w = 1.1, finger = 1 },
        { label = u8"Ctrl", code = 0x11, w = 1.3, finger = 8 },
    },
}

local EN_KB_ROWS = {
    {
        { label = "`", code = 0xC0, w = 1, finger = 1 },
        { label = "1", code = 0x31, w = 1, finger = 1 },
        { label = "2", code = 0x32, w = 1, finger = 2 },
        { label = "3", code = 0x33, w = 1, finger = 3 },
        { label = "4", code = 0x34, w = 1, finger = 4 },
        { label = "5", code = 0x35, w = 1, finger = 4 },
        { label = "6", code = 0x36, w = 1, finger = 5 },
        { label = "7", code = 0x37, w = 1, finger = 5 },
        { label = "8", code = 0x38, w = 1, finger = 6 },
        { label = "9", code = 0x39, w = 1, finger = 7 },
        { label = "0", code = 0x30, w = 1, finger = 8 },
        { label = "-", code = 0xBD, w = 1, finger = 8 },
        { label = "=", code = 0xBB, w = 1, finger = 8 },
        { label = "Backspace", code = 0x08, w = 2.4, finger = 8 },
    },
    {
        { label = "Tab", code = 0x09, w = 1.5, finger = 1 },
        { label = "Q", code = 0x51, w = 1, finger = 1 },
        { label = "W", code = 0x57, w = 1, finger = 2 },
        { label = "E", code = 0x45, w = 1, finger = 3 },
        { label = "R", code = 0x52, w = 1, finger = 4 },
        { label = "T", code = 0x54, w = 1, finger = 4 },
        { label = "Y", code = 0x59, w = 1, finger = 5 },
        { label = "U", code = 0x55, w = 1, finger = 5 },
        { label = "I", code = 0x49, w = 1, finger = 6 },
        { label = "O", code = 0x4F, w = 1, finger = 7 },
        { label = "P", code = 0x50, w = 1, finger = 8 },
        { label = "[", code = 0xDB, w = 1, finger = 8 },
        { label = "]", code = 0xDD, w = 1, finger = 8 },
        { label = "\\", code = 0xDC, w = 1.3, finger = 8 },
    },
    {
        { label = "Caps Lock", code = 0x14, w = 1.9, finger = 1 },
        { label = "A", code = 0x41, w = 1, finger = 1 },
        { label = "S", code = 0x53, w = 1, finger = 2 },
        { label = "D", code = 0x44, w = 1, finger = 3 },
        { label = "F", code = 0x46, w = 1, finger = 4, homeBump = true },
        { label = "G", code = 0x47, w = 1, finger = 4 },
        { label = "H", code = 0x48, w = 1, finger = 5 },
        { label = "J", code = 0x4A, w = 1, finger = 5, homeBump = true },
        { label = "K", code = 0x4B, w = 1, finger = 6 },
        { label = "L", code = 0x4C, w = 1, finger = 7 },
        { label = ";", code = 0xBA, w = 1, finger = 8 },
        { label = "'", code = 0xDE, w = 1, finger = 8 },
        { label = "Enter", code = 0x0D, w = 1.9, finger = 8 },
    },
    {
        { label = "Shift", code = 0x10, w = 2.4, finger = 1 },
        { label = "Z", code = 0x5A, w = 1, finger = 1 },
        { label = "X", code = 0x58, w = 1, finger = 2 },
        { label = "C", code = 0x43, w = 1, finger = 3 },
        { label = "V", code = 0x56, w = 1, finger = 4 },
        { label = "B", code = 0x42, w = 1, finger = 4 },
        { label = "N", code = 0x4E, w = 1, finger = 5 },
        { label = "M", code = 0x4D, w = 1, finger = 5 },
        { label = ",", code = 0xBC, w = 1, finger = 6 },
        { label = ".", code = 0xBE, w = 1, finger = 7 },
        { label = "/", code = 0xBF, w = 1, finger = 8 },
        { label = "Shift", code = 0x10, w = 2.4, finger = 8 },
    },
    {
        { label = "Ctrl", code = 0x11, w = 1.3, finger = 1 },
        { label = "Win", code = 0x5B, w = 1.1, finger = 1 },
        { label = "Alt", code = 0x12, w = 1.1, finger = 1 },
        { label = u8"Пробел", code = 0x20, w = 6.2, finger = 9 },
        { label = "Alt", code = 0x12, w = 1.1, finger = 1 },
        { label = "Win", code = 0x5B, w = 1.1, finger = 1 },
        { label = "Menu", code = 0x5D, w = 1.1, finger = 1 },
        { label = "Ctrl", code = 0x11, w = 1.3, finger = 8 },
    },
}

function getKeyboardRows()
    return ui.layout == "en" and EN_KB_ROWS or RU_KB_ROWS
end

function buildCharMap(rows)
    local map = {}
    for _, row in ipairs(rows) do
        for _, key in ipairs(row) do
            if #key.label > 0 and #utf8_chars(key.label) == 1 then
                local lower = utf8_lower_char(key.label)
                if not map[lower] then map[lower] = key end
            end
        end
    end
    map[" "] = { code = 0x20, finger = 9, label = u8"Пробел" }
    return map
end

local RU_CHAR_TO_KEY = buildCharMap(RU_KB_ROWS)
local EN_CHAR_TO_KEY = buildCharMap(EN_KB_ROWS)
local BACKSPACE_KEY = RU_KB_ROWS[1][14]

function getActiveCharMap()
    return ui.layout == "en" and EN_CHAR_TO_KEY or RU_CHAR_TO_KEY
end

local KEY_HINT = {
    ru = {
        ["!"] = { code = 0x31, shift = true }, [string.char(34)] = { code = 0x32, shift = true },
        [u8"№"] = { code = 0x33, shift = true }, [";"] = { code = 0x34, shift = true },
        ["%"] = { code = 0x35, shift = true }, [":"] = { code = 0x36, shift = true },
        ["?"] = { code = 0x37, shift = true }, ["*"] = { code = 0x38, shift = true },
        ["("] = { code = 0x39, shift = true }, [")"] = { code = 0x30, shift = true },
        ["_"] = { code = 0xBD, shift = true }, ["+"] = { code = 0xBB, shift = true },


        [","] = { code = 0xBF, shift = true }, ["."] = { code = 0xBF, shift = false },
        ["\t"] = { code = 0x09, shift = false }, ["\n"] = { code = 0x0D, shift = false },
    },
    en = {
        ["~"] = { code = 0xC0, shift = true }, ["!"] = { code = 0x31, shift = true },
        ["@"] = { code = 0x32, shift = true }, ["#"] = { code = 0x33, shift = true },
        ["$"] = { code = 0x34, shift = true }, ["%"] = { code = 0x35, shift = true },
        ["^"] = { code = 0x36, shift = true }, ["&"] = { code = 0x37, shift = true },
        ["*"] = { code = 0x38, shift = true }, ["("] = { code = 0x39, shift = true },
        [")"] = { code = 0x30, shift = true }, ["_"] = { code = 0xBD, shift = true },
        ["+"] = { code = 0xBB, shift = true }, ["{"] = { code = 0xDB, shift = true },
        ["}"] = { code = 0xDD, shift = true }, ["|"] = { code = 0xDC, shift = true },
        [":"] = { code = 0xBA, shift = true }, [string.char(34)] = { code = 0xDE, shift = true },
        ["<"] = { code = 0xBC, shift = true }, [">"] = { code = 0xBE, shift = true },
        ["?"] = { code = 0xBF, shift = true },
        ["\t"] = { code = 0x09, shift = false }, ["\n"] = { code = 0x0D, shift = false },
    },
}

local CLAVA_TEXT_MIN_CHARS = 200
local CLAVA_TEXT_MAX_CHARS = 650
local CLAVA_INPUT_BUFFER_BYTES = 8192

local function buildPlayableCharSet(rows, hints)
    local set = {}
    for _, row in ipairs(rows or {}) do
        for _, key in ipairs(row or {}) do
            if type(key.label) == "string" then
                local chars = utf8_chars(key.label)
                if #chars == 1 then
                    set[chars[1]] = true
                    set[utf8_lower_char(chars[1])] = true
                end
            end
        end
    end
    for ch in pairs(hints or {}) do set[ch] = true end
    set[" "] = true
    return set
end

local CLAVA_PLAYABLE_SET = {
    ru = buildPlayableCharSet(RU_KB_ROWS, KEY_HINT.ru),
    en = buildPlayableCharSet(EN_KB_ROWS, KEY_HINT.en),
}

local CLAVA_ACCENT_MAP = {
    [u8"a"]="a", [u8"a"]="a", [u8"a"]="a", [u8"a"]="a", [u8"a"]="a", [u8"a"]="a",
    [u8"A"]="A", [u8"A"]="A", [u8"A"]="A", [u8"A"]="A", [u8"A"]="A", [u8"A"]="A",
    [u8"c"]="c", [u8"C"]="C", [u8"e"]="e", [u8"e"]="e", [u8"e"]="e", [u8"e"]="e",
    [u8"E"]="E", [u8"E"]="E", [u8"E"]="E", [u8"E"]="E", [u8"i"]="i", [u8"i"]="i",
    [u8"i"]="i", [u8"i"]="i", [u8"I"]="I", [u8"I"]="I", [u8"I"]="I", [u8"I"]="I",
    [u8"n"]="n", [u8"N"]="N", [u8"o"]="o", [u8"o"]="o", [u8"o"]="o", [u8"o"]="o", [u8"o"]="o",
    [u8"O"]="O", [u8"O"]="O", [u8"O"]="O", [u8"O"]="O", [u8"O"]="O", [u8"u"]="u", [u8"u"]="u",
    [u8"u"]="u", [u8"u"]="u", [u8"U"]="U", [u8"U"]="U", [u8"U"]="U", [u8"U"]="U",
    [u8"y"]="y", [u8"y"]="y", [u8"Y"]="Y", [u8"Y"]="Y",
    [u8"?"]="ae", [u8"?"]="AE", [u8"?"]="oe", [u8"?"]="OE", [u8"?"]="ss",
}

local CLAVA_UNSUPPORTED_REPLACEMENTS = {
    [string.char(226, 128, 148)] = string.char(45),
    [string.char(226, 128, 147)] = string.char(45),
    [string.char(226, 128, 149)] = string.char(45),
    [string.char(226, 128, 145)] = string.char(45),
    [string.char(226, 136, 146)] = string.char(45),
    [string.char(226, 128, 146)] = string.char(45),
    [string.char(226, 128, 166)] = string.char(46, 46, 46),
    [string.char(194, 183)] = string.char(46),
    [string.char(226, 128, 162)] = string.char(45),
    [string.char(195, 151)] = string.char(120),
    [string.char(195, 183)] = string.char(47),
    [string.char(194, 177)] = string.char(43, 47, 45),
    [string.char(194, 171)] = string.char(34),
    [string.char(194, 187)] = string.char(34),
    [string.char(226, 128, 156)] = string.char(34),
    [string.char(226, 128, 157)] = string.char(34),
    [string.char(226, 128, 158)] = string.char(34),
    [string.char(226, 128, 159)] = string.char(34),
    [string.char(226, 128, 185)] = string.char(34),
    [string.char(226, 128, 186)] = string.char(34),
    [string.char(226, 128, 153)] = string.char(39),
    [string.char(226, 128, 152)] = string.char(39),
    [string.char(226, 128, 154)] = string.char(39),
    [string.char(226, 128, 155)] = string.char(39),
    [string.char(194, 160)] = string.char(32),
    [string.char(226, 128, 135)] = string.char(32),
    [string.char(226, 128, 175)] = string.char(32),
    [string.char(226, 128, 137)] = string.char(32),
    [string.char(226, 128, 139)] = string.char(),
    [string.char(226, 128, 140)] = string.char(),
    [string.char(226, 128, 141)] = string.char(),
    [string.char(239, 187, 191)] = string.char(),
}

function clavaNormalizePlayableText(text, layout)
    text = tostring(text or "")
    layout = (layout == "en") and "en" or "ru"

    text = text:gsub("[\r\n\t]+", " ")
    text = text:gsub("%s+", " ")

    for from, to in pairs(CLAVA_UNSUPPORTED_REPLACEMENTS) do
        text = text:gsub(from, to)
    end
    for from, to in pairs(CLAVA_ACCENT_MAP) do
        text = text:gsub(from, to)
    end


    text = text:gsub("чердакa", "чердака")
    text = text:gsub("le roi de Prusse", "прусский король")
    text = text:gsub("m%-lle Bourienne", "мадемуазель Бурьен")

    local allowed = CLAVA_PLAYABLE_SET[layout]
    local out = {}
    for _, ch in ipairs(utf8_chars(text)) do
        if allowed[ch] then
            out[#out + 1] = ch
        else


            out[#out + 1] = " "
        end
    end

    text = table.concat(out):gsub("%s+", " "):gsub("^%s+", ""):gsub("%s+$", "")
    return text
end

function clavaTextLength(text)
    return #utf8_chars(text or "")
end

function clavaTextFitsPlayableLimits(text, minLen, maxLen)
    local n = clavaTextLength(text)
    return n >= (minLen or CLAVA_TEXT_MIN_CHARS) and n <= (maxLen or CLAVA_TEXT_MAX_CHARS)
end

function clavaTextFitsBuffer(text)
    return #(tostring(text or "")) + 1 <= CLAVA_INPUT_BUFFER_BYTES
end

function clavaNormalizeSourceItem(item, layout)
    if not item then return nil end
    local out = {
        text = clavaNormalizePlayableText(item.text or "", layout),
        author = clavaNormalizePlayableText(item.author or "", layout),
        book = clavaNormalizePlayableText(item.book or "", layout),
        genre = clavaNormalizePlayableText(item.genre or "", layout),
    }
    return out
end

function setLayout(layout)
    if layout ~= "en" then layout = "ru" end
    ui.layout = layout
end

function toggleLayout()
    setLayout(ui.layout == "en" and "ru" or "en")
end

local function detectSystemKeyboardLayout()
    local ok, layout = pcall(function()
        local hwnd = ffi.C.GetForegroundWindow()
        if hwnd == nil then return nil end
        local threadId = ffi.C.GetWindowThreadProcessId(hwnd, nil)
        if not threadId or threadId == 0 then return nil end
        local hkl = tonumber(ffi.C.GetKeyboardLayout(threadId))
        if not hkl then return nil end
        local langId = hkl % 0x10000
        local primary = langId % 0x400
        if primary == 0x09 then return "en" end
        if primary == 0x19 then return "ru" end
        return nil
    end)
    return ok and layout or nil
end

function pollLayoutSwitch()



    local detected = detectSystemKeyboardLayout()
    if detected then
        ui.layout = detected
    end

    local okShift, shift = pcall(function()
        return ffi.C.GetAsyncKeyState(0x10) < 0
    end)
    local okAlt, alt = pcall(function()
        return ffi.C.GetAsyncKeyState(0x12) < 0
    end)
    ui.layoutSwitchLatch = (okShift and okAlt and shift and alt) or false
end

local FINGER_COLOR = {
    [0] = { 0.66, 0.66, 0.66 },
    [1] = { 241/255, 207/255, 207/255 },
    [2] = { 241/255, 239/255, 207/255 },
    [3] = { 213/255, 241/255, 207/255 },
    [4] = { 207/255, 238/255, 241/255 },
    [5] = { 240/255, 206/255, 240/255 },
    [6] = { 213/255, 241/255, 207/255 },
    [7] = { 241/255, 239/255, 207/255 },
    [8] = { 241/255, 207/255, 207/255 },
    [9] = { 220/255, 207/255, 241/255 },
}

local FINGER_PRESSED_COLOR = {
    [0] = { 0.45, 0.45, 0.45 },
    [1] = { 199/255, 112/255, 112/255 },
    [2] = { 198/255, 189/255, 103/255 },
    [3] = { 126/255, 200/255, 111/255 },
    [4] = { 103/255, 189/255, 198/255 },
    [5] = { 198/255, 103/255, 198/255 },
    [6] = { 126/255, 200/255, 111/255 },
    [7] = { 198/255, 189/255, 103/255 },
    [8] = { 199/255, 112/255, 112/255 },
    [9] = { 140/255, 103/255, 198/255 },
}

CLAVA_SOURCE_RU = {
    {text=u8"Следователь Марков третий день изучал бухгалтерские книги завода и никак не мог найти ошибку, о которой говорил директор. Только вечером, сверяя даты отпусков, он заметил, что кассир числился на рабочем месте в день, когда официально находился в больнице. Марков закрыл папку и решил, что утром стоит начать разговор именно с этого вопроса.", author=u8"Игорь Северцев", book=u8"Тихая бухгалтерия", genre=u8"Детектив"},
    {text=u8"Экспертиза почерка заняла два часа, и криминалист вышел из кабинета с разочарованным лицом: подпись на завещании совпадала с образцами лишь наполовину. Он разложил документы на столе и заметил, что нажим пера менялся ровно посередине текста, будто писавший на минуту останавливался и передавал ручку другому человеку.", author=u8"Игорь Северцев", book=u8"Тихая бухгалтерия", genre=u8"Детектив"},
    {text=u8"Дежурный на посту у моста клялся, что после полуночи никто не проезжал, но камера на въезде зафиксировала силуэт грузовика без номеров. Инспектор пересмотрел запись трижды и понял, что тень появляется на пленке ровно за минуту до того, как гаснет уличный фонарь, а значит, кто-то заранее знал расписание освещения.", author=u8"Ольга Ремез", book=u8"Дело о трех фонарях", genre=u8"Детектив"},
    {text=u8"В номере гостиницы не нашли ни одной личной вещи постояльца, кроме связки ключей от квартиры в другом городе. Портье вспомнил, что мужчина расплатился заранее за месяц вперед, хотя обычно снимал номер на одну ночь. Детектив решил для начала съездить по адресу с той самой связки.", author=u8"Ольга Ремез", book=u8"Дело о трех фонарях", genre=u8"Детектив"},
    {text=u8"Свидетель уверял, что видел подозреваемого на рынке в момент кражи, но билет на автобус в его кармане был пробит на десять минут раньше нужного часа. Лейтенант Соснин молча вернул билет владельцу и попросил вспомнить, во сколько именно тронулась маршрутка, а не смотреть на циферблат станции.", author=u8"Павел Гринько", book=u8"Билет до полудня", genre=u8"Детектив"},
    {text=u8"В архиве страховой компании обнаружили две одинаковые заявки на возмещение ущерба, поданные с разницей в год. Совпадали даже орфографические ошибки в описании происшествия. Аналитик отдела сразу заподозрил, что кто-то просто переписал текст под новую фамилию, не потрудившись изменить детали аварии.", author=u8"Павел Гринько", book=u8"Билет до полудня", genre=u8"Детектив"},
    {text=u8"Сторож склада клялся, что замок был цел, однако товар исчез без следов взлома. Инспектор осмотрел петли двери и заметил свежие царапины на внутренней стороне косяка. Значит, дверь снимали с петель целиком, а потом аккуратно вешали обратно, чтобы замок оставался нетронутым.", author=u8"Марина Углова", book=u8"Склад номер семь", genre=u8"Детектив"},
    {text=u8"Почтальон сообщил, что письмо адресату так и не доставил, потому что дом на указанной улице снесли еще весной. Но штамп на конверте стоял с датой позавчерашнего числа. Отделение связи решило проверить, кто именно принял письмо к отправке под несуществующий адрес.", author=u8"Марина Углова", book=u8"Склад номер семь", genre=u8"Детектив"},
    {text=u8"В музее пропала одна из акварелей, а на ее месте осталась точная копия, отличавшаяся лишь подписью художника в нижнем углу. Реставратор заметил разницу первым, разглядывая холст под лампой. Подделку явно писали в спешке, но кто-то очень хорошо знал технику оригинала.", author=u8"Тимур Ясенев", book=u8"Копия под лампой", genre=u8"Детектив"},
    {text=u8"Диспетчер такси вспомнила заказ на утро понедельника, хотя в компьютерной базе такой записи не было. Она показала следователю черновой блокнот, куда записывала адреса от руки, если система зависала. Именно там нашелся нужный адрес, стертый из электронного журнала кем-то изнутри офиса.", author=u8"Тимур Ясенев", book=u8"Копия под лампой", genre=u8"Детектив"},
    {text=u8"Станция связи на орбите приняла сигнал, который повторялся каждые одиннадцать минут вот уже сорок лет, но никто не мог расшифровать его смысл. Молодой инженер решил наложить запись на карту звездного неба и обнаружил, что интервалы совпадают с периодом вращения планеты, которую еще не нашли ни одним телескопом.", author=u8"Артем Валеев", book=u8"Одиннадцать минут молчания", genre=u8"Научная фантастика"},
    {text=u8"Колонисты второго поколения никогда не видели настоящего дождя, только его имитацию в куполе оранжереи. Когда система впервые дала сбой и вода полилась без предупреждения, дети выбежали наружу и стояли под каплями так долго, что взрослые не решились их звать обратно.", author=u8"Артем Валеев", book=u8"Одиннадцать минут молчания", genre=u8"Научная фантастика"},
    {text=u8"Робот-садовник обслуживал парк уже полвека и помнил имена всех деревьев, посаженных первыми жителями города. Когда последнее из них срубили из-за болезни, машина отказалась выполнять новую команду посадки и целую неделю просто стояла у пустого места, будто ожидая, что дерево вернется.", author=u8"Светлана Корн", book=u8"Сад механической памяти", genre=u8"Научная фантастика"},
    {text=u8"Экипаж грузового корабля обнаружил на борту лишний ящик без маркировки, который не значился ни в одном манифесте. Внутри лежали семена растений, вымерших на Земле два века назад. Никто из команды не мог объяснить, откуда ящик взялся и кто успел погрузить его перед стартом.", author=u8"Светлана Корн", book=u8"Сад механической памяти", genre=u8"Научная фантастика"},
    {text=u8"В подземном городе свет включали строго по расписанию, экономя энергию последнего реактора. Однажды лампы вспыхнули на два часа раньше положенного времени, и жители впервые за годы увидели рассвет через щели вентиляционных шахт, хотя техники клялись, что расписание не меняли.", author=u8"Денис Рогачев", book=u8"Расписание солнца", genre=u8"Научная фантастика"},
    {text=u8"Архив искусственного интеллекта хранил миллиарды человеческих писем, но одно сообщение система помечала как нечитаемое уже триста лет подряд. Инженеры наконец расшифровали файл и обнаружили, что это письмо самому себе, написанное создателем архива в день его запуска.", author=u8"Денис Рогачев", book=u8"Расписание солнца", genre=u8"Научная фантастика"},
    {text=u8"На заброшенной лунной базе нашли журнал наблюдений, обрывающийся на полуслове посреди фразы про странное свечение над кратером. Спасательная экспедиция включила приборы в тот же час суток, что и в записи, и действительно увидела слабое зеленоватое сияние у самого горизонта.", author=u8"Инна Батурина", book=u8"Свечение над кратером", genre=u8"Научная фантастика"},
    {text=u8"Ученые вывели сорт пшеницы, способный расти в почве с высоким содержанием соли, но не учли, что колосья начинают светиться в темноте. Фермеры сначала испугались нового поля, а потом стали специально выключать освещение по вечерам, чтобы посмотреть на бледное сияние над землей.", author=u8"Инна Батурина", book=u8"Свечение над кратером", genre=u8"Научная фантастика"},
    {text=u8"Автопилот межзвездного лайнера отказался выполнять маршрут, проложенный штурманом, и без объяснений увел корабль в сторону от курса. Через два дня пассажиры узнали причину: впереди по расчетной траектории должен был произойти взрыв звезды, о котором наземные обсерватории еще не сообщили.", author=u8"Ярослав Дегтярь", book=u8"Отклонение курса", genre=u8"Научная фантастика"},
    {text=u8"Переселенцы на новой планете назвали местное дерево ложным дубом за сходство коры, хотя оно раз в сто лет меняло форму листьев на нечто похожее на человеческую ладонь. Ботаники так и не решили, стоит ли считать это совпадением или сигналом какой-то давно забытой цивилизации.", author=u8"Ярослав Дегтярь", book=u8"Отклонение курса", genre=u8"Научная фантастика"},
    {text=u8"Осенью тысяча восемьсот двенадцатого года обоз с ранеными растянулся по дороге на добрый десяток верст, и крестьяне соседних деревень выходили к обочине с хлебом и водой, не спрашивая, кто из солдат откуда родом. Полковой лекарь позже вспоминал, что именно эта помощь спасла больше жизней, чем все запасы полевого госпиталя.", author=u8"Всеволод Ланской", book=u8"Дорога на Смоленск", genre=u8"Исторический роман"},
    {text=u8"Купец третьей гильдии Прохор Ильич вел торговые книги мелким убористым почерком и никогда не доверял счетоводам чужие цифры. Когда сгорел склад на пристани, именно эти записи помогли восстановить убытки до последней копейки, и городская управа впервые за много лет назначила ему возмещение убытков без единой проволочки.", author=u8"Всеволод Ланской", book=u8"Дорога на Смоленск", genre=u8"Исторический роман"},
    {text=u8"В осажденной крепости хлеб делили по счету караваев, а не по весу, потому что весы разбились еще в первую неделю обстрела. Комендант распорядился выдавать хлеб детям в первую очередь, и старожилы города потом рассказывали об этом решении своим внукам как о главном чуде той зимы.", author=u8"Аглая Ветрова", book=u8"Хлеб по счету", genre=u8"Исторический роман"},
    {text=u8"Молодой землемер прибыл в уездный город с новыми инструментами и картой, составленной по последним правилам геодезии, но старики упрямо показывали границы полей по памятным камням и старым межам. Спор решился только после того, как обе линии сошлись до последней сажени в одном заброшенном овраге.", author=u8"Аглая Ветрова", book=u8"Хлеб по счету", genre=u8"Исторический роман"},
    {text=u8"После указа о вольных хлебопашцах в деревне долго не могли поверить, что бумага и вправду меняет судьбу человека. Старый Фрол трижды перечитывал грамоту вслух перед сходом, пока наконец не поставил под ней свою неуверенную подпись, впервые в жизни написав собственное имя без посторонней помощи.", author=u8"Родион Шатров", book=u8"Вольная грамота", genre=u8"Исторический роман"},
    {text=u8"Гарнизонный врач вел дневник погоды наравне с историей болезней, полагая, что перемена ветра сказывается на здоровье солдат не меньше, чем скудный паек. Спустя годы его записи оказались единственным подробным источником о климате той местности за целое десятилетие.", author=u8"Родион Шатров", book=u8"Вольная грамота", genre=u8"Исторический роман"},
    {text=u8"Городской архитектор настаивал на широких улицах вопреки желанию купцов сэкономить на мостовой, доказывая, что узкие проезды опасны при пожаре. Через два года именно эти улицы остановили огонь, перекинувшийся с торговых рядов, и совет города признал его правоту публично.", author=u8"Ксения Воробьева", book=u8"Широкие улицы", genre=u8"Исторический роман"},
    {text=u8"Учительница земской школы добивалась открытия библиотеки для крестьянских детей три года подряд, обивая пороги уездного правления с одинаковым упорством. Когда первые книги наконец привезли на телеге, она лично расставляла их по темам, не доверив это дело даже своим помощникам.", author=u8"Ксения Воробьева", book=u8"Широкие улицы", genre=u8"Исторический роман"},
    {text=u8"Полк возвращался из похода поздней осенью, и жители встречали солдат факелами вдоль всей дороги, потому что телеграф принес весть о победе раньше самого полка на два дня. Старики говорили потом, что такого света на памяти их города не видели даже в самые большие праздники.", author=u8"Матвей Осокин", book=u8"Факелы у дороги", genre=u8"Исторический роман"},
    {text=u8"Судебный пристав описывал имущество разорившегося помещика с явной неохотой, зная его еще ребенком, и нарочно медлил с описью самых ветхих вещей, давая семье время собрать их тайком. Соседи заметили эту медлительность, но никто не подал жалобы вышестоящему начальству.", author=u8"Матвей Осокин", book=u8"Факелы у дороги", genre=u8"Исторический роман"},
    {text=u8"Мать не разговаривала с сыном три года после его отъезда в другой город, но каждую неделю писала письма и складывала их в ящик комода, так и не отправив ни одного. Когда он наконец вернулся сам, без предупреждения, она молча протянула ему всю пачку писем вместо приветствия.", author=u8"Наталья Гречко", book=u8"Ящик комода", genre=u8"Драма"},
    {text=u8"Врач сообщил семье диагноз спокойным голосом, но руки его дрожали сильнее обычного, потому что пациентом был его собственный учитель, тот самый профессор, что тридцать лет назад принимал у него первый экзамен по анатомии. Они оба это понимали и оба промолчали об этом до конца разговора.", author=u8"Наталья Гречко", book=u8"Ящик комода", genre=u8"Драма"},
    {text=u8"Отец учил дочь водить машину на пустой парковке по воскресеньям, хотя у него самого давно не было прав из-за болезни глаз. Он сидел рядом, командовал поворотами по памяти и ни разу не признался, что видит дорогу перед собой лишь размытым пятном света.", author=u8"Семен Артюхов", book=u8"Воскресная парковка", genre=u8"Драма"},
    {text=u8"Сестры не виделись пятнадцать лет из-за старой ссоры, причину которой обе уже плохо помнили. Встретившись на похоронах общей тети, они простояли рядом весь вечер, обмениваясь короткими фразами о погоде, и только у ворот кладбища одна из них наконец взяла другую за руку.", author=u8"Семен Артюхов", book=u8"Воскресная парковка", genre=u8"Драма"},
    {text=u8"Учитель музыки продолжал вести уроки в пустом классе даже после того, как школу закрыли на ремонт, потому что единственная ученица, слепая девочка из соседнего дома, приходила туда каждый вторник, не зная о закрытии. Директор так и не решился прервать эти занятия официальным приказом.", author=u8"Полина Загорская", book=u8"Пустой класс", genre=u8"Драма"},
    {text=u8"Бывшие соседи по коммунальной квартире встретились случайно через двадцать лет в очереди на почте и сначала не узнали друг друга, а потом проговорили два часа, вспоминая общую кухню, скандалы из-за очереди в ванную и единственный на весь этаж телефон в коридоре.", author=u8"Полина Загорская", book=u8"Пустой класс", genre=u8"Драма"},
    {text=u8"Молодой актер репетировал роль умирающего отца, хотя его собственный отец лежал в больнице этажом ниже театра. После каждой репетиции он поднимался к нему в палату и читал те же самые реплики уже не для зрителей, а просто чтобы услышать в ответ хоть слово.", author=u8"Григорий Плахов", book=u8"Этажом ниже", genre=u8"Драма"},
    {text=u8"Почтальонша разносила письма по одному и тому же маршруту тридцать два года и знала имена жильцов лучше участкового врача. Когда почту заменили электронными уведомлениями, она еще долго ходила по привычному кругу, просто чтобы поздороваться с теми, кто выходил на крыльцо.", author=u8"Григорий Плахов", book=u8"Этажом ниже", genre=u8"Драма"},
    {text=u8"Дед рассказывал внуку одну и ту же историю про фронтовую переправу каждый год в один и тот же день, и каждый раз добавлял новую деталь, будто вспоминал ее только сейчас. Внук записал все версии в отдельную тетрадь, так и не решив, какая из них ближе к правде.", author=u8"Ирина Соловьева", book=u8"Одна и та же переправа", genre=u8"Драма"},
    {text=u8"Женщина вернулась в родной город спустя тридцать лет, чтобы продать дом покойных родителей, но провела в нем целую неделю, разбирая старые фотографии вместо того, чтобы звонить риелтору. К концу недели она решила дом не продавать, хотя жить в нем тоже не собиралась.", author=u8"Ирина Соловьева", book=u8"Одна и та же переправа", genre=u8"Драма"},
    {text=u8"Экспедиция вышла к перевалу на два дня позже графика из-за непогоды, и проводник настоял на ночевке в старой пастушьей хижине вместо продолжения пути в темноте. Утром выяснилось, что именно эта задержка спасла группу от схода лавины, случившегося ровно на том участке тропы, который они не успели пройти накануне.", author=u8"Богдан Ключевский", book=u8"Хижина у перевала", genre=u8"Приключения"},
    {text=u8"Капитан речного парохода знал каждую отмель на своем участке реки наизусть, но новый лоцман настоял на смене курса из-за показаний свежей карты. Судно село на мель именно там, где старик предупреждал не сворачивать, и с тех пор команда слушала его советы без единого возражения.", author=u8"Богдан Ключевский", book=u8"Хижина у перевала", genre=u8"Приключения"},
    {text=u8"Группа спелеологов обнаружила в дальнем зале пещеры наскальные рисунки, которых не было ни в одном каталоге исследованных полостей региона. Пришлось прокладывать новый маршрут через узкий лаз, названный впоследствии в честь самого маленького участника экспедиции, единственного, кто смог туда протиснуться.", author=u8"Ярина Костенко", book=u8"Зал без имени", genre=u8"Приключения"},
    {text=u8"Охотники за метеоритами шли по следу упавшего камня три недели, ориентируясь по показаниям очевидцев из разных деревень. Найденный в итоге осколок оказался меньше ожидаемого, но именно его химический состав заинтересовал ученых больше, чем любая крупная находка за последние годы.", author=u8"Ярина Костенко", book=u8"Зал без имени", genre=u8"Приключения"},
    {text=u8"Команда яхты попала в штиль посреди пролива и провела на воде почти неделю, экономя пресную воду по строгому графику. Капитан вел судовой журнал с подчеркнутым спокойствием, хотя позже признавался, что именно эта запись давалась ему тяжелее всех предыдущих плаваний вместе взятых.", author=u8"Аркадий Немов", book=u8"Неделя без ветра", genre=u8"Приключения"},
    {text=u8"Проводник горного маршрута никогда не рассказывал туристам про заброшенную штольню в стороне от тропы, опасаясь несчастных случаев, но однажды сам привел туда группу, узнав, что вход собираются взорвать при разработке карьера. Он хотел, чтобы кто-то еще увидел это место, пока оно существует.", author=u8"Аркадий Немов", book=u8"Неделя без ветра", genre=u8"Приключения"},
    {text=u8"Дайверы искали затонувшее судно по старым портовым записям, где координаты были указаны с явной ошибкой в градусах. После третьей неудачной попытки один из них предложил проверить журнал наблюдений соседнего маяка, и именно там нашлась верная поправка к курсу корабля.", author=u8"Устин Бережной", book=u8"Поправка к курсу", genre=u8"Приключения"},
    {text=u8"Альпинисты решили штурмовать вершину раньше рассвета, чтобы успеть спуститься до дневной жары, но потеряли час из-за сломанного крепления рюкзака. Этот час оказался решающим: именно тогда облака разошлись ровно настолько, чтобы показать безопасный путь через ледовый разлом.", author=u8"Устин Бережной", book=u8"Поправка к курсу", genre=u8"Приключения"},
    {text=u8"Путешественник пересек пустыню с караваном верблюдов, полагаясь на старые звездные карты вместо современного навигатора, который сломался в первую же ночь. К удивлению спутников, старый способ оказался точнее: караван вышел к колодцу с разницей всего в несколько сотен метров.", author=u8"Заряна Митрохина", book=u8"Старые звездные карты", genre=u8"Приключения"},
    {text=u8"Речные сплавщики выбрали опасный порог вместо длинного обходного пути, доверившись местному рыбаку, который знал реку с детства. Порог действительно оказался проходимым в это время года, и группа сэкономила почти два дня похода, о чем потом жалели все, кроме промокшего насквозь фотографа.", author=u8"Заряна Митрохина", book=u8"Старые звездные карты", genre=u8"Приключения"},
    {text=u8"Заведующий гаражным кооперативом составил расписание дежурств настолько подробное, что включил в него даже время на чаепитие, но забыл указать, кто именно должен открывать ворота по утрам. В результате первую неделю ворота открывал сосед с соседней улицы, просто потому что вставал раньше всех.", author=u8"Аполлинарий Смехов", book=u8"Расписание дежурств", genre=u8"Юмористическая проза"},
    {text=u8"Комиссия по благоустройству двора спорила о цвете новой лавочки дольше, чем плотник строил саму лавочку. К моменту, когда наконец выбрали оттенок зеленого, лавочка уже успела выцвести на солнце и приобрести ровно тот цвет, который все дружно отвергли на первом заседании.", author=u8"Аполлинарий Смехов", book=u8"Расписание дежурств", genre=u8"Юмористическая проза"},
    {text=u8"Начальник отдела требовал от сотрудников краткости в отчетах и разослал циркуляр объемом в семь страниц с объяснением, как правильно писать коротко. Никто из подчиненных не решился указать на очевидное противоречие, и следующие отчеты стали еще длиннее прежних.", author=u8"Феликс Бурлаков", book=u8"Циркуляр о краткости", genre=u8"Юмористическая проза"},
    {text=u8"Дачники соседних участков десять лет судились из-за границы забора, передвинутой на полметра еще до их рождения. Когда старая тяжба наконец завершилась мировым соглашением, оказалось, что оба забора давно сгнили и требуют полной замены, о чем стороны немедленно поссорились снова.", author=u8"Феликс Бурлаков", book=u8"Циркуляр о краткости", genre=u8"Юмористическая проза"},
    {text=u8"Городская библиотека ввела строгий штраф за просроченные книги, но самым злостным должником оказался директор той же библиотеки, задолжавший читальному залу три тома собственных методических указаний. Коллеги вежливо намекали на проблему целый год, прежде чем он наконец вернул книги сам.", author=u8"Регина Пчелкина", book=u8"Должник методкабинета", genre=u8"Юмористическая проза"},
    {text=u8"На собрании жильцов обсуждали установку домофона так бурно, что забыли проголосовать за сам вопрос, ради которого собрались. Протокол собрания получился длиннее устава дома, а домофон в итоге поставили только через год, когда тема всплыла случайно на совсем другом заседании.", author=u8"Регина Пчелкина", book=u8"Должник методкабинета", genre=u8"Юмористическая проза"},
    {text=u8"Молодой стажер решил произвести впечатление и переписал инструкцию по технике безопасности более строгим языком, добавив десяток новых пунктов. Через неделю выяснилось, что по его версии инструкции нельзя было даже войти в собственный кабинет без письменного разрешения троих начальников.", author=u8"Кузьма Веселов", book=u8"Три подписи на дверь", genre=u8"Юмористическая проза"},
    {text=u8"Ветеринар городской клиники завел отдельную тетрадь для жалоб владельцев котов на характер их питомцев, полагая это полезной статистикой. За год тетрадь заполнилась настолько похожими записями, что он в шутку предложил печатать типовой бланк с одним и тем же текстом жалобы.", author=u8"Кузьма Веселов", book=u8"Три подписи на дверь", genre=u8"Юмористическая проза"},
    {text=u8"Экскурсовод краеведческого музея так увлекся легендой о кладе под старой мельницей, что туристы начали копать землю прямо на экскурсии лопаткой, одолженной у сторожа. Клад, разумеется, не нашли, зато сторож получил неожиданно вскопанную грядку под будущую рассаду.", author=u8"Аглая Пересветова", book=u8"Грядка вместо клада", genre=u8"Юмористическая проза"},
    {text=u8"Автор районной газеты годами вел рубрику советов огородникам, хотя сам ни разу не сажал ничего сложнее лука на подоконнике. Читатели присылали настолько благодарные письма, что редактор так и не решился раскрыть эту маленькую тайну и закрыть многолетний обман.", author=u8"Аглая Пересветова", book=u8"Грядка вместо клада", genre=u8"Юмористическая проза"},
    {text=u8"В доме на окраине каждую зиму промерзало одно и то же окно, хотя стеклопакет меняли уже трижды. Новый хозяин решил проверить старые чертежи здания и обнаружил, что именно за этой стеной когда-то стояла печь, которую разобрали при перестройке, оставив на ее месте только холодный сквозняк памяти.", author=u8"Лукерья Ставрова", book=u8"Холодное окно", genre=u8"Мистическая проза"},
    {text=u8"Смотритель маяка вел журнал наблюдений сорок лет и ни разу не пропустил запись, кроме одной ночи, когда страница осталась совершенно пустой. В тот вечер, как выяснилось позже, в проливе затонуло судно, о котором смотритель никогда никому не рассказывал, хотя явно что-то видел с башни.", author=u8"Лукерья Ставрова", book=u8"Холодное окно", genre=u8"Мистическая проза"},
    {text=u8"Часовщик из маленького городка чинил старинные часы с кукушкой, доставшиеся заказчице от прабабки, и заметил, что птица начинает куковать ровно в момент, когда в доме кто-то произносит имя прежней хозяйки. Он не стал упоминать об этом наблюдении в квитанции о ремонте.", author=u8"Аристарх Половцев", book=u8"Кукушка и имя", genre=u8"Мистическая проза"},
    {text=u8"На чердаке заброшенной усадьбы нашли сундук с письмами, адресованными человеку, который родился спустя двадцать лет после того, как эти письма были написаны. Почерк на конвертах не совпадал ни с одним из известных жильцов дома, и местный архивариус так и не смог установить автора.", author=u8"Аристарх Половцев", book=u8"Кукушка и имя", genre=u8"Мистическая проза"},
    {text=u8"Рыбаки прибрежной деревни избегали одной бухты после заката, ссылаясь на давнюю историю о корабле, потерявшемся там во время шторма без единого выжившего. Молодой моряк не поверил в суеверие и однажды остался там на ночь, но наутро отказался объяснять, почему его сеть оказалась порвана в клочья.", author=u8"Флориана Дегтярева", book=u8"Бухта без имени", genre=u8"Мистическая проза"},
    {text=u8"Библиотекарь заметила, что одна книга на дальней полке всегда стоит чуть иначе, чем остальные, независимо от того, как часто ее переставляют. Однажды она решила проследить за полкой ночью через камеру наблюдения, но запись за ту ночь оказалась полностью стерта неизвестной ошибкой системы.", author=u8"Флориана Дегтярева", book=u8"Бухта без имени", genre=u8"Мистическая проза"},
    {text=u8"В старой деревне колодец считался пересохшим уже полвека, однако каждую весну на его дне появлялась свежая вода ровно на три дня, а потом исчезала снова. Гидрогеологи так и не смогли объяснить эту закономерность, а местные жители просто перестали задавать вопросы и продолжали набирать воду по привычке.", author=u8"Прохор Заречный", book=u8"Три дня воды", genre=u8"Мистическая проза"},
    {text=u8"Художник рисовал портреты соседей по памяти, никогда не приглашая их позировать, и все находили сходство поразительным, пока один заказчик не заметил на своем портрете шрам, которого у него никогда не было. Через месяц шрам появился на самом деле, после несчастного случая на стройке.", author=u8"Прохор Заречный", book=u8"Три дня воды", genre=u8"Мистическая проза"},
    {text=u8"В старинном особняке лестница на второй этаж имела на одну ступеньку больше, чем показывал план здания, хранившийся в городском архиве. Новый владелец пересчитывал ступени десятки раз, приглашал независимых замерщиков, но лишняя ступенька неизменно оказывалась на месте, будто существовала только для того, кто по ней поднимался.", author=u8"Устинья Радимова", book=u8"Лишняя ступень", genre=u8"Мистическая проза"},
    {text=u8"Почтовый ящик на заброшенной станции продолжал наполняться письмами еще много лет после закрытия почтового отделения, хотя разносчики давно не заезжали в эти края. Местный смотритель собирал конверты из любопытства и обнаружил, что все они адресованы людям, чьи фамилии совпадают с именами на старом деревенском кладбище.", author=u8"Устинья Радимова", book=u8"Лишняя ступень", genre=u8"Мистическая проза"},
    {text=u8"Дорога вдоль побережья петляла между скал так резко, что автобус останавливался на каждом повороте, пропуская встречный транспорт. Пассажиры успевали разглядеть рыбацкие лодки внизу и белые домики на склонах, прежде чем водитель снова трогался с места без единого объявления остановки.", author=u8"Марфа Окунева", book=u8"Записки попутчика", genre=u8"Путевые заметки"},
    {text=u8"Рынок в старом квартале открывался затемно, и торговцы раскладывали товар при свете керосиновых ламп еще добрых полчаса после восхода. Запах свежего хлеба смешивался с ароматом специй так плотно, что казалось, будто сам воздух здесь имеет собственный вкус, знакомый лишь местным жителям.", author=u8"Марфа Окунева", book=u8"Записки попутчика", genre=u8"Путевые заметки"},
    {text=u8"Горная деревня встретила путешественников густым туманом, из-за которого дома казались подвешенными прямо в облаках. Местный трактирщик посоветовал переждать непогоду за чашкой травяного чая, и уже через час туман действительно разошелся, открыв вид на долину внизу.", author=u8"Кондратий Ясаков", book=u8"Долина в тумане", genre=u8"Путевые заметки"},
    {text=u8"Паром через пролив ходил лишь дважды в сутки, и опоздавшие пассажиры коротали время в маленьком кафе на пристани, где хозяйка знала расписание приливов лучше любого справочника. Она же первой предупреждала о задержке рейса задолго до официального объявления.", author=u8"Кондратий Ясаков", book=u8"Долина в тумане", genre=u8"Путевые заметки"},
    {text=u8"Старый город строился без единого плана, поэтому улицы сходились под самыми неожиданными углами, а некоторые заканчивались тупиком прямо во дворе чужого дома. Карта туристического бюро откровенно не поспевала за этим лабиринтом, и заблудиться здесь считалось почти традицией.", author=u8"Аврора Липневич", book=u8"Лабиринт без плана", genre=u8"Путевые заметки"},
    {text=u8"На вокзале маленького городка расписание поездов писали мелом на грифельной доске, и дежурный лично стирал прошедшие рейсы каждое утро влажной тряпкой. Туристы фотографировали эту доску чаще, чем сам вокзал, находя ее удивительно живой на фоне электронных табло больших станций.", author=u8"Аврора Липневич", book=u8"Лабиринт без плана", genre=u8"Путевые заметки"},
    {text=u8"Караван-сарай на старом торговом пути превратили в гостиницу, сохранив прежние каменные своды и колодец во внутреннем дворе. Постояльцы часто отмечали, что вечерами здесь особенно тихо, будто стены до сих пор помнят голоса купцов, останавливавшихся тут столетия назад.", author=u8"Радим Осетров", book=u8"Своды караван-сарая", genre=u8"Путевые заметки"},
    {text=u8"Прибрежная деревня жила рыбной ловлей столько поколений, что каждый дом на набережной украшали сети, развешанные для просушки. Гости приходили сюда специально ради утреннего возвращения лодок, когда весь берег на несколько минут заполнялся криками чаек и голосами рыбаков.", author=u8"Радим Осетров", book=u8"Своды караван-сарая", genre=u8"Путевые заметки"},
    {text=u8"Перевал закрывали для транспорта при первом снегопаде, и местные жители заранее закупали продукты на всю зиму, зная точную дату по многолетним наблюдениям. Приезжие удивлялись такой уверенности, пока сами не убеждались, что прогноз старожилов точнее метеосводки.", author=u8"Владлена Чубарова", book=u8"Закрытый перевал", genre=u8"Путевые заметки"},
    {text=u8"Маленький порт встречал корабли колокольным звоном с ближайшей часовни, хотя расписание прибытия судов давно никто не сверял с церковным календарем. Моряки шутили, что колокол звонит просто по привычке, но каждый из них признавался, что этот звук особенно ждал в долгом плавании.", author=u8"Владлена Чубарова", book=u8"Закрытый перевал", genre=u8"Путевые заметки"},
    {text=u8"Наблюдая за колонией муравьев в лаборатории, биологи заметили, что рабочие особи меняют маршрут к источнику пищи после малейшего изменения освещения, хотя расстояние остается прежним. Это натолкнуло исследователей на мысль, что навигация насекомых опирается не только на запаховый след, но и на угол падения света.", author=u8"Тарас Медовиков", book=u8"Записки натуралиста", genre=u8"Научно-популярная проза"},
    {text=u8"Геологи, изучавшие слои осадочных пород на берегу реки, обнаружили тонкую прослойку пепла, совпадающую по составу с извержением вулкана на другом континенте. Эта находка позволила уточнить датировку окрестных находок с точностью до нескольких десятилетий, что раньше казалось почти невозможным.", author=u8"Тарас Медовиков", book=u8"Записки натуралиста", genre=u8"Научно-популярная проза"},
    {text=u8"Метеорологи давно замечали, что перелетные птицы меняют маршрут за несколько дней до резкого похолодания, опережая любые спутниковые прогнозы. Причину этого явления объяснили лишь недавно, связав поведение птиц с изменением атмосферного давления, незаметным для человеческих приборов того времени.", author=u8"Аделаида Лучникова", book=u8"Прогноз без приборов", genre=u8"Научно-популярная проза"},
    {text=u8"Химики, исследующие состав древнего стекла, обнаружили в нем следы металлов, которые не добывались в регионе находки. Это заставило пересмотреть представления о торговых путях эпохи, доказав, что сырье привозили издалека задолго до появления письменных свидетельств о такой торговле.", author=u8"Аделаида Лучникова", book=u8"Прогноз без приборов", genre=u8"Научно-популярная проза"},
    {text=u8"Астрономы, ведущие многолетние наблюдения за двойной звездной системой, зафиксировали небольшое отклонение в периоде обращения, которое поначалу списали на ошибку измерений. Позже выяснилось, что причиной оказалась невидимая третья звезда, чье существование удалось подтвердить только косвенными расчетами.", author=u8"Никодим Стожаров", book=u8"Третья звезда", genre=u8"Научно-популярная проза"},
    {text=u8"Гидрологи, исследующие подземные реки известнякового плато, заметили, что уровень воды в отдаленных колодцах меняется синхронно с приливами на побережье в сотне километров отсюда. Эта связь объяснялась сетью карстовых пустот, соединяющих сушу с морем на большой глубине.", author=u8"Никодим Стожаров", book=u8"Третья звезда", genre=u8"Научно-популярная проза"},
    {text=u8"Энтомологи, изучающие ночных бабочек городского парка, обнаружили, что искусственное освещение фонарей меняет их брачное поведение сильнее, чем предполагалось ранее. Часть видов начала избегать освещенных участков полностью, сместив активность на предрассветные часы, когда фонари уже гаснут.", author=u8"Милана Осокина", book=u8"Бабочки и фонари", genre=u8"Научно-популярная проза"},
    {text=u8"Палеонтологи, разбирая находки из старой шахты, наткнулись на отпечаток растения, не встречавшегося прежде в слоях такого возраста. Анализ показал, что вид просуществовал значительно дольше, чем считалось, попросту не оставляя заметных следов в более поздних отложениях по чистой случайности сохранности.", author=u8"Милана Осокина", book=u8"Бабочки и фонари", genre=u8"Научно-популярная проза"},
    {text=u8"Инженеры, тестировавшие новый сплав для мостовых конструкций, заметили неожиданную устойчивость материала к перепадам температуры зимой. Причина крылась в микроскопических пустотах внутри структуры, случайно образовавшихся из-за нестандартного режима охлаждения при первой же экспериментальной плавке.", author=u8"Автандил Сорокопуд", book=u8"Пустоты в сплаве", genre=u8"Научно-популярная проза"},
    {text=u8"Вирусологи, изучавшие сезонные вспышки простуды в небольшом городе, заметили, что заболеваемость снижается на тех улицах, где сохранились старые тополя, дающие густую тень летом. Гипотеза о влиянии микроклимата на распространение инфекции впоследствии подтвердилась и в других регионах.", author=u8"Автандил Сорокопуд", book=u8"Пустоты в сплаве", genre=u8"Научно-популярная проза"},
    {text=u8"Странник спросил у старого мельника, зачем тот каждый день чинит одно и то же колесо, которое к утру снова изнашивается от воды. Мельник ответил, что дело не в колесе, а в реке: она не останавливается ни на миг, и потому работа, кажущаяся бессмысленной, на самом деле есть разговор с течением.", author=u8"Феодосий Ключников", book=u8"Разговор с течением", genre=u8"Философская проза"},
    {text=u8"Ученик спросил учителя, почему тот не записывает свои мысли, ведь память ненадежна и многое забудется с годами. Учитель ответил, что мысль, ради которой стоит жить, сама находит способ вернуться, а та, что забывается навсегда, вероятно, и не была такой важной, как казалось вначале.", author=u8"Феодосий Ключников", book=u8"Разговор с течением", genre=u8"Философская проза"},
    {text=u8"Садовник объяснял гостю, что не срезает засохшие ветви сразу после увядания, а ждет весны, потому что иногда дерево само решает, какую часть себя сохранить, а какую отпустить. Гость заметил, что это похоже на человеческую жизнь больше, чем на садоводство.", author=u8"Ефросинья Небылицына", book=u8"Ветвь, которую ждут", genre=u8"Философская проза"},
    {text=u8"Путник, застигнутый в горах непогодой, укрылся в пастушьей хижине и провел там три дня наедине с чужими вещами и собственными мыслями. Он вышел оттуда с твердым убеждением, что одиночество страшно не само по себе, а лишь тогда, когда его боятся заполнить тишиной.", author=u8"Ефросинья Небылицына", book=u8"Ветвь, которую ждут", genre=u8"Философская проза"},
    {text=u8"Часовщик говорил, что чинит не механизмы, а время людей, которые приносят к нему сломанные часы вместе со своими воспоминаниями об утраченных минутах. Каждый заказ он выполнял медленнее, чем требовалось, полагая, что спешка недостойна ремесла, связанного с самим понятием времени.", author=u8"Порфирий Загребельный", book=u8"Время в мастерской", genre=u8"Философская проза"},
    {text=u8"Рыбак объяснял внуку, что удача в его деле никогда не бывает случайной: она складывается из тысячи мелких решений, принятых задолго до того, как рыба клюнет на крючок. Внук долго не понимал этих слов, пока сам не провел на воде достаточно рассветов подряд.", author=u8"Порфирий Загребельный", book=u8"Время в мастерской", genre=u8"Философская проза"},
    {text=u8"Странствующий философ утверждал, что города меняют людей быстрее, чем люди успевают заметить перемены в самих себе, и потому советовал раз в несколько лет возвращаться туда, где прошло детство, чтобы измерить пройденный путь не по годам, а по знакомым улицам.", author=u8"Аполлон Вербицкий", book=u8"Измерение по улицам", genre=u8"Философская проза"},
    {text=u8"Старая ткачиха сравнивала человеческую жизнь с полотном, где узор становится виден только на расстоянии, а вблизи различимы лишь отдельные нити, часто перепутанные и неровные. Она никогда не судила о работе, пока станок не был снят и ткань не расправлена целиком.", author=u8"Аполлон Вербицкий", book=u8"Измерение по улицам", genre=u8"Философская проза"},
    {text=u8"Учитель черчения повторял ученикам, что прямая линия существует только на бумаге, а в реальности каждая ровная с виду поверхность хранит невидимые изгибы, заметные лишь под увеличением. Он считал это лучшим доказательством того, что совершенство всегда остается вопросом масштаба взгляда.", author=u8"Селиверст Гранев", book=u8"Вопрос масштаба", genre=u8"Философская проза"},
    {text=u8"Смотритель маяка признавался, что за долгие годы службы научился отличать корабли не по огням, а по тому, как меняется их скорость при виде берега. Он говорил, что так же можно узнать человека: не по словам, а по тому, что он делает, приближаясь к чему-то важному для себя.", author=u8"Селиверст Гранев", book=u8"Вопрос масштаба", genre=u8"Философская проза"},
    {text=u8"Она писала ему письма каждую неделю все годы, пока он служил на дальней заставе, и ни разу не пожаловалась на трудности, хотя растила сына одна. Когда он вернулся, первым делом спросил, где хранятся все ответы, которые так и не успел отправить, боясь, что почта их просто не довезет.", author=u8"Есения Прибрежная", book=u8"Письма на заставу", genre=u8"Любовный роман"},
    {text=u8"Они познакомились в очереди на регистрацию рейса, который в итоге отменили из-за непогоды, и провели вместе весь вечер в аэропорту, рассказывая друг другу истории, которые обычно берегут для самых близких людей. Утром оба поняли, что не хотят садиться на разные самолеты.", author=u8"Есения Прибрежная", book=u8"Письма на заставу", genre=u8"Любовный роман"},
    {text=u8"Он приходил в ее кофейню каждое утро ровно в восемь и заказывал один и тот же напиток, хотя терпеть не мог кофе, лишь бы услышать несколько фраз перед началом смены. Через год он наконец признался в этой маленькой лжи, и она рассмеялась так, что уронила поднос.", author=u8"Радослав Вечерин", book=u8"Один и тот же напиток", genre=u8"Любовный роман"},
    {text=u8"Их разделяло целое море, и письма шли по полтора месяца в каждую сторону, поэтому влюбленные завели привычку писать даты в верхнем углу листа, чтобы читать письмо так, будто оно приходит день в день. Спустя годы эта переписка легла в основу их семейного архива.", author=u8"Радослав Вечерин", book=u8"Один и тот же напиток", genre=u8"Любовный роман"},
    {text=u8"Вдовец решил снова научиться танцевать вальс к юбилею дочери, стесняясь признаться, что последний раз выходил на паркет со своей покойной женой. Учительница танцев заметила его волнение и предложила заниматься по вечерам, когда в зале никого, кроме них двоих, не было.", author=u8"Ганна Светозарова", book=u8"Вальс к юбилею", genre=u8"Любовный роман"},
    {text=u8"Она вернула ему старое кольцо через двадцать лет после расставания, найдя его случайно на дне шкатулки во время переезда, и приложила короткую записку с одной строчкой благодарности за годы, о которых оба вспоминали чаще, чем признавались самим себе.", author=u8"Ганна Светозарова", book=u8"Вальс к юбилею", genre=u8"Любовный роман"},
    {text=u8"Молодые супруги переписывались смс-сообщениями весь рабочий день, хотя сидели в соседних кабинетах одного офиса, потому что так признания казались легче, чем произнесенные вслух через приоткрытую дверь. Коллеги давно догадались об их секрете, но вежливо делали вид, что ничего не замечают.", author=u8"Матвей Огарев", book=u8"Соседние кабинеты", genre=u8"Любовный роман"},
    {text=u8"Он ждал ее у вокзала каждую пятницу вечером все три года, пока она училась в другом городе, и никогда не жаловался на долгую дорогу в оба конца. Она узнала об этом только после свадьбы, случайно наткнувшись на старые билеты, которые он бережно хранил.", author=u8"Матвей Огарев", book=u8"Соседние кабинеты", genre=u8"Любовный роман"},
    {text=u8"Их первое свидание сорвалось из-за поломки лифта, и вместо ресторана они провели два часа, застряв между этажами, рассказывая друг другу анекдоты, чтобы не поддаваться панике. Через несколько лет они специально вернулись в тот же дом, чтобы сфотографироваться у той самой двери.", author=u8"Злата Веретенникова", book=u8"Застрявший лифт", genre=u8"Любовный роман"},
    {text=u8"Он выучил ее любимый язык за год, тайно занимаясь по вечерам после работы, чтобы однажды заговорить с ее бабушкой без переводчика на семейном празднике. Бабушка расплакалась от неожиданности и с тех пор называла его исключительно родным именем, придуманным в первый же вечер знакомства.", author=u8"Злата Веретенникова", book=u8"Застрявший лифт", genre=u8"Любовный роман"},
    {text=u8"Санитарка выносила раненых с передовой всю ночь напролет и вела счет спасенным зарубками на прикладе трофейной винтовки, которую так и не научилась использовать по назначению. После войны она хранила эту винтовку в чулане, никому не объясняя истинный смысл зарубок на ложе.", author=u8"Гордей Солоневич", book=u8"Зарубки на прикладе", genre=u8"Военная проза"},
    {text=u8"Связист протянул провод через минное поле, ориентируясь только по памяти о рельефе местности, изученной еще до начала обстрела. Командир полка позже говорил, что этот кабель спас связь батальона в самый критический час, хотя сам связист об этом почти не рассказывал.", author=u8"Гордей Солоневич", book=u8"Зарубки на прикладе", genre=u8"Военная проза"},
    {text=u8"В осажденном городе учительница продолжала вести уроки в подвале школы при свече, потому что дети настаивали на занятиях даже во время обстрелов, не желая отставать от программы. После освобождения города именно этот класс показал лучшие результаты на итоговых экзаменах области.", author=u8"Милослава Ратникова", book=u8"Уроки в подвале", genre=u8"Военная проза"},
    {text=u8"Полевой повар готовил на весь батальон из скудного пайка, экономя каждую крупу так тщательно, что солдаты шутили, будто он умеет варить кашу из воздуха. После войны он открыл маленькую столовую в родном городе и до старости отказывался выбрасывать даже хлебные крошки.", author=u8"Милослава Ратникова", book=u8"Уроки в подвале", genre=u8"Военная проза"},
    {text=u8"Летчик посадил подбитый самолет на неровное поле в трех километрах от линии фронта и провел ночь, пряча машину под ветками, прежде чем добраться до своих пешком. Много лет спустя он специально приехал в те места и нашел то самое поле, заросшее теперь высокой пшеницей.", author=u8"Терентий Ободов", book=u8"Поле под ветками", genre=u8"Военная проза"},
    {text=u8"Разведчица переходила линию фронта под видом крестьянки трижды за одну неделю, каждый раз меняя маршрут, чтобы не оставлять заметного следа для наблюдателей. О ее работе командование узнало подробности только после войны, из скупых строк наградного листа.", author=u8"Терентий Ободов", book=u8"Поле под ветками", genre=u8"Военная проза"},
    {text=u8"Старшина берег последнюю пачку писем от жены в нагрудном кармане гимнастерки на протяжении всей кампании, перечитывая их перед каждым боем в строгом порядке дат. Он объяснял сослуживцам, что так легче помнить, за что именно стоит вернуться домой живым.", author=u8"Ярополк Стрешнев", book=u8"Порядок дат", genre=u8"Военная проза"},
    {text=u8"Полковой врач оперировал раненых при свете фар грузовика после того, как в медсанбате погас генератор, и не остановил работу до самого рассвета. Медсестры вспоминали потом, что за ту ночь он не присел ни разу, хотя сам едва держался на ногах от усталости.", author=u8"Ярополк Стрешнев", book=u8"Порядок дат", genre=u8"Военная проза"},
    {text=u8"Подросток из прифронтовой деревни носил донесения между постами партизанского отряда, прячась в высокой траве и запоминая маршрут наизусть, потому что карту доверять бумаге было слишком опасно. После войны он стал картографом, составляя карты уже совсем другого рода дорог.", author=u8"Влада Перекопская", book=u8"Карта другого рода", genre=u8"Военная проза"},
    {text=u8"Комбат вел дневник боевых действий убористым почерком в блокноте, который берег как самую ценную вещь при отступлении, полагая, что правда о войне важнее любого личного имущества. Дневник сохранился до наших дней и стал основой музейной экспозиции родного города комбата.", author=u8"Влада Перекопская", book=u8"Карта другого рода", genre=u8"Военная проза"},
    {text=u8"Бабка Аксинья вставала до петухов не из привычки, а потому что верила: кто первым увидит рассвет над своим огородом, у того и урожай выйдет богаче. Соседи посмеивались над этой приметой, но каждый год именно ее грядки давали самые крупные огурцы во всей округе.", author=u8"Ефим Колотушкин", book=u8"Грядки Аксиньи", genre=u8"Деревенская проза"},
    {text=u8"Пастух Микола знал по кличкам всех коров в стаде и мог с закрытыми глазами сказать, какая корова отбилась от общего маршрута по одному только звуку колокольчика. Хозяйки доверяли ему стадо без опаски, зная, что ни одна животина не пропадет по пути домой.", author=u8"Ефим Колотушкин", book=u8"Грядки Аксиньи", genre=u8"Деревенская проза"},
    {text=u8"Кузнец в дальнем конце села подковывал лошадей так же, как его дед и прадед, отказываясь признавать новомодные железные подковы, привезенные из города. Односельчане приезжали к нему даже из соседних деревень, хотя дорога занимала лишний час пути.", author=u8"Агафья Стожарова", book=u8"Кузня на краю села", genre=u8"Деревенская проза"},
    {text=u8"После сенокоса вся деревня собиралась на общий обед прямо в поле, расстилая скатерти на свежескошенной траве, и старики рассказывали молодежи истории про урожайные и голодные годы, чтобы те помнили цену хлеба, лежащего сейчас на столе.", author=u8"Агафья Стожарова", book=u8"Кузня на краю села", genre=u8"Деревенская проза"},
    {text=u8"Мельница на краю реки работала только по большой воде, и мельник Тимофей подстраивал весь свой быт под капризы течения, зная его лучше собственного огорода. Соседи шутили, что он женился на реке раньше, чем на собственной жене, и в этой шутке была немалая доля правды.", author=u8"Родион Пересвет", book=u8"Мельник и река", genre=u8"Деревенская проза"},
    {text=u8"Каждую осень в деревне резали общего кабана вскладчину, деля мясо по числу дворов поровну, и это событие считалось едва ли не праздником, потому что означало, что зима не застанет семьи без запасов. Дети помнили этот день лучше многих официальных праздников.", author=u8"Родион Пересвет", book=u8"Мельник и река", genre=u8"Деревенская проза"},
    {text=u8"Старая учительница деревенской школы преподавала одновременно четыре класса в одной комнате, рассаживая учеников рядами по возрасту, и умудрялась держать в голове задания для каждого ряда сразу. Выпускники вспоминали ее метод спустя десятилетия с неизменным уважением.", author=u8"Пелагея Гуменюк", book=u8"Четыре класса в одной комнате", genre=u8"Деревенская проза"},
    {text=u8"Пасечник объяснял внуку, что пчелы чувствуют перемену погоды за сутки вперед лучше любого барометра, и советовал следить за ульем, а не за небом, если хочешь заранее знать, стоит ли откладывать полевые работы на завтра.", author=u8"Пелагея Гуменюк", book=u8"Четыре класса в одной комнате", genre=u8"Деревенская проза"},
    {text=u8"Печник ходил по окрестным деревням, складывая печи по особому секрету, доставшемуся от отца, и никогда не брал плату вперед, доверяя хозяевам рассчитаться после первой протопленной зимы. За полвека работы он не помнил ни одного случая обмана.", author=u8"Онисим Бортников", book=u8"Секрет печника", genre=u8"Деревенская проза"},
    {text=u8"Вдовы деревни по очереди помогали друг другу убирать урожай, распределив дни недели между хозяйствами задолго до самой страды, и эта негласная договоренность держалась крепче любого писаного расписания много лет подряд.", author=u8"Онисим Бортников", book=u8"Секрет печника", genre=u8"Деревенская проза"},
    {text=u8"Городской архив хранит переписку строителей первого моста через реку, из которой видно, что расчеты опор пересматривали четыре раза из-за нового обмера дна. Именно эта переписка помогла современным инженерам понять, почему конструкция моста оказалась настолько прочной для своего времени.", author=u8"Аркадий Летописцев", book=u8"Мостовая переписка", genre=u8"Документальный очерк"},
    {text=u8"В краеведческом музее хранится дневник фельдшера, который вел прием в единственной сельской амбулатории на три соседних деревни в течение тридцати лет. Его записи стали ценным источником для изучения эпидемий и урожайности местности того периода.", author=u8"Аркадий Летописцев", book=u8"Мостовая переписка", genre=u8"Документальный очерк"},
    {text=u8"Городская библиотека оцифровала подшивку районной газеты за полвека, и исследователи неожиданно обнаружили в объявлениях о пропаже скота косвенные сведения о миграции населения, которые ни один официальный отчет того времени не фиксировал напрямую.", author=u8"Стефания Родникова", book=u8"Объявления о пропаже", genre=u8"Документальный очерк"},
    {text=u8"Историки промышленности изучили журналы смен на старом текстильном комбинате и восстановили по ним точную хронологию внедрения новых станков, которую сама заводская документация приводила лишь приблизительно, без конкретных дат и фамилий мастеров.", author=u8"Стефания Родникова", book=u8"Объявления о пропаже", genre=u8"Документальный очерк"},
    {text=u8"Записки участкового врача провинциального города за военные годы подробно фиксируют не только болезни пациентов, но и цены на продукты, что позволило современным экономистам восстановить динамику местного рынка с точностью, недоступной официальной статистике.", author=u8"Гаврила Осокин", book=u8"Записки участкового", genre=u8"Документальный очерк"},
    {text=u8"Архивариус областного музея обнаружил переписку двух учителей из разных школ, которые десятилетиями обменивались методическими находками по почте, ни разу не встретившись лично. Их совместный опыт лег в основу целой педагогической традиции региона.", author=u8"Гаврила Осокин", book=u8"Записки участкового", genre=u8"Документальный очерк"},
    {text=u8"Метеорологическая станция небольшого городка вела непрерывные наблюдения сто двадцать лет подряд, и эти данные оказались едва ли не единственным полным источником о локальном климате целого региона, не тронутого крупными городскими застройками.", author=u8"Людмила Заряницкая", book=u8"Сто двадцать лет наблюдений", genre=u8"Документальный очерк"},
    {text=u8"Исследователи транспортной истории по старым билетам конки восстановили маршрутную сеть города, ликвидированную еще до появления первых подробных карт общественного транспорта, найденную случайно в архиве частного коллекционера.", author=u8"Людмила Заряницкая", book=u8"Сто двадцать лет наблюдений", genre=u8"Документальный очерк"},
    {text=u8"Записи смотрителя маяка о каждом прошедшем судне за полвека помогли современным исследователям восстановить интенсивность судоходства в проливе задолго до появления официальной портовой статистики, которую начали вести лишь спустя десятилетия.", author=u8"Захар Прибрежанин", book=u8"Судовой список смотрителя", genre=u8"Документальный очерк"},
    {text=u8"Городская управа сохранила комплект технических паспортов первых домов с водопроводом, что позволило современным коммунальным службам точно определить возраст изношенных труб без дорогостоящей и разрушительной инженерной экспертизы всего квартала.", author=u8"Захар Прибрежанин", book=u8"Судовой список смотрителя", genre=u8"Документальный очерк"},
    {text=u8"Тренер заставлял команду отрабатывать один и тот же угловой удар до автоматизма целый месяц, хотя игроки открыто скучали на этих занятиях. В решающем матче сезона именно этот отработанный угловой принес единственный гол, решивший исход турнира в последнюю минуту встречи.", author=u8"Богдан Пересветов", book=u8"Отработанный угловой", genre=u8"Спортивная проза"},
    {text=u8"Пловчиха начинала тренировки в пять утра задолго до открытия основного бассейна, договорившись со сторожем об одной дорожке специально для себя. Через два года такой дисциплины она установила региональный рекорд, который продержался почти десятилетие.", author=u8"Богдан Пересветов", book=u8"Отработанный угловой", genre=u8"Спортивная проза"},
    {text=u8"Шахматист изучал партии соперника по архивным записям три недели перед турниром, выискивая малейшие закономерности в дебютных решениях. На финальной партии именно эта подготовка позволила ему поймать оппонента на редко применяемой, но давно просчитанной комбинации.", author=u8"Изольда Ракитина", book=u8"Дебютная закономерность", genre=u8"Спортивная проза"},
    {text=u8"Марафонец бегал по одному и тому же маршруту вдоль реки каждое утро, специально выбирая участки с неровным покрытием, чтобы тело привыкало к любым условиям соревновательной трассы. Соседи давно перестали удивляться этой фигуре в предрассветном тумане.", author=u8"Изольда Ракитина", book=u8"Дебютная закономерность", genre=u8"Спортивная проза"},
    {text=u8"Гимнастка репетировала одну связку движений сотни раз подряд, добиваясь идеальной синхронности каждого поворота с музыкальным акцентом. Судьи на итоговых соревнованиях отметили именно эту связку как самую техничную во всей программе турнира.", author=u8"Радомир Ковальчук", book=u8"Идеальная синхронность", genre=u8"Спортивная проза"},
    {text=u8"Хоккейный вратарь просматривал записи бросков соперника перед каждой игрой, составляя короткие заметки о привычках нападающих в специальном блокноте. Его партнеры по команде шутили, что этот блокнот стоит дороже любого контракта клуба.", author=u8"Радомир Ковальчук", book=u8"Идеальная синхронность", genre=u8"Спортивная проза"},
    {text=u8"Тяжелоатлет вел подробный дневник каждой тренировки, отмечая не только вес снаряда, но и собственное самочувствие в тот день. Спустя годы этот дневник помог ему точно определить, какие факторы влияют на результат сильнее всего остального режима подготовки.", author=u8"Ярина Стрельцова", book=u8"Дневник тяжелоатлета", genre=u8"Спортивная проза"},
    {text=u8"Фигурист сменил тренера в середине сезона, рискуя потерять наработанную программу, но новый специалист предложил переработать всего один элемент, который прежде считался слабым местом выступления. Именно этот элемент вывел спортсмена на пьедестал впервые за карьеру.", author=u8"Ярина Стрельцова", book=u8"Дневник тяжелоатлета", genre=u8"Спортивная проза"},
    {text=u8"Гребец готовился к регате в одиночку на рассвете, изучая течение реки в разное время суток, чтобы выбрать оптимальный момент старта для своей лодки. Соперники недооценивали эту подготовку, пока не увидели итоговое время на финишном створе.", author=u8"Демьян Взморьев", book=u8"Течение перед стартом", genre=u8"Спортивная проза"},
    {text=u8"Юный теннисист записывал результаты каждой тренировочной подачи в тетрадь, выискивая закономерность в собственных ошибках при игре на ветру. Спустя сезон эта тетрадь превратилась в подробное пособие, которым позже пользовались и его младшие товарищи по секции.", author=u8"Демьян Взморьев", book=u8"Течение перед стартом", genre=u8"Спортивная проза"},
}

CLAVA_SOURCE_EN = {
    {text="Inspector Hale spent three evenings comparing the ferry ledgers with the harbour master's notes before he noticed that one crossing was recorded twice, once at dusk and once at dawn, by the same clerk. Either the man had been careless, or he had wanted someone to look very closely at that particular night.", author="Martin Ashgrove", book="The Second Crossing", genre="Mystery"},
    {text="The locksmith swore he had cut only two keys for the flat above the bakery, yet the police found a third one hanging inside the owner's coat. It was still bright and unworn, as though it had never turned in any lock at all, and its teeth matched no door in the whole building.", author="Martin Ashgrove", book="The Second Crossing", genre="Mystery"},
    {text="A pianist was found asleep in the empty concert hall with the lid of the grand piano closed and a folded note under his hand. The note contained only a list of dates, each one a Thursday, and the caretaker admitted quietly that every one of those evenings had ended with a locked door and a missing candle.", author="Nora Whitcombe", book="Thursday Candles", genre="Mystery"},
    {text="The librarian noticed that the same overdue novel came back every month, always with a different bookmark tucked inside. By the fifth return she had collected a thin stack of train tickets, and every ticket led to a small town that had no station at all.", author="Nora Whitcombe", book="Thursday Candles", genre="Mystery"},
    {text="Detective Okafor studied the muddy footprints on the veranda and frowned. They led toward the house but never away from it, and the owner insisted nobody had come in. Only when he lifted the doormat did he find the neat pair of boots, still wet, hidden where a careful visitor would leave them.", author="Daniel Prescott", book="Boots on the Veranda", genre="Mystery"},
    {text="The auction house discovered that a small landscape had been sold twice in one week to two different buyers, each holding a perfect receipt. The clerk who signed both slips had left for the coast that morning, taking only a green umbrella and, as it later turned out, a very old catalogue.", author="Daniel Prescott", book="Boots on the Veranda", genre="Mystery"},
    {text="Every clock in the village tower struck thirteen on the night the mayor's ring vanished. The watchmaker examined the mechanism and found a strip of paper wedged between two gears, carefully cut so that it would stop the bell only after the last stroke, giving the thief exactly one minute of confusion.", author="Helena Marsh", book="Thirteen Strokes", genre="Mystery"},
    {text="A courier delivered a sealed box to the lawyer's office and refused to leave until someone signed for it. Inside lay a single pressed flower and a receipt for a rented garden plot, dated forty years earlier, in the name of a man who had officially never existed.", author="Helena Marsh", book="Thirteen Strokes", genre="Mystery"},
    {text="The night porter remembered the guest in room nine because he asked for two cups of tea and drank neither. In the morning the bed was untouched, the window was latched from the inside, and on the table stood a chessboard with every white piece removed and set neatly in a row.", author="Gareth Lindqvist", book="Room Nine", genre="Mystery"},
    {text="Constable Reed traced the stolen bicycle to a barn three miles away, where it leaned against a wall beside forty identical bicycles, each freshly painted blue. The farmer shrugged and said he had only been storing them for a friend who promised to collect them once the rain stopped.", author="Gareth Lindqvist", book="Room Nine", genre="Mystery"},
    {text="The colony ship had been travelling for ninety years when the navigator noticed that the stars ahead were arranged in a pattern she remembered from an old children's book. She checked the charts twice, then quietly asked the archivist whether anyone had ever mentioned that the book was not fiction.", author="Ilya Brandt", book="The Pattern Ahead", genre="Science fiction"},
    {text="A maintenance drone on the orbital station began leaving small paper boats in the corridors, folded from discarded manuals. The engineers assumed a fault in its software until they realised that each boat pointed toward a valve that would have failed within the week.", author="Ilya Brandt", book="The Pattern Ahead", genre="Science fiction"},
    {text="When the last rain machine broke down, the village children were told that water would come from the sky again only if somebody remembered how to ask for it. The oldest woman began to hum a tune nobody recognised, and by evening the horizon had turned the colour of iron.", author="Priya Nandakumar", book="The Rain Machine", genre="Science fiction"},
    {text="The translator program worked perfectly on every alien signal except one, which it kept rendering as a single, repeated sentence: please do not answer yet. The linguists argued for weeks about whether the message was a warning, a plea, or simply a good piece of advice.", author="Priya Nandakumar", book="The Rain Machine", genre="Science fiction"},
    {text="On the far side of the moon, a research team unearthed a metal plate covered with rows of tiny holes. When they held it up to the sun, the light that passed through drew a map of their own base, complete with the cracked window in the kitchen module.", author="Victor Almeida", book="Holes in the Light", genre="Science fiction"},
    {text="Every morning the city's weather AI posted a short poem instead of a forecast, and every morning the poem turned out to be accurate. Residents stopped carrying umbrellas by rule and started carrying them by rhyme, which the engineers found faintly alarming and deeply touching.", author="Victor Almeida", book="Holes in the Light", genre="Science fiction"},
    {text="The seed vault beneath the glacier held one drawer that no record described. Inside sat a jar of soil, still faintly warm, labelled in handwriting that matched the chief botanist's, though she had never opened that door in her life and the ink looked several centuries old.", author="Mei-Lin Zhou", book="Warm Soil", genre="Science fiction"},
    {text="A courier ship dropped out of hyperspace three light years from its destination and found itself surrounded by thousands of silent lanterns floating in the dark. The pilot counted them until she fell asleep, and woke to find every lantern turned, very slightly, toward her.", author="Mei-Lin Zhou", book="Warm Soil", genre="Science fiction"},
    {text="The engineers built a bridge across the frozen ocean of the outer moon and were surprised when the ice beneath it began to hum. Within a month the note had settled into a steady chord, and the crew learned to tell time by the slow changes in its pitch.", author="Tobias Renner", book="The Humming Bridge", genre="Science fiction"},
    {text="The archivist of the wandering fleet spent her final years copying every recipe she could find onto sheets of thin metal. She claimed that when the ships eventually reached a new world, the first thing people would need was not a map but a reason to sit down together.", author="Tobias Renner", book="The Humming Bridge", genre="Science fiction"},
    {text="In the winter of 1709 the miller's wife counted the remaining sacks of flour every morning and wrote the number on the wall in charcoal. By spring the wall was covered with figures, and the neighbours, who had never learned to read, could still tell at a glance how close the village was to hunger.", author="Edmund Carrow", book="Charcoal on the Wall", genre="Historical fiction"},
    {text="The young surveyor arrived at the market town with a brass theodolite and a letter of introduction, only to discover that the mayor had already hired a rival who measured land by the length of his own stride. The dispute was settled in a field, and the theodolite lost by two feet.", author="Edmund Carrow", book="Charcoal on the Wall", genre="Historical fiction"},
    {text="During the siege, the baker's apprentice was sent through the lines each night with a basket of loaves and a single instruction: never look at the sentries. He obeyed for six weeks, and only afterward learned that half the sentries had been leaving him a candle stub to light his way.", author="Rosalind Aldous", book="The Baker's Apprentice", genre="Historical fiction"},
    {text="A travelling printer set up his press in a barn during the harvest fair and produced two hundred pamphlets in a single night. By dawn every farmer within ten miles had read the news of the treaty, and a rumour that had begun as a whisper became an argument at every breakfast table.", author="Rosalind Aldous", book="The Baker's Apprentice", genre="Historical fiction"},
    {text="Sister Agnes kept the abbey's accounts in a ledger bound in green leather, and she recorded every gift and every debt with the same steady hand. When the king's collectors arrived, they found nothing to dispute, and left believing that holiness and arithmetic were the same virtue.", author="Conrad Wexley", book="The Green Ledger", genre="Historical fiction"},
    {text="The harbour of Valdera filled with masts each spring, and the harbour master rowed out to greet every captain in person, carrying a small bell to signal the start of trading. Traders said that a bargain struck after that bell had never once been broken in three hundred years.", author="Conrad Wexley", book="The Green Ledger", genre="Historical fiction"},
    {text="When the railway finally reached the mountain town, the old coachman refused to sell his horses and drove the empty road every morning out of pure stubbornness. Within a year he was carrying passengers again, those who wanted to see the valley slowly and were willing to pay for the privilege.", author="Beatrix Holloway", book="The Empty Road", genre="Historical fiction"},
    {text="The lighthouse keeper's daughter learned to read from the storm logs her father kept, and her first written sentence was a weather report. It read simply that the wind was from the west, the sea was rough, and she was hungry, which her father framed and hung above the stove.", author="Beatrix Holloway", book="The Empty Road", genre="Historical fiction"},
    {text="In the spring after the flood, the townspeople rebuilt the bridge stone by stone and carved the name of each family on the underside of the arch. Nobody could see the names from above, but every child who crawled beneath at low water went home knowing exactly where they belonged.", author="Silas Thornbury", book="Names Beneath the Arch", genre="Historical fiction"},
    {text="The cartographer worked for eleven years on a single map of the coast and refused every offer to sell it unfinished. When he died, they found that the last unmarked corner held only a small drawing of himself, standing on the shore with a lamp, waiting for a ship.", author="Silas Thornbury", book="Names Beneath the Arch", genre="Historical fiction"},
    {text="My father never said he was proud of me, but every Sunday he polished my old school shoes and set them beside the door, as if I might still need them. When he passed away, I found forty pairs lined up in the attic, each one cleaned, each one waiting for a child who had already grown.", author="Claire Donovan", book="Forty Pairs of Shoes", genre="Drama"},
    {text="The two brothers had not spoken since the funeral, yet both turned up at the old house on the same afternoon to sell it. They sat on the porch for an hour, arguing about the price, until one of them laughed and said the porch swing still creaked exactly the way it used to.", author="Claire Donovan", book="Forty Pairs of Shoes", genre="Drama"},
    {text="She kept her mother's voicemail for eight years and played it only on the worst days. On the day she finally deleted it, she realised she could recite every word by heart, and that the message had never really been stored on the phone in the first place.", author="Adrian Fell", book="Voicemail", genre="Drama"},
    {text="The retired teacher read the same poem aloud each morning to an empty classroom, because the school had closed but the habit had not. One day a former student passed by, stopped at the window, and quietly joined in from memory, word for word, after thirty years.", author="Adrian Fell", book="Voicemail", genre="Drama"},
    {text="Every winter the old couple set the table for three, though their son had moved abroad long ago and rarely called. They never mentioned the empty chair, but the wife always left the window unlatched, just in case he came home in the middle of the night.", author="Lena Kowalczyk", book="The Third Chair", genre="Drama"},
    {text="The nurse on the night shift learned that the man in bed twelve could not sleep unless someone read him the football scores from a newspaper years out of date. She read them faithfully, and on his last night he whispered that his team had won every single match.", author="Lena Kowalczyk", book="The Third Chair", genre="Drama"},
    {text="After the argument she drove for hours with no destination, and ended up outside the house where she had grown up. The porch light was on, and a stranger was watering the garden she had once planted, humming the same tune her mother used to hum at that hour.", author="Oliver Brennan", book="The Porch Light", genre="Drama"},
    {text="The young violinist practised in the stairwell because the flat was too small and the neighbours too tired. Over time the residents began leaving their doors slightly open, and on the night of her first concert the whole building sat quietly on the steps to listen.", author="Oliver Brennan", book="The Porch Light", genre="Drama"},
    {text="He wrote his daughter a letter every birthday and hid them in a drawer, telling himself he would give them to her when she was old enough to understand. She was thirty when she found them, and by then she understood far more than he had ever intended to say.", author="Marguerite Lowell", book="Letters in a Drawer", genre="Drama"},
    {text="The bakery on the corner closed after fifty years, and the whole street gathered to watch the last loaf come out of the oven. Nobody spoke while the owner sliced it, and each person took one piece home, carrying it carefully, as if it were something far more fragile than bread.", author="Marguerite Lowell", book="Letters in a Drawer", genre="Drama"},
    {text="The expedition reached the river's edge just as the rains began, and the guide insisted they cross that same night rather than wait for the water to rise. By morning the ford had vanished beneath a brown, roaring flood, and nobody questioned his judgment for the rest of the journey.", author="Rufus Callahan", book="The Night Ford", genre="Adventure"},
    {text="Deep inside the cave, the explorers found a chamber lined with pale crystals that hummed faintly whenever anyone spoke. They spent an entire day whispering to it, and left with the strange feeling that the cave had learned their voices and would remember them long after they were gone.", author="Rufus Callahan", book="The Night Ford", genre="Adventure"},
    {text="The captain steered the little schooner into a bay that no chart admitted existed, following a line of white birds that seemed to know the way. The water was clear as glass, the beach was empty, and on a rock by the shore sat a rusted lantern with its flame still burning.", author="Isabel Fairweather", book="The White Birds", genre="Adventure"},
    {text="Two climbers spent the night on a ledge no wider than a doorstep, tied together and sharing a single blanket. At dawn the fog lifted to reveal that the summit they had been fighting toward for three days was a mere hour's walk away along a gentle, sunlit ridge.", author="Isabel Fairweather", book="The White Birds", genre="Adventure"},
    {text="The old prospector drew his map on the back of a tavern menu and swore the gold lay beneath a tree shaped like a hand. The boy who followed him spent a month among the forests before realising that every tree in the valley looked like a hand if you squinted long enough.", author="Jasper Quill", book="A Tree Like a Hand", genre="Adventure"},
    {text="Halfway across the desert the caravan's water ran low, and the leader ordered a detour toward a dry riverbed nobody had visited in years. There, beneath a flat stone, they found a wooden cup and a fresh spring, and a note asking travellers to leave the cup for the next ones.", author="Jasper Quill", book="A Tree Like a Hand", genre="Adventure"},
    {text="The raft carried five people and a goat down a river that grew louder with every bend. When the roar finally became a waterfall, they steered for the bank and hauled the raft ashore, all of them laughing so hard that the goat, unimpressed, wandered off to find breakfast.", author="Tamsin Okonkwo", book="Five People and a Goat", genre="Adventure"},
    {text="The glaciologist lowered a camera into a crack in the ice and watched the screen fill with pale blue light. Forty metres down, the lens caught something small and orange drifting in the current, and it took the whole team a minute to recognise a child's mitten.", author="Tamsin Okonkwo", book="Five People and a Goat", genre="Adventure"},
    {text="On the last day of the voyage, the cook baked bread using the final handful of flour and shared it with the whole crew on the deck. Nobody said much, but afterward the sailors agreed that no meal on land had ever tasted quite so much like being alive.", author="Leopold Banks", book="The Last Handful of Flour", genre="Adventure"},
    {text="The trail guide carried a compass that pointed a few degrees west of north, and he refused to replace it. He said he had walked with it so long that his feet no longer trusted any other direction, and in thirty years he had never once lost a traveller.", author="Leopold Banks", book="The Last Handful of Flour", genre="Adventure"},
    {text="The neighbourhood committee spent two hours debating whether the new bench should face the road or the park, and finally decided to build two benches back to back. Each side then complained that the other had the better view, and the committee scheduled another meeting to discuss it.", author="Percival Dunn", book="Two Benches", genre="Humor"},
    {text="My uncle insisted that he could assemble the wardrobe without instructions, and for a whole Saturday the living room echoed with hammering and cheerful optimism. By evening he had built a very sturdy bookcase, which we all agreed was exactly what the room needed.", author="Percival Dunn", book="Two Benches", genre="Humor"},
    {text="The office kettle had been broken for a month, but nobody wanted to report it, because each of us secretly enjoyed the walk to the kitchen on the fourth floor. When it was finally repaired, productivity dropped, and morale followed it down a flight of stairs.", author="Winifred Lark", book="The Broken Kettle", genre="Humor"},
    {text="Our cat has learned to open the fridge, and refuses to admit it. Every morning she sits beside the open door with a look of perfect innocence, as though the milk had simply decided to leap out and greet her on its own initiative.", author="Winifred Lark", book="The Broken Kettle", genre="Humor"},
    {text="The town's only taxi driver knew every shortcut, and used none of them, on the grounds that a passenger who reaches home too quickly has no time to appreciate the conversation. His fares were high, his stories were long, and his customers were remarkably loyal.", author="Barnaby Trout", book="The Long Way Round", genre="Humor"},
    {text="At the village fete, the prize for the largest marrow was awarded to a vegetable that turned out to be a very well painted pumpkin. The judges admitted the mistake, but the winner pointed out that nobody had specified what colour a marrow should be.", author="Barnaby Trout", book="The Long Way Round", genre="Humor"},
    {text="The new manager introduced a rule that all meetings must be standing, and for a week everyone stood in the conference room looking uncomfortable. On Friday somebody brought a stool, and by Monday the entire office had quietly returned to the old, sitting way of doing things.", author="Cordelia Finch", book="Standing Meetings", genre="Humor"},
    {text="Grandma learned to send text messages last year and now writes them with the solemnity of a royal decree. Every message ends with her full name and a small, formal farewell, which makes even a request to buy bread sound like an international treaty.", author="Cordelia Finch", book="Standing Meetings", genre="Humor"},
    {text="The local choir practised for months for the spring concert, only to discover on the day that the church organ had been sold. They sang without accompaniment, out of tune and full of enthusiasm, and the audience declared it the best performance in living memory.", author="Humphrey Gale", book="No Organ Today", genre="Humor"},
    {text="I bought a book about time management, but I have not had a chance to read it, because I am far too busy. Perhaps the author would be kind enough to write a shorter edition for people like me, ideally one that can be finished in a single sentence.", author="Humphrey Gale", book="No Organ Today", genre="Humor"},
    {text="The manor stood at the end of a road that seemed to grow longer each time the carriage turned a corner. When at last the lamps came into view, the driver refused to go any further, and the traveller walked the final half mile alone, listening to his own footsteps arrive slightly late.", author="Ambrose Wraith", book="The Longer Road", genre="Gothic fiction"},
    {text="Every evening at nine the cellar door of the old rectory opened by itself and closed again a minute later. The new vicar decided to wait beside it with a lantern, and was found at midnight sitting calmly on the stairs, unable to say what he had seen but unwilling to leave.", author="Ambrose Wraith", book="The Longer Road", genre="Gothic fiction"},
    {text="In the attic of the boarding house stood a wardrobe that nobody could remember buying. Its mirror reflected the room perfectly, except that in the reflection the window was always open, and the curtains were always moving, though the air in the room was perfectly still.", author="Serena Blackwood", book="The Wardrobe Mirror", genre="Gothic fiction"},
    {text="The fog rolled in from the marshes every autumn and stayed for weeks. Villagers kept their doors locked and their candles lit, and children were taught a rhyme to recite if they heard someone calling their name from the mist, whatever voice it happened to be using.", author="Serena Blackwood", book="The Wardrobe Mirror", genre="Gothic fiction"},
    {text="The portrait in the hallway had been painted a century ago, but its eyes seemed to follow the housekeeper as she dusted the frame. She began to greet it politely every morning, mostly to be safe, and for years the house remained remarkably calm.", author="Lucian Grey", book="The Polite Housekeeper", genre="Gothic fiction"},
    {text="A single candle burned in the tower window every night for a hundred years, though no one had ever seen anyone climb the stairs. When the tower finally collapsed in a storm, the villagers found the stub of a candle at the top, no longer than a fingernail, and still warm.", author="Lucian Grey", book="The Polite Housekeeper", genre="Gothic fiction"},
    {text="The graveyard keeper always left one gate unlocked, explaining that the residents sometimes liked to take a walk. Nobody laughed, since several villagers had noticed fresh footprints in the frost each dawn, leading calmly out of the grass and calmly back again.", author="Vivienne Crowe", book="The Unlocked Gate", genre="Gothic fiction"},
    {text="The violin in the museum was said to play itself at midnight. The night guard, a sensible man, sat next to the case with a flask of tea and a crossword, and reported the next morning that the music had been lovely, although he wished it would choose a livelier tune.", author="Vivienne Crowe", book="The Unlocked Gate", genre="Gothic fiction"},
    {text="Something was scratching inside the wall of the nursery, faintly but regularly, like a pencil writing very small words. The father cut a neat hole in the plaster and found only a rolled sheet of paper covered with tiny drawings of a house, a garden, and a small figure waving from the window.", author="Dorian Ashby", book="Scratching in the Wall", genre="Gothic fiction"},
    {text="The well behind the inn was said to be bottomless, and travellers often dropped a coin into it for luck. The innkeeper, however, noted with quiet unease that in forty years he had never heard a single coin land, and that the well had grown a little wider each winter.", author="Dorian Ashby", book="Scratching in the Wall", genre="Gothic fiction"},
    {text="The night train from the capital moved so slowly that passengers could read the names of the villages by lantern light. I shared a compartment with a retired sailor who explained, at length and with great affection, why every station in the country deserved its own small national holiday.", author="Hugo Sinclair", book="The Slow Night Train", genre="Travel writing"},
    {text="In the mountain market, an old woman sold woollen hats in a hundred shades of green, each one dyed with a different plant from the valley. She could tell, by the colour alone, which hillside and which season a hat had come from, and she was never once wrong.", author="Hugo Sinclair", book="The Slow Night Train", genre="Travel writing"},
    {text="The ferry across the lake departed whenever the captain finished his breakfast, which was a matter of some importance to the passengers waiting on the pier. We spent the wait watching pelicans and drinking coffee so strong that it seemed to hum inside the cup.", author="Ottilie Marsh", book="When the Captain Finishes", genre="Travel writing"},
    {text="The little coastal town was famous for its blue doors, each painted by the family who lived behind it. Walking down the main street felt like turning the pages of a large and slightly untidy picture book, where every page had a different weather and a different smell of bread.", author="Ottilie Marsh", book="When the Captain Finishes", genre="Travel writing"},
    {text="Our guide in the desert carried no map and needed none. He read the dunes the way a scholar reads a manuscript, pausing occasionally to smile at a familiar ridge, and when we finally reached the oasis he simply nodded at it, as if greeting an old friend he had not seen in a week.", author="Felix Ormond", book="Reading the Dunes", genre="Travel writing"},
    {text="The bus wound up the hillside past terraces of tea, each row exactly as wide as a picker could reach. In the misty morning, the workers moved like slow green waves, and the driver turned the radio down out of a respect that no one had ever asked him to show.", author="Felix Ormond", book="Reading the Dunes", genre="Travel writing"},
    {text="At the harbour cafe the waiter brought us a plate of grilled fish and a small dish of lemons without being asked. When we tried to pay, he shook his head and said the sea had already charged us plenty, since we had come so far to see it.", author="Rowena Hartley", book="The Sea Charges Enough", genre="Travel writing"},
    {text="Every evening the square filled with old men playing draughts on wooden tables, and every evening they argued as though each game were the final of a great tournament. A visitor could sit for hours and never understand the rules, yet leave feeling thoroughly entertained.", author="Rowena Hartley", book="The Sea Charges Enough", genre="Travel writing"},
    {text="I found the bookshop by accident, tucked between a pharmacy and a shop that sold only umbrellas. The owner, a tall man with ink on his cuffs, recommended a novel I had never heard of, and told me to return the book on my next visit, whenever that might be.", author="Emmett Rowan", book="Between the Umbrellas", genre="Travel writing"},
    {text="From the top of the cathedral tower, the city looked like a crowded drawing of itself, with red roofs, narrow streets, and small clouds of chimney smoke. A child beside me pointed at his own house and announced, with great confidence, that it was the only one that mattered.", author="Emmett Rowan", book="Between the Umbrellas", genre="Travel writing"},
    {text="Biologists studying a small colony of bats noticed that the animals changed their flight paths whenever a new building was erected nearby, even if the structure was several streets away. The finding suggested that bats map their surroundings in far more detail than anyone had previously assumed.", author="Dr. Alan Whitfield", book="Maps in the Dark", genre="Popular science"},
    {text="Geologists reading a cliff face along the coast found a thin band of volcanic ash sandwiched between layers of ordinary sand. The ash had travelled thousands of miles before settling, and it gave researchers a precise marker for dating every fossil found above and below it.", author="Dr. Alan Whitfield", book="Maps in the Dark", genre="Popular science"},
    {text="Astronomers watching a distant star noticed a faint, regular dimming that repeated every eleven days. After months of analysis, they concluded that a planet roughly the size of Jupiter was passing in front of it, tugging gently on the star as it went.", author="Dr. Helen Prakash", book="The Eleven Day Star", genre="Popular science"},
    {text="A team of chemists discovered that a common kitchen spice slowed the decay of certain paints, which explained why some old murals had stayed bright for centuries. Restorers soon began testing the same substance on damaged frescoes, with encouraging early results.", author="Dr. Helen Prakash", book="The Eleven Day Star", genre="Popular science"},
    {text="Ecologists tracking a herd of migrating deer found that the animals paused every few miles to eat a specific type of moss. When researchers analysed the moss, they discovered it contained trace minerals that appeared to help the deer recover from the strain of the long journey.", author="Dr. Gregor Vance", book="The Moss Route", genre="Popular science"},
    {text="Engineers testing a new kind of concrete were surprised to see hairline cracks close on their own after a heavy rain. The secret was a population of dormant bacteria in the mixture, which woke up in the damp and produced limestone to seal every gap.", author="Dr. Gregor Vance", book="The Moss Route", genre="Popular science"},
    {text="Sleep researchers monitoring volunteers in a dark laboratory found that most people naturally drifted toward two separate periods of rest each night. The discovery revived an old historical notion, that our ancestors once slept in two shifts with a quiet hour of wakefulness between.", author="Dr. Miriam Solis", book="Two Shifts of Night", genre="Popular science"},
    {text="Oceanographers listening to underwater microphones recorded a low, steady rumble that seemed to travel across an entire basin. It turned out to be the sound of ice shelves grinding against the seabed, thousands of kilometres away, carried effortlessly through the cold water.", author="Dr. Miriam Solis", book="Two Shifts of Night", genre="Popular science"},
    {text="Botanists comparing two neighbouring forests noticed that the trees in one of them grew noticeably taller, despite identical soil and rainfall. The difference was traced to an underground network of fungi, which shared nutrients between roots like a slow and quiet postal system.", author="Dr. Theodore Marsh", book="The Quiet Postal System", genre="Popular science"},
    {text="Physicists building a very sensitive clock found that it ran slightly faster on the top shelf than on the bottom one. The difference was tiny, but it matched the predictions of relativity so closely that the team celebrated with tea and a slightly nervous toast.", author="Dr. Theodore Marsh", book="The Quiet Postal System", genre="Popular science"},
    {text="A traveller once asked an old gardener why he pruned the roses so severely each winter. The gardener replied that the plant does not grow in spite of the cutting, but because of it, and that the same is true of most things worth keeping.", author="Alistair Penhallow", book="The Winter Pruning", genre="Philosophical prose"},
    {text="The student asked the teacher how one might know whether a decision was wise. The teacher said that wise decisions rarely feel triumphant at the moment they are made, but often feel quiet, a little heavy, and strangely calm afterward, like a door closing softly.", author="Alistair Penhallow", book="The Winter Pruning", genre="Philosophical prose"},
    {text="There is a kind of silence that belongs only to the early morning, before the first cart, before the first bell. In that silence a person can hear their own thoughts distinctly, which is perhaps why so many of us are afraid to wake early and listen.", author="Genevieve Rook", book="Before the First Bell", genre="Philosophical prose"},
    {text="A well-worn path across a field is not a plan but a memory. Countless people, each taking a small shortcut, have drawn it together without ever meeting, and the lesson may be that agreement does not always require a conversation.", author="Genevieve Rook", book="Before the First Bell", genre="Philosophical prose"},
    {text="The potter told his apprentice that a cracked bowl is not a failure but a record, since it shows exactly where the clay was weakest. He kept every broken piece on a shelf, and visitors often asked why a craftsman would display his mistakes so proudly.", author="Nathaniel Frost", book="The Potter's Shelf", genre="Philosophical prose"},
    {text="Time, the old clockmaker liked to say, is not a river but a room, and we simply walk through it one board at a time. He believed that nothing was ever lost, only left behind on the floor a few steps back, where the light still fell softly.", author="Nathaniel Frost", book="The Potter's Shelf", genre="Philosophical prose"},
    {text="To be generous with attention is harder than to be generous with money, because attention cannot be counted or returned. Yet the people we remember most fondly are rarely those who gave us gifts, but those who once listened without glancing at the clock.", author="Imogen Vale", book="Attention", genre="Philosophical prose"},
    {text="It is easy to forgive a stranger and difficult to forgive a friend, since a stranger has never promised us anything. The measure of a friendship may be the amount of disappointment it can absorb before it turns, quietly, into something deeper and more honest.", author="Imogen Vale", book="Attention", genre="Philosophical prose"},
    {text="Some questions are like seeds, and answering them too quickly is like eating them before they can sprout. The wise person carries a few good questions for years, watering them occasionally, and is rarely surprised when one of them finally blossoms into understanding.", author="Ferdinand Lyle", book="Seeds and Questions", genre="Philosophical prose"},
    {text="The lighthouse does not chase the ships, nor does it apologise for the rocks. It simply stands in its place and shines, and this, perhaps, is the most honest kind of usefulness that any of us can hope to offer to anyone else.", author="Ferdinand Lyle", book="Seeds and Questions", genre="Philosophical prose"},
    {text="They met on a rainy platform when she offered him half of her umbrella, and he offered her half of his sandwich in return. By the time the train arrived, they had agreed that it was the most sensible trade either of them had made all year.", author="Juliet Harcourt", book="Half an Umbrella", genre="Romance"},
    {text="He wrote her a note every morning and hid it inside the sugar bowl, on the theory that nobody could be unhappy while stirring their tea. After fifteen years the sugar bowl was full of paper, and the tea had never once tasted so sweet.", author="Juliet Harcourt", book="Half an Umbrella", genre="Romance"},
    {text="She was a florist who spoke to every bouquet as she arranged it, and he was a postman who spoke to every door as he knocked. Their first conversation lasted exactly seven minutes, and both later insisted that it had felt like a single, perfect sentence.", author="Rupert Ainsley", book="Bouquets and Doors", genre="Romance"},
    {text="The letters between them crossed the ocean by ship, and each took three weeks to arrive. When they finally met, they discovered that they already knew each other's handwriting, favourite words, and the exact length of each other's pauses, which is a rare kind of intimacy.", author="Rupert Ainsley", book="Bouquets and Doors", genre="Romance"},
    {text="At the dance, he stepped on her foot twice and apologised three times, and she told him that she had never been so charmed by clumsiness. They danced the rest of the evening very slowly, mostly to avoid further accidents, and neither of them wanted the music to end.", author="Cecily Rowland", book="Two Left Feet", genre="Romance"},
    {text="The old couple still held hands while crossing the street, though both of them could see perfectly well and neither had ever been in any danger. When asked why, the husband said that it was simply a habit, and the wife said it was a decision she renewed every single day.", author="Cecily Rowland", book="Two Left Feet", genre="Romance"},
    {text="He proposed on a small, crooked bridge in the middle of the park, mostly because he had lost the restaurant reservation and did not want to waste the ring. She said yes before he had finished the sentence, and the ducks below applauded in their usual, noisy, and completely unprompted fashion.", author="Tobias Merrin", book="The Crooked Bridge", genre="Romance"},
    {text="Every year on their anniversary, they returned to the same bench and ate the same terrible sandwiches from the same little shop. It was, they agreed, the least romantic tradition imaginable, and therefore the only one that could truly be counted upon to last.", author="Tobias Merrin", book="The Crooked Bridge", genre="Romance"},
    {text="When the power failed across the whole city, she lit a candle in the window and he saw it from three streets away. He walked there through the dark with a torch and a bag of oranges, and stayed until the lights came back and then a little longer.", author="Annabel Sutton", book="Three Streets Away", genre="Romance"},
    {text="She kept his old scarf in the hall cupboard long after they had parted, telling herself that it was too good to throw away. When he finally rang the bell to collect it, she handed it over without a word, and both of them looked at the floor for some time.", author="Annabel Sutton", book="Three Streets Away", genre="Romance"},
    {text="The radio operator spent the long winter nights tapping out messages in a cold, cramped shelter, and learned to recognise each distant colleague by the rhythm of their fingers. Years afterward he could still pick out three or four of them in a crowded room simply by the way they tapped a table.", author="Colonel Ernest Barrow", book="Rhythm of the Wire", genre="War memoir"},
    {text="Our cook carried a small tin of salt through the whole campaign and guarded it more fiercely than his rifle. He claimed that a meal without salt was a surrender, and on the coldest nights, that tin did more for morale than any speech from headquarters.", author="Colonel Ernest Barrow", book="Rhythm of the Wire", genre="War memoir"},
    {text="The field hospital was set up in a schoolhouse, and the nurses worked among tiny desks and faded maps of a peaceful world. One evening a wounded soldier asked for a pencil, and used it to correct a spelling mistake on the blackboard before he fell asleep.", author="Margaret Dunmore", book="The Schoolhouse Ward", genre="War memoir"},
    {text="My brother wrote to me from the front every fortnight, describing the weather in careful detail and never once mentioning the fighting. I understood only later that the weather was the only thing he was certain he could describe honestly to a person he loved.", author="Margaret Dunmore", book="The Schoolhouse Ward", genre="War memoir"},
    {text="The bridge had been destroyed twice, and twice the engineers rebuilt it overnight using whatever timber they could find. On the third morning a farmer arrived with his cart and asked politely whether he might cross, and the sergeant, after a moment, saluted him.", author="Major Peter Halloran", book="The Third Morning", genre="War memoir"},
    {text="We marched for eleven days through mud that swallowed boots and patience alike. On the twelfth day the sun came out, and the whole column stopped without an order, simply standing in the light with their faces raised like a field of tired flowers.", author="Major Peter Halloran", book="The Third Morning", genre="War memoir"},
    {text="The pilot kept a photograph of his mother tucked inside his cap, and swore that the plane flew better whenever he remembered to touch it before take-off. The mechanics found this entirely reasonable, and began tucking small charms of their own inside the engine covers.", author="Sergeant Walter Finch", book="Inside the Cap", genre="War memoir"},
    {text="At dusk the men gathered around a single lantern to hear the letters read aloud, since half of them could not read and the other half preferred to listen. The reader never hurried, and every man, regardless of rank, waited for his turn with the same patient face.", author="Sergeant Walter Finch", book="Inside the Cap", genre="War memoir"},
    {text="When the ceasefire was announced, nobody cheered at first. The men simply put down their tools, sat on their helmets, and looked at one another in disbelief, as though someone had just told them that the sea had been switched off.", author="Captain Leonard Rooke", book="The Silent Ceasefire", genre="War memoir"},
    {text="The village we passed through on the way home had lost every window, but the baker was already at work, sliding loaves into a battered oven. He gave each of us a warm roll and refused payment, saying that the first bread after war should always be a gift.", author="Captain Leonard Rooke", book="The Silent Ceasefire", genre="War memoir"},
    {text="Old Tom rose before the cockerel every morning, not from duty but from a private belief that the fields liked to be greeted first. He walked the boundary hedge with his stick, muttering good mornings to each gatepost, and his barley, everyone agreed, grew a shade taller than anyone else's.", author="Wilfred Hollis", book="Good Mornings to the Gateposts", genre="Rural fiction"},
    {text="The shepherd knew each sheep by her cough, and could tell from the far end of the valley which ewe had wandered from the flock. His neighbours trusted him with their animals the way they might trust a good clock, without ever thinking to check the time.", author="Wilfred Hollis", book="Good Mornings to the Gateposts", genre="Rural fiction"},
    {text="After the hay was cut, the whole village gathered in the meadow for a long, lazy supper, with tablecloths laid straight upon the stubble. The old told stories of hard winters and lucky summers, and the young listened, chewing slowly and learning what a loaf of bread really costs.", author="Agatha Fenwick", book="Supper in the Meadow", genre="Rural fiction"},
    {text="The blacksmith shod horses exactly as his grandfather had done, ignoring the shiny new shoes brought by the salesman from the city. Farmers travelled miles out of their way to visit him, partly for the quality of his work, and partly for the pleasure of watching sparks fly.", author="Agatha Fenwick", book="Supper in the Meadow", genre="Rural fiction"},
    {text="The mill only worked when the river was high, so the miller organised his whole life around the water, like a sailor around the tide. His neighbours joked that he had married the river before his wife, and the wife, to her credit, generally agreed.", author="Ambrose Tull", book="The Miller and the River", genre="Rural fiction"},
    {text="Each autumn the village slaughtered one pig together and shared the meat equally among all households, which made the day feel more like a festival than a chore. Children remembered it long after they had forgotten the details of every other season of their childhood.", author="Ambrose Tull", book="The Miller and the River", genre="Rural fiction"},
    {text="The village schoolmistress taught four classes in a single room, seating the pupils in rows by age and somehow keeping four lessons in her head at once. Former pupils spoke of her decades later with the particular fondness reserved for people who were never once bored by them.", author="Prudence Ashworth", book="Four Classes, One Room", genre="Rural fiction"},
    {text="The beekeeper told his grandson that the hive knows tomorrow's weather better than any barometer, and advised him to watch the bees rather than the sky. The boy never forgot the lesson, and forty years later still glanced at a hive before planning a picnic.", author="Prudence Ashworth", book="Four Classes, One Room", genre="Rural fiction"},
    {text="The thatcher travelled from farm to farm with a ladder and a bundle of straw, never asking for payment in advance. He trusted every household to settle up after the first winter, and in fifty years of work, he could not recall a single person who had let him down.", author="Horace Lindley", book="Straw and Ladder", genre="Rural fiction"},
    {text="The widows of the parish took turns helping each other with the harvest, dividing the weeks between their farms long before the first sheaf was cut. The arrangement was never written down, yet it lasted longer than any contract signed in the market town.", author="Horace Lindley", book="Straw and Ladder", genre="Rural fiction"},
    {text="The town archive holds the correspondence of the engineers who built the first stone bridge across the river, and their letters show that the plans for the piers were revised four times. It was this careful, quarrelsome process that gave the bridge its remarkable strength.", author="Cornelius Ward", book="Letters on the Piers", genre="Documentary essay"},
    {text="A rural doctor kept a daily record of his visits for thirty years, noting not only symptoms but also prices at the market and the state of the roads. Historians now treat his notebooks as one of the richest sources for understanding everyday life in the district.", author="Cornelius Ward", book="Letters on the Piers", genre="Documentary essay"},
    {text="Volunteers recently digitised fifty years of a local newspaper, and discovered that the small advertisements for lost livestock reveal how families moved from farm to farm. No official report of the period had recorded such movement so faithfully or so casually.", author="Eleanor Sharpe", book="Small Advertisements", genre="Documentary essay"},
    {text="Records from an old cotton mill show exactly when each new loom was installed, along with the names of the men who oversaw them. The dates sometimes contradict the company's own history, which insisted for many years that the machines had arrived all in a single season.", author="Eleanor Sharpe", book="Small Advertisements", genre="Documentary essay"},
    {text="For a hundred and twenty years, a small weather station on the hill recorded the temperature every morning at eight. Its unbroken series of numbers is now valued by climate scientists as one of the most reliable local records in the entire region.", author="Gideon Marlowe", book="Eight in the Morning", genre="Documentary essay"},
    {text="Two teachers in different towns wrote to each other for forty years, sharing lesson plans and complaints, yet never met in person. Their surviving letters, gathered into a single volume, offer a warm and surprisingly funny portrait of classroom life in a changing century.", author="Gideon Marlowe", book="Eight in the Morning", genre="Documentary essay"},
    {text="The lighthouse log book lists every ship that passed the headland over fifty years, with the time, the weather and, occasionally, a short remark about the crew. Together these small entries form a detailed history of the local sea trade that no harbour office ever compiled.", author="Phoebe Langdon", book="Every Ship That Passed", genre="Documentary essay"},
    {text="Municipal records preserve the technical drawings for the first houses to receive running water, and engineers have found them invaluable when repairing the old pipes. The drawings are neat, precise, and annotated in the handwriting of a clerk who clearly took pride in his work.", author="Phoebe Langdon", book="Every Ship That Passed", genre="Documentary essay"},
    {text="Old tram tickets, found in a shoebox at a flea market, allowed a group of enthusiasts to reconstruct the routes of a network that had disappeared before anyone had thought to map it. The project took two years and produced a map that now hangs in the city museum.", author="Lucas Pemberton", book="Tickets in a Shoebox", genre="Documentary essay"},
    {text="A retired postman spent a decade collecting the stories of the streets he had walked, interviewing former customers and noting the changes in each house. His handwritten volumes are now consulted by architects who want to understand how the town truly looked and lived.", author="Lucas Pemberton", book="Tickets in a Shoebox", genre="Documentary essay"},
    {text="The coach made the team practise one corner kick until they could do it in their sleep, and the players quietly groaned every afternoon for a month. In the final minute of the championship, that one rehearsed move produced the only goal of the match.", author="Reggie Calloway", book="One Corner Kick", genre="Sports fiction"},
    {text="The swimmer started training at five each morning, long before the main pool opened, having arranged a single lane with the caretaker. Two years of such discipline gave her a regional record that stood for almost a decade, and the caretaker was invited to the ceremony.", author="Reggie Calloway", book="One Corner Kick", genre="Sports fiction"},
    {text="The chess player studied his opponent's old games for three weeks before the tournament, searching for the smallest habits in the opening moves. In the final round, that preparation allowed him to spot a rarely used trap and to spring it at exactly the right moment.", author="Lydia Bannerman", book="The Opening Habit", genre="Sports fiction"},
    {text="The marathon runner trained on the same riverside path every morning, choosing the roughest sections on purpose so that his legs would be ready for any surface. The neighbours long ago stopped remarking on the lone figure moving through the early mist.", author="Lydia Bannerman", book="The Opening Habit", genre="Sports fiction"},
    {text="The gymnast repeated a single sequence hundreds of times, matching every turn to a note in the music until the two became one thing. The judges at the final competition singled out that sequence as the most technically perfect moment of the entire evening.", author="Oswald Kerrigan", book="Matching the Music", genre="Sports fiction"},
    {text="The goalkeeper watched film of every opposing striker before each match and kept notes in a small black book. His teammates joked that the notebook was worth more to the club than the entire transfer budget, and he never once disagreed with them.", author="Oswald Kerrigan", book="Matching the Music", genre="Sports fiction"},
    {text="The weightlifter recorded every training session in a notebook, noting not only the weights lifted but also how he felt that day. After several years, the record revealed patterns that no coach had ever noticed, and he adjusted his routine accordingly.", author="Frances Mortimer", book="The Training Notebook", genre="Sports fiction"},
    {text="The figure skater changed coaches halfway through the season, a risky move that alarmed her family. The new coach altered a single element of her programme, one that everyone had accepted as her weakness, and the change carried her onto the podium for the very first time.", author="Frances Mortimer", book="The Training Notebook", genre="Sports fiction"},
    {text="The rower spent his early mornings studying the current at different times of day, learning exactly when the river would help him and when it would resist. His rivals dismissed the habit as eccentric, until they saw the time posted on the finishing board.", author="Kenneth Ashdown", book="Reading the Current", genre="Sports fiction"},
    {text="The young tennis player wrote down the result of every practice serve in a small notebook, hunting for patterns in her errors on windy days. By the end of the season, the notebook had become a handbook that her younger teammates borrowed and passed around.", author="Kenneth Ashdown", book="Reading the Current", genre="Sports fiction"},
}


local CLAVA_SOURCE_RUNTIME = {
    ru = {used={}, lastBook="", lastAuthor="", lastGenre="", lastFirstLetter="", lastFirstWord="", firstLetterCount={}, firstWordCount={}, authorCount={}, bookCount={}, genreCount={}},
    en = {used={}, lastBook="", lastAuthor="", lastGenre="", lastFirstLetter="", lastFirstWord="", firstLetterCount={}, firstWordCount={}, authorCount={}, bookCount={}, genreCount={}},
}

function clavaSourceTextKey(text)
    local low = tostring(text or ""):lower()
    low = low:gsub("[%p%c]+", " ")
    low = low:gsub("%s+", " "):gsub("^%s+", ""):gsub("%s+$", "")
    return low
end

function clavaSourceFirstWord(text)
    local chars = utf8_chars(text or "")
    local out = {}
    for i = 1, #chars do
        local ch = chars[i]
        if ch == " " or ch == "\n" or ch == "\r" or ch == "\t" then break end
        out[#out + 1] = ch
    end
    return table.concat(out):lower():gsub("^[%p]+", ""):gsub("[%p]+$", "")
end

function clavaSourceFirstLetter(text)
    local chars = utf8_chars(text or "")
    for i = 1, #chars do
        local ch = chars[i]
        local cp = utf8_codepoint(ch)
        if ch:match("%a") or (cp >= 0x410 and cp <= 0x44F) then
            return utf8_lower_char(ch)
        end
    end
    return "#"
end

function clavaAuditPlayableText(text, layout, enforceLength)
    local normalized = clavaNormalizePlayableText(text, layout)
    local allowed = CLAVA_PLAYABLE_SET[(layout == "en") and "en" or "ru"]
    local bad = {}
    for _, ch in ipairs(utf8_chars(normalized)) do
        if not allowed[ch] then bad[ch] = true end
    end
    local charCount = #utf8_chars(normalized)
    local byteCount = #normalized
    local lengthOk = (not enforceLength) or (charCount >= CLAVA_TEXT_MIN_CHARS and charCount <= CLAVA_TEXT_MAX_CHARS)
    local bufferOk = byteCount + 1 <= CLAVA_INPUT_BUFFER_BYTES
    return normalized, next(bad) == nil, lengthOk, bufferOk
end



function clavaNormalizeSourcePool(pool, layout)
    local out, seen = {}, {}
    layout = (layout == "en") and "en" or "ru"
    for _, item in ipairs(pool or {}) do
        if item and tostring(item.text or "") ~= ""
            and tostring(item.author or "") ~= ""
            and tostring(item.book or "") ~= ""
            and tostring(item.genre or "") ~= "" then
            local normalizedItem = clavaNormalizeSourceItem(item, layout)
            local normalizedText = normalizedItem.text
            local _, charsOk, lengthOk, bufferOk = clavaAuditPlayableText(normalizedText, layout, true)
            local key = clavaSourceTextKey(normalizedText)
            if key ~= "" and charsOk and lengthOk and bufferOk and not seen[key] then
                seen[key] = true
                out[#out + 1] = normalizedItem
            end
        end
    end
    return out
end

CLAVA_SOURCE_RU = clavaNormalizeSourcePool(CLAVA_SOURCE_RU, "ru")

CLAVA_SOURCE_EN = clavaNormalizeSourcePool(CLAVA_SOURCE_EN, "en")


function clavaSourceInRange(text, minLen, maxLen)
    local n = #utf8_chars(text or "")
    return n >= minLen and n <= maxLen
end


function clavaSourceState(lang)
    local state = CLAVA_SOURCE_RUNTIME[lang]
    if not state then
        state = {used={}, lastBook="", lastAuthor="", lastGenre="", lastFirstLetter="", lastFirstWord="", firstLetterCount={}, firstWordCount={}, authorCount={}, bookCount={}, genreCount={}}
        CLAVA_SOURCE_RUNTIME[lang] = state
    end
    return state
end

function clavaPickSourceCandidate(candidates, state)
    if #candidates > 1 then
        local nonA = {}
        for _, c in ipairs(candidates) do
            if c.firstLetter ~= "a" then nonA[#nonA + 1] = c end
        end
        if #nonA > 0 then
            candidates = nonA
        end
    end
    local bestScore = math.huge
    local best = {}

    for _, c in ipairs(candidates) do
        local score = 0
        local item = c.item
        local letterCount = state.firstLetterCount[c.firstLetter] or 0
        local wordCount = state.firstWordCount[c.firstWord] or 0
        local authorCount = state.authorCount[item.author] or 0
        local bookCount = state.bookCount[item.book] or 0
        local genreCount = state.genreCount[item.genre] or 0

        score = score + letterCount * 1000
        score = score + wordCount * 450
        score = score + authorCount * 70
        score = score + bookCount * 120
        score = score + genreCount * 90
        if c.firstLetter == state.lastFirstLetter then score = score + 1800 end
        if c.firstWord == state.lastFirstWord then score = score + 1500 end
        if item.author == state.lastAuthor then score = score + 12000 end
        if item.book == state.lastBook then score = score + 50000 end
        if item.genre == state.lastGenre then score = score + 1800 end
        score = score + math.random()

        if score < bestScore - 0.000001 then
            bestScore = score
            best = {c}
        elseif math.abs(score - bestScore) <= 0.000001 then
            best[#best + 1] = c
        end
    end

    if #best == 0 then return nil end
    return best[math.random(1, #best)]
end

function pickLiterarySource(pool, lang, avoid)
    if not pool or #pool == 0 then return "", nil end





    local minLen = CLAVA_TEXT_MIN_CHARS
    local maxLen = CLAVA_TEXT_MAX_CHARS
    local candidates = {}
    local candidatesWithoutPrevious = {}

    for i, item in ipairs(pool) do
        local text = tostring(item.text or "")
        if clavaSourceInRange(text, minLen, maxLen) then
            local candidate = {
                index = i,
                item = item,
            }
            candidatesWithoutPrevious[#candidatesWithoutPrevious + 1] = candidate
            if text ~= tostring(avoid or "") then
                candidates[#candidates + 1] = candidate
            end
        end
    end

    local list = (#candidates > 0) and candidates or candidatesWithoutPrevious
    if #list == 0 then return "", nil end

    local chosen = list[math.random(1, #list)]
    if not chosen or not chosen.item then return "", nil end

    local item = chosen.item
    return item.text, {
        author = item.author or "",
        book = item.book or "",
        genre = item.genre or "",
    }
end

function genNormalText(avoid) return pickLiterarySource(CLAVA_SOURCE_RU, "ru", avoid) end
function genEnglishText(avoid) return pickLiterarySource(CLAVA_SOURCE_EN, "en", avoid) end





local PUNCT_BUILDERS = {
    function()
        return (math.random(1, 2) == 1)
            and u8"Когда дежурный вошел в архив, начальник спросил: \"Кто закрыл шкаф?\" - никто не ответил; только сторож пожал плечами."
            or u8"Утром диспетчер уточнил: \"Маршрут уже изменили?\" - механик ответил, что нет, но добавил: \"Проверьте карту еще раз\"."
    end,
    function()
        return (math.random(1, 2) == 1)
            and u8"Документы лежали в сейфе; папку, которую искали весь день, нашли позже (она оказалась в соседнем ящике)."
            or u8"В журнале было три записи; последняя - самая короткая (и, как ни странно, самая важная)."
    end,
    function()
        return (math.random(1, 2) == 1)
            and u8"\"Не спеши, проверь цифры!\" - сказала Ольга, - и тут же добавила: \"Ошибка может быть совсем рядом...\""
            or u8"\"Стой!\" - крикнул проводник, - потом посмотрел на часы (времени почти не осталось) и снова замолчал."
    end,
    function()
        return (math.random(1, 2) == 1)
            and u8"Если поезд задержится, придется менять план: сначала ждать, потом звонить диспетчеру, а уже после - искать запасной маршрут."
            or u8"Если отчет готов, отправь его сегодня: утром проверят подписи, днем сверят даты, вечером закроют дело."
    end,
    function()
        return (math.random(1, 2) == 1)
            and u8"Причина оказалась простой - сломался старый датчик; новый уже привезли, но установить его успели только к ночи."
            or u8"Решение было неожиданным - перенести встречу; участники согласились быстро, хотя еще минуту назад спорили о сроках."
    end,
    function()
        return (math.random(1, 2) == 1)
            and u8"В папке нашлись заметки, фотографии и карта: все три листа были помечены одним знаком, но дата на обороте отличалась."
            or u8"На столе остались блокнот, ключи и конверт: казалось бы, обычный набор, однако внутри конверта лежала только одна записка."
    end,
    function()
        return (math.random(1, 2) == 1)
            and u8"Он перечитал письмо еще раз - медленно, по словам, - затем подчеркнул две фразы и сказал: \"Теперь понятно, что делать\"."
            or u8"Она сверила список еще раз - спокойно, без спешки, - и вдруг заметила: одна фамилия повторялась дважды."
    end,
    function()
        return (math.random(1, 2) == 1)
            and u8"Вопрос был коротким: \"Вы точно видели этот знак?\" Ответ тоже оказался коротким; свидетель кивнул и показал на окно."
            or u8"Вопрос звучал просто: \"Кто оставил ключ?\" Ответ задержался; потом охранник вспомнил одну деталь (он видел незнакомца у двери)."
    end,
    function()
        return (math.random(1, 2) == 1)
            and u8"Проверили все: двери, окна, замки; ничего подозрительного не нашли. Но когда выключили свет, раздался странный щелчок..."
            or u8"Осмотрели все: полки, коробки, стол; следов не было. И все же перед уходом кто-то тихо сказал: \"Подождите...\""
    end,
    function()
        return (math.random(1, 2) == 1)
            and u8"Диспетчер записал время (18:40), номер вагона (7) и фамилию машиниста; затем поставил точку и закрыл журнал."
            or u8"Секретарь отметила время (09:15), номер кабинета (12) и тему встречи; после этого добавила: \"Перенос подтвержден\"."
    end,
}

function genPunct(avoid)
    local minLen = CLAVA_TEXT_MIN_CHARS
    local maxLen = CLAVA_TEXT_MAX_CHARS
    local tries = 0

    repeat
        tries = tries + 1
        local parts = {}
        local total = 0



        local order = {1, 2, 3, 4, 5}
        for i = #order, 2, -1 do
            local j = math.random(1, i)
            order[i], order[j] = order[j], order[i]
        end

        for _, idx in ipairs(order) do
            local piece = PUNCT_BUILDERS[idx]()
            local add = (total > 0) and 1 or 0
            local pieceLen = clavaTextLength(piece)
            if total + add + pieceLen <= maxLen - 20 then
                parts[#parts + 1] = piece
                total = total + add + pieceLen
            end
        end



        local extraCount = math.random(1, 3)
        for _ = 1, extraCount do
            local idx = math.random(1, #PUNCT_BUILDERS)
            local piece = PUNCT_BUILDERS[idx]()
            local add = (total > 0) and 1 or 0
            local pieceLen = clavaTextLength(piece)
            if total + add + pieceLen <= maxLen - 8 then
                parts[#parts + 1] = piece
                total = total + add + pieceLen
            end
        end

        local text = table.concat(parts, " ")
        local sameAsPrevious = text == tostring(avoid or "")
        local punctuationCount = 0
        for _, ch in ipairs(utf8_chars(text)) do
            if ch == "," or ch == "." or ch == ":" or ch == ";"
                or ch == "-" or ch == "(" or ch == ")" or ch == "\""
                or ch == "?" or ch == "!" then
                punctuationCount = punctuationCount + 1
            end
        end

        if clavaTextFitsPlayableLimits(text, minLen, maxLen)
            and not sameAsPrevious and punctuationCount >= 24 then
            return text, {
                author = u8"Тренажер пунктуации",
                book = u8"Знаки в контексте",
                genre = u8"Пунктуационный тренинг",
            }
        end
    until tries >= 30



    local fallback = PUNCT_BUILDERS[1]() .. " " .. PUNCT_BUILDERS[2]()
    return fallback, {
        author = u8"Тренажер пунктуации",
        book = u8"Знаки в контексте",
        genre = u8"Пунктуационный тренинг",
    }
end

function genOneMistakeText(avoid) return pickLiterarySource(CLAVA_SOURCE_RU, "ru", avoid) end

function genHundred()

    local count = math.random(34, 50)
    local doubleCount = 101 - 2 * count
    local parts = {}

    for i = 1, doubleCount do
        parts[#parts + 1] = string.format("%02d", math.random(0, 99))
    end
    for i = doubleCount + 1, count do
        parts[#parts + 1] = tostring(math.random(0, 9))
    end

    for i = #parts, 2, -1 do
        local j = math.random(1, i)
        parts[i], parts[j] = parts[j], parts[i]
    end
    return table.concat(parts, " ")
end

function genCaptcha()
    local parts = {}
    for i = 1, 20 do
        parts[#parts + 1] = string.format("%05d", math.random(0, 99999))
    end
    return table.concat(parts, " ")
end

function genNumbers()
    local parts = {}
    local total = 0
    local target = 300

    local function randDigits(width)
        local chars = {}
        for i = 1, width do chars[#chars + 1] = tostring(math.random(0, 9)) end
        return table.concat(chars)
    end

    while total < target do
        local extra = (#parts > 0) and 1 or 0
        local remaining = target - total - extra
        if remaining <= 0 then break end

        local token
        if remaining <= 4 then
            token = randDigits(remaining)
        else
            local width = math.random(1, 4)
            token = randDigits(width)

            if math.random() < 0.24 then
                local decimals = math.random(1, 2)
                if width + 1 + decimals <= remaining then
                    token = token .. "," .. randDigits(decimals)
                end
            end
        end

        parts[#parts + 1] = token
        total = total + extra + #token
    end

    return table.concat(parts, " ")
end

local MODES = {
    { id = "normal", name = u8"Обычный текст", gen = genNormalText },
    { id = "english", name = u8"English Text", gen = genEnglishText, layout = "en" },
    { id = "hundred", name = u8"Цифросоточка", gen = genHundred },
    { id = "numbers", name = u8"Числа", gen = genNumbers },
    { id = "punct", name = u8"Пунктуация", gen = genPunct },
    { id = "captcha", name = u8"Тренировка капчи", gen = genCaptcha },
    { id = "onemistake", name = u8"Одна ошибка", gen = genOneMistakeText, oneMistake = true },
}

function getModeById(id)
    for _, m in ipairs(MODES) do if m.id == id then return m end end
    return MODES[1]
end

local MODE_COLORS = {
    colorVec(0.90, 0.55, 0.15), colorVec(0.35, 0.65, 0.85), colorVec(0.50, 0.78, 0.45),
    colorVec(0.85, 0.45, 0.55), colorVec(0.62, 0.55, 0.85), colorVec(0.90, 0.75, 0.25),
}

local MODE_BUTTON_COLORS = {
    colorVec(0.84, 0.84, 0.84),
    colorVec(0.96, 0.77, 0.52),
    colorVec(0.93, 0.69, 0.79),
    colorVec(0.76, 0.61, 0.48),
    colorVec(0.59, 0.79, 0.90),
    colorVec(0.90, 0.83, 0.48),
    colorVec(0.78, 0.69, 0.88),
}

local DICTIONARY_MODE_COLOR = colorVec(0.48, 0.78, 0.56)

function modeButtonColor(index)
    return MODE_BUTTON_COLORS[((tonumber(index) or 1) - 1) % #MODE_BUTTON_COLORS + 1]
end

function modeIndexById(id)
    for i, m in ipairs(MODES) do
        if m.id == id then return i end
    end
    return 1
end

function drawOutlinedButtonText(label, pmin, pmax, alpha)
    if not (imgui.GetWindowDrawList and imgui.CalcTextSize and imgui.ColorConvertFloat4ToU32) then return end
    local dl = imgui.GetWindowDrawList()
    if not dl or not label or not pmin or not pmax then return end
    local okSize, textSize = pcall(imgui.CalcTextSize, label)
    if not okSize or not textSize then return end
    local a = math.max(0, math.min(1, tonumber(alpha) or 1.0))
    local x = (pmin.x + pmax.x - textSize.x) * 0.5
    local y = (pmin.y + pmax.y - textSize.y) * 0.5
    local black = imgui.ColorConvertFloat4ToU32(colorVec(0, 0, 0, a))
    local white = imgui.ColorConvertFloat4ToU32(colorVec(1, 1, 1, a))
    local textPos = imgui.ImVec2(x, y)

    dl:AddText(imgui.ImVec2(x - 1, y), black, label)
    dl:AddText(imgui.ImVec2(x + 1, y), black, label)
    dl:AddText(imgui.ImVec2(x, y - 1), black, label)
    dl:AddText(imgui.ImVec2(x, y + 1), black, label)
    dl:AddText(imgui.ImVec2(x - 1, y - 1), black, label)
    dl:AddText(imgui.ImVec2(x + 1, y - 1), black, label)
    dl:AddText(imgui.ImVec2(x - 1, y + 1), black, label)
    dl:AddText(imgui.ImVec2(x + 1, y + 1), black, label)
    dl:AddText(textPos, white, label)
end

local iniFile = 'clava_races.ini'
local defaultCfg = {
    colors = {
        correct_r = 0.25, correct_g = 0.55, correct_b = 0.30,
        error_r   = 0.55, error_g   = 0.10, error_b   = 0.12,
        active_r  = 0.15, active_g  = 0.35, active_b  = 0.75,
        next_r    = 0.90, next_g    = 0.55, next_b    = 0.15,
    },
    settings = {
        countdown_seconds = 5,
        highlight_mode = 0,
        speedometer = 1,
        display_mode = 0,
        font_index = 0,
        text_scale = 1.0,
        char_spacing = 100,
        text_area_height = 150,
        style_index = 0,
        mode_id = "normal",
        fastchat_enabled = 0,
        fastchat_interval = 2000,
    },
    custom_dicts = { count = 0 },
    stats_debug = {
        enabled = 0,
        main_group_x = 118, main_group_y = 65,
        main_group_scale = 1.56,
        main_ring_x = 0, main_ring_y = 0,
        main_legend_x = 0, main_legend_y = 0,
        main_legend_1_x = 0, main_legend_1_y = 0,
        main_legend_2_x = 0, main_legend_2_y = 0,
        main_legend_3_x = 0, main_legend_3_y = 0,
        main_legend_4_x = 0, main_legend_4_y = 0,
        main_legend_5_x = 0, main_legend_5_y = 0,
        main_legend_6_x = 0, main_legend_6_y = 0,
        main_legend_7_x = 0, main_legend_7_y = 0,
        main_dict_x = 30, main_dict_y = 0,
        detail_back_x = 0, detail_back_y = 0,
        detail_title_x = 0, detail_title_y = 0,
        detail_card_1_x = 0, detail_card_1_y = 0,
        detail_card_2_x = 0, detail_card_2_y = 0,
        detail_card_3_x = 0, detail_card_3_y = 0,
        detail_card_4_x = 0, detail_card_4_y = 0,
        detail_toolbar_x = 0, detail_toolbar_y = 0,
        detail_chart_x = 0, detail_chart_y = 0,
        detail_table_x = 0, detail_table_y = 0,
    },
}
for _, m in ipairs(MODES) do
    defaultCfg["mode_" .. m.id] = { races = 0, best_speed = 0, best_accuracy = 0, history = "" }
end

cfg = defaultCfg
if ok_ini then
    local loaded = inicfg.load(defaultCfg, iniFile)
    if loaded then cfg = loaded end
end

cfg.colors = cfg.colors or defaultCfg.colors
cfg.settings = cfg.settings or defaultCfg.settings
cfg.settings.countdown_seconds = cfg.settings.countdown_seconds or 5
cfg.settings.highlight_mode = tonumber(cfg.settings.highlight_mode) or 0
cfg.settings.speedometer = tonumber(cfg.settings.speedometer) or 1
cfg.settings.display_mode = tonumber(cfg.settings.display_mode) or 0
cfg.settings.font_index = tonumber(cfg.settings.font_index) or 0
cfg.settings.text_scale = tonumber(cfg.settings.text_scale) or 1.0
cfg.settings.char_spacing = tonumber(cfg.settings.char_spacing) or 100
cfg.settings.text_area_height = tonumber(cfg.settings.text_area_height) or 150
cfg.settings.style_index = tonumber(cfg.settings.style_index) or 0
cfg.settings.mode_id = tostring(cfg.settings.mode_id or "normal")
cfg.settings.fastchat_enabled = tonumber(cfg.settings.fastchat_enabled) or 0
cfg.settings.fastchat_interval = tonumber(cfg.settings.fastchat_interval) or 2000
cfg.settings.fastchat_enabled = cfg.settings.fastchat_enabled ~= 0 and 1 or 0
cfg.settings.fastchat_interval = math.max(100, math.min(10000, math.floor(cfg.settings.fastchat_interval + 0.5)))
cfg.settings.text_min_chars = nil
cfg.settings.text_max_chars = nil

cfg.settings.text_scale = math.max(0.70, math.min(1.60, cfg.settings.text_scale))

if cfg.settings.char_spacing < 20 then cfg.settings.char_spacing = 100 end
cfg.settings.char_spacing = math.max(100, math.min(400, math.floor(cfg.settings.char_spacing + 0.5)))
cfg.settings.text_area_height = math.max(90, math.min(260, math.floor(cfg.settings.text_area_height + 0.5)))
cfg.settings.countdown_seconds = math.max(0, math.min(15, math.floor((tonumber(cfg.settings.countdown_seconds) or 5) + 0.5)))
cfg.custom_dicts = cfg.custom_dicts or { count = 0 }
cfg.custom_dicts.count = math.max(0, math.floor(tonumber(cfg.custom_dicts.count) or 0))
for i = 1, cfg.custom_dicts.count do
    local dsec = cfg["custom_dict_" .. i]
    if dsec then
        dsec.played = tonumber(dsec.played) or 0
        dsec.best_speed = tonumber(dsec.best_speed) or 0
        dsec.best_accuracy = tonumber(dsec.best_accuracy) or 0
        dsec.history = dsec.history or ""
    end
end
for _, m in ipairs(MODES) do
    cfg["mode_" .. m.id] = cfg["mode_" .. m.id] or { races = 0, best_speed = 0, best_accuracy = 0, history = "" }
end

cfg.stats_debug = cfg.stats_debug or defaultCfg.stats_debug
local STATS_DEBUG_DEFAULT_KEYS = {
    "main_group",
    "main_ring",
    "main_legend",
    "main_legend_1", "main_legend_2", "main_legend_3", "main_legend_4",
    "main_legend_5", "main_legend_6", "main_legend_7", "main_dict",
}
for _, key in ipairs(STATS_DEBUG_DEFAULT_KEYS) do
    cfg.stats_debug[key .. "_x"] = tonumber(cfg.stats_debug[key .. "_x"]) or 0
    cfg.stats_debug[key .. "_y"] = tonumber(cfg.stats_debug[key .. "_y"]) or 0
end
cfg.stats_debug.main_group_x = tonumber(cfg.stats_debug.main_group_x) or 118
cfg.stats_debug.main_group_y = tonumber(cfg.stats_debug.main_group_y) or 65
cfg.stats_debug.main_group_scale = math.max(0.50, math.min(2.00, tonumber(cfg.stats_debug.main_group_scale) or 1.56))
cfg.stats_debug.enabled = tonumber(cfg.stats_debug.enabled) or 0

cfg.settings.mode_id = getModeById(cfg.settings.mode_id).id

local cfgSavePending = false

local cfgSaveLastError = nil

local function writeCfgNow()
    if not ok_ini then
        cfgSaveLastError = "inicfg недоступен"
        return false
    end

    local ok, err = pcall(inicfg.save, cfg, iniFile)
    if not ok then
        cfgSaveLastError = tostring(err)
        cfgSavePending = true
        return false
    end

    cfgSaveLastError = nil
    cfgSavePending = false
    return true
end

function saveCfg()
    return writeCfgNow()
end

function flushCfgSave()
    if not cfgSavePending or not ok_ini then return false end
    return writeCfgNow()
end

pcall(writeCfgNow)

function historyAppend(modeId, entry)
    local sec = cfg["mode_" .. modeId]
    if not sec then return end
    local items = {}
    if sec.history and sec.history ~= "" then
        for part in sec.history:gmatch("[^;]+") do items[#items + 1] = part end
    end
    items[#items + 1] = string.format("%d:%d:%d:%d:%d", entry.speed, entry.accuracy, entry.errors, entry.time, entry.chars or 0)
    while #items > 30 do table.remove(items, 1) end
    sec.history = table.concat(items, ";")
end

function historyParse(modeId)
    local sec = cfg["mode_" .. modeId]
    local out = {}
    if sec and sec.history and sec.history ~= "" then
        for part in sec.history:gmatch("[^;]+") do
            local sp, ac, er, tm, chars = part:match("(%-?%d+):(%-?%d+):(%-?%d+):(%-?%d+):(%-?%d+)")
            if not sp then
                sp, ac, er, tm = part:match("(%-?%d+):(%-?%d+):(%-?%d+):(%-?%d+)")
            end
            if sp then
                out[#out + 1] = { speed = tonumber(sp), accuracy = tonumber(ac), errors = tonumber(er), time = tonumber(tm), chars = tonumber(chars) or 0 }
            end
        end
    end
    return out
end

function hexEncode(value)
    value = tostring(value or "")
    local out = {}
    for i = 1, #value do out[#out + 1] = string.format("%02X", value:byte(i)) end
    return table.concat(out)
end

function hexDecode(value)
    value = tostring(value or "")
    if value == "" then return "" end
    local out = {}
    for pair in value:gmatch("%x%x") do out[#out + 1] = string.char(tonumber(pair, 16)) end
    return table.concat(out)
end

function getCustomDictionary(index)
    index = tonumber(index) or 0
    if index < 1 or index > (cfg.custom_dicts.count or 0) then return nil end
    local sec = cfg["custom_dict_" .. index]
    if not sec then return nil end
    return {
        name = hexDecode(sec.name_hex or sec.name or ""),
        content = hexDecode(sec.content_hex or sec.content or ""),
    }
end

function customDictionaryStatsSection(index)
    index = tonumber(index)
    if not index or index < 1 then return nil end
    local sec = cfg["custom_dict_" .. index]
    if not sec then return nil end
    sec.played = tonumber(sec.played) or 0
    sec.best_speed = tonumber(sec.best_speed) or 0
    sec.best_accuracy = tonumber(sec.best_accuracy) or 0
    sec.history = sec.history or ""
    return sec
end

function customDictionaryHistoryAppend(index, entry)
    local sec = customDictionaryStatsSection(index)
    if not sec then return end
    local items = {}
    if sec.history ~= "" then
        for part in sec.history:gmatch("[^;]+") do items[#items + 1] = part end
    end
    items[#items + 1] = string.format("%d:%d:%d:%d:%d", entry.speed or 0, entry.accuracy or 0, entry.errors or 0, entry.time or os.time(), entry.chars or 0)
    while #items > 30 do table.remove(items, 1) end
    sec.history = table.concat(items, ";")
end

function customDictionaryHistoryParse(index)
    local sec = customDictionaryStatsSection(index)
    local out = {}
    if sec and sec.history ~= "" then
        for part in sec.history:gmatch("[^;]+") do
            local sp, ac, er, tm, chars = part:match("(%-?%d+):(%-?%d+):(%-?%d+):(%-?%d+):(%-?%d+)")
            if not sp then
                sp, ac, er, tm = part:match("(%-?%d+):(%-?%d+):(%-?%d+):(%-?%d+)")
            end
            if sp then
                out[#out + 1] = {
                    speed = tonumber(sp) or 0, accuracy = tonumber(ac) or 0, errors = tonumber(er) or 0,
                    time = tonumber(tm) or os.time(), chars = tonumber(chars) or 0
                }
            end
        end
    end
    return out
end

function saveCustomDictionary(index, name, content)
    index = tonumber(index)
    if not index or index < 1 then return false end
    local old = cfg["custom_dict_" .. index] or {}
    cfg["custom_dict_" .. index] = {
        name_hex = hexEncode(name),
        content_hex = hexEncode(content),
        played = tonumber(old.played) or 0,
        best_speed = tonumber(old.best_speed) or 0,
        best_accuracy = tonumber(old.best_accuracy) or 0,
        history = old.history or "",
    }
    cfg.custom_dicts.count = math.max(cfg.custom_dicts.count or 0, index)
    saveCfg()
    return true
end

function addCustomDictionary(name, content)
    name = tostring(name or ""):gsub("^%s+", ""):gsub("%s+$", "")
    content = tostring(content or ""):gsub("^%s+", ""):gsub("%s+$", "")
    if name == "" or content == "" then return false end
    local index = (cfg.custom_dicts.count or 0) + 1
    saveCustomDictionary(index, name, content)
    return index
end

function editCustomDictionary(index)
    local d = getCustomDictionary(index)
    if not d then return end
    ui.dictionaryEditIndex = tonumber(index) or 0
    ffi.fill(ui.dictionaryTitleBuffer, ffi.sizeof(ui.dictionaryTitleBuffer))
    ffi.fill(ui.dictionaryContentBuffer, ffi.sizeof(ui.dictionaryContentBuffer))
    ffi.copy(ui.dictionaryTitleBuffer, d.name or "", math.min(#(d.name or ""), ffi.sizeof(ui.dictionaryTitleBuffer) - 1))
    ffi.copy(ui.dictionaryContentBuffer, d.content or "", math.min(#(d.content or ""), ffi.sizeof(ui.dictionaryContentBuffer) - 1))
    ui.dictionaryWrapRaw = d.content or ""
    ui.dictionaryWrapWidth = 0
    ui.dictionaryWrapPending = true
end

function deleteCustomDictionary(index)
    index = tonumber(index)
    local count = cfg.custom_dicts.count or 0
    if not index or index < 1 or index > count then return end

    for i = index, count - 1 do
        local nextDict = cfg["custom_dict_" .. (i + 1)]
        if nextDict then
            cfg["custom_dict_" .. i] = nextDict
        else
            cfg["custom_dict_" .. i] = nil
        end
    end
    cfg["custom_dict_" .. count] = nil
    cfg.custom_dicts.count = math.max(0, count - 1)
    if ui.dictionaryEditIndex ~= 0 then
        ui.dictionaryEditIndex = 0
        ffi.fill(ui.dictionaryTitleBuffer, ffi.sizeof(ui.dictionaryTitleBuffer))
        ffi.fill(ui.dictionaryContentBuffer, ffi.sizeof(ui.dictionaryContentBuffer))
        ui.dictionaryWrapRaw = ""
        ui.dictionaryWrapWidth = 0
        ui.dictionaryWrapPending = true
    end
    saveCfg()
end

local DICT_WRAP = {}
DICT_WRAP.WORD_WRAP_FLAG = 16777216

function DICT_WRAP.unwrapSoftBreaks(value)
    value = tostring(value or "")
    value = value:gsub("\r\n", "\n"):gsub("\r", "\n")
    value = value:gsub("\194\173", "")
    value = value:gsub("\226\128\139", "")
    value = value:gsub("\226\128\140", "")
    value = value:gsub("\226\128\141", "")
    value = value:gsub("\239\187\191", "")
    return value
end

function DICT_WRAP.measure(text)
    local ok, sz = pcall(imgui.CalcTextSize, text or "")
    if ok and sz and sz.x then return sz.x end
    return (#utf8_chars(text or "")) * 7.0
end

function DICT_WRAP.getWidth()
    local ok, w = pcall(imgui.CalcItemWidth)
    if ok and w and w > 20 then return math.max(30, w - 8) end
    local ok2, avail = pcall(imgui.GetContentRegionAvail)
    if ok2 and avail and avail.x and avail.x > 20 then return math.max(30, avail.x - 8) end
    return 520
end

function DICT_WRAP.buildDisplay(raw, maxWidth)
    raw = DICT_WRAP.unwrapSoftBreaks(raw or "")
    maxWidth = tonumber(maxWidth) or 520
    maxWidth = math.max(30, maxWidth)

    local chars = utf8_chars(raw)
    local lines, line = {}, {}
    local lineW = 0
    local word, wordW = {}, 0
    local spaceW = DICT_WRAP.measure(" ")

    local function flushLine()
        lines[#lines + 1] = table.concat(line)
        line = {}
        lineW = 0
    end

    local function putWord()
        if #word == 0 then return end
        if wordW <= maxWidth then
            if lineW > 0 and lineW + wordW > maxWidth then
                flushLine()
            end
            for i = 1, #word do
                line[#line + 1] = word[i].ch
                lineW = lineW + word[i].w
            end
        else
            if lineW > 0 then flushLine() end
            for i = 1, #word do
                local cell = word[i]
                if lineW > 0 and lineW + cell.w > maxWidth then
                    flushLine()
                end
                line[#line + 1] = cell.ch
                lineW = lineW + cell.w
            end
        end
        word, wordW = {}, 0
    end

    for i = 1, #chars do
        local ch = chars[i]
        if ch == "\n" then
            putWord()
            flushLine()
        elseif ch == " " then
            putWord()

            if lineW > 0 and lineW + spaceW <= maxWidth then
                line[#line + 1] = " "
                lineW = lineW + spaceW
            end
        else
            local w = DICT_WRAP.measure(ch)
            word[#word + 1] = { ch = ch, w = w }
            wordW = wordW + w
        end
    end
    putWord()
    if #line > 0 or #lines == 0 then
        lines[#lines + 1] = table.concat(line)
    end
    return table.concat(lines, "\n")
end

function DICT_WRAP.setRaw(value, wrapNow)
    value = DICT_WRAP.unwrapSoftBreaks(value or "")
    ui.dictionaryWrapRaw = value
    ui.dictionaryWrapDisplay = wrapNow and DICT_WRAP.buildDisplay(value, DICT_WRAP.getWidth()) or value
    ffi.fill(ui.dictionaryContentBuffer, ffi.sizeof(ui.dictionaryContentBuffer))
    local display = ui.dictionaryWrapDisplay or ""
    ffi.copy(ui.dictionaryContentBuffer, display, math.min(#display, ffi.sizeof(ui.dictionaryContentBuffer) - 1))
    ui.dictionaryWrapSyncing = false
end

function DICT_WRAP.rewrap(force)
    local raw = ui.dictionaryWrapRaw
    if raw == nil then
        raw = DICT_WRAP.unwrapSoftBreaks(ffi.string(ui.dictionaryContentBuffer))
        ui.dictionaryWrapRaw = raw
    end
    local width = DICT_WRAP.getWidth()
    if force or width ~= (ui.dictionaryWrapWidth or 0) or raw ~= (ui.dictionaryWrapLastRaw or "") then
        local display = DICT_WRAP.buildDisplay(raw, width)
        ui.dictionaryWrapWidth = width
        ui.dictionaryWrapLastRaw = raw
        ui.dictionaryWrapDisplay = display
        ffi.fill(ui.dictionaryContentBuffer, ffi.sizeof(ui.dictionaryContentBuffer))
        ffi.copy(ui.dictionaryContentBuffer, display, math.min(#display, ffi.sizeof(ui.dictionaryContentBuffer) - 1))
    end
end

function DICT_WRAP.syncChanged()
    local display = ffi.string(ui.dictionaryContentBuffer)
    local oldDisplay = ui.dictionaryWrapDisplay or ""
    local raw = ui.dictionaryWrapRaw or ""
    if display == oldDisplay then return false end

    local dchars = utf8_chars(display)
    local cleaned = {}
    for i = 1, #dchars do
        local ch = dchars[i]
        if ch == "\n" then
            local prev = dchars[i - 1]
            local nextc = dchars[i + 1]
            if prev and nextc and prev ~= "\n" and nextc ~= "\n" then

            else
                cleaned[#cleaned + 1] = ch
            end
        else
            cleaned[#cleaned + 1] = ch
        end
    end
    local nextRaw = table.concat(cleaned)
    raw = nextRaw
    ui.dictionaryWrapRaw = raw
    ui.dictionaryWrapDisplay = display
    ui.dictionaryWrapLastRaw = nil
    ui.dictionaryWrapWidth = 0
    return true
end

function DICT_WRAP.prepare()
    if ui.dictionaryWrapRaw == nil then
        local raw = DICT_WRAP.unwrapSoftBreaks(ffi.string(ui.dictionaryContentBuffer))
        ui.dictionaryWrapRaw = raw
        ui.dictionaryWrapDisplay = ""
        ui.dictionaryWrapLastRaw = nil
        ui.dictionaryWrapWidth = 0
    end
    DICT_WRAP.rewrap(false)
end


function playCustomDictionary(index)
    local d = getCustomDictionary(index)
    if not d or d.content == "" then return false end

    local ok, started = pcall(setCustomText, d.content, tonumber(index))
    if not ok or started ~= true then
        return false
    end

    ui.open[0] = true
    ui.activePanel = "keyboard"
    return true
end

ui = {
    open          = new.bool(false),
    activePanel   = "keyboard",
    keyboardVisible = new.bool(true),
    customBuffer  = new.char[2048](""),
    dictionaryTitleBuffer = new.char[512](""),
    dictionaryContentBuffer = new.char[32768](""),
    dictionaryEditIndex = 0,
    dictionaryWrapRaw = nil,
    dictionaryWrapWidth = 0,
    dictionaryWrapPending = true,
    statsMode     = nil,
    statsGroup     = "all",
    statsMetric     = "speed",
    statsPeriod     = "all",

    sortCol       = "time",
    sortDesc      = true,



    layout        = detectSystemKeyboardLayout() or "ru",
    layoutSwitchLatch = false,

    fontsLoaded   = false,
    fontNames     = { "System" },
    fontObjects   = {},
    fontFiles     = {},
    fontComboItems = nil,
    fontLoadFailed = {},
    fontLoadError = {},
    fontScanError = nil,

    highlightModePtr = new.int(0),
    speedometerPtr = new.bool(true),
    displayModePtr = new.int(0),
    fontIndexPtr = new.int(0),
    textScalePtr = new.float(1.0),
    charSpacingPtr = new.int(100),
    textAreaHeightPtr = new.int(150),
    countdownPtr = new.int(5),
    fastChatEnabledPtr = new.bool(false),
    fastChatIntervalPtr = new.int(2000),
    fastChatWindowOpen = new.bool(false),
    fastChatWindowNeedPos = false,
    fastChatWindowPosX = 0,
    fastChatWindowPosY = 0,
    controlsSynced = false,

    modeMenuOpen = false,
    modeMenuAnim = 0.0,
    modeMenuClock = nil,

    fastChatStartTime = 0,
    fastChatInputWasEmpty = true,
    fastChatLastState = false,

    statsDebug = {
        enabled = false,
        windowOpen = new.bool(false),
        initialized = false,
        ptrs = {},
        scalePtr = new.float(1.0),
    },
}
ui.statsDebug.enabled = false
ui.statsDebug.windowOpen[0] = false

local race = {
    modeId        = getModeById(cfg.settings.mode_id).id,
    currentText   = "",
    targetChars   = {},
    words         = {},
    typedChars    = {},
    prevTyped     = "",
    buffer        = new.char[CLAVA_INPUT_BUFFER_BYTES](""),
    lines         = {},
    confirmedLen  = 0,
    wordStartConfirmed = 0,
    inError       = false,
    failed        = false,
    errorMarkers  = {},
    startTime     = nil,
    endTime       = nil,
    finished      = false,
    correctCount  = 0,
    totalErrors   = 0,
    needFocus     = false,
    countdownEnd  = nil,
    countdownWasActive = false,
    lastTypingAt   = nil,
    abortReason    = nil,
    completed      = false,
    isCustomDictionary = false,
    customDictionaryIndex = false,
    dictionaryName = "",
    replayText = "",
    replayModeId = nil,
    replayCustomDictionaryIndex = false,
    replayDictionaryName = "",
    replaySourceMeta = { author = "", book = "", genre = "" },
    started        = false,
    sourceAuthor   = "",
    sourceBook     = "",
    sourceGenre    = "",
}

local LINE_WIDTH = 64

function wrapChars(chars, maxLen)
    local lines, current, currentLen = {}, {}, 0
    local wordBuf, wordLen = {}, 0
    local function flushWord()
        if wordLen == 0 then return end
        if currentLen + wordLen > maxLen and currentLen > 0 then
            lines[#lines + 1] = current
            current, currentLen = {}, 0
        end
        for _, c in ipairs(wordBuf) do
            current[#current + 1] = c
            currentLen = currentLen + 1
        end
        wordBuf, wordLen = {}, 0
    end
    for idx, ch in ipairs(chars) do
        if ch == " " then
            flushWord()
            if currentLen >= maxLen then

                lines[#lines + 1] = current
                current, currentLen = {}, 0
            else
                current[#current + 1] = { ch = ch, idx = idx }
                currentLen = currentLen + 1
            end
        else
            wordBuf[#wordBuf + 1] = { ch = ch, idx = idx }
            wordLen = wordLen + 1
        end
    end
    flushWord()
    if currentLen > 0 then lines[#lines + 1] = current end
    return lines
end

function wrapCharsPixel(chars, maxWidthPx)
    if not maxWidthPx or maxWidthPx <= 1 or not imgui or not imgui.CalcTextSize then
        return wrapChars(chars, LINE_WIDTH)
    end

    local function measureText(text)
        local ok, sz = pcall(imgui.CalcTextSize, text or "")
        return (ok and sz and sz.x) or 7
    end

    local spaceW = measureText(" ")
    local lines = {}
    local current, currentW = {}, 0
    local wordBuf = {}
    local wordText = ""

    local function newLine()
        if #current > 0 then
            lines[#lines + 1] = current
        end
        current, currentW = {}, 0
    end

    local function emit(cell)
        current[#current + 1] = cell
        currentW = currentW + (cell.w or 0)
    end

    local function placeWord()
        if #wordBuf == 0 then return end

        local wordW = measureText(wordText)
        if wordW <= maxWidthPx then
            if currentW > 0 and currentW + wordW > maxWidthPx then
                newLine()
            end

            local prefix = ""
            local prevW = 0
            for _, cell in ipairs(wordBuf) do
                prefix = prefix .. cell.ch
                local prefixW = measureText(prefix)
                local advance = math.max(0, prefixW - prevW)
                emit({ ch = cell.ch, idx = cell.idx, w = advance })
                prevW = prefixW
            end
        else

            local prefix = ""
            local prevW = 0
            for _, cell in ipairs(wordBuf) do
                prefix = prefix .. cell.ch
                local prefixW = measureText(prefix)
                local charW = math.max(0, prefixW - prevW)
                if currentW > 0 and currentW + charW > maxWidthPx then
                    newLine()
                end
                emit({ ch = cell.ch, idx = cell.idx, w = charW })
                prevW = prefixW
            end
        end

        wordBuf = {}
        wordText = ""
    end

    for idx, ch in ipairs(chars) do
        if ch == " " then
            placeWord()
            if currentW > 0 and currentW + spaceW > maxWidthPx then

                newLine()
                emit({ ch = ch, idx = idx, w = 0, hiddenBreakSpace = true })
            else
                emit({ ch = ch, idx = idx, w = spaceW })
            end
        else
            wordBuf[#wordBuf + 1] = { ch = ch, idx = idx }
            wordText = wordText .. ch
        end
    end

    placeWord()
    if #current > 0 then lines[#lines + 1] = current end
    if #lines == 0 then lines[1] = {} end
    return lines
end

function computeWords(chars)
    local words, s = {}, nil
    for i, ch in ipairs(chars) do
        if ch == " " then
            if s then words[#words + 1] = { s = s, e = i - 1 }; s = nil end
        else
            if not s then s = i end
        end
    end
    if s then words[#words + 1] = { s = s, e = #chars } end
    return words
end

function currentWordRange()
    if race.confirmedLen >= #race.targetChars then return nil end
    local pos = race.confirmedLen + 1
    for _, w in ipairs(race.words) do
        if pos <= w.e then return w end
    end
    return race.words[#race.words]
end

function resetBuffer()
    ffi.fill(race.buffer, ffi.sizeof(race.buffer))
end

function beginRace(text, modeId, sourceMeta, customDictionaryIndex)
    local selectedMode = getModeById(modeId or race.modeId or cfg.settings.mode_id or "normal")
    local layout = selectedMode.layout or "ru"
    text = clavaNormalizePlayableText(text, layout)
    if text == "" then return false end

    local isCustomDictionary = tonumber(customDictionaryIndex) or false




    local enforceLength = not isCustomDictionary and (
        selectedMode.id == "normal" or selectedMode.id == "english"
        or selectedMode.id == "punct" or selectedMode.id == "onemistake"
    )
    if enforceLength and not clavaTextFitsPlayableLimits(text, CLAVA_TEXT_MIN_CHARS, CLAVA_TEXT_MAX_CHARS) then
        return false
    end
    if not clavaTextFitsBuffer(text) then return false end

    race.modeId       = selectedMode.id
    race.targetLayout = (selectedMode.layout == "en") and "en" or "ru"
    cfg.settings.mode_id = race.modeId





    race.started      = true
    race.currentText  = text
    race.targetChars  = utf8_chars(text)
    race.words        = computeWords(race.targetChars)
    race.typedChars   = {}
    race.prevTyped    = ""
    race.lines        = wrapChars(race.targetChars, LINE_WIDTH)
    race.confirmedLen = 0
    race.wordStartConfirmed = 0
    race.inError      = false
    race.failed       = false
    race.errorMarkers = {}
    race.startTime    = nil
    race.endTime      = nil
    race.finished     = false
    race.correctCount = 0
    race.totalErrors  = 0
    race.needFocus    = false
    race.inputGeneration = 0
    race.lastTypingAt = nil
    race.abortReason  = nil
    race.completed    = false
    race.isCustomDictionary = isCustomDictionary
    race.customDictionaryIndex = isCustomDictionary or false
    race.dictionaryName = ""
    race.sourceAuthor = clavaNormalizePlayableText((sourceMeta and sourceMeta.author) or "", layout)
    race.sourceBook = clavaNormalizePlayableText((sourceMeta and sourceMeta.book) or "", layout)
    race.sourceGenre = clavaNormalizePlayableText((sourceMeta and sourceMeta.genre) or "", layout)
    race._wrapWidth = nil
    race._wrapText = nil
    race._wrapFont = nil
    race._wrapScale = nil
    local cd = (cfg.settings and cfg.settings.countdown_seconds) or 5
    race.countdownEnd = os.clock() + math.max(0, cd)
    resetBuffer()
    return true
end

function selectMode(modeId)
    local mode = getModeById(modeId)
    race.modeId = mode.id
    cfg.settings.mode_id = mode.id




    race.isCustomDictionary = false
    race.customDictionaryIndex = false
    race.dictionaryName = ""
    race.replayText = ""
    race.replayModeId = nil
    race.replayCustomDictionaryIndex = false
    race.replayDictionaryName = ""
    race.replaySourceMeta = { author = "", book = "", genre = "" }
    race.currentText = ""
    race.targetChars = {}
    race.words = {}
    race.typedChars = {}
    race.prevTyped = ""
    race.lines = {}
    race.confirmedLen = 0
    race.wordStartConfirmed = 0
    race.inError = false
    race.failed = false
    race.errorMarkers = {}
    race.startTime = nil
    race.endTime = nil
    race.finished = false
    race.completed = false
    race.correctCount = 0
    race.totalErrors = 0
    race.countdownEnd = nil
    race.countdownWasActive = false
    race.lastTypingAt = nil
    race.abortReason = nil
    race.started = false
    race.needFocus = false
    race.sourceAuthor = ""
    race.sourceBook = ""
    race.sourceGenre = ""
    race.inputGeneration = (race.inputGeneration or 0) + 1
    resetBuffer()

    ui.modeMenuOpen = false

    saveCfg()
end

function isLiteraryMode(modeId)
    return modeId == "normal" or modeId == "english" or modeId == "punct" or modeId == "onemistake"
end

function directLiteraryFallback(mode, avoid)
    local pool = (mode.layout == "en") and CLAVA_SOURCE_EN or CLAVA_SOURCE_RU
    if not pool or #pool == 0 then return nil, nil end

    local minLen = CLAVA_TEXT_MIN_CHARS
    local maxLen = CLAVA_TEXT_MAX_CHARS

    local candidates = {}
    local candidatesNoAvoid = {}
    for _, item in ipairs(pool) do
        local candidate = tostring(item.text or "")
        if clavaSourceInRange(candidate, minLen, maxLen) then
            candidatesNoAvoid[#candidatesNoAvoid + 1] = item
            if candidate ~= avoid then candidates[#candidates + 1] = item end
        end
    end

    local list = (#candidates > 0) and candidates or candidatesNoAvoid
    if #list == 0 then return nil, nil end


    local item = list[math.random(1, #list)]
    return item.text, {
        author = item.author or "",
        book = item.book or "",
        genre = item.genre or "",
    }
end

function pickModeText(modeId)
    local mode = getModeById(modeId)




    local previousText = race.currentText or ""
    local textValue, sourceMeta


    local okGen
    okGen, textValue, sourceMeta = pcall(mode.gen, previousText)
    if not okGen then
        textValue, sourceMeta = nil, nil
    end

    if (type(textValue) ~= "string" or textValue == "") then
        local okGen2, value2, meta2 = pcall(mode.gen, nil)
        if okGen2 then
            textValue, sourceMeta = value2, meta2
        end
    end



    if isLiteraryMode(mode.id) and (type(textValue) ~= "string" or textValue == "") then
        textValue, sourceMeta = directLiteraryFallback(mode, previousText)
    end


    if (type(textValue) ~= "string" or textValue == "") and isLiteraryMode(mode.id) then
        textValue, sourceMeta = directLiteraryFallback(mode, nil)
    end


    if (type(textValue) ~= "string" or textValue == "") and not isLiteraryMode(mode.id) and previousText ~= "" then
        textValue = previousText
        sourceMeta = {
            author = race.sourceAuthor or "",
            book = race.sourceBook or "",
            genre = race.sourceGenre or "",
        }
    end

    if type(textValue) ~= "string" or textValue == "" then
        return false
    end

    local layout = mode.layout or "ru"
    local normalized = clavaNormalizePlayableText(textValue, layout)
    local _, charsOk, lengthOk, bufferOk = clavaAuditPlayableText(normalized, layout, isLiteraryMode(mode.id))
    if not charsOk or not lengthOk or not bufferOk then
        if isLiteraryMode(mode.id) then
            local fallbackText, fallbackMeta = directLiteraryFallback(mode, previousText)
            if fallbackText then
                normalized, sourceMeta = clavaNormalizePlayableText(fallbackText, layout), fallbackMeta
                local _, c2, l2, b2 = clavaAuditPlayableText(normalized, layout, true)
                if not c2 or not l2 or not b2 then normalized = "" end
            end
        end
    end

    if normalized == "" then return false end
    return beginRace(normalized, mode.id, sourceMeta) == true
end

function pickNewTextSameMode()
    pickModeText(race.modeId or "normal")
end

function restartCurrentText()
    local text = ""
    local modeId = race.modeId or "normal"
    local customIndex = false
    local dictionaryName = ""
    local sourceMeta = {
        author = race.sourceAuthor or "",
        book = race.sourceBook or "",
        genre = race.sourceGenre or "",
    }

    if race.finished and race.completed and not race.failed then
        text = tostring(race.replayText or "")
        modeId = race.replayModeId or modeId
        customIndex = tonumber(race.replayCustomDictionaryIndex) or false
        dictionaryName = tostring(race.replayDictionaryName or "")
        sourceMeta = race.replaySourceMeta or sourceMeta
    elseif race.targetChars and #race.targetChars > 0 then
        text = table.concat(race.targetChars)
        customIndex = tonumber(race.customDictionaryIndex) or false
        dictionaryName = tostring(race.dictionaryName or "")
    elseif race.currentText and race.currentText ~= "" then
        text = tostring(race.currentText)
        customIndex = tonumber(race.customDictionaryIndex) or false
        dictionaryName = tostring(race.dictionaryName or "")
    end

    if text ~= "" then
        local ok = beginRace(text, modeId, sourceMeta, customIndex)
        if ok and customIndex then
            race.dictionaryName = dictionaryName
        end
        return ok == true
    end

    return pickModeText(modeId) == true
end

function restartFinishedRaceExact()
    if not race.finished or not race.completed or race.failed then
        return false
    end
    return restartCurrentText() == true
end

function detectCustomDictionaryLayout(text)
    local ruCount, enCount = 0, 0
    for _, ch in ipairs(utf8_chars(tostring(text or ""))) do
        local cp = utf8_codepoint(ch)
        if (cp >= 0x410 and cp <= 0x44F) or cp == 0x401 or cp == 0x451 then
            ruCount = ruCount + 1
        elseif (cp >= 0x41 and cp <= 0x5A) or (cp >= 0x61 and cp <= 0x7A) then
            enCount = enCount + 1
        end
    end
    return enCount > ruCount and "en" or "ru"
end

function setCustomText(text, dictionaryIndex)
    local index = tonumber(dictionaryIndex) or false
    local dict = index and getCustomDictionary(index) or nil
    if not index or not dict or dict.content == "" then
        return false
    end

    local layout = detectCustomDictionaryLayout(dict.content)
    local normalized = clavaNormalizePlayableText(dict.content, layout)
    normalized = normalized:gsub("^%s+", ""):gsub("%s+$", "")
    if normalized == "" or not clavaTextFitsBuffer(normalized) then
        return false
    end

    local modeId = layout == "en" and "english" or "normal"
    local started = beginRace(normalized, modeId, {
        author = "",
        book = "",
        genre = "",
    }, index)
    if not started then return false end

    race.dictionaryName = (dict.name and dict.name ~= "" and clavaNormalizePlayableText(dict.name, layout)) or u8"Словарь"
    return true
end

function recordErrorMarker(pos)
    for _, m in ipairs(race.errorMarkers) do
        if m.pos == pos then m.count = m.count + 1; return end
    end
    race.errorMarkers[#race.errorMarkers + 1] = { pos = pos, count = 1 }
end

function finishRace()
    race.replayText = table.concat(race.targetChars or {})
    if race.replayText == "" then
        race.replayText = race.currentText or ""
    end
    race.replayModeId = race.modeId or "normal"
    race.replayCustomDictionaryIndex = tonumber(race.customDictionaryIndex) or false
    race.replayDictionaryName = race.dictionaryName or ""
    race.replaySourceMeta = {
        author = race.sourceAuthor or "",
        book = race.sourceBook or "",
        genre = race.sourceGenre or "",
    }

    race.finished = true
    race.completed = true
    race.endTime = os.clock()




    setBufferString("")
    race.typedChars = {}
    race.prevTyped = ""
    race.needFocus = false
    race.inputGeneration = (race.inputGeneration or 0) + 1
    local elapsed = math.max(race.endTime - (race.startTime or race.endTime), 0.01)
    local speed = math.floor((race.correctCount / elapsed) * 60 + 0.5)
    local total = race.correctCount + race.totalErrors
    local acc = total > 0 and math.floor((race.correctCount / total) * 100 + 0.5) or 100

    if race.isCustomDictionary then
        local sec = customDictionaryStatsSection(race.isCustomDictionary)
        if sec then
            sec.played = (tonumber(sec.played) or 0) + 1
            if speed > (sec.best_speed or 0) then sec.best_speed = speed end
            if acc > (sec.best_accuracy or 0) then sec.best_accuracy = acc end
            customDictionaryHistoryAppend(race.isCustomDictionary, {
                speed = speed, accuracy = acc, errors = race.totalErrors,
                time = os.time(), chars = race.correctCount
            })
        end
    else
        local sec = cfg["mode_" .. race.modeId]
        if sec then
            sec.races = (sec.races or 0) + 1
            if speed > (sec.best_speed or 0) then sec.best_speed = speed end
            if acc > (sec.best_accuracy or 0) then sec.best_accuracy = acc end
            historyAppend(race.modeId, { speed = speed, accuracy = acc, errors = race.totalErrors, time = os.time(), chars = race.correctCount })
        end
    end
    saveCfg()
end

function setBufferString(value)
    ffi.fill(race.buffer, ffi.sizeof(race.buffer))
    if value and value ~= "" then ffi.copy(race.buffer, value, math.min(#value, ffi.sizeof(race.buffer) - 1)) end
end

function updateTyping()
    if not race.started or #race.targetChars == 0 or race.finished or race.countingDown then return end

    local typedStr = ffi.string(race.buffer)
    if typedStr == race.prevTyped then return end
    race.lastTypingAt = os.clock()

    if race.failed then
        race.typedChars = utf8_chars(typedStr)
        race.prevTyped = typedStr
        return
    end

    local newChars = utf8_chars(typedStr)
    local newLen, oldLen = #newChars, #race.typedChars
    local wordCompleted = false
    local completedInputIndex = nil

    if newLen > oldLen then
        for i = oldLen + 1, newLen do
            if not race.startTime then race.startTime = os.clock() end

            if not race.inError then
                local expected = race.targetChars[race.confirmedLen + 1]
                local typedCh = newChars[i]

                if expected and charsEquivalent(typedCh, expected) then
                    race.confirmedLen = race.confirmedLen + 1
                    race.correctCount = race.correctCount + 1
                    if expected == " " then
                        wordCompleted = true
                        completedInputIndex = i
                        break
                    end
                else
                    race.inError = true
                    race.totalErrors = race.totalErrors + 1
                    recordErrorMarker(race.confirmedLen + 1)

                    local mode = getModeById(race.modeId)
                    if mode.oneMistake then

                        race.failed = true
                        race.endTime = os.clock()
                        setBufferString("")
                        race.typedChars = {}
                        race.prevTyped = ""
                        race.needFocus = false
                        race.inputGeneration = (race.inputGeneration or 0) + 1
                    end
                end
            end
        end
    elseif newLen < oldLen then
        local localConfirmed = race.confirmedLen - race.wordStartConfirmed
        if newLen < localConfirmed then
            race.confirmedLen = race.wordStartConfirmed + newLen
        end
        if newLen <= (race.confirmedLen - race.wordStartConfirmed) then
            race.inError = false
        end
    end

    if wordCompleted and not race.inError and not race.failed then
        race.wordStartConfirmed = race.confirmedLen

        setBufferString("")
        race.typedChars = {}
        race.prevTyped = ""
        race.inputGeneration = (race.inputGeneration or 0) + 1
        race.needFocus = true
    else
        race.typedChars = newChars
        race.prevTyped = typedStr
    end

    if not race.finished and not race.failed and race.confirmedLen >= #race.targetChars then
        finishRace()
    end
end

function fmtTime(sec)
    sec = math.max(sec or 0, 0)
    local m = math.floor(sec / 60)
    local s = math.floor(sec % 60)
    return string.format("%02d:%02d", m, s)
end

function fmtDate(ts)
    if not ts or ts == 0 then return "-" end
    local ok, str = pcall(os.date, "%d.%m %H:%M", ts)
    return ok and str or "-"
end

local COL_CORRECT = colorVec(0.25, 0.55, 0.30)
local COL_ERROR   = colorVec(0.55, 0.10, 0.12)
local COL_ACTIVE  = colorVec(0.15, 0.35, 0.75)
local COL_ACCENT  = colorVec(0.90, 0.55, 0.15)
local COL_YELLOW  = colorVec(0.95, 0.78, 0.15)
local COL_PENDING = colorVec(0.27, 0.26, 0.24)

local STYLE_PRESETS = {
    {
        name = u8"Светлый",
        windowBg = {0.93,0.93,0.92,0.98}, childBg = {0.98,0.98,0.97,1.00},
        titleBg = {0.42,0.42,0.44,1.00}, titleBgAct = {0.36,0.36,0.38,1.00},
        border = {0.78,0.78,0.77,1.00}, frameBg = {1.00,1.00,1.00,1.00},
        text = {0.16,0.16,0.15,1.00}, button = {0.60,0.60,0.62,1.00},
        buttonHov = {0.68,0.68,0.70,1.00}, buttonAct = {0.52,0.52,0.54,1.00},
        header = {0.84,0.84,0.82,1.00}, headerHov = {0.88,0.88,0.86,1.00},
        headerAct = {0.78,0.78,0.76,1.00}, separator = {0.80,0.80,0.78,1.00},
        correct={0.25,0.55,0.30,1}, error={0.55,0.10,0.12,1},
        active={0.15,0.35,0.75,1}, accent={0.90,0.55,0.15,1}, yellow={0.95,0.78,0.15,1}, pending={0.27,0.26,0.24,1},
    },
    {
        name = u8"Тёмный",
        windowBg={0.12,0.13,0.15,0.98}, childBg={0.16,0.17,0.19,1},
        titleBg={0.09,0.10,0.12,1}, titleBgAct={0.16,0.17,0.20,1},
        border={0.32,0.34,0.38,1}, frameBg={0.09,0.10,0.12,1},
        text={0.92,0.93,0.95,1}, button={0.25,0.27,0.31,1},
        buttonHov={0.33,0.36,0.42,1}, buttonAct={0.20,0.22,0.26,1},
        header={0.21,0.23,0.27,1}, headerHov={0.27,0.30,0.35,1}, headerAct={0.31,0.34,0.40,1}, separator={0.30,0.32,0.36,1},
        correct={0.35,0.82,0.48,1}, error={0.93,0.25,0.28,1}, active={0.32,0.58,1,1}, accent={0.98,0.55,0.20,1}, yellow={1,0.78,0.18,1}, pending={0.68,0.70,0.74,1},
    },
    {
        name = u8"Синий",
        windowBg={0.90,0.94,0.98,0.98}, childBg={0.97,0.985,1,1},
        titleBg={0.18,0.30,0.46,1}, titleBgAct={0.12,0.24,0.38,1},
        border={0.60,0.70,0.82,1}, frameBg={1,1,1,1},
        text={0.10,0.16,0.24,1}, button={0.42,0.58,0.76,1},
        buttonHov={0.50,0.66,0.84,1}, buttonAct={0.34,0.49,0.66,1},
        header={0.78,0.86,0.95,1}, headerHov={0.84,0.90,0.98,1}, headerAct={0.70,0.80,0.92,1}, separator={0.68,0.76,0.86,1},
        correct={0.22,0.62,0.38,1}, error={0.72,0.16,0.20,1}, active={0.12,0.42,0.84,1}, accent={0.16,0.48,0.88,1}, yellow={0.96,0.72,0.16,1}, pending={0.34,0.40,0.48,1},
    },
    {
        name = u8"Зелёный",
        windowBg={0.91,0.96,0.92,0.98}, childBg={0.98,1,0.98,1},
        titleBg={0.18,0.36,0.25,1}, titleBgAct={0.13,0.29,0.19,1},
        border={0.61,0.76,0.66,1}, frameBg={1,1,1,1},
        text={0.10,0.19,0.13,1}, button={0.40,0.64,0.48,1},
        buttonHov={0.47,0.72,0.56,1}, buttonAct={0.32,0.55,0.40,1},
        header={0.80,0.91,0.83,1}, headerHov={0.86,0.94,0.89,1}, headerAct={0.74,0.88,0.78,1}, separator={0.70,0.82,0.73,1},
        correct={0.18,0.60,0.32,1}, error={0.76,0.16,0.18,1}, active={0.18,0.48,0.70,1}, accent={0.22,0.64,0.34,1}, yellow={0.92,0.76,0.18,1}, pending={0.34,0.43,0.36,1},
    },
    {
        name = u8"Фиолетовый",
        windowBg={0.12,0.08,0.18,0.99}, childBg={0.16,0.11,0.23,1},
        titleBg={0.20,0.12,0.29,1}, titleBgAct={0.28,0.17,0.39,1},
        border={0.45,0.34,0.56,1}, frameBg={0.14,0.09,0.21,1},
        text={1,1,1,1}, button={0.34,0.23,0.46,1},
        buttonHov={0.43,0.30,0.57,1}, buttonAct={0.27,0.17,0.38,1},
        header={0.26,0.17,0.36,1}, headerHov={0.34,0.23,0.45,1}, headerAct={0.40,0.28,0.52,1}, separator={0.38,0.29,0.46,1},
        correct={0.25,0.72,0.46,1}, error={0.92,0.28,0.34,1}, active={0.58,0.36,0.95,1}, accent={0.74,0.44,0.96,1}, yellow={0.98,0.78,0.20,1}, pending={0.70,0.65,0.78,1},
    },
}

local THEME = {}

function applyInterfaceStyle(index)
    index = math.max(0, math.min(#STYLE_PRESETS - 1, math.floor(tonumber(index) or 0)))
    cfg.settings.style_index = index
    local s = STYLE_PRESETS[index + 1]
    THEME.accent = colorVec(s.accent[1], s.accent[2], s.accent[3], s.accent[4])
    for _, key in ipairs({"windowBg","childBg","titleBg","titleBgAct","border","frameBg","text","button","buttonHov","buttonAct","header","headerHov","headerAct","separator"}) do
        local v = s[key]
        THEME[key] = colorVec(v[1], v[2], v[3], v[4])
    end
    COL_CORRECT = colorVec(s.correct[1], s.correct[2], s.correct[3], s.correct[4])
    COL_ERROR   = colorVec(s.error[1], s.error[2], s.error[3], s.error[4])
    COL_ACTIVE  = colorVec(s.active[1], s.active[2], s.active[3], s.active[4])
    COL_ACCENT  = colorVec(s.accent[1], s.accent[2], s.accent[3], s.accent[4])
    COL_YELLOW  = colorVec(s.yellow[1], s.yellow[2], s.yellow[3], s.yellow[4])
    COL_PENDING = colorVec(s.pending[1], s.pending[2], s.pending[3], s.pending[4])
end

applyInterfaceStyle(cfg.settings.style_index)

function themeMix(a, b, t)
    t = math.max(0, math.min(1, t or 0.5))
    return colorVec(
        a.x + (b.x - a.x) * t,
        a.y + (b.y - a.y) * t,
        a.z + (b.z - a.z) * t,
        a.w + (b.w - a.w) * t
    )
end

function themeTextMuted()
    return themeMix(THEME.text, THEME.windowBg, 0.48)
end

function themeTextSubtle()
    return themeMix(THEME.text, THEME.windowBg, 0.68)
end

function themeFrameHover()
    return themeMix(THEME.frameBg, THEME.accent or COL_ACCENT, 0.10)
end

function themeFrameActive()
    return themeMix(THEME.frameBg, THEME.accent or COL_ACCENT, 0.18)
end

function themeBorderSoft()
    return themeMix(THEME.border, THEME.windowBg, 0.28)
end

function themeBorderStrong()
    return themeMix(THEME.border, THEME.accent or COL_ACCENT, 0.34)
end

function themeSliderTrack()
    return themeMix(THEME.border, THEME.button, 0.35)
end

function themeSliderTrackHover()
    return themeMix(THEME.border, THEME.accent or COL_ACCENT, 0.30)
end

function themeSliderValue()
    return THEME.accent or COL_ACCENT
end

function themeSliderKnobBorder()
    return themeMix(THEME.text, THEME.accent or COL_ACCENT, 0.20)
end

function themeScrollbarBg()
    return themeMix(THEME.windowBg, THEME.border, 0.38)
end

function themeScrollbarGrab()
    return themeMix(THEME.border, THEME.accent or COL_ACCENT, 0.22)
end

function themeScrollbarGrabHover()
    return themeMix(THEME.border, THEME.accent or COL_ACCENT, 0.38)
end

function themeScrollbarGrabActive()
    return themeMix(THEME.accent or COL_ACCENT, THEME.text, 0.24)
end

function themeActiveButton()
    return themeMix(THEME.accent or COL_ACCENT, THEME.buttonAct, 0.38)
end

function themeActiveButtonHover()
    return themeMix(THEME.accent or COL_ACCENT, THEME.buttonHov, 0.28)
end

function themeInactiveButton()
    return THEME.button
end

function themeHoverColor()
    return themeMix(THEME.accent or COL_ACCENT, THEME.windowBg, 0.84)
end

function contrastText(bg)
    local lum = 0.2126 * bg[1] + 0.7152 * bg[2] + 0.0722 * bg[3]
    return lum > 0.60 and colorVec(0.08, 0.08, 0.08, 1) or colorVec(1, 1, 1, 1)
end

function styleButtonColors(style)

    local bg = style.titleBg
    local lum = 0.2126 * bg[1] + 0.7152 * bg[2] + 0.0722 * bg[3]
    local factor = lum < 0.60 and 1.16 or 0.92
    local hov = {
        math.min(1, bg[1] * factor),
        math.min(1, bg[2] * factor),
        math.min(1, bg[3] * factor),
        bg[4] or 1
    }
    return colorVec(bg[1], bg[2], bg[3], bg[4] or 1),
           colorVec(hov[1], hov[2], hov[3], hov[4]),
           contrastText(bg)
end

local THEME_PUSH_COUNT = 0
local THEME_STYLE_PUSH_COUNT = 0
local BUTTON_FRAME_ROUNDING = 10.0
local THEME_PREV_FRAME_ROUNDING = nil

function pushTheme()
    local list = {
        { imgui.Col.WindowBg, THEME.windowBg }, { imgui.Col.ChildBg, THEME.childBg },
        { imgui.Col.TitleBg, THEME.titleBg }, { imgui.Col.TitleBgActive, THEME.titleBgAct },
        { imgui.Col.Border, THEME.border }, { imgui.Col.FrameBg, THEME.frameBg },
        { imgui.Col.FrameBgHovered, themeFrameHover() }, { imgui.Col.FrameBgActive, themeFrameActive() },
        { imgui.Col.SliderGrab, themeSliderValue() }, { imgui.Col.SliderGrabActive, themeMix(themeSliderValue(), colorVec(1,1,1,1), 0.12) },
        { imgui.Col.ScrollbarBg, themeScrollbarBg() },
        { imgui.Col.ScrollbarGrab, themeScrollbarGrab() },
        { imgui.Col.ScrollbarGrabHovered, themeScrollbarGrabHover() },
        { imgui.Col.ScrollbarGrabActive, themeScrollbarGrabActive() },
        { imgui.Col.PopupBg, THEME.childBg },
        { imgui.Col.Text, THEME.text }, { imgui.Col.Button, THEME.button },
        { imgui.Col.ButtonHovered, THEME.buttonHov }, { imgui.Col.ButtonActive, THEME.buttonAct },
        { imgui.Col.Header, THEME.header }, { imgui.Col.HeaderHovered, THEME.headerHov },
        { imgui.Col.HeaderActive, THEME.headerAct }, { imgui.Col.Separator, THEME.separator },
        -- Edge resizing in ImGui uses SeparatorHovered/SeparatorActive.
        -- Keep those states in the selected theme instead of default blue.
        { imgui.Col.SeparatorHovered, themeMix(THEME.separator, THEME.accent or COL_ACCENT, 0.55) },
        { imgui.Col.SeparatorActive, themeMix(THEME.separator, THEME.accent or COL_ACCENT, 0.78) },
        { imgui.Col.CheckMark, COL_ACCENT },
    }
    local n = 0
    for _, p in ipairs(list) do
        if p[1] ~= nil and pcall(imgui.PushStyleColor, p[1], p[2]) then n = n + 1 end
    end
    THEME_PUSH_COUNT = n

    -- mimgui versions used by MoonLoader can fail to apply ResizeGripActive
    -- reliably through PushStyleColor(). Set the resize-grip colors directly
    -- in ImGuiStyle so the pressed state cannot fall back to the default blue.
    local okResizeStyle, resizeStyle = pcall(imgui.GetStyle)
    if okResizeStyle and resizeStyle and resizeStyle.Colors and imgui.Col.ResizeGrip then
        pcall(function()
            resizeStyle.Colors[imgui.Col.ResizeGrip] =
                themeMix(THEME.border, THEME.accent or COL_ACCENT, 0.28)
        end)
        if imgui.Col.ResizeGripHovered then
            pcall(function()
                resizeStyle.Colors[imgui.Col.ResizeGripHovered] =
                    themeMix(THEME.border, THEME.accent or COL_ACCENT, 0.55)
            end)
        end
        if imgui.Col.ResizeGripActive then
            pcall(function()
                resizeStyle.Colors[imgui.Col.ResizeGripActive] =
                    colorVec((THEME.accent or COL_ACCENT).x, (THEME.accent or COL_ACCENT).y, (THEME.accent or COL_ACCENT).z, 1.0)
            end)
        end
    end

    THEME_PREV_FRAME_ROUNDING = nil
    local okStyle, style = pcall(imgui.GetStyle)
    if okStyle and style then
        local okPrev, prev = pcall(function() return style.FrameRounding end)
        if okPrev and type(prev) == 'number' then
            THEME_PREV_FRAME_ROUNDING = prev
            pcall(function() style.FrameRounding = BUTTON_FRAME_ROUNDING end)
        end
    end
    THEME_STYLE_PUSH_COUNT = 0
end
function popTheme()
    local okStyle, style = pcall(imgui.GetStyle)
    if okStyle and style and THEME_PREV_FRAME_ROUNDING ~= nil then
        pcall(function() style.FrameRounding = THEME_PREV_FRAME_ROUNDING end)
    end
    THEME_PREV_FRAME_ROUNDING = nil
    THEME_STYLE_PUSH_COUNT = 0
    if THEME_PUSH_COUNT > 0 then pcall(imgui.PopStyleColor, THEME_PUSH_COUNT) end
    THEME_PUSH_COUNT = 0
end

function pushButtonFrameBorder(size)
    local okStyle, style = pcall(imgui.GetStyle)
    if not okStyle or not style then return nil, nil end
    local okPrev, prev = pcall(function() return style.FrameBorderSize end)
    if not okPrev or type(prev) ~= 'number' then return nil, nil end
    pcall(function() style.FrameBorderSize = size or 1.0 end)
    return style, prev
end

function popButtonFrameBorder(style, prev)
    if style and prev ~= nil then
        pcall(function() style.FrameBorderSize = prev end)
    end
end

function getRaceTextAutoOffset(lines, areaH, lineHeight, showOne)
    if showOne or not lines or #lines <= 1 then
        return 0
    end

    local activeIdx = race.confirmedLen + 1
    if race.finished or race.failed then
        activeIdx = #race.targetChars
    end
    if activeIdx < 1 then activeIdx = 1 end
    if #race.targetChars > 0 and activeIdx > #race.targetChars then
        activeIdx = #race.targetChars
    end

    local targetLine = #lines
    for li, line in ipairs(lines) do
        for _, cell in ipairs(line) do
            if cell.idx == activeIdx then
                targetLine = li
                break
            end
        end
        if targetLine == li then break end
    end

    local viewportH = math.max(1, areaH or 1)
    local totalH = math.max(viewportH, (#lines * lineHeight) + 6)

    local anchorY = math.max(lineHeight * 1.2, viewportH * 0.34)
    local desired = (targetLine - 1) * lineHeight - anchorY
    local maxOffset = math.max(0, totalH - viewportH)
    if desired < 0 then desired = 0 end
    if desired > maxOffset then desired = maxOffset end
    return desired
end

function drawFinishedRaceSummary()
    local areaH = tonumber(cfg.settings.text_area_height) or 150
    local scale = tonumber(cfg.settings.text_scale) or 1.0
    local fontIndex = tonumber(cfg.settings.font_index) or 0

    local font = (fontIndex > 0 and ui.fontObjects[fontIndex]) or nil
    local fontPushed = false
    if font and imgui.PushFont then
        local ok = pcall(imgui.PushFont, font)
        fontPushed = ok
    end
    pcall(imgui.SetWindowFontScale, scale)

    imgui.BeginChild("##clava_finish_summary", imgui.ImVec2(0, areaH), false)



    pcall(imgui.Indent, 4.0)

    local sourceBlue = COL_ACTIVE

    local function line(label, value)
        value = tostring(value or "")
        if value == "" then value = u8"Не указано" end
        imgui.TextColored(sourceBlue, label)
        imgui.SameLine(0, 8)
        imgui.TextColored(sourceBlue, value)
    end

    imgui.Spacing()
    imgui.TextColored(COL_CORRECT, u8"Заезд завершён")
    imgui.Spacing()

    if race.isCustomDictionary and (race.dictionaryName or "") ~= "" then

        line(u8"Источник:", race.dictionaryName)
    elseif race.sourceAuthor ~= "" or race.sourceBook ~= "" or race.sourceGenre ~= "" then
        line(u8"Автор:", race.sourceAuthor)
        line(u8"Книга:", race.sourceBook)
        line(u8"Жанр:", race.sourceGenre)
    else
        imgui.TextColored(sourceBlue, u8"Источник текста не указан.")
    end

    imgui.Spacing()
    imgui.Text(u8(string.format(
        "Скорость: %d зн/мин    Ошибок: %d    Точность: %d%%",
        math.floor((race.correctCount / math.max((race.endTime or 0) - (race.startTime or race.endTime or 0), 0.01)) * 60 + 0.5),
        race.totalErrors,
        (function()
            local total = race.correctCount + race.totalErrors
            return total > 0 and math.floor((race.correctCount / total) * 100 + 0.5) or 100
        end)()
    )))

    pcall(imgui.Unindent, 4.0)
    imgui.EndChild()

    if fontPushed then pcall(imgui.PopFont) end
    pcall(imgui.SetWindowFontScale, 1.0)
end

function drawRaceText()
    local areaH = tonumber(cfg.settings.text_area_height) or 150
    local scale = tonumber(cfg.settings.text_scale) or 1.0
    local fontIndex = tonumber(cfg.settings.font_index) or 0

    local font = (fontIndex > 0 and ui.fontObjects[fontIndex]) or nil
    local fontPushed = false
    if font and imgui.PushFont then
        local ok = pcall(imgui.PushFont, font)
        fontPushed = ok
    end
    pcall(imgui.SetWindowFontScale, scale)

    imgui.BeginChild("##clava_text_area", imgui.ImVec2(0, areaH), false)

    local okAvail, avail = pcall(imgui.GetContentRegionAvail)
    local availW = (okAvail and avail and avail.x) or 0
    local roundedW = math.floor(availW + 0.5)
    if roundedW ~= (race._wrapWidth or -1)
        or race.currentText ~= race._wrapText
        or fontIndex ~= race._wrapFont
        or scale ~= race._wrapScale
    then
        race.lines = wrapCharsPixel(race.targetChars, math.max(10, roundedW - 8))
        race._wrapWidth = roundedW
        race._wrapText = race.currentText
        race._wrapFont = fontIndex
        race._wrapScale = scale
    end

    local drawlist = imgui.GetWindowDrawList()
    local activeWord = currentWordRange()
    local showOne = (tonumber(cfg.settings.display_mode) or 0) == 1
    local highlightMode = tonumber(cfg.settings.highlight_mode) or 0
    local intervalPercent = tonumber(cfg.settings.char_spacing) or 100

    local shownLine = 1
    if showOne then
        local activeIdx = race.confirmedLen + 1
        for li, line in ipairs(race.lines) do
            for _, cell in ipairs(line) do
                if cell.idx == activeIdx then
                    shownLine = li
                    break
                end
            end
            if shownLine == li and #line > 0 and line[1].idx <= activeIdx then break end
        end
    end

    local okLineHeight, textLineHeight = pcall(imgui.GetTextLineHeight)
    if not okLineHeight or not textLineHeight or textLineHeight <= 0 then textLineHeight = 20 end
    local lineHeight = textLineHeight * (math.max(50, intervalPercent) / 100)

    local contentStart = imgui.GetCursorScreenPos()
    local scrollOffset = getRaceTextAutoOffset(race.lines, areaH, lineHeight, showOne)

    local function measureTextWidth(text)
        local ok, sz = pcall(imgui.CalcTextSize, text or "")
        return (ok and sz and sz.x) or 0
    end

    local dictSourceName = (race.isCustomDictionary and tostring(race.dictionaryName or "") ~= "")
        and tostring(race.dictionaryName) or nil
    local showSource = race.finished and race.completed and not race.failed
        and (race.sourceBook ~= "" or dictSourceName ~= nil)




    local sourcePadLeft = 0
    local sourcePadRight = 12
    local sourceTopPad = 20
    local sourceMetaLineH = lineHeight * 0.84
    local sourceMaxW = math.max(80, availW - sourcePadLeft - sourcePadRight)

    local function wrapSourceText(text, maxWidth)
        text = tostring(text or "")
        local words = {}
        for word in text:gmatch("%S+") do words[#words + 1] = word end
        if #words == 0 then return {""} end

        local linesOut = {}
        local current = ""
        local function pushCurrent()
            if current ~= "" then
                linesOut[#linesOut + 1] = current
                current = ""
            end
        end

        for _, word in ipairs(words) do
            local trial = current == "" and word or (current .. " " .. word)
            if measureTextWidth(trial) <= maxWidth then
                current = trial
            elseif current ~= "" then
                pushCurrent()
                if measureTextWidth(word) <= maxWidth then
                    current = word
                else
                    local chunk = ""
                    for _, ch in ipairs(utf8_chars(word)) do
                        local probe = chunk .. ch
                        if chunk ~= "" and measureTextWidth(probe) > maxWidth then
                            linesOut[#linesOut + 1] = chunk
                            chunk = ch
                        else
                            chunk = probe
                        end
                    end
                    current = chunk
                end
            else
                local chunk = ""
                for _, ch in ipairs(utf8_chars(word)) do
                    local probe = chunk .. ch
                    if chunk ~= "" and measureTextWidth(probe) > maxWidth then
                        linesOut[#linesOut + 1] = chunk
                        chunk = ch
                    else
                        chunk = probe
                    end
                end
                current = chunk
            end
        end
        pushCurrent()
        if #linesOut == 0 then linesOut[1] = "" end
        return linesOut
    end

    local sourceAuthorLines, sourceBookLines, sourceGenreLines
    if showSource then
        if dictSourceName then

            sourceAuthorLines = wrapSourceText(dictSourceName, sourceMaxW)
            sourceBookLines = {}
            sourceGenreLines = {}
        else
            sourceAuthorLines = wrapSourceText(u8"Автор: " .. tostring(race.sourceAuthor or ""), sourceMaxW)
            sourceBookLines = wrapSourceText(u8"Книга: " .. tostring(race.sourceBook or ""), sourceMaxW)
            sourceGenreLines = wrapSourceText(u8"Жанр: " .. tostring(race.sourceGenre or ""), sourceMaxW)
        end

        local sourceMetaLines = #sourceAuthorLines + #sourceBookLines + #sourceGenreLines
        local sourceBlockH = sourceTopPad + lineHeight + sourceMetaLines * sourceMetaLineH + 10
        local sourceTotalH = (#race.lines * lineHeight) + sourceBlockH
        local sourceMaxOffset = math.max(0, sourceTotalH - areaH)
        if sourceMaxOffset > scrollOffset then scrollOffset = sourceMaxOffset end
    end

    if drawlist then
        local startPos = contentStart
        local baseX = startPos.x + 4
        local baseY = startPos.y - scrollOffset
        local pendingU32 = imgui.ColorConvertFloat4ToU32(COL_PENDING)
        local activeU32 = imgui.ColorConvertFloat4ToU32(COL_ACTIVE)
        local errorU32 = imgui.ColorConvertFloat4ToU32(COL_ERROR)

        for li, line in ipairs(race.lines) do
            if (not showOne) or li == shownLine then
                local x = baseX
                local y = baseY + ((showOne and 0 or li - 1) * lineHeight)
                local linePrefix = ""
                local linePrefixW = 0
                local runText, runColor = nil, nil
                local runX = x
                local runUnderline = false

                local function flushRun()
                    if runText and runText ~= "" then
                        drawlist:AddText(imgui.ImVec2(runX, y), runColor, runText)
                        if runUnderline then

                            local exactW = measureTextWidth(runText)
                            if exactW > 0 then
                                drawlist:AddLine(
                                    imgui.ImVec2(runX, y + textLineHeight - 2),
                                    imgui.ImVec2(runX + exactW, y + textLineHeight - 2),
                                    runColor, 1.6
                                )
                            end
                        end
                    end
                    runText, runColor, runUnderline = nil, nil, false
                end

                for _, cell in ipairs(line) do

                    if cell.hiddenBreakSpace then
                        flushRun()
                    else
                        local idx = cell.idx
                        local isActive
                        if highlightMode == 1 then
                            isActive = (idx == race.confirmedLen + 1)
                        else
                            isActive = activeWord and idx >= activeWord.s and idx <= activeWord.e
                        end

                        local colorU32 = isActive
                            and (race.inError and errorU32 or activeU32)
                            or pendingU32
                        local underline = isActive

                        local newPrefix = linePrefix .. cell.ch
                        local newPrefixW = measureTextWidth(newPrefix)
                        local charAdvance = math.max(0, newPrefixW - linePrefixW)
                        local cellX = baseX + linePrefixW

                        if runColor ~= colorU32 then
                            flushRun()
                            runColor, runText, runX = colorU32, "", cellX
                            runUnderline = underline
                        elseif underline then
                            runUnderline = true
                        end

                        runText = runText .. cell.ch
                        linePrefix = newPrefix
                        linePrefixW = newPrefixW
                        x = baseX + linePrefixW
                    end
                end
                flushRun()
            end
        end

        if showSource then
            local sourceY = baseY + (#race.lines * lineHeight) + sourceTopPad
            local sourceX = baseX + sourcePadLeft
            local sourceTitleU32 = imgui.ColorConvertFloat4ToU32(COL_ACTIVE)
            local sourceTextU32 = imgui.ColorConvertFloat4ToU32(COL_PENDING)

            drawlist:AddText(imgui.ImVec2(sourceX, sourceY), sourceTitleU32, u8"Источник")

            local metaY = sourceY + lineHeight
            local function drawSourceLines(lines)
                for _, line in ipairs(lines) do
                    drawlist:AddText(imgui.ImVec2(sourceX, metaY), sourceTextU32, line)
                    metaY = metaY + sourceMetaLineH
                end
            end

            drawSourceLines(sourceAuthorLines)
            drawSourceLines(sourceBookLines)
            drawSourceLines(sourceGenreLines)
        end
    end

    imgui.EndChild()

    if fontPushed then pcall(imgui.PopFont) end
    pcall(imgui.SetWindowFontScale, 1.0)
end

local TXT_BQ = "\208\145\209\139\209\129\209\130\209\128\209\139\208\181\32\208\189\208\176\209\129\209\130\209\128\208\190\208\185\208\186\208\184"
local TXT_HL = "\208\159\208\190\208\180\209\129\208\178\208\181\209\130\208\186\208\176"
local TXT_WORD = "\209\129\208\187\208\190\208\178\208\190"
local TXT_CHAR = "\209\129\208\184\208\188\208\178\208\190\208\187"
local TXT_SPEED = "\208\161\208\191\208\184\208\180\208\190\208\188\208\181\209\130\209\128"
local TXT_OFF = "\208\178\209\139\208\186\208\187"
local TXT_ON = "\208\178\208\186\208\187"
local TXT_DISP = "\208\158\209\130\208\190\208\177\209\128\208\176\208\182\208\176\209\130\209\140"
local TXT_ALL = "\208\178\208\181\209\129\209\140\32\209\130\208\181\208\186\209\129\209\130"
local TXT_ONE = "\208\190\208\180\208\189\208\176\32\209\129\209\130\209\128\208\190\208\186\208\176"
local TXT_FONT = "\208\168\209\128\208\184\209\132\209\130"
local TXT_SIZE = "\208\160\208\176\208\183\208\188\208\181\209\128\32\209\130\208\181\208\186\209\129\209\130\208\176"
local TXT_SPACE = "\208\152\208\189\209\130\208\181\209\128\208\178\208\176\208\187"
local TXT_FIELD = "\208\160\208\176\208\183\208\188\208\181\209\128\32\208\191\208\190\208\187\209\143"
local CLAVA_FONT_GLYPH_RANGES = ffi.new("unsigned short[9]",
    0x0020, 0x00FF,
    0x0400, 0x04FF,
    0x2000, 0x206F,
    0x2DE0, 0x2DFF,
    0x0000
)

function ensureDirectoryExists(path)
    if not ok_lfs or not lfs then return end
    local clean = path:gsub("[\\/]+$", "")
    local okAttr, attr = pcall(lfs.attributes, clean)
    if okAttr and attr then return end
    pcall(lfs.mkdir, clean)
end

function loadClavaFonts()
    if ui.fontsLoaded then return true end

    ui.fontNames = { "System" }
    ui.fontFiles = {}
    ui.fontObjects = {}
    ui.fontLoadFailed = {}
    ui.fontLoadError = {}
    ui.fontScanError = nil

    local workDir = getWorkingDirectory()
    local fontsDir = workDir .. "\\fonts\\"
    pcall(ensureDirectoryExists, fontsDir)

    local windowsFontsDir = (os.getenv("WINDIR") or "C:\\Windows") .. "\\Fonts\\"
    local systemFonts = {
        { name = "Arial",           file = "arial.ttf" },
        { name = "Arial Bold",      file = "arialbd.ttf" },
        { name = "Arial Italic",    file = "ariali.ttf" },
        { name = "Tahoma",          file = "tahoma.ttf" },
        { name = "Tahoma Bold",     file = "tahomabd.ttf" },
        { name = "Verdana",         file = "verdana.ttf" },
        { name = "Verdana Bold",     file = "verdanab.ttf" },
        { name = "Segoe UI",        file = "segoeui.ttf" },
        { name = "Segoe UI Bold",   file = "segoeuib.ttf" },
        { name = "Segoe UI Light",  file = "segoeuil.ttf" },
        { name = "Calibri",         file = "calibri.ttf" },
        { name = "Calibri Bold",    file = "calibrib.ttf" },
        { name = "Times New Roman", file = "times.ttf" },
        { name = "Courier New",     file = "cour.ttf" },
        { name = "Comic Sans MS",   file = "comic.ttf" },
        { name = "Georgia",         file = "georgia.ttf" },
        { name = "Trebuchet MS",    file = "trebuc.ttf" },
        { name = "Impact",          file = "impact.ttf" },
        { name = "Consolas",        file = "consola.ttf" },
        { name = "Candara",         file = "Candara.ttf" },
        { name = "Franklin Gothic", file = "framd.ttf" },
        { name = "Palatino",        file = "pala.ttf" },
    }

    for _, fd in ipairs(systemFonts) do
        local path = windowsFontsDir .. fd.file
        local f = io.open(path, "rb")
        if f then
            f:close()
            ui.fontNames[#ui.fontNames + 1] = fd.name
            ui.fontFiles[#ui.fontFiles + 1] = path
        end
    end

    if ok_lfs and lfs then
        local okScan, scanErr = pcall(function()
            local files = {}
            local iter = assert(lfs.dir(fontsDir))
            for name in iter do
                if name ~= "." and name ~= ".." then
                    files[#files + 1] = name
                end
            end
            table.sort(files, function(a,b) return a:lower() < b:lower() end)

            for _, name in ipairs(files) do
                local ext = name:match("%.([^.]+)$")
                if ext and (ext:lower() == "ttf" or ext:lower() == "otf") then
                    local base = name:gsub("%.[^.]+$", "")
                    if not base:lower():find("nextwaveouttital", 1, true) then
                        local displayName = base
                        local okName, converted = pcall(function() return u8(base) end)
                        if okName and converted then displayName = converted end
                        ui.fontNames[#ui.fontNames + 1] = displayName
                        ui.fontFiles[#ui.fontFiles + 1] = fontsDir .. name
                    end
                end
            end
        end)
        if not okScan then ui.fontScanError = tostring(scanErr) end
    end

    ui.fontsLoaded = true
    return true
end

function buildFontAtlas()
    local ok, io_obj = pcall(imgui.GetIO)
    if not ok or not io_obj or not io_obj.Fonts then return false end
    if io_obj.Fonts.Build then
        local okBuild = pcall(function() io_obj.Fonts:Build() end)
        return okBuild
    end
    return false
end

function loadFontAtIndex(index)
    index = tonumber(index) or 0
    if index <= 0 then return true end
    if not ui.fontsLoaded then loadClavaFonts() end
    if ui.fontObjects[index] then return true end

    local path = ui.fontFiles[index]
    if not path or path == "" then
        ui.fontLoadFailed[index] = true
        ui.fontLoadError[index] = "no file mapped to this font index"
        return false
    end

    local io_obj = imgui.GetIO()
    if not io_obj or not io_obj.Fonts then
        ui.fontLoadFailed[index] = true
        ui.fontLoadError[index] = "ImGui IO/Fonts unavailable"
        return false
    end

    local ok, fontOrErr = pcall(function()
        local f = assert(io.open(path, "rb"))
        f:close()
        local font = io_obj.Fonts:AddFontFromFileTTF(path, 18.0, nil, CLAVA_FONT_GLYPH_RANGES)
        assert(font, "AddFontFromFileTTF returned nil")
        return font
    end)

    if not ok or not fontOrErr then
        ui.fontLoadFailed[index] = true
        ui.fontLoadError[index] = tostring(fontOrErr or "unknown font load error")
        return false
    end

    ui.fontObjects[index] = fontOrErr
    return true
end

if imgui.OnInitialize then
    imgui.OnInitialize(function()
        loadClavaFonts()
        for i = 1, #ui.fontFiles do
            loadFontAtIndex(i)
        end

        local io_obj = imgui.GetIO()
        if io_obj and io_obj.Fonts and io_obj.Fonts.Build then
            pcall(function() io_obj.Fonts:Build() end)
        end
    end)
end

function syncSettingsControls()
    local s = cfg.settings or {}
    ui.highlightModePtr[0] = math.max(0, math.min(1, math.floor((tonumber(s.highlight_mode) or 0) + 0.5)))
    ui.speedometerPtr[0] = (tonumber(s.speedometer) or 1) ~= 0
    ui.displayModePtr[0] = math.max(0, math.min(1, math.floor((tonumber(s.display_mode) or 0) + 0.5)))
    ui.fontIndexPtr[0] = math.max(0, math.floor((tonumber(s.font_index) or 0) + 0.5))
    ui.textScalePtr[0] = math.max(0.70, math.min(1.60, tonumber(s.text_scale) or 1.0))
    ui.charSpacingPtr[0] = math.max(100, math.min(400, math.floor((tonumber(s.char_spacing) or 100) + 0.5)))
    ui.textAreaHeightPtr[0] = math.max(90, math.min(260, math.floor((tonumber(s.text_area_height) or 150) + 0.5)))
    ui.countdownPtr[0] = math.max(0, math.min(15, math.floor((tonumber(s.countdown_seconds) or 5) + 0.5)))
    ui.fastChatEnabledPtr[0] = (tonumber(s.fastchat_enabled) or 0) ~= 0
    ui.fastChatIntervalPtr[0] = math.max(100, math.min(10000, math.floor((tonumber(s.fastchat_interval) or 2000) + 0.5)))
    ui.controlsSynced = true
end


local QUICK_FIELD_LEFT = 4.0
local function quickFieldShift(px)
    px = tonumber(px) or QUICK_FIELD_LEFT
    local ok, x = pcall(imgui.GetCursorPosX)
    if ok and type(x) == "number" then
        pcall(imgui.SetCursorPosX, x + px)
    end
end

function drawChoiceButtons(idPrefix, label, valuePtr, options, onChange)

    imgui.Text(label)
    local widths, totalW = {}, 0
    for i, option in ipairs(options) do
        local ok, ts = pcall(imgui.CalcTextSize, option)
        local tw = (ok and ts and ts.x) or (#utf8_chars(option) * 6.0)
        local bw = math.max(46, math.ceil(tw + 14))
        widths[i] = bw
        totalW = totalW + bw
        if i > 1 then totalW = totalW + 4 end
    end

    local okAvail, avail = pcall(imgui.GetContentRegionAvail)
    if okAvail and avail and totalW > avail.x then
        local usable = math.max(40, (avail.x - 4 * (#options - 1)))
        local scale = usable / math.max(1, totalW - 4 * (#options - 1))
        totalW = 0
        for i = 1, #widths do
            widths[i] = math.max(40, math.floor(widths[i] * scale))
            totalW = totalW + widths[i]
            if i > 1 then totalW = totalW + 4 end
        end
    end

    local okX, cursorX = pcall(imgui.GetCursorPosX)
    local okAvail2, avail2 = pcall(imgui.GetContentRegionAvail)
    if okX and okAvail2 and avail2 then
        pcall(imgui.SetCursorPosX, cursorX + math.max(0, (avail2.x - totalW) * 0.5) + QUICK_FIELD_LEFT)
    end

    for i, option in ipairs(options) do
        if i > 1 then imgui.SameLine(0, 2) end
        local selected = valuePtr[0] == (i - 1)
        local pushed = 0
        local selectedBg = themeActiveButton()
        local selectedHover = themeActiveButtonHover()
        if pcall(imgui.PushStyleColor, imgui.Col.Text, selected and colorVec(1,1,1,1) or THEME.text) then pushed = pushed + 1 end
        if pcall(imgui.PushStyleColor, imgui.Col.Button, selected and selectedBg or THEME.button) then pushed = pushed + 1 end
        if pcall(imgui.PushStyleColor, imgui.Col.ButtonHovered, selected and selectedHover or THEME.buttonHov) then pushed = pushed + 1 end
        if pcall(imgui.PushStyleColor, imgui.Col.ButtonActive, selected and COL_ACCENT or THEME.buttonAct) then pushed = pushed + 1 end
        if pcall(imgui.PushStyleColor, imgui.Col.Border, THEME.border) then pushed = pushed + 1 end
        local pushedVars = 0
        if imgui.StyleVar and imgui.StyleVar.FrameBorderSize then
            if pcall(imgui.PushStyleVar, imgui.StyleVar.FrameBorderSize, 1.0) then
                pushedVars = pushedVars + 1
            end
        end
        if imgui.Button(option .. "##" .. idPrefix .. tostring(i), imgui.ImVec2(widths[i], 0)) then
            valuePtr[0] = i - 1
            onChange(valuePtr[0])
        end
        if pushedVars > 0 then pcall(imgui.PopStyleVar, pushedVars) end
        if pushed > 0 then pcall(imgui.PopStyleColor, pushed) end
    end
end

function drawThinSlider(id, ptr, minValue, maxValue, isInt, format, widthOverride)

    local width = tonumber(widthOverride) or 65
    local height = 15
    local ok_p, p0 = pcall(imgui.GetCursorScreenPos)
    if not ok_p or not p0 then return false end

    local changed = false
    pcall(imgui.InvisibleButton, id, imgui.ImVec2(width, height))

    local ok_min, bmin = pcall(imgui.GetItemRectMin)
    local ok_max, bmax = pcall(imgui.GetItemRectMax)
    if not (ok_min and ok_max and bmin and bmax) then return false end

    local ok_active, active = pcall(imgui.IsItemActive)
    local ok_hover, hovered = pcall(imgui.IsItemHovered)
    local ok_click, clicked = pcall(imgui.IsItemClicked, 0)
    active = ok_active and active or false
    hovered = ok_hover and hovered or false
    clicked = ok_click and clicked or false

    local mouseX = nil
    if active or (hovered and clicked) then
        local ok_m, mp = pcall(imgui.GetMousePos)
        if ok_m and mp then mouseX = mp.x end
    end

    local knobRadius = 4.0
    local sidePad = knobRadius + 3.0
    local x0 = bmin.x + sidePad
    local x1 = bmax.x - sidePad
    local cy = (bmin.y + bmax.y) * 0.5
    local usable = math.max(1, x1 - x0)

    local value = tonumber(ptr[0]) or minValue
    if mouseX then
        local t = math.max(0, math.min(1, (mouseX - x0) / usable))
        local nv = minValue + (maxValue - minValue) * t
        if isInt then
            nv = math.floor(nv + 0.5)
        end
        nv = math.max(minValue, math.min(maxValue, nv))
        if nv ~= value then
            ptr[0] = nv
            value = nv
            changed = true
        end
    end

    local t = (value - minValue) / math.max(0.000001, maxValue - minValue)
    t = math.max(0, math.min(1, t))
    local knobX = x0 + usable * t

    local drawlist = imgui.GetWindowDrawList()
    if drawlist then
        local lineCol = imgui.ColorConvertFloat4ToU32(themeSliderTrack())
        local lineColHover = imgui.ColorConvertFloat4ToU32(themeSliderTrackHover())
        local knobCol = imgui.ColorConvertFloat4ToU32(themeSliderValue())
        local knobBorder = imgui.ColorConvertFloat4ToU32(themeSliderKnobBorder())
        drawlist:AddLine(imgui.ImVec2(x0, cy), imgui.ImVec2(x1, cy), hovered and lineColHover or lineCol, 1.5)
        drawlist:AddCircleFilled(imgui.ImVec2(knobX, cy), knobRadius, knobCol, 20)
        drawlist:AddCircle(imgui.ImVec2(knobX, cy), knobRadius, knobBorder, 20, 1.0)
    end

    return changed
end

function drawNumericFloat(label, ptr, minValue, maxValue, format)
    quickFieldShift()
    local changed = drawThinSlider("##thin_float_" .. label, ptr, minValue, maxValue, false, format)
    imgui.SameLine(0, 2)
    imgui.Text(label)
    return changed
end

function drawNumericInt(label, ptr, minValue, maxValue)
    quickFieldShift()
    local changed = drawThinSlider("##thin_int_" .. label, ptr, minValue, maxValue, true, "")
    imgui.SameLine(0, 2)
    imgui.Text(label .. "  [" .. tostring(ptr[0]) .. "]")
    return changed
end

function drawFontChoice()
    imgui.Text(TXT_FONT)
    imgui.SameLine(0, 2)

    local names = ui.fontNames or { "System" }
    if #names == 0 then return end
    if ui.fontIndexPtr[0] < 0 or ui.fontIndexPtr[0] >= #names then
        ui.fontIndexPtr[0] = 0
    end

    if not ui.fontComboItems or ui.fontComboItemCount ~= #names then
        ui.fontComboItems = ffi.new("const char*[?]", #names, names)
        ui.fontComboItemCount = #names
    end

    local pushed = 0
    local function pc(id, c)
        if id ~= nil and pcall(imgui.PushStyleColor, id, c) then pushed = pushed + 1 end
    end
    pc(imgui.Col.FrameBg,       THEME.frameBg)
    pc(imgui.Col.FrameBgHovered,THEME.headerHov)
    pc(imgui.Col.FrameBgActive, themeMix(THEME.frameBg, COL_ACCENT, 0.16))
    pc(imgui.Col.Text,          THEME.text)
    if imgui.Col.PopupBg then pc(imgui.Col.PopupBg, THEME.childBg) end
    pc(imgui.Col.Header,        THEME.header)
    pc(imgui.Col.HeaderHovered, THEME.headerHov)
    pc(imgui.Col.HeaderActive,  THEME.headerAct)

    pc(imgui.Col.Border,        THEME.border)
    local pushedVars = 0
    if imgui.StyleVar and imgui.StyleVar.FrameBorderSize then
        if pcall(imgui.PushStyleVar, imgui.StyleVar.FrameBorderSize, 1.0) then pushedVars = pushedVars + 1 end
    end
    if imgui.StyleVar and imgui.StyleVar.PopupBorderSize then
        if pcall(imgui.PushStyleVar, imgui.StyleVar.PopupBorderSize, 1.0) then pushedVars = pushedVars + 1 end
    end

    local fontBoxMin, fontBoxMax
    quickFieldShift()
    if imgui.SetNextItemWidth then pcall(imgui.SetNextItemWidth, 120) end
    local ok, changed = pcall(imgui.Combo, "##qs_font_combo", ui.fontIndexPtr, ui.fontComboItems, #names)
    if pcall(imgui.GetItemRectMin) then
        fontBoxMin = imgui.GetItemRectMin()
        fontBoxMax = imgui.GetItemRectMax()
    end
    if pushedVars > 0 then pcall(imgui.PopStyleVar, pushedVars) end
    if pushed > 0 then pcall(imgui.PopStyleColor, pushed) end

    if fontBoxMin and fontBoxMax then
        local dl = imgui.GetWindowDrawList()
        if dl then
            dl:AddRect(
                imgui.ImVec2(fontBoxMin.x, fontBoxMin.y),
                imgui.ImVec2(fontBoxMax.x, fontBoxMax.y),
                imgui.ColorConvertFloat4ToU32(THEME.text),
                3.0, 0, 1.2
            )
        end
    end

    if ok and changed then
        local newIndex = math.max(0, math.min(#names - 1, tonumber(ui.fontIndexPtr[0]) or 0))
        ui.fontIndexPtr[0] = newIndex
        cfg.settings.font_index = newIndex
        if newIndex > 0 then pcall(loadFontAtIndex, newIndex) end
        saveCfg()
    end
end

function drawQuickSettings()
    if not ui.controlsSynced then syncSettingsControls() end


    local quickStyle = nil
    local quickPadX, quickPadY = nil, nil
    local okQuickStyle, st = pcall(imgui.GetStyle)
    if okQuickStyle and st then
        quickStyle = st
        local okPad, fp = pcall(function() return st.FramePadding end)
        if okPad and fp then
            quickPadX, quickPadY = fp.x, fp.y
            pcall(function() st.FramePadding = imgui.ImVec2(4.0, fp.y) end)
        end
    end
    if not ui.fontsLoaded then pcall(loadClavaFonts) end

    local compactPushed = pcall(imgui.SetWindowFontScale, 0.74)
    imgui.Text(TXT_BQ)
    imgui.Separator()

    drawChoiceButtons("qs_highlight_", TXT_HL, ui.highlightModePtr, {TXT_WORD, TXT_CHAR}, function(v)
        cfg.settings.highlight_mode = v
        saveCfg()
    end)
    imgui.Dummy(imgui.ImVec2(0, 1))

    imgui.Text(TXT_SPEED)
    imgui.SameLine(0, 2)
    quickFieldShift()
    local okSpeed, speedChanged = pcall(imgui.Checkbox, "##qs_speed_checkbox", ui.speedometerPtr)

    if okSpeed then
        pcall(function()
            local pmin = imgui.GetItemRectMin()
            local pmax = imgui.GetItemRectMax()
            local dl = imgui.GetWindowDrawList()
            if dl and pmin and pmax then
                local boxH = pmax.y - pmin.y
                local boxW = math.min(boxH, pmax.x - pmin.x)
                local x1 = pmin.x + 0.5
                local y1 = pmin.y + 0.5
                local x2 = x1 + boxW - 1.0
                local y2 = y1 + boxH - 1.0
                dl:AddRect(
                    imgui.ImVec2(x1, y1),
                    imgui.ImVec2(x2, y2),
                    imgui.ColorConvertFloat4ToU32(THEME.border),
                    0.0, 0, 1.0
                )
            end
        end)
    end
    imgui.SameLine(0, 3)
    imgui.Text(ui.speedometerPtr[0] and TXT_ON or TXT_OFF)
    if okSpeed and speedChanged then
        cfg.settings.speedometer = ui.speedometerPtr[0] and 1 or 0
        saveCfg()
    end
    imgui.Dummy(imgui.ImVec2(0, 1))

    drawChoiceButtons("qs_display_", TXT_DISP, ui.displayModePtr, {TXT_ALL, TXT_ONE}, function(v)
        cfg.settings.display_mode = v
        saveCfg()
    end)
    imgui.Dummy(imgui.ImVec2(0, 1))

    drawFontChoice()
    imgui.Dummy(imgui.ImVec2(0, 1))

    if drawNumericFloat(TXT_SIZE, ui.textScalePtr, 0.70, 1.60, "%.2fx") then
        cfg.settings.text_scale = math.floor((tonumber(ui.textScalePtr[0]) or 1.0) * 100 + 0.5) / 100
        saveCfg()
    end
    imgui.Dummy(imgui.ImVec2(0, 1))

    if drawNumericInt(TXT_SPACE, ui.charSpacingPtr, 100, 400, "%") then
        cfg.settings.char_spacing = math.floor(ui.charSpacingPtr[0])
        saveCfg()
    end
    imgui.Dummy(imgui.ImVec2(0, 1))

    if drawNumericInt(TXT_FIELD, ui.textAreaHeightPtr, 90, 260) then
        cfg.settings.text_area_height = math.floor(ui.textAreaHeightPtr[0])
        saveCfg()
    end

    if quickStyle and quickPadX ~= nil and quickPadY ~= nil then
        pcall(function() quickStyle.FramePadding = imgui.ImVec2(quickPadX, quickPadY) end)
    end
    if compactPushed then pcall(imgui.SetWindowFontScale, 1.0) end
end

local KEY_SCALE = 1.10
local KEY_SIZE = 25 * KEY_SCALE
local KEY_GAP  = 3 * KEY_SCALE
local HOME_ROW_INDEX = 3

function measureTextWidth(label)
    local ok, size = pcall(imgui.CalcTextSize, label)
    if ok and size and size.x and size.x > 0 then return size.x end

    return #utf8_chars(label) * 7.0
end

function drawFingerLabels(bounds, y)
    local drawlist = imgui.GetWindowDrawList()
    if not drawlist or not bounds then return end
    local groups = {
        { key = 1, label = u8"Мизинец" },
        { key = 2, label = u8"Безымянный" },
        { key = 3, label = u8"Средний" },
        { key = "idx", label = u8"Указательные" },
        { key = 6, label = u8"Средний" },
        { key = 7, label = u8"Безымянный" },
        { key = 8, label = u8"Мизинец" },
    }

    local scaledOk = pcall(imgui.SetWindowFontScale, 0.72)
    local layout = {}
    for _, g in ipairs(groups) do
        local b
        if g.key == "idx" then
            local b4, b5 = bounds[4], bounds[5]
            if b4 and b5 then
                b = { minX = math.min(b4.minX, b5.minX), maxX = math.max(b4.maxX, b5.maxX) }
            end
        else
            b = bounds[g.key]
        end
        if b then
            local badgeScale = 0.72
            if g.label == u8"Безымянный" then
                badgeScale = 0.60
            elseif g.label == u8"Указательные" then
                badgeScale = 0.62
            elseif g.label == u8"Средний" then
                badgeScale = 0.66
            end
            pcall(imgui.SetWindowFontScale, badgeScale)
            local textW, textH = 0, 0
            local okSize, size = pcall(imgui.CalcTextSize, g.label)
            if okSize and size then
                textW = tonumber(size.x) or 0
                textH = tonumber(size.y) or 0
            end
            if textW <= 0 then textW = measureTextWidth(g.label) * badgeScale end
            if textH <= 0 then textH = 11 end
            local padX = (g.key == 1 or g.key == 8) and 6 or 3
            layout[#layout + 1] = {
                g = g, b = b, cx = (b.minX + b.maxX) / 2,
                textW = textW, textH = textH, padX = padX,
                badgeScale = badgeScale
            }
        end
    end

    local pinkLeft, pinkRight
    for _, item in ipairs(layout) do
        if item.g.key == 1 then pinkLeft = item
        elseif item.g.key == 8 then pinkRight = item
        end
    end
    local outerShift = 8.0
    if pinkLeft then pinkLeft.cx = pinkLeft.cx - outerShift end
    if pinkRight then pinkRight.cx = pinkRight.cx + outerShift end

    if pinkLeft and pinkRight and pinkRight.cx > pinkLeft.cx then
        local leftEdge = pinkLeft.cx + (pinkLeft.textW / 2 + pinkLeft.padX)
        local rightEdge = pinkRight.cx - (pinkRight.textW / 2 + pinkRight.padX)
        local inner = {}
        for _, item in ipairs(layout) do
            if item ~= pinkLeft and item ~= pinkRight then
                inner[#inner + 1] = item
            end
        end
        table.sort(inner, function(a, b) return a.cx < b.cx end)

        local totalWidth = 0
        for _, item in ipairs(inner) do
            totalWidth = totalWidth + item.textW + item.padX * 2
        end
        local available = rightEdge - leftEdge
        local gap = 6.0
        local requiredGaps = (#inner + 1) * gap
        if available > totalWidth + requiredGaps then
            gap = (available - totalWidth) / (#inner + 1)
        else
            gap = 4.0
        end

        local cursor = leftEdge + gap
        for _, item in ipairs(inner) do
            local half = item.textW / 2 + item.padX
            item.cx = cursor + half
            cursor = cursor + half * 2 + gap
        end
    end

    pcall(function()
        for _, item in ipairs(layout) do
            local g, b = item.g, item.b
            local cx = item.cx
            local textW, textH, padX, badgeScale = item.textW, item.textH, item.padX, item.badgeScale
            pcall(imgui.SetWindowFontScale, badgeScale)
            local badgeH = math.max(17, textH + 5)
            local bx0 = cx - textW / 2 - padX
            local bx1 = cx + textW / 2 + padX
            local by0 = y
            local by1 = y + badgeH

                if g.key == "idx" and bounds[4] and bounds[5] then

                    local midX = (bx0 + bx1) / 2
                    local c4 = FINGER_COLOR[4]
                    local c5 = FINGER_COLOR[5]
                    local leftCol = imgui.ColorConvertFloat4ToU32(colorVec(c4[1], c4[2], c4[3], 1.0))
                    local rightCol = imgui.ColorConvertFloat4ToU32(colorVec(c5[1], c5[2], c5[3], 1.0))
                    drawlist:AddRectFilled(imgui.ImVec2(bx0, by0), imgui.ImVec2(midX, by1), leftCol)
                    drawlist:AddRectFilled(imgui.ImVec2(midX, by0), imgui.ImVec2(bx1, by1), rightCol)
                    local borderCol = imgui.ColorConvertFloat4ToU32(colorVec(0.34, 0.34, 0.34, 1.0))
                    drawlist:AddRect(imgui.ImVec2(bx0, by0), imgui.ImVec2(bx1, by1), borderCol, 5.0, nil, 1.0)
                else
                    local color = FINGER_COLOR[g.key] or FINGER_COLOR[0]
                    local badgeCol = imgui.ColorConvertFloat4ToU32(colorVec(color[1], color[2], color[3], 1.0))
                    local borderCol = imgui.ColorConvertFloat4ToU32(darken(color, 0.72))
                    drawlist:AddRectFilled(imgui.ImVec2(bx0, by0), imgui.ImVec2(bx1, by1), badgeCol, 5.0)
                    drawlist:AddRect(imgui.ImVec2(bx0, by0), imgui.ImVec2(bx1, by1), borderCol, 5.0, nil, 1.0)
                end

                local textCol = imgui.ColorConvertFloat4ToU32(colorVec(0.08, 0.08, 0.08, 1.0))
                drawlist:AddText(
                    imgui.ImVec2(cx - textW / 2, by0 + (badgeH - textH) / 2),
                    textCol,
                    g.label
                )
            pcall(imgui.SetWindowFontScale, 0.72)
        end
    end)
    if scaledOk then pcall(imgui.SetWindowFontScale, 1.0) end
    pcall(imgui.Dummy, imgui.ImVec2(10, 21))
end

local drawKeyboardToggle

function drawKeyboard()

    local keyboardPrevRounding = nil
    local okStyle, keyboardStyle = pcall(imgui.GetStyle)
    if okStyle and keyboardStyle then
        local okPrev, prev = pcall(function() return keyboardStyle.FrameRounding end)
        if okPrev and type(prev) == 'number' then
            keyboardPrevRounding = prev
            pcall(function() keyboardStyle.FrameRounding = 0.0 end)
        end
    end

    local nextIdx = race.confirmedLen + 1
    local nextCh = race.targetChars[nextIdx]
    local showInputHints = race.started and not race.finished and not race.failed and not race.countingDown






    local symbolTargetLayout = race.targetLayout
        or ((getModeById(race.modeId).layout == "en") and "en" or "ru")

    local targetMap = (symbolTargetLayout == "en") and EN_CHAR_TO_KEY or RU_CHAR_TO_KEY
    local hintSet = KEY_HINT[symbolTargetLayout] or KEY_HINT.ru
    local nextLower = nextCh and (nextCh == " " and " " or utf8_lower_char(nextCh)) or nil
    local hintInfo = showInputHints and nextCh and hintSet[nextCh] or nil
    local targetKeyRef = showInputHints and (not race.inError) and nextLower and targetMap[nextLower] or nil
    local needsLayoutSwitch = showInputHints and (not race.inError) and symbolTargetLayout ~= ui.layout
    local needsShift = showInputHints and (not race.inError) and nextCh and (utf8_is_upper(nextCh) or (hintInfo and hintInfo.shift)) or false
    local nextKeyCode = nil
    if showInputHints and not race.inError then
        if hintInfo and hintInfo.code then
            nextKeyCode = hintInfo.code
        elseif nextCh == " " then

            nextKeyCode = 0x20
        elseif targetKeyRef and targetKeyRef.code then
            nextKeyCode = targetKeyRef.code
        end
    end

    local needsBackspace = showInputHints and race.inError and not race.failed

    local drawlist = imgui.GetWindowDrawList()
    local fingerBounds = {}

    for rowIdx, row in ipairs(getKeyboardRows()) do
        for ki, key in ipairs(row) do
            local w = KEY_SIZE * key.w + KEY_GAP * (key.w - 1)
            local h = KEY_SIZE
            local fc = FINGER_COLOR[key.finger] or FINGER_COLOR[0]
            local pc = FINGER_PRESSED_COLOR[key.finger] or FINGER_PRESSED_COLOR[0]
            local isPhysicallyDown = false
            if key.code and key.code ~= 0 then
                local okDown, down = pcall(function()
                    return ffi.C.GetAsyncKeyState(key.code) < 0
                end)
                isPhysicallyDown = okDown and down or false
            end

            local fill = colorVec(fc[1], fc[2], fc[3], 1.0)







            local isNextKey = showInputHints and not race.inError
                and not needsLayoutSwitch
                and ui.layout == symbolTargetLayout
                and nextKeyCode and key.code == nextKeyCode or false
            local isShiftKey = (key.code == 0x10)
            local isAltKey = (key.code == 0x12)
            local isBackspaceKey = (key == BACKSPACE_KEY)

            if isPhysicallyDown and key.finger ~= 0 then
                fill = colorVec(pc[1], pc[2], pc[3], 1.0)
            elseif key.homeBump then

                fill = colorVec(fc[1], fc[2], fc[3], 1.0)
            end

            if not isPhysicallyDown then

                if isNextKey
                    or (isShiftKey and (needsShift or needsLayoutSwitch))
                    or (isAltKey and needsLayoutSwitch)
                    or (isBackspaceKey and needsBackspace) then
                    fill = colorVec(pc[1], pc[2], pc[3], 1.0)
                end
            end

            local pushed = 0
            if pcall(imgui.PushStyleColor, imgui.Col.Button, fill) then pushed = pushed + 1 end
            if pcall(imgui.PushStyleColor, imgui.Col.ButtonHovered, fill) then pushed = pushed + 1 end
            if pcall(imgui.PushStyleColor, imgui.Col.ButtonActive, fill) then pushed = pushed + 1 end
            if pcall(imgui.PushStyleColor, imgui.Col.Text, colorVec(0.12, 0.11, 0.10, 1)) then pushed = pushed + 1 end

            local labelScale = 1.0
            local textOk, textSize = pcall(imgui.CalcTextSize, key.label)
            if textOk and textSize and textSize.x and textSize.x > 0 then
                local innerW = math.max(12, w - 10)
                if textSize.x > innerW then
                    labelScale = math.max(0.56, math.min(1.0, innerW / textSize.x))
                end
                if key.code == 0x08 then



                    labelScale = math.min(labelScale, 0.64)
                end
            end

            local fontScaled = false
            if labelScale < 0.999 then
                fontScaled = pcall(imgui.SetWindowFontScale, labelScale)
            end

            local uniqueLabel = key.label .. "##kb" .. tostring(ki) .. "_" .. tostring(key.code) .. "_" .. tostring(rowIdx)



            local pushedTextAlign = false
            local alignX = (key.code == 0x08) and 0.54 or 0.5
            if imgui.StyleVar and imgui.StyleVar.ButtonTextAlign then
                pushedTextAlign = pcall(imgui.PushStyleVar, imgui.StyleVar.ButtonTextAlign, imgui.ImVec2(alignX, 0.5))
            end
            imgui.Button(uniqueLabel, imgui.ImVec2(w, h))
            if pushedTextAlign then pcall(imgui.PopStyleVar, 1) end

            if fontScaled then pcall(imgui.SetWindowFontScale, 1.0) end

            if key.homeBump and drawlist then
                pcall(function()
                    local pmin = imgui.GetItemRectMin()
                    local pmax = imgui.GetItemRectMax()
                    local pressColor = FINGER_PRESSED_COLOR[key.finger] or FINGER_PRESSED_COLOR[0]
                    local outline = imgui.ColorConvertFloat4ToU32(
                        colorVec(pressColor[1], pressColor[2], pressColor[3], 1.0)
                    )
                    drawlist:AddRect(
                        imgui.ImVec2(pmin.x, pmin.y),
                        imgui.ImVec2(pmax.x, pmax.y),
                        outline,
                        0.0,
                        nil,
                        2.0
                    )
                end)
            end

            if rowIdx == HOME_ROW_INDEX and key.finger and key.finger >= 1 and key.finger <= 8 and drawlist then
                pcall(function()
                    local pmin = imgui.GetItemRectMin()
                    local pmax = imgui.GetItemRectMax()
                    local b = fingerBounds[key.finger]
                    if not b then
                        fingerBounds[key.finger] = { minX = pmin.x, maxX = pmax.x }
                    else
                        b.minX = math.min(b.minX, pmin.x)
                        b.maxX = math.max(b.maxX, pmax.x)
                    end
                end)
            end

            if pushed > 0 then pcall(imgui.PopStyleColor, pushed) end
            imgui.SameLine(0, KEY_GAP)
        end
        imgui.NewLine()
    end

    if keyboardPrevRounding ~= nil and okStyle and keyboardStyle then
        pcall(function() keyboardStyle.FrameRounding = keyboardPrevRounding end)
    end

    imgui.Spacing()
    local ok_p, p0 = pcall(imgui.GetCursorScreenPos)
    if ok_p then
        drawFingerLabels(fingerBounds, p0.y)

        imgui.Spacing()
        drawKeyboardToggle()
    end

end

drawKeyboardToggle = function()
    local label = ui.keyboardVisible[0] and u8"Скрыть экранную клавиатуру" or u8"Показать экранную клавиатуру"
    local toggleW = 235
    local pushed = 0
    if pcall(imgui.PushStyleColor, imgui.Col.Text, THEME.accent or COL_ACCENT) then pushed = pushed + 1 end
    if pcall(imgui.PushStyleColor, imgui.Col.Button, colorVec(0,0,0,0)) then pushed = pushed + 1 end
    if pcall(imgui.PushStyleColor, imgui.Col.ButtonHovered, themeMix(THEME.accent or COL_ACCENT, THEME.windowBg, 0.84)) then pushed = pushed + 1 end
    if pcall(imgui.PushStyleColor, imgui.Col.ButtonActive, themeMix(THEME.accent or COL_ACCENT, THEME.windowBg, 0.70)) then pushed = pushed + 1 end
    if pcall(imgui.PushStyleColor, imgui.Col.Border, themeBorderSoft()) then pushed = pushed + 1 end

    local ok_a, av = pcall(imgui.GetContentRegionAvail)
    local ok_x, cx = pcall(imgui.GetCursorPosX)
    if ok_a and av and ok_x and cx then
        pcall(imgui.SetCursorPosX, cx + math.max(0, (av.x - toggleW) * 0.5))
    end
    imgui.SmallButton(label .. "##keyboard_toggle_bottom")
    if imgui.IsItemClicked and imgui.IsItemClicked() then
        ui.keyboardVisible[0] = not ui.keyboardVisible[0]
    end
    if pushed > 0 then pcall(imgui.PopStyleColor, pushed) end
end

function drawBackButton(label, id)
    local pushed = 0
    if pcall(imgui.PushStyleColor, imgui.Col.Text, THEME.accent or COL_ACCENT) then pushed = pushed + 1 end
    if pcall(imgui.PushStyleColor, imgui.Col.Button, colorVec(0,0,0,0)) then pushed = pushed + 1 end
    if pcall(imgui.PushStyleColor, imgui.Col.ButtonHovered, themeMix(THEME.accent or COL_ACCENT, THEME.windowBg, 0.84)) then pushed = pushed + 1 end
    if pcall(imgui.PushStyleColor, imgui.Col.ButtonActive, themeMix(THEME.accent or COL_ACCENT, THEME.windowBg, 0.70)) then pushed = pushed + 1 end
    if pcall(imgui.PushStyleColor, imgui.Col.Border, themeBorderSoft()) then pushed = pushed + 1 end
    local clicked = imgui.SmallButton((label or u8"< Назад") .. (id or ""))
    if pushed > 0 then pcall(imgui.PopStyleColor, pushed) end
    return clicked
end

function drawTrack(progress)
    local ok_dl, drawlist = pcall(imgui.GetWindowDrawList)
    local ok_p, p0 = pcall(imgui.GetCursorScreenPos)
    if not (ok_dl and ok_p and drawlist) then return end
    local ok_w, avail = pcall(imgui.GetContentRegionAvail)
    local width = (ok_w and avail and avail.x) or 640
    local laneH = 40
    local x0, y0 = p0.x, p0.y + 24
    local x1 = x0 + width

    pcall(function()
        local dashCol = imgui.ColorConvertFloat4ToU32(COL_YELLOW)
        local dashLen, gapLen = 10, 6
        local x = x0
        while x < x1 - 6 do
            local xend = math.min(x + dashLen, x1 - 6)
            drawlist:AddLine(imgui.ImVec2(x, y0), imgui.ImVec2(xend, y0), dashCol, 3.0)
            x = x + dashLen + gapLen
        end

        local carX = x0 + (x1 - x0 - 18) * math.max(0, math.min(1, progress))
        local carCol = imgui.ColorConvertFloat4ToU32(colorVec(0.85, 0.08, 0.08, 1.0))
        drawlist:AddRectFilled(imgui.ImVec2(carX, y0 - 10), imgui.ImVec2(carX + 18, y0 - 2), carCol, 3.0)
        local wheelCol = imgui.ColorConvertFloat4ToU32(colorVec(0.02, 0.02, 0.02, 1.0))
        drawlist:AddCircleFilled(imgui.ImVec2(carX + 3, y0 - 1), 2.6, wheelCol, 8)
        drawlist:AddCircleFilled(imgui.ImVec2(carX + 15, y0 - 1), 2.6, wheelCol, 8)

        local fx = x1 - 6 - 16
        local rows, cols, sq = 5, 2, 4
        local c1 = imgui.ColorConvertFloat4ToU32(colorVec(0.10, 0.10, 0.10, 1))
        local c2 = imgui.ColorConvertFloat4ToU32(colorVec(1, 1, 1, 1))
        for row = 0, rows - 1 do
            for col = 0, cols - 1 do
                local cc = ((row + col) % 2 == 0) and c1 or c2
                drawlist:AddRectFilled(
                    imgui.ImVec2(fx + col * sq, y0 - 4 - rows * sq + row * sq),
                    imgui.ImVec2(fx + col * sq + sq, y0 - 4 - rows * sq + row * sq + sq), cc)
            end
        end

        for _, m in ipairs(race.errorMarkers) do
            local frac = math.max(0, math.min(1, (m.pos - 1) / math.max(1, #race.targetChars)))
            local mx = x0 + (x1 - x0) * frac
            local mcol = imgui.ColorConvertFloat4ToU32(COL_ERROR)
            drawlist:AddCircleFilled(imgui.ImVec2(mx, y0 + 12), 3.5, mcol, 10)
            drawlist:AddCircle(imgui.ImVec2(mx, y0 + 12), 3.5, imgui.ColorConvertFloat4ToU32(themeMix(COL_ERROR, THEME.windowBg, 0.25)), 10, 1.0)
            if m.count > 1 then
                drawlist:AddText(imgui.ImVec2(mx + 5, y0 + 7), mcol, "x" .. tostring(m.count))
            end
        end
    end)

    pcall(imgui.Dummy, imgui.ImVec2(width, laneH))
end

function drawDashboard(speedVal, errVal, maxSpeed)
    local ok_dl, drawlist = pcall(imgui.GetWindowDrawList)
    local ok_p, p0 = pcall(imgui.GetCursorScreenPos)
    if not (ok_dl and ok_p and drawlist) then return end

    local panelH, dialW, errW = 82, 89, 89
    local panelW = dialW + errW
    local x0, y0 = p0.x, p0.y
    local x1, y1 = x0 + panelW, y0 + panelH

    pcall(function()
        local bg = imgui.ColorConvertFloat4ToU32(THEME.titleBgAct)
        drawlist:AddRectFilled(imgui.ImVec2(x0, y0), imgui.ImVec2(x1, y1), bg, 10.0)
        local border = imgui.ColorConvertFloat4ToU32(THEME.border)
        drawlist:AddRect(imgui.ImVec2(x0, y0), imgui.ImVec2(x1, y1), border, 10.0, nil, 1.5)
        drawlist:AddLine(imgui.ImVec2(x0 + dialW, y0 + 8), imgui.ImVec2(x0 + dialW, y1 - 8),
            imgui.ColorConvertFloat4ToU32(themeMix(THEME.border, THEME.text, 0.35)), 1.0)
    end)

    local cx, cy = x0 + dialW * 0.5, y0 + 75 * 0.5 - 4
    local r = 26
    local aMin, aMax = math.rad(160), math.rad(380)
    pcall(function()
        drawlist:PathClear()
        drawlist:PathArcTo(imgui.ImVec2(cx, cy), r, aMin, aMax, 40)
        drawlist:PathStroke(imgui.ColorConvertFloat4ToU32(THEME.headerAct), false, 6.0)
    end)
    local frac = math.max(0, math.min(1, speedVal / (maxSpeed or 220)))
    local aVal = aMin + (aMax - aMin) * frac
    pcall(function()
        drawlist:PathClear()
        drawlist:PathArcTo(imgui.ImVec2(cx, cy), r, aMin, aVal, 40)
        drawlist:PathStroke(imgui.ColorConvertFloat4ToU32(COL_YELLOW), false, 6.0)
    end)
    pcall(function()
        local nx = cx + math.cos(aVal) * (r - 10)
        local ny = cy + math.sin(aVal) * (r - 10)
        drawlist:AddLine(imgui.ImVec2(cx, cy), imgui.ImVec2(nx, ny), imgui.ColorConvertFloat4ToU32(THEME.text), 2.0)
        drawlist:AddCircleFilled(imgui.ImVec2(cx, cy), 3.0, imgui.ColorConvertFloat4ToU32(THEME.text), 12)
    end)

    pcall(function()
        local white = imgui.ColorConvertFloat4ToU32(THEME.text)
        local dim = imgui.ColorConvertFloat4ToU32(themeTextSubtle())
        local speedText = tostring(speedVal)
        local unitText = u8"зн/мин"

        local function centeredTextX(text, centerX)
            local okSize, size = pcall(imgui.CalcTextSize, text)
            local width = (okSize and size and size.x) or (#text * 7)
            return centerX - width * 0.5
        end

        local dialCenterX = x0 + dialW * 0.5
        drawlist:AddText(
            imgui.ImVec2(centeredTextX(speedText, dialCenterX), y0 + panelH - 34),
            imgui.ColorConvertFloat4ToU32(COL_YELLOW),
            speedText
        )
        drawlist:AddText(
            imgui.ImVec2(centeredTextX(unitText, dialCenterX), y1 - 18),
            dim,
            unitText
        )
        drawlist:AddText(imgui.ImVec2(x0 + dialW + 14, y0 + 10), dim, u8"ОШИБКИ")
        drawlist:AddText(imgui.ImVec2(x0 + dialW + 14, y0 + 34), imgui.ColorConvertFloat4ToU32(COL_ERROR), tostring(errVal))
    end)

end

function drawStatCard(x, y, w, h, label, value, sub, kind)
    local ok_dl, drawlist = pcall(imgui.GetWindowDrawList)
    if not ok_dl then return end
    pcall(function()
        local isBlue = kind == "blue"
        local metricCol = isBlue and COL_ACTIVE or COL_YELLOW
        local bg = imgui.ColorConvertFloat4ToU32(themeMix(THEME.childBg, metricCol, 0.10))
        local border = imgui.ColorConvertFloat4ToU32(themeMix(THEME.border, metricCol, 0.45))
        local labelCol = imgui.ColorConvertFloat4ToU32(themeMix(THEME.text, metricCol, 0.42))
        local valueCol = imgui.ColorConvertFloat4ToU32(metricCol)
        drawlist:AddRectFilled(imgui.ImVec2(x, y), imgui.ImVec2(x + w, y + h), bg, 5.0)
        drawlist:AddRect(imgui.ImVec2(x, y), imgui.ImVec2(x + w, y + h), border, 5.0, nil, 1.0)

        drawlist:AddText(imgui.ImVec2(x + 13, y + 7), labelCol, label)
        drawlist:AddText(imgui.ImVec2(x + 9, y + 25), valueCol, value)
        if sub then
            drawlist:AddText(imgui.ImVec2(x + 9, y + h - 18), labelCol, sub)
        end
    end)
end

function statsGroupKey(ts, group)
    if group == "day" then
        return os.date("%Y-%m-%d", ts)
    elseif group == "week" then
        local t = os.date("*t", ts)
        local day = t.wday - 1
        local mondayOffset = (day == 0) and 6 or (day - 1)
        local monday = os.time({
            year = t.year, month = t.month, day = t.day,
            hour = 0, min = 0, sec = 0
        }) - mondayOffset * 86400
        return os.date("%Y-%m-%d", monday)
    end
    return tostring(ts)
end

function fmtGroupLabel(key, group)
    if group == "day" then
        local y, m, d = key:match("(%d+)%-(%d+)%-(%d+)")
        if y then return string.format("%02d.%02d.%04d", tonumber(d), tonumber(m), tonumber(y)) end
    elseif group == "week" then
        local y, m, d = key:match("(%d+)%-(%d+)%-(%d+)")
        if y then return u8"Неделя с " .. string.format("%02d.%02d.%04d", tonumber(d), tonumber(m), tonumber(y)) end
    end
    return key
end

function aggregateHistory(hist, group)
    if group == "all" then
        local out = {}
        for _, e in ipairs(hist) do
            out[#out + 1] = {
                key = tostring(e.time),
                time = e.time,
                speed = e.speed or 0,
                accuracy = e.accuracy or 0,
                errors = e.errors or 0,
                chars = e.chars or 0,
                races = 1,
            }
        end
        return out
    end

    local buckets = {}
    for _, e in ipairs(hist) do
        local key = statsGroupKey(e.time, group)
        local b = buckets[key]
        if not b then
            b = { key = key, time = e.time, speed = 0, accuracy = 0, errors = 0, chars = 0, races = 0 }
            buckets[key] = b
        end
        b.speed = b.speed + (e.speed or 0)
        b.accuracy = b.accuracy + (e.accuracy or 0)
        b.errors = b.errors + (e.errors or 0)
        b.chars = b.chars + (e.chars or 0)
        b.races = b.races + 1
        if e.time > b.time then b.time = e.time end
    end

    local out = {}
    for _, b in pairs(buckets) do
        b.speed = math.floor(b.speed / math.max(1, b.races) + 0.5)
        b.accuracy = b.accuracy / math.max(1, b.races)
        out[#out + 1] = b
    end
    table.sort(out, function(a, b) return a.time < b.time end)
    return out
end

function drawStatsCombo(id, label, ptr, values, width)
    local names = {}
    for i, v in ipairs(values) do names[i] = v.label end
    local items = ffi.new("const char*[?]", #names, names)

    if imgui.AlignTextToFramePadding then pcall(imgui.AlignTextToFramePadding) end
    imgui.Text(label)
    imgui.SameLine(0, 5)

    local pushed = 0
    if pcall(imgui.PushStyleColor, imgui.Col.FrameBg, THEME.frameBg) then pushed = pushed + 1 end
    if pcall(imgui.PushStyleColor, imgui.Col.FrameBgHovered, themeFrameHover()) then pushed = pushed + 1 end
    if pcall(imgui.PushStyleColor, imgui.Col.FrameBgActive, themeFrameActive()) then pushed = pushed + 1 end
    if pcall(imgui.PushStyleColor, imgui.Col.Text, THEME.text) then pushed = pushed + 1 end
    if imgui.Col.PopupBg and pcall(imgui.PushStyleColor, imgui.Col.PopupBg, themeMix(THEME.frameBg, THEME.childBg, 0.35)) then pushed = pushed + 1 end
    if pcall(imgui.PushStyleColor, imgui.Col.Header, THEME.header) then pushed = pushed + 1 end
    if pcall(imgui.PushStyleColor, imgui.Col.HeaderHovered, THEME.headerHov) then pushed = pushed + 1 end
    if pcall(imgui.PushStyleColor, imgui.Col.HeaderActive, THEME.headerAct) then pushed = pushed + 1 end
    if pcall(imgui.PushStyleColor, imgui.Col.Border, THEME.border) then pushed = pushed + 1 end

    local pv = 0
    if imgui.StyleVar and imgui.StyleVar.FrameBorderSize then
        if pcall(imgui.PushStyleVar, imgui.StyleVar.FrameBorderSize, 1.0) then pv = 1 end
    end

    if imgui.SetNextItemWidth then pcall(imgui.SetNextItemWidth, width or 145) end

    local okCombo, changed = pcall(imgui.Combo, "##" .. id, ptr, items, #names)

    local okMin, itemMin = pcall(imgui.GetItemRectMin)
    local okMax, itemMax = pcall(imgui.GetItemRectMax)
    if okMin and okMax and itemMin and itemMax then
        local dl = imgui.GetWindowDrawList()
        if dl then
            dl:AddRect(
                imgui.ImVec2(itemMin.x, itemMin.y),
                imgui.ImVec2(itemMax.x, itemMax.y),
                imgui.ColorConvertFloat4ToU32(THEME.border),
                3.0, 0, 1.1
            )
        end
    end

    if pv > 0 then pcall(imgui.PopStyleVar, pv) end
    if pushed > 0 then pcall(imgui.PopStyleColor, pushed) end
    return okCombo and changed or false
end

local STATS_GROUP_ITEMS = {
    { id = "all",  label = u8"всё" },
    { id = "day",  label = u8"по дням" },
    { id = "week", label = u8"по неделям" },
}

local STATS_METRIC_ITEMS = {
    { id = "speed",  label = u8"скорость" },
    { id = "errors", label = u8"ошибки" },
    { id = "run",    label = u8"пробег" },
}

local STATS_PERIOD_ITEMS = {
    { id = "today", label = u8"сегодня" },
    { id = "30d",   label = u8"последний месяц" },
    { id = "90d",   label = u8"последние 3 месяца" },
    { id = "365d",  label = u8"последний год" },
    { id = "all",   label = u8"за все время" },
}

function filterHistoryByPeriod(hist, period)
    if period == "all" then return hist end

    local now = os.time()
    local nowDate = os.date("*t", now)
    local cutoff

    if period == "today" then

        cutoff = os.time({
            year = nowDate.year, month = nowDate.month, day = nowDate.day,
            hour = 0, min = 0, sec = 0
        })
    elseif period == "30d" then

        local month = nowDate.month - 1
        local year = nowDate.year
        if month == 0 then month = 12; year = year - 1 end
        cutoff = os.time({
            year = year, month = month, day = nowDate.day,
            hour = nowDate.hour, min = nowDate.min, sec = nowDate.sec
        })
    elseif period == "90d" then

        local month = nowDate.month - 3
        local year = nowDate.year
        while month <= 0 do month = month + 12; year = year - 1 end
        cutoff = os.time({
            year = year, month = month, day = nowDate.day,
            hour = nowDate.hour, min = nowDate.min, sec = nowDate.sec
        })
    elseif period == "365d" then
        cutoff = os.time({
            year = nowDate.year - 1, month = nowDate.month, day = nowDate.day,
            hour = nowDate.hour, min = nowDate.min, sec = nowDate.sec
        })
    else
        return hist
    end

    local out = {}
    for _, e in ipairs(hist) do
        if (e.time or 0) >= cutoff then out[#out + 1] = e end
    end
    return out
end

function drawStatsPeriodChoice()
    local periodIndex =
        ui.statsPeriod == "today" and 0 or
        (ui.statsPeriod == "30d" and 1 or
        (ui.statsPeriod == "90d" and 2 or
        (ui.statsPeriod == "365d" and 3 or 4)))
    local periodPtr = new.int(periodIndex)
    drawStatsCombo("stats_period", u8"Период:", periodPtr, STATS_PERIOD_ITEMS, 155)
    local selected = math.max(0, math.min(4, tonumber(periodPtr[0]) or 0))
    ui.statsPeriod = STATS_PERIOD_ITEMS[selected + 1].id
end

function drawStatsGrouping()
    local groupIndex = ui.statsGroup == "day" and 1 or (ui.statsGroup == "week" and 2 or 0)
    local groupPtr = new.int(groupIndex)
    drawStatsCombo("stats_group", u8"Группировать:", groupPtr, STATS_GROUP_ITEMS, 135)
    local selected = math.max(0, math.min(2, tonumber(groupPtr[0]) or 0))
    ui.statsGroup = STATS_GROUP_ITEMS[selected + 1].id
end

function drawStatsMetricChoice()
    local metricIndex = ui.statsMetric == "errors" and 1 or (ui.statsMetric == "run" and 2 or 0)
    local metricPtr = new.int(metricIndex)
    drawStatsCombo("stats_metric", u8"Показатель:", metricPtr, STATS_METRIC_ITEMS, 135)
    local selected = math.max(0, math.min(2, tonumber(metricPtr[0]) or 0))
    ui.statsMetric = STATS_METRIC_ITEMS[selected + 1].id
end

function drawStatsToolbar()
    drawStatsPeriodChoice()
    imgui.SameLine(0, 10)
    drawStatsMetricChoice()
    imgui.SameLine(0, 10)
    drawStatsGrouping()
end

function statsDebugOffset(key)
    local d = cfg.stats_debug or {}
    return tonumber(d[key .. "_x"]) or 0, tonumber(d[key .. "_y"]) or 0
end

function statsDebugPos(basePos, key, fallbackX, fallbackY)
    local dx, dy = statsDebugOffset(key)
    return imgui.ImVec2(basePos.x + (fallbackX or 0) + dx, basePos.y + (fallbackY or 0) + dy)
end

function statsDebugSetCursor(basePos, key, fallbackX, fallbackY)
    local pos = statsDebugPos(basePos, key, fallbackX, fallbackY)
    pcall(imgui.SetCursorScreenPos, pos)
    return pos
end

function statsDebugPtr(key)
    ui.statsDebug.ptrs = ui.statsDebug.ptrs or {}
    local ptrs = ui.statsDebug.ptrs
    if not ptrs[key] then
        ptrs[key] = {
            x = new.int(math.floor(statsDebugOffset(key))),
            y = new.int(math.floor(select(2, statsDebugOffset(key)))),
        }
    end
    return ptrs[key]
end

function syncStatsDebugPtrs()
    ui.statsDebug.ptrs = ui.statsDebug.ptrs or {}
    for _, key in ipairs(STATS_DEBUG_DEFAULT_KEYS) do
        local pxy = statsDebugPtr(key)
        pxy.x[0] = math.floor(statsDebugOffset(key))
        pxy.y[0] = math.floor(select(2, statsDebugOffset(key)))
    end
    ui.statsDebug.initialized = true
end

function statsDebugSaveKey(key, ptrs)
    cfg.stats_debug[key .. "_x"] = math.floor(tonumber(ptrs.x[0]) or 0)
    cfg.stats_debug[key .. "_y"] = math.floor(tonumber(ptrs.y[0]) or 0)
end

function drawStatsDebugControl(key, label)
    local ptrs = statsDebugPtr(key)
    local changed = false
    imgui.Text(label)
    imgui.SameLine(0, 8)
    if drawNumericInt("X##statsdbg_" .. key, ptrs.x, -400, 400) then
        statsDebugSaveKey(key, ptrs)
        saveCfg()
        changed = true
    end
    imgui.SameLine(0, 10)
    if drawNumericInt("Y##statsdbg_" .. key, ptrs.y, -300, 300) then
        statsDebugSaveKey(key, ptrs)
        saveCfg()
        changed = true
    end
    return changed
end

function drawModeDetail(modeId, historyOverride, titleOverride)
    local mode = getModeById(modeId) or { name = titleOverride or u8"Статистика" }
    local detailBase = imgui.GetCursorScreenPos()
    if drawBackButton(u8"< Назад", "##stats_detail_back") then
        if historyOverride then
            ui.statsDictionary = -1
        else
            ui.statsMode = nil
        end
    end

    imgui.SameLine(0, 30)
    imgui.TextColored(THEME.text, titleOverride or mode.name)

    local hist = historyOverride or historyParse(modeId)
    if #hist == 0 then
        imgui.Text(u8"Нет сыгранных заездов в этом режиме.")
        return
    end

    local displayHist = filterHistoryByPeriod(hist, ui.statsPeriod)
    if #displayHist == 0 then
        imgui.Spacing()
        drawStatsToolbar()
        imgui.TextColored(themeTextSubtle(), u8"За выбранный период нет данных.")
        return
    end

    local chrono = aggregateHistory(displayHist, ui.statsGroup)

    local bestSpeed, bestEntry, sumSpeed, sumAcc, totalRun = 0, displayHist[1], 0, 0, 0
    for _, e in ipairs(displayHist) do
        sumSpeed = sumSpeed + (e.speed or 0)
        sumAcc = sumAcc + (e.accuracy or 0)
        totalRun = totalRun + 1
        if (e.speed or 0) > bestSpeed then bestSpeed = e.speed; bestEntry = e end
    end
    local avgSpeed = math.floor(sumSpeed / math.max(1, #displayHist) + 0.5)
    local avgAcc = sumAcc / math.max(1, #displayHist)
    local avgErrRate = math.max(0, 100 - avgAcc)

    imgui.Spacing()
    local ok_p1, p0 = pcall(imgui.GetCursorScreenPos)
    if ok_p1 then
        local cardW, cardH, gap = 162, 80, 10
        local cardKeys = {"detail_card_1", "detail_card_2", "detail_card_3", "detail_card_4"}
        local cardXs = {0, cardW + gap, (cardW + gap) * 2, (cardW + gap) * 3}
        drawStatCard(p0.x + cardXs[1], p0.y, cardW, cardH,
            u8"ЛУЧШИЙ РЕЗУЛЬТАТ", tostring(bestSpeed) .. u8" зн/мин", fmtDate(bestEntry and bestEntry.time), "yellow")
        drawStatCard(p0.x + cardXs[2], p0.y, cardW, cardH,
            u8"СРЕДНЯЯ СКОРОСТЬ", tostring(avgSpeed) .. u8" зн/мин", nil, "blue")
        drawStatCard(p0.x + cardXs[3], p0.y, cardW, cardH,
            u8"ОШИБКИ", string.format("%.2f%%", avgErrRate), nil, "blue")
        drawStatCard(p0.x + cardXs[4], p0.y, cardW, cardH,
            u8"ПРОБЕГ", tostring(totalRun) .. u8" текстов", nil, "blue")
        pcall(imgui.Dummy, imgui.ImVec2((cardW + gap) * 4 - gap, cardH))
    end

    drawStatsToolbar()

    imgui.Spacing()
    local ok_dl, drawlist = pcall(imgui.GetWindowDrawList)
    local ok_p, p0c = pcall(imgui.GetCursorScreenPos)
    if ok_dl and ok_p then
        local w, h = 678, 205
        local padL, padB = 50, 24
        local plotX0, plotY0 = p0c.x + padL, p0c.y + 8
        local plotX1, plotY1 = p0c.x + w - 12, p0c.y + h - padB

        local metricTitle = u8"Скорость"
        local metricUnit = u8"зн/мин"
        local metricColor = COL_ACTIVE
        if ui.statsMetric == "errors" then
            metricTitle = u8"Ошибки"
            metricUnit = u8"%"
            metricColor = COL_ERROR
        elseif ui.statsMetric == "run" then
            metricTitle = u8"Пробег"
            metricUnit = u8"текстов"
            metricColor = COL_CORRECT
        end

        local function metricValue(e)
            if ui.statsMetric == "errors" then return math.max(0, 100 - (e.accuracy or 100))
            elseif ui.statsMetric == "run" then return e.races or 0 end
            return e.speed or 0
        end

        local maxValue = 1
        local cumulativeRun = 0
        for _, e in ipairs(chrono) do
            if ui.statsMetric == "run" then
                cumulativeRun = cumulativeRun + (e.races or 0)
                e.__run = cumulativeRun
            end
            maxValue = math.max(maxValue, ui.statsMetric == "run" and e.__run or metricValue(e))
        end

        local step
        if ui.statsMetric == "errors" then
            step = 1
        elseif ui.statsMetric == "run" then
            step = 1
        else
            step = 50
        end
        maxValue = math.max(step, math.ceil(maxValue / step) * step)

        pcall(function()
            local bg = imgui.ColorConvertFloat4ToU32(THEME.childBg)
            local border = imgui.ColorConvertFloat4ToU32(THEME.border)
            drawlist:AddRectFilled(imgui.ImVec2(p0c.x, p0c.y), imgui.ImVec2(p0c.x + w, p0c.y + h), bg, 4.0)
            drawlist:AddRect(imgui.ImVec2(p0c.x, p0c.y), imgui.ImVec2(p0c.x + w, p0c.y + h), border, 4.0, 0, 1.0)

            local gridCol = imgui.ColorConvertFloat4ToU32(THEME.separator)
            local dimCol = imgui.ColorConvertFloat4ToU32(themeTextSubtle())
            for level = 0, 4 do
                local val = maxValue * level / 4
                local yy = plotY1 - (val / maxValue) * (plotY1 - plotY0)
                drawlist:AddLine(imgui.ImVec2(plotX0, yy), imgui.ImVec2(plotX1, yy), gridCol, 1.0)
                local axisLabel
                if ui.statsMetric == "errors" then
                    axisLabel = string.format("%.1f", val)
                else
                    axisLabel = tostring(math.floor(val))
                end
                drawlist:AddText(imgui.ImVec2(p0c.x + 4, yy - 6), dimCol, axisLabel)
            end
            drawlist:AddText(imgui.ImVec2(plotX0 + 8, p0c.y + 7),
                imgui.ColorConvertFloat4ToU32(metricColor), metricTitle)
        end)

        local n = #chrono
        local stepX = n > 1 and (plotX1 - plotX0 - 10) / (n - 1) or 0
        local points = {}
        for i, e in ipairs(chrono) do
            local val = ui.statsMetric == "run" and e.__run or metricValue(e)
            local xx = plotX0 + 5 + stepX * (i - 1)
            local yy = plotY1 - (val / maxValue) * (plotY1 - plotY0)
            points[i] = { x = xx, y = yy, e = e, value = val }
        end

        pcall(function()
            local lineCol = imgui.ColorConvertFloat4ToU32(metricColor)
            local fillCol = imgui.ColorConvertFloat4ToU32(colorVec(metricColor.x, metricColor.y, metricColor.z, 0.16))
            if n > 1 then
                for i = 1, n - 1 do
                    drawlist:AddQuadFilled(
                        imgui.ImVec2(points[i].x, points[i].y), imgui.ImVec2(points[i + 1].x, points[i + 1].y),
                        imgui.ImVec2(points[i + 1].x, plotY1), imgui.ImVec2(points[i].x, plotY1), fillCol)
                    drawlist:AddLine(
                        imgui.ImVec2(points[i].x, points[i].y),
                        imgui.ImVec2(points[i + 1].x, points[i + 1].y),
                        lineCol, 2.4)
                end
            end
            for i = 1, n do
                drawlist:AddCircleFilled(imgui.ImVec2(points[i].x, points[i].y), 3.0, lineCol, 8)
            end
            local dimCol = imgui.ColorConvertFloat4ToU32(themeTextSubtle())
            local mid = math.ceil(n / 2)
            if n > 0 then
                local firstLabel = ui.statsGroup == "all" and fmtDate(points[1].e.time) or fmtGroupLabel(points[1].e.key, ui.statsGroup)
                drawlist:AddText(imgui.ImVec2(points[1].x - 10, plotY1 + 5), dimCol, firstLabel)
            end
            if n > 2 then
                local midLabel = ui.statsGroup == "all" and fmtDate(points[mid].e.time) or fmtGroupLabel(points[mid].e.key, ui.statsGroup)
                drawlist:AddText(imgui.ImVec2(points[mid].x - 20, plotY1 + 5), dimCol, midLabel)
            end
            if n > 1 then
                local lastLabel = ui.statsGroup == "all" and fmtDate(points[n].e.time) or fmtGroupLabel(points[n].e.key, ui.statsGroup)
                local lastTextW = 0
                local okLastW, lastSize = pcall(imgui.CalcTextSize, lastLabel)
                if okLastW and lastSize then lastTextW = lastSize.x end
                local lastX = math.min(
                    p0c.x + w - lastTextW - 8,
                    points[n].x - lastTextW * 0.5 - 18
                )
                lastX = math.max(p0c.x + 5, lastX)
                drawlist:AddText(imgui.ImVec2(lastX, plotY1 + 5), dimCol, lastLabel)
            end
        end)

        local ok_hr, hoveredChart = pcall(imgui.IsMouseHoveringRect, imgui.ImVec2(p0c.x, p0c.y), imgui.ImVec2(p0c.x + w, p0c.y + h))
        if ok_hr and hoveredChart and n > 0 then
            local ok_mp, mpos = pcall(imgui.GetMousePos)
            if ok_mp and mpos then
                local nearest, nearestDist = 1, math.huge
                for i, pt in ipairs(points) do
                    local d = math.abs(pt.x - mpos.x)
                    if d < nearestDist then nearestDist = d; nearest = i end
                end
                local pt = points[nearest]
                pcall(function()
                    local lineCol = imgui.ColorConvertFloat4ToU32(metricColor)
                    drawlist:AddCircleFilled(imgui.ImVec2(pt.x, pt.y), 4.5, imgui.ColorConvertFloat4ToU32(THEME.text), 12)
                    drawlist:AddCircle(imgui.ImVec2(pt.x, pt.y), 4.5, lineCol, 12, 2.0)
                end)

                local tipColors = 0
                if imgui.Col.PopupBg and pcall(imgui.PushStyleColor, imgui.Col.PopupBg, themeMix(THEME.frameBg, THEME.childBg, 0.35)) then
                    tipColors = tipColors + 1
                end
                if pcall(imgui.PushStyleColor, imgui.Col.Text, THEME.text) then
                    tipColors = tipColors + 1
                end
                if imgui.Col.Border and pcall(imgui.PushStyleColor, imgui.Col.Border, THEME.border) then
                    tipColors = tipColors + 1
                end

                local tooltipOk = imgui.BeginTooltip and pcall(imgui.BeginTooltip)
                if tooltipOk then
                    imgui.Text(ui.statsGroup == "all" and fmtDate(pt.e.time) or fmtGroupLabel(pt.e.key, ui.statsGroup))
                    if ui.statsMetric == "errors" then
                        imgui.Text(u8"Ошибки: " .. string.format("%.2f%%", pt.value))
                    elseif ui.statsMetric == "run" then
                        imgui.Text(u8"Пробег: " .. tostring(pt.value) .. u8" текстов")
                    else
                        imgui.Text(u8"Скорость: " .. tostring(pt.value) .. u8" зн/мин")
                    end
                    imgui.Text(u8"Точность: " .. string.format("%.0f", pt.e.accuracy or 0) .. "%")
                    pcall(imgui.EndTooltip)
                end
                if tipColors > 0 then pcall(imgui.PopStyleColor, tipColors) end
            end
        end

        pcall(imgui.Dummy, imgui.ImVec2(w, h))
    end

    imgui.Spacing()
    local tableAnchor = imgui.GetCursorScreenPos()
    pcall(imgui.SetCursorScreenPos, tableAnchor)
    local tableHist = aggregateHistory(displayHist, ui.statsGroup)
    table.sort(tableHist, function(a, b)
        local va = (ui.sortCol == "error_rate") and (100 - (a.accuracy or 100)) or a[ui.sortCol]
        local vb = (ui.sortCol == "error_rate") and (100 - (b.accuracy or 100)) or b[ui.sortCol]
        if ui.sortDesc then return va > vb else return va < vb end
    end)
    local function header(label, key)

        imgui.TextColored(THEME.text, label)
        local ok_c, clicked = pcall(imgui.IsItemClicked)
        if ok_c and clicked then
            if ui.sortCol == key then ui.sortDesc = not ui.sortDesc else ui.sortCol = key; ui.sortDesc = true end
        end
        imgui.SameLine(0, 24)
    end

    local tableX = {}
    local okBase, baseX = pcall(imgui.GetCursorPosX)
    baseX = (okBase and baseX) or 0
    tableX[1] = baseX
    tableX[2] = baseX + 85
    tableX[3] = baseX + 165
    tableX[4] = baseX + 235
    tableX[5] = baseX + 310

    local function nextColumn(x)
        pcall(imgui.SameLine, 0, 0)
        pcall(imgui.SetCursorPosX, x)
    end

    local function columnHeader(label, key, x, last)
        if not last then

            if x ~= tableX[1] then nextColumn(x) end
        else
            nextColumn(x)
        end

        imgui.TextColored(THEME.text, label)
    end

    columnHeader(u8"Дата", "time", tableX[1], false)
    columnHeader(u8"Скорость", "speed", tableX[2], true)
    columnHeader(u8"Точность", "accuracy", tableX[3], true)
    columnHeader(u8"Ошибки", "error_rate", tableX[4], true)
    columnHeader(u8"Пробег", "races", tableX[5], true)
    imgui.Separator()

    for _, e in ipairs(tableHist) do
        local dateLabel = (ui.statsGroup == "all") and fmtDate(e.time) or fmtGroupLabel(e.key, ui.statsGroup)

        pcall(imgui.SetCursorPosX, tableX[1])
        imgui.Text(dateLabel)

        nextColumn(tableX[2])
        imgui.Text(tostring(e.speed) .. u8" зн/мин")

        nextColumn(tableX[3])
        imgui.Text(string.format("%.0f%%", e.accuracy))

        nextColumn(tableX[4])
        imgui.Text(string.format("%.2f%%", math.max(0, 100 - (e.accuracy or 100))))

        nextColumn(tableX[5])
        imgui.Text(tostring(e.races or 0))
    end
end

function drawDictionaryStatsList()
    if drawBackButton(u8"< Назад", "##dict_stats_back") then
        ui.statsDictionary = nil
        return
    end
    imgui.SameLine(0, 12)
    imgui.TextColored(THEME.text, u8"Мои словари")
    imgui.Spacing()

    local items = {}
    local count = cfg.custom_dicts.count or 0
    for idx = 1, count do
        local d = getCustomDictionary(idx)
        local sec = customDictionaryStatsSection(idx)
        if d and sec then
            items[#items + 1] = {
                index = idx,
                name = (d.name ~= "" and d.name or (u8"Словарь #" .. tostring(idx))),
                played = sec.played or 0,
                best_speed = sec.best_speed or 0,
                best_accuracy = sec.best_accuracy or 0,
                chars = clavaTextLength(d.content or ""),
            }
        end
    end

    if #items == 0 then
        imgui.BeginChild(u8"##my_dictionary_stats_empty", imgui.ImVec2(0, 72), true)
        imgui.Dummy(imgui.ImVec2(0, 8))
        imgui.TextColored(themeTextSubtle(), u8"Сыграйте заезд в словаре, чтобы накопить статистику.")
        imgui.EndChild()
        return
    end

    local rowH, gap = 48, 7
    local listH = math.min(300, math.max(62, #items * (rowH + gap) - gap + 10))
    local okList = pcall(imgui.BeginChild, u8"##my_dictionary_stats_list_v2", imgui.ImVec2(0, listH), true)
    if not okList then return end

    for _, item in ipairs(items) do
        local p0 = imgui.GetCursorScreenPos()
        local avail = imgui.GetContentRegionAvail()
        local w = math.max(220, avail.x)
        local x0, y0 = p0.x, p0.y
        local x1, y1 = x0 + w, y0 + rowH
        local hovered = false
        pcall(function()
            local mp = imgui.GetMousePos()
            hovered = mp.x >= x0 and mp.x <= x1 and mp.y >= y0 and mp.y <= y1
        end)

        local bg = hovered
            and themeMix(THEME.accent, THEME.childBg, 0.84)
            or themeMix(THEME.frameBg, THEME.childBg, 0.28)
        local border = hovered and THEME.accent or themeMix(THEME.border, THEME.text, 0.25)
        local strip = hovered and THEME.accent or themeMix(THEME.accent, THEME.childBg, 0.18)

        pcall(function()
            local dl = imgui.GetWindowDrawList()
            dl:AddRectFilled(imgui.ImVec2(x0, y0), imgui.ImVec2(x1, y1),
                imgui.ColorConvertFloat4ToU32(bg), 6.0)
            dl:AddRect(imgui.ImVec2(x0, y0), imgui.ImVec2(x1, y1),
                imgui.ColorConvertFloat4ToU32(border), 6.0, nil, hovered and 1.6 or 1.0)
            dl:AddRectFilled(imgui.ImVec2(x0, y0), imgui.ImVec2(x0 + 5, y1),
                imgui.ColorConvertFloat4ToU32(strip), 6.0)
        end)

        imgui.SetCursorScreenPos(imgui.ImVec2(x0 + 15, y0 + 7))
        imgui.TextColored(hovered and THEME.text or THEME.text, item.name)
        imgui.SetCursorScreenPos(imgui.ImVec2(x0 + 15, y0 + 26))
        imgui.TextColored(themeTextMuted(),
            u8"Заездов: " .. tostring(item.played) ..
            u8"    -    Лучшее: " .. tostring(item.best_speed) .. u8" зн/мин" ..
            u8"    -    " .. string.format("%.0f%%", item.best_accuracy or 0) ..
            u8"    -    " .. tostring(item.chars or 0) .. u8" зн.")

        imgui.SetCursorScreenPos(imgui.ImVec2(x0, y0))
        local pushed = 0
        if pcall(imgui.PushStyleColor, imgui.Col.Button, colorVec(0, 0, 0, 0)) then pushed = pushed + 1 end
        if pcall(imgui.PushStyleColor, imgui.Col.ButtonHovered, colorVec(0, 0, 0, 0)) then pushed = pushed + 1 end
        if pcall(imgui.PushStyleColor, imgui.Col.ButtonActive, colorVec(0, 0, 0, 0)) then pushed = pushed + 1 end
        if pcall(imgui.PushStyleColor, imgui.Col.Text, colorVec(0, 0, 0, 0)) then pushed = pushed + 1 end
        local clicked = imgui.Button(u8"##mydictstats" .. tostring(item.index), imgui.ImVec2(w, rowH))
        if pushed > 0 then pcall(imgui.PopStyleColor, pushed) end
        if clicked then ui.statsDictionary = item.index end

        imgui.SetCursorScreenPos(imgui.ImVec2(x0, y1 + gap))
    end
    pcall(imgui.EndChild)
end

function drawDictionaryStatsDetail(index)
    local d = getCustomDictionary(index)
    local sec = customDictionaryStatsSection(index)
    if not d or not sec or (sec.played or 0) == 0 then
        ui.statsDictionary = -1
        return
    end
    local title = d.name ~= "" and d.name or (u8"Словарь #" .. tostring(index))
    drawModeDetail(index, customDictionaryHistoryParse(index), title)
end

function drawMyDictionariesStatsLink()
    local pushed = 0
    if pcall(imgui.PushStyleColor, imgui.Col.Text, THEME.accent) then pushed = pushed + 1 end
    if pcall(imgui.PushStyleColor, imgui.Col.Button, colorVec(0, 0, 0, 0)) then pushed = pushed + 1 end
    if pcall(imgui.PushStyleColor, imgui.Col.ButtonHovered, themeMix(THEME.accent, THEME.childBg, 0.80)) then pushed = pushed + 1 end
    if pcall(imgui.PushStyleColor, imgui.Col.ButtonActive, themeMix(THEME.accent, THEME.childBg, 0.65)) then pushed = pushed + 1 end
    local clicked = imgui.SmallButton(u8"Мои словари##stats_my_dictionaries")
    if pushed > 0 then pcall(imgui.PopStyleColor, pushed) end
    if clicked then ui.statsDictionary = -1 end
end

function drawModeStats()
    if not ui.statsDictionary then
        local customCount = tonumber(cfg.custom_dicts and cfg.custom_dicts.count) or 0
        if customCount > 0 then
            drawMyDictionariesStatsLink()
            imgui.SameLine(0, 12)
            imgui.TextColored(themeTextSubtle(), u8"Статистика ваших словарей")
            imgui.Spacing()
        end
    end

    if ui.statsDictionary then
        if ui.statsDictionary == -1 then
            drawDictionaryStatsList()
        else
            drawDictionaryStatsDetail(ui.statsDictionary)
        end
        return
    end

    if ui.statsMode then
        drawModeDetail(ui.statsMode)
        return
    end

    local totalRaces, dataset = 0, {}
    for i, m in ipairs(MODES) do
        local sec = cfg["mode_" .. m.id] or {}
        local races = sec.races or 0
        totalRaces = totalRaces + races
        dataset[i] = {
            id = m.id, name = m.name, races = races,
            best_speed = sec.best_speed or 0, best_accuracy = sec.best_accuracy or 0,
            color = MODE_COLORS[((i - 1) % #MODE_COLORS) + 1],
        }
    end

    if totalRaces == 0 then
        imgui.TextColored(themeTextSubtle(), u8"Сыграйте хотя бы один заезд, чтобы увидеть статистику.")
        imgui.Spacing()
        return
    end

    local ok_dl, drawlist = pcall(imgui.GetWindowDrawList)
    local ok_p, p0 = pcall(imgui.GetCursorScreenPos)
    if not (ok_dl and ok_p) then return end
    local groupX, groupY = statsDebugOffset("main_group")
    local groupScale = math.max(0.50, math.min(2.00, tonumber(cfg.stats_debug.main_group_scale) or 1.0))
    local groupPos = imgui.ImVec2(p0.x + groupX, p0.y + groupY)
    local baseSize = 140
    local size = math.max(60, math.floor(baseSize * groupScale + 0.5))
    local ringX, ringY = statsDebugOffset("main_ring")
    local ringPos = imgui.ImVec2(groupPos.x + ringX * groupScale, groupPos.y + ringY * groupScale)
    local cx, cy = ringPos.x + size / 2, ringPos.y + size / 2
    local rOuter, rInner = size / 2 - 2, size / 2 - math.max(18, math.floor(26 * groupScale + 0.5))

    local ok_mouse, mpos = pcall(imgui.GetMousePos)
    local hoveredIdx = nil
    local startAngle = -math.pi / 2
    local atan2 = math.atan2 or function(y, x) return math.atan(y / x) end

    local angle = startAngle
    for i, d in ipairs(dataset) do
        local sweep = (d.races / totalRaces) * math.pi * 2
        if sweep > 0.0005 then
            local a0, a1 = angle, angle + sweep
            local segs = math.max(10, math.floor(sweep / 0.08))
            pcall(function()
                local center = imgui.ImVec2(cx, cy)
                drawlist:PathClear()
                drawlist:PathLineTo(center)
                drawlist:PathArcTo(center, rOuter, a0, a1, segs)
                drawlist:PathFillConvex(imgui.ColorConvertFloat4ToU32(d.color))
            end)
            if ok_mouse and mpos then
                local dx, dy = mpos.x - cx, mpos.y - cy
                local dist = math.sqrt(dx * dx + dy * dy)
                if dist >= rInner - 4 and dist <= rOuter + 4 then
                    local ok_ang, ang = pcall(atan2, dy, dx)
                    if ok_ang then
                        local function norm(a)
                            while a < startAngle do a = a + math.pi * 2 end
                            while a >= startAngle + math.pi * 2 do a = a - math.pi * 2 end
                            return a
                        end
                        local na, na0, na1 = norm(ang), norm(a0), norm(a1)
                        if na1 <= na0 then na1 = na1 + math.pi * 2 end
                        if na >= na0 and na <= na1 then hoveredIdx = i end
                    end
                end
            end
        end
        angle = angle + sweep
    end

    pcall(imgui.SetCursorScreenPos, imgui.ImVec2(p0.x, p0.y))
    pcall(imgui.Dummy, imgui.ImVec2(math.max(size + 20 * groupScale, 160), math.max(size, 140)))

    if hoveredIdx then
        local d = dataset[hoveredIdx]
        local tipColors = 0
        if imgui.Col.PopupBg and pcall(imgui.PushStyleColor, imgui.Col.PopupBg, themeMix(THEME.frameBg, THEME.childBg, 0.35)) then
            tipColors = tipColors + 1
        end
        if pcall(imgui.PushStyleColor, imgui.Col.Text, THEME.text) then
            tipColors = tipColors + 1
        end
        if imgui.Col.Border and pcall(imgui.PushStyleColor, imgui.Col.Border, THEME.border) then
            tipColors = tipColors + 1
        end
        local tooltipOk = imgui.BeginTooltip and pcall(imgui.BeginTooltip)
        if tooltipOk then
            imgui.Text(d.name)
            imgui.Text(u8"Заездов: " .. d.races)
            imgui.Text(u8"Лучшая скорость: " .. d.best_speed .. u8" зн/мин")
            imgui.Text(u8"Лучшая точность: " .. d.best_accuracy .. "%")
            pcall(imgui.EndTooltip)
        end
        if tipColors > 0 then pcall(imgui.PopStyleColor, tipColors) end
        local ok_click, clicked = pcall(imgui.IsMouseClicked, 0)
        if ok_click and clicked then ui.statsMode = d.id end
    end

    local legendGroupX, legendGroupY = statsDebugOffset("main_legend")
    local legendBase = imgui.ImVec2(groupPos.x + (size + 20 * groupScale) + legendGroupX * groupScale, groupPos.y + legendGroupY * groupScale)
    for i, d in ipairs(dataset) do
        local baseLegend = imgui.ImVec2(legendBase.x, legendBase.y + (i - 1) * 22 * groupScale)
        local lx, ly = statsDebugOffset("main_legend_" .. i)
        local lp = imgui.ImVec2(baseLegend.x + lx * groupScale, baseLegend.y + ly * groupScale)
        pcall(imgui.SetCursorScreenPos, lp)
        pcall(function()
            local dl2 = imgui.GetWindowDrawList()
            dl2:AddRectFilled(imgui.ImVec2(lp.x, lp.y + 3), imgui.ImVec2(lp.x + 10, lp.y + 13),
                imgui.ColorConvertFloat4ToU32(d.color), 2.0)
        end)
        imgui.SetCursorScreenPos(imgui.ImVec2(lp.x + 14 * groupScale, lp.y))
        local legendFontScaled = pcall(imgui.SetWindowFontScale, groupScale)
        local clicked = imgui.Selectable(d.name .. u8" (" .. d.races .. u8")##stats_legend_" .. i, false, 0, imgui.ImVec2(250 * groupScale, 20 * groupScale))
        if legendFontScaled then pcall(imgui.SetWindowFontScale, 1.0) end
        if clicked then ui.statsMode = d.id end
        local ok_lh, lhov = pcall(imgui.IsItemHovered)
        if ok_lh and lhov and imgui.BeginTooltip then
            local tipColors = 0
            if imgui.Col.PopupBg and pcall(imgui.PushStyleColor, imgui.Col.PopupBg, themeMix(THEME.frameBg, THEME.childBg, 0.35)) then
                tipColors = tipColors + 1
            end
            if pcall(imgui.PushStyleColor, imgui.Col.Text, THEME.text) then
                tipColors = tipColors + 1
            end
            if imgui.Col.Border and pcall(imgui.PushStyleColor, imgui.Col.Border, THEME.border) then
                tipColors = tipColors + 1
            end
            local tooltipOk = pcall(imgui.BeginTooltip)
            if tooltipOk then
                imgui.Text(d.name)
                imgui.Text(u8"Заездов: " .. d.races)
                imgui.Text(u8"Лучшая скорость: " .. d.best_speed .. u8" зн/мин")
                imgui.Text(u8"Лучшая точность: " .. d.best_accuracy .. "%")
                imgui.TextColored(themeTextSubtle(), u8"(клик - подробная статистика)")
                pcall(imgui.EndTooltip)
            end
            if tipColors > 0 then pcall(imgui.PopStyleColor, tipColors) end
        end
    end

end

function drawTrafficLight(activeIdx)

    local ok_dl, drawlist = pcall(imgui.GetWindowDrawList)
    local ok_p, p0 = pcall(imgui.GetCursorScreenPos)
    if not (ok_dl and ok_p and drawlist) then return end
    local w, h = 20, 46
    local yOffset = 8
    pcall(function()
        local body = imgui.ColorConvertFloat4ToU32(colorVec(0.25, 0.23, 0.20))
        drawlist:AddRectFilled(imgui.ImVec2(p0.x, p0.y + yOffset), imgui.ImVec2(p0.x + w, p0.y + yOffset + h), body, 4.0)
        local bright = { colorVec(0.90, 0.20, 0.20), colorVec(0.95, 0.78, 0.15), colorVec(0.25, 0.75, 0.30) }
        local dim = { colorVec(0.45, 0.20, 0.20), colorVec(0.45, 0.38, 0.20), colorVec(0.20, 0.35, 0.22) }
        for i = 1, 3 do
            local c = (activeIdx == i) and bright[i] or dim[i]
            drawlist:AddCircleFilled(imgui.ImVec2(p0.x + w / 2, p0.y + yOffset + 8 + (i - 1) * 14), 5.5,
                imgui.ColorConvertFloat4ToU32(c), 16)
        end
    end)
    pcall(imgui.Dummy, imgui.ImVec2(w, h))
end

function replayFinishedRace()
    if not race.finished or not race.completed or race.failed then return false end

    local text = race.replayText
    if text == "" then
        text = race.currentText or ""
    end
    if text == "" then return false end

    local modeId = race.replayModeId or race.modeId or "normal"
    local customIndex = tonumber(race.replayCustomDictionaryIndex) or false
    local dictionaryName = race.replayDictionaryName or ""
    local sourceMeta = race.replaySourceMeta or {
        author = race.sourceAuthor or "",
        book = race.sourceBook or "",
        genre = race.sourceGenre or "",
    }

    local ok = beginRace(text, modeId, sourceMeta, customIndex)
    if ok and customIndex then
        race.dictionaryName = dictionaryName
    end
    return ok == true
end

function endFinishedRace()
    if not race.finished then return end
    race.started = false
    race.countingDown = false
    race.countdownEnd = nil
    race.countdownWasActive = false
    race.needFocus = false
    race.abortReason = nil
    race.finished = false
    race.completed = false
    race.failed = false
    race.startTime = nil
    race.endTime = nil
    race.lastTypingAt = nil
    race.currentText = ""
    race.replayText = ""
    race.replayModeId = nil
    race.replayCustomDictionaryIndex = false
    race.replayDictionaryName = ""
    race.replaySourceMeta = { author = "", book = "", genre = "" }
    race.targetChars = {}
    race.words = {}
    race.lines = {}
    race.confirmedLen = 0
    race.wordStartConfirmed = 0
    race.inError = false
    race.errorMarkers = {}
    race.correctCount = 0
    race.totalErrors = 0
    race.sourceAuthor = ""
    race.sourceBook = ""
    race.sourceGenre = ""
    race.isCustomDictionary = false
    race.customDictionaryIndex = false
    race.dictionaryName = ""
    race.inputGeneration = (race.inputGeneration or 0) + 1
    resetBuffer()
    race.typedChars = {}
    race.prevTyped = ""
end

function abortRace(reason)
    if not race.started then return end
    race.started = false
    race.countingDown = false
    race.countdownEnd = nil
    race.countdownWasActive = false
    race.needFocus = false
    race.inputGeneration = (race.inputGeneration or 0) + 1
    race.abortReason = reason
    race.finished = true
    race.completed = false
    race.failed = false
    race.endTime = os.clock()
    resetBuffer()
    race.typedChars = {}
    race.prevTyped = ""
end

function resetFastChatTimer()
    ui.fastChatStartTime = 0
    ui.fastChatInputWasEmpty = true
end

function fastChatToggleState(enabled)
    ui.fastChatEnabledPtr[0] = enabled and true or false
    cfg.settings.fastchat_enabled = ui.fastChatEnabledPtr[0] and 1 or 0
    resetFastChatTimer()
    saveCfg()
end

function fastChatSetInterval(value)
    local interval = tonumber(value) or 2000
    interval = math.max(100, math.min(10000, math.floor(interval + 0.5)))
    ui.fastChatIntervalPtr[0] = interval
    cfg.settings.fastchat_interval = interval
    saveCfg()
end

function fastChatUpdate()
    local enabled = ui.fastChatEnabledPtr[0] and true or false
    if not enabled then
        if ui.fastChatLastState then resetFastChatTimer() end
        ui.fastChatLastState = false
        return
    end

    ui.fastChatLastState = true

    if not sampIsChatInputActive or not sampGetChatInputText or not sampSetChatInputText then
        return
    end

    local okActive, chatActive = pcall(sampIsChatInputActive)
    if not okActive or not chatActive then
        resetFastChatTimer()
        return
    end

    local okText, text = pcall(sampGetChatInputText)
    if not okText then
        return
    end

    text = tostring(text or "")

    if text:sub(1, 1) == "/" then
        resetFastChatTimer()
        return
    end

    if text == "" then
        ui.fastChatInputWasEmpty = true
        ui.fastChatStartTime = 0
        return
    end

    if ui.fastChatInputWasEmpty then
        ui.fastChatStartTime = os.clock() * 1000
        ui.fastChatInputWasEmpty = false
        return
    end

    local elapsed = os.clock() * 1000 - ui.fastChatStartTime
    local interval = tonumber(ui.fastChatIntervalPtr[0]) or 2000

    if elapsed >= interval then
        pcall(sampSetChatInputText, "")
        ui.fastChatInputWasEmpty = true
        ui.fastChatStartTime = 0
    end
end

function drawFastChatMiniPanel()
    if not ui.fastChatWindowOpen[0] then return end

    if ui.fastChatWindowNeedPos then
        pcall(imgui.SetNextWindowPos, imgui.ImVec2(ui.fastChatWindowPosX, ui.fastChatWindowPosY))
        ui.fastChatWindowNeedPos = false
    end

    pcall(imgui.SetNextWindowSize, imgui.ImVec2(350, 0), imgui.Cond and imgui.Cond.Always or nil)

    local flags = 0
    if imgui.WindowFlags then
        flags = (imgui.WindowFlags.AlwaysAutoResize or 0) +
            (imgui.WindowFlags.NoCollapse or 0) +
            (imgui.WindowFlags.NoSavedSettings or 0)
    end

    local okBegin, opened = pcall(imgui.Begin, u8"FastChat###fastchat_settings_window", ui.fastChatWindowOpen, flags)
    if not okBegin or not opened then
        if okBegin then pcall(imgui.End) end
        return
    end

    imgui.Text(u8"FastChat")
    imgui.Separator()

    local okCheck, checkChanged = pcall(imgui.Checkbox, "##fastchat_enabled", ui.fastChatEnabledPtr)
    if okCheck then
        pcall(function()
            local pmin = imgui.GetItemRectMin()
            local pmax = imgui.GetItemRectMax()
            local dl = imgui.GetWindowDrawList()
            if dl and pmin and pmax then
                dl:AddRect(
                    imgui.ImVec2(pmin.x + 0.5, pmin.y + 0.5),
                    imgui.ImVec2(pmax.x - 0.5, pmax.y - 0.5),
                    imgui.ColorConvertFloat4ToU32(colorVec(0.10, 0.10, 0.10, 1.0)),
                    0.0, 0, 1.0
                )
            end
        end)
    end
    if okCheck and checkChanged then
        fastChatToggleState(ui.fastChatEnabledPtr[0])
    end
    imgui.SameLine(0, 5)
    imgui.Text(u8"Включить")

    imgui.Spacing()
    imgui.Text(u8"Интервал (100–10000 мс)")

    ui.fastChatIntervalPtr[0] = math.max(100, math.min(10000, tonumber(ui.fastChatIntervalPtr[0]) or 2000))

    local changedSlider = drawThinSlider("##fastchat_interval_slider", ui.fastChatIntervalPtr, 100, 10000, true, "", 150)
    if changedSlider then
        fastChatSetInterval(ui.fastChatIntervalPtr[0])
    end

    imgui.SameLine(0, 8)
    pcall(imgui.SetNextItemWidth, 125)
    local beforeInput = tonumber(ui.fastChatIntervalPtr[0]) or 2000
    local changedInput = false
    local okInput, inputResult = pcall(imgui.InputInt, "##fastchat_interval_input", ui.fastChatIntervalPtr, 100, 1000)
    if okInput and inputResult then changedInput = true end
    local inputValue = math.max(100, math.min(10000, tonumber(ui.fastChatIntervalPtr[0]) or beforeInput))
    if inputValue ~= ui.fastChatIntervalPtr[0] then
        ui.fastChatIntervalPtr[0] = inputValue
        changedInput = true
    end
    if changedInput and inputValue ~= beforeInput then
        fastChatSetInterval(inputValue)
    end

    imgui.SameLine(0, 5)
    imgui.Text(u8"мс")

    imgui.Spacing()
    imgui.TextWrapped(u8"Очищает текст в игровом чате, через заданное время.")

    pcall(imgui.End)
end

function drawMainWindow()

    local windowH
    if not ui.activePanel then
        windowH = race.started and 430 or 430
    elseif ui.activePanel == "keyboard" then
        if race.started then

            windowH = ui.keyboardVisible[0] and 610 or 390
        else

            windowH = ui.keyboardVisible[0] and 430 or 320
        end
    elseif ui.activePanel == "dictionaries" then
        windowH = 610
    else
        windowH = 610
    end
    local ok_size = pcall(imgui.SetNextWindowSize, imgui.ImVec2(760, windowH), imgui.Cond and imgui.Cond.Always or nil)
    if not ok_size then pcall(imgui.SetNextWindowSize, imgui.ImVec2(760, windowH)) end
    local titleColorPushed = false
    if pcall(imgui.PushStyleColor, imgui.Col.Text, colorVec(1.0, 1.0, 1.0, 1.0)) then
        titleColorPushed = true
    end
    imgui.Begin(u8"Clava Races - by Pryanix###clava_main", ui.open)
    if titleColorPushed then pcall(imgui.PopStyleColor) end

    local curMode = getModeById(race.modeId)
    local curSec = cfg["mode_" .. race.modeId] or {}
    local waiting = not race.started
    local countingDown = race.started and race.countdownEnd and os.clock() < race.countdownEnd

    if race.countdownWasActive and not countingDown then
        race.needFocus = true
        race.lastTypingAt = os.clock()
    end
    race.countdownWasActive = countingDown
    race.countingDown = countingDown
    local raceOngoing = race.started and not race.finished and not race.failed
    local elapsed = 0

    if raceOngoing and not countingDown then
        if not race.lastTypingAt then
            race.lastTypingAt = os.clock()
        end
        if os.clock() - race.lastTypingAt >= 50 then
            abortRace("afk")
            raceOngoing = false
        end
    end

    if race.finished or race.failed then
        elapsed = (race.endTime or 0) - (race.startTime or race.endTime or 0)
    elseif race.startTime then
        elapsed = os.clock() - race.startTime
    end

    local speed = elapsed > 0 and math.floor((race.correctCount / elapsed) * 60 + 0.5) or 0
    local total = race.correctCount + race.totalErrors
    local accuracy = total > 0 and math.floor((race.correctCount / total) * 100 + 0.5) or 100
    local progress = race.started and #race.targetChars > 0 and (race.confirmedLen / #race.targetChars) or 0

    local linkCol = COL_ACCENT

    if waiting then
        imgui.TextColored(themeTextMuted(), u8"Тренировка - " .. curMode.name)

        if ui.activePanel then

        end
        imgui.Separator()
        imgui.Spacing()

        local modeNow = os.clock()
        local modePrev = ui.modeMenuClock or modeNow
        local modeDt = math.max(0.0, math.min(0.05, modeNow - modePrev))
        ui.modeMenuClock = modeNow
        local revealSpeed = 5.8
        if ui.modeMenuOpen then
            ui.modeMenuAnim = math.min(1.0, (ui.modeMenuAnim or 0.0) + modeDt * revealSpeed)
        else
            ui.modeMenuAnim = math.max(0.0, (ui.modeMenuAnim or 0.0) - modeDt * revealSpeed)
        end

        imgui.TextColored(themeTextMuted(), u8"Режим:")
        imgui.SameLine(0, 8)

        local currentMode = getModeById(race.modeId)

        local modeToggleName = race.isCustomDictionary and u8"Словарь" or currentMode.name
        local modeToggleLabel = u8"Режимы: " .. modeToggleName
        local selectedModeColor = race.isCustomDictionary and DICTIONARY_MODE_COLOR or modeButtonColor(modeIndexById(race.modeId))
        local togglePushed = 0
        if pcall(imgui.PushStyleColor, imgui.Col.Button, selectedModeColor) then togglePushed = togglePushed + 1 end
        if pcall(imgui.PushStyleColor, imgui.Col.ButtonHovered, darkenImVec4(selectedModeColor, 0.94)) then togglePushed = togglePushed + 1 end
        if pcall(imgui.PushStyleColor, imgui.Col.ButtonActive, darkenImVec4(selectedModeColor, 0.88)) then togglePushed = togglePushed + 1 end

        if pcall(imgui.PushStyleColor, imgui.Col.Text, colorVec(0.08, 0.08, 0.08, 1.0)) then togglePushed = togglePushed + 1 end
        local toggleClicked = imgui.Button(modeToggleLabel .. "##mode_toggle")
        if togglePushed > 0 then pcall(imgui.PopStyleColor, togglePushed) end

        if toggleClicked then
            ui.modeMenuOpen = not ui.modeMenuOpen
        end

        imgui.SameLine(0, 6)
        local fastChatButtonPushed = 0
        local fastChatButtonBg = ui.fastChatEnabledPtr[0]
            and colorVec(0.72, 0.86, 0.76, 1.0)
            or colorVec(0.92, 0.62, 0.62, 1.0)
        local fastChatButtonHover = ui.fastChatEnabledPtr[0]
            and colorVec(0.78, 0.90, 0.82, 1.0)
            or colorVec(0.97, 0.70, 0.70, 1.0)
        local fastChatButtonText = colorVec(0.10, 0.10, 0.10, 1.0)
        if pcall(imgui.PushStyleColor, imgui.Col.Button, fastChatButtonBg) then fastChatButtonPushed = fastChatButtonPushed + 1 end
        if pcall(imgui.PushStyleColor, imgui.Col.ButtonHovered, fastChatButtonHover) then fastChatButtonPushed = fastChatButtonPushed + 1 end
        if pcall(imgui.PushStyleColor, imgui.Col.ButtonActive, fastChatButtonBg) then fastChatButtonPushed = fastChatButtonPushed + 1 end
        if pcall(imgui.PushStyleColor, imgui.Col.Text, fastChatButtonText) then fastChatButtonPushed = fastChatButtonPushed + 1 end
        local fastChatClicked = imgui.Button(u8"FastChat##fastchat_button")
        if fastChatButtonPushed > 0 then pcall(imgui.PopStyleColor, fastChatButtonPushed) end

        if fastChatClicked then
            local okPos, pmax = pcall(imgui.GetItemRectMax)
            if okPos and pmax then
                ui.fastChatWindowPosX = pmax.x + 6
                ui.fastChatWindowPosY = pmax.y + 2
                ui.fastChatWindowNeedPos = true
            end
            ui.fastChatWindowOpen[0] = true
        end

        drawFastChatMiniPanel()

        if ui.modeMenuAnim > 0.001 then
            imgui.Spacing()

            local rowX = imgui.GetCursorPosX()
            local rowY = imgui.GetCursorPosY()
            local rowStartX = rowX
            local spacing = 5.0
            local stagger = 0.075
            local itemDuration = 0.26
            local slidePx = 18.0
            local buttonH = 28.0
            local widths = {}
            local totalW = 0.0

            for i, m in ipairs(MODES) do
                local okText, textSize = pcall(imgui.CalcTextSize, m.name)
                local tw = (okText and textSize and textSize.x) or (#m.name * 7.0)
                local width = math.max(76.0, math.ceil(tw + 18.0))
                widths[i] = width
                totalW = totalW + width
                if i > 1 then totalW = totalW + spacing end
            end

            local okAvail, avail = pcall(imgui.GetContentRegionAvail)
            if okAvail and avail and totalW > avail.x then
                local usable = math.max(100.0, avail.x - spacing * (#MODES - 1))
                local scale = usable / math.max(1.0, totalW - spacing * (#MODES - 1))
                totalW = 0.0
                for i = 1, #widths do
                    widths[i] = math.max(58.0, math.floor(widths[i] * scale))
                    totalW = totalW + widths[i]
                    if i > 1 then totalW = totalW + spacing end
                end
            end

            local okAvail2, avail2 = pcall(imgui.GetContentRegionAvail)
            if okAvail2 and avail2 then
                rowStartX = rowX + math.max(0.0, (avail2.x - totalW) * 0.5)
            end

            local x = rowStartX
            for i, m in ipairs(MODES) do
                local raw = (ui.modeMenuAnim - (i - 1) * stagger) / itemDuration
                local pAnim = math.max(0.0, math.min(1.0, raw))
                if pAnim > 0.001 then
                    local active = race.modeId == m.id
                    local itemX = x - slidePx * (1.0 - pAnim)

                    pcall(imgui.SetCursorPosX, itemX)
                    pcall(imgui.SetCursorPosY, rowY)

                    local alphaStylePushed = false
                    if imgui.StyleVar and imgui.StyleVar.Alpha then
                        local okAlpha = pcall(imgui.PushStyleVar, imgui.StyleVar.Alpha, pAnim)
                        alphaStylePushed = okAlpha
                    end

                    local pushed = 0
                    if pcall(imgui.PushStyleColor, imgui.Col.Button, modeButtonColor(i)) then pushed = pushed + 1 end
                    if pcall(imgui.PushStyleColor, imgui.Col.ButtonHovered, darkenImVec4(modeButtonColor(i), 0.94)) then pushed = pushed + 1 end
                    if pcall(imgui.PushStyleColor, imgui.Col.ButtonActive, darkenImVec4(modeButtonColor(i), 0.88)) then pushed = pushed + 1 end

                    if pcall(imgui.PushStyleColor, imgui.Col.Text, colorVec(0.08, 0.08, 0.08, pAnim)) then pushed = pushed + 1 end
                    local clickedMode = imgui.Button(m.name .. "##animated_mode" .. i, imgui.ImVec2(widths[i], buttonH))

                    if clickedMode then
                        selectMode(m.id)
                    end

                    if pushed > 0 then pcall(imgui.PopStyleColor, pushed) end
                    if alphaStylePushed then pcall(imgui.PopStyleVar) end
                end

                x = x + widths[i] + spacing
            end

            pcall(imgui.SetCursorPosX, rowX)
            pcall(imgui.SetCursorPosY, rowY + buttonH + 6.0)
        end

        imgui.Spacing()
        imgui.TextColored(themeTextSubtle(), u8"Выберите режим и нажмите \"Начать игру\".")
    else

        drawTrafficLight(countingDown and 1 or (raceOngoing and 3 or nil))
        imgui.SameLine(0, 14)
        imgui.BeginGroup()
            local topModeLabel = (race.isCustomDictionary and race.dictionaryName ~= "" and race.dictionaryName) or curMode.name
            imgui.TextColored(themeTextMuted(), u8"Тренировка - " .. topModeLabel)
            if not race.finished and not race.failed and countingDown then
                local remain = math.max(0, race.countdownEnd - os.clock())
                imgui.TextColored(COL_ACCENT, u8"Старт через: " .. fmtTime(remain))
            else
                imgui.Text(u8"Время заезда: " .. fmtTime(elapsed))
            end
            imgui.Text(u8"Точность: " .. accuracy .. "%")
            imgui.TextColored(themeTextSubtle(), u8"Рекорд режима: " .. (curSec.best_speed or 0) .. u8" зн/мин")
        imgui.EndGroup()
        imgui.SameLine(0, 0)
        local ok_av, availTop = pcall(imgui.GetContentRegionAvail)
        local ok_x, curTopX = pcall(imgui.GetCursorPosX)
        local dashboardW = 178
        if ok_av and availTop and ok_x and curTopX then
            pcall(imgui.SetCursorPosX, curTopX + math.max(0, availTop.x - dashboardW))
        end
        if (tonumber(cfg.settings.speedometer) or 1) ~= 0 then
            drawDashboard(speed, race.totalErrors, 220)
        end

        imgui.Dummy(imgui.ImVec2(0, 83))

        if countingDown then
            imgui.PushStyleColor(imgui.Col.ChildBg, THEME.headerAct)
            local ok_bc = pcall(imgui.BeginChild, u8"##clava_hidden_banner", imgui.ImVec2(0, 150), false)
            if ok_bc then
                local hiddenText = u8"Текст скрыт до начала игры"

                local hiddenScale = (tonumber(cfg.settings.text_scale) or 1.0) * 2.20
                pcall(imgui.SetWindowFontScale, hiddenScale)

                local ok_size, textSize = pcall(imgui.CalcTextSize, hiddenText)
                local ok_avail, avail = pcall(imgui.GetContentRegionAvail)
                local areaW = (ok_avail and avail and avail.x) or 700
                local areaH = 150
                local textW = (ok_size and textSize and textSize.x) or 0
                local textH = (ok_size and textSize and textSize.y) or 0
                local centerX = math.max(0, (areaW - textW) / 2)
                local centerY = math.max(0, (areaH - textH) / 2)
                pcall(imgui.SetCursorPos, imgui.ImVec2(centerX, centerY))

                imgui.PushStyleColor(imgui.Col.Text, colorVec(1, 1, 1, 1))
                imgui.Text(hiddenText)
                imgui.PopStyleColor(1)
                pcall(imgui.SetWindowFontScale, 1.0)
            end
            pcall(imgui.EndChild)
            imgui.PopStyleColor(1)
        else
            if race.finished and race.completed and not race.failed then


                setBufferString("")
                drawFinishedRaceSummary()
            else
                drawRaceText()
                local ok_gap_y, gap_y = pcall(imgui.GetCursorPosY)
                if ok_gap_y and gap_y then
                    pcall(imgui.SetCursorPosY, math.max(0, gap_y - 4))
                end
            end
        end

        if countingDown then
            local ok_dl3, dl3 = pcall(imgui.GetWindowDrawList)
            local ok_p3, p3 = pcall(imgui.GetCursorScreenPos)
            local ok_w3, avail3 = pcall(imgui.GetContentRegionAvail)
            if ok_dl3 and ok_p3 then
                local ww = (ok_w3 and avail3 and avail3.x) or 700
                local hh = 24
                pcall(function()

                    dl3:AddRectFilled(imgui.ImVec2(p3.x, p3.y), imgui.ImVec2(p3.x + ww, p3.y + hh), imgui.ColorConvertFloat4ToU32(THEME.frameBg), 0.0)
                    dl3:AddRect(imgui.ImVec2(p3.x, p3.y), imgui.ImVec2(p3.x + ww, p3.y + hh), imgui.ColorConvertFloat4ToU32(THEME.border), 0.0, nil, 1.0)
                    dl3:AddText(imgui.ImVec2(p3.x + 4, p3.y + 4), imgui.ColorConvertFloat4ToU32(themeTextSubtle()), u8"Набирайте здесь текст после начала игры")
                end)
                pcall(imgui.Dummy, imgui.ImVec2(ww, hh))
            end
        else
            if race.finished and race.completed and not race.failed then

                setBufferString("")
                imgui.Dummy(imgui.ImVec2(0, 0))
            else
                if race.inError or race.failed then
                    imgui.TextColored(COL_ERROR, u8"Исправьте опечатку!")
                else
                    imgui.Dummy(imgui.ImVec2(0, 0))
                end

                local pushedErr = 0
            if race.inError or race.failed then
                if pcall(imgui.PushStyleColor, imgui.Col.FrameBg, colorVec(COL_ERROR.x, COL_ERROR.y, COL_ERROR.z, 0.90)) then pushedErr = pushedErr + 1 end
                if pcall(imgui.PushStyleColor, imgui.Col.FrameBgHovered, colorVec(COL_ERROR.x, COL_ERROR.y, COL_ERROR.z, 0.95)) then pushedErr = pushedErr + 1 end
                if pcall(imgui.PushStyleColor, imgui.Col.FrameBgActive, colorVec(COL_ERROR.x, COL_ERROR.y, COL_ERROR.z, 0.95)) then pushedErr = pushedErr + 1 end
            end
            local textCol = (race.inError or race.failed) and colorVec(1, 1, 1, 1) or THEME.text
            local pushedTxt = pcall(imgui.PushStyleColor, imgui.Col.Text, textCol)
            imgui.SetNextItemWidth(-1)
            local inputId = u8("##clava_input_" .. tostring(race.inputGeneration or 0))
            if race.needFocus and not countingDown then
                imgui.SetKeyboardFocusHere()
                race.needFocus = false
            end

            local inputFrameRounding = nil
            local inputFramePaddingX = nil
            local inputFramePaddingY = nil
            local okInputStyle, inputStyle = pcall(imgui.GetStyle)
            if okInputStyle and inputStyle then
                local okCurrent, currentRounding = pcall(function() return inputStyle.FrameRounding end)
                if okCurrent and type(currentRounding) == 'number' then
                    inputFrameRounding = currentRounding
                    pcall(function() inputStyle.FrameRounding = 0.0 end)
                end
                local okPadding, framePadding = pcall(function() return inputStyle.FramePadding end)
                if okPadding and framePadding then
                    inputFramePaddingX = framePadding.x
                    inputFramePaddingY = framePadding.y
                    pcall(function()
                        inputStyle.FramePadding = imgui.ImVec2(4.0, framePadding.y)
                    end)
                end
            end
            imgui.InputText(inputId, race.buffer, ffi.sizeof(race.buffer))
            if okInputStyle and inputStyle then
                if inputFrameRounding ~= nil then
                    pcall(function() inputStyle.FrameRounding = inputFrameRounding end)
                end
                if inputFramePaddingX ~= nil and inputFramePaddingY ~= nil then
                    pcall(function() inputStyle.FramePadding = imgui.ImVec2(inputFramePaddingX, inputFramePaddingY) end)
                end
            end
            if pushedTxt then pcall(imgui.PopStyleColor, 1) end
            if pushedErr > 0 then pcall(imgui.PopStyleColor, pushedErr) end
                updateTyping()
            end
        end

        imgui.Spacing()
        drawTrack(progress)
        imgui.Spacing()

        if not raceOngoing then
            if race.failed then
                imgui.Separator()
                imgui.TextColored(COL_ERROR, u8"Заезд провален: в режиме \"Одна ошибка\" опечатки не прощаются.")
            elseif race.finished and race.abortReason == "afk" then
                imgui.Separator()
                imgui.TextColored(COL_ERROR, u8"Заезд прерван: 50 секунд бездействия.")
            elseif race.finished and race.correctCount > 0 then
                imgui.Separator()
                imgui.TextColored(COL_CORRECT, u8"Финиш! Заезд окончен.")
                imgui.Text(u8(string.format("Скорость: %d зн/мин   Ошибок: %d   Точность: %d%%", speed, race.totalErrors, accuracy)))
            end
        end
    end

    if ui.activePanel then
        imgui.Separator()
        imgui.Spacing()

        local function textLink(label, id)
            local pushed = 0
            if pcall(imgui.PushStyleColor, imgui.Col.Text, THEME.accent or linkCol) then pushed = pushed + 1 end
            if pcall(imgui.PushStyleColor, imgui.Col.Button, colorVec(0, 0, 0, 0)) then pushed = pushed + 1 end
            if pcall(imgui.PushStyleColor, imgui.Col.ButtonHovered, themeMix(THEME.accent or linkCol, THEME.windowBg, 0.90)) then pushed = pushed + 1 end
            if pcall(imgui.PushStyleColor, imgui.Col.ButtonActive, themeMix(THEME.accent or linkCol, THEME.windowBg, 0.78)) then pushed = pushed + 1 end
            if pcall(imgui.PushStyleColor, imgui.Col.Border, themeBorderSoft()) then pushed = pushed + 1 end
            local clicked = imgui.SmallButton(label .. '##' .. id)
            if pushed > 0 then pcall(imgui.PopStyleColor, pushed) end
            return clicked
        end

        if raceOngoing or countingDown or race.failed then
            if textLink(u8"Прервать игру", "abort") then abortRace() end
            imgui.SameLine(0, 12)
            if textLink(u8"Заново", "restart_active") then restartCurrentText() end
        else
            if race.finished and race.completed and not race.failed then
                if textLink(u8"Начать заново", "restart_finished") then
                    restartCurrentText()
                end
                imgui.SameLine(0, 12)
                if textLink(u8"Закончить игру", "finish") then
                    endFinishedRace()
                end
            else
                if textLink(u8"Начать игру", "start") then
                    if race.isCustomDictionary then
                        restartCurrentText()
                    else
                        pcall(pickModeText, race.modeId)
                    end
                end
            end
        end

        imgui.SameLine(0, 18)
        for i, panel in ipairs({
            { id = "keyboard", label = u8"Клавиатура" },
            { id = "dictionaries", label = u8"Мои словари" },
            { id = "stats", label = u8"Статистика" },
            { id = "settings", label = u8"Настройки" },
        }) do
            if i > 1 then imgui.SameLine(0, 8) end
            local active = ui.activePanel == panel.id
            local pushed = 0
            if pcall(imgui.PushStyleColor, imgui.Col.Text, active and (THEME.accent or linkCol) or themeTextMuted()) then pushed = pushed + 1 end
            if pcall(imgui.PushStyleColor, imgui.Col.Button, active and themeMix(THEME.accent or linkCol, THEME.windowBg, 0.92) or colorVec(0, 0, 0, 0)) then pushed = pushed + 1 end
            if pcall(imgui.PushStyleColor, imgui.Col.ButtonHovered, themeMix(THEME.accent or linkCol, THEME.windowBg, 0.90)) then pushed = pushed + 1 end
            if pcall(imgui.PushStyleColor, imgui.Col.ButtonActive, themeMix(THEME.accent or linkCol, THEME.windowBg, 0.76)) then pushed = pushed + 1 end
            if pcall(imgui.PushStyleColor, imgui.Col.Border, active and themeBorderStrong() or themeBorderSoft()) then pushed = pushed + 1 end
            if imgui.SmallButton(panel.label .. "##top_" .. panel.id) then ui.activePanel = active and nil or panel.id end
            if pushed > 0 then pcall(imgui.PopStyleColor, pushed) end
        end

        imgui.Spacing()

        local panelH = (ui.activePanel == "keyboard" and not ui.keyboardVisible[0]) and 40 or (ui.activePanel == "keyboard" and 250 or 400)
        local ok_child = pcall(imgui.BeginChild, u8"##clava_panel", imgui.ImVec2(0, panelH), true)
        if ok_child then
            if ui.activePanel == "keyboard" then
                if ui.keyboardVisible[0] then
                    local okAvail, av = pcall(imgui.GetContentRegionAvail)
                    local totalW = (okAvail and av and av.x) or 700

                    local quickW = 156
                    local sideSlotW = math.max(220, math.min(280, totalW * 0.34))
                    local gapW = 10
                    local keyW = math.max(360, totalW - sideSlotW - gapW)

                    pcall(imgui.BeginChild, u8"##clava_keyboard_left", imgui.ImVec2(keyW, 0), false)
                    drawKeyboard()
                    pcall(imgui.EndChild)
                    imgui.SameLine(0, gapW)

                    local okRightX, rightX = pcall(imgui.GetCursorPosX)
                    if okRightX and rightX then
                        local centeredOffset = math.max(0, (sideSlotW - quickW) * 0.5)
                        pcall(imgui.SetCursorPosX, rightX + centeredOffset)
                    end

                    pcall(imgui.BeginChild, u8"##clava_quick_right", imgui.ImVec2(quickW, 0), false)
                    drawQuickSettings()
                    pcall(imgui.EndChild)
                    imgui.Spacing()
                end
                if not ui.keyboardVisible[0] then

                    drawKeyboardToggle()
                end
            elseif ui.activePanel == "stats" then
                drawModeStats()
            elseif ui.activePanel == "dictionaries" then

                local function drawDictionaryFieldBorder()
                    pcall(function()
                        local dl = imgui.GetWindowDrawList()
                        local pmin = imgui.GetItemRectMin()
                        local pmax = imgui.GetItemRectMax()
                        if dl and pmin and pmax then
                            local hovered = imgui.IsItemHovered and imgui.IsItemHovered() or false
                            local focused = imgui.IsItemActive and imgui.IsItemActive() or false
                            local c = focused and COL_ACCENT
                                or (hovered and THEME.headerAct or THEME.border)
                            dl:AddRect(
                                imgui.ImVec2(pmin.x - 0.5, pmin.y - 0.5),
                                imgui.ImVec2(pmax.x + 0.5, pmax.y + 0.5),
                                imgui.ColorConvertFloat4ToU32(c), 2.0, 0, focused and 1.6 or 1.1
                            )
                        end
                    end)
                end

                if ui.dictionaryEditIndex == 0 then
                    imgui.Text(u8"Название")
                else
                    imgui.Text(u8"Редактирование словаря #" .. tostring(ui.dictionaryEditIndex))
                end


                local dictionaryInputStyle = nil
                local dictionaryInputPaddingX = nil
                local dictionaryInputPaddingY = nil
                local okDictionaryInputStyle, currentDictionaryInputStyle = pcall(imgui.GetStyle)
                if okDictionaryInputStyle and currentDictionaryInputStyle then
                    dictionaryInputStyle = currentDictionaryInputStyle
                    local okPadding, framePadding = pcall(function() return dictionaryInputStyle.FramePadding end)
                    if okPadding and framePadding then
                        dictionaryInputPaddingX = framePadding.x
                        dictionaryInputPaddingY = framePadding.y
                        pcall(function()
                            dictionaryInputStyle.FramePadding = imgui.ImVec2(4.0, framePadding.y)
                        end)
                    end
                end

                imgui.SetNextItemWidth(-1)
                imgui.InputText(u8"##dictionary_title", ui.dictionaryTitleBuffer, ffi.sizeof(ui.dictionaryTitleBuffer))
                drawDictionaryFieldBorder()

                imgui.Text(u8"Содержание")
                imgui.SetNextItemWidth(-1)

                DICT_WRAP.prepare()
                local changed = imgui.InputTextMultiline(
                    u8"##dictionary_content",
                    ui.dictionaryContentBuffer,
                    ffi.sizeof(ui.dictionaryContentBuffer),
                    imgui.ImVec2(-1, 110),
                    0
                )
                drawDictionaryFieldBorder()

                if dictionaryInputStyle and dictionaryInputPaddingX ~= nil and dictionaryInputPaddingY ~= nil then
                    pcall(function()
                        dictionaryInputStyle.FramePadding = imgui.ImVec2(dictionaryInputPaddingX, dictionaryInputPaddingY)
                    end)
                end

                if changed then
                    DICT_WRAP.syncChanged()
                    DICT_WRAP.rewrap(true)
                end

                local title = ffi.string(ui.dictionaryTitleBuffer):gsub("^%s+", ""):gsub("%s+$", "")
                local content = (ui.dictionaryWrapRaw or DICT_WRAP.unwrapSoftBreaks(ffi.string(ui.dictionaryContentBuffer)))
                    :gsub("^%s+", ""):gsub("%s+$", "")
                local canSave = title ~= "" and content ~= ""
                local editIndex = ui.dictionaryEditIndex

                local function dictionaryButton(label, width, bg, hov, txt, enabled, id)
                    local pushed = 0
                    local alpha = enabled and 1.0 or 0.45
                    local function pc(col, c)
                        if pcall(imgui.PushStyleColor, col, colorVec(c.x, c.y, c.z, alpha)) then pushed = pushed + 1 end
                    end
                    pc(imgui.Col.Button, bg)
                    pc(imgui.Col.ButtonHovered, hov)
                    pc(imgui.Col.ButtonActive, bg)
                    pc(imgui.Col.Text, txt)
                    local clicked = imgui.Button(label .. (id or ""), imgui.ImVec2(width, 30))
                    if pushed > 0 then pcall(imgui.PopStyleColor, pushed) end
                    return enabled and clicked
                end

                if editIndex == 0 then
                    if dictionaryButton(
                        u8"Добавить словарь", 170,
                        COL_CORRECT, themeMix(COL_CORRECT, colorVec(1,1,1,1), 0.14),
                        colorVec(1, 1, 1, 1), canSave, "##add_dictionary"
                    ) then
                        local newIndex = addCustomDictionary(title, content)
                        if newIndex then
                            ffi.fill(ui.dictionaryTitleBuffer, ffi.sizeof(ui.dictionaryTitleBuffer))
                            ffi.fill(ui.dictionaryContentBuffer, ffi.sizeof(ui.dictionaryContentBuffer))
                            ui.dictionaryWrapRaw = ""
                            ui.dictionaryWrapWidth = 0
                            ui.dictionaryWrapPending = true
                        end
                    end
                else
                    if dictionaryButton(
                        u8"Сохранить изменения", 190,
                        COL_ACCENT, themeMix(COL_ACCENT, colorVec(1,1,1,1), 0.14),
                        colorVec(1, 1, 1, 1), canSave, "##save_dictionary"
                    ) then
                        saveCustomDictionary(editIndex, title, content)
                        ui.dictionaryEditIndex = 0
                        ffi.fill(ui.dictionaryTitleBuffer, ffi.sizeof(ui.dictionaryTitleBuffer))
                        ffi.fill(ui.dictionaryContentBuffer, ffi.sizeof(ui.dictionaryContentBuffer))
                        ui.dictionaryWrapRaw = ""
                        ui.dictionaryWrapWidth = 0
                        ui.dictionaryWrapPending = true
                    end
                    imgui.SameLine(0, 8)
                    if dictionaryButton(
                        u8"Отмена", 100,
                        THEME.button, THEME.buttonHov, contrastText({THEME.button.x, THEME.button.y, THEME.button.z, THEME.button.w}), true, "##cancel_dictionary"
                    ) then
                        ui.dictionaryEditIndex = 0
                        ffi.fill(ui.dictionaryTitleBuffer, ffi.sizeof(ui.dictionaryTitleBuffer))
                        ffi.fill(ui.dictionaryContentBuffer, ffi.sizeof(ui.dictionaryContentBuffer))
                        ui.dictionaryWrapRaw = ""
                        ui.dictionaryWrapWidth = 0
                        ui.dictionaryWrapPending = true
                    end
                end

                imgui.Spacing()
                imgui.TextColored(themeTextMuted(), u8"Добавленные черновики")

                local count = cfg.custom_dicts.count or 0
                if count == 0 then
                    imgui.TextColored(themeTextSubtle(), u8"Пока нет добавленных словарей.")
                else
                    local listH = math.max(150, panelH - 255)
                    local okList = pcall(imgui.BeginChild, u8"##custom_dictionary_list", imgui.ImVec2(0, listH), true)
                    if okList then
                        for idx = 1, count do
                            local d = getCustomDictionary(idx)
                            if d then

                                local preview = d.content:gsub("%s+", " ")
                                local previewChars = utf8_chars(preview)
                                local PREVIEW_MAX_CHARS = 45
                                if #previewChars > PREVIEW_MAX_CHARS then
                                    local trimmed = {}
                                    for i = 1, PREVIEW_MAX_CHARS - 3 do
                                        trimmed[#trimmed + 1] = previewChars[i]
                                    end
                                    preview = table.concat(trimmed) .. "..."
                                end

                                local textColumnW = 330

                                local rowTopY = imgui.GetCursorPosY()
                                local rowHeight = 48
                                local buttonHeight = 28
                                local buttonTopOffset = math.max(0, (rowHeight - buttonHeight) * 0.5)
                                imgui.BeginGroup()
                                    imgui.PushItemWidth(textColumnW)
                                    imgui.Text(d.name ~= "" and d.name or u8"Без названия")
                                    imgui.TextColored(themeTextSubtle(), preview)

                                    imgui.Dummy(imgui.ImVec2(textColumnW, 0))
                                    imgui.PopItemWidth()
                                imgui.EndGroup()

                                imgui.SameLine(0, 10)

                                imgui.SetCursorPosY(rowTopY + buttonTopOffset)

                                local function dictionaryListButton(label, width, bg, hov, txt, id)
                                    local pushed = 0
                                    local function push(col, c)
                                        if pcall(imgui.PushStyleColor, col, c) then pushed = pushed + 1 end
                                    end
                                    push(imgui.Col.Button, bg)
                                    push(imgui.Col.ButtonHovered, hov)
                                    push(imgui.Col.ButtonActive, themeMix(bg, THEME.buttonAct, 0.22))
                                    push(imgui.Col.Text, txt)
                                    local clicked = imgui.Button(label .. id, imgui.ImVec2(width, 28))
                                    if pushed > 0 then pcall(imgui.PopStyleColor, pushed) end
                                    return clicked
                                end

                                if dictionaryListButton(
                                    u8"Играть", 68,
                                    COL_CORRECT, themeMix(COL_CORRECT, colorVec(1,1,1,1), 0.14),
                                    colorVec(1, 1, 1, 1), "##play" .. idx
                                ) then
                                    playCustomDictionary(idx)
                                end

                                imgui.SameLine(0, 6)
                                if dictionaryListButton(
                                    u8"Редактировать", 118,
                                    COL_ACCENT, themeMix(COL_ACCENT, colorVec(1,1,1,1), 0.14),
                                    colorVec(1, 1, 1, 1), "##edit" .. idx
                                ) then
                                    editCustomDictionary(idx)
                                end

                                imgui.SameLine(0, 6)
                                if dictionaryListButton(
                                    u8"Убрать", 70,
                                    COL_ERROR, themeMix(COL_ERROR, colorVec(1,1,1,1), 0.14),
                                    colorVec(1, 1, 1, 1), "##delete" .. idx
                                ) then
                                    deleteCustomDictionary(idx)
                                    if ui.dictionaryEditIndex == idx then ui.dictionaryEditIndex = 0 end
                                end
                                imgui.Separator()
                            end
                        end
                        pcall(imgui.EndChild)
                    end
                end

            elseif ui.activePanel == "settings" then
                if imgui.CollapsingHeader(u8"Отсчёт перед стартом") then
                    local changed = drawThinSlider("##thin_countdown", ui.countdownPtr, 0, 15, true, "")
                    ui.countdownPtr[0] = math.max(0, math.min(15, math.floor(tonumber(ui.countdownPtr[0]) or 5)))
                    imgui.SameLine(0, 8)
                    imgui.Text(u8"Секунд перед стартом [" .. tostring(ui.countdownPtr[0]) .. "]")
                    if changed then
                        cfg.settings.countdown_seconds = ui.countdownPtr[0]
                        saveCfg()
                    end
                end
                if imgui.CollapsingHeader(u8"Стиль интерфейса") then
                    imgui.TextColored(themeTextSubtle(), u8"Выберите готовое оформление всего интерфейса:")
                    imgui.Spacing()
                    local currentStyle = tonumber(cfg.settings.style_index) or 0
                    for i, style in ipairs(STYLE_PRESETS) do
                        local idx = i - 1
                        local selected = currentStyle == idx
                        local styleBg, styleHov, styleTxt = styleButtonColors(style)
                        pcall(imgui.PushStyleColor, imgui.Col.Button, styleBg)
                        pcall(imgui.PushStyleColor, imgui.Col.ButtonHovered, styleHov)
                        pcall(imgui.PushStyleColor, imgui.Col.ButtonActive, styleBg)
                        pcall(imgui.PushStyleColor, imgui.Col.Text, styleTxt)
                        if selected then
                            pcall(imgui.PushStyleColor, imgui.Col.Border, THEME.accent or COL_ACCENT)
                        else
                            pcall(imgui.PushStyleColor, imgui.Col.Border, THEME.border)
                        end
                        local borderStyle, borderPrev = pushButtonFrameBorder(1.0)
                        local clickedStyle = imgui.Button(style.name .. "##style_" .. idx, imgui.ImVec2(130, 30))
                        popButtonFrameBorder(borderStyle, borderPrev)
                        pcall(imgui.PopStyleColor, 5)
                        if clickedStyle then
                            applyInterfaceStyle(idx)
                            saveCfg()
                        end
                        if i < #STYLE_PRESETS then imgui.SameLine(0, 8) end
                    end
                end
            end
        end
        pcall(imgui.EndChild)
    end

    imgui.End()
end

local RENDER_STATE = { lastError = nil, lastErrorAt = 0 }
RENDER_STATE.render = imgui.OnFrame(
    function() return ui.open[0] end,
    function(self)
        if not ui.fontsLoaded then pcall(loadClavaFonts) end

        ui.fontFallbackFrames = (ui.fontFallbackFrames or 0) + 1
        if not ui.fontFallbackDone and ui.fontFallbackFrames > 5 then
            ui.fontFallbackDone = true
            local selected = tonumber(ui.fontIndexPtr[0]) or 0
            if selected > 0 and not ui.fontObjects[selected] then
                pcall(loadFontAtIndex, selected)
            end

            if not next(ui.fontObjects or {}) then
                pcall(buildFontAtlas)
            end
        end
        pushTheme()
        local ok, err = pcall(function()
            drawMainWindow()
        end)
        popTheme()
        if not ok then
            pcall(imgui.End)
            ui.open[0] = false
            local now = os.clock()
            if RENDER_STATE.lastError ~= tostring(err) or now - RENDER_STATE.lastErrorAt > 3 then
                RENDER_STATE.lastError = tostring(err)
                RENDER_STATE.lastErrorAt = now
            end
        else

        end

        flushCfgSave()
    end
)
RENDER_STATE.render.HideCursor = false
RENDER_STATE.render.LockPlayer = true

sampRegisterChatCommand('clava', function(param)
    param = param or ""
    local p = param:gsub("^%s+", ""):gsub("%s+$", "")
    local pLower = p:lower()

    if p == "" then
        ui.open[0] = not ui.open[0]
    elseif pLower == "next" or pLower == u8"далее" or pLower == u8"следующий" then
        ui.open[0] = true
        pickNewTextSameMode()
    elseif pLower == "restart" or pLower == u8"заново" then
        ui.open[0] = true
        restartCurrentText()
    else
        ui.open[0] = true
        setCustomText(u8(p))
    end
end)

function main()
    local seed = os.time() + math.floor(os.clock() * 1000000) + math.floor(collectgarbage('count') * 10)
    math.randomseed(seed)


    math.random(); math.random(); math.random()

    while true do
        pollLayoutSwitch()
        fastChatUpdate()
        wait(10)
    end
end

function onScriptTerminate(script, quitGame)
    pcall(writeCfgNow)
end