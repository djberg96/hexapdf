# -*- encoding: utf-8 -*-

require 'test_helper'
require 'hexapdf/document'

describe HexaPDF::Layout::LineFragment do
  before do
    @doc = HexaPDF::Document.new
    @font = @doc.fonts.load("Times", custom_encoding: true)
    @line = setup_line
  end

  def setup_fragment(text)
    HexaPDF::Layout::TextFragment.new(font: @font, font_size: 10, items: @font.decode_utf8(text))
  end

  def setup_box(width, height, valign = :baseline)
    HexaPDF::Layout::InlineBox.new(width, height, valign: valign) {}
  end

  def setup_line(items: [], **options)
    HexaPDF::Layout::LineFragment.new(items: items, **options)
  end

  describe "initialize" do
    it "allows setting the items of the line fragment" do
      assert_equal(:value, setup_line(items: :value).items)
    end

    it "allows setting custom options" do
      assert_equal({key: :value}, setup_line(key: :value).options)
    end
  end

  it "adds items to the line" do
    @line << :test << :other
    assert_equal([:test, :other], @line.items)
  end

  describe "with text fragments" do
    before do
      @frag_h = setup_fragment("H")
      @frag_y = setup_fragment("y")
      @line << @frag_h << @frag_y << @frag_h
    end

    it "calculates the various x/y values correctly" do
      assert_equal(@frag_h.x_min, @line.x_min)
      assert_equal(@frag_h.width + @frag_y.width + @frag_h.x_max, @line.x_max)
      assert_equal(@frag_y.y_min, @line.y_min)
      assert_equal(@frag_h.y_max, @line.y_max)
      assert_equal(@frag_y.y_min, @line.text_y_min)
      assert_equal(@frag_h.y_max, @line.text_y_max)
      assert_equal(2 * @frag_h.width + @frag_y.width, @line.width)
      assert_equal(@frag_h.y_max - @frag_y.y_min, @line.height)
      assert_equal(-@frag_y.y_min, @line.baseline_offset)
    end

    describe "and with inline boxes" do
      it "x_min is correct if an inline box is the first item" do
        @line.items.unshift(setup_box(10, 10))
        assert_equal(0, @line.x_min)
      end

      it "x_max is correct if an inline box is the last item" do
        @line << setup_box(10, 10)
        assert_equal(@line.width, @line.x_max)
      end

      it "doesn't change text_y_min/text_y_max" do
        text_y_min, text_y_max = @line.text_y_min, @line.text_y_max
        @line << setup_box(10, 30, :text_top) << setup_box(10, 30, :text_bottom)
        @line.clear_cache
        assert_equal(text_y_min, @line.text_y_min)
        assert_equal(text_y_max, @line.text_y_max)
      end

      it "y values are not changed if all boxes are smaller than the text's height" do
        *y_values = @line.y_min, @line.y_max, @line.text_y_min, @line.text_y_max
        @line << setup_box(10, 5, :baseline)
        @line.clear_cache
        assert_equal(y_values, [@line.y_min, @line.y_max, @line.text_y_min, @line.text_y_max])
      end

      it "changes y_max to fit if baseline/text_bottom/bottom boxes are higher than the text" do
        y_min = @line.y_min
        box = setup_box(10, 50, :baseline)
        @line.add(box)

        @line.clear_cache
        assert_equal(50, @line.y_max)
        assert_equal(y_min, @line.y_min)

        box.instance_variable_set(:@valign, :text_bottom)
        @line.clear_cache
        assert_equal(50 + @line.text_y_min, @line.y_max)
        assert_equal(y_min, @line.y_min)

        box.instance_variable_set(:@valign, :bottom)
        @line.clear_cache
        assert_equal(50 + @line.text_y_min, @line.y_max)
        assert_equal(y_min, @line.y_min)
      end

      it "changes y_min to fit if text_top/top boxes are higher than the text" do
        y_max = @line.y_max
        box = setup_box(10, 50, :text_top)
        @line.add(box)

        @line.clear_cache
        assert_equal(@line.text_y_max - 50, @line.y_min)
        assert_equal(y_max, @line.y_max)

        box.instance_variable_set(:@valign, :top)
        @line.clear_cache
        assert_equal(@line.text_y_max - 50, @line.y_min)
        assert_equal(y_max, @line.y_max)
      end

      it "changes y_min/y_max to fit if boxes are aligned in both directions" do
        @line << setup_box(10, 20, :text_top) <<
          setup_box(10, 20, :text_bottom) <<
          setup_box(10, 20, :top) <<
          setup_box(10, 70, :bottom)
        assert_equal(@line.text_y_max - 20, @line.y_min)
        assert_equal(@line.text_y_max - 20 + 70, @line.y_max)
      end
    end
  end

  it "fails if an item uses an invalid valign value" do
    @line << setup_box(10, 20, :invalid)
    assert_raises(HexaPDF::Error) { @line.y_min }
  end

  describe "each" do
    it "iterates over all items and yields them with their offset values" do
      @line << setup_fragment("H") <<
        setup_box(10, 10, :top) <<
        setup_box(10, 10, :text_top) <<
        setup_box(10, 10, :baseline) <<
        setup_box(10, 10, :text_bottom) <<
        setup_box(10, 10, :bottom)
      result = [
        [@line.items[0], 0, 0],
        [@line.items[1], @line.items[0].width, @line.y_max - 10],
        [@line.items[2], @line.items[0].width + 10, @line.text_y_max - 10],
        [@line.items[3], @line.items[0].width + 20, 0],
        [@line.items[4], @line.items[0].width + 30, @line.text_y_min],
        [@line.items[5], @line.items[0].width + 40, @line.y_min],
      ]
      assert_equal(result, @line.to_enum(:each).map {|*a| a})
    end

    it "fails if an item uses an invalid valign value" do
      @line << setup_box(10, 10, :invalid)
      assert_raises(HexaPDF::Error) { @line.each {} }
    end
  end
end