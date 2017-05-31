import asyncdispatch, strutils

proc f1(): Future[void] =
  var fut = newFuture[void]()
  sleepAsync(100).callback = proc () =
    echo 1
    fail(fut, newException(ValueError, "error"))
  return fut

proc f2(): Future[void] =
  var fut = newFuture[void]()
  sleepAsync(100).callback = proc () =
    echo 2
    complete(fut)
  return fut

proc f() {.async.} =
  try:
    await f1()
    await f2()
    await f1()
    await f2()
  except ValueError:
    echo 1
  except IOError:
    raise newException(ValueError, "error io")
  except:
    raise newException(ValueError, "error")

waitFor f()

proc f_compiled(): Future[void] =
  var retFuture262078 = newFuture[void]("f")
  iterator fIter262079(): FutureBase {.closure.} =
    var future262080 = f1()
    yield future262080

    if future262080.failed:
      setCurrentException(future262080.error)
      if future262080.error of ValueError:
        echo 1
      elif future262080.error of IOError:
        raise newException(ValueError, "error io")
      elif true:
        raise newException(ValueError, "error")
      elif true:
        raise future262080.error
      setCurrentException(nil)
    else:
      future262080.read



      var future262081 = f2()
      yield future262081

      if future262081.failed:
        setCurrentException(future262081.error)
        if future262081.error of ValueError:
          echo 1
        elif future262081.error of IOError:
          raise newException(ValueError, "error io")
        elif true:
          raise newException(ValueError, "error")
        elif true:
          raise future262081.error
        setCurrentException(nil)
      else:
        future262081.read



        var future262082 = f1()
        yield future262082
        if future262082.failed:
          setCurrentException(future262082.error)
          if future262082.error of ValueError:
            echo 1
          elif future262082.error of IOError:
            raise newException(ValueError, "error io")
          elif true:
            raise newException(ValueError, "error")
          elif true:
            raise future262082.error
          setCurrentException(nil)
        else:
          future262082.read



          var future262083 = f2()
          yield future262083

          if future262083.failed:
            setCurrentException(future262083.error)
            if future262083.error of ValueError:
              echo 1
            elif future262083.error of IOError:
              raise newException(ValueError, "error io")
            elif true:
              raise newException(ValueError, "error")
            elif true:
              raise future262083.error
            setCurrentException(nil)
          else:
            try:
              future262083.read
            except ValueError:
              echo 1
            except IOError:
              raise newException(ValueError, "error io")
            except :
              raise newException(ValueError, "error")
              
    complete(retFuture262078)

  var nameIterVar262085 = fIter262079
  proc cb() {.closure, gcsafe.} =
    try:
      if not nameIterVar262085.finished:
        var next262087 = nameIterVar262085()
        if next262087 == nil:
          if not retFuture262078.finished:
            let msg262089 = "Async procedure ($1) yielded `nil`, are you await\'ing a " &
                "`nil` Future?"
            raise newException(AssertionError, msg262089 % "f")
        else:
          next262087.callback = cb
    except :
      if retFuture262078.finished:
        raise
      else:
        retFuture262078.fail(getCurrentException())

  cb()
  return retFuture262078
