"""
main.py
=======
Entrypoint for the SafeNav backend.

* Adds the bundled Depth-Anything-V2 source tree to sys.path so the
  `depth_anything_v2` package imports cleanly without a pip install.
* Configures logging (the api.server module also configures it; calling
  it from here just means the URL banner is captured in logs/server.log too).
* Discovers the VM's LAN IP and prints a copy-pastable URL.
* Boots uvicorn against api.server:app on 0.0.0.0:<PORT>.

Run:
    python main.py                # default port 8000
    PORT=9000 python main.py      # override
    SKIP_MODEL_LOAD=1 python main.py   # smoke-test without loading models
"""
from __future__ import annotations

import os
import sys

ROOT = os.path.dirname(os.path.abspath(__file__))

# Make the bundled DAV2 source importable as `depth_anything_v2.*`.
# The repo ships TWO copies: a relative-depth one at Depth-Anything-V2/ and
# a metric-depth one at Depth-Anything-V2/metric_depth/. We use the metric
# variant because models/depth_anything.py loads the metric checkpoints and
# passes `max_depth` to the constructor (only the metric variant accepts it).
_DAV2_SRC = os.path.join(ROOT, "Depth-Anything-V2", "metric_depth")
if os.path.isdir(_DAV2_SRC) and _DAV2_SRC not in sys.path:
    sys.path.insert(0, _DAV2_SRC)

# Ensure project root is on sys.path (so `utils.*`, `api.*`, `models.*` import).
if ROOT not in sys.path:
    sys.path.insert(0, ROOT)

# DepthAnythingModel resolves checkpoints relative to cwd as "checkpoints/...".
# Run uvicorn from the project root so that path resolves to our symlink.
os.chdir(ROOT)


def _print_url_banner(host: str, port: int) -> None:
    from api.server import get_lan_ip, log

    lan_ip = get_lan_ip()
    bind = host if host != "0.0.0.0" else "0.0.0.0"
    urls = [
        f"http://{lan_ip}:{port}",
        f"http://127.0.0.1:{port}",
    ]
    ws_urls = [u.replace("http://", "ws://") + "/ws/avoidance" for u in urls]

    banner = [
        "",
        "=" * 64,
        f" SafeNav backend listening on {bind}:{port}",
        "",
        " HTTP endpoints:",
        *[f"   {u}/health" for u in urls],
        "",
        " WebSocket endpoint:",
        *[f"   {u}" for u in ws_urls],
        "=" * 64,
        "",
    ]
    msg = "\n".join(banner)
    print(msg, flush=True)
    log.info("URL banner:\n%s", msg)


def main() -> None:
    import uvicorn

    host = os.environ.get("HOST", "0.0.0.0")
    port = int(os.environ.get("PORT", "8000"))

    _print_url_banner(host, port)

    uvicorn.run(
        "api.server:app",
        host=host,
        port=port,
        log_level=os.environ.get("UVICORN_LOG_LEVEL", "info"),
        reload=False,
        ws_max_size=32 * 1024 * 1024,   # allow up to ~32 MB JPEG frames
    )


if __name__ == "__main__":
    main()
