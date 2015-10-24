module SetlistFm
  class SearchResponse
    class Event
      Artist = Struct.new(:name)
      Song = Struct.new(:title)
      Venue = Struct.new(:name, :city, :state)

      def initialize(setlist_json_response)
        @response = setlist_json_response
      end

      def artist
        artist_json = response.fetch('artist')

        Artist.new(artist_json.fetch('@name'))
      end

      def date
        Date.parse(response.fetch('@eventDate'))
      end

      def setlist
        songs = SetListParser.new(response).json_songs_array

        songs.map do |song_json|
          Song.new(song_json.fetch('@name'))
        end
      end

      def venue
        venue_json = response.fetch('venue')

        Venue.new(
          venue_json.fetch('@name'),
          venue_json.fetch('city').fetch('@name'),
          venue_json.fetch('city').fetch('@state')
        )
      end

      def url
        response.fetch('url')
      end

      private

      attr_reader :response

      def songlist_json_array
        sets_json = response.fetch('sets')
        Array[sets_json.fetch('set')].flatten
      end
    end
  end
end
