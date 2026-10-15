script_author('MLycoris')
script_version('0.3')
local imgui = require 'mimgui'
local ffi = require 'ffi'
local encoding = require 'encoding'
encoding.default = 'CP1251'
local u8 = encoding.UTF8 
local resGif, gif = pcall(require, "GifPlayerLua")
local new = imgui.new
local inicfg = require 'inicfg'
local settings = inicfg.load({
    shit = {
        posX = 500,
        posY = 500,
        text = '',
        active = false,
        fontSize = 12,
        hideDial = false,
        downloadMode = 1,
        testCheatText = '',
    }}, 'watermark.ini')
inicfg.save(settings, 'watermark.ini')

function json(filePath)
    local filePath = getWorkingDirectory()..'\\config\\'..(filePath:find('(.+).json') and filePath or filePath..'.json')
    local class = {}
    if not doesDirectoryExist(getWorkingDirectory()..'\\config') then
        createDirectory(getWorkingDirectory()..'\\config')
    end
    function class:Save(tbl)
        if tbl then
            local F = io.open(filePath, 'w')
            F:write(encodeJson(tbl) or {})
            F:close()
            return true, 'ok'
        end
        return false, 'table = nil'
    end
    function class:Load(defaultTable)
        if not doesFileExist(filePath) then
            class:Save(defaultTable or {})
        end
        local F = io.open(filePath, 'r+')
        local TABLE = decodeJson(F:read() or {})
        F:close()
        for def_k, def_v in next, defaultTable do
            if TABLE[def_k] == nil then
                TABLE[def_k] = def_v
            end
        end
        return TABLE
    end
    return class
end

local glSet = {
    WinState = new.bool(), -- осн окно
    mimImages = {}, -- табл с пнг для окна
    images = {}, -- табл с пнг
    gifs = {}, -- табл с гиф
    currentTab = 2, -- вкладка
    movewin = false, -- перемещ
    movepic = -1, -- мувпик
    path = getWorkingDirectory()..'\\resource\\watermark\\', -- путь к пнг
    hideDial = new.bool(settings.shit.hideDial), -- скр пнг при откр диалоге
    downloadModeList = {'При входе в игру','При спавне','При введении чит-кода'},
    downloadMode = new.int(settings.shit.downloadMode), -- когда загружать
    downloadModeCheck = false,
    cheatCodeInput = new.char[512](u8(settings.shit.testCheatText)),
}

imgui.OnInitialize(function()
    imgui.GetIO().IniFilename = nil
    local glyph_ranges = imgui.GetIO().Fonts:GetGlyphRangesCyrillic()
    bold = imgui.GetIO().Fonts:AddFontFromFileTTF(getFolderPath(0x14)..'\\impact.ttf', 24, _, glyph_ranges)
    justBig = imgui.GetIO().Fonts:AddFontFromFileTTF(getFolderPath(0x14)..'\\Arial.ttf', 30, _, glyph_ranges)
    theme()
    for k,v in pairs(getFilesInPath(glSet.path, {'*.png'})) do
        table.insert(glSet.mimImages,{imgui.CreateTextureFromFile(glSet.path..v), v})
    end
end)
local st = {
    text = new.char[512](u8(settings.shit.text)),
    active = new.bool(settings.shit.active),
    size = new.int(settings.shit.fontSize),
}
local wmJSON = json('watermark.json'):Load({})

function main()
    while not isSampAvailable() do wait(100) end
    sampRegisterChatCommand('wmark', function() glSet.WinState[0] = not glSet.WinState[0] end)
    if not doesDirectoryExist('moonloader/resource/watermark') then createDirectory('moonloader/resource/watermark') end
    if not settings.downloadModeCheck and (settings.shit.downloadMode == 1 or settings.shit.downloadMode == 2) then
        if settings.shit.downloadMode == 2 then
            while not sampIsLocalPlayerSpawned() do wait(100) end
        end
        for k,image in pairs(getFilesInPath(glSet.path, {'*.png'})) do checkImGif(image,1) end
        for k,gif in pairs(getFilesInPath(glSet.path, {'*.gif'})) do checkImGif(gif,2) end
        settings.downloadModeCheck = true
        if #glSet.gifs > 0 then renderGif() end
    end
    for k,data in pairs(wmJSON) do if data.status == nil then data.status = true save() end end
    font = renderCreateFont('TimesNewRoman', settings.shit.fontSize, 5)
    while true do wait(0)
        if not settings.downloadModeCheck and settings.shit.downloadMode == 3 and testCheat(settings.shit.testCheatText) then
            for k,image in pairs(getFilesInPath(glSet.path, {'*.png'})) do checkImGif(image,1) end
            for k,gif in pairs(getFilesInPath(glSet.path, {'*.gif'})) do checkImGif(gif,2) end
            settings.downloadModeCheck = true
            if #glSet.gifs > 0 then renderGif() end
        end
        if not isPauseMenuActive() and (not glSet.hideDial[0] and 0 or not sampIsDialogActive()) then
            if settings.shit.text ~= '' then
                renderFontDrawText(font, settings.shit.text:gsub('/ns','\n'):gsub('/bb','     '), settings.shit.posX, settings.shit.posY, 0xFFFFFFFF)
                if glSet.movewin then
                    if glSet.movewin then settings.shit.posX, settings.shit.posY = getCursorPos() end
                    if wasKeyPressed(0x20) then
                        glSet.movewin = false
                        inicfg.save(settings, 'watermark.ini') 
                    end 
                end
            end
            if #glSet.images ~= 0 then
                for k,v in pairs(glSet.images) do
                    for index,data in pairs(wmJSON) do
                        if data.status and tostring(v[6]):find(tostring(data.imageName)) then
                            renderDrawTexture(v[1], data.posX, data.posY, data.sizeX, data.sizeY, 0, -1)
                        end
                    end
                end
            end
        end
    end
end

imgui.OnFrame(function() return glSet.WinState[0] and not isPauseMenuActive() end, function(player)
    imgui.SetNextWindowPos(imgui.ImVec2(400,500), imgui.Cond.FirstUseEver, imgui.ImVec2(0.5, 0.5))
    imgui.SetNextWindowSize(imgui.ImVec2(470, 540), imgui.Cond.Always)
    imgui.Begin('##WindowTwo', glSet.WinState, imgui.WindowFlags.NoResize)
    if imgui.Button(u8'Настройки',imgui.ImVec2(imgui.GetWindowWidth()-10, 24)) then
        imgui.OpenPopup(u8'Настройки##1')
    end
    if imgui.BeginPopupModal(u8'Настройки##1', _, imgui.WindowFlags.AlwaysAutoResize) then
        --imgui.SetWindowSizeVec2(imgui.ImVec2(290, 190))
        if imgui.Checkbox(u8'Скрывать Текст/PNG/GIF при открытом диалоге',glSet.hideDial) then
            settings.shit.hideDial = glSet.hideDial[0]
            inicfg.save(settings, 'watermark.ini')
        end
        imgui.Separator() imgui.CenterText('Когда подгружать PNG/GIF') imgui.Separator()
        for i=1, 3 do
            if imgui.RadioButtonIntPtr(u8(glSet.downloadModeList[i]),glSet.downloadMode,i) then
                settings.shit.downloadMode = glSet.downloadMode[0]
                inicfg.save(settings, 'watermark.ini')
            end
        end
        if settings.shit.downloadMode == 3 then
            if imgui.InputText('##cheatCode',glSet.cheatCodeInput,512) then
                local inpText = u8:decode(ffi.string(glSet.cheatCodeInput))
                if inpText:find('[А-Яа-я]') then
                    inpText = inpText:gsub('[А-Яа-я]','')
                end
                settings.shit.testCheatText = inpText
                inicfg.save(settings, 'watermark.ini')
            end
            imgui.Text(u8'Текущ. чит-код: '..settings.shit.testCheatText)
        end
        if imgui.Button(u8'Закрыть',imgui.ImVec2(imgui.GetWindowWidth()-10, 24)) then
            imgui.CloseCurrentPopup()
        end
        imgui.End()
    end
    imgui.PushFont(bold) 
    for numTab, nameTab in pairs({'Текст','Картинки','[Beta] Гифки'}) do
        if imgui.Button(u8(nameTab),imgui.ImVec2(150,40)) then glSet.currentTab = numTab end 
        if numTab < 3 then imgui.SameLine() end
    end imgui.PopFont()
    -- Text
        if glSet.currentTab == 1 then
            imgui.PushItemWidth(imgui.GetWindowWidth()-10)
            if imgui.InputTextWithHint(u8"##Многострочный инпут",u8'Введите текст', st.text, 256) then
                settings.shit.text = u8:decode(ffi.string(st.text)) inicfg.save(settings, 'watermark.ini')
            end imgui.PopItemWidth()
            imgui.Hint('Используйте:\n/ns для переноса на следующую строку\n/bb для большого пробела\n{RRGGBB} для смены цвета текста')
            imgui.Separator()
            local bs = imgui.GetWindowWidth()/2-8
            if imgui.Button(u8'Переместить##1',imgui.ImVec2(bs, 24)) then glSet.movewin = true 
                sampAddChatMessage('{FF634F}[{ffffff}WaterMark{FF634F}] {ffffff}Нажмите {FF634F}ПРОБЕЛ{ffffff}, чтобы сохранить позицию',-1) end imgui.SameLine()
            if imgui.Button(u8'Очистить', imgui.ImVec2(bs, 24)) then settings.shit.text = '' inicfg.save(settings, 'watermark.ini') imgui.StrCopy(st.text, '') end
            if imgui.SliderInt(u8'Размер шрифта', st.size, 1, 50) then
                settings.shit.fontSize = st.size[0]
                font = renderCreateFont('TimesNewRoman', settings.shit.fontSize, 5)
            end imgui.Separator() imgui.CenterText('Ваш текст выглядит так:')
            imgui.PushFont(justBig)
            imgui.TextColoredRGB('{FFFFFF}'..settings.shit.text:gsub('/ns','\n{FFFFFF}'):gsub('/bb','     ')) 
            imgui.PopFont()
    -- Image
        elseif glSet.currentTab == 2 then
            if imgui.Button(u8'Обновить##Image',imgui.ImVec2(imgui.GetWindowWidth()-10, 24)) then 
                glSet.images = {}
                glSet.mimImages = {}
                for k,v in pairs(getFilesInPath(glSet.path, {'*.png'})) do
                    table.insert(glSet.mimImages,{imgui.CreateTextureFromFile(glSet.path..v), v})
                    checkImGif(v,1)
                end
            end
            if #glSet.images ~= 0 then
                imgui.Separator()
                for k, v in pairs(glSet.mimImages) do
                    imgui.ColoredImageButton(v[1],v[2],imgui.ImVec2(100, 100))
                    imgui.Hint(v[2]..'\n\nНажмите на картинку, чтобы отобразить/скрыть её') imgui.SameLine()
                    if imgui.BeginChild('ImageTab##'..k, imgui.ImVec2(350, 110), false) then
                        for index, data in pairs(wmJSON) do
                            if tostring(data.imageName):find(tostring(v[2])) then
                                imgui.Dummy(imgui.ImVec2(0,10))
                                local picSizeY = new.int(data.sizeY/100)
                                local picSizeX = new.int(data.sizeX/100)
                                imgui.PushItemWidth(imgui.GetWindowWidth()-70)
                                if imgui.SliderInt(u8'Высота##'..index, picSizeY, 1, 10) then
                                    data.sizeY = picSizeY[0]*100 save()
                                end
                                if imgui.SliderInt(u8'Ширина##'..index, picSizeX, 1, 10) then
                                    data.sizeX = picSizeX[0]*100 save()
                                end imgui.PopItemWidth()
                                if imgui.Button(u8'Переместить##'..index,imgui.ImVec2(imgui.GetWindowWidth()-20, 24)) then
                                    glSet.movepic = index
                                    sampAddChatMessage('{FF634F}[{ffffff}WaterMark{FF634F}] {ffffff}Нажмите {FF634F}ПРОБЕЛ{ffffff}, чтобы сохранить позицию',-1)
                                end
                                if glSet.movepic == index then 
                                    data.posX, data.posY = getCursorPos()
                                    if wasKeyPressed(0x20) then
                                        glSet.movepic = -1 save()
                                    end
                                end
                            end
                        end
                        imgui.EndChild()
                    end imgui.Separator()
                end
            end
    -- GIF
        elseif glSet.currentTab == 3 then
            imgui.TextDisabled(u8'Вкладка ещё в процессе тестов, но у вас уже есть возможность добавить\nGIF на свои экраны.')
            if imgui.Button(u8'Обновить##Gifs',imgui.ImVec2(imgui.GetWindowWidth()-10, 24)) then 
                thisScript():reload()
            end imgui.Hint('Это приведёт к перезагрузке скрипта')
            if #glSet.gifs ~= 0 then
                imgui.Separator()
                for k, v in pairs(glSet.gifs) do
                    imgui.ColoredImageButton(ffi.cast("void*", v[1]:ProcessPlay()),v[6],imgui.ImVec2(100, 100))
                    imgui.Hint(v[6]..'\n\nНажмите на гифку, чтобы отобразить/скрыть её') imgui.SameLine()
                    if imgui.BeginChild('Name2##'..k, imgui.ImVec2(350, 110), false) then
                        for index, data in pairs(wmJSON) do
                            if tostring(data.imageName):find(tostring(v[6])) then
                                imgui.Dummy(imgui.ImVec2(0,10))
                                local picSizeY = new.int(data.sizeY/100)
                                local picSizeX = new.int(data.sizeX/100)
                                imgui.PushItemWidth(imgui.GetWindowWidth()-50)
                                if imgui.SliderInt(u8'Высота##'..index, picSizeY, 1, 10) then
                                    data.sizeY = picSizeY[0]*100 save()
                                end
                                if imgui.SliderInt(u8'Ширина##'..index, picSizeX, 1, 10) then
                                    data.sizeX = picSizeX[0]*100 save()
                                end imgui.PopItemWidth()
                                if imgui.Button(u8'Переместить##'..index,imgui.ImVec2(imgui.GetWindowWidth(), 24)) then
                                    glSet.movepic = index
                                    sampAddChatMessage('{FF634F}[{ffffff}WaterMark{FF634F}] {ffffff}Нажмите {FF634F}ПРОБЕЛ{ffffff}, чтобы сохранить позицию',-1)
                                end
                                if glSet.movepic == index then 
                                    data.posX, data.posY = getCursorPos()
                                    if wasKeyPressed(0x20) then
                                        glSet.movepic = -1 save()
                                    end
                                end
                            end
                        end
                        imgui.EndChild()
                    end imgui.Separator()
                end
            end
        end
    -- END
    imgui.End()
end)
function renderGif()
    for index, data in pairs(wmJSON) do
        imgui.OnFrame(function() return data.status and not isPauseMenuActive()  and (not glSet.hideDial[0] and 0 or not sampIsDialogActive()) end, function(player)
            imgui.PushStyleColor(imgui.Col.WindowBg, imgui.ImVec4(0, 0, 0, 0.0))
            imgui.PushStyleColor(imgui.Col.Border, imgui.ImVec4(0.0, 0.0, 0.0, 0.0))
            for k, v in pairs(glSet.gifs) do
                if tostring(data.imageName):find(tostring(v[6])) then
                    imgui.SetNextWindowPos(imgui.ImVec2(data.posX,data.posY), imgui.Cond.Always, imgui.ImVec2(0.5, 0.5))
                    if imgui.Begin("##gif"..index, nil, imgui.WindowFlags.AlwaysAutoResize + imgui.WindowFlags.NoDecoration) then
                        imgui.Image(ffi.cast("void*", v[1]:ProcessPlay()), imgui.ImVec2(data.sizeX, data.sizeY))
                        imgui.End()
                    end
                end
            end
            imgui.PopStyleColor(2)
        end).HideCursor = true
    end
end
-- Func
    addEventHandler('onWindowMessage', function(msg, key)
        if (glSet.movewin or glSet.movepic ~= -1) and msg == 0x0100 then
            if key == 0x20 then
                consumeWindowMessage(true, false)
            end
        end
    end)
    function checkImGif(imName,imType)
        if imType == 2 then
            if not resGif then
                sampAddChatMessage("{FF634F}[{ffffff}WaterMark{FF634F}]{FFFFFF} У вас нет {FF634F}GifPlayerLua{FFFFFF}. Скачайте его с бластхака или удалите гифки", -1)
            end
            gifHandle = gif.GifPlayer.new(glSet.path..imName)
            gifHandle:ToggleBg(false)
        end
        local set = {
            check = false,
            nTable = imType == 1 and glSet.images or imType == 2 and glSet.gifs,
            nHan = imType == 1 and renderLoadTextureFromFile(glSet.path..imName) or imType == 2 and gifHandle,
        }
        for index,data in pairs(wmJSON) do
            if data.imageName:find(imName) then
                set.check = true
                table.insert(set.nTable,{set.nHan, data.posX, data.posY, data.sizeX,data.sizeY, imName,data.status})
                break
            end
        end
        if not set.check then
            table.insert(wmJSON, {imageName = tostring(imName), posX = 500, posY = 500, sizeX = 200, sizeY = 200, status = true,}) save()
            table.insert(set.nTable,{set.nHan, 500,500,200,200, imName,true})
        end
    end
    function imgui.ColoredImageButton(image,sex,size)
        local bool = false
        for index, data in pairs(wmJSON) do
            if tostring(data.imageName):find(tostring(sex)) then bool = data.status end
        end
        imgui.PushStyleColor(imgui.Col.Button, imgui.ImVec4(bool and 0.2 or 0.98,bool and 0.8 or 0.26,bool and 0.2 or 0.26, 0.55))
        imgui.PushStyleColor(imgui.Col.ButtonHovered, imgui.ImVec4(bool and 0.2 or 0.98,bool and 0.8 or 0.26,bool and 0.2 or 0.26, 0.55))
        imgui.PushStyleColor(imgui.Col.ButtonActive, imgui.ImVec4(bool and 0.2 or 0.98,bool and 0.8 or 0.26,bool and 0.2 or 0.26, 0.55))
        local button = imgui.ImageButton(image, size)
        imgui.PopStyleColor(3)
        if imgui.IsItemClicked() then -- костыль для гифки
            for index, data in pairs(wmJSON) do
                if tostring(data.imageName):find(tostring(sex)) then data.status = not data.status save() end
            end
        end
        return button
    end
    function getFilesInPath(path, ftype)
        assert(path, '"path" is required');
        assert(type(ftype) == 'table' or type(ftype) == 'string', '"ftype" must be a string or array of strings');
        local result = {};
        for _, thisType in ipairs(type(ftype) == 'table' and ftype or { ftype }) do
            local searchHandle, file = findFirstFile(path.."\\"..thisType);
            table.insert(result, file)
            while file do file = findNextFile(searchHandle) table.insert(result, file) end
        end
        return result;
    end
    function save() json('watermark.json'):Save(wmJSON) end
    function imgui.Hint(arg)
        if imgui.IsItemHovered() then
            imgui.BeginTooltip()
            imgui.Text(u8(arg))
            imgui.EndTooltip()
        end
    end
    function imgui.CenterText(text)
        imgui.SetCursorPosX(imgui.GetWindowWidth()/2-imgui.CalcTextSize(u8(text)).x/2)
        imgui.Text(u8(text))
    end
    function imgui.TextColoredRGB(text)
        local style = imgui.GetStyle()
        local colors = style.Colors
        local ImVec4 = imgui.ImVec4

        local explode_argb = function(argb)
            local a = bit.band(bit.rshift(argb, 24), 0xFF)
            local r = bit.band(bit.rshift(argb, 16), 0xFF)
            local g = bit.band(bit.rshift(argb, 8), 0xFF)
            local b = bit.band(argb, 0xFF)
            return a, r, g, b
        end

        local getcolor = function(color)
            if color:sub(1, 6):upper() == 'SSSSSS' then
                local r, g, b = colors[1].x, colors[1].y, colors[1].z
                local a = tonumber(color:sub(7, 8), 16) or colors[1].w * 255
                return ImVec4(r, g, b, a / 255)
            end
            local color = type(color) == 'string' and tonumber(color, 16) or color
            if type(color) ~= 'number' then return end
            local r, g, b, a = explode_argb(color)
            return imgui.ImVec4(r/255, g/255, b/255, a/255)
        end

        local render_text = function(text_)
            for w in text_:gmatch('[^\r\n]+') do
                local text, colors_, m = {}, {}, 1
                w = w:gsub('{(......)}', '{%1FF}')
                while w:find('{........}') do
                    local n, k = w:find('{........}')
                    local color = getcolor(w:sub(n + 1, k - 1))
                    if color then
                        text[#text], text[#text + 1] = w:sub(m, n - 1), w:sub(k + 1, #w)
                        colors_[#colors_ + 1] = color
                        m = n
                    end
                    w = w:sub(1, n - 1) .. w:sub(k + 1, #w)
                end
                if text[0] then
                    for i = 0, #text do
                        imgui.TextColored(colors_[i] or colors[1], u8(text[i]))
                        imgui.SameLine(nil, 0)
                    end
                    imgui.NewLine()
                else imgui.Text(u8(w)) end
            end
        end

        render_text(text)
    end
    function theme()
        imgui.SwitchContext()
        local ImVec4 = imgui.ImVec4
        imgui.GetStyle().WindowPadding = imgui.ImVec2(5, 5)
        imgui.GetStyle().FramePadding = imgui.ImVec2(5, 5)
        imgui.GetStyle().ItemSpacing = imgui.ImVec2(5, 5)
        imgui.GetStyle().ItemInnerSpacing = imgui.ImVec2(2, 2)
        imgui.GetStyle().TouchExtraPadding = imgui.ImVec2(0, 0)
        imgui.GetStyle().IndentSpacing = 0
        imgui.GetStyle().ScrollbarSize = 10
        imgui.GetStyle().GrabMinSize = 10
        imgui.GetStyle().WindowBorderSize = 1
        imgui.GetStyle().ChildBorderSize = 1
        imgui.GetStyle().PopupBorderSize = 1
        imgui.GetStyle().FrameBorderSize = 1
        imgui.GetStyle().TabBorderSize = 1
        imgui.GetStyle().WindowRounding = 8
        imgui.GetStyle().ChildRounding = 8
        imgui.GetStyle().FrameRounding = 8
        imgui.GetStyle().PopupRounding = 8
        imgui.GetStyle().ScrollbarRounding = 8
        imgui.GetStyle().GrabRounding = 8
        imgui.GetStyle().TabRounding = 8
    
        imgui.GetStyle().Colors[imgui.Col.Text]                   = ImVec4(1.00, 1.00, 1.00, 1.00)
        imgui.GetStyle().Colors[imgui.Col.TextDisabled]           = ImVec4(0.50, 0.50, 0.50, 1.00)
        imgui.GetStyle().Colors[imgui.Col.WindowBg]               = ImVec4(0.06, 0.06, 0.06, 0.94)
        imgui.GetStyle().Colors[imgui.Col.ChildBg]                = ImVec4(1.00, 1.00, 1.00, 0.00)
        imgui.GetStyle().Colors[imgui.Col.PopupBg]                = ImVec4(0.08, 0.08, 0.08, 0.94)
        imgui.GetStyle().Colors[imgui.Col.Border]                 = ImVec4(0.43, 0.43, 0.50, 0.50)
        imgui.GetStyle().Colors[imgui.Col.BorderShadow]           = ImVec4(0.00, 0.00, 0.00, 0.00)
        imgui.GetStyle().Colors[imgui.Col.FrameBg]                = ImVec4(0.48, 0.16, 0.16, 0.54)
        imgui.GetStyle().Colors[imgui.Col.FrameBgHovered]         = ImVec4(0.98, 0.26, 0.26, 0.40)
        imgui.GetStyle().Colors[imgui.Col.FrameBgActive]          = ImVec4(0.98, 0.26, 0.26, 0.67)
        imgui.GetStyle().Colors[imgui.Col.TitleBg]                = ImVec4(0.04, 0.04, 0.04, 1.00)
        imgui.GetStyle().Colors[imgui.Col.TitleBgActive]          = ImVec4(0.48, 0.16, 0.16, 1.00)
        imgui.GetStyle().Colors[imgui.Col.TitleBgCollapsed]       = ImVec4(0.00, 0.00, 0.00, 0.51)
        imgui.GetStyle().Colors[imgui.Col.MenuBarBg]              = ImVec4(0.14, 0.14, 0.14, 1.00)
        imgui.GetStyle().Colors[imgui.Col.ScrollbarBg]            = ImVec4(0.02, 0.02, 0.02, 0.53)
        imgui.GetStyle().Colors[imgui.Col.ScrollbarGrab]          = ImVec4(0.31, 0.31, 0.31, 1.00)
        imgui.GetStyle().Colors[imgui.Col.ScrollbarGrabHovered]   = ImVec4(0.41, 0.41, 0.41, 1.00)
        imgui.GetStyle().Colors[imgui.Col.ScrollbarGrabActive]    = ImVec4(0.51, 0.51, 0.51, 1.00)
        imgui.GetStyle().Colors[imgui.Col.CheckMark]              = ImVec4(0.98, 0.26, 0.26, 1.00)
        imgui.GetStyle().Colors[imgui.Col.SliderGrab]             = ImVec4(0.88, 0.26, 0.24, 1.00)
        imgui.GetStyle().Colors[imgui.Col.SliderGrabActive]       = ImVec4(0.98, 0.26, 0.26, 1.00)
        imgui.GetStyle().Colors[imgui.Col.Button]                 = ImVec4(0.98, 0.26, 0.26, 0.40)
        imgui.GetStyle().Colors[imgui.Col.ButtonHovered]          = ImVec4(0.98, 0.26, 0.26, 1.00)
        imgui.GetStyle().Colors[imgui.Col.ButtonActive]           = ImVec4(0.98, 0.06, 0.06, 1.00)
        imgui.GetStyle().Colors[imgui.Col.Header]                 = ImVec4(0.98, 0.26, 0.26, 0.31)
        imgui.GetStyle().Colors[imgui.Col.HeaderHovered]          = ImVec4(0.98, 0.26, 0.26, 0.80)
        imgui.GetStyle().Colors[imgui.Col.HeaderActive]           = ImVec4(0.98, 0.26, 0.26, 1.00)
        imgui.GetStyle().Colors[imgui.Col.Separator]              = ImVec4(0.43, 0.43, 0.50, 0.50)
        imgui.GetStyle().Colors[imgui.Col.SeparatorHovered]       = ImVec4(0.75, 0.10, 0.10, 0.78)
        imgui.GetStyle().Colors[imgui.Col.SeparatorActive]        = ImVec4(0.75, 0.10, 0.10, 1.00)
        imgui.GetStyle().Colors[imgui.Col.ResizeGrip]             = ImVec4(0.98, 0.26, 0.26, 0.25)
        imgui.GetStyle().Colors[imgui.Col.ResizeGripHovered]      = ImVec4(0.98, 0.26, 0.26, 0.67)
        imgui.GetStyle().Colors[imgui.Col.ResizeGripActive]       = ImVec4(0.98, 0.26, 0.26, 0.95)
        imgui.GetStyle().Colors[imgui.Col.Tab]                    = ImVec4(0.98, 0.26, 0.26, 0.40)
        imgui.GetStyle().Colors[imgui.Col.TabHovered]             = ImVec4(0.98, 0.26, 0.26, 1.00)
        imgui.GetStyle().Colors[imgui.Col.TabActive]              = ImVec4(0.98, 0.06, 0.06, 1.00)
        imgui.GetStyle().Colors[imgui.Col.TabUnfocused]           = ImVec4(0.98, 0.26, 0.26, 1.00)
        imgui.GetStyle().Colors[imgui.Col.TabUnfocusedActive]     = ImVec4(0.98, 0.26, 0.26, 1.00)
        imgui.GetStyle().Colors[imgui.Col.PlotLines]              = ImVec4(0.61, 0.61, 0.61, 1.00)
        imgui.GetStyle().Colors[imgui.Col.PlotLinesHovered]       = ImVec4(1.00, 0.43, 0.35, 1.00)
        imgui.GetStyle().Colors[imgui.Col.PlotHistogram]          = ImVec4(0.90, 0.70, 0.00, 1.00)
        imgui.GetStyle().Colors[imgui.Col.PlotHistogramHovered]   = ImVec4(1.00, 0.60, 0.00, 1.00)
        imgui.GetStyle().Colors[imgui.Col.TextSelectedBg]         = ImVec4(0.98, 0.26, 0.26, 0.35)
    end