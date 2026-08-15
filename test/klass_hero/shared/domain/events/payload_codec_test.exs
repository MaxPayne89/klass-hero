defmodule KlassHero.Shared.Domain.Events.PayloadCodecTest do
  @moduledoc """
  The one list of what an event payload leaf may be, and how it crosses jsonb.

  Both walkers ask this module: `EventMetadata` before construction, to reject a
  payload at its source, and `EventSerializer` on the way out and back.
  Keeping that list in one place is the point — it lived in two before #1317, and
  both #1316 and this change had to edit both halves in lockstep.
  """
  use ExUnit.Case, async: true
  use ExUnitProperties

  alias KlassHero.Shared.Domain.Events.PayloadCodec

  # Every leaf a payload may carry, and the tag recording it. A nil tag means the
  # value is already a JSON scalar and needs nothing remembered.
  @encodable [
    {"a string", "Chess", "Chess", nil},
    {"an integer", 7, 7, nil},
    {"a float", 1.5, 1.5, nil},
    {"true", true, true, nil},
    {"false", false, false, nil},
    {"nil", nil, nil, nil},
    {"an atom", :direct, "direct", "atom"},
    {"a Date", ~D[2026-08-12], "2026-08-12", "date"},
    {"a Time", ~T[15:00:00], "15:00:00", "time"},
    {"a DateTime", ~U[2026-08-12 10:00:00Z], "2026-08-12T10:00:00Z", "datetime"},
    {"a NaiveDateTime", ~N[2026-08-12 10:00:00], "2026-08-12T10:00:00", "naive_datetime"},
    {"a Decimal", Decimal.new("12.50"), "12.50", "decimal"}
  ]

  # Nothing records what these were, so a consumer would receive something else.
  @rejected [
    {"a tuple", {1, 2}},
    {"a schema struct", %URI{host: "example.com"}},
    {"a function", &String.upcase/1}
  ]

  describe "encodable?/1" do
    for {label, value, _encoded, _tag} <- @encodable do
      test "accepts #{label}" do
        assert PayloadCodec.encodable?(unquote(Macro.escape(value)))
      end
    end

    for {label, value} <- @rejected do
      test "rejects #{label}" do
        refute PayloadCodec.encodable?(unquote(Macro.escape(value)))
      end
    end
  end

  describe "encode/1" do
    for {label, value, encoded, tag} <- @encodable do
      test "encodes #{label}" do
        assert PayloadCodec.encode(unquote(Macro.escape(value))) ==
                 {unquote(Macro.escape(encoded)), unquote(tag)}
      end
    end

    # nil, true and false all satisfy is_atom/1. Encoding them as "atom" would turn
    # JSON null into the string "nil" and break every `Map.get(payload, :k) || default`
    # a consumer has.
    test "leaves nil and booleans as JSON scalars rather than tagging them atoms" do
      for value <- [nil, true, false] do
        assert PayloadCodec.encode(value) == {value, nil},
               "expected #{inspect(value)} to encode as a bare JSON scalar"
      end
    end

    for {label, value} <- @rejected do
      test "raises on #{label}" do
        assert_raise ArgumentError, ~r/cannot cross the Oban jsonb boundary/, fn ->
          PayloadCodec.encode(unquote(Macro.escape(value)))
        end
      end
    end
  end

  describe "decode/2" do
    for {label, value, encoded, tag} <- @encodable do
      test "restores #{label}" do
        assert PayloadCodec.decode(unquote(Macro.escape(encoded)), unquote(tag)) ==
                 unquote(Macro.escape(value))
      end
    end

    # Args staged before a tag existed carry no tag, so the value stays as jsonb left
    # it. That is what in-flight jobs and undelivered_events rows need at deploy.
    test "leaves an untagged value alone" do
      assert PayloadCodec.decode("2026-08-12", nil) == "2026-08-12"
    end

    # A tag from a newer version. Raising here would dead-letter every job that version
    # staged the moment anything rolled back — which is exactly what the pre-#1317
    # serializer did, since its decode had a clause per known tag and no fallback.
    test "degrades an unrecognised tag to the raw scalar rather than raising" do
      assert PayloadCodec.decode("PT1H", "duration") == "PT1H"
    end
  end

  describe "round-trip" do
    property "any encodable leaf comes back as what went in" do
      check all(value <- encodable_leaf()) do
        {encoded, tag} = PayloadCodec.encode(value)

        assert PayloadCodec.decode(encoded, tag) === value
      end
    end

    property "an encoded leaf is always a JSON scalar" do
      check all(value <- encodable_leaf()) do
        {encoded, _tag} = PayloadCodec.encode(value)

        assert is_binary(encoded) or is_number(encoded) or is_boolean(encoded) or is_nil(encoded)
      end
    end
  end

  # Atoms must survive String.to_existing_atom/1, so the generator draws from ones
  # this module has already created.
  @atoms [:direct, :program_broadcast, :text, :system, :pending, :confirmed]

  defp encodable_leaf do
    one_of([
      string(:printable),
      integer(),
      float(),
      boolean(),
      constant(nil),
      member_of(@atoms),
      map(integer(0..36_500), &Date.add(~D[1990-01-01], &1)),
      map(integer(0..86_399), &Time.add(~T[00:00:00], &1)),
      map(integer(0..2_000_000_000), &DateTime.from_unix!/1),
      map(integer(0..2_000_000_000), &(&1 |> DateTime.from_unix!() |> DateTime.to_naive())),
      map(integer(-1_000_000..1_000_000), &Decimal.new/1)
    ])
  end
end
