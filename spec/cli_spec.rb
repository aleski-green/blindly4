require 'spec_helper'

RSpec.describe 'The public CLI' do
  it 'rejects duplicate options instead of silently overriding them' do
    usage_error('tree', '--depth', '2', '--depth', '3')
  end

  it 'describes all 22 commands through schema version 2' do
    schema = success('schema')
    expect(schema.fetch('schemaVersion')).to eq(2)
    expect(schema.fetch('commands').map { |command| command.fetch('name') }).to match_array(Blindly::COMMANDS)
    schema.fetch('commands').each do |command|
      expect(command).to include('usage' => a_string_starting_with("blindly4 #{command.fetch('name')}"),
                                'summary' => a_string_matching(/\S/),
                                'options' => an_instance_of(Array),
                                'requiresAccessibility' => satisfy { |value| [true, false].include?(value) })
    end
  end

  it 'warns callers which commands can commit an external action' do
    commands = success('schema').fetch('commands').to_h { |command| [command.fetch('name'), command] }
    %w[press key].each { |name| expect(commands.fetch(name).fetch('risk')).to eq('external-commit') }
    %w[schema apps tree show find focused inspect actions].each do |name|
      expect(commands.fetch(name).fetch('risk')).to eq('read-only')
    end
    %w[scroll scroll-to].each { |name| expect(commands.fetch(name).fetch('risk')).to eq('ui-mutation') }
    expect(commands.fetch('key').fetch('options')).to include('pid', 'target-path', 'require-value')
    expect(commands.fetch('press').fetch('options')).to include('require-selected', 'require-value-path', 'require-value')
  end

  it 'keeps profiling on stderr and retains no profiling state between invocations' do
    first = cli('schema')
    profiled = cli('schema', '--profile')
    second = cli('schema')
    expect([first.status, profiled.status, second.status]).to eq([0, 0, 0])
    expect(profiled.stdout).to eq(first.stdout)
    expect(second.stdout).to eq(first.stdout)
    expect([first.stderr, second.stderr]).to eq(['', ''])
    expect(profiled.stderr).to match(/elapsed/i)
    expect(profiled.stderr).not_to include('cache_')
  end

  [[], ['--help'], ['help']].each do |arguments|
    it "explains the available commands for #{arguments.inspect}" do
      result = cli(*arguments)
      expect(result.status).to eq(0)
      expect(result.stdout).to include('schema', 'paste', 'key')
      expect(result.stderr).to eq('')
    end
  end

  Blindly::COMMANDS.each do |command|
    it "explains #{command} without requiring desktop access" do
      result = cli(command, '--help')
      expect(result.status).to eq(0)
      expect(result.stdout).to include("blindly4 #{command}")
      expect(result.stderr).to eq('')
    end

    it "rejects an unknown option for #{command} before doing any work" do
      usage_error(command, '--not-a-real-option', 'value')
    end
  end

  %w[serve workflow snapshot changes unknown-command --self-test --integration-test].each do |command|
    it "rejects the unsupported command #{command}" do
      usage_error(command)
    end
  end

  [ %w[--no-service schema], %w[schema --no-log], %w[schema --lease old-token],
    %w[schema unexpected], %w[tree --depth], %w[find --titel Settings],
    %w[type --text], %w[paste --target-path],
    %w[type --text help --not-a-real-option value],
    %w[set-value --path 0 --value -h --not-a-real-option value] ].each do |arguments|
    it "rejects invalid arguments #{arguments.inspect}" do
      usage_error(*arguments)
    end
  end

  ['-1', '1..2', '1.', 'a', '2147483648', '0. 1', '١', '+1', (['0'] * 65).join('.')].each do |path|
    it "rejects malformed element path #{path.inspect} before desktop access" do
      usage_error('focus', '--path', path)
    end
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

  ['ctrl+bogus', 'command+bogus', 'unknown+a', '', 'ctrl+', 'command+', 'f0', 'f25'].each do |key|
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

  [['key', '--key', 'return', '--pid', '1', '--target-path', '', '--require-value', 'draft'],
   ['key', '--key', 'return', '--pid', '1', '--target-path', '0', '--require-value', '  ']].each do |arguments|
    it "rejects an empty guarded target or draft before input: #{arguments.inspect}" do
      usage_error(*arguments)
    end
  end
  ['RETURN', 'ctrl+alt+shift+a', 'cmd+v', 'command+control+option+shift+F12',
   '9', 'forward-delete', 'pageup', 'pagedown'].each do |key|
    it "accepts the key grammar before refusing an absent target: #{key}" do
      result = cli('key', '--key', key, '--pid', '2147483647')
      expect(result.status).to eq(77)
      expect(%w[accessibility_error accessibility_permission_denied]).to include(result.json.fetch('code'))
    end
  end

  [%w[activate], %w[open], %w[click --x 0], %w[type], %w[paste],
   %w[key], %w[scroll], %w[set-value --path 0], %w[set-selected-text --path 0]].each do |arguments|
    it "rejects missing required values before desktop work: #{arguments.inspect}" do
      usage_error(*arguments)
    end
  end

end
