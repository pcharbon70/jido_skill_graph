defmodule Jido.Skillset.Manifest do
  @moduledoc """
  Manifest contract for skill graph discovery metadata.

  Supported fields in `graph.yml`:

  - `graph_id`: string
  - `root`: path (relative to manifest directory when not absolute)
  - `includes`: list of include patterns or paths
  - `metadata`: map
  """

  @enforce_keys [:path]
  defstruct [:path, :graph_id, :root, includes: [], metadata: %{}]

  @type t :: %__MODULE__{
          path: Path.t(),
          graph_id: String.t() | nil,
          root: Path.t() | nil,
          includes: [Path.t()],
          metadata: map()
        }

  @spec load(Path.t()) :: {:ok, t()} | {:error, term()}
  def load(path) when is_binary(path) do
    with {:ok, document} <- YamlElixir.read_from_file(path),
         :ok <- validate_document(document) do
      manifest_dir = Path.dirname(path)

      {:ok,
       %__MODULE__{
         path: path,
         graph_id: fetch_string(document, "graph_id"),
         root: resolve_root(manifest_dir, fetch_string(document, "root")),
         includes: normalize_includes(fetch_list(document, "includes")),
         metadata: fetch_map(document, "metadata")
       }}
    else
      {:error, reason} -> {:error, {:invalid_manifest, path, reason}}
      :error -> {:error, {:invalid_manifest, path, :invalid_shape}}
    end
  end

  defp validate_document(document) when is_map(document), do: :ok
  defp validate_document(_document), do: :error

  defp fetch_string(map, key) do
    case map[key] do
      value when is_binary(value) and value != "" -> value
      _ -> nil
    end
  end

  defp fetch_list(map, key) do
    case map[key] do
      values when is_list(values) -> values
      _ -> []
    end
  end

  defp fetch_map(map, key) do
    case map[key] do
      values when is_map(values) -> values
      _ -> %{}
    end
  end

  defp normalize_includes(includes) do
    includes
    |> Enum.filter(&is_binary/1)
    |> Enum.map(&String.trim/1)
    |> Enum.reject(&(&1 == ""))
  end

  defp resolve_root(_manifest_dir, nil), do: nil

  defp resolve_root(_manifest_dir, root) when root in [".", "./"], do: nil

  defp resolve_root(manifest_dir, root) do
    if Path.type(root) == :absolute do
      Path.expand(root)
    else
      manifest_dir
      |> Path.join(root)
      |> Path.expand()
    end
  end
end
