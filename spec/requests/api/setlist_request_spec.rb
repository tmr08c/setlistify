require 'spec_helper'

describe 'Searching setlist spec', type: :request do
  describe 'GET /api/setlists' do
    let(:request_url) { '/api/setlists' }
    let(:request_options) { { format: 'json' } }
    let(:requst_html_options) { { 'Accept' => 'application/json' } }

    context 'when there is a search query' do
      it 'should inclue the page number' do
        VCR.use_cassette('modern baseball search') do
          get(
            request_url,
            request_options.merge(query: 'modern+baseball'),
            requst_html_options
          )
          results = json(response.body)

          expect(results[:page]).to eq 1
        end
      end

      it 'should incluce events' do
        VCR.use_cassette('modern baseball search') do
          get(
            request_url,
            request_options.merge(query: 'modern+baseball'),
            requst_html_options
          )
          results = json(response.body)

          expect(results[:events].size).to eq 20
        end
      end

      it 'returns Posts' do
        VCR.use_cassette('modern baseball search') do
          get(
            request_url,
            request_options.merge(query: 'modern+baseball')
          )

          expect(response.status).to eq 200
          expect(response).to match_response_schema('search_response')
        end
      end
    end
  end
end
