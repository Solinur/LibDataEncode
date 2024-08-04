--[[

Charset = "0123456789ABCDEFGHIJKLMNOPQRSTUVWXYZabcdefghijklmnopqrstuvwxyz-_"

Boolean true/false: !?
Value end: ,
String: '
table: {
num indexed table: [
StringId 1/2/3 chars: $§&
integer number: <
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

-- Encoding table

local controlCharConfig = {
	[","] = {"END", nil},
	["!"] = {"TRUE", 1, "DecodeBool"},
	["?"] = {"FALSE", 1, "DecodeBool"},
	["#"] = {"STRINGID_1", 1, "DecodeStringId"},
	["&"] = {"STRINGID_2", 2, "DecodeStringId"},
	["§"] = {"STRINGID_3", 3, "DecodeStringId"},
	["$"] = {"STRING", nil, "DecodeString"},
	["%"] = {"STRING_LONG", nil, "DecodeString"},
	["["] = {"TABLE", nil, "DecodeTable"},
	["]"] = {"ARRAY", nil, "DecodeArray"},
	["+"] = {"INT", nil, "DecodeInteger"},
	["="] = {"NUMERIC", nil, "DecodeNumeric"},
}

local charset = ""
for i = 32, 126 do
	local char = string.char(i)
	if controlCharConfig[char] == nil and char ~= '"' then
		charset = charset .. char
	end
end
local charsetLength = charset:len()
local valueToChar = {}
local charToValue = {}

for i = 1, charsetLength do

	local char = string.sub(charset, i, i)
	valueToChar[i-1] = char
	charToValue[char] = i-1

end



local controlChars = {}
local decoderFunctionNames = {}

for char, data in pairs(controlCharConfig) do
	assert(charToValue[char] == nil, "Error: A char cannot be part of the control character set and the encoder character set at the same time!")

	local name, length, decoderName = unpack(data)
	controlChars[name] = char

	if decoderName then
		decoderFunctionNames[char] = decoderName
	end
end

DictionaryObject = ZO_InitializingObject:Subclass()

local function getKeysSortedByValue(t)
	local keys = {}
	for key in pairs(t) do
	  table.insert(keys, key)
	end
  
	table.sort(keys, function(a, b) return t[a] < t[b] end)  
	return keys
end

---@diagnostic disable-next-line: duplicate-set-field
function DictionaryObject:Initialize(data)
	self.dictionary = {}
	self.counts = {[1] ={}, [2] ={}, [3] ={}}
	self:ScanTable(data)
	local sortedDict = getKeysSortedByValue(self.counts[3], sortFunction)
	TESTDICT = sortedDict
end


function DictionaryObject:ScanTable(data)
	local isArray = type(data) == "table" and (#data == NonContiguousCount(data))
	for k,v in pairs(data) do
		if not isArray and self:ValidateValue(k) then
			self:IncreaseCount(k)
		end		
		if self:ValidateValue(v) then
			self:IncreaseCount(v)
		end
	end
end

function DictionaryObject:ValidateValue(value)
	if type(value) == "number" then
		if math.floor(value) == value and value <100 and value >= 0 then
			return true
		end
		return string.len(value) > 2
	end
	if type(value) == "string" then
		return value:len() > 2
	end
	if type(value) == "table" then
		DictionaryObject:ScanTable(value)
	end
	return false
end

function DictionaryObject:IncreaseCount(value)
	local counts = self.counts
	if counts[1][value] == nil then
		counts[1][value] = true
	elseif counts[2][value] == nil then
		counts[2][value] = true
	elseif counts[3][value] == nil then
		counts[3][value] = 3
	else
		counts[3][value] = counts[3][value] + 1
	end
end

local function MakeDictionary(data)
	local dict = DictionaryObject:New(data)
	return dict.dictionary
end

lib.MakeDictionary = MakeDictionary

-- Encoding
EncodeDataHandler = ZO_InitializingObject:Subclass()

---@diagnostic disable-next-line: duplicate-set-field
function EncodeDataHandler:Initialize(data, dictionary)
	if dictionary == true then
		dictionary = MakeDictionary(data)
	end

	self.encodedStrings = {}
	self.currentString = ""
	self.currentStringLength = 0

	if dictionary ~= nil then 
		self:AddString("D" .. controlChars.ARRAY)
		self:EncodeArray(dictionary)
		self:AddString(controlChars.END)
		self.dictionary = dictionary
	else 
		self.dictionary = {}
	end

	self:EncodeItem(data)
	self:NewLine()

	self.currentString = nil
	self.currentStringLength = nil
end

function EncodeDataHandler:AddString(str)
	local numChars = str:len()
	if self.currentStringLength + numChars > 999 then self:NewLine() end
	self.currentString = self.currentString .. str
	self.currentStringLength = self.currentStringLength + numChars
end

function EncodeDataHandler:AddInteger(integer)
	local str = ""

	while integer > 0 do
		local res = valueToChar[integer % 64]
		str = res .. str
		integer = math.floor(integer / 64)
	end
	self:AddString(str)
end

function EncodeDataHandler:NewLine()
	if self.currentStringLength == 0 then return end
	local strings = self.encodedStrings
	strings[#strings+1] = self.currentString
	self.currentString = ""
	self.currentStringLength = 0
end

function EncodeDataHandler:EncodeItem(value)
	local valueType = type(value)

	if valueType == "table" then
		local numEntries = NonContiguousCount(value)

		if #value == numEntries then
			self:AddString(controlChars.ARRAY)
			self:EncodeArray(value)
			self:AddString(controlChars.END)
		else
			self:AddString(controlChars.TABLE)
			self:EncodeTable(value)
			self:AddString(controlChars.END)
		end

	elseif valueType == "string" then
		local stringId = self.dictionary[value]
		if stringId and stringId < charsetLength^3 then
			if stringId < charsetLength then
				self:AddString(controlChars.STRINGID_1)
			elseif stringId < charsetLength^2 then
				self:AddString(controlChars.STRINGID_2)
			else
				self:AddString(controlChars.STRINGID_3)
			end
			self:AddInteger(stringId)
		else
			local stringLength = value:len()
			if stringLength < charsetLength then
				self:AddString(controlChars.STRING)
				self:AddInteger(stringLength)
				self:AddString(value)
			elseif stringLength < charsetLength^2 then
				if stringLength > 996 then
					Print(LOG_LEVEL_ERROR, "Trying to encode a string, which exceeds maximum length of 996 chars!")
				end
				self:AddString(controlChars.STRING_LONG)
				self:AddInteger(stringLength)
				self:AddString(value:sub(1, 996))
			end
		end
	elseif valueType == "number" then
		if math.floor(value) == value and value < 68719476736 then	-- for integers
			self:AddString(controlChars.INT)
			self:AddInteger(value)
			self:AddString(controlChars.END)
		else
			self:AddString(controlChars.NUMERIC)
			self:AddString(tostring(value))
			self:AddString(controlChars.END)
		end

	elseif valueType == "boolean" then
		if value == true then
			self:AddString(controlChars.TRUE)
		else
			self:AddString(controlChars.FALSE)
		end

	elseif valueType == "function" then
		Print(LOG_LEVEL_INFO, "Encoding of functions is not supported.")
	end
end

function EncodeDataHandler:EncodeArray(array)
	for key, value in ipairs(array) do
		self:EncodeItem(value)
	end
end

function EncodeDataHandler:EncodeTable(table)
	for key, value in pairs(table) do
		self:EncodeItem(key)
		self:EncodeItem(value)
	end
end

function lib.Encode(data, dictionary)
	local encodedData = EncodeDataHandler:New(data, dictionary)
	return encodedData.encodedStrings
end

-- Decoding
local DecodeDataHandler = ZO_InitializingObject:Subclass()

---@diagnostic disable-next-line: duplicate-set-field
function DecodeDataHandler:Initialize(encodedData)
	self.encodedStrings = encodedData
	self.dictionary = {}
	self.currentStringIndex = 1
	self.currentStringPos = 1
	self.currentString = self:GetCurrentString()
	self.currentStringLength = string.len(self.currentString)
	if encodedData[1]:sub(1, 2) == "D[" then
		self.currentStringPos = 2
		self.dictionary = self:DecodeArray()
	end
	self.data = self:DecodeItem()
end

function DecodeDataHandler:GetCurrentString()
	return self.encodedStrings[self.currentStringIndex]
end

function DecodeDataHandler:GetCurrentStringAndPos()
	return self:GetCurrentString(), self.currentStringPos
end

function DecodeDataHandler:GetNextChar(noPosIncrement)
	local encodedString, pos = self:GetCurrentStringAndPos()
	if encodedString == nil then return controlChars.END end
	if noPosIncrement ~= true then
		self.currentStringPos = pos + 1
	end
	Print(LOG_LEVEL_DEBUG, "Next char: %s - New pos: %d", encodedString:sub(pos, pos), self.currentStringPos)
	return encodedString:sub(pos, pos)
end

function DecodeDataHandler:GetEncodedItem(length)
	local encodedString, pos = self:GetCurrentStringAndPos()
	if length == nil then
		length = encodedString:find(controlChars.END, pos, true) - pos	--TODO detect if "," is part of string!
		self:MoveCurrentPos(1)
	end
	self:MoveCurrentPos(length)
	Print(LOG_LEVEL_DEBUG, "Item: %s - New pos: %d", encodedString:sub(pos, pos+length), self.currentStringPos)
	return encodedString:sub(pos, pos+length-1)
end

function DecodeDataHandler:MoveCurrentPos(offset)
	local newpos = self.currentStringPos + offset
	if newpos < self.currentStringLength then
		self.currentStringPos = newpos
		return
	end
	self.currentStringIndex = self.currentStringIndex + 1
	self.currentStringPos = 1
end

function DecodeDataHandler:DecodeItem()
	local controlChar = self:GetNextChar()
	local functionName = decoderFunctionNames[controlChar]
	Print(LOG_LEVEL_DEBUG, "%s (%s):", functionName, controlChar)
	return self[functionName](self, controlChar)
end

function DecodeDataHandler:DecodeBool(controlChar)
	if controlChar == controlChars.TRUE then return true end
	if controlChar == controlChars.FALSE then return false end
	assert(true, "Error: the control character is not boolean!")
end

function DecodeDataHandler:DecodeStringId(controlChar)
	local length = controlCharConfig[controlChar][2]
	local encodedItem = self:GetEncodedItem(length)
	local stringId = self:DecodeBase(encodedItem)
	return self.dictionary[stringId]
end

function DecodeDataHandler:DecodeBase(encodedItem)
	local value = 0
	for i = 1, encodedItem:len() do
		local char = encodedItem:sub(i,i)
		value = value + charToValue[char] * charsetLength^(i-1)
	end
	Print(LOG_LEVEL_DEBUG, "IntChars: %s (%d):", encodedItem, value)
	return value
end

function DecodeDataHandler:DecodeString(controlChar)
	local encodedLength = self:GetNextChar()
	if controlChar == controlChars.STRING_LONG then
		encodedLength = encodedLength .. self:GetNextChar()
	end
	local length = self:DecodeBase(encodedLength)
	return self:GetEncodedItem(length)
end

function DecodeDataHandler:DecodeArray()
	local array = {}
	while self:GetNextChar(true) ~= "," do
		array[#array+1] = self:DecodeItem()
	end
	self:MoveCurrentPos(1)
	return array
end

function DecodeDataHandler:DecodeTable()
	local table = {}
	while self:GetNextChar(true) ~= "," do
		local key = self:DecodeItem()
		table[key] = self:DecodeItem()
	end
	self:MoveCurrentPos(1)
	return table
end

function DecodeDataHandler:DecodeInteger()
	local encodedItem = self:GetEncodedItem()
	return self:DecodeBase(encodedItem)
end

function DecodeDataHandler:DecodeNumeric()
	return tonumber(self:GetEncodedItem())
end


function lib.Decode(data)
	local decoded = DecodeDataHandler:New(data)
	return decoded.data, decoded.dictionary
end

local subTable = {
	["A"] = 1,
	["{1,2,3}"] = "A",
	[0.5] = "asdada",
	[1.5] = "bsdada",
	[2.5] = "csdada",
}

local testTable = {
	["tarb"] = subTable,
	["tarb2"] = subTable,
	["tarb3"] = subTable,
	[0.5] = "asdada",
	[0] = 0.5,
	[1] = {"A", "B", "C"},
	[2] = 0.5,
	[3] = 0.5,
	[4] = 0.5,
}

local testDict = {0.5, 1.5, 2.5, "asdada", "bsdada", "csdada"}

lib.testTable = testTable
lib.testDict = testDict

local function CompareTables(t1, t2)
	for k, v in pairs(t1) do
		if type(v) == "table" and type(t2[k]) == "table" then
			CompareTables(v, t2[k])
		elseif v ~= t2[k] then
			return false
		end
	end
	for k, v in pairs(t2) do
		if type(v) == "table" and type(t1[k]) == "table" then
			CompareTables(v, t1[k])
		elseif v ~= t1[k] then
			return false
		end
	end
	return true
end


local function PerformTest(testname, testTable, testDict)

	local decoded = lib.Decode(lib.Encode(testTable, testDict))
	local result = CompareTables(testTable, decoded)
	Print(LOG_LEVEL_INFO, "Test '%s': %s", testname, tostring(result))
	if result == false then TESTDATA = {testTable, decoded} end

end


function lib.PerformSelfTest()
	PerformTest("No Dictionary", testTable)
	PerformTest("With Dictionary", testTable, true)
	PerformTest("Auto Dictionary", testTable, testDict)
end


local function Initialize(event, addon)
	if addon ~= lib.name then return end
	em:UnregisterForEvent(lib.name, EVENT_ADD_ON_LOADED)
	lib.PerformSelfTest()
end

em:RegisterForEvent(lib.name, EVENT_ADD_ON_LOADED, Initialize)