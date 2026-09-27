require 'rails_helper'

RSpec.describe 'Devise secret configuration', skip_hooks: true do
  around do |example|
    original_secret = Devise.secret_key
    original_jwt_secret = Devise::JWT.config.secret
    example.run
  ensure
    Devise.secret_key = original_secret
    Devise::JWT.config.secret = original_jwt_secret
  end

  before do
    allow(ENV).to receive(:[]).and_call_original
    allow(Rails.application).to receive(:secret_key_base).and_return('runtime-rails-secret')
  end

  it 'uses separately configured keys when supplied' do
    allow(ENV).to receive(:[]).with('DEVISE_SECRET_KEY').and_return('runtime-devise-secret')
    allow(ENV).to receive(:[]).with('DEVISE_JWT_SECRET_KEY').and_return('runtime-jwt-secret')

    load Rails.root.join('config/initializers/devise.rb')

    expect(Devise.secret_key).to eq('runtime-devise-secret')
    expect(Devise::JWT.config.secret).to eq('runtime-jwt-secret')
  end

  it 'uses the Rails secret for absent or blank overrides' do
    allow(ENV).to receive(:[]).with('DEVISE_SECRET_KEY').and_return(nil)
    allow(ENV).to receive(:[]).with('DEVISE_JWT_SECRET_KEY').and_return('')

    load Rails.root.join('config/initializers/devise.rb')

    expect(Devise.secret_key).to eq('runtime-rails-secret')
    expect(Devise::JWT.config.secret).to eq('runtime-rails-secret')
  end
end
