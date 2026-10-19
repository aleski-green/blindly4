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

  %w[paste type].product(%w[press space enter]).each do |input, submission|
    it "uses #{input} only in the second field, waits two seconds, and submits once with #{submission}" do
      message = "Second field via #{input}: مرحبا café 🪟"
      if input == 'paste'
        expect(app('paste', '--target-path', draft, '--text', message)).to include('verified' => true)
      else
        app('focus', '--path', draft)
        expect(app('focused')).to include('title' => 'Draft', 'focused' => true)
        app('type', '--text', message)
      end
      expect(draft_value).to eq(message)
      expect_untouched_neighbors
      expect_not_submitted

      sleep 2
      expect(draft_value).to eq(message)
      expect_untouched_neighbors
      expect_label('Submission count: 0')

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
    sleep 2
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
    it "blocks #{submission} when the second field changes during the delay, even if the first still matches" do
      message = 'original draft'
      app('set-value', '--path', find_control_path('First field', 'AXTextField'), '--value', message)
      app('paste', '--target-path', draft, '--text', message)
      sleep 1
      set_draft('changed during wait')
      sleep 1
      if submission == 'press'
        rejected_app(77, 'press', '--path', submit, '--require-value-path', draft, '--require-value', message)
      else
        app('focus', '--path', draft)
        rejected_app(77, 'key', '--key', 'enter', '--target-path', draft, '--require-value', message)
      end
      expect(draft_value).to eq('changed during wait')
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
end
