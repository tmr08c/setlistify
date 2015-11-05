module SetlistFm
  class Searcher
    def initialize(api = SetlistFm::SearchApi.new('setlists'))
      @api = api
    end

    def search_by_artist(artist_name)
      search_resuls = search('artistName' => artist_name)

      SetlistFm::SearchResponse.new(search_resuls)
    end

    private

    attr_reader :api

    def search(query_hash)
      api.search_by(query_hash)
    end
  end
end
