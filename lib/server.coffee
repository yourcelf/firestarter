express       = require 'express'
socketio      = require 'socket.io'
mongoose      = require 'mongoose'
RoomManager   = require('iorooms').RoomManager
RedisStore    = require('connect-redis')(express)
intertwinkles = require 'node-intertwinkles'
models        = require './schema'
config        = require './config'
_             = require 'underscore'
async         = require 'async'

start = (config) ->
  db = mongoose.connect(
    "mongodb://#{config.dbhost}:#{config.dbport}/#{config.dbname}"
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
      secret: config.secret
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

  io = socketio.listen app, {"log level": 0}
  iorooms = new RoomManager("/iorooms", io, sessionStore)
  iorooms.authorizeJoinRoom = (session, name, callback) ->
    # Only allow to join the room if we're allowed to view the firestarter.
    models.Firestarter.findOne {'slug': name}, 'sharing', (err, doc) ->
      return callback(err) if err?
      if intertwinkles.can_view(session, doc)
        callback(null)
      else
        callback("Permission denied")
    
  io.of("/iorooms").setMaxListeners(15)

  #
  # Routes
  #

  index_res = (req, res, initial_data) ->
    intertwinkles.list_accessible_documents models.Firestarter, req.session, (err, docs) ->
      return res.send(500) if err?
      clean_conf = _.extend({}, config.intertwinkles)
      delete clean_conf.api_key
      res.render 'index', {
        title: "Firestarter"
        initial_data: _.extend({
          email: req.session.auth?.email or null
          groups: req.session.groups or null
          listed_firestarters: docs
        }, initial_data)
        conf: clean_conf
      }

  app.get '/', (req, res) -> index_res(req, res, {})
  app.get '/new', (req, res) -> index_res(req, res, {})
  app.get '/f/:slug', (req, res) ->
    models.Firestarter.with_responses {slug: req.params.slug}, (err, doc) ->
      return res.send(500) if err?
      return res.send(404) if not doc?
      #FIXME: Redirect to login instead.
      return res.send(403) if not intertwinkles.can_view(req.session, doc)

      if intertwinkles.is_authenticated(req.session)
        intertwinkles.post_event_for req.session.auth.email, {
          type: "visit"
          application: "firestarter"
          entity: doc.id
          entity_url: "#{config.intertwinkles.apps.firestarter.url}/f/#{doc.slug}"
          user: req.session.auth.email
          group: doc.sharing.group_id
        }, config, (->), 5000 * 60

      doc.sharing = intertwinkles.clean_sharing(req.session, doc)
      index_res(req, res, {
        firestarter: doc.toJSON()
        can_edit: intertwinkles.can_edit(req.session, doc)
        can_change_sharing: intertwinkles.can_change_sharing(req.session, doc)
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
        if intertwinkles.is_authenticated(socket.session)
          url = "#{config.intertwinkles.apps.firestarter.url}/f/#{model.slug}"
          intertwinkles.post_event_for socket.session.auth.email, {
            type: "create"
            application: "firestarter"
            entity: model.id
            entity_url: url
            user: socket.session.auth.email
            group: model.sharing.group_id
            data: {
              name: model.name
              prompt: model.prompt
            }
          }, config
          intertwinkles.post_search_index {
            application: "firestarter"
            entity: model.id
            type: "firestarter"
            url: url
            title: model.name
            summary: model.prompt
            content: [model.name, model.prompt].join("\n")
            sharing: model.sharing
          }, config

  # Edit a firestarter
  iorooms.onChannel 'edit_firestarter', (socket, data) ->
    updates = {}
    changes = false
    for key in ["name", "prompt", "public", "sharing"]
      if data.model?[key]
        updates[key] = data.model[key]
        changes = true
    if not changes then return socket.emit "error", {error: "No edits specified."}

    models.Firestarter.findOne({
      _id: data.model._id
    }).populate('responses').exec (err, doc) ->
      if err? then return socket.emit "error", {error: err}
      unless intertwinkles.can_edit(socket.session, doc)
        return socket.emit("error", {error: "Permission denied"})
      unless intertwinkles.can_change_sharing(socket.session, doc)
        delete updates.sharing
      for key, val of updates
        doc[key] = val
      doc.save (err, doc) ->
        if err? then return socket.emit "error", {error: err}
        doc.sharing = intertwinkles.clean_sharing(socket.session, doc)
        res = {model: doc.toJSON()}
        delete res.model.responses
        if data.callback? then socket.emit data.callback, res
        socket.broadcast.to(doc.slug).emit "firestarter", res
        
        # Add event and search index.
        url = "#{config.intertwinkles.apps.firestarter.url}/f/#{doc.slug}"
        if intertwinkles.is_authenticated(socket.session)
          intertwinkles.post_event_for(socket.session.auth.email, {
            type: "update"
            application: "firestarter"
            entity: doc.id
            entity_url: url
            user: socket.session.auth.email
            group: doc.sharing.group_id
            data: updates
          }, config)
        intertwinkles.post_search_index({
          application: "firestarter"
          entity: doc.id
          type: "firestarter"
          url: url
          title: doc.name
          summary: doc.prompt
          content: [doc.name, doc.prompt].concat((
            res.response for res in doc.responses
          )).join("\n")
        }, config)


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
          can_edit: intertwinkles.can_edit(socket.session, model)
          can_change_sharing: intertwinkles.can_change_sharing(socket.session, model)
        })
        if intertwinkles.is_authenticated(socket.session)
          intertwinkles.post_event_for socket.session.auth.email, {
            type: "visit"
            application: "firestarter"
            entity: model.id
            entity_url: "#{config.intertwinkles.apps.firestarter.url}/f/#{model.slug}"
            user: socket.session.auth.email
            group: model.sharing.group_id
          }, config, (->), 5000 * 60
  
  iorooms.onChannel "get_firestarter_list", (socket, data) ->
    if not data.callback?
      socket.emit "error", {error: "Missing callback parameter."}
    else
      intertwinkles.list_accessible_documents(
        models.Firestarter, socket.session, (err, docs) ->
          if err? then return socket.emit data.callback, {error: err}
          socket.emit data.callback, {docs: docs}
      )


  # Save a response to a firestarter.
  iorooms.onChannel "save_response", (socket, data) ->
    async.waterfall [
      # Grab the firestarter. Populate responses so we can build search
      # content.
      (done) ->
        models.Firestarter.findOne({
          _id: data.model.firestarter_id
        }).populate("responses").exec (err, firestarter) ->
          return done(err) if err?
          unless intertwinkles.can_edit(socket.session, firestarter)
            done("Permission denied")
          else
            done(null, firestarter)

      # Save the response.
      (firestarter, done) ->
        updates = {
          user_id: data.model.user_id
          name: data.model.name
          response: data.model.response
          firestarter_id: firestarter._id
        }
        if data.model._id
          conditions = {
            _id: data.model._id
          }
          options = {upsert: true, 'new': true}
          models.Response.findOneAndUpdate conditions, updates, options, (err, doc) ->
            done(err, firestarter, doc)
        else
          new models.Response(updates).save (err, doc) ->
            done(err, firestarter, doc)

      # Replace or insert the response, build search content
      (firestarter, response, done) ->
        found = false
        for orig_response,i in firestarter.responses
          if orig_response._id == response._id
            firestarter.responses.splice(i, 1, response)
            found = true
            break
        if not found
          firestarter.responses.push(response)
          console.log(firestarter.responses)

        # Get the search content.
        search_content = [firestarter.name, firestarter.prompt].concat((
          r.response for r in firestarter.responses
        )).join("\n")

        # If this is a new response, un-populate responses and save it to
        # the firestarter's list.
        if not found
          firestarter.save (err, doc) ->
            done(err, doc, response, search_content)
        else
          done(err, firestarter, response, search_content)

    ], (err, firestarter, response, search_content) ->
      # Call back to sockets.
      return socket.emit "error", {error: err} if err?
      responseData = {model: response.toJSON()}
      socket.broadcast.to(firestarter.slug).emit("response", responseData)
      socket.emit(data.callback, responseData) if data.callback?

      # Post search data
      url = "#{config.intertwinkles.apps.firestarter.url}/f/#{firestarter.slug}"
      intertwinkles.post_search_index {
        application: "firestarter", entity: firestarter.id,
        type: "firestarter", url: url,
        title: firestarter.name, summary: firestarter.prompt,
        content: search_content
      }, config, (err) ->
        socket.emit("error", {error: err}) if err?

      # Post an event if we're signed in.
      if intertwinkles.is_authenticated(socket.session)
        intertwinkles.post_event_for(socket.session.auth.email, {
          type: "append"
          application: "firestarter"
          entity: firestarter.id
          entity_url: url
          user: response.user_id or null
          via_user: socket.session.auth.user_id
          group: firestarter.sharing.group_id
          data: response.toJSON()
        }, config)

  # Delete a response
  iorooms.onChannel "delete_response", (socket, data) ->
    return done("No response._id specified") unless data.model._id?
    return done("No firestarter_id specified") unless data.model.firestarter_id?
    async.waterfall [
      (done) ->
        # Fetch firestarter and validate permissions.
        models.Firestarter.findOne({
          _id: data.model.firestarter_id
          responses: data.model._id
        }).populate('responses').exec (err, firestarter) ->
          return done(err) if err?
          return done("Firestarter not found.") unless firestarter?
          unless intertwinkles.can_edit(socket.session, firestarter)
            return done("Permission denied")
          
          for response,i in firestarter.responses
            if response._id.toString() == data.model._id
              firestarter.responses.splice(i, 1)
              return done(null, firestarter, response)
          return done("Error: response not found")

      (firestarter, response, done) ->
        # Build search content, save firestarter and response.
        search_content = [firestarter.name, firestarter.prompt].concat((
          r.response for r in firestarter.responses
        )).join("\n")
        async.parallel [
          (done) -> firestarter.save(done)
          (done) -> response.remove(done)
        ], (err) ->
          done(err, firestarter, response, search_content)

      (firestarter, response, search_content, done) ->
        # Respond to the sockets
        responseData = {model: {_id: data.model._id}}
        socket.emit(data.callback, responseData) if data.callback?
        socket.broadcast.to(firestarter.slug).emit("delete_response", responseData)

        # Post event
        url = "#{config.intertwinkles.apps.firestarter.url}/f/#{firestarter.slug}"
        if intertwinkles.is_authenticated(socket.session)
          intertwinkles.post_event_for socket.session.auth.email, {
            type: "trim"
            application: "firestarter"
            entity: firestarter.id
            entity_url: url
            user: socket.session.auth.email
            group: firestarter.sharing.group_id
            data: response?.toJSON()
          }, config, (err) ->
            socket.emit "error", {error: err} if err?
        
        # Post search index
        intertwinkles.post_search_index {
            application: "firestarter", entity: firestarter.id,
            type: "firestarter", url: url,
            title: firestarter.name, summary: firestarter.prompt,
            content: search_content
          }, config, (err) ->
            socket.emit "error", {error: err} if err?

    ], (err) ->
      socket.emit "error", {error: err} if err?


  intertwinkles.attach(config, app, iorooms)

  #
  # Start
  #
  app.listen config.port
  return { app, io, iorooms, sessionStore, db }

module.exports = { start }
