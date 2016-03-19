require 'spec_helper'
Venue = SetlistFm::SearchResponse::Event::Venue

describe SetlistFm::SearchResponse::Event do
  describe '#artist' do
    subject { described_class.new(response_with_artist_info) }
    let(:response_with_artist_info) do
      {
        'artist' => {
          '@disambiguation' => '',
          '@mbid' => 'a96ac800-bfcb-412a-8a63-0a98df600700',
          '@name' => 'Modest Mouse',
          '@sortName' => 'Modest Mouse',
          '@tmid' => '781346',
          'url' => 'http://www.setlist.fm/setlists/modest-mouse-73d6ae69.html'
        }
      }
    end

    it "should return the artist's name" do
      expect(subject.artist.name).to eq 'Modest Mouse'
    end
  end

  describe '#date' do
    subject { described_class.new(response_with_date) }
    let(:response_with_date) do
      {
        '@eventDate' => '22-10-2015'
      }
    end

    it 'should return a Date object containing the date' do
      expect(subject.date).to eq Date.new(2015, 10, 22)
    end
  end

  describe '#setlist' do
    subject { described_class.new({}) }
    let(:set_list_parser) do
      double(
        'set_list_parser',
        json_songs_array: [
          { '@name' => 'song1' },
          { '@name' => 'song2', 'info' => 'Meowed intro' },
          {
            '@name' => 'encore 1 song 1',
            'info' => 'walked off stage again after'
          },
          { '@name' => 'encore 2 song 1' },
          { '@name' => 'encore 2 song 2' }
        ]
      )
    end

    before do
      allow(SetlistFm::SearchResponse::SetListParser)
        .to receive(:new)
        .and_return(set_list_parser)
    end

    it 'should have the title of each song in order' do
      expect(subject.setlist.map(&:title)).to eq([
                                                   'song1',
                                                   'song2',
                                                   'encore 1 song 1',
                                                   'encore 2 song 1',
                                                   'encore 2 song 2'
                                                 ])
    end
  end

  describe '#venue' do
    it 'create a Venue using the venue hash' do
      response_with_venue = { 'venue' => { venue: :info } }

      expect(Venue).to receive(:new).with(venue: :info)

      described_class.new(response_with_venue).venue
    end
  end

  describe '#url' do
    subject { described_class.new(setlist_with_url) }
    let(:setlist_with_url) do
      { 'url' => 'http://www.setlist.fm/events/1' }
    end

    it 'should have a link to the setlist.fm page' do
      expect(subject.url).to eq 'http://www.setlist.fm/events/1'
    end
  end

  describe '#as_json' do
    subject { described_class.new(setlists) }
    let(:setlists) do
      {
        '@eventDate' => '22-10-2015',
        'artist' => { '@name' => 'Hip Band Name' },
        'venue' => {
          '@name' => 'Hip Club',
          'city' => {
            '@name' => 'Brooklyn',
            '@state' => 'New York'
          },
          'country' => {
            '@code' => 'US',
            '@name' => 'United States'
          }
        },
        'sets' => {
          'set' => [
            {
              'song' => [
                { '@name' => 'song1' },
                { '@name' => 'song2' }
              ]
            }
          ]
        },
        'url' => 'setlist.fm/setliests/1'
      }
    end

    it 'should include nice versions of all the info' do
      expect(JSON.parse(subject.as_json)).to eq(
        'artist' => { 'name' => 'Hip Band Name' },
        'date' => '2015-10-22',
        'setlist' => [
          { 'title' => 'song1' },
          { 'title' => 'song2' }
        ],
        'venue' => {
          'name' => 'Hip Club',
          'city' => 'Brooklyn',
          'state' => 'New York'
        }
      )
    end
  end
end
