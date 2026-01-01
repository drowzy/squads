defmodule Squads.Agents.NameGeneratorTest do
  use ExUnit.Case, async: true

  alias Squads.Agents.NameGenerator

  describe "generate/0" do
    test "returns a name in AdjectiveNoun format" do
      name = NameGenerator.generate()
      assert Regex.match?(~r/^[A-Z][a-z]+[A-Z][a-z]+$/, name)
    end

    test "returns different names on multiple calls" do
      names = for _ <- 1..100, do: NameGenerator.generate()
      unique_names = Enum.uniq(names)
      # Should get at least 50 unique names in 100 tries
      assert length(unique_names) >= 50
    end
  end

  describe "generate_unique/1" do
    test "avoids existing names" do
      existing = ["GreenPanda", "BlueFalcon"]
      name = NameGenerator.generate_unique(existing)
      refute name in existing
    end

    test "works with empty list" do
      name = NameGenerator.generate_unique([])
      assert is_binary(name)
      assert String.length(name) > 0
    end

    test "handles large existing set" do
      # Generate many existing names
      existing = for _ <- 1..1000, do: NameGenerator.generate()
      name = NameGenerator.generate_unique(existing)
      assert is_binary(name)
    end
  end

  describe "to_slug/1" do
    test "converts CamelCase to slug" do
      assert NameGenerator.to_slug("GreenPanda") == "green-panda"
      assert NameGenerator.to_slug("AzurePhoenix") == "azure-phoenix"
      assert NameGenerator.to_slug("MightyOak") == "mighty-oak"
    end
  end

  describe "from_slug/1" do
    test "converts slug to CamelCase" do
      assert NameGenerator.from_slug("green-panda") == "GreenPanda"
      assert NameGenerator.from_slug("azure-phoenix") == "AzurePhoenix"
      assert NameGenerator.from_slug("mighty-oak") == "MightyOak"
    end
  end

  describe "to_slug/1 and from_slug/1 roundtrip" do
    test "roundtrips correctly" do
      for _ <- 1..10 do
        name = NameGenerator.generate()
        slug = NameGenerator.to_slug(name)
        restored = NameGenerator.from_slug(slug)
        assert name == restored
      end
    end
  end

  describe "validate_name/1" do
    test "accepts valid names" do
      assert :ok = NameGenerator.validate_name("GreenPanda")
      assert :ok = NameGenerator.validate_name("AzurePhoenix")
    end

    test "rejects invalid names" do
      assert {:error, _} = NameGenerator.validate_name("greenpanda")
      assert {:error, _} = NameGenerator.validate_name("Green")
      assert {:error, _} = NameGenerator.validate_name("GREENPANDA")
      assert {:error, _} = NameGenerator.validate_name("Green-Panda")
      assert {:error, _} = NameGenerator.validate_name("")
      assert {:error, _} = NameGenerator.validate_name(123)
    end
  end

  describe "validate_slug/1" do
    test "accepts valid slugs" do
      assert :ok = NameGenerator.validate_slug("green-panda")
      assert :ok = NameGenerator.validate_slug("azure-phoenix")
    end

    test "rejects invalid slugs" do
      assert {:error, _} = NameGenerator.validate_slug("GreenPanda")
      assert {:error, _} = NameGenerator.validate_slug("green_panda")
      assert {:error, _} = NameGenerator.validate_slug("green")
      assert {:error, _} = NameGenerator.validate_slug("")
      assert {:error, _} = NameGenerator.validate_slug(123)
    end
  end

  describe "adjectives/0 and nouns/0" do
    test "returns 100 adjectives" do
      assert length(NameGenerator.adjectives()) == 100
    end

    test "returns 100 nouns" do
      assert length(NameGenerator.nouns()) == 100
    end

    test "all adjectives are unique" do
      adjectives = NameGenerator.adjectives()
      assert length(adjectives) == length(Enum.uniq(adjectives))
    end

    test "all nouns are unique" do
      nouns = NameGenerator.nouns()
      assert length(nouns) == length(Enum.uniq(nouns))
    end

    test "all adjectives start with uppercase" do
      for adj <- NameGenerator.adjectives() do
        assert String.match?(adj, ~r/^[A-Z][a-z]+$/)
      end
    end

    test "all nouns start with uppercase" do
      for noun <- NameGenerator.nouns() do
        assert String.match?(noun, ~r/^[A-Z][a-z]+$/)
      end
    end
  end

  describe "combination_count/0" do
    test "returns 10000" do
      assert NameGenerator.combination_count() == 10000
    end
  end
end
