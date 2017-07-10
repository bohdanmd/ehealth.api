defmodule EHealth.DeclarationRequest.APITest do
  @moduledoc false

  use EHealth.Web.ConnCase, async: true
  import EHealth.DeclarationRequest.API
  import EHealth.SimpleFactory
  alias EHealth.DeclarationRequest
  alias EHealth.Repo

  describe "pending_declaration_requests/2" do
    test "returns pending requests" do
      raw_declaration_request = %{
        "person" => %{
          "tax_id" => "111"
        },
        "employee_id" => "222",
        "legal_entity_id" => "333"
      }

      {:ok, pending_declaration_req_1} = copy_declaration_request(raw_declaration_request, "NEW")
      {:ok, pending_declaration_req_2} = copy_declaration_request(raw_declaration_request, "APPROVED")

      query = pending_declaration_requests(raw_declaration_request, "333")

      assert [pending_declaration_req_1, pending_declaration_req_2] == Repo.all(query)
    end
  end

  def copy_declaration_request(template, status) do
    attrs = %{
      "status" => status,
      "data" => %{
        "person" => %{
          "tax_id" => get_in(template, ["person", "tax_id"])
        },
        "employee_id" => get_in(template, ["employee_id"]),
        "legal_entity_id" => get_in(template, ["legal_entity_id"])
      },
      "authentication_method_current" => %{
        "number" => "+380508887700",
        "type" => "OTP"
      },
      "documents" => [],
      "printout_content" => "Some fake content",
      "inserted_by" => Ecto.UUID.generate(),
      "updated_by" => Ecto.UUID.generate()
    }

    allowed =
      attrs
      |> Map.keys
      |> Enum.map(&String.to_atom(&1))

    %DeclarationRequest{}
    |> Ecto.Changeset.cast(attrs, allowed)
    |> Repo.insert()
  end

  test "get_declaration_request_by_id!/1" do
    %{id: id} = fixture(DeclarationRequest)
    declaration_request = get_declaration_request_by_id!(id)
    assert id == declaration_request.id
  end
end
