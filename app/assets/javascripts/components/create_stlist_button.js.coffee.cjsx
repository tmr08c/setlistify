@CreatSetlistButton = React.createClass
  hasSongs: ->
    if this.props.setlist.length == 0
      false
    else
      true

  createPlaylist: ->
    return unless this.hasSongs()

    console.log 'making playlist'

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
