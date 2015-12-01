@SetlistList = React.createClass
  componentDidMount: ->
    searchValue = this.props.query.query

    $.ajax
      url: '/api/setlists',
      data:
        query: searchValue,
      dataType: 'json'
      success: (data) =>
        this.setState(data)

  render: ->
    <div>
      {
        if this.state && this.state.events
          this.state.events.map (event, index) ->
            event = JSON.parse(event)

            <Setlist
              key=index
              artist=event.artist.name
              date=event.date
              setlist=event.setlist
              venue=event.venue
            />
        else
          <div>Fetching playlists</div>
      }
    </div>
