require 'support/desktop_fixture'

RSpec.shared_examples 'a three-field form' do
  it 'exposes three text fields with the draft in the second position' do
    fields = app('find', '--role', 'AXTextField').fetch('matches').reject { |field| field['subrole'] == 'AXSecureTextField' }
    expect(fields.map { |field| field.fetch('title') }).to eq(['First field', 'Draft', 'Third field'])
    expect(fields.map { |field| field.fetch('position').fetch('y') }).to eq(
      fields.map { |field| field.fetch('position').fetch('y') }.sort
    )
    expect_untouched_neighbors
    expect(draft_value).to eq('')
  end

  [%w[paste press], %w[type enter], %w[paste space]].each do |input, submission|
    it "uses #{input} only in the second field and submits once with #{submission}" do
      message = "Second field via #{input}: مرحبا café 🪟"
      set_draft('old draft') if input == 'paste'
      if input == 'paste'
        expect(app('paste', '--target-path', draft, '--text', message)).to include('verified' => true)
      else
        app('focus', '--path', draft)
        expect(app('focused')).to include('title' => 'Draft', 'focused' => true)
        app('type', '--text', message)
        expect(app('focused')).to include('focused' => true, 'value' => message)
      end
      expect(draft_value).to eq(message)
      expect_untouched_neighbors
      expect_not_submitted

      if submission == 'press'
        expect(app('press', '--path', submit, '--require-value-path', draft,
                   '--require-value', message)).to include('verified' => true)
      else
        app('focus', '--path', submit)
        expect(app('focused')).to include('title' => 'Submit test draft', 'role' => 'AXButton', 'focused' => true)
        app('key', '--key', submission)
      end
      expect_label("Submitted: #{message}")
      expect_label('Submission count: 1')
      expect(draft_value).to eq(message)
      expect_untouched_neighbors
    end
  end

  it 'submits once with guarded Enter while the second field has focus' do
    message = 'Enter from the second field'
    app('paste', '--target-path', draft, '--text', message)
    expect(app('key', '--key', 'enter', '--target-path', draft,
               '--require-value', message)).to include('verified' => true)
    expect(draft_value).to eq(message)
    expect_label("Submitted: #{message}")
    expect_label('Submission count: 1')
    expect_untouched_neighbors
  end

  it 'inserts Space in the second field without submitting the form' do
    app('focus', '--path', draft)
    app('type', '--text', 'hello')
    app('key', '--key', 'space', '--target-path', draft, '--require-value', 'hello')
    expect(draft_value).to eq('hello ')
    expect_not_submitted
    expect_label('Submission count: 0')
    expect_untouched_neighbors
  end

  it 'replaces selected text only in the second field' do
    set_draft('replace this')
    app('focus', '--path', draft)
    app('key', '--key', (Blindly::WINDOWS ? 'ctrl+a' : 'command+a'), '--target-path', draft, '--require-value', 'replace this')
    app('set-selected-text', '--path', draft, '--value', 'replacement مرحبا')
    expect(draft_value).to eq('replacement مرحبا')
    expect_untouched_neighbors
    expect_not_submitted
  end

  %w[press enter].each do |submission|
    it "blocks #{submission} when the second field changes before submission, even if the first still matches" do
      message = 'original draft'
      app('set-value', '--path', find_control_path('First field', 'AXTextField'), '--value', message)
      app('paste', '--target-path', draft, '--text', message)
      set_draft('changed before submission')
      if submission == 'press'
        rejected_app(77, 'press', '--path', submit, '--require-value-path', draft, '--require-value', message)
      else
        app('focus', '--path', draft)
        rejected_app(77, 'key', '--key', 'enter', '--target-path', draft, '--require-value', message)
      end
      expect(draft_value).to eq('changed before submission')
      expect(field_value('First field')).to eq(message)
      expect(field_value('Third field')).to eq('third untouched')
      expect_not_submitted
      expect_label('Submission count: 0')
    end
  end

  it 'supports an empty verified paste without inserting or submitting text' do
    set_draft('old draft')
    expect(app('paste', '--target-path', draft, '--text', '')).to include('verified' => true)
    expect(draft_value).to eq('')
    expect_not_submitted
  end

  it 'preserves character counts and optional PID output through the shared typing workflow' do
    message = "e\u0301🙂"
    app('focus', '--path', draft)
    result = app('type', '--text', message)
    expect(result).to include('pid' => @fixture_pid, 'characters' => (Blindly::WINDOWS ? 3 : 2))
    expect(draft_value).to eq(message)
    set_draft('')
    app('focus', '--path', draft)
    implicit = success('type', '--text', message)
    expect(implicit.key?('pid')).to eq(Blindly::WINDOWS)
    expect(implicit['pid']).to eq(@fixture_pid) if Blindly::WINDOWS
    expect(implicit.fetch('characters')).to eq(result.fetch('characters'))
    expect(draft_value).to eq(message)
    expect_untouched_neighbors
    expect_not_submitted
  end
  it 'discovers the complete form and its supported submit action' do
    expect(success('apps').fetch('apps')).to include(a_hash_including('pid' => @fixture_pid))
    tree = app('tree', '--depth', 6, '--max-nodes', 1000)
    expect(tree.fetch('truncated')).to be(false)
    expect(tree.fetch('tree')).to include('role' => 'AXApplication')
    expect(tree.to_json).to include('Submit test draft', 'AXSecureTextField')
    expect(app('inspect', '--path', '')).to include('role' => 'AXApplication')
    outline = cli('show', '--pid', @fixture_pid, '--depth', 6)
    expect(outline.status).to eq(0)
    expect(outline.stdout).to include('AXApplication', 'Draft', 'Submit test draft')
    expect(app('actions', '--path', submit).fetch('actions')).to include('AXPress')
  end

  it 'bounds traversal and redacts secure fields' do
    tree = app('tree', '--max-nodes', 1)
    expect(tree.fetch('truncated')).to be(true)
    expect(tree.fetch('tree').fetch('children', [])).to be_empty
    expect(app('find', '--title', 'Draft', '--depth', 0).fetch('matches')).to be_empty
    limited = app('find', '--role', 'AXTextField', '--limit', 1)
    expect(limited.fetch('matches').length).to eq(1)
    expect(limited.fetch('truncated')).to be(true)
    passwords = app('find', '--title', 'Password').fetch('matches').select do |row|
      [row['role'], row['subrole']].include?('AXSecureTextField')
    end
    expect(passwords.length).to eq(1)
    password = passwords.first
    expect(app('inspect', '--path', password.fetch('path'))['value']).to be_nil
    expect(app('tree', '--depth', 6, '--max-nodes', 1000).to_json).not_to include('fixture secret')
    expect(app('find', '--value', 'fixture secret').fetch('matches')).to be_empty
    shown = cli('show', '--pid', @fixture_pid, '--depth', 6)
    expect(shown.status).to eq(0)
    expect(shown.stdout).not_to include('fixture secret')
    rejected_app(64, 'paste', '--target-path', password.fetch('path'), '--text', 'blocked')
    expect_not_submitted
  end

  ['old draft', ' draft', 'draft ', "draft\n", 'Draft'].each do |actual|
    it "rejects the nonmatching draft #{actual.inspect} without editing or submitting" do
      set_draft(actual)
      app('focus', '--path', draft)
      rejected_app(77, 'key', '--key', 'enter', '--target-path', draft, '--require-value', 'draft')
      rejected_app(77, 'press', '--path', submit, '--require-value-path', draft, '--require-value', 'draft')
      expect(draft_value).to eq(actual)
      expect_not_submitted
    end
  end

  [['café', "cafe\u0301"], ["\u200fمرحبا", 'مرحبا'], ['', '']].each do |actual, expected|
    it "submits once after verifying the matching draft #{actual.inspect}" do
      set_draft(actual)
      expect(app('press', '--path', submit, '--require-value-path', draft, '--require-value', expected)).to include('verified' => true)
      expect_label("Submitted: #{actual}")
      expect_label('Submission count: 1')
    end
  end

  it 'rejects wrong focus, description, nonwritable targets, stale paths and cross-app clicks' do
    set_draft('unchanged')
    app('focus', '--path', find_control_path('First field', 'AXTextField'))
    rejected_app(77, 'key', '--key', 'enter', '--target-path', draft, '--require-value', 'unchanged')
    rejected_app(64, 'press', '--path', submit, '--expect-description', 'wrong button')
    rejected_app(64, 'paste', '--target-path', submit, '--text', 'never entered')
    rejected_app(77, 'inspect', '--path', '99999')
    rejected_app(77, 'click', '--x', -99999, '--y', -99999)
    expect(draft_value).to eq('unchanged')
    expect_not_submitted
  end

  it 'toggles a checkbox through accessible presses without submitting' do
    expect_label('Checkbox: unchecked')
    %w[checked unchecked].each do |state|
      app('press', '--path', find_control_path('Test checkbox', 'AXCheckBox'))
      expect_label("Checkbox: #{state}")
    end
    expect_not_submitted
  end
end
