defmodule KlassHeroWeb.PrivacyPolicyLive do
  use KlassHeroWeb, :live_view

  alias KlassHero.Contact
  alias KlassHeroWeb.Theme

  @impl true
  def mount(_params, _session, socket) do
    socket =
      socket
      |> assign(page_title: gettext("Privacy Policy"))
      |> assign(active_nav: :legal)

    {:ok, socket}
  end

  defp last_updated, do: "February 1, 2026"

  defp privacy_sections do
    email = Contact.email() |> Phoenix.HTML.html_escape() |> Phoenix.HTML.safe_to_string()

    [
      %{
        id: "introduction",
        icon: "hero-information-circle",
        gradient: Theme.gradient(:cool),
        title: gettext("Introduction"),
        content: """
        <p class="mb-4">Welcome to Klass Hero's Privacy Policy. At Klass Hero, we connect families with enriching afterschool programs, camps, and educational activities. We understand that when you entrust us with your family's information, you expect us to handle it responsibly and transparently.</p>
        <p class="mb-4">This Privacy Policy explains what information we collect, how we use it, and your rights regarding your personal data. We are committed to protecting your privacy and complying with data protection laws, including GDPR.</p>
        <p class="font-semibold text-gray-900">Last Updated: #{last_updated()}</p>
        """
      },
      %{
        id: "information-collected",
        icon: "hero-document-text",
        gradient: Theme.gradient(:primary),
        title: gettext("Information We Collect"),
        content: """
        <p class="mb-4">To provide our platform services, we collect the following types of information:</p>
        <h4 class="font-semibold text-gray-900 mb-2">Account Information:</h4>
        <ul class="list-disc pl-6 mb-4 space-y-1">
          <li>Email address (for login and communication)</li>
          <li>Password (encrypted and never stored in plain text using bcrypt)</li>
          <li>Parent/guardian name</li>
        </ul>
        <h4 class="font-semibold text-gray-900 mb-2">Child Information:</h4>
        <ul class="list-disc pl-6 mb-4 space-y-1">
          <li>Child's first and last name (for enrollment and identification)</li>
          <li>Date of birth (to match age-appropriate programs)</li>
          <li>Emergency contact information</li>
          <li>Optional: support needs and allergies — parent-controlled, shared with program providers only when you explicitly consent</li>
        </ul>
        <h4 class="font-semibold text-gray-900 mb-2">Booking Information:</h4>
        <ul class="list-disc pl-6 mb-4 space-y-1">
          <li>Program enrollments and preferences</li>
          <li>Schedule selections</li>
          <li>Communication history with instructors</li>
        </ul>
        <h4 class="font-semibold text-gray-900 mb-2">Payment Information:</h4>
        <ul class="list-disc pl-6 mb-4 space-y-1">
          <li>We accept credit card, direct transfer, and cash payments</li>
          <li>For credit card payments, we use third-party payment processors</li>
          <li>We do not store credit card numbers or banking details</li>
          <li>We only retain transaction records for accounting purposes</li>
        </ul>
        <h4 class="font-semibold text-gray-900 mb-2">Usage Information:</h4>
        <ul class="list-disc pl-6 space-y-1">
          <li>Pages visited on our platform</li>
          <li>Device and browser information</li>
          <li>Session data (essential for platform functionality)</li>
        </ul>
        """
      },
      %{
        id: "how-we-use",
        icon: "hero-cog-6-tooth",
        gradient: Theme.gradient(:warm_yellow),
        title: gettext("How We Use Your Information"),
        content: """
        <p class="mb-4">We use the information we collect for the following purposes:</p>
        <ul class="list-disc pl-6 space-y-2">
          <li><strong>Program Enrollment:</strong> To facilitate registration and enrollment in afterschool programs, camps, and activities</li>
          <li><strong>Communication:</strong> To send important updates about programs, bookings, and platform changes</li>
          <li><strong>Platform Improvement:</strong> To understand how our platform is used and improve functionality</li>
          <li><strong>Safety & Security:</strong> To verify instructor credentials and maintain secure facilities</li>
          <li><strong>Legal Compliance:</strong> To meet legal and regulatory requirements</li>
        </ul>
        """
      },
      %{
        id: "data-sharing",
        icon: "hero-share",
        gradient: Theme.gradient(:cool_magenta),
        title: gettext("Data Sharing"),
        content: """
        <p class="mb-4">We take your privacy seriously and limit data sharing to what's necessary:</p>
        <h4 class="font-semibold text-gray-900 mb-2">Program Providers:</h4>
        <p class="mb-4">Providers see enrolled children's names for program management. Optional safety information (support needs, allergies) is visible to providers only when a parent explicitly consents to share it. Session notes written by providers about a child require parent approval before being displayed.</p>
        <h4 class="font-semibold text-gray-900 mb-2">Payment Processors:</h4>
        <p class="mb-4">For credit card payments, we work with third-party payment processors who handle transaction processing securely. They only receive the information necessary to process payments.</p>
        <h4 class="font-semibold text-gray-900 mb-2">Platform Administrators:</h4>
        <p class="mb-4">Our staff can read messages exchanged on the platform, for child safety, abuse prevention and to meet our legal obligations. Access is read-only — administrators cannot post, edit or delete messages in your conversations — and every access is logged. Conversations with a provider display a notice telling you this. We look at message content only when there is a safeguarding, abuse or legal reason to.</p>
        <h4 class="font-semibold text-gray-900 mb-2">What We Don't Do:</h4>
        <ul class="list-disc pl-6 space-y-1">
          <li><strong>We never sell your personal data</strong> to third parties</li>
          <li><strong>We never share your data</strong> with advertisers or marketers</li>
          <li><strong>We never use your data</strong> for purposes other than those stated in this policy</li>
        </ul>
        """
      },
      %{
        id: "user-rights",
        icon: "hero-shield-check",
        gradient: Theme.gradient(:safety),
        title: gettext("Your Privacy Rights"),
        content: """
        <p class="mb-4">Under GDPR and other data protection laws, you have the following rights:</p>
        <h4 class="font-semibold text-gray-900 mb-2">Right to Access:</h4>
        <p class="mb-4">You can request a copy of all personal data we hold about you. Use the <strong>"Export My Data"</strong> feature in your Settings page to download your information as a JSON file.</p>
        <h4 class="font-semibold text-gray-900 mb-2">Right to Deletion:</h4>
        <p class="mb-4">You can request deletion of your account at any time from your Settings page. When you delete your account, we immediately anonymize your email and name. Note that some information may be retained for legal or accounting purposes (such as completed booking records).</p>
        <h4 class="font-semibold text-gray-900 mb-2">Right to Correction:</h4>
        <p class="mb-4">You can update your profile information at any time through the Settings page.</p>
        <h4 class="font-semibold text-gray-900 mb-2">Right to Data Portability:</h4>
        <p class="mb-4">Your exported data is provided in a standard JSON format that can be used with other services.</p>
        <h4 class="font-semibold text-gray-900 mb-2">Right to Object:</h4>
        <p class="mb-4">You can object to certain types of data processing. Contact us at #{email} to discuss your concerns.</p>
        <p class="mt-4 p-4 bg-blue-50 border border-blue-200 rounded-lg">
          <strong class="text-blue-900">To exercise any of these rights:</strong> Visit your Settings page or contact us at <a href="mailto:#{email}" class="text-blue-600 hover:underline">#{email}</a>
        </p>
        """
      },
      %{
        id: "data-security",
        icon: "hero-lock-closed",
        gradient: Theme.gradient(:primary),
        title: gettext("Data Security"),
        content: """
        <p class="mb-4">We take data security seriously and implement multiple layers of protection:</p>
        <ul class="list-disc pl-6 space-y-2">
          <li><strong>Encryption in Transit:</strong> All data transmitted between your device and our servers is encrypted using HTTPS</li>
          <li><strong>Password Security:</strong> Passwords are hashed using bcrypt and never stored in plain text</li>
          <li><strong>Access Controls:</strong> We limit access to personal data to authorized personnel only</li>
          <li><strong>Regular Updates:</strong> We keep our systems updated with the latest security patches</li>
          <li><strong>Monitoring:</strong> We actively monitor for security threats and suspicious activity</li>
        </ul>
        <p class="mt-4">While we implement robust security measures, no system is 100% secure. We encourage you to use strong, unique passwords and contact us immediately if you suspect unauthorized access to your account.</p>
        """
      },
      %{
        id: "children-privacy",
        icon: "hero-heart",
        gradient: Theme.gradient(:cool_magenta),
        title: gettext("Children's Privacy"),
        content: """
        <p class="mb-4">Klass Hero is designed to help parents manage their children's activities. We prioritize protection for children's data, strict data minimization, role-based access, and explicit parental consent for any optional health-related notes shared solely for safety and participation purposes.</p>
        <ul class="list-disc pl-6 space-y-2 mb-4">
          <li><strong>Parental Consent:</strong> Parents or legal guardians must create accounts and provide consent for their children's participation</li>
          <li><strong>Consent-Gated Sharing:</strong> Optional safety information (support needs, allergies) is shared with program providers only when a parent explicitly consents</li>
          <li><strong>Data Minimization:</strong> Only a child's name and date of birth are required; all health and safety notes are optional and parent-controlled</li>
          <li><strong>Session Notes:</strong> Observations written by providers about a child require parent approval before they are displayed</li>
          <li><strong>COPPA Compliance:</strong> We comply with the Children's Online Privacy Protection Act (COPPA) for children under 13</li>
          <li><strong>Limited Collection:</strong> We only collect the minimum information necessary for program enrollment and safety</li>
          <li><strong>No Direct Marketing:</strong> We never market directly to children or collect information from them for marketing purposes</li>
        </ul>
        <p class="p-4 bg-amber-50 border border-amber-200 rounded-lg">
          <strong class="text-amber-900">Important:</strong> Children should never create accounts or provide personal information without parental permission.
        </p>
        """
      },
      %{
        id: "cookies",
        icon: "hero-computer-desktop",
        gradient: Theme.gradient(:warm_yellow),
        title: gettext("Cookies & Tracking"),
        content: """
        <p class="mb-4">Klass Hero uses minimal tracking to provide essential functionality:</p>
        <h4 class="font-semibold text-gray-900 mb-2">Essential Cookies:</h4>
        <p class="mb-4">We use session cookies that are necessary for authentication and platform functionality. These cookies do not track you across other websites and are automatically deleted when you close your browser or log out.</p>
        <h4 class="font-semibold text-gray-900 mb-2">No Third-Party Tracking:</h4>
        <p class="mb-4">We do not currently use analytics, advertising, or other third-party tracking cookies. If this changes in the future, we will update this policy and request your consent before implementing such tracking.</p>
        <p class="mt-4 p-4 bg-green-50 border border-green-200 rounded-lg">
          <strong class="text-green-900">Good News:</strong> Since we only use essential cookies, you don't need to worry about complex cookie consent or settings. Your privacy is protected by default.
        </p>
        """
      },
      %{
        id: "data-retention",
        icon: "hero-clock",
        gradient: Theme.gradient(:cool),
        title: gettext("Data Retention"),
        content: """
        <p class="mb-4">We retain your personal data only as long as necessary:</p>
        <ul class="list-disc pl-6 space-y-2">
          <li><strong>Active Accounts:</strong> Information is retained while your account is active and you continue using our services</li>
          <li><strong>Deleted Accounts:</strong> When you delete your account, personal identifiers (email, name) are immediately anonymized</li>
          <li><strong>Booking Records:</strong> Transaction records may be retained for legal and accounting requirements (typically 7 years)</li>
          <li><strong>Anonymized Data:</strong> Anonymized data used for statistical purposes may be retained indefinitely as it cannot be linked back to you</li>
        </ul>
        """
      },
      %{
        id: "policy-changes",
        icon: "hero-arrow-path",
        gradient: Theme.gradient(:primary),
        title: gettext("Changes to This Policy"),
        content: """
        <p class="mb-4">We may update this Privacy Policy from time to time to reflect changes in our practices or legal requirements.</p>
        <h4 class="font-semibold text-gray-900 mb-2">How We Notify You:</h4>
        <ul class="list-disc pl-6 space-y-2 mb-4">
          <li>We will update the "Last Updated" date at the top of this policy</li>
          <li>For material changes, we will send an email notification to all active users</li>
          <li>Continued use of Klass Hero after changes constitute acceptance of the updated policy</li>
        </ul>
        <p>We encourage you to review this policy periodically to stay informed about how we protect your information.</p>
        """
      },
      %{
        id: "contact",
        icon: "hero-envelope",
        gradient: Theme.gradient(:cool_magenta),
        title: gettext("Contact Us"),
        content: """
        <p class="mb-4">If you have any questions about this Privacy Policy or how we handle your data, please contact us:</p>
        <div class="space-y-2">
          <p><strong>Email:</strong> <a href="mailto:#{email}" class="text-blue-600 hover:underline">#{email}</a></p>
          <p><strong>General Inquiries:</strong> <a href="mailto:#{email}" class="text-blue-600 hover:underline">#{email}</a></p>
        </div>
        <p class="mt-4">You can also reach us through our <a href="/contact" class="text-blue-600 hover:underline">Contact Page</a>.</p>
        """
      }
    ]
  end

  @impl true
  def render(assigns) do
    ~H"""
    <.document_page
      eyebrow_pill={gettext("Privacy")}
      title={gettext("Privacy Policy")}
      subtitle={gettext("Your privacy matters to us")}
      last_updated={last_updated()}
      sections={privacy_sections()}
      cta_title={gettext("Questions About Privacy?")}
      cta_body={gettext("We're here to help with any privacy-related concerns.")}
    />
    """
  end
end
