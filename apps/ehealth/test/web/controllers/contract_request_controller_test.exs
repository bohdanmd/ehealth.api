defmodule EHealth.Web.ContractRequestControllerTest do
  @moduledoc false

  use EHealth.Web.ConnCase
  alias EHealth.ContractRequests.ContractRequest
  alias EHealth.Employees.Employee
  alias EHealth.LegalEntities.LegalEntity
  alias Ecto.UUID
  import Mox
  import EHealth.MockServer, only: [get_client_admin: 0]

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

  describe "update contract_request" do
    test "user is not NHS ADMIN SIGNER", %{conn: conn} do
      contract_request = insert(:il, :contract_request)

      expect(MithrilMock, :get_user_roles, fn _, _, _ ->
        {:ok, %{"data" => [%{"role_name" => "OWNER"}]}}
      end)

      legal_entity = insert(:prm, :legal_entity)
      conn = put_client_id_header(conn, legal_entity.id)

      conn =
        patch(conn, contract_request_path(conn, :update, contract_request.id), %{
          "nhs_signer_base" => "на підставі наказу",
          "nhs_contract_price" => 50_000,
          "nhs_payment_method" => "prepayment"
        })

      assert json_response(conn, 403)
    end

    test "no contract_request found", %{conn: conn} do
      expect(MithrilMock, :get_user_roles, fn _, _, _ ->
        {:ok, %{"data" => [%{"role_name" => "NHS ADMIN SIGNER"}]}}
      end)

      legal_entity = insert(:prm, :legal_entity)
      conn = put_client_id_header(conn, legal_entity.id)

      conn =
        patch(conn, contract_request_path(conn, :update, UUID.generate()), %{
          "nhs_signer_base" => "на підставі наказу",
          "nhs_contract_price" => 50_000,
          "nhs_payment_method" => "prepayment"
        })

      assert json_response(conn, 404)
    end

    test "contract_request has wrong status", %{conn: conn} do
      contract_request = insert(:il, :contract_request, status: ContractRequest.status(:signed))

      expect(MithrilMock, :get_user_roles, fn _, _, _ ->
        {:ok, %{"data" => [%{"role_name" => "NHS ADMIN SIGNER"}]}}
      end)

      legal_entity = insert(:prm, :legal_entity)
      conn = put_client_id_header(conn, legal_entity.id)

      conn =
        patch(conn, contract_request_path(conn, :update, contract_request.id), %{
          "nhs_signer_base" => "на підставі наказу",
          "nhs_contract_price" => 50_000,
          "nhs_payment_method" => "prepayment"
        })

      assert resp = json_response(conn, 422)

      assert %{
               "invalid" => [
                 %{"entry_type" => "request", "rules" => [%{"rule" => "json"}]}
               ],
               "message" => "Incorrect status of contract_request to modify it",
               "type" => "request_malformed"
             } = resp["error"]
    end

    test "success update contract_request", %{conn: conn} do
      contract_request = insert(:il, :contract_request)

      expect(MithrilMock, :get_user_roles, fn _, _, _ ->
        {:ok, %{"data" => [%{"role_name" => "NHS ADMIN SIGNER"}]}}
      end)

      legal_entity = insert(:prm, :legal_entity)
      conn = put_client_id_header(conn, legal_entity.id)

      conn =
        patch(conn, contract_request_path(conn, :update, contract_request.id), %{
          "nhs_signer_base" => "на підставі наказу",
          "nhs_contract_price" => 50_000,
          "nhs_payment_method" => "prepayment"
        })

      assert resp = json_response(conn, 200)

      schema =
        "specs/json_schemas/contract_request/contract_request_show_response.json"
        |> File.read!()
        |> Poison.decode!()

      assert :ok = NExJsonSchema.Validator.validate(schema, resp["data"])
    end
  end

  describe "show contract_request details" do
    setup %{conn: conn} do
      %{id: legal_entity_id_1} = insert(:prm, :legal_entity, type: "MSP")
      %{id: contract_request_id_1} = insert(:il, :contract_request, contractor_legal_entity_id: legal_entity_id_1)

      %{id: legal_entity_id_2} = insert(:prm, :legal_entity, type: "MSP")
      %{id: contract_request_id_2} = insert(:il, :contract_request, contractor_legal_entity_id: legal_entity_id_2)

      {:ok,
       %{
         conn: conn,
         legal_entity_id_1: legal_entity_id_1,
         contract_request_id_1: contract_request_id_1,
         contract_request_id_2: contract_request_id_2
       }}
    end

    test "success showing data for correct MPS client", %{conn: conn} = context do
      assert conn
             |> put_client_id_header(context.legal_entity_id_1)
             |> get(contract_request_path(conn, :show, context.contract_request_id_1))
             |> json_response(200)
    end

    test "denied showing data for uncorrect MPS client", %{conn: conn} = context do
      assert conn
             |> put_client_id_header(context.legal_entity_id_1)
             |> get(contract_request_path(conn, :show, context.contract_request_id_2))
             |> json_response(403)
    end

    test "contract_request not found", %{conn: conn} = context do
      assert conn
             |> put_client_id_header(context.legal_entity_id_1)
             |> get(contract_request_path(conn, :show, UUID.generate()))
             |> json_response(404)
    end

    test "success showing any contract_request for NHS ADMIN client", %{conn: conn} = context do
      assert conn
             |> put_client_id_header(get_client_admin())
             |> get(contract_request_path(conn, :show, context.contract_request_id_1))
             |> json_response(200)

      assert conn
             |> put_client_id_header(get_client_admin())
             |> get(contract_request_path(conn, :show, context.contract_request_id_2))
             |> json_response(200)
    end

    test "contract_request not found for NHS ADMIN client", %{conn: conn} do
      assert conn
             |> put_client_id_header(get_client_admin())
             |> get(contract_request_path(conn, :show, UUID.generate()))
             |> json_response(404)
    end
  end

  describe "approve contract_request" do
    test "user is not NHS ADMIN SIGNER", %{conn: conn} do
      contract_request = insert(:il, :contract_request)

      expect(MithrilMock, :get_user_roles, fn _, _, _ ->
        {:ok, %{"data" => [%{"role_name" => "OWNER"}]}}
      end)

      legal_entity = insert(:prm, :legal_entity)
      conn = put_client_id_header(conn, legal_entity.id)
      conn = patch(conn, contract_request_path(conn, :approve, contract_request.id))
      assert json_response(conn, 403)
    end

    test "no contract_request found", %{conn: conn} do
      expect(MithrilMock, :get_user_roles, fn _, _, _ ->
        {:ok, %{"data" => [%{"role_name" => "NHS ADMIN SIGNER"}]}}
      end)

      legal_entity = insert(:prm, :legal_entity)
      conn = put_client_id_header(conn, legal_entity.id)
      conn = patch(conn, contract_request_path(conn, :approve, UUID.generate()))
      assert json_response(conn, 404)
    end

    test "contract_request has wrong status", %{conn: conn} do
      contract_request = insert(:il, :contract_request, status: ContractRequest.status(:signed))

      expect(MithrilMock, :get_user_roles, fn _, _, _ ->
        {:ok, %{"data" => [%{"role_name" => "NHS ADMIN SIGNER"}]}}
      end)

      legal_entity = insert(:prm, :legal_entity)
      conn = put_client_id_header(conn, legal_entity.id)
      conn = patch(conn, contract_request_path(conn, :approve, contract_request.id))
      assert resp = json_response(conn, 422)

      assert %{
               "invalid" => [
                 %{"entry_type" => "request", "rules" => [%{"rule" => "json"}]}
               ],
               "message" => "Incorrect status of contract_request to modify it",
               "type" => "request_malformed"
             } = resp["error"]
    end

    test "contractor_legal_entity not found", %{conn: conn} do
      expect(MithrilMock, :get_user_roles, fn _, _, _ ->
        {:ok, %{"data" => [%{"role_name" => "NHS ADMIN SIGNER"}]}}
      end)

      legal_entity = insert(:prm, :legal_entity)
      contract_request = insert(:il, :contract_request, contractor_legal_entity_id: UUID.generate())
      conn = put_client_id_header(conn, legal_entity.id)
      conn = patch(conn, contract_request_path(conn, :approve, contract_request.id))
      assert resp = json_response(conn, 422)

      assert %{
               "invalid" => [
                 %{
                   "entry" => "$.contractor_legal_entity_id",
                   "entry_type" => "json_data_property",
                   "rules" => [
                     %{
                       "description" => "Legal entity not found",
                       "params" => [],
                       "rule" => "invalid"
                     }
                   ]
                 }
               ]
             } = resp["error"]
    end

    test "contractor_legal_entity is not active", %{conn: conn} do
      expect(MithrilMock, :get_user_roles, fn _, _, _ ->
        {:ok, %{"data" => [%{"role_name" => "NHS ADMIN SIGNER"}]}}
      end)

      legal_entity = insert(:prm, :legal_entity, status: LegalEntity.status(:closed))
      contract_request = insert(:il, :contract_request, contractor_legal_entity_id: legal_entity.id)
      legal_entity = insert(:prm, :legal_entity)
      conn = put_client_id_header(conn, legal_entity.id)
      conn = patch(conn, contract_request_path(conn, :approve, contract_request.id))
      assert resp = json_response(conn, 422)

      assert %{
               "invalid" => [
                 %{
                   "entry" => "$.contractor_legal_entity_id",
                   "entry_type" => "json_data_property",
                   "rules" => [
                     %{
                       "description" => "Legal entity in contract request should be active",
                       "params" => [],
                       "rule" => "invalid"
                     }
                   ]
                 }
               ]
             } = resp["error"]
    end

    test "contractor_owner_id not found", %{conn: conn} do
      expect(MithrilMock, :get_user_roles, fn _, _, _ ->
        {:ok, %{"data" => [%{"role_name" => "NHS ADMIN SIGNER"}]}}
      end)

      legal_entity = insert(:prm, :legal_entity)

      contract_request =
        insert(
          :il,
          :contract_request,
          contractor_legal_entity_id: legal_entity.id,
          contractor_owner_id: UUID.generate()
        )

      conn = put_client_id_header(conn, legal_entity.id)
      conn = patch(conn, contract_request_path(conn, :approve, contract_request.id))
      assert resp = json_response(conn, 422)

      assert %{
               "invalid" => [
                 %{
                   "entry" => "$.employee_id",
                   "entry_type" => "json_data_property",
                   "rules" => [
                     %{
                       "description" => "Employee not found",
                       "params" => [],
                       "rule" => "invalid"
                     }
                   ]
                 }
               ]
             } = resp["error"]
    end

    test "contractor_owner_id has invalid status", %{conn: conn} do
      expect(MithrilMock, :get_user_roles, fn _, _, _ ->
        {:ok, %{"data" => [%{"role_name" => "NHS ADMIN SIGNER"}]}}
      end)

      legal_entity = insert(:prm, :legal_entity)
      employee = insert(:prm, :employee, status: Employee.status(:new))

      contract_request =
        insert(
          :il,
          :contract_request,
          contractor_legal_entity_id: legal_entity.id,
          contractor_owner_id: employee.id
        )

      conn = put_client_id_header(conn, legal_entity.id)
      conn = patch(conn, contract_request_path(conn, :approve, contract_request.id))
      assert resp = json_response(conn, 422)

      assert %{
               "invalid" => [
                 %{
                   "entry" => "$.contractor_owner_id",
                   "entry_type" => "json_data_property",
                   "rules" => [
                     %{
                       "description" =>
                         "Contractor owner must be active within current legal entity in contract request",
                       "params" => [],
                       "rule" => "invalid"
                     }
                   ]
                 }
               ]
             } = resp["error"]
    end

    test "employee legal_entity_id doesn't match contractor_legal_entity_id", %{conn: conn} do
      expect(MithrilMock, :get_user_roles, fn _, _, _ ->
        {:ok, %{"data" => [%{"role_name" => "NHS ADMIN SIGNER"}]}}
      end)

      legal_entity = insert(:prm, :legal_entity)
      employee = insert(:prm, :employee)

      contract_request =
        insert(
          :il,
          :contract_request,
          contractor_legal_entity_id: legal_entity.id,
          contractor_owner_id: employee.id
        )

      conn = put_client_id_header(conn, legal_entity.id)
      conn = patch(conn, contract_request_path(conn, :approve, contract_request.id))
      assert resp = json_response(conn, 422)

      assert %{
               "invalid" => [
                 %{
                   "entry" => "$.contractor_owner_id",
                   "entry_type" => "json_data_property",
                   "rules" => [
                     %{
                       "description" =>
                         "Contractor owner must be active within current legal entity in contract request",
                       "params" => [],
                       "rule" => "invalid"
                     }
                   ]
                 }
               ]
             } = resp["error"]
    end

    test "employee is not owner", %{conn: conn} do
      expect(MithrilMock, :get_user_roles, fn _, _, _ ->
        {:ok, %{"data" => [%{"role_name" => "NHS ADMIN SIGNER"}]}}
      end)

      legal_entity = insert(:prm, :legal_entity)
      employee = insert(:prm, :employee, legal_entity_id: legal_entity.id)

      contract_request =
        insert(
          :il,
          :contract_request,
          contractor_legal_entity_id: legal_entity.id,
          contractor_owner_id: employee.id
        )

      conn = put_client_id_header(conn, legal_entity.id)
      conn = patch(conn, contract_request_path(conn, :approve, contract_request.id))
      assert resp = json_response(conn, 422)

      assert %{
               "invalid" => [
                 %{
                   "entry" => "$.contractor_owner_id",
                   "entry_type" => "json_data_property",
                   "rules" => [
                     %{
                       "description" =>
                         "Contractor owner must be active within current legal entity in contract request",
                       "params" => [],
                       "rule" => "invalid"
                     }
                   ]
                 }
               ]
             } = resp["error"]
    end

    test "external contractor division is not present in employee divisions", %{conn: conn} do
      expect(MithrilMock, :get_user_roles, fn _, _, _ ->
        {:ok, %{"data" => [%{"role_name" => "NHS ADMIN SIGNER"}]}}
      end)

      legal_entity = insert(:prm, :legal_entity)
      employee = insert(:prm, :employee, legal_entity_id: legal_entity.id, employee_type: Employee.type(:owner))

      contract_request =
        insert(
          :il,
          :contract_request,
          contractor_legal_entity_id: legal_entity.id,
          contractor_owner_id: employee.id,
          contractor_employee_divisions: [
            %{division_id: UUID.generate(), employee_id: employee.id}
          ]
        )

      conn = put_client_id_header(conn, legal_entity.id)
      conn = patch(conn, contract_request_path(conn, :approve, contract_request.id))
      assert resp = json_response(conn, 422)

      assert %{
               "invalid" => [
                 %{
                   "entry" => "$.contractor_employee_divisions.employee_id",
                   "entry_type" => "json_data_property",
                   "rules" => [
                     %{
                       "description" => "Employee must be active DOCTOR with linked division",
                       "params" => [],
                       "rule" => "invalid"
                     }
                   ]
                 }
               ]
             } = resp["error"]
    end

    test "invalid start date", %{conn: conn} do
      expect(MithrilMock, :get_user_roles, fn _, _, _ ->
        {:ok, %{"data" => [%{"role_name" => "NHS ADMIN SIGNER"}]}}
      end)

      legal_entity = insert(:prm, :legal_entity)
      employee_owner = insert(:prm, :employee, legal_entity_id: legal_entity.id, employee_type: Employee.type(:owner))
      division = insert(:prm, :division, legal_entity: legal_entity)
      employee_doctor = insert(:prm, :employee, legal_entity_id: legal_entity.id, division: division)
      now = Date.utc_today()
      start_date = Date.add(now, 3650)

      contract_request =
        insert(
          :il,
          :contract_request,
          contractor_legal_entity_id: legal_entity.id,
          contractor_owner_id: employee_owner.id,
          start_date: start_date,
          contractor_employee_divisions: [
            %{
              "employee_id" => employee_doctor.id,
              "staff_units" => 0.5,
              "declaration_limit" => 2000,
              "division_id" => division.id
            }
          ]
        )

      conn = put_client_id_header(conn, legal_entity.id)
      conn = patch(conn, contract_request_path(conn, :approve, contract_request.id))
      assert resp = json_response(conn, 422)

      assert %{
               "invalid" => [
                 %{
                   "entry" => "$.start_date",
                   "entry_type" => "json_data_property",
                   "rules" => [
                     %{
                       "description" => "Start date must be within this or next year",
                       "params" => [],
                       "rule" => "invalid"
                     }
                   ]
                 }
               ]
             } = resp["error"]
    end

    test "success approve contract request", %{conn: conn} do
      expect(MithrilMock, :get_user_roles, fn _, _, _ ->
        {:ok, %{"data" => [%{"role_name" => "NHS ADMIN SIGNER"}]}}
      end)

      legal_entity = insert(:prm, :legal_entity)
      employee_owner = insert(:prm, :employee, legal_entity_id: legal_entity.id, employee_type: Employee.type(:owner))
      division = insert(:prm, :division, legal_entity: legal_entity)
      employee_doctor = insert(:prm, :employee, legal_entity_id: legal_entity.id, division: division)
      now = Date.utc_today()
      start_date = Date.add(now, 10)

      contract_request =
        insert(
          :il,
          :contract_request,
          contractor_legal_entity_id: legal_entity.id,
          contractor_owner_id: employee_owner.id,
          contractor_employee_divisions: [
            %{
              "employee_id" => employee_doctor.id,
              "staff_units" => 0.5,
              "declaration_limit" => 2000,
              "division_id" => division.id
            }
          ],
          start_date: start_date
        )

      conn = put_client_id_header(conn, legal_entity.id)
      conn = patch(conn, contract_request_path(conn, :approve, contract_request.id))
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
