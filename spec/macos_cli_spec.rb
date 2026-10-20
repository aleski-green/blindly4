require 'spec_helper'

RSpec.describe 'The macOS CLI contract', :macos do
  it 'keeps native error streams and rejects fixture launch without opt-in' do
    usage_error('--test-app') unless ENV['BLINDLY4_LIVE'] == '1'
    expect(cli('apps').json.fetch('apps')).to all(include('name', 'pid', 'bundleId'))
  end
  it 'keeps unsupported function keys out of native input' do
    %w[f01 f13 f24].each { |key| usage_error('key', '--key', key, '--pid', '2147483647') }
  end

end
