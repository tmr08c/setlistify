@ProgressModal = class ProgressModal
  modalId: 'progressModal'

  constructor: (wrapperId = 'modalWrapper') ->
    @wrapperSelector = $("##{wrapperId}")
    @modalSelector = @_createModal()
    @modalContent = @modalSelector.find('.modal-content')
    @modalStatusSelector = @modalContent.find('.status')
    @modalBodySelector = @modalContent.find('.modal-body')
    @modalBodyProgressMessage = @modalBodySelector.find('.progress-message')
    @modalBodyProgressBar = @modalBodySelector.find('.progress-bar')
    @modalFooterSelector = @modalSelector.find('.modal-footer')
    @_addEventListeners()

  openModal: ->
    @modalSelector.openModal()

  closeModal: ->
    @modalSelector.closeModal()
    @wrapperSelector.remove('.modal')

  displayLogInModal: () ->
    @updateStatus('Not Logged In')
    @replaceBody(@_logInBody)
    @modalFooterSelector.html(@_errorModalFooter)

  updateStatus: (statusText) ->
    @modalStatusSelector.text(statusText)

  updateProgress: (statusMessage, percent) ->
    @modalBodyProgressMessage.html(statusMessage)
    @modalBodyProgressBar.attr('style', "width: #{percent}%")

  updateBody: (text) ->
    @modalBodySelector.append(text)

  replaceBody: (html) ->
    @modalBodySelector.html(html)

  displaySuccessFooter: () ->
    @modalFooterSelector.html(@_successModalFooter)

  displayErrorFooter: () ->
    @modalFooterSelector.html(@_errorModalFooter)

  _baseModalHtml: =>
    """
    <div id="#{@modalId}" class='modal'>
      <div class='modal-content'>
        <h4 class='status'></h4>
        <div class='modal-body'>
          <div class='progress-message'></div>
          <div class='progress'>
            <div class='progress-bar determinate' style='0%'></div>
          </div>
        </div>
      </div>
      <div class='modal-footer'>
      </div>
    </div>
    """

  _logInBody: ->
    """
    You need to log in to Spotify to let Setlistify make a playlist for you.
    <br>
    <br>
    Click <a href="#" class='spotifySignIn'>here</a> to sign in to Spotify
    """

  _successModalFooter: ->
    """
    <a class='modal-action modal-close waves-effect waves-green btn-flat'>Close</a>
    """

  _errorModalFooter: ->
    """
    <a class='modal-action modal-close waves-effect waves-red btn-flat'>Close</a>
    """

  _createModal: =>
    @wrapperSelector.html(@_baseModalHtml)
    $("##{@modalId}")

  _addEventListeners: ->
    @modalFooterSelector.on('click', '.modal-close', =>
      @closeModal()
    )
