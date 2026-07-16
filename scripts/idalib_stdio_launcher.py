#!/usr/bin/env python3
"""Stdio MCP launcher for ida-pro-mcp's idalib (headless) server.

Upstream `idalib_server.main()` only exposes the Streamable-HTTP transport, which
forces users to start a long-lived server manually. This launcher reuses the exact
same initialization (session manager, unsafe-tool gating, context-activation hooks,
all @tool registrations from idalib_server) but drives the underlying MCP_SERVER
over **stdio** instead, so an MCP client (e.g. Hermes) can spawn it on demand.

Binaries are loaded at runtime via the `idalib_open` tool -- no initial file needed.

Requires: idalib activated for this interpreter (import idapro works) and the
ida_pro_mcp package importable. Intended to run under:
  ~/.local/share/ida-pro-mcp-venv/bin/python
"""
import logging
import os
import sys

# idalib emits a harmless RuntimeWarning when a different venv is active in the
# environment; drop VIRTUAL_ENV so it uses this interpreter's prefix cleanly.
os.environ.pop("VIRTUAL_ENV", None)

import idapro  # noqa: E402  (activates idalib; must import before ida_* modules)

# Importing idalib_server registers every @tool (idalib_open/close/switch/list,
# plus all the ida_mcp analysis tools: decompile, disasm, func_query, xrefs, ...).
from ida_pro_mcp import idalib_server  # noqa: E402
from ida_pro_mcp.ida_mcp import MCP_SERVER, MCP_UNSAFE  # noqa: E402
from ida_pro_mcp.idalib_session_manager import get_session_manager  # noqa: E402


def main() -> None:
    # Logs must go to stderr -- stdout is the MCP transport.
    logging.basicConfig(level=logging.INFO, stream=sys.stderr)
    idapro.enable_console_messages(False)

    # Shared-fallback context mode (matches the server's default, non-isolated).
    idalib_server._ISOLATED_CONTEXTS_ENABLED = False
    get_session_manager()  # initialize the manager singleton

    # Gate unsafe tools off (same policy as the default HTTP server).
    for name in MCP_UNSAFE:
        MCP_SERVER.tools.methods.pop(name, None)

    # Stdio uses a single shared context, never per-request HTTP sessions.
    MCP_SERVER.require_streamable_http_session = False
    idalib_server._install_context_activation_hooks()

    logging.getLogger(__name__).info(
        "idalib stdio launcher ready -- load binaries with idalib_open()"
    )
    MCP_SERVER.stdio()


if __name__ == "__main__":
    main()
