@App = React.createClass
  render: ->
    <div id='content'>
      <RouteHandler {...this.props}/>
    </div>
