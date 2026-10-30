import hashlib
import json
import time
import urllib.error
import urllib.request
import uuid

from django.conf import settings
from django.core.exceptions import ValidationError

UPLOAD_TIMEOUT_SECONDS = 30
MAX_PHOTO_BYTES = 5 * 1024 * 1024


def upload_parcel_photo(photo):
    """
    Envoie une photo à Cloudinary et renvoie (url, public_id).
    Tout l'échange tient ici : changer de stockage (VPS) ne touchera que ce fichier.
    """
    cloud, key, secret = settings.CLOUDINARY_CLOUD_NAME, settings.CLOUDINARY_API_KEY, settings.CLOUDINARY_API_SECRET
    if not (cloud and key and secret):
        raise ValidationError("Le stockage des photos n'est pas configuré.")
    if photo.size > MAX_PHOTO_BYTES:
        raise ValidationError("Photo trop lourde (5 Mo maximum).")
    params = {"folder": "axis/colis", "timestamp": str(int(time.time()))}
    to_sign = "&".join(f"{name}={params[name]}" for name in sorted(params))
    signature = hashlib.sha1(f"{to_sign}{secret}".encode()).hexdigest()
    fields = {**params, "api_key": key, "signature": signature}
    boundary = uuid.uuid4().hex
    body = bytearray()
    for name, value in fields.items():
        body += f'--{boundary}\r\nContent-Disposition: form-data; name="{name}"\r\n\r\n{value}\r\n'.encode()
    body += f'--{boundary}\r\nContent-Disposition: form-data; name="file"; filename="colis.jpg"\r\n'.encode()
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
