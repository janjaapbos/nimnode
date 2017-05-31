#    NimNode - Library for async programming and communication
#        (c) Copyright 2017 Wang Tong
#
#    See the file "LICENSE", included in this distribution, for
#    details about the copyright.

## Provides infrastructure for building flexible and efficient HTTP server.

import uv, error, timers, streams, net, httpcore, strtabs, strutils

type
  HttpServer* = ref object ## Abstraction of HTTP Server.
    onClientError: proc (conn: TcpConnection, err: ref NodeError) {.closure, gcsafe.}
    onRequest: proc (req: ServerRequest) {.closure, gcsafe.}
    onUpgrade: proc (conn: TcpConnection, req: ServerRequest, 
                     firstPacket: ChunkBuffer) {.closure, gcsafe.}
    onClose: proc (err: ref NodeError) {.closure, gcsafe.}
    base: TcpServer

  ReadPhase = enum
    rpInit, rpProtocol, rpHeaders, rpCheck, rpUpgrade, rpRequest

  RequestStat = enum
    statActive, statFlowing, statEnd, statEndEmitted, statReadChunkedTransferEncoding, statReadKeepAlive,
    statSentHead, statWriteChunk, statWriteChunkedTransferEncoding, statWriteKeepAlive,
    statNeedDrain, statWriteEnd, statFinish, statClosed

  HttpReader = object
    reqMethod: string
    url: string
    protocol: tuple[orig: string, major, minor: int]
    headers: StringTableRef
    line: Line
    chunk: pointer
    chunkLen: int
    chunkPos: int
    cache: array[BufSize, char]
    cacheLen: int
    contentLength: int
    phase: ReadPhase

  HttpWriter = object
    statusCode: int
    headers: StringTableRef

  ServerRequest* = ref object ## Abstraction of HTTP request on server.
    onData: proc (data: ChunkBuffer) {.closure, gcsafe.}
    onEnd: proc () {.closure, gcsafe.}
    onDrain: proc () {.closure, gcsafe.}
    onFinish: proc () {.closure, gcsafe.}
    onClose: proc (err: ref NodeError) {.closure, gcsafe.}
    server: HttpServer
    conn: TcpConnection
    reader: HttpReader
    writer: HttpWriter
    error: ref NodeError
    stats: set[RequestStat]

template offchar(x: pointer, i: int): pointer =
  cast[pointer](cast[ByteAddress](x) + i * sizeof(char))

proc close(req: ServerRequest) =
  template stats: untyped = req.stats
  template conn: untyped = req.conn  
  if statClosed notin stats:
    stats.incl(statClosed)
    conn.closeSoon()

proc getChunk(req: ServerRequest): ChunkBuffer = 
  template reader: untyped = req.reader
  if reader.chunkPos < reader.chunkLen:
    result.base = offchar(reader.chunk, reader.chunkPos)
    result.size = reader.chunkLen - reader.chunkPos
  else:
    result.base = nil
    result.size = 0

proc pickChunk(req: ServerRequest, buf: pointer, size: int) =
  req.reader.chunk = buf
  req.reader.chunkLen = size
  req.reader.chunkPos = 0

proc readOnInit(req: ServerRequest) =
  template stats: untyped = req.stats
  template reader: untyped = req.reader
  template writer: untyped = req.writer
  reader.reqMethod = ""
  reader.url = ""
  reader.protocol.orig = ""
  reader.protocol.major = 0
  reader.protocol.minor = 0 
  clear(reader.headers, modeCaseInsensitive) 
  clear(reader.line)
  reader.phase = rpInit
  reader.contentLength = 0
  writer.statusCode = 200
  writer.headers = nil
  stats = {statFlowing}

proc readOnProtocol(req: ServerRequest): bool =
  template reader: untyped = req.reader
  template line: untyped = reader.line
  while reader.chunkPos < reader.chunkLen:
    assert line.ok == false
    assert line.err == nil
    let n = read(line, offchar(reader.chunk, reader.chunkPos), reader.chunkLen - reader.chunkPos)
    inc(reader.chunkPos, n)
    if line.err != nil:
      raise line.err 
    elif line.ok:
      parseRequestProtocol(line.base, reader.reqMethod, reader.url, reader.protocol)
      clear(line) 
      return true
    else:
      assert reader.chunkPos == reader.chunkLen
  return false

proc readOnHeaders(req: ServerRequest): bool =
  template reader: untyped = req.reader
  template line: untyped = reader.line
  while reader.chunkPos < reader.chunkLen:
    assert line.ok == false
    assert line.err == nil
    let n = read(line, offchar(reader.chunk, reader.chunkPos), reader.chunkLen - reader.chunkPos)
    inc(reader.chunkPos, n)
    if line.err != nil:
      raise line.err #close(conn, line.err) # TODO: close bad readeruest 400
    elif line.ok:
      if line.base == "":
        clear(line)
        return true
      try:
        parseHeader(line.base, reader.headers)
        clear(line) 
      except:
        clear(line)
    else:
      assert reader.chunkPos == reader.chunkLen
  return false

proc readOnCheck(req: ServerRequest) =       
  template stats: untyped = req.stats
  template reader: untyped = req.reader
  try:
    reader.contentLength = parseInt(reader.headers.getOrDefault("Content-Length"))
    if reader.contentLength < 0:
      reader.contentLength = 0
  except:
    reader.contentLength = 0
  if reader.headers.getOrDefault("Transfer-Encoding") == "chunked":
    stats.incl(statReadChunkedTransferEncoding)
  if (reader.protocol.major == 1 and reader.protocol.minor == 1 and
      normalize(reader.headers.getOrDefault("Connection")) != "close") or
     (reader.protocol.major == 1 and reader.protocol.minor == 0 and
      normalize(reader.headers.getOrDefault("Connection")) == "keep-alive"):
    stats.incl(statReadKeepAlive)

proc readOnRequest(req: ServerRequest): bool =
  template reader: untyped = req.reader
  if reader.contentLength == 0 and req.onEnd != nil:
    req.onEnd()
  else:
    let remained = reader.chunkLen - reader.chunkPos
    if remained == 0:
      return false
    elif remained < reader.contentLength:
      if req.onData != nil:
        req.onData(ChunkBuffer(base: offchar(reader.chunk, reader.chunkPos), size: remained))
      inc(reader.chunkPos, remained)
      dec(reader.contentLength, remained)
      return false
    else:
      if req.onData != nil:
        req.onData(ChunkBuffer(base: offchar(reader.chunk, reader.chunkPos), size: reader.contentLength))
      inc(reader.chunkPos, reader.contentLength)
      dec(reader.contentLength, reader.contentLength)
      if req.onEnd != nil:
        req.onEnd()
  return true

proc parse(req: ServerRequest) =
  template server: untyped = req.server
  template stats: untyped = req.stats  
  template reader: untyped = req.reader
  template conn: untyped = req.conn
  while true:
    case reader.phase
    of rpInit:
      req.readOnInit()
      reader.phase = rpProtocol
    of rpProtocol:
      try:
        if req.readOnProtocol():
          reader.phase = rpHeaders
        else:
          return
      except:
        conn.write("HTTP/1.1 400 bad request\r\L")
        req.error = newNodeError(END_BADREQ)
        req.close()
        return
    of rpHeaders:
      try:
        if req.readOnHeaders():
          reader.phase = rpCheck
        else:
          return
      except:
        conn.write("HTTP/1.1 400 bad request\r\L")
        req.error = newNodeError(END_BADREQ)
        req.close()
        return
    of rpCheck:
      req.readOnCheck()
      if reader.headers.getOrDefault("Connection") == "Upgrade":
        reader.phase = rpUpgrade
        continue
      if reader.headers.hasKey("Expect"):
        if "100-continue" in reader.headers["Expect"]: 
          # if server.on100Continue != nil:
          #   server.on100Continue(req, writer)
          # else:
          conn.write("HTTP/1.1 100 Continue\r\L")
        else: 
          conn.write("HTTP/1.1 417 Expectation Failed\r\L")
      if server.onRequest != nil:
        server.onRequest(req)
        reader.phase = rpRequest
        stats.incl(statActive)
        continue
      req.close()
      return
    of rpUpgrade:
      if server.onUpgrade == nil:
        req.close()  
      else:
        conn.onData = nil
        conn.onEnd = nil
        conn.onDrain = nil
        conn.onFinish = nil
        conn.onClose = nil
        server.onUpgrade(conn, req, req.getChunk())
      return
    of rpRequest:
      # echo "...", statFlowing notin stats
      if statFlowing notin stats:
        return
      if not req.readOnRequest():
        return
      if statReadKeepAlive in stats and statWriteKeepAlive in stats:
        reader.phase = rpInit
        if statFlowing notin stats:
          return
      else:
        req.close()
        return

proc readPause*(req: ServerRequest) =
  template stats: untyped = req.stats
  template reader: untyped = req.reader
  template conn: untyped = req.conn  
  if statFlowing in stats:
    stats.excl(statFlowing)
    if statClosed notin stats and statActive in stats:
      let n = reader.chunkLen - reader.chunkPos
      if n > 0:
        copyMem(reader.cache[0].addr, reader.chunk, n)
        reader.cacheLen = n
      conn.readPause()

proc readResume*(req: ServerREquest) =
  template stats: untyped = req.stats
  template reader: untyped = req.reader
  template conn: untyped = req.conn    
  if statFlowing notin stats:
    stats.incl(statFlowing)
    if statClosed notin stats and statActive in stats:
      if reader.cacheLen > 0:
        req.pickChunk(reader.cache[0].addr, reader.cacheLen)
        req.parse()
        reader.cacheLen = 0
      conn.readResume()

proc flowing*(req: ServerRequest): bool =
  result = statFlowing in req.stats

proc protocol*(req: ServerRequest): tuple[orig: string, major, minor: int] =
  result = req.reader.protocol

proc reqMethod*(req: ServerRequest): string =
  result = req.reader.reqMethod

proc url*(req: ServerRequest): string =
  result = req.reader.url

proc headers*(req: ServerRequest): StringTableRef = 
  result = req.reader.headers

proc writeHead*(req: ServerRequest, statusCode: int, headers: StringTableRef = nil) =
  ## Sends a writerponse header to the request.  
  template stats: untyped = req.stats
  template writer: untyped = req.writer
  if statWriteEnd in stats or statClosed in stats:
    req.error = newNodeError(END_WREND)
    req.close()
    return
  stats.excl(statSentHead)
  writer.statusCode = statusCode
  writer.headers = headers
  if writer.headers.getOrDefault("Transfer-Encoding") == "chunked":
    stats.incl(statWriteChunkedTransferEncoding)
  else:
    stats.excl(statWriteChunkedTransferEncoding)
  if writer.headers.getOrDefault("Connection") != "close":
    stats.incl(statWriteKeepAlive)
  else:
    stats.excl(statWriteKeepAlive)

proc genHeadStr(req: ServerRequest): string =
  template writer: untyped = req.writer
  result = "HTTP/1.1 " & $writer.statusCode & " OK\r\L"
  if writer.headers != nil:
    for key,value in pairs(writer.headers):
      add(result, key & ": " & value & "\r\L")
  else:
    add(result, "Content-Length: 0\r\L")
  add(result, "\r\L")

proc write*(req: ServerRequest, buf: pointer, size: int,  
            cb: proc (err: ref NodeError) {.closure, gcsafe.} = nil) =
  ## Sends a chunk of the writerponse body. 
  template stats: untyped = req.stats
  template conn: untyped = req.conn
  if statWriteEnd in stats or statClosed in stats:
    req.error = newNodeError(END_WREND)
    req.close()
    return
  conn.cork()
  if statSentHead notin stats:
    stats.incl(statSentHead)
    conn.write(req.genHeadStr())
  conn.write(buf, size, cb)
  conn.uncork()
  if conn.needDrain:
    stats.incl(statNeedDrain)

proc write*(req: ServerRequest, buf: string,  
            cb: proc (err: ref NodeError) {.closure, gcsafe.} = nil) =
  ## Sends a chunk of the writerponse body. 
  GC_ref(buf)
  req.write(cstring(buf), len(buf)) do (err: ref NodeError):
    GC_unref(buf)
    if cb != nil:
      cb(err)

proc writeEnd*(req: ServerRequest) =
  ## Signals to the server that all of the writerponse headers and body have been 
  ## sent; that server should consider this message complete. The method must be 
  ## called on each writerponse.
  template stats: untyped = req.stats
  template conn: untyped = req.conn
  if statWriteEnd in stats or statClosed in stats:
    return  
  if statSentHead notin stats:
    stats.incl(statSentHead)
    conn.write(req.genHeadStr())  
  stats.incl(statWriteEnd)
  callSoon() do ():
    if req.onFinish != nil:
      req.onFinish()

proc newServerRequest(server: HttpServer, conn: TcpConnection): ServerRequest =
  template stats: untyped = req.stats
  template reader: untyped = req.reader
  new(result)
  var req = result
  req.server = server
  req.conn = conn
  req.stats = {}
  reader.phase = rpInit
  reader.headers = newStringTable(modeCaseInsensitive)
  conn.onClose = proc (err: ref NodeError) =
    if statClosed notin stats:
      stats.incl(statClosed)
    # if statActive in stats:
    #    stats.excl(statActive)
    if req.onClose != nil:  
      if req.error != nil: 
        req.onClose(req.error)
      else:
        req.onClose(err)
  conn.onData = proc (data: ChunkBuffer) = 
    req.pickChunk(data.base, data.size)
    req.parse()
  conn.onEnd = proc () = 
    if statClosed notin stats and statActive in stats:
      conn.write("HTTP/1.1 400 bad request\r\L")
      req.error = newNodeError(END_BADREQ)
      req.close()
    else:
      req.close()
  conn.onDrain = proc () = 
    if statClosed notin stats and statActive in stats:
      stats.excl(statNeedDrain)
      if req.onDrain != nil:
        req.onDrain()

proc newHttpServer*(maxConnections = 1024): HttpServer =
  ## Create a new HTTP Server.
  new(result)
  var server = result
  server.base = newTcpServer(maxConnections)
  server.base.onClose = proc (err: ref NodeError) = 
    if server.onClose == nil:
      raise err
    server.onClose(err)
  server.base.onConnection = proc (conn: TcpConnection) =
    newServerRequest(server, conn).readResume()

proc close*(server: HttpServer) =
  ## Close `server` to close the file descriptors and release internal writerources. 
  server.base.close()

proc serve*(server: HttpServer, port: Port, hostname = "127.0.0.1", 
            backlog = 511, domain = Domain.AF_INET) =
  ## Start the process of listening for incoming TCP connections on the specified 
  ## ``hostname`` and ``port``. 
  ##
  ## ``backlog`` specifies the length of the queue for pending connections. When the 
  ## queue fills, new clients attempting to connect fail with ECONNREFUSED until the 
  ## server calls accept to accept a connection from the queue.
  server.base.serve(port, hostname, backlog, domain)

proc `onRequest=`*(server: HttpServer, cb: proc (req: ServerRequest) {.closure, gcsafe.}) =
  server.onRequest = cb