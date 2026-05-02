"""Thin Redmine REST client used by every CLI command."""

from __future__ import annotations

import sys
from typing import Any, Iterator

import requests

from .config import Credential


# Exit codes — kept identical to those documented in README.
EXIT_OK = 0
EXIT_NOT_FOUND = 2
EXIT_VALIDATION = 3
EXIT_AUTH = 4
EXIT_NETWORK = 5


class APIError(Exception):
    def __init__(self, message: str, *, status: int | None = None, exit_code: int = EXIT_NETWORK,
                 payload: Any = None):
        super().__init__(message)
        self.status = status
        self.exit_code = exit_code
        self.payload = payload


class Client:
    """Wraps requests.Session with credential and error handling.

    Methods return parsed JSON on success and raise APIError otherwise.
    """

    def __init__(self, cred: Credential, *, timeout: float = 30.0):
        self.cred = cred
        self.timeout = timeout
        self.session = requests.Session()
        self.session.headers.update(cred.headers)
        self.session.headers.update({"Accept": "application/json"})

    # ---- low-level ----
    def _url(self, path: str) -> str:
        if path.startswith("http://") or path.startswith("https://"):
            return path
        return f"{self.cred.url}/{path.lstrip('/')}"

    def request(self, method: str, path: str, *, params: dict | None = None,
                json: Any = None, data: Any = None, files: Any = None,
                headers: dict | None = None, raw: bool = False) -> Any:
        url = self._url(path)
        try:
            resp = self.session.request(
                method, url, params=params, json=json, data=data, files=files,
                headers=headers, timeout=self.timeout,
            )
        except requests.RequestException as e:
            raise APIError(f"network error: {e}", exit_code=EXIT_NETWORK) from e

        if 200 <= resp.status_code < 300:
            if raw:
                return resp
            if resp.status_code == 204 or not resp.content:
                return None
            ctype = resp.headers.get("content-type", "")
            if "json" in ctype:
                return resp.json()
            return resp.content

        # Map HTTP errors to APIError.
        msg, payload = self._error_message(resp)
        if resp.status_code == 404:
            raise APIError(msg, status=404, exit_code=EXIT_NOT_FOUND, payload=payload)
        if resp.status_code == 422:
            raise APIError(msg, status=422, exit_code=EXIT_VALIDATION, payload=payload)
        if resp.status_code in (401, 403):
            raise APIError(msg, status=resp.status_code, exit_code=EXIT_AUTH, payload=payload)
        raise APIError(msg, status=resp.status_code, exit_code=EXIT_NETWORK, payload=payload)

    @staticmethod
    def _error_message(resp: requests.Response) -> tuple[str, Any]:
        try:
            data = resp.json()
        except ValueError:
            return f"HTTP {resp.status_code}: {resp.text[:200]}", None
        if isinstance(data, dict) and "errors" in data:
            errs = data["errors"]
            if isinstance(errs, list):
                return f"HTTP {resp.status_code}: {'; '.join(str(e) for e in errs)}", data
        return f"HTTP {resp.status_code}: {data}", data

    # ---- convenience ----
    def get(self, path: str, **params) -> Any:
        return self.request("GET", path, params=params or None)

    def post(self, path: str, json: Any = None, **kwargs) -> Any:
        return self.request("POST", path, json=json, **kwargs)

    def put(self, path: str, json: Any = None, **kwargs) -> Any:
        return self.request("PUT", path, json=json, **kwargs)

    def patch(self, path: str, json: Any = None, **kwargs) -> Any:
        return self.request("PATCH", path, json=json, **kwargs)

    def delete(self, path: str, **kwargs) -> Any:
        return self.request("DELETE", path, **kwargs)

    # ---- pagination ----
    def paginate(self, path: str, *, key: str, page_size: int = 100,
                 limit: int | None = None, **params) -> Iterator[dict]:
        """Yield items across pages from a Redmine list endpoint.

        `key` is the response array name (e.g. "issues", "projects").
        Stop when `limit` items have been yielded (None = all).
        """
        offset = 0
        yielded = 0
        while True:
            page_params = {**params, "limit": page_size, "offset": offset}
            data = self.get(path, **page_params)
            items = data.get(key, [])
            if not items:
                return
            for item in items:
                yield item
                yielded += 1
                if limit is not None and yielded >= limit:
                    return
            total = data.get("total_count")
            offset += len(items)
            if total is not None and offset >= total:
                return
            if len(items) < page_size:
                return


def die(msg: str, code: int = EXIT_NETWORK) -> None:
    print(f"error: {msg}", file=sys.stderr)
    raise SystemExit(code)
