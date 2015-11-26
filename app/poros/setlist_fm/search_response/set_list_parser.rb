module SetlistFm
  class SearchResponse
    class SetListParser
      def initialize(json_of_sets)
        @response = json_of_sets
      end

      def json_songs_array
        inner_set_list_json.each_with_object([]) do |setlist_entry, songs|
          songs.concat([setlist_entry.fetch('song')])
        end.flatten
      end

      private

      attr_reader :response

      def inner_set_list_json
        outer_sets = response.fetch('sets')

        # API returns an empty string if no set informatin exists
        if outer_sets.blank?
          []
        else
          Array[outer_sets.fetch('set')].flatten
        end
      end
    end
  end
end
