# Script for populating the database. You can run it as:
#
#     mix run priv/repo/seeds.exs
#
# Seeds every table so all features are testable out of the box.

alias KlassHero.Accounts.User
alias KlassHero.Enrollment.Adapters.Driven.Persistence.Schemas.EnrollmentPolicySchema
alias KlassHero.Enrollment.Adapters.Driven.Persistence.Schemas.EnrollmentSchema
alias KlassHero.Enrollment.Adapters.Driven.Persistence.Schemas.ParticipantPolicySchema
alias KlassHero.Family.Adapters.Driven.Persistence.Schemas.ChildGuardianSchema
alias KlassHero.Family.Adapters.Driven.Persistence.Schemas.ChildSchema
alias KlassHero.Family.Adapters.Driven.Persistence.Schemas.ConsentSchema
alias KlassHero.Family.Adapters.Driven.Persistence.Schemas.ParentProfileSchema
alias KlassHero.Messaging.Adapters.Driven.Persistence.Schemas.ConversationSchema
alias KlassHero.Messaging.Adapters.Driven.Persistence.Schemas.MessageSchema
alias KlassHero.Messaging.Adapters.Driven.Persistence.Schemas.ParticipantSchema
alias KlassHero.Messaging.Adapters.Driven.Projections.ConversationSummaries
alias KlassHero.Participation.Adapters.Driven.Persistence.Schemas.BehavioralNoteSchema
alias KlassHero.Participation.Adapters.Driven.Persistence.Schemas.ParticipationRecordSchema
alias KlassHero.Participation.Adapters.Driven.Persistence.Schemas.ProgramSessionSchema
alias KlassHero.ProgramCatalog.Adapters.Driven.Persistence.Schemas.ProgramSchema
alias KlassHero.ProgramCatalog.Adapters.Driven.Projections.ProgramListings
alias KlassHero.ProgramCatalog.Adapters.Driven.Projections.VerifiedProviders
alias KlassHero.Provider.Adapters.Driven.Persistence.Schemas.ProviderProfileSchema
alias KlassHero.Provider.Adapters.Driven.Persistence.Schemas.StaffMemberSchema
alias KlassHero.Provider.Adapters.Driven.Persistence.Schemas.VerificationDocumentSchema
alias KlassHero.Repo
alias KlassHero.Shared.Storage

require Logger

# Deterministic randomness for reproducible seed data
:rand.seed(:exsss, {42, 42, 42})

# ==============================================================================
# CLEAR EXISTING DATA (deepest dependents first)
# ==============================================================================

Logger.info("Clearing existing data...")

# Messaging
Repo.delete_all(MessageSchema)
Repo.delete_all(ParticipantSchema)
Repo.delete_all(ConversationSchema)

# Participation
Repo.delete_all(BehavioralNoteSchema)
Repo.delete_all(ParticipationRecordSchema)
Repo.delete_all(ProgramSessionSchema)

# Enrollment + policies
Repo.delete_all(EnrollmentSchema)
Repo.delete_all(EnrollmentPolicySchema)
Repo.delete_all(ParticipantPolicySchema)

# Family
Repo.delete_all(ConsentSchema)
Repo.delete_all(ChildGuardianSchema)
Repo.delete_all(ChildSchema)
Repo.delete_all(ParentProfileSchema)

# Programs + staff
Repo.delete_all(ProgramSchema)
Repo.delete_all(StaffMemberSchema)
Repo.delete_all(VerificationDocumentSchema)
Repo.delete_all(ProviderProfileSchema)

# Users last (everything else references them)
Repo.delete_all(User)

Logger.info("Cleared all existing data")

# ==============================================================================
# S1: USERS (16 total: 10 parents + 1 admin + 5 providers)
# ==============================================================================

Logger.info("Seeding users...")

hashed_pw = Bcrypt.hash_pwd_salt("password")
now = DateTime.utc_now(:second)

parent_user_data = [
  %{name: "Anna Müller", email: "anna.mueller@example.com"},
  %{name: "Thomas Schmidt", email: "thomas.schmidt@example.com"},
  %{name: "Sabine Weber", email: "sabine.weber@example.com"},
  %{name: "Klaus Fischer", email: "klaus.fischer@example.com"},
  %{name: "Petra Becker", email: "petra.becker@example.com"},
  %{name: "Michael Wagner", email: "michael.wagner@example.com"},
  # Parents 7-10: active tier
  %{name: "Julia Hoffmann", email: "julia.hoffmann@example.com"},
  %{name: "Stefan Schäfer", email: "stefan.schaefer@example.com"},
  %{name: "Monika Koch", email: "monika.koch@example.com"},
  %{name: "Andreas Bauer", email: "andreas.bauer@example.com"}
]

parent_users =
  Enum.map(parent_user_data, fn data ->
    %User{}
    |> Ecto.Changeset.change(%{
      name: data.name,
      email: data.email,
      hashed_password: hashed_pw,
      confirmed_at: now,
      intended_roles: [:parent]
    })
    |> Repo.insert!()
  end)

Logger.info("Created #{length(parent_users)} parent users")

# Admin user (created before providers for verified_by_id)
admin =
  %User{}
  |> Ecto.Changeset.change(%{
    name: "Klass Hero Admin",
    email: "app@klasshero.com",
    hashed_password: hashed_pw,
    confirmed_at: now,
    is_admin: true
  })
  |> Repo.insert!()

Logger.info("Created admin user")

provider_user_data = [
  %{name: "Lena Hartmann", email: "lena.hartmann@example.com"},
  %{name: "Markus Klein", email: "markus.klein@example.com"},
  %{name: "Claudia Wolf", email: "claudia.wolf@example.com"},
  %{name: "Robert Braun", email: "robert.braun@example.com"},
  %{name: "Katharina Richter", email: "katharina.richter@example.com"}
]

provider_users =
  Enum.map(provider_user_data, fn data ->
    %User{}
    |> Ecto.Changeset.change(%{
      name: data.name,
      email: data.email,
      hashed_password: hashed_pw,
      confirmed_at: now,
      intended_roles: [:provider]
    })
    |> Repo.insert!()
  end)

Logger.info("Created #{length(provider_users)} provider users")

# ==============================================================================
# S2: PARENT PROFILES (10 total: 6 explorer + 4 active)
# ==============================================================================

Logger.info("Seeding parent profiles...")

parent_profile_data = [
  %{display_name: "Anna M.", phone: "+49 170 111 0001", location: "Berlin", tier: "explorer"},
  %{display_name: "Thomas S.", phone: "+49 170 111 0002", location: "Hamburg", tier: "explorer"},
  %{display_name: "Sabine W.", phone: "+49 170 111 0003", location: "Munich", tier: "explorer"},
  %{display_name: "Klaus F.", phone: "+49 170 111 0004", location: "Cologne", tier: "explorer"},
  %{display_name: "Petra B.", phone: "+49 170 111 0005", location: "Frankfurt", tier: "explorer"},
  %{
    display_name: "Michael W.",
    phone: "+49 170 111 0006",
    location: "Stuttgart",
    tier: "explorer"
  },
  %{display_name: "Julia H.", phone: "+49 170 111 0007", location: "Dresden", tier: "active"},
  %{display_name: "Stefan S.", phone: "+49 170 111 0008", location: "Leipzig", tier: "active"},
  %{display_name: "Monika K.", phone: "+49 170 111 0009", location: "Düsseldorf", tier: "active"},
  %{display_name: "Andreas B.", phone: "+49 170 111 0010", location: "Nuremberg", tier: "active"}
]

parent_profiles =
  Enum.zip(parent_users, parent_profile_data)
  |> Enum.map(fn {user, data} ->
    %ParentProfileSchema{}
    |> ParentProfileSchema.changeset(%{
      identity_id: user.id,
      display_name: data.display_name,
      phone: data.phone,
      location: data.location,
      subscription_tier: data.tier
    })
    |> Repo.insert!()
  end)

Logger.info("Created #{length(parent_profiles)} parent profiles (6 explorer, 4 active)")

# ==============================================================================
# S3: PROVIDER PROFILES (5 total: 2 starter + 2 professional + 1 business_plus)
# ==============================================================================

Logger.info("Seeding provider profiles...")

provider_profile_data = [
  %{
    business_name: "Hartmann Sport Studio",
    description: "Entry-level fitness and movement classes for children",
    phone: "+49 89 200 0001",
    website: "https://hartmann-sport.example.com",
    address: "Hauptstr. 12, 80331 Munich",
    categories: ["sports", "life-skills"]
  },
  %{
    business_name: "Klein Kreativ Werkstatt",
    description: "Arts and crafts workshops for young minds",
    phone: "+49 89 200 0002",
    website: "https://klein-kreativ.example.com",
    address: "Leopoldstr. 45, 80802 Munich",
    categories: ["arts", "workshops"]
  },
  %{
    business_name: "Wolf Musik Akademie",
    description: "Professional music education and performance training",
    phone: "+49 30 300 0003",
    website: "https://wolf-musik.example.com",
    address: "Kurfürstendamm 88, 10709 Berlin",
    categories: ["music", "arts", "education"]
  },
  %{
    business_name: "Braun Bildungszentrum",
    description: "Comprehensive educational programs and tutoring",
    phone: "+49 40 400 0004",
    website: "https://braun-bildung.example.com",
    address: "Mönckebergstr. 20, 20095 Hamburg",
    categories: ["education", "life-skills", "workshops"]
  },
  %{
    business_name: "Richter Elite Academy",
    description: "Premium sports training, camps, and youth development programs",
    phone: "+49 69 500 0005",
    website: "https://richter-elite.example.com",
    address: "Zeil 100, 60313 Frankfurt",
    categories: ["sports", "camps", "education", "life-skills"]
  }
]

provider_profiles =
  Enum.zip(provider_users, provider_profile_data)
  |> Enum.map(fn {user, data} ->
    %ProviderProfileSchema{}
    |> ProviderProfileSchema.changeset(%{
      identity_id: user.id,
      business_name: data.business_name,
      description: data.description,
      phone: data.phone,
      website: data.website,
      address: data.address,
      categories: data.categories,
      verified: true,
      verified_at: now,
      verified_by_id: admin.id
    })
    |> Repo.insert!()
  end)

Logger.info("Created #{length(provider_profiles)} provider profiles")

# Convenient references
[starter_1, starter_2, pro_1, pro_2, biz] = provider_profiles
[starter_1_user, starter_2_user, pro_1_user, pro_2_user, biz_user] = provider_users

# ==============================================================================
# S4: CHILDREN (~20, deterministic 1-3 per parent)
# ==============================================================================

Logger.info("Seeding children...")

today = Date.utc_today()

# German first names pool
boy_names = [
  "Lukas",
  "Felix",
  "Leon",
  "Maximilian",
  "Paul",
  "Noah",
  "Ben",
  "Elias",
  "Jonas",
  "Finn"
]

girl_names = ["Emma", "Mia", "Hannah", "Sofia", "Lina", "Emilia", "Marie", "Lena", "Lea", "Clara"]
all_first_names = boy_names ++ girl_names

# Deterministic child count per parent (1-3)
child_counts = Enum.map(1..10, fn _ -> :rand.uniform(3) end)

# Build children with their parent profile reference for later guardian linking
{children, _name_idx} =
  Enum.zip(parent_profiles, child_counts)
  |> Enum.flat_map_reduce(0, fn {parent, count}, name_idx ->
    parent_idx = Enum.find_index(parent_profiles, &(&1.id == parent.id))

    # Derive child's last name from parent user's full name
    last_name =
      Enum.at(parent_user_data, parent_idx).name
      |> String.split(" ")
      |> List.last()

    children_with_parent =
      Enum.map(0..(count - 1), fn i ->
        # Age between 5 and 14
        age = 5 + :rand.uniform(10) - 1
        dob = Date.add(today, -365 * age - :rand.uniform(180))
        first_name = Enum.at(all_first_names, rem(name_idx + i, length(all_first_names)))

        gender =
          cond do
            first_name in boy_names -> "male"
            first_name in girl_names -> "female"
            true -> "not_specified"
          end

        child =
          %ChildSchema{}
          |> ChildSchema.changeset(%{
            first_name: first_name,
            last_name: last_name,
            date_of_birth: dob,
            gender: gender,
            emergency_contact: "+49 170 999 #{String.pad_leading(Integer.to_string(name_idx + i), 4, "0")}"
          })
          |> Repo.insert!()

        {child, parent}
      end)

    {children_with_parent, name_idx + count}
  end)

child_records = Enum.map(children, fn {child, _parent} -> child end)
Logger.info("Created #{length(child_records)} children")

# ==============================================================================
# S5: CHILD GUARDIANS (1:1 with children)
# ==============================================================================

Logger.info("Seeding child-guardian relationships...")

Enum.each(children, fn {child, parent} ->
  ChildGuardianSchema.changeset(%{
    child_id: child.id,
    guardian_id: parent.id,
    relationship: "parent",
    is_primary: true
  })
  |> Repo.insert!()
end)

Logger.info("Created #{length(children)} child-guardian links")

# ==============================================================================
# S6: CONSENTS (1 per child)
# ==============================================================================

Logger.info("Seeding consents...")

Enum.each(children, fn {child, parent} ->
  %ConsentSchema{}
  |> ConsentSchema.changeset(%{
    parent_id: parent.id,
    child_id: child.id,
    consent_type: "provider_data_sharing",
    granted_at: now
  })
  |> Repo.insert!()
end)

Logger.info("Created #{length(children)} consent records")

# ==============================================================================
# S7: STAFF MEMBERS (7 total: pro providers + business_plus)
# ==============================================================================

Logger.info("Seeding staff members...")

staff_data = [
  # Wolf Musik Akademie (pro_1): 2 staff
  %{
    provider: pro_1,
    first_name: "Maria",
    last_name: "Schulz",
    role: "Piano Instructor",
    email: "maria.schulz@example.com",
    tags: ["music"],
    qualifications: ["Music Education Degree"]
  },
  %{
    provider: pro_1,
    first_name: "Peter",
    last_name: "Neumann",
    role: "Vocal Coach",
    email: "peter.neumann@example.com",
    tags: ["music", "arts"],
    qualifications: ["Vocal Performance MA"]
  },
  # Braun Bildungszentrum (pro_2): 2 staff
  %{
    provider: pro_2,
    first_name: "Heike",
    last_name: "Zimmermann",
    role: "Math Tutor",
    email: "heike.zimmermann@example.com",
    tags: ["education"],
    qualifications: ["Mathematics MSc"]
  },
  %{
    provider: pro_2,
    first_name: "Jürgen",
    last_name: "Krüger",
    role: "Science Instructor",
    email: "juergen.krueger@example.com",
    tags: ["education", "workshops"],
    qualifications: ["Physics BSc", "Teaching Certificate"]
  },
  # Richter Elite Academy (biz): 3 staff
  %{
    provider: biz,
    first_name: "Sven",
    last_name: "Lehmann",
    role: "Head Coach",
    email: "sven.lehmann@example.com",
    tags: ["sports", "camps"],
    qualifications: ["Sports Science PhD", "DFB A-License"]
  },
  %{
    provider: biz,
    first_name: "Tanja",
    last_name: "Köhler",
    role: "Fitness Trainer",
    email: "tanja.koehler@example.com",
    tags: ["sports", "life-skills"],
    qualifications: ["Certified Personal Trainer"]
  },
  %{
    provider: biz,
    first_name: "Dirk",
    last_name: "Schreiber",
    role: "Camp Director",
    email: "dirk.schreiber@example.com",
    tags: ["camps", "sports", "education"],
    qualifications: ["Youth Development Diploma"]
  }
]

staff_members =
  Enum.map(staff_data, fn data ->
    %StaffMemberSchema{}
    |> StaffMemberSchema.create_changeset(%{
      provider_id: data.provider.id,
      first_name: data.first_name,
      last_name: data.last_name,
      role: data.role,
      email: data.email,
      tags: data.tags,
      qualifications: data.qualifications
    })
    |> Repo.insert!()
  end)

Logger.info("Created #{length(staff_members)} staff members")

# Staff lookup by provider
staff_by_provider =
  Enum.group_by(staff_members, fn s ->
    Enum.find(staff_data, fn d -> d.first_name == s.first_name end).provider.id
  end)

# ==============================================================================
# S7b: UI TEST STAFF USER
# ==============================================================================
# A confirmed staff user for test-driving staff dashboard flows.
# Linked to Wolf Musik Akademie (pro_1), empty tags (sees all programs).

Logger.info("Seeding UI test staff user...")

uitest_staff_user =
  %User{}
  |> Ecto.Changeset.change(%{
    name: "UI TestStaff",
    email: "uitest-staff@example.com",
    hashed_password: hashed_pw,
    confirmed_at: now,
    intended_roles: [:staff, :provider]
  })
  |> Repo.insert!()

uitest_staff_member =
  %StaffMemberSchema{}
  |> StaffMemberSchema.create_changeset(%{
    provider_id: pro_1.id,
    first_name: "UI",
    last_name: "TestStaff",
    role: "General Staff",
    tags: [],
    qualifications: []
  })
  |> Repo.insert!()

# Link the user to the staff member via invitation acceptance
uitest_staff_member
|> StaffMemberSchema.invitation_changeset(%{
  user_id: uitest_staff_user.id,
  invitation_status: "accepted"
})
|> Repo.update!()

Logger.info("Created UI test staff user: uitest-staff@example.com (Wolf Musik Akademie)")

# ==============================================================================
# S8: VERIFICATION DOCUMENTS (~12)
# ==============================================================================

Logger.info("Seeding verification documents...")

seed_ts = 1_738_800_000_000

seed_file_key = fn provider_id, filename ->
  safe = String.replace(filename, ~r/[^a-zA-Z0-9._-]/, "_")
  "verification-docs/providers/#{provider_id}/#{seed_ts}_#{safe}"
end

verification_documents = [
  # Starter 1: 1 approved, 1 pending
  %{
    provider_id: starter_1.id,
    document_type: "business_registration",
    status: "approved",
    reviewed_by_id: admin.id,
    reviewed_at: now
  },
  %{provider_id: starter_1.id, document_type: "insurance_certificate", status: "pending"},
  # Starter 2: 2 approved
  %{
    provider_id: starter_2.id,
    document_type: "business_registration",
    status: "approved",
    reviewed_by_id: admin.id,
    reviewed_at: now
  },
  %{
    provider_id: starter_2.id,
    document_type: "insurance_certificate",
    status: "approved",
    reviewed_by_id: admin.id,
    reviewed_at: now
  },
  # Pro 1: 2 approved, 1 rejected
  %{
    provider_id: pro_1.id,
    document_type: "business_registration",
    status: "approved",
    reviewed_by_id: admin.id,
    reviewed_at: now
  },
  %{
    provider_id: pro_1.id,
    document_type: "id_document",
    status: "approved",
    reviewed_by_id: admin.id,
    reviewed_at: now
  },
  %{
    provider_id: pro_1.id,
    document_type: "insurance_certificate",
    status: "rejected",
    rejection_reason: "Document expired",
    reviewed_by_id: admin.id,
    reviewed_at: now
  },
  # Pro 2: 2 approved
  %{
    provider_id: pro_2.id,
    document_type: "business_registration",
    status: "approved",
    reviewed_by_id: admin.id,
    reviewed_at: now
  },
  %{
    provider_id: pro_2.id,
    document_type: "insurance_certificate",
    status: "approved",
    reviewed_by_id: admin.id,
    reviewed_at: now
  },
  # Biz: 3 approved
  %{
    provider_id: biz.id,
    document_type: "business_registration",
    status: "approved",
    reviewed_by_id: admin.id,
    reviewed_at: now
  },
  %{
    provider_id: biz.id,
    document_type: "insurance_certificate",
    status: "approved",
    reviewed_by_id: admin.id,
    reviewed_at: now
  },
  %{
    provider_id: biz.id,
    document_type: "tax_certificate",
    status: "approved",
    reviewed_by_id: admin.id,
    reviewed_at: now
  }
]

Enum.each(verification_documents, fn doc_attrs ->
  filename = "#{doc_attrs.document_type}.pdf"

  full_attrs =
    Map.merge(doc_attrs, %{
      file_url: seed_file_key.(doc_attrs.provider_id, filename),
      original_filename: filename
    })

  %VerificationDocumentSchema{}
  |> VerificationDocumentSchema.changeset(full_attrs)
  |> Repo.insert!()
end)

Logger.info("Created #{length(verification_documents)} verification documents")

# ==============================================================================
# UPLOAD DUMMY PDFs TO STORAGE
# ==============================================================================

seed_pdf_binary = fn label ->
  content_stream = "BT /F1 12 Tf 72 720 Td (Seed: #{label}) Tj ET"
  stream_length = byte_size(content_stream)

  "%PDF-1.4\n" <>
    "1 0 obj<</Type/Catalog/Pages 2 0 R>>endobj\n" <>
    "2 0 obj<</Type/Pages/Kids[3 0 R]/Count 1>>endobj\n" <>
    "3 0 obj<</Type/Page/Parent 2 0 R/MediaBox[0 0 612 792]/Contents 4 0 R/Resources<</Font<</F1<</Type/Font/Subtype/Type1/BaseFont/Helvetica>>>>>>>>endobj\n" <>
    "4 0 obj<</Length #{stream_length}>>\nstream\n#{content_stream}\nendstream\nendobj\n" <>
    "xref\n0 5\n" <>
    "trailer<</Size 5/Root 1 0 R>>\n" <>
    "startxref\n0\n%%EOF\n"
end

storage_uploaded =
  Enum.reduce(verification_documents, 0, fn doc_attrs, count ->
    filename = "#{doc_attrs.document_type}.pdf"
    key = seed_file_key.(doc_attrs.provider_id, filename)
    pdf = seed_pdf_binary.(filename)

    case Storage.upload(:private, key, pdf, content_type: "application/pdf") do
      {:ok, _} -> count + 1
      {:error, _reason} -> count
    end
  end)

if storage_uploaded > 0 do
  Logger.info("Uploaded #{storage_uploaded}/#{length(verification_documents)} dummy PDFs to storage")
else
  Logger.warning("No PDFs uploaded — storage may be unavailable (MinIO not running?). DB records are fine.")
end

# ==============================================================================
# S9: PROGRAMS (~19 provider programs)
# ==============================================================================

Logger.info("Seeding programs...")

pro_1_staff = Map.get(staff_by_provider, pro_1.id, [])
pro_2_staff = Map.get(staff_by_provider, pro_2.id, [])
biz_staff = Map.get(staff_by_provider, biz.id, [])

# First two providers: 2 programs each
starter_1_programs = [
  %{
    title: "Youth Fitness Basics",
    description: "Entry-level fitness and movement for young athletes",
    category: "sports",
    price: Decimal.new("80.00"),
    provider_id: starter_1.id,
    meeting_days: ["Monday", "Wednesday"],
    meeting_start_time: ~T[16:00:00],
    meeting_end_time: ~T[17:00:00],
    start_date: Date.add(today, -90),
    end_date: Date.add(today, -10)
  },
  %{
    title: "Soccer Fundamentals",
    description: "Learn basic soccer skills and teamwork",
    category: "sports",
    price: Decimal.new("100.00"),
    provider_id: starter_1.id,
    meeting_days: ["Tuesday", "Thursday"],
    meeting_start_time: ~T[16:00:00],
    meeting_end_time: ~T[17:30:00],
    start_date: Date.add(today, -30),
    end_date: Date.add(today, 120)
  }
]

starter_2_programs = [
  %{
    title: "Watercolor Workshop",
    description: "Explore watercolor painting techniques for beginners",
    category: "arts",
    price: Decimal.new("90.00"),
    provider_id: starter_2.id,
    meeting_days: ["Wednesday"],
    meeting_start_time: ~T[15:00:00],
    meeting_end_time: ~T[17:00:00],
    start_date: Date.add(today, -60),
    end_date: Date.add(today, 60)
  },
  %{
    title: "Clay & Sculpture",
    description: "Hands-on sculpting and pottery for children",
    category: "workshops",
    price: Decimal.new("110.00"),
    provider_id: starter_2.id,
    meeting_days: ["Friday"],
    meeting_start_time: ~T[14:00:00],
    meeting_end_time: ~T[16:00:00],
    start_date: Date.add(today, 14),
    end_date: Date.add(today, 90)
  }
]

# Professional providers: 4-5 each
pro_1_programs = [
  %{
    title: "Piano for Beginners",
    description: "Introduction to piano, reading music, and basic technique",
    category: "music",
    price: Decimal.new("150.00"),
    provider_id: pro_1.id,
    instructor_id: Enum.at(pro_1_staff, 0).id,
    instructor_name: "Maria Schulz",
    meeting_days: ["Monday", "Wednesday"],
    meeting_start_time: ~T[15:00:00],
    meeting_end_time: ~T[16:00:00],
    start_date: Date.add(today, -60),
    end_date: Date.add(today, 90)
  },
  %{
    title: "Children's Choir",
    description: "Group vocal training with performance opportunities",
    category: "music",
    price: Decimal.new("120.00"),
    provider_id: pro_1.id,
    instructor_id: Enum.at(pro_1_staff, 1).id,
    instructor_name: "Peter Neumann",
    meeting_days: ["Tuesday", "Thursday"],
    meeting_start_time: ~T[16:00:00],
    meeting_end_time: ~T[17:30:00],
    start_date: Date.add(today, -45),
    end_date: Date.add(today, 75)
  },
  %{
    title: "Music Theory Essentials",
    description: "Learn to read music, understand rhythm, and compose simple melodies",
    category: "education",
    price: Decimal.new("100.00"),
    provider_id: pro_1.id,
    meeting_days: ["Saturday"],
    meeting_start_time: ~T[10:00:00],
    meeting_end_time: ~T[11:30:00],
    start_date: Date.add(today, -30),
    end_date: Date.add(today, 60)
  },
  %{
    title: "Art & Music Fusion",
    description: "Creative workshop combining visual arts with musical expression",
    category: "arts",
    price: Decimal.new("130.00"),
    provider_id: pro_1.id,
    meeting_days: ["Friday"],
    meeting_start_time: ~T[15:00:00],
    meeting_end_time: ~T[17:00:00],
    start_date: Date.add(today, 30),
    end_date: Date.add(today, 150)
  }
]

pro_2_programs = [
  %{
    title: "Math Mastery",
    description: "Fun and interactive math tutoring for grades 3-6",
    category: "education",
    price: Decimal.new("140.00"),
    provider_id: pro_2.id,
    instructor_id: Enum.at(pro_2_staff, 0).id,
    instructor_name: "Heike Zimmermann",
    meeting_days: ["Monday", "Wednesday"],
    meeting_start_time: ~T[15:00:00],
    meeting_end_time: ~T[16:30:00],
    start_date: Date.add(today, -45),
    end_date: Date.add(today, 75)
  },
  %{
    title: "Science Explorers",
    description: "Hands-on experiments and STEM learning for curious minds",
    category: "education",
    price: Decimal.new("130.00"),
    provider_id: pro_2.id,
    instructor_id: Enum.at(pro_2_staff, 1).id,
    instructor_name: "Jürgen Krüger",
    meeting_days: ["Tuesday", "Thursday"],
    meeting_start_time: ~T[15:30:00],
    meeting_end_time: ~T[17:00:00],
    start_date: Date.add(today, -60),
    end_date: Date.add(today, 60)
  },
  %{
    title: "Life Skills Workshop",
    description: "Practical everyday skills: cooking basics, first aid, money management",
    category: "life-skills",
    price: Decimal.new("95.00"),
    provider_id: pro_2.id,
    meeting_days: ["Saturday"],
    meeting_start_time: ~T[10:00:00],
    meeting_end_time: ~T[12:00:00],
    start_date: Date.add(today, -20),
    end_date: Date.add(today, 100)
  },
  %{
    title: "Coding for Kids",
    description: "Introduction to programming with Scratch and Python",
    category: "education",
    price: Decimal.new("160.00"),
    provider_id: pro_2.id,
    meeting_days: ["Wednesday", "Friday"],
    meeting_start_time: ~T[16:00:00],
    meeting_end_time: ~T[17:30:00],
    start_date: Date.add(today, -90),
    end_date: Date.add(today, -5)
  },
  %{
    title: "Weekend STEM Camp",
    description: "Intensive weekend workshops on robotics and engineering",
    category: "workshops",
    price: Decimal.new("200.00"),
    provider_id: pro_2.id,
    meeting_days: ["Saturday", "Sunday"],
    meeting_start_time: ~T[09:00:00],
    meeting_end_time: ~T[15:00:00],
    start_date: Date.add(today, 30),
    end_date: Date.add(today, 60)
  }
]

# Business plus: 6 programs
biz_programs = [
  %{
    title: "Elite Soccer Training",
    description: "Competitive soccer training for advanced young players",
    category: "sports",
    price: Decimal.new("250.00"),
    provider_id: biz.id,
    instructor_id: Enum.at(biz_staff, 0).id,
    instructor_name: "Sven Lehmann",
    meeting_days: ["Monday", "Wednesday", "Friday"],
    meeting_start_time: ~T[16:00:00],
    meeting_end_time: ~T[18:00:00],
    start_date: Date.add(today, -30),
    end_date: Date.add(today, 150)
  },
  %{
    title: "Athletic Conditioning",
    description: "Strength, agility, and endurance training for youth athletes",
    category: "sports",
    price: Decimal.new("180.00"),
    provider_id: biz.id,
    instructor_id: Enum.at(biz_staff, 1).id,
    instructor_name: "Tanja Köhler",
    meeting_days: ["Tuesday", "Thursday"],
    meeting_start_time: ~T[16:30:00],
    meeting_end_time: ~T[18:00:00],
    start_date: Date.add(today, -45),
    end_date: Date.add(today, 75)
  },
  %{
    title: "Summer Sports Camp",
    description: "Comprehensive multi-sport summer camp with outdoor activities",
    category: "camps",
    price: Decimal.new("450.00"),
    provider_id: biz.id,
    instructor_id: Enum.at(biz_staff, 2).id,
    instructor_name: "Dirk Schreiber",
    meeting_days: ["Monday", "Tuesday", "Wednesday", "Thursday", "Friday"],
    meeting_start_time: ~T[08:00:00],
    meeting_end_time: ~T[16:00:00],
    start_date: Date.add(today, 60),
    end_date: Date.add(today, 90)
  },
  %{
    title: "Basketball League",
    description: "Organized basketball training with regular friendly matches",
    category: "sports",
    price: Decimal.new("160.00"),
    provider_id: biz.id,
    meeting_days: ["Saturday"],
    meeting_start_time: ~T[09:00:00],
    meeting_end_time: ~T[12:00:00],
    start_date: Date.add(today, -60),
    end_date: Date.add(today, 60)
  },
  %{
    title: "Leadership & Team Building",
    description: "Developing leadership skills through team challenges and outdoor activities",
    category: "life-skills",
    price: Decimal.new("120.00"),
    provider_id: biz.id,
    meeting_days: ["Sunday"],
    meeting_start_time: ~T[10:00:00],
    meeting_end_time: ~T[13:00:00],
    start_date: Date.add(today, -20),
    end_date: Date.add(today, 100)
  },
  %{
    title: "Winter Adventure Camp",
    description: "Outdoor winter sports and indoor activities during school holidays",
    category: "camps",
    price: Decimal.new("380.00"),
    provider_id: biz.id,
    meeting_days: ["Monday", "Tuesday", "Wednesday", "Thursday", "Friday"],
    meeting_start_time: ~T[09:00:00],
    meeting_end_time: ~T[15:00:00],
    start_date: Date.add(today, -120),
    end_date: Date.add(today, -90)
  }
]

all_program_data =
  starter_1_programs ++
    starter_2_programs ++
    pro_1_programs ++
    pro_2_programs ++
    biz_programs

inserted_programs =
  Enum.map(all_program_data, fn program_attrs ->
    %ProgramSchema{}
    |> ProgramSchema.create_changeset(program_attrs)
    |> Repo.insert!()
  end)

program_by_title = Map.new(inserted_programs, fn p -> {p.title, p} end)

Logger.info("Created #{length(inserted_programs)} programs")

# ==============================================================================
# S10: ENROLLMENT POLICIES (~8 programs)
# ==============================================================================

Logger.info("Seeding enrollment policies...")

enrollment_policy_programs = [
  {"Soccer Fundamentals", 3, 20},
  {"Piano for Beginners", 3, 12},
  {"Children's Choir", 5, 25},
  {"Math Mastery", 3, 15},
  {"Science Explorers", 4, 18},
  {"Elite Soccer Training", 5, 20},
  {"Athletic Conditioning", 4, 16},
  {"Summer Sports Camp", 8, 25}
]

Enum.each(enrollment_policy_programs, fn {title, min, max} ->
  program = Map.fetch!(program_by_title, title)

  EnrollmentPolicySchema.changeset(%{
    program_id: program.id,
    min_enrollment: min,
    max_enrollment: max
  })
  |> Repo.insert!()
end)

Logger.info("Created #{length(enrollment_policy_programs)} enrollment policies")

# ==============================================================================
# S11: PARTICIPANT POLICIES (~6 programs)
# ==============================================================================

Logger.info("Seeding participant policies...")

participant_policy_data = [
  %{title: "Youth Fitness Basics", min_age_months: 60, max_age_months: 120},
  %{title: "Soccer Fundamentals", min_age_months: 72, max_age_months: 144},
  %{title: "Piano for Beginners", min_age_months: 72, max_age_months: 168},
  %{
    title: "Elite Soccer Training",
    min_age_months: 120,
    max_age_months: 192,
    allowed_genders: ["male"]
  },
  %{title: "Math Mastery", min_grade: 3, max_grade: 6},
  %{title: "Science Explorers", min_age_months: 84, max_age_months: 156}
]

Enum.each(participant_policy_data, fn data ->
  program = Map.fetch!(program_by_title, data.title)

  attrs =
    %{program_id: program.id}
    |> Map.merge(Map.delete(data, :title))

  ParticipantPolicySchema.changeset(attrs)
  |> Repo.insert!()
end)

Logger.info("Created #{length(participant_policy_data)} participant policies")

# ==============================================================================
# S12: ENROLLMENTS (~16, 80% of children enrolled)
# ==============================================================================

Logger.info("Seeding enrollments...")

# Programs that accept enrollments (current or past, with confirmed status possible)
enrollable_programs = [
  "Soccer Fundamentals",
  "Watercolor Workshop",
  "Piano for Beginners",
  "Children's Choir",
  "Music Theory Essentials",
  "Math Mastery",
  "Science Explorers",
  "Life Skills Workshop",
  "Coding for Kids",
  "Elite Soccer Training",
  "Athletic Conditioning",
  "Basketball League",
  "Leadership & Team Building",
  "Youth Fitness Basics",
  "Winter Adventure Camp"
]

# Pick ~80% of children (deterministic)
enrollable_children =
  children
  |> Enum.filter(fn _ -> :rand.uniform(100) <= 80 end)

# Status distribution: 60% confirmed, 20% pending, 10% completed, 10% cancelled
status_pool =
  List.duplicate("confirmed", 6) ++ List.duplicate("pending", 2) ++ ["completed", "cancelled"]

enrollment_records =
  enrollable_children
  |> Enum.with_index()
  |> Enum.map(fn {{child, parent}, idx} ->
    # Pick a program for this child (round-robin through enrollable programs)
    program_title = Enum.at(enrollable_programs, rem(idx, length(enrollable_programs)))
    program = Map.fetch!(program_by_title, program_title)
    status = Enum.at(status_pool, rem(idx, length(status_pool)))

    days_ago = 60 - idx * 3
    enrolled_at = DateTime.add(now, -days_ago, :day)

    base_attrs = %{
      program_id: program.id,
      child_id: child.id,
      parent_id: parent.id,
      status: status,
      enrolled_at: enrolled_at,
      subtotal: program.price,
      vat_amount: Decimal.mult(program.price, Decimal.new("0.19")) |> Decimal.round(2),
      total_amount: Decimal.mult(program.price, Decimal.new("1.19")) |> Decimal.round(2),
      payment_method: "card"
    }

    extra =
      case status do
        "confirmed" ->
          %{confirmed_at: DateTime.add(enrolled_at, 1, :day)}

        "completed" ->
          %{
            confirmed_at: DateTime.add(enrolled_at, 1, :day),
            completed_at: DateTime.add(enrolled_at, 60, :day)
          }

        "cancelled" ->
          %{
            cancelled_at: DateTime.add(enrolled_at, 5, :day),
            cancellation_reason: "Schedule conflict"
          }

        _ ->
          %{}
      end

    attrs = Map.merge(base_attrs, extra)

    %EnrollmentSchema{}
    |> EnrollmentSchema.create_changeset(attrs)
    |> Repo.insert!()
  end)

Logger.info("Created #{length(enrollment_records)} enrollments")

# ==============================================================================
# S13: PROGRAM SESSIONS (~6 per enrolled program with confirmed enrollments)
# ==============================================================================

Logger.info("Seeding program sessions...")

# Find programs with confirmed enrollments
confirmed_enrollments = Enum.filter(enrollment_records, &(&1.status == "confirmed"))
confirmed_program_ids = Enum.map(confirmed_enrollments, & &1.program_id) |> Enum.uniq()

session_records =
  Enum.flat_map(confirmed_program_ids, fn program_id ->
    program = Enum.find(inserted_programs, &(&1.id == program_id))
    start_time = program.meeting_start_time || ~T[15:00:00]
    end_time = program.meeting_end_time || ~T[17:00:00]

    # 3 past sessions (completed), 1 today (in_progress), 2 future (scheduled)
    session_dates = [
      {Date.add(today, -21), :completed},
      {Date.add(today, -14), :completed},
      {Date.add(today, -7), :completed},
      {today, :in_progress},
      {Date.add(today, 7), :scheduled},
      {Date.add(today, 14), :scheduled}
    ]

    Enum.map(session_dates, fn {date, status} ->
      ProgramSessionSchema.create_changeset(%{
        program_id: program_id,
        session_date: date,
        start_time: start_time,
        end_time: end_time,
        status: status,
        max_capacity: 20
      })
      |> Repo.insert!()
    end)
  end)

Logger.info("Created #{length(session_records)} program sessions")

# Staff-testable sessions: ensure Wolf Musik Akademie (pro_1) has sessions
# even without enrollments, so the seed staff user can test-drive sessions/participation
staff_session_programs = [
  program_by_title["Piano for Beginners"],
  program_by_title["Children's Choir"]
]

staff_session_records =
  Enum.flat_map(staff_session_programs, fn program ->
    if program do
      start_time = program.meeting_start_time || ~T[15:00:00]
      end_time = program.meeting_end_time || ~T[17:00:00]

      [
        {Date.add(today, -7), :completed},
        {today, :in_progress},
        {Date.add(today, 7), :scheduled}
      ]
      |> Enum.map(fn {date, status} ->
        ProgramSessionSchema.create_changeset(%{
          program_id: program.id,
          session_date: date,
          start_time: start_time,
          end_time: end_time,
          status: status,
          max_capacity: 15
        })
        |> Repo.insert!()
      end)
    else
      []
    end
  end)

session_records = session_records ++ staff_session_records

Logger.info("Created #{length(staff_session_records)} staff-testable sessions for Wolf Musik Akademie")

# ==============================================================================
# S14: PARTICIPATION RECORDS
# ==============================================================================

Logger.info("Seeding participation records...")

# For each confirmed enrollment, create participation records for past + today sessions
participation_records =
  Enum.flat_map(confirmed_enrollments, fn enrollment ->
    program_sessions =
      Enum.filter(session_records, fn s ->
        s.program_id == enrollment.program_id and s.status in [:completed, :in_progress]
      end)

    # Find provider for this program
    program = Enum.find(inserted_programs, &(&1.id == enrollment.program_id))
    provider = Enum.find(provider_profiles, &(&1.id == program.provider_id))

    Enum.map(program_sessions, fn session ->
      {status, check_in_at, check_out_at} =
        case session.status do
          :completed ->
            # Past sessions: 70% checked_out, 20% checked_in (left early?), 10% absent
            roll = :rand.uniform(100)

            cond do
              roll <= 70 ->
                ci = DateTime.new!(session.session_date, session.start_time, "Etc/UTC")
                co = DateTime.new!(session.session_date, session.end_time, "Etc/UTC")
                {:checked_out, ci, co}

              roll <= 90 ->
                ci = DateTime.new!(session.session_date, session.start_time, "Etc/UTC")
                {:checked_in, ci, nil}

              true ->
                {:absent, nil, nil}
            end

          :in_progress ->
            # Today: 60% checked_in, 40% registered
            if :rand.uniform(100) <= 60 do
              ci = DateTime.new!(session.session_date, session.start_time, "Etc/UTC")
              {:checked_in, ci, nil}
            else
              {:registered, nil, nil}
            end
        end

      attrs = %{
        session_id: session.id,
        child_id: enrollment.child_id,
        parent_id: enrollment.parent_id,
        provider_id: provider && provider.id,
        status: status
      }

      attrs = if check_in_at, do: Map.put(attrs, :check_in_at, check_in_at), else: attrs
      attrs = if check_out_at, do: Map.put(attrs, :check_out_at, check_out_at), else: attrs

      ParticipationRecordSchema.create_changeset(attrs)
      |> Repo.insert!()
    end)
  end)

Logger.info("Created #{length(participation_records)} participation records")

# ==============================================================================
# S15: BEHAVIORAL NOTES (~30% of checked_out records)
# ==============================================================================

Logger.info("Seeding behavioral notes...")

checked_out_records = Enum.filter(participation_records, &(&1.status == :checked_out))

note_contents = [
  "Participated enthusiastically in all group activities today.",
  "Showed great improvement in coordination exercises.",
  "Was very helpful to younger participants during warm-up.",
  "Needed extra encouragement during the team exercise but finished strong.",
  "Excellent focus and attention throughout the session.",
  "Had a minor disagreement with another child but resolved it maturely.",
  "Demonstrated natural leadership skills during group project.",
  "Was quieter than usual today but engaged well one-on-one.",
  "Made significant progress on the technique we practiced last week.",
  "Very creative approach to the assigned task — impressed the instructor."
]

# Status distribution: 60% approved, 20% pending_approval, 20% rejected
note_status_pool =
  List.duplicate(:approved, 6) ++
    List.duplicate(:pending_approval, 2) ++ List.duplicate(:rejected, 2)

behavioral_notes =
  checked_out_records
  |> Enum.filter(fn _ -> :rand.uniform(100) <= 30 end)
  |> Enum.with_index()
  |> Enum.map(fn {record, idx} ->
    content = Enum.at(note_contents, rem(idx, length(note_contents)))
    status = Enum.at(note_status_pool, rem(idx, length(note_status_pool)))

    # Find the provider for this participation record
    session = Enum.find(session_records, &(&1.id == record.session_id))
    program = Enum.find(inserted_programs, &(&1.id == session.program_id))
    provider = Enum.find(provider_profiles, &(&1.id == program.provider_id))

    attrs = %{
      participation_record_id: record.id,
      child_id: record.child_id,
      parent_id: record.parent_id,
      provider_id: provider.id,
      content: content,
      status: status,
      submitted_at: DateTime.add(now, -(60 - idx), :day)
    }

    attrs =
      if status in [:approved, :rejected] do
        Map.put(attrs, :reviewed_at, DateTime.add(attrs.submitted_at, 1, :day))
      else
        attrs
      end

    attrs =
      if status == :rejected do
        Map.put(attrs, :rejection_reason, "Content needs more specific observations")
      else
        attrs
      end

    BehavioralNoteSchema.create_changeset(attrs)
    |> Repo.insert!()
  end)

Logger.info("Created #{length(behavioral_notes)} behavioral notes")

# ==============================================================================
# S16: CONVERSATIONS (5 total)
# ==============================================================================

Logger.info("Seeding conversations...")

# 3 direct conversations (active-tier parents with messaging-enabled providers)
# Active parents: indices 6-9 (Julia, Stefan, Monika, Andreas)
# Messaging-enabled providers: pro_1, pro_2, biz (professional + business_plus)

direct_conversations = [
  %{provider: pro_1, parent_user: Enum.at(parent_users, 6), subject: nil},
  %{provider: pro_2, parent_user: Enum.at(parent_users, 7), subject: nil},
  %{provider: biz, parent_user: Enum.at(parent_users, 8), subject: nil}
]

# 2 program_broadcast conversations
broadcast_conversations = [
  %{
    provider: pro_1,
    program: Map.fetch!(program_by_title, "Piano for Beginners"),
    subject: "Weekly practice tips"
  },
  %{
    provider: biz,
    program: Map.fetch!(program_by_title, "Elite Soccer Training"),
    subject: "Upcoming tournament info"
  }
]

inserted_direct_convos =
  Enum.map(direct_conversations, fn data ->
    ConversationSchema.create_changeset(%{
      type: "direct",
      provider_id: data.provider.id
    })
    |> Repo.insert!()
  end)

inserted_broadcast_convos =
  Enum.map(broadcast_conversations, fn data ->
    ConversationSchema.create_changeset(%{
      type: "program_broadcast",
      provider_id: data.provider.id,
      program_id: data.program.id,
      subject: data.subject
    })
    |> Repo.insert!()
  end)

all_conversations = inserted_direct_convos ++ inserted_broadcast_convos
Logger.info("Created #{length(all_conversations)} conversations (3 direct, 2 broadcast)")

# ==============================================================================
# S17: CONVERSATION PARTICIPANTS + MESSAGES
# ==============================================================================

Logger.info("Seeding conversation participants and messages...")

participant_count = 0
message_count = 0

# Direct conversation participants and messages
{participant_count, message_count} =
  Enum.zip(inserted_direct_convos, direct_conversations)
  |> Enum.reduce({participant_count, message_count}, fn {convo, data}, {pc, mc} ->
    # Find the provider user for this provider profile
    provider_user =
      case data.provider.id do
        id when id == pro_1.id -> pro_1_user
        id when id == pro_2.id -> pro_2_user
        id when id == biz.id -> biz_user
        _ -> nil
      end

    # Add both participants
    ParticipantSchema.create_changeset(%{
      conversation_id: convo.id,
      user_id: provider_user.id,
      joined_at: now
    })
    |> Repo.insert!()

    ParticipantSchema.create_changeset(%{
      conversation_id: convo.id,
      user_id: data.parent_user.id,
      joined_at: now
    })
    |> Repo.insert!()

    # Generate 4-6 messages alternating between participants
    msg_count = 4 + :rand.uniform(3) - 1
    senders = [provider_user.id, data.parent_user.id]

    direct_messages = [
      "Hello! I have a question about the program schedule.",
      "Of course! How can I help?",
      "Are there any spots available for next month?",
      "Yes, we still have a few openings. Would you like me to reserve one?",
      "That would be great, thank you!",
      "Done! I've noted your interest. You can complete the enrollment online."
    ]

    msgs =
      Enum.map(0..(msg_count - 1), fn i ->
        MessageSchema.create_changeset(%{
          conversation_id: convo.id,
          sender_id: Enum.at(senders, rem(i, 2)),
          content: Enum.at(direct_messages, rem(i, length(direct_messages))),
          message_type: "text"
        })
        |> Repo.insert!()
      end)

    {pc + 2, mc + length(msgs)}
  end)

# Broadcast conversation participants and messages
{participant_count, message_count} =
  Enum.zip(inserted_broadcast_convos, broadcast_conversations)
  |> Enum.reduce({participant_count, message_count}, fn {convo, data}, {pc, mc} ->
    provider_user =
      case data.provider.id do
        id when id == pro_1.id -> pro_1_user
        id when id == biz.id -> biz_user
        _ -> nil
      end

    # Provider is always a participant in broadcasts
    ParticipantSchema.create_changeset(%{
      conversation_id: convo.id,
      user_id: provider_user.id,
      joined_at: now
    })
    |> Repo.insert!()

    # Add 2-3 parent users as participants
    broadcast_parent_users = Enum.take(Enum.drop(parent_users, 6), 3)

    added_parents =
      Enum.map(broadcast_parent_users, fn parent_user ->
        ParticipantSchema.create_changeset(%{
          conversation_id: convo.id,
          user_id: parent_user.id,
          joined_at: now
        })
        |> Repo.insert!()
      end)

    broadcast_messages = [
      "Welcome to the program broadcast channel! Important updates will be shared here.",
      "Reminder: Next session starts at the usual time. Please bring water bottles.",
      "Great progress this week! Keep up the practice at home."
    ]

    msgs =
      Enum.map(broadcast_messages, fn content ->
        MessageSchema.create_changeset(%{
          conversation_id: convo.id,
          sender_id: provider_user.id,
          content: content,
          message_type: "text"
        })
        |> Repo.insert!()
      end)

    {pc + 1 + length(added_parents), mc + length(msgs)}
  end)

Logger.info("Created #{participant_count} conversation participants")
Logger.info("Created #{message_count} messages")

# ==============================================================================
# S18: REBUILD CQRS READ MODEL PROJECTIONS
# ==============================================================================

# Trigger: seeds inserted directly into write tables, bypassing integration events
# Why: projection GenServers only bootstrap on startup — seeding after startup leaves
#      read tables empty (e.g. program_listings, conversation_summaries)
# Outcome: all read tables rebuilt from authoritative write data
Logger.info("Rebuilding CQRS projections...")

# Order matters: VerifiedProviders must be rebuilt first because ProgramListings
# reads provider verification status from it during bootstrap
VerifiedProviders.rebuild()
ProgramListings.rebuild()
ConversationSummaries.rebuild()

Logger.info("Rebuilt CQRS projections")

# ==============================================================================
# S19: SUMMARY
# ==============================================================================

Logger.info("Seeding complete!")
Logger.info("Summary:")

Logger.info(
  "  Users: #{length(parent_users) + 1 + length(provider_users)} (#{length(parent_users)} parents, 1 admin, #{length(provider_users)} providers)"
)

Logger.info("  Parent profiles: #{length(parent_profiles)}")
Logger.info("  Provider profiles: #{length(provider_profiles)}")
Logger.info("  Children: #{length(child_records)}")
Logger.info("  Child-guardian links: #{length(children)}")
Logger.info("  Consents: #{length(children)}")
Logger.info("  Staff members: #{length(staff_members)}")
Logger.info("  Verification documents: #{length(verification_documents)}")
Logger.info("  Programs: #{length(inserted_programs)}")
Logger.info("  Enrollment policies: #{length(enrollment_policy_programs)}")
Logger.info("  Participant policies: #{length(participant_policy_data)}")
Logger.info("  Enrollments: #{length(enrollment_records)}")
Logger.info("  Program sessions: #{length(session_records)}")
Logger.info("  Participation records: #{length(participation_records)}")
Logger.info("  Behavioral notes: #{length(behavioral_notes)}")
Logger.info("  Conversations: #{length(all_conversations)}")
Logger.info("  Conversation participants: #{participant_count}")
Logger.info("  Messages: #{message_count}")
