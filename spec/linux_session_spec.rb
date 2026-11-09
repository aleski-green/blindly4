RSpec.describe 'Linux session boundary' do
  before { skip 'Linux only' unless RUBY_PLATFORM.include?('linux') }

  [
    {'XDG_SESSION_TYPE' => 'wayland', 'DISPLAY' => ':99', 'WAYLAND_DISPLAY' => 'wayland-0'},
    {'XDG_SESSION_TYPE' => nil, 'DISPLAY' => ':99', 'WAYLAND_DISPLAY' => 'wayland-0'},
    {'XDG_SESSION_TYPE' => 'tty', 'DISPLAY' => ':99', 'WAYLAND_DISPLAY' => nil},
    {'XDG_SESSION_TYPE' => 'x11', 'DISPLAY' => nil, 'WAYLAND_DISPLAY' => nil}
  ].each do |environment|
    it "refuses desktop access with #{environment.inspect}" do
      permission = cli('request-permission', env: environment)
      expect(permission.status).to eq(0)
      expect(permission.json).to include('trusted' => false, 'foregroundAvailable' => false,
        'inputAvailable' => false, 'error' => a_string_including('requires an X11 session'))
      expect(cli('schema', env: environment).status).to eq(0)
      [%w[apps], %w[key --pid 1 --key enter], %w[click --pid 1 --x 0 --y 0],
        %w[paste --pid 1 --target-path 0 --text replacement]].each do |arguments|
        result = cli(*arguments, env: environment)
        expect(result.status).to eq(77), result.stdout + result.stderr
        expect(result.stdout + result.stderr).to include('requires an X11 session')
      end
    end
  end
end
