from django.db import transaction
from django.db.models.signals import post_delete, post_save

from .models import LineStop, Location, Route, RouteStop, SegmentFare, Trip
from .services import invalidate_segment_catalog


def _invalidate(**_kwargs):
    # Aussi après validation : une lecture pendant la transaction remettrait sinon l'ancienne liste en cache.
    invalidate_segment_catalog()
    transaction.on_commit(invalidate_segment_catalog)


for model in (SegmentFare, Trip, LineStop, Location, Route, RouteStop):
    post_save.connect(_invalidate, sender=model, dispatch_uid=f"segments-save-{model.__name__}")
    post_delete.connect(_invalidate, sender=model, dispatch_uid=f"segments-delete-{model.__name__}")
