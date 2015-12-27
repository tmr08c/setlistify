@PlaylistBuilder = class PlaylistBuilder
  constructor: (artist, setlist) ->
    console.log 'new playlist builder'
    @artist = artist
    @setlist = setlist
    @api = new SpotifyApi()

  buildPlaylist: (onSuccess, onFailure) =>
    @_createPlaylist().then((playlistResult) =>
      playlistId = playlistResult.id
      $.when.apply(undefined, @_getSongUris()).then((results) =>
        songInfoResponses = [].slice.apply(arguments)
        @_addTracksToPlaylist(playlistId, songInfoResponses )
      )
    )

  _createPlaylist: () ->
    console.log "In 'createPlaylist'"
    @api.createPlaylist('tmr08c', 'Playlist5')

  _getSongUris: () ->
    console.log "In 'getSongUris'"
    requests = []
    for song in @setlist
      requests.push(@api.songSearch(@artist, song.title))
    requests

  _addTracksToPlaylist: (playlistId, songInfoResponses) ->
    console.log "In 'addTracksToPlaylist'. playlistId: #{playlistId} / songUris: #{songUris}"
    songUris = []

    songInfoResponses.forEach (songInfoResponse, _) ->
      # If the song is found by the API, add it to our array of Song IDs
      if songInfoResponse[0].tracks.items.length > 0
        songUris.push songInfoResponse[0].tracks.items[0].uri
      else
        console.log "Couldn't find song"
    @api.addToPlaylist(songUris, playlistId, 'tmr08c')
