--[[

Charset = "0123456789ABCDEFGHIJKLMNOPQRSTUVWXYZabcdefghijklmnopqrstuvwxyz-_"

Boolean true/false: !?
Value end: ,
String: <
table: {
num indexed table: [
StringId 1/2/3 chars: $§&
integer number: +*/~#|
other numbers: =

]]


-- namespace for the addon
if LibDataEncode == nil then LibDataEncode = {} end
local lib = LibDataEncode

-- Basic values
lib.name = "LibDataEncode"
lib.shortName = "LDE"
lib.version = "1"
lib.internal = {}
local libint = lib.internal

-- Logger

local logger
local LOG_LEVEL_VERBOSE = "V"
local LOG_LEVEL_DEBUG = "D"
local LOG_LEVEL_INFO = "I"
local LOG_LEVEL_WARNING ="W"
local LOG_LEVEL_ERROR = "E"

if LibDebugLogger then

	logger = LibDebugLogger.Create(lib.shortName)

	LOG_LEVEL_VERBOSE = LibDebugLogger.LOG_LEVEL_VERBOSE
	LOG_LEVEL_DEBUG = LibDebugLogger.LOG_LEVEL_DEBUG
	LOG_LEVEL_INFO = LibDebugLogger.LOG_LEVEL_INFO
	LOG_LEVEL_WARNING = LibDebugLogger.LOG_LEVEL_WARNING
	LOG_LEVEL_ERROR = LibDebugLogger.LOG_LEVEL_ERROR

end

local function Print(level, ...)

	if logger == nil then return end

	if type(logger.Log)=="function" then logger:Log(level, ...) end

end

-- Locals

local em = GetEventManager()
local EncodeItem
local EncodeArray
local EncodeTable
local Encode
local log64 = math.log(64)

-- Encoding table

local charset = "0123456789ABCDEFGHIJKLMNOPQRSTUVWXYZabcdefghijklmnopqrstuvwxyz-_"

local controlChars = {
	["TRUE"] = "!",
	["FALSE"] = "?",
	["END"] = ",",
	["STRING"] = "'",
	["TABLE"] = "{",
	["ARRAY"] = "[",
	["STRINGID_1"] = "$",
	["STRINGID_2"] = "§",
	["STRINGID_3"] = "&",
	["INT"] = "<",
	["NUMERIC"] = "=",

}

local chars = {}
local values = {}

for i = 1, 64 do

	local newchar = string.sub(charset, i, i)
	chars[i-1] = newchar
	values[newchar] = i-1

end

-- Encoding

local EncodedDataHandler = ZO_InitializingObject:New()

function EncodedDataHandler:AddString(str)

	local numChars = str:len()

	if self.currentStringLength + numChars > 999 then EncodedDataHandler:NewLine() end

	self.currentString = self.currentString .. str
	self.currentStringLength = self.currentStringLength + numChars

end

function EncodedDataHandler:AddBase64(integer)

	local str = ""

	while integer > 0 do
		local res = chars[integer % 64]
		str = res .. str
		integer = math.floor(integer / 64)
	end

	EncodedDataHandler:AddString(str)

end

function EncodedDataHandler:NewLine()

	if self.currentStringLength == 0 then return end

	local strings = self.encodedStrings

	strings[#strings+1] = self.currentString
	self.currentString = ""
	self.currentStringLength = 0

end

function EncodedDataHandler:EncodeItem(item)

	local itemType = type(item)	-- not sure if an ESO addon should use "itemType" in such a context 

	if itemType == "table" then

		local numEntries = NonContiguousCount(item)
		
		if #item == NonContiguousCount(item) then

			self:AddString(controlChars.ARRAY)
			self:EncodeArray(item)
			self:AddString(controlChars.END)

		else

			self:AddString(controlChars.TABLE)
			self:EncodeTable(item)
			self:AddString(controlChars.END)


		end

	elseif itemType == "string" then

		if self.dictionary[item] then

			local stringId = self.dictionary[item]

			if stringId > 262143 then				
				Print(LOG_LEVEL_WARNING, "StringId out of bounds. The dictionary may contain too many values. Falling back on adding the full string")
				self:AddString(controlChars.STRING)
				self:AddString(item)
				self:AddString(controlChars.END)
		
			else
				if stringId < 63 then
					self:AddString(controlChars.STRINGID_1)
				elseif stringId < 4095 then
					self:AddString(controlChars.STRINGID_2)
				else
					self:AddString(controlChars.STRINGID_3)
				end
				self:AddBase64(stringId)
			end
		else
			self:AddString(controlChars.STRING)
			self:AddString(item)
			self:AddString(controlChars.END)
		end

		self:AddString(item)
		self:AddString(controlChars.END)

	elseif itemType == "number" then

		if math.floor(item) == item and item < 68719476736 then	-- for integers

			self:AddString(controlChars.INT)
			self:AddBase64(item)
			self:AddString(controlChars.END)
		
		else
			self:AddString(controlChars.NUMERIC)
			self:AddString(tostring(item))
			self:AddString(controlChars.END)
		end

	elseif itemType == "boolean" then

		if item == true then
			self:AddString(controlChars.TRUE)
		else
			self:AddString(controlChars.FALSE)
		end

	elseif itemType == "function" then

		Print(LOG_LEVEL_WARNING, "Trying to encode a function. Functions can not be decoded.")

	end

end

function EncodedDataHandler:EncodeArray(array)

	for key, value in ipairs(array) do

		EncodeItem(value)

	end

end

function EncodedDataHandler:EncodeTable(table)

	for key, value in pairs(table) do

		EncodeItem(key)
		EncodeItem(value)

	end

end

---@diagnostic disable-next-line: duplicate-set-field
function EncodedDataHandler:Initialize(data, dictionary)

	self.encodedStrings = {}
	self.dictionary = dictionary

	self.currentString = ""
	self.currentStringLength = 0

	self:EncodeTable(data)
	EncodedDataHandler:NewLine()

	self.currentString = nil
	self.currentStringLength = nil

end

function lib.Encode(data, dictionary)

	return EncodedDataHandler:New(data, dictionary)

end

local function Initialize(event, addon)

	if addon ~= lib.name then return end

	em:UnregisterForEvent(lib.name, EVENT_ADD_ON_LOADED)

end

em:RegisterForEvent(lib.name, EVENT_ADD_ON_LOADED, Initialize)