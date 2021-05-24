# frozen_string_literal: true

require "dry/core/equalizer"

require "dry/validation/constants"
require "dry/validation/function"

module Dry
  module Validation
    # Rules capture configuration and evaluator blocks
    #
    # When a rule is applied, it creates an `Evaluator` using schema result and its
    # block will be evaluated in the context of the evaluator.
    #
    # @see Contract#rule
    #
    # @api public
    class Rule < Function
      include Dry::Equalizer(:keys, :block, inspect: false)

      # @!attribute [r] keys
      #   @return [Array<Symbol, String, Hash>]
      #   @api private
      option :keys

      # @!attribute [r] macros
      #   @return [Array<Symbol>]
      #   @api private
      option :macros, default: proc { EMPTY_ARRAY.dup }

      # Evaluate the rule within the provided context
      #
      # @param [Contract] contract
      # @param [Result] result
      #
      # @api private
      def call(contract, result)
        block = if true || keys.join.include?('[]')
                  evaluated_block
                else
                  @block
                end

        Evaluator.new(
          contract,
          keys: [],
          macros: macros,
          block_options: block_options,
          result: result,
          values: result.values,
          _context: result.context,
          &block
        )
      end

      def evaluated_block
        macros = parse_macros(*@macros)
        real_block = @block
        real_keys = @each_each ? [*@each_each, :[]] : keys

        @evaluated_block ||= proc do
          @real_keys = real_keys
          keys = real_keys
            .flat_map { |k| Schema::Path[k].keys }
            .map(&:to_s)
            .flat_map { |k| k.end_with?('[]') ? [k[0..-3], '[]'] : k }
            .map(&:to_sym)
            .reject(&:empty?)

          xx = keys.reduce([[]]) do |paths, key|
            paths.reduce([]) do |memo, current_path|
              if key == :'[]'
                next memo unless result[current_path].is_a?(Array)

                memo.concat(Array.new(result[current_path].size) { |idx| [*current_path, idx] })
              else
                memo << [*current_path, key]
              end

              memo
            end
          end
          xx.each do |*base_path, idx|

            path = [*base_path, idx]

            next if result.schema_error?(path)

            evaluator = with(macros: macros, keys: [path], index: idx, &real_block)

            failures.concat(evaluator.failures)
          end
        end
      end

      # Define which macros should be executed
      #
      # @see Contract#rule
      # @return [Rule]
      #
      # @api public
      def validate(*macros, &block)
        @macros = parse_macros(*macros)
        @block = block if block
        self
      end

      # Define a validation function for each element of an array
      #
      # The function will be applied only if schema checks passed
      # for a given array item.
      #
      # @example
      #   rule(:nums).each do |index:|
      #     key([:number, index]).failure("must be greater than 0") if value < 0
      #   end
      #   rule(:nums).each(min: 3)
      #   rule(address: :city) do
      #      key.failure("oops") if value != 'Munich'
      #   end
      #
      # @return [Rule]
      #
      # @api public
      def each(*macros, &block)
        @macros = parse_macros(*macros)
        @each_each = @keys
        @keys = []

        @block = block
        @block_options = map_keywords(block) if block

        self
      end

      # Return a nice string representation
      #
      # @return [String]
      #
      # @api public
      def inspect
        %(#<#{self.class} keys=#{keys.inspect}>)
      end

      # Parse function arguments into macros structure
      #
      # @return [Array]
      #
      # @api private
      def parse_macros(*args)
        args.each_with_object([]) do |spec, macros|
          case spec
          when Hash
            add_macro_from_hash(macros, spec)
          else
            macros << Array(spec)
          end
        end
      end

      def add_macro_from_hash(macros, spec)
        spec.each do |k, v|
          macros << [k, v.is_a?(Array) ? v : [v]]
        end
      end
    end
  end
end
