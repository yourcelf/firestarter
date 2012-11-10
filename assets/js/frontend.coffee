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
#= require ./flash
#= require ./intertwinkles

fire = {}

$("header").html(new intertwinkles.Toolbar(appname: "Firestarter").render().el)

Backbone.Model.prototype.idAttribute = "_id"
class Firestarter extends Backbone.Model
class Response extends Backbone.Model
class ResponseCollection extends Backbone.Collection
  model: Response

class SplashView extends Backbone.View
  template: _.template($("#splashTemplate").html())
  groupControlsTemplate: _.template($("#newFirestarterGroupControl").html())
  events:
    "submit #new_firestarter_form": "createFirestarter"
    "keyup  #id_slug": "displayURL"
    "change #id_slug": "displayURL"
    "click .sign-in": "signIn"

  initialize: ->
    intertwinkles.user.on "change", @renderGroupControls

  signIn: ->
    navigator.id.request()

  render: =>
    @$el.html(@template())
    @renderGroupControls()

    @initializeURL()
    @displayURL()

  renderGroupControls: =>
    @$("#group_controls").html(@groupControlsTemplate())

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
            @$("#id_#{error.field}").parentsUntil(
              ".control-group").parent().addClass("error")
            @$("#id_#{error.field}").after(
              "<span class='help-inline error-msg'>#{error.message}</span>"
            )
        else
          alert("Unexpected server error! Oh fiddlesticks!")
      else
        @$("#newFirestarterModal").modal('hide')
        responses = data.model.responses
        delete data.model.responses
        fire.model = new Firestarter(data.model)
        fire.responses = new ResponseCollection
        for response in responses
          fire.responses.add(new Response(response))
        fire.app.navigate("/f/#{encodeURIComponent(fire.model.get("slug"))}", {trigger: true})

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
  events:
    'click #add_response': 'showAddResponseForm'

  initialize: (options) ->
    if not fire.model?
      fire.model = new Firestarter()
    if not fire.responses?
      fire.responses = new ResponseCollection()
    @responseViews = []

    fire.socket.on "firestarter", (data) =>
      fire.model.set(data)

    fire.socket.on "response", (data) =>
      response = fire.responses.get(data._id)
      if not response?
        responses.add(new Response(data))
      else
        response.set(data)
        @addResponse(response)

    fire.model.on "change", @updateFirestarter
    fire.responses.on "add", @addResponse
    fire.responses.on "remove", @removeResponse

    unless fire.model.get("slug") == options.slug
      fire.socket.emit "get_firestarter", {slug: options.slug}

  updateFirestarter: =>
    @$(".first-loading").hide()
    @$(".name").html(fire.model.get("name"))
    @$(".prompt").html(fire.model.get("prompt"))
    @$(".date").html(fire.model.get("date")) # FIXME

  showAddResponseForm: (event) =>
    event.preventDefault()
    @$("#add_response").hide()
    editor = new EditResponseView()
    @$(".add-response-holder").html(editor.el)
    editor.render()
    editor.on "save", (model) =>
      fire.socket.emit "add_response", {model: model.toJSON()}
      fire.responses.add(model)
      editor.remove()

  addResponse: (response) =>
    view = new ResponseView(model: response)
    @$(".responses").append(view.el)
    view.render()
    @responseViews.add(view)

  removeResponse: (response) =>
    for view in @responseViews
      if view.model.id == response.id
        view.remove()
        @responseViews = _.reject @responseViews, (a) -> a.model.id == response.id
        return

  render: =>
    @$el.html(@template())
    if @my_response?
      @$(".edit-response-holder").hide()
    if fire.model?
      @updateFirestarter()
    if fire.responses?
      for response in fire.responses
        @addResponse(response)

class EditResponseView extends Backbone.View
  template: _.template $("#editResponseTemplate").html()
  events:
    'submit #edit_response_form': 'saveResponse'

  initialize: (options={}) =>
    @model = options.model or new Response()

  render: =>
    context = _.extend({
      response: ""
    }, @model.toJSON())
    @$el.html @template(context)

  saveResponse: (event) =>
    event.preventDefault()
    @$("#edit_response_form input[type=submit]").addClass("loading")

class ShowResponseView extends Backbone.View
  template: _.template $("#responseTemplate").html()

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
    if fire.model?
      socket.emit("leave", {room: fire.model.get("slug")})
      delete fire.model
    if fire.responses?
      delete fire.responses
    socket.removeAllListeners("firestarter")
    socket.removeAllListeners("response")

    # Connect to new room.
    socket.emit("join", {room: slug})
    view = new RoomWithAView({slug: slug})
    $("#app").html(view.el)
    view.render()

socket = io.connect("/iorooms")
socket.on "error", (data) ->
  flash("error", "Oh hai, the server has ERRORed. Oh noes!")
  window.console?.log?(data.error)

socket.on "connect", ->
  fire.socket = socket
  intertwinkles.socket = socket
  unless fire.started == true
    fire.app = new Router()
    Backbone.history.start(pushState: true, silent: false)
    fire.started = true
