require 'support/desktop_fixture'

RSpec.describe 'Windows cross-process providers', :windows, :live, child_process: true do
  include_context 'a native desktop fixture'

  around do |example|
    begin
      wait_for_observed_state('Embedded child fixture') do
        result = cli('find', '--pid', @fixture_pid, '--title', 'Child process:', '--role', 'AXStaticText')
        if result.status == 0 && (row = result.json.fetch('matches').first)
          @child_pid = Integer(row.fetch('title').split(': ').last)
          cli('find', '--pid', @fixture_pid, '--title', 'Child process draft', '--role', 'AXTextField').json.fetch('matches').length == 1
        end
      end
      example.run
    ensure
      begin
        Process.kill('KILL', @child_pid) if @child_pid
      rescue Errno::ESRCH
        nil
      end
    end
  end

  it 'reads and pastes into an embedded provider while retaining the window owner PID and exact draft guard' do
    child = find_control('Child process draft', 'AXTextField')
    expect(child.fetch('pid')).to eq(@fixture_pid)
    message = 'Embedded provider: مرحبا café 🪟'
    expect(app('paste', '--target-path', child.fetch('path'), '--text', message)).to include('verified' => true)
    expect(app('focused')).to include('title' => 'Child process draft', 'value' => message, 'pid' => @fixture_pid)
    child = find_control('Child process draft', 'AXTextField')
    expect(app('inspect', '--path', child.fetch('path'))).to include('value' => message)
    rejected_app(77, 'key', '--key', 'return', '--target-path', child.fetch('path'), '--require-value', 'wrong draft')
    expect(app('find', '--title', 'Submission count: 0', '--role', 'AXStaticText').fetch('matches').length).to eq(2)
    expect(app('inspect', '--path', child.fetch('path'))).to include('value' => message)
  end

  it 'does not accept a detached provider just because it is a child process of the requested application' do
    target = find_control_path('Child process draft', 'AXTextField')
    app('press', '--path', find_control_path('Detach child window', 'AXButton'))
    wait_for_observed_state('Detached child visible') { success('apps').fetch('apps').any? { |row| row['pid'] == @child_pid } }
    result = cli('focused', '--pid', @fixture_pid)
    expect(result.status).to eq(77)
    expect(result.json).to include('code' => 'focus_unavailable')
    expect(app('find', '--title', 'Child process draft', '--role', 'AXTextField').fetch('matches')).to eq([])
    rejected_app(77, 'paste', '--target-path', target, '--text', 'must not appear')
    expect(success('find', '--pid', @child_pid, '--title', 'Child process draft', '--role', 'AXTextField').fetch('matches').first)
      .to include('value' => '')
  end
end
