module SetlistFm
  class SearchApi < Api
    #
    # `entity` is a string representing the type of element you are serching for
    #
    # Check the [api reference](http://api.setlist.fm/docs/index.html)
    # for what can be searched on
    def initialize(entity)
      @entity = entity
    end

    def search_by(query_hash = {})
      self.class.get(
        "/#{version}/#{service}/#{entity}.json",
        query: query_hash
      ).fetch(entity)
    end

    private

    attr_reader :entity

    def service
      'search'.freeze
    end
  end
end
