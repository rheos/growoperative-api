require 'rails_helper'

# The point of this endpoint is that it FAILS when the database is gone.
# "/up" returns a static 200 and auth.foaf.io rendered a static hash, which is
# why the 2026-09 outage was invisible for three days. So the example that
# matters most here is the unhappy one.
RSpec.describe 'Health', type: :request, skip_hooks: true do
  it 'returns 200 and reports the database when it is reachable' do
    get '/v1/health'

    expect(response).to have_http_status(:ok)
    body = JSON.parse(response.body)
    expect(body['status']).to eq('ok')
    expect(body['database']).to eq('ok')
  end

  it 'needs no authentication, so a monitor can call it' do
    get '/v1/health'

    expect(response).to have_http_status(:ok)
  end

  it 'returns 503 when the database is unreachable' do
    allow(ActiveRecord::Base.connection)
      .to receive(:select_value)
      .and_raise(ActiveRecord::ConnectionNotEstablished, 'connection refused')

    get '/v1/health'

    expect(response).to have_http_status(:service_unavailable)
    body = JSON.parse(response.body)
    expect(body['status']).to eq('error')
    expect(body['database']).to eq('unreachable')
  end

  it 'does not put connection details in the response body' do
    allow(ActiveRecord::Base.connection)
      .to receive(:select_value)
      .and_raise(ActiveRecord::ConnectionNotEstablished, 'host=secret-db.internal password=hunter2')

    get '/v1/health'

    expect(response).to have_http_status(:service_unavailable)
    expect(response.body).not_to include('hunter2')
    expect(response.body).not_to include('secret-db.internal')
  end
end
