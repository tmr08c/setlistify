@SpotifyApi = class SpotifyApi
  base_url: 'https://api.spotify.com/v1/'
  auth_token: "Bearer BQCnqZVbaLL17Zf0zCm2Uv1287nDYjseLsuZWGLrC9bP_1OXw4PfZvVWsBr2_1-2DEdH4yLOkCHRebHQ1cpqnyuCl9iHsCeGhbcVrJDJ8sxMGRxp9wRA5L6bqLoEY2FXKkTjRSER2j6syytF8wpRNe5bL23TwnDjElXLEPbwXXklqwVMtNXjoe7eIb5bhbi4VscymH7DWG98uLqQX1rYYaFvZ4Oe_qqRzi6wMn2Ynun6zmqaftCtiureb5iPnLUWsWkRScd3-4Nko51lgJys2f2DzrRp-xBYnL94vg"

  search: (query, type, callback) ->
    $.ajax
      url: 'https://api.spotify.com/v1/search',
      data: "q=#{query}&type=#{type}",
      dataType: 'json'
      success: (data) ->
        callback(data)
      error: () ->
        console.log 'fail'

  createPlaylist: (username, playlistName, onSuccess) ->
    $.ajax
      url: "https://api.spotify.com/v1/users/#{username}/playlists",
      type: 'POST',
      data: JSON.stringify({ name: playlistName, public: 'false' }),
      dataType: 'json',
      beforeSend: (xhr) =>
        xhr.setRequestHeader("Authorization", @auth_token)
      success: (data) ->
        onSuccess(data.id)
      # need to add better handling and handle common issues
      # * Playlist exists
      # * No access
      error: (e) ->
        console.log 'Issue making playlist'
        e

  songSearch: (artist, title, onSuccess) ->
    console.log "Song search. Artist: #{artist} / title: #{title}"
    @search("#{title} #{artist}", 'track', (data) ->
      # naievely for now we should just grab the first result's URI
      # eventually we should handle
      # * multiple pages
      # * checking title
      # * checking artist
      onSuccess(data.tracks.items[0].uri)
    )

  addToPlaylist: (song_uri, playlist_uri, user_id) ->
    console.log "Adding to playlist. Song: #{song_uri} / Playlist: #{playlist_uri}"
    $.ajax
      url: "https://api.spotify.com/v1/users/#{user_id}/playlists/#{playlist_uri}/tracks?uris=#{song_uri}",
      type: 'POST',
      # data: {uris: playlist_uri},
      dataType: 'json',
      beforeSend: (xhr) =>
        xhr.setRequestHeader("Authorization", @auth_token)
      success: (data) ->
        console.log 'added'
      # need to add better handling and handle common issues
      # * Playlist exists
      # * No access
      error: (e) ->
        console.log 'issue adding to playlist'
        e
