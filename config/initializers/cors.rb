Rails.application.config.middleware.insert_before 0, Rack::Cors do
  allow do
    origins ENV['FRONTEND_URL'] || 'http://localhost:3000', 'http://localhost:8081', 'http://localhost:19006', 'http://10.0.1.6:3000', 'https://beta.growoperative.app'

    resource '*',
             headers: ['Origin', 'X-Requested-With', 'Content-Type', 'Accept', 'Authorization'],
             methods: [:get, :post, :delete, :put, :patch, :options, :head],
             credentials: true,
             max_age: 3600,
             expose_headers: ['access-token', 'expiry', 'token-type', 'uid', 'client']
  end
end
