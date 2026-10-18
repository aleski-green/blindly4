require 'spec_helper'

RSpec.describe 'The Windows CLI contract', :windows do
  it 'preserves the complete published schema-version-2 contract' do
    expected = JSON.parse(File.read(File.join(__dir__, 'fixtures', 'windows-schema-v2.json')))
    expect(success('schema')).to eq(expected)
  end

  it 'rejects duplicate options instead of silently overriding them' do
    usage_error('tree', '--depth', '2', '--depth', '3')
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

  %w[-1 65 2147483648 x].each do |depth|
    it "rejects invalid tree depth #{depth}" do
      usage_error('tree', '--depth', depth)
    end
  end

  %w[NaN inf -inf 1e999 100001].each do |coordinate|
    it "rejects invalid click coordinate #{coordinate} before emitting input" do
      usage_error('click', '--x', coordinate, '--y', '0')
    end
  end

  ['file:///C:/test', 'javascript:alert(1)', 'shell:AppsFolder', 'relative', 'https://', 'slack:'].each do |url|
    it "refuses to open unsupported URL #{url.inspect}" do
      usage_error('open', '--url', url)
    end
  end

  ['ctrl+bogus', 'unknown+a', '', 'ctrl+', 'f0', 'f25'].each do |key|
    it "rejects invalid key #{key.inspect} before emitting input" do
      usage_error('key', '--key', key)
    end
  end

  [ %w[key --key return --target-path 0 --require-value draft],
    %w[key --key return --pid 1 --target-path 0],
    %w[key --key return --pid 1 --require-value draft],
    %w[press --path 0 --require-value draft],
    %w[press --path 0 --require-value-path 0],
    %w[paste --target-path 0 --text draft],
    %w[scroll --direction diagonal], %w[scroll --direction down --amount 0],
    %w[tree --pid 0], %w[tree --max-nodes 0], %w[find --limit 0 --title Draft] ].each do |arguments|
    it "refuses incomplete or unsafe input #{arguments.inspect}" do
      usage_error(*arguments)
    end
  end
end
