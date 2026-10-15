script_name('MapPodarki')
script_author('HarikAng')

local state = false
local radius = 5000
-- Для ПК версии цвет меток задается через игровой ID (3 - синий, 2 - зеленый, 1 - красный)
local blipColor = 2 -- Изменил на зеленый, чтобы визуально отличался от укропа
local pool = {}

function main()
	while not isSampAvailable() do wait(100) end
	sampAddChatMessage(' >>{FFFFFF} Скрипт на подарки активирован | {FF7070}Команда: /rppod', 0xFF7070)
	sampRegisterChatCommand('rppod', function() 
		state = not state
		printStyledString(state and '~g~ON' or '~r~OFF', 1000, 6)
		if not state then remove_all() end
	end)
	addEventHandler('onScriptTerminate', function(script, quit)
		if script == thisScript() then
			remove_all()
		end
	end)
	while true do
		if state then
			local myX, myY, myZ = getCharCoordinates(PLAYER_PED)
			for i, B in ipairs(coords) do
				local dist = getDistanceBetweenCoords3d(myX, myY, myZ, B[1], B[2], B[3])
				if dist <= radius and pool[i] == nil then
					pool[i] = addBlipForCoord(B[1], B[2], B[3])
					changeBlipColour(pool[i], blipColor)
				elseif dist > radius and pool[i] ~= nil then
					removeBlip(pool[i])
					pool[i] = nil
				end
			end
		end
		wait(0)
	end
end

function remove_all()
	for i = 1, #coords do
		if pool[i] ~= nil then
			removeBlip(pool[i])
			pool[i] = nil
		end
	end
end

coords = {
    { -79.74, -1552.09, 1.61 },
    { -1715.23, 394.07, 6.18 },
    { -1520.32, 2572.53, 54.84 },
    { -2084.52, 62.20, 33.42 },
    { -2133.10, 174.52, 34.31 },
    { -2102.55, 654.57, 51.37 },
    { -1949.50, 792.37, 54.72 },
    { -1980.59, 884.79, 44.20 },
    { -1705.20, 1222.28, 29.08 },
    { -1556.53, 968.99, 6.27 },
    { -1496.46, 590.32, 41.26 },
    { 2074.26, 1786.78, 9.82 },
    { 2249.12, 2255.41, 9.82 },
    { 1599.32, -1780.98, 12.44 },
    { 2641.56, 1603.39, 9.82 },
    { 2177.47, 2049.24, 15.32 },
    { 2013.58, 2342.81, 9.82 },
    { 2060.67, 2435.75, 18.42 },
    { 1765.95, 2793.28, 7.34 },
    { 2209.72, 2744.23, 9.82 },
    { 1594.26, 1170.62, 13.22 },
    { 1787.81, 349.06, 18.03 },
    { 378.24, -1308.38, 13.74 },
    { 816.01, -1096.52, 24.79 },
    { 1990.58, -2063.77, 12.37 },
    { -2318.09, 324.29, 38.24 }
}