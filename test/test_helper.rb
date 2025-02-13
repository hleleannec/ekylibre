require 'minitest/mock'
require "minitest/reporters"
Minitest::Reporters.use! Minitest::Reporters::SpecReporter.new

ENV['RAILS_ENV'] ||= 'test'

require File.expand_path('../../config/environment', __FILE__)
require 'rails/test_help'

require 'rake'
require 'minitest/mock'
require 'database_cleaner'

helper = Ekylibre::Testing::Helper.new
helper.setup

if ENV['COVERAGE']
  require 'simplecov'

  if ENV['CI']
    require 'simplecov-cobertura'
    SimpleCov.formatter = SimpleCov::Formatter::CoberturaFormatter
  end

  SimpleCov.start('rails') do
    add_group 'Concepts', 'app/concepts'
    add_group 'Decorators', 'app/decorators'
    add_group 'Integrations', 'app/integrations'
    add_group 'Interactors', 'app/interactors'
    add_group 'Queries', 'app/queries'
    add_group 'Services', 'app/services'
    add_group 'Exchangers', 'app/exchangers'
    add_group 'Validators', 'app/validators'
    add_filter do |source_file|
      source_file.lines.count < 7
    end
  end

  SimpleCov.at_exit do
    # SimpleCov.minimum_coverage 43
    SimpleCov.result.format!
  end
end

class Minitest::Result
  def method(name)
    self.instance_of?(Minitest::Result) && name == self.name ? self : super
  end
end

if RUBY_VERSION >= '2.6.0'
  if Rails.version < '5'
    class ActionController::TestResponse < ActionDispatch::TestResponse
      def recycle!
        # hack to avoid MonitorMixin double-initialize error:
        @mon_mutex_owner_object_id = nil
        @mon_mutex = nil
        initialize
      end
    end
  else
    puts "Monkeypatch for ActionController::TestResponse no longer needed"
  end
end

ActionView::TestCase.send :include, FactoryBot::Syntax::Methods

module ActiveSupport
  def omniauth_mock(uid: '123',
                    email: 'john.doe@ekylibre.org',
                    first_name: 'John',
                    last_name: 'Doe')

    OmniAuth.config.mock_auth[:ekylibre] = OmniAuth::AuthHash.new(
      provider: 'ekylibre',
      uid: uid,
      info:
        {
          email: email,
          first_name: first_name,
          last_name: last_name
        }
    )
  end
end

class HashCollector
  def initialize
    @hash = {}
  end

  def to_hash
    @hash
  end

  def method_missing(method_name, *args, &_block)
    @hash[method_name.to_sym] = args.first
  end
end

class ActiveSupport::TestCase
  include ::Ekylibre::Testing::Concerns::LocaleSetter

  setup do
    reset_locale
  end
end

module ActionController
  class TestCase
    include Devise::Test::ControllerHelpers
    include ::Ekylibre::Testing::Concerns::LocaleSetter

    setup do
      Ekylibre::Tenant.filter_list!
      Ekylibre::Tenant.switch_each do
        Preference.set!("first_run.executed", true)
      end

      reset_locale
    end

    def fixture_files
      #     Rails.root.join('test', 'fixture-files')
      Pathname.new('../fixture-files')
    end

    def file_upload(path, mime_type = nil, binary = false)
      fixture_file_upload(fixture_files.join(path), mime_type, binary)
    end

    private def crush_hash(hash)
      hash.compact.transform_values { |v| v.is_a?(Hash) ? crush_hash(v) : v }
    end

    class << self
      def connect_with_token
        class_eval do
          setup do
            @admin_user = User.find_by(email: 'admin@ekylibre.org')
            authorize_user @admin_user
          end

          def switch_user(user, &block)
            authorize_user user
            sign_out @admin_user
            sign_in user
            yield
            sign_out user
            sign_in @admin_user
          end

          def authorize_user(user)
            user.update_column(:authentication_token, User.generate_authentication_token) if user.authentication_token.blank?
            authorization_token = "simple-token #{user.email} " + user.authentication_token
            @request.headers['Authorization'] = authorization_token
          end
        end
      end

      def setup_sign_in
        setup do
          @request.env['HTTP_REFERER'] = 'http://test.ekylibre.farm/backend'
          @user = if with_fixtures?
                    users(:users_001)
                  else
                    create(:user)
                  end
          @user.update_column(:language, I18n.locale)
          sign_in(@user)
        end

        teardown do
          sign_out(@user)
        end
      end

      def test_restfully_all_actions(options = {}, &_block)
        controller_name = controller_class.controller_name
        controller_path = controller_class.controller_path
        table_name = options.delete(:table_name) || controller_name
        model_name = options.delete(:class_name) || table_name.classify
        model = begin
                  model_name.constantize
                rescue
                  nil
                end
        record = model_name.underscore
        other_record = "other_#{record}"
        attributes = nil
        file_columns = {}
        if model && model < ActiveRecord::Base
          if model.respond_to?(:attachment_definitions)
            unless model.attachment_definitions.nil?
              file_columns = model.attachment_definitions
            end
          end
          attributes = model.content_columns.map(&:name).map(&:to_sym).delete_if do |c|
            %i[depth lft rgt].include?(c)
          end

          attributes += options.delete(:other_attributes) || []
          attributes = ('{' + attributes.map(&:to_sym).uniq.collect do |a|
            if file_columns[a]
              "#{a}: fixture_file_upload('files/sample_image.png')"
            else
              "#{a}: #{record}.#{a}"
            end
          end.join(', ') + '}').c
        end

        if block_given?
          collector = HashCollector.new
          yield collector
          options.update(collector.to_hash)
        end

        code = ''

        setup_sign_in unless options[:sign_in].is_a?(FalseClass)

        code << "def beautify(value, back = true)\n"
        code << "  if value.is_a?(Hash)\n"
        code << "    (back ? \"\\n\" : '') + value.map{|k,v| \"\#{k.to_s.yellow}: \#{beautify(v)}\"}.join(\"\\n\").dig\n"
        code << "  elsif value.is_a?(Array)\n"
        code << "    (back ? \"\\n\" : '') + value.map{|v| \"- \#{beautify(v)}\"}.join(\"\\n\").dig\n"
        code << "  elsif value.is_a?(ActiveRecord::Base)\n"
        code << "    \"\#{value.class.name} #\#{value.id}\" + (value.errors.any? ? '. Errors: ' + value.errors.full_messages.to_sentence.red : '')"
        code << "  else\n"
        code << "    value.inspect\n"
        code << "  end\n"
        code << "end\n"
        code << "\n"

        actions = controller_class.action_methods.to_a.map(&:to_sym)
        actions &= [options.delete(:only)].flatten if options[:only]
        actions -= [options.delete(:except)].flatten if options[:except]

        ignored = controller_class.action_methods.to_a.map(&:to_sym) - actions
        puts "Ignore in #{controller_path}: " + ignored.map(&:to_s).map(&:yellow).join(', ') if ENV.fetch('RESTFULLY_VERBOSE', false) && ignored.any?

        infos = []
        infos << '"Response code: " + @response.response_code.to_s'
        infos << '"Locale: " + I18n.locale.to_s'
        infos << '(flash[:notifications].is_a?(Hash) ? "Notifications are:\n" + flash[:notifications].collect{|k,v| "[#{k.to_s.upcase.yellow}] " + v.to_sentence(locale: :eng)}.join("\n").dig : "No notifications.")'
        infos << '(assigns.any? ? "Assigns are:" + beautify(assigns) : "No assigns.")'

        code << "def show_context\n"
        code << infos.join(" +\n  \"\\n\" + ").dig
        code << "end\n\n"

        context = 'show_context'
        # context = infos.join(' + "\n" + ')

        default_params = options[:params] || {}
        strictness = options[:strictness] || :default

        actions.sort.each do |action|
          action_label = "#{controller_path}##{action}"

          params = {}.merge(default_params)
          mode = options[action]
          if mode.is_a?(Hash)
            if mode[:params].is_a?(Hash)
              params.update mode[:params]
              mode = mode.delete(:mode)
            else
              mode = mode.delete(:mode)
              params.update(options[action])
            end
          end
          mode ||= choose_mode(action_label)

          params.deep_symbolize_keys!
          fixtures_to_use = Ekylibre::Testing::FixtureRetriever.new(model, params.delete(:fixture), params.delete(:fixture_options))
          test_code = ''

          sanitized_params = proc do |p = {}|
            p.deep_symbolize_keys
             .merge(locale: '@locale'.c)
             .deep_merge(params)
             .inspect
             .gsub('OTHER_RECORD', other_record)
             .gsub('RECORD', record)
          end
          if mode == :index
            test_code << "get :#{action}, params: crush_hash(#{sanitized_params[]})\n"
            test_code << "assert_response :success, 'Try to get action: #{action} #{sanitized_params[]}. ' + #{context}\n"
            test_code << "get :#{action}, params: crush_hash(#{sanitized_params[q: 'abc']})\n"
            test_code << "assert_response :success, 'Try to get action: #{action} #{sanitized_params[]}. ' + #{context}\n"
            if params[:format] == :json
              # TODO: JSON parsing test
            else
              test_code << "assert_select('html body #main #content', 1, 'Cannot find #main #content element')\n"
            end
          elsif mode == :new_product
            test_code << "get :#{action}, params: crush_hash(#{sanitized_params[]})\n"
            test_code << "if ProductNatureVariant.of_variety('#{model_name.underscore}').any?\n"
            test_code << "  assert_response :success, #{context}\n"
            test_code << "else\n"
            test_code << "  assert_response :redirect, #{context}\n"
            test_code << "end\n"
          elsif mode == :show_sti_record
            test_code << "get :#{action}, params: crush_hash(#{sanitized_params[id: 'NaID', redirect: 'root_url'.c]})\n"
            test_code << "assert_redirected_to root_url\n"
            test_code << "#{model}.limit(5).each do |record|\n"
            test_code << "  get :#{action}, params: crush_hash(#{sanitized_params[id: 'record.id'.c, redirect: 'root_url'.c]})\n"
            test_code << "  if record.type && record.type != '#{model.name}'\n"
            test_code << "    assert_redirected_to({controller: record.class.name.tableize, action: :show, id: record.id})\n" # , #{context}
            test_code << "  else\n"
            test_code << "    assert_response :success, #{context}\n"
            test_code << "    assert_not_nil assigns(:#{record})\n"
            test_code << "  end\n"
            test_code << "end\n"
          elsif mode == :show
            test_code << "get :#{action}, params: crush_hash(#{sanitized_params[id: 'NaID', redirect: 'root_url'.c]})\n"
            test_code << (strictness == :api ? "assert_response 404\n" : "assert_redirected_to root_url\n")
            if model
              test_code << "#{model}.limit(5).each do |record|\n"
              test_code << "  get :#{action}, params: crush_hash(#{sanitized_params[id: 'record.id'.c]})\n"
              test_code << "  assert_response :success\n" # , #{context}
              test_code << "  assert_not_nil assigns(:#{record})\n"
              test_code << "end\n"
            end
          elsif mode == :picture
            test_code << "#{record} = #{fixtures_to_use.retrieve(:first)}\n"
            test_code << "assert_equal 1, #{model_name}.where(id: #{record}.id).count\n"
            test_code << "get :#{action}, params: crush_hash(#{sanitized_params[id: 'RECORD.id'.c]})\n"
            test_code << "if #{record}.picture.file?\n"
            test_code << "  assert_response :success, #{context}\n"
            test_code << "  assert_not_nil assigns(:#{record})\n"
            test_code << "end\n"
          elsif mode == :list_things
            test_code << "#{record} = #{fixtures_to_use.retrieve(:first)}\n"
            test_code << "assert_equal 1, #{model_name}.where(id: #{record}.id).count\n"
            test_code << "get :#{action}, params: crush_hash(#{sanitized_params[id: 'RECORD.id'.c]})\n"
            test_code << "assert_response :success, #{context}\n"
            %i[csv ods].each do |format|
              test_code << "get :#{action}, params: crush_hash(#{sanitized_params[id: 'RECORD.id'.c, format: format]})\n"
              test_code << "assert_response :success, 'Action #{action} does not export in format #{format}'\n"
            end
          elsif mode == :create
            test_code << "#{record} = #{fixtures_to_use.retrieve(:first)}\n"
            test_code << "post :#{action}, params: crush_hash(#{sanitized_params[record => attributes]})\n"
          elsif mode == :update
            test_code << "#{record} = #{fixtures_to_use.retrieve(:first)}\n"
            test_code << "patch :#{action}, params: crush_hash(#{sanitized_params[id: 'RECORD.id'.c, record => attributes]})\n"
            test_code << "assert_response :redirect, \"After update on record ID=\#{#{record}.id} we should be redirected to another page. \" + #{context}\n"
          elsif mode == :destroy
            test_code << "#{record} = #{fixtures_to_use.retrieve(:first, :second)}\n"
            test_code << "delete :#{action}, params: crush_hash(#{sanitized_params[id: 'RECORD.id'.c]})\n"
            test_code << "assert_response :redirect, #{context}\n"
          elsif mode == :list
            test_code << "get :#{action}, params: crush_hash(#{sanitized_params[]})\n"
            test_code << "assert_response :success, \"The action #{action.inspect} does not seem to support GET method \#{redirect_to_url} / \#{flash.inspect}\"\n"
            %i[csv ods].each do |format|
              test_code << "get :#{action}, params: crush_hash(#{sanitized_params[format: format]})\n"
              test_code << "assert_response :success, 'Action #{action} does not export in format #{format}'\n"
            end
          elsif mode == :touch
            test_code << "post :#{action}, params: crush_hash(#{sanitized_params[id: 'NaID']})\n"
            test_code << "#{record} = #{fixtures_to_use.retrieve(:first)}\n"
            test_code << "post :#{action}, params: crush_hash(#{sanitized_params[id: 'RECORD.id'.c]})\n"
            test_code << "assert_response :redirect, #{context}\n"
          elsif mode == :poke
            test_code << "post :#{action}, params: crush_hash(#{sanitized_params[id: 'NaID']})\n"
            test_code << "#{record} = #{fixtures_to_use.retrieve(:first)}\n"
            test_code << "post :#{action}, params: crush_hash(#{sanitized_params[id: 'RECORD.id'.c]})\n"
            test_code << "assert_response :success, #{context}\n"
          elsif mode == :evolve
            test_code << "#{record} = #{fixtures_to_use.retrieve(:first)}\n"
            model.state_machine.states.each do |state|
              test_code << "patch :#{action}, params: crush_hash(#{sanitized_params[id: 'RECORD.id'.c, state: state.name]})\n"
              test_code << "assert_response :redirect, #{context}\n"
            end
          elsif mode == :take
            test_code << "post :#{action}, params: crush_hash(#{sanitized_params[id: 'NaID', format: :json]})\n"
            test_code << "assert_response :redirect, #{context}\n"
            test_code << "#{record} = #{fixtures_to_use.retrieve(:first)}\n"
            test_code << "post :#{action}, params: crush_hash(#{sanitized_params[id: 'RECORD.id'.c, format: :json]})\n"
            test_code << "assert_response :unprocessable_entity\n"
            test_code << "post :#{action}, params: crush_hash(#{sanitized_params[id: 'RECORD.id'.c, format: :json, indicator: 'net_mass']})\n"
            test_code << "assert_response :success, #{context}\n"
          elsif mode == :soft_touch
            test_code << "post :#{action}, params: crush_hash(#{sanitized_params[]})\n"
            test_code << "assert_response :success, #{context}\n"
          elsif mode == :multi_touch
            test_code << "post :#{action}, params: crush_hash(#{sanitized_params[id: 'NaID']})\n"
            test_code << "#{record} = #{fixtures_to_use.retrieve(:first)}\n"
            test_code << "post :#{action}, params: crush_hash(#{sanitized_params[id: 'RECORD.id'.c]})\n"
            test_code << "assert_response :redirect, #{context}\n"
            # Multi IDS
            test_code << "#{other_record} = #{fixtures_to_use.retrieve(:second)}\n"
            test_code << "post :#{action}, params: crush_hash(#{sanitized_params[id: '[RECORD.id, OTHER_RECORD.id].join(", ")'.c]})\n"
            test_code << "assert_response :redirect, #{context}\n"
          elsif mode == :redirected_get # with ID
            test_code << "#{record} = #{fixtures_to_use.retrieve(:first)}\n"
            test_code << "get :#{action}, params: crush_hash(#{sanitized_params[id: 'RECORD.id'.c]})\n"
            test_code << "assert_response :redirect, #{context}\n"
          elsif mode == :get_and_post # with ID
            test_code << "get :#{action}, params: crush_hash(#{sanitized_params[id: 'NaID']})\n"
            test_code << "#{record} = #{fixtures_to_use.retrieve(:first)}\n"
            test_code << "get :#{action}, params: crush_hash(#{sanitized_params[id: 'RECORD.id'.c]})\n"
            test_code << "assert_response :success, #{context}\n"
          elsif mode == :index_xhr
            test_code << "get :#{action}, params: crush_hash(#{sanitized_params[]})\n"
            test_code << "assert_response :redirect, #{context}\n"
            test_code << "get :#{action}, params: crush_hash(#{sanitized_params[]}), xhr: true\n"
            test_code << "assert_response :success, #{context}\n"
          elsif mode == :show_xhr
            test_code << "#{record} = #{fixtures_to_use.retrieve(:first)}\n"
            test_code << "get :#{action}, params: crush_hash(#{sanitized_params[id: 'RECORD.id'.c]})\n"
            test_code << "assert_response :redirect, #{context}\n"
            test_code << "get :#{action}, params: #{sanitized_params[id: 'RECORD.id'.c]}, xhr: true\n"
            test_code << "assert_not_nil assigns(:#{record})\n"
          elsif mode == :resource
            # TODO: Adds test for resource
          elsif mode == :unroll
            test_code << "get :#{action}, params: crush_hash(#{sanitized_params[]}), xhr: true\n"
            test_code << "assert_response :success, #{context}\n"
            test_code << "get :#{action}, params: crush_hash(#{sanitized_params[q: 'foo)bar']}), xhr: true\n"
            test_code << "assert_response :success, #{context}\n"
            test_code << "get :#{action}, params: crush_hash(#{sanitized_params[q: 'foo(bar']}), xhr: true\n"
            test_code << "assert_response :success, #{context}\n"
            test_code << "get :#{action}, params: crush_hash(#{sanitized_params[q: 'foo"bar\'qux']}), xhr: true\n"
            test_code << "assert_response :success, #{context}\n"
            test_code << "get :#{action}, params: crush_hash(#{sanitized_params[q: '"; DROP TABLE ' + model.table_name + ';']}), xhr: true\n"
            test_code << "assert_response :success, #{context}\n"
            test_code << "get :#{action}, params: crush_hash(#{sanitized_params[q: 'foo bar qux']}), xhr: true\n"
            test_code << "assert_response :success, #{context}\n"
            test_code << "get :#{action}, params: crush_hash(#{sanitized_params[format: :json]}), xhr: true\n"
            test_code << "assert_response :success, #{context}\n"
            test_code << "get :#{action}, params: crush_hash(#{sanitized_params[format: :xml]}), xhr: true\n"
            test_code << "assert_response :success, #{context}\n"
            if model
              test_code << "#{record} = #{fixtures_to_use.retrieve(:first)}\n"
              test_code << "get :#{action}, params: crush_hash(#{sanitized_params[id: 'RECORD.id'.c]}), xhr: true\n"
              test_code << "assert_response :success, #{context}\n"
              model.simple_scopes.each do |scope|
                test_code << "get :#{action}, params: crush_hash(#{sanitized_params[scopes: scope.name]}), xhr: true\n"
                test_code << "assert_response :success, #{context}\n"
                test_code << "get :#{action}, params: crush_hash(#{sanitized_params[scopes: scope.name, format: :json]}), xhr: true\n"
                test_code << "assert_response :success, #{context}\n"
                test_code << "get :#{action}, params: crush_hash(#{sanitized_params[scopes: scope.name, format: :xml]}), xhr: true\n"
                test_code << "assert_response :success, #{context}\n"
                test_code << "get :#{action}, params: crush_hash(#{sanitized_params[scopes: scope.name, id: 'RECORD.id'.c]}), xhr: true\n"
                test_code << "assert_response :success, #{context}\n"
              end
              # TODO: test complex scopes
            end
          elsif mode == :get
            test_code << "get :#{action}, params: crush_hash(#{sanitized_params[]})\n"
            test_code << "assert_response :success, #{context}\n"
          elsif mode == :post
            test_code << "post :#{action}, params: crush_hash(#{sanitized_params[]})\n"
            test_code << "assert_response :success, #{context}\n"
          elsif mode == :post_and_redirect
            test_code << "post :#{action}, params: crush_hash(#{sanitized_params[]})\n"
            test_code << "assert_response :redirect, #{context}\n"
          elsif mode == :redirect
            test_code << "get :#{action}, params: crush_hash(#{sanitized_params[]})\n"
            test_code << "assert_response :redirect, #{context}\n"
          else
            test_code << "raise StandardError, 'What is this mode? #{mode.inspect}'\n"
          end

          code << "test '#{action} action"
          code << " in #{mode}" if action != mode
          code << "' do\n"
          # code << "  puts '#{controller_path.to_s.yellow}##{action.to_s.red}'\n"
          code << test_code.dig
          code << "end\n\n"
        end
        # code << "end\n"

        file = Rails.root.join('tmp', 'code', 'test', "#{controller_path}.rb")
        FileUtils.mkdir_p(file.dirname)
        File.open(file, 'wb') do |f|
          f.write(code)
        end

        class_eval(code, "(test) #{controller_path}") # :#{__LINE__}
      end

      MODES = {
        /\Abackend\/cells\/.*\#show\z/ => :get,
        # /\Abackend\/cells\/.*\#list\z/ => :index_xhr,
        /\#(index|new|pick|set)\z/ => :index,
        /\#(show|edit|detail)\z/ => :show,
        /\#picture\z/ => :picture,
        /\#list\_\w+\z/ => :list_things,
        /\#list\z/ => :list,
        /\#(create|load|incorporate)\z/ => :create,
        /\#update\z/ => :update,
        /\#evolve\z/ => :evolve,
        /\#destroy\z/ => :destroy,
        /\#attachments\z/ => :resource,
        /\#(decrement|duplicate|down|lock|toggle|unlock|up|increment|propose|confirm|refuse|invoice|abort|correct|finish|propose_and_invoice|sort|run|qualify|evaluate|quote|negociate|win|lose|reset|start|prospect|retrieve)\z/ => :touch,
        /\#take\z/ => :take,
        /\#unroll\z/ => :unroll
      }.freeze

      def choose_mode(action)
        array = action.to_s.split('#')
        action_name = array.last.to_sym
        if action_name == :new
          model = begin
                    array.first.split(/\//).last.classify.constantize
                  rescue
                    nil
                  end
          return :new_product if model && model <= Product
        elsif action_name == :show
          model = begin
                    array.first.split(/\//).last.classify.constantize
                  rescue
                    nil
                  end
          return :show_sti_record if model && (model <= Product || model <= Affair)
        end
        MODES.each do |exp, mode|
          return mode if action =~ exp
        end
        :get
      end
    end
  end
end

def without_output(&block)
  main.stub :puts, Proc.new, &block
end

module FFaker
  module Shape
    module_function

    SHAPES = File.readlines(Rails.root.join('test', 'fixture-files', "shapes")).freeze

    def polygon
      Charta.new_geometry(SHAPES.sample).to_rgeo
    end
  end
end

module ImportTest
  class ImportTestDummyExchanger < ActiveExchanger::Base
    mattr_accessor :check_block, :import_block

    def check
      if check_block.nil?
        true
      else
        check_block.call
      end
    end

    def import
      if import_block.nil?
        true
      else
        import_block.call
      end
    end
  end
end

def main
  TOPLEVEL_BINDING.eval('self')
end

require 'vcr'

VCR.configure do |config|
  config.allow_http_connections_when_no_cassette = true
  config.cassette_library_dir = File.expand_path('test/cassettes', __dir__)
  config.hook_into :webmock
  config.ignore_request { ENV['DISABLE_VCR'] }
  config.ignore_localhost = true
end
