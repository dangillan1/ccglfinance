#!/usr/bin/env python3
"""
CCGL Finance Dashboard — Nightly Update Script
Runs at midnight via launchd. Fetches live QBO data, rebuilds the dashboard
HTML, and pushes to GitHub. No interaction required.

First-time setup — set QBO_DIR to the full path of your ccgl_qbo folder:
    QBO_DIR = "/Users/dangillan/path/to/ccgl_qbo"
"""

import sys, json, re, subprocess, os, logging
from datetime import date, timedelta
from pathlib import Path

# ── CONFIG ────────────────────────────────────────────────────────────────
SCRIPT_DIR  = Path(__file__).resolve().parent
HTML_FILE   = SCRIPT_DIR / "CCGL_Finance_Dashboard.html"
LOG_FILE    = SCRIPT_DIR / "update.log"
REPO_DIR    = SCRIPT_DIR          # git repo lives here
GITHUB_REMOTE = "origin"          # git remote name

# Path to your ccgl_qbo folder (contains auth.py, qbo_client.py, config.json)
# Tries sibling directory first, then falls back to this explicit path:
_sibling = SCRIPT_DIR.parent / "ccgl_qbo"
QBO_DIR = _sibling if _sibling.exists() else Path("/Users/dangillan/ccgl_qbo")

# ── LOGGING ───────────────────────────────────────────────────────────────
logging.basicConfig(
    filename=str(LOG_FILE),
    level=logging.INFO,
    format="%(asctime)s  %(levelname)s  %(message)s",
    datefmt="%Y-%m-%d %H:%M:%S",
)
log = logging.getLogger("ccgl_update")

# ── QBO IMPORTS ───────────────────────────────────────────────────────────
sys.path.insert(0, str(QBO_DIR))
try:
    from auth import get_valid_token, load_config
    from qbo_client import query as qbo_query, get_realm_id
except ImportError as e:
    log.error(f"Cannot import QBO modules from {QBO_DIR}: {e}")
    sys.exit(1)


# ── QBO DATA FETCH ────────────────────────────────────────────────────────
def fetch_open_invoices():
    result = qbo_query("SELECT * FROM Invoice WHERE Balance > '0' MAXRESULTS 200")
    return result.get("QueryResponse", {}).get("Invoice", [])

def fetch_open_bills():
    result = qbo_query("SELECT * FROM Bill WHERE Balance > '0' MAXRESULTS 200")
    return result.get("QueryResponse", {}).get("Bill", [])


# ── BUCKET LOGIC ──────────────────────────────────────────────────────────
EMBER_CUSTOMER = "Ember Gardens Cape Cod LLC"

def week_label(n, today):
    """Return 'Wk N · MMM D–D' label for week offset n from today."""
    start = today + timedelta(days=n * 7)
    end   = start + timedelta(days=6)
    if start.month == end.month:
        return f"Wk {n+1} · {start.strftime('%b %-d')}–{end.strftime('%-d')}"
    return f"Wk {n+1} · {start.strftime('%b %-d')}–{end.strftime('%b %-d')}"

def bucket_invoice(inv, today):
    """
    Return bucket key for an invoice: 'overdue', 'wk1'..'wk4', 'later'.
    Ember Gardens always goes to 'later' regardless of due date.
    """
    customer = inv.get("CustomerRef", {}).get("name", "")
    if EMBER_CUSTOMER in customer:
        return "later"

    due_str = inv.get("DueDate", "")
    if not due_str:
        return "later"
    due = date.fromisoformat(due_str)

    if due < today:
        return "overdue"
    delta = (due - today).days
    if delta <= 6:   return "wk1"
    if delta <= 13:  return "wk2"
    if delta <= 20:  return "wk3"
    if delta <= 27:  return "wk4"
    return "later"

def build_ar_buckets(invoices, today):
    buckets = {k: [] for k in ["overdue", "wk1", "wk2", "wk3", "wk4", "later"]}
    for inv in invoices:
        inv_id   = int(inv.get("DocNumber") or inv.get("Id", 0))
        customer = inv.get("CustomerRef", {}).get("name", "Unknown")
        amt      = float(inv.get("Balance", 0))
        due_str  = inv.get("DueDate", "")
        due      = date.fromisoformat(due_str) if due_str else None
        days_od  = max(0, (today - due).days) if due and due < today else 0
        due_fmt  = due.strftime("%b %-d") if due else ""
        bkt      = bucket_invoice(inv, today)
        entry = {"name": customer, "amt": round(amt, 2), "id": inv_id}
        if days_od:
            entry["daysOD"] = days_od
            entry["due"]    = due_fmt
        buckets[bkt].append(entry)

    # Sort overdue oldest first; others by amount desc
    buckets["overdue"].sort(key=lambda x: -x.get("daysOD", 0))
    for k in ["wk1", "wk2", "wk3", "wk4", "later"]:
        buckets[k].sort(key=lambda x: -x["amt"])

    return buckets

def compute_kpis(invoices, bills, today):
    total_ar     = sum(float(i.get("Balance", 0)) for i in invoices)
    overdue_ar   = sum(
        float(i.get("Balance", 0)) for i in invoices
        if i.get("CustomerRef", {}).get("name", "") != EMBER_CUSTOMER
        and i.get("DueDate", "") and date.fromisoformat(i["DueDate"]) < today
    )
    overdue_inv  = sum(
        1 for i in invoices
        if i.get("CustomerRef", {}).get("name", "") != EMBER_CUSTOMER
        and i.get("DueDate", "") and date.fromisoformat(i["DueDate"]) < today
    )
    total_bills  = sum(float(b.get("Balance", 0)) for b in bills)
    pct_od       = int(overdue_ar / total_ar * 100) if total_ar else 0
    unique_cust  = len(set(i.get("CustomerRef", {}).get("name", "") for i in invoices))

    return {
        "total_ar":    total_ar,
        "overdue_ar":  overdue_ar,
        "overdue_inv": overdue_inv,
        "total_bills": total_bills,
        "total_inv":   len(invoices),
        "unique_cust": unique_cust,
        "pct_od":      pct_od,
    }

def fmt_k(n):
    """Format number as $XXX.Xk"""
    return f"${n/1000:.1f}k"

def fmt_currency(n):
    """Format as $XX,XXX"""
    return f"${n:,.0f}"


# ── WEEK HEADER STRINGS ───────────────────────────────────────────────────
def week_date_range(offset_days, today):
    """Return 'Apr 6–12' style string."""
    start = today + timedelta(days=offset_days)
    end   = start + timedelta(days=6)
    if start.month == end.month:
        return f"{start.strftime('%b %-d')}–{end.strftime('%-d')}"
    return f"{start.strftime('%b %-d')}–{end.strftime('%b %-d')}"


# ── HTML PATCHING ─────────────────────────────────────────────────────────
def build_ar_buckets_js(buckets):
    """Render the arBuckets JS const."""
    lines = ["const arBuckets = {"]
    bucket_keys = ["overdue", "wk1", "wk2", "wk3", "wk4", "later"]
    for i, key in enumerate(bucket_keys):
        entries = buckets[key]
        comma = "," if i < len(bucket_keys) - 1 else ""
        lines.append(f'  "{key}":[')
        for j, e in enumerate(entries):
            ec = "," if j < len(entries) - 1 else ""
            if "daysOD" in e:
                lines.append(
                    f'    {{"name":"{e["name"]}","amt":{e["amt"]},"id":{e["id"]},'
                    f'"daysOD":{e["daysOD"]},"due":"{e["due"]}"}}{ec}'
                )
            else:
                lines.append(f'    {{"name":"{e["name"]}","amt":{e["amt"]},"id":{e["id"]}}}{ec}')
        lines.append(f"  ]{comma}")
    lines.append("};")
    return "\n".join(lines)

def patch_html(html, buckets, kpis, today):
    # ── arBuckets JS block ────────────────────────────────────────────────
    new_buckets_js = build_ar_buckets_js(buckets)
    html = re.sub(
        r'const arBuckets = \{.*?\};',
        new_buckets_js,
        html, flags=re.DOTALL
    )

    # ── KPI: Receivables Outstanding ─────────────────────────────────────
    html = re.sub(
        r'(<h3>Receivables Outstanding</h3>\s*<div class="kpi-val">)[^<]*(</div>\s*<div class="kpi-sub"><b>)\d+(</b> invoices · <b>)\d+(</b> unique accounts</div>)',
        lambda m: f'{m.group(1)}{fmt_k(kpis["total_ar"])}{m.group(2)}{kpis["total_inv"]}{m.group(3)}{kpis["unique_cust"]}{m.group(4)}',
        html
    )

    # ── KPI: Overdue AR ───────────────────────────────────────────────────
    html = re.sub(
        r'(<h3>Overdue AR</h3>\s*<div class="kpi-val clr-red">)[^<]*(</div>\s*<div class="kpi-sub"><b>)\d+(</b> invoices · <b>)\d+(</b>% of total AR</div>)',
        lambda m: f'{m.group(1)}{fmt_k(kpis["overdue_ar"])}{m.group(2)}{kpis["overdue_inv"]}{m.group(3)}{kpis["pct_od"]}{m.group(4)}',
        html
    )

    # ── KPI: Open Payables ────────────────────────────────────────────────
    html = re.sub(
        r'(<h3>Open Payables</h3>\s*<div class="kpi-val clr-gold">)[^<]*(</div>\s*<div class="kpi-sub"><b>)\d+(</b> bills · aging detail below</div>)',
        lambda m: f'{m.group(1)}{fmt_k(kpis["total_bills"])}{m.group(2)}{len([])}{m.group(3)}',
        html
    )
    # bills count separately (lambda can't easily capture from kpis)
    bill_count = sum(1 for _ in range(1))  # placeholder; do it directly:
    html = re.sub(
        r'(<h3>Open Payables</h3>\s*<div class="kpi-val clr-gold">)[^<]*(</div>\s*<div class="kpi-sub"><b>)\d+(</b> bills)',
        lambda m: f'{m.group(1)}{fmt_k(kpis["total_bills"])}{m.group(2)}{kpis["bill_count"]}{m.group(3)}',
        html
    )

    # ── AR bar: overdue segment ───────────────────────────────────────────
    html = re.sub(
        r'(<div class="ar-seg seg-red">.*?<span class="ar-seg-v">)[^<]*(</span>.*?<span class="ar-seg-c">)\d+ invoices(</span>)',
        lambda m: f'{m.group(1)}{fmt_currency(kpis["overdue_ar"])}{m.group(2)}{kpis["overdue_inv"]} invoices{m.group(3)}',
        html, flags=re.DOTALL
    )

    # ── Receivables meta line ─────────────────────────────────────────────
    html = re.sub(
        r'(Live from QBO · )\d+( invoices · )\d+( customers)',
        lambda m: f'{m.group(1)}{kpis["total_inv"]}{m.group(2)}{kpis["unique_cust"]}{m.group(3)}',
        html
    )

    # ── Week column headers in AR table ───────────────────────────────────
    wk_ranges = [week_date_range(i * 7, today) for i in range(1, 5)]
    for i, (offset, label) in enumerate(zip(range(1, 5), ["Wk 1", "Wk 2", "Wk 3", "Wk 4"])):
        new_range = wk_ranges[i]
        html = re.sub(
            rf'({re.escape(label)} · )[A-Za-z0-9–]+',
            lambda m, r=new_range: f'{m.group(1)}{r}',
            html
        )

    # ── AR bar week labels ────────────────────────────────────────────────
    ar_bar_labels = [
        ("Wk 1", week_date_range(0, today)),
        ("Wk 2", week_date_range(7, today)),
        ("Wk 3", week_date_range(14, today)),
        ("Wk 4", week_date_range(21, today)),
    ]
    for wk_label_str, date_range in ar_bar_labels:
        html = re.sub(
            rf'({re.escape(wk_label_str)} · )[A-Za-z0-9–]+(?=</span>)',
            lambda m, r=date_range: f'{m.group(1)}{r}',
            html
        )

    # ── Refresh timestamp ─────────────────────────────────────────────────
    ts = today.strftime("%B %-d, %Y")
    html = re.sub(
        r'Refreshed [A-Za-z]+ \d+, \d+',
        f'Refreshed {ts}',
        html
    )

    return html


# ── GIT PUSH ──────────────────────────────────────────────────────────────
def git_push(today):
    msg = f"nightly update {today.isoformat()}"
    cmds = [
        ["git", "-C", str(REPO_DIR), "add", "CCGL_Finance_Dashboard.html"],
        ["git", "-C", str(REPO_DIR), "commit", "-m", msg],
        ["git", "-C", str(REPO_DIR), "push", GITHUB_REMOTE, "HEAD"],
    ]
    for cmd in cmds:
        result = subprocess.run(cmd, capture_output=True, text=True)
        if result.returncode != 0:
            # "nothing to commit" is not a real error
            if "nothing to commit" in result.stdout + result.stderr:
                log.info("git: nothing to commit")
                return
            log.error(f"git error: {result.stderr.strip()}")
            raise RuntimeError(f"git failed: {' '.join(cmd)}\n{result.stderr}")
        log.info(f"git ok: {' '.join(cmd[2:])}")


# ── MAIN ──────────────────────────────────────────────────────────────────
def main():
    today = date.today()
    log.info(f"=== nightly update starting {today.isoformat()} ===")

    try:
        log.info("fetching QBO invoices...")
        invoices = fetch_open_invoices()
        log.info(f"  {len(invoices)} open invoices")

        log.info("fetching QBO bills...")
        bills = fetch_open_bills()
        log.info(f"  {len(bills)} open bills")

        buckets = build_ar_buckets(invoices, today)
        kpis    = compute_kpis(invoices, bills, today)
        kpis["bill_count"] = len(bills)

        log.info(f"  AR ${kpis['total_ar']:,.0f}  OD ${kpis['overdue_ar']:,.0f}  AP ${kpis['total_bills']:,.0f}")

        html = HTML_FILE.read_text(encoding="utf-8")
        html = patch_html(html, buckets, kpis, today)
        HTML_FILE.write_text(html, encoding="utf-8")
        log.info("dashboard HTML updated")

        git_push(today)
        log.info("pushed to GitHub ✓")

    except Exception as e:
        log.exception(f"update failed: {e}")
        sys.exit(1)

    log.info("=== done ===")


if __name__ == "__main__":
    main()
