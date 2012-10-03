request = require 'request'
cheerio = require 'cheerio'
xml2json = require 'xml2json'
restify = require 'restify'

fetchArticles = (input) ->
  options = input.options
  callback = input.callback

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
    o[hash[key]] = key for key in Object.keys(hash)
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
    (key + '=' + translateOption(key,options[key]) for key in Object.keys(options)).join('&')

  optionString = serializeOptions options
  uri = 'http://land.naver.com/article/articleList.nhn?' + optionString

  console.log uri

  request uri, (error,response,body) ->
    $ = cheerio.load body
    articles = []

    $('.sale_list>tbody>tr').each () ->
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
    $('.paginate>a:not(.next)').each () ->
      lastPage = parseInt $(this).text()
    hasMore = $('.paginate>a.next').length

    callback
      input : input
      articles : articles
      thisPage : thisPage
      nextPage : nextPage
      lastPage : lastPage
      hasMore : hasMore


class Article
  @constructor(@size)
  dump : () ->
    avg = (inarray) ->
      array = inarray.map (x) ->
        x.price
      sum = array.reduce (a,b) ->
        if (a == undefined) then return b
        if (b == undefined) then return a
        c = []

        for i in [0..a.length-1]
          c.push( a[i] + b[i] )

        return c

      result = sum.map (x) ->
        x / array.length

      return result

    avgs = {}
    avgs.A1 = avg(@A1) if @A1
    avgs.B1 = avg(@B1) if @B1
    avgs.B2 = avg(@B2) if @B2

    avgs

test = (options,next) ->
  h = {}
  inProgress = 1
  fetchArticles
    fetchAll : true,
    options : options
    callback :
      (result) ->
        addToHash = (a) ->
          hashTag = a.name + "/" + a.size
          if h[hashTag] == undefined
            h[hashTag] = new Article(a.size)
          o = h[hashTag]
          if (o[a.deal] == undefined) then o[a.deal] = []
          o[a.deal].push a

        addToHash(a) for a in result.articles

        if result.input.fetchAll and result.thisPage < result.lastPage
          for page in [result.thisPage+1..result.lastPage]
            result.input.options.page = page
            inProgress += 1
            fetchArticles
              fetchAll : page == result.lastPage and result.hasMore
              options : result.input.options
              callback : result.input.callback

        inProgress -= 1

        console.log 'inProgress:', inProgress

        if (inProgress == 0)
          next(h)


if process.argv[2] == 'test'
  test
    rletTypeCd : '아파트'
    cortarNo : 1168010500,
    (h) ->
      for k in Object.keys(h).sort()
        console.log(k,h[k].dump())
  return

respond = (req,res,next) ->
  res.send 'hello' + req.params.cortarNo

server = restify.createServer
  name: 'naverLand',
  version: '0.1.0'
server.use restify.acceptParser(server.acceptable)
server.use restify.queryParser()
server.use restify.bodyParser()

server.get '/apartment/:cortarNo', (req,res,next) ->
  cortarNo = req.params.cortarNo
  if (cortarNo == undefined)
    res.send 'invalid arguments'
    next()
  else
    test
      rletTypeCd : '아파트'
      cortarNo : cortarNo,
      (h) ->
        result = []
        for k in Object.keys(h).sort()
          result.push
            name : k
            data : h[k].dump()
        res.send(result)
        next()


server.listen 8080