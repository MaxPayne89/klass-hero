defmodule KlassHero.Shared.Interaction.Kind do
  @moduledoc """
  Per-I/O-kind policy for the `KlassHero.Shared.Interaction` envelope.

  An adapter wraps an outbound call in an `interaction`/`db_interaction`/... block.
  The macro builds an `Interaction` carrier, runs the block, then asks the kind
  module four questions about the outcome:

  - `classify/1` — was this a success or a failure, for metrics purposes?
  - `normalize_error/1` — what low-cardinality, PII-free term describes the failure?
  - `attributes/2` — what bounded-cardinality tags belong on the span and telemetry?
  - `sanitize/2` — what, if anything, of the inputs is safe to emit?

  The carrier never reaches callers; the adapter's native return value is preserved.
  These callbacks only shape the *observability projection* of the call.

  Implementations live under `KlassHero.Shared.Interaction.Kind.*` — one per kind
  (`Db`, `Http`, `S3`, `Email`, `FeatureFlags`).
  """

  @type result :: term()
  @type input :: term()
  @type status :: :ok | :error

  @doc """
  Classifies the block's native return value as a success or failure.

  This is the kind-level default. A per-call `success:` classifier passed to the
  macro overrides it for return shapes the kind can't reason about generically
  (bare lists, bare booleans, "`:not_found` is expected here").
  """
  @callback classify(result()) :: status()

  @doc """
  Maps a failure-classified result to a low-cardinality, PII-free term.

  Used for the `:error` field and as telemetry metadata (never a metric tag —
  could be unbounded). Must not echo user data.
  """
  @callback normalize_error(result()) :: term()

  @doc """
  Extracts bounded-cardinality attributes for both the OTel span and telemetry
  metadata. `opts` carries macro call options (`:operation`, `:entity`, `:service`).
  """
  @callback attributes(result(), opts :: keyword()) :: map()

  @doc """
  Redacts the captured input down to something safe to emit.

  Conservative by contract: the default implementation drops everything to
  `:redacted`. Callers opt into an allowlist via `capture:` on the macro.
  """
  @callback sanitize(input(), opts :: keyword()) :: term()

  @doc """
  Conservative sanitiser shared by every kind until per-kind allowlists land.

  Drops the input entirely unless the call opted into a key allowlist via
  `capture: {:keys, [...]}` over a map input. Refining which keys are safe to
  emit per kind is a privacy decision, owned per kind, not here.
  """
  @spec default_sanitize(input(), keyword()) :: term()
  def default_sanitize(input, opts) do
    case Keyword.get(opts, :capture, :drop) do
      {:keys, keys} when is_map(input) -> Map.take(input, keys)
      _ -> :redacted
    end
  end
end
