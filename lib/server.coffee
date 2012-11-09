express     = require 'express'
socketio    = require 'socket.io'
mongoose    = require 'mongoose'
RoomManager = require('iorooms').RoomManager
RedisStore  = require('connect-redis')(express)
models      = require './schema'

start = (options) ->
  db = mongoose.connect(
    "mongodb://#{options.dbhost}:#{options.dbport}/#{options.dbname}"
  )
  sessionStore = new RedisStore

  app = express.createServer()

  #
  # Config
  #
  app.configure ->
    app.use require('connect-assets')()
    app.use express.bodyParser()
    app.use express.cookieParser()
    app.use express.session
      secret: options.secret
      key: 'express.sid'
      store: sessionStore
    app.set 'view options', {layout: false}

  app.configure 'development', ->
    app.use express.static __dirname + '/../assets'
    app.use express.errorHandler {dumpExceptions: true, showStack: true }

  app.configure 'production', ->
    # Cache long time in production.
    app.use express.static __dirname + '/../assets', { maxAge: 1000*60*60*24 }
  app.set 'view engine', 'jade'

  io = socketio.listen(app, {"log level": 0})
  iorooms = new RoomManager("/iorooms", io, sessionStore)

  #
  # Routes
  #

  app.get '/', (req, res) ->
    res.render 'index', { title: "Firestarter", initial_data: {} }

  app.get '/f/:room', (req, res) ->
    res.render 'index', { title: req.params.room, initial_data: {} }

  iorooms.onChannel "create_firestarter", (socket, data) ->
    unless data.callback?
      socket.emit("error", {error: "Must specifiy callback."})
    unless data.model?
      socket.emit(data.callback, {error: "Missing required model attribute."})

    model = new models.Firestarter(data.model)
    model.save (err, model) ->
      if err?
        errors = []
        if err.name == "ValidationError"
          for field, error of err.errors
            if error.type == "required"
              errors.push({field: field, message: "This field is required."})
            else
              errors.push({field: field, message: error.message})
          socket.emit(data.callback, {error: errors, type: "ValidationError"})
        else if err.name == "MongoError" and err.err.indexOf("duplicate key") != -1
          errors.push({field: "slug", message: "This name is already taken."})
          socket.emit(data.callback, {error: errors, type: "ValidationError"})
        else
          socket.emit(data.callback, {error: []})
      else
        socket.emit(data.callback, {model: model.toJSON()})

  iorooms.onChannel 'get_unused_slug', (socket, data) ->
    choices = "abcdefghijklmnopqrstuvwxyzABCDEFGHIJKLMNOPQRSTUVWXYZ0123456789"
    unless data.callback?
      socket.emit("error", {error: "Must specify callback."})
      return

    get_slug = ->
      random_name = (
        choices.substr(parseInt(Math.random() * choices.length), 1) for i in [0...6]
      ).join("")
      models.Firestarter.find {slug: random_name}, (err, things) ->
        socket.emit({error: err}) if err
        if things.length == 0
          socket.emit(data.callback, {slug: random_name})
        else
          get_slug()
    get_slug()

  iorooms.onChannel 'get_firestarter', (socket, data) ->
    unless data.slug?
      socket.emit("error", {error: "Missing slug!"})
    models.Firestarter.with_reponses {slug: data.slug}, (err, model) ->
      if err?
        socket.emit({error: err})
      else
        socket.emit("firestarter", model.toJSON())

  #
  # Start
  #
  app.listen options.port
  return { app, io, iorooms, sessionStore, db }

module.exports = { start }
