require 'spec_helper'

describe SetlistFm::SearchResponse::SetListParser do
  describe '#json_songs_array' do
    # the setlist.fm api returns an empty string when setlist isn't available
    context 'when there is no setlist available' do
      subject { described_class.new('sets' => '') }

      it 'should return an empty array' do
        expect(subject.json_songs_array).to eq([])
      end
    end

    context 'when there is only one song' do
      # the setlist.fm api doest not return an array if there is only one song
      subject do
        described_class.new(
          'sets' => { 'set' => { 'song' => { '@name' => 'song1' } } }
        )
      end

      it 'should return an array with the single song' do
        expect(subject.json_songs_array).to eq [{ '@name' => 'song1' }]
      end
    end

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
                    'url' => 'www.setlist.fm/setlists/lauren-mayberry.html'
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
                    'url' => 'www.setlist.fm/setlists/grateful-dead.html'
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

      it 'should return an array with the json for all songs played' do
        expect(subject.json_songs_array).to eq([
          {
            '@name' => 'I Need My Girl',
            'with' => {
              '@disambiguation' => '',
              '@mbid' => 'a3de3425-e96b-4857-a35c-e949fab8d80b',
              '@name' => 'Lauren Mayberry',
              '@sortName' => 'Mayberry, Lauren',
              'url' => 'www.setlist.fm/setlists/lauren-mayberry.html'
            }
          },
          { '@name' => 'This Is the Last Time' },
          {
            '@name' => 'Peggy-O',
            'cover' => {
              '@disambiguation' => '',
              '@mbid' => '6faa7ca7-0d99-4a5e-bfa6-1fd5037520c6',
              '@name' => 'Grateful Dead',
              '@sortName' => 'Grateful Dead',
              '@tmid' => '735200',
              'url' => 'www.setlist.fm/setlists/grateful-dead.html'
            }
          },
          { '@name' => 'Pink Rabbits' },
          { '@name' => 'England' },
          { '@name' => 'Graceless' },
          { '@name' => 'Mr. November' },
          { '@name' => 'Terrible Love' }
        ])
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

      it 'should return an array with the json for all songs played' do
        expect(subject.json_songs_array).to eq([
          { '@name' => 'song1' },
          { '@name' => 'song2', 'info' => 'Meowed intro' },
          {
            '@name' => 'encore 1 song 1',
            'info' => 'walked off stage again after'
          },
          { '@name' => 'encore 2 song 1' },
          { '@name' => 'encore 2 song 2' }
        ])
      end
    end
  end
end
