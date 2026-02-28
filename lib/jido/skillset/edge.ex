defmodule Jido.Skillset.Edge do
  @moduledoc """
  Edge model and relation taxonomy for skill graph links.
  """

  @type relation :: :related | :prereq | :extends | :contains | :references

  @relations [:related, :prereq, :extends, :contains, :references]
  @string_relations %{
    "related" => :related,
    "prereq" => :prereq,
    "extends" => :extends,
    "contains" => :contains,
    "references" => :references
  }

  @enforce_keys [:from, :to, :rel]
  defstruct [:from, :to, :rel, :label, :source_span, meta: %{}]

  @type t :: %__MODULE__{
          from: String.t(),
          to: String.t(),
          rel: relation(),
          label: String.t() | nil,
          source_span: term(),
          meta: map()
        }

  @type option ::
          {:from, String.t()}
          | {:to, String.t()}
          | {:rel, relation() | String.t()}
          | {:label, String.t()}
          | {:source_span, term()}
          | {:meta, map()}

  @spec relations() :: [relation()]
  def relations, do: @relations

  @spec new([option()]) :: {:ok, t()} | {:error, term()}
  def new(opts) when is_list(opts) do
    from = Keyword.get(opts, :from)
    to = Keyword.get(opts, :to)

    with :ok <- validate_endpoints(from, to),
         {:ok, rel} <- normalize_relation(Keyword.get(opts, :rel, :related)) do
      {:ok,
       %__MODULE__{
         from: from,
         to: to,
         rel: rel,
         label: Keyword.get(opts, :label),
         source_span: Keyword.get(opts, :source_span),
         meta: Keyword.get(opts, :meta, %{})
       }}
    end
  end

  @spec normalize_relation(relation() | String.t()) :: {:ok, relation()} | {:error, term()}
  def normalize_relation(rel) when is_atom(rel) do
    if rel in @relations do
      {:ok, rel}
    else
      {:error, {:invalid_relation, rel}}
    end
  end

  def normalize_relation(rel) when is_binary(rel) do
    case Map.fetch(@string_relations, String.downcase(rel)) do
      {:ok, normalized} -> {:ok, normalized}
      :error -> {:error, {:invalid_relation, rel}}
    end
  end

  def normalize_relation(rel), do: {:error, {:invalid_relation, rel}}

  defp validate_endpoints(from, to)
       when is_binary(from) and from != "" and is_binary(to) and to != "",
       do: :ok

  defp validate_endpoints(_from, _to), do: {:error, :invalid_edge_endpoints}
end
