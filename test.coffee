request = require 'request'
cheerio = require 'cheerio'
restify = require 'restify'
connect = require 'connect'

class Ticket
  constructor: (@parent,@id) ->
    @count = 0
    @stat = {}
  ref: ->
    @count += 1
    #console.log("ticket ref #{@id} has #{@count}")
  unref: ->
    @count -= 1
    #console.log("ticket unref #{@id} has #{@count}")
    if (@count == 0)
      @parent.delete(@id)
  kill: ->
    @pendingKill = true
    #console.log("ticket #{@id} killed")

class Tickets
  constructor: ->
    @active = {}
    @next = 1
  create: () ->
    r = new Ticket(this,@next)
    @active[@next] = r
    @next += 1
    #console.log "ticket created #{r.id}"
    r
  delete: (id) ->
    #console.log("ticket destroyed #{id}")
    delete @active[id]
  find: (id) ->
    #console.log "tickets find #{id} -> #{@active[id]}"
    @active[id]

naverApiUri = (cortarNo) ->
  uri = "http://land.naver.com/article/"
  if cortarNo % 100000000 == 0
    uri += "cityInfo"
  else if cortarNo % 1000000 == 0
    uri += "divisionInfo"
  else
    uri += "articleList"
  uri += ".nhn"
  uri

fetchArticles = (ticket,input) ->
  options = input.options
  callback = input.callback

  if ticket.pendingKill
    #console.log('early out because of expired ticket')
    callback
      input : input
      articles : []
    return

  ticket.ref()

  rletTypeCd =
    A01 : '아파트'
    A02 : '오피스텔'
    B01 : '분양권'
    C01 : '원룸'
    C02 : '빌라'
    C03 : '주택'
    D01 : '사무실'
    D02 : '상가'
    D03 : '건물'
    E02 : '공장'
    E03 : '토지'
    F01 : '재개발'

  tradeTypeCd =
    all : '전체'
    A1 : '매매'
    B1 : '전세'
    B2 : '월세'

  invLookup = (hash) ->
    o = {}
    o[value] = key for key, value of hash
    o

  dictHelper =
    rletTypeCd : invLookup rletTypeCd
    tradeTypeCd : invLookup tradeTypeCd

  translateOption = (key,value) ->
    inv = dictHelper[key]
    if (inv == undefined) then return value
    if (inv[value] == undefined) then throw "invalid value" + value
    inv[value]

  serializeOptions = (options) ->
    ("#{key}=#{translateOption(key,options[key])}" for key in Object.keys(options)).join('&')

  optionString = serializeOptions options
  uri = "#{naverApiUri(options.cortarNo)}?#{optionString}"

  request uri, (error,response,body) ->
    $ = cheerio.load body
    articles = []

    $('.sale_list>tbody>tr').each ->
      if (this[0].children.length == 3) then return
      a = this[0].children
      valid = true
      o =
        deal : translateOption('tradeTypeCd',$(a[1]).text())
        type : $(a[3]).text()
        name : $('a',a[5]).text()
        size : parseInt $('strong',a[7]).text()
        price : $('strong',a[9]).text().replace(/,/g,'').split('/').map (x) ->
          v = parseInt(x)
          if (isNaN(v))
            valid = false
          v

      articles.push o if valid

    thisPage = parseInt $('.paginate>strong').text()
    nextPage = parseInt $('.paginate>strong+a').text()
    lastPage = undefined
    $('.paginate>a:not(.next)').each ->
      lastPage = parseInt $(this).text()
    hasMore = $('.paginate>a.next').length

    callback
      input : input
      articles : articles
      thisPage : thisPage
      nextPage : nextPage
      lastPage : lastPage
      hasMore : hasMore

    ticket.unref()


class Article
  constructor : (@name,@size) ->
  dump : ->
    avg = (inarray) ->
      array = inarray.map (x) ->
        x.price
      sum = array.reduce (a,b) ->
        if (a == undefined) then return b
        if (b == undefined) then return a
        return (a[i] + b[i] for i in [0..a.length-1])

      result = sum.map (x) ->
        Math.floor(x / array.length)

      return result

    result =
      name : @name
      size : @size
      A1 : avg(@A1)[0] if @A1
      B1 : avg(@B1)[0] if @B1
      B2 : avg(@B2) if @B2

    # rent 이율 Y = 12 * 월세 / (투자비용 = 매매 - 보증금)
    result.rentalInterest = (result.B2[1] * 12) / (result.A1 - result.B2[0]) if result.A1 and result.B1 and result.B2

    result

test = (ticket,options,next) ->
  h = {}
  inProgress = 1
  fetchArticles ticket,
    fetchAll : true
    options : options
    callback :
      (result) ->
        addToHash = (a) ->
          hashTag = a.name + "/" + a.size
          if h[hashTag] == undefined
            h[hashTag] = new Article(a.name,a.size)
            ticket.stat.articles ?= 0
            ticket.stat.articles += 1
          o = h[hashTag]
          if (o[a.deal] == undefined) then o[a.deal] = []
          o[a.deal].push a

        addToHash(a) for a in result.articles

        if result.input.fetchAll and result.thisPage < result.lastPage
          ## 속도를 올리기 위해서 마지막 페이지부터 query 날림!
          for page in [result.lastPage..result.thisPage+1]
            # option의 page번호를 변경한다!
            result.input.options.page = page
            # 진행 중인 쿼리의 개수를 증가시키자!
            inProgress += 1
            # 마지막 페이지만 나머지를 모조리 갖고 올 자격이 있다!
            fetchAll = (page == result.lastPage and result.hasMore)
            # go go go!
            fetchArticles ticket,
              fetchAll : fetchAll
              options : result.input.options
              callback : result.input.callback

        inProgress -= 1

        ticket.stat.workers = inProgress

        if (inProgress == 0)
          next(h)

divisionList = (cortarNo,index,next) ->
  uri = "#{naverApiUri(cortarNo)}?cortarNo=#{cortarNo}"
  request uri, (error,response,body) ->
    $ = cheerio.load body
    result = []
    $("#loc_view#{index} option[value]").each ->
      result.push
        value : parseInt $(this).attr('value')
        name : $(this).text()
    next(result)

switch process.argv[2]
  when 'test'
    tickets = new Tickets()
    test tickets.create(),
      rletTypeCd : '아파트'
      hsehCnt : 1000
      cortarNo : 1168000000,#1171010900,#1171011400,
      (h) ->
        for k in Object.keys(h).sort()
          console.log(k,h[k].dump())
    break
  when 'divisionList'
    divisionList 1168000000, 3, (result) ->
      console.log(result)
    break
  when 'server'
    tickets = new Tickets()
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
        divisionList cortarNo, index, (result) ->
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

          test ticket,
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