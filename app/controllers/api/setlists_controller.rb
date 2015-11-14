module Api
  class SetlistsController < ApplicationController
    def index
      search_response = SetlistFm::Searcher.new.search_by_artist(params[:query])

      render json: search_response
    end
  end
end
