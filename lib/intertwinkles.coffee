browserid = require 'browserid-consumer'
url = require 'url'
querystring = require 'querystring'
_ = require 'underscore'


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
          socket.emit reqdata.callback, {
            email: auth.email,
            groups: socket.session.groups,
            messages: groupdata.messages
          }
          iorooms.saveSession(socket.session)
    iorooms.onChannel "logout", (socket, data) ->
      # Keep the session around, so that we maintain our socket list.
      socket.session.auth = null
      socket.session.groups = null
      iorooms.saveSession socket.session, ->
        socket.emit(data.callback, {status: "success"})
  if app?
    null
    # TODO: Add routes to "/verify" and "/logout" for AJAX

module.exports = { attach, verify }
