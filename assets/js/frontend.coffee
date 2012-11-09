#= require vendor/jquery
#= require vendor/underscore
#= require vendor/underscore-autoescape
#= require vendor/backbone
#= require vendor/jquery-ui-1.9.0.custom
#= require ../bootstrap/js/bootstrap-transition.js
#= require ../bootstrap/js/bootstrap-modal.js
#= require ../bootstrap/js/bootstrap-dropdown.js
#= require ../bootstrap/js/bootstrap-scrollspy.js
#= require ../bootstrap/js/bootstrap-tab.js
#= require ../bootstrap/js/bootstrap-tooltip.js
#= require ../bootstrap/js/bootstrap-popover.js
#= require ../bootstrap/js/bootstrap-alert.js
#= require ../bootstrap/js/bootstrap-button.js
#= require ../bootstrap/js/bootstrap-collapse.js
#= require ../bootstrap/js/bootstrap-carousel.js
#= require ../bootstrap/js/bootstrap-typeahead.js
#= require ../bootstrap/js/bootstrap-affix.js
#= require flash

fire = {}

class SplashView extends Backbone.View
  template: _.template($("#splashTemplate").html())
  events:
    "submit #new_firestarter_form": "createFirestarter"
    "click #id_public": "setPublicness"
    "keyup  #id_slug": "displayURL"
    "change #id_slug": "displayURL"

  render: =>
    @$el.html(@template())
    @initializeURL()
    @displayURL()

  setPublicness: (event) =>
    checked = @$("#id_public").is(":checked")

  displayURL: =>
    val = @$("#id_slug").val()
    val = encodeURIComponent(val)
    if val
      @$(".firestarter-url").html(
        window.location.protocol + "//" + window.location.host + "/f/" + val
      )
    else
      @$(".firestarter-url").html("")

  initializeURL: =>
    fire.socket.once "unused_slug", (data) =>
      @$("#id_slug").val(data.slug)
      @displayURL()
    fire.socket.emit "get_unused_slug", {callback: "unused_slug"}

  createFirestarter: (event) =>
    event.preventDefault()
    @$("#new_firestarter_form .error").removeClass("error")
    @$("#new_firestarter_form .error-msg").remove()
    @$("input[type=submit]").addClass("loading")

    fire.socket.once "create_firestarter", (data) =>
      @$("input[type=submit]").removeClass("loading")
      if data.error?
        if data.type == "ValidationError"
          for error in data.error
            console.log error
            @$("#id_#{error.field}").parentsUntil(
              ".control-group").parent().addClass("error")
            @$("#id_#{error.field}").after(
              "<span class='help-inline error-msg'>#{error.message}</span>"
            )
        else
          alert("Unexpected server error! Oh fiddlesticks!")
      else
        fire.model = data.model
        fire.app.navigate("/f/#{encodeURIComponent(fire.model.slug)}", {trigger: true})

    fire.socket.emit "create_firestarter", {
      callback: "create_firestarter"
      model: {
        name: @$("#id_name").val()
        prompt: @$("#id_prompt").val()
        slug: @$("#id_slug").val()
        public: @$("#id_public").val()
      }
    }

class RoomWithAView extends Backbone.View
  template: _.template $("#firestarterTemplate").html()
  responseTemplate: _.template $("#responseTemplate").html()

  initialize: (options) ->
    fire.socket.on "firestarter", @updateFirestarter
    fire.socket.on "response", @updateResponse
    unless fire.model? and fire.model.slug == options.slug
      fire.socket.emit "get_firestarter", {slug: options.slug}

  updateFirestarter: (data) =>
    fire.model = data
    @$(".name").html(data.name)
    @$(".prompt").html(data.prompt)
    for response in data.responses
      @updateResponse(response)
  
  updateResponse: (data) =>

  render: =>
    @$el.html(@template())



class Router extends Backbone.Router
  routes:
    'f/:room': 'room'
    '':        'index'

  index: ->
    view = new SplashView()
    $("#app").html(view.el)
    view.render()

  room: (roomName) ->
    slug = decodeURIComponent(roomName)

    # Disconnect from previous room, if any.
    if fire.slug?
      socket.emit("leave", {room: slug})
    socket.removeAllListeners("firestarter")
    socket.removeAllListeners("response")

    # Connect to new room.
    fire.slug = slug
    socket.emit("join", {room: slug})
    view = new RoomWithAView({slug: slug})
    $("#app").html(view.el)
    view.render()

socket = io.connect("/iorooms")
socket.on "error", (data) ->
  alert("Oh hai, the server has ERRORed. Oh noes!")
  window.console?.log?(error)

socket.on "connect", ->
  fire.socket = socket
  unless fire.started == true
    fire.app = new Router()
    Backbone.history.start(pushState: true, silent: false)
    fire.started = true
