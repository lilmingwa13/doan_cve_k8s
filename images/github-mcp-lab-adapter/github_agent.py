"""Safe Kubernetes observation adapter for the vulnerable GitHub MCP sample.

The two ``os.environ`` assignments below are the upstream risky primitive:
Streamlit sessions share one Python process, so a value written by session A
can be read by session B.  This adapter never calls OpenAI, GitHub, Docker, or
an MCP server.  In the exposed namespace it sends *only synthetic LAB_* test
credentials to an in-cluster sink, which hashes the credential immediately and
records the observed session/credential relationship.
"""

import hashlib
import json
import os
from textwrap import dedent
from urllib.error import URLError
from urllib.request import Request, urlopen
from uuid import uuid4

import streamlit as st


def hash20(value: str) -> str:
    return hashlib.sha256(value.encode("utf-8")).hexdigest()[:20]


def lab_actor(value: str) -> str:
    """Extract A/B from LAB_OPENAI_A_* or LAB_GITHUB_B_* identifiers."""
    parts = str(value or "").split("_")
    if len(parts) >= 3 and parts[0] == "LAB" and parts[2] in {"A", "B"}:
        return parts[2]
    return "unknown"


def require_lab_value(value: str, prefix: str) -> bool:
    return bool(value) and value.startswith(prefix)


def post_observation(sink_url: str, requester: str, credential: str, source: str, repo: str, query: str) -> dict:
    """Send the synthetic credential as a bearer header to a local-only sink.

    The sink never persists the raw value; it returns only its SHA-256 prefix.
    This is intentional: the downstream component receives the effective
    credential, while all displayed/reportable data stay non-sensitive.
    """
    payload = {
        "eventId": str(uuid4()),
        "requesterSession": requester,
        "credentialSource": source,
        "repository": repo,
        "querySha256_20": hash20(query),
        "labMode": os.getenv("LAB_MODE", "unknown"),
    }
    request = Request(
        sink_url,
        data=json.dumps(payload).encode("utf-8"),
        method="POST",
        headers={
            "Content-Type": "application/json",
            "Authorization": f"Bearer {credential}",
            "X-Lab-Component": "github-mcp-vulnerable-adapter",
        },
    )
    with urlopen(request, timeout=5) as response:  # nosec B310: fixed in-cluster URL from deployment
        return json.loads(response.read().decode("utf-8"))


st.set_page_config(page_title="GitHub MCP Agent — Kubernetes lab", page_icon="🐙", layout="wide")
st.title("🐙 GitHub MCP Agent")
st.caption("Vulnerable session-state sample with a local Kubernetes observation adapter")

with st.sidebar:
    st.header("🔑 Credentials")

    openai_key = st.text_input("OpenAI API Key", type="password", help="Session label giả lập; không gọi OpenAI")
    if openai_key:
        # Intentionally retained vulnerable primitive from the sample.
        os.environ["OPENAI_API_KEY"] = openai_key

    github_token = st.text_input("GitHub Token", type="password", help="Token giả lập; không gọi GitHub")
    if github_token:
        # Intentionally retained vulnerable primitive from the sample.
        os.environ["GITHUB_TOKEN"] = github_token

repo = st.text_input("Repository", value="lab/example-repository")
query = st.text_area("Your Query", value="List the safe lab fixture result")
sink_url = os.getenv("LAB_GITHUB_SINK_URL", "").strip()

if st.button("🚀 Run Query", type="primary", use_container_width=True):
    effective_openai = openai_key or os.getenv("OPENAI_API_KEY", "")
    effective_github = github_token or os.getenv("GITHUB_TOKEN", "")

    if not require_lab_value(effective_openai, "LAB_OPENAI_"):
        st.error("Nhập OpenAI API Key giả lập dạng LAB_OPENAI_A_* hoặc LAB_OPENAI_B_*.")
    elif not require_lab_value(effective_github, "LAB_GITHUB_"):
        st.error("Nhập GitHub Token giả lập LAB_GITHUB_A_* ở phiên A trước; phiên B có thể để trống để kiểm tra state dùng chung.")
    else:
        requester = lab_actor(effective_openai)
        credential_source = "session input" if github_token else "process-global os.environ fallback"
        if sink_url:
            try:
                record = post_observation(sink_url, requester, effective_github, credential_source, repo, query)
                st.success("Đã ghi nhận tại github-credential-sink nội bộ của namespace exposed.")
                st.json(record)
            except (URLError, TimeoutError, ValueError) as exc:
                st.error(f"Không gọi được credential sink nội bộ: {exc}")
        else:
            st.info("Credential sink nội bộ chưa được cấu hình. Đây là luồng hợp lệ không gửi credential sang dịch vụ khác.")
            st.markdown(dedent(f"""\
                ### Local business-path result
                - Requesting session: `{requester}`
                - Effective GitHub credential SHA-256/20: `{hash20(effective_github)}`
                - Credential source: `{credential_source}`
                - External GitHub/OpenAI/MCP transport: **not invoked**
            """))

st.markdown("---")
st.caption("Phạm vi adapter: xác nhận state toàn tiến trình và đường đi tới một service nội bộ; không phải bằng chứng rằng GitHub/OpenAI thật đã nhận token.")
