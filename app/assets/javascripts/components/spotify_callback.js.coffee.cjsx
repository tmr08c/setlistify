@SpotifyCallback = React.createClass
  contextTypes:
    router: React.PropTypes.func

  componentDidMount: ->
    hashArguments = {}
    window.location.hash.substring(1).split('&').forEach (hashArgument) ->
      hashArgument = hashArgument.split('=')
      hashArguments[hashArgument[0]] = hashArgument.slice(1).join('=')

    if hashArguments['access_token'] == undefined
      window.opener.Materialize.toast('Error signing in to Spotify', 4500, 'error-red')
    else
      window.localStorage.setItem('accessToken', hashArguments['access_token'])
      window.opener.Materialize.toast('Signed in with Spotify', 4500, 'main-green')
    window.close()

  render: ->
    <div>
      {
        <div>Fetching Access Token</div>
      }
    </div>
