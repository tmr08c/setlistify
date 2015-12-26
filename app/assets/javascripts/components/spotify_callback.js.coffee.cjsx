@SpotifyCallback = React.createClass
  contextTypes:
    router: React.PropTypes.func

  componentDidMount: ->
    hashArguments = {}
    window.location.hash.substring(1).split('&').forEach (hashArgument) ->
      hashArgument = hashArgument.split('=')
      hashArguments[hashArgument[0]] = hashArgument.slice(1).join('=')
    window.sessionStorage.setItem('accessToken', hashArguments['access_token'])
    this.setState({
      access_token: hashArguments['access_token'],
      state: hashArguments['state']
    })

  render: ->
    <div>
      {
        if this.state
          window.location = '/search?query=' + this.state.state
        else
          <div>Fetching Access Token</div>
      }
    </div>
