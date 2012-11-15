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

  # Two-step operation: first, verify the assertion with Mozilla Persona.
  # Second, authorize the user with the InterTwinkles api server.
  #audience = "#{config.host}:#{config.port}"
  audience = config.intertwinkles_base_url.split("://")[1]
  browserid.verify assertion, audience, (err, auth) ->
    if (err)
      callback({'error': err})
    else
      # BrowserID success; now authorize with InterTwinkles.
      api_url = url.parse(config.intertwinkles_base_url + "/api/groups/")
      if api_url.protocol == "https:"
        httplib = require 'https'
      else if api_url.protocol == "http:"
        httplib = require 'http'

      opts = {
        hostname: api_url.hostname
        port: api_url.port
        path: "#{api_url.pathname}?" + querystring.stringify({
          api_key: config.intertwinkles_api_key
          user: auth.email
        })
      }
      req = httplib.get(opts, (res) ->
        res.setEncoding('utf8')
        data = ''
        res.on 'data', (chunk) -> data += chunk
        res.on 'end', ->
          if res.statusCode != 200
            return callback {error: "Status #{res.statusCode}"}
          else
            # Parse group data, and forward it along to client along with
            # persona auth.
            try
              groups = JSON.parse(data)
            catch e
              return callback {error: e}
            if groups.error?
              callback(groups)
            else
              callback(null, auth, groups)
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

    # Edit the more trivial profile details (email, name, color)
    iorooms.onChannel "edit_profile", (socket, data) ->
      respond = (err, res) ->
        if err?
          if data.callback?
            socket.emit data.callback, {error: err}
          else
            socket.emit "error", {error: err}
        else if data.callback?
          socket.emit data.callback, res

      if socket.session.auth.email != data.model.email
        return respond("Not authorized")
      if not data.model.name
        return respond("Invalid name")
      if not /[0-9a-fA-F]{6}/.test(data.model.icon.color)
        return respond("Invalid color #{data.model.icon.color}")
      if isNaN(data.model.icon.id)
        return respond("Invalid icon id")

      api_url = url.parse(config.intertwinkles_base_url + "/api/profiles/")
      opts = {
        hostname: api_url.hostname
        port: api_url.port
        path: api_url.pathname
        method: 'POST'
      }
      if api_url.protocol == "https:"
        httplib = require('https')
      else if api_url.protocol == "http:"
        httplib = require('http')

      # Make http request
      req = httplib.request opts, (res) ->
        res.setEncoding('utf8')
        answer = ''
        res.on 'data', (chunk) -> answer += chunk
        res.on 'end', ->
          if res.statusCode == 200
            profile = JSON.parse(answer)
            respond(null, model: profile)
          else
            respond("InterTwinkles status #{res.statusCode}")
            console.log(answer)
      post_data = querystring.stringify({
        api_key: config.intertwinkles_api_key,
        user: socket.session.auth.email
        name: data.model.name
        icon_id: data.model.icon.id
        icon_color: data.model.icon.color
      })
      req.setHeader("Content-Type", "applicatin/x-www-urlencoded")
      req.setHeader("Content-Length", post_data.length)
      req.write(post_data)
      req.end()

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
