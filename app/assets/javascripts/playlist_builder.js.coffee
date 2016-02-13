@PlaylistBuilder = class PlaylistBuilder
  constructor: (artistName, venueName, date, setlist, modalSelector) ->
    @artistName = artistName
    @venueName = venueName
    @date = date
    @setlist = setlist
    @api = new SpotifyApi()
    @progressModal = new ProgressModal()

  buildPlaylist: (onSuccess, onFailure) =>
    @progressModal.openModal()
    @progressModal.updateStatus('Creating Playlist')
    @_createPlaylist().then(
      (playlistResult) =>
        @progressModal.updateProgress('Playlist Created', 15)
        playlistId = playlistResult.id
        $.when.apply(undefined, @_getSongUris()).then(
          (results) =>
            songInfoResponses = [].slice.apply(arguments)
            @_addTracksToPlaylist(playlistId, songInfoResponses ).then(
              (__) =>
                @_completeWithSuccess(playlistId)
              ,
              (error) =>
                @_completeWithError(error)
            )
          ,
          (result) =>
            alert 'error getting song URIs'
        )
      ,
    (error) =>
      @_completeWithError(error)
  )

  _createPlaylist: () ->
    console.log "In 'createPlaylist'"
    @api.createPlaylist(@_playlistName())

  _getSongUris: () ->
    @progressModal.updateStatus('Searching for songs')
    @progressModal.updateProgress('Fetching setlist', 20)
    console.log "In 'getSongUris'"
    console.log @setlist

    requests = []
    for song in @setlist
      requests.push(@api.songSearch(@artistName, song.title))
    console.log(requests)
    requests

  _addTracksToPlaylist: (playlistId, songInfoResponses) ->
    console.log "In 'addTracksToPlaylist'. playlistId: #{playlistId} / songUris: #{songUris}"
    songUris = []

    songInfoResponses.forEach (songInfoResponse, index) =>
      currentPercent = 20
      # At 20% goal to get to 80% => 60% total gain searching for tracks
      percentGainPerSong = 60 / @setlist.length
      # If the song is found by the API, add it to our array of Song IDs
      if songInfoResponse[0].tracks.items.length > 0
        @progressModal.updateProgress("Found track #{@setlist[index].title}", currentPercent + percentGainPerSong)
        songUris.push songInfoResponse[0].tracks.items[0].uri
      else
        @progressModal.updateProgress("Error finding track #{@setlist[index].title}", currentPercent + percentGainPerSong)
        console.log "Couldn't find song"
    @progressModal.updateStatus('Adding songs to playlist')
    @progressModal.updateProgress('Collecting songs', 80)
    @api.addToPlaylist(songUris, playlistId)

  _playlistName: ->
    @progressModal.updateProgress('Determining Playlist Name', 5)
    "#{@artistName} - #{@venueName} (#{@date})"

  _completeWithSuccess: (playlistId) ->
    @progressModal.updateStatus('Successfully Created PLaylist')
    @progressModal.replaceBody(
      """
      Listen to your new
      <a href='https://open.spotify.com/user/#{sessionStorage.getItem('userId')}/playlist/#{playlistId}' targer='_blank'>
        playlist
      </a>!
      """
    )
    @progressModal.displaySuccessFooter()

  _completeWithError: (error) ->
    @progressModal.updateStatus('Error Creating Playlist')
    @progressModal.replaceBody(
      """
      We received the following error from Spotify while trying to create your playlist:
      <br>
      <br>
      <code class='red-text text-darken-2'>
        #{error.responseJSON.error.message}
      </code>
      <br>
      <br>
      <br>
      We apologize for the inconvenience!
      """
    )
    @progressModal.displayErrorFooter()
