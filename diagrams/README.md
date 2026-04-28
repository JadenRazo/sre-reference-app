# Architecture diagrams as code

The two PNGs at `docs/architecture-runtime.png` and `docs/architecture-deploy.png` are generated from `architecture.py` using [mingrammer/diagrams](https://diagrams.mingrammer.com/), which wraps Graphviz with the official AWS Web Services icon set. The README and `docs/architecture.md` both embed those PNGs.

The point of doing this in code: the diagram does not drift from reality. When the Terraform changes, you change the Python and regenerate. No "I'll update the lucidchart later" debt.

## Regenerate

Requires the system `graphviz` package:

```
sudo apt-get install -y graphviz       # Debian / Ubuntu
brew install graphviz                  # macOS
```

Then:

```
cd diagrams
python3 -m venv .venv
.venv/bin/pip install -r requirements.txt
.venv/bin/python architecture.py
```

Output lands in `../docs/architecture-runtime.png` and `../docs/architecture-deploy.png`. Commit the PNGs alongside the script.

## Editing tips

- **Layout direction**: the `direction="LR"` arg controls left-to-right vs `TB` top-to-bottom.
- **Edge style**: `Edge(style="dashed", color="#6E7B91")` for metric flows, `Edge(color="#1F6FEB", penwidth="2")` for the primary request path. The convention is enforced by repetition, not by a wrapper.
- **Subgraphs**: `Cluster(...)` blocks. Keep nesting at most two levels deep. The Mermaid version of this diagram failed because nested subgraphs produced visual noise on every label.
- **Avoid IGW as a separate node**. It is implicit when an ALB is internet-facing, and adding it to the diagram costs a node and an arrow without adding information.

If a diagram looks cramped, try the alternate direction or move a node out of a cluster. Graphviz's `splines="ortho"` is on by default in this script, which gives clean orthogonal edges but can produce crossings in dense graphs; switching to `splines="polyline"` or `splines="curved"` is the next thing to try.
