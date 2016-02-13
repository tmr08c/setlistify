@Route = ReactRouter.Route
@DefaultRoute = ReactRouter.DefaultRoute
@RouteHandler = ReactRouter.RouteHandler
@Navigation = ReactRouter.Navigation
@History = ReactRouter.History
@Link = ReactRouter.Link


@MyRoutes = (
  <Route handler={App}>
    <DefaultRoute handler={SearchPage} />
    <Route path='search' handler={SetlistList} />
    <Route path='spotifycallback' handler={SpotifyCallback} />
  </Route>
)
