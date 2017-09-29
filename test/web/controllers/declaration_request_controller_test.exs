defmodule EHealth.Web.DeclarationRequestControllerTest do
  @moduledoc false

  use EHealth.Web.ConnCase

  import EHealth.SimpleFactory

  alias Ecto.UUID
  alias EHealth.DeclarationRequest

  describe "list declaration requests" do
    test "no legal_entity_id match", %{conn: conn} do
      legal_entity_id = UUID.generate()
      Enum.map(1..2, fn _ ->
        fixture(DeclarationRequest, fixture_params())
      end)
      conn = put_client_id_header(conn, legal_entity_id)
      conn = get conn, declaration_request_path(conn, :index)
      resp = json_response(conn, 200)

      assert_count_declaration_request_list(resp)
    end

    test "match by legal_entity_id", %{conn: conn} do
      legal_entity_id = UUID.generate()
      employee_id = UUID.generate()
      params =
        fixture_params()
        |> put_in([:data, :employee, :id], employee_id)
        |> put_in([:data, :legal_entity, :id], legal_entity_id)
      Enum.map(1..2, fn _ ->
        fixture(DeclarationRequest, params)
      end)

      conn = put_client_id_header(conn, legal_entity_id)
      conn = get conn, declaration_request_path(conn, :index)
      resp = json_response(conn, 200)

      assert_count_declaration_request_list(resp, 2)
    end

    test "no employee_id match", %{conn: conn} do
      legal_entity_id = UUID.generate()
      employee_id = UUID.generate()
      params =
        fixture_params()
        |> put_in([:data, :legal_entity, :id], legal_entity_id)
      Enum.map(1..2, fn _ ->
        fixture(DeclarationRequest, params)
      end)
      conn = put_client_id_header(conn, legal_entity_id)
      conn = get conn, declaration_request_path(conn, :index, %{employee_id: employee_id})
      resp = json_response(conn, 200)

      assert_count_declaration_request_list(resp)
    end

    test "match by employee_id", %{conn: conn} do
      legal_entity_id = UUID.generate()
      employee_id = UUID.generate()
      params =
        fixture_params()
        |> put_in([:data, :legal_entity, :id], legal_entity_id)
        |> put_in([:data, :employee, :id], employee_id)
      Enum.map(1..2, fn _ ->
        fixture(DeclarationRequest, params)
      end)
      conn = put_client_id_header(conn, legal_entity_id)
      conn = get conn, declaration_request_path(conn, :index, %{employee_id: employee_id})
      resp = json_response(conn, 200)

      assert_count_declaration_request_list(resp, 2)
    end

    test "no status match", %{conn: conn} do
      legal_entity_id = UUID.generate()
      params =
        fixture_params()
        |> put_in([:data, :legal_entity, :id], legal_entity_id)
      Enum.map(1..2, fn _ ->
        fixture(DeclarationRequest, params)
      end)
      conn = put_client_id_header(conn, legal_entity_id)
      conn = get conn, declaration_request_path(conn, :index, %{status: "ACTIVE"})
      resp = json_response(conn, 200)

      assert_count_declaration_request_list(resp)
    end

    test "match by status", %{conn: conn} do
      legal_entity_id = UUID.generate()
      status = "ACTIVE"
      params =
        fixture_params()
        |> put_in([:data, :legal_entity, :id], legal_entity_id)
        |> put_in([:status], status)
      Enum.map(1..2, fn _ ->
        fixture(DeclarationRequest, params)
      end)
      conn = put_client_id_header(conn, legal_entity_id)
      conn = get conn, declaration_request_path(conn, :index, %{status: status})
      resp = json_response(conn, 200)

      assert_count_declaration_request_list(resp, 2)
    end

    test "match by legal_entity_id, employee_id, status", %{conn: conn} do
      legal_entity_id = UUID.generate()
      employee_id = UUID.generate()
      status = "ACTIVE"
      params =
        fixture_params()
        |> put_in([:data, :legal_entity, :id], legal_entity_id)
        |> put_in([:data, :employee, :id], employee_id)
        |> put_in([:status], status)
      Enum.map(1..2, fn _ ->
        fixture(DeclarationRequest, params)
      end)

      conn = put_client_id_header(conn, legal_entity_id)
      conn = get conn, declaration_request_path(conn, :index, %{
        status: status,
        employee_id: employee_id
      })
      resp = json_response(conn, 200)

      assert_count_declaration_request_list(resp, 2)
    end
  end

  describe "approve declaration_request" do
    test "approve NEW declaration_request", %{conn: conn} do
      declaration_request = fixture(DeclarationRequest, fixture_params())

      conn = put_client_id_header(conn, "356b4182-f9ce-4eda-b6af-43d2de8602f2")
      conn = patch conn, declaration_request_path(conn, :approve, declaration_request)

      resp = json_response(conn, 200)
      assert DeclarationRequest.status(:approved) == resp["data"]["status"]
    end

    test "approve APPROVED declaration_request", %{conn: conn} do
      params = Map.put(fixture_params(), :status, DeclarationRequest.status(:approved))
      declaration_request = fixture(DeclarationRequest, params)

      conn = put_client_id_header(conn, "356b4182-f9ce-4eda-b6af-43d2de8602f2")
      conn = patch conn, declaration_request_path(conn, :approve, declaration_request)

      resp = json_response(conn, 409)
      assert "Invalid transition" == get_in(resp, ["error", "message"])
    end
  end

  describe "get declaration request by id" do
    defmodule DynamicSeedValue do
      use MicroservicesHelper

      Plug.Router.get "/latest_block" do
        block = %{
          "block_start" => "some_time",
          "block_end" => "some_time",
          "hash" => "some_hash",
          "inserted_at" => "some_time"
        }

        Plug.Conn.send_resp(conn, 200, Poison.encode!(%{data: block}))
      end
    end

    setup do
      {:ok, port, ref} = start_microservices(DynamicSeedValue)
      System.put_env("OPS_ENDPOINT", "http://localhost:#{port}")
      on_exit fn ->
        System.put_env("OPS_ENDPOINT", "http://localhost:4040")
        stop_microservices(ref)
      end
    end

    test "get declaration request by invalid id", %{conn: conn} do
      conn = put_client_id_header(conn, "356b4182-f9ce-4eda-b6af-43d2de8602f2")
      assert_raise Ecto.NoResultsError, fn ->
        get conn, declaration_request_path(conn, :show, UUID.generate())
      end
    end

    test "get declaration request by invalid legal_entity_id", %{conn: conn} do
      %{id: id} = fixture(DeclarationRequest, fixture_params())
      conn = put_client_id_header(conn, UUID.generate)
      assert_raise Ecto.NoResultsError, fn ->
        get conn, declaration_request_path(conn, :show, id)
      end
    end

    test "get declaration request by id", %{conn: conn} do
      %{id: id, data: data} = fixture(DeclarationRequest, fixture_params())
      conn = put_client_id_header(conn, get_in(data, [:legal_entity, :id]))
      conn = get conn, declaration_request_path(conn, :show, id)
      resp = json_response(conn, 200)

      assert Map.has_key?(resp, "data")
      assert Map.has_key?(resp, "urgent")
      assert "some_hash" == get_in resp, ["data", "seed"]
    end
  end

  describe "resend otp" do
    defmodule OTPVerificationMock do
      use MicroservicesHelper

      Plug.Router.post "/verifications" do
        send_resp(conn, 200, Poison.encode!(%{status: "NEW"}))
      end
    end

    setup do
      {:ok, port, ref} = start_microservices(OTPVerificationMock)

      System.put_env("OTP_VERIFICATION_ENDPOINT", "http://localhost:#{port}")
      on_exit fn ->
        System.put_env("OTP_VERIFICATION_ENDPOINT", "http://localhost:4040")
        stop_microservices(ref)
      end

      :ok
    end

    test "when declaration request id is invalid", %{conn: conn} do
      conn = put_client_id_header(conn, UUID.generate)
      assert_raise Ecto.NoResultsError, fn ->
        post conn, declaration_request_path(conn, :resend_otp, UUID.generate())
      end
    end

    test "when declaration request status is not NEW", %{conn: conn} do
      conn = put_client_id_header(conn, UUID.generate)

      params =
        fixture_params()
        |> Map.put(:status, "APPROVED")

      %{id: id} = fixture(DeclarationRequest, params)

      conn = post conn, declaration_request_path(conn, :resend_otp, id)
      resp = json_response(conn, 422)
      assert Map.has_key?(resp, "error")
      error = resp["error"]
      assert Map.has_key?(error, "invalid")
      assert 1 == length(error["invalid"])
      invalid = Enum.at(error["invalid"], 0)
      assert "$.status" == invalid["entry"]
      assert 1 == length(invalid["rules"])
      rule = Enum.at(invalid["rules"], 0)
      assert "incorrect status" == rule["description"]
    end

    test "when declaration request auth method is not OTP", %{conn: conn} do
      conn = put_client_id_header(conn, UUID.generate)

      params =
        fixture_params()
        |> Map.put(:authentication_method_current, %{type: "OFFLINE"})

      %{id: id} = fixture(DeclarationRequest, params)

      conn = post conn, declaration_request_path(conn, :resend_otp, id)
      resp = json_response(conn, 422)
      assert Map.has_key?(resp, "error")
      error = resp["error"]
      assert Map.has_key?(error, "invalid")
      assert 1 == length(error["invalid"])
      invalid = Enum.at(error["invalid"], 0)
      assert "$.authentication_method_current" == invalid["entry"]
      assert 1 == length(invalid["rules"])
      rule = Enum.at(invalid["rules"], 0)
      assert "Auth method is not OTP" == rule["description"]
    end

    test "when declaration request fields are correct", %{conn: conn} do
      conn = put_client_id_header(conn, UUID.generate)

      params =
        fixture_params()
        |> Map.put(:authentication_method_current, %{type: "OTP", number: 111})

      %{id: id} = fixture(DeclarationRequest, params)

      conn = post conn, declaration_request_path(conn, :resend_otp, id)
      resp = json_response(conn, 200)
      assert Map.has_key?(resp, "data")
      assert %{"status" => "NEW"} == resp["data"]
    end
  end

  describe "get documents" do
    defmodule MediaContentStorageMock do
      use MicroservicesHelper

      Plug.Router.post "/media_content_storage_secrets" do
        params = conn.body_params["secret"]

        data = %{
          data: %{
            secret_url: "http://a.link.for/#{params["resource_id"]}/#{params["resource_name"]}"
          }
        }

        Plug.Conn.send_resp(conn, 200, Poison.encode!(data))
      end
    end

    setup do
      {:ok, port, ref} = start_microservices(MediaContentStorageMock)

      System.put_env("MEDIA_STORAGE_ENDPOINT", "http://localhost:#{port}")
      on_exit fn ->
        System.put_env("MEDIA_STORAGE_ENDPOINT", "http://localhost:4040")
        stop_microservices(ref)
      end

      :ok
    end

    test "when declaration id is invalid", %{conn: conn} do
      assert_raise Ecto.NoResultsError, fn ->
        get conn, declaration_request_path(conn, :documents, UUID.generate())
      end
    end

    test "when declaration id is valid", %{conn: conn} do
      %{id: id, declaration_id: declaration_id} = fixture(DeclarationRequest, fixture_params())

      conn = get conn, declaration_request_path(conn, :documents, declaration_id)
      result = json_response(conn, 200)["data"]
      expected_result = [
        %{
          "type" => "person.PASSPORT",
          "url" => "http://a.link.for/#{id}/declaration_request_person.PASSPORT.jpeg"
        },
        %{
          "type" => "confidant_person.0.PRIMARY.RELATIONSHIP.COURT_DECISION",
          "url" => "http://a.link.for/#{id}/declaration_request_confidant_person.0.PRIMARY.RELATIONSHIP.COURT_DECISION.jpeg"
        },
      ]
      assert expected_result == result
    end
  end

  defp fixture_params do
    uuid = UUID.generate()
    %{
      data: %{
        id: UUID.generate(),
        start_date: "2017-03-02",
        end_date: "2017-03-02",
        person: %{
          id: UUID.generate(),
          first_name: "Петро",
          last_name: "Іванов",
          second_name: "Миколайович",
          documents: [
            %{
              type: "PASSPORT",
              number: "120518"
            }
          ],
          confidant_person: [
            %{
              relation_type: "PRIMARY",
              first_name: "Іван",
              last_name: "Петров",
              second_name: "Миколайович",
              birth_date: "1991-08-20",
              birth_country: "Україна",
              birth_settlement: "Вінниця",
              gender: "MALE",
              tax_id: "2222222225",
              documents_person: [
                %{
                  type: "PASSPORT",
                  number: "120518"
                }
              ],
              documents_relationship: [
                %{
                  type: "COURT_DECISION",
                  number: "120518"
                }
              ],
              phones: [
                %{
                  type: "MOBILE",
                  number: "+380503410870"
                }
              ]
            }
          ]
        },
        employee: %{
          id: UUID.generate(),
          position: "P6",
          party: %{
            id: UUID.generate(),
            first_name: "Петро",
            last_name: "Іванов",
            second_name: "Миколайович",
            email: "email@example.com",
            phones: [
              %{
                type: "MOBILE",
                number: "+380503410870"
              }
            ],
            tax_id: "12345678"
          },
        },
        legal_entity: %{
          id: UUID.generate(),
          name: "Клініка Борис",
          short_name: "Борис",
          legal_form: "140",
          edrpou: "5432345432",
        },
        division: %{
          id: UUID.generate(),
          name: "Бориспільське відділення Клініки Борис",
          type: "CLINIC",
          status: "NEW"
        }
      },
      status: "NEW",
      inserted_by: uuid,
      updated_by: uuid,
      authentication_method_current: %{"type" => "NA"},
      printout_content: "",
      declaration_id: UUID.generate()
    }
  end

  defp assert_count_declaration_request_list(resp, count \\ 0) do
    schema =
      "test/data/declaration_request/index_api_response_schema.json"
      |> File.read!()
      |> Poison.decode!()
    :ok = NExJsonSchema.Validator.validate(schema, resp["data"])

    assert Map.has_key?(resp, "data")
    assert Map.has_key?(resp, "paging")
    assert is_list(resp["data"])
    assert count == length(resp["data"])
  end
end
