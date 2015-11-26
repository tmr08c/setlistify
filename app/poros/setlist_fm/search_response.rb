module SetlistFm
  class SearchResponse
    def initialize(parsed_json_response)
      @response = parsed_json_response
    end

    def page
      @page ||= Integer(response.fetch('@page'))
    end

    def events
      @events ||= response.fetch('setlist').map { |setlist| Event.new(setlist) }
    end

    def as_json(_options = {})
      {
        events: events,
        page: page
      }
    end

    private

    attr_reader :response
  end
end
