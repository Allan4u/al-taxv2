fx_version 'cerulean'
game 'gta5'

author 'Allan'
description 'AL-Tax - Automatic Tax System V2'
version '1.0.0'

shared_scripts {
    'config.lua'
}

client_scripts {
    'client.lua'
}

server_scripts {
    '@oxmysql/lib/MySQL.lua', 
    'server.lua'
}

dependencies {
    'oxmysql',
    'es_extended' 
}
