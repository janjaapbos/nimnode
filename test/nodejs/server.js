require('net').createServer({
  allowHalfOpen: true
}, function (conn) {
  conn.on('data', (d) => {
    console.log(d.toString())
    conn.end()
    // setTimeout(() => {
    //   conn.write('hello')
    //     setTimeout(() => {
    //     conn.write('hello')
    //   }, 3000)
    // }, 3000)
  })
  conn.on('end', (d) => {
    console.log('end')
  })
  conn.on('finish', (d) => {
    console.log('finish')
  })
  conn.on('close', () => {
    console.log('close')
  })

}).listen(10000)