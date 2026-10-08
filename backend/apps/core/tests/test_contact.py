from rest_framework.test import APITestCase

from apps.core.models import SystemSetting

URL = "/api/v1/client/contact/"


class PublicContactTests(APITestCase):
    def test_empty_when_not_configured(self):
        self.assertEqual(self.client.get(URL).json(), {"contact_phone": "", "contact_whatsapp": ""})

    def test_returns_admin_values_without_authentication(self):
        SystemSetting.objects.create(key="contact_phone", value=" 0100000000 ")
        SystemSetting.objects.create(key="contact_whatsapp", value="")
        SystemSetting.objects.create(key="ticket_hold_minutes", value=10)
        response = self.client.get(URL)
        self.assertEqual(response.status_code, 200)
        self.assertEqual(response.json(), {"contact_phone": "0100000000", "contact_whatsapp": ""})

    def test_non_text_value_is_treated_as_empty(self):
        SystemSetting.objects.create(key="contact_phone", value=12345)
        self.assertEqual(self.client.get(URL).json()["contact_phone"], "")
