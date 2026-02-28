defmodule Jido.Skillset.Node do
  @moduledoc """
  Node model and identity rules for skill graph entries.
  """

  @enforce_keys [:id, :graph_id, :path]
  defstruct [
    :id,
    :graph_id,
    :path,
    :title,
    :checksum,
    :body_ref,
    :placeholder?,
    tags: [],
    meta: %{}
  ]

  @type t :: %__MODULE__{
          id: String.t(),
          graph_id: String.t(),
          path: Path.t(),
          title: String.t() | nil,
          checksum: String.t() | nil,
          body_ref: term(),
          placeholder?: boolean() | nil,
          tags: [String.t()],
          meta: map()
        }

  @type option ::
          {:graph_id, String.t()}
          | {:path, Path.t()}
          | {:root, Path.t()}
          | {:slug, String.t()}
          | {:title, String.t()}
          | {:checksum, String.t()}
          | {:body_ref, term()}
          | {:placeholder?, boolean()}
          | {:tags, [String.t()]}
          | {:meta, map()}

  @spec new([option()]) :: {:ok, t()} | {:error, term()}
  def new(opts) when is_list(opts) do
    graph_id = Keyword.get(opts, :graph_id)
    path = Keyword.get(opts, :path)

    with :ok <- validate_required(graph_id, path),
         id <- derive_id(path, root: Keyword.get(opts, :root), slug: Keyword.get(opts, :slug)),
         :ok <- validate_id(id) do
      {:ok,
       %__MODULE__{
         id: id,
         graph_id: graph_id,
         path: path,
         title: Keyword.get(opts, :title),
         checksum: Keyword.get(opts, :checksum),
         body_ref: Keyword.get(opts, :body_ref),
         placeholder?: Keyword.get(opts, :placeholder?, false),
         tags: Keyword.get(opts, :tags, []),
         meta: Keyword.get(opts, :meta, %{})
       }}
    end
  end

  @spec placeholder(String.t(), String.t()) :: t()
  def placeholder(graph_id, id) when is_binary(graph_id) and is_binary(id) do
    %__MODULE__{
      id: id,
      graph_id: graph_id,
      path: "/virtual/#{graph_id}/#{id}",
      title: id,
      checksum: nil,
      body_ref: nil,
      placeholder?: true,
      tags: [],
      meta: %{}
    }
  end

  @spec derive_id(Path.t(), keyword()) :: String.t()
  def derive_id(path, opts \\ []) when is_binary(path) do
    case Keyword.get(opts, :slug) do
      slug when is_binary(slug) and slug != "" ->
        normalize_id(slug)

      _ ->
        path
        |> normalize_relative_path(Keyword.get(opts, :root))
        |> strip_skill_filename()
        |> normalize_id()
    end
  end

  @spec normalize_id(String.t()) :: String.t()
  def normalize_id(raw_id) when is_binary(raw_id) do
    raw_id
    |> String.replace("\\", "/")
    |> String.split("/", trim: true)
    |> Enum.map(&normalize_segment/1)
    |> Enum.reject(&(&1 == ""))
    |> case do
      [] -> "root"
      segments -> Enum.join(segments, "/")
    end
  end

  defp normalize_relative_path(path, nil), do: path

  defp normalize_relative_path(path, root) do
    if Path.type(path) == :absolute and Path.type(root) == :absolute do
      Path.relative_to(path, root)
    else
      path
    end
  end

  defp strip_skill_filename(path) do
    base = path |> Path.basename() |> Path.rootname()

    if String.downcase(base) == "skill" do
      Path.dirname(path)
    else
      Path.rootname(path)
    end
  end

  defp normalize_segment(segment) do
    segment
    |> String.downcase()
    |> String.replace(~r/[^a-z0-9]+/u, "-")
    |> String.trim("-")
  end

  defp validate_required(graph_id, path)
       when is_binary(graph_id) and graph_id != "" and is_binary(path) and path != "",
       do: :ok

  defp validate_required(_graph_id, _path), do: {:error, :invalid_required_fields}

  defp validate_id(id) when is_binary(id) and id != "", do: :ok
  defp validate_id(_id), do: {:error, :invalid_id}
end
