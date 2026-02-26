# frozen_string_literal: true

module ChromaWave
  module DriverExtraction
    # Sentinel opcodes and lookup tables for driver config extraction.
    #
    # Sentinel opcodes match the constants defined in chroma_wave.h.
    # Lookup tables map Ruby symbols to their C enum/flag names.
    module Opcodes
      # Sentinel opcodes matching chroma_wave.h
      SEQ_SET_CURSOR = 0xF9
      SEQ_SET_WINDOW = 0xFA
      SEQ_SW_RESET   = 0xFB
      SEQ_HW_RESET   = 0xFC
      SEQ_DELAY_MS   = 0xFD
      SEQ_END        = 0xFE
      SEQ_WAIT_BUSY  = 0xFF

      # Human-readable names for sentinel opcodes, used in C output comments.
      SENTINEL_NAMES = {
        SEQ_SET_CURSOR => 'SEQ_SET_CURSOR',
        SEQ_SET_WINDOW => 'SEQ_SET_WINDOW',
        SEQ_SW_RESET => 'SEQ_SW_RESET',
        SEQ_HW_RESET => 'SEQ_HW_RESET',
        SEQ_DELAY_MS => 'SEQ_DELAY_MS',
        SEQ_END => 'SEQ_END',
        SEQ_WAIT_BUSY => 'SEQ_WAIT_BUSY'
      }.freeze

      # Models requiring Tier 2 manual overrides due to complex init protocols.
      TIER2_MODELS = {
        'EPD_4in2' => 'LUT selection in init',
        'EPD_3in7' => 'LUT + 4-gray, unusual register protocol',
        'EPD_7in5_V2' => 'Buffer inversion in Display()',
        'EPD_5in65f' => 'Power cycling per refresh, dual busy polarity',
        'EPD_4in01f' => 'Power cycling per refresh, dual busy polarity',
        'EPD_2in7_V2' => '159-byte LUT for 4-gray mode',
        'EPD_1in02d' => 'Unusual protocol, LUT-based, non-standard busy',
        'EPD_3in52' => 'Complex LUT loading',
        'EPD_2in7' => 'Embedded LUT tables'
      }.freeze

      # Maps Ruby pixel format symbols to C enum names.
      PIXEL_FORMAT_NAMES = {
        mono: 'PIXEL_FORMAT_MONO',
        gray4: 'PIXEL_FORMAT_GRAY4',
        color4: 'PIXEL_FORMAT_COLOR4',
        color7: 'PIXEL_FORMAT_COLOR7'
      }.freeze

      # Maps Ruby busy polarity symbols to C enum names.
      BUSY_POLARITY_NAMES = {
        active_high: 'BUSY_ACTIVE_HIGH',
        active_low: 'BUSY_ACTIVE_LOW'
      }.freeze

      # Maps Ruby capability symbols to C flag names.
      CAPABILITY_NAMES = {
        partial: 'EPD_CAP_PARTIAL',
        fast: 'EPD_CAP_FAST',
        grayscale: 'EPD_CAP_GRAYSCALE',
        dual_buf: 'EPD_CAP_DUAL_BUF'
      }.freeze

      # Display data command bytes used to identify primary/secondary write commands.
      DISPLAY_DATA_CMDS = [0x10, 0x13, 0x24, 0x26].freeze

      # Standard TurnOnDisplay sequences considered "normal" (not Tier 2).
      STANDARD_TURN_ON_SEQUENCES = [[0x22, 0x20], [0x12], [0x20]].freeze
    end
  end
end
