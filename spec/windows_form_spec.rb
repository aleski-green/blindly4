require 'support/form_examples'

RSpec.describe 'A three-field Windows form', :windows, :live do
  include_context 'a native desktop fixture'
  include_examples 'a three-field form'
end
