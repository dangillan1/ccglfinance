---
name: qbo-bill-from-image
description: Turn a photo, scan, screenshot, or PDF (single-page OR multi-page batch) of one or more vendor invoices/bills into real A/P Bills in QuickBooks Online via the ccgl-qbo MCP. Trigger ANY time Dan uploads a picture, scan, screenshot, or PDF of an invoice, bill, statement, or payable — including PDFs containing many bills at once — even if he just says "add this to QBO", "book this", "process these bills", "here's another one", or just drops the file with no text. Also trigger when he describes a bill verbally (vendor + amount + invoice number) and asks to enter it. Do NOT use this skill for receipts that are already paid (those are Expenses, not Bills) — but DO use it for any unpaid invoice that should sit in payables.
---

# QBO Bill from Image or PDF

Turn vendor invoice images and PDFs (single bill OR multi-page batch of many bills) into real Bills (A/P) in QuickBooks Online. This is the formalized version of the workflow Dan and Claude have already done manually — see `/sessions/hopeful-inspiring-babbage/mnt/.auto-memory/feedback_qbo_create_bill.md` for the underlying memory if you want the full backstory.

## When to use this skill

Use it whenever Dan provides one or more invoice images/PDFs and wants them recorded as unpaid bills in QBO. The trigger is permissive on purpose — better to load the skill and exit early if the image turns out to be a paid receipt than to miss the workflow entirely.

Do **not** use this skill for:
- Already-paid receipts where Dan wants an Expense record (use `post_expense` directly)
- Bank-feed for-review transactions (use `categorize_transaction` / `update_purchase_category`)
- Customer invoices Dan is sending out (those are A/R, different entity)

## The required tools

This skill assumes the `ccgl-qbo` MCP is connected and these tools are available:
- `mcp__ccgl-qbo__run_qbo_query` — for vendor lookups, dedupe checks, and historical account lookups
- `mcp__ccgl-qbo__create_bill` — the actual write
- `mcp__ccgl-qbo__list_accounts` — only if you need to confirm an account name

If `create_bill` is missing, the ccgl-qbo MCP at `/Users/dangillan/ccgl_qbo` needs the patch from `feedback_qbo_create_bill.md`. Don't fall back to `post_expense` — that creates the wrong record type and Dan will reject it. Stop and tell him the MCP needs updating.

## Input shapes

Dan typically delivers bills one of three ways:

1. **A single phone photo** of one invoice — straightforward, one bill to extract.
2. **A single PDF or screenshot** of one invoice — same as above.
3. **A multi-page PDF containing many bills** — the most common batch case. Each page is a separate invoice, sometimes from different vendors. The Read tool renders PDF pages as images, so you can extract data page-by-page just like with photos. Process every page, build one combined plan table, then push everything in parallel after Dan says "go". (This is exactly the pattern used for the `Payables Scan 4_6_26.pdf` batch — 8 bills, multiple vendors, single PDF.)

For a multi-page PDF with > ~10 pages, Read requires a `pages` parameter (e.g. `pages: "1-10"`). Process in chunks if needed and tell Dan up front how many pages you're seeing.

## Workflow

### 1. Extract bill data from each image/page

For each image or PDF page Dan provides, pull out:
- **Vendor name** (as it appears on the invoice — NOT the "remit to" if different)
- **Invoice / document number** (sometimes labeled "Invoice #", "Document #", "Statement #", "Account #" — pick the most uniquely-identifying one)
- **Bill date** / invoice date — convert to `YYYY-MM-DD`
- **Due date** if shown — convert to `YYYY-MM-DD`. If not shown, leave blank or compute Net 30 from bill date and flag it for Dan in the plan
- **Total amount due** (the amount Dan will pay — usually "Total Due" or "Balance Forward + Current Charges", NOT individual line items)
- **Brief memo** describing what it's for, if non-obvious from the vendor name

If the image is unclear or rotated, do your best and flag low-confidence fields in the plan table so Dan can correct before you push.

### 2. Match each vendor to an existing QBO vendor — never create new ones

For each extracted vendor name, query QBO with a substring LIKE to find the existing vendor:

```
SELECT Id, DisplayName FROM Vendor WHERE DisplayName LIKE '%<core name>%'
```

Use the most distinctive word from the invoice name (e.g. "Airgas", "Eversource", "Seaside") — not articles, not "Inc.", not "LLC". If you get exactly one match, use it. If you get multiple, pick the closest by full name and note it in the plan. If you get zero matches, **stop and ask Dan** before doing anything else — he has been clear about not wanting new vendors created automatically.

The full vendor list is now properly paginated (the `get_vendors()` function in qbo_client.py was patched to fetch all pages — Dan has 340+ vendors, the old 200-cap caused silent vendor-lookup failures for vendors alphabetically past "S").

### 3. Dedupe against existing bills

Before pushing anything, check if any of the bills you're about to create already exist:

```
SELECT Id, DocNumber, VendorRef, TotalAmt FROM Bill WHERE DocNumber IN ('<num1>', '<num2>', ...)
```

If a DocNumber already matches an existing Bill, mark that row as "skip — duplicate" in the plan and do not push it. (Dan has had real cases where the same invoice was scanned twice — RAM #55930 was a recent example.)

### 4. Pick the expense account from the vendor's history

For each vendor, look up their most recent Bill in QBO and read what account was used for the line items. Same vendor → same account is the default and is right ~95% of the time.

```
SELECT * FROM Bill WHERE VendorRef = '<vendor_id>' ORDER BY MetaData.CreateTime DESC MAXRESULTS 1
```

The query above returns sparse Bills with empty `Line: []`, which won't tell you the account. To see the account, fetch the full record:

```
SELECT * FROM Bill WHERE Id = '<recent_bill_id>'
```

The full (non-sparse) representation includes `Line[].AccountBasedExpenseLineDetail.AccountRef` with both the `value` (id) and `name` (full account name). Use the `name` field for the `account_name` parameter to `create_bill` — the lookup is case-insensitive and substring-tolerant, so the exact full name from QBO is the safest bet.

Common CCGL mappings (from history):
- **Airgas** → COGS - Cultivation Supplies
- **Eversource** → Production Overhead:Facility Cost - Electric
- **Seaside Alarms Inc.** → Security Expense
- **National Grid** → Production Overhead:Facility Cost - Gas (verify in history)
- New vendor types → derive from history; if no history exists, ask Dan

### 5. Present the plan as a table and wait for "go"

Always show Dan a markdown table before pushing. He has explicit feedback on this: plan-then-go is his preferred pattern. The table should have these columns:

| # | Vendor (matched) | Doc # | Bill date | Due date | Amount | Account | Status |
|---|---|---|---|---|---|---|---|

Status values:
- `new` — will be pushed
- `skip — duplicate of Bill <id>` — will not be pushed
- `⚠ low confidence: <field>` — pushed but Dan should glance at it
- `🛑 needs decision: <reason>` — blocked, waiting on Dan

End the plan with the total amount about to be posted and one of these prompts:
- "Reply 'go' to push, or tell me what to change."
- If anything is `🛑`, ask the specific question first and DON'T offer "go" yet.

### 6. On "go", push all bills in parallel

`create_bill` is idempotent enough to run in parallel — Dan has 7+ bills at a time and waiting serially is annoying. Fire all the `mcp__ccgl-qbo__create_bill` calls in a single turn (one tool block, multiple invocations).

### 7. Verify after pushing

After all the bills come back with IDs, run one query to confirm they all landed correctly:

```
SELECT Id, DocNumber, VendorRef, TxnDate, DueDate, TotalAmt FROM Bill WHERE Id IN ('<id1>', '<id2>', ...)
```

Show Dan the verified results in a compact table with the new Bill IDs, the total posted, and a count of any that were skipped as dupes. Don't write a long summary — the table is enough.

## Failure modes and what to do

**`Vendor not found: <name>`** — The substring lookup inside `create_bill` failed even though you matched it earlier. Two likely causes: (1) you're passing a name with extra punctuation like "Inc." that isn't in the canonical name, try a simpler core word; (2) the vendor really isn't there (you matched the wrong one), back to step 2. Don't create the vendor — ask Dan.

**`Account not found: <name>`** — You guessed an account name that doesn't exist in the chart of accounts. Run `list_accounts` (or query `Account` directly) and pick the closest match, then retry. Don't push with a wrong account just to make the call succeed.

**HTTP 400 from QBO** — Usually a malformed payload or a bad date format. Echo the payload to Dan, don't retry blindly.

**Missing due date** — If the invoice has no due date and you can't infer Net 30 from terms, push without a due date (the field is optional) but flag it in the verification table so Dan can edit later.

**Multi-line bills (different categories on one invoice)** — `create_bill` currently only takes one expense account per bill. If a real invoice has line items that should hit two different accounts, push it as a single bill with the dominant account and tell Dan he'll need to split the line items in the QBO UI. Don't try to be clever and split into two bills — that misrepresents the invoice.

## Example interaction

**Dan uploads `bill1.jpg` (an Airgas invoice for $432.10)**

> Got it — extracting now.
>
> Found 1 bill:
>
> | # | Vendor | Doc # | Bill date | Due date | Amount | Account | Status |
> |---|---|---|---|---|---|---|---|
> | 1 | Airgas (Id 30) | 9170123456 | 2026-04-02 | 2026-05-02 | $432.10 | COGS - Cultivation Supplies | new |
>
> Total: $432.10 · No duplicates found · Reply "go" to push.

**Dan: "go"**

> ✅ Bill 6241 created. Verified in QBO with the right vendor, dates, and amount.

That's the whole loop.
