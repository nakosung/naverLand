restify = require 'restify'
connect = require 'connect'
naverLand = require './naverLand'

tickets = new naverLand.Tickets()
cache = {}
respond = (req,res,next) ->
  res.send 'hello' + req.params.cortarNo

server = restify.createServer
  name: 'naverLand',
  version: '0.1.0'
server.use restify.acceptParser(server.acceptable)
server.use restify.queryParser()
server.use restify.bodyParser()

# 기본 redirect
server.get '/', (req,res,next) ->
  res.writeHead 302, Location:'/docs/test.html'
  res.end()
  next()

# static file serving
static_docs_server = connect.static(__dirname)
server.get /\/docs\/*/, (req,res,next) ->
  req.url = req.url.substr('/docs'.length)
  static_docs_server(req,res,next)

# 지역 번호 알림
server.get '/cortar/:cortarNo/:index', (req,res,next) ->
  cortarNo = req.params.cortarNo
  index = req.params.index
  if (cortarNo and index)
    naverLand.fetchDivisions cortarNo, index, (result) ->
      res.send result
      next()
  else
    res.send 'invalid arguments'
    next()

# 아파트 query
server.get '/apt/:cortarNo', (req,res,next) ->
  cortarNo = req.params.cortarNo
  if (cortarNo == undefined)
    res.send 'invalid arguments'
    next()
  else
    if cache[cortarNo]
      res.send(cache[cortarNo])
      next()
    else
      ticket = tickets.find(req.query.ticket)
      if (!ticket)
        ticket = ticket.create()
      ticket.ref()

      naverLand.fetchArticles ticket,
        rletTypeCd : '아파트'
        cortarNo : cortarNo,
        (h) ->
          result = []
          for k in Object.keys(h).sort()
            result.push
              name : k
              data : h[k].dump()

          if not ticket.pendingKill
            cache[cortarNo] = result

          ticket.unref()

          res.send(result)
          next()


server.post '/ticket', (req,res,next) ->
  res.send 201, {ticket:tickets.create().id}
  next()
server.del '/ticket/:id', (req,res,next) ->
  (tickets.find req.params.id)?.kill()
  res.send 204
  next()
server.get '/ticket-stat/:id', (req,res,next) ->
  res.send (tickets.find req.params.id)?.stat
  next()

# for c9.io support
port = process.env.PORT
host = process.env.HOST
port ?= 8081

console.log "시작합니다! @#{port} listening!"
server.listen port, host