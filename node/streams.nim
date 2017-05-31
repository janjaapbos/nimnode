#    NimNode - Library for async programming and communication
#        (c) Copyright 2017 Wang Tong
#
#    See the file "LICENSE", included in this distribution, for
#    details about the copyright.
#
# ``UvStream`` 的使用情况是这样的：
#
#   * call ``init()`` 初始化，流会在内部创建文件描述符以及分配必需的内存空间
#
#   * call ``readStart()`` 启动流的流动模式，这个时候流运行在 ``statFlowing`` 模式。流在这个
#     模式下，开始监听数据的到来。当数据到来的时候，会有以下情况：
#
#       * 有效的可读数据，触发 ``onData()`` 
#       * 数据到达末尾，触发 ``onEnd()``
#
#   * 在 ``statFlowing`` 模式期间可以随时调用 ``readStop()`` 停止流的流动
#
#   * call ``write()`` 写入数据
#
#   * 当写入数据时，如果过于频繁并且数据量过大，外部的缓冲区会在内部缓存。检查当前的 ``needDrain=true``，
#     当缓存完全清空的时候，触发``onDrain()`` 这表示继续写入是安全的 (``needDrain=false``)
#
#   * call ``endSoon()`` 关闭写入端，当所有数据写入完成，触发 ``onFinish()``
#
#   * 期间的任何操作倒置内部错误时，自动关闭流触发 ``onClose()``
#
#   * call ``closeSoon()`` 立刻停止读端，关闭写端，当当所有数据写入完成，触发 ``onFinish()``，然后关闭流
#     触发 ``onClose()``
#
#   * call ``close()`` 立刻关闭流，释放所有的文件描述符，如果当前有数据等待写入则丢弃，触发 ``onClose()``

## This module implements a duplex (readable, writable) stream based on libuv. A
## stream is an abstract interface which provides reading and writing for 
## non-blocking I/O.

import uv, error, timers

when defined(nodeBufSize):
  const BufSize* = nodeBufSize
else:
  const BufSize* = 4 * 1024

when defined(nodeWriteLimit):
  const WriteLimit* = nodeWriteLimit
else:
  const WriteLimit* = 16 * 1024 

type
  ChunkBuffer* = object ## A chunk data.
    base*: pointer
    size*: int

proc `$`*(x: ChunkBuffer): string =
  ## Returns ``x`` converted to a string. 
  result = newString(x.size)
  if x.size > 0:
    copyMem(cstring(result), x.base, x.size)

iterator items*(x: ChunkBuffer): char =
  ## Iterates over each character of ``x``.
  for i in 0..<x.size:
    yield cast[ptr char](cast[ByteAddress](x.base) + i * sizeof(char))[]

type
  BaseStream* = concept s
    stream.onClose is proc (err: ref NodeError) {.closure, gcsafe.}
    stream.close()

  ReadableStream* = concept s of BaseStream
    stream.onData is proc (data: ChunkBuffer) {.closure, gcsafe.}
    stream.onEnd is proc () {.closure, gcsafe.}
    stream.flowing() is bool
    stream.readStart() 
    stream.readStop()
    
  WritableStream* = concept s of BaseStream
    stream.onDrain is proc () {.closure, gcsafe.}
    stream.onFinish is proc () {.closure, gcsafe.}
    stream.needDrain() is bool
    stream.write(buf: pointer, size: int, cb: proc (err: ref NodeError) {.closure, gcsafe.})
    stream.write(buf: string, cb: proc (err: ref NodeError) {.closure, gcsafe.})
    stream.writeEnd()

  DuplexStream* = concept s of ReadableStream, WritableStream
    stream.closeSoon()

type
  StreamStat = enum
    statFlowing, statReadStop, statEnd, statEndEmitted, statNeedDrain, 
    statWriting, statCorked, statShutdown, statFinish, statClosing, statClosed  

  StreamReader = object
    buf: array[BufSize, char]
    bufLen: int

  StreamWriter = object
    req: Write
    buf: seq[tuple[base: pointer, length: int, cb: proc (err: ref NodeError) {.closure, gcsafe.}]]
    bufLen: int
    bufBaseSize: int
    bufCurrSize: int
    cb: proc (err: ref NodeError) {.closure, gcsafe.}

  FDStream* = ref object of RootObj ## Abstraction of duplex stream created via file descriptor. 
    onData: proc (data: ChunkBuffer) {.closure, gcsafe.}
    onEnd: proc () {.closure, gcsafe.}
    onDrain: proc () {.closure, gcsafe.}
    onFinish: proc () {.closure, gcsafe.}
    onClose: proc (err: ref NodeError) {.closure, gcsafe.}
    reader: StreamReader
    writer: StreamWriter
    shutdown: Shutdown
    stats: set[StreamStat]
    handle*: Stream
    error*: ref NodeError

template stats: untyped = stream.stats
template reader: untyped = stream.reader
template writer: untyped = stream.writer  

template cond(exp: untyped): untyped =
  let err = exp
  if err < 0:
    stream.error = newNodeError(err)
    stream.close()
    return

proc `onClose=`*(stream: FDStream, cb: proc (err: ref NodeError) {.closure, gcsafe.}) =
  stream.onClose = cb

proc `onData=`*(stream: FDStream, cb: proc (data: ChunkBuffer) {.closure, gcsafe.}) =
  stream.onData = cb

proc `onEnd=`*(stream: FDStream, cb: proc () {.closure, gcsafe.}) =
  stream.onEnd = cb

proc `onDrain=`*(stream: FDStream, cb: proc () {.closure, gcsafe.}) =
  stream.onDrain = cb

proc `onFinish=`*(stream: FDStream, cb: proc () {.closure, gcsafe.}) =
  stream.onFinish = cb

proc closeCb(handle: ptr Handle) {.cdecl.} =
  var stream = cast[FDStream](handle.data)
  GC_unref(stream)
  if writer.cb != nil:
    writer.cb(stream.error)
  for i in 0..<writer.bufLen:
    let cb = writer.buf[i].cb
    if cb != nil:
      cb(stream.error)
  reader.bufLen = 0
  writer.buf.setLen(0)
  writer.bufLen = 0
  writer.bufBaseSize = 0
  writer.bufCurrSize = 0
  writer.cb = nil
  if stream.onClose != nil:
    stream.onClose(stream.error)
  elif stream.error != nil:
    raise stream.error

proc close*(stream: FDStream) =
  ## Close ``stream``. Handles that wrap file descriptors are closed immediately.
  if statClosed notin stats:
    stats.excl(statClosing)
    stats.incl(statClosed)
    close(cast[ptr Handle](addr(stream.handle)), closeCb)

proc shutdownCb(req: ptr Shutdown, status: cint) {.cdecl.} =
  template stats: untyped = stats
  let stream = cast[FDStream](cast[ptr Stream](req.handle).data) 
  stats.incl(statFinish)
  cond status
  if stream.onFinish != nil:
    stream.onFinish() 
  if statClosing in stats:
    stream.close()

proc clearWriter(stream: FDStream): cint {.gcsafe.}

proc writeEnd*(stream: FDStream) = 
  ## Shutdown the outgoing (write) side and waits for all pending write requests to complete.
  if statClosed notin stats and statShutdown notin stats: 
    stats.incl(statShutdown)
    if statCorked in stats:
      stats.excl(statCorked)
    if statWriting notin stats and writer.bufLen > 0:
      stats.incl(statWriting)
      cond stream.clearWriter()
    cond shutdown(addr(stream.shutdown), 
                  cast[ptr Stream](addr(stream.handle)), shutdownCb)

proc closeSoon*(stream: FDStream) = 
  ## Shutdown the outgoing (write) side. After all pending write requests 
  ## are completed, close the ``stream``.
  if statClosed notin stats and statClosing notin stats:
    stats.incl(statClosing)
    if statShutdown notin stats:
      stream.writeEnd()
    elif statFinish notin stats:
      discard
    else:
      stream.close()

proc writeAfterEnd(stream: FDStream, cb: proc (err: ref NodeError) {.closure, gcsafe.}) =
  stream.error = newNodeError(END_WREND)
  if cb != nil:
    cb(stream.error)
  stream.close()

proc writeCb(req: ptr Write, status: cint) {.cdecl.} =
  let stream = cast[FDStream](cast[ptr Stream](req.handle).data) 
  cond status
  writer.bufBaseSize.dec(writer.bufCurrSize)
  writer.bufCurrSize = 0
  if statNeedDrain in stats and writer.bufBaseSize < WriteLimit:
    stats.excl(statNeedDrain)
    if stream.onDrain != nil:
      stream.onDrain()
  if writer.cb != nil:
    writer.cb(nil)
  writer.cb = nil
  if writer.bufLen > 0 and statCorked notin stats:
    cond stream.clearWriter()
  else:
    stats.excl(statWriting)

proc doWrite(stream: FDStream, buf: pointer, size: int, 
             cb: proc (err: ref NodeError) {.closure, gcsafe.}): cint =
  var buffer = Buffer()
  buffer.base = buf
  buffer.length = size
  writer.req = Write()
  writer.cb = cb
  writer.bufCurrSize = size
  return write(addr(writer.req), cast[ptr Stream](addr(stream.handle)), 
               addr(buffer), 1, writeCb)

proc doWrite(stream: FDStream): cint =
  assert writer.bufLen > 0
  let n = writer.bufLen
  var bufCurrSize = 0
  var bufs = cast[ptr Buffer](alloc(n * sizeof(Buffer)))
  var cbs = newSeqOfCap[proc (err: ref NodeError) {.closure, gcsafe.}](n)
  for i in 0..<n:
    var buf = cast[ptr Buffer](cast[ByteAddress](bufs) + i * sizeof(Buffer))
    buf.base = writer.buf[i].base
    buf.length = writer.buf[i].length
    cbs.add(writer.buf[i].cb)
    bufCurrSize.inc(writer.buf[i].length)
  writer.req = Write()
  let err = write(addr(writer.req), cast[ptr Stream](addr(stream.handle)), 
                  bufs, cuint(n), writeCb)
  if err < 0:
    bufs.dealloc()
    return err
  GC_ref(cbs)
  writer.cb = proc (err: ref NodeError) =
    for cb in cbs:
      if cb != nil:
        cb(err)
    GC_unref(cbs)
    bufs.dealloc()
  writer.bufCurrSize = bufCurrSize

proc clearWriter(stream: FDStream): cint =
  assert writer.bufLen > 0
  if writer.bufLen == 1:
    let err = stream.doWrite(writer.buf[0].base, writer.buf[0].length, writer.buf[0].cb)
    if err < 0:
      return err
  else:
    let err = stream.doWrite()
    if err < 0:
      return err
  writer.buf.setLen(0)
  writer.bufLen = 0

proc write*(stream: FDStream, buf: pointer, size: int, 
            cb: proc (err: ref NodeError) {.closure, gcsafe.} = nil) =
  stats.incl(statNeedDrain)
  if statShutdown in stats or statClosed in stats:
    stream.writeAfterEnd(cb)
    return
  if statWriting in stats or statCorked in stats: 
    writer.buf.add((base: buf, length: size, cb: cb))
    writer.bufLen.inc(1)
    writer.bufBaseSize.inc(size)   
    if writer.bufBaseSize < WriteLimit:
      stats.excl(statNeedDrain)
  else:
    assert writer.bufLen == 0
    stats.incl(statWriting)
    cond stream.doWrite(buf, size, cb)
    writer.bufBaseSize.inc(size)   
    if writer.bufBaseSize < WriteLimit:
      stats.excl(statNeedDrain)

proc write*(stream: FDStream, buf: string, 
            cb: proc (err: ref NodeError) {.closure, gcsafe.} = nil) =
  ## Writes ``buf`` to the stream ``stream``. 
  GC_ref(buf)
  stream.write(cstring(buf), len(buf)) do (err: ref NodeError):
    GC_unref(buf)
    if cb != nil:
      cb(err)

proc cork*(stream: FDStream) =
  if statCorked notin stats:
    stats.incl(statCorked)

proc uncork*(stream: FDStream) = 
  if statCorked in stats:
    stats.excl(statCorked)
    if writer.bufLen > 0 and statWriting notin stats:
      stats.incl(statWriting)
      cond stream.clearWriter()

proc needDrain*(stream: FDStream): bool =
  result = statNeedDrain in stats

proc allocCb(handle: ptr Handle, size: csize, buf: ptr Buffer) {.cdecl.} =
  let stream = cast[FDStream](handle.data)
  buf.base = cast[pointer](cast[ByteAddress](reader.buf[0].addr) + reader.bufLen * sizeof(char))
  buf.length = BufSize - reader.bufLen

proc readCb(handle: ptr Stream, nread: cssize, buf: ptr Buffer) {.cdecl.} =
  if nread == 0: # EINTR or EAGAIN or EWOULDBLOCK
    return
  let stream = cast[FDStream](handle.data)
  if nread < 0:
    if cint(nread) == uv.EOF:
      stats.incl(statEnd)
      if statFlowing in stats:
        stats.incl(statEndEmitted)
        if stream.onEnd != nil:
          stream.onEnd()
      ##############################
      # if not stream.allowHalfOpen:
      #   if statFinish in stats:
      #     stream.close()
      #   elif statWriteEnd in stats:
      #     discard
      #   else:
      #     stream.endSoon()
      # else:
      #   if statFinish in stats:
      #     stream.close()
      ####################
    else:
      stream.error = newNodeError(cint(nread))
      stream.close()
  else:
    if statFlowing in stats:
      if stream.onData != nil:
        stream.onData(ChunkBuffer(base: addr(reader.buf[0]), size: int(cint(nread))))
    else:
      inc(reader.bufLen, int(cint(nread)))
      if reader.bufLen >= BufSize:
        let err = readStop(cast[ptr Stream](addr(stream.handle)))
        if err < 0:
          stream.error = newNodeError(err)
          stream.close()
        else:
          stats.incl(statReadStop)    

proc readResume*(stream: FDStream) =
  if statFlowing notin stats:
    stats.incl(statFlowing)
    if statClosed notin stats:
      if statEnd in stats:
        if statEndEmitted notin stats:
          stats.incl(statEndEmitted)
          if stream.onEnd != nil:
            stream.onEnd()
      else:
        if statReadStop in stats:
          cond readStart(cast[ptr Stream](addr(stream.handle)), allocCb, readCb)
          stats.excl(statReadStop)
        if reader.bufLen > 0:
          let bufLen = reader.bufLen
          reader.bufLen = 0  
          stream.onData(ChunkBuffer(base: addr(stream.reader.buf[0]), size: bufLen))

proc readPause*(stream: FDStream) =
  if statFlowing in stats:
    stats.excl(statFlowing)

proc flowing*(stream: FDStream): bool =
  result = statFlowing in stats

type
  TcpConnection* = ref object of FdStream ## Abstraction of TCP connection. 
    onConnect*: proc () {.closure, gcsafe.}

proc `onConnect=`*(conn: TcpConnection, cb: proc () {.closure, gcsafe.}) =
  conn.onConnect = cb

proc newTcpConnection*(): TcpConnection =
  ## Create a new TCP connection.
  new(result)
  GC_ref(result) 
  result.writer.buf = @[]
  result.stats = {statReadStop}
  let err = init(getDefaultLoop(), cast[ptr Tcp](addr(result.handle)))
  if err < 0:
    result.error = newNodeError(err)
    result.close()  
  else:
    result.handle.data = cast[pointer](result)

