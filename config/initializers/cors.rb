Rails.application.config.middleware.insert_before 0, Rack::Cors do
  allow do
    origins ENV['FRONTEND_URL']

    resource '*',
             headers: :any,
             methods: [:get, :post, :delete, :put, :patch, :options, :head],
             credentials: true
  end
end
