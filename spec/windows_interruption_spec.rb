require 'support/desktop_fixture'

RSpec.describe 'Windows interrupted input', :windows, :live do
  include_context 'a native desktop fixture'

  around do |example|
    with_clipboard_fixture do |clipboard|
      clipboard.call('write' => clipboard_text('interruption fixture clipboard'))
      example.run
    end
  end

  def expect_paste_rejected(result)
    expect(result.status).to eq(77), result.stdout
    expect(result.json).to include('code' => 'accessibility_error')
    expect(result.json).not_to have_key('verified')
    expect_not_submitted
    expect_label('Submission count: 0')
  end

  def during_pending_paste(text)
    target = draft
    release = find_control_path('Release pending paste', 'AXButton')
    worker = Thread.new { cli('paste', '--pid', @fixture_pid, '--target-path', target, '--text', text) }
    expect_label('Paste pending: 1')
    expect(worker.alive?).to be(true), 'Paste finished before the interference was introduced'
    yield release
    Timeout.timeout(30) { worker.value }
  ensure
    # cli has its own process timeout/cleanup; never leave input running after a failed assertion.
    worker&.join(35)
  end

  it 'activates and validates a fixture that deliberately starts in the background', background_start: true do
    expect(success('apps').fetch('apps')).to include(a_hash_including('pid' => @fixture_pid, 'frontmost' => true))
    expect(draft_value).to eq('')
    expect_not_submitted
  end

  it 'rejects a busy clipboard before clearing the original draft' do
    set_draft('original draft')
    target = draft
    with_clipboard_fixture do |clipboard|
      original = clipboard.call('write' => clipboard_text('original clipboard'))
      begin
        expect(clipboard.call('lock' => true)).to eq('locked' => true)
        result = cli('paste', '--pid', @fixture_pid, '--target-path', target, '--text', 'must not appear')
      ensure
        clipboard.call('lock' => false)
      end
      expect_paste_rejected(result)
      expect(result.json.fetch('error')).to include('Clipboard is busy')
      expect(draft_value).to eq('original draft')
      expect(clipboard.call({})).to eq(original)
    end
    expect_untouched_neighbors
  end

  it 'waits for delayed native paste consumption and restores the clipboard', paste_mode: 'delay' do
    with_clipboard_fixture do |clipboard|
      original = clipboard.call('write' => clipboard_text('original clipboard'))
      text = 'Delayed native paste: مرحبا café 🪟'
      expect(app('paste', '--target-path', draft, '--text', text)).to include('verified' => true)
      expect(draft_value).to eq(text)
      expect_label('Paste completed: 1')
      expect(clipboard.call({})).to eq(original)
    end
    expect_untouched_neighbors
    expect_not_submitted
  end

  it 'preserves a competing process copy and rejects the substituted draft', paste_mode: 'hold' do
    with_clipboard_fixture do |clipboard|
      clipboard.call('write' => clipboard_text('original clipboard'))
      newer = nil
      result = during_pending_paste('requested draft') do |release|
        newer = clipboard.call('write' => clipboard_text('newer copy'))
        app('press', '--path', release)
      end
      expect_paste_rejected(result)
      expect(draft_value).to eq('newer copy')
      expect_label('Paste completed: 1')
      expect(clipboard.call({})).to eq(newer)
    end
    expect_untouched_neighbors
  end

  it 'rejects a matching draft when focus moves after paste consumption', paste_mode: 'focus-after' do
    result = cli('paste', '--pid', @fixture_pid, '--target-path', draft, '--text', 'matching draft')
    expect_paste_rejected(result)
    expect(draft_value).to eq('matching draft')
    expect(app('focused')).to include('title' => 'First field')
    rejected_app(77, 'key', '--key', 'enter', '--target-path', draft, '--require-value', 'matching draft')
    expect_label('Paste completed: 1')
    expect_untouched_neighbors
    expect_not_submitted
  end

  it 'does not retry or submit when native consumption happens after the verification timeout', paste_mode: 'hold' do
    with_clipboard_fixture do |clipboard|
      original = clipboard.call('write' => clipboard_text('restored fixture clipboard'))
      result = cli('paste', '--pid', @fixture_pid, '--target-path', draft, '--text', 'requested draft')
      expect_paste_rejected(result)
      expect(result.json.fetch('error')).to include('Paste failed exact draft verification')
      expect(draft_value).to eq('')
      expect_label('Paste pending: 1')
      expect(clipboard.call({})).to eq(original)

      # A native app may consume the restored clipboard after the command failed.
      # Failure is not a rollback guarantee: callers must inspect before any retry/send.
      app('press', '--path', find_control_path('Release pending paste', 'AXButton'))
      expect(draft_value).to eq('restored fixture clipboard')
      expect_label('Paste completed: 1')
      rejected_app(77, 'press', '--path', submit, '--require-value-path', draft, '--require-value', 'requested draft')
      expect_not_submitted
    end
    expect_untouched_neighbors
  end

  it 'fails closed when another process takes focus during pending paste', paste_mode: 'hold' do
    other = Process.spawn({ 'BLINDLY4_FIXTURE_PASTE' => nil, 'BLINDLY4_FIXTURE_BACKGROUND' => '1' },
                          [fixture_binary, fixture_binary], '--test-app', in: File::NULL, out: File::NULL, err: File::NULL)
    wait_for_observed_state('Second fixture ready') do
      result = cli('find', '--pid', other, '--title', 'Fixture ready', '--role', 'AXStaticText')
      result.status == 0 && !result.json.fetch('matches').empty?
    end
    switch_focus = find_control_path('Switch fixture focus', 'AXButton')
    result = during_pending_paste('requested draft') do |release|
      app('press', '--path', switch_focus)
      expect(success('apps').fetch('apps')).to include(a_hash_including('pid' => other, 'frontmost' => true))
      app('press', '--path', release)
    end
    expect_paste_rejected(result)
    expect(draft_value).to eq('requested draft')
    expect_untouched_neighbors
    other_fields = success('find', '--pid', other, '--role', 'AXTextField').fetch('matches')
    %w[First\ field Draft Third\ field].zip(['first untouched', '', 'third untouched']).each do |title, value|
      expect(other_fields).to include(a_hash_including('title' => title, 'value' => value))
    end
    expect(success('find', '--pid', other, '--title', 'Not submitted').fetch('matches')).not_to be_empty
  ensure
    if other
      Process.kill('KILL', other)
      Process.waitpid(other)
    end
  end
end
