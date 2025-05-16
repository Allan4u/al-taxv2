local ESX, QBCore = nil, nil

CreateThread(function()
    if Config.Framework == 'esx' then
        if Config.UseESXModern then
            ESX = exports['es_extended']:getSharedObject()
        else
            while ESX == nil do
                TriggerEvent('esx:getSharedObject', function(obj) ESX = obj end)
                Wait(0)
            end
        end
    elseif Config.Framework == 'qbcore' then
        QBCore = exports['qb-core']:GetCoreObject()
    end
    
    TriggerEvent('chat:addSuggestion', '/taxinfo', 'Lihat informasi pajak player', {
        { name = "ID Player", help = "ID player yang ingin dilihat informasi pajaknya" }
    })
    
    TriggerEvent('chat:addSuggestion', '/forcetax', 'Paksa pemungutan pajak untuk player', {
        { name = "ID Player", help = "ID player yang ingin dipaksa membayar pajak" }
    })
    
    TriggerEvent('chat:addSuggestion', '/settaxbracket', 'Atur bracket pajak untuk player', {
        { name = "ID Player", help = "ID player yang ingin diatur bracket pajaknya" },
        { name = "Bracket", help = "Nomor bracket (1-7)" }
    })
    
    TriggerEvent('chat:addSuggestion', '/pajakku', 'Lihat status pajak pribadi Anda')
end)

RegisterNetEvent('al-tax:notify')
AddEventHandler('al-tax:notify', function(message, type)
    if Config.Notifications.useCustomNotify then
    else
        TriggerEvent('chat:addMessage', {
            color = {255, 255, 255},
            multiline = true,
            args = {Config.Notifications.prefix, message}
        })
    end
end)
