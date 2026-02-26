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

require "pathname"
require "strscan"

VENDOR_DIR = Pathname.new(__dir__).join("..", "vendor", "waveshare_epd", "lib", "e-Paper").expand_path
OUTPUT_PATH = Pathname.new(__dir__).join("..", "ext", "chroma_wave", "driver_configs_generated.h").expand_path

# Sentinel opcodes matching chroma_wave.h
SEQ_SET_CURSOR = 0xF9
SEQ_SET_WINDOW = 0xFA
SEQ_SW_RESET   = 0xFB
SEQ_HW_RESET   = 0xFC
SEQ_DELAY_MS   = 0xFD
SEQ_END        = 0xFE
SEQ_WAIT_BUSY  = 0xFF

SENTINEL_NAMES = {
  SEQ_SET_CURSOR => "SEQ_SET_CURSOR",
  SEQ_SET_WINDOW => "SEQ_SET_WINDOW",
  SEQ_SW_RESET   => "SEQ_SW_RESET",
  SEQ_HW_RESET   => "SEQ_HW_RESET",
  SEQ_DELAY_MS   => "SEQ_DELAY_MS",
  SEQ_END        => "SEQ_END",
  SEQ_WAIT_BUSY  => "SEQ_WAIT_BUSY"
}.freeze

# Models that need Tier 2 manual overrides
TIER2_MODELS = {
  "EPD_4in2"     => "LUT selection in init",
  "EPD_3in7"     => "LUT + 4-gray, unusual register protocol",
  "EPD_7in5_V2"  => "Buffer inversion in Display()",
  "EPD_5in65f"   => "Power cycling per refresh, dual busy polarity",
  "EPD_4in01f"   => "Power cycling per refresh, dual busy polarity",
  "EPD_2in7_V2"  => "159-byte LUT for 4-gray mode",
  "EPD_1in02d"   => "Unusual protocol, LUT-based, non-standard busy",
  "EPD_3in52"    => "Complex LUT loading",
  "EPD_2in7"     => "Embedded LUT tables"
}.freeze

# Pixel format detection based on model name suffixes
COLOR4_PATTERNS = /(?:b(?:_V\d+)?|bc)$/i.freeze   # tri-color: b, b_V2, b_V3, b_V4, bc
GATE_COLOR_PATTERN = /g$/i.freeze                   # gate-driven tri-color: g suffix
COLOR7_PATTERN = /(?:5in65f|4in01f|7in3f|7in3e)$/i.freeze  # 7-color ACeP

# Regex patterns for parsing C source files
WIDTH_HEIGHT_RE  = /#define\s+(\w+)_WIDTH\s+(\d+)/.freeze
HEIGHT_RE        = /#define\s+(\w+)_HEIGHT\s+(\d+)/.freeze
SEND_COMMAND_RE  = /SendCommand\s*\(\s*(0x[0-9A-Fa-f]+|0X[0-9A-Fa-f]+|\d+)\s*\)/.freeze
SEND_DATA_RE     = /SendData\s*\(\s*(0x[0-9A-Fa-f]+|0X[0-9A-Fa-f]+|\d+)\s*\)/.freeze
DELAY_RE         = /DEV_Delay_ms\s*\(\s*(\d+)\s*\)/.freeze
READ_BUSY_RE     = /ReadBusy|WaitUntilIdle|BusyHigh|BusyLow|ReadBusy_HIGH/.freeze
SET_WINDOWS_RE   = /SetWindows?\s*\(\s*0\s*,\s*0\s*/.freeze
SET_CURSOR_RE    = /SetCursor\s*\(\s*0\s*,\s*0\s*\)/.freeze

RESET_DELAY_RE   = /DEV_Delay_ms\s*\(\s*(\d+)\s*\)/.freeze
RESET_WRITE_HI   = /DEV_Digital_Write\s*\(\s*EPD_RST_PIN\s*,\s*1\s*\)/.freeze
RESET_WRITE_LO   = /DEV_Digital_Write\s*\(\s*EPD_RST_PIN\s*,\s*0\s*\)/.freeze

# Represents a single extracted driver model configuration
DriverConfig = Struct.new(
  :model_name,        # e.g., "EPD_2in13_V4"
  :width,             # integer
  :height,            # integer
  :pixel_format,      # :mono, :gray4, :color4, :color7
  :busy_polarity,     # :active_high, :active_low, :dual, :unknown
  :reset_ms,          # [pre_high, low, post_high] or nil
  :display_cmd,       # primary display command byte
  :display_cmd_2,     # secondary display command byte or nil
  :sleep_cmd,         # sleep command byte
  :sleep_data,        # sleep data byte
  :capabilities,      # Set of symbols: :partial, :fast, :grayscale, :dual_buf
  :init_sequence,     # Array of integers (encoded bytes)
  :init_fast_sequence,    # Array or nil
  :init_partial_sequence, # Array or nil
  :tier2_reason,      # String or nil
  :warnings,          # Array of warning strings
  keyword_init: true
) do
  # Returns the C identifier name (lowercase, underscored).
  # @return [String] C-safe identifier
  def c_name
    model_name.downcase
  end

  # Returns the C pixel format enum name.
  # @return [String]
  def c_pixel_format
    case pixel_format
    when :mono   then "PIXEL_FORMAT_MONO"
    when :gray4  then "PIXEL_FORMAT_GRAY4"
    when :color4 then "PIXEL_FORMAT_COLOR4"
    when :color7 then "PIXEL_FORMAT_COLOR7"
    else "PIXEL_FORMAT_MONO"
    end
  end

  # Returns the C busy polarity enum name.
  # @return [String]
  def c_busy_polarity
    case busy_polarity
    when :active_high then "BUSY_ACTIVE_HIGH"
    when :active_low  then "BUSY_ACTIVE_LOW"
    else "BUSY_ACTIVE_HIGH"
    end
  end

  # Returns the C capabilities expression.
  # @return [String]
  def c_capabilities
    caps = []
    caps << "EPD_CAP_PARTIAL"   if capabilities.include?(:partial)
    caps << "EPD_CAP_FAST"      if capabilities.include?(:fast)
    caps << "EPD_CAP_GRAYSCALE" if capabilities.include?(:grayscale)
    caps << "EPD_CAP_DUAL_BUF"  if capabilities.include?(:dual_buf)
    caps.empty? ? "0" : caps.join(" | ")
  end
end

# Parses a vendor .h file to extract dimensions and detect capabilities from function declarations.
#
# @param header_path [Pathname] path to .h file
# @return [Hash] extracted data with keys :width, :height, :capabilities, :prefix
def parse_header(header_path)
  content = header_path.read(encoding: "ASCII-8BIT").encode("UTF-8", invalid: :replace, undef: :replace)
  result = { capabilities: Set.new, width: nil, height: nil, prefix: nil }

  # Extract WIDTH and HEIGHT
  content.scan(WIDTH_HEIGHT_RE) do |name, val|
    result[:width] = val.to_i
    result[:prefix] = name
  end
  content.scan(HEIGHT_RE) do |name, val|
    result[:height] = val.to_i
    result[:prefix] ||= name
  end

  # Detect capabilities from function declarations
  result[:capabilities] << :fast      if content.match?(/Init_Fast\b/)
  result[:capabilities] << :partial   if content.match?(/Display_Partial|PartialDisplay|DisplayPartial|Part_Init/i)
  result[:capabilities] << :grayscale if content.match?(/4Gray|4grey|4GRAY/i)
  result[:capabilities] << :dual_buf  if content.match?(/Display_Base\b/)

  result
rescue StandardError => e
  warn "  [WARN] Failed to parse header #{header_path.basename}: #{e.message}"
  result
end

# Extracts reset timing from the Reset() function in a .c file.
#
# @param content [String] full C source text
# @param prefix [String] function prefix (e.g., "EPD_2in13_V4")
# @return [Array<Integer>, nil] [pre_high_ms, low_ms, post_high_ms] or nil
def extract_reset_timing(content, prefix)
  # Find the Reset function body
  reset_fn = extract_function_body(content, /#{Regexp.escape(prefix)}[_]?Reset|EPD_Reset/)
  return nil unless reset_fn

  delays = reset_fn.scan(RESET_DELAY_RE).flatten.map(&:to_i)

  # Standard pattern: HIGH, delay, LOW, delay, HIGH, delay -> 3 delays
  # EPD_4in2 has a non-standard triple-reset pattern
  if delays.length >= 3
    # Find the pattern: write HIGH, delay, write LOW, delay, write HIGH, delay
    lines = reset_fn.lines
    timings = []
    lines.each do |line|
      if line.match?(RESET_DELAY_RE)
        timings << line.match(RESET_DELAY_RE)[1].to_i
      end
    end
    return timings[0..2] if timings.length >= 3

    delays[0..2]
  elsif delays.length == 2
    # Some drivers have only 2 delays (LOW, delay, HIGH, delay)
    [0, delays[0], delays[1]]
  else
    nil
  end
end

# Extracts the body of a C function matching the given pattern.
#
# @param content [String] full C source
# @param name_pattern [Regexp] function name pattern to match
# @return [String, nil] function body text or nil
def extract_function_body(content, name_pattern)
  # Match function definition: return_type FUNCTION_NAME(args) { ... }
  pattern = /(?:static\s+)?(?:void|UBYTE|int)\s+(#{name_pattern.source})\s*\([^)]*\)\s*\{/m
  match = content.match(pattern)
  return nil unless match

  start_idx = match.end(0)
  brace_depth = 1
  idx = start_idx

  while idx < content.length && brace_depth > 0
    case content[idx]
    when "{" then brace_depth += 1
    when "}" then brace_depth -= 1
    end
    idx += 1
  end

  content[start_idx...idx - 1]
end

# Extracts busy polarity from the ReadBusy/WaitUntilIdle function.
#
# @param content [String] full C source
# @param prefix [String] function prefix
# @return [Symbol] :active_high, :active_low, :dual, or :unknown
def extract_busy_polarity(content, prefix)
  # Check for dual busy (both BusyHigh and BusyLow functions)
  has_busy_high = content.match?(/#{Regexp.escape(prefix)}[_]?BusyHigh|BusyHigh/)
  has_busy_low  = content.match?(/#{Regexp.escape(prefix)}[_]?BusyLow|BusyLow/)
  return :dual if has_busy_high && has_busy_low

  # Find the ReadBusy / WaitUntilIdle function
  busy_fn = extract_function_body(content, /#{Regexp.escape(prefix)}[_]?ReadBusy|#{Regexp.escape(prefix)}[_]?WaitUntilIdle|EPD_WaitUntilIdle|#{Regexp.escape(prefix)}[_]?ReadBusy_HIGH/)

  return :unknown unless busy_fn

  # Check for the comparison pattern
  # ==0 means "break/done when LOW" → busy when HIGH → BUSY_ACTIVE_HIGH
  # ==1 means "break/done when HIGH" → busy when LOW → BUSY_ACTIVE_LOW
  # !(busy & 0x01) means reading and inverting → ACTIVE_LOW (done when HIGH)
  # while(!(DEV_Digital_Read...)) means "loop while LOW" → ACTIVE_LOW (busy when LOW)
  if busy_fn.match?(/DEV_Digital_Read\s*\(\s*EPD_BUSY_PIN\s*\)\s*==\s*0/)
    :active_high  # breaks when pin reads 0, so busy while HIGH
  elsif busy_fn.match?(/DEV_Digital_Read\s*\(\s*EPD_BUSY_PIN\s*\)\s*==\s*1/)
    :active_low   # breaks when pin reads 1, so busy while LOW
  elsif busy_fn.match?(/!\s*\(\s*DEV_Digital_Read\s*\(\s*EPD_BUSY_PIN\s*\)\s*\)/) ||
        busy_fn.match?(/while\s*\(\s*!\s*\(\s*DEV_Digital_Read/)
    :active_low   # loops while !read, so exits when HIGH → busy when LOW
  elsif busy_fn.match?(/while\s*\(\s*DEV_Digital_Read/) ||
        busy_fn.match?(/while\s*\(\s*busy\s*\)/) # busy = DEV_Digital_Read; while(busy)
    :active_high  # loops while read is truthy, so busy when HIGH
  elsif busy_fn.match?(/!\s*\(\s*busy\s*&\s*0x01\s*\)/)
    :active_low   # EPD_1in02d pattern: invert → busy when LOW
  else
    :unknown
  end
end

# Extracts sleep command and data from the Sleep() function.
#
# @param content [String] full C source
# @param prefix [String] function prefix
# @return [Array(Integer, Integer)] [cmd, data] or [0x10, 0x01] as default
def extract_sleep_command(content, prefix)
  sleep_fn = extract_function_body(content, /#{Regexp.escape(prefix)}[_]?Sleep/)
  return [0x10, 0x01] unless sleep_fn

  commands = sleep_fn.scan(SEND_COMMAND_RE).flatten.map { |v| Integer(v) }
  datas = sleep_fn.scan(SEND_DATA_RE).flatten.map { |v| Integer(v) }

  # The deep sleep command is typically the last command+data pair
  # For UC8179 family: 0x07 + 0xA5
  # For SSD1680 family: 0x10 + 0x01
  # For EPD_3in7: 0x10 + 0x03
  if commands.include?(0x07) && datas.include?(0xA5)
    [0x07, 0xA5]
  elsif commands.include?(0x10)
    idx = commands.index(0x10)
    data_val = idx && idx < datas.length ? datas[idx] : 0x01
    [0x10, data_val]
  elsif !commands.empty? && !datas.empty?
    # Last command+data pair
    [commands.last, datas.last]
  else
    [0x10, 0x01]
  end
end

# Extracts the primary and secondary display command bytes from Display(), Display_Base(),
# and Clear() functions.
#
# @param content [String] full C source
# @param prefix [String] function prefix
# @return [Array(Integer, Integer)] [primary_cmd, secondary_cmd] where secondary may be 0
def extract_display_commands(content, prefix)
  primary = nil
  secondary = nil

  # Check Display_Base first (dual-buffer sends both primary and secondary)
  base_fn = extract_function_body(content, /#{Regexp.escape(prefix)}[_]?Display_Base\b/)
  if base_fn
    base_cmds = base_fn.scan(SEND_COMMAND_RE).flatten.map { |v| Integer(v) }
    data_cmds = base_cmds.select { |c| [0x10, 0x13, 0x24, 0x26].include?(c) }
    if data_cmds.length >= 2
      primary = data_cmds[0]
      secondary = data_cmds[1]
    end
  end

  # Check Display function for primary command if not yet found
  unless primary
    display_fn = extract_function_body(content, /#{Regexp.escape(prefix)}[_]?Display[^_P]|#{Regexp.escape(prefix)}[_]?Display\b/)
    if display_fn
      cmds = display_fn.scan(SEND_COMMAND_RE).flatten.map { |v| Integer(v) }
      data_cmds = cmds.select { |c| [0x10, 0x13, 0x24, 0x26].include?(c) }
      primary = data_cmds[0] if data_cmds.length >= 1
      secondary ||= data_cmds[1] if data_cmds.length >= 2
    end
  end

  # Fallback to Clear function
  unless primary
    clear_fn = extract_function_body(content, /#{Regexp.escape(prefix)}[_]?Clear\b/)
    if clear_fn
      cmds = clear_fn.scan(SEND_COMMAND_RE).flatten.map { |v| Integer(v) }
      data_cmds = cmds.select { |c| [0x10, 0x13, 0x24, 0x26].include?(c) }
      primary = data_cmds[0] if data_cmds.length >= 1
      secondary ||= data_cmds[1] if data_cmds.length >= 2
    end
  end

  [primary || 0x24, secondary || 0x00]
end

# Parses an Init function body and encodes the command sequence as a flat byte array.
#
# @param content [String] full C source
# @param prefix [String] function prefix
# @param func_pattern [Regexp] function name pattern
# @param header_data [Hash] header data with :width, :height, :prefix
# @return [Array<Integer>, nil] encoded init sequence or nil
def extract_init_sequence(content, prefix, func_pattern, header_data)
  init_fn = extract_function_body(content, func_pattern)
  return nil unless init_fn

  sequence = []
  current_cmd = nil
  current_data = []
  all_lines = init_fn.lines
  total_lines = all_lines.length

  # Process line by line
  all_lines.each_with_index do |line, line_idx|
    remaining_lines = all_lines[line_idx + 1..]
    stripped = line.strip

    # Skip comments, blank lines, variable declarations
    next if stripped.empty?
    next if stripped.start_with?("//")
    next if stripped.match?(/^\s*(UWORD|UBYTE|unsigned|static|UDOUBLE|int)\b/)
    next if stripped.match?(/^\s*Debug\b/)

    # Check for function calls in the line
    if stripped.match?(/Reset\s*\(\s*\)/)
      flush_command(sequence, current_cmd, current_data)
      current_cmd = nil
      current_data = []
      sequence << SEQ_HW_RESET
    elsif stripped.match?(SET_WINDOWS_RE)
      flush_command(sequence, current_cmd, current_data)
      current_cmd = nil
      current_data = []
      sequence << SEQ_SET_WINDOW
    elsif stripped.match?(SET_CURSOR_RE)
      flush_command(sequence, current_cmd, current_data)
      current_cmd = nil
      current_data = []
      sequence << SEQ_SET_CURSOR
    elsif stripped.match?(READ_BUSY_RE) && !stripped.match?(SEND_COMMAND_RE)
      flush_command(sequence, current_cmd, current_data)
      current_cmd = nil
      current_data = []
      sequence << SEQ_WAIT_BUSY
    elsif (match = stripped.match(SEND_COMMAND_RE))
      flush_command(sequence, current_cmd, current_data)
      cmd_byte = Integer(match[1])

      # Software reset command 0x12 on SSD1680 family (small displays)
      # Only treat as SW_RESET if it's followed by ReadBusy, not by data or used for DISPLAY_REFRESH
      if cmd_byte == 0x12 && is_sw_reset_context?(remaining_lines, line_idx)
        current_cmd = nil
        current_data = []
        sequence << SEQ_SW_RESET
      else
        current_cmd = cmd_byte
        current_data = []
      end
    elsif (match = stripped.match(SEND_DATA_RE))
      if current_cmd
        current_data << Integer(match[1])
      end
    elsif (match = stripped.match(DELAY_RE))
      flush_command(sequence, current_cmd, current_data)
      current_cmd = nil
      current_data = []
      delay_val = match[1].to_i
      # Only encode delays > 0 that appear mid-init (not in Reset)
      if delay_val > 0 && delay_val <= 255
        sequence << SEQ_DELAY_MS
        sequence << delay_val
      elsif delay_val > 255
        # Split large delays
        (delay_val / 255).times { sequence.push(SEQ_DELAY_MS, 255) }
        remainder = delay_val % 255
        sequence.push(SEQ_DELAY_MS, remainder) if remainder > 0
      end
    elsif stripped.match?(/SetFulltReg|SetPartReg|SetLut|Partial_SetLut|4Gray_lut|Load_LUT|Lut\b/i)
      # LUT loading function call - mark as tier2 indicator
      flush_command(sequence, current_cmd, current_data)
      current_cmd = nil
      current_data = []
      # We skip encoding LUT calls; tier2 override will handle these
    elsif stripped.match?(/SetWindows|SetWindow/)
      # SetWindows with non-zero args (partial update window) - encode as is
      flush_command(sequence, current_cmd, current_data)
      current_cmd = nil
      current_data = []
      sequence << SEQ_SET_WINDOW
    end
  end

  # Flush final command
  flush_command(sequence, current_cmd, current_data)
  sequence << SEQ_END

  sequence.empty? || sequence == [SEQ_END] ? nil : sequence
end

# Flushes a pending command and its data bytes into the sequence array.
#
# @param sequence [Array<Integer>] sequence being built
# @param cmd [Integer, nil] command byte
# @param data [Array<Integer>] data bytes
# @return [void]
def flush_command(sequence, cmd, data)
  return unless cmd

  sequence << cmd
  sequence << data.length
  sequence.concat(data)
end

# Determines whether a 0x12 command in context is a software reset (SWRESET)
# versus a DISPLAY_REFRESH command. SWRESET is typically followed by ReadBusy
# with no SendData before the next SendCommand. DISPLAY_REFRESH is followed
# by for-loops that send image data.
#
# @param remaining_lines [Array<String>] lines after the current one
# @param current_idx [Integer] current line index (unused, kept for API clarity)
# @return [Boolean]
def is_sw_reset_context?(remaining_lines, current_idx)
  return true if remaining_lines.nil? || remaining_lines.empty?

  # Check lines until we find the next SendCommand, SendData, or for-loop
  remaining_lines.each do |line|
    stripped = line.strip
    next if stripped.empty? || stripped.start_with?("//")

    # If we hit ReadBusy before any SendData/SendCommand/loop, it's SWRESET
    return true if stripped.match?(/ReadBusy|WaitUntilIdle|BusyHigh/)

    # If we hit SendData or a for-loop first, it's DISPLAY_REFRESH
    return false if stripped.match?(/SendData|for\s*\(/)

    # If we hit another SendCommand, the 0x12 had no data -> likely SWRESET
    return true if stripped.match?(/SendCommand/)

    # If we hit a DEV_Delay_ms, keep looking (delays can follow SWRESET)
    next if stripped.match?(/DEV_Delay_ms/)
  end

  # If we reach the end without finding anything decisive, assume SWRESET
  true
end

# Detects the pixel format for a model based on its name and source contents.
#
# @param model_name [String] e.g., "EPD_2in13b_V4"
# @param h_content [String] header file content
# @return [Symbol] :mono, :color4, or :color7
def detect_pixel_format(model_name, h_content)
  base = model_name.sub(/^EPD_/, "")

  # 7-color ACeP displays
  return :color7 if base.match?(COLOR7_PATTERN)

  # Gate-driven color displays (g suffix)
  return :color4 if base.match?(GATE_COLOR_PATTERN)

  # Tri-color displays (b, bc suffixes)
  return :color4 if base.match?(COLOR4_PATTERNS)

  # Check header for color index definitions (7-color marker)
  return :color7 if h_content.match?(/BLACK\s+0x0.*GREEN\s+0x2.*RED\s+0x4/m)

  :mono
end

# Detects whether embedded LUT tables exceed a threshold.
#
# @param c_content [String] C source content
# @return [Boolean]
def has_large_luts?(c_content)
  # Match C array initializers like: unsigned char LUT[] = { ... };
  # or UBYTE lut[] = { ... };
  lut_sizes = c_content.scan(/(?:unsigned\s+char|UBYTE|const\s+unsigned\s+char|static\s+const\s+unsigned\s+char|static\s+const\s+UBYTE)\s+\w*[Ll][Uu][Tt]\w*\s*\[\s*(\d*)\s*\]/).flatten
  lut_sizes.any? { |s| s.to_i > 50 }
rescue StandardError
  false
end

# Generates the C array initializer for an init sequence.
#
# @param sequence [Array<Integer>] encoded byte sequence
# @param indent [String] indentation prefix
# @return [String] C array content
def format_init_sequence(sequence, indent = "    ")
  return "" if sequence.nil? || sequence.empty?

  lines = []
  i = 0

  while i < sequence.length
    byte = sequence[i]

    if SENTINEL_NAMES.key?(byte)
      name = SENTINEL_NAMES[byte]
      if byte == SEQ_DELAY_MS && i + 1 < sequence.length
        lines << "#{indent}#{name}, #{sequence[i + 1]},"
        i += 2
      else
        lines << "#{indent}#{name},"
        i += 1
      end
    else
      # Command byte followed by count and data
      cmd = byte
      if i + 1 < sequence.length
        count = sequence[i + 1]
        if count >= 0 && count < 0xF0 # valid count (not a sentinel)
          data_bytes = sequence[i + 2, count] || []
          if data_bytes.empty?
            lines << "#{indent}0x%02X, 0," % cmd
          else
            data_str = data_bytes.map { |b| "0x%02X" % b }.join(", ")
            lines << "#{indent}0x%02X, %d, %s," % [cmd, count, data_str]
          end
          i += 2 + count
        else
          # Count looks like a sentinel - just emit command with 0 data
          lines << "#{indent}0x%02X, 0," % cmd
          i += 1
        end
      else
        lines << "#{indent}0x%02X, 0," % cmd
        i += 1
      end
    end
  end

  lines.join("\n")
end

# Top-level extraction: processes a single model's .h and .c files.
#
# @param h_path [Pathname] header file path
# @param c_path [Pathname] source file path
# @return [DriverConfig]
def extract_model(h_path, c_path)
  model_name = h_path.basename(".h").to_s
  h_content = h_path.read(encoding: "ASCII-8BIT").encode("UTF-8", invalid: :replace, undef: :replace)
  c_content = c_path.read(encoding: "ASCII-8BIT").encode("UTF-8", invalid: :replace, undef: :replace)
  warnings = []

  # Parse header
  header_data = parse_header(h_path)

  unless header_data[:width] && header_data[:height]
    warnings << "Could not extract WIDTH/HEIGHT"
  end

  prefix = header_data[:prefix] || model_name.upcase.gsub(/[^A-Z0-9]/, "_")

  # Extract C-level data
  reset_ms = extract_reset_timing(c_content, prefix)
  warnings << "Could not extract reset timing" unless reset_ms

  busy_pol = extract_busy_polarity(c_content, prefix)
  warnings << "Could not determine busy polarity" if busy_pol == :unknown

  display_cmds = extract_display_commands(c_content, prefix)
  sleep_cmd, sleep_data = extract_sleep_command(c_content, prefix)

  # Detect capabilities from header
  capabilities = header_data[:capabilities]

  # Detect pixel format
  pixel_format = detect_pixel_format(model_name, h_content)

  # Extract init sequences - find the main Init function
  # Try multiple patterns: EPD_XXX_Init, EPD_XXX_Init_Fast, etc.
  init_patterns = [
    /#{Regexp.escape(prefix)}_Init\b(?!_Fast|_Part|_Partial|_4Gray|_4GRAY|_GUI)/,
    /#{Regexp.escape(prefix)}[_]?Init\b(?!_Fast|_Part|_Partial|_4Gray|_4GRAY|_GUI)/
  ]

  # For models like EPD_3in7 that have 1Gray_Init / 4Gray_Init instead of plain Init
  if model_name == "EPD_3in7"
    init_patterns.unshift(/EPD_3IN7_1Gray_Init/)
  end

  init_seq = nil
  init_patterns.each do |pattern|
    init_seq = extract_init_sequence(c_content, prefix, pattern, header_data)
    break if init_seq
  end
  warnings << "Could not extract init sequence" unless init_seq

  # Fast init
  fast_pattern = /#{Regexp.escape(prefix)}[_]?Init_Fast/
  init_fast_seq = extract_init_sequence(c_content, prefix, fast_pattern, header_data)

  # Partial init (various naming conventions)
  partial_patterns = [
    /#{Regexp.escape(prefix)}[_]?Init_Partial/,
    /#{Regexp.escape(prefix)}[_]?Part_Init/,
    /#{Regexp.escape(prefix)}[_]?Init_Part/
  ]
  init_partial_seq = nil
  partial_patterns.each do |pattern|
    init_partial_seq = extract_init_sequence(c_content, prefix, pattern, header_data)
    break if init_partial_seq
  end

  # Tier 2 detection
  tier2_reason = TIER2_MODELS[model_name]
  tier2_reason ||= "Large embedded LUT tables" if has_large_luts?(c_content)

  # Check for custom TurnOnDisplay that's unusual
  turn_on = extract_function_body(c_content, /#{Regexp.escape(prefix)}[_]?TurnOnDisplay\b/)
  if turn_on
    cmds_in_turn_on = turn_on.scan(SEND_COMMAND_RE).flatten.map { |v| Integer(v) }
    # Standard is: 0x22 + data + 0x20 + busy, or just 0x12 + busy
    # Flag unusual ones
    unless cmds_in_turn_on.empty? ||
           cmds_in_turn_on == [0x22, 0x20] ||
           cmds_in_turn_on == [0x12] ||
           cmds_in_turn_on == [0x20]
      tier2_reason ||= "Non-standard TurnOnDisplay sequence"
    end
  end

  DriverConfig.new(
    model_name:,
    width: header_data[:width] || 0,
    height: header_data[:height] || 0,
    pixel_format:,
    busy_polarity: busy_pol == :dual ? :active_low : busy_pol,
    reset_ms: reset_ms || [20, 2, 20],
    display_cmd: display_cmds[0],
    display_cmd_2: display_cmds[1],
    sleep_cmd:,
    sleep_data:,
    capabilities:,
    init_sequence: init_seq,
    init_fast_sequence: init_fast_seq,
    init_partial_sequence: init_partial_seq,
    tier2_reason:,
    warnings:
  )
end

# Generates the complete C header file content from extracted configs.
#
# @param configs [Array<DriverConfig>] all extracted model configurations
# @return [String] complete C header file content
def generate_header(configs)
  lines = []
  lines << "/* AUTO-GENERATED by script/extract_driver_configs.rb -- DO NOT EDIT */"
  lines << "/* Models: #{configs.length} total, #{configs.count { |c| c.tier2_reason }} tier2 */"
  lines << ""
  lines << "#ifndef DRIVER_CONFIGS_GENERATED_H"
  lines << "#define DRIVER_CONFIGS_GENERATED_H"
  lines << ""
  lines << '#include "chroma_wave.h"'
  lines << '#include "driver_registry.h"'
  lines << ""

  # Emit init sequence arrays
  configs.each do |config|
    tier2_comment = config.tier2_reason ? " /* TIER2: #{config.tier2_reason} */" : ""

    if config.init_sequence
      lines << "static const uint8_t #{config.c_name}_init[] = {#{tier2_comment}"
      lines << format_init_sequence(config.init_sequence)
      lines << "};"
      lines << ""
    end

    if config.init_fast_sequence
      lines << "static const uint8_t #{config.c_name}_init_fast[] = {"
      lines << format_init_sequence(config.init_fast_sequence)
      lines << "};"
      lines << ""
    end

    if config.init_partial_sequence
      lines << "static const uint8_t #{config.c_name}_init_partial[] = {"
      lines << format_init_sequence(config.init_partial_sequence)
      lines << "};"
      lines << ""
    end
  end

  # Emit model config table
  lines << "/* Model configuration table */"
  lines << "static const epd_model_config_t epd_model_configs[] = {"

  configs.each_with_index do |config, idx|
    tier2_comment = config.tier2_reason ? " /* TIER2: #{config.tier2_reason} */" : ""
    reset = config.reset_ms

    lines << "    {#{tier2_comment}"
    lines << "        .name = \"#{config.c_name}\","
    lines << "        .width = #{config.width},"
    lines << "        .height = #{config.height},"
    lines << "        .pixel_format = #{config.c_pixel_format},"
    lines << "        .busy_polarity = #{config.c_busy_polarity},"
    lines << "        .reset_ms = {#{reset[0]}, #{reset[1]}, #{reset[2]}},"
    lines << "        .display_cmd = 0x%02X," % config.display_cmd
    lines << "        .display_cmd_2 = 0x%02X," % (config.display_cmd_2 || 0)
    lines << emit_sequence_field(config, :init_sequence, "init")
    lines << "        .capabilities = #{config.c_capabilities},"
    lines << emit_sequence_field(config, :init_fast_sequence, "init_fast")
    lines << emit_sequence_field(config, :init_partial_sequence, "init_partial")
    lines << "        .sleep_cmd = 0x%02X," % config.sleep_cmd
    lines << "        .sleep_data = 0x%02X" % config.sleep_data
    lines << "    }#{idx < configs.length - 1 ? ',' : ''}"
  end

  lines << "};"
  lines << ""
  lines << "#define EPD_MODEL_COUNT (sizeof(epd_model_configs) / sizeof(epd_model_configs[0]))"
  lines << ""
  lines << "#endif /* DRIVER_CONFIGS_GENERATED_H */"
  lines << ""

  lines.join("\n")
end

# Emits the .init_sequence / .init_fast_sequence / .init_partial_sequence field pair.
#
# @param config [DriverConfig] the model config
# @param field [Symbol] one of :init_sequence, :init_fast_sequence, :init_partial_sequence
# @param prefix [String] C field name prefix (e.g., "init", "init_fast", "init_partial")
# @return [String] two lines for .xxx_sequence and .xxx_sequence_len
def emit_sequence_field(config, field, prefix)
  seq = config.send(field)
  if seq
    arr_name = "#{config.c_name}_#{prefix}"
    "        .#{prefix}_sequence = #{arr_name},\n" \
    "        .#{prefix}_sequence_len = sizeof(#{arr_name}),"
  else
    "        .#{prefix}_sequence = NULL,\n" \
    "        .#{prefix}_sequence_len = 0,"
  end
end

# Main execution
def main
  puts "Extracting driver configs from #{VENDOR_DIR}"
  puts "Output: #{OUTPUT_PATH}"
  puts

  # Discover all .h files
  headers = VENDOR_DIR.glob("EPD_*.h").sort_by(&:basename)
  puts "Found #{headers.length} header files"
  puts

  configs = []
  skipped = []

  headers.each do |h_path|
    model_name = h_path.basename(".h").to_s
    c_path = h_path.sub_ext(".c")

    unless c_path.exist?
      puts "  [SKIP] #{model_name}: no matching .c file"
      skipped << model_name
      next
    end

    print "  #{model_name}... "
    config = extract_model(h_path, c_path)

    if config.width.zero? || config.height.zero?
      puts "SKIP (no dimensions)"
      skipped << model_name
      next
    end

    configs << config

    status_parts = []
    status_parts << "#{config.width}x#{config.height}"
    status_parts << config.pixel_format.to_s
    status_parts << "busy:#{config.busy_polarity}"
    status_parts << "caps:[#{config.capabilities.to_a.join(',')}]"
    status_parts << "TIER2" if config.tier2_reason
    status_parts << "init:#{config.init_sequence&.length || 0}B"
    status_parts << "fast:#{config.init_fast_sequence&.length || 0}B" if config.init_fast_sequence
    status_parts << "partial:#{config.init_partial_sequence&.length || 0}B" if config.init_partial_sequence

    warns = config.warnings.empty? ? "" : " [WARN: #{config.warnings.join('; ')}]"
    puts status_parts.join(" ") + warns
  end

  puts
  puts "=" * 70
  puts "SUMMARY"
  puts "=" * 70
  puts "Total models extracted: #{configs.length}"
  puts "Skipped: #{skipped.length} (#{skipped.join(', ')})" unless skipped.empty?
  puts "Tier 2 models: #{configs.count { |c| c.tier2_reason }}"
  puts

  tier2 = configs.select(&:tier2_reason)
  unless tier2.empty?
    puts "Tier 2 models requiring manual overrides:"
    tier2.each { |c| puts "  - #{c.model_name}: #{c.tier2_reason}" }
    puts
  end

  with_warnings = configs.select { |c| !c.warnings.empty? }
  unless with_warnings.empty?
    puts "Models with warnings:"
    with_warnings.each { |c| puts "  - #{c.model_name}: #{c.warnings.join('; ')}" }
    puts
  end

  # Generate output
  header_content = generate_header(configs)
  OUTPUT_PATH.dirname.mkpath
  OUTPUT_PATH.write(header_content)
  puts "Generated #{OUTPUT_PATH} (#{header_content.length} bytes, #{configs.length} models)"
end

main
