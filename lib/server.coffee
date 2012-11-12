express       = require 'express'
socketio      = require 'socket.io'
mongoose      = require 'mongoose'
RoomManager   = require('iorooms').RoomManager
RedisStore    = require('connect-redis')(express)
models        = require './schema'
intertwinkles = require './intertwinkles'
config        = require './config'

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

  index_res = (req, res) ->
    res.render 'index', {
      title: "Firestarter"
      initial_data: {
        email: req.session.auth?.email or null
        groups: req.session.groups or null
      }
      intertwinkles_base_url: config.intertwinkles_base_url
    }

  app.get '/', index_res
  app.get '/new', index_res
  app.get '/f/:room', index_res

  # Get a valid slug for a firestarter that hasn't yet been used.
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

  # Create a new firestarter.
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

  # Retrieve a firestarter with responses.
  iorooms.onChannel 'get_firestarter', (socket, data) ->
    unless data.slug?
      socket.emit("error", {error: "Missing slug!"})
    models.Firestarter.with_responses {slug: data.slug}, (err, model) ->
      if err?
        socket.emit("error", {error: err})
      else
        socket.emit("firestarter", model.toJSON())

  # Save a response to a firestarter.
  iorooms.onChannel "save_response", (socket, data) ->
    console.log("save_response", data)
    respond = (err, firestarter, response) ->
      console.log("respond", err, firestarter, response)
      if err?
        socket.emit "error", {error: err}
      else
        response = {model: doc.toJSON()}
        if data.callback? then socket.emit(data.callback, response)
        socket.broadcast.to(firestarter.slug).emit("response", response)

    if not data.model?.firestarter_id
      respond("Missing firestarter id")

    models.Firestarter.findOne {_id: data.model.firestarter_id }, (err, firestarter) ->
      if err? then return respond(err)
      console.log("found", err, firestarter)

      updateFirestarter = (err, responseDoc) ->
        console.log("updateFirestarter", err, responseDoc)
        if err? then return respond(err)
        if firestarter.responses.indexOf(responseDoc._id) == -1
          # Add response to firestarter.
          firestarter.responses.push(responseDoc._id)
          firestarter.save (err, firestarter) ->
            respond(err, firestarter, responseDoc)
        else
          respond(err, firestarter, responseDoc)
      
      updates = {
        user: {
          user_id: data.model.user_id
          name: data.model.name
        }
        response: data.model.response
      }
      if data.model._id
        console.log "try update"
        models.Response.update({_id: data.model._id}, updates, updateFirestarter)
      else
        console.log "try insert"
        doc = new models.Response(updates)
        doc.save(updateFirestarter)

  intertwinkles.attach(config, app, iorooms)

  #
  # Start
  #
  app.listen options.port
  return { app, io, iorooms, sessionStore, db }

module.exports = { start }
