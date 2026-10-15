script_name("Salary")
script_authors("hijuce, mark, verbuk")
script_version("2.0")

enable = true
newbalance = 0

local oX = 5
local oY = 210

color = "0xFFFFD700"

function main()
    while not isSampAvailable() do wait(0) end
		userscreenX, userscreenY = getScreenResolution()
		sampAddChatMessage("{CC8C51}[Salary] {d5dedd}Скрипт активирован или баланс перезагружен. Автор: {CC8C51}hijuce., Verbuk", 0x01A0E9)
		sampRegisterChatCommand("salary.turn", function()
			enable = not enable
		end)
		sampRegisterChatCommand("salary.reset", function()
			local script = thisScript()
            script:reload()
		end)
		while true do
			if sampIsLocalPlayerSpawned() then
					oldMoney = getPlayerMoney(Player)
					while true do
						if oldMoney < getPlayerMoney(Player) then
							newbalance = getPlayerMoney(Player) - oldMoney
						elseif oldMoney > getPlayerMoney(Player) then
							newbalance = -oldMoney + getPlayerMoney(Player)
						end
						if enable == true then
							sampTextdrawCreate(223, "€apa—oЏok_џa_ceccњ”", oX, oY)
							sampTextdrawSetLetterSizeAndColor(223, 0.2, 1, 0xFFe1e1e1)
							sampTextdrawSetOutlineColor(223, 0.5, 0xFF000000)
							sampTextdrawSetAlign(223, 1)
							sampTextdrawSetStyle(223, 2)
							sampTextdrawCreate(224, newbalance, 6, 220)
							sampTextdrawSetLetterSizeAndColor(224, 0.3, 1.7, color)
							sampTextdrawSetOutlineColor(224, 0.5, 0xFF000000)
							sampTextdrawSetAlign(224, 1)
							sampTextdrawSetStyle(224, 2)
						elseif enable == false then
							sampTextdrawDelete(223)
							sampTextdrawDelete(224)
						end
						if newbalance >= 1 then
							color = "0xFF32CD32"
						elseif newbalance <= -1 then
							color = "0xFFB22222"
						elseif newbalance == 0 then
							color = "0xFFFFD700"
						end
					  wait(0)
					end
			end
			wait(0)
		end
end