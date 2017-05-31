#    NimNode - Library for async programming and communication
#        (c) Copyright 2017 Wang Tong
#
#    See the file "LICENSE", included in this distribution, for
#    details about the copyright.

import unittest, node, os

suite "Timer dispatch":
  test "modify coin with base API":
    var coin = 0
    proc incCoin(): Future[void] =  
      var future = newFuture[void]("incCoin")
      var timer: Timer
      result = future
      timer = newTimer(100, proc () = 
        inc(coin)
        start(timer)
        if coin >= 2:
          clear(timer)
          complete(future), true)
      join(timer)
      start(timer)
    waitFor incCoin()  
    check coin == 2

  test "modify coin with setTimeout":
    var coin = 0
    proc incCoin(): Future[void] =  
      var future = newFuture[void]("incCoin")
      var n1, n2, n3, n4, n5, n6: Timer
      result = future
      n1 = setTimeout(0)   do (): check coin == 0; coin = 1
      n2 = setTimeout(100) do (): check coin == 1; coin = 2
      sleep(1000)
      n3 = setTimeout(100) do (): check coin == 5; coin = 3; clear(n4)
      n4 = setTimeout(100) do (): check coin == 3; echo "would'nt display"
      n5 = setTimeout(10)  do (): check coin == 2; coin = 5
      n6 = setTimeout(100) do (): check coin == 3; coin = 6
      discard setTimeout(100) do ():
        check coin == 6
        discard setTimeout(100) do (): 
          inc(coin)
          complete(future)
    waitFor incCoin()  
    check coin == 7
    
  test "modify coin with sleepAsync":
    var coin = 0
    proc incCoin() {.async.} =
      await sleepAsync(100)
      inc(coin)
    waitFor incCoin()
    check coin == 1

suite "Ticker dispatch":
  test "modify coin with callSoon":
    var coin = 0
    proc incCoin(): Future[void] =
      var future = newFuture[void]("incCoin")
      result = future
      callSoon() do ():
        inc(coin)
        complete(future)
      check coin == 0
    waitFor incCoin()
    check coin == 1

  test "modify coin with async nextTick":
    var coin = 0
    proc incCoin() {.async.} =
      await nextTick()
      inc(coin)
    waitFor incCoin()
    check coin == 1


