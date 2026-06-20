defmodule KlassHero.Provider.Domain.Models.IdentityVerification do
  @moduledoc """
  Evidence for a Stripe Identity vetting step: the outcome of one Stripe Identity Verification
  Session run against a person (the individual Provider, or a business's responsible person).

  Klass Hero stores only the session id and the pass/fail outcome — never the date of birth and
  never document images (see ADR-0007 and `CONTEXT.md`). One row per session, append-only: a retry
  creates a fresh Stripe session and a fresh `IdentityVerification`.

  This module also owns the **fail-closed 18+ age gate**: `age_18_plus?/2` is pure and returns
  `true` only for a well-formed date of birth that is at least 18 years before the reference date.
  Every other input — a minor, a missing or malformed DOB — returns `false`.
  """

  @typedoc "Stripe `verified_outputs.dob` shape, or nil when Stripe returned no document DOB."
  @type dob :: %{day: integer(), month: integer(), year: integer()} | nil

  @type status :: :processing | :verified | :requires_input | :canceled
  @type outcome :: :pass | :fail | nil

  @enforce_keys [:provider_id, :stripe_session_id]
  defstruct [
    :id,
    :provider_id,
    :stripe_session_id,
    :failure_reason,
    :verified_at,
    status: :processing,
    outcome: nil
  ]

  @type t :: %__MODULE__{
          id: String.t() | nil,
          provider_id: String.t(),
          stripe_session_id: String.t(),
          failure_reason: String.t() | nil,
          verified_at: DateTime.t() | nil,
          status: status(),
          outcome: outcome()
        }

  @doc """
  Starts a new in-flight verification for a freshly created Stripe session: `:processing`, no
  outcome yet. Each call models a distinct session (retries append new records).
  """
  @spec new(%{provider_id: String.t(), stripe_session_id: String.t()}) :: t()
  def new(%{provider_id: provider_id, stripe_session_id: session_id}) do
    %__MODULE__{
      id: Ecto.UUID.generate(),
      provider_id: provider_id,
      stripe_session_id: session_id,
      status: :processing,
      outcome: nil
    }
  end

  @doc """
  Records a Stripe `verified` outcome, applying the fail-closed age gate against `today`: an adult
  passes (`:pass`); a minor fails (`"under_18"`); a missing/unparseable DOB fails
  (`"age_unverifiable"`). The Stripe status is `:verified` regardless — `outcome` carries our gate.
  """
  @spec mark_verified(t(), dob(), Date.t()) :: t()
  def mark_verified(%__MODULE__{} = iv, dob, %Date{} = today) do
    case classify_age(dob, today) do
      :adult -> %{iv | status: :verified, outcome: :pass, failure_reason: nil, verified_at: now()}
      :minor -> %{iv | status: :verified, outcome: :fail, failure_reason: "under_18"}
      :unverifiable -> %{iv | status: :verified, outcome: :fail, failure_reason: "age_unverifiable"}
    end
  end

  @doc "Records a Stripe `requires_input` outcome — a failed verification the provider can retry."
  @spec mark_requires_input(t()) :: t()
  def mark_requires_input(%__MODULE__{} = iv) do
    %{iv | status: :requires_input, outcome: :fail, failure_reason: "requires_input"}
  end

  @doc "Records a Stripe `canceled` outcome — a failed verification the provider can retry."
  @spec mark_canceled(t()) :: t()
  def mark_canceled(%__MODULE__{} = iv) do
    %{iv | status: :canceled, outcome: :fail, failure_reason: "canceled"}
  end

  @doc """
  Returns `true` only when `dob` is a valid date of birth at least 18 years before `today`.

  Fail-closed: a nil or malformed `dob` returns `false`. The boundary is inclusive — turning 18 on
  `today` passes. A Feb-29 birth date observes its 18th birthday on Mar 1 in a non-leap year.
  """
  @spec age_18_plus?(dob(), Date.t()) :: boolean()
  def age_18_plus?(dob, %Date{} = today), do: classify_age(dob, today) == :adult

  @spec classify_age(dob(), Date.t()) :: :adult | :minor | :unverifiable
  defp classify_age(dob, today) do
    case eighteenth_birthday(dob) do
      {:ok, birthday} -> if Date.before?(today, birthday), do: :minor, else: :adult
      :error -> :unverifiable
    end
  end

  @spec eighteenth_birthday(dob()) :: {:ok, Date.t()} | :error
  defp eighteenth_birthday(%{day: day, month: month, year: year})
       when is_integer(day) and is_integer(month) and is_integer(year) do
    with {:error, _} <- Date.new(year + 18, month, day),
         {:error, _} <- shift_leap_day(year + 18, month, day) do
      :error
    end
  end

  defp eighteenth_birthday(_dob), do: :error

  # A Feb-29 birth date has no Feb-29 in a non-leap target year; its 18th birthday is observed Mar 1.
  defp shift_leap_day(year, 2, 29) do
    with {:ok, feb28} <- Date.new(year, 2, 28), do: {:ok, Date.add(feb28, 1)}
  end

  defp shift_leap_day(_year, _month, _day), do: :error

  defp now, do: DateTime.utc_now() |> DateTime.truncate(:second)
end
