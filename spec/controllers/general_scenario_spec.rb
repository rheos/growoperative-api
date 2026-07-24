require 'rails_helper'

RSpec.describe 'Legacy global scenario test', type: :request do
  it 'needs a Bearer-only auth.foaf.io rewrite before it can run again',
     skip: 'Retired legacy /login and /signup flow; use focused request specs and scripts/trade_test.py for current coverage.'
end
