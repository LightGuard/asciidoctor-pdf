module Asciidoctor
module Prawn
  module Extensions
    LineMetrics = ::Struct.new :leading, :shift, :height, :final_gap

    # Core

    # Retrieves the catalog reference data for the PDF.
    #
    def catalog
      state.store.root
    end

    # Measurements

    # Returns the width of the current page from edge-to-edge
    #
    def page_width
      page.dimensions[2]
    end

    # Returns the height of the current page from edge-to-edge
    #
    def page_height
      page.dimensions[3]
    end

    # Returns the width of the left margin for the current page
    #
    def left_margin
      page.margins[:left]
    end

    # Returns the width of the right margin for the current page
    #
    def right_margin
      page.margins[:right]
    end

    # Returns whether the cursor is at the top of the page (i.e., margin box)
    #
    def at_page_top?
      @y == @margin_box.absolute_top
    end

    # Destinations

    # Generates a destination object that resolves to the top of the page
    # specified by the page_num parameter or the current page if no page number
    # is provided. The destination preserves the user's zoom level unlike
    # the destinations generated by the outline builder.
    #
    def dest_top page_num = nil
      dest_xyz 0, page_height, nil, (page_num ? state.pages[page_num - 1] : page)
    end

    # Text

=begin
    # Draws a disc bullet as float text
    def draw_bullet
      float { text '•' }
    end
=end

    # Fonts

    # Registers a new custom font described in the data parameter
    # after converting the font name to a String.
    #
    # Example:
    #
    #  register_font GillSans: {
    #    normal: 'assets/fonts/GillSans.ttf',
    #    bold: 'assets/fonts/GillSans-Bold.ttf',
    #    italic: 'assets/fonts/GillSans-Italic.ttf',
    #  }
    #  
    def register_font data
      font_families.update data.inject({}) {|accum, (key, val)| accum[key.to_s] = val; accum }
    end

    # Enhances the built-in font method to allow the font
    # size to be specified as the second option.
    #
    def font name = nil, options = {}
      if !name.nil? && ((size = options).is_a? ::Numeric)
        options = { size: size }
      end
      super name, options
    end

    # Retrieves the current font name (i.e., family).
    #
    def font_family
      font.options[:family]
    end

    alias :font_name :font_family

    # Retrieves the current font info (family, style, size) as a Hash
    #
    def font_info
      { family: font.options[:family], style: font.options[:style] || :normal, size: @font_size }
    end

    # Sets the font style for the scope of the block to which this method
    # yields. If the style is nil and no block is given, return the current 
    # font style.
    #
    def font_style style = nil
      if block_given?
        font font.options[:family], style: style do
          yield
        end
      elsif style.nil?
        font.options[:style] || :normal
      else
        font font.options[:family], style: style
      end
    end

    # Applies points as a scale factor of the current font if the value
    # provided is less than or equal to 1, then delegates to the super
    # implementation to carry out the built-in functionality.
    #
    def font_size points = nil
      return @font_size unless points
      points = (@font_size * points).round if points <= 1
      super points
    end

    def calc_line_metrics line_height = 1, font = self.font, font_size = self.font_size
      line_height_length = font_size * line_height
      line_gap = line_height_length - font_size
      correction = font.height - font_size
      leading = line_gap - correction
      shift = (font.line_gap + correction + line_gap) / 2
      final_gap = font.line_gap != 0
      LineMetrics.new leading, shift, line_height_length, final_gap
    end

    # Cursor

    # Short-circuits the call to the built-in move_up operation
    # when n is 0.
    #
    def move_up n
      super unless n == 0
    end

    # Short-circuits the call to the built-in move_down operation
    # when n is 0.
    #
    def move_down n
      super unless n == 0
    end

    # Bounds

    # Overrides the built-in pad operation to allow for asymmetric paddings.
    #
    # Example:
    #
    #  pad 20, 10 do
    #    text 'A paragraph with twice as much top padding as bottom padding.'
    #  end
    #
    def pad top, bottom = nil
      move_down top
      yield
      move_down(bottom || top)
    end

    # Combines the built-in pad and indent operations into a single method.
    #
    # Example:
    #
    #  pad_box 20 do
    #    text 'A paragraph with even padding on all sides.'
    #  end
    #
    def pad_box padding
      p_top, p_right, p_bottom, p_left = (padding.is_a? ::Array) ? padding : ([padding] * 4)

      # inlined logic
      move_down p_top
      bounds.add_left_padding p_left
      bounds.add_right_padding p_right
      yield
      move_down p_bottom
    ensure
      bounds.subtract_left_padding p_left
      bounds.subtract_right_padding p_right

      # delegated logic
      #pad padding[0], padding[2] do
      #  indent padding[1], padding[3] do
      #    yield
      #  end
      #end
    end

    # Stretch the current bounds to the left and right edges of the current page.
    #
    def use_page_width_if verdict
      if verdict
        indent(-bounds.absolute_left, bounds.absolute_right - page_width) do
          yield
        end
      else
        yield
      end
    end

    # Graphics

    # Fills the current bounding box with the specified fill color. Before
    # returning from this method, the original fill color on the document is
    # restored.
    #
    def fill_bounds f_color = fill_color
      unless f_color.nil? || f_color.to_s == 'transparent'
        original_fill_color = fill_color
        fill_color f_color
        fill_rectangle bounds.top_left, bounds.width, bounds.height
        fill_color original_fill_color
      end
    end

    # Fills the current bounds using the specified fill color and strokes the
    # bounds using the specified stroke color. Sets the line with if specified
    # in the options. Before returning from this method, the original fill
    # color, stroke color and line width on the document are restored.
    #
    def fill_and_stroke_bounds f_color = fill_color, s_color = stroke_color, options = {}
      save_graphics_state do
        radius = options[:radius] || 0

        # fill
        unless f_color.nil? || f_color.to_s == 'transparent'
          fill_color f_color
          fill_rounded_rectangle bounds.top_left, bounds.width, bounds.height, radius
        end

        # stroke
        unless s_color.nil? || s_color.to_s == 'transparent'
          stroke_color s_color
          line_width options[:line_width] || 0.5
          # FIXME think about best way to indicate dashed borders
          #if options.has_key? :dash_width
          #  dash options[:dash_width], space: options[:dash_space] || 1
          #end
          stroke_rounded_rectangle bounds.top_left, bounds.width, bounds.height, radius
          #undash if options.has_key? :dash_width
        end
      end
    end

    # Fills and, optionally, strokes the current bounds using the fill and
    # stroke color specified, then yields to the block. The only_if option can
    # be used to conditionally disable this behavior.
    #
    def shade_box color, line_color = nil, options = {}
      if (!options.has_key? :only_if) || options[:only_if]
        # FIXME could use save_graphics_state here
        previous_fill_color = current_fill_color
        fill_color color
        fill_rectangle [bounds.left, bounds.top], bounds.right, bounds.top - bounds.bottom
        fill_color previous_fill_color
        if line_color
          line_width 0.5
          previous_stroke_color = current_stroke_color
          stroke_color line_color
          stroke_bounds
          stroke_color previous_stroke_color
        end
      end
      yield
    end

    # A compliment to the stroke_horizontal_rule method, strokes a
    # vertical line using the current bounds. The width of the line
    # can be specified using the line_width option. The horizontal (x)
    # position can be specified using the at option.
    #
    def stroke_vertical_rule s_color = stroke_color, options = {}
      save_graphics_state do
        line_width options[:line_width] || 0.5
        stroke_color s_color
        stroke_vertical_line bounds.bottom, bounds.top, at: (options[:at] || 0)
      end
    end

    # Strokes a horizontal line using the current bounds. The width of the line
    # can be specified using the line_width option.
    #
    def stroke_horizontal_rule s_color = stroke_color, options = {}
      save_graphics_state do
        line_width options[:line_width] || 0.5
        stroke_color s_color
        stroke_horizontal_line bounds.left, bounds.right
      end
    end

    # Pages

    # Import the specified page into the current document.
    #
    def import_page file
      state.compress = false # can't use compression if using template
      start_new_page_discretely template: file
      go_to_page page_count
    end

    # Create a new page for the specified image. If the
    # canvas option is true, the image is stretched to the
    # edges of the page (full coverage).
    def image_page file, options = {}
      start_new_page_discretely
      if options[:canvas]
        canvas do
          image file, width: bounds.width, height: bounds.height
        end
      else
        image file, fit: [bounds.width, bounds.height]
      end
      go_to_page page_count
    end

    # Start a new page without triggering the on_page_create callback
    #
    def start_new_page_discretely options = {}
      saved_callback = state.on_page_create_callback
      state.on_page_create_callback = nil
      start_new_page options
      state.on_page_create_callback = saved_callback
    end

    # Grouping

    # Conditional group operation
    #
    def group_if verdict
      if verdict
        state.optimize_objects = false # optimize objects breaks group
        group { yield }
      else
        yield
      end
    end

    def get_scratch_document
      # marshal if not using transaction feature
      #Marshal.load Marshal.dump @prototype

      # use cached instance, tests show it's faster
      #@prototype ||= ::Prawn::Document.new
      @scratch ||= if defined? @prototype
        scratch = Marshal.load Marshal.dump @prototype
        scratch.instance_variable_set(:@prototype, @prototype)
        scratch
      else
        ::Prawn::Document.new
      end
    end

    def is_scratch?
      state.store.info.data.fetch(:Scratch, false)
    end

    # TODO document me
    def dry_run &block
      scratch = get_scratch_document
      scratch.start_new_page
      original_y = scratch.y
      scratch.font font_family, style: font_style, size: font_size do
        scratch.instance_exec(&block)
      end
      # transaction isn't always reliable
      #scratch.transaction do
      #  scratch.instance_exec(&block)
      #end
      height_of_content = original_y - scratch.y
      #scratch.render_file 'scratch.pdf'
      height_of_content
    end

    # Attempt to keep the objects generated in the block on the same page
    #
    # TODO short-circuit nested usage
    def keep_together &block
      available_space = cursor
      if (height_of_content = dry_run(&block)) > available_space
        started_new_page = true
        start_new_page
      else
        started_new_page = false
      end
      yield height_of_content, started_new_page
    end

    # Attempt to keep the objects generated in the block on the same page
    # if the verdict parameter is true.
    #
    def keep_together_if verdict, &block
      if verdict
        keep_together(&block)
      else
        yield
      end
    end

    def run_with_trial &block
      available_space = cursor
      if (height_of_content = dry_run(&block)) > available_space
        started_new_page = true
      else
        started_new_page = false
      end
      yield height_of_content, started_new_page
    end
  end
end
end
