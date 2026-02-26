#!/usr/bin/env ruby
# frozen_string_literal: true

# AUTO-GENERATES ext/chroma_wave/driver_configs_generated.h from vendor Waveshare
# E-Paper driver source files. Parses ~70 .h/.c pairs to extract display dimensions,
# init sequences, reset timing, busy polarity, sleep commands, and capabilities.
#
# Usage:
#   ruby script/extract_driver_configs.rb
#
# Idempotent: running twice produces the same output.

require 'pathname'
require 'strscan'

VENDOR_DIR = Pathname.new(__dir__).join('..', 'vendor', 'waveshare_epd', 'lib', 'e-Paper').expand_path
OUTPUT_PATH = Pathname.new(__dir__).join('..', 'ext', 'chroma_wave', 'driver_configs_generated.h').expand_path

# Sentinel opcodes matching chroma_wave.h
SEQ_SET_CURSOR = 0xF9
SEQ_SET_WINDOW = 0xFA
SEQ_SW_RESET   = 0xFB
SEQ_HW_RESET   = 0xFC
SEQ_DELAY_MS   = 0xFD
SEQ_END        = 0xFE
SEQ_WAIT_BUSY  = 0xFF

SENTINEL_NAMES = {
  SEQ_SET_CURSOR => 'SEQ_SET_CURSOR',
  SEQ_SET_WINDOW => 'SEQ_SET_WINDOW',
  SEQ_SW_RESET => 'SEQ_SW_RESET',
  SEQ_HW_RESET => 'SEQ_HW_RESET',
  SEQ_DELAY_MS => 'SEQ_DELAY_MS',
  SEQ_END => 'SEQ_END',
  SEQ_WAIT_BUSY => 'SEQ_WAIT_BUSY'
}.freeze

# Models that need Tier 2 manual overrides
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

# Pixel format detection based on model name suffixes
COLOR4_PATTERNS = /(?:b(?:_V\d+)?|bc)$/i
GATE_COLOR_PATTERN = /g$/i
COLOR7_PATTERN = /(?:5in65f|4in01f|7in3f|7in3e)$/i

# Regex patterns for parsing C source files
WIDTH_HEIGHT_RE = /#define\s+(\w+)_WIDTH\s+(\d+)/
HEIGHT_RE       = /#define\s+(\w+)_HEIGHT\s+(\d+)/
SEND_COMMAND_RE = /SendCommand\s*\(\s*(0x[0-9A-Fa-f]+|0X[0-9A-Fa-f]+|\d+)\s*\)/
SEND_DATA_RE    = /SendData\s*\(\s*(0x[0-9A-Fa-f]+|0X[0-9A-Fa-f]+|\d+)\s*\)/
DELAY_RE        = /DEV_Delay_ms\s*\(\s*(\d+)\s*\)/
READ_BUSY_RE    = /ReadBusy|WaitUntilIdle|BusyHigh|BusyLow|ReadBusy_HIGH/
SET_WINDOWS_RE  = /SetWindows?\s*\(\s*0\s*,\s*0\s*/
SET_CURSOR_RE   = /SetCursor\s*\(\s*0\s*,\s*0\s*\)/
RESET_DELAY_RE  = /DEV_Delay_ms\s*\(\s*(\d+)\s*\)/

# Display data command bytes used to identify primary/secondary write commands
DISPLAY_DATA_CMDS = [0x10, 0x13, 0x24, 0x26].freeze

# Standard TurnOnDisplay sequences that are considered "normal"
STANDARD_TURN_ON_SEQUENCES = [[0x22, 0x20], [0x12], [0x20]].freeze

# LUT array pattern in vendor C source
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

# Pixel format lookup table
PIXEL_FORMAT_NAMES = {
  mono: 'PIXEL_FORMAT_MONO',
  gray4: 'PIXEL_FORMAT_GRAY4',
  color4: 'PIXEL_FORMAT_COLOR4',
  color7: 'PIXEL_FORMAT_COLOR7'
}.freeze

# Busy polarity lookup table
BUSY_POLARITY_NAMES = {
  active_high: 'BUSY_ACTIVE_HIGH',
  active_low: 'BUSY_ACTIVE_LOW'
}.freeze

# Capability flag names
CAPABILITY_NAMES = {
  partial: 'EPD_CAP_PARTIAL',
  fast: 'EPD_CAP_FAST',
  grayscale: 'EPD_CAP_GRAYSCALE',
  dual_buf: 'EPD_CAP_DUAL_BUF'
}.freeze

# Represents a single extracted driver model configuration
DriverConfig = Struct.new(
  :model_name,
  :width,
  :height,
  :pixel_format,
  :busy_polarity,
  :reset_ms,
  :display_cmd,
  :display_cmd_two,
  :sleep_cmd,
  :sleep_data,
  :capabilities,
  :init_sequence,
  :init_fast_sequence,
  :init_partial_sequence,
  :tier2_reason,
  :warnings,
  keyword_init: true
) do
  # @return [String] C-safe identifier (lowercase, underscored)
  def c_name
    model_name.downcase
  end

  # @return [String] C pixel format enum name
  def c_pixel_format
    PIXEL_FORMAT_NAMES.fetch(pixel_format, 'PIXEL_FORMAT_MONO')
  end

  # @return [String] C busy polarity enum name
  def c_busy_polarity
    BUSY_POLARITY_NAMES.fetch(busy_polarity, 'BUSY_ACTIVE_HIGH')
  end

  # @return [String] C capabilities expression
  def c_capabilities
    caps = CAPABILITY_NAMES.filter_map { |sym, name| name if capabilities.include?(sym) }
    caps.empty? ? '0' : caps.join(' | ')
  end
end

# Reads a file with safe encoding conversion.
#
# @param path [Pathname] file path
# @return [String] UTF-8 encoded content
def read_vendor_file(path)
  path.read(encoding: 'ASCII-8BIT')
      .encode('UTF-8', invalid: :replace, undef: :replace)
end

# Extracts WIDTH/HEIGHT definitions from header content.
#
# @param content [String] header file content
# @return [Hash] with :width, :height, :prefix keys
def extract_dimensions(content)
  result = { width: nil, height: nil, prefix: nil }

  content.scan(WIDTH_HEIGHT_RE) do |name, val|
    result[:width] = val.to_i
    result[:prefix] = name
  end
  content.scan(HEIGHT_RE) do |name, val|
    result[:height] = val.to_i
    result[:prefix] ||= name
  end

  result
end

# Detects capabilities from function declarations in header content.
#
# @param content [String] header file content
# @return [Set<Symbol>] detected capabilities
def detect_capabilities(content)
  caps = Set.new
  caps << :fast      if content.match?(/Init_Fast\b/)
  caps << :partial   if content.match?(/Display_Partial|PartialDisplay|DisplayPartial|Part_Init/i)
  caps << :grayscale if content.match?(/4Gray|4grey|4GRAY/i)
  caps << :dual_buf  if content.match?(/Display_Base\b/)
  caps
end

# Parses a vendor .h file to extract dimensions and detect capabilities.
#
# @param header_path [Pathname] path to .h file
# @return [Hash] extracted data
def parse_header(header_path)
  content = read_vendor_file(header_path)
  dims = extract_dimensions(content)
  { capabilities: detect_capabilities(content), **dims }
rescue StandardError => e
  warn "  [WARN] Failed to parse header #{header_path.basename}: #{e.message}"
  { capabilities: Set.new, width: nil, height: nil, prefix: nil }
end

# Extracts delay timings from reset function lines.
#
# @param reset_fn [String] reset function body
# @return [Array<Integer>] all delay values found
def collect_reset_delays(reset_fn)
  reset_fn.lines.filter_map { |l| l.match(RESET_DELAY_RE)&.[](1)&.to_i }
end

# Extracts reset timing from the Reset() function in a .c file.
#
# @param content [String] full C source text
# @param prefix [String] function prefix
# @return [Array<Integer>, nil] [pre_high_ms, low_ms, post_high_ms] or nil
def extract_reset_timing(content, prefix)
  reset_fn = extract_function_body(content, /#{Regexp.escape(prefix)}_?Reset|EPD_Reset/)
  return nil unless reset_fn

  delays = reset_fn.scan(RESET_DELAY_RE).flatten.map(&:to_i)

  if delays.length >= 3
    timings = collect_reset_delays(reset_fn)
    return timings[0..2] if timings.length >= 3

    delays[0..2]
  elsif delays.length == 2
    [0, delays[0], delays[1]]
  end
end

# Builds a regex to match a C function signature.
#
# @param name_pattern [Regexp] function name pattern
# @return [Regexp]
def function_signature_pattern(name_pattern)
  /(?:static\s+)?(?:void|UBYTE|int)\s+(#{name_pattern.source})\s*\([^)]*\)\s*\{/m
end

# Extracts a brace-delimited block starting at the given index.
#
# @param content [String] source text
# @param start_idx [Integer] index just past the opening brace
# @return [String] block contents
def extract_brace_block(content, start_idx)
  depth = 1
  idx = start_idx

  while idx < content.length && depth.positive?
    case content[idx]
    when '{' then depth += 1
    when '}' then depth -= 1
    end
    idx += 1
  end

  content[start_idx...(idx - 1)]
end

# Extracts the body of a C function matching the given pattern.
#
# @param content [String] full C source
# @param name_pattern [Regexp] function name pattern to match
# @return [String, nil] function body text or nil
def extract_function_body(content, name_pattern)
  match = content.match(function_signature_pattern(name_pattern))
  return nil unless match

  extract_brace_block(content, match.end(0))
end

# Builds a busy-function pattern from prefix.
#
# @param prefix [String] function prefix
# @return [Regexp]
def busy_function_pattern(prefix)
  escaped = Regexp.escape(prefix)
  parts = ["#{escaped}_?ReadBusy", "#{escaped}_?WaitUntilIdle",
           'EPD_WaitUntilIdle', "#{escaped}_?ReadBusy_HIGH"]
  Regexp.new(parts.join('|'))
end

# Checks whether any pattern in the list matches the function body.
#
# @param fn_body [String] function body text
# @param patterns [Array<Regexp>] patterns to check
# @return [Boolean]
def any_pattern_matches?(fn_body, patterns)
  patterns.any? { |pat| fn_body.match?(pat) }
end

# Determines busy polarity from the ReadBusy function body.
#
# @param busy_fn [String] function body text
# @return [Symbol] :active_high, :active_low, or :unknown
def classify_busy_polarity(busy_fn)
  return :active_high if any_pattern_matches?(busy_fn, BUSY_HIGH_PATTERNS)
  return :active_low if any_pattern_matches?(busy_fn, BUSY_LOW_PATTERNS)
  return :active_high if any_pattern_matches?(busy_fn, BUSY_HIGH_LOOP_PATTERNS)

  :unknown
end

# Extracts busy polarity from the ReadBusy/WaitUntilIdle function.
#
# @param content [String] full C source
# @param prefix [String] function prefix
# @return [Symbol] :active_high, :active_low, :dual, or :unknown
def extract_busy_polarity(content, prefix)
  escaped = Regexp.escape(prefix)
  has_high = content.match?(/#{escaped}_?BusyHigh|BusyHigh/)
  has_low  = content.match?(/#{escaped}_?BusyLow|BusyLow/)
  return :dual if has_high && has_low

  busy_fn = extract_function_body(content, busy_function_pattern(prefix))
  return :unknown unless busy_fn

  classify_busy_polarity(busy_fn)
end

# Identifies sleep command pair for UC8179 family (0x07 + 0xA5).
#
# @param commands [Array<Integer>] command bytes
# @param datas [Array<Integer>] data bytes
# @return [Array(Integer, Integer), nil]
def sleep_uc8179(commands, datas)
  [0x07, 0xA5] if commands.include?(0x07) && datas.include?(0xA5)
end

# Identifies sleep command pair for SSD1680 family (0x10 + data).
#
# @param commands [Array<Integer>] command bytes
# @param datas [Array<Integer>] data bytes
# @return [Array(Integer, Integer), nil]
def sleep_ssd1680(commands, datas)
  return nil unless commands.include?(0x10)

  idx = commands.index(0x10)
  data_val = idx && idx < datas.length ? datas[idx] : 0x01
  [0x10, data_val]
end

# Fallback sleep detection: last command+data pair or default.
#
# @param commands [Array<Integer>] command bytes
# @param datas [Array<Integer>] data bytes
# @return [Array(Integer, Integer)]
def fallback_sleep(commands, datas)
  return [0x10, 0x01] if commands.empty? || datas.empty?

  [commands.last, datas.last]
end

# Extracts sleep command and data from the Sleep() function.
#
# @param content [String] full C source
# @param prefix [String] function prefix
# @return [Array(Integer, Integer)] [cmd, data]
def extract_sleep_command(content, prefix)
  sleep_fn = extract_function_body(content, /#{Regexp.escape(prefix)}_?Sleep/)
  return [0x10, 0x01] unless sleep_fn

  cmds = sleep_fn.scan(SEND_COMMAND_RE).flatten.map { |v| Integer(v) }
  datas = sleep_fn.scan(SEND_DATA_RE).flatten.map { |v| Integer(v) }

  sleep_uc8179(cmds, datas) || sleep_ssd1680(cmds, datas) || fallback_sleep(cmds, datas)
end

# Scans a function body for display data command bytes.
#
# @param fn_body [String] function body text
# @return [Array<Integer>] filtered data command bytes
def scan_display_data_cmds(fn_body)
  fn_body.scan(SEND_COMMAND_RE)
         .flatten
         .map { |v| Integer(v) }
         .select { |c| DISPLAY_DATA_CMDS.include?(c) }
end

# Attempts to extract primary/secondary display commands from a function.
#
# @param content [String] full C source
# @param pattern [Regexp] function name pattern
# @return [Array(Integer, Integer), nil]
def try_extract_display_pair(content, pattern)
  fn_body = extract_function_body(content, pattern)
  return nil unless fn_body

  cmds = scan_display_data_cmds(fn_body)
  return nil if cmds.empty?

  [cmds[0], cmds[1]]
end

# Builds display function patterns in priority order.
#
# @param prefix [String] function prefix
# @return [Array<Regexp>]
def display_patterns_for(prefix)
  escaped = Regexp.escape(prefix)
  [
    /#{escaped}_?Display_Base\b/,
    /#{escaped}_?Display[^_P]|#{escaped}_?Display\b/,
    /#{escaped}_?Clear\b/
  ]
end

# Extracts the primary and secondary display command bytes.
#
# @param content [String] full C source
# @param prefix [String] function prefix
# @return [Array(Integer, Integer)] [primary_cmd, secondary_cmd]
def extract_display_commands(content, prefix)
  pair = first_display_pair(content, prefix)
  [pair&.first || 0x24, pair&.last || 0x00]
end

# Finds the first matching display command pair from candidate functions.
#
# @param content [String] full C source
# @param prefix [String] function prefix
# @return [Array(Integer, Integer), nil]
def first_display_pair(content, prefix)
  display_patterns_for(prefix).each do |pattern|
    pair = try_extract_display_pair(content, pattern)
    return pair if pair
  end
  nil
end

# Determines whether a line should be skipped during init parsing.
#
# @param stripped [String] stripped line content
# @return [Boolean]
def skip_init_line?(stripped)
  stripped.empty? ||
    stripped.start_with?('//') ||
    stripped.match?(/^\s*(UWORD|UBYTE|unsigned|static|UDOUBLE|int)\b/) ||
    stripped.match?(/^\s*Debug\b/)
end

# State container for init sequence parsing.
class InitParseState
  attr_reader :sequence

  def initialize
    @sequence = []
    @current_cmd = nil
    @current_data = []
  end

  # Flushes pending command then resets current state.
  # @return [void]
  def flush_and_reset
    flush_command
    @current_cmd = nil
    @current_data = []
  end

  # Appends a sentinel, flushing pending command first.
  # @param sentinel [Integer] sentinel opcode
  # @return [void]
  def emit_sentinel(sentinel)
    flush_and_reset
    @sequence << sentinel
  end

  # Sets the current command byte.
  # @param cmd_byte [Integer] command byte
  # @return [void]
  def start_command(cmd_byte)
    flush_command
    @current_cmd = cmd_byte
    @current_data = []
  end

  # Appends a data byte to the current command.
  # @param byte [Integer] data byte
  # @return [void]
  def add_data(byte)
    @current_data << byte if @current_cmd
  end

  # Encodes a delay value into the sequence.
  # @param delay [Integer] delay in milliseconds
  # @return [void]
  def encode_delay(delay)
    flush_and_reset
    emit_delay_bytes(delay)
  end

  # Finalizes the sequence by flushing and appending SEQ_END.
  # @return [Array<Integer>, nil] the final sequence or nil
  def finalize
    flush_command
    @sequence << SEQ_END
    @sequence == [SEQ_END] ? nil : @sequence
  end

  private

  # @return [void]
  def flush_command
    return unless @current_cmd

    @sequence << @current_cmd
    @sequence << @current_data.length
    @sequence.concat(@current_data)
  end

  # @param delay [Integer] delay in milliseconds
  # @return [void]
  def emit_delay_bytes(delay)
    return unless delay.positive?

    (delay / 255).times { @sequence.push(SEQ_DELAY_MS, 255) }
    remainder = delay % 255
    @sequence.push(SEQ_DELAY_MS, remainder) if remainder.positive?
  end
end

# Maps init line patterns to handler methods for dispatch.
INIT_SENTINEL_PATTERNS = {
  /Reset\s*\(\s*\)/ => SEQ_HW_RESET,
  SET_WINDOWS_RE => SEQ_SET_WINDOW,
  SET_CURSOR_RE => SEQ_SET_CURSOR
}.freeze

# LUT function call pattern
LUT_CALL_RE = /SetFulltReg|SetPartReg|SetLut|Partial_SetLut|4Gray_lut|Load_LUT|Lut\b/i

# Dispatches a stripped init line to the appropriate handler.
#
# @param stripped [String] stripped line text
# @param remaining [Array<String>] remaining lines
# @param state [InitParseState] mutable parse state
# @return [void]
def process_init_line(stripped, remaining, state)
  dispatch_init_line(stripped, remaining, state)
end

# Attempts each init-line handler in priority order.
#
# @param stripped [String] stripped line text
# @param remaining [Array<String>] remaining lines
# @param state [InitParseState] parse state
# @return [void]
def dispatch_init_line(stripped, remaining, state)
  emit_sentinel_match(stripped, state) ||
    emit_busy_match(stripped, state) ||
    emit_command_match(stripped, remaining, state) ||
    emit_data_match(stripped, state) ||
    emit_misc_match(stripped, state)
end

# Emits a sentinel if the line matches a sentinel pattern.
#
# @param stripped [String] stripped line text
# @param state [InitParseState] parse state
# @return [Boolean, nil]
def emit_sentinel_match(stripped, state)
  INIT_SENTINEL_PATTERNS.each do |pattern, sentinel|
    next unless stripped.match?(pattern)

    state.emit_sentinel(sentinel)
    return true
  end
  nil
end

# Emits a busy-wait sentinel if the line matches.
#
# @param stripped [String] stripped line text
# @param state [InitParseState] parse state
# @return [Boolean, nil]
def emit_busy_match(stripped, state)
  return nil unless stripped.match?(READ_BUSY_RE) && !stripped.match?(SEND_COMMAND_RE)

  state.emit_sentinel(SEQ_WAIT_BUSY)
  true
end

# Processes a SendCommand match.
#
# @param stripped [String] stripped line text
# @param remaining [Array<String>] remaining lines
# @param state [InitParseState] parse state
# @return [Boolean, nil]
def emit_command_match(stripped, remaining, state)
  match = stripped.match(SEND_COMMAND_RE)
  return nil unless match

  cmd_byte = Integer(match[1])
  if cmd_byte == 0x12 && sw_reset_context?(remaining)
    state.emit_sentinel(SEQ_SW_RESET)
  else
    state.start_command(cmd_byte)
  end
  true
end

# Processes SendData or Delay matches.
#
# @param stripped [String] stripped line text
# @param state [InitParseState] parse state
# @return [Boolean, nil]
def emit_data_match(stripped, state)
  if (m = stripped.match(SEND_DATA_RE))
    state.add_data(Integer(m[1]))
  elsif (m = stripped.match(DELAY_RE))
    state.encode_delay(m[1].to_i)
  end
  m ? true : nil
end

# Processes LUT calls and SetWindow matches.
#
# @param stripped [String] stripped line text
# @param state [InitParseState] parse state
# @return [Boolean, nil]
def emit_misc_match(stripped, state)
  if stripped.match?(LUT_CALL_RE)
    state.flush_and_reset
  elsif stripped.match?(/SetWindows|SetWindow/)
    state.emit_sentinel(SEQ_SET_WINDOW)
  end
end

# Parses an Init function body into an encoded init sequence.
#
# @param content [String] full C source
# @param _prefix [String] unused, kept for API consistency
# @param func_pattern [Regexp] function name pattern
# @param _header_data [Hash] unused, kept for API consistency
# @return [Array<Integer>, nil] encoded init sequence or nil
def extract_init_sequence(content, _prefix, func_pattern, _header_data)
  init_fn = extract_function_body(content, func_pattern)
  return nil unless init_fn

  state = InitParseState.new
  lines = init_fn.lines

  lines.each_with_index do |line, idx|
    stripped = line.strip
    next if skip_init_line?(stripped)

    process_init_line(stripped, lines[(idx + 1)..], state)
  end

  state.finalize
end

# Classifies a line as decisive for SW reset context.
#
# @param stripped [String] stripped line
# @return [true, false, nil] true=SWRESET, false=REFRESH, nil=keep looking
def classify_sw_reset_line(stripped)
  return nil if stripped.empty? || stripped.start_with?('//')
  return true if stripped.match?(/ReadBusy|WaitUntilIdle|BusyHigh/)
  return false if stripped.match?(/SendData|for\s*\(/)
  return true if stripped.match?(/SendCommand/)

  nil
end

# Determines whether a 0x12 command is a software reset.
#
# @param remaining_lines [Array<String>] lines after the current one
# @return [Boolean]
def sw_reset_context?(remaining_lines)
  return true if remaining_lines.nil? || remaining_lines.empty?

  remaining_lines.each do |line|
    result = classify_sw_reset_line(line.strip)
    return result unless result.nil?
  end

  true
end

# Detects the pixel format for a model.
#
# @param model_name [String] e.g., "EPD_2in13b_V4"
# @param h_content [String] header file content
# @return [Symbol] :mono, :color4, or :color7
def detect_pixel_format(model_name, h_content)
  base = model_name.sub(/^EPD_/, '')

  return :color7 if base.match?(COLOR7_PATTERN)
  return :color4 if base.match?(GATE_COLOR_PATTERN)
  return :color4 if base.match?(COLOR4_PATTERNS)
  return :color7 if h_content.match?(/BLACK\s+0x0.*GREEN\s+0x2.*RED\s+0x4/m)

  :mono
end

# Detects whether embedded LUT tables exceed a threshold.
#
# @param c_content [String] C source content
# @return [Boolean]
def large_luts?(c_content)
  c_content.scan(LUT_ARRAY_PATTERN).flatten.any? { |s| s.to_i > 50 }
rescue StandardError
  false
end

# Formats a hex byte for C output.
#
# @param value [Integer] byte value
# @return [String]
def hex_byte(value)
  format('0x%02X', value)
end

# Formats a sentinel opcode and its optional delay argument.
#
# @param sequence [Array<Integer>] encoded byte sequence
# @param index [Integer] current index
# @param indent [String] indentation prefix
# @return [Array(String, Integer)] [formatted_line, new_index]
def format_sentinel(sequence, index, indent)
  byte = sequence[index]
  name = SENTINEL_NAMES[byte]

  if byte == SEQ_DELAY_MS && index + 1 < sequence.length
    ["#{indent}#{name}, #{sequence[index + 1]},", index + 2]
  else
    ["#{indent}#{name},", index + 1]
  end
end

# Formats a command with no data or an invalid count.
#
# @param cmd [Integer] command byte
# @param index [Integer] current index
# @param indent [String] indentation prefix
# @return [Array(String, Integer)] [formatted_line, new_index]
def format_bare_command(cmd, index, indent)
  ["#{indent}#{hex_byte(cmd)}, 0,", index + 1]
end

# Formats a command byte with its count and data payload.
#
# @param sequence [Array<Integer>] encoded byte sequence
# @param index [Integer] current index
# @param indent [String] indentation prefix
# @return [Array(String, Integer)] [formatted_line, new_index]
def format_command_entry(sequence, index, indent)
  cmd = sequence[index]
  return format_bare_command(cmd, index, indent) unless index + 1 < sequence.length

  count = sequence[index + 1]
  return format_bare_command(cmd, index, indent) unless count >= 0 && count < 0xF0

  data_bytes = sequence[index + 2, count] || []
  [format_data_line(cmd, count, data_bytes, indent), index + 2 + count]
end

# Builds the formatted line for a command with data.
#
# @param cmd [Integer] command byte
# @param count [Integer] data count
# @param data_bytes [Array<Integer>] data payload
# @param indent [String] indentation prefix
# @return [String]
def format_data_line(cmd, count, data_bytes, indent)
  return "#{indent}#{hex_byte(cmd)}, 0," if data_bytes.empty?

  data_str = data_bytes.map { |b| hex_byte(b) }.join(', ')
  "#{indent}#{hex_byte(cmd)}, #{count}, #{data_str},"
end

# Generates the C array initializer for an init sequence.
#
# @param sequence [Array<Integer>] encoded byte sequence
# @param indent [String] indentation prefix
# @return [String] C array content
def format_init_sequence(sequence, indent = '    ')
  return '' if sequence.nil? || sequence.empty?

  lines = []
  i = 0
  while i < sequence.length
    line, i = format_one_entry(sequence, i, indent)
    lines << line
  end
  lines.join("\n")
end

# Formats a single entry (sentinel or command) from a sequence.
#
# @param sequence [Array<Integer>] encoded byte sequence
# @param index [Integer] current index
# @param indent [String] indentation prefix
# @return [Array(String, Integer)] [formatted_line, new_index]
def format_one_entry(sequence, index, indent)
  if SENTINEL_NAMES.key?(sequence[index])
    format_sentinel(sequence, index, indent)
  else
    format_command_entry(sequence, index, indent)
  end
end

# Finds the first matching init sequence from a list of patterns.
#
# @param content [String] full C source
# @param prefix [String] function prefix
# @param patterns [Array<Regexp>] patterns to try
# @param header_data [Hash] header data
# @return [Array<Integer>, nil]
def find_init_sequence(content, prefix, patterns, header_data)
  patterns.each do |pattern|
    seq = extract_init_sequence(content, prefix, pattern, header_data)
    return seq if seq
  end
  nil
end

# Builds the list of init function patterns for a model.
#
# @param model_name [String] model name
# @param prefix [String] function prefix
# @return [Array<Regexp>]
def init_patterns_for(model_name, prefix)
  escaped = Regexp.escape(prefix)
  patterns = [
    /#{escaped}_Init\b(?!_Fast|_Part|_Partial|_4Gray|_4GRAY|_GUI)/,
    /#{escaped}_?Init\b(?!_Fast|_Part|_Partial|_4Gray|_4GRAY|_GUI)/
  ]
  patterns.unshift(/EPD_3IN7_1Gray_Init/) if model_name == 'EPD_3in7'
  patterns
end

# Builds the list of partial init function patterns.
#
# @param prefix [String] function prefix
# @return [Array<Regexp>]
def partial_init_patterns_for(prefix)
  escaped = Regexp.escape(prefix)
  [/#{escaped}_?Init_Partial/, /#{escaped}_?Part_Init/, /#{escaped}_?Init_Part/]
end

# Detects a Tier 2 reason for a model.
#
# @param model_name [String] model name
# @param c_content [String] C source content
# @param prefix [String] function prefix
# @return [String, nil]
def detect_tier2_reason(model_name, c_content, prefix)
  TIER2_MODELS[model_name] ||
    (large_luts?(c_content) && 'Large embedded LUT tables') ||
    detect_nonstandard_turn_on(c_content, prefix)
end

# Detects non-standard TurnOnDisplay sequences.
#
# @param c_content [String] C source content
# @param prefix [String] function prefix
# @return [String, nil]
def detect_nonstandard_turn_on(c_content, prefix)
  turn_on = extract_function_body(c_content, /#{Regexp.escape(prefix)}_?TurnOnDisplay\b/)
  return nil unless turn_on

  cmds = turn_on.scan(SEND_COMMAND_RE).flatten.map { |v| Integer(v) }
  return nil if cmds.empty? || STANDARD_TURN_ON_SEQUENCES.include?(cmds)

  'Non-standard TurnOnDisplay sequence'
end

# Collects extraction warnings for missing data.
#
# @param header_data [Hash] parsed header data
# @param reset_ms [Array, nil] reset timing
# @param busy_pol [Symbol] busy polarity
# @param init_seq [Array, nil] init sequence
# @return [Array<String>]
def collect_warnings(header_data:, reset_ms:, busy_pol:, init_seq:)
  [].tap do |w|
    w << 'Could not extract WIDTH/HEIGHT' unless header_data[:width] && header_data[:height]
    w << 'Could not extract reset timing' unless reset_ms
    w << 'Could not determine busy polarity' if busy_pol == :unknown
    w << 'Could not extract init sequence' unless init_seq
  end
end

# Extracts all C-level signal data from source content.
#
# @param c_content [String] C source content
# @param prefix [String] function prefix
# @return [Hash]
def extract_signals(c_content, prefix)
  sleep_cmd, sleep_data = extract_sleep_command(c_content, prefix)

  {
    reset_ms: extract_reset_timing(c_content, prefix),
    busy_pol: extract_busy_polarity(c_content, prefix),
    display_cmds: extract_display_commands(c_content, prefix),
    sleep_cmd:,
    sleep_data:
  }
end

# Extracts all init sequences for a model.
#
# @param c_content [String] C source content
# @param prefix [String] function prefix
# @param model_name [String] model name
# @param header_data [Hash] header data
# @return [Hash] init, fast, and partial sequences
def extract_all_inits(c_content, prefix, model_name, header_data)
  escaped = Regexp.escape(prefix)
  {
    init_seq: find_init_sequence(c_content, prefix, init_patterns_for(model_name, prefix), header_data),
    init_fast_seq: extract_init_sequence(c_content, prefix, /#{escaped}_?Init_Fast/, header_data),
    init_partial_seq: find_init_sequence(c_content, prefix, partial_init_patterns_for(prefix), header_data)
  }
end

# Derives the C function prefix from header data or model name.
#
# @param header_data [Hash] parsed header data
# @param model_name [String] model name
# @return [String]
def derive_prefix(header_data, model_name)
  header_data[:prefix] || model_name.upcase.gsub(/[^A-Z0-9]/, '_')
end

# Top-level extraction: processes a single model's .h and .c files.
#
# @param h_path [Pathname] header file path
# @param c_path [Pathname] source file path
# @return [DriverConfig]
def extract_model(h_path, c_path)
  model_name = h_path.basename('.h').to_s
  header_data = parse_header(h_path)
  prefix = derive_prefix(header_data, model_name)
  c_content = read_vendor_file(c_path)

  assemble_config(
    { model_name:, header_data:, prefix:,
      h_content: read_vendor_file(h_path),
      c_content:, signals: extract_signals(c_content, prefix),
      inits: extract_all_inits(c_content, prefix, model_name, header_data) }
  )
end

# Assembles the final DriverConfig from extracted components.
#
# @param ctx [Hash] extraction context with all needed data
# @return [DriverConfig]
def assemble_config(ctx)
  DriverConfig.new(
    **config_identity_fields(ctx),
    **config_signal_fields(ctx[:signals]),
    **config_init_fields(ctx),
    **config_meta_fields(ctx)
  )
end

# Builds identity fields (name, dimensions, format, capabilities).
#
# @param ctx [Hash] extraction context
# @return [Hash]
def config_identity_fields(ctx)
  {
    model_name: ctx[:model_name],
    width: ctx[:header_data][:width] || 0,
    height: ctx[:header_data][:height] || 0,
    pixel_format: detect_pixel_format(ctx[:model_name], ctx[:h_content]),
    capabilities: ctx[:header_data][:capabilities]
  }
end

# Builds signal fields (busy, reset, display, sleep).
#
# @param signals [Hash] extracted signal data
# @return [Hash]
def config_signal_fields(signals)
  busy = signals[:busy_pol] == :dual ? :active_low : signals[:busy_pol]
  {
    busy_polarity: busy,
    reset_ms: signals[:reset_ms] || [20, 2, 20],
    display_cmd: signals[:display_cmds][0],
    display_cmd_two: signals[:display_cmds][1],
    sleep_cmd: signals[:sleep_cmd],
    sleep_data: signals[:sleep_data]
  }
end

# Builds init sequence fields.
#
# @param ctx [Hash] extraction context
# @return [Hash]
def config_init_fields(ctx)
  inits = ctx[:inits]
  {
    init_sequence: inits[:init_seq],
    init_fast_sequence: inits[:init_fast_seq],
    init_partial_sequence: inits[:init_partial_seq]
  }
end

# Builds metadata fields (tier2 reason, warnings).
#
# @param ctx [Hash] extraction context
# @return [Hash]
def config_meta_fields(ctx)
  {
    tier2_reason: detect_tier2_reason(ctx[:model_name], ctx[:c_content], ctx[:prefix]),
    warnings: collect_warnings(
      header_data: ctx[:header_data], reset_ms: ctx[:signals][:reset_ms],
      busy_pol: ctx[:signals][:busy_pol], init_seq: ctx[:inits][:init_seq]
    )
  }
end

# Emits C array declarations for a config's init sequences.
#
# @param config [DriverConfig] the model config
# @return [Array<String>]
def emit_init_arrays(config)
  lines = emit_primary_init_array(config)
  emit_named_init_array(config, :init_fast_sequence, 'init_fast', lines)
  emit_named_init_array(config, :init_partial_sequence, 'init_partial', lines)
  lines
end

# Emits the primary init array with optional tier2 comment.
#
# @param config [DriverConfig] the model config
# @return [Array<String>]
def emit_primary_init_array(config)
  return [] unless config.init_sequence

  tier2 = config.tier2_reason ? " /* TIER2: #{config.tier2_reason} */" : ''
  [
    "static const uint8_t #{config.c_name}_init[] = {#{tier2}",
    format_init_sequence(config.init_sequence),
    '};',
    ''
  ]
end

# Emits a named init array if the sequence exists.
#
# @param config [DriverConfig] the model config
# @param field [Symbol] sequence field name
# @param suffix [String] C array name suffix
# @param lines [Array<String>] output accumulator
# @return [void]
def emit_named_init_array(config, field, suffix, lines)
  seq = config.send(field)
  return unless seq

  lines << "static const uint8_t #{config.c_name}_#{suffix}[] = {"
  lines << format_init_sequence(seq)
  lines << '};'
  lines << ''
end

# Emits the .xxx_sequence and .xxx_sequence_len field pair.
#
# @param config [DriverConfig] the model config
# @param field [Symbol] sequence field
# @param name [String] C field name prefix
# @return [String]
def emit_sequence_field(config, field, name)
  seq = config.send(field)
  if seq
    arr = "#{config.c_name}_#{name}"
    "        .#{name}_sequence = #{arr},\n        .#{name}_sequence_len = sizeof(#{arr}),"
  else
    "        .#{name}_sequence = NULL,\n        .#{name}_sequence_len = 0,"
  end
end

# Emits the identity fields of a config entry (name, dimensions, format).
#
# @param config [DriverConfig] the model config
# @param tier2_comment [String] tier2 comment or empty string
# @return [Array<String>]
def emit_config_identity(config, tier2_comment)
  [
    "    {#{tier2_comment}",
    "        .name = \"#{config.c_name}\",",
    "        .width = #{config.width},",
    "        .height = #{config.height},",
    "        .pixel_format = #{config.c_pixel_format},"
  ]
end

# Emits the hardware fields of a config entry (busy, reset, display).
#
# @param config [DriverConfig] the model config
# @return [Array<String>]
def emit_config_hardware(config)
  reset = config.reset_ms
  [
    "        .busy_polarity = #{config.c_busy_polarity},",
    "        .reset_ms = {#{reset[0]}, #{reset[1]}, #{reset[2]}},",
    "        .display_cmd = #{hex_byte(config.display_cmd)},",
    "        .display_cmd_2 = #{hex_byte(config.display_cmd_two || 0)},"
  ]
end

# Emits the sequence and trailing fields of a config entry.
#
# @param config [DriverConfig] the model config
# @param last [Boolean] whether this is the last entry
# @return [Array<String>]
def emit_config_sequence_fields(config, last)
  [
    emit_sequence_field(config, :init_sequence, 'init'),
    "        .capabilities = #{config.c_capabilities},",
    emit_sequence_field(config, :init_fast_sequence, 'init_fast'),
    emit_sequence_field(config, :init_partial_sequence, 'init_partial'),
    "        .sleep_cmd = #{hex_byte(config.sleep_cmd)},",
    "        .sleep_data = #{hex_byte(config.sleep_data)}",
    "    }#{',' unless last}"
  ]
end

# Emits the struct entry for a single model in the config table.
#
# @param config [DriverConfig] the model config
# @param last [Boolean] whether this is the last entry
# @return [Array<String>]
def emit_config_entry(config, last:)
  tier2 = config.tier2_reason ? " /* TIER2: #{config.tier2_reason} */" : ''
  emit_config_identity(config, tier2) + emit_config_hardware(config) + emit_config_sequence_fields(config, last)
end

# Emits the config table entries for all models.
#
# @param configs [Array<DriverConfig>] all model configs
# @return [Array<String>]
def emit_config_table(configs)
  lines = ['/* Model configuration table */', 'static const epd_model_config_t epd_model_configs[] = {']
  configs.each_with_index do |config, idx|
    lines.concat(emit_config_entry(config, last: idx == configs.length - 1))
  end
  lines << '};'
  lines
end

# Generates the complete C header file content.
#
# @param configs [Array<DriverConfig>] all model configurations
# @return [String] complete C header file content
def generate_header(configs)
  lines = header_preamble(configs)
  configs.each { |config| lines.concat(emit_init_arrays(config)) }
  lines.concat(emit_config_table(configs))
  lines.concat(header_footer)
  lines.join("\n")
end

# Returns the C header preamble lines.
#
# @param configs [Array<DriverConfig>] configs for summary comment
# @return [Array<String>]
def header_preamble(configs)
  tier2_count = configs.count(&:tier2_reason)
  [
    '/* AUTO-GENERATED by script/extract_driver_configs.rb -- DO NOT EDIT */',
    "/* Models: #{configs.length} total, #{tier2_count} tier2 */",
    '', '#ifndef DRIVER_CONFIGS_GENERATED_H', '#define DRIVER_CONFIGS_GENERATED_H',
    '', '#include "chroma_wave.h"', '#include "driver_registry.h"', ''
  ]
end

# Returns the C header footer lines.
#
# @return [Array<String>]
def header_footer
  [
    '',
    '#define EPD_MODEL_COUNT (sizeof(epd_model_configs) / sizeof(epd_model_configs[0]))',
    '',
    '#endif /* DRIVER_CONFIGS_GENERATED_H */',
    ''
  ]
end

# Processes a single header file and returns the config or nil.
#
# @param h_path [Pathname] header file path
# @param skipped [Array<String>] accumulator for skipped model names
# @return [DriverConfig, nil]
def process_model(h_path, skipped)
  model_name = h_path.basename('.h').to_s
  c_path = h_path.sub_ext('.c')

  return skip_model(model_name, 'no matching .c file', skipped) unless c_path.exist?

  print "  #{model_name}... "
  config = extract_model(h_path, c_path)

  return skip_model(nil, 'SKIP (no dimensions)', skipped, model_name) if config.width.zero? || config.height.zero?

  puts format_config_status(config)
  config
end

# Records a skipped model and prints a message.
#
# @param label [String, nil] label for the skip message
# @param reason [String] skip reason
# @param skipped [Array<String>] accumulator
# @param name [String] model name to add to skipped list
# @return [nil]
def skip_model(label, reason, skipped, name = label)
  if label
    puts "  [SKIP] #{label}: #{reason}"
  else
    puts reason
  end
  skipped << name
  nil
end

# Builds the core status parts for a config.
#
# @param config [DriverConfig] the model config
# @return [Array<String>]
def core_status_parts(config)
  [
    "#{config.width}x#{config.height}",
    config.pixel_format.to_s,
    "busy:#{config.busy_polarity}",
    "caps:[#{config.capabilities.to_a.join(',')}]"
  ]
end

# Builds the optional status parts for init sequences.
#
# @param config [DriverConfig] the model config
# @return [Array<String>]
def init_status_parts(config)
  parts = []
  parts << 'TIER2' if config.tier2_reason
  parts << seq_status('init', config.init_sequence)
  parts << seq_status('fast', config.init_fast_sequence) if config.init_fast_sequence
  parts << seq_status('partial', config.init_partial_sequence) if config.init_partial_sequence
  parts
end

# Formats a sequence length status string.
#
# @param label [String] label prefix
# @param sequence [Array, nil] the sequence
# @return [String]
def seq_status(label, sequence)
  "#{label}:#{sequence&.length || 0}B"
end

# Formats a status line for a successfully extracted config.
#
# @param config [DriverConfig] the model config
# @return [String]
def format_config_status(config)
  parts = core_status_parts(config) + init_status_parts(config)
  warns = config.warnings.empty? ? '' : " [WARN: #{config.warnings.join('; ')}]"
  parts.join(' ') + warns
end

# Prints summary header lines.
#
# @param configs [Array<DriverConfig>] extracted configs
# @param skipped [Array<String>] skipped model names
# @return [void]
def print_summary_header(configs, skipped)
  puts '=' * 70
  puts 'SUMMARY'
  puts '=' * 70
  puts "Total models extracted: #{configs.length}"
  puts "Skipped: #{skipped.length} (#{skipped.join(', ')})" unless skipped.empty?
  puts "Tier 2 models: #{configs.count(&:tier2_reason)}"
end

# Prints the extraction summary.
#
# @param configs [Array<DriverConfig>] extracted configs
# @param skipped [Array<String>] skipped model names
# @return [void]
def print_summary(configs, skipped)
  puts
  print_summary_header(configs, skipped)
  puts
  print_tier2_details(configs)
  print_warning_details(configs)
end

# Prints Tier 2 model details.
#
# @param configs [Array<DriverConfig>] extracted configs
# @return [void]
def print_tier2_details(configs)
  tier2 = configs.select(&:tier2_reason)
  return if tier2.empty?

  puts 'Tier 2 models requiring manual overrides:'
  tier2.each { |c| puts "  - #{c.model_name}: #{c.tier2_reason}" }
  puts
end

# Prints models with warnings.
#
# @param configs [Array<DriverConfig>] extracted configs
# @return [void]
def print_warning_details(configs)
  with_warnings = configs.reject { |c| c.warnings.empty? }
  return if with_warnings.empty?

  puts 'Models with warnings:'
  with_warnings.each { |c| puts "  - #{c.model_name}: #{c.warnings.join('; ')}" }
  puts
end

# Writes the generated header and prints a summary.
#
# @param configs [Array<DriverConfig>] extracted configs
# @return [void]
def write_output(configs)
  header_content = generate_header(configs)
  OUTPUT_PATH.dirname.mkpath
  OUTPUT_PATH.write(header_content)
  puts "Generated #{OUTPUT_PATH} (#{header_content.length} bytes, #{configs.length} models)"
end

# Main execution
def main
  puts "Extracting driver configs from #{VENDOR_DIR}"
  puts "Output: #{OUTPUT_PATH}"
  puts
  headers = VENDOR_DIR.glob('EPD_*.h').sort_by(&:basename)
  puts "Found #{headers.length} header files"
  puts
  skipped = []
  configs = headers.filter_map { |h| process_model(h, skipped) }
  print_summary(configs, skipped)
  write_output(configs)
end

main
