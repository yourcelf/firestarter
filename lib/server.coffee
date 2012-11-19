express       = require 'express'
socketio      = require 'socket.io'
mongoose      = require 'mongoose'
RoomManager   = require('iorooms').RoomManager
RedisStore    = require('connect-redis')(express)
intertwinkles = require 'node-intertwinkles'
models        = require './schema'
config        = require './config'
_             = require 'underscore'

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
    app.use require('connect-assets')({servePath: ""})
    app.use express.bodyParser()
    app.use express.cookieParser()
    app.use express.session
      secret: options.secret
      key: 'express.sid'
      store: sessionStore
    app.set 'view options', {layout: false}

  app.configure 'development', ->
    app.use '/static', express.static(__dirname + '/../assets')
    app.use '/static', express.static(__dirname + '/../node_modules/node-intertwinkles/assets')
    app.use express.errorHandler {dumpExceptions: true, showStack: true }

  app.configure 'production', ->
    # Cache long time in production.
    app.use '/static', express.static(__dirname + '/../assets', { maxAge: 1000*60*60*24 })
    app.use '/static', express.static(__dirname + '/../node_modules/node-intertwinkles/assets', { maxAge: 1000*60*60*24 })

  app.set 'view engine', 'jade'

  io = socketio.listen(app, {"log level": 0})
  iorooms = new RoomManager("/iorooms", io, sessionStore)

  #
  # Routes
  #

  index_res = (req, res, initial_data) ->
    intertwinkles.list_accessible_documents models.Firestarter, req.session, (err, docs) ->
      return res.send(500) if err?
      res.render 'index', {
        title: "Firestarter"
        initial_data: _.extend({
          email: req.session.auth?.email or null
          groups: req.session.groups or null
          listed_firestarters: docs
        }, initial_data)
        conf: options.intertwinkles
      }

  app.get '/', (req, res) -> index_res(req, res, {})
  app.get '/new', (req, res) -> index_res(req, res, {})
  app.get '/f/:slug', (req, res) ->
    models.Firestarter.with_responses {slug: req.params.slug}, (err, doc) ->
      return res.send(500) if err?
      return res.send(404) if not doc?
      #FIXME: Redirect to login instead.
      return res.send(403) if not intertwinkles.can_view(req.session, doc)

      editable =  intertwinkles.can_edit(req.session, doc)
      doc.sharing = intertwinkles.clean_sharing(req.session, doc)
      index_res(req, res, {
        firestarter: doc.toJSON()
        editable: editable
      })

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
      return socket.emit("error", {error: "Must specifiy callback."})
    unless data.model?
      return socket.emit("error", {error: "Missing required model attribute."})
    unless intertwinkles.can_edit(socket.session, data.model)
      return socket.emit("error", {error: "Permission denied"})

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

  # Edit a firestarter
  iorooms.onChannel 'edit_firestarter', (socket, data) ->
    updates = {}
    changes = false
    for key in ["name", "prompt", "public", "sharing"]
      if data.model?[key]
        updates[key] = data.model[key]
        changes = true
    if not changes then return socket.emit "error", {error: "No edits specified."}

    models.Firestarter.findOne {_id: data.model._id}, (err, doc) ->
      if err? then return socket.emit "error", {error: err}
      unless intertwinkles.can_edit(socket.session, doc)
        return socket.emit("error", {error: "Permission denied"})
      for key, val of updates
        doc[key] = val
      doc.save (err, doc) ->
        if err? then return socket.emit "error", {error: err}
        doc.sharing = intertwinkles.clean_sharing(socket.session, doc)
        res = {model: doc.toJSON()}
        delete res.model.responses
        if data.callback? then socket.emit data.callback, res
        socket.broadcast.to(doc.slug).emit "firestarter", res

  # Retrieve a firestarter with responses.
  iorooms.onChannel 'get_firestarter', (socket, data) ->
    unless data.slug?
      socket.emit("error", {error: "Missing slug!"})
    models.Firestarter.with_responses {slug: data.slug}, (err, model) ->
      if err?
        socket.emit("error", {error: err})
      else if not model?
        socket.emit("firestarter", {error: 404})
      else if not intertwinkles.can_view(socket.session, model)
        socket.emit("error", {error: "Permission denied"})
      else
        model.sharing = intertwinkles.clean_sharing(socket.session, model)
        socket.emit("firestarter", {
          model: model.toJSON()
          editable: intertwinkles.can_edit(socket.session, model)
        })

  # Save a response to a firestarter.
  iorooms.onChannel "save_response", (socket, data) ->
    respond = (err, firestarter, response) ->
      if err?
        socket.emit "error", {error: err}
      else
        responseData = {model: response.toJSON()}
        if data.callback? then socket.emit(data.callback, responseData)
        socket.broadcast.to(firestarter.slug).emit("response", responseData)

    if not data.model?.firestarter_id
      respond("Missing firestarter id")


    models.Firestarter.findOne {_id: data.model.firestarter_id }, (err, firestarter) ->
      if err? then return respond(err)
      unless intertwinkles.can_edit(socket.session, firestarter)
        return respond("Permission denied")

      updateFirestarter = (err, responseDoc) ->
        if err? then return respond(err)
        if firestarter.responses.indexOf(responseDoc._id) == -1
          # Add response to firestarter.
          firestarter.responses.push(responseDoc._id)
          firestarter.save (err, firestarter) ->
            respond(err, firestarter, responseDoc)
        else
          respond(err, firestarter, responseDoc)
      
      updates = {
        user_id: data.model.user_id
        name: data.model.name
        response: data.model.response
        firestarter_id: firestarter._id
      }
      if data.model._id
        models.Response.findOne {_id: data.model._id}, (err, doc) ->
          if err? then return respond(err)
          for key, val of updates
            doc[key] = val
          doc.save(updateFirestarter)
      else
        doc = new models.Response(updates)
        doc.save(updateFirestarter)

  # Delete a response
  iorooms.onChannel "delete_response", (socket, data) ->
    if not data.model?.firestarter_id? then respond("Missing firestarter id")

    respond = (err, firestarter, response) ->
      if err? then return socket.emit "error", {error: err}
      responseData = {model: {_id: data.model._id}}
      if data.callback? then socket.emit(data.callback, responseData)
      socket.broadcast.to(firestarter.slug).emit("delete_response", responseData)

    models.Firestarter.findOne {_id: data.model.firestarter_id }, (err, firestarter) ->
      if err? then return respond(err)
      unless intertwinkles.can_edit(socket.session, firestarter)
        return respond("Permission denied")

      if not firestarter? then return respond("Error: firestarter not found.")
      unless data.model._id? then return respond("No response._id specified.")

      models.Response.findOne {_id: data.model._id}, (err, doc) ->
        if err? then return respond(err)
        doc.remove (err) ->
          if err? then return respond(err)
          # Remove response ID from firestarter doc
          index = firestarter.responses.indexOf(data.model._id)
          if index != -1
            firestarter.responses.splice(index, 1)
            firestarter.save(respond)
          else
            respond(err, firestarter)

  intertwinkles.attach(config, app, iorooms)

  #
  # Start
  #
  app.listen options.port
  return { app, io, iorooms, sessionStore, db }

module.exports = { start }
