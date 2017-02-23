local stdlib	= require "stdlib"
local types		= require "types"

-- The streaming library namespace.
local streaming = {}

-- Abstract stream type.
streaming.Stream = Type("Stream", "abstract")

function streaming.Stream:read()
	error("Not supported.", 2)
end
function streaming.Stream:write()
	error("Not supported.", 2)
end
function streaming.Stream:seek()
	error("Not supported.", 2)
end
function streaming.Stream:close()
	error("Not supported.", 2)
end
function streaming.Stream:flush()
	error("Not supported.", 2)
end

streaming.Stream["Length.__get"] = function (self)
	error("Abstract error.", 2)
end

-- Abstract stream adapter type.
streaming.StreamAdapter = Type("StreamAdapter", streaming.Stream, "abstract")

function streaming.Stream:seek(...)
	return self.__FHandle:seek(...)
end
function streaming.Stream:close()
	self.__FHandle:close()
end
function streaming.Stream:flush()
	self.__FHandle:flush()
end

streaming.StreamAdapter["Handle.__get"] = function (self)
	return self.__FHandle
end

-- Memory buffer object.
streaming.Buffer = Type("Buffer", streaming.Stream)

function streaming.Buffer.New(AData, AMode, ACapacity)
	AData = defaultArg("AData", AData, "string", "")
	AMode = defaultArg("AMode", AMode, "string", "rw")
	ACapacity = defaultArg("ACapacity", ACapacity, "number", math.huge)
	
	if ACapacity < 0 then
		ACapacity = math.huge
	end
	
	local tMode = {}
	local tFields =
	{
		FData		= AData,
		FMode		= tMode,
		FCapacity	= ACapacity,
		FPointer	= 0
	}

	if AMode == "r" then
		tMode.Read = true
		tMode.Write = false
		tMode.Insert = false
	elseif AMode == "w" then
		tMode.Read = false
		tMode.Write = true
		tMode.Insert = false
	elseif AMode == "rw" then
		tMode.Read = true
		tMode.Write = true
		tMode.Insert = false
	elseif AMode == "wi" then
		tMode.Read = false
		tMode.Write = true
		tMode.Insert = true
	elseif AMode == "rwi" then
		tMode.Read = true
		tMode.Write = true
		tMode.Insert = true
	else
		errorf("Unknown buffer mode %q.", AMode, 2)
	end
	
	return New(streaming.Buffer, tFields)
end

function streaming.Buffer:read(AFilter)
	if not self.__FMode.Read then
		error("Buffer is not in readable mode.", 2)
	end
	AFilter = defaultArg("AFilter", AFilter, "string", "number", "l")
	
	local nPointer = self.__FPointer
	
	if type(AFilter) == "number" then
		if AFilter == 0 then
			return ""
		elseif AFilter < 0 then
			error("Number of bytes to read must be >= 0.", 2)
		end
		
		local sRead = string.sub(self.__FData, nPointer + 1, nPointer + AFilter)
		if sRead == "" then
			return nil
		else
			self.__FPointer = nPointer + #sRead
			return sRead
		end
	elseif AFilter == "l" then
		local sRead, sChar
		repeat
			sChar = string.sub(self.__FData, nPointer + 1, nPointer + 1)
			
			if sChar == "" or sChar == nil then
				break
			elseif sChar == "\n" then
				nPointer = nPointer + 1
				break
			else
				if sRead == nil then sRead = "" end
				nPointer = nPointer + 1
				sRead = sRead .. sChar
			end
		until false
		
		self.__FPointer = nPointer
		return sRead
	elseif AFilter == "a" then
		local sRead = string.sub(self.__FData, nPointer + 1)
		
		self.__FPointer = #self.__FData
		if sRead == "" then
			return nil
		else
			return sRead
		end
	else
		errorf("Unknown read filter mode %q.", AFilter, 2)
	end
end
function streaming.Buffer:write(AData)
	if not self.__FMode.Write then
		error("Buffer is not in writeable mode.", 2)
	end
	if AData == nil then
		return 0
	end
	checkArg("AData", AData, "string")
	
	local nPointer = self.__FPointer
	local nToWrite = #AData
	if self.__FMode.Insert then
		local nToWrite = math.max(0, math.min(self.__FCapacity - #self.__FData, nToWrite))
		
		if nToWrite == 0 then
			return 0
		end
		
		AData = string.sub(AData, 1, nToWrite)
		self.__FData = string.sub(self.__FData, 1, nPointer) .. AData .. string.sub(self.__FData, nPointer + 1)
		self.__FPointer = nPointer + nToWrite

		return nToWrite
	else
		local nToWrite = math.max(0, math.min(self.__FCapacity - nPointer, nToWrite))
		
		if nToWrite == 0 then
			return 0
		end
		
		AData = string.sub(AData, 1, nToWrite)
		self.__FData = string.sub(self.__FData, 1, nPointer) .. AData .. string.sub(self.__FData, nPointer + 1 + nToWrite)
		self.__FPointer = nPointer + nToWrite
		
		return nToWrite
	end
end
function streaming.Buffer:seek(AOrigin, AOffset)
	AOrigin = defaultArg("AOrigin", AOrigin, "string", "cur")
	AOffset = defaultArg("AOffset", AOffset, "number", 0)
	
	local nPointer = self.__FPointer
	
	if AOrigin == "set" then
		nPointer = AOffset
	elseif AOrigin == "cur" then
		nPointer = nPointer + AOffset
	elseif AOrigin == "end" then
		nPointer = #self.__FData + AOffset
	else
		errorf("Unknown seek origin %q.", AOrigin, 2)
	end
	
	if self.__FMode.Write and nPointer > #self.__FData then
		nPointer = math.min(nPointer, self.__FCapacity)
		
		local nFill = nPointer - #self.__FData
		if nFill > 0 then
			self.__FData = self.__FData .. string.rep(string.char(0x00), nFill)
		end
	end
	
	self.__FPointer = math.max(0, math.min(#self.__FData, nPointer))
	return nPointer
end
function streaming.Buffer:close() end
function streaming.Buffer:flush() end

function streaming.Buffer:Drop(ACount)
	defaultArg("ACount", ACount, "number", #self.__FData)
	ACount = math.min(ACount, #self.__FData)
	
	if ACount < 0 then
		error("Count must be >= 0.", 2)
	end
	
	local sDrop = string.sub(self.__FData, 1, ACount)
	self.__FData = string.sub(self.__FData, ACount + 1)
	self.__FPointer = math.max(0, self.__FPointer - ACount)
	return sDrop
end
function streaming.Buffer:Copy()
	return self.__FData
end

streaming.Buffer["self.__get"] = function (self, AIndex)
	if type(AIndex) == "number" then
		local sChar = string.sub(self.__FData, AIndex, AIndex)
		if sChar == "" then
			return nil
		else
			return sChar
		end
	elseif type(AIndex) == "string" then
		local sFrom, sTo = string.match(AIndex, "^([0-9]*)%-([0-9]*)$")
		
		if sFrom == nil then
			error("Invalid query.", 2)
		elseif sFrom == "" and sTo == "" then
			error("Invalid subsequence query.", 2)
		end
		
		local nFrom, nTo
		if sFrom == "" then nFrom = 1 else nFrom = tonumber(sFrom) end
		if sTo == "" then nTo = #self.__FData else nTo = tonumber(sTo) end
		
		local sSub = string.sub(self.__FData, nFrom, nTo)
		if sSub == "" then
			return nil
		else
			return sSub
		end
	end
	
	return nil
end

streaming.Buffer["Capacity.__get"] = function (self)
	return self.__FCapacity
end
streaming.Buffer["Length.__get"] = function (self)
	return #self.__FData
end

-- Adapter for reading byte streams.
streaming.ByteReader = Type("ByteReader", stdlib.StreamAdapter)

function streaming.ByteReader.New(AHandle, AEndianness)
	checkArg("AHandle", AHandle, "file", streaming.Buffer)
	AEndianness = defaultArg("AEndianness", AEndianness, "string", "le")

	if AEndianness ~= "le" and AEndianness ~= "be" then
		errorf("Unknown endianness %q.", AEndianness, 2)
	end	

	local tFields =
	{
		FHandle		= AHandle,
		FEndianness = AEndianness
	}
	
	return New(streaming.ByteReader, tFields)		
end

function streaming.ByteReader:read(ALength)
	if ALength == nil then ALength = 1 end
	stdlib.assertf("Length must be a number.", type(ALength) == "number", 2)

	self.__FHandle:read(ALength)
end

function streaming.ByteReader:ReadUInt(ALength)
	checkArg("ALength", ALength, "number")
	assertf("Length (%d) is not in range [1|4].", ALength, ALength >= 1 and ALength <= 4, 2)
	
	local sBytes 	= self.__FHandle:read(ALength)
	local nResult	= 0

	local I
	if self.__FEndianness == "le" then
		for I = 1, ALength do
			nResult = bit32.bor(nResult, bit32.lshift(string.byte(sBytes, I), (I - 1) * 8))
		end
	else
		for I = 1, ALength do
			nResult = bit32.bor(nResult, bit32.lshift(string.byte(sBytes, I), (ALength - I) * 8))
		end
	end
	
	return nResult
end
function streaming.ByteReader:ReadInt(ALength)
	local nUInt = self:ReadUInt(ALength)
	
	local nNegate = bit32.lshift(0x1, ALength * 8 - 1)
	if bit32.band(nUInt, nNegate) == nNegate then
		return bit32.bnot(nUInt) + 1
	end
	
	return nUInt
end

-- Adapter for writing byte streams.
streaming.ByteWriter = Type("ByteWriter", stdlib.StreamAdapter)

function streaming.ByteWriter.New(AHandle, AEndianness)
	checkArg("AHandle", AHandle, "file", streaming.Buffer)
	AEndianness = defaultArg("AEndianness", AEndianness, "string", "le")

	if AEndianness ~= "le" and AEndianness ~= "be" then
		errorf("Unknown endianness %q.", AEndianness, 2)
	end	

	local tFields =
	{
		FHandle		= AHandle,
		FEndianness = AEndianness
	}
	
	return New(streaming.ByteWriter, tFields)		
end

function streaming.ByteWriter:write(AByte)
	stdlib.assertf("Byte must be a number.", type(AByte) == "number", 2)
	stdlib.assertf("Byte must be in range.", AByte >= 0 and AByte <= 255, 2)

	self.__FHandle:write(string.char(AByte))
end

function streaming.ByteWriter:WriteUInt(ALength, AValue)
	checkArg("ALength", ALength, "number")
	checkArg("AValue", AValue, "number")
	assertf("Length (%d) is not in range [1|4].", ALength, ALength >= 1 and ALength <= 4, 2)
	
	local sBytes = ""

	local I
	if self.__FEndianness == "le" then
		for I = 1, ALength do
			sBytes = sBytes .. string.char(bit32.band(bit32.rshift(AValue, (I - 1) * 8), 0xFF))
		end
	else
		for I = 1, ALength do
			sBytes = sBytes .. string.char(bit32.band(bit32.rshift(AValue, (ALength - I) * 8), 0xFF))
		end
	end
	
	self.__FHandle:write(sBytes)
end
function streaming.ByteWriter:WriteInt(ALength, AValue)
	checkArg("AValue", AValue, "number")

	if AValue < 0 then
		AValue = bit32.bnot(AValue - 1)
	end
	
	self:WriteUInt(ALength, AValue)
end

-- Adapter for reading character streams.
streaming.TextReader = Type("TextReader", stdlib.StreamAdapter)

function streaming.TextReader.New(AHandle, ABufferSize, AEnableCounter)
	checkArg("AHandle", AHandle, "file", streaming.Buffer)
	ABufferSize = defaultArg("ABufferSize", ABufferSize, "number", 0)
	AEnableCounter = defaultArg("AEnableCounter", AEnableCounter, "boolean", false)
	
	local tFields =
	{
		FHandle	= AHandle,
	}
	
	if AEnableCounter then
		tFields.FCounter =
		{
			Line	= 1,
			Char	= 0
		}
	end
	
	if ABufferSize > 0 then
		tFields.FBuffer = streaming.Buffer.New(nil, "rw", ABufferSize)
	elseif ABufferSize ~= 0 then
		error("BufferSize must be >= 0.", 2)
	end
	
	return New(streaming.TextReader, tFields)		
end

function streaming.TextReader:Peek(...)
	local tArgs = {...}
	local nSkip, nCount = 0, 1
	
	if #tArgs == 1 then
		checkArg("ACount", tArgs[1], "number")
		nCount = tArgs[1]
	elseif #tArgs == 2 then
		checkArg("ASkip", tArgs[1], "number")
		checkArg("ACount", tArgs[2], "number")
		nSkip = tArgs[1]
		nCount = tArgs[2]
	elseif #tArgs ~= 0 then
		error("Too many arguments.", 2)
	end
	
	if nSkip < 0 then
		error("Skip must be >= 0.", 2)
	end
	if nCount < 0 then
		error("Count must be >= 0.", 2)
	end
	
	if nSkip + nCount == 0 then
		return ""
	end
	
	if self.__FBuffer then
		if nSkip + nCount > self.__FBuffer.Capacity then
			error("Exceeds buffer capacity.", 2)
		end
		self:PopulateBuffer()
		
		self.__FBuffer:seek("set", 0)
		local sPeek = self.__FBuffer:read(nSkip + nCount)
		
		if sPeek ~= nil then
			return string.sub(sPeek, nSkip + 1)
		else
			return nil
		end
	else
		local nPos = self.__FHandle:seek()
		local sRead = self.__FHandle:read(nSkip + nCount)
		
		if sRead ~= nil then
			self.__FHandle:seek("set", nPos)
			return string.sub(sRead, nSkip + 1)
		else
			return sRead
		end
	end
end
function streaming.TextReader:Pop(ACount)
	ACount = defaultArg("ACount", ACount, "number", 1)
	
	if ACount < 0 then
		error("Count must be >= 0.", 2)
	elseif ACount == 0 then
		return ""
	end
	
	local sRead
	if self.__FBuffer then
		if ACount > self.__FBuffer.Capacity then
			error("Exceeds buffer capacity.", 2)
		end
		self:PopulateBuffer()
		
		sRead = self.__FBuffer:Drop(ACount)
		if sRead == "" then
			return nil
		end
	else
		sRead = self.__FHandle:read(ACount)
		if sRead == nil then
			return nil
		end
	end
	
	if self.__FCounter then
		local tCounter = self.__FCounter
		
		local nLineBreak, nLast
		for nLineBreak in string.gmatch(sRead, "\n()") do
			tCounter.Line = tCounter.Line + 1
			nLast = nLineBreak
		end

		if nLast then
			tCounter.Char = #sRead - nLast
		else
			tCounter.Char = tCounter.Char + #sRead
		end
	end
	
	return sRead
end

function streaming.TextReader:read(AFilter)
	if AFilter == nil then AFilter = "l" end
	
	if AFilter == "l" then
		local sLine = ""
		repeat
			local sPop = self:Pop(1)
			if sPop == nil and sLine == "" then
				return nil
			elseif sPop == "\n" then			
				return sLine
			end
			
			sLine = sLine .. sPop
		until false
	elseif type(AFilter) == "number" then
		return self:Pop(AFilter)
	else
		error('Filter argument must be a number or "l".', 2)
	end
end
function streaming.Stream:seek(...)
	error("Not supported.", 2)
end

function streaming.TextReader:PopulateBuffer()
	if self.__FBuffer == nil then
		return
	end

	local nToRead = self.__FBuffer.Capacity - self.__FBuffer.Length
	self.__FBuffer:seek("end", 0)
	self.__FBuffer:write(self.__FHandle:read(nToRead))
end
function streaming.TextReader:ResetCounter(ALine, AChar)
	ALine = defaultArg("ALine", ALine, "number", 1)
	AChar = defaultArg("AChar", AChar, "number", 0)
end

function streaming.TextReader:GetLocation()	
	local nOffset = self.Offset
	local sLocation = string.format("At offset %d [0x%X]", nOffset, nOffset)
	
	if self.__FCounter then
		sLocation = sLocation .. string.format(", on line %d, at char %d", self.__FCounter.Line, self.__FCounter.Char)
	end
	
	return sLocation
end

streaming.TextReader["BufferSize.__get"] = function (self)
	if self.__FBuffer then
		return self.__FBuffer.Capacity
	else
		return 0
	end
end
streaming.TextReader["Offset.__get"] = function (self)
	local nPos = self.__FHandle:seek()
	
	if self.__FBuffer then
		return nPos - self.__FBuffer.Length
	else
		return nPos
	end
end
streaming.TextReader["Counter.__get"] = function (self)
	return self.__FCounter
end

-- Adapter for writing text streams.
streaming.TextWriter = Type("TextWriter", stdlib.StreamAdapter)

function streaming.TextWriter.New(AHandle)
	checkArg("AHandle", AHandle, "file", streaming.Buffer)
	
	local tFields =
	{
		FHandle		= AHandle,
		FIndent 	= {},
		FLineStart	= true
	}

	return New(streaming.TextWriter, tFields)
end

function streaming.TextWriter:PushIndent(AIndent)
	checkArg("AIndent", AIndent, "string")
	
	if not self.__FLineStart then
		self.__FHandle:write("\n")
		self.__FLineStart = true
	end

	table.insert(self.__FIndent, AIndent)
end
function streaming.TextWriter:PopIndent()
	local nCount = #self.__FIndent
	if nCount == 0 then
		return nil
	end
	
	if not self.__FLineStart then
		self.__FHandle:write("\n")
		self.__FLineStart = true
	end
	
	local sIndent = self.__FIndent[nCount]
	self.__FIndent[nCount] = nil
	return sIndent
end

function streaming.TextWriter:write(AString)
	self:Write(AString)
end
function streaming.Stream:seek(...)
	error("Not supported.", 2)
end

function streaming.TextWriter:Write(AString)
	checkArg("AString", AString, "string")
	local sIndent = table.concat(self.__FIndent)

	repeat
		if AString == "" then
			return
		end
		if self.__FLineStart then
			self.__FHandle:write(sIndent)
			self.__FLineStart = false
		end
	
		local nFind = string.find(AString, "\n")
		if nFind == nil then
			self.__FHandle:write(AString)
			return
		else
			local sLine = string.sub(AString, 1, nFind)
			AString = string.sub(AString, nFind + 1)
			
			self.__FHandle:write(sLine)
			self.__FLineStart = true
		end
	until false
end
function streaming.TextWriter:WriteLine(AString)
	checkArg("AString", AString, "string")
	
	self:Write(AString .. "\n")
end
function streaming.TextWriter:WriteFmt(AString, ...)
	checkArg("AString", AString, "string")
	
	self:Write(string.format(AString, ...))
end
function streaming.TextWriter:WriteLineFmt(AString, ...)
	checkArg("AString", AString, "string")
	
	self:Write(string.format(AString, ...) .. "\n")
end

streaming.TextWriter["AtLineStart.__get"] = function (self)
	return self.__FLineStart
end

-- Base class for token readers.
streaming.TokenReader = Type("TokenReader", "abstract")

function streaming.TokenReader:Next()
	error("Abstract error.", 2)
end
function streaming.TokenReader:All(AAcceptor)
	checkArg("AAcceptor", AAcceptor, "function")
	
	local tToken
	repeat
		tToken = {self:Next()}
		if #tToken == 0 then
			return
		end
		AAcceptor(table.unpack(tToken))
	until false
end

-- Base class for token writers.
streaming.TokenWriter = Type("TokenWriter", "abstract")

function streaming.TokenWriter:Emit(AToken)
	error("Abstract error.", 2)
end

return streaming