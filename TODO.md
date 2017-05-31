
TODO
====

Test and examples
-----------------

- tests of net, http

- examples of chat room, http server and client, websocket server and client,
  mqtt server and client, httpflv server and client, ...

Core modules
------------

- http web server with router

- websocket parser

- mqtt      parser

- httpflv   parser

- webrtc    parser ?

- child_process

- tty

- ssl support

- uri tools ?

Expansion packages
------------------

- nimnode-redis

- nimnode-mysql

- nimnode-pgsql

- nimnode-mongodb

- nimnode-docker

- ...

-------------------------------------------------------------------

Tcp Server
----------

```nim
server = newTcpServer()
server.server(10000) do (conn: TcpConnection):
  
```

Tcp Client
----------

```nim
client = connect()
```

Http Server
-----------

```nim
server = newHttpServer()
server.serve(10000)

server.onClietError = proc (req): Future[void]
server.onUpgrade    = proc (conn, remainData): Future[void]
server.onRequest    = proc (req): Future[void]
server.onError      = proc (e): Future[void]
...
```

```nim
while true:
  var chunk = await req.read(1024)
  if chunk == "":
    break
  else:
    echo chunk

await res.writeHead(200, newStringTable({
  "Transfer-Encoding": "chunked",
  "Connection": "close"
}))
await res.write("Accept")
await res.writeEnd()
```


Http Client
-----------

```nim
client = newHttpClient()

req1 = client.request('/', {

})
req1.onResponse = proc (req1): Future[void]
  while true:
    req1.read()
req1.write()  

# 如果上一个请求未能正确发送数据长度，则关闭连接，建立一个新的连接发送数据
req2 = client.request('/', {

})
req2.onResponse = 
  while true:
    read()
req2.write()

client.close()
```

```nim
client = newHttpClient()

client.writeHead('/', {
  
})
client.write()
client.readHead()
while true:
  client.read()

client.writeHead('/', {
  
})
client.write()
client.readHead()
while true:
  client.read()

client.writeHead('/', {
  connection: 'Upgrade'
})
client.readHead()
client.write()
client.write()
client.read()
```

```nim
var client = newHttpClient(Port(10000))

var req, res = await client.request("GET", "/", newStringTable({
  "Transfer-Encoding": "chunked",
  "Connection": "keep-alive"
}))
await req.write("Hello") 
await req.write("world")
await req.writeEnd()

# 对于普通 Content-Lenngth 写入过量的数据是不允许的，这会抛出错误

# 对于普通 Content-Lenngth 写入不足量的数据是允许的，下一次 request 会关闭上一次的 request

# 一旦 writeEnd 不允许再次写入

# 对于普通 TransefEncoding: chunked 必须调用 writeEnd 写入最后一块

# write("") 不会进行任何操作

echo "  <<< ", res.statusMessage, " ", res.statusCode,  " HTTP/", 
     $res.httpVersionMajor, ".", $res.httpVersionMinor
for key,value in res.headers.pairs():
  echo "  <<< ", key, ": ", value
while true:
  let chunk = await res.read(1024)
  if chunk == "":
    break
  else:
    echo "  <<< ", chunk

echo ""

# 一旦发起一个新的 request，上一次的 request 便不可以使用：request 是串行的，不要并行
# 新的 request 会把上一次的 request 存留的数据读出来

#[

HttpClient - ClientRequest - ClientResponse

                             - {statusCode, ...}

             - write         - read
             - writeEnd 

HttpServer - ServerRequest - ServerResponse
             
             - {url, ...} 

             - read          - write
                             - writeEnd

]#

var req2, res2 = await client.request("GET", "/", newStringTable({
  "Transfer-Encoding": "chunked",
  "Connection": "keep-alive"
}))
await req2.write("Hello")
await req2.write("world")
await req2.writeEnd()

echo "  <<< ", res2.statusMessage, " ", res2.statusCode,  " HTTP/", 
     $res2.httpVersionMajor, ".", $res2.httpVersionMinor
for key,value in res2.headers.pairs():
  echo "  <<< ", key, ": ", value
while true:
  let chunk = await res2.read(1024)
  if chunk == "":
    break
  else:
    echo "  <<< ", chunk

echo ""

close(client)
```