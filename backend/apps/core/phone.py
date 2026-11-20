"""Numéro de téléphone d'un compte : une seule forme en base, « +229 » suivi de 10 chiffres commençant par 01."""
import re

_SEPARATORS = re.compile(r"[\s.\-()]")


def normalize_benin_phone(value):
    """
    Forme unique d'un numéro béninois, ou None s'il n'en est pas un.
    Acceptés : 0197000000, 01 97 00 00 00, 01.97.00.00.00, 01-97-00-00-00, +229 01…, 00229 01…, 229 01….
    Les anciens numéros à 8 chiffres (sans le 01) ne sont pas acceptés.
    """
    text = _SEPARATORS.sub("", str(value or "").strip())
    if text.startswith("+229"):
        text = text[4:]
    elif text.startswith("00229"):
        text = text[5:]
    elif text.startswith("229") and len(text) == 13:
        text = text[3:]
    if re.fullmatch(r"01\d{8}", text):
        return f"+229{text}"
    return None
