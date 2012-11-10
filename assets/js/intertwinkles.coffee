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
intertwinkles.users = null  # map of intertwinkles_user_id to user data
intertwinkles.groups = null # map of group_id to group data
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
      console.log(data)
      if not data.error? and data.email
        intertwinkles.users = data.groups.users
        intertwinkles.groups = data.groups.groups
        user = _.find intertwinkles.users, (e) -> e.email == data.email
        if user?
          intertwinkles.user.set(user)
        else
          intertwinkles.user.clear()

      if data.error?
        navigator.id.logout()
        flash "error", data.error or "Error signing in."

    if intertwinkles.socket?
      # Use socket if we have one...
      intertwinkles.socket.once "login", handle
      intertwinkles.socket.emit "verify", {callback: "login", assertion: assertion}
    else
      # Otherwise use ajax.
      $.ajax {
        url: "/verify"
        type: 'POST'
        data: {assertion: encodeURIComponent(assertion)}
        success: handle
        error: (err) ->
          flash "error", "Server OH NOES ERROR!!"
          console.log(err)
      }

  onlogout: ->
    console.log "onlogout"
    reload = intertwinkles.user.get("id")?
    handler = -> if reload then window.location.pathname = "/"
    intertwinkles.users = null
    intertwinkles.groups = null
    intertwinkles.user.clear()
    if intertwinkles.socket?
      intertwinkles.socket.once "logout", handler
      intertwinkles.socket.emit "logout", {callback: "logout"}
    else
      $.ajax {
        url: "/logout"
        type: "GET"
        success: handler
        error: (err) -> flash "error", "Server OH NOES ERROR!!one"
      }
}

#
# User UI
#

user_menu_template = "
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
      <li><a tabindex='-1' href='#'>Settings</a></li>
      <li><a class='sign-out' href='#'>Sign out</a></li>
    </ul>
  </div>
"
class intertwinkles.UserMenu extends Backbone.View
  template: _.template(user_menu_template)
  events:
    'click .sign-out': 'signOut'

  initialize: ->
    intertwinkles.user.on "change", @render

  render: =>
    @$el.html(@template(user: intertwinkles.user.toJSON()))

  signOut: =>
    navigator.id?.logout()

toolbar_template = "
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
"

class intertwinkles.Toolbar extends Backbone.View
  template: _.template(toolbar_template)
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

