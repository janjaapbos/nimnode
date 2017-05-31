#    NimNode - Library for async programming and communication
#        (c) Copyright 2017 Wang Tong
#
#    See the file "LICENSE", included in this distribution, for
#    details about the copyright.

import unittest, node, strtabs

suite "HTTP request":
  test "construct a base HTTP server and client":
    proc consServer() =
      var server = newHttpServer(1_024_000)
      serve(server, Port(10000))
      server.onRequest = proc (req: ServerRequest) =
        writeHead(req, 200, newStringTable({
          "Content-Length": "11"
        }))
        write(req, "hello world")
        endSoon(req)       

    proc consClient() = 
      discard  

    # consServer()
    # runLoop()

 



