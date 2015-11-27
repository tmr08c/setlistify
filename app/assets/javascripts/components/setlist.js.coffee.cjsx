@Setlist = React.createClass
  render: ->
    <div className='card setlistWrapper'>
      <div className='card-content'>
        <span className="card-title activator grey-text text-darken-4">
          {this.props.artist}
          <i className="material-icons right">more_vert</i>
        </span>
        <div>
          <div className='eventDate'>{this.props.date}</div>
          <Venue name={this.props.venue.name} city={this.props.venue.city} state={this.props.venue.state} />
        </div>
      </div>
      <div className="card-reveal">
        <span className="card-title grey-text text-darken-4">Setlist<i className="material-icons
  right">close</i></span>
        <ol>
          {
            this.props.setlist.map (song, index) ->
              <Song key=index title=song.title />
          }
        </ol>
      </div>
    </div>
