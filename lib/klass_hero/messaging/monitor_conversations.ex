defmodule KlassHero.Messaging.MonitorConversations do
  @moduledoc """
  Lists every conversation on the platform, for a platform admin.

  This is the one read in Messaging that is not scoped to a participant. It exists
  for safety, abuse prevention and compliance — see #744 and ADR-0021 — and it is
  strictly read-only: it creates no `Participant` row, writes no `last_read_at`, and
  subscribes to nothing.

  It deliberately does **not** read the `conversation_summaries` projection. That
  table is keyed `(conversation_id, user_id)`, so an admin has no row in it, and
  reading it anyway would yield one row per participant per conversation. The
  write-side `conversations` table is the only correct source for a platform-wide
  view.
  """

  use KlassHero.Shared.Tracing

  alias KlassHero.Accounts.Scope
  alias KlassHero.Messaging.Authorization
  alias KlassHero.Messaging.Conversation
  alias KlassHero.Messaging.Queries.ConversationQueries
  alias KlassHero.Repo

  @default_limit 25

  @doc """
  Returns a page of conversations, newest first.

  ## Options

    * `:provider_id` - restrict to one provider
    * `:type` - `:direct` or `:program_broadcast`
    * `:limit` - page size, defaults to #{@default_limit}
    * `:before` - exclusive `inserted_at` cursor for the next (older) page

  Authorization resolves before any option is read, so a non-admin's refusal cannot
  depend on what they asked for.
  """
  @spec execute(Scope.t(), keyword()) ::
          {:ok, [Conversation.t()], boolean()} | {:error, :unauthorized}
  def execute(%Scope{} = scope, opts \\ []) do
    span do
      OpenTelemetry.Tracer.set_attribute("messaging.monitoring.admin_id", scope.user.id)

      list(scope, opts)
    end
  end

  defp list(%Scope{} = scope, opts) do
    with :ok <- Authorization.authorize_admin(scope) do
      limit = Keyword.get(opts, :limit, @default_limit)

      rows =
        ConversationQueries.base()
        |> maybe_by_provider(Keyword.get(opts, :provider_id))
        |> maybe_by_type(Keyword.get(opts, :type))
        |> ConversationQueries.order_by_newest()
        |> ConversationQueries.paginate(Keyword.put(opts, :limit, limit))
        |> ConversationQueries.preload_assocs([:participants])
        |> Repo.all()

      {:ok, Enum.take(rows, limit), length(rows) > limit}
    end
  end

  defp maybe_by_provider(query, nil), do: query

  defp maybe_by_provider(query, provider_id), do: ConversationQueries.by_provider(query, provider_id)

  defp maybe_by_type(query, nil), do: query
  defp maybe_by_type(query, type), do: ConversationQueries.by_type(query, type)
end
