local ESX, QBCore = nil, nil
local Players = {}

CreateThread(function()
    if Config.Framework == 'esx' then
        if Config.UseESXModern then
            ESX = exports['es_extended']:getSharedObject()
        else
            TriggerEvent('esx:getSharedObject', function(obj) ESX = obj end)
        end
    elseif Config.Framework == 'qbcore' then
        QBCore = exports['qb-core']:GetCoreObject()
    end
    InitializeTaxTimer()
end)

function InitializeTaxTimer()
    CreateThread(function()
        while true do
            local currentTime = os.time()
            local currentDate = os.date("*t", currentTime)
            
            local nextTaxTime = os.time({
                year = currentDate.year,
                month = currentDate.month,
                day = currentDate.day,
                hour = Config.TaxCollection.hour,
                min = Config.TaxCollection.minute,
                sec = 0
            })
            
            if currentTime > nextTaxTime then
                nextTaxTime = nextTaxTime + (Config.TaxCollection.intervalDays * 24 * 60 * 60)
            end
            
            local timeUntilNextTax = nextTaxTime - currentTime
            
            print(Config.Notifications.prefix .. "Next tax collection in " .. SecondsToTime(timeUntilNextTax))
            
            Wait(timeUntilNextTax * 1000)
            
            CollectTaxesFromAllPlayers()
            
            Wait(60 * 1000)
        end
    end)
end

function SecondsToTime(seconds)
    local days = math.floor(seconds / 86400)
    seconds = seconds - days * 86400
    local hours = math.floor(seconds / 3600)
    seconds = seconds - hours * 3600
    local minutes = math.floor(seconds / 60)
    seconds = seconds - minutes * 60
    
    return string.format("%d days, %d hours, %d minutes", days, hours, minutes)
end

function CollectTaxesFromAllPlayers()
    print(Config.Notifications.prefix .. "Starting tax collection for all citizens...")
    
    if Config.Framework == 'esx' then
        local xPlayers = ESX.GetExtendedPlayers()
        for _, xPlayer in pairs(xPlayers) do
            CollectTaxesFromPlayer(xPlayer.identifier, true, xPlayer.source)
        end
    elseif Config.Framework == 'qbcore' then
        for _, Player in pairs(QBCore.Functions.GetPlayers()) do
            local xPlayer = QBCore.Functions.GetPlayer(Player)
            if xPlayer then
                CollectTaxesFromPlayer(xPlayer.PlayerData.citizenid, true, xPlayer.PlayerData.source)
            end
        end
    end
    
    CollectTaxesFromOfflinePlayers()
    
    print(Config.Notifications.prefix .. "Tax collection completed!")
end

function CollectTaxesFromOfflinePlayers()
    if Config.Framework == 'esx' then
        MySQL.query('SELECT identifier FROM users WHERE identifier NOT IN (SELECT identifier FROM users WHERE connected = 1)', function(result)
            if result and #result > 0 then
                for i = 1, #result do
                    CollectTaxesFromPlayer(result[i].identifier, false)
                end
            end
        end)
    elseif Config.Framework == 'qbcore' then
        MySQL.query('SELECT citizenid FROM players WHERE license NOT IN (SELECT license FROM players WHERE last_logout > DATE_SUB(NOW(), INTERVAL 10 MINUTE))', function(result)
            if result and #result > 0 then
                for i = 1, #result do
                    CollectTaxesFromPlayer(result[i].citizenid, false)
                end
            end
        end)
    end
end

function CollectTaxesFromPlayer(identifier, isOnline, source)
    local playerMoney, playerBank = 0, 0
    local totalTax = 0
    local taxDetails = {}
    
    if isOnline then
        if Config.Framework == 'esx' then
            local xPlayer = ESX.GetPlayerFromIdentifier(identifier)
            playerMoney = xPlayer.getMoney()
            playerBank = xPlayer.getAccount('bank').money
        elseif Config.Framework == 'qbcore' then
            local xPlayer = QBCore.Functions.GetPlayer(source)
            playerMoney = xPlayer.PlayerData.money['cash']
            playerBank = xPlayer.PlayerData.money['bank']
        end
        
        local totalWealth = playerMoney + playerBank
        local incomeTax, taxBracket = CalculateIncomeTax(totalWealth)
        
        totalTax = totalTax + incomeTax
        table.insert(taxDetails, {
            type = "Income",
            bracket = taxBracket.name,
            amount = incomeTax,
            rate = taxBracket.taxRate * 100 .. "%"
        })
        
        local vehicleTax, vehicleCount = CalculateVehicleTax(identifier)
        
        totalTax = totalTax + vehicleTax
        table.insert(taxDetails, {
            type = "Vehicle",
            count = vehicleCount,
            amount = vehicleTax,
            rate = "150k per vehicle"
        })
        
        local electronicTax, electronicItems = CalculateElectronicTax(source, isOnline, identifier)
        
        totalTax = totalTax + electronicTax
        table.insert(taxDetails, {
            type = "Electronic",
            items = electronicItems,
            amount = electronicTax,
            rate = "5k per item"
        })
        
        DeductTaxFromPlayer(source, totalTax, taxDetails, isOnline, identifier)
    else
        -- For offline players, we need to get data from the database
        if Config.Framework == 'esx' then
            MySQL.query('SELECT accounts FROM users WHERE identifier = ?', {identifier}, function(result)
                if result and #result > 0 then
                    local accounts = json.decode(result[1].accounts)
                    playerMoney = accounts.money or 0
                    playerBank = accounts.bank or 0
                    
                    local totalWealth = playerMoney + playerBank
                    local incomeTax, taxBracket = CalculateIncomeTax(totalWealth)
                    
                    totalTax = totalTax + incomeTax
                    table.insert(taxDetails, {
                        type = "Income",
                        bracket = taxBracket.name,
                        amount = incomeTax,
                        rate = taxBracket.taxRate * 100 .. "%"
                    })
                
                    local vehicleTax, vehicleCount = CalculateVehicleTax(identifier)
                    
                    totalTax = totalTax + vehicleTax
                    table.insert(taxDetails, {
                        type = "Vehicle",
                        count = vehicleCount,
                        amount = vehicleTax,
                        rate = "150k per vehicle"
                    })
                    
                    local electronicTax, electronicItems = CalculateElectronicTax(nil, isOnline, identifier)
                    
                    totalTax = totalTax + electronicTax
                    table.insert(taxDetails, {
                        type = "Electronic",
                        items = electronicItems,
                        amount = electronicTax,
                        rate = "5k per item"
                    })
                    
                    DeductTaxFromPlayer(nil, totalTax, taxDetails, isOnline, identifier)
                end
            end)
        elseif Config.Framework == 'qbcore' then
            MySQL.query('SELECT money FROM players WHERE citizenid = ?', {identifier}, function(result)
                if result and #result > 0 then
                    local money = json.decode(result[1].money)
                    playerMoney = money.cash or 0
                    playerBank = money.bank or 0
                    
                    local totalWealth = playerMoney + playerBank
                    local incomeTax, taxBracket = CalculateIncomeTax(totalWealth)
                    
                    totalTax = totalTax + incomeTax
                    table.insert(taxDetails, {
                        type = "Income",
                        bracket = taxBracket.name,
                        amount = incomeTax,
                        rate = taxBracket.taxRate * 100 .. "%"
                    })
                    
                    local vehicleTax, vehicleCount = CalculateVehicleTax(identifier)
                    
                    totalTax = totalTax + vehicleTax
                    table.insert(taxDetails, {
                        type = "Vehicle",
                        count = vehicleCount,
                        amount = vehicleTax,
                        rate = "150k per vehicle"
                    })
                    
                    local electronicTax, electronicItems = CalculateElectronicTax(nil, isOnline, identifier)
                    
                    totalTax = totalTax + electronicTax
                    table.insert(taxDetails, {
                        type = "Electronic",
                        items = electronicItems,
                        amount = electronicTax,
                        rate = "5k per item"
                    })
                    
                    -- Deduct tax from player
                    DeductTaxFromPlayer(nil, totalTax, taxDetails, isOnline, identifier)
                end
            end)
        end
    end
end

function CalculateIncomeTax(totalWealth)
    if identifier then
        local result = MySQL.query.await('SELECT bracket_index FROM al_tax_custom_brackets WHERE identifier = ?', {identifier})
        if result and #result > 0 then
            local bracketIndex = result[1].bracket_index
            local bracket = Config.IncomeTaxBrackets[bracketIndex]
            if bracket then
                local taxAmount = math.floor(totalWealth * bracket.taxRate)
                return taxAmount, bracket
            end
        end
    end
    
    for _, bracket in ipairs(Config.IncomeTaxBrackets) do
        if totalWealth >= bracket.minAmount and totalWealth <= bracket.maxAmount then
            local taxAmount = math.floor(totalWealth * bracket.taxRate)
            return taxAmount, bracket
        end
    end
    
    local highestBracket = Config.IncomeTaxBrackets[#Config.IncomeTaxBrackets]
    local taxAmount = math.floor(totalWealth * highestBracket.taxRate)
    return taxAmount, highestBracket
end

function CalculateVehicleTax(identifier)
    local vehicleCount = 0
    
    if Config.Framework == 'esx' then
        local result = MySQL.query.await('SELECT COUNT(*) as count FROM owned_vehicles WHERE owner = ?', {identifier})
        if result and result[1] then
            vehicleCount = result[1].count
        end
    elseif Config.Framework == 'qbcore' then
        local result = MySQL.query.await('SELECT COUNT(*) as count FROM player_vehicles WHERE citizenid = ?', {identifier})
        if result and result[1] then
            vehicleCount = result[1].count
        end
    end
    
    local taxAmount = vehicleCount * Config.VehicleTax.amountPerVehicle
    return taxAmount, vehicleCount
end

function CalculateElectronicTax(source, isOnline, identifier)
    local electronicItemCount = 0
    local electronicItems = {}
    
    if isOnline then
        if Config.Framework == 'esx' then
            local xPlayer = ESX.GetPlayerFromIdentifier(identifier)
            for _, itemName in ipairs(Config.ElectronicTax.items) do
                local item = xPlayer.getInventoryItem(itemName)
                if item and item.count > 0 then
                    electronicItemCount = electronicItemCount + item.count
                    table.insert(electronicItems, {name = itemName, count = item.count})
                end
            end
        elseif Config.Framework == 'qbcore' then
            local xPlayer = QBCore.Functions.GetPlayer(source)
            local items = xPlayer.PlayerData.items
            for _, itemName in ipairs(Config.ElectronicTax.items) do
                for _, item in pairs(items) do
                    if item.name == itemName then
                        electronicItemCount = electronicItemCount + item.amount
                        table.insert(electronicItems, {name = itemName, count = item.amount})
                    end
                end
            end
        end
    else
        if Config.Framework == 'esx' then
            for _, itemName in ipairs(Config.ElectronicTax.items) do
                local result = MySQL.query.await('SELECT COUNT(*) as count FROM user_inventory WHERE identifier = ? AND item = ?', {identifier, itemName})
                if result and result[1] and result[1].count > 0 then
                    electronicItemCount = electronicItemCount + result[1].count
                    table.insert(electronicItems, {name = itemName, count = result[1].count})
                end
            end
        elseif Config.Framework == 'qbcore' then
            local result = MySQL.query.await('SELECT items FROM players WHERE citizenid = ?', {identifier})
            if result and result[1] and result[1].items then
                local items = json.decode(result[1].items)
                for _, itemName in ipairs(Config.ElectronicTax.items) do
                    for _, item in pairs(items) do
                        if item.name == itemName then
                            electronicItemCount = electronicItemCount + item.amount
                            table.insert(electronicItems, {name = itemName, count = item.amount})
                        end
                    end
                end
            end
        end
    end
    
    local taxAmount = electronicItemCount * Config.ElectronicTax.taxAmount
    return taxAmount, electronicItems
end

function DeductTaxFromPlayer(source, taxAmount, taxDetails, isOnline, identifier)
    if isOnline then
        if Config.Framework == 'esx' then
            local xPlayer = ESX.GetPlayerFromIdentifier(identifier)
            SaveTaxRecord(identifier, taxAmount, taxDetails)
            
            local bankBalance = xPlayer.getAccount('bank').money
            if bankBalance >= taxAmount then
                xPlayer.removeAccountMoney('bank', taxAmount)
                NotifyPlayer(source, "Pajak sebesar $" .. taxAmount .. " telah dipotong dari rekening bank Anda.")
            else
                local remainingTax = taxAmount - bankBalance
                if bankBalance > 0 then
                    xPlayer.removeAccountMoney('bank', bankBalance)
                end
                
                local cashBalance = xPlayer.getMoney()
                if cashBalance >= remainingTax then
                    xPlayer.removeMoney(remainingTax)
                    NotifyPlayer(source, "Pajak sebesar $" .. taxAmount .. " telah dipotong dari rekening bank dan uang tunai Anda.")
                else
                    local totalPaid = bankBalance + cashBalance
                    local debt = taxAmount - totalPaid
                    
                    if cashBalance > 0 then
                        xPlayer.removeMoney(cashBalance)
                    end
                    
                    RecordTaxDebt(identifier, debt)
                    NotifyPlayer(source, "Anda tidak memiliki cukup uang untuk membayar pajak. $" .. totalPaid .. " telah dibayarkan dan $" .. debt .. " dicatat sebagai hutang.")
                end
            end
        elseif Config.Framework == 'qbcore' then
            local xPlayer = QBCore.Functions.GetPlayer(source)
            
            SaveTaxRecord(identifier, taxAmount, taxDetails)
            
            local bankBalance = xPlayer.PlayerData.money['bank']
            if bankBalance >= taxAmount then
                xPlayer.Functions.RemoveMoney('bank', taxAmount, "Tax Payment")
                NotifyPlayer(source, "Pajak sebesar $" .. taxAmount .. " telah dipotong dari rekening bank Anda.")
            else
                local remainingTax = taxAmount - bankBalance
                if bankBalance > 0 then
                    xPlayer.Functions.RemoveMoney('bank', bankBalance, "Tax Payment")
                end
                
                local cashBalance = xPlayer.PlayerData.money['cash']
                if cashBalance >= remainingTax then
                    xPlayer.Functions.RemoveMoney('cash', remainingTax, "Tax Payment")
                    NotifyPlayer(source, "Pajak sebesar $" .. taxAmount .. " telah dipotong dari rekening bank dan uang tunai Anda.")
                else
                    local totalPaid = bankBalance + cashBalance
                    local debt = taxAmount - totalPaid
                    
                    if cashBalance > 0 then
                        xPlayer.Functions.RemoveMoney('cash', cashBalance, "Tax Payment")
                    end
                    
                    RecordTaxDebt(identifier, debt)
                    NotifyPlayer(source, "Anda tidak memiliki cukup uang untuk membayar pajak. $" .. totalPaid .. " telah dibayarkan dan $" .. debt .. " dicatat sebagai hutang.")
                end
            end
        end
    else
        SaveTaxRecord(identifier, taxAmount, taxDetails)
        
        if Config.Framework == 'esx' then
            local result = MySQL.query.await('SELECT accounts FROM users WHERE identifier = ?', {identifier})
            if result and result[1] and result[1].accounts then
                local accounts = json.decode(result[1].accounts)
                local bankBalance = accounts.bank or 0
                local cashBalance = accounts.money or 0
                
                if bankBalance >= taxAmount then
                    accounts.bank = bankBalance - taxAmount
                    MySQL.update('UPDATE users SET accounts = ? WHERE identifier = ?', {json.encode(accounts), identifier})
                else
                    local remainingTax = taxAmount - bankBalance
                    accounts.bank = 0
                    
                    if cashBalance >= remainingTax then
                        accounts.money = cashBalance - remainingTax
                        MySQL.update('UPDATE users SET accounts = ? WHERE identifier = ?', {json.encode(accounts), identifier})
                    else
                        local totalPaid = bankBalance + cashBalance
                        local debt = taxAmount - totalPaid
                        
                        accounts.money = 0
                        MySQL.update('UPDATE users SET accounts = ? WHERE identifier = ?', {json.encode(accounts), identifier})
                        RecordTaxDebt(identifier, debt)
                    end
                end
            end
        elseif Config.Framework == 'qbcore' then
            local result = MySQL.query.await('SELECT money FROM players WHERE citizenid = ?', {identifier})
            if result and result[1] and result[1].money then
                local money = json.decode(result[1].money)
                local bankBalance = money.bank or 0
                local cashBalance = money.cash or 0
                
                if bankBalance >= taxAmount then
                    money.bank = bankBalance - taxAmount
                    MySQL.update('UPDATE players SET money = ? WHERE citizenid = ?', {json.encode(money), identifier})
                else
                    local remainingTax = taxAmount - bankBalance
                    money.bank = 0
                    
                    if cashBalance >= remainingTax then
                        money.cash = cashBalance - remainingTax
                        MySQL.update('UPDATE players SET money = ? WHERE citizenid = ?', {json.encode(money), identifier})
                    else
                        local totalPaid = bankBalance + cashBalance
                        local debt = taxAmount - totalPaid
                        
                        money.cash = 0
                        MySQL.update('UPDATE players SET money = ? WHERE citizenid = ?', {json.encode(money), identifier})
                        
                        RecordTaxDebt(identifier, debt)
                    end
                end
            end
        end
    end
end

function SaveTaxRecord(identifier, taxAmount, taxDetails)
    MySQL.insert('INSERT INTO al_tax_records (identifier, tax_amount, tax_details, timestamp) VALUES (?, ?, ?, ?)', {
        identifier,
        taxAmount,
        json.encode(taxDetails),
        os.time()
    })
end

function RecordTaxDebt(identifier, debtAmount)
    -- Check if player already has a debt record
    local result = MySQL.query.await('SELECT debt_amount FROM al_tax_debts WHERE identifier = ?', {identifier})
    
    if result and #result > 0 then
        -- Update existing debt
        local newDebt = result[1].debt_amount + debtAmount
        MySQL.update('UPDATE al_tax_debts SET debt_amount = ?, last_updated = ? WHERE identifier = ?', {
            newDebt,
            os.time(),
            identifier
        })
    else
        -- Create new debt record
        MySQL.insert('INSERT INTO al_tax_debts (identifier, debt_amount, created_at, last_updated) VALUES (?, ?, ?, ?)', {
            identifier,
            debtAmount,
            os.time(),
            os.time()
        })
    end
end

-- Function to notify player
function NotifyPlayer(source, message, type)
    if not source then return end
    
    type = type or 'info'
    
    if Config.Notifications.useCustomNotify then
        Config.Notifications.customNotify(source, message, type)
    else
        TriggerClientEvent('chat:addMessage', source, {
            color = {255, 255, 255},
            multiline = true,
            args = {Config.Notifications.prefix, message}
        })
    end
end

-- Admin command to view player tax info
RegisterCommand('taxinfo', function(source, args)
    if not IsPlayerAdmin(source) then
        NotifyPlayer(source, "Anda tidak memiliki izin untuk menggunakan perintah ini.")
        return
    end
    
    if not args[1] then
        NotifyPlayer(source, "Penggunaan: /taxinfo [ID Player]")
        return
    end
    
    local targetSource = tonumber(args[1])
    local targetIdentifier
    
    if Config.Framework == 'esx' then
        local xPlayer = ESX.GetPlayerFromId(targetSource)
        if xPlayer then
            targetIdentifier = xPlayer.identifier
        else
            NotifyPlayer(source, "Player dengan ID tersebut tidak ditemukan.")
            return
        end
    elseif Config.Framework == 'qbcore' then
        local xPlayer = QBCore.Functions.GetPlayer(targetSource)
        if xPlayer then
            targetIdentifier = xPlayer.PlayerData.citizenid
        else
            NotifyPlayer(source, "Player dengan ID tersebut tidak ditemukan.")
            return
        end
    end
    
    -- Get player's tax records
    MySQL.query('SELECT * FROM al_tax_records WHERE identifier = ? ORDER BY timestamp DESC LIMIT 5', {targetIdentifier}, function(records)
        if records and #records > 0 then
            NotifyPlayer(source, "=== Riwayat Pajak Player ===")
            for i = 1, #records do
                local record = records[i]
                local date = os.date("%Y-%m-%d %H:%M", record.timestamp)
                NotifyPlayer(source, date .. " - $" .. record.tax_amount)
            end
        else
            NotifyPlayer(source, "Tidak ada riwayat pajak untuk player ini.")
        end
    end)
    
    -- Get player's tax debt
    MySQL.query('SELECT debt_amount FROM al_tax_debts WHERE identifier = ?', {targetIdentifier}, function(debt)
        if debt and #debt > 0 and debt[1].debt_amount > 0 then
            NotifyPlayer(source, "Hutang Pajak: $" .. debt[1].debt_amount)
        else
            NotifyPlayer(source, "Player tidak memiliki hutang pajak.")
        end
    end)
end)

-- Admin command to force tax collection for a player
RegisterCommand('forcetax', function(source, args)
    if not IsPlayerAdmin(source) then
        NotifyPlayer(source, "Anda tidak memiliki izin untuk menggunakan perintah ini.")
        return
    end
    
    if not args[1] then
        NotifyPlayer(source, "Penggunaan: /forcetax [ID Player]")
        return
    end
    
    local targetSource = tonumber(args[1])
    local targetIdentifier
    
    if Config.Framework == 'esx' then
        local xPlayer = ESX.GetPlayerFromId(targetSource)
        if xPlayer then
            targetIdentifier = xPlayer.identifier
            CollectTaxesFromPlayer(targetIdentifier, true, targetSource)
            NotifyPlayer(source, "Pajak telah dipaksa untuk player dengan ID " .. targetSource)
        else
            NotifyPlayer(source, "Player dengan ID tersebut tidak ditemukan.")
        end
    elseif Config.Framework == 'qbcore' then
        local xPlayer = QBCore.Functions.GetPlayer(targetSource)
        if xPlayer then
            targetIdentifier = xPlayer.PlayerData.citizenid
            CollectTaxesFromPlayer(targetIdentifier, true, targetSource)
            NotifyPlayer(source, "Pajak telah dipaksa untuk player dengan ID " .. targetSource)
        else
            NotifyPlayer(source, "Player dengan ID tersebut tidak ditemukan.")
        end
    end
end)

-- Admin command to set tax bracket for a player
RegisterCommand('settaxbracket', function(source, args)
    if not IsPlayerAdmin(source) then
        NotifyPlayer(source, "Anda tidak memiliki izin untuk menggunakan perintah ini.")
        return
    end
    
    if not args[1] or not args[2] then
        NotifyPlayer(source, "Penggunaan: /settaxbracket [ID Player] [Bracket Number 1-" .. #Config.IncomeTaxBrackets .. "]")
        return
    end
    
    local targetSource = tonumber(args[1])
    local bracketNum = tonumber(args[2])
    
    if bracketNum < 1 or bracketNum > #Config.IncomeTaxBrackets then
        NotifyPlayer(source, "Bracket number harus antara 1 dan " .. #Config.IncomeTaxBrackets)
        return
    end
    
    local targetIdentifier
    
    if Config.Framework == 'esx' then
        local xPlayer = ESX.GetPlayerFromId(targetSource)
        if xPlayer then
            targetIdentifier = xPlayer.identifier
            -- Set custom tax bracket in the database
            MySQL.update('INSERT INTO al_tax_custom_brackets (identifier, bracket_index) VALUES (?, ?) ON DUPLICATE KEY UPDATE bracket_index = ?', {
                targetIdentifier,
                bracketNum,
                bracketNum
            })
            NotifyPlayer(source, "Tax bracket untuk player ID " .. targetSource .. " telah diatur ke " .. Config.IncomeTaxBrackets[bracketNum].name)
        else
            NotifyPlayer(source, "Player dengan ID tersebut tidak ditemukan.")
        end
    elseif Config.Framework == 'qbcore' then
        local xPlayer = QBCore.Functions.GetPlayer(targetSource)
        if xPlayer then
            targetIdentifier = xPlayer.PlayerData.citizenid
            -- Set custom tax bracket in the database
            MySQL.update('INSERT INTO al_tax_custom_brackets (identifier, bracket_index) VALUES (?, ?) ON DUPLICATE KEY UPDATE bracket_index = ?', {
                targetIdentifier,
                bracketNum,
                bracketNum
            })
            NotifyPlayer(source, "Tax bracket untuk player ID " .. targetSource .. " telah diatur ke " .. Config.IncomeTaxBrackets[bracketNum].name)
        else
            NotifyPlayer(source, "Player dengan ID tersebut tidak ditemukan.")
        end
    end
end)

-- Command for players to view their own tax status
RegisterCommand('pajakku', function(source)
    if source == 0 then return end -- Not for console
    
    local identifier
    
    if Config.Framework == 'esx' then
        local xPlayer = ESX.GetPlayerFromId(source)
        if xPlayer then
            identifier = xPlayer.identifier
        else
            return
        end
    elseif Config.Framework == 'qbcore' then
        local xPlayer = QBCore.Functions.GetPlayer(source)
        if xPlayer then
            identifier = xPlayer.PlayerData.citizenid
        else
            return
        end
    end
    
    -- Get player's income tax bracket
    local totalWealth = 0
    
    if Config.Framework == 'esx' then
        local xPlayer = ESX.GetPlayerFromId(source)
        totalWealth = xPlayer.getMoney() + xPlayer.getAccount('bank').money
    elseif Config.Framework == 'qbcore' then
        local xPlayer = QBCore.Functions.GetPlayer(source)
        totalWealth = xPlayer.PlayerData.money['cash'] + xPlayer.PlayerData.money['bank']
    end
    
    local _, taxBracket = CalculateIncomeTax(totalWealth)
    
    -- Get player's last tax payment
    MySQL.query('SELECT tax_amount, timestamp FROM al_tax_records WHERE identifier = ? ORDER BY timestamp DESC LIMIT 1', {identifier}, function(records)
        NotifyPlayer(source, "=== Status Pajak Anda ===")
        NotifyPlayer(source, "Bracket Pajak: " .. taxBracket.name .. " (" .. (taxBracket.taxRate * 100) .. "%)")
        
        if records and #records > 0 then
            local record = records[1]
            local date = os.date("%Y-%m-%d %H:%M", record.timestamp)
            NotifyPlayer(source, "Pembayaran Pajak Terakhir: $" .. record.tax_amount .. " pada " .. date)
            
            -- Calculate next tax date
            local nextTaxTime = record.timestamp + (Config.TaxCollection.intervalDays * 24 * 60 * 60)
            local nextTaxDate = os.date("%Y-%m-%d %H:%M", nextTaxTime)
            NotifyPlayer(source, "Pembayaran Pajak Berikutnya: " .. nextTaxDate)
        else
            NotifyPlayer(source, "Belum ada riwayat pembayaran pajak.")
        end
        
        -- Get player's tax debt
        MySQL.query('SELECT debt_amount FROM al_tax_debts WHERE identifier = ?', {identifier}, function(debt)
            if debt and #debt > 0 and debt[1].debt_amount > 0 then
                NotifyPlayer(source, "Hutang Pajak: $" .. debt[1].debt_amount)
            end
        end)
    end)
end)

-- Function to check if player is admin
function IsPlayerAdmin(source)
    if source == 0 then return true end -- Console is always admin
    
    if Config.Framework == 'esx' then
        local xPlayer = ESX.GetPlayerFromId(source)
        if xPlayer then
            local playerGroup = xPlayer.getGroup()
            for _, group in ipairs(Config.AdminGroups) do
                if playerGroup == group then
                    return true
                end
            end
        end
    elseif Config.Framework == 'qbcore' then
        local Player = QBCore.Functions.GetPlayer(source)
        if Player then
            local playerPermission = QBCore.Functions.GetPermission(source)
            for _, group in ipairs(Config.AdminGroups) do
                if playerPermission[group] then
                    return true
                end
            end
        end
    end
    
    return false
end

-- Create necessary database tables on resource start
MySQL.ready(function()
    -- Create tax records table
    MySQL.query([[
        CREATE TABLE IF NOT EXISTS al_tax_records (
            id INT AUTO_INCREMENT PRIMARY KEY,
            identifier VARCHAR(50) NOT NULL,
            tax_amount INT NOT NULL,
            tax_details LONGTEXT NOT NULL,
            timestamp INT NOT NULL,
            INDEX idx_identifier (identifier),
            INDEX idx_timestamp (timestamp)
        )
    ]])
    
    -- Create tax debts table
    MySQL.query([[
        CREATE TABLE IF NOT EXISTS al_tax_debts (
            id INT AUTO_INCREMENT PRIMARY KEY,
            identifier VARCHAR(50) NOT NULL UNIQUE,
            debt_amount INT NOT NULL,
            created_at INT NOT NULL,
            last_updated INT NOT NULL,
            INDEX idx_identifier (identifier)
        )
    ]])
    
    -- Create custom tax brackets table
    MySQL.query([[
        CREATE TABLE IF NOT EXISTS al_tax_custom_brackets (
            id INT AUTO_INCREMENT PRIMARY KEY,
            identifier VARCHAR(50) NOT NULL UNIQUE,
            bracket_index INT NOT NULL,
            INDEX idx_identifier (identifier)
        )
    ]])
    
    print(Config.Notifications.prefix .. "Database tables initialized!")
end)
