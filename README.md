# NPC Gift Entry Matching

A metadata-driven Apex batch engine for **Salesforce Nonprofit Cloud (NPC) Fundraising** that automatically pre-populates lookup fields on `GiftEntry` records and creates employer matching gift entries from Benevity donation data.

---

## Table of Contents

1. [Overview](#overview)
2. [Components](#components)
3. [Engine 1 — Gift Entry Matching](#engine-1--gift-entry-matching)
   - [How It Works](#how-it-works)
   - [Token Syntax](#token-syntax)
   - [Date Offset Tokens](#date-offset-tokens)
   - [First-Match-Wins](#first-match-wins)
   - [Match Score Fields](#match-score-fields)
   - [Included Matching Rules](#included-matching-rules)
4. [Engine 2 — Benevity Employer Matching](#engine-2--benevity-employer-matching)
   - [How It Works](#how-it-works-1)
   - [Custom Setting Reference](#custom-setting-reference)
   - [Setup Steps](#setup-steps)
5. [GiftBatch Page Action](#giftbatch-page-action)
6. [Deployment](#deployment)
7. [Custom Fields Reference](#custom-fields-reference)
8. [Creating & Managing Matching Rules](#creating--managing-matching-rules)
9. [Behavior Notes](#behavior-notes)
10. [Troubleshooting](#troubleshooting)

---

## Overview

This package solves two import-time problems:

| Problem | Solution |
|---|---|
| Imported `GiftEntry` records have blank lookup fields (`DonorId`, `CampaignId`, etc.) | **Engine 1** — `GiftEntryMatchingBatch` evaluates configurable SOQL-based rules to auto-populate 7 lookup fields |
| Benevity reports include an employer match amount that needs a separate gift record | **Engine 2** — `BenevityEmployerMatchingBatch` creates a new `GiftEntry` for the employer, driven entirely by a Hierarchy Custom Setting |

Both engines are triggered from a single Lightning Web Component on the **GiftBatch record page**.

---

## Components

```
force-app/main/default/
├── classes/
│   ├── GiftEntryMatchingBatch.cls              # Engine 1: lookup field matching batch
│   ├── GiftEntryMatchingBatchScheduler.cls     # Schedulable wrapper for Engine 1
│   ├── GiftEntryMatchingController.cls         # AuraEnabled controller for LWC (both engines)
│   ├── GiftEntryMatchingRuleEvaluator.cls      # Token substitution & rule evaluation engine
│   ├── GiftEntryMatchingBatchTest.cls          # Tests for Engine 1
│   ├── BenevityEmployerMatchingBatch.cls       # Engine 2: employer matching gift batch
│   ├── BenevityEmployerMatchingBatchTest.cls   # Tests for Engine 2
│   ├── DoubleMetaphoneUtil.cls                 # Phonetic matching utility
│   └── DoubleMetaphoneUtilTest.cls             # Tests for phonetic utility
├── customMetadata/
│   ├── GiftEntryMatchingRule.Donor_Match_By_Email.md-meta.xml
│   ├── GiftEntryMatchingRule.Donor_Match_By_Name.md-meta.xml
│   ├── GiftEntryMatchingRule.Donor_Match_By_Metaphone.md-meta.xml
│   ├── GiftEntryMatchingRule.GiftCommitment_Match_By_Donor.md-meta.xml
│   └── GiftEntryMatchingRule.GiftCommitment_Active_Installment.md-meta.xml
├── lwc/
│   └── giftEntryMatchingAction/                # Lightning component for GiftBatch page
│       ├── giftEntryMatchingAction.html
│       ├── giftEntryMatchingAction.js
│       └── giftEntryMatchingAction.js-meta.xml
└── objects/
    ├── Account/fields/
    │   └── Matching_Employer__c                # Lookup → employer Account
    ├── BenevityMatchingSettings__c/            # Hierarchy Custom Setting (Engine 2)
    │   └── fields/ (7 fields)
    ├── GiftEntry/fields/                       # Match score fields + Benevity fields
    └── GiftEntryMatchingRule__mdt/             # CMT object + field definitions
```

---

## Engine 1 — Gift Entry Matching

### How It Works

`GiftEntryMatchingBatch` queries all `GiftEntry` records in a `GiftBatch` and evaluates Custom Metadata rules to populate the following lookup fields **in strict sequential order**:

| Step | Field | Target Object |
|---|---|---|
| 1 | `DonorId` | `Account` |
| 2 | `GiftCommitmentId` | `GiftCommitment` |
| 3 | `OutreachSourceCodeId` | `OutreachSourceCode` |
| 4 | `CampaignId` | `Campaign` |
| 5 | `GiftDesignation1Id` | `GiftDesignation` |
| 6 | `GiftDesignation2Id` | `GiftDesignation` |
| 7 | `GiftDesignation3Id` | `GiftDesignation` |

Fields are resolved **sequentially** — a resolved value (e.g. `DonorId`) is immediately available as a token for rules in subsequent steps (e.g. `GiftCommitmentId`).

The batch automatically scans all active rules for `{!GiftEntry.*}` tokens and dynamically builds the `SELECT` clause to include every referenced field — **no code changes required** when you add new rules.

### Token Syntax

Reference any `GiftEntry` field value in a WHERE clause using:

```
{!GiftEntry.FieldApiName}
```

**Type handling is automatic:**

| Field Type | Output Example | Notes |
|---|---|---|
| String / Id | `'smith@example.com'` | Single-quoted and escaped |
| Date | `2024-03-11` | ISO format, no quotes |
| DateTime | `2024-06-01T12:00:00Z` | ISO format, no quotes |
| Boolean | `true` / `false` | Unquoted |
| Decimal / Number | `250.00` | Unquoted |

> **Important:** Never surround a token with single quotes — `toSoqlLiteral()` adds them automatically for string types.
>
> ✅ `PersonEmail = {!GiftEntry.Email}` → produces `PersonEmail = 'smith@example.com'`
>
> ❌ `PersonEmail = '{!GiftEntry.Email}'` → produces `PersonEmail = ''smith@example.com''`

**Example rules:**

```sql
-- Match Account by email
PersonEmail = {!GiftEntry.Email} AND IsPersonAccount = true

-- Match Account by first + last name
FirstName = {!GiftEntry.FirstName} AND LastName = {!GiftEntry.LastName} AND IsPersonAccount = true

-- Match GiftCommitment using already-resolved DonorId
DonorId = {!GiftEntry.DonorId} AND Status = 'Active'
```

### Date Offset Tokens

Date and DateTime fields support an optional `+N` / `-N` day offset, enabling date window queries:

```
{!GiftEntry.GiftReceivedDate-10}   → GiftReceivedDate minus 10 days
{!GiftEntry.GiftReceivedDate+10}   → GiftReceivedDate plus 10 days
```

This is used in the pre-built `GiftCommitment_Active_Installment` rule to replicate NPC's "Installment Extension Day Count" window:

```sql
DonorId = {!GiftEntry.DonorId}
AND Status = 'Active'
AND EffectiveStartDate != null
AND Id IN (
    SELECT GiftCommitmentId FROM GiftTransaction
    WHERE Status = 'Unpaid'
    AND DueDate >= {!GiftEntry.GiftReceivedDate-10}
    AND DueDate <= {!GiftEntry.GiftReceivedDate+10}
)
```

> **Tip:** Change `±10` to match your org's **Installment Extension Day Count** setting in General Fundraising Settings.

### First-Match-Wins

Rules targeting the same `TargetField__c` are evaluated in `Priority__c` ascending order. The first rule that returns a record wins; remaining rules for that field are skipped.

### Match Score Fields

For each populated lookup field, a companion currency field records the `Weight__c` of the winning rule (0.0–1.0). These fields provide a confidence audit trail.

| Lookup Field | Score Field |
|---|---|
| `DonorId` | `GEM_DonorMatchScore__c` |
| `GiftCommitmentId` | `GEM_GiftCommitmentMatchScore__c` |
| `OutreachSourceCodeId` | `GEM_OutreachSourceCodeMatchScore__c` |
| `CampaignId` | `GEM_CampaignMatchScore__c` |
| `GiftDesignation1Id` | `GEM_GiftDesignation1MatchScore__c` |
| `GiftDesignation2Id` | `GEM_GiftDesignation2MatchScore__c` |
| `GiftDesignation3Id` | `GEM_GiftDesignation3MatchScore__c` |

### Included Matching Rules

Five sample rules are deployed with the package:

| Record Name | Target Field | Logic |
|---|---|---|
| `Donor_Match_By_Email` | `DonorId` | Match Account by `PersonEmail` |
| `Donor_Match_By_Name` | `DonorId` | Match Account by `FirstName` + `LastName` |
| `Donor_Match_By_Metaphone` | `DonorId` | Phonetic name match via Double Metaphone |
| `GiftCommitment_Match_By_Donor` | `GiftCommitmentId` | Active commitment by resolved `DonorId` |
| `GiftCommitment_Active_Installment` | `GiftCommitmentId` | Active commitment with unpaid installment in ±10 day window |

All rules are inactive by default — activate the ones appropriate for your org.

---

## Engine 2 — Benevity Employer Matching

### How It Works

Benevity donation reports include two amount columns per row:
- **Total Donation to be Acknowledged** — the employee's gift (already on `GiftEntry` as `GiftAmount`)
- **Match Amount** — the employer's matching gift (stored in `Matching_Gift_Amount__c`)

`BenevityEmployerMatchingBatch` processes `GiftEntry` records that have a match amount and:
1. Resolves the employer `Account` Id by traversing a configurable dot-notation field path on the employee's donor Account
2. Creates a new `GiftEntry` for the employer, copying a configurable set of fields from the employee's entry
3. Overrides `DonorId` with the employer Account Id and `GiftAmount` with the match amount
4. Applies a default `PaymentMethod` if the field wasn't copied or is blank
5. Stamps `GEM_MatchingGiftCreated__c = true` on the original entry to prevent reprocessing

> **Prerequisite:** Run **Engine 1** first so that `DonorId` is resolved on employee entries before Engine 2 attempts to traverse the `Donor.Matching_Employer__c` path.

### Custom Setting Reference

Configure via **Setup → Custom Settings → Benevity Matching Settings → Manage → New**.

| Field | Type | Description | Example |
|---|---|---|---|
| `IsActive__c` | Checkbox | Master on/off switch | ✅ |
| `EmployeeGiftCondition__c` | TextArea | SOQL WHERE clause to select eligible employee gift entries | `Matching_Gift_Amount__c > 0 AND GEM_MatchingGiftCreated__c = false` |
| `EmployerIdPath__c` | Text(255) | SOQL dot-notation path from `GiftEntry` to the employer Account Id | `Donor.Matching_Employer__c` |
| `FieldsToCopy__c` | TextArea | Semicolon-separated `GiftEntry` API field names to clone onto the employer gift | `GiftBatchId;GiftReceivedDate;CurrencyIsoCode;GiftDesignation1Id` |
| `MatchAmountField__c` | Text(100) | API name of the field holding the employer match amount | `Matching_Gift_Amount__c` |
| `MatchFlagField__c` | Text(100) | API name of the boolean field stamped `true` after processing (prevents reprocessing) | `GEM_MatchingGiftCreated__c` |
| `DefaultPaymentMethod__c` | Text(50) | Fallback `PaymentMethod` picklist value applied when the field is not copied or is blank | `Check` |

**Employer path traversal** supports multi-level paths:

```
Donor.Matching_Employer__c          → GiftEntry → Account.Matching_Employer__c
Donor.Parent.Matching_Employer__c   → GiftEntry → Account → Parent Account.Matching_Employer__c
```

### Setup Steps

1. **Deploy** the package to your org
2. **Populate** `Matching_Employer__c` on employee donor `Account` records with the employer Account lookup
3. **Map the CSV column**: In your Benevity import mapping, map `Match Amount` → `Matching_Gift_Amount__c`
4. **Configure the Custom Setting** (Setup → Custom Settings → Benevity Matching Settings → Manage → New):

   ```
   Is Active:                    ✅
   Employee Gift Condition:      Matching_Gift_Amount__c > 0 AND GEM_MatchingGiftCreated__c = false
   Employer ID Field Path:       Donor.Matching_Employer__c
   Fields To Copy:               GiftBatchId;GiftReceivedDate;CurrencyIsoCode;GiftDesignation1Id
   Match Amount Field API Name:  Matching_Gift_Amount__c
   Match Flag Field API Name:    GEM_MatchingGiftCreated__c
   Default Payment Method:       Check
   ```

5. **Run Engine 1** first (resolves `DonorId`), then **Run Engine 2**

---

## GiftBatch Page Action

The `giftEntryMatchingAction` Lightning Web Component provides a no-code UI for triggering both engines directly from a **GiftBatch record page**.

### Adding to the GiftBatch Page

1. Open a **GiftBatch** record in Salesforce
2. Click the **gear icon ⚙️ → Edit Page**
3. Search for **"Gift Entry Matching"** in the left component panel
4. Drag it onto the page (sidebar or main column)
5. Click **Save → Activate**

### UI States & Buttons

| State | What the user sees |
|---|---|
| **Idle** | Two buttons: **Run Gift Entry Matching** and **Create Employer Matching Gifts** |
| **Running** | Spinner with contextual label (e.g. "Submitting matching batch job…") |
| **Success** | Green confirmation with the Apex Job ID + toast notification |
| **Error** | Red error message with retry button |

Monitor batch progress under **Setup → Apex Jobs**.

---

## Deployment

### Deploy to Org

```bash
sf project deploy start --target-org <your-org-alias>
```

### Run via Developer Console (Execute Anonymous)

**Engine 1 — Gift Entry Matching:**
```apex
Id giftBatchId = '0Ci...'; // paste your GiftBatch Id
Id jobId = Database.executeBatch(new GiftEntryMatchingBatch(giftBatchId), 50);
System.debug('Job Id: ' + jobId);
```

**Engine 2 — Employer Matching Gifts:**
```apex
Id giftBatchId = '0Ci...'; // paste your GiftBatch Id
Id jobId = Database.executeBatch(new BenevityEmployerMatchingBatch(giftBatchId), 50);
System.debug('Job Id: ' + jobId);
```

**Both in sequence (recommended order):**
```apex
Id giftBatchId = '0Ci...';
// Run matching first so DonorId is resolved before employer lookup
Id matchingJobId = Database.executeBatch(new GiftEntryMatchingBatch(giftBatchId), 50);
System.debug('Matching Job Id: ' + matchingJobId);
Id employerJobId = Database.executeBatch(new BenevityEmployerMatchingBatch(giftBatchId), 50);
System.debug('Employer Matching Job Id: ' + employerJobId);
```

> **Tip:** Find your GiftBatch Id in the record URL — it starts with `0Ci`.

### Schedule Engine 1 Nightly

```apex
Id giftBatchId = '0Ci...';
System.schedule(
    'Gift Entry Matching - Nightly',
    '0 0 2 * * ?',  // Every day at 2:00 AM
    new GiftEntryMatchingBatchScheduler(giftBatchId)
);
```

### Run Tests

```bash
# Engine 1
sf apex run test --class-names GiftEntryMatchingBatchTest --target-org <alias> --result-format human

# Engine 2
sf apex run test --class-names BenevityEmployerMatchingBatchTest --target-org <alias> --result-format human
```

---

## Custom Fields Reference

### On `GiftEntry`

| Field | Type | Purpose |
|---|---|---|
| `GEM_DonorMatchScore__c` | Decimal | Match confidence for `DonorId` (0.0–1.0) |
| `GEM_GiftCommitmentMatchScore__c` | Decimal | Match confidence for `GiftCommitmentId` |
| `GEM_OutreachSourceCodeMatchScore__c` | Decimal | Match confidence for `OutreachSourceCodeId` |
| `GEM_CampaignMatchScore__c` | Decimal | Match confidence for `CampaignId` |
| `GEM_GiftDesignation1MatchScore__c` | Decimal | Match confidence for `GiftDesignation1Id` |
| `GEM_GiftDesignation2MatchScore__c` | Decimal | Match confidence for `GiftDesignation2Id` |
| `GEM_GiftDesignation3MatchScore__c` | Decimal | Match confidence for `GiftDesignation3Id` |
| `Matching_Gift_Amount__c` | Currency | Employer match amount from Benevity `Match Amount` column |
| `GEM_MatchingGiftCreated__c` | Checkbox | `true` after employer gift entry has been created |
| `GEM_MatchAmount__c` | Currency | Legacy match amount field (use `Matching_Gift_Amount__c` instead) |
| `FirstName_MP_Primary__c` | Text | Double Metaphone primary code for first name |
| `FirstName_MP_Secondary__c` | Text | Double Metaphone secondary code for first name |
| `LastName_MP_Primary__c` | Text | Double Metaphone primary code for last name |
| `LastName_MP_Secondary__c` | Text | Double Metaphone secondary code for last name |

### On `Account`

| Field | Type | Purpose |
|---|---|---|
| `Matching_Employer__c` | Lookup (Account) | Links an individual donor to their employer's Account record |

---

## Creating & Managing Matching Rules

### Via Setup UI

1. Go to **Setup → Custom Metadata Types → Gift Entry Matching Rule → Manage Records**
2. Click **New** and fill in:
   - **Label** — descriptive name (max 40 characters)
   - **Target Field** — API name of the `GiftEntry` lookup to populate (e.g. `DonorId`)
   - **Target Object** — API name of the object to query (e.g. `Account`)
   - **SOQL WHERE Clause** — see [Token Syntax](#token-syntax) above
   - **Priority** — lower runs first (use gaps: 10, 20, 30)
   - **Weight** — confidence score 0.0–1.0
   - **Is Active** — must be checked to run

> **Tip:** Use gaps in priority numbers so you can insert rules later without renumbering.

### Using Custom Fields in Rules

Any `GiftEntry` field — including custom fields — can be referenced in a token. The batch automatically detects them and adds them to the query at runtime.

```sql
-- Custom field example
MySegmentCode__c = {!GiftEntry.MySegmentCode__c}
```

### Available Standard GiftEntry Token Fields

The following NPC standard fields are included in every query automatically:

`FirstName` · `LastName` · `Email` · `HomePhone` · `MobilePhone` · `Salutation` · `OrganizationName` · `Street` · `City` · `State` · `PostalCode` · `Country` · `GiftAmount` · `GiftType` · `GiftReceivedDate` · `PaymentMethod` · `PaymentIdentifier` · `Last4` · `ExpiryMonth` · `ExpiryYear` · `GiftProcessingStatus` · `GiftProcessingResult` · `IsNewRecurringGift` · `IsSetAsDefault` · `TransactionInterval` · `TransactionPeriod` · `TransactionDay` · `EffectiveStartDate` · `ExpectedEndDate` · `CheckDate` · `CurrencyIsoCode` · `DonorId` · `GiftCommitmentId` · `OutreachSourceCodeId` · `CampaignId` · `GiftDesignation1Id` · `GiftDesignation2Id` · `GiftDesignation3Id`

---

## Behavior Notes

### Engine 1 (Gift Entry Matching)
- **Does not overwrite**: If a lookup field already has a value, it is skipped entirely
- **Sequential resolution**: Resolved values (e.g. `DonorId`) are immediately available as tokens for subsequent fields in the same entry
- **No match → leave blank**: If no rule produces a result, the field is left unchanged
- **Ordered by date**: Records in a batch are processed in `GiftReceivedDate ASC` order
- **Partial success**: Uses `Database.update(records, false)` — one failed record doesn't block others

### Engine 2 (Benevity Employer Matching)
- **Idempotent**: `GEM_MatchingGiftCreated__c` prevents duplicate employer gifts on re-runs
- **Skips gracefully**: Entries with zero/null match amount or unresolvable employer path are skipped with a WARN log — they never fail the batch
- **Default PaymentMethod**: Applied only when the field is absent or blank after copying; never overrides an explicitly copied value
- **Run order matters**: Engine 1 should complete before Engine 2 to ensure `DonorId` is populated for employer path traversal

---

## Troubleshooting

Enable **Debug Logs** for your user in Setup with `Apex Code` set to `INFO` or higher.

### Engine 1 Log Messages

| Message | Meaning |
|---|---|
| `field [DonorId] has 0 active rule(s)` | No active CMT records exist for this field |
| `field [DonorId] already populated — skipping` | Field had a value, not overwritten |
| `token {!GiftEntry.FirstName} resolved to NULL` | Field name in token doesn't match a real GiftEntry API name |
| `executing SOQL: SELECT Id FROM Account WHERE ...` | Full resolved query — verify field values look correct |
| `matched record Id=001... (score=0.8)` | Successful match with rule weight |
| `rule [...] skipped — one or more token fields are null` | Token field exists but has no value on this entry |

### Engine 2 Log Messages

| Message | Meaning |
|---|---|
| `IsActive__c is false or settings not configured` | Custom Setting is off or not saved |
| `skipped — match amount is null or zero` | `Matching_Gift_Amount__c` is blank or 0 |
| `skipped — could not resolve employer Id via path` | `Donor.Matching_Employer__c` is null or path is misconfigured |
| `applied default PaymentMethod="Check"` | Default payment method was applied as fallback |
| `created employer gift Id=...` | Employer GiftEntry successfully created |
| `failed to create employer gift` | DML error — check required field violations |

---

## License

MIT
