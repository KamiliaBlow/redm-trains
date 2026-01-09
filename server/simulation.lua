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

    -- 2. Определяем, какой маршрут и какие точки использовать
    local routePoints = {}
    local routeStops = {}
    local routeTickTime = Config.RouteOnePointTick -- По умолчанию тик такой же как у 1 поезда

    if trainConfig.route == 'trainRouteOne' then
        routePoints = Config.RouteOnePoints
        routeStops = Config.RouteOneTrainStops
    elseif trainConfig.route == 'trainRouteTwo' then
        routePoints = Config.RouteTwoPoints -- ВАЖНО: Этот массив должен быть в config.lua
        routeStops = Config.RouteTwoTrainStops
    else
        return lastCoords, direction -- Неизвестный маршрут, не двигаемся
    end

    -- Если точки маршрута не найдены (пустые или nil), не двигаем поезд
    if not routePoints or #routePoints == 0 then
        return lastCoords, direction
    end

    local trainArrivesAt = trainArrivesTimestamps[trainId] or GetGameTimer()
    local nextPointTickAt = trainPointsTimestamps[trainId] or GetGameTimer()

    local currentlyWaiting = GetGameTimer() < trainArrivesAt

    if currentlyWaiting then
        return lastCoords, direction
    end

    -- Отправка сообщения об отправлении (как в прошлом шаге)
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

    -- Ищем ближайшую точку в ТЕКУЩЕМ (правильном) маршруте
    local closestPoint = {dist = math.huge, index = nil}
    for k,v in ipairs(routePoints) do
        local dist = #(lastCoords - v[1])
        if dist < closestPoint.dist then
            closestPoint.dist = dist
            closestPoint.index = k
        end
    end
    local pointIndex = closestPoint.index

    -- Переходим к следующей точке
    pointIndex = pointIndex + 1
    if pointIndex >= #routePoints then
        pointIndex = 1
    end

    -- Обновляем координаты
    lastCoords, direction = routePoints[pointIndex][1], routePoints[pointIndex][2]

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