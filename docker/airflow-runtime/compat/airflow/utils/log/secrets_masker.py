"""
Backwards compatibility shim for Airflow 3.x.

Airflow 3.1 relocated the secrets masker utilities to
``airflow._shared.secrets_masker``.  Providers released for Airflow 2.x (and
still bundled with apache-airflow 3.1) continue to import
``airflow.utils.log.secrets_masker``.  This module re-exports the public API
from the new location so legacy imports continue to function.
"""

from __future__ import annotations

from airflow._shared import secrets_masker as _secrets_masker_impl

DEFAULT_SENSITIVE_FIELDS = _secrets_masker_impl.DEFAULT_SENSITIVE_FIELDS
Redactable = _secrets_masker_impl.Redactable
Redacted = _secrets_masker_impl.Redacted
RedactedIO = getattr(_secrets_masker_impl, "RedactedIO", None)
SecretsMasker = _secrets_masker_impl.SecretsMasker

mask_secret = _secrets_masker_impl.mask_secret
redact = _secrets_masker_impl.redact
reset_secrets_masker = _secrets_masker_impl.reset_secrets_masker
should_hide_value_for_key = _secrets_masker_impl.should_hide_value_for_key
merge = _secrets_masker_impl.merge
_secrets_masker = _secrets_masker_impl._secrets_masker
_is_v1_env_var = _secrets_masker_impl._is_v1_env_var

__all__ = [
    "SecretsMasker",
    "mask_secret",
    "redact",
    "reset_secrets_masker",
    "should_hide_value_for_key",
    "merge",
    "_secrets_masker",
    "_is_v1_env_var",
    "DEFAULT_SENSITIVE_FIELDS",
    "Redactable",
    "Redacted",
    "RedactedIO",
]
