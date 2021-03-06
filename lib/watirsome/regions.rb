module Watirsome
  module Regions
    #
    # Defines region accessor.
    #
    # @param [Symbol] region_name
    # @param [Block] block
    #
    def has_one(region_name, &block)
      define_region_accessor(region_name, &block)
    end

    #
    # Defines multiple regions accessor.
    #
    # @param [Symbol] region_name
    # @param [Hash] within
    # @param [Hash] each
    # @param [Block] block
    #
    def has_many(region_name, each:, within: nil, &block)
      define_region_accessor(region_name, within: within, each: each, &block)
      define_finder_method(region_name)
    end

    private

    # rubocop:disable Metrics/AbcSize, Metrics/BlockLength, Metrics/MethodLength, Metrics/PerceivedComplexity, Metrics/CyclomaticComplexity
    def define_region_accessor(region_name, within: nil, each: nil, &block)
      define_method(region_name) do
        class_path = self.class.name.split('::')
        namespace = if class_path.size > 1
                      class_path.pop
                      Object.const_get(class_path.join('::'))
                    elsif class_path.size == 1
                      self.class
                    else
                      raise "Cannot understand namespace from #{class_path}"
                    end

        if block_given?
          region_class = Class.new
          region_class.class_eval { include(Watirsome) }
          region_class.class_eval(&block)
        else
          singular_klass = region_name.to_s.split('_').map(&:capitalize).join
          if each
            collection_klass = "#{singular_klass}Region"
            singular_klass = singular_klass.sub(/s\z/, '')
          end
          singular_klass << 'Region'
          region_class = namespace.const_get(singular_klass)
        end

        region_class.class_eval do
          attr_reader :parent
          attr_reader :region_element

          def initialize(browser, region_element, parent)
            super(browser)
            @region_element = region_element
            @parent = parent
          end
        end

        scope = case within
                when Proc
                  instance_exec(&within)
                when Hash
                  @browser.element(within)
                else
                  @browser
                end

        if each
          elements = (scope.exists? ? scope.elements(each) : [])
          if block_given? || !namespace.const_defined?(collection_klass)
            return elements.map { |element| region_class.new(@browser, element, self) }
          end

          region_collection_class = namespace.const_get(collection_klass)
          region_collection_class.class_eval do
            include Enumerable

            attr_reader :region_collection
            attr_reader :region_element

            define_method(:initialize) do |browser, region_element, region_elements|
              super(browser)
              @region_element = region_element
              @region_collection = if region_elements.all? { |element| element.is_a?(Watir::Element) }
                                     region_elements.map { |element| region_class.new(browser, element, self) }
                                   else
                                     region_elements
                                   end
            end

            def each(&block)
              region_collection.each(&block)
            end
          end

          region_collection_class.new(@browser, scope, elements)
        else
          region_class.new(@browser, @browser, self)
        end
      end
    end
    # rubocop:enable Metrics/AbcSize, Metrics/BlockLength, Metrics/MethodLength, Metrics/PerceivedComplexity, Metrics/CyclomaticComplexity

    def define_finder_method(region_name)
      finder_method_name = region_name.to_s.sub(/s\z/, '')
      define_method(finder_method_name) do |**opts|
        __send__(region_name).find do |entity|
          opts.all? do |key, value|
            entity.__send__(key) == value
          end
        end || raise("No #{finder_method_name} matching: #{opts}.")
      end
    end
  end
end
