#= require vendor/jquery
#= require vendor/underscore
#= require vendor/underscore-autoescape
#= require vendor/backbone
#= require vendor/jquery-ui-1.9.1.custom
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

class Firestarter extends Backbone.Model
  idAttribute: "_id"
class Response extends Backbone.Model
  idAttribute: "_id"
class ResponseCollection extends Backbone.Collection
  model: Response
  comparator: (r) ->
    return (new Date(r.get("created")).getTime())


load_firestarter_data = (data) ->
  if not fire.responses?
    fire.responses = new ResponseCollection()
  if data.responses?
    while fire.responses.pop()
      null
    for response in data.responses
      fire.responses.add(new Response(response))
    data.responses = (a._id for a in data.responses)
  if not fire.model?
    fire.model = new Firestarter()
  fire.model.set(data)

#
# Load initial data if any
#
if INITIAL_DATA.firestarter?
  load_firestarter_data(INITIAL_DATA.firestarter)

class SplashView extends Backbone.View
  template: _.template($("#splashTemplate").html())
  events:
    "click .new-firestarter": "newFirestarter"

  render: =>
    @$el.html(@template())

  newFirestarter: (event) =>
    event.preventDefault()
    fire.app.navigate("/new", {trigger: true})

class AddFirestarterView extends Backbone.View
  template: _.template($("#addFirestarterTemplate").html())
  events:
    "submit #new_firestarter_form": "createFirestarter"
    "keyup  #id_slug": "displayURL"
    "change #id_slug": "displayURL"
    "click .sign-in": "signIn"

  initialize: ->
    intertwinkles.user.on "change", @renderGroupControls

  render: =>
    @$el.html(@template())
    @renderGroupControls()

    @initializeURL()
    @displayURL()

  renderGroupControls: =>
    view = new intertwinkles.GroupChoice()
    @$("#group_controls").html(view.el)
    view.render()

  signIn: ->
    navigator.id.request()

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
        load_firestarter_data(data.model)
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



class ShowFirestarter extends Backbone.View
  template: _.template $("#firestarterTemplate").html()
  events:
    'click #add_response': 'showAddResponseForm'
    'click .edit-name':    'editName'
    'click .edit-prompt':  'editPrompt'
    'click #id_save_name': 'saveName'
    'click #id_save_prompt': 'savePrompt'

  initialize: (options) ->
    if not fire.model?
      fire.model = new Firestarter()
    if not fire.responses?
      fire.responses = new ResponseCollection()
    @responseViews = []

    @roomUsersMenu = new intertwinkles.RoomUsersMenu({room: options.slug})

    fire.socket.on "firestarter", (data) =>
      console.log "on firestarter", data
      if data.model?
        load_firestarter_data(data.model)

    fire.socket.on "response", (data) =>
      console.log "on response", data
      response = fire.responses.get(data._id)
      if not response?
        response = new Response(data.model)
        fire.responses.add(response)
      else
        response.set(data)

    fire.socket.on "delete_response", (data) =>
      console.log "on delete_response", data
      fire.responses.remove(fire.responses.get(data.model._id))

    fire.model.on "change", @updateFirestarter
    fire.responses.on "add", @addResponseView
    fire.responses.on "remove", @removeResponseView

    unless fire.model.get("slug") == options.slug
      fire.socket.emit "get_firestarter", {slug: options.slug}

  remove: =>
    @roomusersMenu.remove()
    fire.socket.removeAllListeners("firestarter")
    fire.socket.removeAllListeners("response")
    fire.socket.removeAllListeners("delete_response")
    delete fire.model
    if fire.responses?
      delete fire.responses
    super()

  editName: (event) =>
    event.preventDefault()
    @$(".edit-name-modal").modal('show').on 'shown', =>
      @$("#id_firestarter_name").focus()
    @$("#id_firestarter_name").val(fire.model.get("name"))

  saveName: (event) =>
    event.preventDefault()
    val = @$("#id_firestarter_name").val()
    @$("#id_save_name").addClass("loading")
    done = =>
      @$("#id_save_name").removeClass("loading")
      @$(".edit-name-modal").modal('hide')

    if val != fire.model.get("name")
      @editFirestarter({name: val}, done)
    else
      done()

  editPrompt: (event) =>
    event.preventDefault()
    @$(".edit-prompt-modal").modal('show').on 'shown', =>
      @$("#id_firestarter_prompt").focus()
    @$("#id_firestarter_prompt").val(fire.model.get("prompt"))

  savePrompt: (event) =>
    event.preventDefault()
    val = @$("#id_firestarter_prompt").val()
    @$("#id_save_prompt").addClass("loading")
    done = =>
      @$("#id_save_prompt").removeClass("loading")
      @$(".edit-prompt-modal").modal('hide')
    if val != fire.model.get("prompt")
      @editFirestarter({prompt: val}, done)
    else
      done()

  editFirestarter: (updates, cb) =>
    fire.socket.once 'firestarter_edited', (data) =>
      if data.error?
        flash "error", "Oh no!  Survur Urrur!"
        console.log(data.error)
      else
        fire.model.set(data.model)
      cb()
    fire.socket.emit "edit_firestarter", {
      callback: 'firestarter_edited'
      model: _.extend({
        _id: fire.model.get("_id")
      }, updates)
    }

  updateFirestarter: =>
    @$(".first-loading").hide()
    @$(".firestarter-name").html(fire.model.get("name"))
    @$(".firestarter-prompt").html(fire.model.get("prompt"))
    @$(".firestarter-date").html(
      new Date(fire.model.get("created")).toString("htt dddd, MMMM dd, yyyy")
    )

  showAddResponseForm: (event) =>
    event.preventDefault()
    @editResponse(new Response())

  editResponse: (response) =>
    editor = new EditResponseView(model: response)
    @$(".add-response-holder").html(editor.el)
    editor.render()
    @$(".add-response-holder").modal('show').on("shown", -> $("#id_user").focus())
    editor.on "done", =>
      @$(".add-response-holder").modal('hide')

  addResponseView: (response) =>
    view = new ShowResponseView(response: response)
    @$(".responses").prepend(view.el)
    view.render()
    view.on "edit", =>
      @editResponse(response)
    view.on "delete", =>
      fire.socket.once "response_deleted", (data) ->
        if data.error?
          flash "error", "Oh No! Server fail..."
          console.log(data.error)
        else
          fire.responses.remove(response)
          fire.model.set({
            responses: _.reject(fire.model.get("responses"), (r) -> r.id == response.id)
          })
      fire.socket.emit "delete_response", {
        callback: "response_deleted"
        model: response.toJSON()
      }

    @responseViews.push(view)

  removeResponseView: (model) =>
    for view in @responseViews
      if view.response.get("_id") == model.get("_id")
        do (view) ->
          view.$el.fadeOut 800, ->
            @responseViews = _.reject @responseViews, (v) ->
              v.response.get("_id") == model.get("_id")
            view.remove()
            return

  render: =>
    @$el.html(@template())
    if fire.model?
      @updateFirestarter()
    if fire.responses?
      for response in fire.responses.models
        @addResponseView(response)
    $("header .room-users").html(@roomUsersMenu.el)
    @roomUsersMenu.render()

class EditResponseView extends Backbone.View
  template: _.template $("#editResponseTemplate").html()
  events:
    'submit #edit_response_form': 'saveResponse'
    'click .cancel': 'cancel'

  initialize: (options={}) =>
    @model = options.model or new Response()

  cancel: =>
    @trigger "done"

  render: =>
    context = _.extend({
      response: ""
    }, @model.toJSON())
    context.verb = if @model.get("_id") then "Save" else "Add"
    @$el.html @template(context)

    user_choice = new intertwinkles.UserChoice(model: @model)
    @$("#name_controls").html user_choice.el
    user_choice.render()

  saveResponse: (event) =>
    event.preventDefault()
    @$("#edit_response_form input[type=submit]").addClass("loading")
    @$(".error").removeClass("error")
    @$(".error-msg").remove()
    errors = false

    name = @$("#id_user").val()
    if not name
      @$("#id_user").parentsUntil(".control-group").parent().addClass("error")
      @$("#id_user").append("<span class='help-text error-msg'>This field is required</span>")
      errors = true
    response = @$("#id_response").val()
    if not response
      @$("#id_response").parentsUntil(".control-group").parent().addClass("error")
      @$("#id_response").append("<span class='help-text error-msg'>This field is required</span>")
      errors = true

    if errors
      @$("#edit_response_form input[type=submit]").removeClass("loading")
    else
      updates = {
        _id: @model.get("_id")
        user_id: @$("#id_user_id").val()
        name: name
        response: response
        firestarter_id: fire.model.id
      }
      fire.socket.once "response_saved", (data) =>
        if data.error
          flash "error", "Oh noes. SERVER ERROR. !!"
          console.log data.error
        else
          add_it = not @model.get("_id")?
          @model.set(data.model)
          if add_it
            fire.responses.add(@model)
          @trigger "done"
      fire.socket.emit "save_response", { callback: "response_saved", model: updates }

class ShowResponseView extends Backbone.View
  template: _.template $("#responseTemplate").html()
  events:
    'click .really-delete': 'deleteResponse'
    'click .delete': 'confirmDelete'
    'click .edit':   'editResponse'

  initialize: (options={}) ->
    @response = options.response
    @response.on "change", @render
    intertwinkles.user.on "change", @render

  render: =>
    @$el.addClass("firestarter-response")
    @$el.html(@template(@response.toJSON()))
    date = new intertwinkles.AutoUpdatingDate(@response.get("created"))
    @$(".date-holder").html date.el
    date.render()
    @$el.effect("highlight", {}, 3000)

  confirmDelete: (event) =>
    event.preventDefault()
    @$(".delete-confirmation").modal('show')

  deleteResponse: (event) =>
    event.preventDefault()
    @$(".delete-confirmation").modal('hide')
    @trigger "delete", @response

  editResponse: (event) =>
    event.preventDefault()
    @trigger "edit", @response

class Router extends Backbone.Router
  routes:
    'f/:room': 'room'
    'new':     'newFirestarter'
    '':        'index'

  index: =>
    @view?.remove()
    @view = new SplashView()
    $("#app").html(@view.el)
    @view.render()

  newFirestarter: =>
    @view?.remove()
    @view = new AddFirestarterView()
    $("#app").html(@view.el)
    @view.render()

  room: (roomName) =>
    @view?.remove()
    slug = decodeURIComponent(roomName)

    @view = new ShowFirestarter({slug: slug})
    $("#app").html(@view.el)
    @view.render()

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

