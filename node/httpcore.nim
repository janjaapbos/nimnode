#    NimNode - Library for async programming and communication
#        (c) Copyright 2017 Wang Tong
#
#    See the file "LICENSE", included in this distribution, for
#    details about the copyright.

## Base utilities for processing http operations.

import uv, error, strtabs, strutils, parseutils

when defined(nodeHeaderBufSize):
  const HeaderBufSize* = nodeHeaderBufSize ## Buffer size for reading http header.
else:
  const HeaderBufSize* = 1 * 1024          ## Buffer size for reading http header.

type
  LinePhase = enum
    lpNormal, lpCRLF

  Line* = object
    err*: ref NodeError
    base*: string
    length: int
    parse: LinePhase
    ok*: bool

proc clear*(line: var Line) = 
  line.err = nil
  line.base = ""
  line.length = 0
  line.parse = lpNormal
  line.ok = false

proc read*(line: var Line, buf: pointer, size: int): int =
  result = 0
  while result < size:
    let c = cast[cstring](buf)[result]
    case line.parse
    of lpNormal:
      if c == '\r':
        line.parse = lpCRLF
      else:
        add(line.base, c)
        inc(line.length)
        if line.length >= HeaderBufSize:
          line.err = newNodeError(END_OVERFLOW)
          return
    of lpCRLF:
      if c == '\L':
        line.ok = true
        inc(result)
        break
      else:
        line.err = newNodeError(END_CRLF)
        return
    inc(result)

iterator splitProtocol*(line: string): string =
  let n = len(line)
  var word = newStringOfCap(n)
  var j = 0
  for i in 0..n-1:
    var c = line[i]
    case j
    of 0:
      if c == ' ':
        if len(word) > 0:
          yield word
          setLen(word, 0)
          inc(j)
      else:
        add(word, c)
    of 1:
      if c == ' ':
        if len(word) > 0:
          yield word
          setLen(word, 0)
          inc(j)
      else:
        add(word, c)
    else:
      add(word, c)
  yield word

proc parseRequestProtocol*(line: string; reqMethod, url: var string; 
                           protocol: var tuple[orig: string, major, minor: int]) =
  var i = 0
  for word in splitProtocol(line):
    case i
    of 0:
      reqMethod = word
    of 1:
      url = word
    of 2:
      protocol.orig = word
      var j = skipIgnoreCase(word, "Http/")
      if j != 5:
        raise newException(ValueError, "Invalid Request Protocol")
      inc(j, parseInt(word, protocol.major, j))
      inc(j)
      discard parseInt(word, protocol.minor, j)
    else:
      raise newException(ValueError, "Invalid Request Protocol")
    inc(i)
  if i < 3:
    raise newException(ValueError, "Invalid Request Protocol")

proc parseResponseProtocol*(line: string; statusCode: var int; statusMessage: var string; 
                            protocol: var tuple[orig: string, major, minor: int]) =
  var i = 0
  for word in splitProtocol(line):
    case i
    of 0:
      protocol.orig = word
      var j = skipIgnoreCase(word, "Http/")
      if j != 5:
        raise newException(ValueError, "Invalid Request Protocol")
      inc(j, parseInt(word, protocol.major, j))
      inc(j)
      discard parseInt(word, protocol.minor, j)
    of 1:
      statusCode = parseInt(word)
    of 2:
      statusMessage = word
    else:
      raise newException(ValueError, "Invalid Request Protocol")
    inc(i)
  if i < 3:
    raise newException(ValueError, "Invalid Request Protocol")

proc parseHeader*(line: string, headers: StringTableRef) =
  let n = len(line)
  var i = 0
  while i < n:
    if line[i] == ':':
      break
    inc(i)
  if i == 0 or i >= n:
    raise newException(ValueError, "Invalid Request Header")
  var key = newString(i)
  copyMem(cstring(key), cstring(line), i * sizeof(char))
  if i < n-2:
    var value = newString(n - 2 - i)
    copyMem(cstring(value), 
            cast[pointer](cast[ByteAddress](cstring(line)) + (i + 2) * sizeof(char)),
            (n - 2 - i) * sizeof(char))
    headers[key] = value
  else:
    headers[key] = ""

proc parseChunkSize*(line: string): int = 
  result = 0
  var i = 0
  while true:
    case line[i]
    of '0'..'9':
      result = result shl 4 or (ord(line[i]) - ord('0'))
    of 'a'..'f':
      result = result shl 4 or (ord(line[i]) - ord('a') + 10)
    of 'A'..'F':
      result = result shl 4 or (ord(line[i]) - ord('A') + 10)
    of '\0':
      break
    of ';':
      # http://tools.ietf.org/html/rfc2616#section-3.6.1
      # We don't care about chunk-extensions.
      break
    else:
      raise newException(ValueError, "Invalid Chunk Encoded")
    inc(i)