require 'spec_helper'

RSpec.describe 'The public CLI' do
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
end
