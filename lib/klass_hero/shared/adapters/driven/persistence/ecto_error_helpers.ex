defmodule KlassHero.Shared.Adapters.Driven.Persistence.EctoErrorHelpers do
  @moduledoc """
  Shared utilities for detecting and categorizing Ecto changeset constraint errors
  across all repository implementations.
  """

  @doc """
  Returns true if `field` has a unique constraint violation in the changeset error list.
  """
  @spec unique_constraint_violation?(
          errors :: [{atom(), {String.t(), Keyword.t()}}],
          field :: atom()
        ) :: boolean()
  def unique_constraint_violation?(errors, field) when is_list(errors) and is_atom(field) do
    constraint_violation?(errors, field, :unique)
  end

  @doc """
  Returns true if any field has a unique constraint violation (field-agnostic variant).
  """
  @spec any_unique_constraint_violation?(errors :: [{atom(), {String.t(), Keyword.t()}}]) ::
          boolean()
  def any_unique_constraint_violation?(errors) when is_list(errors) do
    Enum.any?(errors, fn {_field, {_message, opts}} ->
      Keyword.get(opts, :constraint) == :unique
    end)
  end

  @doc """
  Returns true if `field` carries a uniqueness conflict from *either* mechanism.

  A schema that pairs `unsafe_validate_unique/3` with `unique_constraint/2` rejects a
  duplicate two different ways depending on when the competing row lands: the pre-flight
  SELECT tags the error `validation: :unsafe_unique`, the database constraint tags it
  `constraint: :unique`. Both mean the same thing to a caller recovering from a lost race,
  and the pre-flight one wins the wider window — so recovery code must accept both.

  Use `unique_constraint_violation?/2` instead when you specifically mean "the database
  rejected this write".
  """
  @spec unique_conflict?(errors :: [{atom(), {String.t(), Keyword.t()}}], field :: atom()) ::
          boolean()
  def unique_conflict?(errors, field) when is_list(errors) and is_atom(field) do
    Enum.any?(errors, fn {error_field, {_message, opts}} ->
      error_field == field and
        (Keyword.get(opts, :constraint) == :unique or
           Keyword.get(opts, :validation) == :unsafe_unique)
    end)
  end

  @doc """
  Returns true if `field` has a foreign key constraint violation in the changeset error list.
  """
  @spec foreign_key_violation?(
          errors :: [{atom(), {String.t(), Keyword.t()}}],
          field :: atom()
        ) :: boolean()
  def foreign_key_violation?(errors, field) when is_list(errors) and is_atom(field) do
    constraint_violation?(errors, field, :foreign)
  end

  @doc """
  Returns true if `field` has the specified constraint type (`:unique`, `:foreign`, etc.).
  """
  @spec constraint_violation?(
          errors :: [{atom(), {String.t(), Keyword.t()}}],
          field :: atom(),
          constraint_type :: atom()
        ) :: boolean()
  def constraint_violation?(errors, field, constraint_type)
      when is_list(errors) and is_atom(field) and is_atom(constraint_type) do
    Enum.any?(errors, fn {error_field, {_message, opts}} ->
      error_field == field and Keyword.get(opts, :constraint) == constraint_type
    end)
  end
end
