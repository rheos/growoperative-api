require_relative 'boot'

require 'rails/all'
require 'sprockets/railtie'

# Require the gems listed in Gemfile, including any gems
# you've limited to :test, :development, or :production.
Bundler.require(*Rails.groups)

if ['development', 'test'].include? ENV['RAILS_ENV']
  Dotenv::Railtie.load
end

module Realgrow
  class Application < Rails::Application
    # Initialize configuration defaults for originally generated Rails version
    config.load_defaults 8.1

    # Rails 7.2 default, deliberately NOT adopted.
    #
    # db/migrate/201811070122202_add_column_item_sumbol_to_item_unit.rb has a
    # 15-digit version prefix; valid Rails timestamps are 14 (there is a stray
    # trailing digit). With validation on, ActiveRecord raises
    # InvalidMigrationTimestampError inside maintain_test_schema!, which takes
    # the whole suite down before a single example runs.
    #
    # Renaming the file is not a safe fix: the migration is an unguarded
    # add_column, so a corrected filename reads as a pending migration and
    # Rails would try to re-add an existing column. Making that work means
    # rewriting schema_migrations on prod, demo and beta to chase a cosmetic
    # typo in a 2018 file. Rails documents this opt-out for exactly this case.
    #
    # New migrations are generated with valid timestamps regardless, so the
    # only thing lost is the guard against a future hand-edited filename.
    config.active_record.validate_migration_timestamps = false

    config.middleware.use ActionDispatch::Cookies
    config.middleware.use ActionDispatch::Session::CookieStore
    config.middleware.use ActionDispatch::Flash
    config.middleware.use Rack::MethodOverride

    # Settings in config/environments/* take precedence over those specified here.
    # Application configuration can go into files in config/initializers
    # -- all .rb files in that directory are automatically loaded after loading
    # the framework and any gems in your application.
  end
end
