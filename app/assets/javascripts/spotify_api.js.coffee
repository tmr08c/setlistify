# May need a global version or something
@SpotifyApi = class SpotifyApi
  base_url: 'https://api.spotify.com/v1/'

  constructor: ->
    @fetchToken()

  # Provides a way to call a method of the SpotifyApi class
  # but allows us to handle wrapping it in generic error handling
  execute: (action, args...) ->
    this.fetchToken().then(
      # success
      (accessToken) ->
        console.log 'have token'
        this[action].apply(this, args)
      , #failure
      (error) ->
        console.log 'no token'
        Materialize.toast('Not logged in', 4500, 'error-red')
    )

  fetchToken: ->
    console.log 'fetching'
    new Promise((resolve, reject) =>
      if window.localStorage.getItem('accessToken') == null
        @authorize().then(
          resolve(window.localStorage.getItem('accessToken'))
        )
      else
        resolve(window.localStorage.getItem('accessToken'))
    )

  authorize: ->
    authorizer = new Authorizer(this)
    authorizer.authorize()

  userInfo: ->
    if sessionStorage.getItem('userId') == null
      $.ajax
        url: 'https://api.spotify.com/v1/me',
        type: 'GET',
        beforeSend: (xhr) =>
          xhr.setRequestHeader("Authorization", "Bearer #{@accessToken}")
        success: (data) ->
          sessionStorage.setItem('userId', data.id)
          @userId = data.id
    else
      new Promise((resolve, reject) ->
        resolve({id: sessionStorage.getItem('userId')})
      )

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
      success: ->
        console.log('Failed to get token')

  createPlaylist: (playlistName) =>
    @execute('_createPlaylist', playlistName)

  _createPlaylist: (playlistName) =>
    api = this
    @userInfo().then((userInfoResponse) =>
      $.ajax
        url: "https://api.spotify.com/v1/users/#{userInfoResponse.id}/playlists",
        type: 'POST',
        data: JSON.stringify({ name: playlistName, public: 'false' }),
        dataType: 'json',
        beforeSend: (xhr) ->
          xhr.setRequestHeader("Authorization", "Bearer #{api.accessToken}")
        # success: (data) ->
        ## onSuccess(data.id)
        # need to add better handling and handle common issues
        # * Playlist exists
        # * No access
        error: (e) ->
          console.log "Issue making playlist: #{e}"
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

  addToPlaylist: (songUris, playlist_uri) ->
    console.log songUris
    # console.log "Adding to playlist. Song: #{song_uri} / Playlist: #{playlist_uri}"

    @userInfo().then((userInfoResponse) =>
      $.ajax
        url: "https://api.spotify.com/v1/users/#{userInfoResponse.id}/playlists/#{playlist_uri}/tracks",
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
    )
