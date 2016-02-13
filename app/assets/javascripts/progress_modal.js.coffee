@ProgressModal = class ProgressModal
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

  _baseModalHtml: ->
    """
    <div id='progressModal' class='modal'>
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

  _successModalFooter: ->
    """
    <a class='modal-action modal-close waves-effect waves-green btn-flat'>Close</a>
    """

  _errorModalFooter: ->
    """
    <a class='modal-action modal-close waves-effect waves-red btn-flat'>Close</a>
    """

  _createModal: ->
    @wrapperSelector.html(@_baseModalHtml)
    $('#progressModal')

  _addEventListeners: ->
    @modalFooterSelector.on('click', '.modal-close', =>
      @closeModal()
    )
