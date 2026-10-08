from django.core.exceptions import ValidationError
from django.test import TestCase

from apps.core.models import Parcel
from apps.core.services import transition_parcel

from .factories import build_operational_context


class ParcelLifecycleTests(TestCase):
    def setUp(self):
        self.context = build_operational_context()
        self.parcel = Parcel.objects.create(
            customer=self.context["client"],
            sender_name="Expéditeur",
            sender_phone="00000000",
            recipient_name="Destinataire",
            recipient_phone="11111111",
            origin=self.context["origin"],
            destination=self.context["destination"],
            description="Colis test",
        )

    def test_strict_parcel_lifecycle(self):
        statuses = [
            Parcel.Status.DEPOSITED,
            Parcel.Status.ACCEPTED,
            Parcel.Status.ASSIGNED,
            Parcel.Status.LOADED,
            Parcel.Status.IN_TRANSIT,
            Parcel.Status.ARRIVED,
            Parcel.Status.READY_FOR_PICKUP,
            Parcel.Status.PICKED_UP,
        ]
        self.parcel.trip = self.context["trip"]
        self.parcel.pickup_recipient_identity = "Code configuré fourni"
        self.parcel.save()
        for next_status in statuses:
            self.parcel = transition_parcel(self.parcel, next_status, actor=self.context["admin"])
        self.assertEqual(self.parcel.status, Parcel.Status.PICKED_UP)
        self.assertEqual(self.parcel.status_history.count(), len(statuses))

    def test_cannot_skip_status(self):
        with self.assertRaises(ValidationError):
            transition_parcel(self.parcel, Parcel.Status.IN_TRANSIT, actor=self.context["admin"])

