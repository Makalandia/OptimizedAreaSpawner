-- jmod_area_spawner.lua
print("JMOD Area Spawner addon loaded!")

local function parseXML(file)
    local spawnAreas = {}
    if not file.Exists(file, "DATA") then return spawnAreas end

    local contents = file.Read(file, "DATA")
    local xmlData = util.JSONToTable(contents)
    for _, area in ipairs(xmlData.spawnareas) do
        local spawnArea = {
            name = area.name,
            items = {},
            chance = tonumber(area.chance)
        }
        for _, item in ipairs(area.items) do
            table.insert(spawnArea.items, item)
        end
        table.insert(spawnAreas, spawnArea)
    end

    return spawnAreas
end

local spawnAreas = parseXML("spawnareas.xml")

for _, area in ipairs(spawnAreas) do
    print("Spawn Area: " .. area.name)
    for _, item in ipairs(area.items) do
        print("  Item: " .. item)
    end
    print("  Chance: " .. area.chance)
end

-- Здесь вы можете добавить код для создания областей спавна на основе данных из spawnAreas