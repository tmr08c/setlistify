@SearchPage = React.createClass
  render: ->
    <div id='searchBox'>
      <form action='/search' method='GET' autoComplete='off'>
        <label htmlFor='query'>Search For:</label>
        <input type='text', name='query' id='query' ref='query' />

        <button type='submit' className='waves=effects waves-light btn'>Search</button>
      </form>
    </div>
