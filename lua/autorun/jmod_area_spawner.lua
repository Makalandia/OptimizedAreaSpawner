-- jmod_area_spawner.lua
print("JMOD Area Spawner addon loaded!")

-- Загружаем данные из spawnareas.lua
include("spawnareas.lua")

for _, area in ipairs(spawnareas) do
    print("Spawn Area: " .. area.name)
    for _, item in ipairs(area.items) do
        print("  Item: " .. item)
    end
    print("  Chance: " .. area.chance)
end

-- Здесь вы можете добавить код для создания областей спавна на основе данных из spawnareas