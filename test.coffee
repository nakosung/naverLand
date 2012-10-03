request = require 'request'
cheerio = require 'cheerio'
xml2json = require 'xml2json'

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

h = {}
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

fetchArticles
  fetchAll : true,
  options :
    rletTypeCd : '아파트'
    cortarNo : 1168010500,
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
          fetchArticles
            fetchAll : page == result.lastPage and result.hasMore
            options : result.input.options
            callback : result.input.callback

      console.log '*' for i in [1..10]
      for k in Object.keys(h).sort()
        console.log(k,h[k].dump())

