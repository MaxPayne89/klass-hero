defmodule KlassHero.ProgramCatalog.Adapters.Driven.Persistence.Queries.CursorCodecTest do
  use ExUnit.Case, async: true

  alias KlassHero.ProgramCatalog.Adapters.Driven.Persistence.Queries.CursorCodec

  @valid_uuid "550e8400-e29b-41d4-a716-446655440000"

  @sample_datetime ~U[2026-05-15 10:30:00.123456Z]

  describe "encode/1 and decode/1 round-trip" do
    test "decode reverses encode for a well-formed record" do
      record = %{inserted_at: @sample_datetime, id: @valid_uuid}

      encoded = CursorCodec.encode(record)
      assert is_binary(encoded)

      assert {:ok, {@sample_datetime, @valid_uuid}} = CursorCodec.decode(encoded)
    end

    test "preserves microsecond precision across encode/decode" do
      dt = ~U[2026-01-01 00:00:00.999999Z]
      record = %{inserted_at: dt, id: @valid_uuid}

      assert {:ok, {decoded_dt, _}} = CursorCodec.decode(CursorCodec.encode(record))
      assert decoded_dt == dt
    end

    test "preserves UUID across encode/decode" do
      uuid = "a0eebc99-9c0b-4ef8-bb6d-6bb9bd380a11"
      record = %{inserted_at: @sample_datetime, id: uuid}

      assert {:ok, {_, decoded_uuid}} = CursorCodec.decode(CursorCodec.encode(record))
      assert decoded_uuid == uuid
    end

    test "produced cursor is a URL-safe base64 string (no padding chars)" do
      cursor = CursorCodec.encode(%{inserted_at: @sample_datetime, id: @valid_uuid})
      # URL-safe base64: only A-Z, a-z, 0-9, - and _ allowed; no +, /, or =
      assert cursor =~ ~r/^[A-Za-z0-9\-_]+$/
    end
  end

  describe "decode/1 — nil cursor" do
    test "returns {:ok, nil} for nil" do
      assert {:ok, nil} == CursorCodec.decode(nil)
    end
  end

  describe "decode/1 — invalid cursors" do
    test "returns {:error, :invalid_cursor} for empty string" do
      assert {:error, :invalid_cursor} = CursorCodec.decode("")
    end

    test "returns {:error, :invalid_cursor} for random non-base64 garbage" do
      assert {:error, :invalid_cursor} = CursorCodec.decode("not-valid-base64!!!")
    end

    test "returns {:error, :invalid_cursor} for valid base64 that is not JSON" do
      not_json = Base.url_encode64("this is not json", padding: false)
      assert {:error, :invalid_cursor} = CursorCodec.decode(not_json)
    end

    test "returns {:error, :invalid_cursor} when ts field is missing" do
      payload = Jason.encode!(%{"id" => @valid_uuid}) |> Base.url_encode64(padding: false)
      assert {:error, :invalid_cursor} = CursorCodec.decode(payload)
    end

    test "returns {:error, :invalid_cursor} when id field is missing" do
      payload =
        Jason.encode!(%{"ts" => DateTime.to_unix(@sample_datetime, :microsecond)})
        |> Base.url_encode64(padding: false)

      assert {:error, :invalid_cursor} = CursorCodec.decode(payload)
    end

    test "returns {:error, :invalid_cursor} when ts is not an integer" do
      payload =
        Jason.encode!(%{"ts" => "2026-05-15T10:30:00Z", "id" => @valid_uuid})
        |> Base.url_encode64(padding: false)

      assert {:error, :invalid_cursor} = CursorCodec.decode(payload)
    end

    test "returns {:error, :invalid_cursor} when id is not a valid UUID" do
      payload =
        Jason.encode!(%{"ts" => DateTime.to_unix(@sample_datetime, :microsecond), "id" => "not-a-uuid"})
        |> Base.url_encode64(padding: false)

      assert {:error, :invalid_cursor} = CursorCodec.decode(payload)
    end

    test "returns {:error, :invalid_cursor} for a truncated cursor" do
      full = CursorCodec.encode(%{inserted_at: @sample_datetime, id: @valid_uuid})
      truncated = String.slice(full, 0, 5)
      assert {:error, :invalid_cursor} = CursorCodec.decode(truncated)
    end
  end
end
