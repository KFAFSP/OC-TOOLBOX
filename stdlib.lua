-- The standard library namespace.
local stdlib = {}

-- Formatted versions of print and error (optionally conditional).
function stdlib.printf(...)
	local tArgs = {...}
	
	if #tArgs == 0 then
		print()
	else
		local sMessage = tArgs[1]
		local _, nFmtArgs = string.gsub((string.gsub(sMessage, "%%%%", "")), "%%", "")
		
		if #tArgs < 1 + nFmtArgs then
			error("Too few arguments.", 2)
		elseif #tArgs > 1 + nFmtArgs then
			error("Too many arguments.", 2)
		end
		
		local bSuccess, sMessage = pcall(string.format, sMessage, table.unpack(tArgs, 2, 1 + nFmtArgs))
		if not bSuccess then
			error(sMessage, 2)
		end
		
		print(sMessage)
	end
end
function stdlib.errorf(...)
	local tArgs = {...}
	
	if #tArgs == 0 then
		error(nil, 2)
	else
		local sMessage = tArgs[1]
		local nLevel = 2
		local _, nFmtArgs = string.gsub((string.gsub(sMessage, "%%%%", "")), "%%", "")
		
		if #tArgs < 1 + nFmtArgs then
			error("Too few arguments.", 2)
		elseif #tArgs == 2 + nFmtArgs then
			if type(tArgs[#tArgs]) ~= "number" then
				error("Error level argument must be a number.", 2)
			end
			
			nLevel = 1 + tArgs[#tArgs]
		elseif #tArgs > 2 + nFmtArgs then
			error("Too many arguments.", 2)
		end
		
		local bSuccess, sMessage = pcall(string.format, sMessage, table.unpack(tArgs, 2, 1 + nFmtArgs))
		if not bSuccess then
			error(sMessage, 2)
		end
		
		error(sMessage, nLevel)
	end
end
function stdlib.cerrorf(...)
	local tArgs = {...}
	
	if #tArgs < 2 then
		error("Too few arguments.", 2)
	else
		local vCondition = tArgs[#tArgs]
		if type(vCondition) == "number" then
			tArgs[#tArgs] = vCondition + 1
			vCondition = tArgs[#tArgs - 1]
			table.remove(tArgs, #tArgs - 1)
		else
			table.remove(tArgs, #tArgs)
		end
		
		local sCondType = type(vCondition)
		if sCondType == "string" then
			local sError
			vCondition, sError = load(vCondition, "error_condition", "t", _ENV)
			if fCond == nil then
				error("Invalid condition: " .. sError, 2)
			end
			sCondType = "function"
		end
		if sCondType == "function" then
			local bOK
			bOK, vCondition = pcall(vCondition)
			
			if not bOK then
				vCondition = false
			end
		end

		if vCondition then
			return vCondition
		end
		
		stdlib.errorf(table.unpack(tArgs))
	end
end

-- Debug flag which enables the contract verification functions.
stdlib.DEBUG = true

-- Debugging functions (contract verification), which can be disabled.
function stdlib.assertf(...)
	if not stdlib.DEBUG then return end

	local tArgs = {...}
	if #tArgs >= 3 and type(tArgs[#tArgs]) == "number" then
		tArgs[#tArgs] = tArgs[#tArgs] + 1
	end
	return cerrorf(table.unpack(tArgs))
end
function stdlib.debugf(...)
	if not stdlib.DEBUG then return end

	local tArgs = {...}
	if #tArgs == 0 then
		return
	else
		tArgs[1] = "#DEBUG# " .. tArgs[1]
		printf(table.unpack(tArgs))
	end
end

-- Read the contents of a file into a string or a table of lines.
function stdlib.readFile(AFilePath, AMode)
	stdlib.assertf("Path must be a string.", type(AFilePath) == "string", 2)
	if AMode == nil then
		AMode = "string"
	else
		stdlib.assertf("Mode must be a string.", type(AMode) == "string", 2)
	end
	
	local hFile, sError = io.open(AFilePath, "r")
	if hFile == nil then
		stdlib.errorf("Unable to open file %q for reading: %q.", AFilePath, sError, 2)
	end
	
	if AMode == "string" then
		local sRead = hFile:read("*a")
		hFile:close()
		
		return sRead
	elseif AMode == "table" then
		local tRead = {}
		local sLine = hFile:read("*l")
		
		while sLine ~= nil do
			table.insert(tRead, sLine)
			sLine = hFile:read("*l")
		end
		
		hFile:close()
		
		return tRead
	else
		stdlib.errorf("Unknown readFile mode %q.", AMode, 2)
	end
end
-- Write a file via a string or a table of lines.
function stdlib.writeFile(AFilePath, AData)
	stdlib.assertf("Path must be a string.", type(AFilePath) == "string", 2)

	local hFile, sError = io.open(AFilePath, "w")
	if hFile == nil then
		stdlib.errorf("Unable to open file %q for writing: %q.", AFilePath, sError, 2)
	end
	
	local sDataType = type(AData)
	if sDataType == "string" then
		hFile:write(AData)
	elseif sDataType == "table" then
		local sLine
		for _, sLine in ipairs(AData) do
			hFile:write(sLine .. "\n")
		end
	else
		error("Data must be either a table or a string.", 2)
	end
	
	hFile:close()
end

-- Escape a string.
function stdlib.escape(AString)
	stdlib.assertf("Input must be a string.", type(AString) == "string", 2)
	
	AString = string.gsub(AString, "\n", "\\n")
	return string.format("%q", AString)
end

-- Create a deep copy of a value.
function stdlib.copy(AVariable, ALookup, ARecursion, ASuppressErrors)
	if ALookup == nil then ALookup = {} end
	if ARecursion == nil then ARecursion = math.huge end
	if ASuppressErrors == nil then ASuppressErrors = false end
	
	stdlib.assertf("Lookup argument must be a table.", type(ALookup) == "table", 2)
	stdlib.assertf("Recursion argument must be a number.", type(ARecursion) == "number", 2)
	stdlib.assertf("Error suppression option must be a boolean.", type(ASuppressErrors) == "boolean", 2)

	local function __copy(__Var, __Recursion)
		local sVarType = type(__Var)
		if sVarType == "table" then
			local tCached = ALookup[__Var]
			if tCached ~= nil then return tCached end
			
			if __Recursion > 0 then
				local tCopy = {}
				ALookup[__Var] = tCopy
				setmetatable(tCopy, getmetatable(__Var))
				
				local vKey, vValue
				for vKey, vValue in next, __Var, nil do
					rawset(tCopy, __copy(vKey, __Recursion - 1), __copy(vValue, __Recursion - 1))
				end			
				
				return tCopy
			else
				error("Recursion limit exceeded.", 2)
			end
		elseif sVarType == "userdata" or sVarType == "thread" then
			if ASuppressErrors then
				return nil
			end
			
			error("Uncopyable variable.", 2)
		else
			return __Var
		end
	end
	
	return __copy(AVariable, ARecursion)
end
-- Dump a value as a readable string and pass it to a sink function.
function stdlib.dump(AVariable, AOutput, ALookup, ARecursion, AIndentation)
	if AOutput == nil then AOutput = io.output() end
	if ALookup == nil then ALookup = {} end
	if ARecursion == nil then ARecursion = math.huge end
	if AIndentation == nil then AIndentation = 0 end
	
	stdlib.assertf("Lookup argument must be a table.", type(ALookup) == "table", 2)
	stdlib.assertf("Recursion argument must be a number.", type(ARecursion) == "number", 2)
	stdlib.assertf("Indentation argument must be a number.", type(AIndentation) == "number", 2)
	
	local function __dump(__Var, __Recursion, __Indent)
		local sVarType = type(__Var)
		if sVarType == "table" then
			local tCached = ALookup[__Var]
			if tCached ~= nil then
				if __Indent >= 0 then
					AOutput:write(string.rep("\t", __Indent + 1))
				end
				AOutput:write("[" .. tostring(__Var) .. "]")
				return		
			end
			ALookup[__Var] = true
			
			if __Recursion > 0 then
				if __Indent > 0 then
					AOutput:write(string.rep("\t", __Indent))
				end
				AOutput:write("{")
			
				local bFirst = true
			
				local vKey, vValue
				for vKey, vValue in next, __Var, nil do
					if not bFirst then
						AOutput:write(", ")
						if __Indent >= 0 then
							AOutput:write("\n")
						end					
					else
						if __Indent >= 0 then
							AOutput:write("\n")
						end				
						bFirst = false
					end
				
					local sKey
					local sKeyType = type(vKey)
					if sKeyType == "string" then
						sKey = string.gsub(vKey, "\n", "\\n")
						sKey = string.format("%q", sKey)
					else
						sKey = tostring(vKey)
					end
					
					local nNewIndent
					if __Indent >= 0 then
						nNewIndent = __Indent + 1
					else
						nNewIndent = -1
					end
					
					if __Indent >= 0 then
						AOutput:write(string.rep("\t", nNewIndent))
					end
					AOutput:write("[" .. sKey .. "]")
					AOutput:write(" = ")
					
					local sValueType = type(vValue)
					if sValueType == "table" then
						if __Indent >= 0 then
							AOutput:write("\n")
						end
					end
					
					__dump(vValue, __Recursion - 1, nNewIndent)
				end
				
				if __Indent >= 0 and not bFirst then
					AOutput:write("\n")
					AOutput:write(string.rep("\t", __Indent))
				end
				AOutput:write("}")
				if __Indent == 0 then
					AOutput:write("\n")
				end
			else
				AOutput:write("[recursion terminated]")
			end
		elseif sVarType == "string" then
			__Var = string.gsub(__Var, "\n", "\\n")
			__Var = string.format("%q", __Var)
			AOutput:write(__Var)
		else
			AOutput:write(tostring(__Var))
		end
	end
	
	__dump(AVariable, ARecursion, AIndentation)
end

-- Check if two iterator sequences are equal.
function stdlib.sequenceEqual(ALeftIt, ALeft, ALeftStart, ARightIt, ARight, ARightStart, AEquator)
	if AEquator == nil then AEquator = function (AL, AR) return AL == AR end end
	
	stdlib.assertf("Left iterator must be a function.", type(ALeftIt) == "function", 2)
	stdlib.assertf("Right iterator must be a function.", type(ARightIt) == "function", 2)
	
	local function __sequenceEqual(__LeftIdx, __RightIdx)	
		local vLeftIdx, vLeft = ALeftIt(ALeft, __LeftIdx)
		local vRightIdx, vRight = ARightIt(ARight, __RightIdx)
		
		if vLeftIdx == nil then
			if vRightIdx == nil then
				return true
			end
			
			return false
		elseif vRightIdx == nil then
			return false
		else
			if not AEquator(vLeft, vRight) then
				return false
			end
			
			return __sequenceEqual(vLeftIdx, vRightIdx)
		end
	end
	
	return __sequenceEqual(ALeftStart, ARightStart)
end

-- Check the suffix of a string.
function string.endsWith(AString, ASuffix, AIgnoreCase)
	stdlib.assertf("Input must be a string.", type(AString) == "string", 2)
	stdlib.assertf("Suffix must be a string.", type(ASuffix) == "string", 2)
	if AIgnoreCase == nil then AIgnoreCase = false end
	stdlib.assertf("Ignore case option must be a boolean.", type(AIgnoreCase) == "boolean", 2)
	
	if #ASuffix == 0 then
		return true
	end
	
	local sSuffix = string.sub(AString, -#ASuffix)
	if AIgnoreCase then
		sSuffix = string.lower(sSuffix)
		ASuffix = string.lower(ASuffix)
	end
	
	return sSuffix == ASuffix
end
-- Check the prefix of a string.
function string.startsWith(AString, APrefix, AIgnoreCase)
	stdlib.assertf("Input must be a string.", type(AString) == "string", 2)
	stdlib.assertf("Prefix must be a string.", type(APrefix) == "string", 2)
	if AIgnoreCase == nil then AIgnoreCase = false end
	stdlib.assertf("Ignore case option must be a boolean.", type(AIgnoreCase) == "boolean", 2)
	
	if #APrefix == 0 then
		return true
	end
	
	local sPrefix = string.sub(AString, 1, #APrefix)
	if AIgnoreCase then
		sPrefix = string.lower(sPrefix)
		APrefix = string.lower(APrefix)
	end
	
	return sPrefix == APrefix
end

-- Fast list structure.
stdlib.List = {}

stdlib.List.Properties =
{
	Count = function (self)
		return #self
	end,
	Items = function (self)
		return self.__FItems
	end,
	IsEmpty = function (self)
		return self.__FEnd < self.__FStart
	end
}
stdlib.List.Methods =
{
	PushLeft = function (self, AValue)
		self.__FStart = self.__FStart - 1
		self.__FItems[self.__FStart] = AValue
	end,
	PushRight = function (self, AValue)
		self.__FEnd = self.__FEnd + 1
		self.__FItems[self.__FEnd] = AValue
	end,
	PopLeft = function (self, ADelete)
		cerrorf("List is empty.", self.__FStart <= self.__FEnd, 2)
		if ADelete == nil then ADelete = true end
		
		local vValue = self[self.__FStart]
		
		if ADelete then
			self.__FItems[self.__FStart] = nil
		end
		
		self.__FStart = self.__FStart + 1		
		return vValue
	end,
	PopRight = function (self, ADelete)
		cerrorf("List is empty.", self.__FStart <= self.__FEnd, 2)
		if ADelete == nil then ADelete = true end
		
		local vValue = self[self.__FEnd]

		if ADelete then
			self.__FItems[self.__FEnd] = nil
		end
		
		self.__FEnd = self.__FEnd - 1
		return vValue
	end,

	SetBounds = function (self, AStart, AEnd)
		stdlib.assertf("Start argument must be a number.", type(AStart) == "number", 2)
		stdlib.assertf("End argument must be a number.", type(AEnd) == "number", 2)
		
		if AStart > AEnd then
			self:Clear()
		else
			self.__FStart = AStart
			self.__FEnd = AEnd
		end
	end,
	WithBounds = function (self, AStart, AEnd)
		local tList = stdlib.List.New(self.__FItems)
		tList:SetBounds(AStart, AEnd)
		return tList
	end,
	
	Insert = function (self, AIndex, AValue, AFowardOnly)
		if AFowardOnly == nil then AFowardOnly = false end
		stdlib.assertf("Index must be a number.", type(AIndex) == "number", 2)
		stdlib.assertf("Foward only option must be a boolean.", type(AFowardOnly) == "boolean", 2)
		
		if AIndex < 0 then AIndex = #self + AIndex + 1 end
		AIndex = self.__FStart + AIndex - 1
		
		if AIndex == self.__FStart - 1 then
			self:PushLeft(AValue)
		elseif AIndex == self.__FEnd + 1 then
			self:PushRight(AValue)
		elseif AIndex < self.__FStart or AIndex > self.__FEnd then
			errorf("Index %d is out of range [%d, %d].", AIndex, self.__FStart - 1, self.__FEnd + 1)
		else
			local nSplit = self.__FStart + math.floor((self.__FEnd - self.__FStart + 1) / 2)
			local I
			if AIndex < nSplit and (not AFowardOnly) then
				for I = self.__FStart - 1, AIndex, 1 do
					self.__FItems[I] = self.__FItems[I + 1]
				end
				self.__FStart = self.__FStart - 1
			else
				for I = self.__FEnd + 1, AIndex, -1 do
					self.__FItems[I] = self.__FItems[I - 1]
				end
				self.__FEnd = self.__FEnd + 1
			end
			
			self.__FItems[AIndex] = AValue
		end
	end,
	Remove = function (self, AIndex, AFowardOnly)
		if AFowardOnly == nil then AFowardOnly = false end
		stdlib.assertf("Index must be a number.", type(AIndex) == "number", 2)
		stdlib.assertf("Foward only option must be a boolean.", type(AFowardOnly) == "boolean", 2)
		
		if AIndex < 0 then AIndex = #self + AIndex + 1 end
		AIndex = self.__FStart + AIndex - 1
		
		if AIndex == self.__FStart then
			self:PopLeft(true)
		elseif AIndex == self.__FEnd then
			self:PopRight(true)
		elseif AIndex < self.__FStart or AIndex > self.__FEnd then
			errorf("Index %d is out of range [%d, %d].", AIndex, self.__FStart, self.__FEnd)
		else
			local nSplit = self.__FStart + math.floor((self.__FEnd - self.__FStart + 1) / 2)
			local I
			local vRemoved = self.__FItems[AIndex]
			if AIndex < nSplit and (not AFowardOnly) then
				for I = AIndex, self.__FStart + 1, -1 do
					self.__FItems[I] = self.__FItems[I - 1]
				end
				self.__FItems[self.__FStart] = nil
				self.__FStart = self.__FStart + 1
			else
				for I = AIndex, self.__FEnd - 1, 1 do
					self.__FItems[I] = self.__FItems[I + 1]
				end
				self.__FItems[self.__FEnd] = nil
				self.__FEnd = self.__FEnd - 1
			end
			
			return vRemoved
		end
	end,
	Clear = function (self)
		self.__FStart = 1
		self.__FEnd = 0
	end,

	Get = function (self, AIndex)
		stdlib.assertf("Index must be a number.", type(AIndex) == "number", 2)
		if AIndex < 0 then AIndex = #self + AIndex + 1 end
		AIndex = self.__FStart + AIndex - 1
		
		stdlib.assertf("Index %d out of range [%d, %d].", AIndex, 1, #self, AIndex >= 1 and AIndex <= #self, 2)
		
		return self.__FItems[AIndex]
	end,
	Set = function (self, AIndex, AValue)
		stdlib.assertf("Index must be a number.", type(AIndex) == "number", 2)
		if AIndex < 0 then AIndex = #self + AIndex + 1 end
		AIndex = self.__FStart + AIndex - 1
		
		stdlib.assertf("Index %d out of range [%d, %d].", AIndex, 1, #self, AIndex >= 1 and AIndex <= #self, 2)
		
		self.__FItems[AIndex] = AValue
	end
}

function stdlib.List.New(AItems)
	if AItems == nil then AItems = {} end
	
	stdlib.assertf("Items argument must be a table.", type(AItems) == "table", 2)

	local tList = {}
	tList.__FStart = 1
	tList.__FEnd = #AItems
	tList.__FItems = AItems
	
	setmetatable(tList, stdlib.List)	
	return tList
end
function stdlib.List.Iterator(AList, AIndex)
	if AList == nil then
		return nil
	end
	
	if AIndex == nil then
		if AList.__FEnd < AList.__FStart then
			return nil
		end
		
		return 1, AList.__FItems[AList.__FStart]
	else
		if AIndex >= #AList then
			return nil
		end
		
		return AIndex + 1, AList.__FItems[AList.__FStart + AIndex]
	end
end

function stdlib.List:__index(AKey)
	local fFunction
	
	if type(AKey) == "number" then	
		return self:Get(AKey)
	end
	
	fFunction = stdlib.List.Properties[AKey]
	if fFunction ~= nil then
		return fFunction(self)
	end
	
	fFunction = stdlib.List.Methods[AKey]
	if fFunction ~= nil then
		return fFunction
	end
	
	return nil
end
function stdlib.List:__newindex(AKey, AValue)
	if type(AKey) == "number" then
		self:Set(AKey, AValue)
		return
	end

	errorf('Mutation of "%q" prohibited.', AKey, 2)
end
function stdlib.List:__len()
	return math.max(self.__FEnd - self.__FStart + 1, 0)
end
function stdlib.List:__eq(AOther)
	if type(AOther) ~= "table" then
		return false
	elseif #AOther ~= #self then
		return false
	end
	
	local fOtherIt, _, vOtherStart = ipairs(AOther)
	if getmetatable(AOther) == stdlib.List then
		fOtherIt = stdlib.List.Iterator
		vOtherStart = nil
	end
	
	return stdlib.sequenceEqual(stdlib.List.Iterator, self, nil, fOtherIt, AOther, vOtherStart)
end

_G.printf		= stdlib.printf
_G.errorf 		= stdlib.errorf
_G.cerrorf		= stdlib.cerrorf

_G.assertf		= stdlib.assertf
_G.debugf		= stdlib.debugf

_G.readFile		= stdlib.readFile
_G.writeFile	= stdlib.writeFile

_G.copy			= stdlib.copy
_G.dump			= stdlib.dump

return stdlib