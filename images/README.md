# Image definitions used by lab v3

Only the following directories are build inputs for the active namespace
`ai-cve-lab-exposed`:

| Directory | Image | Purpose |
|---|---|---|
| `beifong-boundary-model` | `lab/beifong-boundary-model:chapter3-v1` | Beifong boundary model with a synthetic filesystem canary. |
| `github-mcp-lab-adapter` | `lab/github-mcp-vuln-observer:chapter3-boundary-v2` | Local Streamlit adapter for observing process-global credential state. |
| `github-credential-sink` | `lab/github-credential-sink:chapter3-boundary-v1` | In-cluster hash-only event sink. |
| `paperclip` | `lab/paperclip-v0.3.1-ui-lab:chapter3-v1` | Paperclip v0.3.1 server/UI fixture. |

`beifong-frontend` is a build-time helper used by the Beifong Dockerfile.
Build and redeploy through `scripts/10-setup-ai-cve-lab.ps1` or
`scripts/92-redeploy-ai-cve-lab.ps1`; do not change image tags independently
of `k8s/exposed/01-workloads.yaml`.
