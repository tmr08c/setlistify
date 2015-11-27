@Setlist = React.createClass
  render: ->
    <div className='eventWrapper'>
      <div className='artistName'>{this.props.artist}</div>
      <div className='eventDate'>{this.props.date}</div>
      <Venue name={this.props.venue.name} city={this.props.venue.city} state={this.props.venue.state} />
    </div>
