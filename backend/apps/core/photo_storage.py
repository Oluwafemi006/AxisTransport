import hashlib
import io
import json
import time
import urllib.error
import urllib.request
import uuid

from django.conf import settings
from django.core.exceptions import ValidationError
from PIL import Image, UnidentifiedImageError

UPLOAD_TIMEOUT_SECONDS = 30
MAX_PHOTO_BYTES = 5 * 1024 * 1024
PARCEL_FOLDER = "axis/colis"
VEHICLE_FOLDER = "axis/vehicules"
# Photos de véhicule : formats acceptés (type réel lu par Pillow) et plus grand côté après réduction.
VEHICLE_FORMATS = {"JPEG", "PNG", "WEBP"}
VEHICLE_MAX_SIDE_PX = 1600


def upload_parcel_photo(photo):
    """Photo de colis : envoyée telle quelle dans le dossier des colis (comportement inchangé)."""
    return upload_photo(photo, folder=PARCEL_FOLDER)


def prepare_vehicle_photo(photo):
    """
    Vérifie le vrai type de l'image (JPG, PNG, WebP), la réduit à 1600 px au plus et la recompresse en JPEG.
    Le nom d'origine n'est pas gardé : Cloudinary attribue un identifiant non prévisible.
    """
    if photo.size > MAX_PHOTO_BYTES:
        raise ValidationError("Photo trop lourde (5 Mo maximum).")
    try:
        image = Image.open(photo)
        image.verify()
        photo.seek(0)
        image = Image.open(photo)
        kind = image.format
        image.load()
    except (UnidentifiedImageError, OSError, SyntaxError) as exc:
        raise ValidationError("Ce fichier n'est pas une image lisible (JPG, PNG ou WebP).") from exc
    if kind not in VEHICLE_FORMATS:
        raise ValidationError("Format refusé : envoyez une photo JPG, PNG ou WebP.")
    image.thumbnail((VEHICLE_MAX_SIDE_PX, VEHICLE_MAX_SIDE_PX))
    buffer = io.BytesIO()
    image.convert("RGB").save(buffer, format="JPEG", quality=82, optimize=True)
    data = buffer.getvalue()
    return _Bytes(data)


class _Bytes:
    """Fichier en mémoire avec la même interface que les fichiers envoyés (size, read)."""

    def __init__(self, data):
        self._data = data
        self.size = len(data)

    def read(self):
        return self._data


def upload_photo(photo, *, folder):
    """
    Envoie une photo à Cloudinary dans `folder` et renvoie (url, public_id).
    Tout l'échange tient ici : changer de stockage (VPS) ne touchera que ce fichier.
    """
    cloud, key, secret = settings.CLOUDINARY_CLOUD_NAME, settings.CLOUDINARY_API_KEY, settings.CLOUDINARY_API_SECRET
    if not (cloud and key and secret):
        raise ValidationError("Le stockage des photos n'est pas configuré.")
    if photo.size > MAX_PHOTO_BYTES:
        raise ValidationError("Photo trop lourde (5 Mo maximum).")
    params = {"folder": folder, "timestamp": str(int(time.time()))}
    to_sign = "&".join(f"{name}={params[name]}" for name in sorted(params))
    signature = hashlib.sha1(f"{to_sign}{secret}".encode()).hexdigest()
    fields = {**params, "api_key": key, "signature": signature}
    boundary = uuid.uuid4().hex
    body = bytearray()
    for name, value in fields.items():
        body += f'--{boundary}\r\nContent-Disposition: form-data; name="{name}"\r\n\r\n{value}\r\n'.encode()
    body += f'--{boundary}\r\nContent-Disposition: form-data; name="file"; filename="photo.jpg"\r\n'.encode()
    body += b"Content-Type: image/jpeg\r\n\r\n" + photo.read() + f"\r\n--{boundary}--\r\n".encode()
    request = urllib.request.Request(
        f"https://api.cloudinary.com/v1_1/{cloud}/image/upload",
        data=bytes(body),
        headers={"Content-Type": f"multipart/form-data; boundary={boundary}"},
    )
    try:
        with urllib.request.urlopen(request, timeout=UPLOAD_TIMEOUT_SECONDS) as response:
            payload = json.load(response)
    except (urllib.error.URLError, TimeoutError, ValueError) as exc:
        raise ValidationError("La photo n'a pas pu être enregistrée. Réessayez.") from exc
    return payload["secure_url"], payload["public_id"]
