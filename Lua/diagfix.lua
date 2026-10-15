local sampev = require 'lib.samp.events'

local id = 1488

function sampev.onShowDialog(dialogId, style, title, button1, button2, text)
    if dialogId == 19999 or (dialogId == 0 and title:find("Этот аккаунт заблокирован")) then
        local dStyle, dTitle, dB1, dB2, dText = style, title, button1, button2, text

        lua_thread.create(function()
            wait(300)
            sampShowDialog(id, dTitle, dText, dB1, dB2, dStyle)
        end)
        
        return false
    end
end