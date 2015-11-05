require 'spec_helper'

describe SetlistFm::SearchResponse do
  let(:api_response) do
    response = JSON.parse(File.read('./spec/fixtures/sample_response.json'))
    response.fetch('setlists')
  end

  describe '#page' do
    subject { described_class.new(api_response) }

    it 'should include which page or results this is assoacited with' do
      expect(subject.page).to eq 1
    end
  end

  describe '#events' do
    context 'when there are events' do
      subject { described_class.new(api_response) }

      it 'should return an event instance for each matching record' do
        expect(subject.events.size).to eq 2
      end

      it 'should have a date' do
        event = subject.events.first

        expect(event.date).to eq Date.new(2015, 10, 22)
      end

      it 'should have the artist' do
        event = subject.events.first

        expect(event.artist.name).to eq 'Modest Mouse'
      end

      it 'should have a venus' do
        event = subject.events.first

        expect(event.venue.name).to eq 'The Space at Westbury'
        expect(event.venue.city).to eq 'Westbury'
        expect(event.venue.state).to eq 'New York'
      end

      it 'should have a setlist' do
        event = subject.events.first

        expect(event.setlist.size).to eq 23
      end

      it 'should have a title for songs in the set list' do
        event = subject.events.first
        song = event.setlist.first

        expect(song.title).to eq 'Strangers to Ourselves'
      end
    end
  end
end
