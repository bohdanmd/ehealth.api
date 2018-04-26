defmodule EHealth.Web.ContractControllerTest do
  @moduledoc false

  use EHealth.Web.ConnCase

  import Mox
  import EHealth.MockServer, only: [get_client_admin: 0]

  alias Ecto.UUID

  describe "show contract details" do
    setup do
      # string_params_for converts NaiveDateTime to map instead of string, so, old way
      contract_id = UUID.generate()
      contract = build(:contract, id: contract_id) |> Poison.encode!() |> Poison.decode!()

      expect(OPSMock, :get_contract, fn _, _ ->
        {:ok, %{"data" => contract}}
      end)

      {:ok, %{contract: contract, contract_id: contract_id}}
    end

    test "successfully finds contract", %{conn: conn, contract: contract, contract_id: contract_id} do
      assert %{"data" => response_data} = do_get_contract(conn, contract_id, get_client_admin())
      assert response_data["id"] == contract_id

      # add assertion with json schema
    end
  end

  defp do_get_contract(conn, contract_id, client_id) do
    conn
    |> put_client_id_header(client_id)
    |> get(contract_path(conn, :show, contract_id))
    |> json_response(200)
  end
end
