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
