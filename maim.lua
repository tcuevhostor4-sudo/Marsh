-- Author: Pashenkov
local imgui = require 'imgui'
local encoding = require 'encoding'
local key = require('vkeys')
local ffi = require('ffi')
local sampev = require('lib.samp.events')
local dlstatus = require('moonloader').download_status

script_name('M-AIM')
script_author('Pashenkov')
script_version('1.0.9')

local CURRENT_VERSION = '1.0.9'
local VERSION_URL = 'https://raw.githubusercontent.com/tcuevhostor4-sudo/Marsh/main/version.txt'
local SCRIPT_URL = 'https://raw.githubusercontent.com/tcuevhostor4-sudo/Marsh/main/maim.lua'

local cfgDir = getWorkingDirectory() .. '\\config'
local cfgPath = cfgDir .. '\\M-AIM.ini'
local wlPath = cfgDir .. '\\M-AIM_whitelist.txt'
local updateVersionPath = cfgDir .. '\\M-AIM_remote_version.txt'
local updateScriptPath = cfgDir .. '\\M-AIM_update.lua'
encoding.default = 'UTF-8'
u8 = encoding.UTF8

local function chatMessage(text)
    if isSampAvailable() then
        sampAddChatMessage(u8:decode(tostring(text)), -1)
    end
end

local getBonePosition = ffi.cast("int (__thiscall*)(void*, float*, int, bool)", 0x5E4280)

function GetBodyPartCoordinates(id, handle)
    local pedptr = getCharPointer(handle)
    local vec = ffi.new("float[3]")
    getBonePosition(ffi.cast("void*", pedptr), vec, id, true)
    return vec[0], vec[1], vec[2]
end

local fontsize = nil

function imgui.BeforeDrawFrame()
    if fontsize == nil then
        fontsize = imgui.GetIO().Fonts:AddFontFromFileTTF(getFolderPath(0x14) .. '\\trebucbd.ttf', 27.0, nil, imgui.GetIO().Fonts:GetGlyphRangesCyrillic())
    end
end

function imgui.CenterText(text)
    local width = imgui.GetWindowWidth()
    local calc = imgui.CalcTextSize(text)
    imgui.SetCursorPosX( width / 2 - calc.x / 2 )
    imgui.Text(text)
end

Speed = imgui.ImFloat(0)
Dist = imgui.ImFloat(0)
Fov = imgui.ImFloat(0)
SwayAmount = imgui.ImFloat(1.2)
SwaySpeed = imgui.ImFloat(2.0)

local cbz1 = imgui.ImBool(false)
local cbz2 = imgui.ImBool(false)
local cbz3 = imgui.ImBool(false)
local cbz4 = imgui.ImBool(false)
local cbz5 = imgui.ImBool(false)
local cbz6 = imgui.ImBool(false)
local cbz7 = imgui.ImBool(true)
local cbz8 = imgui.ImBool(false)
local cbz9 = imgui.ImBool(false)
local aimEnabled = imgui.ImBool(true)
local nearestTargetEnabled = imgui.ImBool(true)
local liquidTargetEnabled = imgui.ImBool(false)

local aiming = 8

local weaponToProfile = {
    [24] = 24, [31] = 24,
    [107] = 107, [108] = 107,
    [103] = 103, [104] = 103,
    [76] = 76, [5] = 76
}

local profileLabels = {
    [24] = 'DEAGLE [24, 31]',
    [107] = 'M4 [107, 108]',
    [103] = 'UZI [103, 104]',
    [76] = 'БИТА [76, 5]'
}

local gunCfg = {
    -- Оставлено только для безопасного чтения старого INI.
    other = {
        enabled = true, speed = 10.0, dist = 20.0, fov = 15.0, aiming = 8,
        sway_enabled = false, sway_amount = 1.2, sway_speed = 2.0,
        wallcheck_enabled = true, nearest_target_enabled = true, liquid_target_enabled = false
    },
    [24] = {
        enabled = true, speed = 10.0, dist = 20.0, fov = 15.0, aiming = 8,
        sway_enabled = false, sway_amount = 1.2, sway_speed = 2.0,
        wallcheck_enabled = true, nearest_target_enabled = true, liquid_target_enabled = false
    },
    [107] = {
        enabled = true, speed = 10.0, dist = 20.0, fov = 15.0, aiming = 8,
        sway_enabled = false, sway_amount = 1.2, sway_speed = 2.0,
        wallcheck_enabled = true, nearest_target_enabled = true, liquid_target_enabled = false
    },
    [103] = {
        enabled = true, speed = 10.0, dist = 20.0, fov = 15.0, aiming = 8,
        sway_enabled = false, sway_amount = 1.2, sway_speed = 2.0,
        wallcheck_enabled = true, nearest_target_enabled = true, liquid_target_enabled = false
    },
    [76] = {
        enabled = true, speed = 10.0, dist = 20.0, fov = 15.0, aiming = 8,
        sway_enabled = false, sway_amount = 1.2, sway_speed = 2.0,
        wallcheck_enabled = true, nearest_target_enabled = true, liquid_target_enabled = false
    }
}
local editProfile = 24
local profileName = profileLabels[24]
local lastGunProfile = -1
local saveMsgUntil = 0

local liquidTargetPlayerId = -1
local liquidTargetUntil = 0.0
local liquidResetKeyWasDown = false
local whitelistToggleKeyWasDown = false
local whitelistNotifications = imgui.ImBool(true)
local autoCheckUpdates = imgui.ImBool(true)
local updateChecking = false
local updateDownloading = false
local updateAvailable = false
local remoteVersion = ''
local updateStatusText = 'Версия: ' .. CURRENT_VERSION
local updateMsgUntil = 0

local windows = imgui.ImBool(false)

local whitelist = {}
local wlInput = imgui.ImBuffer(64)

local function cleanNick(name)
    return tostring(name or ''):gsub('^%s+', ''):gsub('%s+$', ''):lower()
end

local function inWhitelist(name)
    return whitelist[cleanNick(name)] ~= nil
end

local function makeCfgDir()
    if not doesDirectoryExist(cfgDir) then
        createDirectory(cfgDir)
    end
end

local function saveWL()
    makeCfgDir()
    local file = io.open(wlPath, 'w')
    if not file then return false end

    local names = {}
    for _, nick in pairs(whitelist) do
        names[#names + 1] = nick
    end
    table.sort(names, function(a, b) return a:lower() < b:lower() end)

    for _, name in ipairs(names) do
        file:write(name .. '\n')
    end
    file:close()
    return true
end

local function loadWL()
    makeCfgDir()
    whitelist = {}
    local file = io.open(wlPath, 'r')
    if not file then
        saveWL()
        return
    end
    for line in file:lines() do
        local name = line:gsub('^%s+', ''):gsub('%s+$', '')
        if name ~= '' then whitelist[cleanNick(name)] = name end
    end
    file:close()
end

local function addWL(name)
    name = tostring(name or ''):gsub('^%s+', ''):gsub('%s+$', '')
    if name == '' then return false end
    whitelist[cleanNick(name)] = name
    saveWL()
    return true
end

local function removeWL(name)
    whitelist[cleanNick(name)] = nil
    saveWL()
end

local holdKey = 0x31
local activationToggleMode = imgui.ImBool(false)
local activationToggled = false
local activationKeyWasDown = false
local menuKey1 = key.VK_Q
local menuKey2 = key.VK_E
local liquidResetKey = 0x34
local whitelistToggleKey = 0x35
local chatCommand = 'maim'
local registeredCommand = nil

local commandInput = imgui.ImBuffer(32)
local holdKeyInput = imgui.ImBuffer(16)
local menuKey1Input = imgui.ImBuffer(16)
local menuKey2Input = imgui.ImBuffer(16)
local liquidResetKeyInput = imgui.ImBuffer(16)
local whitelistToggleKeyInput = imgui.ImBuffer(16)
local controlMsgUntil = 0

local keyNames = {
    SHIFT = key.VK_SHIFT, CTRL = key.VK_CONTROL, ALT = key.VK_MENU,
    SPACE = key.VK_SPACE, TAB = key.VK_TAB, ENTER = key.VK_RETURN,
    INSERT = key.VK_INSERT, DELETE = key.VK_DELETE, HOME = key.VK_HOME,
    END = key.VK_END, PGUP = key.VK_PRIOR, PGDN = key.VK_NEXT,
    UP = key.VK_UP, DOWN = key.VK_DOWN, LEFT = key.VK_LEFT, RIGHT = key.VK_RIGHT,
    LMB = key.VK_LBUTTON, RMB = key.VK_RBUTTON, MMB = key.VK_MBUTTON
}

for i = 0, 9 do keyNames[tostring(i)] = 0x30 + i end
for i = 0, 25 do keyNames[string.char(65 + i)] = 0x41 + i end
for i = 1, 12 do keyNames['F' .. i] = 0x6F + i end

local function trim(text)
    return tostring(text or ''):gsub('^%s+', ''):gsub('%s+$', '')
end

local function keyCode(name, fallback)
    name = trim(name):upper()
    return keyNames[name] or fallback
end

local function keyName(code)
    for name, value in pairs(keyNames) do
        if value == code and #name <= 5 then return name end
    end
    return tostring(code)
end

local function toggleMenu()
    windows.v = not windows.v
    imgui.Process = windows.v
end

local function registerMenuCommand()
    local cmd = trim(chatCommand):gsub('^/', ''):lower()
    if cmd == '' then cmd = 'maim' end

    if registeredCommand and registeredCommand ~= cmd then
        pcall(sampUnregisterChatCommand, registeredCommand)
    end

    local ok = pcall(sampRegisterChatCommand, cmd, toggleMenu)
    if ok then
        registeredCommand = cmd
        chatCommand = cmd
    end
end

local function saveCfg()
    makeCfgDir()

    local file = io.open(cfgPath, 'w')
    if not file then return false end

    file:write('[settings]\n')
    file:write('speed=' .. tostring(Speed.v) .. '\n')
    file:write('dist=' .. tostring(Dist.v) .. '\n')
    file:write('fov=' .. tostring(Fov.v) .. '\n')
    file:write('aiming=' .. tostring(aiming) .. '\n')
    file:write('sway_enabled=' .. tostring(cbz6.v) .. '\n')
    file:write('sway_amount=' .. tostring(SwayAmount.v) .. '\n')
    file:write('sway_speed=' .. tostring(SwaySpeed.v) .. '\n')
    file:write('wallcheck_enabled=' .. tostring(cbz7.v) .. '\n')
    file:write('ignore_anim_1151=' .. tostring(cbz8.v) .. '\n')
    file:write('command=' .. chatCommand .. '\n')
    file:write('hold_key=' .. tostring(holdKey) .. '\n')
    file:write('activation_toggle_mode=' .. tostring(activationToggleMode.v) .. '\n')
    file:write('activation_toggled=' .. tostring(activationToggled) .. '\n')
    file:write('menu_key_1=' .. tostring(menuKey1) .. '\n')
    file:write('menu_key_2=' .. tostring(menuKey2) .. '\n')
    file:write('liquid_reset_key=' .. tostring(liquidResetKey) .. '\n')
    file:write('whitelist_toggle_key=' .. tostring(whitelistToggleKey) .. '\n')
    file:write('whitelist_notifications=' .. tostring(whitelistNotifications.v) .. '\n')
    file:write('auto_check_updates=' .. tostring(autoCheckUpdates.v) .. '\n')
    for _, id in ipairs({24, 107, 103, 76}) do
        local p = gunCfg[id]
        local prefix = 'weapon' .. tostring(id) .. '_'
        file:write(prefix .. 'enabled=' .. tostring(p.enabled ~= false) .. '\n')
        file:write(prefix .. 'speed=' .. tostring(p.speed) .. '\n')
        file:write(prefix .. 'dist=' .. tostring(p.dist) .. '\n')
        file:write(prefix .. 'fov=' .. tostring(p.fov) .. '\n')
        file:write(prefix .. 'aiming=' .. tostring(p.aiming) .. '\n')
        file:write(prefix .. 'sway_enabled=' .. tostring(p.sway_enabled) .. '\n')
        file:write(prefix .. 'sway_amount=' .. tostring(p.sway_amount) .. '\n')
        file:write(prefix .. 'sway_speed=' .. tostring(p.sway_speed) .. '\n')
        file:write(prefix .. 'wallcheck_enabled=' .. tostring(p.wallcheck_enabled) .. '\n')
        file:write(prefix .. 'nearest_target_enabled=' .. tostring(p.nearest_target_enabled ~= false) .. '\n')
        file:write(prefix .. 'liquid_target_enabled=' .. tostring(p.liquid_target_enabled == true) .. '\n')
    end
    file:close()
    return true
end

local function loadCfg()
    makeCfgDir()

    local file = io.open(cfgPath, 'r')
    if not file then
        Speed.v = 10.0
        Dist.v = 20.0
        Fov.v = 15.0
        SwayAmount.v = 1.2
        SwaySpeed.v = 2.0
        aiming = 8
        cbz1.v = true
        cbz7.v = true
        commandInput.v = chatCommand
        holdKeyInput.v = keyName(holdKey)
        menuKey1Input.v = keyName(menuKey1)
        menuKey2Input.v = keyName(menuKey2)
        liquidResetKeyInput.v = keyName(liquidResetKey)
        whitelistToggleKeyInput.v = keyName(whitelistToggleKey)
        saveCfg()
        return
    end

    for line in file:lines() do
        local name, value = line:match('^([%w_]+)%s*=%s*(.-)%s*$')
        if name and value then
            if name == 'speed' then
                Speed.v = tonumber(value) or 10.0
            elseif name == 'dist' then
                Dist.v = tonumber(value) or 20.0
            elseif name == 'fov' then
                Fov.v = tonumber(value) or 15.0
            elseif name == 'aiming' then
                aiming = tonumber(value) or 8
            elseif name == 'sway_enabled' then
                cbz6.v = value == 'true'
            elseif name == 'sway_amount' then
                SwayAmount.v = tonumber(value) or 1.2
            elseif name == 'sway_speed' then
                SwaySpeed.v = tonumber(value) or 2.0
            elseif name == 'wallcheck_enabled' then
                cbz7.v = value == 'true'
            elseif name == 'ignore_anim_1151' then
                cbz8.v = value == 'true'
            elseif name == 'command' then
                chatCommand = trim(value):gsub('^/', '')
            elseif name == 'hold_key' then
                holdKey = tonumber(value) or 0x31
            elseif name == 'activation_toggle_mode' then
                activationToggleMode.v = value == 'true'
            elseif name == 'activation_toggled' then
                activationToggled = value == 'true'
            elseif name == 'menu_key_1' then
                menuKey1 = tonumber(value) or key.VK_Q
            elseif name == 'menu_key_2' then
                menuKey2 = tonumber(value) or key.VK_E
            elseif name == 'liquid_reset_key' then
                liquidResetKey = tonumber(value) or 0x34
            elseif name == 'whitelist_toggle_key' then
                whitelistToggleKey = tonumber(value) or 0x35
            elseif name == 'whitelist_notifications' then
                whitelistNotifications.v = value == 'true'
            elseif name == 'auto_check_updates' then
                autoCheckUpdates.v = value == 'true'
            else
                local otherField = name:match('^weapon_other_(.+)$')
                if otherField then
                    local p = gunCfg.other
                    if otherField == 'speed' then p.speed = tonumber(value) or p.speed
                    elseif otherField == 'dist' then p.dist = tonumber(value) or p.dist
                    elseif otherField == 'fov' then p.fov = tonumber(value) or p.fov
                    elseif otherField == 'aiming' then p.aiming = tonumber(value) or p.aiming
                    elseif otherField == 'sway_enabled' then p.sway_enabled = value == 'true'
                    elseif otherField == 'sway_amount' then p.sway_amount = tonumber(value) or p.sway_amount
                    elseif otherField == 'sway_speed' then p.sway_speed = tonumber(value) or p.sway_speed
                    elseif otherField == 'wallcheck_enabled' then p.wallcheck_enabled = value == 'true'
                    elseif otherField == 'nearest_target_enabled' then p.nearest_target_enabled = value == 'true'
                    elseif otherField == 'liquid_target_enabled' then p.liquid_target_enabled = value == 'true'
                    end
                else
                local id, field = name:match('^weapon(%d+)_(.+)$')
                id = tonumber(id)
                local p = gunCfg[id]
                if p and field then
                    if field == 'enabled' then p.enabled = value == 'true'
                    elseif field == 'speed' then p.speed = tonumber(value) or p.speed
                    elseif field == 'dist' then p.dist = tonumber(value) or p.dist
                    elseif field == 'fov' then p.fov = tonumber(value) or p.fov
                    elseif field == 'aiming' then p.aiming = tonumber(value) or p.aiming
                    elseif field == 'sway_enabled' then p.sway_enabled = value == 'true'
                    elseif field == 'sway_amount' then p.sway_amount = tonumber(value) or p.sway_amount
                    elseif field == 'sway_speed' then p.sway_speed = tonumber(value) or p.sway_speed
                    elseif field == 'wallcheck_enabled' then p.wallcheck_enabled = value == 'true'
                    elseif field == 'nearest_target_enabled' then p.nearest_target_enabled = value == 'true'
                    elseif field == 'liquid_target_enabled' then p.liquid_target_enabled = value == 'true'
                    end
                end
                end
            end
        end
    end
    file:close()

    commandInput.v = chatCommand
    holdKeyInput.v = keyName(holdKey)
    menuKey1Input.v = keyName(menuKey1)
    menuKey2Input.v = keyName(menuKey2)

    cbz1.v = aiming == 8
    cbz2.v = aiming == 3
    cbz3.v = aiming == 42
    cbz4.v = aiming == 54
    cbz9.v = aiming == -1
end

local function setAimingCheckboxes(bone)
    aiming = tonumber(bone) or 8
    cbz1.v = aiming == 8
    cbz2.v = aiming == 3
    cbz3.v = aiming == 42
    cbz4.v = aiming == 54
    cbz9.v = aiming == -1
end

local function updateGunCfg(id)
    local p = gunCfg[id]
    if not p then return false end
    p.enabled = aimEnabled.v
    p.speed = Speed.v
    p.dist = Dist.v
    p.fov = Fov.v
    p.aiming = aiming
    p.sway_enabled = cbz6.v
    p.sway_amount = SwayAmount.v
    p.sway_speed = SwaySpeed.v
    p.wallcheck_enabled = cbz7.v
    p.nearest_target_enabled = nearestTargetEnabled.v
    p.liquid_target_enabled = liquidTargetEnabled.v
    return true
end

local function saveGunCfg(id)
    if not updateGunCfg(id) then return end
    saveCfg()
    saveMsgUntil = os.clock() + 2.5
end

local function loadGunCfg(id)
    local p = gunCfg[id]
    if not p then return false end
    aimEnabled.v = p.enabled ~= false
    Speed.v = p.speed
    Dist.v = p.dist
    Fov.v = p.fov
    SwayAmount.v = p.sway_amount
    SwaySpeed.v = p.sway_speed
    cbz6.v = p.sway_enabled
    cbz7.v = p.wallcheck_enabled
    nearestTargetEnabled.v = p.nearest_target_enabled ~= false
    liquidTargetEnabled.v = p.liquid_target_enabled == true
    setAimingCheckboxes(p.aiming)
    return true
end

local function parseVersion(version)
    local result = {}
    for number in tostring(version or ''):gmatch('%d+') do
        result[#result + 1] = tonumber(number) or 0
    end
    return result
end

local function isVersionNewer(remote, current)
    local a = parseVersion(remote)
    local b = parseVersion(current)
    local count = math.max(#a, #b)
    for i = 1, count do
        local av = a[i] or 0
        local bv = b[i] or 0
        if av > bv then return true end
        if av < bv then return false end
    end
    return false
end

local function downloadFinished(status)
    return status == dlstatus.STATUS_ENDDOWNLOADDATA
        or status == dlstatus.STATUSEX_ENDDOWNLOAD
end

local function validDownloadedScript(path)
    local file = io.open(path, 'rb')
    if not file then return false end
    local data = file:read('*a') or ''
    file:close()
    return #data > 1000 and data:find("local imgui", 1, true) ~= nil
end

local function installUpdate()
    if updateDownloading then return end
    updateDownloading = true
    updateStatusText = 'Начата загрузка версии ' .. tostring(remoteVersion) .. '...'
    if isSampAvailable() then
        chatMessage('[M-AIM] Начата загрузка обновления ' .. tostring(remoteVersion) .. '...')
    end
    os.remove(updateScriptPath)

    local callbackFinished = false
    downloadUrlToFile(SCRIPT_URL .. '?t=' .. tostring(os.time()), updateScriptPath, function(_, status)
        if callbackFinished or not downloadFinished(status) then return end
        callbackFinished = true
        updateDownloading = false

        if not validDownloadedScript(updateScriptPath) then
            os.remove(updateScriptPath)
            updateStatusText = 'Ошибка: получен повреждённый файл'
            chatMessage('[M-AIM] Ошибка загрузки: файл повреждён.')
            updateMsgUntil = os.clock() + 5.0
            return
        end

        local currentPath = thisScript().path
        local backupPath = currentPath .. '.bak'
        os.remove(backupPath)

        local backupOk = os.rename(currentPath, backupPath)
        if not backupOk then
            updateStatusText = 'Ошибка замены текущего файла'
            chatMessage('[M-AIM] Ошибка: не удалось заменить текущий файл.')
            updateMsgUntil = os.clock() + 5.0
            return
        end

        local replaceOk = os.rename(updateScriptPath, currentPath)
        if not replaceOk then
            os.rename(backupPath, currentPath)
            updateStatusText = 'Ошибка установки обновления'
            chatMessage('[M-AIM] Ошибка установки обновления.')
            updateMsgUntil = os.clock() + 5.0
            return
        end

        os.remove(backupPath)
        updateAvailable = false
        updateStatusText = 'Обновлено до ' .. tostring(remoteVersion)
        if isSampAvailable() then
            chatMessage('[M-AIM] Обновление загружено и установлено. Перезапуск скрипта...')
        end
        lua_thread.create(function()
            wait(800)
            thisScript():reload()
        end)
    end)
end

local function checkForUpdates(manual, autoInstall)
    if updateChecking or updateDownloading then return end
    updateChecking = true
    updateStatusText = 'Проверка обновлений...'
    os.remove(updateVersionPath)

    local callbackFinished = false
    downloadUrlToFile(VERSION_URL .. '?t=' .. tostring(os.time()), updateVersionPath, function(_, status)
        if callbackFinished or not downloadFinished(status) then return end
        callbackFinished = true
        updateChecking = false

        local file = io.open(updateVersionPath, 'r')
        if not file then
            updateStatusText = 'Не удалось проверить обновление'
            updateMsgUntil = os.clock() + 5.0
            return
        end

        local version = trim(file:read('*a'))
        file:close()
        os.remove(updateVersionPath)

        if version == '' then
            updateStatusText = 'Файл version.txt пуст'
            updateMsgUntil = os.clock() + 5.0
            return
        end

        remoteVersion = version
        updateAvailable = isVersionNewer(remoteVersion, CURRENT_VERSION)

        if updateAvailable then
            updateStatusText = 'Доступна версия ' .. remoteVersion
            if autoInstall then
                installUpdate()
                return
            end
            if isSampAvailable() then
                chatMessage('[M-AIM] Найдено обновление ' .. remoteVersion .. '. Нажми ОБНОВИТЬ.')
            end
            updateMsgUntil = os.clock() + 8.0
        else
            updateStatusText = 'Установлена последняя версия ' .. CURRENT_VERSION
            if manual and isSampAvailable() then
                chatMessage('[M-AIM] Обновлений нет. Версия ' .. CURRENT_VERSION .. '.')
            end
            updateMsgUntil = os.clock() + 4.0
        end
    end)
end

local function activationActive()
    if sampIsChatInputActive() or sampIsDialogActive() then
        return false
    end

    if activationToggleMode.v then
        return activationToggled
    end

    return isKeyDown(holdKey)
end

function sampev.onSendGiveDamage(playerId, damage, weaponId, bodypart)
    local currentWeapon = getCurrentCharWeapon(PLAYER_PED)
    local profileId = weaponToProfile[currentWeapon]
    local cfg = profileId and gunCfg[profileId] or nil

    if cfg and cfg.liquid_target_enabled == true then
        liquidTargetPlayerId = tonumber(playerId) or -1
        liquidTargetUntil = os.clock() + 2.0
    end
end

local function resetLiquidTarget()
    liquidTargetPlayerId = -1
    liquidTargetUntil = 0.0
end

local function getPlayerUnderCrosshair()
    local camX, camY, camZ = getActiveCameraCoordinates()
    local viewX = fix(representIntAsFloat(readMemory(0xB6F258, 4, false)))
    local viewY = fix(representIntAsFloat(readMemory(0xB6F248, 4, false)))
    local zFix = isWidescreenOnInOptions() and 0.0778 or 0.103
    local bestPlayerId = -1
    local bestAngle = math.rad(4.0)
    local _, myId = sampGetPlayerIdByCharHandle(PLAYER_PED)

    for playerId = 0, sampGetMaxPlayerId(true) do
        if playerId ~= myId and sampIsPlayerConnected(playerId) then
            local found, handle = sampGetCharHandleBySampPlayerId(playerId)
            if found and isCharOnScreen(handle) and not isCharDead(handle) then
                local x, y, z = GetBodyPartCoordinates(3, handle)
                if isLineOfSightClear(camX, camY, camZ, x, y, z, true, true, false, true, true, false, false) then
                    local dx, dy, dz = camX - x, camY - y, camZ - z
                    local angleX = math.atan2(dy, dx) + 0.04253
                    local angleY = math.atan2(math.sqrt(dx * dx + dy * dy), dz) - math.pi / 2 - zFix
                    local angle = math.sqrt(fix(angleX - viewX) ^ 2 + fix(angleY - viewY) ^ 2)

                    if angle < bestAngle then
                        bestAngle = angle
                        bestPlayerId = playerId
                    end
                end
            end
        end
    end

    return bestPlayerId
end

local function toggleAimedPlayerWhitelist()
    if not isKeyDown(key.VK_RBUTTON) then return end

    local playerId = getPlayerUnderCrosshair()
    if playerId == -1 then return end

    local nickname = sampGetPlayerNickname(playerId)
    if inWhitelist(nickname) then
        removeWL(nickname)
        if whitelistNotifications.v then
            chatMessage('[M-AIM] ' .. nickname .. ' удалён из белого списка.')
        end
    else
        addWL(nickname)
        if whitelistNotifications.v then
            chatMessage('[M-AIM] ' .. nickname .. ' добавлен в белый список.')
        end
    end
end

function main()
    repeat wait(0) until isSampAvailable()

    loadCfg()
    loadWL()

    registerMenuCommand()

    lua_thread.create(MAIM)

    -- Проверяем обновления не только при запуске, но и во время игры.
    lua_thread.create(function()
        wait(1500)
        while true do
            if autoCheckUpdates.v then
                checkForUpdates(false)
            end
            wait(30000) -- раз в 60 секунд
        end
    end)

    local menuPressed = false
    local oldCfgState = ''

    while true do
        wait(0)

        local whitelistToggleDown = isKeyDown(whitelistToggleKey)
        if whitelistToggleDown and not whitelistToggleKeyWasDown
        and not sampIsChatInputActive() and not sampIsDialogActive() then
            toggleAimedPlayerWhitelist()
        end
        whitelistToggleKeyWasDown = whitelistToggleDown

        local liquidResetDown = isKeyDown(liquidResetKey)
        if liquidResetDown and not liquidResetKeyWasDown
        and not sampIsChatInputActive() and not sampIsDialogActive() then
            resetLiquidTarget()
        end
        liquidResetKeyWasDown = liquidResetDown

        local activationKeyDown = isKeyDown(holdKey)
        if activationToggleMode.v and activationKeyDown and not activationKeyWasDown
        and not sampIsChatInputActive() and not sampIsDialogActive() then
            activationToggled = not activationToggled
            saveCfg()
        end
        activationKeyWasDown = activationKeyDown

        if not windows.v then
            imgui.Process = false
        end

        local menuKeys = isKeyDown(menuKey1) and isKeyDown(menuKey2)
        if menuKeys and not menuPressed then
            windows.v = not windows.v
            imgui.Process = windows.v
        end
        menuPressed = menuKeys

        if cbz1.v then
            aiming = 8
            cbz2.v, cbz3.v, cbz4.v, cbz9.v = false, false, false, false
        elseif cbz2.v then
            aiming = 3
            cbz1.v, cbz3.v, cbz4.v, cbz9.v = false, false, false, false
        elseif cbz3.v then
            aiming = 42
            cbz1.v, cbz2.v, cbz4.v, cbz9.v = false, false, false, false
        elseif cbz4.v then
            aiming = 54
            cbz1.v, cbz2.v, cbz3.v, cbz9.v = false, false, false, false
        elseif cbz9.v then
            aiming = -1
            cbz1.v, cbz2.v, cbz3.v, cbz4.v = false, false, false, false
        end

        local cfgState = table.concat({
            string.format('%.3f', Speed.v),
            string.format('%.3f', Dist.v),
            string.format('%.3f', Fov.v),
            tostring(aiming),
            tostring(cbz5.v),
            tostring(cbz6.v),
            string.format('%.3f', SwayAmount.v),
            string.format('%.3f', SwaySpeed.v),
            tostring(cbz7.v),
            tostring(cbz8.v),
            tostring(cbz9.v),
            chatCommand, tostring(holdKey), tostring(activationToggleMode.v), tostring(activationToggled), tostring(menuKey1), tostring(menuKey2), tostring(liquidResetKey), tostring(whitelistToggleKey), tostring(whitelistNotifications.v), tostring(autoCheckUpdates.v)
        }, '|')

        if cfgState ~= oldCfgState then
            -- Не записываем настройки наведения в профиль автоматически.
            -- Профиль сохраняется только кнопкой «СОХРАНИТЬ ПРОФИЛЬ».
            oldCfgState = cfgState
        end
    end
end

function imgui.OnDrawFrame()
    if not windows.v then return end

    imgui.SetNextWindowPos(imgui.ImVec2(175.0, 135.0), imgui.Cond.FirstUseEver)
    imgui.SetNextWindowSize(imgui.ImVec2(980.0, 690.0), imgui.Cond.FirstUseEver)

    local flags = imgui.WindowFlags.NoResize + imgui.WindowFlags.NoCollapse + imgui.WindowFlags.ShowBorders
    imgui.Begin(u8('M-AIM  |  НОВОЕ'), windows, flags)

    local holdActive = activationActive()
    local activeCount = 0
    for _ in pairs(whitelist) do activeCount = activeCount + 1 end

    imgui.BeginChild('Header', imgui.ImVec2(0, 68), true)
    imgui.PushFont(fontsize)
    imgui.Text(u8('M-AIM'))
    imgui.PopFont()

    local versionText = u8('Версия: ' .. CURRENT_VERSION)
    local buttonText = updateDownloading and u8('ЗАГРУЗКА...') or u8('ОБНОВИТЬ')
    local buttonWidth = 112
    local versionWidth = imgui.CalcTextSize(versionText).x
    imgui.SetCursorPos(imgui.ImVec2(imgui.GetWindowWidth() - versionWidth - buttonWidth - 34, 10))
    imgui.TextDisabled(versionText)
    imgui.SameLine()
    if imgui.Button(buttonText, imgui.ImVec2(buttonWidth, 28)) and not updateDownloading and not updateChecking then
        if updateAvailable then
            installUpdate()
        else
            updateStatusText = 'Проверка и загрузка обновления...'
            checkForUpdates(true, true)
        end
    end

    imgui.SetCursorPosY(38)
    if holdActive then
        imgui.Text(u8('АКТИВЕН'))
    else
        if activationToggleMode.v then
            imgui.TextDisabled(u8('НАЖМИ ' .. keyName(holdKey) .. ' ДЛЯ ВКЛ/ВЫКЛ'))
        else
            imgui.TextDisabled(u8('УДЕРЖИВАЙ ' .. keyName(holdKey)))
        end
    end
    imgui.SameLine(240)
    imgui.TextDisabled(u8(keyName(menuKey1) .. ' + ' .. keyName(menuKey2) .. ' — меню'))
    imgui.SameLine(430)
    imgui.TextDisabled(u8('/' .. chatCommand .. ' — команда'))
    imgui.SameLine(710)
    imgui.TextDisabled(u8('Белый список: ') .. tostring(activeCount))
    imgui.EndChild()

    imgui.Dummy(imgui.ImVec2(0, 8))

    imgui.BeginChild('Left', imgui.ImVec2(305, 500), true)
    imgui.Text(u8('НАВЕДЕНИЕ'))
    imgui.Separator()
    imgui.Dummy(imgui.ImVec2(0, 8))

    imgui.PushItemWidth(185.0)
    imgui.SliderFloat(u8('Скорость##speed'), Speed, 1.0, 50.0, '%.1f')
    imgui.SliderFloat(u8('Дистанция##dist'), Dist, 1.0, 100.0, '%.1f')
    imgui.SliderFloat(u8('Угол обзора##fov'), Fov, 1.0, 100.0, '%.1f')
    imgui.PopItemWidth()

    imgui.Dummy(imgui.ImVec2(0, 12))
    imgui.Text(u8('ТОЧКА'))
    imgui.Separator()
    if imgui.Checkbox(u8('Голова'), cbz1) and cbz1.v then setAimingCheckboxes(8) end
    imgui.SameLine(150)
    if imgui.Checkbox(u8('Торс'), cbz2) and cbz2.v then setAimingCheckboxes(3) end
    if imgui.Checkbox(u8('Стопа'), cbz3) and cbz3.v then setAimingCheckboxes(42) end
    imgui.SameLine(150)
    if imgui.Checkbox(u8('Нога'), cbz4) and cbz4.v then setAimingCheckboxes(54) end
    if imgui.Checkbox(u8('Ближайшая точка'), cbz9) and cbz9.v then setAimingCheckboxes(-1) end

    imgui.Dummy(imgui.ImVec2(0, 12))
    imgui.Text(u8('ДОПОЛНИТЕЛЬНО'))
    imgui.Separator()
    imgui.Checkbox(u8('Плавное смещение'), cbz6)
    imgui.Checkbox(u8('Проверка стен'), cbz7)
    imgui.Checkbox(u8('Игнорировать анимацию 1151'), cbz8)

    if cbz6.v then
        imgui.PushItemWidth(185.0)
        imgui.SliderFloat(u8('Размах##swayamount'), SwayAmount, 0.1, 5.0, '%.1f')
        imgui.SliderFloat(u8('Темп##swayspeed'), SwaySpeed, 0.2, 8.0, '%.1f')
        imgui.PopItemWidth()
    end
    imgui.EndChild()

    imgui.SameLine()

    imgui.BeginChild('Center', imgui.ImVec2(300, 500), true)
    imgui.Text(u8('ПРОФИЛИ ОРУЖИЯ'))
    imgui.Separator()
    imgui.TextDisabled(u8('Активный: ') .. u8(profileName))
    imgui.Dummy(imgui.ImVec2(0, 8))
    imgui.Checkbox(u8('Аим включён для профиля'), aimEnabled)
    imgui.Checkbox(u8('Стрелять в ближайшего'), nearestTargetEnabled)
    imgui.Checkbox(u8('Стрелять ликвид'), liquidTargetEnabled)
    imgui.Dummy(imgui.ImVec2(0, 6))

    if imgui.Button(u8('DEAGLE  24/31'), imgui.ImVec2(134, 34)) then
        editProfile = 24
        profileName = profileLabels[24]
        loadGunCfg(24)
    end
    imgui.SameLine()
    if imgui.Button(u8('M4  107/108'), imgui.ImVec2(134, 34)) then
        editProfile = 107
        profileName = profileLabels[107]
        loadGunCfg(107)
    end
    if imgui.Button(u8('UZI  103/104'), imgui.ImVec2(134, 34)) then
        editProfile = 103
        profileName = profileLabels[103]
        loadGunCfg(103)
    end
    imgui.SameLine()
    if imgui.Button(u8('БИТА  76/5'), imgui.ImVec2(134, 34)) then
        editProfile = 76
        profileName = profileLabels[76]
        loadGunCfg(76)
    end
    imgui.Dummy(imgui.ImVec2(0, 8))
    if imgui.Button(u8('СОХРАНИТЬ ПРОФИЛЬ'), imgui.ImVec2(-1, 36)) then
        saveGunCfg(editProfile)
    end

    if os.clock() < saveMsgUntil then
        imgui.Text(u8('Настройки сохранены'))
    else
        imgui.TextDisabled(u8('Аим работает только на указанных ID оружия.'))
    end

    imgui.Dummy(imgui.ImVec2(0, 12))
    imgui.Text(u8('УПРАВЛЕНИЕ'))
    imgui.Separator()
    imgui.PushItemWidth(145)
    imgui.InputText(u8('Команда##cmd'), commandInput)
    imgui.InputText(u8('Активация##hold'), holdKeyInput)
    if imgui.Checkbox(u8('Включать по нажатию'), activationToggleMode) then
        activationToggled = false
    end
    imgui.InputText(u8('Меню 1##menu1'), menuKey1Input)
    imgui.InputText(u8('Меню 2##menu2'), menuKey2Input)
    imgui.InputText(u8('Сброс ликвид##liquidreset'), liquidResetKeyInput)
    imgui.InputText(u8('Белый список##whitelisttoggle'), whitelistToggleKeyInput)
    imgui.PopItemWidth()
    imgui.Checkbox(u8('Уведомления белого списка'), whitelistNotifications)
    if imgui.Checkbox(u8('Проверять обновления при запуске'), autoCheckUpdates) then
        saveCfg()
    end

    imgui.TextDisabled(u8(updateStatusText))

    if imgui.Button(u8('ПРИМЕНИТЬ УПРАВЛЕНИЕ'), imgui.ImVec2(-1, 34)) then
        chatCommand = trim(u8:decode(commandInput.v)):gsub('^/', ''):lower()
        if chatCommand == '' then chatCommand = 'maim' end
        holdKey = keyCode(u8:decode(holdKeyInput.v), holdKey)
        menuKey1 = keyCode(u8:decode(menuKey1Input.v), menuKey1)
        menuKey2 = keyCode(u8:decode(menuKey2Input.v), menuKey2)
        liquidResetKey = keyCode(u8:decode(liquidResetKeyInput.v), liquidResetKey)
        whitelistToggleKey = keyCode(u8:decode(whitelistToggleKeyInput.v), whitelistToggleKey)
        commandInput.v = chatCommand
        holdKeyInput.v = keyName(holdKey)
        menuKey1Input.v = keyName(menuKey1)
        menuKey2Input.v = keyName(menuKey2)
        liquidResetKeyInput.v = keyName(liquidResetKey)
        whitelistToggleKeyInput.v = keyName(whitelistToggleKey)
        registerMenuCommand()
        saveCfg()
        controlMsgUntil = os.clock() + 2.5
    end

    if os.clock() < controlMsgUntil then
        imgui.Text(u8('Управление сохранено'))
    else
        imgui.TextDisabled(u8('Пример клавиш: Q, 1, F5, SHIFT'))
    end
    imgui.EndChild()

    imgui.SameLine()

    imgui.BeginChild('Right', imgui.ImVec2(0, 500), true)
    imgui.Text(u8('БЕЛЫЙ СПИСОК'))
    imgui.SameLine(210)
    imgui.TextDisabled(tostring(activeCount))
    imgui.Separator()
    imgui.Dummy(imgui.ImVec2(0, 6))

    imgui.PushItemWidth(210.0)
    imgui.InputText(u8('##whitelist_nick'), wlInput)
    imgui.PopItemWidth()
    imgui.SameLine()
    if imgui.Button(u8('+'), imgui.ImVec2(38, 0)) then
        local typedName = u8:decode(wlInput.v)
        if addWL(typedName) then wlInput.v = '' end
    end

    imgui.Dummy(imgui.ImVec2(0, 7))
    imgui.BeginChild('WhitelistList', imgui.ImVec2(0, 370), true)
    local names = {}
    for _, nick in pairs(whitelist) do names[#names + 1] = nick end
    table.sort(names, function(a, b) return a:lower() < b:lower() end)

    if #names == 0 then
        imgui.Dummy(imgui.ImVec2(0, 145))
        imgui.CenterText(u8('СПИСОК ПУСТ'))
    else
        for index, name in ipairs(names) do
            imgui.Text(u8(name))
            imgui.SameLine(205)
            if imgui.SmallButton(u8('?##wl_') .. tostring(index)) then
                removeWL(name)
            end
            if index < #names then imgui.Separator() end
        end
    end
    imgui.EndChild()

    imgui.Dummy(imgui.ImVec2(0, 8))
    imgui.TextDisabled(u8('Игроки из списка полностью игнорируются.'))
    imgui.EndChild()

    imgui.Separator()
    local authorText = u8('Автор: @pashenkov тг')
    local authorWidth = imgui.CalcTextSize(authorText).x
    imgui.SetCursorPosX((imgui.GetWindowWidth() - authorWidth) / 2)
    imgui.Text(authorText)
    if imgui.IsItemClicked() then
        os.execute('start "" "https://t.me/pashenkov"')
    end
    if imgui.IsItemHovered() then
        imgui.SetTooltip(u8('Открыть Telegram'))
    end

    imgui.End()
end

function fix(angle)
    if angle > math.pi then
        angle = angle - (math.pi * 2)
    elseif angle < -math.pi then
        angle = angle + (math.pi * 2)
    end
    return angle
end

local function canSee(x, y, z, cfg)
    if not cfg.wallcheck_enabled then
        return true
    end

    local camX, camY, camZ = getActiveCameraCoordinates()

    return isLineOfSightClear(
        camX, camY, camZ,
        x, y, z,
        true,
        true,
        false,
        true,
        true,
        false,
        false
    )
end

local function ignoreAnim(playerId)
    if not cbz8.v then
        return false
    end

    local ok, animationId = pcall(sampGetPlayerAnimationId, playerId)
    return ok and tonumber(animationId) == 1151
end

local aimBones = {8, 7, 6, 5, 4, 3, 2, 1, 42, 43, 44, 51, 52, 53, 54, 55, 56}

local function getTargetPoint(handle, cfg)
    if cfg.aiming ~= -1 then
        local x, y, z = GetBodyPartCoordinates(cfg.aiming, handle)
        return x, y, z
    end

    local camX, camY, camZ = getActiveCameraCoordinates()
    local viewX = fix(representIntAsFloat(readMemory(0xB6F258, 4, false)))
    local viewY = fix(representIntAsFloat(readMemory(0xB6F248, 4, false)))
    local zFix = isWidescreenOnInOptions() and 0.0778 or 0.103
    local bestX, bestY, bestZ
    local bestAngle = math.huge

    for _, bone in ipairs(aimBones) do
        local x, y, z = GetBodyPartCoordinates(bone, handle)
        local dx, dy, dz = camX - x, camY - y, camZ - z
        local aX = math.atan2(dy, dx) + 0.04253
        local aY = math.atan2(math.sqrt(dx * dx + dy * dy), dz) - math.pi / 2 - zFix
        local angle = math.sqrt((fix(aX - viewX) ^ 2) + (fix(aY - viewY) ^ 2))

        if angle < bestAngle then
            bestAngle = angle
            bestX, bestY, bestZ = x, y, z
        end
    end

    return bestX, bestY, bestZ
end

local function getNearestPed(cfg)
    local bestMetric = math.huge
    local nearestPED = -1

    for i = 0, sampGetMaxPlayerId(true) do
        if sampIsPlayerConnected(i) then
            local find, handle = sampGetCharHandleBySampPlayerId(i)
            if find and isCharOnScreen(handle) and not isCharDead(handle) then
                local _, myId = sampGetPlayerIdByCharHandle(PLAYER_PED)
                local nickname = sampGetPlayerNickname(i)

                if i ~= myId and not inWhitelist(nickname) and not ignoreAnim(i) then
                    local enX, enY, enZ = getTargetPoint(handle, cfg)

                    if canSee(enX, enY, enZ, cfg) then
                        local camX, camY, camZ = getActiveCameraCoordinates()
                        local vectorX = camX - enX
                        local vectorY = camY - enY
                        local vectorZ = camZ - enZ
                        local coefficentZ = isWidescreenOnInOptions() and 0.0778 or 0.103
                        local angleX = math.atan2(vectorY, vectorX) + 0.04253
                        local angleY = math.atan2(math.sqrt(vectorX * vectorX + vectorY * vectorY), vectorZ) - math.pi / 2 - coefficentZ
                        local viewX = fix(representIntAsFloat(readMemory(0xB6F258, 4, false)))
                        local viewY = fix(representIntAsFloat(readMemory(0xB6F248, 4, false)))
                        local screenDistance = math.sqrt((angleX - viewX) ^ 2 + (angleY - viewY) ^ 2) * 57.2957795131

                        if screenDistance <= cfg.fov then
                            local myX, myY, myZ = getCharCoordinates(PLAYER_PED)
                            local worldDistance = math.sqrt((enX - myX) ^ 2 + (enY - myY) ^ 2 + (enZ - myZ) ^ 2)

                            if worldDistance <= cfg.dist then
                                -- Для каждого профиля оружия отдельно:
                                -- true = ближайший по дистанции, false = ближайший к прицелу.
                                local metric = cfg.nearest_target_enabled and worldDistance or screenDistance
                                if metric < bestMetric then
                                    nearestPED = handle
                                    bestMetric = metric
                                end
                            end
                        end
                    end
                end
            end
        end
    end

    return nearestPED
end

function MAIM()
    local currentTarget = -1
    local currentProfile = nil
    local nextTargetSearch = 0.0
    local lastFrameTime = os.clock()

    while true do
        wait(0)

        local now = os.clock()
        local deltaTime = now - lastFrameTime
        lastFrameTime = now

        if deltaTime <= 0.0 or deltaTime > 0.1 then
            deltaTime = 1.0 / 60.0
        end

        local weapon = getCurrentCharWeapon(PLAYER_PED)
        local profileId = weaponToProfile[weapon]
        local cfg = profileId and gunCfg[profileId] or nil

        if profileId ~= currentProfile then
            currentProfile = profileId
            currentTarget = -1
            nextTargetSearch = 0.0
        end

        local isBatProfile = profileId == 76
        local attackKeysActive = isBatProfile
            or (isKeyDown(key.VK_RBUTTON) and isKeyDown(key.VK_LBUTTON))

        local active = cfg
            and cfg.enabled ~= false
            and activationActive()
            and cfg.speed > 0
            and attackKeysActive

        if not active then
            currentTarget = -1
        else
            local targetValid = currentTarget ~= -1
                and doesCharExist(currentTarget)
                and not isCharDead(currentTarget)
                and isCharOnScreen(currentTarget)

            if targetValid then
                local tx, ty, tz = getTargetPoint(currentTarget, cfg)
                targetValid = tx ~= nil and canSee(tx, ty, tz, cfg)
            end

            if cfg.liquid_target_enabled == true then
                if liquidTargetPlayerId ~= -1 and now < liquidTargetUntil then
                    local found, lockedHandle = sampGetCharHandleBySampPlayerId(liquidTargetPlayerId)
                    if found and doesCharExist(lockedHandle) and not isCharDead(lockedHandle) then
                        currentTarget = lockedHandle
                    else
                        resetLiquidTarget()
                        currentTarget = -1
                    end
                else
                    if now >= liquidTargetUntil then resetLiquidTarget() end
                    currentTarget = -1
                end
            elseif not targetValid or now >= nextTargetSearch then
                local foundTarget = getNearestPed(cfg)

                if foundTarget ~= -1 then
                    currentTarget = foundTarget
                elseif not targetValid then
                    currentTarget = -1
                end

                nextTargetSearch = now + 0.04
            end

            if currentTarget ~= -1 then
                local camX, camY, camZ = getActiveCameraCoordinates()
                local targetX, targetY, targetZ = getTargetPoint(currentTarget, cfg)

                if targetX and canSee(targetX, targetY, targetZ, cfg) then
                    local vectorX = camX - targetX
                    local vectorY = camY - targetY
                    local vectorZ = camZ - targetZ
                    local coefficentZ = isWidescreenOnInOptions() and 0.0778 or 0.103
                    local horizontalOffset = 0.0

                    if cfg.sway_enabled then
                        horizontalOffset = math.rad(cfg.sway_amount) * math.sin(now * cfg.sway_speed)
                    end

                    local targetAngleX = math.atan2(vectorY, vectorX) + 0.04253 + horizontalOffset
                    local targetAngleY = math.atan2(
                        math.sqrt(vectorX * vectorX + vectorY * vectorY),
                        vectorZ
                    ) - math.pi / 2 - coefficentZ

                    local viewX = fix(representIntAsFloat(readMemory(0xB6F258, 4, false)))
                    local viewY = fix(representIntAsFloat(readMemory(0xB6F248, 4, false)))

                    local differenceX = fix(targetAngleX - viewX)
                    local differenceY = fix(targetAngleY - viewY)

                    local response = 60.0 / math.max(cfg.speed, 1.0)
                    local smoothFactor = 1.0 - math.exp(-response * deltaTime)

                    local stepX = differenceX * smoothFactor
                    local stepY = differenceY * smoothFactor
                    local maxStep = math.rad(4.0) * math.max(deltaTime * 60.0, 0.5)

                    if stepX > maxStep then stepX = maxStep end
                    if stepX < -maxStep then stepX = -maxStep end
                    if stepY > maxStep then stepY = maxStep end
                    if stepY < -maxStep then stepY = -maxStep end

                    setCameraPositionUnfixed(
                        viewY + stepY,
                        viewX + stepX
                    )
                else
                    currentTarget = -1
                end
            end
        end
    end
end

imgui.SwitchContext()
local style = imgui.GetStyle()
local colors = style.Colors
local clr = imgui.Col
local ImVec4 = imgui.ImVec4

style.WindowPadding = imgui.ImVec2(12.0, 11.0)
style.WindowRounding = 8.0
style.WindowTitleAlign = imgui.ImVec2(0.02, 0.5)
style.ChildWindowRounding = 6.0
style.FrameRounding = 5.0
style.ItemSpacing = imgui.ImVec2(8.0, 7.0)
style.ItemInnerSpacing = imgui.ImVec2(6.0, 4.0)
style.ScrollbarSize = 10.0
style.ScrollbarRounding = 5.0
style.GrabMinSize = 9.0
style.GrabRounding = 4.0

colors[clr.Text]                   = ImVec4(0.90, 0.90, 0.92, 1.00)
colors[clr.TextDisabled]           = ImVec4(0.48, 0.49, 0.52, 1.00)
colors[clr.WindowBg]               = ImVec4(0.035, 0.037, 0.041, 0.99)
colors[clr.ChildWindowBg]          = ImVec4(0.060, 0.063, 0.070, 0.98)
colors[clr.PopupBg]                = ImVec4(0.070, 0.073, 0.080, 0.99)
colors[clr.Border]                 = ImVec4(0.18, 0.19, 0.21, 1.00)
colors[clr.BorderShadow]           = ImVec4(0.00, 0.00, 0.00, 0.00)
colors[clr.FrameBg]                = ImVec4(0.105, 0.108, 0.116, 1.00)
colors[clr.FrameBgHovered]         = ImVec4(0.145, 0.150, 0.160, 1.00)
colors[clr.FrameBgActive]          = ImVec4(0.185, 0.190, 0.202, 1.00)
colors[clr.TitleBg]                = ImVec4(0.045, 0.047, 0.052, 1.00)
colors[clr.TitleBgActive]          = ImVec4(0.060, 0.063, 0.070, 1.00)
colors[clr.TitleBgCollapsed]       = ImVec4(0.040, 0.042, 0.047, 1.00)
colors[clr.MenuBarBg]              = ImVec4(0.055, 0.058, 0.064, 1.00)
colors[clr.ScrollbarBg]            = ImVec4(0.040, 0.042, 0.047, 0.70)
colors[clr.ScrollbarGrab]          = ImVec4(0.22, 0.23, 0.25, 0.90)
colors[clr.ScrollbarGrabHovered]   = ImVec4(0.30, 0.31, 0.34, 1.00)
colors[clr.ScrollbarGrabActive]    = ImVec4(0.38, 0.39, 0.42, 1.00)
colors[clr.CheckMark]              = ImVec4(0.78, 0.79, 0.82, 1.00)
colors[clr.SliderGrab]             = ImVec4(0.58, 0.59, 0.62, 1.00)
colors[clr.SliderGrabActive]       = ImVec4(0.82, 0.83, 0.86, 1.00)
colors[clr.Button]                 = ImVec4(0.115, 0.118, 0.126, 1.00)
colors[clr.ButtonHovered]          = ImVec4(0.175, 0.180, 0.192, 1.00)
colors[clr.ButtonActive]           = ImVec4(0.245, 0.250, 0.265, 1.00)
colors[clr.Header]                 = ImVec4(0.135, 0.140, 0.150, 1.00)
colors[clr.HeaderHovered]          = ImVec4(0.195, 0.200, 0.212, 1.00)
colors[clr.HeaderActive]           = ImVec4(0.260, 0.265, 0.280, 1.00)
colors[clr.Separator]              = ImVec4(0.19, 0.20, 0.22, 1.00)
colors[clr.SeparatorHovered]       = ImVec4(0.34, 0.35, 0.38, 1.00)
colors[clr.SeparatorActive]        = ImVec4(0.48, 0.49, 0.52, 1.00)
colors[clr.ResizeGrip]             = ImVec4(0.20, 0.21, 0.23, 0.25)
colors[clr.ResizeGripHovered]      = ImVec4(0.35, 0.36, 0.39, 0.70)
colors[clr.ResizeGripActive]       = ImVec4(0.50, 0.51, 0.54, 0.95)
colors[clr.CloseButton]            = ImVec4(0.16, 0.17, 0.18, 0.55)
colors[clr.CloseButtonHovered]     = ImVec4(0.30, 0.31, 0.33, 1.00)
colors[clr.CloseButtonActive]      = ImVec4(0.42, 0.43, 0.46, 1.00)
colors[clr.TextSelectedBg]         = ImVec4(0.38, 0.39, 0.42, 0.35)
colors[clr.ComboBg]                = colors[clr.PopupBg]
colors[clr.ModalWindowDarkening]   = ImVec4(0.00, 0.00, 0.00, 0.72)
