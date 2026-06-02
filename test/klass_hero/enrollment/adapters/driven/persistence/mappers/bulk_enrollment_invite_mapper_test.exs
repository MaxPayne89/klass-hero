defmodule KlassHero.Enrollment.Adapters.Driven.Persistence.Mappers.BulkEnrollmentInviteMapperTest do
  use ExUnit.Case, async: true

  alias KlassHero.Enrollment.Adapters.Driven.Persistence.Mappers.BulkEnrollmentInviteMapper
  alias KlassHero.Enrollment.Adapters.Driven.Persistence.Schemas.BulkEnrollmentInviteSchema
  alias KlassHero.Enrollment.Domain.Models.BulkEnrollmentInvite

  describe "to_domain/1" do
    test "maps all fields from schema to domain struct" do
      id = Ecto.UUID.generate()
      program_id = Ecto.UUID.generate()
      provider_id = Ecto.UUID.generate()
      enrollment_id = Ecto.UUID.generate()
      now = DateTime.utc_now() |> DateTime.truncate(:second)

      schema = %BulkEnrollmentInviteSchema{
        id: id,
        program_id: program_id,
        provider_id: provider_id,
        child_first_name: "Emma",
        child_last_name: "Müller",
        child_date_of_birth: ~D[2017-06-15],
        guardian_email: "parent@example.com",
        guardian_first_name: "Anna",
        guardian_last_name: "Müller",
        guardian2_email: "parent2@example.com",
        guardian2_first_name: "Thomas",
        guardian2_last_name: "Müller",
        school_grade: 3,
        school_name: "Grundschule Mitte",
        medical_conditions: "mild asthma",
        nut_allergy: true,
        consent_photo_marketing: true,
        consent_photo_social_media: false,
        status: :invite_sent,
        invite_token: "secure_token_abc123",
        invite_sent_at: now,
        registered_at: nil,
        enrolled_at: nil,
        enrollment_id: enrollment_id,
        error_details: nil
      }

      result = BulkEnrollmentInviteMapper.to_domain(schema)

      assert %BulkEnrollmentInvite{} = result
      assert result.id == to_string(id)
      assert result.program_id == program_id
      assert result.provider_id == provider_id
      assert result.child_first_name == "Emma"
      assert result.child_last_name == "Müller"
      assert result.child_date_of_birth == ~D[2017-06-15]
      assert result.guardian_email == "parent@example.com"
      assert result.guardian_first_name == "Anna"
      assert result.guardian_last_name == "Müller"
      assert result.guardian2_email == "parent2@example.com"
      assert result.guardian2_first_name == "Thomas"
      assert result.guardian2_last_name == "Müller"
      assert result.school_grade == 3
      assert result.school_name == "Grundschule Mitte"
      assert result.medical_conditions == "mild asthma"
      assert result.nut_allergy == true
      assert result.consent_photo_marketing == true
      assert result.consent_photo_social_media == false
      assert result.status == :invite_sent
      assert result.invite_token == "secure_token_abc123"
      assert result.invite_sent_at == now
      assert result.registered_at == nil
      assert result.enrolled_at == nil
      assert result.enrollment_id == enrollment_id
      assert result.error_details == nil
    end

    test "maps schema with all optional fields nil" do
      schema = build_schema(%{
        guardian2_email: nil,
        guardian2_first_name: nil,
        guardian2_last_name: nil,
        school_grade: nil,
        school_name: nil,
        medical_conditions: nil,
        nut_allergy: nil,
        consent_photo_marketing: nil,
        consent_photo_social_media: nil,
        invite_token: nil,
        invite_sent_at: nil,
        registered_at: nil,
        enrolled_at: nil,
        enrollment_id: nil,
        error_details: nil
      })

      result = BulkEnrollmentInviteMapper.to_domain(schema)

      assert result.guardian2_email == nil
      assert result.guardian2_first_name == nil
      assert result.guardian2_last_name == nil
      assert result.school_grade == nil
      assert result.school_name == nil
      assert result.medical_conditions == nil
      assert result.nut_allergy == nil
      assert result.consent_photo_marketing == nil
      assert result.consent_photo_social_media == nil
      assert result.invite_token == nil
      assert result.invite_sent_at == nil
      assert result.registered_at == nil
      assert result.enrolled_at == nil
      assert result.enrollment_id == nil
      assert result.error_details == nil
    end

    test "preserves all status values" do
      for status <- [:pending, :invite_sent, :registered, :enrolled, :failed] do
        schema = build_schema(%{status: status})
        result = BulkEnrollmentInviteMapper.to_domain(schema)
        assert result.status == status
      end
    end

    test "maps lifecycle timestamps when all are populated" do
      now = DateTime.utc_now() |> DateTime.truncate(:second)
      later = DateTime.add(now, 3600, :second)
      even_later = DateTime.add(later, 3600, :second)

      schema =
        build_schema(%{
          status: :enrolled,
          invite_sent_at: now,
          registered_at: later,
          enrolled_at: even_later
        })

      result = BulkEnrollmentInviteMapper.to_domain(schema)

      assert result.invite_sent_at == now
      assert result.registered_at == later
      assert result.enrolled_at == even_later
    end

    test "maps error_details for failed status" do
      schema = build_schema(%{status: :failed, error_details: "Email delivery failed: mailbox full"})

      result = BulkEnrollmentInviteMapper.to_domain(schema)

      assert result.status == :failed
      assert result.error_details == "Email delivery failed: mailbox full"
    end

    test "converts UUID id to string via Ecto.UUID.cast!" do
      raw_id = Ecto.UUID.generate()
      schema = build_schema(%{id: raw_id})

      result = BulkEnrollmentInviteMapper.to_domain(schema)

      assert is_binary(result.id)
      assert result.id == to_string(raw_id)
    end
  end

  defp build_schema(overrides) do
    defaults = %{
      id: Ecto.UUID.generate(),
      program_id: Ecto.UUID.generate(),
      provider_id: Ecto.UUID.generate(),
      child_first_name: "Max",
      child_last_name: "Mustermann",
      child_date_of_birth: ~D[2018-03-10],
      guardian_email: "guardian@example.com",
      guardian_first_name: "Klaus",
      guardian_last_name: "Mustermann",
      guardian2_email: nil,
      guardian2_first_name: nil,
      guardian2_last_name: nil,
      school_grade: nil,
      school_name: nil,
      medical_conditions: nil,
      nut_allergy: false,
      consent_photo_marketing: false,
      consent_photo_social_media: false,
      status: :pending,
      invite_token: nil,
      invite_sent_at: nil,
      registered_at: nil,
      enrolled_at: nil,
      enrollment_id: nil,
      error_details: nil
    }

    struct!(BulkEnrollmentInviteSchema, Map.merge(defaults, overrides))
  end
end
