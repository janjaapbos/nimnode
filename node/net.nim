#    NimNode - Library for async programming and communication
#        (c) Copyright 2017 Wang Tong
#
#    See the file "LICENSE", included in this distribution, for
#    details about the copyright.

## Provides an asynchronous network wrapper. It contains functions for creating 
## both servers and clients (called streams). 

import uv, error, timers, streams, nativesockets

type
  Port* = distinct uint16 ## Port type.

  Domain* = enum
    ## specifies the protocol family of the created socket. Other domains than
    ## those that are listed here are unsupported.
    AF_UNIX,             ## for local socket (using a file). Unsupported on Windows.
    AF_INET = 2,         ## for network protocol IPv4 or
    AF_INET6 = 23        ## for network protocol IPv6.

  KeepAliveDelay* = distinct cuint

  TcpServer* = ref object ## Abstraction of TCP server.
    onConnection: proc (conn: TcpConnection) {.closure, gcsafe.}
    onClose: proc (err: ref NodeError) {.closure, gcsafe.}
    handle: Tcp
    maxConnections: int
    connections: int
    error: ref NodeError
    closed: bool

proc `onConnection=`*(server: TcpServer, cb: proc (conn: TcpConnection) {.closure, gcsafe.}) =
  server.onConnection = cb

proc `onClose=`*(server: TcpServer, cb: proc (err: ref NodeError) {.closure, gcsafe.}) =
  server.onClose = cb

proc closeServerCb(handle: ptr Handle) {.cdecl.} =
  var server = cast[TcpServer](handle.data) 
  GC_unref(server)
  if server.onClose != nil:
    server.onClose(server.error)
  elif server.error != nil:
    raise server.error 

proc close*(server: TcpServer) =
  ## Close `server` to close the file descriptors and release internal resources. 
  if not server.closed:
    server.closed = true
    close(cast[ptr Handle](addr(server.handle)), closeServerCb)

proc newTcpServer*(maxConnections = 1024): TcpServer =
  ## Create a new TCP server.
  new(result)
  GC_ref(result)
  result.closed = false
  result.maxConnections = maxConnections
  let err = init(getDefaultLoop(), cast[ptr Tcp](addr(result.handle)))
  if err < 0:
    result.error = newNodeError(err)
    result.close()
  else:
    result.handle.data = cast[pointer](result)   

proc bindAddr(server: TcpServer, port: Port, hostname = "127.0.0.1", domain = AF_INET) =
  template condFree(exp: untyped): untyped =
    let err = exp
    if err < 0:
      uv.freeAddrInfo(req.addrInfo)
      server.error = newNodeError(err)
      server.close()
      return
  var req: GetAddrInfo
  var hints: uv.AddrInfo
  hints.ai_family = cint(domain)
  hints.ai_socktype = 0
  hints.ai_protocol = 0
  condFree getAddrInfo(getDefaultLoop(), addr(req), nil, hostname, $(int(port)), addr(hints))
  condFree bindAddr(addr(server.handle), req.addrInfo.ai_addr, cuint(0))
  uv.freeAddrInfo(req.addrInfo)

proc connectionCb(handle: ptr Stream, status: cint) {.cdecl.} =
  let server = cast[TcpServer](handle.data)
  if status < 0 or server.maxConnections <= server.connections:
    discard
  else:
    var conn = newTcpConnection()
    let err = accept(cast[ptr Stream](addr(server.handle)), cast[ptr Stream](addr(conn.handle)))
    if err < 0:
      conn.error = newNodeError(err)
      conn.close()
    else:
      if server.onConnection != nil:
        server.onConnection(conn)
        conn.readResume()
        server.connections.inc(1)

proc serve*(server: TcpServer, port: Port, hostname = "127.0.0.1", backlog = 511, domain = AF_INET) =
  ## Start the process of listening for incoming TCP connections on the specified 
  ## ``hostname`` and ``port``. 
  ##
  ## ``backlog`` specifies the length of the queue for pending connections. When the 
  ## queue fills, new clients attempting to connect fail with ECONNREFUSED until the 
  ## server calls accept to accept a connection from the queue.
  server.bindAddr(port, hostname, domain)
  let err = listen(cast[ptr Stream](addr(server.handle)), cint(backlog), connectionCb)
  if err < 0:
    server.error = newNodeError(err)
    server.close()

proc connectCb(req: ptr Connect, status: cint) {.cdecl.} =
  let conn = cast[TcpConnection](req.data)
  dealloc(req)
  if status < 0:
    conn.error = newNodeError(status)
    conn.close()
  elif conn.onConnect != nil:
    conn.onConnect()
    conn.readResume()

proc connect*(port: Port, hostname = "127.0.0.1", domain = AF_INET): TcpConnection =
  ## Establishs an IPv4 or IPv6 TCP connection and returns a fresh ``TcpConnection``.
  template condFree(exp: untyped): untyped =
    let err = exp
    if err < 0:
      uv.freeAddrInfo(addrReq.addrInfo)
      dealloc(connectReqPtr)
      conn.error = newNodeError(err)
      conn.close()
      return
  result = newTcpConnection()
  let conn = result
  var connectReqPtr = cast[ptr Connect](alloc0(sizeof(Connect)))
  var addrReq: GetAddrInfo
  var hints: uv.AddrInfo
  hints.ai_family = cint(domain)
  hints.ai_socktype = 0
  hints.ai_protocol = 0
  condFree getAddrInfo(getDefaultLoop(), addr(addrReq), nil, 
                       hostname, $(int(port)), addr(hints))
  connectReqPtr.data = cast[pointer](conn)
  condFree connect(connectReqPtr, cast[ptr Tcp](addr(conn.handle)),
                   addrReq.addrInfo.ai_addr, connectCb)
  uv.freeAddrInfo(addrReq.addrInfo)  
  