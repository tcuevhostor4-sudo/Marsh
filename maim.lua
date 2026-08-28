local imgui = require 'imgui'
local encoding = require 'encoding'
local vkeys = require 'vkeys'
local ffi = require 'ffi'
local sampev = require 'lib.samp.events'
local dlstatus = require('moonloader').download_status

script_name('M-AIM')
script_author('M-NaPamPah')
script_version('1.2.21')

local CURRENT_VERSION = '1.2.21'
local SCRIPT_URL = 'https://raw.githubusercontent.com/tcuevhostor4-sudo/Marsh/main/maim.lua'

encoding.default = 'CP1251'
local u8 = encoding.UTF8

local cfgDir = getWorkingDirectory() .. '\\config'
local cfgFile = cfgDir .. '\\M-AIM.ini'
local updateFile = cfgDir .. '\\M-AIM_update.lua'

local menu = imgui.ImBool(false)
local welcome = imgui.ImBool(false)
local welcomeSeen = false
local enabled = true
local selected = 103
local targetId = -1
local targetUntil = 0
local toggleKey = 0xBD
local menuKey1, menuKey2 = vkeys.VK_Q, vkeys.VK_E
local toggleWasDown, menuWasDown = false, false
local keyInput = imgui.ImBuffer(16)
local font

local profiles = {
    [103] = { name = 'UZI 103/104', speed = 10, dist = 20, fov = 15, bone = 8, wall = true },
    [107] = { name = 'M4 107/108',  speed = 10, dist = 20, fov = 15, bone = 8, wall = true }
}

local weaponProfile = {
    [103] = 103, [104] = 103,
    [107] = 107, [108] = 107
}

local ui = {
    speed = imgui.ImFloat(10),
    dist = imgui.ImFloat(20),
    fov = imgui.ImFloat(15),
    wall = imgui.ImBool(true),
    head = imgui.ImBool(true),
    torso = imgui.ImBool(false),
    foot = imgui.ImBool(false),
    leg = imgui.ImBool(false),
    nearest = imgui.ImBool(false)
}

local keys = {
    ['-'] = 0xBD,
    MINUS = 0xBD,
    ['NUM-'] = 0x6D,
    NUMMINUS = 0x6D,
    SHIFT = vkeys.VK_SHIFT,
    CTRL = vkeys.VK_CONTROL,
    ALT = vkeys.VK_MENU,
    SPACE = vkeys.VK_SPACE,
    TAB = vkeys.VK_TAB,
    ENTER = vkeys.VK_RETURN,
    INSERT = vkeys.VK_INSERT,
    DELETE = vkeys.VK_DELETE,
    HOME = vkeys.VK_HOME,
    END = vkeys.VK_END
}

for i = 0, 9 do keys[tostring(i)] = 0x30 + i end
for i = 0, 25 do keys[string.char(65 + i)] = 0x41 + i end
for i = 1, 12 do keys['F' .. i] = 0x6F + i end

local getBonePosition = ffi.cast('int (__thiscall*)(void*, float*, int, bool)', 0x5E4280)

local function bonePos(handle, bone)
    local pos = ffi.new('float[3]')
    getBonePosition(ffi.cast('void*', getCharPointer(handle)), pos, bone, true)
    return pos[0], pos[1], pos[2]
end

local function fixAngle(a)
    if a > math.pi then return a - math.pi * 2 end
    if a < -math.pi then return a + math.pi * 2 end
    return a
end

local function makeCfgDir()
    if not doesDirectoryExist(cfgDir) then createDirectory(cfgDir) end
end

local function keyName(code)
    if code == 0xBD then return '-' end
    if code == 0x6D then return 'NUM-' end
    for name, value in pairs(keys) do
        if value == code and #name <= 8 then return name end
    end
    return tostring(code)
end

local function keyCode(text)
    text = tostring(text or ''):gsub('^%s+', ''):gsub('%s+$', ''):upper()
    return keys[text]
end

local function setBone(bone)
    ui.head.v = bone == 8
    ui.torso.v = bone == 3
    ui.foot.v = bone == 42
    ui.leg.v = bone == 54
    ui.nearest.v = bone == -1
end

local function loadProfile(id)
    local p = profiles[id]
    if not p then return end
    ui.speed.v = p.speed
    ui.dist.v = p.dist
    ui.fov.v = p.fov
    ui.wall.v = p.wall
    setBone(p.bone)
end

local function saveProfile(id)
    local p = profiles[id]
    if not p then return end

    p.speed = ui.speed.v
    p.dist = ui.dist.v
    p.fov = ui.fov.v
    p.wall = ui.wall.v

    if ui.head.v then p.bone = 8
    elseif ui.torso.v then p.bone = 3
    elseif ui.foot.v then p.bone = 42
    elseif ui.leg.v then p.bone = 54
    elseif ui.nearest.v then p.bone = -1
    else
        p.bone = 8
        setBone(8)
    end
end

local function saveConfig()
    makeCfgDir()
    saveProfile(selected)

    local f = io.open(cfgFile, 'w')
    if not f then return end

    f:write('enabled=' .. tostring(enabled) .. '\n')
    f:write('toggle_key=' .. tostring(toggleKey) .. '\n')
    f:write('welcome_seen=' .. tostring(welcomeSeen) .. '\n')

    for _, id in ipairs({103, 107}) do
        local p = profiles[id]
        f:write('weapon' .. id .. '_speed=' .. p.speed .. '\n')
        f:write('weapon' .. id .. '_dist=' .. p.dist .. '\n')
        f:write('weapon' .. id .. '_fov=' .. p.fov .. '\n')
        f:write('weapon' .. id .. '_aiming=' .. p.bone .. '\n')
        f:write('weapon' .. id .. '_wallcheck=' .. tostring(p.wall) .. '\n')
    end

    f:close()
end

local function loadConfig()
    makeCfgDir()
    local f = io.open(cfgFile, 'r')

    if not f then
        keyInput.v = keyName(toggleKey)
        loadProfile(selected)
        saveConfig()
        return
    end

    for line in f:lines() do
        local name, value = line:match('^([%w_]+)%s*=%s*(.-)%s*$')
        if name == 'enabled' then
            enabled = value == 'true'
        elseif name == 'toggle_key' then
            toggleKey = tonumber(value) or toggleKey
        elseif name == 'welcome_seen' then
            welcomeSeen = value == 'true'
        elseif name then
            local id, field = name:match('^weapon(%d+)_(.+)$')
            id = tonumber(id)
            local p = id and profiles[id]
            if p then
                if field == 'speed' then p.speed = tonumber(value) or p.speed
                elseif field == 'dist' then p.dist = tonumber(value) or p.dist
                elseif field == 'fov' then p.fov = tonumber(value) or p.fov
                elseif field == 'aiming' then p.bone = tonumber(value) or p.bone
                elseif field == 'wallcheck' then p.wall = value == 'true' end
            end
        end
    end

    f:close()
    keyInput.v = keyName(toggleKey)
    loadProfile(selected)
end

local function readFile(path)
    local f = io.open(path, 'rb')
    if not f then return nil end
    local data = f:read('*a')
    f:close()
    return data
end

local function writeFile(path, data)
    local f = io.open(path, 'wb')
    if not f then return false end
    local ok = f:write(data)
    f:close()
    return ok ~= nil
end

local function versionNewer(a, b)
    local aa, bb = {}, {}
    for n in tostring(a):gmatch('%d+') do aa[#aa + 1] = tonumber(n) end
    for n in tostring(b):gmatch('%d+') do bb[#bb + 1] = tonumber(n) end

    for i = 1, math.max(#aa, #bb) do
        local x, y = aa[i] or 0, bb[i] or 0
        if x > y then return true end
        if x < y then return false end
    end
    return false
end

local function getVersion(data)
    return data and (
        data:match("local%s+CURRENT_VERSION%s*=%s*['\"]([^'\"]+)['\"]")
        or data:match("script_version%s*%(%s*['\"]([^'\"]+)['\"]%s*%)")
    )
end

local function checkUpdate()
    lua_thread.create(function()
        makeCfgDir()
        os.remove(updateFile)

        local done, failed = false, false
        downloadUrlToFile(SCRIPT_URL .. '?t=' .. os.time(), updateFile, function(_, status)
            if status == dlstatus.STATUS_ENDDOWNLOADDATA or status == dlstatus.STATUSEX_ENDDOWNLOAD then
                done = true
            elseif status == dlstatus.STATUS_ERROR or status == dlstatus.STATUSEX_ERROR then
                failed = true
            end
        end)

        local timer = 0
        while not done and not failed and timer < 10000 do
            wait(100)
            timer = timer + 100
        end

        if failed or not done then
            os.remove(updateFile)
            return
        end

        local data = readFile(updateFile)
        if not data or #data < 1000 then
            os.remove(updateFile)
            return
        end

        local remote = getVersion(data)
        if not remote or not versionNewer(remote, CURRENT_VERSION) then
            os.remove(updateFile)
            return
        end

        if not data:find("script_name('M-AIM')", 1, true)
        and not data:find('script_name("M-AIM")', 1, true) then
            os.remove(updateFile)
            return
        end

        if not loadstring(data, '@M-AIM_update.lua') then
            os.remove(updateFile)
            return
        end

        local current = thisScript().path
        local old = readFile(current)
        if not old then return end

        writeFile(current .. '.bak', old)

        if not writeFile(current, data) then
            writeFile(current, old)
            os.remove(updateFile)
            return
        end

        os.remove(updateFile)
        sampAddChatMessage('[M-AIM] Обновление до версии ' .. remote .. ' установлено.', -1)
        wait(1000)
        thisScript():reload()
    end)
end

local function clearTarget()
    targetId = -1
    targetUntil = 0
end

local function toggleAim()
    enabled = not enabled
    clearTarget()
    saveConfig()

    local color = enabled and 0x55FF55 or 0xFF5555
    sampAddChatMessage('[M-AIM] ' .. (enabled and 'ON' or 'OFF'), color)
end

function sampev.onSendGiveDamage(playerId)
    if not enabled then return end

    local weapon = getCurrentCharWeapon(PLAYER_PED)
    if not weaponProfile[weapon] then return end

    targetId = tonumber(playerId) or -1
    targetUntil = os.clock() + 1.0
end

local function canSee(x, y, z, p)
    if not p.wall then return true end
    local cx, cy, cz = getActiveCameraCoordinates()
    return isLineOfSightClear(cx, cy, cz, x, y, z, true, true, false, true, true, false, false)
end

local aimBones = {8, 7, 6, 5, 4, 3, 2, 1, 42, 43, 44, 51, 52, 53, 54, 55, 56}

local function nearestBone(handle)
    local cx, cy, cz = getActiveCameraCoordinates()
    local vx = fixAngle(representIntAsFloat(readMemory(0xB6F258, 4, false)))
    local vy = fixAngle(representIntAsFloat(readMemory(0xB6F248, 4, false)))
    local zfix = isWidescreenOnInOptions() and 0.0778 or 0.103
    local best, bx, by, bz = math.huge

    for _, bone in ipairs(aimBones) do
        local x, y, z = bonePos(handle, bone)
        local dx, dy, dz = cx - x, cy - y, cz - z
        local ax = math.atan2(dy, dx) + 0.04253
        local ay = math.atan2(math.sqrt(dx * dx + dy * dy), dz) - math.pi / 2 - zfix
        local d1, d2 = fixAngle(ax - vx), fixAngle(ay - vy)
        local angle = math.sqrt(d1 * d1 + d2 * d2)

        if angle < best then
            best, bx, by, bz = angle, x, y, z
        end
    end

    return bx, by, bz
end

local function aimAtPlayer(p, dt)
    local found, handle = sampGetCharHandleBySampPlayerId(targetId)
    if not found or not doesCharExist(handle) or isCharDead(handle) or not isCharOnScreen(handle) then
        clearTarget()
        return
    end

    local x, y, z
    if p.bone == -1 then x, y, z = nearestBone(handle)
    else x, y, z = bonePos(handle, p.bone) end
    if not x then return end

    local px, py, pz = getCharCoordinates(PLAYER_PED)
    local distance = math.sqrt((x - px)^2 + (y - py)^2 + (z - pz)^2)
    if distance > p.dist or not canSee(x, y, z, p) then return end

    local cx, cy, cz = getActiveCameraCoordinates()
    local dx, dy, dz = cx - x, cy - y, cz - z
    local zfix = isWidescreenOnInOptions() and 0.0778 or 0.103
    local tx = math.atan2(dy, dx) + 0.04253
    local ty = math.atan2(math.sqrt(dx * dx + dy * dy), dz) - math.pi / 2 - zfix
    local vx = fixAngle(representIntAsFloat(readMemory(0xB6F258, 4, false)))
    local vy = fixAngle(representIntAsFloat(readMemory(0xB6F248, 4, false)))
    local diffX, diffY = fixAngle(tx - vx), fixAngle(ty - vy)

    if math.sqrt(diffX * diffX + diffY * diffY) * 57.2957795131 > p.fov then return end

    local smooth = 1 - math.exp(-(60 / math.max(p.speed, 1)) * dt)
    local stepX, stepY = diffX * smooth, diffY * smooth
    local maxStep = math.rad(4) * math.max(dt * 60, 0.5)

    stepX = math.max(-maxStep, math.min(maxStep, stepX))
    stepY = math.max(-maxStep, math.min(maxStep, stepY))
    setCameraPositionUnfixed(vy + stepY, vx + stepX)
end

local function aimThread()
    local last = os.clock()

    while true do
        wait(0)
        local now = os.clock()
        local dt = now - last
        last = now
        if dt <= 0 or dt > 0.1 then dt = 1 / 60 end

        if targetId ~= -1 and now >= targetUntil then clearTarget() end

        if enabled and targetId ~= -1 and isKeyDown(vkeys.VK_LBUTTON) then
            local id = weaponProfile[getCurrentCharWeapon(PLAYER_PED)]
            if id then aimAtPlayer(profiles[id], dt) end
        end
    end
end

local function chooseProfile(id)
    if id == selected then return end
    saveProfile(selected)
    selected = id
    loadProfile(selected)
end

local function centerText(text)
    local size = imgui.CalcTextSize(text)
    imgui.SetCursorPosX((imgui.GetWindowWidth() - size.x) / 2)
    imgui.Text(text)
end

function imgui.BeforeDrawFrame()
    if font then return end
    font = imgui.GetIO().Fonts:AddFontFromFileTTF(
        getFolderPath(0x14) .. '\\trebucbd.ttf',
        18.0,
        nil,
        imgui.GetIO().Fonts:GetGlyphRangesCyrillic()
    )
end

local function darkTheme()
    imgui.SwitchContext()
    local s = imgui.GetStyle()
    local c, col, v = s.Colors, imgui.Col, imgui.ImVec4

    s.WindowPadding = imgui.ImVec2(12, 11)
    s.WindowRounding = 8
    s.FrameRounding = 5
    s.ItemSpacing = imgui.ImVec2(8, 7)

    c[col.Text] = v(0.90, 0.90, 0.92, 1)
    c[col.TextDisabled] = v(0.48, 0.49, 0.52, 1)
    c[col.WindowBg] = v(0.035, 0.037, 0.041, 0.99)
    c[col.Border] = v(0.18, 0.19, 0.21, 1)
    c[col.FrameBg] = v(0.105, 0.108, 0.116, 1)
    c[col.FrameBgHovered] = v(0.145, 0.150, 0.160, 1)
    c[col.FrameBgActive] = v(0.185, 0.190, 0.202, 1)
    c[col.TitleBg] = v(0.045, 0.047, 0.052, 1)
    c[col.TitleBgActive] = v(0.060, 0.063, 0.070, 1)
    c[col.CheckMark] = v(0.78, 0.79, 0.82, 1)
    c[col.SliderGrab] = v(0.58, 0.59, 0.62, 1)
    c[col.Button] = v(0.115, 0.118, 0.126, 1)
    c[col.ButtonHovered] = v(0.175, 0.180, 0.192, 1)
    c[col.ButtonActive] = v(0.245, 0.250, 0.265, 1)
    c[col.Separator] = v(0.19, 0.20, 0.22, 1)
end


local function openTelegram(username)
    os.execute('start "" "https://t.me/' .. username .. '"')
end

local function drawWelcome()
    if not welcome.v then return end

    imgui.SetNextWindowPos(imgui.ImVec2(310, 220), imgui.Cond.FirstUseEver)
    imgui.SetNextWindowSize(imgui.ImVec2(500, 245), imgui.Cond.FirstUseEver)
    imgui.Begin(u8('M-AIM | Приветствие'), welcome, imgui.WindowFlags.NoResize + imgui.WindowFlags.NoCollapse + imgui.WindowFlags.ShowBorders)

    if font then imgui.PushFont(font) end
    centerText(u8('M-AIM'))
    if font then imgui.PopFont() end

    imgui.Dummy(imgui.ImVec2(0, 8))
    centerText(u8('Я Майк Гусятский, я со своим помощником'))
    centerText(u8('создал этот скрипт.'))
    imgui.Dummy(imgui.ImVec2(0, 12))

    if imgui.Button(u8('Майк — @arkaloid'), imgui.ImVec2(-1, 34)) then
        openTelegram('arkaloid')
    end

    if imgui.Button(u8('Милфа — @wiokyrov'), imgui.ImVec2(-1, 34)) then
        openTelegram('wiokyrov')
    end

    imgui.Dummy(imgui.ImVec2(0, 8))
    if imgui.Button(u8('ПОНЯТНО'), imgui.ImVec2(-1, 34)) then
        welcomeSeen = true
        welcome.v = false
        saveConfig()
        imgui.Process = menu.v
    end

    imgui.End()
end

function imgui.OnDrawFrame()
    drawWelcome()
    if not menu.v then return end

    imgui.SetNextWindowPos(imgui.ImVec2(120, 90), imgui.Cond.FirstUseEver)
    imgui.SetNextWindowSize(imgui.ImVec2(620, 540), imgui.Cond.FirstUseEver)
    imgui.Begin(u8('M-AIM | UZI / M4'), menu, imgui.WindowFlags.NoResize + imgui.WindowFlags.NoCollapse + imgui.WindowFlags.ShowBorders)

    if font then imgui.PushFont(font) end
    centerText('M-AIM')
    if font then imgui.PopFont() end
    centerText(u8('Статус: ' .. (enabled and 'ВКЛЮЧЕН' or 'ВЫКЛЮЧЕН')))

    imgui.Dummy(imgui.ImVec2(0, 5))
    if imgui.Button(u8(enabled and 'ВЫКЛЮЧИТЬ M-AIM' or 'ВКЛЮЧИТЬ M-AIM'), imgui.ImVec2(-1, 38)) then
        toggleAim()
    end

    imgui.TextDisabled(u8('Клавиша ВКЛ/ВЫКЛ: ' .. keyName(toggleKey)))
    imgui.PushItemWidth(180)
    imgui.InputText(u8('Клавиша##toggle'), keyInput)
    imgui.PopItemWidth()
    imgui.SameLine()

    if imgui.Button(u8('ПРИМЕНИТЬ##toggle')) then
        local code = keyCode(keyInput.v)
        if code then
            toggleKey = code
            keyInput.v = keyName(toggleKey)
            saveConfig()
        else
            keyInput.v = keyName(toggleKey)
        end
    end

    imgui.TextDisabled(u8('Примеры: -, NUM-, X, 5, F6, CTRL, ALT'))
    imgui.Separator()

    if imgui.Button(u8('UZI  103/104'), imgui.ImVec2(285, 38)) then chooseProfile(103) end
    imgui.SameLine()
    if imgui.Button(u8('M4  107/108'), imgui.ImVec2(285, 38)) then chooseProfile(107) end

    imgui.Dummy(imgui.ImVec2(0, 8))
    imgui.Text(u8('Профиль: ' .. profiles[selected].name))
    imgui.Separator()

    imgui.PushItemWidth(350)
    imgui.SliderFloat(u8('Скорость##speed'), ui.speed, 1, 50, '%.1f')
    imgui.SliderFloat(u8('Дистанция##dist'), ui.dist, 1, 100, '%.1f')
    imgui.SliderFloat(u8('Угол##fov'), ui.fov, 1, 100, '%.1f')
    imgui.PopItemWidth()

    imgui.Dummy(imgui.ImVec2(0, 8))
    imgui.Text(u8('ТОЧКА НАВЕДЕНИЯ'))
    imgui.Separator()

    if imgui.Checkbox(u8('Голова'), ui.head) and ui.head.v then setBone(8) end
    imgui.SameLine(150)
    if imgui.Checkbox(u8('Торс'), ui.torso) and ui.torso.v then setBone(3) end
    if imgui.Checkbox(u8('Стопа'), ui.foot) and ui.foot.v then setBone(42) end
    imgui.SameLine(150)
    if imgui.Checkbox(u8('Нога'), ui.leg) and ui.leg.v then setBone(54) end
    if imgui.Checkbox(u8('Ближайшая точка'), ui.nearest) and ui.nearest.v then setBone(-1) end

    imgui.Dummy(imgui.ImVec2(0, 8))
    imgui.Text(u8('ДОПОЛНИТЕЛЬНО'))
    imgui.Separator()
    imgui.Checkbox(u8('Проверка стен'), ui.wall)

    imgui.Dummy(imgui.ImVec2(0, 10))
    if imgui.Button(u8('СОХРАНИТЬ НАСТРОЙКИ'), imgui.ImVec2(-1, 36)) then saveConfig() end

    imgui.Separator()
    imgui.TextDisabled(u8('Наводка работает после твоего попадания и только пока зажат ЛКМ.'))
    imgui.TextDisabled(u8('/maim или Q + E — меню.  ' .. keyName(toggleKey) .. ' — ВКЛ/ВЫКЛ.'))
    imgui.End()
end

local function toggleMenu()
    menu.v = not menu.v
    imgui.Process = menu.v
end

function main()
    repeat wait(0) until isSampAvailable()

    loadConfig()
    darkTheme()
    if not welcomeSeen then
        welcome.v = true
        imgui.Process = true
    end
    sampRegisterChatCommand('maim', toggleMenu)
    lua_thread.create(aimThread)
    checkUpdate()

    while true do
        wait(0)

        local blocked = sampIsChatInputActive() or sampIsDialogActive()
        local down = isKeyDown(toggleKey)
        if down and not toggleWasDown and not blocked then toggleAim() end
        toggleWasDown = down

        local menuDown = isKeyDown(menuKey1) and isKeyDown(menuKey2)
        if menuDown and not menuWasDown and not blocked then toggleMenu() end
        menuWasDown = menuDown

        if not menu.v and not welcome.v then imgui.Process = false end
    end
end
