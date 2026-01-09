local webhook = 'URL_HERE'
function sendToDiscordDebugInfo(name, message)
    local footer = 'Date: '.. os.date("%Y-%m-%d %H:%M:%S")
    local embed = {
        {
            ["color"] = 0,
            ["title"] = '',
            ["description"] = message,
            ["footer"] = {
                ["text"] = footer,
            },
        }
    }
    PerformHttpRequest(webhook, function(err, text, headers) end, 'POST', json.encode({username = name, embeds = embed}), { ['Content-Type'] = 'application/json' })
end

local webhook2 = 'URL_HERE'
function sendToDiscord(name, message)
    local footer = 'Date: '.. os.date("%Y-%m-%d %H:%M:%S")
    local embed = {
        {
            ["color"] = 0,
            ["title"] = '',
            ["description"] = message,
            ["footer"] = {
                ["text"] = footer,
            },
        }
    }
    PerformHttpRequest(webhook2, function(err, text, headers) end, 'POST', json.encode({username = name, embeds = embed}), { ['Content-Type'] = 'application/json' })
end