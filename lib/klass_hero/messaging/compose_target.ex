defmodule KlassHero.Messaging.ComposeTarget do
  @moduledoc """
  Who a compose screen is about to write to, before any `Conversation` exists.

  A Direct Conversation is a thread between Users, and there is no thread until
  the first Message — so the compose screen holds this instead of a half-built
  Conversation. A distinct struct rather than a `%Conversation{id: nil}` because
  the show path does DB work keyed on that id and would silently misbehave.

  Built only by `KlassHero.Messaging.build_compose_target/3`, which refuses
  targets the scope may not write to.
  """

  @enforce_keys [:provider_id, :target_user_id]
  defstruct [:provider_id, :target_user_id, :program_id, :target_name]

  @type t :: %__MODULE__{
          provider_id: String.t(),
          target_user_id: String.t(),
          program_id: String.t() | nil,
          target_name: String.t() | nil
        }
end
