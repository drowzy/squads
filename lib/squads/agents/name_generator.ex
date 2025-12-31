defmodule Squads.Agents.NameGenerator do
  @moduledoc """
  Generates human-friendly agent names in AdjectiveNoun format.

  Names are curated to be memorable, professional, and unique within a squad.
  Each name has a corresponding slug form for use in paths and branch names.

  ## Examples

      iex> Squads.Agents.NameGenerator.generate()
      "GreenPanda"

      iex> Squads.Agents.NameGenerator.to_slug("GreenPanda")
      "green-panda"

      iex> Squads.Agents.NameGenerator.from_slug("green-panda")
      "GreenPanda"
  """

  @adjectives ~w(
    Amber Ancient Azure Blazing Bold Brave Bright Calm Clever Cosmic
    Crimson Crystal Daring Dawn Deep Diamond Dusty Echo Electric Emerald
    Epic Eternal Fierce Frosty Gentle Giant Glowing Golden Grand Green
    Hidden Humble Icy Iron Jade Keen Laser Light Lucky Lunar
    Magic Marble Mighty Misty Mystic Noble Ocean Onyx Orange Pale
    Phantom Polar Prime Proud Purple Quantum Quick Quiet Radiant Rapid
    Regal Rising Rocky Royal Ruby Rustic Sacred Sage Sandy Scarlet
    Secret Shadow Sharp Shiny Silent Silver Sleek Solar Solid Sonic
    Spark Spring Starry Steady Storm Strong Summer Super Swift Teal
    Thunder Tiny Topaz Tranquil Twilight Ultra Velvet Verdant Violet Vivid
  )

  @nouns ~w(
    Arrow Atlas Beacon Bear Blade Blaze Boulder Bridge Breeze Canyon
    Castle Cedar Cloud Comet Coral Crane Creek Crest Crystal Dawn
    Delta Dolphin Dragon Drift Eagle Echo Ember Falcon Fern Flame
    Forest Frost Galaxy Garden Gate Glacier Grove Harbor Haven Hawk
    Horizon Hunter Island Jade Jasper Knight Lake Lantern Leaf Lion
    Lotus Maple Marble Meadow Mesa Mirror Moon Mountain Nebula Nest
    Oak Ocean Orbit Osprey Otter Owl Palm Panda Peak Pearl
    Phoenix Pine Planet Pond Prairie Quest Quill Raven Reef Ridge
    River Robin Rock Rose Sage Sapphire Scout Seal Shadow Shore
    Sierra Spark Spirit Spruce Star Stone Storm Stream Summit Swan
  )

  @doc """
  Generates a random agent name in AdjectiveNoun format.
  """
  @spec generate() :: String.t()
  def generate do
    adjective = Enum.random(@adjectives)
    noun = Enum.random(@nouns)
    "#{adjective}#{noun}"
  end

  @doc """
  Generates a random name that is not in the given list of existing names.

  Tries up to 1000 times before falling back to appending a number.
  """
  @spec generate_unique([String.t()]) :: String.t()
  def generate_unique(existing_names) when is_list(existing_names) do
    existing_set = MapSet.new(existing_names)
    do_generate_unique(existing_set, 0)
  end

  defp do_generate_unique(existing_set, attempts) when attempts < 1000 do
    name = generate()

    if MapSet.member?(existing_set, name) do
      do_generate_unique(existing_set, attempts + 1)
    else
      name
    end
  end

  defp do_generate_unique(_existing_set, _attempts) do
    # Fallback: append timestamp suffix
    base = generate()
    suffix = :erlang.unique_integer([:positive]) |> rem(1000)
    "#{base}#{suffix}"
  end

  @doc """
  Converts a CamelCase name to a hyphenated slug.

  ## Examples

      iex> Squads.Agents.NameGenerator.to_slug("GreenPanda")
      "green-panda"

      iex> Squads.Agents.NameGenerator.to_slug("AzurePhoenix")
      "azure-phoenix"
  """
  @spec to_slug(String.t()) :: String.t()
  def to_slug(name) when is_binary(name) do
    name
    |> String.replace(~r/([A-Z])/, "-\\1")
    |> String.trim_leading("-")
    |> String.downcase()
  end

  @doc """
  Converts a hyphenated slug back to CamelCase name.

  ## Examples

      iex> Squads.Agents.NameGenerator.from_slug("green-panda")
      "GreenPanda"

      iex> Squads.Agents.NameGenerator.from_slug("azure-phoenix")
      "AzurePhoenix"
  """
  @spec from_slug(String.t()) :: String.t()
  def from_slug(slug) when is_binary(slug) do
    slug
    |> String.split("-")
    |> Enum.map(&String.capitalize/1)
    |> Enum.join()
  end

  @doc """
  Validates that a name matches the AdjectiveNoun format.

  Returns `:ok` if valid, `{:error, reason}` otherwise.
  """
  @spec validate_name(String.t()) :: :ok | {:error, String.t()}
  def validate_name(name) when is_binary(name) do
    if Regex.match?(~r/^[A-Z][a-z]+[A-Z][a-z]+$/, name) do
      :ok
    else
      {:error, "name must be in AdjectiveNoun format (e.g., GreenPanda)"}
    end
  end

  def validate_name(_), do: {:error, "name must be a string"}

  @doc """
  Validates that a slug matches the expected format.

  Returns `:ok` if valid, `{:error, reason}` otherwise.
  """
  @spec validate_slug(String.t()) :: :ok | {:error, String.t()}
  def validate_slug(slug) when is_binary(slug) do
    if Regex.match?(~r/^[a-z]+-[a-z]+$/, slug) do
      :ok
    else
      {:error, "slug must be lowercase hyphenated (e.g., green-panda)"}
    end
  end

  def validate_slug(_), do: {:error, "slug must be a string"}

  @doc """
  Returns the list of available adjectives.
  """
  @spec adjectives() :: [String.t()]
  def adjectives, do: @adjectives

  @doc """
  Returns the list of available nouns.
  """
  @spec nouns() :: [String.t()]
  def nouns, do: @nouns

  @doc """
  Returns the total number of possible unique combinations.
  """
  @spec combination_count() :: non_neg_integer()
  def combination_count do
    length(@adjectives) * length(@nouns)
  end
end
