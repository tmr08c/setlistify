module SetlistFm
  class SearchResponse
    class Event
      class Venue
        def initialize(venue_info_hash)
          @venue_info_hash = venue_info_hash
        end

        def as_json(_options = {})
          {
            name: name,
            city: city,
            state: state
          }
        end

        def name
          venue_info_hash['@name']
        end

        def city
          city_info['@name']
        end

        def state
          city_info['@state'] || country
        end

        def country
          country_info['@name']
        end

        private

        attr_reader :venue_info_hash

        def city_info
          @city_info ||=
            venue_info_hash['city'] || {}
        end

        def country_info
          @country_info ||=
            city_info['country'] || {}
        end
      end
    end
  end
end
