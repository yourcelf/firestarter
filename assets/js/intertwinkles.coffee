#= require vendor/jquery
#= require vendor/underscore
#= require vendor/underscore-autoescape
#= require vendor/backbone
#= require vendor/date.js
#= require vendor/jscolor/jscolor.js
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

intertwinkles.request_logout = ->
  frame = $("#auth_frame")[0].contentWindow
  frame.postMessage {action: 'intertwinkles_logout'}, INTERTWINKLES_BASE_URL

onlogin = (assertion) ->
  console.log "onlogin"
  handle = (data) ->
    old_user = intertwinkles.user?.get("email")
    if not data.error? and data.email
      intertwinkles.users = data.groups.users
      intertwinkles.groups = data.groups.groups
      user = _.find intertwinkles.users, (e) -> e.email == data.email
      if user?
        intertwinkles.user.set(user)
      else
        intertwinkles.user.clear()
    
      if _.contains data.messages, "NEW_ACCOUNT"
        #modal = $(new_account_template())
        #$("body").append(modal)
        #modal.modal('show')
        profile_editor = new intertwinkles.EditNewProfile()
        $("body").append(profile_editor.el)
        profile_editor.render()
        profile_editor.on "done", -> profile_editor.remove()
      else if old_user != intertwinkles.user.get("email")
        flash "info", "Welcome, #{intertwinkles.user.get("name")}"

    if data.error?
      intertwinkles.request_logout()
      flash "error", data.error or "Error signing in."

  if intertwinkles.socket?
    socket_ready = setInterval ->
      clearInterval(socket_ready)
      intertwinkles.socket.once "login", handle
      intertwinkles.socket.emit "verify", {callback: "login", assertion: assertion}
    , 50

onlogout = ->
  reload = intertwinkles.is_authenticated()
  intertwinkles.users = null
  intertwinkles.groups = null
  intertwinkles.user.clear()
  socket_ready = setInterval ->
    clearInterval(socket_ready)
    intertwinkles.socket.once "logout", -> if reload then window.location.pathname = "/"
    intertwinkles.socket.emit "logout", {callback: "logout"}
  , 50

onmessage = (event) ->
  if event.origin == INTERTWINKLES_BASE_URL
    switch event.data.action
      when 'onlogin' then onlogin(event.data.assertion)
      when 'onlogout' then onlogout()
window.addEventListener('message', onmessage, false)

intertwinkles.is_authenticated = ->
  return intertwinkles.user.get("email")?

#
# Authentication UI
#

intertwinkles.auth_frame_template = _.template("""<iframe id='auth_frame'
  src='#{INTERTWINKLES_BASE_URL}/api/auth_frame/'
  style='border: none; overflow: hidden;' width=97 height=29></iframe>""")

new_account_template = _.template("""
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
""")

edit_new_profile_template = _.template("""
  <div class='modal hide fade'>
    <div class='modal-body'>
      <h1 style='text-align: center;'>Ready in 1, 2, 3:</h1><br />
      <div class='control-group'>
        <b>1: What is your name?</b><br />
        <input type='text' name='name' value='<%= name %>' />
      </div>
      <div class='control-group'>
        <b>2: What is your favorite color?</b><br />
        <input type='text' name='color' value='<%= color %>' class='color' />
        <span class='help-text color-label'></span>
      </div>
      <div class='control-group'>
        <b>3. Which icon do you like the best?</b><br />
        <div class='image-chooser'></div>
      </div>
    </div>
    <div class='modal-footer'>
      <input type='submit' value='OK, Ready, Go!' class='btn btn-primary btn-large' />
    </div>
  </div>
""")

class intertwinkles.EditNewProfile extends Backbone.View
  template: edit_new_profile_template
  events:
    'click input[type=submit]': 'saveProfile'
  render: =>
    name = intertwinkles.user.get("name")
    icon = intertwinkles.user.get("icon")
    if icon?
      color = icon.color
      icon_id = icon.id
    else
      color = ""
      icon_id = ""
    @$el.html(@template({name, color}))
    chooser = new intertwinkles.IconChooser(chosen: icon_id)
    @$(".image-chooser").html(chooser.el)
    chooser.render()
    @$(".modal").modal("show")
    name_color = =>
      @$(".color-label").html(intertwinkles.match_color(@$(".color").val()))
    @$(".color").on "change", name_color
    name_color()

    # Make it bigger.
    #width = Math.max(@$(".modal").width(), $(window).width() * 0.8)
    #height = Math.max(@$(".modal").height(), $(window).height() * 0.8)
    #@$(".modal").css({
    #  width: width + "px"
    #  "margin-left": -(width / 2) + "px"
    #  "top": (height / 2) + "px"
    #})
    #@$(".modal-body").css({
    #  "max-height": (height - 48) + "px"
    #})
    this

  saveProfile: =>
    new_name = @$("input[name=name]").val()
    new_icon = @$("input[name=icon]").val()
    new_color = @$("input[name=color]").val()
    @$(".error-msg").remove()
    @$("input[type=submit]").addClass("loading")
    errors = []
    if not new_name
      errors.push({field: "name", message: "Please choose a name."})
    if not new_icon
      errors.push({field: "icon", message: "Please choose an icon."})
    if not new_color or not /[a-f0-9A-F]{6}/.exec(new_color)?
      errors.push({field: "color", message: "Invalid color..."})
    if errors.length != 0
      console.log errors
      for error in errors
        @$("input[name=#{error.field}]").parent().addClass("error")
        @$("input[name=#{error.field}]").after(
          "<span class='help-inline error-msg'>#{error.message}</span>"
        )
        @$("input[type=submit]").removeClass("loading")
    else
      intertwinkles.socket.once "profile_updated", (data) =>
        @$("input[type=submit]").removeClass("loading")
        if data.error?
          flash "error", "Oh Noes... Server errorrrrrrr........."
          console.log(data)
          @$(".modal").modal("hide")
          @trigger "done"
        else
          intertwinkles.user.set(data.model)
          @$(".modal").modal("hide")
          @trigger "done"

      intertwinkles.socket.emit "edit_profile", {
        callback: "profile_updated"
        model: {
          email: intertwinkles.user.get("email")
          name: new_name
          icon: { id: new_icon, color: new_color }
        }
      }

#
# Icon Chooser widget
#

icon_chooser_template = _.template("""
  <input name='icon' id='id_icon' value='<%= chosen %>' type='hidden' />
  <div class='profile-image-chooser'><img src='/img/spinner.gif' alt='Loading...'/></div>
  <div>
    <a class='attribution-link' href='#{INTERTWINKLES_BASE_URL}/profiles/icon_attribution/'>
      About these icons
    </a>
  </div>
  <div style='clear: both;'></div>
""")

class intertwinkles.IconChooser extends Backbone.View
  template: icon_chooser_template
  chooser_image: "#{INTERTWINKLES_BASE_URL}/media/profile_icons/chooser.png"
  initialize: (options={}) ->
    @chosen = options.chosen

  render: =>
    @$el.html(@template(chosen: @chosen or ""))
    $.get "/js/intertwinkles_icon_chooser.json", (data) =>
      icon_holder = @$(".profile-image-chooser")
      icon_holder.html("")
      _.each data, (def, i) =>
        cls = "profile-image"
        cls += " chosen" if @chosen == def.pk
        icon = $("<div/>").html(def.name).attr({ "class": cls }).css {
          "background-image": "url('#{@chooser_image}')"
          "background-position": "#{-32 * i}px 0px"
        }
        icon.on "click", =>
          @$(".profile-image.chosen").removeClass("chosen")
          icon.addClass("chosen")
          @$("input[name=icon]").val(def.pk)
          @chosen = def.pk
        icon_holder.append(icon)
      icon_holder.append("<div style='clear: both;'></div>")
    jscolor.bind()

#
# User menu
#

user_menu_template = _.template("""
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
    <li><a tabindex='-1' class='sign-out' href='#'>Sign out</a></li>
  </ul>
""")
class intertwinkles.UserMenu extends Backbone.View
  tagName: 'li'
  template: user_menu_template
  events:
    'click .sign-out': 'signOut'

  initialize: ->
    intertwinkles.user.on "change", @render

  render: =>
    @$el.addClass("dropdown")
    if intertwinkles.is_authenticated()
      @$el.html(@template(user: intertwinkles.user.toJSON()))
    else
      @$el.html("")
    @setAuthFrameVisibility()

  setAuthFrameVisibility: =>
    if intertwinkles.is_authenticated()
      $("#auth_frame").hide()
    else
      $("#auth_frame").show()

  signOut: (event) =>
    event.preventDefault()
    intertwinkles.request_logout()

#
# Room users menu
#

room_users_menu_template = _.template("""
  <a class='room-menu dropdown-toggle' href='#' data-toggle='dropdown'
     title='People in this room'>
    <i class='icon-user'></i><span class='count'></span>
    <b class='caret'></b>
  </a>
  <ul class='dropdown-menu' role='menu'></ul>
""")
room_users_menu_item_template = _.template("""
  <li><a>
    <% if (icon) { %>
      <img src='<%= icon.tiny %>' />
    <% } else { %>
      <i class='icon icon-user'></i>
    <% } %>
    <%= name %>
  </a></li>
""")

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

toolbar_template = _.template("""
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
""")

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

footer_template = _.template("""
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
          <li><a href='#{INTERTWINKLES_BASE_URL}/about/related/'>Related projects</a></li>
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
""")

intertwinkles.build_footer = (destination) ->
  $(destination).html(footer_template())


#
# User choice widget
#

user_choice_template = _.template("""
  <input type='text' name='name' id='id_user' data-provide='typeahead' autocomplete='off' value='<%= name %>' />
  <span class='icon-holder' style='width: 32px; display: inline-block;'>
    <% if (icon) { %><img src='<%= icon %>' /><% } %>
  </span>
  <input type='hidden' name='user_id' id='id_user_id' value='<%= user_id %>' />
""")

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

group_choice_template = _.template("""
  <% if (intertwinkles.is_authenticated()) { %>
    <% if (intertwinkles.groups.length > 0) { %>
      <select id='id_group'>
        <option value=''>----</option>
        <% for (var i = 0; i < intertwinkles.groups.length; i++) { %>
          <% group = intertwinkles.groups[i]; %>
          <option value='<%= group.id %>'><%= group.name %></option>
        <% } %>
      </select>
    <% } else { %>
      You don't have any groups yet.
    <% } %>
    <br />
    (or <a href='<%= INTERTWINKLES_BASE_URL %>/groups/edit'>create a new group</a>)
  <% } else { %>
    Sign in to add a group.
  <% } %>
""")

class intertwinkles.GroupChoice extends Backbone.View
  tagName: "span"
  template: group_choice_template
  initialize: (options={}) ->
  render: =>
    @$el.html(@template())
    this

#
# Sharing control widget
#

sharing_control_template = _.template("""
  <% if (intertwinkles.is_authenticated()) { %>
    <div>
      <a href='#' class='show-all-options'>Change sharing options</a>
    </div>
    <div class='hide all-options'>
      <div class='group-options'>
        Group:
        <div class='group-choice'></div>
      </div>
      <div class='public-options'>
        <div class='public-editing'>
            In addition to group members, share with:<br />
            Public: <select name='public_edit_or_view'>
                      <option value=''>No</option>
                      <option value='edit'>can edit</option>
                      <option value='view'>can view</option>
                    </select>
          </label>
          <span class='public-until'>
            until <select name='public_until'>
                    <option value='-1'>Forever</option>
                    <option value='<%= 1000 * 60 * 60 %>'>One hour</option>
                    <option value='<%= 1000 * 60 * 60 * 24 %>'>One day</option>
                    <option value='<%= 1000 * 60 * 60 * 24 * 7 %>'>One week</option>
                  </select>
          </span>
          <div>
            <% var has_more_sharing = sharing.extra_editors != null || sharing.extra_viewers != null; %>
            <% if (!has_more_sharing) { %>
              <a href='#' class='more-sharing-options'>More sharing options</a>
            <% } %>
            <div class='extra<%= has_more_sharing ? '' : ' hide' %>'>
              Extra editors (list email addresses):<br />
              <textarea name='extra_editors'><%= (sharing.extra_editors || []).join(', ') %></textarea>
              <br />
              Extra viewers (list email addresses):<br />
              <textarea name='extra_viewers'><%= (sharing.extra_viewers || []).join(', ') %></textarea>
            </div>
          </div>
        </div>
      </div>
      <div class='advertise'>
        <label>
          List the URL publicly?
          <input type='checkbox' name='advertise' value='on' <%= sharing.advertise ? 'checked=\"checked\"' : '' %> />
        </label>
      </div>
    </div>
    <div class='summary'>
      <h4>Sharing summary:</h4>
      <div class='perms'>
      </div>
      <div class='additional'>
        The URL will <span class='public-url'></span> be listed publicly.<br />
      </div>
    </div>
  <% } else { %>
    <span class='help-inline'>
      Anyone with the URL can edit or view.<br />
      Sign in to change this.
    </span>
  <% } %>
""")

class intertwinkles.SharingFormControl extends Backbone.View
  #
  # A control for editing the sharing settings within a form.
  #
  template: sharing_control_template
  initialize: (options={}) ->
    @sharing = options.sharing or {}
    
    # Normalize sharing
    now = new Date()
    if @sharing.public_edit_until?
      # Remove stale public edit until
      @sharing.public_edit_until = new Date(@sharing.public_edit_until)
      if @sharing.public_edit_until < now
        delete @sharing.public_edit_until
    if @sharing.public_view_until?
      # Remove stale public view until
      @sharing.public_view_until = new Date(@sharing.public_view_until)
      if @sharing.public_view_until < now
        delete @sharing.public_view_until
    if @sharing.extra_editors?.length == 0
      # Remove empty extra editors.
      delete @sharing.extra_editors
    if @sharing.extra_viewers?.length == 0
      # Remove empty extra viewers.
      delete @sharing.extra_viewers
    if not (@sharing.public_edit_until? or @sharing.public_view_until?)
      # Can't advertise unless it's public.
      @sharing.advertise = false

    intertwinkles.user.on "change", @render

  render: =>
    @$el.addClass("sharing-controls")
    @$el.html(@template({sharing: @sharing}))
    @render_summary()
    return unless intertwinkles.is_authenticated()

    group_choice = new intertwinkles.GroupChoice()
    @$(".group-choice").html(group_choice.el)
    group_choice.render()
    @$("#id_group").val(@sharing.group_id) if @sharing.group_id?

    if @sharing.public_edit_until?
      @$("select[name=public_edit_or_view]").val("edit")
    else if @sharing.public_view_until?
      @$("select[name=public_edit_or_view]").val("view")
    public_until = @sharing.public_edit_until or @sharing.public_view_until
    if public_until
      diff = public_until - new Date().getTime()
      if diff > 1000 * 60 * 60 * 24 * 365
        @$("select[name=public_until]").val("-1")
      else if diff > 1000 * 60 * 60 * 24
        @$("select[name=public_until]").val(1000 * 60 * 60 * 24 * 7) # one week
      else if diff > 1000 * 60 * 60
        @$("select[name=public_until]").val(1000 * 60 * 60 * 24) # one day
      else
        @$("select[name=public_until]").val(1000 * 60 * 60) # one hour

    @$(".show-all-options").on "click", (event) =>
      event.preventDefault()
      $(event.currentTarget).hide()
      @$(".all-options").show()

    @$(".more-sharing-options").on "click", (event) =>
      event.preventDefault()
      @$(".extra").show()

    setSharingVisibility = => @$(".public-options").toggle(@sharing.group_id?)
    setSharingVisibility()

    @$("#id_group").on "change", =>
      @sharing.group_id = @$("#id_group").val()
      if @sharing.group_id
        @sharing.group_id = parseInt(@sharing.group_id)
      else
        delete @sharing.group_id
        delete @sharing.public_view_until
        delete @sharing.public_edit_until
        delete @sharing.extra_viewers
        delete @sharing.extra_editors
      setSharingVisibility()
      @render_summary()

    setUntil = =>
      val = parseInt(@$("select[name=public_until]").val())
      if val == -1
        # 1000 years in the future should be good enough for 'forever'.
        val = 1000 * 60 * 60 * 24 * 365 * 1000
      future = new Date(new Date().getTime() + val)
      switch @$("select[name=public_edit_or_view]").val()
        when 'edit'
          @sharing.public_edit_until = future
          @sharing.public_view_until = null
          @$(".advertise").show()
        when 'view'
          @sharing.public_edit_until = null
          @sharing.public_view_until = future
          @$(".advertise").show()
        when ''
          @sharing.public_edit_until = null
          @sharing.public_view_until = null
          @sharing.advertise = false
          @$("input[name=advertise]").val(false)
          @$(".advertise").hide()
      @render_summary()

    @$("select[name=public_until]").on "change", setUntil
    @$("select[name=public_edit_or_view]").on "change", (event) =>
      val = $(event.currentTarget).val()
      @$(".public-until").toggle(val != '')
      setUntil()
    @$(".public-until").toggle(@sharing.public_edit_until? or @sharing.public_view_until?)

    @$("input[name=advertise]").on "change", (event) =>
      @sharing.advertise = @$("input[name=advertise]").is(":checked")
      @render_summary()

    @$("textarea[name=extra_editors], textarea[name=extra_viewers]").on "change", =>
      @sharing.extra_editors = _.reject(
        @$("textarea[name=extra_editors]").val().split(/[,\s]+/), (e) -> not e
      )
      @sharing.extra_viewers = _.reject(
        @$("textarea[name=extra_viewers]").val().split(/[,\s]+/), (e) -> not e
      )
      if @sharing.extra_editors.length == 0
        @sharing.extra_editors = null
      if @sharing.extra_viewers.length == 0
        @sharing.extra_viweers = null
      @render_summary()


  render_summary: =>
    # Render a natural-language summary of the model's current sharing preferences.
    sharing = @sharing
    console.log(sharing)
    @$(".summary .public-url").html(if sharing.advertise then "" else "not")
    if not sharing? or not sharing.group_id?
      @$(".summary .perms").html("Anyone with the URL can edit.")
    else
      perms = []
      now = new Date()
      is_public = false
      if sharing.public_edit_until?
        if sharing.public_edit_until.getTime() - now.getTime() > 1000 * 60 * 60 * 24 * 365 * 100
          future = "forever"
        else
          future = "until #{@sharing.public_edit_until.toString("ddd MMM d, h:mmtt")}"
        perms.push("Anyone with the URL can edit this #{future}.")
        is_public = true
      else if sharing.public_view_until?
        if sharing.public_view_until.getTime() - now.getTime() > 1000 * 60 * 60 * 24 * 365 * 100
          future = "forever"
        else
          future = "until #{@sharing.public_view_until.toString("ddd MMM d, h:mmtt")}"
        perms.push("Anyone with the URL can view this #{future}.")
        is_public = true
      group = _.find intertwinkles.groups, (g) -> "" + g.id == "" + sharing.group_id
      group_list = _.map(group.members, (m) ->
        intertwinkles.users[m.user_id].email
      )
      perms.push("Members of <acronym title='#{group_list.join(", ")}'>#{group.name}</acronym> can view and edit#{if is_public then " beyond that date" else ""}.")
      if sharing.extra_editors?.length > 0
        other_editors = _.difference(sharing.extra_editors, group_list)
      else
        other_editors = []
      if sharing.extra_viewers?.length > 0
        other_viewers = _.difference(sharing.extra_viewers, group_list, other_editors)
      else
        other_viewers = []
      if other_editors.length > 0
        perms.push("<br />The following people can also edit: <i>#{other_editors.join(", ")}</i>.")
      if other_viewers.length > 0
        perms.push("<br />The following people can also view: <i>#{other_viewers.join(", ")}</i>.")
      if not is_public
        perms.push("All others, and people who aren't signed in, cannot view or edit.")
      @$(".summary .perms").html(perms.join(" "))

sharing_settings_button_template = _.template("""
  <div class='sharing-settings-button'>
    <a class='btn btn-success open-sharing'><i class='icon-globe'></i> Share</a>
  </div>
""")
sharing_settings_modal_template = _.template("""
  <div class='modal hide fade'>
    <div class='modal-header'>
      <button type='button' class='close' data-dismiss='modal' aria-hidden='true'>&times;</button>
      <h3>Sharing</h3>
    </div>
    <form class='form-horizontal'>
      <div class='modal-body'>
        <div class='sharing-controls'></div>
      </div>
      <div class='modal-footer'>
        <input type='submit' class='btn btn-primary' value='Save' />
      </div>
    </form>
  </div>
""")

class intertwinkles.SharingSettingsButton extends Backbone.View
  # A control that briefly summarizes the sharing preferences for a document,
  # and invokes a form to edit them.
  template: sharing_settings_button_template
  modalTemplate: sharing_settings_modal_template
  events:
    'click .open-sharing': 'renderModal'

  initialize: (options={}) ->
    @model = options.model
    @model.on "change", @render

  render: =>
    @$el.html(@template())

  renderModal: (event) =>
    event.preventDefault()
    @modal = $(@modalTemplate())
    $("body").append(@modal)
    @modal.modal('show').on('hidden', => @modal.remove())
    @sharing = new intertwinkles.SharingFormControl(sharing: @model.get("sharing"))
    $(".sharing-controls", @modal).html(@sharing.el)
    @sharing.render()
    $("form", @modal).on "submit", @save

  close: =>
    @modal.modal('hide')

  save: (event) =>
    event.preventDefault()
    $("input[type=submit]", @modal).addClass("loading")
    @trigger "save", @sharing.sharing
    return false

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

html_colors = [
  [0x80, 0x00, 0x00, "maroon"],
  [0x8B, 0x00, 0x00, "darkred"],
  [0xFF, 0x00, 0x00, "red"],
  [0xFF, 0xB6, 0xC1, "lightpink"],
  [0xDC, 0x14, 0x3C, "crimson"],
  [0xDB, 0x70, 0x93, "palevioletred"],
  [0xFF, 0x69, 0xB4, "hotpink"],
  [0xFF, 0x14, 0x93, "deeppink"],
  [0xC7, 0x15, 0x85, "mediumvioletred"],
  [0x80, 0x00, 0x80, "purple"],
  [0x8B, 0x00, 0x8B, "darkmagenta"],
  [0xDA, 0x70, 0xD6, "orchid"],
  [0xD8, 0xBF, 0xD8, "thistle"],
  [0xDD, 0xA0, 0xDD, "plum"],
  [0xEE, 0x82, 0xEE, "violet"],
  [0xFF, 0x00, 0xFF, "fuchsia"],
  [0xFF, 0x00, 0xFF, "magenta"],
  [0xBA, 0x55, 0xD3, "mediumorchid"],
  [0x94, 0x00, 0xD3, "darkviolet"],
  [0x99, 0x32, 0xCC, "darkorchid"],
  [0x8A, 0x2B, 0xE2, "blueviolet"],
  [0x4B, 0x00, 0x82, "indigo"],
  [0x93, 0x70, 0xDB, "mediumpurple"],
  [0x6A, 0x5A, 0xCD, "slateblue"],
  [0x7B, 0x68, 0xEE, "mediumslateblue"],
  [0x00, 0x00, 0x8B, "darkblue"],
  [0x00, 0x00, 0xCD, "mediumblue"],
  [0x00, 0x00, 0xFF, "blue"],
  [0x00, 0x00, 0x80, "navy"],
  [0x19, 0x19, 0x70, "midnightblue"],
  [0x48, 0x3D, 0x8B, "darkslateblue"],
  [0x41, 0x69, 0xE1, "royalblue"],
  [0x64, 0x95, 0xED, "cornflowerblue"],
  [0xB0, 0xC4, 0xDE, "lightsteelblue"],
  [0xF0, 0xF8, 0xFF, "aliceblue"],
  [0xF8, 0xF8, 0xFF, "ghostwhite"],
  [0xE6, 0xE6, 0xFA, "lavender"],
  [0x1E, 0x90, 0xFF, "dodgerblue"],
  [0x46, 0x82, 0xB4, "steelblue"],
  [0x00, 0xBF, 0xFF, "deepskyblue"],
  [0x70, 0x80, 0x90, "slategray"],
  [0x77, 0x88, 0x99, "lightslategray"],
  [0x87, 0xCE, 0xFA, "lightskyblue"],
  [0x87, 0xCE, 0xEB, "skyblue"],
  [0xAD, 0xD8, 0xE6, "lightblue"],
  [0x00, 0x80, 0x80, "teal"],
  [0x00, 0x8B, 0x8B, "darkcyan"],
  [0x00, 0xCE, 0xD1, "darkturquoise"],
  [0x00, 0xFF, 0xFF, "cyan"],
  [0x48, 0xD1, 0xCC, "mediumturquoise"],
  [0x5F, 0x9E, 0xA0, "cadetblue"],
  [0xAF, 0xEE, 0xEE, "paleturquoise"],
  [0xE0, 0xFF, 0xFF, "lightcyan"],
  [0xF0, 0xFF, 0xFF, "azure"],
  [0x20, 0xB2, 0xAA, "lightseagreen"],
  [0x40, 0xE0, 0xD0, "turquoise"],
  [0xB0, 0xE0, 0xE6, "powderblue"],
  [0x2F, 0x4F, 0x4F, "darkslategray"],
  [0x7F, 0xFF, 0xD4, "aquamarine"],
  [0x00, 0xFA, 0x9A, "mediumspringgreen"],
  [0x66, 0xCD, 0xAA, "mediumaquamarine"],
  [0x00, 0xFF, 0x7F, "springgreen"],
  [0x3C, 0xB3, 0x71, "mediumseagreen"],
  [0x2E, 0x8B, 0x57, "seagreen"],
  [0x32, 0xCD, 0x32, "limegreen"],
  [0x00, 0x64, 0x00, "darkgreen"],
  [0x00, 0x80, 0x00, "green"],
  [0x00, 0xFF, 0x00, "lime"],
  [0x22, 0x8B, 0x22, "forestgreen"],
  [0x8F, 0xBC, 0x8F, "darkseagreen"],
  [0x90, 0xEE, 0x90, "lightgreen"],
  [0x98, 0xFB, 0x98, "palegreen"],
  [0xF5, 0xFF, 0xFA, "mintcream"],
  [0xF0, 0xFF, 0xF0, "honeydew"],
  [0x7F, 0xFF, 0x00, "chartreuse"],
  [0x7C, 0xFC, 0x00, "lawngreen"],
  [0x6B, 0x8E, 0x23, "olivedrab"],
  [0x55, 0x6B, 0x2F, "darkolivegreen"],
  [0x9A, 0xCD, 0x32, "yellowgreen"],
  [0xAD, 0xFF, 0x2F, "greenyellow"],
  [0xF5, 0xF5, 0xDC, "beige"],
  [0xFA, 0xF0, 0xE6, "linen"],
  [0xFA, 0xFA, 0xD2, "lightgoldenrodyellow"],
  [0x80, 0x80, 0x00, "olive"],
  [0xFF, 0xFF, 0x00, "yellow"],
  [0xFF, 0xFF, 0xE0, "lightyellow"],
  [0xFF, 0xFF, 0xF0, "ivory"],
  [0xBD, 0xB7, 0x6B, "darkkhaki"],
  [0xF0, 0xE6, 0x8C, "khaki"],
  [0xEE, 0xE8, 0xAA, "palegoldenrod"],
  [0xF5, 0xDE, 0xB3, "wheat"],
  [0xFF, 0xD7, 0x00, "gold"],
  [0xFF, 0xFA, 0xCD, "lemonchiffon"],
  [0xFF, 0xEF, 0xD5, "papayawhip"],
  [0xB8, 0x86, 0x0B, "darkgoldenrod"],
  [0xDA, 0xA5, 0x20, "goldenrod"],
  [0xFA, 0xEB, 0xD7, "antiquewhite"],
  [0xFF, 0xF8, 0xDC, "cornsilk"],
  [0xFD, 0xF5, 0xE6, "oldlace"],
  [0xFF, 0xE4, 0xB5, "moccasin"],
  [0xFF, 0xDE, 0xAD, "navajowhite"],
  [0xFF, 0xA5, 0x00, "orange"],
  [0xFF, 0xE4, 0xC4, "bisque"],
  [0xD2, 0xB4, 0x8C, "tan"],
  [0xFF, 0x8C, 0x00, "darkorange"],
  [0xDE, 0xB8, 0x87, "burlywood"],
  [0x8B, 0x45, 0x13, "saddlebrown"],
  [0xF4, 0xA4, 0x60, "sandybrown"],
  [0xFF, 0xEB, 0xCD, "blanchedalmond"],
  [0xFF, 0xF0, 0xF5, "lavenderblush"],
  [0xFF, 0xF5, 0xEE, "seashell"],
  [0xFF, 0xFA, 0xF0, "floralwhite"],
  [0xFF, 0xFA, 0xFA, "snow"],
  [0xCD, 0x85, 0x3F, "peru"],
  [0xFF, 0xDA, 0xB9, "peachpuff"],
  [0xD2, 0x69, 0x1E, "chocolate"],
  [0xA0, 0x52, 0x2D, "sienna"],
  [0xFF, 0xA0, 0x7A, "lightsalmon"],
  [0xFF, 0x7F, 0x50, "coral"],
  [0xE9, 0x96, 0x7A, "darksalmon"],
  [0xFF, 0xE4, 0xE1, "mistyrose"],
  [0xFF, 0x45, 0x00, "orangered"],
  [0xFA, 0x80, 0x72, "salmon"],
  [0xFF, 0x63, 0x47, "tomato"],
  [0xBC, 0x8F, 0x8F, "rosybrown"],
  [0xFF, 0xC0, 0xCB, "pink"],
  [0xCD, 0x5C, 0x5C, "indianred"],
  [0xF0, 0x80, 0x80, "lightcoral"],
  [0xA5, 0x2A, 0x2A, "brown"],
  [0xB2, 0x22, 0x22, "firebrick"],
  [0x00, 0x00, 0x00, "black"],
  [0x69, 0x69, 0x69, "dimgray"],
  [0x80, 0x80, 0x80, "gray"],
  [0xA9, 0xA9, 0xA9, "darkgray"],
  [0xC0, 0xC0, 0xC0, "silver"],
  [0xD3, 0xD3, 0xD3, "lightgrey"],
  [0xDC, 0xDC, 0xDC, "gainsboro"],
  [0xF5, 0xF5, 0xF5, "whitesmoke"],
  [0xFF, 0xFF, 0xFF, "white"],
]
intertwinkles.match_color = (hexstr) ->
  r1 = parseInt(hexstr[0...2], 16)
  g1 = parseInt(hexstr[2...4], 16)
  b1 = parseInt(hexstr[4...6], 16)
  distance = 255 * 3
  best = html_colors[0][3]
  for [r2, g2, b2, name] in html_colors
    # Lame, lame, RGB based additive distance.  Not great.
    diff = Math.abs(r1 - r2) + Math.abs(g1 - g2) + Math.abs(b1 - b2)
    if diff < distance
      distance = diff
      best = name
  return best

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


