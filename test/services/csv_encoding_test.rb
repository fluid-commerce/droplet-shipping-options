require "test_helper"
require "csv"

class CsvEncodingTest < ActiveSupport::TestCase
  BOM = "\xEF\xBB\xBF".b.freeze

  test "returns valid UTF-8 content byte for byte unchanged" do
    utf8_bytes = "Caf\xC3\xA9 Express,Se\xC3\xB1or Freight,\xE2\x82\xAC9.99".b

    normalized = CsvEncoding.to_utf8(utf8_bytes)

    assert_equal utf8_bytes, normalized.b
    assert_equal "Café Express,Señor Freight,€9.99", normalized
    assert_equal Encoding::UTF_8, normalized.encoding
    assert_predicate normalized, :valid_encoding?
  end

  test "transcodes genuine Windows-1252 content instead of dropping its accents" do
    normalized = CsvEncoding.to_utf8("Se\xF1or Freight".b)

    assert_equal "Señor Freight", normalized
  end

  test "transcodes Windows-1252 content that uses several high bytes" do
    normalized = CsvEncoding.to_utf8("Se\xF1or M\xFCller caf\xE9 \x93quoted\x94".b)

    assert_equal "Señor Müller café “quoted”", normalized
  end

  test "keeps intact multi-byte characters when UTF-8 content carries a truncated sequence" do
    # The regression this guards: an all-or-nothing valid_encoding? check lets a
    # single truncated sequence re-read the whole file as Windows-1252, which
    # turns every legitimate "é" into "Ã©".
    normalized = CsvEncoding.to_utf8("Caf\xC3\xA9 Express".b + "\xC3".b)

    assert_equal "Café Express�", normalized
    assert_not_includes normalized, "Ã", "the intact UTF-8 body must not be re-read as Windows-1252"
  end

  test "keeps intact multi-byte characters when a bad byte sits in the middle" do
    normalized = CsvEncoding.to_utf8("Caf\xC3\xA9,\xC3,Se\xC3\xB1or,\xE2\x82\xAC5".b)

    assert_equal "Café,�,Señor,€5", normalized
  end

  test "reads content as Windows-1252 when damaged sequences outnumber intact ones" do
    # One accidental 0xC3 0xA9 pair inside an otherwise Windows-1252 file must not
    # flip the whole file to UTF-8 and scrub away the three real accented letters.
    normalized = CsvEncoding.to_utf8("Se\xF1or M\xFCller caf\xE9 \xC3\xA9".b)

    assert_equal "Señor Müller café Ã©", normalized
  end

  test "makes the reported Sentry bytes parseable instead of raising" do
    sentry_bytes = "Expr\xC2ess Shipping,US,CA,0,5,9.99,5.00".b

    assert_raises(CSV::InvalidEncodingError) do
      CSV.parse(sentry_bytes.dup.force_encoding(Encoding::UTF_8))
    end

    normalized = CsvEncoding.to_utf8(sentry_bytes)

    assert_equal "ExprÂess Shipping,US,CA,0,5,9.99,5.00", normalized
    assert_nothing_raised { CSV.parse(normalized) }
  end

  test "strips the UTF-8 BOM whatever the rest of the content turns out to be" do
    assert_equal "Café", CsvEncoding.to_utf8(BOM + "Caf\xC3\xA9".b)
    assert_equal "Señor", CsvEncoding.to_utf8(BOM + "Se\xF1or".b)
    assert_equal "Café�", CsvEncoding.to_utf8(BOM + "Caf\xC3\xA9".b + "\xC3".b)
    assert_equal "ExprÂess", CsvEncoding.to_utf8(BOM + "Expr\xC2ess".b)
    assert_equal "plain", CsvEncoding.to_utf8(BOM + "plain".b)
    assert_equal "", CsvEncoding.to_utf8(BOM)
  end

  test "replaces the five Windows-1252 undefined bytes rather than raising" do
    assert_nothing_raised do
      assert_equal "A�����B", CsvEncoding.to_utf8("A\x81\x8D\x8F\x90\x9DB".b)
    end

    assert_equal "Señor�Freight", CsvEncoding.to_utf8("Se\xF1or\x81Freight".b)
  end

  test "is idempotent so a second pass never re-damages content" do
    once = CsvEncoding.to_utf8("Se\xF1or\x81 Caf\xC3\xA9".b)

    assert_equal once, CsvEncoding.to_utf8(once)
  end

  test "handles empty and nil content" do
    assert_equal "", CsvEncoding.to_utf8("")
    assert_nil CsvEncoding.to_utf8(nil)
  end
end
