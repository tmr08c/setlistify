module SetlistFm
  class Api
    include HTTParty
    base_uri 'api.setlist.fm/rest'.freeze

    private

    def version
      '0.1'.freeze
    end

    def service
      fail NotImplementedError
    end
  end
end
