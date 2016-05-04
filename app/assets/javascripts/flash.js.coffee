@Flash = class Flash
  constructor: (message, options = {}) ->
    @message = message
    @type = options.type || 'success'
    @scope = options.scope || window
    @_display()

  _display: ->
    @scope.Materialize.toast(@message, 4500, @_cssClass())

  _cssClass: ->
    switch @type
      when 'success' then 'main-green'
      when 'error' then 'error-red'
      else ''
