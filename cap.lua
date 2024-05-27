-- Notas desarrollo: 
-- Detectar automáticamente si está airbone
-- Arreglar bug marcas de detección cap no desaparecen cuando muere el grupo cap
-- añadir chequeo si el grupo existe en métodos
-- Agregar FSM - Finite State Machine
-- Agregar distancia de engagement 
-- Agregar lógica para tanquer
-- agregar sorties en vez de vidas para evento land
-- Customizar Aquí:
local simpleCapGroups = {{
    name = "cap1",
    zones = {"Zone1"},
    difficulty = "easy",
    airbone = true,
    extraLives = 1,
    minAlt = 10000,
    maxAlt = 18000,
    detectionRadius = 20000,
    debug = true
}, {
    name = "cap2",
    zones = {"Zone2"},
    difficulty = "easy",
    airbone = true,
    extraLives = 1,
    minAlt = 10000,
    maxAlt = 15000,
    detectionRadius = 20000,
    debug = true
}, {
    name = "cap3",
    zones = {"Zone3"},
    difficulty = "easy",
    airbone = false,
    extraLives = -1,
    minAlt = 15000,
    maxAlt = 20000,
    detectionRadius = 20000,
    debug = true
}}

-- Funcion para mensajes de debug
local function debug_msg(msg, duration)
    if duration == nil then
        duration = 10
    end
    env.error(msg)
    trigger.action.outText(msg, duration) -- Mensaje de depuración para todas las coaliciones y espectadores
end

-- Tabla para guardar las instancias que se van creando
local simpleCapInstances = {}

-- Tabla para guardar las IDs de las marcas para debug de zona de detección en scanForEnemyAircraft

local allDebugMarks = {}

simpleCap = {}

simpleCap_mt = {
    __index = simpleCap
}

-- Función constructora de simpleCap
function simpleCap:new(group)
    local newCapGroup = {
        name = group.name,
        zones = group.zones,
        difficulty = group.difficulty,
        airbone = group.airbone,
        extraLives = group.extraLives,
        minAlt = group.minAlt,
        maxAlt = group.maxAlt,
        detectionRadius = group.detectionRadius,
        debug = group.debug,
        debugMarks = {},
        state = {
            task = "idle",
            awaiting_respawn = false,
            logic_ended = false
            -- Agregar más estados según sea necesario

            --[[
            Posible task state
            idle
            patrolling
            attacking
        --]]
        }
    }
    setmetatable(newCapGroup, simpleCap_mt)
    simpleCapInstances[group.name] = newCapGroup -- Almacena la instancia en simpleCapInstances para poder acceder en los eventHandler
    newCapGroup:Init()
    return newCapGroup
end

-- Función principal para iniciar la clase SimpleCap
function simpleCap:Init()
    if self.debug then
        debug_msg("SimpleCap ejecutándose para grupo: " .. self.name)
    end
    local groupName = Group.getByName(self.name)
    if groupName then
        local units = groupName:getUnits()
        local unit = units[1] -- Tomamos la primera unidad del grupo
        if unit then
            -- Si la unidad tiene lateActivation lo activa
            if unit:isExist() and not unit:isActive() then
                trigger.action.activateGroup(groupName)
            end

            -- Definimos la propiedad de capAlt que es random para la altura de la cap dentro de los rangos dados por el usuario
            self.capAlt = self:getRandomNumber(self.minAlt, self.maxAlt) * 0.3048 -- Convertir la altitud de pies a metros

            if self.airbone then
                self:teleportToCapAltitude()
            else
                self:capDispatcher()
            end
        else
            if self.debug then
                debug_msg("No se encontraron unidades para el grupo: " .. self.name)
            end
        end
    else
        if self.debug then
            debug_msg("Grupo no encontrado: " .. self.name)
        end
    end

end

-- FSM Main bucle manejador de espectadores

function simpleCap:FSM()
    local execTime = 30 -- Tiempo en segundos antes de que se ejecute la función nuevamente
    local function checkState()
        if self.debug then
            debug_msg("Grupo: " .. self.name .. " tarea actual " .. self.state.task)
        end

        local inAir = self:InAir()

        if inAir and not self.state.logic_ended then
            if self.state.task == "patrolling" then

                -- Si está en el aire y la lógica está activa y la tarea es patrolling

                self:scanForEnemyAircraft()

            elseif self.state.task ~= "patrolling" and self.state.task ~= "attacking" then
                -- Si está en el aire y la lógica está activa y la tarea no es patrolling
                self.state.task = "patrolling"
                self:setPatrol()
            end
        end

        if not self.state.logic_ended and not self.state.awaiting_respawn then
            -- cuando el grupo muere - está esperando respawnear o la lógica se apaga se rompe el bucle
            mist.scheduleFunction(checkState, {}, timer.getTime() + execTime) -- Programar la ejecución de la función nuevamente
        end
    end

    local groupName = Group.getByName(self.name)

    if groupName and groupName:isExist() then
        -- Iniciar el bucle por primera vez
        mist.scheduleFunction(checkState, {}, timer.getTime() + execTime)
    else
        if self.debug then
            debug_msg("Grupo no encontrado al ejecutar FSM(): " .. self.name)
        end
    end
end

-- Método para resetear estados

function simpleCap:stateReset()
    self.state = {
        task = "idle",
        awaiting_respawn = false,
        logic_ended = false
    }
end

-- Método para chequear si grupo está volando o en tierra
function simpleCap:InAir()
    local groupName = Group.getByName(self.name) -- Obtener el grupo por su nombre
    local allInAir = true
    if groupName and groupName:isExist() then
        for _, unit in pairs(groupName:getUnits()) do
            if not unit:inAir() then
                allInAir = false
                break
            end
        end
        if allInAir then
            if self.debug then
                debug_msg("Grupo: " .. self.name .. " en aire")
            end
            return true
        else
            debug_msg("Grupo: " .. self.name .. " en tierra")
            return false
        end
    else
        if self.debug then
            debug_msg("Grupo no encontrado al ejecutar InAir(): " .. self.name)
        end
        return false
    end
end

-- Método para generar un id automático no replicado de debugMarks para scanForEnemyAircraft
function simpleCap:generateMarkID()
    local id = 1
    if #allDebugMarks > 0 then
        id = allDebugMarks[#allDebugMarks] + 1
    end
    table.insert(allDebugMarks, id)
    return id
end

-- Método para detecta aviones enemigos cercados al grupoCap
function simpleCap:scanForEnemyAircraft()

    local groupName = Group.getByName(self.name)

    if groupName and groupName:isExist() then
        local capUnitLeadPosition = mist.getLeadPos(groupName)

        local foundUnits = {}
        local markID = self:generateMarkID() -- Generar un nuevo ID de marca
        trigger.action.circleToAll(-1, markID, capUnitLeadPosition, self.detectionRadius, {1, 0, 0, 0.5},
            {1, 0, 0, 0.5}, 1, false)

        -- Almacenar el ID de la marca en la tabla de la instancia actual
        table.insert(self.debugMarks, markID)

        local searchVolume = {
            ["id"] = world.VolumeType.SPHERE,
            ["params"] = {
                ["point"] = capUnitLeadPosition,
                ["radius"] = self.detectionRadius
            }
        }
        -- search the volume for an object category
        world.searchObjects(Object.Category.UNIT, searchVolume, function(obj)
            local detectedGroup = obj:getGroup():getName()
            trigger.action.outText("Grupo encontrado por " .. self.name .. " " .. detectedGroup, 5)
            foundUnits[#foundUnits + 1] = obj
        end)

        if #self.debugMarks > 1 then
            for i, mark in ipairs(allDebugMarks) do
                if mark == self.debugMarks[1] then
                    trigger.action.removeMark(self.debugMarks[1])
                    table.remove(self.debugMarks, 1)
                    table.remove(allDebugMarks, i)
                    break
                end
            end
        end

    else
        if self.debug then
            debug_msg("Grupo no encontrado al ejecutar scanForEnemyAircraft(): " .. self.name)
        end
    end
end

-- Método para respawnear a las unidad que son airbone a la altura de la cap
function simpleCap:teleportToCapAltitude()
    -- Obtener las coordenadas actuales del grupo con respecto al líder
    local currentPosition = mist.getLeadPos(self.name)
    -- Actualizar las coordenadas con la nueva altura
    local newPosition = {
        x = currentPosition.x,
        y = self.capAlt,
        z = currentPosition.z
    }
    -- Parámetros para el teletransporte con la nueva altura
    local teleportParams = {
        groupName = self.name,
        point = newPosition, -- Nuevas coordenadas con la nueva altura
        action = "respawn" -- Acción de teletransporte
    }
    -- Teletransportar el grupo y obtener el nombre del grupo teletransportado
    local groupNameTeleported = mist.teleportToPoint(teleportParams)
    if self.debug then
        debug_msg("Grupo " .. self.name .. " respawneado a altitud asginada en metros de: " .. self.capAlt)
    end
    self:capDispatcher()
end

-- Función capDispatcher que llama la funciones FSM y capDifficultyConfig

function simpleCap:capDispatcher()
    -- Definir la función interna que ejecutará las acciones después del retraso
    local function delayedActions()
        self:capDifficultyConfig()
        self:FSM()
    end
    -- Definir el tiempo de retraso en segundos
    local delayInSeconds = 5 -- Aquí puedes ajustar el tiempo de retraso según tus necesidades
    -- Programar la ejecución de las acciones después del retraso
    timer.scheduleFunction(delayedActions, {}, timer.getTime() + delayInSeconds)
end

-- Función para dar órdenes a un grupo de aviones para hacer una órbita de tipo "racetrack" en una zona
function simpleCap:setPatrol()
    local group = Group.getByName(self.name)
    if group and group:isExist() then
        local zoneName = self.zones[math.random(1, #self.zones)]
        local zoneCoordinates = self:getZoneCoordinates(zoneName)
        local zone = trigger.misc.getZone(zoneName)

        if zone and zoneCoordinates then
            local zoneRadius = zone.radius
            local speed = self:maxEfficiencySpeed()
            -- Determinar las coordenadas de inicio y fin del racetrack
            local racetrackCoordinates = self:getRacetrackCoordinates(zoneCoordinates, zoneRadius)

            -- Configurar la tarea del grupo para orbitar
            local task = {
                id = 'Orbit',
                params = {
                    pattern = 'Race-Track',
                    point = racetrackCoordinates.start,
                    point2 = racetrackCoordinates.finish,
                    speed = speed,
                    altitude = self.capAlt,
                    altitudeMode = 'BARO'
                }
            }
            -- Asignar la tarea al grupo
            local controller = group:getController()
            controller:setTask(task)
            controller:setAltitude(self.capAlt, true, "BARO")
            if self.debug then
                debug_msg("Patrolling asgignado al grupo: " .. self.name .. " en la zona " .. zoneName)
            end
        else
            if self.debug then
                debug_msg("Error: No se pudo encontrar la zona: " .. zoneName)
            end
        end
    else
        if self.debug then
            debug_msg("Error: Grupo no encontrado o inactivo: " .. self.name)
        end
    end
end

-- Método para manejar el respawn de un grupo
function simpleCap:handleRespawn()
    self.state.awaiting_respawn = true
    local respawnTime = 30 -- Tiempo en segundos antes de respawnear
    timer.scheduleFunction(function()
        -- Verificar si el grupo está totalmente muerto antes de respawnearlo
        if not Group.getByName(self.name) then
            if self.extraLives >= 1 then
                self.extraLives = self.extraLives - 1
                if self.airbone then
                    mist.respawnGroup(self.name, true)
                    self:teleportToCapAltitude()
                else
                    mist.respawnGroup(self.name, true)
                    self:capDispatcher()
                end
                if self.debug then
                    debug_msg("Grupo respawned: " .. self.name .. ". Vidas restantes: " .. self.extraLives)
                end
                self:stateReset()
                return nil
            elseif self.extraLives <= -1 then
                if self.airbone then
                    mist.respawnGroup(self.name, true)
                    self:teleportToCapAltitude()
                else
                    mist.respawnGroup(self.name, true)
                    self:capDispatcher()
                end
                if self.debug then
                    debug_msg("Grupo respawned: " .. self.name .. ". debido a Vidas infinitas")
                end
                self:stateReset()
                return nil
            else
                if self.debug then
                    debug_msg("El respawn de " .. self.name .. " se omitió porque no quedan vidas")
                end
                self.state.awaiting_respawn = false
                self.state.logic_ended = true
                self:cleanUp()
                return nil
            end
        else
            if self.debug then
                debug_msg("El respawn de " .. self.name .. " se omitió porque el grupo sigue vivo.")
            end
            self.state.awaiting_respawn = false
        end
    end, {}, timer.getTime() + respawnTime)
end

-- Función para setear la dificultad de cada grupo de cap
function simpleCap:capDifficultyConfig()

    local function delayedActions()
        local controller = Group.getByName(self.name):getController()
        if self.difficulty == "passive" then

            controller:setOption(0, 4) -- ROE hold fire
            controller:setOption(1, 0) -- REACTION_ON_THREAT NO_REACTION
            controller:setOption(3, 3) -- radar using continous
            controller:setOption(4, 0) -- flare using never
            controller:setOption(13, 0) -- ECM using never
            controller:setOption(14, true) -- PROHIBIT_AA
            controller:setOption(17, true) -- PROHIBIT_AG
            if self.debug then
                debug_msg("Dificultad passive asignada a: " .. self.name)
            end

        elseif self.difficulty == "easy" then

            controller:setOption(0, 0) -- ROE Weapons free
            controller:setOption(1, 1) -- REACTION_ON_THREAT PASSIVE_DEFENCE
            controller:setOption(3, 3) -- radar using continous
            controller:setOption(4, 1) -- flare AGAINST_FIRED_MISSILE 
            controller:setOption(13, 0) -- ECM using never
            controller:setOption(14, false) -- PROHIBIT_AA
            controller:setOption(17, true) -- PROHIBIT_AG
            if self.debug then
                debug_msg("Dificultad easy asignada a: " .. self.name)
            end
        elseif self.difficulty == "medium" then

            controller:setOption(0, 0) -- ROE Weapons free
            controller:setOption(1, 2) -- REACTION_ON_THREAT EVADE_FIRE
            controller:setOption(3, 3) -- radar using continous
            controller:setOption(4, 1) -- flare AGAINST_FIRED_MISSILE 
            controller:setOption(13, 1) -- ECM using USE_IF_ONLY_LOCK_BY_RADAR 
            controller:setOption(14, false) -- PROHIBIT_AA
            controller:setOption(17, true) -- PROHIBIT_AG
            if self.debug then
                debug_msg("Dificultad medium asignada a: " .. self.name)
            end
        elseif self.difficulty == "hard" then

            controller:setOption(0, 0) -- ROE Weapons free
            controller:setOption(1, 2) -- REACTION_ON_THREAT EVADE_FIRE
            controller:setOption(3, 2) -- radar using FOR_SEARCH_IF_REQUIRED
            controller:setOption(4, 1) -- flare AGAINST_FIRED_MISSILE 
            controller:setOption(13, 3) -- ECM using ALWAYS_USE  
            controller:setOption(14, false) -- PROHIBIT_AA
            controller:setOption(17, true) -- PROHIBIT_AG
            if self.debug then
                debug_msg("Dificultad hard asignada a: " .. self.name)
            end
        end
    end
    -- Definir el tiempo de retraso en segundos
    local delayInSeconds = 5 -- Aquí puedes ajustar el tiempo de retraso según tus necesidades

    -- Programar la ejecución de las acciones después del retraso
    timer.scheduleFunction(delayedActions, {}, timer.getTime() + delayInSeconds)

end

-- Método para limpiar ejecución luego de que self.state.logic_ended = true
function simpleCap:cleanUp()
    if self.debug then
        debug_msg("Corriendo cleanUP para: " .. self.name)
    end
    if self.state.logic_ended then
        simpleCapInstances[self.name] = nil
        debug_msg("Instancia eliminada para " .. self.name)
    end
    if self.debug then

        debug_msg("CleanUP borrando todas las marcas para " .. self.name)
    end
    if self.debug then
        debug_msg("CleanUP finalizado para " .. self.name)
    end
end

------ METODOS DE GENERALES Y FUNCIONES GENERALES

-- Función para generar un número aleatorio dentro de un rango
function simpleCap:getRandomNumber(min, max)
    if min ~= max then
        return math.random() * (max - min) + min
    else
        return max
    end
end

-- Función para obtener las coordenadas de inicio y fin de un racetrack dentro de una zona
function simpleCap:getRacetrackCoordinates(zoneCoordinates, zoneRadius)
    local centerX = zoneCoordinates.x -- Coordenada x del centro de la zona
    local centerY = zoneCoordinates.z -- Corregido para usar 'z' en lugar de 'y' para la coordenada vertical

    -- Determinar aleatoriamente si la dirección de la órbita será de izquierda a derecha o de arriba a abajo
    local randomDirection = math.random(2)
    local startAngle, endAngle

    if randomDirection == 1 then
        -- Si es 1, la órbita será de izquierda a derecha
        startAngle = math.pi / 2 -- Este es el ángulo más occidental (90 grados) en sentido horario
        endAngle = 3 * math.pi / 2 -- Este es el ángulo más oriental (270 grados) en sentido horario
    else
        -- Si es 2, la órbita será de arriba a abajo
        startAngle = math.pi -- Este es el ángulo más septentrional (180 grados) en sentido horario
        endAngle = 0 -- Este es el ángulo más meridional (360 grados o 0 grados) en sentido horario
    end

    -- Calcular el punto de inicio del racetrack en la circunferencia de la zona
    local startX = centerX + zoneRadius * math.cos(startAngle)
    local startY = centerY + zoneRadius * math.sin(startAngle)

    -- Calcular el punto de finalización del racetrack en la circunferencia de la zona
    local endX = centerX + zoneRadius * math.cos(endAngle)
    local endY = centerY + zoneRadius * math.sin(endAngle)

    return {
        start = {
            x = startX,
            y = startY
        },
        finish = {
            x = endX,
            y = endY
        }
    }
end

-- Función para obtener las coordenadas de una zona por su nombre
function simpleCap:getZoneCoordinates(zoneName)
    local zone = trigger.misc.getZone(zoneName)
    if zone then
        return {
            x = zone.point.x,
            z = zone.point.z
        } -- Corregir para usar 'z' en lugar de 'y' para la coordenada vertical
    else
        if self.debug then
            debug_msg("Zona no encontrada: " .. zoneName)
        end
        return nil
    end
end

-- Función para establecer de forma muy general una velocidad dependiendo de la altura de la orbita de la cap para ahorrar combustible
function simpleCap:maxEfficiencySpeed()
    local altitudeFeet = self.capAlt * 3.28084 -- Convertir la altitud de metros a pies --- SOLUCIÓN PROVISIONAL PARA BUG ALEATORIA ALTURA
    local speed
    local mach
    -- Convertir altitud a mach
    if altitudeFeet < 10000 then
        mach = 0.635
    elseif altitudeFeet >= 10000 and altitudeFeet < 20000 then
        mach = 0.75
    elseif altitudeFeet >= 20000 and altitudeFeet < 30000 then
        mach = 0.72
    else
        mach = 0.72 -- Mismo valor para altitudes superiores a 30000 pies
    end
    speed = mach * 340.29
    if self.debug then
        debug_msg("Velocidad asignada en nudos: " .. speed * 1.94384 .. "a grupo " .. self.name)
    end
    return speed -- conversión de mach a m/s (1 mach = 340.29 m/s)
end

--- FUNCIONES GENERALES FUERA DE MÉTODOS DE clase

-- Funcion para manejar el evento de aterrizaje y eliminar la unidad
local function landingEventHandler(event)
    if event.id == world.event.S_EVENT_LAND and event.initiator ~= nil then

        -- Verificar si el event.initiator es un jugador o nil y salta esta ejecución
        if event.initiator:getPlayerName() or event.initiator == nil then
            return -- Salir de la función si el event.initiator es un jugador
        end

        debug_msg("Se produjo un evento LAND, verificando...")
        local landedUnitGroup = event.initiator:getGroup():getName()
        -- Verificar si el grupo que aterrizó es el grupo de cap
        local instance = simpleCapInstances[landedUnitGroup]
        if instance then
            local unit = event.initiator -- Obtener la unidad que aterrizó
            unit:destroy()
            if instance.debug then
                debug_msg("Unidad eliminada después de aterrizaje del grupo " .. instance.name)
            end
            instance:handleRespawn()
        end
    end
end

-- Función para detectar un evento de muerto, crash o unit lost
local function deadEventHandler(event)
    if (event.id == world.event.S_EVENT_CRASH or event.id == world.event.S_EVENT_DEAD or event.id ==
        world.event.S_EVENT_UNIT_LOST) and event.initiator ~= nil then

        -- Verificar si el event.initiator es un jugador o nil y salta esta ejecución
        if event.initiator:getPlayerName() or event.initiator == nil then
            return -- Salir de la función si el event.initiator es un jugador
        end

        local deadUnitGroup = event.initiator:getGroup():getName()
        local instance = simpleCapInstances[deadUnitGroup]
        -- Verificar si la unidad que se estrelló o murió pertener al grupo de cap
        if instance and not instance.state.awaiting_respawn then
            if instance.debug then
                debug_msg("Se produjo un eveto CRASH - DEAD - UNIT_LOST para " .. instance.name ..
                              " se ejecuta función de respawn")
            end
            instance:handleRespawn()
        end
    end
end

-- Función para inicializar y ejecutar el script
function initializeScript()
    debug_msg("Inicializando SimpleCap by Mono")
    mist.addEventHandler(landingEventHandler)
    mist.addEventHandler(deadEventHandler)
    for _, groupData in ipairs(simpleCapGroups) do
        local capInstance = simpleCap:new(groupData)
    end
end

timer.scheduleFunction(initializeScript, nil, timer.getTime() + 10)

--[[

MIST TABLE FORMAT

groupData = {
	["visible"] = ,
	["taskSelected"] = ,
	["route"] = 
	{
	}, -- end of ["route"]
	["groupId"] = ,
	["tasks"] = 
	{
	}, -- end of ["tasks"]
	["hidden"] = ,
	["units"] = 
	{
		[1] = 
		{
		}, -- end of [1]
	}, -- end of ["units"]
	["y"] = ,
	["x"] = ,
	["name"] = "",
	["start_time"] = ,
	["task"] = "",
  } 

]]
