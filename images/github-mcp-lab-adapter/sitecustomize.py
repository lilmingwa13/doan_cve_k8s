"""Hash-only instrumentation used by the GitHub MCP lab adapter.

It records a fingerprint and length when the adapter writes a synthetic
credential to process-global ``os.environ``. It never stores the value.
"""
import hashlib
import json
import os
import time

_sensitive = {"OPENAI_API_KEY", "GITHUB_TOKEN", "GITHUB_PERSONAL_ACCESS_TOKEN"}
_original_setitem = os._Environ.__setitem__


def _recording_setitem(self, key, value):
    result = _original_setitem(self, key, value)
    if str(key) in _sensitive:
        event = {
            "ts": time.time(),
            "pid": os.getpid(),
            "key": str(key),
            "value_length": len(str(value)),
            "sha256_20": hashlib.sha256(str(value).encode()).hexdigest()[:20],
        }
        try:
            with open("/tmp/lab-env-events.jsonl", "a", encoding="utf-8") as handle:
                handle.write(json.dumps(event, sort_keys=True) + "\\n")
        except OSError:
            pass
    return result


os._Environ.__setitem__ = _recording_setitem
