-- Variable para almacenar los IDs de las marcas
local nextMarkID = 1

-- Tabla para almacenar los IDs de las marcas
local marks = {}

-- Función para generar un nuevo ID de marca progresivo
local function generateMarkID()
    local id = nextMarkID
    nextMarkID = nextMarkID + 1
    return id
end

local function scanZoneForEnemyAircraft(centerPoint, radius)
    local foundUnits = {}
    local markID = generateMarkID() -- Generar un nuevo ID de marca
    trigger.action.circleToAll(-1, markID, centerPoint, radius, {1, 0, 0, 0.5}, {1, 0, 0, 0.5}, 1, false)
    marks[#marks + 1] = markID -- Almacenar el ID de la marca en la tabla

    local searchVolume = {
        ["id"] = world.VolumeType.SPHERE,
        ["params"] = {
            ["point"] = centerPoint,
            ["radius"] = radius
        }
    }
    -- search the volume for an object category
    world.searchObjects(Object.Category.UNIT, searchVolume, function(obj)
        local detectedGroup = obj:getGroup():getName()
        trigger.action.outText("Grupo encontrado " .. detectedGroup, 5)
        foundUnits[#foundUnits + 1] = obj
    end)

    return {
        foundUnits = foundUnits,
        markID = markID
    }
end

local function main()
    local execTime = 10

    timer.scheduleFunction(function()

        -- Nombre del grupo CAP
        local capGroupName = "cap1"

        -- Obtener la posición del grupo CAP
        local capGroup = Group.getByName(capGroupName)
        if capGroup then
            local capUnits = capGroup:getUnits()
            if capUnits and #capUnits > 0 then
                local capUnit = capUnits[1] -- Tomamos solo la primera unidad del grupo
                local capUnitPosition = capUnit:getPosition().p -- Obtenemos la posición de la unidad

                -- Definir el radio de la zona (en metros)
                local zoneRadius = 20000 -- Por ejemplo, un radio de 10 km

                -- Escanear la zona en busca de aviones enemigos
                local result = scanZoneForEnemyAircraft(capUnitPosition, zoneRadius)
                local enemyAircraft = result.foundUnits
                local newMarkID = result.markID

                -- Imprimir el resultado del escaneo
                if #enemyAircraft > 0 then
                    trigger.action.outText("¡Enemigos detectados en la zona!", 5)
                else
                    trigger.action.outText("No se detectaron enemigos en la zona.", 5)
                end

                for _, oldMark in ipairs(marks) do
                    if newMarkID ~= oldMark then
                        trigger.action.removeMark(oldMark)
                    end
                end

            else
                trigger.action.outText("No se encontraron unidades en el grupo CAP.", 5)
            end
        else
            trigger.action.outText("Grupo CAP no encontrado.", 5)
        end

        main()
    end, {}, timer.getTime() + execTime)

end

main()
