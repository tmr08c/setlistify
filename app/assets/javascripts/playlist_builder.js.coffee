@PlaylistBuilder = class PlaylistBuilder
  constructor: (artist, setlist) ->
    @artist = artist
    @setlist = setlist
    @api = new SpotifyApi()

  buildPlaylist: (onSuccess, onFailure) ->
    @api.createPlaylist('tmr08c', 'Playlist1', ((playlist_id) =>
      for song in @setlist
        console.log song
        @api.songSearch(@artist, song.title, ((song_uri) =>
          @api.addToPlaylist(song_uri, playlist_id, 'tmr08c')
        ))
    ))
