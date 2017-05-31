#    NimNode - Library for async programming and communication
#        (c) Copyright 2017 Wang Tong
#
#    See the file "LICENSE", included in this distribution, for
#    details about the copyright.

import unittest, node

suite "TCP server and client":
  test "construct a base TCP server and client":
    proc consServer() =
      var server = newTcpServer()
      var coin = 0
      server.serve(Port(10000), "localhost")
      server.onConnection = proc (conn: TcpConnection) =
        var message = ""
  
        conn.onData = proc (data: ChunkBuffer) =
          message.add($data)

        conn.onEnd = proc () =
          check coin == 0
          inc(coin)
          conn.write("recved " & message)
          conn.closeSoon()

        conn.onFinish = proc () =  
          check coin == 1
          inc(coin)

        conn.onClose = proc (err: ref NodeError) =
          if err != nil:
            echo err.msg
          check coin == 2
          inc(coin)
          server.close()

      server.onClose = proc (err: ref NodeError) =
        check coin == 3
        echo "       >>> server closed, coin=", $coin

    proc consClient() =
      var conn = connect(Port(10000), "localhost")
      var message = ""
      var coin = 0

      conn.onConnect = proc () =
        check coin == 0
        inc(coin)
        conn.write("hello world")
        conn.writeEnd()

      conn.onData = proc (data: ChunkBuffer) =
        for c in data:
          message.add(c)

      conn.onEnd = proc () =
        check message == "recved hello world"
        check coin == 2
        inc(coin)
        conn.closeSoon()

      conn.onFinish = proc () =  
        check coin == 1
        inc(coin)

      conn.onClose = proc (err: ref NodeError) =
        check coin == 3
        echo "       >>> client closed, coin=", $coin

    consServer()
    consClient()
    runLoop()



