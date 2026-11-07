"""Coordonnées des pages /privacy et /suppression-compte : publiques, saisies dans /admin, sans IFU ni RCCM."""
from rest_framework.test import APITestCase

from apps.core.models import AgencyProfile, SystemSetting

URL = "/api/v1/client/privacy-contact/"


class PrivacyContactTests(APITestCase):
    def test_empty_when_nothing_is_entered(self):
        response = self.client.get(URL)
        self.assertEqual(response.status_code, 200)
        self.assertEqual(response.json(), {"legal_name": "", "email": "", "contact_phone": "", "contact_whatsapp": ""})

    def test_admin_values_without_login_and_never_registration_numbers(self):
        agency = AgencyProfile.current()
        agency.legal_name, agency.email, agency.ifu, agency.rccm, agency.bank_accounts = (
            " TEST agence ", "contact.test@exemple.test", "TEST-IFU", "TEST-RCCM", "TEST-banque",
        )
        agency.save()
        SystemSetting.objects.create(key="contact_phone", value="TEST 0100000000")
        payload = self.client.get(URL).json()
        self.assertEqual(payload["legal_name"], "TEST agence")
        self.assertEqual(payload["email"], "contact.test@exemple.test")
        self.assertEqual(payload["contact_phone"], "TEST 0100000000")
        self.assertNotIn("TEST-IFU", str(payload))
        self.assertNotIn("TEST-RCCM", str(payload))
        self.assertNotIn("TEST-banque", str(payload))
