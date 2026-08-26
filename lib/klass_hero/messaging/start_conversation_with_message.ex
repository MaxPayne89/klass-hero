defmodule KlassHero.Messaging.StartConversationWithMessage do
  @moduledoc """
  Opens a direct conversation *and* sends its first message.

  A `Conversation` exists only once a `Message` does. Compose screens therefore
  hold a `ComposeTarget` and call this on send, rather than creating a row when
  the box opens and leaving an empty thread behind if the user backs out (#1446).

  The content check runs first, before anything is created: the empty-message
  rule lives in `SendMessage`, so creating and then rejecting would reintroduce
  the very row this exists to avoid.

  Creation and send commit separately. A send that fails after creation leaves an
  empty conversation, which `find_direct_conversation/2` makes the user's retry
  reuse and fill; `Messaging.list_conversations/2` hides it in the meantime.
  """

  alias KlassHero.Accounts.Scope
  alias KlassHero.Messaging.Conversation
  alias KlassHero.Messaging.CreateDirectConversation
  alias KlassHero.Messaging.Message
  alias KlassHero.Messaging.SendMessage

  @doc """
  Creates or reuses the direct conversation for the target, then sends `content`.

  ## Parameters
  - scope: the initiator's scope
  - provider_id: the provider the conversation is anchored to
  - target_user_id: the other party; ignored when a parent initiates, since the
    provider owner is resolved from `provider_id`
  - content: message text, `nil` when sending attachments only
  - opts: `:program_id`, `:attachments`, `:skip_entitlement_check`

  ## Returns
  - `{:ok, conversation, message}`
  - `{:error, :empty_message | :not_entitled | :not_found | term()}` — with no
    conversation created
  """
  @spec execute(Scope.t(), String.t(), String.t() | nil, String.t() | nil, keyword()) ::
          {:ok, Conversation.t(), Message.t()}
          | {:error, :empty_message | :not_entitled | :not_found | term()}
  def execute(%Scope{} = scope, provider_id, target_user_id, content, opts \\ []) do
    attachments = Keyword.get(opts, :attachments, [])
    creation_opts = maybe_skip_entitlement(scope, provider_id, opts)

    with {:ok, _trimmed} <- SendMessage.validate_content(content, attachments),
         {:ok, conversation} <- find_or_create(scope, provider_id, target_user_id, creation_opts),
         {:ok, message} <- send_first_message(conversation, scope.user.id, content, attachments) do
      {:ok, conversation, message}
    end
  end

  # A staff scope carries no `:provider`, so `can_initiate_messaging?/1` denies it
  # deliberately. Their authority is employment by *this* provider — the same fact
  # the roster gate and `build_compose_target/3` check — so it is verified here
  # rather than skipped outright. A staff member of another provider still fails.
  defp maybe_skip_entitlement(%Scope{provider: nil, parent: nil} = scope, provider_id, opts) do
    if KlassHero.Messaging.acting_provider_id(scope) == provider_id do
      Keyword.put(opts, :skip_entitlement_check, true)
    else
      opts
    end
  end

  defp maybe_skip_entitlement(_scope, _provider_id, opts), do: opts

  # One path for everyone. There used to be two, split on the shape of the scope,
  # because a thread was keyed on a single participant and each side knew a
  # different one of the two. The principal pair keys on both, so the initiator's
  # role no longer decides which command runs — `build_compose_target/3` has
  # already resolved who the other party is.
  defp find_or_create(scope, provider_id, target_user_id, opts) do
    CreateDirectConversation.execute(scope, provider_id, target_user_id, opts)
  end

  defp send_first_message(conversation, sender_id, content, attachments) do
    SendMessage.execute(conversation.id, sender_id, content,
      conversation: conversation,
      attachments: attachments
    )
  end
end
