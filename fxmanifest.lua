fx_version 'cerulean'
game 'gta5'

author 'you'
description 'Batch object screenshotter'
version '1.0.0'

-- You need this resource installed: https://github.com/citizenfx/screenshot-basic
dependency 'screenshot-basic'

shared_scripts {
    'object_list.lua', -- put your models here
}

client_scripts {
    'client.lua',
}

server_scripts {
    'server.lua',
}
