Rails.application.config.middleware.insert_before 0, Rack::Cors do
  allow do
    origins 'https://dev.foaf.io'

    resource '*',
             headers: :any,
             # expose: ['Authorization'],
             methods: [:get, :post, :delete, :put, :patch, :options, :head],
             credentials: true
  end
end
