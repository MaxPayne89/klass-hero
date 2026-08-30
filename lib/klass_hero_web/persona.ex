defmodule KlassHeroWeb.Persona do
  @moduledoc """
  Everything the web layer needs to know about personas.

  The *set* is not declared here — `KlassHero.Accounts.UserRole` owns it,
  and this module delegates. Keeping a second copy is what bit the locale seam
  (#1227): the two lists drifted, and choosing a value the UI offered failed
  with no explanation anywhere.

  This replaced `RoleRouting`, which mapped a roles *list* to one surface by a
  fixed `provider > staff > parent` precedence. That precedence survives as the
  **default**, not the rule: a person holding several personas may choose one,
  and the choice is remembered (ADR-0005, "remembered/last-used dashboard
  switcher").

  ## A preference, never a grant

  `users.active_persona` records what someone *chose to look at*. It confers
  nothing. Authorization stays persona existence — `Scope.parent?/1`,
  `Scope.provider?/1`, `Scope.staff?/1` — so `resolve/1` discards a stored
  persona the person no longer holds rather than honouring it. That is also why
  nothing here writes the column back: a stale value is ignored on every read,
  the same way `KlassHeroWeb.Locale` never rewrites a since-retired
  `users.locale`.

  ## Why there are two entry points

  `resolve/1` is authoritative and needs a *resolved* `Scope`. `from_user/1`
  runs no query and is the login path: `UserAuth.signed_in_path/1` is called
  from `UserLive.Registration`'s `mount/3`, where the personas do not exist yet
  — they are created asynchronously by the outbox handlers reacting to
  `user_registered`. Resolving there would add queries to mount *and* send every
  brand-new provider to the parent dashboard, so it falls back to
  `intended_roles`, the eventual-consistency bridge `CONTEXT.md` names.

  `validate/1` coerces rather than raises, for the same reason
  `KlassHeroWeb.Locale.validate/1` does: every caller receives a persona from
  untrusted input — a path param, a session written by an older release, a
  column holding a value since retired. The changeset is the strict half.
  """

  use KlassHeroWeb, :verified_routes
  use Gettext, backend: KlassHeroWeb.Gettext

  alias KlassHero.Accounts.Scope
  alias KlassHero.Accounts.User
  alias KlassHero.Accounts.UserRole

  @type t :: :parent | :provider | :staff
  @type page :: :dashboard | :messages

  # The historical landing order, kept as the tie-break when nobody has chosen.
  @precedence [:provider, :staff, :parent]

  # Display order for the switcher, deliberately not @precedence: the menu reads
  # as a stable list, so it should not reorder itself as someone gains personas.
  @nav_order [:parent, :provider, :staff]

  @doc "Every persona the app knows. Delegated — never a second copy (#1227)."
  @spec known() :: [t()]
  defdelegate known(), to: UserRole, as: :valid_roles

  @doc """
  Coerces any term to a known persona, or `nil`.

  Never `String.to_atom/1`: this reads user-supplied input, and that would let a
  crafted URL grow the atom table without bound.
  """
  @spec validate(term()) :: t() | nil
  def validate(persona) when is_atom(persona) and not is_nil(persona) do
    if persona in known(), do: persona
  end

  def validate(persona) when is_binary(persona) do
    Enum.find(known(), &(Atom.to_string(&1) == persona))
  end

  def validate(_persona), do: nil

  @doc """
  The surface a resolved scope should see.

  The stored preference wins only if the person still holds that persona;
  otherwise precedence decides.
  """
  @spec resolve(Scope.t()) :: t()
  def resolve(%Scope{} = scope) do
    held = available(scope)
    stored = scope.user && validate(scope.user.active_persona)

    if stored in held, do: stored, else: default_for(held)
  end

  @doc """
  The surface a user should land on, without touching the database.

  Stored preference, else the `intended_roles` landing hint, else parent. Used
  at login and registration, where the personas may not exist yet.
  """
  @spec from_user(User.t() | nil) :: t()
  def from_user(%User{} = user) do
    validate(user.active_persona) || default_for(user.intended_roles || [])
  end

  def from_user(_user), do: :parent

  @doc "The personas this scope actually holds, in switcher display order."
  @spec available(Scope.t()) :: [t()]
  def available(%Scope{} = scope), do: Enum.filter(@nav_order, &holds?(scope, &1))

  @doc "The one URL serving `page` on `persona`."
  @spec path(t(), page()) :: String.t()
  def path(:parent, :dashboard), do: ~p"/dashboard"
  def path(:provider, :dashboard), do: ~p"/provider/dashboard"
  def path(:staff, :dashboard), do: ~p"/staff/dashboard"
  def path(:parent, :messages), do: ~p"/messages"
  def path(:provider, :messages), do: ~p"/provider/messages"
  def path(:staff, :messages), do: ~p"/staff/messages"

  @doc """
  The one URL serving `session_id`'s participation roster on `persona`.

  Separate from `path/2` because it takes an id; same rule otherwise — one clause
  per persona, each `~p`-verified. `:parent` has no clause on purpose: parents have
  no participation roster, and a clause returning `nil` would render a dead link.
  """
  @spec session_path(:provider | :staff, String.t()) :: String.t()
  def session_path(:provider, session_id), do: ~p"/provider/participation/#{session_id}"
  def session_path(:staff, session_id), do: ~p"/staff/participation/#{session_id}"

  @doc "How the persona is named to the person holding it."
  @spec label(t()) :: String.t()
  def label(:parent), do: gettext("Parent")
  def label(:provider), do: gettext("Provider")
  def label(:staff), do: gettext("Staff")

  defp holds?(%Scope{parent: parent}, :parent), do: parent != nil
  defp holds?(%Scope{provider: provider}, :provider), do: provider != nil
  defp holds?(%Scope{staff_member: staff_member}, :staff), do: staff_member != nil

  defp default_for(personas), do: Enum.find(@precedence, :parent, &(&1 in personas))
end
