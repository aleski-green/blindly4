require 'support/windows_fixture'

RSpec.describe 'A three-field Windows form', :windows, :live do
  include_context 'a native Windows fixture'

  it 'exposes three text fields with the draft in the second position' do
    fields = app('find', '--role', 'AXTextField').fetch('matches')
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

      # This is a real elapsed delay, with no mocked clock or fixture shortcut.
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
    app('key', '--key', 'ctrl+a', '--target-path', draft, '--require-value', 'replace this')
    app('set-selected-text', '--path', draft, '--value', 'replacement مرحبا')
    expect(draft_value).to eq('replacement مرحبا')
    expect_untouched_neighbors
    expect_not_submitted
  end

  %w[press enter].each do |submission|
    it "blocks #{submission} when the second field changes during the delay, even if the first still matches" do
      message = 'original draft'
      app('set-value', '--path', control('First field', 'AXTextField'), '--value', message)
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
end
