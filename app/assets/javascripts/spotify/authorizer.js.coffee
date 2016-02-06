@Authorizer = class Authorizer
  clientId: 'e9a442575edf498d858ad8c07396cdb2'
  scopes: 'playlist-modify-public playlist-modify-private'
  redirectUri: "http://#{location.host}/spotifycallback"

  constructor: ->

  authorize: ->
    window.open(
      'https://accounts.spotify.com/authorize' +
        '?response_type=token' +
        "&client_id=#{@clientId}" +
        "&scope=#{encodeURIComponent(@scopes)}" +
        "&redirect_uri=#{encodeURIComponent(@redirectUri)}" +
        "&show_dialog=true",
      '_blank',
      'width=550, height=500'
    )
