@SetlistList = React.createClass
  render: ->
    <div>
      {
        this.props.events.map (event, index) ->
          event = JSON.parse(event)

          <Setlist
            key=index
            artist=event.artist.name
            date=event.date
            setlist=event.setlist
            venue=event.venue
          />
      }
    </div>
