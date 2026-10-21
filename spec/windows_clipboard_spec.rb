require 'support/desktop_fixture'

RSpec.describe 'Windows clipboard restoration', :windows, :live do
  include_context 'a native desktop fixture'

  it 'waits for a native clipboard listener to finish reading before paste' do
    with_clipboard_fixture do |clipboard|
      original = clipboard.call('write' => clipboard_text('clipboard مرحبا café 🪟'))
      expect(clipboard.call('read-next-update-ms' => 100)).to eq('readerArmed' => true)
      expect(app('paste', '--target-path', draft, '--text', 'after clipboard reader')).to include('verified' => true)
      expect(draft_value).to eq('after clipboard reader')
      expect(clipboard.call('reader-status' => true)).to eq('readUpdates' => 1)
      expect(clipboard.call({})).to eq(original)
    end
    expect_untouched_neighbors
    expect_not_submitted
  end
end
