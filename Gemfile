source 'https://rubygems.org'
git_source(:github) { |repo| "https://github.com/#{repo}.git" }

ruby '3.4.11'

# Bundle edge Rails instead: gem 'rails', github: 'rails/rails'
gem 'rails', '~> 8.1.4'
# Use sqlite3 as the database for Active Record
gem 'pg', '~> 1.5'
# csv stopped being a default gem in Ruby 3.4, so `require "csv"` no longer
# resolves without declaring it. Used by lib/tasks/foaf_custody.rake. That is
# a rake task, which the suite never loads, so a green suite would NOT have
# caught this - the task would simply have failed the next time it was run.
# base64 also left the default gems (lib/auth_foaf_client.rb requires it) but
# arrives via activesupport, so it needs no entry.
gem 'csv', '~> 3.3'
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
gem 'carrierwave', '~> 3.1'
gem 'fog-aws'
gem "rmagick", '~> 7.1'
gem 'devise_invitable', '~> 2.0'

group :development, :test do
  # Call 'byebug' anywhere in the code to stop execution and get a debugger console
  gem 'dotenv-rails', '~> 2.7'
  gem 'byebug', '~> 13.0'
  gem 'rspec-rails', '~> 8.0'
  gem 'factory_bot_rails', '~> 6.5'
  gem 'pry-rails', '~> 0.3'
  gem 'pry-byebug', '~> 3.10'
  gem 'pry-stack_explorer', '~> 0.6'
end

group :development do
  # Access an interactive console on exception pages or by calling 'console' anywhere in the code.
  gem 'web-console', '~> 3.7'
  gem 'listen', '~> 3.8'
  # Spring speeds up development by keeping your application running in the background. Read more: https://github.com/rails/spring
  # mutex_m left Ruby 3.4's default gems. spring 2.1.1 requires it via
  # spring-watcher-listen and is unmaintained, so it will not be fixed
  # upstream. Declared here rather than removing spring, to keep this PR to
  # one variable; dropping spring entirely is a reasonable follow-up, since
  # Rails dropped it from the default Gemfile in 7.x and everything here runs
  # in Docker anyway.
  #
  # Worth noting this did NOT show up in the suite: spring is development-group
  # only, so RAILS_ENV=test never loads it. It broke `bin/rails` in
  # development while 735 examples stayed green.
  gem 'mutex_m'
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

# Error tracking. Inert without SENTRY_DSN, which is set only on production.
gem 'sentry-ruby', '~> 7.0'
gem 'sentry-rails', '~> 7.0'
