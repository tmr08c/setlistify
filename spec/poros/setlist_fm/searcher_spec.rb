require 'spec_helper'

describe SetlistFm::Searcher do
  describe '#search_by' do
    context 'when searching by artist name' do
      subject { described_class.new }

      it "should have an event with the artist's name" do
        results = subject.search_by_artist('modest mouse')
        event = results.events.first

        expect(event.artist.name).to match /modest mouse/i
      end
    end
  end
end
