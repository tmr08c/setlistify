@SpotifyApi = class SpotifyApi
  base_url: 'https://api.spotify.com/v1/'
  clientId: 'e9a442575edf498d858ad8c07396cdb2'
  redirectUri: "http://#{location.host}/spotifycallback"
  scopes: 'playlist-modify-public playlist-modify-private'

  constructor: ->
    console.log 'new api'
    @fetchToken()

  fetchToken: ->
    console.log 'fetch'
    if window.sessionStorage.getItem('accessToken') != null
      console.log('in sessoin')
      @accessToken = window.sessionStorage.getItem('accessToken')
    else
      console.log 'authorize'
      @authorize()

  authorize: ->
    console.log 'in authorize'
    currentSearchQuery = window.location.search.slice(1).split('=')[1]
    window.location = 'https://accounts.spotify.com/authorize' +
      '?response_type=token' +
      "&client_id=#{@clientId}" +
      "&scope=#{encodeURIComponent(@scopes)}" +
      "&redirect_uri=#{encodeURIComponent(@redirectUri)}" +
      "&state=#{currentSearchQuery }" +
      "&show_dialog=true"

  userInfo: ->
    $.ajax
      url: 'https://api.spotify.com/v1/me',
      type: 'GET',
      beforeSend: (xhr) =>
        xhr.setRequestHeader("Authorization", "Bearer #{@accessToken}")
      success: (data) ->
        console.log data.id
        @userId = data.id

  search: (query, type) ->
    $.ajax
      url: 'https://api.spotify.com/v1/search',
      data: "q=#{query}&type=#{type}",
      dataType: 'json'
      success: (data) ->
        console.log data
      error: () ->
        console.log 'fail'

  requestToken: (code) ->
    $.ajax
      url: 'https://accounts.spotify.com/api/token',
      type: 'POST',
      data: JSON.stringify({ grant_type: 'authorization_code', code: code, redirect_uri: @redirectUri }),
      beforeSend: (xhr) =>
        xhr.setRequestHeader("Authorization", "Basic ZTlhNDQyNTc1ZWRmNDk4ZDg1OGFkOGMwNzM5NmNkYjI6MGMwZGQxZGJjYWQwNDYzNmI5N2VmYTNkNzVjZWVkMzE=")
        # xhr.setRequestHeader("Access-Control-Allow-Origin", '*')
      success: ->
        debugger

  createPlaylist: (playlistName) =>
    @userInfo().then((userInfoResponse) ->
      sleep 1
      $.ajax
        url: "https://api.spotify.com/v1/users/tmr08c/playlists",
        type: 'POST',
        data: JSON.stringify({ name: playlistName, public: 'false' }),
        dataType: 'json',
        beforeSend: (xhr) =>
          xhr.setRequestHeader("Authorization", "Bearer #{@accessToken}")
        # success: (data) ->
        ## onSuccess(data.id)
        # need to add better handling and handle common issues
        # * Playlist exists
        # * No access
        error: (e) ->
          console.log 'Issue making playlist'
          e
    )

  # naievely for now we should just grab the first result's URI
  # eventually we should handle
  # * multiple pages
  # * checking title
  # * checking artist
  songSearch: (artist, title) ->
    console.log "Song search. Artist: #{artist} / title: #{title}"
    @search("#{title} #{artist}", 'track')

  addToPlaylist: (songUris, playlist_uri, user_id) ->
    console.log songUris
    # console.log "Adding to playlist. Song: #{song_uri} / Playlist: #{playlist_uri}"
    $.ajax
      url: "https://api.spotify.com/v1/users/#{user_id}/playlists/#{playlist_uri}/tracks",
      type: 'POST',
      data: JSON.stringify({
        uris: songUris
      }),
      dataType: 'json',
      beforeSend: (xhr) =>
        xhr.setRequestHeader("Authorization", "Bearer #{@accessToken}")
      success: (data) ->
        console.log 'added'
      # need to add better handling and handle common issues
      # * Playlist exists
      # * No access
      error: (e) ->
        console.log 'issue adding to playlist'
        e
