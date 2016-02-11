@CreatSetlistButton = React.createClass
  hasSongs: ->
    if this.props.setlist.length == 0
      false
    else
      true

  createPlaylist: ->
    return unless this.hasSongs()

    playlistBuilder = new PlaylistBuilder(
      this.props.artist,
      this.props.venue,
      this.props.date,
      this.props.setlist
    )
    playlistBuilder.buildPlaylist()


  render: ->
    baseButtonClass =  "waves-effect waves-light btn-large"
    if this.hasSongs()
      buttonClass = baseButtonClass
    else
      buttonClass= baseButtonClass + ' disabled'

    <div className='center-align playlistButtonWrapper'>
      <a onClick={this.createPlaylist} className={buttonClass}>
        Create Playlist
      </a>
    </div>
