require 'spec_helper'

describe SetlistFm::SearchResponse::Event::Venue do
  describe '#name' do
    it 'should use the @name attribute' do
      venue_hash = { '@name' => 'venue name' }
      venue = described_class.new(venue_hash)

      expect(venue.name).to eq 'venue name'
    end
  end

  describe '#city' do
    it 'should use the @name value in the city hash' do
      venue_hash = { 'city' => { '@name' => 'Westbury' } }
      venue = described_class.new(venue_hash)

      expect(venue.city).to eq 'Westbury'
    end
  end

  describe '#state' do
    context 'when the state name is avilable in the response hash' do
      it "should use the city's state @name" do
        venue_hash = { 'city' => { '@state' => 'New York' } }

        venue = described_class.new(venue_hash)

        expect(venue.state).to eq 'New York'
      end

      context 'when there is no state in the response hash' do
        it 'should use the country' do
          venue_hash = { 'city' => { 'country' => { '@name' => 'Greece' } } }
          venue = described_class.new(venue_hash)

          expect(venue.state).to eq 'Greece'
        end
      end
    end
  end

  describe '#to_json' do
    it 'should return the name, city, and state in a JSON format' do
      venue_hash = {
        '@name' => 'venue name',
        'city' => {
          '@name' => 'venue city',
          '@state' => 'venue state'
        }
      }
      event = described_class.new(venue_hash)
      event_json = JSON.parse(event.to_json)

      expect(event_json).to eq(
        'name' => 'venue name',
        'city' => 'venue city',
        'state' => 'venue state'
      )
    end
  end
end
