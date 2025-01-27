-- lua/weapons/gmod_tool/stools/optimized_area_spawner.lua

TOOL.Category = "Construction"
TOOL.Name = "Optimized Area Spawner"

if CLIENT then
    language.Add("tool.optimized_area_spawner.name", "Optimized Area Spawner")
    language.Add("tool.optimized_area_spawner.desc", "Spawns predefined areas with entities")
    language.Add("tool.optimized_area_spawner.0", "Left-click to set the first point, right-click to set the second point and spawn objects")
    language.Add("tool.optimized_area_spawner.hideborders", "Не отображать границу зоны")
    language.Add("tool.optimized_area_spawner.minobjects", "Минимальное количество объектов в зоне")
    language.Add("tool.optimized_area_spawner.maxobjects", "Максимальное количество объектов в зоне")
    language.Add("tool.optimized_area_spawner.spawnobject", "Объекты для спавна (разделенные точкой с запятой и пробелом)")
    language.Add("tool.optimized_area_spawner.npcweapon", "Оружие для НИПов")
    language.Add("tool.optimized_area_spawner.clearobjects", "Удалить все объекты")
    language.Add("tool.optimized_area_spawner.resumespawn", "Продолжить спавн")
    language.Add("tool.optimized_area_spawner.spawnrange", "Дистанция активации спавна (в юнитах)")
    language.Add("tool.optimized_area_spawner.delay", "Задержка спавна/деспавна (в секундах)")
end

TOOL.ClientConVar["zone"] = "Area1"
TOOL.ClientConVar["hideborders"] = "0"
TOOL.ClientConVar["minobjects"] = "1"
TOOL.ClientConVar["maxobjects"] = "10"
TOOL.ClientConVar["spawnobject"] = ""
TOOL.ClientConVar["npcweapon"] = "weapon_smg1" -- Оружие по умолчанию для НИПов
TOOL.ClientConVar["spawnrange"] = "500" -- Дистанция активации спавна по умолчанию
TOOL.ClientConVar["delay"] = "5" -- Задержка спавна/деспавна по умолчанию

TOOL.Point1 = nil
TOOL.Point2 = nil
TOOL.SpawnedEntities = {}
TOOL.SpawnTimers = {} -- Инициализируем поле SpawnTimers
TOOL.SpawnPaused = false -- Флаг для отслеживания состояния спавна
TOOL.PlayerInZone = {} -- Таблица для отслеживания, находится ли игрок в зоне
TOOL.ZoneSleepTimers = {} -- Таймеры для отслеживания спячки зон

function TOOL:LeftClick(trace)
    if CLIENT then return true end

    local ply = self:GetOwner()
    if not IsValid(ply) then return false end

    self.Point1 = trace.HitPos
    ply:ChatPrint("First point set at: " .. tostring(self.Point1))
    return true
end

function TOOL:RightClick(trace)
    if CLIENT then return true end

    local ply = self:GetOwner()
    if not IsValid(ply) then return false end

    self.Point2 = trace.HitPos
    ply:ChatPrint("Second point set at: " .. tostring(self.Point2))

    if self.Point1 and self.Point2 then
        self:SpawnEntitiesAndMarkers()
        self.Point1 = nil
        self.Point2 = nil
    end

    return true
end

function TOOL:SpawnEntitiesAndMarkers()
    local ply = self:GetOwner()
    if not IsValid(ply) then return end

    local selectedZone = self:GetClientInfo("zone")
    local hideBorders = self:GetClientNumber("hideborders") == 1
    local minObjects = self:GetClientNumber("minobjects")
    local maxObjects = self:GetClientNumber("maxobjects")
    local spawnObjects = self:GetClientInfo("spawnobject")
    local npcWeapon = self:GetClientInfo("npcweapon")
    local spawnRange = self:GetClientNumber("spawnrange")
    local delay = self:GetClientNumber("delay")

    if selectedZone == "Custom zone" and spawnObjects == "" then
        ply:ChatPrint("Please specify objects to spawn in the custom zone!")
        return
    end

    local area = nil

    if selectedZone ~= "Custom zone" then
        for _, a in ipairs(spawnareas) do
            if a.name == selectedZone then
                area = a
                break
            end
        end

        if not area then
            ply:ChatPrint("Invalid area selected!")
            return
        end
    end

    -- Определяем минимальные и максимальные координаты зоны
    local min = self.Point1
    local max = self.Point2

    -- Создаем пропы для отображения границ зоны
    local marker1 = self:CreateMarker(min, hideBorders)
    local marker2 = self:CreateMarker(max, hideBorders)

    -- Создаем энтити для зоны
    local zoneEnt = ents.Create("prop_physics")
    zoneEnt:SetModel("models/hunter/blocks/cube025x025x025.mdl") -- Модель не важна, так как мы её скрываем
    zoneEnt:SetPos((min + max) / 2)
    zoneEnt:SetNoDraw(true) -- Скрываем модель
    zoneEnt:Spawn()

    -- Включаем коллизию для зоны только относительно мира, но не игроков
    zoneEnt:SetCollisionGroup(COLLISION_GROUP_WORLD)

    -- Замораживаем физику зоны
    local phys = zoneEnt:GetPhysicsObject()
    if IsValid(phys) then
        phys:EnableMotion(false) -- Замораживаем физику
    end

    -- Присоединяем маркеры к зоне
    if IsValid(marker1) then marker1:SetParent(zoneEnt) end
    if IsValid(marker2) then marker2:SetParent(zoneEnt) end

    -- Инициализируем таблицу для хранения заспавненных объектов
    self.SpawnedEntities[zoneEnt] = self.SpawnedEntities[zoneEnt] or {}

    -- Добавляем таймер для проверки дистанции до игрока
    local timerName = "OptimizedAreaSpawner_CheckDistance_" .. zoneEnt:EntIndex()
    self.SpawnTimers[zoneEnt:EntIndex()] = timerName
    timer.Create(timerName, 1, 0, function()
        if not IsValid(zoneEnt) then
            timer.Remove(timerName)
            return
        end
        self:CheckPlayerDistance(area, min, max, zoneEnt, minObjects, maxObjects, spawnObjects, npcWeapon, spawnRange, delay)
    end)

    -- Добавляем возможность удаления зоны по клавише Z
    undo.Create("Optimized Area Zone")
    undo.AddEntity(zoneEnt)
    undo.SetPlayer(ply)
    undo.Finish()
end

function TOOL:CheckPlayerDistance(area, min, max, zoneEnt, minObjects, maxObjects, spawnObjects, npcWeapon, spawnRange, delay)
    local ply = self:GetOwner()
    if not IsValid(ply) then return end

    local plyPos = ply:GetPos()
    local zoneCenter = (min + max) / 2
    local distance = plyPos:Distance(zoneCenter)

    if distance <= spawnRange then
        if not self.PlayerInZone[zoneEnt] and not self.ZoneSleepTimers[zoneEnt] then
            self:SpawnObjectsInZone(area, min, max, zoneEnt, minObjects, maxObjects, spawnObjects, npcWeapon)
            self.PlayerInZone[zoneEnt] = true
            self.ZoneSleepTimers[zoneEnt] = true
            timer.Simple(delay, function()
                self.ZoneSleepTimers[zoneEnt] = false
            end)
        end
    else
        if self.PlayerInZone[zoneEnt] and not self.ZoneSleepTimers[zoneEnt] then
            self:ClearSpawnedEntitiesInZone(zoneEnt)
            self.PlayerInZone[zoneEnt] = false
            self.ZoneSleepTimers[zoneEnt] = true
            timer.Simple(delay, function()
                self.ZoneSleepTimers[zoneEnt] = false
            end)
        end
    end
end

function TOOL:SpawnObjectsInZone(area, min, max, zoneEnt, minObjects, maxObjects, spawnObjects, npcWeapon)
    -- Удаляем невалидные объекты из таблицы
    self.SpawnedEntities[zoneEnt] = self.SpawnedEntities[zoneEnt] or {}
    for i = #self.SpawnedEntities[zoneEnt], 1, -1 do
        if not IsValid(self.SpawnedEntities[zoneEnt][i]) then
            table.remove(self.SpawnedEntities[zoneEnt], i)
        end
    end

    -- Проверяем, достигнуто ли максимальное количество объектов
    if #self.SpawnedEntities[zoneEnt] >= maxObjects then
        return
    end

    -- Спавним объекты случайным количеством в диапазоне от minObjects до maxObjects
    local numObjectsToSpawn = math.random(minObjects, maxObjects)
    local items = area and area.items or string.Split(spawnObjects, "; ")

    for i = 1, numObjectsToSpawn do
        if #self.SpawnedEntities[zoneEnt] >= maxObjects then
            break
        end

        -- Поднимаем позицию спавна на 50 юнитов вверх
        local pos = Vector(math.random(min.x, max.x), math.random(min.y, max.y), math.random(min.z, max.z) + 50)
        local angle = Angle(0, math.random(0, 360), 0) -- Случайный угол поворота в плоскости XY

        local item = items[math.random(#items)]
        local ent
        if item:sub(-4) == ".mdl" then
            -- Спавним пропы
            ent = ents.Create("prop_physics")
            ent:SetModel(item)
        elseif string.match(item, "^npc_") then
            -- Спавним NPC
            ent = ents.Create(item)
            ent:SetKeyValue("additionalequipment", npcWeapon)
        elseif item == "Seat_Airboat" then
            -- Спавним сиденье
            ent = ents.Create("prop_vehicle_prisoner_pod")
            ent:SetModel("models/nova/airboat_seat.mdl")
            ent:SetKeyValue("vehiclescript", "scripts/vehicles/prisoner_pod.txt")
        elseif item == "Jeep" then
            -- Спавним транспортное средство Jeep
            ent = ents.Create("prop_vehicle_jeep")
            ent:SetModel("models/buggy.mdl")
            ent:SetKeyValue("vehiclescript", "scripts/vehicles/jeep_test.txt")
        else
            -- Спавним другие энтити
            ent = ents.Create(item)
        end

        if IsValid(ent) then
            ent:SetPos(pos)
            ent:SetAngles(angle) -- Устанавливаем случайный угол поворота
            ent:Spawn()

            table.insert(self.SpawnedEntities[zoneEnt], ent)
        else
            print("Failed to create entity of type " .. item)
        end
    end
end

function TOOL:ClearSpawnedEntitiesInZone(zoneEnt)
    for _, ent in ipairs(self.SpawnedEntities[zoneEnt] or {}) do
        if IsValid(ent) then
            ent:Remove()
        end
    end
end

-- Добавляем функцию для удаления всех объектов, созданных всеми зонами
function TOOL:ClearAllSpawnedEntities()
    for _, entities in pairs(self.SpawnedEntities) do
        for _, ent in ipairs(entities) do
            if IsValid(ent) then
                ent:Remove()
            end
        end
    end
end

-- Добавляем функции для приостановки и продолжения спавна
function TOOL:PauseSpawning()
    self.SpawnPaused = true
end

function TOOL:ResumeSpawning()
    self.SpawnPaused = false
end

function TOOL:CreateMarker(pos, hideBorders)
    local marker = ents.Create("prop_physics")
    marker:SetModel("models/hunter/blocks/cube025x025x025.mdl")
    marker:SetPos(pos)
    marker:Spawn()
    marker:SetCollisionGroup(COLLISION_GROUP_WORLD) -- Отключаем коллизию для маркеров
    marker:SetRenderMode(RENDERMODE_TRANSCOLOR)
    marker:SetColor(Color(255, 0, 0, 150)) -- Полупрозрачный красный цвет
    if hideBorders then
        marker:SetNoDraw(true) -- Скрываем маркеры, если выбрано
    end
    return marker
end

function TOOL.BuildCPanel(CPanel)
    CPanel:AddControl("Header", { Description = "Spawns predefined areas with entities" })

    local zoneList = vgui.Create("DComboBox", CPanel)
    zoneList:SetValue("Select Zone")
    zoneList:AddChoice("Custom zone") -- Добавляем пункт для пользовательской зоны
    for _, area in ipairs(spawnareas) do
        zoneList:AddChoice(area.name)
    end

    zoneList.OnSelect = function(panel, index, value)
        RunConsoleCommand("optimized_area_spawner_zone", value)
    end

    CPanel:AddItem(zoneList)

    -- Добавляем чекбокс для скрытия границ зоны
    CPanel:AddControl("Checkbox", {
        Label = "#tool.optimized_area_spawner.hideborders",
        Command = "optimized_area_spawner_hideborders"
    })

    -- Добавляем поле для ввода минимального количества объектов
    CPanel:AddControl("Slider", {
        Label = "#tool.optimized_area_spawner.minobjects",
        Command = "optimized_area_spawner_minobjects",
        Type = "Int",
        Min = "1",
        Max = "100"
    })

    -- Добавляем поле для ввода максимального количества объектов
    CPanel:AddControl("Slider", {
        Label = "#tool.optimized_area_spawner.maxobjects",
        Command = "optimized_area_spawner_maxobjects",
        Type = "Int",
        Min = "1",
        Max = "100"
    })

    -- Добавляем поле для ввода объектов спавна для пользовательской зоны
    CPanel:AddControl("TextBox", {
        Label = "#tool.optimized_area_spawner.spawnobject",
        Command = "optimized_area_spawner_spawnobject",
        MaxLength = "256",
    })

    -- Добавляем поле для ввода оружия для НИПов
    CPanel:AddControl("TextBox", {
        Label = "#tool.optimized_area_spawner.npcweapon",
        Command = "optimized_area_spawner_npcweapon",
        MaxLength = "256",
    })

    -- Добавляем поле для ввода дистанции активации спавна
    CPanel:AddControl("Slider", {
        Label = "#tool.optimized_area_spawner.spawnrange",
        Command = "optimized_area_spawner_spawnrange",
        Type = "Int",
        Min = "100",
        Max = "10000"
    })

    -- Добавляем поле для ввода задержки спавна/деспавна
    CPanel:AddControl("Slider", {
        Label = "#tool.optimized_area_spawner.delay",
        Command = "optimized_area_spawner_delay",
        Type = "Int",
        Min = "0",
        Max = "60"
    })

    -- Добавляем кнопку для удаления всех объектов
    CPanel:AddControl("Button", {
        Label = "#tool.optimized_area_spawner.clearobjects",
        Command = "optimized_area_spawner_clearobjects",
        Text = "Удалить все объекты",
    })

    -- Добавляем кнопку для приостановки спавна
    CPanel:AddControl("Button", {
        Label = "#tool.optimized_area_spawner.pausespawn",
        Command = "optimized_area_spawner_pausespawn",
        Text = "Приостановить спавн",
    })

    -- Добавляем кнопку для продолжения спавна
    CPanel:AddControl("Button", {
        Label = "#tool.optimized_area_spawner.resumespawn",
        Command = "optimized_area_spawner_resumespawn",
        Text = "Продолжить спавн",
    })
end

-- Обрабатываем команды для удаления всех объектов, приостановки и продолжения спавна
if SERVER then
    concommand.Add("optimized_area_spawner_clearobjects", function(ply, cmd, args)
        if IsValid(ply) and ply:IsAdmin() then
            local tool = ply:GetWeapon("gmod_tool").Tool["optimized_area_spawner"]
            if tool then
                tool:ClearAllSpawnedEntities()
                ply:ChatPrint("All spawned entities have been removed.")
            else
                ply:ChatPrint("Failed to find the Optimized Area Spawner tool.")
            end
        else
            ply:ChatPrint("You do not have permission to use this command.")
        end
    end)

    concommand.Add("optimized_area_spawner_pausespawn", function(ply, cmd, args)
        if IsValid(ply) and ply:IsAdmin() then
            local tool = ply:GetWeapon("gmod_tool").Tool["optimized_area_spawner"]
            if tool then
                tool:PauseSpawning()
                ply:ChatPrint("Spawning has been paused.")
            else
                ply:ChatPrint("Failed to find the Optimized Area Spawner tool.")
            end
        else
            ply:ChatPrint("You do not have permission to use this command.")
        end
    end)

    concommand.Add("optimized_area_spawner_resumespawn", function(ply, cmd, args)
        if IsValid(ply) and ply:IsAdmin() then
            local tool = ply:GetWeapon("gmod_tool").Tool["optimized_area_spawner"]
            if tool then
                tool:ResumeSpawning()
                ply:ChatPrint("Spawning has been resumed.")
            else
                ply:ChatPrint("Failed to find the Optimized Area Spawner tool.")
            end
        else
            ply:ChatPrint("You do not have permission to use this command.")
        end
    end)
end