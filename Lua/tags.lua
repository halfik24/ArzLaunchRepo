script_author("Deps | https://www.blast.hk/members/425043/")

local ffi = require('ffi')
local bit = require('bit')
local imgui = require('mimgui')
local hook = require('hooks')
local memory = require('memory')
local encoding = require('encoding')
local inicfg = require('inicfg')

encoding.default = 'CP1251'
local u8 = encoding.UTF8

ffi.cdef[[
    void* GetModuleHandleA(const char* lpModuleName);
    typedef int (__thiscall *PlayerDraw_t)(void* this_ptr, int player);
    typedef int (__thiscall *FamilyLine_t)(void* this_ptr, int position, int mode);
    typedef int (__thiscall *DrawText_t)(
        void* this_ptr, int a1, int a2, int a3, int a4,
        const uint8_t* str, const uint8_t* str_end,
        int a7, int a8, int a9, int a10
    );
    typedef int (__thiscall *FamilyText_t)(
        void* this_ptr, int position, int color, const uint8_t* str,
        int length, int a5, int a6, int size
    );
]]

local cfg = inicfg.load({
    tags = {
        admin   = false,
        vip     = false,
        vip_lvl = false,
        family  = false,
        family_name = false,
    }
}, 'tags')

local state = {
    window      = imgui.new.bool(false),
    module_base = nil,
    any_active  = false,
    tag_admin   = imgui.new.bool(cfg.tags.admin),
    tag_vip     = imgui.new.bool(cfg.tags.vip),
    tag_vip_lvl = imgui.new.bool(cfg.tags.vip_lvl),
    tag_family  = imgui.new.bool(cfg.tags.family),
    hide_family_name = imgui.new.bool(cfg.tags.family_name or false),
}

local draw_hooks = {}
local player_draw_depth = 0

local function update_active()
    state.any_active = state.tag_admin[0] or state.tag_vip[0]
        or state.tag_vip_lvl[0] or state.tag_family[0]
end

update_active()

local function save_config()
    update_active()
    cfg.tags.admin   = state.tag_admin[0]
    cfg.tags.vip     = state.tag_vip[0]
    cfg.tags.vip_lvl = state.tag_vip_lvl[0]
    cfg.tags.family  = state.tag_family[0]
    cfg.tags.family_name = state.hide_family_name[0]
    inicfg.save(cfg, 'tags')
end

local function should_hide(b2, b3)
    if b2 == 0x89 then
        if b3 == 0x9D and state.tag_admin[0] then return true end
        if (b3 == 0x9A or b3 == 0x9B or b3 == 0x9C) and state.tag_vip[0] then return true end
        if b3 >= 0x90 and b3 <= 0x99 and state.tag_vip_lvl[0] then return true end
    end
    if b2 == 0x88 and b3 >= 0x80 and b3 <= 0xBF and state.tag_family[0] then return true end
    return false
end

local function make_family_detour(get_original)
    return function(this_ptr, position, color, str, length, a5, a6, size)
        if state.hide_family_name[0] then return 0 end
        return get_original()(this_ptr, position, color, str, length, a5, a6, size)
    end
end

local function hide_tag_glyph(this_ptr, font_ptr, codepoint, changed)
    local font = ffi.cast('uint8_t*', font_ptr)
    if font == nil then
        font = ffi.cast('uint8_t**', ffi.cast('uint8_t*', this_ptr) + 0x2C)[0]
    end
    if font == nil then return end
    local lookup_size = tonumber(ffi.cast('int32_t*', font + 0x14)[0])
    if codepoint >= lookup_size then return end
    local lookup = ffi.cast('int32_t**', font + 0x1C)[0]
    if lookup == nil then return end
    local index = tonumber(lookup[codepoint])
    local glyph_count = tonumber(ffi.cast('int32_t*', font + 0x20)[0])
    if index < 0 or index >= glyph_count then return end
    local glyph_data = ffi.cast('uint8_t**', font + 0x28)[0]
    if glyph_data == nil then return end
    local glyph = glyph_data + index * 40
    local flags = tonumber(glyph[0])
    if bit.band(flags, 2) ~= 0 then
        changed[#changed + 1] = {glyph, flags}
        glyph[0] = bit.band(flags, 0xFD)
    end
end

local function make_player_detour(get_original)
    return function(this_ptr, player)
        player_draw_depth = player_draw_depth + 1
        local ok, result = pcall(get_original(), this_ptr, player)
        player_draw_depth = player_draw_depth - 1
        if not ok then error(result) end
        return result
    end
end

local function make_family_line_detour(get_original)
    return function(this_ptr, position, mode)
        if state.hide_family_name[0] then return 0 end
        return get_original()(this_ptr, position, mode)
    end
end

local function make_detour(get_original)
    return function(this_ptr, a1, a2, a3, a4, str, str_end, a7, a8, a9, a10)
        local original = get_original()
        if player_draw_depth == 0 or not state.any_active or str == nil then
            return original(this_ptr, a1, a2, a3, a4, str, str_end, a7, a8, a9, a10)
        end
        local length = str_end ~= nil and tonumber(str_end - str) or 0
        if length == 0 then
            while length < 2000 and str[length] ~= 0 do length = length + 1 end
        end
        if length <= 0 or length >= 2000 then
            return original(this_ptr, a1, a2, a3, a4, str, str_end, a7, a8, a9, a10)
        end
        local changed = {}
        local i = 0
        while i <= length - 3 do
            if str[i] == 0xEF and should_hide(str[i+1], str[i+2]) then
                local codepoint = 0xF000 + (str[i+1] - 0x80) * 64 + str[i+2] - 0x80
                hide_tag_glyph(this_ptr, a1, codepoint, changed)
                i = i + 3
            else
                i = i + 1
            end
        end
        if #changed == 0 then
            return original(this_ptr, a1, a2, a3, a4, str, str_end, a7, a8, a9, a10)
        end
        local ok, result = pcall(original, this_ptr, a1, a2, a3, a4, str, str_end, a7, a8, a9, a10)
        for _, item in ipairs(changed) do item[1][0] = item[2] end
        if not ok then error(result) end
        return result
    end
end

imgui.OnFrame(function() return state.window[0] end, function()
    imgui.SetNextWindowSize(imgui.ImVec2(340, 210), imgui.Cond.FirstUseEver)
    imgui.Begin(u8'Tags', state.window, imgui.WindowFlags.NoResize + imgui.WindowFlags.NoCollapse)

    if imgui.Checkbox(u8'Админ-статус', state.tag_admin) then save_config() end
    if imgui.Checkbox(u8'VIP-статус', state.tag_vip) then save_config() end
    if imgui.Checkbox(u8'Уровни VIP', state.tag_vip_lvl) then save_config() end
    if imgui.Checkbox(u8'Семейный флаг', state.tag_family) then save_config() end
    if imgui.Checkbox(u8'Скрыть дубл. название фамы', state.hide_family_name) then save_config() end

    imgui.End()
end)

local function find_draw_calls(base)
    local pe_offset = memory.getuint32(base + 0x3C)
    if pe_offset < 0x40 or pe_offset > 0x1000 then return nil end
    local pe = base + pe_offset
    if memory.getuint32(pe) ~= 0x4550 then return nil end
    local count = memory.getuint16(pe + 6)
    local sections = pe + 24 + memory.getuint16(pe + 20)
    local code, code_base
    for i = 0, count - 1 do
        local section = sections + i * 40
        if ffi.string(ffi.cast('const char*', section), 5) == '.text' then
            local size = memory.getuint32(section + 8)
            if size == 0 or size > 0x1000000 then return nil end
            code_base = base + memory.getuint32(section + 12)
            code = ffi.string(ffi.cast('const char*', code_base), size)
            break
        end
    end
    if not code then return nil end
    local function locate(signature)
        local pos = code:find(signature, 1, true)
        if not pos or code:find(signature, pos + 1, true) then return nil end
        local addr = code_base + pos - 1 + #signature
        if memory.getuint8(addr) ~= 0xE8 then return nil end
        local target = addr + 5 + tonumber(ffi.cast('const int32_t*', addr + 1)[0])
        if target < code_base or target + 6 > code_base + #code then return nil end
        if ffi.string(ffi.cast('const char*', target), 6) ~=
            string.char(0x55, 0x8B, 0xEC, 0x83, 0xEC, 0x10) then return nil end
        return addr, target
    end
    local shadow, target = locate(string.char(0xF3,0x0F,0x11,0x5D,0xD0,0xF3,0x0F,0x11,0x55,0xCC))
    local text, text_target = locate(string.char(0x4D,0xE8,0xF3,0x0F,0x11,0x04,0x24,0xFF,0x75,0xEC))
    if not shadow or not text or target ~= text_target then return nil end
    local layout = string.char(0x8B,0x43,0x1C,0x8B,0x04,0x88,0x83,0xF8,0xFF)
    if not code:find(layout, 1, true) then return nil end
    local addresses = {}
    local pos = 1
    while true do
        pos = code:find(string.char(0xE8), pos, true)
        if not pos then break end
        if pos + 4 <= #code then
            local addr = code_base + pos - 1
            local destination = addr + 5 + tonumber(ffi.cast('const int32_t*', addr + 1)[0])
            if destination == target then addresses[#addresses + 1] = addr end
        end
        pos = pos + 1
    end
    local family_addresses = {}
    local family_target
    local signature = string.char(0xFF,0xB7,0xA0,0,0,0,0x8D,0x45,0xC8,0x50)
    pos = 1
    while true do
        pos = code:find(signature, pos, true)
        if not pos then break end
        local addr = code_base + pos - 1 + #signature
        if memory.getuint8(addr) ~= 0xE8 then return nil end
        local destination = addr + 5 + tonumber(ffi.cast('const int32_t*', addr + 1)[0])
        if destination < code_base or destination + 4 > code_base + #code then return nil end
        if ffi.string(ffi.cast('const char*', destination), 4) ~= string.char(0x55,0x8B,0xEC,0x51) then return nil end
        if family_target and family_target ~= destination then return nil end
        family_target = destination
        family_addresses[#family_addresses + 1] = addr
        pos = pos + #signature
    end
    if #family_addresses ~= 2 then return nil end
    local scope_signature = string.char(0x8D,0x4F,0xF0,0x51,0x8B,0xCB,0x80,0x78,3,0,0x74,0x0A)
    local scope_pos = code:find(scope_signature, 1, true)
    if not scope_pos or code:find(scope_signature, scope_pos + 1, true) then return nil end
    local scope_first = code_base + scope_pos - 1 + #scope_signature
    local scopes = {scope_first, scope_first + 10}
    for _, addr in ipairs(scopes) do
        if memory.getuint8(addr) ~= 0xE8 then return nil end
        local destination = addr + 5 + tonumber(ffi.cast('const int32_t*', addr + 1)[0])
        if destination < code_base or destination + 8 > code_base + #code then return nil end
        if ffi.string(ffi.cast('const char*', destination), 8) ~= string.char(0x53,0x8B,0xDC,0x83,0xEC,8,0x83,0xE4) then return nil end
    end
    local line_signature = string.char(0xF3,0x0F,0x11,0x4D,0xCC,0xF3,0x0F,0x11,0x45,0xB0,0xF3,0x0F,0x11,0x4D,0xB4)
    local line_pos = code:find(line_signature, 1, true)
    if not line_pos or code:find(line_signature, line_pos + 1, true) then return nil end
    local line_addr = code_base + line_pos - 1 + #line_signature
    if memory.getuint8(line_addr) ~= 0xE8 then return nil end
    return addresses, family_addresses, scopes, line_addr
end

function main()
    if not isSampLoaded() or not isSampfuncsLoaded() then return end
    while not isSampAvailable() do wait(100) end

    local handle = ffi.C.GetModuleHandleA('_chat.asi')
    if handle ~= nil then
        local base = tonumber(ffi.cast('uintptr_t', handle))
        if memory.getuint8(base) == 0x4D then
            state.module_base = base
        end
    end

    if not state.module_base then
        sampAddChatMessage('[Tags] {FF4444}_chat.asi не найден. Скрипт отключен.', 0xFFFFFF)
        thisScript():unload()
        return
    end

    local addresses, family_addresses, scopes, family_line = find_draw_calls(state.module_base)
    if not addresses or #addresses == 0 then
        sampAddChatMessage('[Tags] {FF4444}Не найдена отрисовка: версия _chat.asi не поддерживается.', 0xFFFFFF)
        thisScript():unload()
        return
    end
    for _, addr in ipairs(addresses) do
        local entry = {}
        entry.callback = make_detour(function() return entry.hook end)
        entry.hook = hook.call.new("DrawText_t", entry.callback, addr)
        if not entry.hook then
            for _, installed in ipairs(draw_hooks) do installed.hook.stop() end
            sampAddChatMessage('[Tags] {FF4444}Не удалось установить перехват отрисовки.', 0xFFFFFF)
            thisScript():unload()
            return
        end
        draw_hooks[#draw_hooks + 1] = entry
    end
    for _, addr in ipairs(family_addresses) do
        local entry = {}
        entry.callback = make_family_detour(function() return entry.hook end)
        entry.hook = hook.call.new("FamilyText_t", entry.callback, addr)
        if not entry.hook then
            for _, installed in ipairs(draw_hooks) do installed.hook.stop() end
            sampAddChatMessage('[Tags] {FF4444}Не удалось скрыть верхнюю строку семьи.', 0xFFFFFF)
            thisScript():unload()
            return
        end
        draw_hooks[#draw_hooks + 1] = entry
    end
    local extra = {{family_line, 'FamilyLine_t', make_family_line_detour}}
    for _, addr in ipairs(scopes) do extra[#extra + 1] = {addr, 'PlayerDraw_t', make_player_detour} end
    for _, spec in ipairs(extra) do
        local entry = {}
        entry.callback = spec[3](function() return entry.hook end)
        entry.hook = hook.call.new(spec[2], entry.callback, spec[1])
        if not entry.hook then
            for _, installed in ipairs(draw_hooks) do installed.hook.stop() end
            sampAddChatMessage('[Tags] {FF4444}Не удалось установить перехват над игроками.', 0xFFFFFF)
            thisScript():unload()
            return
        end
        draw_hooks[#draw_hooks + 1] = entry
    end
    print('[Tags] Installed draw hooks: ' .. #draw_hooks)

    sampRegisterChatCommand('tags', function()
        state.window[0] = not state.window[0]
    end)

    wait(-1)
end