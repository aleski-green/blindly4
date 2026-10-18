require 'support/windows_fixture'

RSpec.describe 'Windows desktop behavior', :windows, :live do
  include_context 'a native Windows fixture'

  it 'lists the fixture and reads its real accessibility tree to the last child' do
    expect(success('apps').fetch('apps')).to include(a_hash_including('pid' => @fixture_pid))
    tree = app('tree', '--depth', '6')
    expect(tree.fetch('tree').fetch('role')).to eq('AXApplication')
    expect(tree.fetch('truncated')).to be(false)
    expect(tree.to_json).to include('Submit test draft', 'AXSecureTextField')
    expect(app('inspect', '--path', '').fetch('role')).to eq('AXApplication')
    outline = cli('show', '--pid', @fixture_pid, '--depth', '6')
    expect(outline.status).to eq(0)
    expect(outline.stdout).to include('AXApplication', 'Submit test draft')
  end

  it 'respects tree depth, node budgets, and find result limits' do
    tree = app('tree', '--max-nodes', '1')
    expect(tree.fetch('truncated')).to be(true)
    expect(tree.fetch('tree').fetch('children', [])).to be_empty
    expect(app('find', '--title', 'Draft', '--depth', '0').fetch('matches')).to be_empty
    limited = app('find', '--role', 'AX', '--limit', '1')
    expect(limited.fetch('matches').length).to eq(1)
    expect(limited.fetch('truncated')).to be(true)
  end

  it 'sets a draft, focuses it, and reports the observed value' do
    set_draft('old draft')
    expect(draft_value).to eq('old draft')
    app('focus', '--path', draft)
    expect(app('focused')).to include('focused' => true, 'value' => 'old draft')
  end

  ['', 'Windows مرحبا café 🪟'].each do |text|
    it "replaces an existing draft with a verified paste of #{text.inspect}" do
      set_draft('old draft')
      expect(app('paste', '--target-path', draft, '--text', text)).to include('ok' => true, 'verified' => true)
      expect(draft_value).to eq(text)
      expect_not_submitted
    end
  end

  ["draft\n", 'old draft', 'Draft', ' draft', 'draft '].each do |actual|
    it "blocks stale draft #{actual.inspect} without typing or submitting" do
      set_draft(actual)
      app('focus', '--path', draft)
      rejected_app(77, 'key', '--key', 'return', '--target-path', draft, '--require-value', 'draft')
      rejected_app(77, 'press', '--path', submit, '--require-value-path', draft, '--require-value', 'draft')
      expect(draft_value).to eq(actual)
      expect_not_submitted
    end
  end

  [['café', "cafe\u0301"], ["\u200fمرحبا", 'مرحبا'], ['', '']].each do |actual, expected|
    it "submits only after observing the matching draft #{actual.inspect}" do
      set_draft(actual)
      result = app('press', '--path', submit, '--expect-description', 'Submit',
                   '--require-value-path', draft, '--require-value', expected)
      expect(result).to include('ok' => true, 'verified' => true)
      expect(app('find', '--title', "Submitted: #{actual}").fetch('matches')).to contain_exactly(
        a_hash_including('title' => "Submitted: #{actual}")
      )
    end
  end

  it 'blocks a guarded key when the draft no longer has keyboard focus' do
    set_draft('draft')
    app('focus', '--path', submit)
    rejected_app(77, 'key', '--key', 'return', '--target-path', draft, '--require-value', 'draft')
    expect(draft_value).to eq('draft')
    expect_not_submitted
  end

  it 'refuses a wrong button description and a nonwritable paste target without changing the draft' do
    set_draft('draft')
    rejected_app(64, 'press', '--path', submit, '--expect-description', 'Wrong button')
    rejected_app(64, 'paste', '--target-path', submit, '--text', 'never entered')
    expect(draft_value).to eq('draft')
    expect_not_submitted
  end

  %w[ctrl+a command+a cmd+a].each do |shortcut|
    it "selects the matching draft with #{shortcut} and types Unicode through real keyboard input" do
      set_draft('original')
      app('focus', '--path', draft)
      expect(app('key', '--key', shortcut, '--target-path', draft, '--require-value', 'original')).to include('verified' => true)
      app('type', '--text', 'Typed Unicode: مرحبا café 🪟')
      expect(draft_value).to eq('Typed Unicode: مرحبا café 🪟')
      expect_not_submitted
    end
  end

  it 'preserves backward-delete and forward-delete keyboard behavior' do
    set_draft('abc')
    app('focus', '--path', draft)
    app('key', '--key', 'end')
    app('key', '--key', 'delete')
    expect(draft_value).to eq('ab')
    app('key', '--key', 'home')
    app('key', '--key', 'forward-delete')
    expect(draft_value).to eq('b')
  end

  it 'redacts password text and refuses to paste into a password control' do
    password = control('Password', 'AXSecureTextField')
    expect(app('inspect', '--path', password)['value']).to be_nil
    expect(app('tree', '--depth', '6').to_json).not_to include('fixture secret')
    rejected_app(64, 'paste', '--target-path', control('Password', 'AXSecureTextField'), '--text', 'never entered')
    expect_not_submitted
  end

  it 'fails closed for a stale path and a click outside the requested application' do
    rejected_app(77, 'inspect', '--path', '99999')
    rejected_app(77, 'click', '--x', '-99999', '--y', '-99999')
    expect_not_submitted
  end

  ['-1', '1..2', '1.', 'a', '2147483648', '0. 1', '١', '+1', (['0'] * 65).join('.')].each do |path|
    it "rejects malformed element path #{path.inspect}" do
      rejected_app(64, 'inspect', '--path', path)
    end
  end

  it 'refuses input addressed to a process without a visible target window' do
    result = cli('key', '--pid', Process.pid, '--key', 'return')
    expect(result.status).to eq(77)
    expect(result.json.fetch('code')).to eq('accessibility_error')
    expect_not_submitted
  end
end
