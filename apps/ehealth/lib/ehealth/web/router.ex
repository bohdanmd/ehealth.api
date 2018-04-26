defmodule EHealthWeb.Router do
  @moduledoc """
  The router provides a set of macros for generating routes
  that dispatch to specific controllers and actions.
  Those macros are named after HTTP verbs.

  More info at: https://hexdocs.pm/phoenix/Phoenix.Router.html
  """
  use EHealth.Web, :router
  use Plug.ErrorHandler

  alias Plug.LoggerJSON

  require Logger

  pipeline :api do
    plug(:accepts, ["json"])
    plug(:put_secure_browser_headers)

    # Uncomment to enable versioning of your API
    # plug Multiverse, gates: [
    #   "2016-07-31": EHealth.Web.InitialGate
    # ]

    # You can allow JSONP requests by uncommenting this line:
    # plug :allow_jsonp
  end

  # client_id = legal_entity_id
  pipeline :api_client_id do
    plug(:header_required, "x-consumer-metadata")
    plug(:client_id_exists)
  end

  # consumer_id = user_id
  pipeline :api_consumer_id do
    plug(:header_required, "x-consumer-id")
  end

  pipeline :client_context_list do
    plug(:process_client_context_for_list)
    plug(:put_is_active_into_params)
  end

  pipeline :contract_context do
    plug(:process_client_context_for_list, legal_entity_param_name: "contractor_legal_entity_id")
  end

  pipeline :cabinet do
    plug(:process_client_context_for_list, required_types: ["CABINET"])
  end

  pipeline :jwt do
    plug(Guardian.Plug.Pipeline, module: EHealth.Guardian, error_handler: EHealth.Web.FallbackController)
  end

  pipeline :jwt_registration do
    plug(Guardian.Plug.VerifyHeader, claims: %{typ: "access", aud: EHealth.Guardian.get_aud(:registration)})
    plug(Guardian.Plug.EnsureAuthenticated)
  end

  pipeline :jwt_email_verification do
    plug(Guardian.Plug.VerifyHeader, claims: %{typ: "access", aud: EHealth.Guardian.get_aud(:email_verification)})
    plug(Guardian.Plug.EnsureAuthenticated)
  end

  scope "/api", EHealth.Web do
    pipe_through(:api)

    post("/credentials_recovery_requests", UserController, :create_credentials_recovery_request)
    patch("/credentials_recovery_requests/:id/actions/reset_password", UserController, :reset_password)

    # Legal Entities
    put("/legal_entities", LegalEntityController, :create_or_update)

    get("/dictionaries", DictionaryController, :index)
    patch("/dictionaries/:name", DictionaryController, :update)

    get("/invite/:id", EmployeeRequestController, :invite)
    post("/employee_requests/:id/user", EmployeeRequestController, :create_user)

    patch("/uaddresses/settlements/:id", UaddressesController, :update_settlements)

    get("/declarations/:id/documents", DeclarationRequestController, :documents)

    # Medications
    get("/drugs", MedicationController, :drugs)

    resources("/innms", INNMController, except: [:new, :edit, :update, :delete])

    resources("/innm_dosages", INNMDosageController, except: [:new, :edit, :update, :delete])
    patch("/innm_dosages/:id/actions/deactivate", INNMDosageController, :deactivate)

    resources("/medications", MedicationController, except: [:new, :edit, :update, :delete])
    patch("/medications/:id/actions/deactivate", MedicationController, :deactivate)

    resources("/program_medications", ProgramMedicationController, except: [:new, :edit, :delete])

    resources("/medical_programs", MedicalProgramController, except: [:new, :edit, :update, :delete])
    patch("/medical_programs/:id/actions/deactivate", MedicalProgramController, :deactivate)

    # Global parameters
    get("/global_parameters", GlobalParameterController, :index)

    # Black-listed users
    resources("/black_list_users", BlackListUserController, except: [:new, :edit, :show, :update, :delete])
    patch("/black_list_users/:id/actions/deactivate", BlackListUserController, :deactivate)

    # Cabinet
    scope "/cabinet" do
      post("/email_verification", Cabinet.AuthController, :email_verification, as: :cabinet_auth)
    end

    scope "/cabinet" do
      pipe_through(:jwt)

      scope "/email_validation" do
        pipe_through(:jwt_email_verification)
        post("/", Cabinet.AuthController, :email_validation, as: :cabinet_auth)
      end

      scope "/" do
        pipe_through(:jwt_registration)
        post("/registration", Cabinet.AuthController, :registration, as: :cabinet_auth)
        post("/users", Cabinet.AuthController, :search_user, as: :cabinet_auth)
      end
    end
  end

  scope "/api", EHealth.Web do
    pipe_through([:api, :api_consumer_id])

    # Registers
    post("/registers", RegisterController, :create)
    get("/registers", RegisterController, :index)
    get("/registers_entries", RegisterEntryController, :index)
  end

  # Client context for lists
  scope "/api", EHealth.Web do
    pipe_through([:api, :api_client_id, :client_context_list])

    # Legal Entities
    get("/legal_entities", LegalEntityController, :index)
    # Employees
    get("/employees", EmployeeController, :index)
    # Employees
    get("/divisions", DivisionController, :index)
    # Declarations
    get("/declarations", DeclarationsController, :index)

    # Declaration requests
    scope "/declaration_requests" do
      get("/", DeclarationRequestController, :index)
      get("/:declaration_request_id", DeclarationRequestController, :show)
    end

    # Employee requests
    get("/employee_requests", EmployeeRequestController, :index)
    get("/employee_requests/:id", EmployeeRequestController, :show)
  end

  scope "/api", EHealth.Web do
    pipe_through([:api, :api_client_id])

    # Legal Entities
    get("/legal_entities/:id", LegalEntityController, :show)
    patch("/legal_entities/:id/actions/mis_verify", LegalEntityController, :mis_verify)
    patch("/legal_entities/:id/actions/nhs_verify", LegalEntityController, :nhs_verify)
    patch("/legal_entities/:id/actions/deactivate", LegalEntityController, :deactivate)

    # Temporary mis endpoints
    get("/mis/employee_requests/:id", MisController, :employee_request)

    # Employees
    get("/employees/:id", EmployeeController, :show)

    scope "/employees" do
      pipe_through([:client_context_list])

      patch("/:id/actions/deactivate", EmployeeController, :deactivate)
    end

    # Employee requests
    post("/employee_requests", EmployeeRequestController, :create)
    post("/employee_requests/:id/approve", EmployeeRequestController, :approve)
    post("/employee_requests/:id/reject", EmployeeRequestController, :reject)

    # Divisions
    resources("/divisions", DivisionController, except: [:index, :new, :edit, :delete])
    patch("/divisions/:id/actions/activate", DivisionController, :activate)
    patch("/divisions/:id/actions/deactivate", DivisionController, :deactivate)

    scope "/declaration_requests" do
      pipe_through([:api_consumer_id])

      patch("/:id/actions/sign", DeclarationRequestController, :sign)
    end

    post("/declaration_requests", DeclarationRequestController, :create)
    patch("/declaration_requests/:id/actions/approve", DeclarationRequestController, :approve)
    patch("/declaration_requests/:id/actions/reject", DeclarationRequestController, :reject)
    post("/declaration_requests/:id/actions/resend_otp", DeclarationRequestController, :resend_otp)

    scope "/contracts" do
      pipe_through([:contract_context])

      get("/:id", ContractController, :show)
    end

    post("/contract_requests", ContractRequestController, :create)
    patch("/contract_requests/:id", ContractRequestController, :update)
    patch("/contract_requests/:id/actions/approve", ContractRequestController, :approve)

    scope "/contract_requests" do
      pipe_through([:contract_context])

      get("/", ContractRequestController, :index)
      get("/:id", ContractRequestController, :show)
    end

    resources(
      "/medication_request_requests",
      MedicationRequestRequestController,
      except: [:new, :edit, :update, :delete]
    )

    post("/medication_request_requests/prequalify", MedicationRequestRequestController, :prequalify)
    patch("/medication_request_requests/:id/actions/reject", MedicationRequestRequestController, :reject)
    patch("/medication_request_requests/:id/actions/sign", MedicationRequestRequestController, :sign)

    # Declarations
    get("/declarations/:id", DeclarationsController, :show)
    patch("/declarations/:id/actions/approve", DeclarationsController, :approve)
    patch("/declarations/:id/actions/reject", DeclarationsController, :reject)
    patch("/declarations/terminate", DeclarationsController, :terminate)

    # Medication dispenses
    scope "/medication_dispenses" do
      pipe_through([:client_context_list])

      get("/", MedicationDispenseController, :index)
      get("/:id", MedicationDispenseController, :show)
      patch("/:id/actions/process", MedicationDispenseController, :process)
      patch("/:id/actions/reject", MedicationDispenseController, :reject)
      post("/", MedicationDispenseController, :create)
    end

    scope "/medication_requests" do
      pipe_through([:client_context_list])

      get("/", MedicationRequestController, :index)
      get("/:id", MedicationRequestController, :show)
      get("/:id/dispenses", MedicationDispenseController, :by_medication_request)
      post("/:id/actions/qualify", MedicationRequestController, :qualify)
      patch("/:id/actions/reject", MedicationRequestController, :reject)
      patch("/:id/actions/resend", MedicationRequestController, :resend)
    end

    # Cabinet
    scope "/cabinet" do
      pipe_through([:api_consumer_id, :cabinet])

      patch("/persons/:id", Cabinet.PersonsController, :update_person, as: :cabinet_persons)
      get("/persons", Cabinet.PersonsController, :personal_info, as: :cabinet_persons)
      get("/persons/details", Cabinet.PersonsController, :person_details, as: :cabinet_persons)

      get("/declarations", Cabinet.DeclarationController, :list_declarations, as: :cabinet_declarations)

      post(
        "/declaration_requests",
        Cabinet.DeclarationController,
        :create_declaration_request,
        as: :cabinet_declarations
      )

      patch(
        "/declarations/:id/actions/terminate",
        Cabinet.DeclarationController,
        :terminate_declaration,
        as: :cabinet_declarations
      )

      get("/declarations/:id", Cabinet.DeclarationController, :show_declaration, as: :cabinet_declarations)
    end

    # Person declarations
    get("/persons", PersonController, :search_persons)
    get("/persons/:id/declaration", PersonController, :person_declarations)
    patch("/persons/:id/actions/reset_authentication_method", PersonController, :reset_authentication_method)

    # User roles
    get("/user/roles", UserRoleController, :index)

    # Global parameters
    put("/global_parameters", GlobalParameterController, :create_or_update)

    get("/party_users", PartyUserController, :index)
  end

  scope "/admin", EHealth.Web do
    pipe_through([:api, :client_context_list])

    patch("/clients/:id/refresh_secret", ClientController, :refresh_secret)
  end

  scope "/internal", EHealth.Web do
    pipe_through([:api])

    scope "/deduplication" do
      post("/found_duplicates", DeduplicationsController, :found_duplicates)
    end

    scope "/hash_chain" do
      post("/verification_failed", HashChainController, :verification_failed)
    end

    post("/email/:id", EmailController, :send)
  end

  scope "/", EHealth.Web do
    get("/health", HealthController, :show)
  end

  defp handle_errors(%Plug.Conn{status: 500} = conn, %{kind: kind, reason: reason, stack: stacktrace}) do
    LoggerJSON.log_error(kind, reason, stacktrace)

    Logger.log(:info, fn ->
      Poison.encode!(%{
        "log_type" => "debug",
        "request_params" => conn.params,
        "request_id" => Logger.metadata()[:request_id]
      })
    end)

    send_resp(conn, 500, Poison.encode!(%{errors: %{detail: "Internal server error"}}))
  end

  defp handle_errors(_, _), do: nil
end
