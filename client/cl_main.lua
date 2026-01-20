local createdTrains = {}

-------------------------------------------------------------------------------
-- spawn train function
-------------------------------------------------------------------------------
local function SpawnTrain(trainhash, startcoords, direction)
    SetRandomTrains(false)
    local trainWagons = Citizen.InvokeNative(0x635423D55CA84FC8, trainhash)
    for wagonIndex = 0, trainWagons - 1 do
        local trainWagonModel = Citizen.InvokeNative(0x8DF5F6A19F99F0D5, trainhash, wagonIndex)
        while not HasModelLoaded(trainWagonModel) do
            Citizen.InvokeNative(0xFA28FE3A6246FC30, trainWagonModel, 1)
            Citizen.Wait(100)
        end
    end

    local direction = direction or 0 
    local train = Citizen.InvokeNative(0xc239dbd9a57d2a71, trainhash, startcoords, direction, 1, 1, 0)

    local timeout = GetGameTimer() + 5000
    while not DoesEntityExist(train) do
        Wait(0)
        if GetGameTimer() > timeout then
            print("Error: Train creation timeout")
            return 0
        end
    end
    local netId = VehToNet(train)
    while not NetworkDoesNetworkIdExist(netId) do
        Wait(0)
        netId = VehToNet(train)
        if GetGameTimer() > timeout then print("Error: NetID timeout"); return 0 end
    end

    SetTrainSpeed(train, 0.0)
    SetTrainMaxSpeed(train, 30.0) 

    Citizen.InvokeNative(0x05254BA0B44ADC16, train, false)
    Citizen.InvokeNative(0x06FAACD625D80CAA, train) 
    SetModelAsNoLongerNeeded(train)

    table.insert(createdTrains, {
        trainModel = trainhash,
        trainWagons = trainWagons,
        trainNetId = netId,
        trainDriver = nil,
    })

    return train
end

-------------------------------------------------------------------------------
-- send info to spawn train / train track switches / train route
-------------------------------------------------------------------------------
local Trains = {}

function _getTrains()
    local trains = {}
    local handle, train = FindFirstVehicle()
    if handle and train ~= 0 then
        if IsThisModelATrain(GetEntityModel(train)) then
            table.insert(trains, train)
        end

        local isExist, nextTrain = FindNextVehicle(handle)
        while isExist do
            if IsThisModelATrain(GetEntityModel(nextTrain)) then
                table.insert(trains, nextTrain)
            end
            isExist, nextTrain = FindNextVehicle(handle)
        end
        EndFindVehicle(handle)
    end
    return trains
end


RegisterNetEvent('trains:createTrain', function(trainId, coords, direction)
    local found = false
    for k, v in ipairs(Config.TrainSetup) do
        if v.trainid == trainId then
            found = v
            break
        end
    end
    
    if not found then
        print('Failed: Train with id not found', trainId)
        return
    end

    found.trainStopped = nil

    local startCoords = found.startcoords
    if coords then
        startCoords = coords
    end

    if trainId == 'train1' then
        local index, trainStop = getClosestStop(Config.RouteOneTrainStops, startCoords)
        if direction == nil then
            direction = trainStop.direction or 0
        end
    elseif trainId == 'train2' then
        local index, trainStop = getClosestStop(Config.RouteTwoTrainStops, startCoords)
        if direction == nil then
            direction = trainStop.direction or 0
        end
    end
    
    print("Created train", trainId)
    local trainHandle = SpawnTrain(found.trainhash, startCoords, direction)
    
    if trainHandle == 0 then
        print("Failed to spawn train entity")
        return
    end

    Citizen.InvokeNative(0xBA8818212633500A, trainHandle, 0, 1) -- SetTransportConfigFlag
    local netId = NetworkGetNetworkIdFromEntity(trainHandle)
    
    local trainsInfo = {}
    for kk,vv in ipairs(_getTrains()) do
        table.insert(trainsInfo, {
            netId = NetworkGetNetworkIdFromEntity(vv),
            trainId = Entity(vv).state['trainId'],
        })
    end
    TriggerServerEvent("Trains.Created", found.trainid, netId, trainsInfo)
end)

-------------------------------------------------------------------------------
-- train track switching system
-------------------------------------------------------------------------------
RegisterNetEvent('rsg-trains:client:trackswithches', function(trainId, netId, ms)
    local train = NetworkGetEntityFromNetworkId(netId)
    local route = nil
    local trainname = nil
    for k,v in ipairs(Config.TrainSetup) do
        if v.trainid == trainId then
            route = v.route
            trainname = v.trainname
            break
        end
    end

    local stopAt = GetGameTimer() + ms
    while GetGameTimer() < stopAt do
        Wait(100) 

        if train ~= nil and DoesEntityExist(train) and route == 'trainRouteOne' then
            for i = 1, #Config.RouteOneTrainSwitches do
                local coords = GetEntityCoords(train)
                local switchdist = #(Config.RouteOneTrainSwitches[i].coords - coords)
                if switchdist < 15 then
                    Citizen.InvokeNative(0xE6C5E2125EB210C1, Config.RouteOneTrainSwitches[i].trainTrack, Config.RouteOneTrainSwitches[i].junctionIndex, Config.RouteOneTrainSwitches[i].enabled)
                    Citizen.InvokeNative(0x3ABFA128F5BF5A70, Config.RouteOneTrainSwitches[i].trainTrack, Config.RouteOneTrainSwitches[i].junctionIndex, Config.RouteOneTrainSwitches[i].enabled)
                end
            end
        elseif train ~= nil and DoesEntityExist(train) and route == 'trainRouteTwo' then
            for i = 1, #Config.RouteTwoTrainSwitches do
                local coords = GetEntityCoords(train)
                local switchdist = #(Config.RouteTwoTrainSwitches[i].coords - coords)
                if switchdist < 15 then
                    Citizen.InvokeNative(0xE6C5E2125EB210C1, Config.RouteTwoTrainSwitches[i].trainTrack, Config.RouteTwoTrainSwitches[i].junctionIndex, Config.RouteTwoTrainSwitches[i].enabled)
                    Citizen.InvokeNative(0x3ABFA128F5BF5A70, Config.RouteTwoTrainSwitches[i].trainTrack, Config.RouteTwoTrainSwitches[i].junctionIndex, Config.RouteTwoTrainSwitches[i].enabled)
                end
            end
        end
    end
end)

-------------------------------------------------------------------------------
-- train route system
-------------------------------------------------------------------------------
RegisterNetEvent('rsg-trains:client:startroute', function(trainId, netId, ms)
    local train = NetworkGetEntityFromNetworkId(netId)

    local trainConfig = nil
    for k,v in ipairs(Config.TrainSetup) do
        if v.trainid == trainId then
            trainConfig = v
            break
        end
    end
    if not trainConfig then return end
    
    local route = trainConfig.route
    local stopspeed = trainConfig.stopspeed
    local cruisespeed = trainConfig.cruisespeed
    local fullspeed = trainConfig.fullspeed

    local trainStops = {}
    if route == 'trainRouteOne' then
        trainStops = Config.RouteOneTrainStops
    elseif route == 'trainRouteTwo' then
        trainStops = Config.RouteTwoTrainStops
    end

    local coords = GetEntityCoords(train)
    local index, trainStop = getClosestStop(trainStops, coords)
    local distance = #(coords - trainStop.coords)

    local stopAt = GetGameTimer() + ms
    while GetGameTimer() < stopAt do
        Wait(200)
        if not DoesEntityExist(train) then break end

        coords = GetEntityCoords(train)
        index, trainStop = getClosestStop(trainStops, coords)
        
        if not trainStop then 
            SetTrainCruiseSpeed(train, fullspeed)
            goto continue 
        end

        distance = #(coords - trainStop.coords)

        if distance < trainStop.dst then
            if distance < trainStop.dst2 then
                if not trainConfig.trainStopped then
                    SetTrainCruiseSpeed(train, stopspeed)
                    TriggerServerEvent('trains:trainStopped', trainConfig.trainname, trainStop.name)
                    SetTimeout(trainStop.waittime, function()
                        SetTrainCruiseSpeed(train, cruisespeed)
                        Wait(10000)
                        trainConfig.trainStopped = false
                    end)
                    trainConfig.trainStopped = true
                end
            else
                SetTrainCruiseSpeed(train, cruisespeed)
            end
        elseif distance > trainStop.dst then
            SetTrainCruiseSpeed(train, fullspeed)
        end
        ::continue::
    end
end)

-------------------------------------------------------------------------------
-- setup train blips (ИСПРАВЛЕННАЯ ВЕРСИЯ)
-------------------------------------------------------------------------------

function addBlipToTrain(blipType, train, blipText)
    local blip = Citizen.InvokeNative(0x23f74c2fda6e7c61, blipType, train) 
    Citizen.InvokeNative(0x9CB1A1623062F402, blip, blipText) 
    return blip
end

function trainChecker(train)
    if not DoesEntityExist(train) then return end

    -- Проверка 1: Это вообще поезд?
    if IsThisModelATrain(GetEntityModel(train)) then
        
        -- ИСПРАВЛЕНИЕ ДУБЛИРОВАНИЯ БЛИПОВ:
        -- Сервер устанавливает 'trainId' только на ГЛАВНЫЙ локомотив.
        -- У обычных вагонов (которые FindNextVehicle тоже находит) этот ID отсутствует.
        local trainId = Entity(train).state['trainId']

        -- Если trainId отсутствует, значит это просто один из вагонов, а не голова поезда.
        -- Пропускаем его, чтобы не создавать лишний блип.
        if not trainId then 
            return 
        end

        -- Проверка 2: Есть ли уже блип на этом локомотиве?
        local blip = GetBlipFromEntity(train)
        
        if not DoesBlipExist(blip) then
            local trainName = trainId

            -- Пытаемся найти красивое имя в конфиге
            for k,v in ipairs(Config.TrainSetup) do
                if v.trainid == trainId then
                    trainName = v.trainname or trainId
                    break
                end
            end

            addBlipToTrain(-399496385, train, trainName)
            -- print("Blip created for locomotive: " .. trainName)
        end
    end
end

function getTrains()
    local handle, firstVehicle = FindFirstVehicle()
    if firstVehicle ~= 0 then
        trainChecker(firstVehicle)
        local isExist, nextVeh = FindNextVehicle(handle)
        while isExist do
            trainChecker(nextVeh)
            isExist, nextVeh = FindNextVehicle(handle)
        end
        EndFindVehicle(handle)
    end
end

-- ИСПРАВЛЕНИЕ: Раскомментировали цикл проверки поездов
-- Теперь каждый клиент сканирует поезда вокруг и создает блики
Citizen.CreateThread(function()
    while true do
        getTrains()
        Wait(2000) -- Проверяем каждые 2 секунды
    end
end)
-------------------------------------------------------------------------------


AddEventHandler('onResourceStop', function(name)
    if name == GetCurrentResourceName() then
        for k,v in ipairs(createdTrains) do
            local trainModel = v.trainModel
            local trainWagons = v.trainWagons
            local trainNetId = v.trainNetId
            local trainDriver = v.trainDriver

            local trainHandle = NetworkGetEntityFromNetworkId(trainNetId)

            local trailers = {}
            if DoesEntityExist(trainHandle) then
                for i = 0, trainWagons - 1 do
                    local carriage = GetTrainCarriage(trainHandle, i)
                    if DoesEntityExist(carriage) then
                        table.insert(trailers, carriage)
                    end
                end
            end
            
            for k,v in ipairs(trailers) do
                DeleteEntity(v)
            end

            print('Clean up train', Entity(trainHandle).state['trainId'], NetworkGetNetworkIdFromEntity(trainHandle))
            DeleteEntity(trainHandle)

            if DoesEntityExist(trainDriver) then
                DeleteEntity(trainDriver)
            end
        end
    end
end)

RegisterNetEvent('---', function()

end)

TriggerServerEvent('train:clientStarted')


--- debug tools
local blips = {}
RegisterNetEvent('train:updateBlips', function(data)
    -- Очистка старых бликов, созданных через это событие (например, для игроков)
    -- Мы НЕ удаляем блики поездов здесь, так как теперь они управляются через trainChecker
    for k,v in ipairs(blips) do
        if v ~= 0 and v ~= false and DoesBlipExist(v) then
            RemoveBlip(v)
        end
    end
    blips = {}

    -- Создание бликов для игроков (если нужно для дебага)
    for k,v in ipairs(data.players) do
        local playerCoords = v.playerCoords
        local playerName = v.playerName
        local playerRadius = v.playerRadius

        local blip = Citizen.InvokeNative(0x45F13B7E0A15C880, 1673015813, playerCoords.x, playerCoords.y, playerCoords.z, playerRadius)
        table.insert(blips, blip)

        local blip2 = Citizen.InvokeNative(0x554D9D53F696D002, 1664425300, playerCoords.x, playerCoords.y, playerCoords.z)
        SetBlipSprite(blip2, `blip_hat`, true)
        Citizen.InvokeNative(0x9CB1A1623062F402, blip2, playerName)
        table.insert(blips, blip2)
    end

    -- ИСПРАВЛЕНИЕ: Закомментировали создание бликов поездов через серверные координаты.
    -- Теперь блики поездов создаются только на стороне клиента прикрепленные к entity (см. trainChecker),
    -- что устраняет мерцание и исчезновение при реконнекте.
    
    --[[
    for k,v in ipairs(data.trains) do
        local trainId = v.trainId
        local trainCoords = v.trainCoords
        local trainOwner = v.trainOwner
        local trainName = v.trainName

        local blip = Citizen.InvokeNative(0x554D9D53F696D002, 1664425300, trainCoords.x, trainCoords.y, trainCoords.z)
        SetBlipSprite(blip, `blip_ambient_train`, true)
        if Config.Debug then
            Citizen.InvokeNative(0x9CB1A1623062F402, blip, ('Train: %s (Owned by: %s) (VW #0)'):format(trainId, trainOwner))
        else
            Citizen.InvokeNative(0x9CB1A1623062F402, blip, ('%s'):format(trainName))
        end
        table.insert(blips, blip)
    end
    ]]
end)

AddEventHandler('onResourceStop', function(name)
    if name == GetCurrentResourceName() then
        for k,v in ipairs(blips) do
            RemoveBlip(v)
        end
    end
end)

-- TODO: Write down route coordinates for simulation
RegisterCommand('startrecord', function()
    local trains = _getTrains()
    local train = trains[1]

    Config.TrainSetup[1].stopspeed = 30.0
    Config.TrainSetup[1].cruisespeed = 30.0
    Config.TrainSetup[1].fullspeed = 30.0

    AttachEntityToEntity(PlayerPedId(), train, 0, 0.0, 0.0, 5.0)
    while true do
        Wait(1000)
        local coords = GetEntityCoords(train)
        local direction = Citizen.InvokeNative(0x3C9628A811CBD724, train, Citizen.ResultAsInteger())
        print(tostring(coords) .. ', ' .. direction .. ',')
    end
end)

RegisterNetEvent('trains:requestTrailersInfo', function(trainNetId)
    local train = NetworkGetEntityFromNetworkId(trainNetId)
    local trainTrailerNumber = Citizen.InvokeNative(0x60B7D1DCC312697D, train)
    TriggerServerEvent('trains:onRequestedTrailersInfo', trainNetId, trainTrailerNumber)
end)