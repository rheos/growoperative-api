# This file is copied to spec/ when you run 'rails generate rspec:install'
require 'spec_helper'
ENV['RAILS_ENV'] ||= 'test'
require File.expand_path('../../config/environment', __FILE__)
require 'database_cleaner'

abort("The Rails environment is running in production mode!") if Rails.env.production?
require 'rspec/rails'

begin
  ActiveRecord::Migration.maintain_test_schema!
rescue ActiveRecord::PendingMigrationError => e
  puts e.to_s.strip
  exit 1
end

Dir[Rails.root.join('spec/support/**/*.rb')].sort.each { |f| require f }

def RSpec.set_user(name)
  @current_user = name
end

def RSpec.current_user
  @current_user || "bob"
end

RSpec.configure do |config|
  config.fixture_path = "#{::Rails.root}/spec/fixtures"
  config.use_transactional_fixtures = false
  config.infer_spec_type_from_file_location!
  config.filter_rails_from_backtrace!
  config.include FactoryBot::Syntax::Methods

  # config.before do
  #   Rails.application.load_seed
  # end

  config.before(:each) do |test|
    unless test.metadata[:skip_hooks]
      DatabaseCleaner.strategy = :deletion
      DatabaseCleaner.clean_with(:truncation)
      Rails.application.load_seed
    end
  end

  config.after(:each) do |test|
    unless test.metadata[:skip_hooks]
      DatabaseCleaner.strategy = :deletion
      DatabaseCleaner.clean_with(:truncation)
    end
  end

  # config.after(:all) do
  #   DatabaseCleaner.strategy = :transaction
  #   DatabaseCleaner.clean_with(:truncation)
  # end


end
