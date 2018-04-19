defmodule EHealth.Web.ContractRequestControllerTest do
  @moduledoc false

  use EHealth.Web.ConnCase
  alias Ecto.UUID
  import Mox

  describe "create contract request" do
    test "user is not owner", %{conn: conn} do
      %{legal_entity: legal_entity, division: division, employee: employee} = prepare_data("DOCTOR")
      params = prepare_params(legal_entity, division, employee)
      conn = put_client_id_header(conn, legal_entity.id)
      conn = post(conn, contract_request_path(conn, :create), params)
      assert json_response(conn, 403)
    end

    test "employee division is not active", %{conn: conn} do
      %{legal_entity: legal_entity, employee: employee} = prepare_data()
      division = insert(:prm, :division)
      conn = put_client_id_header(conn, legal_entity.id)
      params = prepare_params(legal_entity, division, employee)
      conn = post(conn, contract_request_path(conn, :create), params)
      resp = json_response(conn, 422)

      assert_error(
        resp,
        "$.contractor_employee_divisions[0].division_id",
        "Division must be active and within current legal_entity"
      )
    end

    test "external contractor division is not present in employee divisions", %{conn: conn} do
      %{legal_entity: legal_entity, division: division, employee: employee} = prepare_data()
      conn = put_client_id_header(conn, legal_entity.id)

      params =
        legal_entity
        |> prepare_params(division, employee)
        |> Map.delete("external_contractor_flag")
        |> Map.put("external_contractors", [
          %{"divisions" => [%{"id" => UUID.generate()}]}
        ])

      conn = post(conn, contract_request_path(conn, :create), params)
      assert resp = json_response(conn, 422)

      assert_error(
        resp,
        "$.external_contractors[0].divisions[0].id",
        "The division is not belong to contractor_employee_divisions"
      )
    end

    test "invalid expires_at date", %{conn: conn} do
      %{legal_entity: legal_entity, division: division, employee: employee} = prepare_data()
      conn = put_client_id_header(conn, legal_entity.id)

      params =
        legal_entity
        |> prepare_params(division, employee, "2018-01-01")
        |> Map.put("start_date", "2018-02-01")
        |> Map.delete("external_contractor_flag")

      conn = post(conn, contract_request_path(conn, :create), params)
      assert resp = json_response(conn, 422)

      assert_error(
        resp,
        "$.external_contractors[0].contract.expires_at",
        "Expires date must be greater than contract start_date"
      )
    end

    test "invalid external_contractor_flag", %{conn: conn} do
      %{legal_entity: legal_entity, division: division, employee: employee} = prepare_data()
      conn = put_client_id_header(conn, legal_entity.id)

      params =
        legal_entity
        |> prepare_params(division, employee, "2018-03-01")
        |> Map.put("start_date", "2018-02-01")
        |> Map.delete("external_contractor_flag")

      conn = post(conn, contract_request_path(conn, :create), params)
      assert resp = json_response(conn, 422)
      assert_error(resp, "$.external_contractor_flag", "Invalid external_contractor_flag")
    end

    test "start_date is in the past", %{conn: conn} do
      %{legal_entity: legal_entity, division: division, employee: employee} = prepare_data()
      conn = put_client_id_header(conn, legal_entity.id)

      params =
        legal_entity
        |> prepare_params(division, employee, "2018-03-01")
        |> Map.put("start_date", "2018-02-01")

      conn = post(conn, contract_request_path(conn, :create), params)
      assert resp = json_response(conn, 422)
      assert_error(resp, "$.start_date", "Start date must be greater than create date")
    end

    test "start_date is too far in the future", %{conn: conn} do
      %{legal_entity: legal_entity, division: division, employee: employee} = prepare_data()
      conn = put_client_id_header(conn, legal_entity.id)
      now = Date.utc_today()
      start_date = Date.add(now, 3650)

      params =
        legal_entity
        |> prepare_params(division, employee, Date.to_iso8601(Date.add(start_date, 1)))
        |> Map.put("start_date", Date.to_iso8601(start_date))

      conn = post(conn, contract_request_path(conn, :create), params)
      assert resp = json_response(conn, 422)
      assert_error(resp, "$.start_date", "Start date must be within this or next year")
    end

    test "invalid end_date", %{conn: conn} do
      %{legal_entity: legal_entity, division: division, employee: employee} = prepare_data()
      conn = put_client_id_header(conn, legal_entity.id)
      now = Date.utc_today()
      start_date = Date.add(now, 10)

      params =
        legal_entity
        |> prepare_params(division, employee, Date.to_iso8601(Date.add(start_date, 1)))
        |> Map.put("start_date", Date.to_iso8601(start_date))
        |> Map.put("end_date", Date.to_iso8601(Date.add(now, 365 * 3)))

      conn = post(conn, contract_request_path(conn, :create), params)
      assert resp = json_response(conn, 422)
      assert_error(resp, "$.end_date", "The year of start_date and and date must be equal")
    end

    test "success create contract request", %{conn: conn} do
      %{legal_entity: legal_entity, division: division, employee: employee} = prepare_data()
      conn = put_client_id_header(conn, legal_entity.id)
      now = Date.utc_today()
      start_date = Date.add(now, 10)

      params =
        legal_entity
        |> prepare_params(division, employee, Date.to_iso8601(Date.add(start_date, 1)))
        |> Map.put("start_date", Date.to_iso8601(start_date))
        |> Map.put("end_date", Date.to_iso8601(Date.add(now, 30)))

      conn = post(conn, contract_request_path(conn, :create), params)
      assert resp = json_response(conn, 200)

      schema =
        "specs/json_schemas/contract_request/contract_request_show_response.json"
        |> File.read!()
        |> Poison.decode!()

      assert :ok = NExJsonSchema.Validator.validate(schema, resp["data"])
    end
  end

  defp prepare_data(role_name \\ "OWNER") do
    expect(MithrilMock, :get_user_roles, fn _, _, _ ->
      {:ok, %{"data" => [%{"role_name" => role_name}]}}
    end)

    legal_entity = insert(:prm, :legal_entity)
    division = insert(:prm, :division, legal_entity: legal_entity)
    employee = insert(:prm, :employee, division: division)
    %{legal_entity: legal_entity, employee: employee, division: division}
  end

  defp prepare_params(legal_entity, division, employee, expires_at \\ nil) do
    %{
      "contractor_owner_id" => UUID.generate(),
      "contractor_base" => "на підставі закону про Медичне обслуговування населення",
      "contractor_payment_details" => %{
        "bank_name" => "Банк номер 1",
        "MFO" => "351005",
        "payer_account" => "32009102701026"
      },
      "contractor_legal_entity_id" => legal_entity.id,
      "contractor_rmsp_amount" => 10,
      "id_form" => "5",
      "contractor_employee_divisions" => [
        %{
          "employee_id" => employee.id,
          "staff_units" => 0.5,
          "declaration_limit" => 2000,
          "division_id" => division.id
        }
      ],
      "external_contractors" => [
        %{
          "divisions" => [%{"id" => division.id}],
          "contract" => %{"expires_at" => expires_at}
        }
      ],
      "external_contractor_flag" => true,
      "start_date" => "2018-01-01",
      "end_date" => "2018-01-01"
    }
  end

  defp assert_error(resp, entry, description) do
    assert %{
             "type" => "validation_failed",
             "invalid" => [
               %{
                 "rules" => [
                   %{
                     "rule" => "invalid",
                     "params" => [],
                     "description" => ^description
                   }
                 ],
                 "entry_type" => "json_data_property",
                 "entry" => ^entry
               }
             ]
           } = resp["error"]
  end
end
