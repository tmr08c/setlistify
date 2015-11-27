# Place all the behaviors and hooks related to the matching controller here.
# All this logic will automatically be available in application.js.
# You can use CoffeeScript in this file: http://coffeescript.org/
$ ->
 $('#setlist_search_form')
   .on 'ajax:success', (e, data, status, xhr) ->
     ReactDOM.render(<SetlistList page=data.page events=data.events />,  document.getElementById('content'))
   .on "ajax:error", (e, xhr, status, error) ->
      # TODO: Better error handling
      console.log 'ERROR'
