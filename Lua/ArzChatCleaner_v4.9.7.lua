script_name('ArzChatCleaner')
script_author('Спасибо за пирог')
script_version('4.9.7')
script_moonloader(26)

require 'lib.moonloader'
local sampev = require 'lib.samp.events'
local encoding = require 'encoding'
encoding.default = 'CP1251'
local u8 = encoding.UTF8
local inicfg = require 'inicfg'
local imgui = require 'mimgui'
local ffi = require 'ffi'

local winApiLoaded, kernel32 = pcall(ffi.load, 'kernel32')
local function hasWinMoveApi()
    if not winApiLoaded or not kernel32 then return false end
    local okMove,move=pcall(function() return kernel32.MoveFileExA end)
    local okError,getLastError=pcall(function() return kernel32.GetLastError end)
    return okMove and move~=nil and okError and getLastError~=nil
end
local winApiReady=hasWinMoveApi()
if not winApiReady then
    pcall(ffi.cdef, [[
        int __stdcall MoveFileExA(const char *lpExistingFileName, const char *lpNewFileName, unsigned long dwFlags);
        unsigned long __stdcall GetLastError(void);
    ]])
    winApiReady=hasWinMoveApi()
end
local MOVEFILE_REPLACE_EXISTING = 0x1
local MOVEFILE_WRITE_THROUGH = 0x8

local APP = {name='ArzChatCleaner', displayName='Arizona RP — Очистка чата', version='4.9.7'}
local CONFIG_NAME = 'arz_chat_cleaner.ini'
local CONFIG_DIR = getWorkingDirectory() .. '/config'
local CONFIG_FILE = CONFIG_DIR .. '/' .. CONFIG_NAME
local CUSTOM_FILE = CONFIG_DIR .. '/arz_cleaner_custom.json'
local UNKNOWN_FILE = CONFIG_DIR .. '/arz_chat_cleaner_unknown.log'
local JOURNAL_LIMIT, LEARNING_LIMIT, LOG_LIMIT = 250, 150, 512 * 1024

local defaults = {settings={
    enabled=true, block_trade_all=true, block_trade_adv_tags=true, block_trade_calls=true,
    block_trade_lavka=true, block_trade_buy=true, block_trade_sell=true, block_trade_rent=true,
    block_trade_invites=true, block_trade_exchange=true, block_hints=true, block_luck=true,
    block_game_events=true, block_family_wars=true, block_veh_spawn=true, block_org_notifs=true,
    block_donate=true, block_gov=true, block_routine_actions=true, block_admin_announcements=true,
    block_empty_lines=true, block_restarts=false, block_auction=false, block_custom=true,
    capture_unknown=false, learning_enabled=false
}}

local function clone(t)
    local out = {}
    for k,v in pairs(t) do out[k] = type(v)=='table' and clone(v) or v end
    return out
end

local Storage = {error=nil}
function Storage.ensureDir()
    if not doesDirectoryExist(CONFIG_DIR) then createDirectory(CONFIG_DIR) end
end
function Storage.read(path)
    local f,err = io.open(path, 'rb')
    if not f then return nil,err end
    local data,readErr = f:read('*a')
    f:close()
    return data,readErr
end
function Storage.write(path, content)
    local f,err = io.open(path, 'wb')
    if not f then return false,err end
    local ok,res,msg = pcall(f.write, f, content)
    if not ok or not res then f:close(); return false,tostring(msg or res) end
    local flushed,flushErr = f:flush()
    local closed,closeErr = f:close()
    if not flushed or not closed then return false,flushErr or closeErr end
    return true
end
function Storage.copy(from, to)
    local data,err = Storage.read(from)
    if data==nil then return false,err end
    return Storage.write(to, data)
end
function Storage.unique(path,extension)
    extension=extension or ''
    local base = path .. '-' .. os.date('%Y%m%d-%H%M%S')
    local out,i = base..extension,0
    while doesFileExist(out) do i=i+1; out=base .. '-' .. i .. extension end
    return out
end
function Storage.atomic(path, content)
    Storage.ensureDir()
    local temp,backup = path .. '.tmp',path .. '.bak'
    local ok,err = Storage.write(temp, content)
    if not ok then return false,err end
    local existed = doesFileExist(path)
    if existed then
        ok,err = Storage.copy(path, backup)
        if not ok then os.remove(temp); return false,err end
    end

    if winApiReady then
        local flags = MOVEFILE_WRITE_THROUGH
        if existed then flags = flags + MOVEFILE_REPLACE_EXISTING end
        local callOk,moved=pcall(function() return kernel32.MoveFileExA(temp,path,flags) end)
        if callOk and moved~=0 then return true end
        if not callOk then return false,'Ошибка вызова MoveFileExA: '..tostring(moved) end
        local errOk,winError=pcall(function() return tonumber(kernel32.GetLastError()) end)
        return false,'MoveFileExA error '..tostring(errOk and winError or 'unknown')
    end

    if existed then
        return false,'MoveFileExA недоступен; существующий файл оставлен без изменений. Новые данные сохранены во временном файле: '..temp
    end
    ok,err = os.rename(temp, path)
    if ok then return true end
    return false,'MoveFileExA недоступен; не удалось создать файл через os.rename: '..tostring(err or 'неизвестная ошибка')
end

local loaded,ini = pcall(inicfg.load, clone(defaults), CONFIG_NAME)
local iniLoadError = not loaded or type(ini)~='table' or type(ini.settings)~='table'
if iniLoadError then ini=clone(defaults) end
for key,default in pairs(defaults.settings) do
    local current=ini.settings[key]
    if current=='true' then current=true elseif current=='false' then current=false end
    ini.settings[key]=type(current)==type(default) and current or default
end

local removedLegacyUiScale = ini.settings.ui_scale ~= nil
ini.settings.ui_scale = nil

if ini.settings.capture_unknown then ini.settings.learning_enabled=true end

local function saveSettings()
    Storage.ensureDir()
    if iniLoadError and doesFileExist(CONFIG_FILE) then
        local ok,err=Storage.copy(CONFIG_FILE,Storage.unique(CONFIG_FILE .. '.broken'))
        if not ok then Storage.error='Не удалось сохранить копию INI: '..tostring(err); return false end
        iniLoadError=false
    end
    local tempName='arz_chat_cleaner_pending.ini'
    local called,result=pcall(inicfg.save,ini,tempName)
    local data=called and result~=false and Storage.read(CONFIG_DIR .. '/' .. tempName) or nil
    if not data then Storage.error='Не удалось записать настройки.'; return false end
    local ok,err=Storage.atomic(CONFIG_FILE,data)
    os.remove(CONFIG_DIR .. '/' .. tempName)
    Storage.error=not ok and ('Настройки не сохранены: '..tostring(err)) or nil
    return ok
end

local saveState={dirty=false,due=0}
local function requestSave()
    saveState.dirty=true
    saveState.due=os.clock()+1
end
local function flushSettings(force)
    if not saveState.dirty then return true end
    if not force and os.clock()<saveState.due then return true end
    saveState.dirty=false
    return saveSettings()
end

local Text = {}
function Text.cp1251Lower(text)
    return (text or ''):gsub('.',function(c)
        local b=c:byte()
        if b>=192 and b<=223 then return string.char(b+32) end
        if b==168 then return string.char(184) end
        if b>=65 and b<=90 then return string.char(b+32) end
        return c
    end)
end

function Text.patternLower(p)
    local out,i={},1
    while i<=#p do
        local c=p:sub(i,i)
        if c=='%' then out[#out+1]=p:sub(i,i+1); i=i+2
        else out[#out+1]=Text.cp1251Lower(c); i=i+1 end
    end
    return table.concat(out)
end
function Text.stripColors(text)
    return (text or ''):gsub('{%x%x%x%x%x%x%x%x}',''):gsub('{%x%x%x%x%x%x}','')
end
function Text.trim(s) return (s or ''):gsub('^%s+',''):gsub('%s+$','') end
function Text.normalize(text)
    return Text.cp1251Lower(Text.trim(Text.stripColors(text):gsub(string.char(160),' '):gsub('[%s%z]+',' ')))
end
function Text.utf8Char(cp)
    if cp<128 then return string.char(cp) end
    if cp<2048 then return string.char(192+math.floor(cp/64),128+cp%64) end
    if cp<65536 then return string.char(224+math.floor(cp/4096),128+math.floor(cp/64)%64,128+cp%64) end
    return string.char(240+math.floor(cp/262144),128+math.floor(cp/4096)%64,128+math.floor(cp/64)%64,128+cp%64)
end
function Text.utf8At(s,i)
    local b=s:byte(i)
    if not b then return nil,0 end
    if b<128 then return b,1 end
    local n=(b>=194 and b<=223 and 2) or (b>=224 and b<=239 and 3) or (b>=240 and b<=244 and 4)
    if not n or i+n-1>#s then return nil,1 end
    local cp=b%(2^(7-n))
    for j=i+1,i+n-1 do
        local c=s:byte(j)
        if c<128 or c>191 then return nil,1 end
        cp=cp*64+c-128
    end
    if cp<(n==2 and 128 or n==3 and 2048 or 65536) or cp>0x10FFFF or
       (cp>=0xD800 and cp<=0xDFFF) then return nil,1 end
    return cp,n
end

local utf8ToCp={}
for b=128,255 do
    local ok,s=pcall(function() return u8:encode(string.char(b)) end)
    if ok and s and s~='' and s~='?' and s~='\239\191\189' then utf8ToCp[s]=string.char(b) end
end
function Text.fromUtf8(s)
    local out,i={},1
    while i<=#s do
        local cp,n=Text.utf8At(s,i)
        if not cp then return nil,'Некорректный UTF-8.' end
        local char=s:sub(i,i+n-1)
        out[#out+1]=cp<128 and char or utf8ToCp[char] or string.format(':u%x:',cp)
        i=i+n
    end
    return table.concat(out)
end
function Text.canonicalCp(raw)
    local out,i={},1
    while i<=#raw do
        local b=raw:byte(i)
        local cp,n
        if b>=224 and b<=244 then cp,n=Text.utf8At(raw,i) end

        if cp and cp>=0xE000 then
            out[#out+1]=string.format(':u%x:',cp); i=i+n
        else out[#out+1]=raw:sub(i,i); i=i+1 end
    end
    return table.concat(out)
end
function Text.display(cp)
    cp=Text.canonicalCp(cp or '')
    local ok,s=pcall(function() return u8:encode(cp) end)
    if ok and type(s)=='string' then return s end
    return (cp:gsub('[\128-\255]',function(c) return string.format('\\x%02X',c:byte()) end))
end
function Text.preview(cp,n)
    n=n or 85
    return Text.display(#cp>n and cp:sub(1,n-3)..'...' or cp)
end
function Text.toCpLowerList(list)
    local out={}
    for i=1,#list do out[i]=Text.normalize(assert(Text.fromUtf8(list[i]))) end
    return out
end
function Text.containsAny(s,list)
    for i=1,#list do if s:find(list[i],1,true) then return true,list[i] end end
    return false
end
function Text.wordSet(list)
    local out={}
    for i=1,#list do out[list[i]]=true end
    return out
end
function Text.tokenize(s)
    local out={}
    s=s:gsub(':[%w_]+:',' '):gsub('[%[%]%(%){}<>/\\|,%.:;%-%+%!%?%*="\'`_]',' '):gsub(string.char(185),' ')
    for w in s:gmatch('%S+') do out[#out+1]=w end
    return out
end
function Text.color(color)
    if type(color)~='number' then return 'не задан' end
    return string.format('0x%08X',color%4294967296)
end
function Text.utf8Length(s)
    local i,n=1,0
    while i<=#s do
        local cp,size=Text.utf8At(s,i)
        if not cp then return nil end
        i=i+size; n=n+1
    end
    return n
end
function Text.buffer(buffer,s)
    local max=ffi.sizeof(buffer)-1
    if #s>max then
        local i,last=1,0
        while i<=#s do
            local _,n=Text.utf8At(s,i)
            if i+n-1>max then break end
            last=i+n-1; i=i+n
        end
        s=s:sub(1,last)
    end
    ffi.fill(buffer,ffi.sizeof(buffer),0)
    ffi.copy(buffer,s,#s)
end

local restoring=false
local function chatMsg(text,color)
    local cp=Text.fromUtf8('{BB86FC}[ArzCleaner]{FFFFFF} '..text)
    local prior=restoring
    restoring=true
    pcall(sampAddChatMessage,cp or text,color or -1)
    restoring=prior
end

local SOURCE = {
    trade_tags = {
        '[vip adv]', '[premium adv]', '[forever adv]', '[реклама] [vip]', '[vip объявление]'
    },
    trade_adv_phrases = {
        '/gomp'
    },
    trade_lavka = {
        'по низу рынка', 'по верху рынка', 'по лоу',
        'сливаю склад', 'успей закупиться', 'самый дорогой скуп', 'в одной лавке'
    },
    trade_invites = {
        'инвайчу в', 'инвайт в', 'набор в семью', 'набор в фаму', 'набор в full',
        'продаю ранг', 'продам ранг', 'покупай ранг', 'в продаже ранг',
        'в продаже 6-ой', 'в продаже 7-ой', 'в продаже 8-ой', 'идет набор в'
    },
    trade_buy_words = {'куплю', 'скуплю', 'скупаю', 'закупаю', 'покупаю', 'приобрету'},
    trade_sell_words = {'продам', 'продаю', 'распродаю', 'сливаю', 'реализую'},
    trade_rent_words = {'сдам', 'сдаю', 'арендую', 'сниму'},
    trade_exchange_words = {'обменяю', 'меняю', 'махну'},
    trade_rent_phrases = {'возьму в аренду', 'сдам в аренду', 'ищу в аренду'},
    trade_exchange_phrases = {
        'ищу зама', 'нужен зам', 'ищу подселение', 'подселю',
        'работает 165 бар', 'работает 51 бар', 'работает казино'
    },
    hints = {
        '[подсказка]', '[item market]', '[arizona rent]', '[хранилище предметов]',
        '[кинотеатр azmax]', '[рабочая акция]', '[аэропорт лос сантос]',
        'с помощью телефона можно заказать такси', 'среднее время ожидания',
        'трудовой книжкой', '/wbook', 'бушует торнадо',
        'обратите внимание! вы можете улучшить свои характеристики',
        'списанный бронежилет на ', 'склад списанных бронежилетов'
    },
    luck = {
        '[удача]', '[лотерейная]', '[рыбалка]', 'выиграл легендарный приз',
        'купить лотерейные билеты можно в уличных киосках нашего штата или в самой лотерейной',
        'купить лотерейные билеты можно', 'мероприятия - лотерейная',
        'выиграл редкий приз', 'выиграл супер приз', 'выиграл главный приз',
        'выбил из ларца', 'забрал сгоревший приз',
        'испытал удачу при открытии'
    },
    game_events = {
        '[game event]', '[event]', '[операция мираж]', '[безумная охота]',
        '[контейнеры]', '[кладоискатели]', '[собиратели]', '[глобальное мероприятие]',
        '[распродажа]', '[зловещая экспедиция]', '[зловещий дворец]',
        '[лагерь бандитов]', '[подземная шахта]', '[pubg]', 'победитель мп',
        'победитель мероприятия', '/gotp', 'турнир был завершен',
        'авария с крушением самолета', 'распродажа нефти', '[гонка вооружений]',
        'уже через 5 минут начинается распродажа одежды в секонд-хенде',
        'начинается распродажа одежды в секонд-хенде'
    },
    family_wars = {'[family war]'},
    veh_spawn = {'[спавн транспорта]'},
    org_notifs = {'[организация]', '[сбор средств]', '[слив информации]'},
    donate = {
        'в нашем магазине ты можешь приобрести', 'в нашем магазине вы можете приобрести',
        'в нашем магазине можно приобрести', 'пополнить счет можно на официальном сайте',
        'пополнить счет можно на сайте', '/donate', 'действует акция x4 донат',
        'действует акция х4 донат', 'включен x4 payday', 'включен х4 payday',
        'включен x3 payday', 'titan vip', 'premium vip', 'донат-меню',
        'донат-магазине', 'боевой пропуск', 'battlepass', '/present',
        'активируйте промокод', 'вводите промокод', 'vk.com/arizona',
        't.me/arizona', 'разработчик arizona games',
        'их на желаемый тобой бизнес, дом, акссесуар',
        'их на желаемый тобой бизнес, дом, аксессуар',
        'или на покупку каких-нибудь безделушек',
        'игроки со статусом vip имеют большие возможности',
        'игроки со статусом vip имеют больше возможностей',
        'в магазине так-же можно приобрести редкие автомобили',
        'в магазине также можно приобрести редкие автомобили',
        'а так-же предметы, которые выделят тебя',
        'предметы, которые выделят тебя из толпы',
        'наш сайт: arizona-rp.com',
        'этот тип недвижимости будет навсегда закреплен за вами',
        'за него не нужно платить',
        'таким образом вы можете сберечь своё имущество',
        'таким образом вы можете сберечь свое имущество'
    },
    gov = {
        'уважаемые жители штата! минуточку внимания', 'уважаемые жители штата',
        'проходит собеседование в организацию', 'проходит собеседование в',
        'для вступления необходимо прибыть', 'собеседование окончено',
        'собеседование завершено', 'собеседование продолжается', 'гос.новости',
        'государственные новости', 'день открытых дверей', 'открыта заявка на пост',
        'на форуме открыты заявки на пост', 'обзвон на',
        'вышел при попытке избежать ареста и был наказан'
    },
    routine_actions = {
        'скушал(а) пачку чипсов', 'автоматически надел бронежилет',
        'скушал(а) жареное мясо оленины', 'достал(а) из мешка за спиной',
        'переодевается в рабочую одежду.', 'переодевается в гражданскую одежду.'
    },
    admin_announcements = {
        'здравствуйте уважаемые игроки',
        'на нашем сервере открыты заявки на пост администратора',
        'требования к кандидатам:', 'ждём ваших заявок', 'ждем ваших заявок',
        'обзвон состоится', 'подать анкету можно тут'
    },
    restarts = {
        'пройдет технический рестарт', 'технический рестарт сервера',
        'disconnect: connection mode', 'сервер закрыл соединение. переподключение'
    },
    auction = {'[аукцион]'}
}

local categoryDefs = {
    {key='block_hints', id='hints', title='Подсказки и приложения', desc='[Подсказка], Item Market, Arizona Rent, Хранилище, рабочие акции, аэропорт и склад бронежилетов'},
    {key='block_luck', id='luck', title='Ларцы и выигрыши', desc='[Удача], рулетки, подарки, лотерея/рыбалка, результаты с AZ Coins, получение транспорта и легендарное качество'},
    {key='block_game_events', id='game_events', title='Мероприятия и ивенты', desc='[Game Event], /gotp, экспедиции, победители МП'},
    {key='block_family_wars', id='family_wars', title='Войны семей', desc='Сообщения с меткой [Family War]'},
    {key='block_veh_spawn', id='veh_spawn', title='Спавн транспорта', desc='Сообщения с меткой [Спавн Транспорта]'},
    {key='block_org_notifs', id='org_notifs', title='Уведомления организаций', desc='[Организация], сбор средств, слив информации'},
    {key='block_donate', id='donate', title='Магазин, донат и промо', desc='/donate, /present, VIP, Battle Pass, промокоды'},
    {key='block_gov', id='gov', title='Гос. сообщения, аресты и собеседования', desc='Гос.Новости, собеседования, дни открытых дверей и системные сообщения об арестах'},
    {key='block_routine_actions', id='routine_actions', title='Еда, одежда и бронежилет', desc='Бытовые системные действия: еда, мешок за спиной, переодевание, автоэкипировка брони'},
    {key='block_admin_announcements', id='admin_announcements', title='Объявления администраторов', desc='Любые общие сообщения, начинающиеся с «Администратор Nick_Name:»'},
    {key='block_restarts', id='restarts', title='Рестарты и отключения', desc='Важные технические сообщения; по умолчанию выключено'},
    {key='block_auction', id='auction', title='Глобальные сообщения аукциона', desc='Метка [Аукцион]; личные действия сохраняются'}
}

-- Optional data-only updates: config/arz_cleaner_rules.json can ADD phrases to any
-- built-in list, e.g. {"extend":{"hints":["[новая метка]"],"donate":["..."]}}.
-- Built-in rules stay in the script as the fallback; a broken file is ignored.
local RULES_FILE = CONFIG_DIR .. '/arz_cleaner_rules.json'
local RulesFile={error=nil,added=0,skipped=0}
function RulesFile.apply(data,source)
    local report={added=0,skipped=0}
    if type(data)~='table' or type(data.extend)~='table' then
        return nil,'Ожидается объект {"extend":{"категория":["фраза",...]}}.'
    end
    for key,phrases in pairs(data.extend) do
        if type(key)~='string' or type(source[key])~='table' or type(phrases)~='table' then
            report.skipped=report.skipped+1
        else
            local have={}
            for _,v in ipairs(source[key]) do have[Text.normalize(assert(Text.fromUtf8(v)))]=true end
            for _,phrase in ipairs(phrases) do
                local cp=type(phrase)=='string' and #phrase<=200 and Text.fromUtf8(phrase)
                local norm=cp and Text.normalize(cp)
                if norm and (Text.utf8Length(Text.trim(phrase)) or 0)>=4 and not have[norm] then
                    source[key][#source[key]+1]=phrase; have[norm]=true
                    report.added=report.added+1
                else report.skipped=report.skipped+1 end
            end
        end
    end
    return report
end
function RulesFile.load(source)
    if not doesFileExist(RULES_FILE) then return end
    local content=Storage.read(RULES_FILE)
    local ok,data=false,nil
    if content then ok,data=pcall(decodeJson,content) end
    if not ok then RulesFile.error='arz_cleaner_rules.json не читается; используются встроенные правила.'; return end
    local called,report,message=pcall(RulesFile.apply,data,source)
    if not called or not report then
        RulesFile.error='arz_cleaner_rules.json: '..tostring(called and message or report)..' Используются встроенные правила.'
        return
    end
    RulesFile.added,RulesFile.skipped=report.added,report.skipped
end
RulesFile.load(SOURCE)

local CP={}
for key,list in pairs(SOURCE) do CP[key]=Text.toCpLowerList(list) end

-- Vehicle-reward lines: "Игрок <ник>(<id>) получил на транспорт <модель>" and
-- lines starting with "Легендарное качество". Named on purpose: the old code
-- addressed these phrases by list index.
local function cpNormalized(text) return Text.normalize(assert(Text.fromUtf8(text))) end
local VEHICLE={
    player=cpNormalized('игрок'),
    received=cpNormalized('получил на транспорт'),
    legendary=cpNormalized('легендарное качество')
}

-- Only these four advertising plates are confirmed by the supplied v4.5 data.
-- Unverified legacy U+F229/U+F22A/U+F236 aliases are intentionally not ad rules.
local VIP_AD_BADGE_CODEPOINTS={0x1FC29,0x1FC2A,0x1FC2B,0x1FC36}

local Custom={block={},allow={},players={},cache={block={},allow={},players={},blockRe={},allowRe={}},
              error=nil,backup=nil,extra={},patternError=nil}

-- Advanced rules: a value starting with "re:" is a Lua pattern (not a PCRE),
-- matched case-insensitively against the cleaned message text.
local PATTERN_PREFIX='re:'
local PATTERN_MAX_BYTES,PATTERN_MAX_QUANTIFIERS,PATTERN_MIN_LITERALS=200,2,4
function Custom.isPattern(value)
    return type(value)=='string' and value:sub(1,#PATTERN_PREFIX):lower()==PATTERN_PREFIX
end
function Custom.compilePattern(value)
    local body=Text.trim(value:sub(#PATTERN_PREFIX+1))
    if body=='' then return nil,'После re: нужен паттерн.' end
    if #body>PATTERN_MAX_BYTES then return nil,'Паттерн длиннее '..PATTERN_MAX_BYTES..' байт.' end
    local cp,err=Text.fromUtf8(body)
    if not cp then return nil,err end
    local pat=Text.patternLower(cp)
    -- Malformed patterns only raise when the matcher reaches the bad part, so
    -- probe with several strings, including the pattern text itself.
    for _,probe in ipairs({'','a',' :u1fc29: nick_name[1]: 123 abc',pat}) do
        local ok,res=pcall(string.find,probe,pat)
        if not ok then return nil,'Некорректный Lua-паттерн: '..tostring(res) end
    end
    if string.find('',pat) then return nil,'Паттерн совпадает с пустой строкой и скрыл бы весь чат.' end
    -- Rough guard against catastrophic backtracking: bound the unbounded quantifiers.
    local bare=pat:gsub('%%.',''):gsub('%b[]','')
    local _,quantifiers=bare:gsub('[%*%+%-]','')
    if quantifiers>PATTERN_MAX_QUANTIFIERS then
        return nil,'Слишком много *, + и - (максимум '..PATTERN_MAX_QUANTIFIERS..'): паттерн может подвесить игру.'
    end
    local _,literals=bare:gsub('[%w\128-\255]','')
    if literals<PATTERN_MIN_LITERALS then
        return nil,'В паттерне должно быть минимум '..PATTERN_MIN_LITERALS..' обычных символа.'
    end
    return pat
end
-- Returns the matching pattern or nil. A pattern that raises at match time is
-- dropped from the live cache (it returns on the next rebuild) and reported.
function Custom.matchPatterns(text,list)
    if not list then return nil end
    local i=1
    while i<=#list do
        local ok,res=pcall(string.find,text,list[i])
        if not ok then
            Custom.patternError='Паттерн отключён из-за ошибки выполнения: '..Text.display(list[i])
            table.remove(list,i)
        elseif res then return list[i]
        else i=i+1 end
    end
end
function Custom.rebuild()
    Custom.cache={block={},allow={},players={},blockRe={},allowRe={}}
    for _,kind in ipairs({'block','allow','players'}) do
        local seen={}
        for _,value in ipairs(Custom[kind]) do
            if kind~='players' and Custom.isPattern(value) then
                local pat=Custom.compilePattern(value)
                if pat and not seen['re:'..pat] then
                    local list=Custom.cache[kind..'Re']
                    list[#list+1]=pat; seen['re:'..pat]=true
                end
            else
                local cp=Text.fromUtf8(value)
                cp=cp and Text.normalize(cp)
                if cp and cp~='' and not seen[cp] then
                    if kind=='players' then Custom.cache.players[cp]=true
                    else Custom.cache[kind][#Custom.cache[kind]+1]=cp end
                    seen[cp]=true
                end
            end
        end
    end
    Custom.patternError=nil
end
function Custom.load()
    Custom.block,Custom.allow,Custom.players,Custom.extra={},{},{},{}
    Custom.error,Custom.backup=nil,nil
    if not doesFileExist(CUSTOM_FILE) then Custom.rebuild(); return end
    local content=Storage.read(CUSTOM_FILE)
    local ok,data=false,nil
    if content then ok,data=pcall(decodeJson,content) end
    if not ok or type(data)~='table' then
        Custom.error='Файл правил не читается или JSON повреждён. Перед записью обязательна резервная копия.'
        Custom.rebuild(); return
    end
    local structured=data.block~=nil or data.allow~=nil or data.players~=nil
    if structured then Custom.extra=clone(data) end
    local function take(src,dest)
        if src==nil then return end
        if type(src)~='table' then Custom.error='Некорректная структура JSON; исходник будет сохранён отдельно.'; return end
        for k,v in pairs(src) do
            if type(k)~='number' or k<1 or k%1~=0 or k>#src or type(v)~='string' then
                Custom.error='В JSON есть неподдерживаемые значения; перед записью будет сохранён исходник.'
            end
        end
        for i=1,#src do
            if type(src[i])=='string' then
                dest[#dest+1]=src[i] -- Keep old short rules and original text intact.
                if not Text.fromUtf8(src[i]) then Custom.error='В JSON есть текст с неверной кодировкой; исходник будет сохранён.' end
            end
        end
    end
    if structured then
        take(data.block,Custom.block); take(data.allow,Custom.allow); take(data.players,Custom.players)
    else take(data,Custom.block) end
    Custom.rebuild()
end
function Custom.save()
    if Custom.error and doesFileExist(CUSTOM_FILE) and not Custom.backup then
        local path=Storage.unique(CUSTOM_FILE..'.broken','.bak')
        local ok,err=Storage.copy(CUSTOM_FILE,path)
        if not ok then return false,'Не удалось создать копию повреждённого JSON: '..tostring(err) end
        Custom.backup=path
    end
    local data=clone(Custom.extra)
    data.block, data.allow, data.players=Custom.block,Custom.allow,Custom.players
    local ok,payload=pcall(encodeJson,data)
    if not ok or type(payload)~='string' then return false,'Не удалось подготовить JSON.' end
    local saved,err=Storage.atomic(CUSTOM_FILE,payload)
    if not saved then return false,'Не удалось сохранить правила: '..tostring(err) end
    Custom.error=nil; Custom.rebuild()
    return true
end
function Custom.validNick(nick)
    return #nick>=3 and #nick<=32 and nick:match('^[A-Za-z0-9]+_[A-Za-z0-9_]+$')~=nil
end
function Custom.put(kind,value,index)
    local list=Custom[kind]
    if not list then return false,'Неизвестный тип правила.' end
    value=Text.trim(value)
    local cp,err=Text.fromUtf8(value)
    if not cp then return false,err end
    local clean=Text.normalize(cp)
    if clean=='' then return false,'Введите непустую фразу.' end
    if kind=='players' then
        if not Custom.validNick(value) then return false,'Нужен точный ник, например Test_Test.' end
    elseif Custom.isPattern(value) then
        local pat,perr=Custom.compilePattern(value)
        if not pat then return false,perr end
    elseif #clean<4 or (Text.utf8Length(value) or 0)<4 then
        return false,'Минимум 4 символа. Лучше указать устойчивую фразу из нескольких слов.'
    end
    if #value>500 then return false,'Максимум 500 байт UTF-8: сократите фразу.' end
    for i,v in ipairs(list) do
        local other=Text.fromUtf8(v)
        if i~=index and other and Text.normalize(other)==clean then return false,'Такое правило уже существует.' end
    end
    local at=index or #list+1
    if index and not list[index] then return false,'Правило больше не существует.' end
    local old=list[at]
    list[at]=value
    local ok,why=Custom.save()
    if not ok then list[at]=old; Custom.rebuild(); return false,why end
    return true
end
function Custom.remove(kind,index)
    local value=table.remove(Custom[kind],index)
    local ok,err=Custom.save()
    if not ok then table.insert(Custom[kind],index,value); Custom.rebuild() end
    return ok,err
end

local ArizonaTokenParser={}
local tokenNames={buy=true,sell=true,trade=true,rent=true,lavka=true,slot=true,house=true,biz=true,call=true}
function ArizonaTokenParser.parse(clean)
    local result={unknown={}}
    for full,name,id in clean:gmatch('(:([a-z]+)(%d*):)') do
        if tokenNames[name] then
            local numbered=name=='lavka' or name=='slot' or name=='house' or name=='biz' or name=='call'
            local valid=numbered and (#id>0 or name=='lavka' or name=='call') or (not numbered and id=='')
            if valid and not result[name] then
                result[name]=true; result[name..'Token']=full
                if id~='' then result[name..'Id']=id end -- Keep large identifiers exact.
            end
        elseif #name>=3 then result.unknown[#result.unknown+1]=full end
    end
    return result
end

local channels=Text.wordSet(Text.toCpLowerList({
    '[vip]','[premium]','[forever]','[vip adv]','[premium adv]','[forever adv]',
    '[реклама]','[vip объявление]','[ooc]','[ic]','[рация]','[семья]','[фракция]',
    '[администрация]','[админ]','[шепот]','[крик]'
}))
local personalTags=Text.wordSet(Text.toCpLowerList({'[информация]','[аукцион]','[уведомление]','[банк]','[предметы]'}))
local personalPhrases=Text.toCpLowerList({
    'вы получили','вы приобрели','вы купили','вы продали','вы активировали','вы использовали',
    'вы переместили','вы перевели','вы выполнили','вы открыли','вы выставили','вы успешно',
    'вы забрали','вы обменяли','вы оплатили','вы пополнили','вы сняли','вы арендовали',
    'вам начислено','вам начислен','вам начислена','вам начислены','вам выдано','вам выдан',
    'вам выдана','вам выданы','вам перечислено','вам переведено'
})
local negations=Text.wordSet(Text.toCpLowerList({'не','никогда','зачем','почему'}))
local broadcastHeads=Text.toCpLowerList({'внимание!','внимание:','объявление:','сервер:','уважаемые игроки','уважаемые жители штата'})
local broadcastPatterns=Text.toCpLowerList({
    '^через %d+ минут[уы]? начнется%s', '^через %d+ минут[уы]? начнётся%s',
    '^через %d+ минут[уы]? начинается%s', '^через %d+ секунд[уы]? начнется%s',
    '^через %d+ секунд[уы]? начнётся%s', '^до начала .+ осталось %d+ секунд'
})
local adminPrefix=assert(Text.fromUtf8('администратор '))
local saysPrefix=assert(Text.fromUtf8('говорит:'))
local dragyTag=assert(Text.fromUtf8('[dragy]'))
local luckPattern=assert(Text.fromUtf8('^%S+ открыл .- и получил супер%-приз:'))
-- Continuation lines printed after the [Рабочая акция] header do not carry the
-- tag themselves. Arizona uses both "Акция для ..." and "Акция на ..." forms,
-- sometimes with a numbered prefix ("1. ...") and sometimes without it.
-- Job/task text and bonus percent are variable.
local workPromoPatterns={
    assert(Text.fromUtf8('^%d+%.%s+акция для .+%.%s+зарплата на %d+%%%s+выше[%.!]*$')),
    assert(Text.fromUtf8('^%d+%.%s+акция на .+%.%s+зарплата на %d+%%%s+выше[%.!]*$')),
    assert(Text.fromUtf8('^акция для .+%.%s+зарплата на %d+%%%s+выше[%.!]*$')),
    assert(Text.fromUtf8('^акция на .+%.%s+зарплата на %d+%%%s+выше[%.!]*$'))
}
local giftExchangeLuckPattern=assert(Text.fromUtf8('^удача улыбнулась игроку .+ при обмене подарков и он выиграл %- .+[%.!]*$'))
local azCoinsWinnerPattern=assert(Text.fromUtf8('^%d+%.%s+[%w_]+%s+заработал%s+%d+%s+az coins[%.!]*$'))
local casinoAdPatterns={
    assert(Text.fromUtf8('^каз%s+%d')),
    assert(Text.fromUtf8('^казино%s+%d'))
}

local MessageContext={}
function MessageContext.sender(plain)
    local rest,prefix=Text.trim(plain),''
    -- Consume only decoration / explicitly known channel names at the start.
    for _=1,12 do
        local part=rest:match('^(:[uU]%x+:)%s*')
        if not part then
            local tag=rest:match('^(%[[^%]]+%])')
            if tag and channels[Text.cp1251Lower(tag)] then part=tag end
        end
        if not part then break end
        prefix=prefix..part..' '; rest=Text.trim(rest:sub(#part+1))
    end
    local nick,id,after=rest:match('^([A-Za-z0-9]+_[A-Za-z0-9_]+)%[(%d+)%](.*)$')
    if not nick or not Custom.validNick(nick) or #id>5 or tonumber(id)>65534 then return nil end
    local tail=Text.trim(after)
    for _=1,8 do
        local icon=tail:match('^(:[uU]%x+:)')
        if not icon then break end
        tail=Text.trim(tail:sub(#icon+1))
    end
    local lowerPrefix=Text.cp1251Lower(prefix)
    local badge
    for _,code in ipairs(VIP_AD_BADGE_CODEPOINTS) do
        local token=string.format(':u%x:',code)
        if lowerPrefix:find(token,1,true) then badge=code; break end
    end
    if tail:sub(1,1)==':' then tail=Text.trim(tail:sub(2))
    elseif Text.cp1251Lower(tail):sub(1,#saysPrefix)==saysPrefix then tail=Text.trim(tail:sub(#saysPrefix+1))
    elseif not badge then return nil end
    return nick,tonumber(id),prefix,tail,badge
end
function MessageContext.personal(ctx)
    if ctx.isPlayerMessage then return nil end
    if ctx.tag==dragyTag then return '[dragy]' end
    local body=ctx.clean
    if ctx.tag then
        if not personalTags[ctx.tag] then return nil end
        body=Text.trim(body:sub(#ctx.tag+1)):gsub('^:%s*','')
    end
    for _,phrase in ipairs(personalPhrases) do
        if body:sub(1,#phrase)==phrase then
            local after=body:sub(#phrase+1,#phrase+1)
            if after=='' or after:match('[%s%p]') then return phrase end
        end
    end
end
function MessageContext.systemLike(ctx)
    if ctx.isPlayerMessage then return false end
    -- An unknown channel before a plausible sender is ambiguous. Do not feed
    -- ordinary conversation into Learning just because the channel is new.
    local withoutTags=ctx.clean
    for _=1,4 do
        local tag=withoutTags:match('^%[[^%]]+%]%s*')
        if not tag then break end
        withoutTags=withoutTags:sub(#tag+1)
    end
    if withoutTags:match('^[a-z0-9]+_[a-z0-9_]+%[%d+%]%s*:') then return false end
    if ctx.tag and not ctx.tag:match('^%[%d+%]$') and #ctx.tag>=4 then return true,'системная метка' end
    for _,head in ipairs(broadcastHeads) do
        if ctx.clean:sub(1,#head)==head then return true,'структура общего объявления' end
    end
    for _,pattern in ipairs(broadcastPatterns) do
        if ctx.clean:find(pattern) then return true,'структура обратного отсчёта события' end
    end
    if ctx.clean:sub(1,#adminPrefix)==adminPrefix and ctx.clean:find(':',1,true) then
        return true,'объявление администратора'
    end
    if #ctx.tokens.unknown>0 and ctx.clean:sub(1,1)==':' then return true,'неизвестный токен в начале строки' end
    return false
end
function MessageContext.new(raw,color)
    raw=type(raw)=='string' and raw or ''
    local canonical=Text.canonicalCp(raw)
    local plain=Text.trim(Text.stripColors(canonical))
    local ctx={raw=raw,plain=plain,rawLower=Text.cp1251Lower(canonical),clean=Text.normalize(plain),color=color}
    ctx.tag=ctx.clean:match('^(%[[^%]]+%])')
    ctx.senderNick,ctx.senderId,ctx.senderPrefix,ctx.body,ctx.vipBadge=MessageContext.sender(plain)
    ctx.isPlayerMessage=ctx.senderNick~=nil
    ctx.tokens=ArizonaTokenParser.parse(ctx.clean)
    ctx.bodyClean=ctx.isPlayerMessage and Text.normalize(ctx.body) or ctx.clean
    ctx.words=Text.tokenize(ctx.bodyClean)
    ctx.hasVipAdBadge=ctx.vipBadge~=nil
    ctx.personalMatched=MessageContext.personal(ctx)
    ctx.isPersonalAction=ctx.personalMatched~=nil
    ctx.isSystemLike,ctx.systemReason=MessageContext.systemLike(ctx)
    return ctx
end

local tradeDefs={
    {key='block_trade_adv_tags',id='trade_adv',phrases=CP.trade_adv_phrases,title='VIP-реклама и плашка с рупором',desc='Рекламные плашки/метки и явные VIP-рекламные команды вроде /gomp. Сам значок после ника без рекламы не блокируется.'},
    {key='block_trade_calls',id='trade_calls',title='Кнопки звонка :call:',desc='Отдельный фильтр :call: и :call<ID>:. Выключение снимает блокировку по кнопке звонка.'},
    {key='block_trade_lavka',id='trade_lavka',title='Лавки и Центральный рынок',desc=':lavka:, :lavka<ID>: и характерные предложения лавок.'},
    {key='block_trade_buy',id='trade_buy',token='buy',words=CP.trade_buy_words,title='Покупка и скупка',desc=':buy:, куплю, скупаю, приобрeту.'},
    {key='block_trade_sell',id='trade_sell',token='sell',words=CP.trade_sell_words,title='Продажа',desc=':sell:, продам, продаю, распродаю, сливаю.'},
    {key='block_trade_rent',id='trade_rent',token='rent',words=CP.trade_rent_words,phrases=CP.trade_rent_phrases,title='Аренда',desc=':rent:, сдам, сдаю, сниму, возьму в аренду.'},
    {key='block_trade_invites',id='trade_invites',phrases=CP.trade_invites,title='Инвайты и продажа рангов',desc='Наборы в семьи и торговля рангами.'},
    {key='block_trade_exchange',id='trade_exchange',token='trade',words=CP.trade_exchange_words,phrases=CP.trade_exchange_phrases,title='Обмен, подселение и заведения',desc=':trade:, обменяю, меняю, подселю, реклама заведений.'}
}
for _,d in ipairs(tradeDefs) do if d.words then d.wordSet=Text.wordSet(d.words) end end
local categoryNames={empty='Пустые строки',custom='Свои фразы',player_block='Чёрный список игроков',vehicle_quality='Ларцы и выигрыши'}
for _,d in ipairs(categoryDefs) do categoryNames[d.id]=d.title end
for _,d in ipairs(tradeDefs) do categoryNames[d.id]=d.title end

local function phraseMatch(clean,phrases)
    for _,phrase in ipairs(phrases or {}) do
        local from=1
        while true do
            local a,b=clean:find(phrase,from,true)
            if not a then break end
            local prev=Text.trim(clean:sub(1,a-1)):match('(%S+)$')
            if not negations[prev] then return phrase end
            from=b+1
        end
    end
end
local function anchoredTagMatch(ctx,list)
    -- Known system tags normally start the line, but Arizona can prepend
    -- "Администратор Nick_Name:" to the same server announcement. For tagged
    -- admin broadcasts, treat the text after the first colon as the tag anchor.
    local tagAnchor=ctx.clean
    if ctx.clean:sub(1,#adminPrefix)==adminPrefix then
        local colon=ctx.clean:find(':',#adminPrefix+1,true)
        if colon then tagAnchor=Text.trim(ctx.clean:sub(colon+1)) end
    end
    for _,p in ipairs(list) do
        if p:sub(1,1)=='[' then
            if tagAnchor:sub(1,#p)==p then return p end
        elseif ctx.clean:find(p,1,true) then return p end
    end
end

local DECISION={
    BLOCK='BLOCK', BLOCK_PLAYER='BLOCK_PLAYER', WOULD_BLOCK='WOULD_BLOCK',
    ALLOW_DISABLED='ALLOW_DISABLED', ALLOW_WHITELIST='ALLOW_WHITELIST',
    ALLOW_PERSONAL='ALLOW_PERSONAL', ALLOW_DEFAULT='ALLOW_DEFAULT',
    ALLOW_PLAYER_CHAT='ALLOW_PLAYER_CHAT', ALLOW_UNKNOWN_SYSTEM='ALLOW_UNKNOWN_SYSTEM'
}
local function isBlockedDecision(decision)
    return decision==DECISION.BLOCK or decision==DECISION.BLOCK_PLAYER
end

local RuleEngine={rules={}}
function RuleEngine.build()
    RuleEngine.rules={}
    for _,def in ipairs(categoryDefs) do
        local d=def
        RuleEngine.rules[#RuleEngine.rules+1]={id=d.id,key=d.key,match=function(ctx)
            -- System categories must not delete a player's discussion of VIP,

            if ctx.isPlayerMessage then return nil end

            if d.id=='hints' then
                for _,pattern in ipairs(workPromoPatterns) do
                    local promo=ctx.clean:match(pattern)
                    if promo then return promo end
                end
            end

            if d.id=='luck' then
                local azCoinsWinner=ctx.clean:match(azCoinsWinnerPattern)
                if azCoinsWinner then return azCoinsWinner end
            end

            if d.id=='admin_announcements' and ctx.clean:sub(1,#adminPrefix)==adminPrefix then
                local colon=ctx.clean:find(':',#adminPrefix+1,true)
                if colon then return ctx.clean:sub(1,colon) end
            end
            return anchoredTagMatch(ctx,CP[d.id])
        end}
    end
end
function RuleEngine.trade(ctx,s)
    if not s.block_trade_all then return nil end
    local clean=ctx.bodyClean
    for _,d in ipairs(tradeDefs) do
        if s[d.key] then
            local hit
            if d.id=='trade_adv' then
                if ctx.hasVipAdBadge then hit=string.format('VIP badge U+%X',ctx.vipBadge)
                else
                    for _,p in ipairs(CP.trade_tags) do
                        if ctx.clean:sub(1,#p)==p then hit=p; break end
                    end
                    if not hit then hit=phraseMatch(clean,d.phrases) end
                end
            elseif d.id=='trade_calls' then hit=ctx.tokens.callToken
            elseif d.id=='trade_lavka' then hit=ctx.tokens.lavkaToken or phraseMatch(clean,CP.trade_lavka)
            else
                hit=d.token and ctx.tokens[d.token..'Token'] or nil
                if not hit then hit=phraseMatch(clean,d.phrases) end
                if not hit and d.id=='trade_exchange' then
                    for _,pattern in ipairs(casinoAdPatterns) do
                        if clean:match(pattern) then hit='казино / ставка'; break end
                    end
                end
                if not hit and d.wordSet then
                    for i,word in ipairs(ctx.words) do
                        if d.wordSet[word] and not negations[ctx.words[i-1]] then hit=word; break end
                    end
                end
            end
            if hit then return d.id,d.title,hit end
        end
    end
end
function RuleEngine.classify(ctx,s,cache,dryRun)
    s,cache=s or ini.settings,cache or Custom.cache
    local function result(decision,id,reason,matched,category)
        local intended=decision
        if dryRun and isBlockedDecision(decision) then decision=DECISION.WOULD_BLOCK end
        return {decision=decision,intendedDecision=intended,ruleId=id or '',category=category or categoryNames[id] or 'Прочее',
                reason=reason or '',matched=matched or '',raw=ctx.raw,clean=ctx.clean,color=ctx.color,
                senderNick=ctx.senderNick,senderId=ctx.senderId,tag=ctx.tag,ctx=ctx}
    end
    if not s.enabled then return result(DECISION.ALLOW_DISABLED,'disabled','Очистка выключена') end
    if ctx.senderNick and cache.players[Text.cp1251Lower(ctx.senderNick)] then
        return result(DECISION.BLOCK_PLAYER,'player_block','Игрок в чёрном списке',ctx.senderNick)
    end
    local allowed,allow=Text.containsAny(ctx.clean,cache.allow)
    if not allowed then allow=Custom.matchPatterns(ctx.clean,cache.allowRe); allowed=allow~=nil end
    if allowed then return result(DECISION.ALLOW_WHITELIST,'whitelist','Пользовательский белый список',allow,'Белый список') end
    if ctx.isPersonalAction then return result(DECISION.ALLOW_PERSONAL,'personal','Персональное подтверждение',ctx.personalMatched,'Личное сообщение') end
    if ctx.clean=='' then
        if s.block_empty_lines then return result(DECISION.BLOCK,'empty','Пустая строка') end
        return result(DECISION.ALLOW_DEFAULT,'default','Пустая строка разрешена')
    end
    local id,why,hit=RuleEngine.trade(ctx,s)
    if id then return result(DECISION.BLOCK,id,why,hit) end
    if not ctx.isPlayerMessage and s.block_luck then
        local giftLuck=ctx.clean:match(giftExchangeLuckPattern)
        if giftLuck then
            return result(DECISION.BLOCK,'luck','Выигрыш при обмене подарков',giftLuck)
        end

        if ctx.clean:sub(1,#VEHICLE.player)==VEHICLE.player and
           ctx.clean:find(VEHICLE.received,#VEHICLE.player+1,true) then
            return result(DECISION.BLOCK,'vehicle_quality','Получение транспорта игроком',VEHICLE.received)
        end
        if ctx.clean:sub(1,#VEHICLE.legendary)==VEHICLE.legendary then
            return result(DECISION.BLOCK,'vehicle_quality','Легендарное качество транспорта',VEHICLE.legendary)
        end
        local luckHit=ctx.clean:match(luckPattern)
        if luckHit then return result(DECISION.BLOCK,'luck','Объявление о супер-призе',luckHit) end
    end
    local disabledRule,disabledEvidence
    for _,rule in ipairs(RuleEngine.rules) do
        local evidence=rule.match(ctx)
        if evidence then
            if s[rule.key] then return result(DECISION.BLOCK,rule.id,categoryNames[rule.id],evidence) end
            if not disabledRule then disabledRule,disabledEvidence=rule,evidence end
        end
    end
    if s.block_custom then
        local blocked,phrase=Text.containsAny(ctx.clean,cache.block)
        if not blocked then phrase=Custom.matchPatterns(ctx.clean,cache.blockRe); blocked=phrase~=nil end
        if blocked then return result(DECISION.BLOCK,'custom','Пользовательская фраза',phrase) end
    end
    if ctx.isPlayerMessage then return result(DECISION.ALLOW_PLAYER_CHAT,'player_chat','Обычный чат игрока',nil,'Чат игроков') end
    if disabledRule then return result(DECISION.ALLOW_DEFAULT,disabledRule.id,'Фильтр этой известной категории выключен',disabledEvidence) end
    if ctx.isSystemLike then return result(DECISION.ALLOW_UNKNOWN_SYSTEM,'unknown_system',ctx.systemReason,nil,'Неизвестное системное') end
    return result(DECISION.ALLOW_DEFAULT,'default','Нет подходящего правила')
end
RuleEngine.build()

local Journal={data={},head=1,count=0,serial=0,version=0,lastBlocked=nil}
function Journal.add(result)
    Journal.serial=Journal.serial+1
    result.serial=Journal.serial
    result.timestamp=os.time()
    result.timeText=os.date('%H:%M:%S',result.timestamp)
    Journal.data[Journal.head]=result
    Journal.head=Journal.head%JOURNAL_LIMIT+1
    Journal.count=math.min(JOURNAL_LIMIT,Journal.count+1)
    Journal.version=Journal.version+1
    if isBlockedDecision(result.decision) then Journal.lastBlocked=result end
end

function Journal.preview(r)
    if not r.preview then r.preview=Text.preview(r.clean,90) end
    return r.preview
end
function Journal.at(index)
    if index<1 or index>Journal.count then return nil end
    return Journal.data[(Journal.head-index-1)%JOURNAL_LIMIT+1]
end
function Journal.clear()
    Journal.data={}; Journal.head=1; Journal.count=0; Journal.lastBlocked=nil
    Journal.version=Journal.version+1
end
function Journal.restoreEntry(r)
    if not r then return false,'Сообщение не выбрано.' end
    if not isBlockedDecision(r.decision) then return false,'Это сообщение не было скрыто.' end
    local prior=restoring
    restoring=true
    local ok,err=pcall(sampAddChatMessage,r.raw,r.color or -1)
    restoring=prior
    if not ok then return false,tostring(err) end
    return true
end
function Journal.restore()
    if not Journal.lastBlocked then return false,'Нет скрытого сообщения.' end
    return Journal.restoreEntry(Journal.lastBlocked)
end
function Journal.describe(r)
    return table.concat({
        os.date('%Y-%m-%d %H:%M:%S',r.timestamp or os.time())..' | '..r.decision..' | '..r.category,
        'rule='..r.ruleId..' | color='..Text.color(r.color),
        'sender='..(r.senderNick or '-')..' | id='..tostring(r.senderId or '-')..' | tag='..Text.display(r.tag or ''),
        'reason='..r.reason..' | matched='..Text.display(r.matched),
        'raw='..Text.display(r.raw):gsub('[\r\n]',function(c) return c=='\r' and '\\r' or '\\n' end),
        'clean='..Text.display(r.clean),' '
    },'\n')
end
function Journal.export()
    local lines={'ArzChatCleaner '..APP.version..' | Журнал по запросу пользователя | '..Journal.count..' сообщений',
                 'Символы вне CP1251 представлены маркерами :uHEX:.',''}
    for i=Journal.count,1,-1 do lines[#lines+1]=Journal.describe(Journal.at(i)) end
    Storage.ensureDir()
    local path=Storage.unique(CONFIG_DIR..'/arz_chat_cleaner_journal','.txt')
    local ok,err=Storage.write(path,table.concat(lines,'\n'))
    return ok,ok and path or err
end

local Learning={data={},order={},count=0,queue={},lastFlush=0,error=nil}
function Learning.signature(ctx)

    return ctx.clean:gsub('%d+','#')
end
function Learning.eligible(result)
    return result.decision==DECISION.ALLOW_UNKNOWN_SYSTEM
end
function Learning.collect(r)
    if not ini.settings.learning_enabled or not Learning.eligible(r) then return end
    local sig=Learning.signature(r.ctx)
    local c=Learning.data[sig]
    if not c then
        if Learning.count>=LEARNING_LIMIT then
            local oldest=table.remove(Learning.order,1)
            Learning.data[oldest]=nil
            Learning.count=Learning.count-1
        end
        c={signature=sig,count=0,firstSeen=r.timestamp,lastSeen=r.timestamp,example=r}
        Learning.data[sig]=c
        Learning.order[#Learning.order+1]=sig
        Learning.count=Learning.count+1
        if ini.settings.capture_unknown then

            if #Learning.queue>=32 then Learning.flush(true) end
            if #Learning.queue<64 then
                Learning.queue[#Learning.queue+1]=os.date('%Y-%m-%d %H:%M:%S',r.timestamp)..
                    ' | ALLOW_UNKNOWN_SYSTEM | reason='..tostring(r.ctx.systemReason or '-')..
                    ' | color='..Text.color(r.color)..' | '..Text.display(r.raw):gsub('[\r\n]',' ')..'\n'
            else
                Learning.error=Learning.error or 'Очередь неизвестных сообщений переполнена; проверьте доступ к файлу журнала.'
            end
        end
    end
    c.count=c.count+1; c.lastSeen=r.timestamp; c.example=r
end
function Learning.flush(force)
    local now=os.time()
    if #Learning.queue==0 or (not force and now-Learning.lastFlush<5) then return end
    Learning.lastFlush=now
    Storage.ensureDir()
    local content=table.concat(Learning.queue)
    local f=io.open(UNKNOWN_FILE,'rb')
    local size=0
    if f then size=f:seek('end') or 0; f:close() end
    if size+#content>LOG_LIMIT then
        if doesFileExist(UNKNOWN_FILE..'.bak') then
            local ok,err=os.remove(UNKNOWN_FILE..'.bak')
            if not ok then Learning.error=tostring(err); return end
        end
        if doesFileExist(UNKNOWN_FILE) then
            local ok,err=os.rename(UNKNOWN_FILE,UNKNOWN_FILE..'.bak')
            if not ok then Learning.error=tostring(err); return end
        end
    end
    local file,err=io.open(UNKNOWN_FILE,'ab')
    if not file then Learning.error=tostring(err); return end
    local ok,writeErr=file:write(content)
    local flushed,flushErr=file:flush()
    local closed,closeErr=file:close()
    if ok and flushed and closed then Learning.queue={}; Learning.error=nil
    else Learning.error=tostring(writeErr or flushErr or closeErr) end
end
function Learning.clear()
    Learning.data,Learning.order,Learning.queue={},{},{}
    Learning.count=0
end

local Session={dryUntil=0,stats={total=0,would=0,shown=0,received=0,byId={},wouldById={}},error=nil}
function Session.isDry() return Session.dryUntil>os.time() end
function Session.process(raw,color)
    local ctx=MessageContext.new(raw,color)
    local result=RuleEngine.classify(ctx,ini.settings,Custom.cache,Session.isDry())
    Journal.add(result)
    local stats=Session.stats
    stats.received=stats.received+1
    if isBlockedDecision(result.decision) then
        stats.total=stats.total+1
        stats.byId[result.ruleId]=(stats.byId[result.ruleId] or 0)+1
    else
        stats.shown=stats.shown+1
        if result.decision==DECISION.WOULD_BLOCK then
            stats.would=stats.would+1
            stats.wouldById[result.ruleId]=(stats.wouldById[result.ruleId] or 0)+1
        end
    end
    Learning.collect(result)
    return result
end
function sampev.onServerMessage(color,text)
    if restoring then return end
    local ok,result=pcall(Session.process,text,color)
    if not ok then

        Session.error=tostring(result)
        return
    end
    Session.error=nil
    if isBlockedDecision(result.decision) then return false end
end

local Settings={refs={},off=imgui.new.bool(false)}
local Presets={}
Presets.balanced=clone(defaults.settings)
Presets.balanced.learning_enabled=nil; Presets.balanced.capture_unknown=nil
Presets.minimal,Presets.maximum={},{}
for key in pairs(Presets.balanced) do Presets.minimal[key]=false; Presets.maximum[key]=true end
for _,key in ipairs({'enabled','block_trade_all','block_trade_adv_tags','block_trade_calls','block_trade_lavka','block_empty_lines','block_custom'}) do
    Presets.minimal[key]=true
end
Presets.labels={minimal='Минимальный',balanced='Сбалансированный',maximum='Максимальный',custom='Пользовательский'}
function Presets.detect(settings)
    for _,name in ipairs({'minimal','balanced','maximum'}) do
        local equal=true
        for key,value in pairs(Presets[name]) do if settings[key]~=value then equal=false; break end end
        if equal then return name end
    end
    return 'custom'
end
function Settings.sync()
    for key,value in pairs(ini.settings) do
        if type(value)=='boolean' then
            if Settings.refs[key] then Settings.refs[key][0]=value
            else Settings.refs[key]=imgui.new.bool(value) end
        end
    end
end
function Settings.set(key,value,defer)
    ini.settings[key]=value
    if key=='capture_unknown' and value then ini.settings.learning_enabled=true end
    if key=='learning_enabled' and not value then
        ini.settings.capture_unknown=false; Learning.queue={}
    end
    if key=='capture_unknown' and not value then Learning.queue={} end
    Settings.sync()
    if not defer then requestSave() end
end
function Presets.apply(name)
    for key,value in pairs(Presets[name]) do Settings.set(key,value,true) end
    requestSave()
end
function Settings.tradeMaster()
    local active=0
    for _,d in ipairs(tradeDefs) do if ini.settings.block_trade_all and ini.settings[d.key] then active=active+1 end end
    return active,#tradeDefs
end
function Settings.setGroup(defs,on,trade)
    if trade then ini.settings.block_trade_all=on end
    for _,d in ipairs(defs) do ini.settings[d.key]=on end
    Settings.sync(); requestSave()
end
Settings.sync()

imgui.OnInitialize(function()
    local io = imgui.GetIO()
    io.IniFilename = nil

    local style = imgui.GetStyle()
    style.WindowRounding = 12
    style.ChildRounding = 10
    style.FrameRounding = 7
    style.GrabRounding = 7
    style.TabRounding = 7
    style.PopupRounding = 8
    style.ScrollbarRounding = 9
    style.WindowBorderSize = 1
    style.ChildBorderSize = 1
    style.FrameBorderSize = 1
    style.PopupBorderSize = 1
    style.ScrollbarSize = 13
    style.WindowPadding = imgui.ImVec2(14, 14)
    style.FramePadding = imgui.ImVec2(9, 6)
    style.ItemSpacing = imgui.ImVec2(8, 8)
    style.ItemInnerSpacing = imgui.ImVec2(7, 5)

    local c, Col, V = style.Colors, imgui.Col, imgui.ImVec4
    c[Col.WindowBg]            = V(0.082, 0.064, 0.118, 0.99)
    c[Col.ChildBg]             = V(0.108, 0.082, 0.158, 0.94)
    c[Col.PopupBg]             = V(0.105, 0.080, 0.155, 0.99)
    c[Col.Border]              = V(0.410, 0.270, 0.570, 0.58)
    c[Col.BorderShadow]        = V(0.000, 0.000, 0.000, 0.00)
    c[Col.FrameBg]             = V(0.155, 0.112, 0.220, 0.96)
    c[Col.FrameBgHovered]      = V(0.215, 0.148, 0.310, 1.00)
    c[Col.FrameBgActive]       = V(0.285, 0.185, 0.405, 1.00)
    c[Col.TitleBg]             = V(0.112, 0.076, 0.170, 1.00)
    c[Col.TitleBgActive]       = V(0.250, 0.132, 0.400, 1.00)
    c[Col.TitleBgCollapsed]    = V(0.095, 0.067, 0.145, 0.94)
    c[Col.MenuBarBg]           = V(0.135, 0.095, 0.205, 0.96)
    c[Col.Button]              = V(0.265, 0.165, 0.390, 0.94)
    c[Col.ButtonHovered]       = V(0.390, 0.235, 0.565, 1.00)
    c[Col.ButtonActive]        = V(0.485, 0.285, 0.685, 1.00)
    c[Col.Header]              = V(0.285, 0.175, 0.420, 0.84)
    c[Col.HeaderHovered]       = V(0.390, 0.245, 0.570, 0.94)
    c[Col.HeaderActive]        = V(0.470, 0.305, 0.670, 1.00)
    c[Col.CheckMark]           = V(0.860, 0.660, 1.000, 1.00)
    c[Col.SliderGrab]          = V(0.560, 0.350, 0.790, 0.90)
    c[Col.SliderGrabActive]    = V(0.680, 0.470, 0.930, 1.00)
    c[Col.ResizeGrip]          = V(0.540, 0.330, 0.760, 0.30)
    c[Col.ResizeGripHovered]   = V(0.650, 0.430, 0.900, 0.78)
    c[Col.ResizeGripActive]    = V(0.720, 0.510, 0.960, 0.95)
    c[Col.Separator]           = V(0.335, 0.220, 0.485, 0.62)
    c[Col.SeparatorHovered]    = V(0.520, 0.350, 0.750, 0.86)
    c[Col.SeparatorActive]     = V(0.630, 0.440, 0.890, 1.00)
    c[Col.Tab]                 = V(0.145, 0.105, 0.215, 0.96)
    c[Col.TabHovered]          = V(0.340, 0.215, 0.505, 0.96)
    c[Col.TabActive]           = V(0.315, 0.185, 0.485, 1.00)
    c[Col.TabUnfocused]        = V(0.118, 0.086, 0.182, 0.97)
    c[Col.TabUnfocusedActive]  = V(0.225, 0.145, 0.345, 1.00)
    c[Col.ScrollbarBg]         = V(0.073, 0.055, 0.105, 0.54)
    c[Col.ScrollbarGrab]       = V(0.315, 0.205, 0.460, 0.86)
    c[Col.ScrollbarGrabHovered]= V(0.430, 0.290, 0.620, 0.96)
    c[Col.ScrollbarGrabActive] = V(0.535, 0.375, 0.770, 1.00)
    c[Col.Text]                = V(0.960, 0.945, 0.985, 1.00)
    c[Col.TextDisabled]        = V(0.650, 0.610, 0.720, 1.00)
end)

local UI={window=imgui.new.bool(false),filter=imgui.new.char[192](''),ruleSearch=imgui.new.char[512](''),
          journalSearch=imgui.new.char[192](''),test=imgui.new.char[4096](''),testColor=imgui.new.char[24]('FFFFFFFF'),
          edit=imgui.new.char[512](''),editor=nil,editorPending=false,notice=nil,testResult=nil,
          selected=nil,journalMode=1,learningView=false,customKind=1,showTechnical=false}

local ACCENT=imgui.ImVec4(0.57,0.32,0.80,1)
local SUCCESS=imgui.ImVec4(0.40,0.95,0.58,1)
local DANGER=imgui.ImVec4(0.95,0.50,0.50,1)
local WARNING=imgui.ImVec4(1.00,0.76,0.38,1)
local MUTED=imgui.ImVec4(0.70,0.66,0.76,1)

local function wrapped(text)
    imgui.PushTextWrapPos(0); imgui.TextUnformatted(text or ''); imgui.PopTextWrapPos()
end
local function hint(text)
    if imgui.IsItemHovered() then
        imgui.BeginTooltip(); imgui.PushTextWrapPos(440)
        imgui.TextUnformatted(text); imgui.PopTextWrapPos(); imgui.EndTooltip()
    end
end
local function notice(ok,text)
    UI.notice=(ok and '' or 'Ошибка: ')..tostring(text or '')
end
local function option(key,title,help)
    if imgui.Checkbox(title..'##'..key,Settings.refs[key]) then Settings.set(key,Settings.refs[key][0]) end
    if help then hint(help) end
end
local function searchBox(id,buffer,label)
    imgui.PushItemWidth(-1)
    imgui.InputText(label..'##'..id,buffer,ffi.sizeof(buffer))
    imgui.PopItemWidth()
    local cp=Text.fromUtf8(ffi.string(buffer))
    return cp and Text.normalize(cp) or ''
end
local function matches(s,needle)
    if needle=='' then return true end
    local cp=Text.fromUtf8(s)
    return cp and Text.normalize(cp):find(needle,1,true)~=nil
end
local function segment(label,id,selected,width)
    if selected then imgui.PushStyleColor(imgui.Col.Button,ACCENT) end
    local hit=imgui.Button(label..'##'..id,imgui.ImVec2(width or 0,0))
    if selected then imgui.PopStyleColor() end
    return hit
end

local function softActionButton(label,id,tone,width)
    local button,hovered,active,textColor
    if tone=='success' then
        button=imgui.ImVec4(0.15,0.29,0.20,0.95)
        hovered=imgui.ImVec4(0.19,0.38,0.26,1.00)
        active=imgui.ImVec4(0.21,0.44,0.30,1.00)
        textColor=imgui.ImVec4(0.76,1.00,0.83,1.00)
    else

        button=imgui.ImVec4(0.27,0.18,0.38,0.96)
        hovered=imgui.ImVec4(0.36,0.24,0.50,1.00)
        active=imgui.ImVec4(0.42,0.28,0.58,1.00)
        textColor=imgui.ImVec4(0.95,0.91,1.00,1.00)
    end

    imgui.PushStyleColor(imgui.Col.Button,button)
    imgui.PushStyleColor(imgui.Col.ButtonHovered,hovered)
    imgui.PushStyleColor(imgui.Col.ButtonActive,active)
    imgui.PushStyleColor(imgui.Col.Text,textColor)
    local hit=imgui.Button(label..'##'..id,imgui.ImVec2(width or 0,0))
    imgui.PopStyleColor(4)
    return hit
end
local function sectionHeader(title,subtitle)
    imgui.Spacing()
    imgui.TextUnformatted(title)
    if subtitle and subtitle~='' then imgui.TextDisabled(subtitle) end
    imgui.Separator()
end
local function decisionLabel(decision)
    if decision==DECISION.BLOCK or decision==DECISION.BLOCK_PLAYER then return 'Скрыто' end
    if decision==DECISION.WOULD_BLOCK then return 'Тест' end
    if decision==DECISION.ALLOW_UNKNOWN_SYSTEM then return 'Неизвестно' end
    return 'Показано'
end
local function decisionColor(decision)
    if decision==DECISION.BLOCK or decision==DECISION.BLOCK_PLAYER then return ACCENT end
    if decision==DECISION.WOULD_BLOCK or decision==DECISION.ALLOW_UNKNOWN_SYSTEM then return WARNING end
    return SUCCESS
end
local function stablePhrase(r)
    if r.tag and #r.tag>=4 and not r.tag:find('%d') then return Text.display(r.tag) end
    local s=r.ctx.isPlayerMessage and r.ctx.body or r.ctx.plain
    s=Text.stripColors(s):gsub(':u%x+:',' ')
    local number=s:find('%d')
    if number then s=s:sub(1,number-1) end
    s=Text.trim(s):gsub('[%s%p]+$','')
    if #s<4 then return '' end
    return Text.display(s:sub(1,120))
end
local function openEditor(kind,value,index)
    UI.editor={kind=kind,index=index,error=nil}
    Text.buffer(UI.edit,value or '')
    UI.editorPending=true
end
local function drawEditor()
    if UI.editorPending then
        imgui.OpenPopup('Правило###rule_editor')
        UI.editorPending=false
    end

    imgui.SetNextWindowSizeConstraints(imgui.ImVec2(550,0),imgui.ImVec2(550,10000))

    if imgui.BeginPopupModal('Правило###rule_editor',nil,imgui.WindowFlags.AlwaysAutoResize) then
        local e=UI.editor
        if e then
            local names={block='Всегда скрывать',allow='Всегда показывать',players='Блокировать игрока'}
            local function editorWrapped(text)
                imgui.PushTextWrapPos(imgui.GetCursorPosX()+520)
                imgui.TextUnformatted(text or '')
                imgui.PopTextWrapPos()
            end

            imgui.TextUnformatted(names[e.kind])
            imgui.TextDisabled(e.kind=='players' and 'Точный ник игрока' or 'Фраза или Lua-шаблон')
            editorWrapped(e.kind=='players' and
                'Упоминания этого ника в чужом сообщении не блокируются.' or
                'Для обычного правила укажите устойчивую часть сообщения. Для расширенного правила используйте префикс re: — это Lua-паттерн, а не PCRE.')

            imgui.PushItemWidth(-1)
            imgui.InputText('##edit_value',UI.edit,ffi.sizeof(UI.edit))
            imgui.PopItemWidth()

            if e.kind=='allow' then
                editorWrapped('Правило «Показывать» имеет приоритет над фильтрами, но не над чёрным списком игроков.')
            end
            if e.error then
                imgui.TextColored(DANGER,'Ошибка')
                editorWrapped(e.error)
            end

            if imgui.Button('Сохранить##edit') then
                local ok,err=Custom.put(e.kind,ffi.string(UI.edit),e.index)
                if ok then
                    UI.editor=nil
                    imgui.CloseCurrentPopup()
                    notice(true,'Правило сохранено.')
                else
                    e.error=err
                end
            end
            imgui.SameLine()
            if imgui.Button('Отмена##edit') then
                UI.editor=nil
                imgui.CloseCurrentPopup()
            end
        else
            imgui.CloseCurrentPopup()
        end
        imgui.EndPopup()
    end
end

local function drawDetails(r,actions)
    local label=decisionLabel(r.decision)
    imgui.TextColored(decisionColor(r.decision),label)
    imgui.SameLine()
    imgui.TextUnformatted('— '..(r.category or 'Прочее'))

    if r.reason and r.reason~='' then
        imgui.TextDisabled('Причина')
        wrapped(r.reason)
    end
    if r.matched and r.matched~='' then
        imgui.TextDisabled('Совпадение')
        wrapped(Text.display(r.matched))
    end
    imgui.TextDisabled('Сообщение')
    wrapped(Text.display(r.raw))

    if actions then
        imgui.Spacing()
        if isBlockedDecision(r.decision) then
            if imgui.Button('Вернуть##journal') then
                local ok,err=Journal.restoreEntry(r); notice(ok,ok and 'Сообщение возвращено в чат.' or err)
            end
            imgui.SameLine()
        end
        if imgui.Button('Всегда скрывать##journal') then openEditor('block',stablePhrase(r)) end
        imgui.SameLine()
        if imgui.Button('Всегда показывать##journal') then openEditor('allow',stablePhrase(r)) end

        if r.senderNick then
            if imgui.Button('Блокировать игрока##journal') then openEditor('players',r.senderNick) end
            imgui.SameLine()
        end
        if imgui.Button('Проверить снова##journal') then
            UI.testResult=RuleEngine.classify(MessageContext.new(r.raw,r.color),ini.settings,Custom.cache,Session.isDry())
            Text.buffer(UI.test,Text.display(r.raw))
            Text.buffer(UI.testColor,Text.color(r.color):gsub('^0x',''))
            notice(true,'Сообщение перенесено в «Диагностику».')
        end
        imgui.SameLine()
        if imgui.Button('Копировать##journal') then imgui.SetClipboardText(Journal.describe(r)) end
    end

    imgui.Spacing()
    if imgui.SmallButton((UI.showTechnical and 'Скрыть технические данные' or 'Технические данные')..'##technical') then
        UI.showTechnical=not UI.showTechnical
    end
    if UI.showTechnical then
        imgui.Separator()
        wrapped('Decision: '..r.decision..'  |  Rule ID: '..r.ruleId)
        wrapped('Color: '..Text.color(r.color)..'  |  Sender: '..(r.senderNick or '-')..'  |  ID: '..tostring(r.senderId or '-')..'  |  Tag: '..Text.display(r.tag or ''))
        wrapped('Clean: '..Text.display(r.clean))
        hint('Raw и Clean нужны для диагностики правил. Вне CP1251 символы отображаются как :uHEX:.')
    end
end

local function drawStatus()
    local active=ini.settings.enabled
    local dry=Session.isDry()
    local statusFlags=imgui.WindowFlags.NoScrollbar + imgui.WindowFlags.NoScrollWithMouse
    imgui.BeginChild('status_header',imgui.ImVec2(0,dry and 88 or 58),true,statusFlags)

    local style=imgui.GetStyle()
    local startX=imgui.GetCursorPosX()
    local avail=imgui.GetContentRegionAvail().x
    local statusText=active and 'Очистка чата включена' or 'Очистка чата выключена'
    local actionText=active and 'Выключить' or 'Включить'
    local hiddenText='Скрыто за сеанс: '..Session.stats.total
    local actionWidth=88
    local rowWidth=imgui.CalcTextSize(statusText).x + style.ItemSpacing.x +
                   actionWidth + style.ItemSpacing.x + imgui.CalcTextSize(hiddenText).x

    imgui.SetCursorPosX(startX + math.max(0,(avail-rowWidth)/2))
    imgui.AlignTextToFramePadding()
    imgui.TextColored(active and SUCCESS or DANGER,statusText)
    imgui.SameLine()
    if softActionButton(actionText,'enabled',active and 'neutral' or 'success',actionWidth) then
        Settings.set('enabled',not active)
    end
    imgui.SameLine()
    imgui.AlignTextToFramePadding()
    imgui.TextDisabled(hiddenText)

    if dry then
        local dryText='Тестовый режим: '..math.max(0,Session.dryUntil-os.time())..' сек.'
        local dryButtonWidth=82
        local dryRowWidth=imgui.CalcTextSize(dryText).x + style.ItemSpacing.x + dryButtonWidth
        imgui.SetCursorPosX(startX + math.max(0,(avail-dryRowWidth)/2))
        imgui.AlignTextToFramePadding()
        imgui.TextColored(WARNING,dryText)
        imgui.SameLine()
        if softActionButton('Завершить','dry_end','neutral',dryButtonWidth) then Session.dryUntil=0 end
    end

    imgui.EndChild()
    imgui.Spacing()
end

local function drawGroup(title,id,defs,needle,trade)
    local active,total=0,#defs
    for _,d in ipairs(defs) do
        if ini.settings[d.key] and (not trade or ini.settings.block_trade_all) then active=active+1 end
    end
    local any=false
    for _,d in ipairs(defs) do if matches(d.title..' '..d.desc,needle) then any=true; break end end
    if not any then return end

    imgui.TextUnformatted(title)
    imgui.SameLine()
    imgui.TextDisabled(active..' из '..total)
    imgui.SameLine()
    if imgui.SmallButton((active==total and 'Выключить все' or 'Включить все')..'##'..id) then
        Settings.setGroup(defs,active~=total,trade)
    end
    imgui.Separator()

    if trade and not ini.settings.block_trade_all then
        imgui.TextColored(WARNING,'Группа выключена')
        imgui.SameLine()
        imgui.TextDisabled('Выберите пункт или включите всю группу.')
    end

    for _,d in ipairs(defs) do
        if matches(d.title..' '..d.desc,needle) then
            if trade and not ini.settings.block_trade_all then
                Settings.off[0]=false
                if imgui.Checkbox(d.title..'##'..d.key,Settings.off) then
                    for _,child in ipairs(tradeDefs) do ini.settings[child.key]=false end
                    ini.settings.block_trade_all=true; ini.settings[d.key]=true
                    Settings.sync(); requestSave()
                end
                hint(d.desc)
            else
                option(d.key,d.title,d.desc)
            end
        end
    end
    imgui.Spacing()
end

local function drawFilters()
    sectionHeader('Профиль фильтрации','Быстрый набор настроек. Отдельные пункты ниже можно менять вручную.')
    local selected=Presets.detect(ini.settings)
    local width=(imgui.GetContentRegionAvail().x-16)/3
    for i,name in ipairs({'minimal','balanced','maximum'}) do
        if i>1 then imgui.SameLine() end
        if segment(Presets.labels[name],name,selected==name,width) then Presets.apply(name) end
    end
    if selected=='custom' then imgui.TextDisabled('Текущий профиль: Пользовательский') end

    imgui.Spacing()
    local needle=searchBox('filters',UI.filter,'Поиск фильтров')
    imgui.Spacing()
    imgui.BeginChild('filter_scroll',imgui.ImVec2(0,0),true)
    drawGroup('Объявления игроков','trade_group',tradeDefs,needle,true)
    drawGroup('Системные сообщения','server_group',categoryDefs,needle,false)

    local showEmpty=matches('Пустые строки разделители отступы',needle)
    local showCustom=matches('Пользовательские фразы свои правила',needle)
    if showEmpty or showCustom then
        imgui.TextUnformatted('Дополнительно')
        imgui.Separator()
        if showEmpty then option('block_empty_lines','Пустые строки','Удалять пустые разделители и отступы.') end
        if showCustom then option('block_custom','Пользовательские правила','Скрывать сообщения по правилам из вкладки «Правила».') end
    end
    imgui.EndChild()
end

local customKinds={
    {id='block',label='Скрывать'},
    {id='allow',label='Показывать'},
    {id='players',label='Игроки'}
}
local function drawCustom()
    sectionHeader('Пользовательские правила','Скрывайте отдельные фразы, всегда показывайте важные сообщения или блокируйте конкретных игроков.')

    local tabWidth=(imgui.GetContentRegionAvail().x-16)/3
    for i,k in ipairs(customKinds) do
        if i>1 then imgui.SameLine() end
        local count=#Custom[k.id]
        if segment(k.label..' ('..count..')','custom_kind_'..k.id,UI.customKind==i,tabWidth) then UI.customKind=i end
    end

    local kind=customKinds[UI.customKind]
    imgui.Spacing()
    if imgui.Button('+ Добавить правило##new_custom') then openEditor(kind.id,'') end
    imgui.SameLine()
    imgui.TextDisabled(kind.id=='block' and 'Сообщение будет скрыто' or kind.id=='allow' and 'Сообщение будет показано' or 'Сообщения игрока будут скрыты')

    local needle=searchBox('custom',UI.ruleSearch,'Поиск в этом списке')
    if Custom.error then imgui.TextColored(DANGER,Custom.error) end
    if Custom.backup then imgui.TextDisabled('Резервная копия: '..Custom.backup) end
    if Custom.patternError then imgui.TextColored(WARNING,Custom.patternError) end

    imgui.BeginChild('custom_scroll',imgui.ImVec2(0,0),true)
    local removeIndex
    local count=0
    for i,value in ipairs(Custom[kind.id]) do
        if matches(value,needle) then
            count=count+1
            wrapped(value)
            if imgui.SmallButton('Изменить##'..kind.id..i) then openEditor(kind.id,value,i) end
            imgui.SameLine()
            if imgui.SmallButton('Удалить##'..kind.id..i) then removeIndex=i end
            imgui.Separator()
        end
    end
    if count==0 then
        imgui.TextDisabled(needle~='' and 'Ничего не найдено.' or 'В этом списке пока нет правил.')
    end
    imgui.EndChild()
    if removeIndex then
        local ok,err=Custom.remove(kind.id,removeIndex)
        notice(ok,ok and 'Правило удалено.' or err)
    end
end

local journalModes={'Все','Скрытые','Показанные','Неизвестные','Тест'}
local function journalMatches(r,mode,needle)
    local block=isBlockedDecision(r.decision)
    if mode==2 and not block or mode==3 and block or mode==4 and r.decision~=DECISION.ALLOW_UNKNOWN_SYSTEM or
       mode==5 and r.decision~=DECISION.WOULD_BLOCK then return false end
    return needle=='' or r.clean:find(needle,1,true)~=nil
end

local function drawJournal()
    if segment('Журнал ('..Journal.count..'/'..JOURNAL_LIMIT..')','journal_view',not UI.learningView) then
        UI.learningView=false; UI.selected=nil; UI.showTechnical=false
    end
    imgui.SameLine()
    if segment('Неизвестные ('..Learning.count..')','learning_view',UI.learningView) then
        UI.learningView=true; UI.selected=nil; UI.showTechnical=false
    end

    imgui.Spacing()
    if not UI.learningView then
        for i,label in ipairs(journalModes) do
            if i>1 then imgui.SameLine() end
            if segment(label,'journal_filter'..i,UI.journalMode==i) then
                UI.journalMode=i; UI.selected=nil; UI.showTechnical=false
            end
        end
    else
        imgui.TextDisabled(ini.settings.learning_enabled and 'Наблюдение за неизвестными включено.' or 'Наблюдение за неизвестными выключено. Включить можно во вкладке «Диагностика».')
    end

    local needle=searchBox('journal',UI.journalSearch,'Поиск сообщений')

    if imgui.Button('Вернуть последнее##journal') then
        local ok,err=Journal.restore(); notice(ok,ok and 'Сообщение возвращено в чат.' or err)
    end
    imgui.SameLine()
    if imgui.Button('Экспорт##journal') then
        local ok,path=Journal.export(); notice(ok,ok and ('Сохранено: '..path) or path)
    end
    imgui.SameLine()
    if UI.learningView then
        if imgui.Button('Очистить неизвестные##history') then Learning.clear(); UI.selected=nil end
    else
        if imgui.Button('Очистить журнал##history') then Journal.clear(); UI.selected=nil end
    end

    imgui.Spacing()
    imgui.BeginChild('journal_rows',imgui.ImVec2(0,190),true)
    local count=0
    if UI.learningView then
        for i=#Learning.order,1,-1 do
            local c=Learning.data[Learning.order[i]]
            if needle=='' or c.example.clean:find(needle,1,true) then
                count=count+1
                local label=c.example.timeText..' | '..c.count..' раз | '..Journal.preview(c.example)
                if imgui.Selectable(label:gsub('##','# #')..'##learn'..i,UI.selected==c.example) then
                    UI.selected=c.example; UI.showTechnical=false
                end
                hint('Первое: '..os.date('%H:%M:%S',c.firstSeen)..' | Последнее: '..os.date('%H:%M:%S',c.lastSeen))
            end
        end
    else
        for i=1,Journal.count do
            local r=Journal.at(i)
            if journalMatches(r,UI.journalMode,needle) then
                count=count+1
                local label=r.timeText..' | '..decisionLabel(r.decision)..' | '..r.category..' | '..Journal.preview(r)
                if imgui.Selectable(label:gsub('##','# #')..'##entry'..r.serial,UI.selected==r) then
                    UI.selected=r; UI.showTechnical=false
                end
            end
        end
    end
    if count==0 then
        imgui.TextDisabled(UI.learningView and 'Неизвестных системных сообщений пока нет.' or 'Подходящих сообщений пока нет.')
    end
    imgui.EndChild()

    imgui.Spacing()
    imgui.BeginChild('journal_details',imgui.ImVec2(0,0),true)
    if UI.selected then drawDetails(UI.selected,true)
    else imgui.TextDisabled('Выберите сообщение, чтобы увидеть причину и доступные действия.') end
    imgui.EndChild()
end

local function drawDiagnostics()
    imgui.BeginChild('diagnostic_scroll',imgui.ImVec2(0,0),true)

    sectionHeader('Проверка сообщения','Проверка использует те же настройки и движок, что игровой чат, но не меняет журнал и счётчики.')
    imgui.TextDisabled('Текст сообщения')
    imgui.InputTextMultiline('##test_message',UI.test,ffi.sizeof(UI.test),imgui.ImVec2(-1,80))
    imgui.PushItemWidth(145)
    imgui.InputText('Цвет HEX##test_color',UI.testColor,ffi.sizeof(UI.testColor))
    imgui.PopItemWidth()
    imgui.SameLine()
    if imgui.Button('Проверить') then
        local sample,err=Text.fromUtf8(ffi.string(UI.test))
        local colorString=Text.trim(ffi.string(UI.testColor)):gsub('^0[xX]','')
        local color=colorString:match('^%x%x%x%x%x%x%x%x$') and tonumber(colorString,16) or nil
        if not color then notice(false,'Укажите цвет из 8 HEX-цифр, например FFFFFFFF.')
        elseif not sample then notice(false,err)
        else
            if color>=2147483648 then color=color-4294967296 end
            UI.testResult=RuleEngine.classify(MessageContext.new(sample,color),ini.settings,Custom.cache,Session.isDry())
            UI.showTechnical=false
        end
    end
    if UI.testResult then
        imgui.Spacing()
        drawDetails(UI.testResult,false)
    end

    sectionHeader('Безопасное тестирование','Проверяйте фильтры на живом чате без фактического скрытия сообщений.')
    if not Session.isDry() then
        if imgui.Button('Включить на 5 минут') then Session.dryUntil=os.time()+300 end
    else
        imgui.TextColored(WARNING,'Тестовый режим включён: '..math.max(0,Session.dryUntil-os.time())..' сек.')
        imgui.SameLine()
        if imgui.Button('Завершить') then Session.dryUntil=0 end
    end
    imgui.TextDisabled('Сообщения, которые обычно скрылись бы, остаются видимыми и помечаются как «Тест».')

    sectionHeader('Неизвестные сообщения','Собирайте системные сообщения, для которых ещё нет подходящего правила.')
    option('learning_enabled','Наблюдать за неизвестными','Кандидаты отображаются в разделе «Неизвестные» вкладки «Журнал».')
    option('capture_unknown','Сохранять неизвестные в файл','Файл config/arz_chat_cleaner_unknown.log, до 512 КиБ плюс резервная копия.')

    sectionHeader('Статистика сеанса','Счётчики сбрасываются при перезапуске скрипта или вручную.')
    local stats=Session.stats
    imgui.TextUnformatted('Получено: '..stats.received)
    imgui.SameLine(); imgui.TextColored(ACCENT,'Скрыто: '..stats.total)
    imgui.SameLine(); imgui.TextColored(SUCCESS,'Показано: '..stats.shown)
    imgui.SameLine(); imgui.TextColored(WARNING,'Тест: '..stats.would)
    imgui.Spacing()

    local ids,seen={},{}
    for id in pairs(stats.byId) do ids[#ids+1]=id; seen[id]=true end
    for id in pairs(stats.wouldById) do if not seen[id] then ids[#ids+1]=id end end
    table.sort(ids,function(a,b)
        local x,y=(stats.byId[a] or 0)+(stats.wouldById[a] or 0),(stats.byId[b] or 0)+(stats.wouldById[b] or 0)
        return x==y and a<b or x>y
    end)
    for _,id in ipairs(ids) do
        imgui.TextUnformatted((categoryNames[id] or id)..' — '..(stats.byId[id] or 0))
        if (stats.wouldById[id] or 0)>0 then
            imgui.SameLine(); imgui.TextDisabled('(тест: '..stats.wouldById[id]..')')
        end
        hint('Rule ID: '..id)
    end
    imgui.Spacing()
    if softActionButton('Сбросить','stats_reset','neutral',92) then
        Session.stats={total=0,would=0,shown=0,received=0,byId={},wouldById={}}
    end
    hint('Сбросить статистику текущего сеанса.')

    sectionHeader('Состояние скрипта','Сообщения о проблемах хранения, обучения и внешних правил.')
    local hasError=Session.error or Learning.error or Storage.error or RulesFile.error or Custom.patternError
    if not hasError then imgui.TextColored(SUCCESS,'Ошибок не обнаружено.') end
    if Session.error then imgui.TextColored(DANGER,'Обработка: '..Session.error) end
    if Learning.error then imgui.TextColored(DANGER,'Журнал неизвестных: '..Learning.error) end
    if Storage.error then imgui.TextColored(DANGER,Storage.error) end
    if RulesFile.error then imgui.TextColored(DANGER,RulesFile.error) end
    if Custom.patternError then imgui.TextColored(WARNING,Custom.patternError) end
    if RulesFile.added>0 or RulesFile.skipped>0 then
        imgui.TextDisabled('Внешние правила: добавлено '..RulesFile.added..(RulesFile.skipped>0 and (', пропущено '..RulesFile.skipped) or '')..'.')
    end

    imgui.EndChild()
end

imgui.OnFrame(function() return UI.window[0] and isSampAvailable() and not isPauseMenuActive() end,function()
    local sx,sy=getScreenResolution()
    imgui.SetNextWindowPos(imgui.ImVec2(sx/2,sy/2),imgui.Cond.FirstUseEver,imgui.ImVec2(0.5,0.5))
    imgui.SetNextWindowSize(imgui.ImVec2(math.min(sx-30,840),math.min(sy-30,740)),imgui.Cond.FirstUseEver)
    imgui.SetNextWindowSizeConstraints(imgui.ImVec2(math.min(sx-20,680),math.min(sy-20,540)),imgui.ImVec2(sx,sy))
    local visible=imgui.Begin(APP.displayName..' v'..APP.version..'###ArzChatCleaner',UI.window,imgui.WindowFlags.NoCollapse)
    if visible then
        drawStatus()
        local footerHeight=UI.notice and 26 or 0
        imgui.BeginChild('main_content',imgui.ImVec2(0,-footerHeight),false)
        if imgui.BeginTabBar('main_tabs') then
            if imgui.BeginTabItem('Фильтры') then drawFilters(); imgui.EndTabItem() end
            if imgui.BeginTabItem('Правила') then drawCustom(); imgui.EndTabItem() end
            if imgui.BeginTabItem('Журнал') then drawJournal(); imgui.EndTabItem() end
            if imgui.BeginTabItem('Диагностика') then drawDiagnostics(); imgui.EndTabItem() end
            imgui.EndTabBar()
        end
        imgui.EndChild()
        if UI.notice then
            local message=Text.fromUtf8(UI.notice)
            imgui.TextUnformatted(message and Text.preview(message,100) or 'Ошибка записи. Подробности в диагностике.'); hint(UI.notice)
        end
        drawEditor()
    end
    imgui.End()
end)

local function toggleWindow() UI.window[0]=not UI.window[0] end
function main()
    while not isSampLoaded() do wait(100) end
    while not isSampAvailable() do wait(100) end
    Storage.ensureDir()
    Custom.load()
    if not doesFileExist(CONFIG_FILE) or removedLegacyUiScale then
        local saved=saveSettings()
        if not saved and Storage.error then chatMsg('{FF7777}'..Storage.error) end
    end
    sampRegisterChatCommand('arzclean',toggleWindow)
    sampRegisterChatCommand('cclean',toggleWindow)
    chatMsg('Загружен v'..APP.version..'. Меню: {BB86FC}/arzclean{FFFFFF} или {BB86FC}/cclean',0xFFFFFF)
    if Custom.error then chatMsg('{FF7777}'..Custom.error) end
    if RulesFile.error then chatMsg('{FF7777}'..RulesFile.error) end
    while true do
        wait(250)
        flushSettings(false)
        Learning.flush(false)
    end
end
function onScriptTerminate(scr,quitGame)
    if scr~=thisScript() then return end
    pcall(flushSettings,true)
    pcall(Learning.flush,true)
end