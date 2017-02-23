local stdlib	= require "stdlib"

-- The type library namespace.
local types = {}

types.NamePattern = "[a-zA-Z_][a-zA-Z0-9_]*"
types.TypeKeywords =
{
	["name"]		= function (AType)
		return AType.__Name
	end,
	["isAbstract"]	= function (AType)
		return AType.__Abstract
	end,
	["base"]		= function (AType)
		return AType.__Inherit
	end,
	["members"]		= function (AType)
		return types.MapMembers(AType)
	end,
	["interfaces"]	= function (AType)
		return types.MapInterfaces(AType)
	end
}
types.ObjectKeywords =
{
	["type"]		= function (AObject)
		return getmetatable(AObject)
	end,
	["fields"]		= function (AObject)
		return types.MapFields(AObject)
	end,
	["properties"]	= function (AObject)
		return types.MapProperties(AObject)
	end
}

types.TypeHandler = {}
-- Indexer for TypeDef tables.
function types.TypeHandler:__index(AKey)
	-- Keys must be strings.
	if type(AKey) ~= "string" then
		return nil
	end

	if string.sub(AKey, 1, 2) == "__" then
		-- Keys with the "__" prefix are not inherited.
		return nil
	elseif types.TypeKeywords[AKey] ~= nil then
		-- Return keyword member.
		return types.TypeKeywords[AKey](self)
	else
		-- Check for an inherited member.
		local tType
		for _, tType in types.TypeIterator, self, nil do
			local vValue = rawget(tType, AKey)
			if vValue ~= nil then
				return vValue
			end
		end
		
		return nil
	end
	
	-- Return nil if not found.
	return nil
end
-- NewIndexer for TypeDef tables.
function types.TypeHandler:__newindex(AKey, AValue)
	-- Keys must be strings.
	cerrorf("Member names must be strings.", type(AKey) == "string", 2)

	local sSuffix = string.sub(AKey, -6)
	if sSuffix == ".__get" or sSuffix == ".__set" then
		-- Property accessors must match the naming conventions.
		local sName = string.sub(AKey, 1, -7)
		cerrorf('Property name "%s" contains invalid characters.', string.match(sName, "^" .. types.NamePattern .. "$") ~= nil, 2)
		
		-- Property name may not be a reserved type keyword.
		cerrorf('Property name "%s" is a reserved type keyword.', types.TypeKeywords[sName] == nil, 2)
		-- Property accessors must be functions.
		cerrorf("Property accessor must be a function.", type(AValue) == "function", 2)
	else
		if string.match(AKey, "^" .. types.NamePattern .. "$") == nil then
			-- Members must match the naming conventions.
			errorf('Member name "%s" contains invalid characters.', AKey, 2)
		else
			-- Member name may not be a reserved type keyword.
			cerrorf('Member name "%s" is a reserved type keyword.', types.TypeKeywords[AKey] == nil, 2)
		end
	end	
	
	-- Set the member.
	rawset(self, AKey, AValue)
end
-- String casting for TypeDef tables.
function types.TypeHandler:__tostring()
	-- Return the type name.
	return string.format("type(%s)", self.__Name)
end
-- Instanciation shortcut.
function types.TypeHandler:__call(...)
	return self.New(...)
end

types.ObjectHandler = {}
-- Indexer for Object tables.
function types.ObjectHandler:__index(AKey)
	local tdType = getmetatable(self)
	
	if type(AKey) == "string" then
		if string.sub(AKey, 1, 2) == "__" then
			-- Field indexer does not query the type.
			return nil
		elseif types.ObjectKeywords[AKey] ~= nil then
			-- Return object keyword.
			return types.ObjectKeywords[AKey](self)
		else
			-- Query the TypeDef.
			local vTypeQuery = tdType[AKey]
			if vTypeQuery ~= nil then
				return vTypeQuery
			elseif string.match(AKey, "^" .. types.NamePattern .. "$") ~= nil then
				-- Try get property.
				local fPropertyGetter = tdType[AKey .. ".__get"]
				if fPropertyGetter ~= nil then
					return fPropertyGetter(self)
				end
			end
		end
	end
	
	-- Try default indexer.
	local fDefaultIndexer = tdType["self.__get"]
	if fDefaultIndexer ~= nil then
		return fDefaultIndexer(self, AKey)
	end
	
	-- Throw error if not found.
	errorf('Attempted to access unknown member "%s.%s".', tdType.__Name, AKey, 2)
end
-- NewIndexer for Object tables.
function types.ObjectHandler:__newindex(AKey, AValue)
	local tdType = getmetatable(self)
	
	if type(AKey) == "string" then
		if string.sub(AKey, 1, 2) == "__" then
			-- Field name must match naming conventions.
			local sName = string.sub(AKey, 3)
			cerrorf('Field name "%s" contains invalid characters.', string.match(sName, "^" .. types.NamePattern .. "$") ~= nil, 2)
		
			-- Direct field access.
			rawset(self, AKey, AValue)
			return
		else
			-- Query the TypeDef.
			local vTypeQuery = tdType[AKey]
			if vTypeQuery ~= nil then
				errorf('Attempted to set type member "%s.%s".', tdType.__Name, AKey, 2)
			elseif string.match(AKey, "^" .. types.NamePattern .. "$") ~= nil then
				-- Try set property.
				local fPropertySetter = tdType[AKey .. ".__set"]
				if fPropertySetter ~= nil then
					fPropertySetter(self, AValue)
					return
				end
			end
		end
	end
	
	-- Try default newindexer.
	local fDefaultNewIndexer = tdType["self.__set"]
	if fDefaultNewIndexer ~= nil then
		fDefaultNewIndexer(self, AKey, AValue)
		return
	end
	
	-- Throw error if not found.
	errorf('Attempted to access unknown member "%s.%s".', tdType.__Name, AKey, 2)
end
-- String casting for Object tables.
function types.ObjectHandler:__tostring()
	local tdType = getmetatable(self)
	
	-- Since this is the default method, just output some instance information.
	local sResult = string.format("object(%s)", tdType.__Name)
	
	-- Map all fields without recursion.
	local tFields = {}
	local sFieldName, vFieldValue
	for sFieldName, vFieldValue in pairs(self.fields) do
		local sFieldValue
		if type(vFieldValue) == "string" then
			sFieldValue = stdlib.escape(vFieldValue)
		else
			sFieldValue = tostring(vFieldValue)
		end
	
		table.insert(tFields, string.format("%s = %s", sFieldName, sFieldValue))
	end
	
	sResult = sResult .. "{" .. table.concat(tFields, ", ") .. "}"
	
	return sResult
end

-- Check if the input is a type.
function types.IsType(AVar)
	return getmetatable(AVar) == types.TypeHandler
end
-- Check if the input is an object.
function types.IsObject(AVar)
	return types.IsType(getmetatable(AVar))
end

-- Iterate over all types in the given hierarchy in level-order left-to-right.
function types.TypeIterator(AType, AState)
	cerrorf("Input argument must be a type.", types.IsType(AType), 2)

	if AState == nil then
		local tInherit = rawget(AType, "__Inherit")
		local tQueue = stdlib.List.New({AType})
		
		for _, tChild in ipairs(tInherit) do
			tQueue:PushRight(tChild)
		end
		
		return tQueue, tQueue:PopLeft()
	else	
		if AState.IsEmpty then
			return nil
		end
	
		local tCurrent = AState:PopLeft()
		local tInherit = rawget(tCurrent, "__Inherit")
		
		for _, tChild in ipairs(tInherit) do
			AState:PushRight(tChild)
		end
		
		return AState, tCurrent
	end
end
-- Recursively map all members of the specified type.
function types.MapMembers(AType, AOutput)
	cerrorf("Input argument must be a type.", types.IsType(AType), 2)
	if AOutput == nil then AOutput = {} end
	cerrorf("Output argument must be a table.", type(AOutput) == "table", 2)
	
	local tType
	for _, tType in types.TypeIterator, AType, nil do
		-- Ensure that the default iterator is used.
		local sKey, vValue
		for sKey, vValue in next, tType, nil do
			if type(sKey) == "string" and string.sub(AKey, 1, 2) ~= "__" then
				if AOutput[sKey] == nil then
					AOutput[sKey] = {Declarer = tType, Declaration = vValue}
				end
			end
		end
	end
	
	return AOutput
end
-- Map all fields of the specified object.
function types.MapFields(AObject)
	cerrorf("Input argument must be an object.", types.IsObject(AObject), 2)
	
	local tResult = {}

	-- Ensure that the default iterator is used.
	local sKey, vValue
	for sKey, vValue in next, AObject, nil do
		if string.sub(sKey, 1, 2) == "__" then
			local sName = string.sub(sKey, 3)
			tResult[sName] = vValue
		end
	end
	
	return tResult
end
-- Map all fields of the specified object.
function types.MapProperties(AObject)
	cerrorf("Input argument must be an object.", types.IsObject(AType), 2)
	local tdType = getmetatable(AObject)
	local tMembers = types.MapMembers(tdType)
	local tProperties = {}
	
	local sMemberName, tMember
	for sMemberName, tMember in pairs(tMembers) do
		if string.sub(sMemberName, -6) == ".__get" then
			local sName = string.sub(sMemberName, 1, -7)
			tProperties[sName] = tMember.Declaration(AObject)
		end
	end
	
	return tProperties
end

-- Check if a type derives from another or is equal to it.
function types.Derives(AType, ABaseType)
	cerrorf("Input type must be a type.", types.IsType(AType), 2)
	cerrorf("Input base type must be a type.", types.IsType(ABaseType), 2)
	
	local tType
	for _, tType in types.TypeIterator, AType, nil do
		if tType == ABaseType then
			return true
		end
	end
	
	return false
end

-- Define a new type.
function types.DeclareType(AName, ...)
	-- Name must match naming conventions.
	cerrorf("Name must be a string.", type(AName) == "string", 2)
	cerrorf("Name contains invalid characters.", string.match(AName, types.NamePattern) ~= nil, 2)
	
	local tArgs = {...}
	local tdType =
	{
		__Name		= AName,
		__Inherit	= {},
		__Abstract	= false,
		
		New			= function () return types.New(tdType) end
	}
	setmetatable(tdType, types.TypeHandler)	
	
	local tArg
	for _, tArg in ipairs(tArgs) do
		if types.IsType(tArg) then
			table.insert(tdType.__Inherit, tArg)
		elseif tArg == "abstract" then
			if tdType.__Abstract then
				error("Abstract modifier already defined.", 2)
			end
			tdType.__Abstract = true
		else
			error("Arguments may only be types and modifiers.", 2)
		end
	end
	
	local sKey, vValue
	for sKey, vValue in next, types.ObjectHandler, nil do
		rawset(tdType, sKey, vValue)
	end
	
	return tdType
end
-- Create a new instance.
function types.New(AType, AFields)
	cerrorf("Input type must be a type.", types.IsType(AType), 2)
	cerrorf("Type must not be abstract.", not AType.__Abstract, 2)
	if AFields == nil then AFields = {} end
	cerrorf("Fields mapping must be a table.", type(AFields) == "table", 2)
	
	local oInstance = {}
	setmetatable(oInstance, AType)
	
	local sFieldName, vFieldValue
	for sFieldName, vFieldValue in next, AFields, nil do
		cerrorf("Field names must be strings.", type(sFieldName) == "string", 2)
		cerrorf('Field name "%s" contains invalid characters.', sFieldName, string.match(sFieldName, types.NamePattern) ~= nil, 2)
		rawset(oInstance, "__" .. sFieldName, vFieldValue)
	end
	
	return oInstance
end

-- Check if a variable satisfies a type constraint.
function types.Is(AVariable, ATypeConstraint)
	local sVarType = type(AVariable)
	if type(ATypeConstraint) == "string" then
		if ATypeConstraint == "type" then
			return types.IsType(AVariable)
		elseif ATypeConstraint == "object" then
			return types.IsObject(AVariable)
		elseif ATypeConstraint == "reference" then
			return sVarType == "table" or sVarType == "userdata" or sVarType == "thread"
		elseif ATypeConstraint == "value" then
			return sVarType == "string" or sVarType == "number" or sVarType == "boolean"
		elseif ATypeConstraint == "any" then		
			return true
		elseif ATypeConstraint == "notnil" then
			return AVariable ~= nil
		elseif ATypeConstraint == "file" then
			return io.type(AVariable) == "file"
		else
			return sVarType == ATypeConstraint
		end
	elseif types.IsType(ATypeConstraint) then
		if types.IsObject(AVariable) then
			return types.Derives(getmetatable(AVariable), ATypeConstraint)
		end
		
		return false
	else
		return false
	end
end
-- Check if a variable satisfies any of the specified type constraints.
function types.IsAny(AVariable, ...)
	local tArgs = {...}
	
	local vConstraint
	for _, vConstraint in ipairs(tArgs) do
		if types.Is(AVariable, vConstraint) then
			return true
		end
	end
	
	return false
end
-- Check if a variable satisfies all of the specified type constraints.
function types.IsAll(AVariable, ...)
	local tArgs = {...}
	
	local vConstraint
	for _, vConstraint in ipairs(tArgs) do
		if not types.Is(AVariable, vConstraint) then
			return false
		end
	end
	
	return true
end

-- Assert argument type validity.
function types.checkArg(AArgumentName, AArgument, ...)
	local tArgs = {...}

	if not stdlib.DEBUG then return end

	if not types.IsAny(AArgument, table.unpack(tArgs)) then
		local sGot
		if types.IsObject(AArgument) then
			sGot = types.ObjectHandler.__tostring(AArgument)
		elseif types.IsType(AArgument) then
			sGot = types.TypeHandler.__tostring(AArgument)
		else
			sGot = type(AArgument)
		end
		
		local tRequire = {}
		local vRequire
		for _, vRequire in ipairs(tArgs) do
			table.insert(tRequire, tostring(vRequire))
		end
	
		errorf("Invalid value for argument %s: got %s, requires any of %s.", AArgumentName, sGot, table.concat(tRequire, "," ), 3)
	end
end
-- Assert argument type validity and use a default value if necessary.
function types.defaultArg(AArgumentName, AArgument, ...)
	local tArgs = {...}
	
	if not stdlib.DEBUG then 
		if AArgument ~= nil then
			return AArgument
		else
			return tArgs[#tArgs]
		end
	end	
	
	if AArgument == nil then
		return tArgs[#tArgs]
	elseif types.IsAny(AArgument, table.unpack(tArgs, 1, #tArgs - 1)) then
		return AArgument
	else
		local sGot
		if types.IsObject(AArgument) then
			sGot = types.ObjectHandler.__tostring(AArgument)
		elseif types.IsType(AArgument) then
			sGot = types.TypeHandler.__tostring(AArgument)
		else
			sGot = type(AArgument)
		end
		
		local tRequire = {}
		local I
		for I = 1, #tArgs - 1 do
			table.insert(tRequire, tostring(tArgs[I]))
		end
	
		errorf("Invalid value for argument %s: got %s, requires any of %s or nil.", AArgumentName, sGot, table.concat(tRequire, "," ), 3)
	end
end

_G.Is 			= types.Is
_G.Type 		= types.DeclareType
_G.New			= types.New
_G.checkArg		= types.checkArg
_G.defaultArg	= types.defaultArg

-- The equatable predicate.
types.Equatable = Type("Equatable", "abstract")

function types.Equatable:Equals(AOther)
	return self == AOther
end

-- Globally unique identifier.
types.GUID = Type("GUID", types.Equatable)

types.GUID.Format = "{%.2X%.2X%.2X%.2X-%.2X%.2X-%.2X%.2X-%.2X%.2X-%.2X%.2X%.2X%.2X%.2X%.2X}"

function types.GUID.New(ABytesOrString)
	if type(ABytesOrString) == "string" then
		return types.GUID.FromString(ABytesOrString)
	elseif type(ABytesOrString) == "table" then
		return types.GUID.FromBytes(ABytesOrString)
	elseif ABytesOrString == nil then
		return types.GUID.FromBytes({})
	else
		error("Invalid types.GUID initializer.", 2)
	end
end
function types.GUID.FromString(AString)
	checkArg("AString", AString, "string")
	
	local tBytes = {}
	AString = string.gsub(AString, "[^a-fA-F0-9]", "")

	if #AString ~= 32 then
		AString = AString .. string.rep("0", 32 - #AString)
	end
	
	local I
	for I = 1, 16 do
		local sHex = string.sub(AString, (I-1)*2 + 1, (I-1)*2 + 2)
		tBytes[I] = tonumber(sHex, 16)
	end
	
	return New(types.GUID, {FBytes = tBytes})
end
function types.GUID.FromBytes(ABytes)
	checkArg("ABytes", ABytes, "table")
	
	local tBytes = {}
	local I
	for I = 1, 16 do
		tBytes[I] = defaultArg(string.format("ABytes[%d]", I), ABytes[I], "number", 0)
	end
	
	return New(types.GUID, {FBytes = tBytes})
end
function types.GUID.Random()
	local tBytes = {}

	local I
	for I = 1, 16 do
		tBytes[I] = math.random(0, 255)
	end
	
	tBytes[5] = bit32.bor(bit32.band(tBytes[5], 0x3F), 0x80)
	tBytes[7] = bit32.bor(bit32.band(tBytes[5], 0x0F), 0x40)
	
	return types.GUID.New(tBytes)
end

function types.GUID:CloneBytes()
	local tCopy = {}

	local I
	for I = 1, 16 do
		tCopy[I] = self.__FBytes[I]
	end

	return tCopy
end
function types.GUID:ToString()
	return string.format(types.GUID.Format, table.unpack(self.__FBytes))
end
function types.GUID:Equals(AOther)
	local tSelf = self.__FBytes

	if Is(AOther, types.GUID) then
		local tOther = AOther:CloneBytes()
		
		local I
		for I = 1, 16 do
			if tSelf[I] ~= tOther[I] then
				return false
			end
		end
		
		return true
	elseif types.IsAny(AOther, "table", "string") then
		return self:Equals(types.GUID.New(AOther))
	else
		return false
	end
end

function types.GUID:__tostring()
	return self:ToString()
end
function types.GUID.__eq(ALeft, ARight)
	if Is(ALeft, types.GUID) then
		return ALeft:Equals(ARight)
	else
		return ARight:Equals(ALeft)
	end
end

-- Wrapper class for the stdlib.List.
types.List = Type("List")

function types.List.New(AItems)
	return New(types.List,
	{
		FList = stdlib.List.New(AItems)
	})
end

local sName, fFunc
for sName, fFunc in next, stdlib.List.Methods, nil do
	types.List[sName] = function (self, ...) return fFunc(self.__FList, ...) end
end
for sName, fFunc in next, stdlib.List.Properties, nil do
	types.List[sName .. ".__get"] = function (self) return fFunc(self.__FList) end
end
types.List.__len = function (self, ...) return stdlib.List.__len(self.__FList, ...) end
types.List.__eq = function (self, ...) return stdlib.List.__eq(self.__FList, ...) end

types.List["self.__get"] = function (self, AKey)
	return self.__FList[AKey]
end
types.List["self.__set"] = function (self, AKey, AValue)
	self.__FList[AKey] = AValue
end

return types