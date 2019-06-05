require 'forwardable'

module Apartment
  #   The main entry point to Apartment functions
  #
  module Tenant

    extend self
    extend Forwardable

    def_delegators :adapter, :create, :drop, :switch, :switch!, :current, :each, :reset, :set_callback, :seed, :current_tenant, :default_tenant

    attr_writer :config

    #   Initialize Apartment config options such as excluded_models
    #
    def init
      if Apartment.included_models.present?
        ActiveRecord::ModelSchema::ClassMethods.module_eval do
          def reset_table_name #:nodoc:
            _table_name = if abstract_class?
                            superclass == ::ActiveRecord::Base ? nil : superclass.table_name
                          elsif superclass.abstract_class?
                            superclass.table_name || compute_table_name
                          else
                            compute_table_name
                          end
            unless _table_name.nil?
              _table_name = _table_name.gsub(/^#{::Apartment.default_tenant}\./,'')
              self.table_name = "#{::Apartment.default_tenant}."+_table_name
            end
          end
        end

        # Move all models to the default schema before applying exceptions!
        ::ActiveRecord::Base.descendants.each do |model|
          if model.table_name.present? && model.table_name !~ /^#{::Apartment.default_tenant}./
            model.table_name = "#{::Apartment.default_tenant}." + model.table_name
          end
        end

        adapter.process_included_models
      else
        adapter.process_excluded_models
      end
    end

    #   Fetch the proper multi-tenant adapter based on Rails config
    #
    #   @return {subclass of Apartment::AbstractAdapter}
    #
    def adapter
      Thread.current[:apartment_adapter] ||= begin
        adapter_method = "#{config[:adapter]}_adapter"

        if defined?(JRUBY_VERSION)
          if config[:adapter] =~ /mysql/
            adapter_method = 'jdbc_mysql_adapter'
          elsif config[:adapter] =~ /postgresql/
            adapter_method = 'jdbc_postgresql_adapter'
          end
        end

        begin
          require "apartment/adapters/#{adapter_method}"
        rescue LoadError
          raise "The adapter `#{adapter_method}` is not yet supported"
        end

        unless respond_to?(adapter_method)
          raise AdapterNotFound, "database configuration specifies nonexistent #{config[:adapter]} adapter"
        end

        send(adapter_method, config)
      end
    end

    #   Reset config and adapter so they are regenerated
    #
    def reload!(config = nil)
      Thread.current[:apartment_adapter] = nil
      @config = config
    end

    private

    #   Fetch the rails database configuration
    #
    def config
      @config ||= Apartment.connection_config
    end
  end
end
