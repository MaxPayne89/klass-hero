defmodule KlassHero.Provider.StepDefinition do
  @moduledoc """
  A static definition of one Verification Step within a Vetting Track.

  Definitions are pure domain policy (see `KlassHero.Provider.Vetting`). When a
  Vetting Case is created, each definition is frozen into a `VerificationStep`
  instance — its structural fields are copied so that later reordering a track
  never mutates an in-flight case.

  ## Fields

  - `key` - Stable identifier for the step (e.g. `:experience`).
  - `completed_via` - How the step reaches `:approved`. `{:document, document_type}`
    for document-evidence steps (admin review); `{:stripe_identity}` for the Stripe
    Identity step (advanced by webhook); `{:signed_agreement, kind}` for an agreement
    the provider signs, which auto-approves on submission.
  - `requires` - Keys of steps that must be `:approved` before this step can start
    (a sparse, acyclic prerequisite graph). Empty for independent steps.
  - `admin_review` - Whether completion needs an admin decision (document steps) or
    auto-approves.
  - `dedicated` - Whether the step has a dedicated submission surface, so it must not
    be reached through the generic document picker. `:command` — a dedicated command
    captures extra structured facts (business registration), so the generic
    `submit_verification_document/1` rejects the type outright. `:widget` — a dedicated
    widget reuses the generic submit command (insurance, video, responsible-person), so
    it is only dropped from the generic picker. `false` (default) — a plain generic
    document step. `:command` implies `:widget` for picker-exclusion purposes.

  Pure struct — not an Ecto schema. Definitions live in code, never the database.
  """

  @enforce_keys [:key, :completed_via]
  defstruct [:key, :completed_via, requires: [], admin_review: false, dedicated: false]

  @type completed_via :: {:document, String.t()} | {:stripe_identity} | {:signed_agreement, atom()}
  @type dedicated :: false | :widget | :command

  @type t :: %__MODULE__{
          key: atom(),
          completed_via: completed_via(),
          requires: [atom()],
          admin_review: boolean(),
          dedicated: dedicated()
        }
end
