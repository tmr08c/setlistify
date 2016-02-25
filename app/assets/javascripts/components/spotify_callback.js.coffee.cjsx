@SpotifyCallback = React.createClass
  contextTypes:
    router: React.PropTypes.func

  _storeAccessToken: (hashArguments) ->
    window.localStorage.setItem('accessToken', hashArguments['access_token'])

  _triggerSuccessfulSignIn: () ->
    elem = window.opener.document.getElementById(ProgressModal::modalId)
    event = document.createEvent('Event')
    event.initEvent(PlaylistBuilder::successfulLoginEvent, true, true)
    elem.dispatchEvent(event)

  componentDidMount: ->
    hashArguments = {}
    window.location.hash.substring(1).split('&').forEach (hashArgument) ->
      hashArgument = hashArgument.split('=')
      hashArguments[hashArgument[0]] = hashArgument.slice(1).join('=')

    if hashArguments['access_token'] == undefined
      new Flash('Error signing in to Spotify', { type: 'error', scope: window.opener })
    else
      @_storeAccessToken(hashArguments)
      @_triggerSuccessfulSignIn()
      new Flash('Signed in with Spotify', { type: 'success', scope: window.opener })

    window.close()

  render: ->
    <div>
      {
        <div>Fetching Access Token</div>
      }
    </div>
