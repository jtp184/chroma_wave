# frozen_string_literal: true

require_relative 'opcodes'

module ChromaWave
  module DriverExtraction
    # Regex patterns for parsing Waveshare vendor C source files.
    #
    # All patterns are constants to avoid repeated compilation. Complex
    # patterns use +/x+ mode for readability.
    module Patterns
      include Opcodes

      # Pixel format detection based on model name suffixes.
      COLOR4_PATTERNS    = /(?:b(?:_V\d+)?|bc)$/i
      GATE_COLOR_PATTERN = /g$/i
      COLOR7_PATTERN     = /(?:5in65f|4in01f|7in3f|7in3e)$/i

      # Dimension extraction from #define directives.
      WIDTH_HEIGHT_RE = /#define\s+(\w+)_WIDTH\s+(\d+)/
      HEIGHT_RE       = /#define\s+(\w+)_HEIGHT\s+(\d+)/

      # C function call patterns.
      SEND_COMMAND_RE = /SendCommand\s*\(\s*(0x[0-9A-Fa-f]+|0X[0-9A-Fa-f]+|\d+)\s*\)/
      SEND_DATA_RE    = /SendData\s*\(\s*(0x[0-9A-Fa-f]+|0X[0-9A-Fa-f]+|\d+)\s*\)/
      DELAY_RE        = /DEV_Delay_ms\s*\(\s*(\d+)\s*\)/
      READ_BUSY_RE    = /ReadBusy|WaitUntilIdle|BusyHigh|BusyLow|ReadBusy_HIGH/
      SET_WINDOWS_RE  = /SetWindows?\s*\(\s*0\s*,\s*0\s*/
      SET_CURSOR_RE   = /SetCursor\s*\(\s*0\s*,\s*0\s*\)/
      RESET_DELAY_RE  = /DEV_Delay_ms\s*\(\s*(\d+)\s*\)/

      # LUT array pattern in vendor C source.
      LUT_ARRAY_PATTERN = /(?:unsigned\s+char|UBYTE|const\s+unsigned\s+char|
        static\s+const\s+unsigned\s+char|
        static\s+const\s+UBYTE)\s+\w*[Ll][Uu][Tt]\w*\s*\[\s*(\d*)\s*\]/x

      # Busy polarity classification patterns grouped by result.
      # Order matters: earlier arms take priority in case/when matching.
      BUSY_HIGH_PATTERNS = [
        /DEV_Digital_Read\s*\(\s*EPD_BUSY_PIN\s*\)\s*==\s*0/
      ].freeze

      BUSY_LOW_PATTERNS = [
        /DEV_Digital_Read\s*\(\s*EPD_BUSY_PIN\s*\)\s*==\s*1/,
        /!\s*\(\s*DEV_Digital_Read\s*\(\s*EPD_BUSY_PIN\s*\)\s*\)/,
        /while\s*\(\s*!\s*\(\s*DEV_Digital_Read/
      ].freeze

      BUSY_HIGH_LOOP_PATTERNS = [
        /while\s*\(\s*DEV_Digital_Read/,
        /while\s*\(\s*busy\s*\)/,
        /!\s*\(\s*busy\s*&\s*0x01\s*\)/
      ].freeze

      # Maps init line patterns to sentinel opcodes for dispatch.
      INIT_SENTINEL_PATTERNS = {
        /Reset\s*\(\s*\)/ => SEQ_HW_RESET,
        SET_WINDOWS_RE => SEQ_SET_WINDOW,
        SET_CURSOR_RE => SEQ_SET_CURSOR
      }.freeze

      # LUT function call pattern.
      LUT_CALL_RE = /SetFulltReg|SetPartReg|SetLut|Partial_SetLut|4Gray_lut|Load_LUT|Lut\b/i
    end
  end
end
