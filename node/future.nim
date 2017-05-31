#    NimNode - Library for async programming and communication
#        (c) Copyright 2017 Wang Tong
#
#    See the file "LICENSE", included in this distribution, for
#    details about the copyright.

## This module is basically equivalent to the Future of standard library, in
## addition to a few special procedures.

import uv, timers, strutils
include future.asyncfutures, future.asyncmacro

template async2*(body: untyped): untyped =
  block:
    proc lmbf() {.async.} = body
    asyncCheck lmbf()

