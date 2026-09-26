source 'https://rubygems.org'
git_source(:github) { |repo| "https://github.com/#{repo}.git" }

ruby '3.2.11'

# Bundle edge Rails instead: gem 'rails', github: 'rails/rails'
gem 'rails', '~> 7.2.4'
# Use sqlite3 as the database for Active Record
gem 'pg', '~> 1.5'
# Use Puma as the app server
gem 'puma', '~> 8.0'
gem 'sprockets-rails'
# Build JSON APIs with ease. Read more: https://github.com/rails/jbuilder
gem 'jbuilder', '~> 2.15'
gem 'jwt'
gem 'jsonapi-serializer'
gem "foaf_client",
    git: "https://github.com/rheos/foaf-client.git",
    tag: "v0.2.0",
    glob: "gem/*.gemspec"


gem 'aws-sdk-s3', '~> 1.130.0', require: false



# Use Redis adapter to run Action Cable in production
# gem 'redis', '~> 4.0'
# Use ActiveModel has_secure_password
# gem 'bcrypt', '~> 3.1.7'

# Use ActiveStorage variant
# gem 'mini_magick', '~> 4.8'

# Use Capistrano for deployment
# gem 'capistrano-rails', group: :development

# Reduces boot times through caching; required in config/boot.rb
gem 'bootsnap', '>= 1.17.0', require: false
# gem 'devise_token_auth'
# gem 'omniauth'
gem 'active_model_serializers', '~> 0.10.16'
gem 'devise',           '~> 5.0'
gem 'devise-jwt'
gem 'carrierwave', '~> 2.0'
gem 'fog-aws'
gem "rmagick", '~> 7.1'
gem 'devise_invitable', '~> 2.0'

group :development, :test do
  # Call 'byebug' anywhere in the code to stop execution and get a debugger console
  gem 'dotenv-rails', '~> 2.7'
  gem 'byebug', '~> 13.0'
  gem 'rspec-rails', '~> 6.1'
  gem 'factory_bot_rails', '~> 6.1'
  gem 'pry-rails', '~> 0.3'
  gem 'pry-byebug', '~> 3.10'
  gem 'pry-stack_explorer', '~> 0.6'
end

group :development do
  # Access an interactive console on exception pages or by calling 'console' anywhere in the code.
  gem 'web-console', '~> 3.7'
  gem 'listen', '~> 3.8'
  # Spring speeds up development by keeping your application running in the background. Read more: https://github.com/rails/spring
  gem 'spring', '~> 2.1'
  gem 'spring-watcher-listen', '~> 2.0.0'
end

group :test do
  # Adds support for Capybara system testing and selenium driver
  gem 'nokogiri', '>= 1.15'
  gem 'capybara', '~> 3.35'
  gem 'selenium-webdriver', '>= 4.11', '< 5'
  gem 'database_cleaner', '~> 2.0'
end

# Windows does not include zoneinfo files, so bundle the tzinfo-data gem
gem 'tzinfo-data', '~> 1.2026.4'
gem 'rack-cors', '~> 2.0'
