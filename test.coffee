naverLand = require './naverLand'
assert = (require 'chai').assert

describe 'naverLand', ->
  describe 'articles', ->
    it 'should fetch articles', (done) ->
      tickets = new naverLand.Tickets()
      naverLand.fetchArticles tickets.create(),
        rletTypeCd : '아파트'
        hsehCnt : 1000
        cortarNo : 1171011400,
        (h) ->
          done()
        ,false

  describe 'divisionList', ->
    it 'should fetch some list', (done) ->
      naverLand.fetchDivisions 1168000000, 1, () ->
        done()
    it 'should fetch some list level 2', (done) ->
      naverLand.fetchDivisions 1168000000, 2, () ->
        done()
    it 'should fetch some list level 3', (done) ->
      naverLand.fetchDivisions 1168000000, 3, ->
        done()

