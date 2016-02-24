@SpotifyCallback = React.createClass
  contextTypes:
    router: React.PropTypes.func

  componentDidMount: ->
    hashArguments = {}
    window.location.hash.substring(1).split('&').forEach (hashArgument) ->
      hashArgument = hashArgument.split('=')
      hashArguments[hashArgument[0]] = hashArgument.slice(1).join('=')

    if hashArguments['access_token'] == undefined
      new Flash('Error signing in to Spotify', { type: 'error', scope: window.opener })
    else
      window.localStorage.setItem('accessToken', hashArguments['access_token'])
      new Flash('Signed in with Spotify', { type: 'success', scope: window.opener })

    window.close()

  render: ->
    <div>
      {
        <div>Fetching Access Token</div>
      }
    </div>
