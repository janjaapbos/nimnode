#    NimNode - Library for async programming and communication
#        (c) Copyright 2017 Wang Tong
#
#    See the file "LICENSE", included in this distribution, for
#    details about the copyright.

## Provides infrastructure for building flexible and efficient HTTP client.

import uv, error, timers, streams, net, httpcore

type
  ClientRequest* = ref object ## Abstraction of HTTP request on client.
    onResponse*: proc (res: ClientResponse) {.closure, gcsafe.}
    onNeedDrain*: proc () {.closure, gcsafe.}
    onDrain*: proc () {.closure, gcsafe.}
    onClose*: proc (err: ref NodeError) {.closure, gcsafe.}

  ClientResponse* = ref object ## Abstraction of HTTP response on client.
    onData*: proc (data: ChunkBuffer) {.closure, gcsafe.}
    onEnd*: proc () {.closure, gcsafe.}
    onClose*: proc (err: ref NodeError) {.closure, gcsafe.}