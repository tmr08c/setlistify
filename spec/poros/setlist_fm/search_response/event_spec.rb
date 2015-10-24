require 'spec_helper'

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
          'url' => "http:\/\/www.setlist.fm\/setlists\/modest-mouse-73d6ae69.html"
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
    context 'when there is no encore' do
      subject { described_class.new(response_with_setlist_with_no_encore) }
      let(:response_with_setlist_with_no_encore) do
        {
          'sets' => {
            'set' => {
              'song' => [
                {
                  '@name' => 'I Need My Girl',
                  'with' => {
                    '@disambiguation' => '',
                    '@mbid' => 'a3de3425-e96b-4857-a35c-e949fab8d80b',
                    '@name' => 'Lauren Mayberry',
                    '@sortName' => 'Mayberry, Lauren',
                    'url' => 'http://www.setlist.fm/setlists/lauren-mayberry-1bdd8dd0.html'
                  }
                },
                {
                  '@name' => 'This Is the Last Time'
                },
                {
                  '@name' => 'Peggy-O',
                  'cover' => {
                    '@disambiguation' => '',
                    '@mbid' => '6faa7ca7-0d99-4a5e-bfa6-1fd5037520c6',
                    '@name' => 'Grateful Dead',
                    '@sortName' => 'Grateful Dead',
                    '@tmid' => '735200',
                    'url' => 'http://www.setlist.fm/setlists/grateful-dead-bd6ad4a.html'
                  }
                },
                {
                  '@name' => 'Pink Rabbits'
                },
                {
                  '@name' => 'England'
                },
                {
                  '@name' => 'Graceless'
                },
                {
                  '@name' => 'Mr. November'
                },
                {
                  '@name' => 'Terrible Love'
                }
              ]
            }
          }
        }
      end

      it 'should have an entry for each song' do
        expect(subject.setlist.size).to eq 8
      end

      it 'should have the title of each song in order' do
        expect(subject.setlist.map(&:title)).to eq [
          'I Need My Girl',
          'This Is the Last Time',
          'Peggy-O',
          'Pink Rabbits',
          'England',
          'Graceless',
          'Mr. November',
          'Terrible Love'
        ]
      end
    end

    context 'when there is an encore' do
      subject { described_class.new(response_with_setlist_with_encore) }
      let(:response_with_setlist_with_encore) do
        {
          'sets' => {
            'set' => [
              {
                'song' => [
                  {
                    '@name' => 'song1'
                  },
                  {
                    '@name' => 'song2',
                    'info' => 'Meowed intro'
                  }
                ]
              },
              {
                '@encore' => '1',
                'song' => [
                  {
                    '@name' => 'encore 1 song 1',
                    'info' => 'walked off stage again after'
                  }
                ]
              },
              {
                '@encore' => '2',
                'song' => [
                  {
                    '@name' => 'encore 2 song 1'
                  },
                  {
                    '@name' => 'encore 2 song 2'
                  }
                ]
              }
            ]
          }
        }
      end

      it 'should hav an entry for each song' do
        expect(subject.setlist.size).to eq 5
      end

      it 'should have the title of each song in order' do
        expect(subject.setlist.map(&:title)).to eq [
          'song1', 'song2', 'encore 1 song 1', 'encore 2 song 1', 'encore 2 song 2'
        ]
      end
    end

    describe '#venue' do
      subject { described_class.new(response_with_venue) }
      let(:response_with_venue) do
        {
          'venue' => {
            '@id' => '53d483fd',
            '@name' => 'The Space at Westbury',
            'city' => {
              '@id' => '5144040',
              '@name' => 'Westbury',
              '@state' => 'New York',
              '@stateCode' => 'NY',
              'coords' => {
                '@lat' => '40.7556561',
                '@long' => '-73.5876273'
              },
              'country' => {
                '@code' => 'US',
                '@name' => 'United States'
              }
            },
            'url' => "http => \/\/www.setlist.fm\/venue\/the-space-at-westbury-westbury-ny-usa-53d483fd.html"
          }
        }
      end

      it 'should have a name' do
        expect(subject.venue.name).to eq 'The Space at Westbury'
      end

      it 'should have a city' do
        expect(subject.venue.city).to eq 'Westbury'
      end

      it 'should have a state' do
        expect(subject.venue.state).to eq 'New York'
      end
    end

    describe '#url' do
      subject { described_class.new(setlist_with_url) }
      let(:setlist_with_url) do
        { 'url' => 'http://www.setlist.fm/events/1' }
      end

      it 'shold have a link to the setlist.fm page' do
        expect(subject.url).to eq 'http://www.setlist.fm/events/1'
      end
    end
  end
end
