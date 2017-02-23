local stdlib		= require "stdlib"
local types			= require "types"
local streaming		= require "streaming"

-- The JSON library namespace.
local json = {}

json.NULL = {}
setmetatable(json.NULL, {__newindex = function () error("Cannot modify value.", 2) end, __tostring = function () return "json.NULL" end})

-- A token reader for parsing JSON text.
json.JsonTokenReader = Type("JsonTokenReader", streaming.TokenReader)

function json.JsonTokenReader.New(ATextReader)
	checkArg("ATextReader", ATextReader, streaming.TextReader)
	
	return New(json.JsonTokenReader,
	{
		FInput	= ATextReader
	})
end

function json.JsonTokenReader:Next()
	local sPop = self.__FInput:Pop(1)
	
	if sPop == nil then
		return nil
	elseif sPop == ":" then
		return "assignment"
	elseif sPop == "," then
		return "separator"
	elseif sPop == "{" then
		return "begin", "object"
	elseif sPop == "}" then
		return "end", "object"
	elseif sPop == "[" then
		return "begin", "array"
	elseif sPop == "]" then
		return "end", "array"
	elseif sPop == "t" then
		local sPeek = self.__FInput:Peek(3)
		if sPeek == "rue" then
			self.__FInput:Pop(3)
			return "boolean", true
		end
		
		error('Expected "rue" after "t".')
	elseif sPop == "f" then
		local sPeek = self.__FInput:Peek(4)
		if sPeek == "alse" then
			self.__FInput:Pop(4)
			return "boolean", false
		end
		
		error('Expected "alse" after "f".')
	elseif sPop == "n" then
		local sPeek = self.__FInput:Peek(3)
		if sPeek == "ull" then
			self.__FInput:Pop(3)
			return "null"
		end
		
		error('Expected "ull" after "n".')
	elseif sPop == '"' then
		local sString = ""
		repeat
			local sNext = self.__FInput:Pop(1)
			if sNext == nil then
				error("Unfinished string.")
			elseif sNext == '"' then
				break
			elseif sNext == "\"" then
				local sEscape = self.__FInput:Pop(1)
				
				if sEscape == "x" then
					local sHex = self.__FInput:Pop(2)
					if sHex == nil or sHex ~= 2 then
						error("Unfinished hexadecimal escape sequence.")
					end
					
					local nByte = tonumber(sHex, 16)
					if nByte == nil then
						errorf('Invalid hexadecimal numeral "%s".', sHex)
					end
					
					sString = sString .. string.char(nByte)
				elseif sEscape == "r" then
					sString = sString .. "\r"
				elseif sEscape == "n" then
					sString = sString .. "\n"
				elseif sEscape == "t" then
					sString = sString .. "\t"
				elseif sEscape == "\"" then
					sString = sString .. "\""
				elseif string.match(sEscape, "[0-9]") then
					local sDecimal = sEscape
					repeat
						local sPeek = self.__FInput:Peek(1)
						if sPeek == nil then
							break
						elseif string.match(sPeek, "[0-9]") then
							sDecimal = sDecimal .. self.__FInput:Pop(1)
						else
							break
						end
					until #sDecimal == 3
					
					sString = sString .. string.char(tonumber(sDecimal))
				else
					errorf('Unsupported escape sequence "%s"', sEscape)
				end
			else
				sString = sString .. sNext
			end
		until false
		
		return "string", sString
	elseif sPop == "+" or sPop == "-" or sPop == "." or string.match(sPop, "[0-9]") ~= nil then
		local sNumeral = sPop
		local bDot = sPop == "."
		local bExp = false
		local bExpSign = false
		
		repeat
			local sPeek = self.__FInput:Peek(1)
			if sPeek == nil then
				break
			elseif string.match(sPeek, "[0-9]") ~= nil then
				sNumeral = sNumeral .. self.__FInput:Pop(1)
			elseif sPeek == "." then
				if bDot then
					error("Only one decimal point allowed.")
				end
				bDot = true
				sNumeral = sNumeral .. self.__FInput:Pop(1)
			elseif sPeek == "e" or sPeek == "E" then
				if bExp then
					error("Only one exponent allowed.")
				end
				bExp = true
				sNumeral = sNumeral .. self.__FInput:Pop(1)
			elseif sPeek == "+" or sPeek == "-" then
				if not bExp or bExpSign then
					error("Misplaced sign.")
				end
				bExpSign = true
				sNumeral = sNumeral .. self.__FInput:Pop(1)
			else
				break
			end
		until false
		
		local nDecimal = tonumber(sNumeral)
		if nDecimal == nil then
			error("Invalid numeral.")
		end
		
		return "number", nDecimal
	elseif string.match(sPop, "%s") ~= nil then
		return "whitespace", sPop
	else
		errorf('Unexpected symbol "%s".', sPop)
	end
end

-- A token writer for creating JSON text.
json.JsonTokenWriter = Type("JsonTokenWriter", streaming.TokenReader)

function json.JsonTokenWriter.New(ATextWriter, AIndent)
	checkArg("ATextWriter", ATextWriter, streaming.TextWriter)
	AIndent = defaultArg("AIndent", AIndent, "boolean", true)
	ACondense = defaultArg("ACondense", ACondense, "boolean", true)
	
	return New(json.JsonTokenWriter,
	{
		FOutput		= ATextWriter,
		FIndent		= AIndent,
	})
end

function json.JsonTokenWriter:Put(AString, ANewLine)
	self.__FOutput:Write(AString)

	if ANewLine then
		if self.__FIndent then
			self.__FOutput:Write("\n")
		else
			self.__FOutput:Write(" ")
		end
	end
end
function json.JsonTokenWriter:Emit(AClass, AData)
	if AClass == "begin" then
		if AData == "object" then
			self:Put("{", true)
		elseif AData == "array" then
			self:Put("[", true)
		end
		
		if self.__FIndent then
			self.__FOutput:PushIndent("\t")
		end
	elseif AClass == "end" then	
		if self.__FIndent then
			self.__FOutput:PopIndent()
		end
	
		if AData == "object" then			
			self:Put("}", false)
		elseif AData == "array" then
			self:Put("]", false)
		end
	elseif AClass == "assignment" then
		self:Put(": ", false)
	elseif AClass == "separator" then
		self:Put(",", true)
	elseif AClass == "null" then
		self:Put("null", false)
	elseif AClass == "string" then
		self:Put(stdlib.escape(AData), false)
	elseif AClass == "boolean" then
		if AData then
			self:Put("true", false)
		else
			self:Put("false", false)
		end
	elseif AClass == "number" then
		self:Put(string.format("%g", AData), false)
	end
end

-- Static (de-/)serialization functions.
function json.Serialize(ATable, ATokenWriter, AClassifier, AAllowNumericKeys)
	checkArg("ATable", ATable, "table")
	checkArg("ATokenWriter", ATokenWriter, json.JsonTokenWriter)
	AClassifier = defaultArg("AClassifier", AClassifier, "function", function (ATable)
		if next(ATable) == nil then
			return "array"
		elseif #ATable ~= 0 then
			return "array"
		else
			return "object"
		end
	end)
	AAllowNumericKeys = defaultArg("AAllowNumericKeys", AAllowNumericKeys, "boolean", false)
	
	local tLookup = {}
	
	local function serialize(AItem)	
		local sType = type(AItem)
		if sType == "table" then
			if tLookup[AItem] ~= nil then
				error("Circular reference detected.", 2)
			end
			tLookup[AItem] = true
		
			local sClass = AClassifier(AItem)
			if sClass == "array" then
				local I = 1	
				ATokenWriter:Emit("begin", "array")
				local bFirst = true
				while AItem[I] ~= nil do
					if not bFirst then
						ATokenWriter:Emit("separator")
					end
					bFirst = false
					
					serialize(AItem[I])
					I = I + 1
				end
				ATokenWriter:Emit("end", "array")
			elseif sClass == "object" then
				ATokenWriter:Emit("begin", "object")
				local bFirst = true
				for vKey, vValue in next, AItem, nil do
					local sKeyType = type(vKey)
					if sKeyType == "string" or (sKeyType == "number" and AAllowNumericKeys) then
						if not bFirst then
							ATokenWriter:Emit("separator")
						end
						bFirst = false
					
						serialize(vKey)
						ATokenWriter:Emit("assignment")
						serialize(vValue)
					end
				end
				ATokenWriter:Emit("end", "object")
			end
		elseif sType == "string" then
			ATokenWriter:Emit("string", AItem)
		elseif sType == "boolean" then
			ATokenWriter:Emit("boolean", AItem)
		elseif sType == "number" then
			ATokenWriter:Emit("number", AItem)
		end
	end
	
	serialize(ATable)
end
function json.Deserialize(ATokenReader, ADropNull, AAllowNumericKeys)
	checkArg("ATokenReader", ATokenReader, json.JsonTokenReader)
	ADropNull = defaultArg("ADropNull", ADropNull, "boolean", true)
	AAllowNumericKeys = defaultArg("AAllowNumericKeys", AAllowNumericKeys, "boolean", false)
	
	local tResult = {}
	local State = {}
	
	function State.pull()
		repeat
			local tToken = {ATokenReader:Next()}
		
			if #tToken == 0 then
				return nil
			elseif tToken[1] ~= "whitespace" then
				return table.unpack(tToken)
			end
		until false
	end
	function State.deserialize_object(AObject)
		local bNeedSep = false
	
		repeat
			local sClass, vData = State.pull()		
			if sClass == nil then
				error("Expected token.", 2)
			elseif sClass == "end" and vData == "object" then
				return
			elseif sClass == "separator" then
				if not bNeedSep then
					error("Unepected separator.", 2)
				end
				
				bNeedSep = false
			elseif sClass == "string" or sClass == "number" then
				if bNeedSep then
					error("Missing separator.", 2)
				end		
				if sClass == "number" and not AAllowNumericKeys then
					error("Numeric keys are not allowed.", 2)
				end
				
				local vKey = vData		
				if State.pull() ~= "assignment" then
					error("Expected assignment.", 2)
				end
				
				local vValue
				sClass, vData = State.pull()	
				if sClass == "begin" then
					vValue = {}
					
					if vData == "array" then
						State.deserialize_array(vValue)
					elseif vData == "object" then
						State.deserialize_object(vValue)
					end
				elseif sClass == "string" or sClass == "number" or sClass == "boolean" then
					vValue = vData
				elseif sClass == "null" then
					if not ADropNull then
						vValue = json.NULL
					end
				else
					local sData
					if vData == nil then
						sData = ""
					else
						sData = tostring(vData)
					end
					
					errorf("Unexpected token: %s(%s).", sClass, sData, 2)
				end
				
				AObject[vKey] = vValue
				
				bNeedSep = true
			else
				local sData
				if vData == nil then
					sData = ""
				else
					sData = tostring(vData)
				end
				
				errorf("Unepected token: %s(%s).", sClass, sData, 2)
			end
		until false
	end
	function State.deserialize_array(AArray)
		local I = 1
		local bNeedSep = false
		
		repeat
			local sClass, vData = State.pull()
			if sClass == nil then
				error("Expected token.", 2)
			elseif sClass == "end" and vData == "array" then
				return
			elseif sClass == "separator" then
				if not bNeedSep then
					error("Unepected separator.", 2)
				end
				
				bNeedSep = false
			elseif sClass == "string" or sClass == "number" or sClass == "boolean" then
				if bNeedSep then
					error("Missing separator.", 2)
				end
			
				AArray[I] = vData
				I = I + 1
				
				bNeedSep = true
			elseif sClass == "null" then
				if bNeedSep then
					error("Missing separator.", 2)
				end
			
				if not ADropNull then
					AArray[I] = json.NULL
					I = I + 1
				end
				
				bNeedSep = true
			elseif sClass == "begin" then
				if bNeedSep then
					error("Missing separator.", 2)
				end
			
				AArray[I] = {}
				
				if vData == "array" then
					State.deserialize_array(AArray[I])
				elseif vData == "object" then
					State.deserialize_object(AArray[I])
				end
				
				I = I + 1
				
				bNeedSep = true
			else
				local sData
				if vData == nil then
					sData = ""
				else
					sData = tostring(vData)
				end
				
				errorf("Unexpected token: %s(%s).", sClass, sData, 2)
			end
		until false
	end

	local sClass, vData = State.pull()
	if sClass == "number" or sClass == "string" or sClass == "boolean" then
		return vData
	elseif sClass == "null" then
		return nil
	elseif sClass == "begin" then
		local tResult = {}
		if vData == "array" then
			State.deserialize_array(tResult)
		elseif vData == "object" then
			State.deserialize_object(tResult)
		end
		
		return tResult
	else
		local sData
		if vData == nil then
			sData = ""
		else
			sData = tostring(vData)
		end
		
		errorf("Unexpected token: %s(%s).", sClass, sData, 2)
	end
end

-- Quick (de-/)serialization shortcuts.
function json.Store(AFileName, ATable, ...)
	checkArg("AFileName", AFileName, "string")
	
	local hFile, sError = io.open(AFileName, "w")
	if hFile == nil then
		errorf('Error opening file "%q": %s', AFileName, sError, 2)
	end
	
	local twWriter = streaming.TextWriter.New(hFile)
	local jtwWriter = json.JsonTokenWriter.New(twWriter)
	json.Serialize(ATable, jtwWriter, ...)
	
	hFile:close()
end
function json.Load(AFileName, ...)
	checkArg("AFileName", AFileName, "string")
	
	local hFile, sError = io.open(AFileName, "r")
	if hFile == nil then
		errorf('Error opening file "%q": %s', AFileName, sError, 2)
	end
	
	local trReader = streaming.TextReader.New(hFile)
	local jtrReader = json.JsonTokenReader.New(trReader)
	local vDeserialize = json.Deserialize(jtrReader, ...)
	
	hFile:close()
	return vDeserialize
end

return json