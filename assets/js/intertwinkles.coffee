#= require vendor/jquery
#= require vendor/underscore
#= require vendor/underscore-autoescape
#= require vendor/backbone
#= require ../bootstrap/js/bootstrap-transition.js
#= require ../bootstrap/js/bootstrap-dropdown.js
#= require flash

window.intertwinkles = intertwinkles = {}
class intertwinkles.User extends Backbone.Model
  idAttribute: "id"

#
# Initial globals
#
intertwinkles.user = new intertwinkles.User()
intertwinkles.users = null  # map of intertwinkles user_id to user data
intertwinkles.groups = null # list of groups
if INITIAL_DATA.groups?
  intertwinkles.users = INITIAL_DATA.groups.users
  intertwinkles.groups = INITIAL_DATA.groups.groups
  user = _.find intertwinkles.users, (e) -> e.email == INITIAL_DATA.email
  if user? then intertwinkles.user.set(user)

#
# Persona handlers
#
navigator.id?.watch {
  onlogin: (assertion) ->
    console.log "onlogin"
    handle = (data) ->
      if not data.error? and data.email
        intertwinkles.users = data.groups.users
        intertwinkles.groups = data.groups.groups
        user = _.find intertwinkles.users, (e) -> e.email == data.email
        if user?
          intertwinkles.user.set(user)
        else
          intertwinkles.user.clear()
      
      if _.contains data.messages, "NEW_ACCOUNT"
        modal = $(new_account_template())
        $("body").append(modal)
        modal.modal('show')

      if data.error?
        navigator.id.logout()
        flash "error", data.error or "Error signing in."

    socket_ready = setInterval ->
      if intertwinkles.socket?
        clearInterval(socket_ready)
        intertwinkles.socket.once "login", handle
        intertwinkles.socket.emit "verify", {callback: "login", assertion: assertion}
    , 50

  onlogout: () ->
    console.log "onlogout"
    reload = intertwinkles.user.get("id")?
    intertwinkles.users = null
    intertwinkles.groups = null
    intertwinkles.user.clear()
    socket_ready = setInterval ->
      if intertwinkles.socket?
        clearInterval(socket_ready)
        intertwinkles.socket.once "logout", -> if reload then window.location.pathane = "/"
        intertwinkles.socket.emit "logout", {callback: "logout"}
    , 50
}

new_account_template = _.template("
  <div class='modal hide fade'>
    <div class='modal-header'>
      <button type='button' class='close' data-dismiss='modal' aria-hidden='true'>&times;</button>
      <h3>Account created</h3>
    </div>
    <div class='modal-body'>
      <p>
      Your new account for the login &ldquo;<%= intertwinkles.user.get('email') %>&rdquo; was created, and you've been given the random icon and name:
      <blockquote>
        <img src='<%= intertwinkles.user.get('icon').small %>' /> <%= intertwinkles.user.get('name') %>
      </blockquote>
      <p>Edit your settings to choose better ones!</p>
      <a class='btn' href='<%= INTERTWINKLES_BASE_URL %>/profiles/edit'>Edit settings</a>
    </div>
    <div class='modal-footer'>
      <a href='#' class='btn' data-dismiss='modal'>Close</a>
    </div>
  </div>
")

#
# User UI
#

user_menu_template = _.template("
  <div class='btn-group'>
    <a class='btn user-menu dropdown-toggle' href='#' data-toggle='dropdown'>
      <% if (user.icon && user.icon.small) { %>
        <img src='<%= user.icon.small %>' alt='<%= user.icon.color %> <%= user.icon.name %>' />
      <% } else { %>
        <i class='icon-user'></i>
      <% } %>
      <%= user.name %>
      <span class='caret'></span>
    </a>
    <ul class='dropdown-menu' role='menu'>
      <li><a tabindex='-1' href='<%= INTERTWINKLES_BASE_URL %>/profiles/edit'>Settings</a></li>
      <li><a class='sign-out' href='#'>Sign out</a></li>
    </ul>
  </div>
")
class intertwinkles.UserMenu extends Backbone.View
  template: user_menu_template
  events:
    'click .sign-out': 'signOut'

  initialize: ->
    intertwinkles.user.on "change", @render

  render: =>
    @$el.html(@template(user: intertwinkles.user.toJSON()))

  signOut: (event) =>
    event.preventDefault()
    navigator.id.logout()

toolbar_template = _.template("
  <div class='navbar navbar-top nav'>
    <div class='navbar-inner'>
      <div class='container-fluid'>

        <a class='brand' href='/'>
          Inter<span class='intertwinkles'>Twinkles</span>:
          <span class='appname'><%= appname %></span>
          <span class='label' style='font-size: 50%;'>BETA</span>
        </a>
        <div class='pull-right'>
          <span class='authentication'></span>
        </div>
      </div>
    </div>
  </div>
")

class intertwinkles.Toolbar extends Backbone.View
  template: toolbar_template
  initialize: (options={}) ->
    @appname = options.appname

  render: =>
    @$el.html(@template(appname: @appname))
    sign_in = new intertwinkles.SignInView()
    @$(".authentication").html(sign_in.el)
    sign_in.render()
    this

class intertwinkles.SignInView extends Backbone.View
  tagName: "span"
  events:
    'click .sign-in': 'signIn'

  initialize: (options={}) ->
    intertwinkles.user.on "change", @render

  render: =>
    if intertwinkles.user.get("email")
      menu = new intertwinkles.UserMenu()
      @$el.html(menu.el)
      menu.render()
    else
      @$el.html("
        <a href='#' class='sign-in'>
          <img src='/img/signin.png' alt='Sign in'/>
        </a>
      ")

  signIn: =>
    navigator.id.request()

user_choice_template = _.template("
  <input type='text' name='name' id='id_user' data-provide='typeahead' value='<%= name %>' />
  <span class='icon-holder' style='width: 32px; display: inline-block;'>
    <% if (icon) { %><img src='<%= icon %>' /><% } %>
  </span>
  <input type='hidden' name='user_id' id='id_user_id' value='<%= user_id %>' />
")

class intertwinkles.UserChoice extends Backbone.View
  tagName: "span"
  template: user_choice_template
  initialize: (options={}) ->
    intertwinkles.user.on "change", @render
  events:
    'keydown input': 'keyup'

  initialize: (options={}) ->
    @model = options.model or {}

  render: =>
    @$el.html(@template({
      name: @model.name or ""
      user_id: @model.id or ""
      icon: if @model.icon?.small then @model.icon.small or ""
    }))

    @$("#id_user").typeahead {
      source: @source
      matcher: @matcher
      sorter: @sorter
      updater: @updater
      highlighter: @highlighter
    }
    this

  keyup: (event) =>
    if @$("#id_user").val() != @model.name
      @$(".icon-holder").html("")
      @$("#id_user_id").val("")

  source: (query) ->
    return ("#{id}" for id,u of intertwinkles.users)

  matcher: (item) ->
    return intertwinkles.users[parseInt(item)].name.toLowerCase().indexOf(@query.toLowerCase()) != -1

  sorter: (items) ->
    return _.sortBy items, (a) -> intertwinkles.users[parseInt(a)].name

  updater: (item) =>
    @$("#id_user_id").val(item)
    user = intertwinkles.users[parseInt(item)]
    @model = user
    if user.icon?
      @$(".icon-holder").html("<img src='#{user.icon.small}' />")
    else
      @$(".icon-holder").html("")
    return intertwinkles.users[parseInt(item)].name

  highlighter: (item) ->
    user = intertwinkles.users[parseInt(item)]
    if user.icon?.small?
      img = "<img src='#{user.icon.small}' />"
    else
      img = "<span style='width: 32px; display: inline-block;'></span>"
    query = this.query.replace(/[\-\[\]{}()*+?.,\\\^$|#\s]/g, '\\$&')
    highlit = user.name.replace new RegExp('(' + query + ')', 'ig'), ($1, match) ->
      return '<strong>' + match + '</strong>'
    return "<span>#{img} #{highlit}</span>"



#
# Group UI
#

group_choice_template = _.template("
  <% if (intertwinkles.user.id) { %>
    <% if (intertwinkles.groups.length > 0) { %>
      <select id='id_group'>
        <option value=''>----</option>
        <% for (var i = 0; i < intertwinkles.groups.length; i++) { %>
          <% group = intertwinkles.groups[i]; %>
          <option val='<%= group.id %>'><%= group.name %></option>
        <% } %>
    <% } else { %>
      You don't have any groups yet.
    <% } %>
    <a class='btn' href'<%= INTERTWINKLES_BASE_URL %>/groups/edit'> Add a group</a>
    <span class='help-text'>Optional</span>
  <% } else { %>
    <a class='sign-in' href='#'>
      <img src='/img/signin.png', alt='Sign in' />
    </a> to add a group
  <% } %>
")

class intertwinkles.GroupChoice extends Backbone.View
  tagName: "span"
  template: group_choice_template
  initialize: (options={}) ->
  render: =>
    @$el.html(@template())
    this

