// const http = require('http');
// var _req = null
// var _socket = null
// var _res = null
// // Create an HTTP server
// var i = 0
// var srv = http.createServer((req, res) => {
// 	//console.log(req.headers);
// 	if (_req !== null) {
// 		console.log('_req === req:', _req === req)
// 	}
// 	if (_socket !== null) {
// 		console.log('_socket === req.socket:', _socket === req.socket)
// 	}
// 	if (_res !== null) {
// 		console.log('_res === res:', _res === res)
// 	}
// 	_req = req
// 	_socket = req.socket
// 	_res = res
// 	var body = ''
// 	req.on('data', (d) => {
// 		body += d
// 		console.log('==> data: ', d.toString())
// 	})
// 	req.on('end', () => {
// 		console.log('==> end: ', body)
// 		if (i === 1) {
//       i = 2
//     } else if (i === 0) {
//     	res.write('---0a')
//       setTimeout(() => {
//         res.end('---0')
//       }, 3000)
//       i = 1
//     } else {
//     	res.write('---2a')
//       res.end('---2')
//     }
// 	})


	
	
	// req.on('data', (d) => {
	// 	console.log('data:', d.toString())
	// })
	// req.on('end', () => {
	// 	console.log('server requested', req.headers);
	// 	res.writeHead(200, {'Content-Type': 'text/plain'});
	// 	res.end('okay');
	// })
// });
// srv.on('upgrade', (req, socket, head) => {
// 	console.log(req.headers, Buffer.byteLength(head));
// 	socket.on('data', function (d) {
// 		console.log(Buffer.byteLength(d))
// 	})
//   socket.write('HTTP/1.1 101 Web Socket Protocol Handshake\r\n' +
//                'Upgrade: WebSocket\r\n' +
//                'Connection: Upgrade\r\n' +
//                '\r\n');

//   socket.pipe(socket); // echo back
// });
// srv.on('checkContinue', (req, res) => {
// 	console.log('got checkContinue');
// 	res.writeContinue()
// });

// now that server is running
const http = require('http')
var srv = http.createServer()
var i = 0
srv.on('request', (req, res) => {
  req.setEncoding('utf-8')
  req.on('data', (d) => {
    console.log('data', d)
    if (i === 0) {
      req.pause()
      //req.resume()
      console.log('...')
      i++
    }
  })
  req.on('end', () => {
    console.log('end ...........................')
  })
  req.on('error', (e) => {
    console.log('error', e)
  })
  req.on('close', (hasError) => {
    console.log('closed', hasError)
  })
})

srv.listen(10000, '127.0.0.1', () => {
  // make a request

});