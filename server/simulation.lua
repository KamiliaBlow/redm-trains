-- simulation.lua

local trainArrivesTimestamps = {}
local trainPointsTimestamps = {}
local trainWasWaiting = {}

function simulationTick(trainId, lastCoords, direction)
    -- 1. Находим конфигурацию конкретного поезда
    local trainConfig = nil
    for k,v in ipairs(Config.TrainSetup) do
        if v.trainid == trainId then
            trainConfig = v
            break
        end
    end
    if not trainConfig then return lastCoords, direction end

    -- 2. Определяем маршрут
    local routePoints = {}
    local routeStops = {}
    local routeTickTime = Config.RouteOnePointTick

    if trainConfig.route == 'trainRouteOne' then
        routePoints = Config.RouteOnePoints
        routeStops = Config.RouteOneTrainStops
    elseif trainConfig.route == 'trainRouteTwo' then
        routePoints = Config.RouteTwoPoints
        routeStops = Config.RouteTwoTrainStops
    else
        return lastCoords, direction
    end

    if not routePoints or #routePoints == 0 then
        return lastCoords, direction
    end

    local trainArrivesAt = trainArrivesTimestamps[trainId] or GetGameTimer()
    local nextPointTickAt = trainPointsTimestamps[trainId] or GetGameTimer()

    local currentlyWaiting = GetGameTimer() < trainArrivesAt

    if currentlyWaiting then
        return lastCoords, direction
    end

    if trainWasWaiting[trainId] == true then
        local _, trainStop = getClosestStop(routeStops, lastCoords)
        if trainStop then
            local trainName = trainConfig.trainname
            --sendToDiscord(nil, ('**%s** отправился от станции **%s**'):format(trainName or trainId, trainStop.name))
        end
        trainWasWaiting[trainId] = false
    end

    if GetGameTimer() < nextPointTickAt then
        return lastCoords, direction
    end

    -- ГИБРИДНАЯ ЛОГИКА ПОИСКА ТОЧКИ
    
    local foundIndex
    local needsFullSearch = false

    -- Проверяем валидность текущего индекса
    if not trainConfig.currentPointIndex or not routePoints[trainConfig.currentPointIndex] then
        needsFullSearch = true -- Индекса нет или он некорректен
    else
        -- Проверяем, далеко ли поезд от точки, на которую указывает индекс
        -- Если дистанция больше 50 метров, значит, произошел дескрон (рестарт и т.д.)
        local distToSavedIndex = #(lastCoords - routePoints[trainConfig.currentPointIndex][1])
        if distToSavedIndex > 50.0 then
            needsFullSearch = true 
        end
    end

    if needsFullSearch then
        -- ПОЛНЫЙ ПОИСК (Оригинальная логика) - выполняется только при десинхроне
        local closestPoint = {dist = math.huge, index = nil}
        for k,v in ipairs(routePoints) do
            local dist = #(lastCoords - v[1])
            if dist < closestPoint.dist then
                closestPoint.dist = dist
                closestPoint.index = k
            end
        end
        foundIndex = closestPoint.index
        -- print(string.format("[Train Sim] %s resynchronized to index %d", trainId, foundIndex))
    else
        -- БЫСТРЫЙ ПОИСК (Оптимизация) - проверяем только текущую и следующие 5 точек
        foundIndex = trainConfig.currentPointIndex
        local closestDist = math.huge
        local searchWindow = 5 
        
        for i = 0, searchWindow do
            local idx = ((foundIndex + i - 1) % #routePoints) + 1
            local dist = #(lastCoords - routePoints[idx][1])
            if dist < closestDist then
                closestDist = dist
                foundIndex = idx
            end
        end
    end
    
    -- Переходим к следующей точке
    local nextIndex = foundIndex + 1
    if nextIndex > #routePoints then
        nextIndex = 1
    end
    
    -- Сохраняем индекс для следующего тика
    trainConfig.currentPointIndex = nextIndex

    -- Обновляем координаты
    lastCoords, direction = routePoints[nextIndex][1], routePoints[nextIndex][2]

    -- Проверяем остановки
    local index, trainStop = getClosestStop(routeStops, lastCoords)
    if trainStop and #(trainStop.coords - lastCoords) <= trainStop.dst2 then
        trainArrivesTimestamps[trainId] = GetGameTimer() + trainStop.waittime
        trainWasWaiting[trainId] = true
        
        local trainName = trainConfig.trainname
        sendToDiscord(nil, ('**%s** stopped at **%s** (S)'):format(trainName or trainId, trainStop.name))
    end
    
    trainPointsTimestamps[trainId] = GetGameTimer() + routeTickTime

    return lastCoords, direction
end