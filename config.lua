Config = {}

Config.Framework = 'esx' -- Options: 'esx', 'qbcore'
Config.UseESXModern = true -- Use ESX Modern version

Config.TaxCollection = {
    intervalDays = 7, -- Collect taxes every 7 days
    hour = 20, -- 8 PM WIB (Western Indonesian Time)
    minute = 0
}

-- Income tax brackets based on total money (money + bank)
Config.IncomeTaxBrackets = {
    {name = "Sangat Miskin", minAmount = 0, maxAmount = 50000, taxRate = 0.02}, -- 2%
    {name = "Miskin", minAmount = 50001, maxAmount = 200000, taxRate = 0.05}, -- 5%
    {name = "Menengah Ke Bawah", minAmount = 200001, maxAmount = 500000, taxRate = 0.08}, -- 8%
    {name = "Menengah", minAmount = 500001, maxAmount = 1000000, taxRate = 0.10}, -- 10%
    {name = "Menengah Ke Atas", minAmount = 1000001, maxAmount = 3000000, taxRate = 0.12}, -- 12%
    {name = "Kaya", minAmount = 3000001, maxAmount = 10000000, taxRate = 0.15}, -- 15%
    {name = "Sangat Kaya", minAmount = 10000001, maxAmount = math.huge, taxRate = 0.20}, -- 20%
}

Config.VehicleTax = {
    amountPerVehicle = 150000 -- 150k per vehicle
}

Config.ElectronicTax = {
    items = {"phone", "iphone"},
    taxAmount = 5000 -- 5k per electronic item
}

Config.Notifications = {
    prefix = "^3[AL-TAX]^7 ", -- Prefix for chat notifications
    useCustomNotify = false, -- Set to true if you want to use a custom notification system
    customNotify = function(source, message, type)
        -- Example: exports['mythic_notify']:DoHudText(type, message)
    end
}

-- Admin permission settings
Config.AdminGroups = {'admin', 'superadmin', 'owner'} -- Groups that can use admin commands
