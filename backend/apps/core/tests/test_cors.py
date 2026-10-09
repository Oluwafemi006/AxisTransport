from django.test import TestCase, override_settings


@override_settings(CORS_ALLOWED_ORIGINS=["https://site.exemple.test"])
class CorsPreflightTests(TestCase):
    """Le site (autre origine que l'API) doit pouvoir envoyer le jeton d'une réservation sans compte."""

    def preflight(self, origin, headers):
        return self.client.options(
            "/api/v1/client/bookings/1/checkout/",
            HTTP_ORIGIN=origin,
            HTTP_ACCESS_CONTROL_REQUEST_METHOD="POST",
            HTTP_ACCESS_CONTROL_REQUEST_HEADERS=headers,
        )

    def test_booking_token_header_is_allowed_for_a_known_origin(self):
        response = self.preflight("https://site.exemple.test", "content-type,x-booking-token")
        allowed = response["Access-Control-Allow-Headers"].lower()
        self.assertIn("x-booking-token", allowed)
        self.assertIn("authorization", allowed)
        self.assertEqual(response["Access-Control-Allow-Origin"], "https://site.exemple.test")

    def test_unknown_origin_gets_no_cors_permission(self):
        response = self.preflight("https://autre.exemple.test", "content-type,x-booking-token")
        self.assertNotIn("Access-Control-Allow-Origin", response)
