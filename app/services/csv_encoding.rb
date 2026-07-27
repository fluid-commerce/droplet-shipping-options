module CsvEncoding
  # Internal: Byte-order mark that Excel and friends prepend to UTF-8 exports.
  BOM = "\xEF\xBB\xBF".b.freeze

  # Internal: Stands in for bytes that no reading can make sense of. Windows-1252
  # leaves five bytes undefined (0x81 0x8D 0x8F 0x90 0x9D), so even the
  # Windows-1252 reading can produce these.
  REPLACEMENT_CHARACTER = "�".freeze

  # Public: Normalizes the raw bytes of an uploaded CSV into valid UTF-8.
  #
  # Uploaded CSVs arrive as raw bytes that are usually UTF-8 (often with a BOM,
  # which is what Excel writes) but are sometimes Windows-1252/Latin-1 instead,
  # and are occasionally UTF-8 that picked up a handful of corrupt bytes along
  # the way (a truncated write, a byte-sliced concatenation, a bad export).
  #
  # Telling "Windows-1252 file" apart from "UTF-8 file with a few bad bytes"
  # matters, because the two need opposite treatment and guessing wrong destroys
  # data either way:
  #
  #   * Transcoding a corrupt UTF-8 file from Windows-1252 mojibakes every
  #     legitimate multi-byte character in it ("Café" becomes "CafÃ©").
  #   * Scrubbing a genuine Windows-1252 file silently deletes every accented
  #     character in it ("Señor" becomes "Seor").
  #
  # The signal used here is that valid multi-byte UTF-8 sequences essentially
  # never occur by accident in Windows-1252 text: an accented Windows-1252
  # character is almost always followed by an ASCII letter or punctuation mark,
  # and ASCII bytes are never UTF-8 continuation bytes. So content that decodes
  # to intact multi-byte characters is UTF-8, and the bytes that do not decode
  # are damage to be scrubbed.
  #
  # Rather than treating a single intact sequence as proof, the two readings are
  # weighed against each other and the one that loses fewer characters wins.
  # That keeps one accidental byte pair in a Windows-1252 file from flipping the
  # whole file to the wrong interpretation.
  #
  # bytes - The String read from the upload. May carry any encoding tag; only the
  #         bytes are used. A leading UTF-8 BOM is removed before anything else
  #         looks at the content.
  #
  # Examples
  #
  #   CsvEncoding.to_utf8("Se\xF1or Freight".b)
  #   # => "Señor Freight"
  #
  #   CsvEncoding.to_utf8("Caf\xC3\xA9 Express".b + "\xC3".b)
  #   # => "Café Express�"
  #
  # Returns a String tagged UTF-8 that is guaranteed to satisfy #valid_encoding?.
  #   Content that is already valid UTF-8 comes back byte for byte unchanged,
  #   apart from the stripped BOM.
  def self.to_utf8(bytes)
    return bytes if bytes.nil?

    content = bytes.to_s.dup.force_encoding(Encoding::BINARY).delete_prefix(BOM)
    content.force_encoding(Encoding::UTF_8)
    return content if content.valid_encoding?

    damaged_sequences = 0
    scrubbed = content.scrub { damaged_sequences += 1; REPLACEMENT_CHARACTER }
    intact_multibyte = multibyte_character_count(scrubbed) - damaged_sequences

    if intact_multibyte.positive? && intact_multibyte >= damaged_sequences
      scrubbed
    else
      content.encode(Encoding::UTF_8, Encoding::WINDOWS_1252, invalid: :replace, undef: :replace)
    end
  end

  # Internal: Counts the characters in a valid UTF-8 String that occupy more than
  # one byte.
  #
  # utf8_content - A String tagged UTF-8 with no invalid byte sequences.
  #
  # Returns an Integer.
  def self.multibyte_character_count(utf8_content)
    utf8_content.each_char.count { |character| character.bytesize > 1 }
  end
  private_class_method :multibyte_character_count
end
