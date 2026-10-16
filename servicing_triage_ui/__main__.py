from __future__ import annotations

import argparse
import os
import webbrowser
from pathlib import Path

from .app import App, import_report, serve
from .security import Guard
from .store import Store
from .sumo_index import SumoIndex, sync

DEFAULT_PORT = 4177


def main() -> None:
    parser = argparse.ArgumentParser(prog="servicing_triage_ui", description="Local UI for servicing failure triage")
    parser.add_argument("command", nargs="?", default="serve", choices=["serve", "sync-monitors", "import"])
    parser.add_argument("file", nargs="?", help="saved failure_triage output, for the import command")
    parser.add_argument("--port", type=int, default=int(os.environ.get("TRIAGE_UI_PORT", DEFAULT_PORT)))
    parser.add_argument("--sumo-config", type=Path, help="sumologic-config checkout (default: the tool's own clone)")
    parser.add_argument("--cwd", type=Path, default=Path.home() / "code", help="directory interactive sessions start in")
    parser.add_argument("--open", action="store_true", help="open the UI in the default browser")
    args = parser.parse_args()

    store = Store()
    monitors_clone = store.home / "sumologic-config"
    if args.command == "sync-monitors":
        print("sumologic-config at", sync(monitors_clone))
        return
    if args.command == "import":
        if not args.file:
            parser.error("import needs a file")
        report = import_report(store, Path(args.file))
        print(f"imported {len(report['findings'])} findings")
        return

    sumo_root = args.sumo_config or monitors_clone
    sumo = SumoIndex(sumo_root if sumo_root.exists() else None)
    app = App(store, Guard(args.port), sumo, args.cwd)
    server = serve(app, args.port)
    url = f"http://127.0.0.1:{args.port}/"
    print(f"Servicing triage UI on {url}  (Ctrl-C to stop)")
    print(f"  data: {store.home}")
    print(f"  claude: {app.claude or 'NOT FOUND (refresh, investigate and launch are disabled)'}")
    print(f"  sumo monitors: {len(sumo.monitors) or 'none indexed (run: python3 -m servicing_triage_ui sync-monitors)'}")
    if args.open:
        webbrowser.open(url)
    try:
        server.serve_forever()
    except KeyboardInterrupt:
        pass


if __name__ == "__main__":
    main()
