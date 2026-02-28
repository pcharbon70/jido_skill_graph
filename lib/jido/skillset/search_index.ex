defmodule Jido.Skillset.SearchIndex do
  @moduledoc """
  Search index metadata contract for phased indexed-search rollout.

  This module defines the shape of index metadata carried inside snapshots.
  Posting lists and ETS-backed storage are introduced in later phases.
  """

  @typedoc "Supported searchable fields for field-aware scoring."
  @type field :: :id | :title | :tags | :body

  @fields [:id, :title, :tags, :body]

  @typedoc "Average token lengths across documents, keyed by field."
  @type avg_field_lengths :: %{
          required(field()) => float()
        }

  @typedoc "Optional metadata for body excerpt caches."
  @type body_cache_meta :: %{
          optional(:enabled) => boolean(),
          optional(:max_bytes_per_node) => non_neg_integer(),
          optional(:cached_nodes) => non_neg_integer()
        }

  @enforce_keys [:build_version, :document_count, :avg_field_lengths]
  defstruct [
    :build_version,
    :document_count,
    :avg_field_lengths,
    body_cache_meta: %{enabled: false, max_bytes_per_node: 0, cached_nodes: 0},
    meta: %{}
  ]

  @type t :: %__MODULE__{
          build_version: pos_integer(),
          document_count: non_neg_integer(),
          avg_field_lengths: avg_field_lengths(),
          body_cache_meta: body_cache_meta(),
          meta: map()
        }

  @type option ::
          {:build_version, pos_integer()}
          | {:document_count, non_neg_integer()}
          | {:avg_field_lengths, map()}
          | {:body_cache_meta, map()}
          | {:meta, map()}

  @spec fields() :: [field()]
  def fields, do: @fields

  @spec empty(keyword()) :: t()
  def empty(opts \\ []) do
    build_version = Keyword.get(opts, :build_version, 1)

    %__MODULE__{
      build_version: build_version,
      document_count: 0,
      avg_field_lengths: default_avg_field_lengths(),
      body_cache_meta: %{enabled: false, max_bytes_per_node: 0, cached_nodes: 0},
      meta: %{}
    }
  end

  @spec new([option()]) :: {:ok, t()} | {:error, term()}
  def new(opts \\ []) when is_list(opts) do
    build_version = Keyword.get(opts, :build_version, 1)
    document_count = Keyword.get(opts, :document_count, 0)
    avg_field_lengths = Keyword.get(opts, :avg_field_lengths, default_avg_field_lengths())

    body_cache_meta =
      Keyword.get(opts, :body_cache_meta, %{
        enabled: false,
        max_bytes_per_node: 0,
        cached_nodes: 0
      })

    meta = Keyword.get(opts, :meta, %{})

    with :ok <- validate_build_version(build_version),
         :ok <- validate_document_count(document_count),
         {:ok, normalized_averages} <- normalize_avg_field_lengths(avg_field_lengths),
         {:ok, normalized_body_cache_meta} <- normalize_body_cache_meta(body_cache_meta),
         :ok <- validate_meta(meta) do
      {:ok,
       %__MODULE__{
         build_version: build_version,
         document_count: document_count,
         avg_field_lengths: normalized_averages,
         body_cache_meta: normalized_body_cache_meta,
         meta: meta
       }}
    end
  end

  @doc """
  Builds index metadata from per-document field token lengths.

  Input shape:

      %{
        "node-id" => %{id: 1, title: 3, tags: 2, body: 40},
        ...
      }
  """
  @spec from_field_lengths(%{optional(String.t()) => map()}, keyword()) ::
          {:ok, t()} | {:error, term()}
  def from_field_lengths(field_lengths_by_doc, opts \\ [])
      when is_map(field_lengths_by_doc) and is_list(opts) do
    doc_count = map_size(field_lengths_by_doc)
    avg_lengths = average_field_lengths(field_lengths_by_doc, doc_count)

    opts
    |> Keyword.put(:document_count, doc_count)
    |> Keyword.put(:avg_field_lengths, avg_lengths)
    |> new()
  end

  @spec default_avg_field_lengths() :: avg_field_lengths()
  def default_avg_field_lengths do
    %{
      id: 0.0,
      title: 0.0,
      tags: 0.0,
      body: 0.0
    }
  end

  defp average_field_lengths(_field_lengths_by_doc, 0), do: default_avg_field_lengths()

  defp average_field_lengths(field_lengths_by_doc, doc_count) do
    totals =
      Enum.reduce(field_lengths_by_doc, %{id: 0, title: 0, tags: 0, body: 0}, fn {_doc_id,
                                                                                  lengths},
                                                                                 acc ->
        Enum.reduce(@fields, acc, fn field, field_acc ->
          value = lengths |> Map.get(field, 0) |> normalize_length_value()
          Map.update!(field_acc, field, &(&1 + value))
        end)
      end)

    Enum.reduce(@fields, %{}, fn field, acc ->
      Map.put(acc, field, totals[field] / doc_count)
    end)
  end

  defp normalize_length_value(value) when is_integer(value) and value >= 0, do: value
  defp normalize_length_value(value) when is_float(value) and value >= 0.0, do: trunc(value)
  defp normalize_length_value(_value), do: 0

  defp normalize_avg_field_lengths(avg_field_lengths) when is_map(avg_field_lengths) do
    Enum.reduce_while(@fields, {:ok, %{}}, fn field, {:ok, acc} ->
      value =
        Map.get(avg_field_lengths, field, Map.get(avg_field_lengths, Atom.to_string(field), 0.0))

      case normalize_non_negative_float(value) do
        {:ok, normalized} ->
          {:cont, {:ok, Map.put(acc, field, normalized)}}

        {:error, _reason} ->
          {:halt, {:error, {:invalid_avg_field_length, field, value}}}
      end
    end)
  end

  defp normalize_avg_field_lengths(_avg_field_lengths), do: {:error, :invalid_avg_field_lengths}

  defp normalize_non_negative_float(value) when is_integer(value) and value >= 0,
    do: {:ok, value / 1}

  defp normalize_non_negative_float(value) when is_float(value) and value >= 0.0, do: {:ok, value}
  defp normalize_non_negative_float(_value), do: {:error, :not_non_negative_float}

  defp normalize_body_cache_meta(meta) when is_map(meta) do
    enabled = Map.get(meta, :enabled, Map.get(meta, "enabled", false))
    max_bytes = Map.get(meta, :max_bytes_per_node, Map.get(meta, "max_bytes_per_node", 0))
    cached_nodes = Map.get(meta, :cached_nodes, Map.get(meta, "cached_nodes", 0))

    with :ok <- validate_boolean(enabled, :enabled),
         :ok <- validate_non_negative_integer(max_bytes, :max_bytes_per_node),
         :ok <- validate_non_negative_integer(cached_nodes, :cached_nodes) do
      {:ok,
       %{
         enabled: enabled,
         max_bytes_per_node: max_bytes,
         cached_nodes: cached_nodes
       }}
    end
  end

  defp normalize_body_cache_meta(_meta), do: {:error, :invalid_body_cache_meta}

  defp validate_build_version(value) when is_integer(value) and value >= 1, do: :ok
  defp validate_build_version(value), do: {:error, {:invalid_build_version, value}}

  defp validate_document_count(value) when is_integer(value) and value >= 0, do: :ok
  defp validate_document_count(value), do: {:error, {:invalid_document_count, value}}

  defp validate_meta(meta) when is_map(meta), do: :ok
  defp validate_meta(meta), do: {:error, {:invalid_meta, meta}}

  defp validate_boolean(value, _field) when is_boolean(value), do: :ok

  defp validate_boolean(value, field),
    do: {:error, {:invalid_body_cache_meta_field, field, value}}

  defp validate_non_negative_integer(value, _field) when is_integer(value) and value >= 0, do: :ok

  defp validate_non_negative_integer(value, field),
    do: {:error, {:invalid_body_cache_meta_field, field, value}}
end
