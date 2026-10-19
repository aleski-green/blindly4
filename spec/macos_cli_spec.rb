require 'spec_helper'

RSpec.describe 'The macOS CLI contract', :macos do
  it 'keeps native error streams and rejects fixture launch without opt-in' do
    usage_error('--test-app') unless ENV['BLINDLY4_LIVE'] == '1'
    expect(cli('apps').json.fetch('apps')).to all(include('name', 'pid', 'bundleId'))
  end
end
