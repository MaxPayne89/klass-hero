defmodule KlassHero.Provider.Domain.Models.StepDefinition do
  @moduledoc """
  A static definition of one Verification Step within a Vetting Track.

  Definitions are pure domain policy (see `KlassHero.Provider.Domain.Services.Vetting`).
  When a Vetting Case is created, each definition is frozen into a `VerificationStep`
  instance — its structural fields are copied so that later reordering a track never
  mutates an in-flight case.

  ## Fields

  - `key` - Stable identifier for the step (e.g. `:experience`)
  - `completed_via` - How the step reaches `:approved`. `{:document, document_type}` for
    document-evidence steps (Admin review); `{:stripe_identity}` for the Stripe Identity step
    (advanced by webhook). Later evidence kinds (`:agreement`) are introduced in their own slices.
  - `requires` - Keys of steps that must be `:approved` before this step can start (a sparse,
    acyclic prerequisite graph). Empty for independent steps.
  - `admin_review?` - Whether completion needs an Admin decision (document steps) or auto-approves.
  """

  @enforce_keys [:key, :completed_via]
  defstruct [:key, :completed_via, requires: [], admin_review?: false]

  @type completed_via :: {:document, String.t()} | {:stripe_identity}

  @type t :: %__MODULE__{
          key: atom(),
          completed_via: completed_via(),
          requires: [atom()],
          admin_review?: boolean()
        }
end
