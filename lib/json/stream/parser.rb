# encoding: UTF-8

module JSON
  module Stream

    class ParserError < RuntimeError; end

    # A streaming JSON parser that generates SAX-like events for
    # state changes. Use the json gem for small documents. Use this
    # for huge documents that won't fit in memory.
    class Parser
      BUF_SIZE      = 512
      CONTROL       = /[[:cntrl:]]/
      WS            = /\s/
      HEX           = /[0-9a-fA-F]/
      DIGIT         = /[0-9]/
      DIGIT_1_9     = /[1-9]/
      DIGIT_END     = /\d$/
      TRUE_RE       = /[rue]/
      FALSE_RE      = /[alse]/
      NULL_RE       = /[ul]/
      TRUE_KEYWORD  = 'true'
      FALSE_KEYWORD = 'false'
      NULL_KEYWORD  = 'null'
      LEFT_BRACE    = '{'
      RIGHT_BRACE   = '}'
      LEFT_BRACKET  = '['
      RIGHT_BRACKET = ']'
      BACKSLASH     = '\\'
      SLASH         = '/'
      QUOTE         = '"'
      COMMA         = ','
      COLON         = ':'
      ZERO          = '0'
      MINUS         = '-'
      PLUS          = '+'
      POINT         = '.'
      EXPONENT      = /[eE]/

      # Parses a full JSON document from a String or an IO stream and returns
      # the parsed object graph. For parsing small JSON documents with small
      # memory requirements, use the json gem's faster JSON.parse method instead.
      def self.parse(json)
        stream = json.is_a?(String) ? StringIO.new(json) : json
        parser = Parser.new
        builder = Builder.new(parser)
        while (buf = stream.read(BUF_SIZE)) != nil
          parser << buf
        end
        raise ParserError, "unexpected eof" unless builder.result
        builder.result
      ensure
        stream.close
      end

      %w[start_document end_document start_object end_object
          start_array end_array key value].each do |name|

        define_method(name) do |&block|
          @listeners[name] << block
        end

        define_method("notify_#{name}") do |*args|
          @listeners[name].each do |block|
            block.call(*args)
          end
        end
        private "notify_#{name}"
      end

      def initialize
        @state = :start_document
        @utf8 = Buffer.new
        @listeners = Hash.new {|h, k| h[k] = [] }
        @stack, @unicode, @buf, @pos = [], "", "", -1
      end

      # Pass data into the parser to advance the state machine and
      # generate callback events. This is well suited for an EventMachine
      # receive_data loop.
      def <<(data)
        (@utf8 << data).each_char do |ch|
          @pos += 1
          case @state
          when :start_document
            case ch
            when LEFT_BRACE
              @state = :start_object
              @stack.push(:object)
              notify_start_document
              notify_start_object
            when LEFT_BRACKET
              @state = :start_array
              @stack.push(:array)
              notify_start_document
              notify_start_array
            when WS
              # ignore
            else
              error("Expected object or array start")
            end
          when :start_object
            case ch
            when RIGHT_BRACE
              end_container(:object)
            when QUOTE
              @state = :start_string
              @stack.push(:key)
            when WS
              # ignore
            else
              error("Expected object key start")
            end
          when :start_string
            case ch
            when QUOTE
              if @stack.pop == :string
                @state = :end_value
                notify_value(@buf)
              else # :key
                @state = :end_key
                notify_key(@buf)
              end
              @buf = ""
            when BACKSLASH
              @state = :start_escape
            when CONTROL
              error('Control characters must be escaped')
            else
              @buf << ch
            end
          when :start_escape
            case ch
            when QUOTE, BACKSLASH, SLASH
              @buf << ch
              @state = :start_string
            when 'b'
              @buf << "\b"
              @state = :start_string
            when 'f'
              @buf << "\f"
              @state = :start_string
            when 'n'
              @buf << "\n"
              @state = :start_string
            when 'r'
              @buf << "\r"
              @state = :start_string
            when 't'
              @buf << "\t"
              @state = :start_string
            when 'u'
              @state = :unicode_escape
            else
              error("Expected escaped character")
            end
          when :unicode_escape
            case ch
            when HEX
              @unicode << ch
              if @unicode.size == 4
                @buf << @unicode.slice!(0, 4).hex
                @state = :start_string
              end
            else
              error('Expected unicode escape hex digit')
            end
          when :start_negative_number
            case ch
            when ZERO
              @state = :start_zero
              @buf << ch
            when DIGIT_1_9
              @state = :start_int
              @buf << ch
            else
              error('Expected 0-9 digit')
            end
          when :start_zero
            case ch
            when POINT
              @state = :start_float
              @buf << ch
            when EXPONENT
              @state = :start_exponent
              @buf << ch
            else
              @state = :end_value
              notify_value(@buf.to_i)
              @buf = ""
              @pos -= 1
              redo
            end
          when :start_float
            case ch
            when DIGIT
              @state = :in_float
              @buf << ch
            else
              error('Expected 0-9 digit')
            end
          when :in_float
            case ch
            when DIGIT
              @buf << ch
            when EXPONENT
              @state = :start_exponent
              @buf << ch
            else
              @state = :end_value
              notify_value(@buf.to_f)
              @buf = ""
              @pos -= 1
              redo
            end
          when :start_exponent
            case ch
            when MINUS, PLUS, DIGIT
              @state = :in_exponent
              @buf << ch
            else
              error('Expected +, -, or 0-9 digit')
            end
          when :in_exponent
            case ch
            when DIGIT
              @buf << ch
            else
              error('Expected 0-9 digit') unless @buf =~ DIGIT_END
              @state = :end_value
              num = @buf.include?('.') ? @buf.to_f : @buf.to_i
              notify_value(num)
              @buf = ""
              @pos -= 1
              redo
            end
          when :start_int
            case ch
            when DIGIT
              @buf << ch
            when POINT
              @state = :start_float
              @buf << ch
            when EXPONENT
              @state = :start_exponent
              @buf << ch
            else
              @state = :end_value
              notify_value(@buf.to_i)
              @buf = ""
              @pos -= 1
              redo
            end
          when :start_true
            keyword(TRUE_KEYWORD, true, TRUE_RE, ch)
          when :start_false
            keyword(FALSE_KEYWORD, false, FALSE_RE, ch)
          when :start_null
            keyword(NULL_KEYWORD, nil, NULL_RE, ch)
          when :end_key
            case ch
            when COLON
              @state = :key_sep
            when WS
              # ignore
            else
              error("Expected colon key separator")
            end
          when :key_sep
            start_value(ch)
          when :start_array
            case ch
            when RIGHT_BRACKET
              end_container(:array)
            when WS
              # ignore
            else
              start_value(ch)
            end
          when :end_value
            case ch
            when COMMA
              @state = :value_sep
            when RIGHT_BRACKET
              end_container(:array)
            when RIGHT_BRACE
              end_container(:object)
            when WS
              # ignore
            else
              error("Expected comma or object or array close")
            end
          when :value_sep
            if @stack[-1] == :object
              case ch
              when QUOTE
                @state = :start_string
                @stack.push(:key)
              when WS
                # ignore
              else
                error("Expected object key start")
              end
            else
              start_value(ch)
            end
          when :end_document
            error("Unexpected data") unless ch =~ WS
          end
        end
      end

      private

      def end_container(type)
        @state = :end_value
        if @stack.pop == type
          send("notify_end_#{type}")
        else
          error("Expected end of #{type}")
        end
        if @stack.empty?
          @state = :end_document
          notify_end_document
        end
      end

      def keyword(word, value, re, ch)
        if ch =~ re
          @buf << ch
        else
          error("Expected #{word} keyword")
        end
        if @buf.size == word.size
          if @buf == word
            @state = :end_value
            @buf = ""
            notify_value(value)
          else
            error("Expected #{word} keyword")
          end
        end
      end

      def start_value(ch)
        case ch
        when LEFT_BRACE
          @state = :start_object
          @stack.push(:object)
          notify_start_object
        when LEFT_BRACKET
          @state = :start_array
          @stack.push(:array)
          notify_start_array
        when QUOTE
          @state = :start_string
          @stack.push(:string)
        when 't'
          @state = :start_true
          @buf << ch
        when 'f'
          @state = :start_false
          @buf << ch
        when 'n'
          @state = :start_null
          @buf << ch
        when MINUS
          @state = :start_negative_number
          @buf << ch
        when ZERO
          @state = :start_zero
          @buf << ch
        when DIGIT_1_9
          @state = :start_int
          @buf << ch
        when WS
          # ignore
        else
          error("Expected value")
        end
      end

      def error(message)
        raise ParserError, "#{message}: char #{@pos}"
      end
    end

  end
end
