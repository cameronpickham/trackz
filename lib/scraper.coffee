request   = require('request')
async     = require('async')
mongoskin = require('mongoskin')

{ apiKey, username } = require('../config')

class Mongo
  constructor: ->
    @host = '127.0.0.1'
    @port = 27017
    @db   = 'trackz'

  getDB: ->
    path = "mongodb://#{@host}:#{@port}/#{@db}"
    db   = mongoskin.db(path, { native_parser: true })

    db.setMaxListeners(1337)

    return db

m  = new Mongo()
db = m.getDB()

class Scraper
  constructor: (apiKey, username) ->
    @apiKey      = apiKey
    @username    = username
    @currentPage = 1

  transform: (data) ->
    scrobbles = data.recenttracks.track.filter (x) ->
      x['@attr']?.nowplaying == false || x['@attr'] == undefined

    ret = scrobbles.map (s) ->
      song:   s.name
      artist: s.artist['#text']
      album:  s.album['#text']
      time:   s.date.uts

    return ret

  insert: (data, cb) ->
    async.each(data, ((s, cb) -> db.collection('scrobbles').insert(s, cb)), cb)

  get: (cb) ->
    done = false

    cycle = (cb) =>
      @getPage @currentPage, (err, data) =>
        return cb(err) if err

        done = data.recenttracks['@attr'].page == data.recenttracks['@attr'].totalPages
        transformed = @transform(data)
        @currentPage++

        @insert(transformed, cb)

    test = -> not done

    async.whilst(test, cycle, cb)

  getPage: (page, cb) ->
    opts =
      api_key: @apiKey
      format:  'json'
      page:    page
      limit:   200
      user:    @username

    request "http://ws.audioscrobbler.com/2.0/?method=user.getrecenttracks", { qs: opts }, (err, response, body) ->
      return cb(err) if err
      cb(null, JSON.parse(body))

s = new Scraper(apiKey, username)
db.collection('scrobbles').remove {}, (err) ->
  s.get (err, data) ->
    if err
      console.log err
      process.exit(1)

    console.log 'Done'
    process.exit(0)
