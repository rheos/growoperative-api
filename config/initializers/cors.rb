Rails.application.config.middleware.insert_before 0, Rack::Cors do
  allow do
    origins ENV['FRONTEND_URL'] || 'http://localhost:3000', 'http://localhost:3001'

    resource '*',
             headers: ['Origin', 'X-Requested-With', 'Content-Type', 'Accept', 'Authorization'],
             methods: [:get, :post, :delete, :put, :patch, :options, :head],
             credentials: true,
             max_age: 3600,
             expose_headers: ['access-token', 'expiry', 'token-type', 'uid', 'client']
  end
end
