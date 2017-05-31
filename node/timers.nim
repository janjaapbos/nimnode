#    NimNode - Library for async programming and communication
#        (c) Copyright 2017 Wang Tong
#
#    See the file "LICENSE", included in this distribution, for
#    details about the copyright.

## This module implements a timer dispatcher and a ticker dispatcher. A timer 
## delays an operation after some milliseconds. A ticker delays an operation to 
## the next iteration.
##
## ..code-block::markdown
##
##   newTimer() -> join() -> start() -> stop() -> clear()
##              -> join() -> ...
##
##   setTimeout() -> clear()

# TODO: implement the Timer(List Node)

import uv, error, tables, times, lists, math

type
  TimerEntity* = object ## Timer object.
    delay: int # milliseconds
    finishAt: float # seconds
    callback: proc()
    active: bool
    reusable: bool
    joined: bool

  Timer* = DoublyLinkedNode[TimerEntity] ## Timer object.

  TimerQueue* = ref object ## Timer queue for one delay.
    handle: uv.Timer
    entities: DoublyLinkedList[TimerEntity]
    delay: int # milliseconds
    length: int
    running: bool
    closed: bool

  TimerDispatcher* = ref object # Dispatcher for timers.
    timers: Table[int, TimerQueue]

  TickerDispatcher* = ref object # Dispatcher for tickers.
    handle: Idle
    started: bool
    entities: seq[proc()]

proc contains[T](L: DoublyLinkedList[T], node: DoublyLinkedNode[T]): bool =
  for n in L.nodes():
    if n == node:
      return true
  return false

proc newTimerDispatcher*(): TimerDispatcher =
  ## Creates new dispatcher for timeout tasks.
  new(result)
  GC_ref(result)
  result.timers = initTable[int, TimerQueue]()

var gTimerDispatcher{.threadvar.}: TimerDispatcher
proc getGTimerDispatcher*(): TimerDispatcher =
  ## Returns the global dispatcher of timeout tasks.
  if gTimerDispatcher == nil:
    gTimerDispatcher = newTimerDispatcher()
  return gTimerDispatcher

proc init(tq: TimerQueue, delay: int) =
  GC_ref(tq)
  tq.delay = delay
  tq.length = 0
  tq.running = false
  tq.closed = false
  discard init(getDefaultLoop(), addr(tq.handle))
  tq.handle.data = cast[pointer](tq)

proc closeTQCb(handle: ptr Handle) {.cdecl.} =
  let tq = cast[TimerQueue](handle.data)
  GC_unref(tq)

proc close(tq: TimerQueue) =
  if not tq.closed:
    let gDisp = getGTimerDispatcher()
    tq.running = false
    tq.closed = true
    gDisp.timers.del(tq.delay)
    close(cast[ptr Handle](addr(tq.handle)), closeTQCb)

proc start(tq: TimerQueue, delay: int) {.gcsafe.}

proc startTQCb(handle: ptr uv.Timer) {.cdecl.} =
  let now = epochTime()
  var tq = cast[TimerQueue](handle.data)
  tq.running = false
  for node in tq.entities.nodes():
    if node.value.active:
      if node.value.finishAt <= now:
        let callback = node.value.callback
        node.value.active = false
        if not node.value.reusable:
          tq.entities.remove(node)
          dec(tq.length)
          node.value.joined = false
        callback()
      else:
        var timeRemaining = (node.value.finishAt - epochTime()) * 1000
        if timeRemaining < 0:
          timeRemaining = 0
        tq.start(toInt(ceil(timeRemaining)))
        return
  assert tq.length >= 0
  if tq.length == 0: # no callback required
    tq.close()

proc start(tq: TimerQueue, delay: int) =
  discard start(addr(tq.handle), startTQCb, uint64(delay), 0)
  tq.running = true

proc newTimer*(delay: int, cb: proc() {.closure,gcsafe.}, reusable = false): Timer =
  ## Creates a new timer. ``cb`` will be executed after ``delay`` 
  ## milliseconds. ``reusable`` pointed out whether this node could be used again.
  result = Timer(
    newDoublyLinkedNode(
      TimerEntity(
        delay: delay,
        callback: cb,
        active: false,
        reusable: reusable)))

proc join*(t: Timer) =
  ## Join ``t`` to the timeout queue.
  template node: untyped = DoublyLinkedNode[TimerEntity](t)
  let gDisp = getGTimerDispatcher()
  let delay = node.value.delay
  if not node.value.joined:
    if not gDisp.timers.hasKey( delay):
      gDisp.timers[delay] = new(TimerQueue) # 启动一个新的定时器,并且维护一个链表
      init(gDisp.timers[delay], delay)
    node.value.joined = true
    gDisp.timers[delay].entities.append(node)
    inc(gDisp.timers[delay].length)

proc start*(t: Timer) =
  ## Starts ``t`` to begin timing and ``t`` is turn to active.
  ## 
  ## ``t`` should has joined in timeout queue.
  template node: untyped = DoublyLinkedNode[TimerEntity](t)
  let gDisp = getGTimerDispatcher()
  let delay = node.value.delay
  assert gDisp.timers.hasKey( delay), "timer of this node not exists"
  assert contains(gDisp.timers[delay].entities, node), "not joined any timer"
  assert gDisp.timers[delay].closed == false, "timer of this node has closed"
  node.value.active = true
  node.value.finishAt = epochTime() + node.value.delay / 1000
  if not gDisp.timers[delay].running:
    gDisp.timers[delay].start(delay)

proc stop*(t: Timer) =
  ## Stops ``t``. ``t`` is no longer active.
  template node: untyped = DoublyLinkedNode[TimerEntity](t)
  if node.value.active:
    node.value.active = false

proc clear*(t: Timer) =
  ## Clears ``t`` from timeout queue before excution.
  template node: untyped = DoublyLinkedNode[TimerEntity](t)
  let gDisp = getGTimerDispatcher()
  let delay = node.value.delay
  node.value.active = false
  if gDisp.timers.hasKey( delay):
    gDisp.timers[delay].entities.remove(node)
    dec(gDisp.timers[delay].length)
    node.value.joined = false
    if gDisp.timers[delay].length == 0:
      gDisp.timers[delay].close()

proc delay*(t: Timer): int =
  ## Returns the delay times (milliseconds) of ``t``.
  result = DoublyLinkedNode[TimerEntity](t).value.delay

proc active*(t: Timer): bool =
  ## Returns if ``t`` is active.
  result = DoublyLinkedNode[TimerEntity](t).value.active

proc setTimeout*(delay: int, cb: proc() {.closure,gcsafe.}, 
                 resuable = false): Timer {.discardable.} =
  ## Adds a new timer to the timeout queue. 
  ##
  ## Equivalent to:
  ##
  ## ..code-block::nim
  ##
  ##   node = newTimer(delay, cb, resuable)
  ##   join(node)
  ##   start(node)
  result = newTimer(delay, cb, resuable)
  result.join()
  result.start()

proc newTickerDispatcher*(): TickerDispatcher =
  ## Creates new dispatcher for tickers.
  new(result)
  GC_ref(result)
  result.started = false
  result.entities = @[]
  discard init(getDefaultLoop(), addr(result.handle))
  result.handle.data = cast[pointer](result)

var gTickerDispatcher{.threadvar.}: TickerDispatcher
proc getGTickerDispatcher*(): TickerDispatcher =
  if gTickerDispatcher == nil:
    gTickerDispatcher = newTickerDispatcher()
  return gTickerDispatcher

proc startTickerCb(handle: ptr Idle) {.cdecl.} =
  let gDisp = getGTickerDispatcher()
  discard stop(handle)
  gDisp.started = false
  var entities = gDisp.entities
  gDisp.entities.setLen(0)
  for callback in entities:
    callback()

proc callSoon*(cb: proc() {.closure,gcsafe.}) =
  ## ``cb`` will be deferred to the next iteration to excute.
  let gDisp = getGTickerDispatcher()
  gDisp.entities.add(cb)
  if not gDisp.started:
    discard start(addr(gDisp.handle), startTickerCb)
    gDisp.started = true

