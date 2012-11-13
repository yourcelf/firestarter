browserid   = require 'browserid-consumer'
url         = require 'url'
querystring = require 'querystring'
_           = require 'underscore'
uuid        = require 'node-uuid'

verify = (assertion, config, callback) ->
  unless config.intertwinkles_base_url?
    throw "Missing required config parameter: intertwinkles_base_url"
  unless config.intertwinkles_api_key?
    throw "Missing required config parameter: intertwinkles_api_key"

  browserid.verify assertion, "#{config.host}:#{config.port}", (err, msg) ->
    if (err)
      callback({'error': err})
    else
      api_url = url.parse(config.intertwinkles_base_url + "/api/groups/")
      if api_url.protocol == "https:"
        httplib = require 'https'
      else if api_url.protocol == "http:"
        httplib = require 'http'

      query = {
        api_key: config.intertwinkles_api_key
        user: msg.email
      }
      opts = {
        hostname: api_url.hostname
        port: api_url.port
        path: "#{api_url.pathname}?#{querystring.stringify(query)}"
      }
      req = httplib.get(opts, (res) ->
        res.setEncoding('utf8')
        data = ''
        res.on 'data', (chunk) ->
          data += chunk
        res.on 'end', ->
          if res.statusCode != 200
            callback(error: "Status #{res.statusCode}")
          else
            try
              data = JSON.parse(data)
            catch e
              callback {error: e}
              return
            if data.error?
              callback(data)
            else
              callback(null, msg, data)
      ).on "error", (e) -> callback(error: e)

attach = (config, app, iorooms) ->
  if iorooms?
    # Build a list of everyone who is currently in the room, anonymous or no.
    build_room_users_list_for = (room, self_session, cb) ->
      iorooms.getSessionsInRoom room, (err, sessions) ->
        if err? then return cb(err)
        room_list = []
        for session in sessions
          authenticated = session.auth?.email? and session.groups?.users?
          if authenticated
            user = _.find session.groups.users, (u) -> u.email == session.auth.email
            info = { name: user.name, icon: user.icon }
          else
            info = { name: "Anonymous", icon: null }
          info.anon_id = session.anon_id
          room_list.push(info)
         cb(err, { room: room, list: room_list })

    # Log in
    iorooms.onChannel 'verify', (socket, reqdata) ->
      verify reqdata.assertion, config, (err, auth, groupdata) ->
        if err?
          socket.emit("error", err)
          socket.session.auth = null
          socket.session.groups = null
          iorooms.saveSession(socket.session)
          console.log "error", err
        else
          socket.session.auth = auth
          socket.session.groups = { groups: groupdata.groups, users: groupdata.users }
          iorooms.saveSession socket.session, (err) ->
            if (err) then return socket.emit "error", {error: err}

            socket.emit reqdata.callback, {
              email: auth.email,
              groups: socket.session.groups,
              messages: groupdata.messages
            }

            #FIXME: Broadcast back to other sockets in this session that they
            #have logged in. Maybe use a dedicated listener (e.g. 'auth')
            #instead of a 'once' listener with reqdata.callback

            # Update all room's user lists to include our logged in name
            rooms = iorooms.sessionRooms[socket.session.sid] or []
            for room in rooms
              do (room) ->
                build_room_users_list_for room, socket.session, (err, users) ->
                  socket.emit "room_users", users
                  socket.broadcast.to(room).emit "room_users", users

    # Log out
    iorooms.onChannel "logout", (socket, data) ->
      # Keep the session around, so that we maintain our socket list.
      socket.session.auth = null
      socket.session.groups = null
      iorooms.saveSession socket.session, ->
        socket.emit(data.callback, {status: "success"})

      # Update the list of room users to remove our logged in name
      rooms = iorooms.sessionRooms[socket.session.sid] or []
      for room in rooms
        do (room) ->
          build_room_users_list_for room, socket.session, (err, users) ->
            socket.emit "room_users", users
            socket.broadcast.to(room).emit "room_users", users

    # Join room
    iorooms.on "join", (data) ->
      join = (err) ->
        if err? then return data.socket.emit "error", {error: err}
        build_room_users_list_for data.room, data.socket.session, (err, users) ->
          if err? then return data.socket.emit "error", {error: err}
          # inform the client of its anon_id on first join.
          data.socket.emit "room_users", _.extend {
              anon_id: data.socket.session.anon_id
            }, users
          if data.first
            # Tell everyone else in the room.
            data.socket.broadcast.to(data.room).emit "room_users", users
      if not data.socket.session.anon_id?
        data.socket.session.anon_id = uuid.v4()
        iorooms.saveSession(data.socket.session, join)
      else
        join()

    # Leave room
    iorooms.on "leave", (data) ->
      return unless data.last
      build_room_users_list_for data.room, data.socket.session, (err, users) ->
        if err? then return data.socket.emit "error", {error: err}
        data.socket.broadcast.to(data.room).emit "room_users", users

  if app?
    null
    # TODO: Add routes to "/verify" and "/logout" for AJAX

module.exports = { attach, verify }
