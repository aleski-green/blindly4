require 'spec_helper'

RSpec.describe 'The Windows CLI contract', :windows do
  it 'requires explicit live opt-in for the clipboard fixture' do
    output, error, status = Open3.capture3({ 'BLINDLY4_LIVE' => nil },
                                         [Blindly::BINARY, Blindly::BINARY], '--test-pasteboard')
    expect(status.exitstatus).to eq(64)
    expect(error).to eq('')
    expect(JSON.parse(output)).to include('code' => 'usage_error', 'error' => 'Clipboard fixture requires BLINDLY4_LIVE=1')
  end

  it 'preserves the complete published schema-version-2 contract' do
    expected = JSON.parse(File.read(File.join(__dir__, 'fixtures', 'windows-schema-v2.json')))
    expect(success('schema')).to eq(expected)
  end

  it 'preserves command validation errors when the requested process has no visible window' do
    %w[inspect press].each do |command|
      result = cli(command, '--pid', Process.pid)
      expect(result.status).to eq(77)
      expect(result.json).to include('error' => "No visible windows for PID #{Process.pid}", 'code' => 'accessibility_error')
    end
    %w[actions focus].each do |command|
      result = cli(command, '--pid', Process.pid)
      expect(result.status).to eq(64)
      expect(result.json).to include('code' => 'usage_error')
    end
    result = cli('inspect', '--pid', Process.pid, '--path', 'malformed')
    expect(result.status).to eq(77)
    expect(result.json).to include('error' => "No visible windows for PID #{Process.pid}")
  end
  it 'accepts Windows function keys and numeric aliases before refusing an absent target' do
    %w[f01 f13 f24].each do |key|
      result = cli('key', '--key', key, '--pid', '2147483647')
      expect(result.status).to eq(77)
      expect(result.json).to include('code' => 'accessibility_error')
    end
  end

end
