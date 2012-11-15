#= require vendor/jquery
#= require vendor/underscore
#= require vendor/underscore-autoescape
#= require vendor/backbone
#= require vendor/date.js
#= require ../bootstrap/js/bootstrap-transition.js
#= require ../bootstrap/js/bootstrap-dropdown.js
#= require flash
#= require urlize

window.intertwinkles = intertwinkles = {}
class intertwinkles.User extends Backbone.Model
  idAttribute: "id"

#
# User authentication state
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

request_logout = ->
  frame = $("#auth_frame")[0].contentWindow
  frame.postMessage {action: 'intertwinkles_logout'}, INTERTWINKLES_BASE_URL

onlogin = (assertion) ->
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
      request_logout()
      flash "error", data.error or "Error signing in."

  if intertwinkles.socket?
    socket_ready = setInterval ->
      clearInterval(socket_ready)
      intertwinkles.socket.once "login", handle
      intertwinkles.socket.emit "verify", {callback: "login", assertion: assertion}
    , 50

onlogout = ->
  console.log "onlogout"
  reload = intertwinkles.user.get("id")?
  intertwinkles.users = null
  intertwinkles.groups = null
  intertwinkles.user.clear()
  if intertwinkles.socket?
    socket_ready = setInterval ->
      clearInterval(socket_ready)
      intertwinkles.socket.once "logout", -> if reload then window.location.pathane = "/"
      intertwinkles.socket.emit "logout", {callback: "logout"}
    , 50

onmessage = (event) ->
  if event.origin == INTERTWINKLES_BASE_URL
    switch event.data.action
      when 'onlogin' then onlogin(event.data.assertion)
      when 'onlogout' then onlogout()
window.addEventListener('message', onmessage, false)

intertwinkles.auth_frame_template = _.template("<iframe id='auth_frame'
  src='#{INTERTWINKLES_BASE_URL}/api/auth_frame/'
  style='border: none; overflow: hidden;' width=97 height=29></iframe>")

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
        <img src='<%= intertwinkles.user.get('icon').small %>' />
        <%= intertwinkles.user.get('name') %>
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
# User menu
#

user_menu_template = _.template("
  <a class='user-menu dropdown-toggle' href='#' data-toggle='dropdown' role='button'>
    <% if (user.icon && user.icon.tiny) { %>
      <img src='<%= user.icon.tiny %>' alt='<%= user.icon.color %> <%= user.icon.name %>' />
    <% } else { %>
      <i class='icon-user'></i>
    <% } %>
    <span class='hidden-phone'>
      <%= user.name %>
    </span>
    <b class='caret'></b>
  </a>
  <ul class='dropdown-menu' role='menu'>
    <li><a tabindex='-1' href='<%= INTERTWINKLES_BASE_URL %>/profiles/edit'><i class='icon icon-cog'></i> Settings</a></li>
    <li class='divider'></li>
    <li><a class='sign-out' href='#'>Sign out</a></li>
  </ul>
")
class intertwinkles.UserMenu extends Backbone.View
  tagName: 'li'
  template: user_menu_template
  events:
    'click .sign-out': 'signOut'

  initialize: ->
    intertwinkles.user.on "change", @render

  render: =>
    @$el.addClass("dropdown")
    if intertwinkles.user.get("email")
      @$el.html(@template(user: intertwinkles.user.toJSON()))
    else
      @$el.html("")
    @setAuthFrameVisibility()

  setAuthFrameVisibility: =>
    if intertwinkles.user.get("email")
      $("#auth_frame").hide()
    else
      $("#auth_frame").show()

  signOut: (event) =>
    event.preventDefault()
    request_logout()

#
# Room users menu
#

room_users_menu_template = _.template("
  <a class='room-menu dropdown-toggle' href='#' data-toggle='dropdown'
     title='People in this room'>
    <i class='icon-user'></i><span class='count'></span>
    <b class='caret'></b>
  </a>
  <ul class='dropdown-menu' role='menu'></ul>
")
room_users_menu_item_template = _.template("
  <li class='<%= (self ? 'self' : '') %>'><a>
    <% if (icon) { %>
      <img src='<%= icon.small %>' />
    <% } else { %>
      <i class='icon icon-user'></i>
    <% } %>
    <%= name %>
  </a></li>
")

class intertwinkles.RoomUsersMenu extends Backbone.View
  tagName: "li"
  template: room_users_menu_template
  item_template: room_users_menu_item_template

  initialize: (options={}) ->
    @room = options.room
    intertwinkles.socket.on "room_users", @roomList
    intertwinkles.socket.emit "join", {room: @room}
    @list = []

  remove: =>
    intertwinkles.socket.removeListener "room_users", @roomList
    intertwinkles.socket.emit "leave", {room: @room}

  roomList: (data) =>
    @list = data.list
    if data.anon_id?
      @anon_id = data.anon_id
    @renderItems()
    
  render: =>
    @$el.addClass("room-users dropdown")
    @$el.html @template()
    @renderItems()

  renderItems: =>
    @$(".count").html(@list.length)
    @menu = @$(".dropdown-menu")
    @menu.html("")
    for item in @list
      self = item.anon_id == @anon_id
      context = _.extend {self}, item
      if self
        @menu.prepend(@item_template(context))
      else
        @menu.append(@item_template(context))
    @menu.prepend("<li><a>Online now:</a></li>")

#
# Toolbar
#

intertwinkles.build_toolbar = (destination, options) ->
  toolbar = new intertwinkles.Toolbar(options)
  $(destination).html(toolbar.el)
  toolbar.render()
  $(".auth_frame").html(intertwinkles.auth_frame_template())
  toolbar.setAuthFrameVisibility()

toolbar_template = _.template("
  <div class='navbar navbar-top nav'>
    <div class='navbar-inner'>
      <div class='container-fluid'>
        <a class='brand visible-phone' href='/'>
          I<span class='intertwinkles'>T</span>
          <span class='appname'><%= appname.substr(0, 1) %></span>
          <span class='label' style='font-size: 50%;'>B</span>
        </a>
        <a class='brand hidden-phone' href='/'>
          Inter<span class='intertwinkles'>Twinkles</span>:
          <span class='appname'><%= appname %></span>
          <span class='label' style='font-size: 50%;'>BETA</span>
        </a>
        <ul class='nav pull-right'>
          <li class='notifications dropdown'></li>
          <li class='room-users dropdown'></li>
          <li class='user-menu dropdown'></li>
          <li class='auth_frame'></li>
        </ul>
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
    @user_menu = new intertwinkles.UserMenu()
    @$(".user-menu.dropdown").replaceWith(@user_menu.el)
    @user_menu.render()
    this

  setAuthFrameVisibility: => @user_menu.setAuthFrameVisibility()

#
# Footer
#

footer_template = _.template("
<div class='bg'>
  <img src='#{INTERTWINKLES_BASE_URL}/static/img/coop-world.png' alt='Flavor image' />
</div>
<div class='container-fluid'>
  <div class='ramp'></div>
  <div class='footer-content'>
    <div class='row-fluid'>
      <div class='span4 about-links'>
        <h2>About</h2>
        <ul>
          <li><a href='#{INTERTWINKLES_BASE_URL}/about/'>About</a><small>: Free software revolutionary research</small></li>
          <li><a href='#{INTERTWINKLES_BASE_URL}/about/terms/'>Terms of Use</a><small>: Play nice</small></li>
          <li><a href='#{INTERTWINKLES_BASE_URL}/about/privacy/'>Privacy Policy</a><small>: You own it</small></li>
          <li><a href='http://bitbucket.org/yourcelf/intertwinkles/'>Source Code</a><small>: Run your own!</small></li>
        </ul>
      </div>
      <div class='span4 community'>
        <h2>Community</h2>
        <ul>
          <li><a href='http://lists.byconsens.us/mailman/listinfo/design'>Codesign mailing list</a></li>
          <li><a href='http://project.intertwinkles.org/'>Project tracker</a></li>
          <li><a href='http://#{INTERTWINKLES_BASE_URL}/about/related/'>Related projects</a></li>
        </ul>
      </div>
      <div class='span4 sponsors'>
        <h2>Supported by</h2>
        <a href='http://civic.mit.edu'>
          <img alt='The MIT Center for Civic Media' src='#{INTERTWINKLES_BASE_URL}/static/img/C4CM.png'>
        </a>
        and
        <a href='http://media.mit.edu/speech'>
          <img alt='The Speech + Mobility Group' src='#{INTERTWINKLES_BASE_URL}/static/img/S_M.png'>
        </a>
      </div>
    </div>
  </div>
</div>
")

intertwinkles.build_footer = (destination) ->
  $(destination).html(footer_template())


#
# User choice widget
#

user_choice_template = _.template("
  <input type='text' name='name' id='id_user' data-provide='typeahead' autocomplete='off' value='<%= name %>' />
  <span class='icon-holder' style='width: 32px; display: inline-block;'>
    <% if (icon) { %><img src='<%= icon %>' /><% } %>
  </span>
  <input type='hidden' name='user_id' id='id_user_id' value='<%= user_id %>' />
")

class intertwinkles.UserChoice extends Backbone.View
  tagName: "span"
  template: user_choice_template
  events:
    'keydown input': 'keyup'

  initialize: (options={}) ->
    @model = options.model or {}
    intertwinkles.user.on "change", @render

  render: =>
    user_id = @model.get("user_id")
    if user_id and intertwinkles.users?[user_id]?
      name = intertwinkles.users[user_id].name
      icon = intertwinkles.users[user_id].icon
    else
      user_id = ""
      name = @model.get("name") or ""
      icon = {}

    @$el.html(@template({
      name: name
      user_id: user_id
      icon: if icon.small? then icon.small else ""
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
# Group choice widget
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
    Sign in to add a group.
  <% } %>
")

class intertwinkles.GroupChoice extends Backbone.View
  tagName: "span"
  template: group_choice_template
  initialize: (options={}) ->
  render: =>
    @$el.html(@template())
    this

#
# Utilities
#

class intertwinkles.AutoUpdatingDate extends Backbone.View
  tagName: "span"
  initialize: (datetime) ->
    if typeof(datetime) == "object"
      @date = datetime
    else
      @date = new Date(datetime)
    @interval = setInterval @render, 60000
    @$el.addClass("date")

  render: =>
    now = new Date()
    date = @date
    if now.getFullYear() != date.getFullYear()
      str = date.toString("MMM d, YYYY")
    else if now.getMonth() != date.getMonth() or now.getDate() != date.getDate()
      str = date.toString("MMM d")
    else
      diff = now.getTime() - date.getTime()
      seconds = diff / 1000
      if seconds > (60 * 60)
        str = parseInt(seconds / 60 / 60) + "h"
      else if seconds > 60
        str = parseInt(seconds / 60) + "m"
      else
        str = parseInt(seconds) + "s"
    @$el.attr("title", date.toString("dddd, MMMM dd, yyyy h:mm:ss tt"))
    @$el.html(str)

intertwinkles.inline_user = (user_id, name) ->
  user = intertwinkles.users?[user_id]
  if user?
    return "<img src='#{_.escapeHTML(user.icon.small)}' /> #{_.escapeHTML(user.name)}"
  else
    return "<span style='width: 32px;'><i class='icon icon-user'></i></span> #{name}"

intertwinkles.markup = (response) ->
  return urlize(response, 50, true, _.escapeHTML)

$(document).ready ->
  $("span.intertwinkles").on "mouseover", ->
    $el = $(this)
    unless $el.hasClass("twunkled")
      $el.addClass("twunkled")
      letters = $el.text()
      spans = []
      for i in [0...letters.length]
        spans.push("<span>#{letters.substr(i, 1)}</span>")
      $el.html(spans.join(""))
    $el.find("span").each (i, el)->
      setTimeout( ->
        el.className = "bump"
        setTimeout((-> el.className = ""), 100)
      , i * 50)

  $(".modal-video").on "click", ->
    width = parseInt($(this).attr("data-width"))
    height = parseInt($(this).attr("data-height"))
    mod = $("<div class='modal' role='dialog'></div>").css {
      display: "none"
      width: "#{width + 10}px"
      height: "#{height + 10}px"
      "background-color": "black"
      "text-align": "center"
      padding: "5px 5px 5px 5px"
    }
    mod.append("<iframe width='#{width}' height='#{height}' src='#{$(this).attr("data-url")}?autoplay=1&cc_load_policy=1' frameborder='0' allowfullscreen></iframe>")
    $("body").append(mod)
    mod.on('hidden', -> mod.remove())
    mod.modal()
    return false

