require 'rails_helper'

RSpec.describe 'Bootstrap account seeding' do
  it 'preserves an existing password when seeds run again' do
    admin = User.find_by!(user_name: 'robin')
    admin.update!(password: 'changed-local-password')
    digest = admin.encrypted_password

    Rails.application.load_seed

    expect(admin.reload.encrypted_password).to eq(digest)
    expect(admin.valid_password?('changed-local-password')).to be(true)
  end

  it 'uses the configured password only when creating the account' do
    User.find_by!(user_name: 'robin').destroy!
    allow(ENV).to receive(:[]).and_call_original
    allow(ENV).to receive(:[]).with('SEED_ADMIN_PASSWORD').and_return('configured-local-password')

    Rails.application.load_seed

    expect(User.find_by!(user_name: 'robin').valid_password?('configured-local-password')).to be(true)
  end

  it 'generates an unshared password outside the test environment' do
    User.find_by!(user_name: 'robin').destroy!
    allow(ENV).to receive(:[]).and_call_original
    allow(ENV).to receive(:[]).with('SEED_ADMIN_PASSWORD').and_return(nil)
    allow(Rails.env).to receive(:test?).and_return(false)
    allow(SecureRandom).to receive(:hex).with(32).and_return('generated-local-password')

    Rails.application.load_seed

    admin = User.find_by!(user_name: 'robin')
    expect(admin.valid_password?('generated-local-password')).to be(true)
    expect(admin.valid_password?('password')).to be(false)
  end
end
