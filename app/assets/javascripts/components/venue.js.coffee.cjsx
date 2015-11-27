@Venue = React.createClass
  render: ->
    <div className='venueWrapper'>
      <div>{this.props.name}</div>
      <div>{this.props.city},&nbsp; {this.props.state}</div>
    </div>
