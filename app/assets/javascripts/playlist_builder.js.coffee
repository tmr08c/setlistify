@PlaylistBuilder = class PlaylistBuilder
  constructor: (artist, setlist) ->
    console.log 'new playlist builder'
    @artist = artist
    @setlist = setlist
    @api = new SpotifyApi()

  buildPlaylist: (onSuccess, onFailure) ->
    @api.createPlaylist('tmr08c', 'Playlist9', ((playlist_id) =>
      requests = []
      for song in @setlist.sort()
        requests.push(@api.songSearch(@artist, song.title, ((song_uri) =>
          # songUris.push(song_uri)
          # console.log song_uri
        )))

      $.when.apply(undefined, requests).then((results) =>
        # arguments is an array of jqXHR objects returned from our Ajax calls
        ajaxCallsReturned = [].slice.apply(arguments)

        songUris = []

        ajaxCallsReturned.forEach (data,i) ->
          # If the song is found by the API, add it to our array of Song IDs
          if data[0].tracks.items.length > 0
            songUris.push data[0].tracks.items[0].uri
          else
            console.log "Couldn't find song"
        @api.addToPlaylist(songUris, playlist_id, 'tmr08c')
      ))
    )
