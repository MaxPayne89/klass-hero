defmodule KlassHero.Shared.Domain.Types.Pagination do
  @moduledoc """
  Pure domain types for cursor-based (seek) pagination across bounded contexts.
  """

  defmodule PageParams do
    @moduledoc """
    Input parameters for paginated queries.

    `limit` (default 20, clamped to 1–100) and optional Base64 `cursor`.
    Out-of-range integer limits are clamped rather than rejected; non-integer
    limits return `{:error, :invalid_limit}`.
    """

    @default_limit 20
    @min_limit 1
    @max_limit 100

    @typedoc "Input parameters for a paginated query."
    @type t :: %__MODULE__{
            limit: pos_integer(),
            cursor: String.t() | nil
          }

    defstruct limit: @default_limit, cursor: nil

    @doc """
    Creates new PageParams with optional attributes, clamping limit to valid bounds.
    """
    def new(attrs \\ []) do
      %__MODULE__{
        limit: Keyword.get(attrs, :limit, @default_limit),
        cursor: Keyword.get(attrs, :cursor)
      }
      |> validate()
    end

    @doc """
    Validates and clamps PageParams limit to 1–100. Non-integer limit returns `{:error, :invalid_limit}`.
    """
    def validate(%__MODULE__{limit: limit} = params) when is_integer(limit) do
      cond do
        limit < @min_limit ->
          {:ok, %{params | limit: @min_limit}}

        limit > @max_limit ->
          {:ok, %{params | limit: @max_limit}}

        true ->
          {:ok, params}
      end
    end

    def validate(%__MODULE__{limit: limit}) when not is_integer(limit) do
      {:error, :invalid_limit}
    end
  end

  defmodule PageResult do
    @moduledoc """
    Output structure for paginated results.

    `items`, `next_cursor` (nil if no more pages), `has_more`, and `metadata` (includes `returned_count`).
    """

    @typedoc "Output of a paginated query."
    @type t :: %__MODULE__{
            items: list(),
            next_cursor: String.t() | nil,
            has_more: boolean(),
            metadata: map()
          }

    defstruct items: [], next_cursor: nil, has_more: false, metadata: %{}

    def new(items, next_cursor, has_more) when is_list(items) and is_boolean(has_more) do
      %__MODULE__{
        items: items,
        next_cursor: next_cursor,
        has_more: has_more,
        metadata: %{
          returned_count: length(items)
        }
      }
    end
  end
end
