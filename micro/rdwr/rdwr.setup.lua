local component = require "component"
local sides = require "sides"
local colors = require "colors"

local args = {...}
local eeprom = component.eeprom

if #args == 0 then
	args = {"123", "", "west", "red", "green", "brown"}
elseif #args < 6 then
	error("Usage: setup port trust side ch_control ch_data [ch_data ...]")
end

local file = io.open("rdwr.min.lua", "r")
local image = file:read("*a")
file:close()

local channels = {}
for I = 5, #args do	channels[I-4] = colors[args[I]] end
local config = string.format("%d;%s;%d;%d;%d;", tonumber(args[1]), args[2], sides[args[3]], colors[args[4]], #args-4) .. table.concat(channels, ";") .. ";"

print("Config: " .. config)
print("")

print(string.format("Flashing %d Bytes...", #image))
eeprom.set(image)
print(string.format("Flashing %d Bytes of config...", #config))
eeprom.setLabel("RDWR_RELAY")
eeprom.setData(config)
print("Done!")