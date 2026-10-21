require 'support/desktop_fixture'

RSpec.describe 'Native clipboard restoration', :live do
  include_context 'a native desktop fixture'

  %w[empty unicode binary].each do |contents|
    it "preserves #{contents} clipboard contents after verified paste" do
      items = case contents
              when 'empty' then []
              when 'unicode' then [clipboard_text('clipboard مرحبا café 🪟')]
              else [clipboard_text('clipboard مرحبا café 🪟').merge('org.blindly4.fixture' => [0, 255, 17, 0]),
                    { 'org.blindly4.fixture-second' => [1, 2, 3, 128] }]
              end
      with_clipboard_fixture do |clipboard|
        original = clipboard.call('write' => clipboard_items(*items))
        expect_clipboard_items(original, items)
        ['', 'pasted into fixture only: مرحبا café 🪟'].each do |text|
          set_draft('replace this draft')
          expect(app('paste', '--target-path', draft, '--text', text)).to include('verified' => true)
          expect(draft_value).to eq(text)
          expect(clipboard.call({})).to eq(original)
          expect_not_submitted
          expect_untouched_neighbors
        end
      end
    end
  end

  it 'restores the pre-test clipboard when the transport exits after a paste' do
    with_clipboard_fixture do |outer|
      original = outer.call('write' => clipboard_items('org.blindly4.fixture-original' => [0, 128, 255, 17]))
      with_clipboard_fixture do |inner|
        expect_clipboard_items(inner.call('write' => clipboard_items), [])
        app('paste', '--target-path', draft, '--text', 'cleanup check')
        expect(draft_value).to eq('cleanup check')
      end
      expect(outer.call({})).to eq(original)
    end
    expect_not_submitted
  end
end
